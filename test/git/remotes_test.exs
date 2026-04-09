defmodule Git.RemotesTest do
  use ExUnit.Case, async: true

  @git_env [
    {"GIT_AUTHOR_NAME", "Test User"},
    {"GIT_AUTHOR_EMAIL", "test@example.com"},
    {"GIT_COMMITTER_NAME", "Test User"},
    {"GIT_COMMITTER_EMAIL", "test@example.com"}
  ]

  defp setup_repo(name) do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "git_#{name}_test_#{:erlang.unique_integer([:positive])}"
      )

    File.mkdir_p!(tmp_dir)
    System.cmd("git", ["init", "--initial-branch=main"], cd: tmp_dir)
    System.cmd("git", ["config", "user.name", "Test User"], cd: tmp_dir)
    System.cmd("git", ["config", "user.email", "test@test.com"], cd: tmp_dir)

    System.cmd("git", ["commit", "--allow-empty", "-m", "initial"],
      cd: tmp_dir,
      env: @git_env
    )

    cfg = Git.Config.new(working_dir: tmp_dir, env: @git_env)

    on_exit(fn -> File.rm_rf!(tmp_dir) end)
    {tmp_dir, cfg}
  end

  defp setup_bare_remote(name) do
    bare_dir =
      Path.join(
        System.tmp_dir!(),
        "git_#{name}_bare_#{:erlang.unique_integer([:positive])}"
      )

    File.mkdir_p!(bare_dir)
    System.cmd("git", ["init", "--bare"], cd: bare_dir)

    on_exit(fn -> File.rm_rf!(bare_dir) end)
    bare_dir
  end

  # ---------------------------------------------------------------------------
  # list_detailed/1
  # ---------------------------------------------------------------------------

  describe "list_detailed/1" do
    test "returns empty list when no remotes" do
      {_dir, cfg} = setup_repo("remotes_list_empty")

      assert {:ok, []} = Git.Remotes.list_detailed(config: cfg)
    end

    test "returns remotes with URLs" do
      {dir, cfg} = setup_repo("remotes_list")
      bare = setup_bare_remote("remotes_list_bare")

      System.cmd("git", ["remote", "add", "origin", bare], cd: dir)

      assert {:ok, remotes} = Git.Remotes.list_detailed(config: cfg)
      assert length(remotes) == 1
      remote = hd(remotes)
      assert remote.name == "origin"
      assert remote.fetch_url == bare
      assert remote.push_url == bare
    end
  end

  # ---------------------------------------------------------------------------
  # add/3
  # ---------------------------------------------------------------------------

  describe "add/3" do
    test "adds a remote" do
      {dir, cfg} = setup_repo("remotes_add")
      bare = setup_bare_remote("remotes_add_bare")

      assert {:ok, :done} = Git.Remotes.add("origin", bare, config: cfg)

      {output, 0} = System.cmd("git", ["remote", "-v"], cd: dir)
      assert String.contains?(output, "origin")
      assert String.contains?(output, bare)
    end
  end

  # ---------------------------------------------------------------------------
  # remove/2
  # ---------------------------------------------------------------------------

  describe "remove/2" do
    test "removes a remote" do
      {dir, cfg} = setup_repo("remotes_remove")
      bare = setup_bare_remote("remotes_remove_bare")

      System.cmd("git", ["remote", "add", "origin", bare], cd: dir)

      assert {:ok, :done} = Git.Remotes.remove("origin", config: cfg)

      {output, 0} = System.cmd("git", ["remote"], cd: dir)
      refute String.contains?(output, "origin")
    end
  end

  # ---------------------------------------------------------------------------
  # set_url/3
  # ---------------------------------------------------------------------------

  describe "set_url/3" do
    test "updates the URL of an existing remote" do
      {dir, cfg} = setup_repo("remotes_set_url")
      bare1 = setup_bare_remote("remotes_set_url_bare1")
      bare2 = setup_bare_remote("remotes_set_url_bare2")

      System.cmd("git", ["remote", "add", "origin", bare1], cd: dir)

      assert {:ok, :done} = Git.Remotes.set_url("origin", bare2, config: cfg)

      {output, 0} = System.cmd("git", ["remote", "-v"], cd: dir)
      assert String.contains?(output, bare2)
      refute String.contains?(output, bare1)
    end
  end

  # ---------------------------------------------------------------------------
  # prune/2
  # ---------------------------------------------------------------------------

  describe "prune/2" do
    test "prunes stale remote-tracking branches" do
      {dir, cfg} = setup_repo("remotes_prune")
      bare = setup_bare_remote("remotes_prune_bare")

      # Push to bare so fetch has something to work with
      System.cmd("git", ["remote", "add", "origin", bare], cd: dir)
      System.cmd("git", ["push", "-u", "origin", "main"], cd: dir, env: @git_env)

      # Prune should succeed even when nothing is stale
      assert {:ok, :done} = Git.Remotes.prune("origin", config: cfg)
    end
  end
end
