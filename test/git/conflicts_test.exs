defmodule Git.ConflictsTest do
  use ExUnit.Case, async: true

  @git_env [
    {"GIT_AUTHOR_NAME", "Test User"},
    {"GIT_AUTHOR_EMAIL", "test@example.com"},
    {"GIT_COMMITTER_NAME", "Test User"},
    {"GIT_COMMITTER_EMAIL", "test@example.com"}
  ]

  setup do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "git_conflicts_test_#{:erlang.unique_integer([:positive])}"
      )

    File.mkdir_p!(tmp_dir)
    System.cmd("git", ["init", "--initial-branch=main"], cd: tmp_dir)
    System.cmd("git", ["config", "user.email", "test@example.com"], cd: tmp_dir)
    System.cmd("git", ["config", "user.name", "Test User"], cd: tmp_dir)

    # Initial commit with a file
    File.write!(Path.join(tmp_dir, "shared.txt"), "initial content")
    System.cmd("git", ["add", "."], cd: tmp_dir)
    System.cmd("git", ["commit", "-m", "initial commit"], cd: tmp_dir, env: @git_env)

    on_exit(fn -> Git.TestHelpers.rm_rf(tmp_dir) end)

    config = Git.Config.new(working_dir: tmp_dir, env: @git_env)

    %{tmp_dir: tmp_dir, config: config}
  end

  # Creates a merge conflict by modifying the same file on two branches
  defp create_conflict(tmp_dir) do
    # Create a branch and modify the file
    System.cmd("git", ["checkout", "-b", "conflict-branch"], cd: tmp_dir)
    File.write!(Path.join(tmp_dir, "shared.txt"), "branch version")
    System.cmd("git", ["add", "shared.txt"], cd: tmp_dir)
    System.cmd("git", ["commit", "-m", "branch change"], cd: tmp_dir, env: @git_env)

    # Switch back to main and modify the same file differently
    System.cmd("git", ["checkout", "main"], cd: tmp_dir)
    File.write!(Path.join(tmp_dir, "shared.txt"), "main version")
    System.cmd("git", ["add", "shared.txt"], cd: tmp_dir)
    System.cmd("git", ["commit", "-m", "main change"], cd: tmp_dir, env: @git_env)

    # Attempt merge (will fail with conflict)
    System.cmd("git", ["merge", "conflict-branch"], cd: tmp_dir, env: @git_env)
  end

  describe "detect/1" do
    test "returns false when no conflicts exist", %{config: config} do
      assert {:ok, false} = Git.Conflicts.detect(config: config)
    end

    test "returns true when merge conflicts exist", %{tmp_dir: tmp_dir, config: config} do
      create_conflict(tmp_dir)

      assert {:ok, true} = Git.Conflicts.detect(config: config)
    end
  end

  describe "files/1" do
    test "returns empty list when no conflicts exist", %{config: config} do
      assert {:ok, []} = Git.Conflicts.files(config: config)
    end

    test "lists conflicted files", %{tmp_dir: tmp_dir, config: config} do
      create_conflict(tmp_dir)

      assert {:ok, files} = Git.Conflicts.files(config: config)
      assert "shared.txt" in files
    end

    test "lists multiple conflicted files", %{tmp_dir: tmp_dir, config: config} do
      # Add a second file to the initial commit
      File.write!(Path.join(tmp_dir, "other.txt"), "initial other")
      System.cmd("git", ["add", "other.txt"], cd: tmp_dir)
      System.cmd("git", ["commit", "-m", "add other file"], cd: tmp_dir, env: @git_env)

      # Create branch, modify both files
      System.cmd("git", ["checkout", "-b", "multi-conflict"], cd: tmp_dir)
      File.write!(Path.join(tmp_dir, "shared.txt"), "branch shared")
      File.write!(Path.join(tmp_dir, "other.txt"), "branch other")
      System.cmd("git", ["add", "."], cd: tmp_dir)
      System.cmd("git", ["commit", "-m", "branch changes"], cd: tmp_dir, env: @git_env)

      # Back to main, modify same files differently
      System.cmd("git", ["checkout", "main"], cd: tmp_dir)
      File.write!(Path.join(tmp_dir, "shared.txt"), "main shared")
      File.write!(Path.join(tmp_dir, "other.txt"), "main other")
      System.cmd("git", ["add", "."], cd: tmp_dir)
      System.cmd("git", ["commit", "-m", "main changes"], cd: tmp_dir, env: @git_env)

      # Merge
      System.cmd("git", ["merge", "multi-conflict"], cd: tmp_dir, env: @git_env)

      assert {:ok, files} = Git.Conflicts.files(config: config)
      assert length(files) == 2
      assert "shared.txt" in files
      assert "other.txt" in files
    end
  end

  describe "resolved?/1" do
    test "returns true when no conflicts exist", %{config: config} do
      assert {:ok, true} = Git.Conflicts.resolved?(config: config)
    end

    test "returns false when conflicts exist", %{tmp_dir: tmp_dir, config: config} do
      create_conflict(tmp_dir)

      assert {:ok, false} = Git.Conflicts.resolved?(config: config)
    end

    test "returns true after conflicts are resolved", %{tmp_dir: tmp_dir, config: config} do
      create_conflict(tmp_dir)

      # Resolve the conflict by writing a resolved version and adding it
      File.write!(Path.join(tmp_dir, "shared.txt"), "resolved content")
      System.cmd("git", ["add", "shared.txt"], cd: tmp_dir)

      assert {:ok, true} = Git.Conflicts.resolved?(config: config)
    end
  end

  describe "abort_merge/1" do
    test "aborts a conflicted merge", %{tmp_dir: tmp_dir, config: config} do
      create_conflict(tmp_dir)

      assert {:ok, true} = Git.Conflicts.detect(config: config)

      assert {:ok, :done} = Git.Conflicts.abort_merge(config: config)

      # After abort, the file should be back to the main version
      assert File.read!(Path.join(tmp_dir, "shared.txt")) == "main version"

      # No more conflicts
      assert {:ok, false} = Git.Conflicts.detect(config: config)
    end
  end

  describe "base/2, ours/2, theirs/2" do
    test "reads each merge stage of a conflicted path", %{tmp_dir: tmp_dir, config: config} do
      create_conflict(tmp_dir)

      # The setup writes files with no trailing newline, so the raw blob
      # content is exactly these strings.
      assert {:ok, "initial content"} = Git.Conflicts.base("shared.txt", config: config)
      assert {:ok, "main version"} = Git.Conflicts.ours("shared.txt", config: config)
      assert {:ok, "branch version"} = Git.Conflicts.theirs("shared.txt", config: config)
    end

    test "base returns an error when there is no common ancestor", %{
      tmp_dir: tmp_dir,
      config: config
    } do
      # An add/add conflict has stages 2 and 3 but no stage 1 (no base).
      System.cmd("git", ["checkout", "-b", "add-side"], cd: tmp_dir)
      File.write!(Path.join(tmp_dir, "added.txt"), "from branch")
      System.cmd("git", ["add", "added.txt"], cd: tmp_dir)
      System.cmd("git", ["commit", "-m", "add on branch"], cd: tmp_dir, env: @git_env)

      System.cmd("git", ["checkout", "main"], cd: tmp_dir)
      File.write!(Path.join(tmp_dir, "added.txt"), "from main")
      System.cmd("git", ["add", "added.txt"], cd: tmp_dir)
      System.cmd("git", ["commit", "-m", "add on main"], cd: tmp_dir, env: @git_env)

      System.cmd("git", ["merge", "add-side"], cd: tmp_dir, env: @git_env)

      assert {:error, _} = Git.Conflicts.base("added.txt", config: config)
      assert {:ok, "from main"} = Git.Conflicts.ours("added.txt", config: config)
      assert {:ok, "from branch"} = Git.Conflicts.theirs("added.txt", config: config)
    end
  end

  describe "take_ours/2" do
    test "resolves a conflict with our side and stages it", %{tmp_dir: tmp_dir, config: config} do
      create_conflict(tmp_dir)

      assert {:ok, :done} = Git.Conflicts.take_ours("shared.txt", config: config)

      # Working tree holds our version and the conflict is resolved+staged.
      assert File.read!(Path.join(tmp_dir, "shared.txt")) == "main version"
      assert {:ok, true} = Git.Conflicts.resolved?(config: config)

      {porcelain, 0} = System.cmd("git", ["status", "--porcelain"], cd: tmp_dir)
      assert String.trim(porcelain) == ""
    end

    test "accepts a list of paths", %{tmp_dir: tmp_dir, config: config} do
      # Second file to conflict on.
      File.write!(Path.join(tmp_dir, "other.txt"), "initial other")
      System.cmd("git", ["add", "other.txt"], cd: tmp_dir)
      System.cmd("git", ["commit", "-m", "add other"], cd: tmp_dir, env: @git_env)

      System.cmd("git", ["checkout", "-b", "multi"], cd: tmp_dir)
      File.write!(Path.join(tmp_dir, "shared.txt"), "branch shared")
      File.write!(Path.join(tmp_dir, "other.txt"), "branch other")
      System.cmd("git", ["add", "."], cd: tmp_dir)
      System.cmd("git", ["commit", "-m", "branch changes"], cd: tmp_dir, env: @git_env)

      System.cmd("git", ["checkout", "main"], cd: tmp_dir)
      File.write!(Path.join(tmp_dir, "shared.txt"), "main shared")
      File.write!(Path.join(tmp_dir, "other.txt"), "main other")
      System.cmd("git", ["add", "."], cd: tmp_dir)
      System.cmd("git", ["commit", "-m", "main changes"], cd: tmp_dir, env: @git_env)

      System.cmd("git", ["merge", "multi"], cd: tmp_dir, env: @git_env)

      assert {:ok, :done} =
               Git.Conflicts.take_ours(["shared.txt", "other.txt"], config: config)

      assert File.read!(Path.join(tmp_dir, "shared.txt")) == "main shared"
      assert File.read!(Path.join(tmp_dir, "other.txt")) == "main other"
      assert {:ok, true} = Git.Conflicts.resolved?(config: config)
    end
  end

  describe "take_theirs/2" do
    test "resolves a conflict with their side and stages it", %{
      tmp_dir: tmp_dir,
      config: config
    } do
      create_conflict(tmp_dir)

      assert {:ok, :done} = Git.Conflicts.take_theirs("shared.txt", config: config)

      # Working tree holds their (branch) version and the conflict is resolved.
      assert File.read!(Path.join(tmp_dir, "shared.txt")) == "branch version"
      assert {:ok, true} = Git.Conflicts.resolved?(config: config)
    end
  end
end
