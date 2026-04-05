defmodule Git.RevertTest do
  use ExUnit.Case, async: true

  alias Git.Commands.Revert
  alias Git.Config
  alias Git.RevertResult

  setup do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "git_wrapper_revert_test_#{:erlang.unique_integer([:positive])}"
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

  describe "Git.Commands.Revert args/1" do
    test "builds args for reverting a commit" do
      assert Revert.args(%Revert{commits: ["HEAD"]}) == ["revert", "HEAD"]
    end

    test "builds args with no_commit flag" do
      assert Revert.args(%Revert{commits: ["HEAD"], no_commit: true}) ==
               ["revert", "--no-commit", "HEAD"]
    end

    test "builds args for abort" do
      assert Revert.args(%Revert{abort: true}) == ["revert", "--abort"]
    end

    test "builds args for continue" do
      assert Revert.args(%Revert{continue_revert: true}) == ["revert", "--continue"]
    end

    test "builds args for skip" do
      assert Revert.args(%Revert{skip: true}) == ["revert", "--skip"]
    end

    test "builds args with mainline option" do
      assert Revert.args(%Revert{commits: ["HEAD"], mainline: 1}) ==
               ["revert", "-m", "1", "HEAD"]
    end

    test "builds args with signoff and no_edit flags" do
      assert Revert.args(%Revert{commits: ["HEAD"], signoff: true, no_edit: true}) ==
               ["revert", "--signoff", "--no-edit", "HEAD"]
    end

    test "builds args with strategy and strategy_option" do
      assert Revert.args(%Revert{commits: ["HEAD"], strategy: "ort", strategy_option: "theirs"}) ==
               ["revert", "--strategy", "ort", "--strategy-option", "theirs", "HEAD"]
    end

    test "builds args with multiple commits" do
      assert Revert.args(%Revert{commits: ["abc123", "def456"]}) ==
               ["revert", "abc123", "def456"]
    end
  end

  describe "revert a commit" do
    test "reverts a commit and returns a RevertResult", %{tmp_dir: tmp_dir, config: config} do
      # Create a commit with a file change to revert
      File.write!(Path.join(tmp_dir, "revertme.txt"), "content\n")
      System.cmd("git", ["add", "revertme.txt"], cd: tmp_dir)

      System.cmd(
        "git",
        [
          "-c",
          "user.name=Test User",
          "-c",
          "user.email=test@test.com",
          "commit",
          "-m",
          "add revertme"
        ],
        cd: tmp_dir
      )

      assert {:ok, %RevertResult{} = result} =
               Git.Command.run(
                 Revert,
                 %Revert{commits: ["HEAD"]},
                 config
               )

      assert result.conflicts == false

      # The file should be gone after the revert
      refute File.exists?(Path.join(tmp_dir, "revertme.txt"))

      # Verify a revert commit was created
      {log_output, 0} = System.cmd("git", ["log", "--oneline", "-1"], cd: tmp_dir)
      assert String.contains?(log_output, "Revert")
    end
  end

  describe "revert --abort" do
    test "aborts an in-progress revert and returns :done", %{tmp_dir: tmp_dir, config: config} do
      # Create a file and commit it
      File.write!(Path.join(tmp_dir, "conflict.txt"), "original\n")
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
          "add conflict file"
        ],
        cd: tmp_dir
      )

      # Modify the file and commit again
      File.write!(Path.join(tmp_dir, "conflict.txt"), "modified\n")
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
          "modify conflict file"
        ],
        cd: tmp_dir
      )

      # Modify the file again and commit, so reverting the middle commit conflicts
      File.write!(Path.join(tmp_dir, "conflict.txt"), "modified again\n")
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
          "modify again"
        ],
        cd: tmp_dir
      )

      # Try to revert the middle commit (should conflict)
      {:error, _} =
        Git.Command.run(
          Revert,
          %Revert{commits: ["HEAD~1"]},
          config
        )

      # Abort the revert
      assert {:ok, :done} =
               Git.Command.run(
                 Revert,
                 %Revert{abort: true},
                 config
               )
    end
  end

  describe "RevertResult.parse/1" do
    test "parses output without conflicts" do
      output = "[main abc1234] Revert \"some commit\"\n 1 file changed, 1 deletion(-)\n"
      result = RevertResult.parse(output)

      assert result.conflicts == false
      assert result.raw == output
    end

    test "parses output with conflicts" do
      output = "CONFLICT (content): Merge conflict in file.txt\nerror: could not revert abc1234\n"
      result = RevertResult.parse(output)

      assert result.conflicts == true
      assert result.raw == output
    end
  end
end
