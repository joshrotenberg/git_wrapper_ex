defmodule Git.InfoTest do
  use ExUnit.Case, async: true

  # ---------------------------------------------------------------------------
  # Test helpers
  # ---------------------------------------------------------------------------

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
    cfg = Git.Config.new(working_dir: tmp_dir, env: @git_env)
    {:ok, :done} = Git.init(config: cfg)
    {:ok, :done} = Git.git_config(set_key: "user.name", set_value: "Test User", config: cfg)
    {:ok, :done} = Git.git_config(set_key: "user.email", set_value: "test@test.com", config: cfg)
    {:ok, _} = Git.commit("initial", allow_empty: true, config: cfg)

    on_exit(fn -> File.rm_rf!(tmp_dir) end)
    {tmp_dir, cfg}
  end

  defp realpath(path) do
    {resolved, 0} = System.cmd("realpath", [path])
    String.trim(resolved)
  end

  # ---------------------------------------------------------------------------
  # summary/1
  # ---------------------------------------------------------------------------

  describe "summary/1" do
    test "returns summary on a clean repo" do
      {_dir, cfg} = setup_repo("info_summary_clean")

      assert {:ok, info} = Git.Info.summary(config: cfg)
      assert is_binary(info.branch)
      assert is_binary(info.commit)
      assert info.dirty == false
      assert info.ahead == 0
      assert info.behind == 0
      assert info.staged == 0
      assert info.modified == 0
      assert info.untracked == 0
      assert info.remote == nil
      assert info.remote_url == nil
      assert is_binary(info.last_commit_subject)
      assert is_binary(info.last_commit_date)
    end

    test "returns summary on a dirty repo" do
      {dir, cfg} = setup_repo("info_summary_dirty")

      # Create an untracked file
      File.write!(Path.join(dir, "untracked.txt"), "hello\n")

      # Create a staged file
      File.write!(Path.join(dir, "staged.txt"), "staged\n")
      {:ok, :done} = Git.add(files: ["staged.txt"], config: cfg)

      assert {:ok, info} = Git.Info.summary(config: cfg)
      assert info.dirty == true
      assert info.staged >= 1
      assert info.untracked >= 1
    end
  end

  # ---------------------------------------------------------------------------
  # head/1
  # ---------------------------------------------------------------------------

  describe "head/1" do
    test "returns branch info when on a branch" do
      {_dir, cfg} = setup_repo("info_head_branch")

      assert {:ok, head} = Git.Info.head(config: cfg)
      assert is_binary(head.branch)
      assert is_binary(head.sha)
      assert String.length(head.sha) == 40
      assert head.detached == false
    end

    test "returns detached state when HEAD is detached" do
      {dir, cfg} = setup_repo("info_head_detached")

      # Get current SHA and detach HEAD
      {:ok, sha} = Git.rev_parse(ref: "HEAD", config: cfg)
      System.cmd("git", ["checkout", sha], cd: dir, env: @git_env)

      assert {:ok, head} = Git.Info.head(config: cfg)
      assert head.branch == nil
      assert head.sha == sha
      assert head.detached == true
    end
  end

  # ---------------------------------------------------------------------------
  # dirty?/1
  # ---------------------------------------------------------------------------

  describe "dirty?/1" do
    test "returns false on clean repo" do
      {_dir, cfg} = setup_repo("info_dirty_clean")

      assert {:ok, false} = Git.Info.dirty?(config: cfg)
    end

    test "returns true when there are changes" do
      {dir, cfg} = setup_repo("info_dirty_dirty")

      File.write!(Path.join(dir, "new_file.txt"), "content\n")

      assert {:ok, true} = Git.Info.dirty?(config: cfg)
    end
  end

  # ---------------------------------------------------------------------------
  # root/1
  # ---------------------------------------------------------------------------

  describe "root/1" do
    test "returns the repository root path" do
      {dir, cfg} = setup_repo("info_root")

      assert {:ok, root} = Git.Info.root(config: cfg)
      # Normalize for macOS /private/var vs /var symlinks
      assert realpath(root) == realpath(dir)
    end
  end

  # ---------------------------------------------------------------------------
  # remotes_detailed/1
  # ---------------------------------------------------------------------------

  describe "remotes_detailed/1" do
    test "returns empty list when no remotes" do
      {_dir, cfg} = setup_repo("info_remotes_empty")

      assert {:ok, []} = Git.Info.remotes_detailed(config: cfg)
    end

    test "returns remote details when remotes exist" do
      {dir, cfg} = setup_repo("info_remotes")

      # Add a remote
      System.cmd("git", ["remote", "add", "origin", "https://example.com/repo.git"], cd: dir)

      assert {:ok, remotes} = Git.Info.remotes_detailed(config: cfg)
      assert length(remotes) == 1
      remote = hd(remotes)
      assert remote.name == "origin"
      assert remote.fetch_url == "https://example.com/repo.git"
      assert remote.push_url == "https://example.com/repo.git"
    end
  end
end
