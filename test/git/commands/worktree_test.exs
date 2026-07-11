defmodule Git.WorktreeTest do
  use ExUnit.Case, async: true

  alias Git.Commands.Worktree, as: WorktreeCmd
  alias Git.{Config, Worktree}

  setup do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "git_wrapper_worktree_test_#{:erlang.unique_integer([:positive])}"
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

  describe "args/1" do
    test "list mode produces porcelain args" do
      assert WorktreeCmd.args(%WorktreeCmd{}) == ["worktree", "list", "--porcelain"]
    end

    test "add mode produces correct args" do
      cmd = %WorktreeCmd{add_path: "/tmp/wt", add_branch: "main"}
      assert WorktreeCmd.args(cmd) == ["worktree", "add", "/tmp/wt", "main"]
    end

    test "add with new branch produces -b flag" do
      cmd = %WorktreeCmd{add_path: "/tmp/wt", add_new_branch: "feat"}
      assert WorktreeCmd.args(cmd) == ["worktree", "add", "-b", "feat", "/tmp/wt"]
    end

    test "add with new branch and explicit start_point" do
      cmd = %WorktreeCmd{add_path: "/tmp/wt", add_new_branch: "feat", start_point: "main"}
      assert WorktreeCmd.args(cmd) == ["worktree", "add", "-b", "feat", "/tmp/wt", "main"]
    end

    test "start_point takes precedence over add_branch as the positional commit-ish" do
      cmd = %WorktreeCmd{
        add_path: "/tmp/wt",
        add_new_branch: "feat",
        start_point: "v1.0",
        add_branch: "main"
      }

      assert WorktreeCmd.args(cmd) == ["worktree", "add", "-b", "feat", "/tmp/wt", "v1.0"]
    end

    test "move mode produces correct args" do
      cmd = %WorktreeCmd{move: {"/tmp/wt", "/tmp/moved"}}
      assert WorktreeCmd.args(cmd) == ["worktree", "move", "/tmp/wt", "/tmp/moved"]
    end

    test "move mode honors force" do
      cmd = %WorktreeCmd{move: {"/tmp/wt", "/tmp/moved"}, force: true}
      assert WorktreeCmd.args(cmd) == ["worktree", "move", "--force", "/tmp/wt", "/tmp/moved"]
    end

    test "unlock mode produces correct args" do
      cmd = %WorktreeCmd{unlock: "/tmp/wt"}
      assert WorktreeCmd.args(cmd) == ["worktree", "unlock", "/tmp/wt"]
    end

    test "repair mode produces correct args" do
      assert WorktreeCmd.args(%WorktreeCmd{repair: true}) == ["worktree", "repair"]
    end

    test "prune with expire produces --expire" do
      cmd = %WorktreeCmd{prune: true, expire: "now"}
      assert WorktreeCmd.args(cmd) == ["worktree", "prune", "--expire", "now"]
    end

    test "add with detach flag" do
      cmd = %WorktreeCmd{add_path: "/tmp/wt", detach: true}
      assert WorktreeCmd.args(cmd) == ["worktree", "add", "--detach", "/tmp/wt"]
    end

    test "remove mode produces correct args" do
      cmd = %WorktreeCmd{remove_path: "/tmp/wt", force: true}
      assert WorktreeCmd.args(cmd) == ["worktree", "remove", "--force", "/tmp/wt"]
    end

    test "prune mode produces correct args" do
      cmd = %WorktreeCmd{prune: true}
      assert WorktreeCmd.args(cmd) == ["worktree", "prune"]
    end
  end

  describe "list worktrees" do
    test "lists the main worktree", %{config: config} do
      assert {:ok, worktrees} =
               Git.Command.run(WorktreeCmd, %WorktreeCmd{}, config)

      assert is_list(worktrees)
      assert worktrees != []

      [main_wt | _] = worktrees
      assert %Worktree{} = main_wt
      assert main_wt.path != nil
      assert String.length(main_wt.head) > 0
      assert main_wt.branch == "refs/heads/main"
    end
  end

  describe "add and remove worktree" do
    test "adds and removes a linked worktree", %{tmp_dir: tmp_dir, config: config} do
      wt_path = Path.join(tmp_dir, "linked-wt")

      # Add worktree
      add_cmd = %WorktreeCmd{add_path: wt_path, add_new_branch: "wt-branch"}

      assert {:ok, :done} =
               Git.Command.run(WorktreeCmd, add_cmd, config)

      assert File.dir?(wt_path)

      # List should show both worktrees
      assert {:ok, worktrees} =
               Git.Command.run(WorktreeCmd, %WorktreeCmd{}, config)

      assert length(worktrees) == 2

      # Remove worktree
      remove_cmd = %WorktreeCmd{remove_path: wt_path, force: true}

      assert {:ok, :done} =
               Git.Command.run(WorktreeCmd, remove_cmd, config)

      # List should show only main
      assert {:ok, worktrees} =
               Git.Command.run(WorktreeCmd, %WorktreeCmd{}, config)

      assert length(worktrees) == 1
    end
  end

  describe "Worktree.parse/1" do
    test "parses porcelain output" do
      output = """
      worktree /tmp/main
      HEAD abc1234def5678abc1234def5678abc1234def5678
      branch refs/heads/main

      worktree /tmp/linked
      HEAD 1234567890abcdef1234567890abcdef12345678
      branch refs/heads/feature

      """

      worktrees = Worktree.parse(output)
      assert length(worktrees) == 2

      [main, linked] = worktrees
      assert main.path == "/tmp/main"
      assert main.head == "abc1234def5678abc1234def5678abc1234def5678"
      assert main.branch == "refs/heads/main"
      assert main.bare == false
      assert main.detached == false

      assert linked.path == "/tmp/linked"
      assert linked.branch == "refs/heads/feature"
    end

    test "parses bare worktree" do
      output = "worktree /tmp/bare\nHEAD abc1234\nbare\n\n"
      [wt] = Worktree.parse(output)
      assert wt.bare == true
    end

    test "parses detached worktree" do
      output = "worktree /tmp/detached\nHEAD abc1234\ndetached\n\n"
      [wt] = Worktree.parse(output)
      assert wt.detached == true
    end

    test "parses a locked worktree with a reason" do
      output = "worktree /tmp/wt\nHEAD abc1234\nbranch refs/heads/wt\nlocked busy testing\n\n"
      [wt] = Worktree.parse(output)
      assert wt.locked == "busy testing"
    end

    test "parses a locked worktree with no reason" do
      output = "worktree /tmp/wt\nHEAD abc1234\nlocked\n\n"
      [wt] = Worktree.parse(output)
      assert wt.locked == ""
    end

    test "parses a prunable worktree" do
      output =
        "worktree /tmp/gone\nHEAD abc1234\nbranch refs/heads/wt\nprunable gitdir file points to non-existent location\n\n"

      [wt] = Worktree.parse(output)
      assert wt.prunable == "gitdir file points to non-existent location"
    end

    test "leaves locked and prunable nil when absent" do
      output = "worktree /tmp/main\nHEAD abc1234\nbranch refs/heads/main\n\n"
      [wt] = Worktree.parse(output)
      assert wt.locked == nil
      assert wt.prunable == nil
    end

    test "parses empty output" do
      assert Worktree.parse("") == []
    end
  end

  describe "move, unlock, repair, prunable (integration)" do
    test "moves a linked worktree to a new path", %{tmp_dir: tmp_dir, config: config} do
      from = Path.join(tmp_dir, "wt-from")
      to = Path.join(tmp_dir, "wt-to")

      assert {:ok, :done} =
               Git.Command.run(
                 WorktreeCmd,
                 %WorktreeCmd{add_path: from, add_new_branch: "mv"},
                 config
               )

      assert {:ok, :done} =
               Git.Command.run(WorktreeCmd, %WorktreeCmd{move: {from, to}}, config)

      refute File.dir?(from)
      assert File.dir?(to)

      # git reports resolved (symlink-followed) paths, so compare by basename.
      {:ok, worktrees} = Git.Command.run(WorktreeCmd, %WorktreeCmd{}, config)
      assert Enum.any?(worktrees, &(Path.basename(&1.path) == "wt-to"))
      refute Enum.any?(worktrees, &(Path.basename(&1.path) == "wt-from"))
    end

    test "detects and unlocks a locked worktree", %{tmp_dir: tmp_dir, config: config} do
      wt = Path.join(tmp_dir, "wt-locked")

      assert {:ok, :done} =
               Git.Command.run(
                 WorktreeCmd,
                 %WorktreeCmd{add_path: wt, add_new_branch: "lk", lock: true},
                 config
               )

      {:ok, worktrees} = Git.Command.run(WorktreeCmd, %WorktreeCmd{}, config)
      locked = Enum.find(worktrees, &(Path.basename(&1.path) == "wt-locked"))
      assert locked.locked != nil

      assert {:ok, :done} =
               Git.Command.run(WorktreeCmd, %WorktreeCmd{unlock: wt}, config)

      {:ok, worktrees} = Git.Command.run(WorktreeCmd, %WorktreeCmd{}, config)
      unlocked = Enum.find(worktrees, &(Path.basename(&1.path) == "wt-locked"))
      assert unlocked.locked == nil
    end

    test "start_point pins the new branch at a given commit-ish", %{
      tmp_dir: tmp_dir,
      config: config
    } do
      wt = Path.join(tmp_dir, "wt-sp")

      assert {:ok, :done} =
               Git.Command.run(
                 WorktreeCmd,
                 %WorktreeCmd{add_path: wt, add_new_branch: "sp", start_point: "main"},
                 config
               )

      {main_head, 0} = System.cmd("git", ["rev-parse", "main"], cd: tmp_dir)
      {sp_head, 0} = System.cmd("git", ["rev-parse", "sp"], cd: tmp_dir)
      assert String.trim(main_head) == String.trim(sp_head)
    end

    test "surfaces a prunable orphan, then prune clears it", %{tmp_dir: tmp_dir, config: config} do
      wt = Path.join(tmp_dir, "wt-orphan")

      assert {:ok, :done} =
               Git.Command.run(
                 WorktreeCmd,
                 %WorktreeCmd{add_path: wt, add_new_branch: "orphan"},
                 config
               )

      # Simulate a crashed agent: the directory vanishes without git cleanup.
      File.rm_rf!(wt)

      {:ok, worktrees} = Git.Command.run(WorktreeCmd, %WorktreeCmd{}, config)
      orphan = Enum.find(worktrees, &(Path.basename(&1.path) == "wt-orphan"))
      assert orphan.prunable != nil

      assert {:ok, :done} =
               Git.Command.run(WorktreeCmd, %WorktreeCmd{prune: true}, config)

      {:ok, worktrees} = Git.Command.run(WorktreeCmd, %WorktreeCmd{}, config)
      refute Enum.any?(worktrees, &(Path.basename(&1.path) == "wt-orphan"))
    end
  end
end
