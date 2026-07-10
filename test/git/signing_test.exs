defmodule Git.SigningTest do
  use ExUnit.Case, async: true

  @git_env [
    {"GIT_AUTHOR_NAME", "Test User"},
    {"GIT_AUTHOR_EMAIL", "test@test.com"},
    {"GIT_COMMITTER_NAME", "Test User"},
    {"GIT_COMMITTER_EMAIL", "test@test.com"}
  ]

  # Builds a repo with an ed25519 SSH signing key generated in the repo dir.
  # SSH signing needs no GPG toolchain, so it works on a headless CI runner.
  defp setup_repo(name) do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "git_signing_#{name}_test_#{:erlang.unique_integer([:positive])}"
      )

    File.mkdir_p!(tmp_dir)
    System.cmd("git", ["init", "--initial-branch=main"], cd: tmp_dir)
    System.cmd("git", ["config", "user.name", "Test User"], cd: tmp_dir)
    System.cmd("git", ["config", "user.email", "test@test.com"], cd: tmp_dir)

    key_path = Path.join(tmp_dir, "key")

    {_, 0} =
      System.cmd(
        "ssh-keygen",
        ["-t", "ed25519", "-f", key_path, "-N", "", "-C", "test@test.com", "-q"]
      )

    cfg = Git.Config.new(working_dir: tmp_dir, env: @git_env)

    on_exit(fn -> Git.TestHelpers.rm_rf(tmp_dir) end)
    {tmp_dir, cfg, key_path <> ".pub"}
  end

  # Registers the public key as an allowed signer so `git verify-commit` /
  # `git verify-tag` can validate the signatures the tests create.
  defp allow_signer(tmp_dir, cfg, pub_path) do
    allowed = Path.join(tmp_dir, "allowed_signers")
    File.write!(allowed, "test@test.com " <> File.read!(pub_path))

    {:ok, :done} =
      Git.git_config(
        set_key: "gpg.ssh.allowedSignersFile",
        set_value: allowed,
        local: true,
        config: cfg
      )

    :ok
  end

  defp write_and_stage(tmp_dir, cfg, file, content) do
    File.write!(Path.join(tmp_dir, file), content)
    {:ok, :done} = Git.add(files: [file], config: cfg)
    :ok
  end

  describe "use_ssh/2" do
    test "sets gpg.format, user.signingkey, and commit.gpgsign" do
      {_dir, cfg, pub} = setup_repo("use_ssh")

      assert {:ok, :done} = Git.Signing.use_ssh(pub, config: cfg)
      assert {:ok, "ssh"} = Git.git_config(get: "gpg.format", config: cfg)
      assert {:ok, ^pub} = Git.git_config(get: "user.signingkey", config: cfg)
      assert {:ok, "true"} = Git.git_config(get: "commit.gpgsign", config: cfg)
    end

    test "commits made with the configuration verify" do
      {dir, cfg, pub} = setup_repo("use_ssh_verify")
      assert {:ok, :done} = Git.Signing.use_ssh(pub, config: cfg)
      allow_signer(dir, cfg, pub)

      write_and_stage(dir, cfg, "a.txt", "a\n")
      assert {:ok, _result} = Git.commit("config-signed", config: cfg)
      assert {:ok, %{valid: true}} = Git.verify_commit("HEAD", config: cfg)
    end
  end

  describe "use_gpg/2" do
    test "sets user.signingkey and commit.gpgsign" do
      {_dir, cfg, _pub} = setup_repo("use_gpg")

      assert {:ok, :done} = Git.Signing.use_gpg("ABCD1234", config: cfg)
      assert {:ok, "ABCD1234"} = Git.git_config(get: "user.signingkey", config: cfg)
      assert {:ok, "true"} = Git.git_config(get: "commit.gpgsign", config: cfg)
    end
  end

  describe "sign_tags/2" do
    test "sets tag.gpgsign" do
      {_dir, cfg, _pub} = setup_repo("sign_tags")

      assert {:ok, :done} = Git.Signing.sign_tags(true, config: cfg)
      assert {:ok, "true"} = Git.git_config(get: "tag.gpgsign", config: cfg)

      assert {:ok, :done} = Git.Signing.sign_tags(false, config: cfg)
      assert {:ok, "false"} = Git.git_config(get: "tag.gpgsign", config: cfg)
    end
  end

  describe "commit sign: option" do
    test "sign: true signs the commit even when commit.gpgsign is off" do
      {dir, cfg, pub} = setup_repo("commit_sign_flag")
      # Configure the key but leave commit.gpgsign unset so the flag is the
      # only thing that can produce a signature.
      {:ok, :done} =
        Git.git_config(set_key: "gpg.format", set_value: "ssh", local: true, config: cfg)

      {:ok, :done} =
        Git.git_config(set_key: "user.signingkey", set_value: pub, local: true, config: cfg)

      allow_signer(dir, cfg, pub)

      write_and_stage(dir, cfg, "a.txt", "a\n")
      assert {:ok, _result} = Git.commit("flag-signed", sign: true, config: cfg)
      assert {:ok, %{valid: true}} = Git.verify_commit("HEAD", config: cfg)
    end

    test "without sign: and with commit.gpgsign off the commit is unsigned" do
      {dir, cfg, pub} = setup_repo("commit_unsigned")

      {:ok, :done} =
        Git.git_config(set_key: "gpg.format", set_value: "ssh", local: true, config: cfg)

      {:ok, :done} =
        Git.git_config(set_key: "user.signingkey", set_value: pub, local: true, config: cfg)

      allow_signer(dir, cfg, pub)

      write_and_stage(dir, cfg, "a.txt", "a\n")
      assert {:ok, _result} = Git.commit("unsigned", config: cfg)
      assert {:ok, %{valid: false}} = Git.verify_commit("HEAD", config: cfg)
    end
  end

  describe "tag sign: and local_user: options" do
    test "sign: true produces a verifiable signed annotated tag" do
      {dir, cfg, pub} = setup_repo("tag_sign_flag")
      {:ok, :done} = Git.Signing.use_ssh(pub, config: cfg)
      allow_signer(dir, cfg, pub)

      write_and_stage(dir, cfg, "a.txt", "a\n")
      {:ok, _result} = Git.commit("base", config: cfg)

      assert {:ok, :done} =
               Git.tag(create: "v1.0.0", message: "release 1.0", sign: true, config: cfg)

      assert {:ok, %{valid: true}} = Git.verify_tag("v1.0.0", config: cfg)
    end
  end

  describe "merge gpg_sign: option" do
    test "signs the merge commit so it verifies" do
      {dir, cfg, pub} = setup_repo("merge_sign")
      {:ok, :done} = Git.Signing.use_ssh(pub, config: cfg)
      allow_signer(dir, cfg, pub)

      write_and_stage(dir, cfg, "base.txt", "base\n")
      {:ok, _result} = Git.commit("base", config: cfg)

      {:ok, _checkout} = Git.checkout(branch: "feature", create: true, config: cfg)
      write_and_stage(dir, cfg, "feature.txt", "feature\n")
      {:ok, _result} = Git.commit("feature work", config: cfg)

      {:ok, _checkout} = Git.checkout(branch: "main", config: cfg)

      # --no-ff forces a merge commit that carries the signature.
      assert {:ok, _merge} =
               Git.merge("feature", no_ff: true, no_edit: true, gpg_sign: true, config: cfg)

      assert {:ok, %{valid: true}} = Git.verify_commit("HEAD", config: cfg)
    end
  end
end
