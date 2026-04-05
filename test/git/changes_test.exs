defmodule Git.ChangesTest do
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

  defp write_and_commit(dir, cfg, filename, content, msg) do
    File.write!(Path.join(dir, filename), content)
    {:ok, :done} = Git.add(files: [filename], config: cfg)
    System.cmd("git", ["commit", "-m", msg], cd: dir, env: @git_env)
  end

  defp create_tag(dir, tag) do
    System.cmd("git", ["tag", tag], cd: dir)
  end

  # ---------------------------------------------------------------------------
  # between/3
  # ---------------------------------------------------------------------------

  describe "between/3" do
    test "detects added, modified, and deleted files" do
      {dir, cfg} = setup_repo("changes_between")

      write_and_commit(dir, cfg, "keep.txt", "original\n", "add keep")
      write_and_commit(dir, cfg, "delete_me.txt", "bye\n", "add delete_me")
      create_tag(dir, "v1")

      # Add a new file
      write_and_commit(dir, cfg, "new.txt", "hello\n", "add new")
      # Modify an existing file
      write_and_commit(dir, cfg, "keep.txt", "changed\n", "modify keep")
      # Delete a file
      File.rm!(Path.join(dir, "delete_me.txt"))
      {:ok, :done} = Git.add(all: true, config: cfg)
      System.cmd("git", ["commit", "-m", "delete delete_me"], cd: dir, env: @git_env)
      create_tag(dir, "v2")

      assert {:ok, changes} = Git.Changes.between("v1", "v2", config: cfg)

      statuses = Map.new(changes, fn c -> {c.path, c.status} end)
      assert statuses["new.txt"] == :added
      assert statuses["keep.txt"] == :modified
      assert statuses["delete_me.txt"] == :deleted
    end

    test "returns empty list when refs are identical" do
      {dir, cfg} = setup_repo("changes_between_same")

      write_and_commit(dir, cfg, "file.txt", "content\n", "add file")
      create_tag(dir, "v1")

      assert {:ok, []} = Git.Changes.between("v1", "v1", config: cfg)
    end

    test "includes stats when stat option is true" do
      {dir, cfg} = setup_repo("changes_between_stat")

      write_and_commit(dir, cfg, "file.txt", "line1\n", "add file")
      create_tag(dir, "v1")

      write_and_commit(dir, cfg, "file.txt", "line1\nline2\nline3\n", "update file")
      create_tag(dir, "v2")

      assert {:ok, changes} = Git.Changes.between("v1", "v2", config: cfg, stat: true)
      assert length(changes) == 1
      file = hd(changes)
      assert file.status == :modified
      assert is_integer(file.insertions)
      assert is_integer(file.deletions)
    end
  end

  # ---------------------------------------------------------------------------
  # uncommitted/1
  # ---------------------------------------------------------------------------

  describe "uncommitted/1" do
    test "groups staged, modified, and untracked files" do
      {dir, cfg} = setup_repo("changes_uncommitted")

      # Create a tracked file
      write_and_commit(dir, cfg, "tracked.txt", "original\n", "add tracked")

      # Stage a new file
      File.write!(Path.join(dir, "staged.txt"), "staged content\n")
      {:ok, :done} = Git.add(files: ["staged.txt"], config: cfg)

      # Modify a tracked file (unstaged)
      File.write!(Path.join(dir, "tracked.txt"), "modified\n")

      # Create an untracked file
      File.write!(Path.join(dir, "untracked.txt"), "untracked\n")

      assert {:ok, result} = Git.Changes.uncommitted(config: cfg)

      assert result.staged != []
      staged_paths = Enum.map(result.staged, & &1.path)
      assert "staged.txt" in staged_paths

      assert result.modified != []
      modified_paths = Enum.map(result.modified, & &1.path)
      assert "tracked.txt" in modified_paths

      assert "untracked.txt" in result.untracked
    end

    test "returns empty groups on clean repo" do
      {_dir, cfg} = setup_repo("changes_uncommitted_clean")

      assert {:ok, result} = Git.Changes.uncommitted(config: cfg)
      assert result.staged == []
      assert result.modified == []
      assert result.untracked == []
    end
  end

  # ---------------------------------------------------------------------------
  # conflicts/1
  # ---------------------------------------------------------------------------

  describe "conflicts/1" do
    test "detects conflicted files during a merge" do
      {dir, cfg} = setup_repo("changes_conflicts")

      # Create base file
      write_and_commit(dir, cfg, "conflict.txt", "base\n", "add conflict file")

      # Create a branch and modify the file
      System.cmd("git", ["checkout", "-b", "feature"], cd: dir)
      write_and_commit(dir, cfg, "conflict.txt", "feature change\n", "feature edit")

      # Go back to the default branch and make a conflicting change
      System.cmd("git", ["checkout", "-"], cd: dir)
      write_and_commit(dir, cfg, "conflict.txt", "main change\n", "main edit")

      # Attempt merge (will fail with conflict)
      System.cmd("git", ["merge", "feature"], cd: dir, env: @git_env)

      assert {:ok, conflicts} = Git.Changes.conflicts(config: cfg)
      assert "conflict.txt" in conflicts
    end

    test "returns empty list when no conflicts" do
      {_dir, cfg} = setup_repo("changes_no_conflicts")

      assert {:ok, []} = Git.Changes.conflicts(config: cfg)
    end
  end

  # ---------------------------------------------------------------------------
  # summary/3
  # ---------------------------------------------------------------------------

  describe "summary/3" do
    test "returns file count, insertions, and deletions between refs" do
      {dir, cfg} = setup_repo("changes_summary")

      write_and_commit(dir, cfg, "a.txt", "line1\nline2\n", "add a")
      create_tag(dir, "v1")

      write_and_commit(dir, cfg, "b.txt", "new file\n", "add b")
      write_and_commit(dir, cfg, "a.txt", "line1\nline2\nline3\n", "update a")
      create_tag(dir, "v2")

      assert {:ok, summary} = Git.Changes.summary("v1", "v2", config: cfg)
      assert summary.files_changed == 2
      assert is_integer(summary.insertions)
      assert is_integer(summary.deletions)
      assert is_list(summary.files)
      assert length(summary.files) == 2
    end
  end
end
