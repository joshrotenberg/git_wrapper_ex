defmodule Git.Commands.RemoteTest do
  use ExUnit.Case, async: true

  alias Git.Commands.Remote
  alias Git.Config

  setup do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "git_wrapper_remote_test_#{:erlang.unique_integer([:positive])}"
      )

    File.mkdir_p!(tmp_dir)

    System.cmd("git", ["init", "--initial-branch=main"], cd: tmp_dir)
    System.cmd("git", ["config", "user.name", "Test User"], cd: tmp_dir)
    System.cmd("git", ["config", "user.email", "test@test.com"], cd: tmp_dir)

    System.cmd(
      "git",
      ["commit", "--allow-empty", "-m", "initial"],
      cd: tmp_dir
    )

    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    config = Config.new(working_dir: tmp_dir)

    %{tmp_dir: tmp_dir, config: config}
  end

  describe "Commands.Remote.args/1" do
    test "list (default, verbose)" do
      assert Remote.args(%Remote{}) == ["remote", "-v"]
    end

    test "list non-verbose" do
      assert Remote.args(%Remote{verbose: false}) == ["remote"]
    end

    test "add remote" do
      assert Remote.args(%Remote{
               add_name: "upstream",
               add_url: "https://github.com/user/repo.git"
             }) ==
               ["remote", "add", "upstream", "https://github.com/user/repo.git"]
    end

    test "remove remote" do
      assert Remote.args(%Remote{remove: "upstream"}) ==
               ["remote", "remove", "upstream"]
    end
  end

  describe "integration" do
    test "add and remove a remote", %{config: config} do
      # Initially no remotes
      assert {:ok, remotes} = Git.remote(config: config)
      assert remotes == []

      # Add a remote
      assert {:ok, :done} =
               Git.remote(
                 add_name: "origin",
                 add_url: "https://github.com/user/repo.git",
                 config: config
               )

      # List remotes -- should include origin
      assert {:ok, remotes} = Git.remote(config: config)
      assert remotes != []
      assert Enum.any?(remotes, fn r -> r.name == "origin" end)

      # Remove the remote
      assert {:ok, :done} = Git.remote(remove: "origin", config: config)

      # Verify removal
      assert {:ok, remotes} = Git.remote(config: config)
      assert remotes == []
    end

    test "list remotes non-verbose", %{config: config} do
      System.cmd(
        "git",
        ["remote", "add", "origin", "https://github.com/user/repo.git"],
        cd: config.working_dir
      )

      assert {:ok, remotes} = Git.remote(verbose: false, config: config)
      assert remotes != []
      assert Enum.any?(remotes, fn r -> r.name == "origin" end)
    end
  end
end
