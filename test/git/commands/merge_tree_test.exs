defmodule Git.Commands.MergeTreeTest do
  use ExUnit.Case, async: true

  alias Git.Commands.MergeTree
  alias Git.Config
  alias Git.MergeTreeResult

  describe "args/1" do
    test "builds merge-tree --write-tree --name-only with both branches" do
      assert MergeTree.args(%MergeTree{branch1: "main", branch2: "feature"}) ==
               ["merge-tree", "--write-tree", "--name-only", "main", "feature"]
    end
  end

  describe "merge-tree integration" do
    setup do
      tmp_dir =
        Path.join(
          System.tmp_dir!(),
          "git_wrapper_merge_tree_test_#{:erlang.unique_integer([:positive])}"
        )

      File.mkdir_p!(tmp_dir)
      git = fn args -> System.cmd("git", args, cd: tmp_dir) end
      git.(["init", "--initial-branch=main"])
      git.(["config", "user.name", "T"])
      git.(["config", "user.email", "t@t.com"])

      File.write!(Path.join(tmp_dir, "f.txt"), "base\n")
      git.(["add", "-A"])
      git.(["commit", "-m", "base"])

      # feat: changes f.txt (will conflict with main) and adds g.txt
      git.(["checkout", "-b", "feat"])
      File.write!(Path.join(tmp_dir, "f.txt"), "feat\n")
      File.write!(Path.join(tmp_dir, "g.txt"), "new\n")
      git.(["add", "-A"])
      git.(["commit", "-m", "feat"])

      # addonly: only adds h.txt (merges cleanly with main)
      git.(["checkout", "main"])
      git.(["checkout", "-b", "addonly"])
      File.write!(Path.join(tmp_dir, "h.txt"), "x\n")
      git.(["add", "-A"])
      git.(["commit", "-m", "addonly"])

      # main: changes f.txt
      git.(["checkout", "main"])
      File.write!(Path.join(tmp_dir, "f.txt"), "main\n")
      git.(["add", "-A"])
      git.(["commit", "-m", "main"])

      on_exit(fn -> Git.TestHelpers.rm_rf(tmp_dir) end)
      %{config: Config.new(working_dir: tmp_dir)}
    end

    test "a clean merge returns clean: true with a tree and no conflicts", %{config: config} do
      assert {:ok, %MergeTreeResult{clean: true, tree: tree, conflicts: []}} =
               Git.merge_tree("main", "addonly", config: config)

      assert tree =~ ~r/^[0-9a-f]{40}$/
    end

    test "a conflicting merge returns clean: false with the conflicted paths",
         %{config: config} do
      assert {:ok, %MergeTreeResult{clean: false, tree: tree, conflicts: conflicts}} =
               Git.merge_tree("main", "feat", config: config)

      assert tree =~ ~r/^[0-9a-f]{40}$/
      assert "f.txt" in conflicts
    end

    test "an unknown ref is a real error, not a conflict", %{config: config} do
      # git also exits 1 for a bad ref, but stdout is not a tree OID, so it must
      # come back as an error rather than a bogus MergeTreeResult.
      assert {:error, {stdout, _exit_code}} =
               Git.merge_tree("main", "does-not-exist", config: config)

      assert stdout =~ "not something we can merge"
    end
  end
end
