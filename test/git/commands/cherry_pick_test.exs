defmodule Git.CherryPickTest do
  use ExUnit.Case, async: true

  alias Git.CherryPickResult
  alias Git.Commands.CherryPick
  alias Git.Config

  @env [
    {"GIT_AUTHOR_NAME", "Test User"},
    {"GIT_AUTHOR_EMAIL", "test@test.com"},
    {"GIT_COMMITTER_NAME", "Test User"},
    {"GIT_COMMITTER_EMAIL", "test@test.com"}
  ]

  setup do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "git_wrapper_cherry_pick_test_#{:erlang.unique_integer([:positive])}"
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
        "initial commit"
      ],
      cd: tmp_dir
    )

    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    config = Config.new(working_dir: tmp_dir, env: @env)
    %{tmp_dir: tmp_dir, config: config}
  end

  describe "args/1" do
    test "builds args for abort" do
      assert CherryPick.args(%CherryPick{abort: true}) == ["cherry-pick", "--abort"]
    end

    test "builds args for continue" do
      assert CherryPick.args(%CherryPick{continue_pick: true}) == ["cherry-pick", "--continue"]
    end

    test "builds args for skip" do
      assert CherryPick.args(%CherryPick{skip: true}) == ["cherry-pick", "--skip"]
    end

    test "builds args with a single commit" do
      assert CherryPick.args(%CherryPick{commits: ["abc123"]}) ==
               ["cherry-pick", "abc123"]
    end

    test "builds args with multiple commits" do
      assert CherryPick.args(%CherryPick{commits: ["abc123", "def456"]}) ==
               ["cherry-pick", "abc123", "def456"]
    end

    test "builds args with --no-commit" do
      assert CherryPick.args(%CherryPick{commits: ["abc123"], no_commit: true}) ==
               ["cherry-pick", "--no-commit", "abc123"]
    end

    test "builds args with --signoff" do
      assert CherryPick.args(%CherryPick{commits: ["abc123"], signoff: true}) ==
               ["cherry-pick", "--signoff", "abc123"]
    end

    test "builds args with -m for merge commits" do
      assert CherryPick.args(%CherryPick{commits: ["abc123"], mainline: 1}) ==
               ["cherry-pick", "-m", "1", "abc123"]
    end

    test "builds args with strategy options" do
      assert CherryPick.args(%CherryPick{
               commits: ["abc123"],
               strategy: "ort",
               strategy_option: "theirs"
             }) ==
               ["cherry-pick", "--strategy", "ort", "--strategy-option", "theirs", "abc123"]
    end
  end

  describe "cherry-pick a commit" do
    test "picks a commit from another branch", %{tmp_dir: tmp_dir, config: config} do
      # Create a branch with a commit
      System.cmd("git", ["checkout", "-b", "feature"], cd: tmp_dir)
      File.write!(Path.join(tmp_dir, "feature.txt"), "feature content\n")
      System.cmd("git", ["add", "feature.txt"], cd: tmp_dir)

      System.cmd(
        "git",
        [
          "-c",
          "user.name=Test User",
          "-c",
          "user.email=test@test.com",
          "commit",
          "-m",
          "feature commit"
        ],
        cd: tmp_dir
      )

      # Get the commit hash
      {hash, 0} = System.cmd("git", ["rev-parse", "HEAD"], cd: tmp_dir)
      hash = String.trim(hash)

      # Switch back to main and cherry-pick
      System.cmd("git", ["checkout", "main"], cd: tmp_dir)

      result =
        Git.Command.run(CherryPick, %CherryPick{commits: [hash]}, config)

      assert {:ok, %CherryPickResult{conflicts: false}} = result
    end
  end

  describe "cherry-pick with --no-commit" do
    test "stages changes without committing", %{tmp_dir: tmp_dir, config: config} do
      System.cmd("git", ["checkout", "-b", "feature"], cd: tmp_dir)
      File.write!(Path.join(tmp_dir, "feature.txt"), "feature content\n")
      System.cmd("git", ["add", "feature.txt"], cd: tmp_dir)

      System.cmd(
        "git",
        [
          "-c",
          "user.name=Test User",
          "-c",
          "user.email=test@test.com",
          "commit",
          "-m",
          "feature commit"
        ],
        cd: tmp_dir
      )

      {hash, 0} = System.cmd("git", ["rev-parse", "HEAD"], cd: tmp_dir)
      hash = String.trim(hash)

      System.cmd("git", ["checkout", "main"], cd: tmp_dir)

      result =
        Git.Command.run(
          CherryPick,
          %CherryPick{commits: [hash], no_commit: true},
          config
        )

      assert {:ok, %CherryPickResult{}} = result
    end
  end

  describe "cherry-pick abort" do
    test "aborts an in-progress cherry-pick and returns :done", %{
      tmp_dir: tmp_dir,
      config: config
    } do
      # Create conflicting changes
      System.cmd("git", ["checkout", "-b", "conflict-branch"], cd: tmp_dir)
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

      {hash, 0} = System.cmd("git", ["rev-parse", "HEAD"], cd: tmp_dir)
      hash = String.trim(hash)

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

      # Trigger a conflicting cherry-pick (expect failure)
      {:error, _} =
        Git.Command.run(CherryPick, %CherryPick{commits: [hash]}, config)

      # Now abort it
      assert {:ok, :done} =
               Git.Command.run(CherryPick, %CherryPick{abort: true}, config)
    end
  end

  describe "cherry-pick failure" do
    test "returns an error for nonexistent commit", %{config: config} do
      assert {:error, {output, exit_code}} =
               Git.Command.run(
                 CherryPick,
                 %CherryPick{commits: ["0000000000000000000000000000000000000000"]},
                 config
               )

      assert exit_code != 0
      assert is_binary(output)
    end
  end

  describe "CherryPickResult.parse/1" do
    test "parses clean cherry-pick output" do
      output = "[main abc1234] cherry-picked commit\n 1 file changed, 1 insertion(+)\n"
      result = CherryPickResult.parse(output)

      assert result.conflicts == false
      assert result.raw == output
    end

    test "parses conflict output" do
      output = "CONFLICT (content): Merge conflict in file.txt\n"
      result = CherryPickResult.parse(output)

      assert result.conflicts == true
      assert result.raw == output
    end
  end
end
