defmodule GitWrapper.RemoteTest do
  use ExUnit.Case, async: true

  alias GitWrapper.Remote
  alias GitWrapper.Commands.Remote, as: RemoteCmd

  # ---------------------------------------------------------------------------
  # Test helpers
  # ---------------------------------------------------------------------------

  defp setup_repo do
    dir =
      Path.join(
        System.tmp_dir!(),
        "git_wrapper_remote_test_#{:erlang.unique_integer([:positive])}"
      )

    File.mkdir_p!(dir)
    System.cmd("git", ["init"], cd: dir)
    System.cmd("git", ["config", "user.email", "test@example.com"], cd: dir)
    System.cmd("git", ["config", "user.name", "Test User"], cd: dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    GitWrapper.Config.new(working_dir: dir)
  end

  # ---------------------------------------------------------------------------
  # Unit tests: Remote.parse_verbose/1
  # ---------------------------------------------------------------------------

  describe "Remote.parse_verbose/1" do
    test "empty string returns empty list" do
      assert Remote.parse_verbose("") == []
    end

    test "single remote with matching fetch and push URLs" do
      output = """
      origin\thttps://github.com/user/repo.git (fetch)
      origin\thttps://github.com/user/repo.git (push)
      """

      assert [%Remote{name: "origin", fetch_url: fetch, push_url: push}] =
               Remote.parse_verbose(output)

      assert fetch == "https://github.com/user/repo.git"
      assert push == "https://github.com/user/repo.git"
    end

    test "two remotes each produce one struct" do
      output = """
      origin\thttps://github.com/user/repo.git (fetch)
      origin\thttps://github.com/user/repo.git (push)
      upstream\thttps://github.com/upstream/repo.git (fetch)
      upstream\thttps://github.com/upstream/repo.git (push)
      """

      remotes = Remote.parse_verbose(output)
      assert length(remotes) == 2

      names = Enum.map(remotes, & &1.name)
      assert "origin" in names
      assert "upstream" in names
    end

    test "differing fetch and push URLs are both captured" do
      output = """
      origin\thttps://github.com/user/repo.git (fetch)
      origin\tgit@github.com:user/repo.git (push)
      """

      assert [%Remote{name: "origin", fetch_url: fetch, push_url: push}] =
               Remote.parse_verbose(output)

      assert fetch == "https://github.com/user/repo.git"
      assert push == "git@github.com:user/repo.git"
    end

    test "only fetch line produces a remote with nil push_url" do
      output = "origin\thttps://github.com/user/repo.git (fetch)\n"

      assert [%Remote{name: "origin", fetch_url: "https://github.com/user/repo.git", push_url: nil}] =
               Remote.parse_verbose(output)
    end
  end

  # ---------------------------------------------------------------------------
  # Unit tests: Commands.Remote.args/1
  # ---------------------------------------------------------------------------

  describe "Commands.Remote.args/1" do
    test "default struct produces verbose list args" do
      assert RemoteCmd.args(%RemoteCmd{}) == ["remote", "-v"]
    end

    test "verbose: false produces plain list args" do
      assert RemoteCmd.args(%RemoteCmd{verbose: false}) == ["remote"]
    end

    test "add_name and add_url produce add args" do
      cmd = %RemoteCmd{add_name: "upstream", add_url: "https://github.com/upstream/repo.git"}
      assert RemoteCmd.args(cmd) == ["remote", "add", "upstream", "https://github.com/upstream/repo.git"]
    end

    test "remove produces remove args" do
      cmd = %RemoteCmd{remove: "upstream"}
      assert RemoteCmd.args(cmd) == ["remote", "remove", "upstream"]
    end
  end

  # ---------------------------------------------------------------------------
  # Unit tests: Commands.Remote.parse_output/2
  # ---------------------------------------------------------------------------

  describe "Commands.Remote.parse_output/2" do
    test "empty stdout with exit 0 returns :done after mutation args" do
      # args/1 must be called first to set the operation mode in the process
      # dictionary, which is how Command.run/3 operates.
      RemoteCmd.args(%RemoteCmd{add_name: "origin", add_url: "https://example.com"})
      assert {:ok, :done} = RemoteCmd.parse_output("", 0)
    end

    test "empty stdout with exit 0 returns empty list in list mode" do
      RemoteCmd.args(%RemoteCmd{})
      assert {:ok, []} = RemoteCmd.parse_output("", 0)
    end

    test "verbose output returns list of Remote structs" do
      output = "origin\thttps://github.com/user/repo.git (fetch)\norigin\thttps://github.com/user/repo.git (push)\n"
      assert {:ok, [%Remote{name: "origin"}]} = RemoteCmd.parse_output(output, 0)
    end

    test "plain name output returns list of Remote structs with only name" do
      output = "origin\nupstream\n"
      assert {:ok, remotes} = RemoteCmd.parse_output(output, 0)
      assert length(remotes) == 2
      names = Enum.map(remotes, & &1.name)
      assert "origin" in names
      assert "upstream" in names
      Enum.each(remotes, fn r ->
        assert r.fetch_url == nil
        assert r.push_url == nil
      end)
    end

    test "non-zero exit code returns error tuple" do
      assert {:error, {"some error\n", 128}} = RemoteCmd.parse_output("some error\n", 128)
    end
  end

  # ---------------------------------------------------------------------------
  # Integration tests
  # ---------------------------------------------------------------------------

  describe "GitWrapperEx.remote/1 integration" do
    test "fresh repo has no remotes" do
      config = setup_repo()
      assert {:ok, []} = GitWrapperEx.remote(config: config)
    end

    test "add remote returns :done" do
      config = setup_repo()

      assert {:ok, :done} =
               GitWrapperEx.remote(
                 config: config,
                 add_name: "origin",
                 add_url: "https://github.com/user/repo.git"
               )
    end

    test "added remote appears in listing" do
      config = setup_repo()

      GitWrapperEx.remote(
        config: config,
        add_name: "origin",
        add_url: "https://github.com/user/repo.git"
      )

      assert {:ok, [%Remote{name: "origin", fetch_url: url}]} =
               GitWrapperEx.remote(config: config)

      assert url == "https://github.com/user/repo.git"
    end

    test "multiple remotes all appear in listing" do
      config = setup_repo()

      GitWrapperEx.remote(
        config: config,
        add_name: "origin",
        add_url: "https://github.com/user/repo.git"
      )

      GitWrapperEx.remote(
        config: config,
        add_name: "upstream",
        add_url: "https://github.com/upstream/repo.git"
      )

      assert {:ok, remotes} = GitWrapperEx.remote(config: config)
      assert length(remotes) == 2
      names = Enum.map(remotes, & &1.name)
      assert "origin" in names
      assert "upstream" in names
    end

    test "remove remote returns :done" do
      config = setup_repo()

      GitWrapperEx.remote(
        config: config,
        add_name: "origin",
        add_url: "https://github.com/user/repo.git"
      )

      assert {:ok, :done} = GitWrapperEx.remote(config: config, remove: "origin")
    end

    test "removed remote no longer appears in listing" do
      config = setup_repo()

      GitWrapperEx.remote(
        config: config,
        add_name: "origin",
        add_url: "https://github.com/user/repo.git"
      )

      GitWrapperEx.remote(config: config, remove: "origin")

      assert {:ok, []} = GitWrapperEx.remote(config: config)
    end

    test "removing non-existent remote returns error" do
      config = setup_repo()
      assert {:error, _} = GitWrapperEx.remote(config: config, remove: "nonexistent")
    end

    test "verbose: false lists remote names without URLs" do
      config = setup_repo()

      GitWrapperEx.remote(
        config: config,
        add_name: "origin",
        add_url: "https://github.com/user/repo.git"
      )

      assert {:ok, [%Remote{name: "origin", fetch_url: nil, push_url: nil}]} =
               GitWrapperEx.remote(config: config, verbose: false)
    end
  end
end
