defmodule GitWrapper.MergeTest do
  use ExUnit.Case, async: true

  alias GitWrapper.MergeResult
  alias GitWrapper.Config

  setup do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "git_wrapper_merge_test_#{:erlang.unique_integer([:positive])}"
      )

    File.mkdir_p!(tmp_dir)

    System.cmd("git", ["init", "--initial-branch=main"], cd: tmp_dir)

    System.cmd(
      "git",
      ["-c", "user.name=Test User", "-c", "user.email=test@test.com", "commit", "--allow-empty", "-m", "initial"],
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

  defp create_branch_with_commit(tmp_dir, branch, filename, content) do
    System.cmd("git", ["checkout", "-b", branch], cd: tmp_dir)
    File.write!(Path.join(tmp_dir, filename), content)
    System.cmd("git", ["add", filename], cd: tmp_dir)

    System.cmd(
      "git",
      ["-c", "user.name=Test User", "-c", "user.email=test@test.com", "commit", "-m", "add #{filename}"],
      cd: tmp_dir
    )

    System.cmd("git", ["checkout", "main"], cd: tmp_dir)
  end

  describe "merge branch (fast-forward)" do
    test "returns a MergeResult with fast_forward true", %{tmp_dir: tmp_dir, config: config} do
      create_branch_with_commit(tmp_dir, "feat/fast-forward", "ff.txt", "content\n")

      assert {:ok, %MergeResult{} = result} =
               GitWrapperEx.merge("feat/fast-forward", config: config)

      assert result.fast_forward == true
      assert result.already_up_to_date == false
    end
  end

  describe "merge branch --no-ff" do
    test "creates a merge commit instead of fast-forwarding", %{tmp_dir: tmp_dir, config: config} do
      create_branch_with_commit(tmp_dir, "feat/no-ff", "noff.txt", "content\n")

      assert {:ok, %MergeResult{} = result} =
               GitWrapperEx.merge("feat/no-ff", no_ff: true, config: config)

      assert result.fast_forward == false
      assert result.already_up_to_date == false
    end
  end

  describe "merge when already up to date" do
    test "returns a MergeResult with already_up_to_date true", %{config: config} do
      assert {:ok, %MergeResult{} = result} =
               GitWrapperEx.merge("main", config: config)

      assert result.already_up_to_date == true
      assert result.fast_forward == false
    end
  end

  describe "merge --abort" do
    test "aborts an in-progress merge and returns :done", %{tmp_dir: tmp_dir, config: config} do
      # Create two branches with conflicting changes on the same file
      System.cmd("git", ["checkout", "-b", "feat/conflict"], cd: tmp_dir)
      File.write!(Path.join(tmp_dir, "conflict.txt"), "branch version\n")
      System.cmd("git", ["add", "conflict.txt"], cd: tmp_dir)

      System.cmd(
        "git",
        ["-c", "user.name=Test User", "-c", "user.email=test@test.com", "commit", "-m", "branch change"],
        cd: tmp_dir
      )

      System.cmd("git", ["checkout", "main"], cd: tmp_dir)
      File.write!(Path.join(tmp_dir, "conflict.txt"), "main version\n")
      System.cmd("git", ["add", "conflict.txt"], cd: tmp_dir)

      System.cmd(
        "git",
        ["-c", "user.name=Test User", "-c", "user.email=test@test.com", "commit", "-m", "main change"],
        cd: tmp_dir
      )

      # Trigger a conflicting merge (expect failure/conflict)
      {:error, _} = GitWrapperEx.merge("feat/conflict", config: config)

      # Now abort it
      assert {:ok, :done} = GitWrapperEx.merge(:abort, config: config)
    end
  end

  describe "merge failure" do
    test "returns an error when merging a nonexistent branch", %{config: config} do
      assert {:error, {output, exit_code}} =
               GitWrapperEx.merge("nonexistent-branch", config: config)

      assert exit_code != 0
      assert is_binary(output)
    end
  end

  describe "MergeResult.parse/1" do
    test "parses fast-forward output" do
      output = "Updating abc1234..def5678\nFast-forward\n file.txt | 1 +\n 1 file changed, 1 insertion(+)\n"
      result = MergeResult.parse(output)

      assert result.fast_forward == true
      assert result.already_up_to_date == false
    end

    test "parses already up to date output" do
      output = "Already up to date.\n"
      result = MergeResult.parse(output)

      assert result.fast_forward == false
      assert result.already_up_to_date == true
    end

    test "parses merge commit output" do
      output = "Merge made by the 'ort' strategy.\n file.txt | 1 +\n 1 file changed, 1 insertion(+)\n"
      result = MergeResult.parse(output)

      assert result.fast_forward == false
      assert result.already_up_to_date == false
    end
  end
end
