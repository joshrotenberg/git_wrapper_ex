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

  # Creates a cherry-pick conflict: `feat` and main change shared.txt
  # differently, so cherry-picking feat onto main conflicts.
  defp create_cherry_pick_conflict(tmp_dir) do
    System.cmd("git", ["checkout", "-b", "feat"], cd: tmp_dir)
    File.write!(Path.join(tmp_dir, "shared.txt"), "feat version")
    System.cmd("git", ["add", "shared.txt"], cd: tmp_dir)
    System.cmd("git", ["commit", "-m", "feat change"], cd: tmp_dir, env: @git_env)

    System.cmd("git", ["checkout", "main"], cd: tmp_dir)
    File.write!(Path.join(tmp_dir, "shared.txt"), "main version")
    System.cmd("git", ["add", "shared.txt"], cd: tmp_dir)
    System.cmd("git", ["commit", "-m", "main change"], cd: tmp_dir, env: @git_env)

    System.cmd("git", ["cherry-pick", "feat"], cd: tmp_dir, env: @git_env)
  end

  # Creates a rebase conflict: `topic` and main change the same line, so
  # rebasing topic onto main conflicts while replaying topic's commit.
  defp create_rebase_conflict(tmp_dir) do
    System.cmd("git", ["checkout", "-b", "topic"], cd: tmp_dir)
    File.write!(Path.join(tmp_dir, "shared.txt"), "topic version")
    System.cmd("git", ["add", "shared.txt"], cd: tmp_dir)
    System.cmd("git", ["commit", "-m", "topic change"], cd: tmp_dir, env: @git_env)

    System.cmd("git", ["checkout", "main"], cd: tmp_dir)
    File.write!(Path.join(tmp_dir, "shared.txt"), "main version")
    System.cmd("git", ["add", "shared.txt"], cd: tmp_dir)
    System.cmd("git", ["commit", "-m", "main change"], cd: tmp_dir, env: @git_env)

    System.cmd("git", ["checkout", "topic"], cd: tmp_dir)
    System.cmd("git", ["rebase", "main"], cd: tmp_dir, env: @git_env)
  end

  # Creates a revert conflict: a commit changes shared.txt, a later commit
  # changes the same line again, so reverting the first conflicts with the
  # second.
  defp create_revert_conflict(tmp_dir) do
    File.write!(Path.join(tmp_dir, "shared.txt"), "second version")
    System.cmd("git", ["add", "shared.txt"], cd: tmp_dir)
    System.cmd("git", ["commit", "-m", "second"], cd: tmp_dir, env: @git_env)

    File.write!(Path.join(tmp_dir, "shared.txt"), "third version")
    System.cmd("git", ["add", "shared.txt"], cd: tmp_dir)
    System.cmd("git", ["commit", "-m", "third"], cd: tmp_dir, env: @git_env)

    {sha, 0} = System.cmd("git", ["rev-parse", "HEAD~1"], cd: tmp_dir)
    System.cmd("git", ["revert", String.trim(sha)], cd: tmp_dir, env: @git_env)
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

  describe "resolve/2" do
    test "using: :ours keeps our side and stages it", %{tmp_dir: tmp_dir, config: config} do
      create_conflict(tmp_dir)

      assert {:ok, :done} = Git.Conflicts.resolve("shared.txt", using: :ours, config: config)
      assert File.read!(Path.join(tmp_dir, "shared.txt")) == "main version"
      assert {:ok, true} = Git.Conflicts.resolved?(config: config)
    end

    test "using: :theirs keeps their side and stages it", %{tmp_dir: tmp_dir, config: config} do
      create_conflict(tmp_dir)

      assert {:ok, :done} = Git.Conflicts.resolve("shared.txt", using: :theirs, config: config)
      assert File.read!(Path.join(tmp_dir, "shared.txt")) == "branch version"
      assert {:ok, true} = Git.Conflicts.resolved?(config: config)
    end

    test "accepts a list of paths", %{tmp_dir: tmp_dir, config: config} do
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
               Git.Conflicts.resolve(["shared.txt", "other.txt"], using: :theirs, config: config)

      assert File.read!(Path.join(tmp_dir, "shared.txt")) == "branch shared"
      assert File.read!(Path.join(tmp_dir, "other.txt")) == "branch other"
      assert {:ok, true} = Git.Conflicts.resolved?(config: config)
    end

    test "returns an error for an unknown strategy", %{config: config} do
      assert {:error, {:invalid_strategy, :bogus}} =
               Git.Conflicts.resolve("shared.txt", using: :bogus, config: config)
    end

    test "returns an error when :using is missing", %{config: config} do
      assert {:error, {:invalid_strategy, nil}} =
               Git.Conflicts.resolve("shared.txt", config: config)
    end
  end

  describe "abort/1" do
    test "aborts an in-progress merge", %{tmp_dir: tmp_dir, config: config} do
      create_conflict(tmp_dir)

      assert {:ok, true} = Git.Conflicts.detect(config: config)
      assert {:ok, :done} = Git.Conflicts.abort(config: config)
      assert File.read!(Path.join(tmp_dir, "shared.txt")) == "main version"
      assert {:ok, false} = Git.Conflicts.detect(config: config)
    end

    test "aborts an in-progress cherry-pick", %{tmp_dir: tmp_dir, config: config} do
      create_cherry_pick_conflict(tmp_dir)

      assert {:ok, true} = Git.Conflicts.detect(config: config)
      assert {:ok, :done} = Git.Conflicts.abort(config: config)
      assert {:ok, false} = Git.Conflicts.detect(config: config)
      refute File.exists?(Path.join([tmp_dir, ".git", "CHERRY_PICK_HEAD"]))
    end

    test "aborts an in-progress rebase", %{tmp_dir: tmp_dir, config: config} do
      create_rebase_conflict(tmp_dir)

      assert {:ok, true} = Git.Conflicts.detect(config: config)
      assert {:ok, :done} = Git.Conflicts.abort(config: config)
      assert {:ok, false} = Git.Conflicts.detect(config: config)
      refute File.dir?(Path.join([tmp_dir, ".git", "rebase-merge"]))
    end

    test "aborts an in-progress revert", %{tmp_dir: tmp_dir, config: config} do
      create_revert_conflict(tmp_dir)

      assert {:ok, true} = Git.Conflicts.detect(config: config)
      assert {:ok, :done} = Git.Conflicts.abort(config: config)
      assert {:ok, false} = Git.Conflicts.detect(config: config)
      refute File.exists?(Path.join([tmp_dir, ".git", "REVERT_HEAD"]))
    end

    test "returns an error when no operation is in progress", %{config: config} do
      assert {:error, :no_operation_in_progress} = Git.Conflicts.abort(config: config)
    end
  end

  describe "continue/1" do
    test "concludes a resolved merge with a merge commit", %{tmp_dir: tmp_dir, config: config} do
      create_conflict(tmp_dir)

      assert {:ok, :done} = Git.Conflicts.resolve("shared.txt", using: :ours, config: config)
      assert {:ok, %Git.CommitResult{}} = Git.Conflicts.continue(config: config)
      assert {:ok, false} = Git.Conflicts.detect(config: config)
      refute File.exists?(Path.join([tmp_dir, ".git", "MERGE_HEAD"]))

      # The concluded commit is a real merge commit with two parents.
      {parents, 0} = System.cmd("git", ["log", "-1", "--pretty=%P"], cd: tmp_dir)
      assert length(String.split(String.trim(parents))) == 2
    end

    test "continues a cherry-pick after resolution", %{tmp_dir: tmp_dir, config: config} do
      create_cherry_pick_conflict(tmp_dir)

      # Resolve to their side so the concluded commit is non-empty.
      assert {:ok, :done} = Git.Conflicts.resolve("shared.txt", using: :theirs, config: config)
      assert {:ok, :done} = Git.Conflicts.continue(config: config)
      assert {:ok, false} = Git.Conflicts.detect(config: config)
      refute File.exists?(Path.join([tmp_dir, ".git", "CHERRY_PICK_HEAD"]))
      assert File.read!(Path.join(tmp_dir, "shared.txt")) == "feat version"
    end

    test "continues a rebase after resolution", %{tmp_dir: tmp_dir, config: config} do
      create_rebase_conflict(tmp_dir)

      assert {:ok, :done} = Git.Conflicts.resolve("shared.txt", using: :theirs, config: config)
      assert {:ok, :done} = Git.Conflicts.continue(config: config)
      assert {:ok, false} = Git.Conflicts.detect(config: config)
      refute File.dir?(Path.join([tmp_dir, ".git", "rebase-merge"]))
      assert File.read!(Path.join(tmp_dir, "shared.txt")) == "topic version"
    end

    test "continues a revert after resolution", %{tmp_dir: tmp_dir, config: config} do
      create_revert_conflict(tmp_dir)

      assert {:ok, :done} = Git.Conflicts.resolve("shared.txt", using: :theirs, config: config)
      assert {:ok, :done} = Git.Conflicts.continue(config: config)
      assert {:ok, false} = Git.Conflicts.detect(config: config)
      refute File.exists?(Path.join([tmp_dir, ".git", "REVERT_HEAD"]))
    end

    test "returns an error when no operation is in progress", %{config: config} do
      assert {:error, :no_operation_in_progress} = Git.Conflicts.continue(config: config)
    end
  end
end
