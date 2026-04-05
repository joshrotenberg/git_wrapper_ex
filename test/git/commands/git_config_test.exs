defmodule Git.GitConfigTest do
  use ExUnit.Case, async: true

  alias Git.Config
  alias Git.Commands.GitConfig

  setup do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "git_wrapper_git_config_test_#{:erlang.unique_integer([:positive])}"
      )

    File.mkdir_p!(tmp_dir)

    System.cmd("git", ["init", "--initial-branch=main"], cd: tmp_dir)

    System.cmd(
      "git",
      [
        "-c",
        "user.name=Test User",
        "-c",
        "user.email=test@test.com",
        "commit",
        "--allow-empty",
        "-m",
        "initial"
      ],
      cd: tmp_dir
    )

    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    config =
      Config.new(
        working_dir: tmp_dir,
        env: [
          {"GIT_AUTHOR_NAME", "Test User"},
          {"GIT_AUTHOR_EMAIL", "test@test.com"},
          {"GIT_COMMITTER_NAME", "Test User"},
          {"GIT_COMMITTER_EMAIL", "test@test.com"}
        ]
      )

    %{tmp_dir: tmp_dir, config: config}
  end

  describe "args/1" do
    test "get builds correct args" do
      assert GitConfig.args(%GitConfig{get: "user.name"}) == ["config", "user.name"]
    end

    test "set builds correct args" do
      assert GitConfig.args(%GitConfig{set_key: "user.name", set_value: "Test"}) ==
               ["config", "user.name", "Test"]
    end

    test "set with global scope" do
      assert GitConfig.args(%GitConfig{set_key: "user.name", set_value: "T", global: true}) ==
               ["config", "--global", "user.name", "T"]
    end

    test "unset builds correct args" do
      assert GitConfig.args(%GitConfig{unset: "user.name"}) ==
               ["config", "--unset", "user.name"]
    end

    test "list builds correct args" do
      assert GitConfig.args(%GitConfig{list: true, local: true}) ==
               ["config", "--local", "--list"]
    end

    test "get_regexp builds correct args" do
      assert GitConfig.args(%GitConfig{get_regexp: "user.*"}) ==
               ["config", "--get-regexp", "user.*"]
    end

    test "set with --add flag" do
      assert GitConfig.args(%GitConfig{
               set_key: "remote.origin.fetch",
               set_value: "+refs/heads/*:refs/remotes/origin/*",
               add: true
             }) ==
               ["config", "--add", "remote.origin.fetch", "+refs/heads/*:refs/remotes/origin/*"]
    end
  end

  describe "set and get config" do
    test "sets and gets a local config value", %{config: config} do
      set_cmd = %GitConfig{set_key: "test.key", set_value: "test-value", local: true}

      assert {:ok, :done} =
               Git.Command.run(GitConfig, set_cmd, config)

      get_cmd = %GitConfig{get: "test.key"}

      assert {:ok, "test-value"} =
               Git.Command.run(GitConfig, get_cmd, config)
    end

    test "unsets a config value", %{config: config} do
      # Set first
      set_cmd = %GitConfig{set_key: "test.remove", set_value: "will-remove", local: true}
      {:ok, :done} = Git.Command.run(GitConfig, set_cmd, config)

      # Unset
      unset_cmd = %GitConfig{unset: "test.remove"}
      assert {:ok, :done} = Git.Command.run(GitConfig, unset_cmd, config)

      # Get should fail
      get_cmd = %GitConfig{get: "test.remove"}
      assert {:error, {_, exit_code}} = Git.Command.run(GitConfig, get_cmd, config)
      assert exit_code != 0
    end
  end

  describe "list config" do
    test "lists local config entries", %{config: config} do
      # Set a known value
      set_cmd = %GitConfig{set_key: "test.listed", set_value: "listed-value", local: true}
      {:ok, :done} = Git.Command.run(GitConfig, set_cmd, config)

      list_cmd = %GitConfig{list: true, local: true}
      assert {:ok, entries} = Git.Command.run(GitConfig, list_cmd, config)

      assert is_list(entries)
      assert Enum.any?(entries, fn {k, v} -> k == "test.listed" and v == "listed-value" end)
    end
  end

  describe "get_regexp" do
    test "returns matching config entries", %{config: config} do
      set_cmd = %GitConfig{set_key: "test.pattern1", set_value: "val1", local: true}
      {:ok, :done} = Git.Command.run(GitConfig, set_cmd, config)

      set_cmd2 = %GitConfig{set_key: "test.pattern2", set_value: "val2", local: true}
      {:ok, :done} = Git.Command.run(GitConfig, set_cmd2, config)

      regexp_cmd = %GitConfig{get_regexp: "test\\.pattern"}
      assert {:ok, entries} = Git.Command.run(GitConfig, regexp_cmd, config)

      assert is_list(entries)
      assert length(entries) >= 2
    end
  end
end
