defmodule Git.BundleTest do
  use ExUnit.Case, async: true

  alias Git.Commands.Bundle
  alias Git.Config

  @env [
    {"GIT_AUTHOR_NAME", "Test User"},
    {"GIT_AUTHOR_EMAIL", "test@test.com"},
    {"GIT_COMMITTER_NAME", "Test User"},
    {"GIT_COMMITTER_EMAIL", "test@test.com"}
  ]

  defp setup_repo do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "git_bundle_test_#{:erlang.unique_integer([:positive])}"
      )

    File.mkdir_p!(tmp_dir)
    cfg = Config.new(working_dir: tmp_dir, env: @env)
    {:ok, :done} = Git.init(config: cfg)
    {:ok, :done} = Git.git_config(set_key: "user.name", set_value: "Test User", config: cfg)
    {:ok, :done} = Git.git_config(set_key: "user.email", set_value: "test@test.com", config: cfg)
    {:ok, _} = Git.commit("initial", allow_empty: true, config: cfg)
    {tmp_dir, cfg}
  end

  setup do
    {tmp_dir, config} = setup_repo()
    on_exit(fn -> File.rm_rf!(tmp_dir) end)
    %{tmp_dir: tmp_dir, config: config}
  end

  describe "Git.Commands.Bundle args/1" do
    test "builds args for create with rev" do
      assert Bundle.args(%Bundle{create: "/tmp/test.bundle", rev: "HEAD"}) ==
               ["bundle", "create", "/tmp/test.bundle", "HEAD"]
    end

    test "builds args for create with --all" do
      assert Bundle.args(%Bundle{create: "/tmp/test.bundle", all: true}) ==
               ["bundle", "create", "/tmp/test.bundle", "--all"]
    end

    test "builds args for create with quiet" do
      assert Bundle.args(%Bundle{create: "/tmp/test.bundle", rev: "HEAD", quiet: true}) ==
               ["bundle", "create", "-q", "/tmp/test.bundle", "HEAD"]
    end

    test "builds args for verify" do
      assert Bundle.args(%Bundle{verify: "/tmp/test.bundle"}) ==
               ["bundle", "verify", "/tmp/test.bundle"]
    end

    test "builds args for list-heads" do
      assert Bundle.args(%Bundle{list_heads: "/tmp/test.bundle"}) ==
               ["bundle", "list-heads", "/tmp/test.bundle"]
    end

    test "builds args for unbundle" do
      assert Bundle.args(%Bundle{unbundle: "/tmp/test.bundle"}) ==
               ["bundle", "unbundle", "/tmp/test.bundle"]
    end
  end

  describe "git bundle create and verify" do
    test "creates a bundle file", %{tmp_dir: tmp_dir, config: config} do
      bundle_path = Path.join(tmp_dir, "test.bundle")
      {:ok, :done} = Git.bundle(create: bundle_path, rev: "HEAD", config: config)
      assert File.exists?(bundle_path)
    end

    test "verifies a valid bundle", %{tmp_dir: tmp_dir, config: config} do
      bundle_path = Path.join(tmp_dir, "test.bundle")
      {:ok, :done} = Git.bundle(create: bundle_path, rev: "HEAD", config: config)
      {:ok, result} = Git.bundle(verify: bundle_path, config: config)
      assert result.valid == true
      assert is_binary(result.raw)
    end

    test "lists heads of a bundle", %{tmp_dir: tmp_dir, config: config} do
      bundle_path = Path.join(tmp_dir, "test.bundle")
      {:ok, :done} = Git.bundle(create: bundle_path, rev: "HEAD", config: config)
      {:ok, heads} = Git.bundle(list_heads: bundle_path, config: config)
      assert [head | _] = heads
      assert is_binary(head.sha)
      assert is_binary(head.ref)
    end
  end

  describe "parse_output/2" do
    test "create mode returns :done on success" do
      Process.put(:__git_bundle_mode__, :create)
      assert Bundle.parse_output("", 0) == {:ok, :done}
    end

    test "verify mode returns valid true on exit 0" do
      Process.put(:__git_bundle_mode__, :verify)

      assert Bundle.parse_output("The bundle is valid.\n", 0) ==
               {:ok, %{valid: true, raw: "The bundle is valid.\n"}}
    end

    test "verify mode returns valid false on exit 1" do
      Process.put(:__git_bundle_mode__, :verify)
      assert Bundle.parse_output("error\n", 1) == {:ok, %{valid: false, raw: "error\n"}}
    end

    test "list_heads mode parses sha ref lines" do
      Process.put(:__git_bundle_mode__, :list_heads)
      output = "abc1234def5678901234567890abcdef12345678 refs/heads/main\n"
      {:ok, [entry]} = Bundle.parse_output(output, 0)
      assert entry.sha == "abc1234def5678901234567890abcdef12345678"
      assert entry.ref == "refs/heads/main"
    end

    test "unbundle mode returns :done on success" do
      Process.put(:__git_bundle_mode__, :unbundle)
      assert Bundle.parse_output("", 0) == {:ok, :done}
    end
  end
end
