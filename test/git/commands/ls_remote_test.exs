defmodule Git.LsRemoteTest do
  use ExUnit.Case, async: true

  alias Git.Commands.LsRemote
  alias Git.Config
  alias Git.LsRemoteEntry

  @env [
    {"GIT_AUTHOR_NAME", "Test User"},
    {"GIT_AUTHOR_EMAIL", "test@test.com"},
    {"GIT_COMMITTER_NAME", "Test User"},
    {"GIT_COMMITTER_EMAIL", "test@test.com"}
  ]

  defp setup_repo_with_remote do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "git_ls_remote_test_#{:erlang.unique_integer([:positive])}"
      )

    File.mkdir_p!(tmp_dir)
    local_dir = Path.join(tmp_dir, "local")
    remote_dir = Path.join(tmp_dir, "remote.git")
    File.mkdir_p!(local_dir)
    File.mkdir_p!(remote_dir)

    # Create bare remote
    System.cmd("git", ["init", "--bare", "--initial-branch=main"], cd: remote_dir)

    # Set up local repo
    cfg = Config.new(working_dir: local_dir, env: @env)
    {:ok, :done} = Git.init(config: cfg)
    {:ok, :done} = Git.git_config(set_key: "user.name", set_value: "Test User", config: cfg)
    {:ok, :done} = Git.git_config(set_key: "user.email", set_value: "test@test.com", config: cfg)

    # Create initial commit
    File.write!(Path.join(local_dir, "README.md"), "# Test\n")
    {:ok, :done} = Git.add(all: true, config: cfg)
    {:ok, _} = Git.commit("initial commit", config: cfg)

    # Add remote and push
    {:ok, :done} = Git.remote(add_name: "origin", add_url: remote_dir, config: cfg)
    {:ok, :done} = Git.push(remote: "origin", branch: "main", set_upstream: true, config: cfg)

    # Create a tag and push it
    {:ok, :done} = Git.tag(create: "v1.0.0", message: "release v1.0.0", config: cfg)
    System.cmd("git", ["push", "origin", "v1.0.0"], cd: local_dir, env: @env)

    {tmp_dir, local_dir, remote_dir, cfg}
  end

  setup do
    {tmp_dir, local_dir, remote_dir, config} = setup_repo_with_remote()
    on_exit(fn -> File.rm_rf!(tmp_dir) end)
    %{tmp_dir: tmp_dir, local_dir: local_dir, remote_dir: remote_dir, config: config}
  end

  describe "args/1" do
    test "builds default args" do
      assert LsRemote.args(%LsRemote{}) == ["ls-remote"]
    end

    test "builds args with heads and tags" do
      assert LsRemote.args(%LsRemote{heads: true, tags: true}) ==
               ["ls-remote", "--heads", "--tags"]
    end

    test "builds args with remote and refs" do
      assert LsRemote.args(%LsRemote{remote: "origin", refs: "refs/heads/main"}) ==
               ["ls-remote", "origin", "refs/heads/main"]
    end

    test "builds args with symref and sort" do
      assert LsRemote.args(%LsRemote{symref: true, sort: "version:refname"}) ==
               ["ls-remote", "--symref", "--sort=version:refname"]
    end

    test "builds args with quiet" do
      assert LsRemote.args(%LsRemote{quiet: true}) ==
               ["ls-remote", "-q"]
    end

    test "builds args with exit_code" do
      assert LsRemote.args(%LsRemote{exit_code: true}) ==
               ["ls-remote", "--exit-code"]
    end
  end

  describe "git ls-remote" do
    test "lists refs from remote", %{remote_dir: remote_dir, config: config} do
      {:ok, entries} =
        Git.Command.run(LsRemote, %LsRemote{remote: remote_dir}, config)

      assert is_list(entries)
      assert entries != []

      Enum.each(entries, fn entry ->
        assert %LsRemoteEntry{} = entry
      end)

      # Should have at least HEAD and refs/heads/main
      refs = Enum.map(entries, & &1.ref)
      assert "HEAD" in refs
      assert "refs/heads/main" in refs
    end

    test "filters heads only", %{remote_dir: remote_dir, config: config} do
      {:ok, entries} =
        Git.Command.run(LsRemote, %LsRemote{remote: remote_dir, heads: true}, config)

      refs = Enum.map(entries, & &1.ref)
      assert Enum.all?(refs, &String.starts_with?(&1, "refs/heads/"))
    end

    test "filters tags only", %{remote_dir: remote_dir, config: config} do
      {:ok, entries} =
        Git.Command.run(LsRemote, %LsRemote{remote: remote_dir, tags: true}, config)

      refs = Enum.map(entries, & &1.ref)
      assert Enum.all?(refs, &String.starts_with?(&1, "refs/tags/"))
      assert Enum.any?(refs, &(&1 == "refs/tags/v1.0.0"))
    end

    test "entries have valid SHAs", %{remote_dir: remote_dir, config: config} do
      {:ok, entries} =
        Git.Command.run(LsRemote, %LsRemote{remote: remote_dir}, config)

      sha_entries = Enum.filter(entries, & &1.sha)

      Enum.each(sha_entries, fn entry ->
        assert String.match?(entry.sha, ~r/^[0-9a-f]{40}$/)
      end)
    end

    test "exit_code 2 returns empty list for no matching refs", %{
      remote_dir: remote_dir,
      config: config
    } do
      {:ok, entries} =
        Git.Command.run(
          LsRemote,
          %LsRemote{remote: remote_dir, exit_code: true, refs: "refs/heads/nonexistent"},
          config
        )

      assert entries == []
    end
  end
end
