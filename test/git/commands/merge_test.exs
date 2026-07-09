defmodule Git.MergeTest do
  use ExUnit.Case, async: true

  alias Git.Commands.Merge
  alias Git.Config
  alias Git.MergeResult

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

    on_exit(fn -> Git.TestHelpers.rm_rf(tmp_dir) end)

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
      [
        "-c",
        "user.name=Test User",
        "-c",
        "user.email=test@test.com",
        "commit",
        "-m",
        "add #{filename}"
      ],
      cd: tmp_dir
    )

    System.cmd("git", ["checkout", "main"], cd: tmp_dir)
  end

  defp commit_all(tmp_dir, message) do
    System.cmd("git", ["add", "-A"], cd: tmp_dir)

    System.cmd(
      "git",
      ["-c", "user.name=Test User", "-c", "user.email=test@test.com", "commit", "-m", message],
      cd: tmp_dir
    )
  end

  describe "Git.Commands.Merge args/1" do
    test "existing output is unchanged" do
      assert Merge.args(%Merge{branch: "feature", no_ff: true}) == ["merge", "--no-ff", "feature"]
    end

    test "builds strategy and repeated strategy options" do
      command = %Merge{
        branch: "b",
        strategy: "ort",
        strategy_option: ["ours", "ignore-space-change"]
      }

      assert Merge.args(command) ==
               [
                 "merge",
                 "--strategy",
                 "ort",
                 "--strategy-option",
                 "ours",
                 "--strategy-option",
                 "ignore-space-change",
                 "b"
               ]
    end

    test "builds --ff-only with a message" do
      assert Merge.args(%Merge{branch: "b", ff_only: true, message: "msg"}) ==
               ["merge", "--ff-only", "-m", "msg", "b"]
    end

    test "continue concludes the merge non-interactively via commit --no-edit" do
      assert Merge.args(%Merge{continue: true}) == ["commit", "--no-edit"]
    end

    test "builds --quit" do
      assert Merge.args(%Merge{quit: true}) == ["merge", "--quit"]
    end
  end

  describe "merge branch (fast-forward)" do
    test "returns a MergeResult with fast_forward true", %{tmp_dir: tmp_dir, config: config} do
      create_branch_with_commit(tmp_dir, "feat/fast-forward", "ff.txt", "content\n")

      assert {:ok, %MergeResult{} = result} =
               Git.merge("feat/fast-forward", config: config)

      assert result.fast_forward == true
      assert result.already_up_to_date == false
    end
  end

  describe "merge branch --no-ff" do
    test "creates a merge commit instead of fast-forwarding", %{tmp_dir: tmp_dir, config: config} do
      create_branch_with_commit(tmp_dir, "feat/no-ff", "noff.txt", "content\n")

      assert {:ok, %MergeResult{} = result} =
               Git.merge("feat/no-ff", no_ff: true, config: config)

      assert result.fast_forward == false
      assert result.already_up_to_date == false
    end
  end

  describe "merge when already up to date" do
    test "returns a MergeResult with already_up_to_date true", %{config: config} do
      assert {:ok, %MergeResult{} = result} =
               Git.merge("main", config: config)

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
        [
          "-c",
          "user.name=Test User",
          "-c",
          "user.email=test@test.com",
          "commit",
          "-m",
          "branch change"
        ],
        cd: tmp_dir
      )

      System.cmd("git", ["checkout", "main"], cd: tmp_dir)
      File.write!(Path.join(tmp_dir, "conflict.txt"), "main version\n")
      System.cmd("git", ["add", "conflict.txt"], cd: tmp_dir)

      System.cmd(
        "git",
        [
          "-c",
          "user.name=Test User",
          "-c",
          "user.email=test@test.com",
          "commit",
          "-m",
          "main change"
        ],
        cd: tmp_dir
      )

      # Trigger a conflicting merge (expect failure/conflict)
      {:error, _} = Git.merge("feat/conflict", config: config)

      # Now abort it
      assert {:ok, :done} = Git.merge(:abort, config: config)
    end
  end

  describe "merge strategy options and drivers" do
    test "-Xours auto-resolves a conflicting merge", %{tmp_dir: tmp_dir, config: config} do
      path = Path.join(tmp_dir, "conflict.txt")
      File.write!(path, "base\n")
      commit_all(tmp_dir, "base")

      System.cmd("git", ["checkout", "-b", "feat/conflict"], cd: tmp_dir)
      File.write!(path, "feat\n")
      commit_all(tmp_dir, "feat")
      System.cmd("git", ["checkout", "main"], cd: tmp_dir)
      File.write!(path, "main\n")
      commit_all(tmp_dir, "main")

      assert {:ok, %MergeResult{}} =
               Git.merge("feat/conflict",
                 config: config,
                 strategy_option: ["ours"],
                 no_edit: true
               )

      assert File.read!(path) == "main\n"
    end

    test "--ff-only errors when a fast-forward is impossible", %{tmp_dir: tmp_dir, config: config} do
      create_branch_with_commit(tmp_dir, "feat/div", "feat.txt", "f\n")
      File.write!(Path.join(tmp_dir, "main.txt"), "m\n")
      commit_all(tmp_dir, "main diverge")

      assert {:error, {_output, exit_code}} = Git.merge("feat/div", config: config, ff_only: true)
      assert exit_code != 0
    end

    test "merge(:continue) completes a merge after resolving conflicts",
         %{tmp_dir: tmp_dir, config: config} do
      path = Path.join(tmp_dir, "c.txt")
      File.write!(path, "base\n")
      commit_all(tmp_dir, "base")

      System.cmd("git", ["checkout", "-b", "feat/cont"], cd: tmp_dir)
      File.write!(path, "feat\n")
      commit_all(tmp_dir, "feat")
      System.cmd("git", ["checkout", "main"], cd: tmp_dir)
      File.write!(path, "main\n")
      commit_all(tmp_dir, "main")

      assert {:error, _} = Git.merge("feat/cont", config: config)

      File.write!(path, "resolved\n")
      System.cmd("git", ["add", "c.txt"], cd: tmp_dir)

      assert {:ok, :done} = Git.merge(:continue, config: config)
    end
  end

  describe "merge failure" do
    test "returns an error when merging a nonexistent branch", %{config: config} do
      assert {:error, {output, exit_code}} =
               Git.merge("nonexistent-branch", config: config)

      assert exit_code != 0
      assert is_binary(output)
    end
  end

  describe "MergeResult.parse/1" do
    test "parses fast-forward output" do
      output =
        "Updating abc1234..def5678\nFast-forward\n file.txt | 1 +\n 1 file changed, 1 insertion(+)\n"

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
      output =
        "Merge made by the 'ort' strategy.\n file.txt | 1 +\n 1 file changed, 1 insertion(+)\n"

      result = MergeResult.parse(output)

      assert result.fast_forward == false
      assert result.already_up_to_date == false
    end
  end
end
