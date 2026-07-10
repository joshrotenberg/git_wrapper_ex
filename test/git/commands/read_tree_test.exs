defmodule Git.Commands.ReadTreeTest do
  use ExUnit.Case, async: true

  alias Git.Commands.ReadTree
  alias Git.Config

  describe "args/1" do
    test "defaults to a bare read-tree with the given trees" do
      assert ReadTree.args(%ReadTree{trees: ["HEAD"]}) == ["read-tree", "HEAD"]
    end

    test "adds -m/-u for a multi-tree merge" do
      assert ReadTree.args(%ReadTree{trees: ["a", "b"], merge: true, update: true}) ==
               ["read-tree", "-m", "-u", "a", "b"]
    end

    test "adds --reset and --prefix" do
      assert ReadTree.args(%ReadTree{trees: ["t"], reset: true, prefix: "sub/"}) ==
               ["read-tree", "--reset", "--prefix=sub/", "t"]
    end
  end

  describe "read-tree integration" do
    setup do
      tmp_dir =
        Path.join(
          System.tmp_dir!(),
          "git_wrapper_read_tree_test_#{:erlang.unique_integer([:positive])}"
        )

      File.mkdir_p!(tmp_dir)
      git = fn args -> System.cmd("git", args, cd: tmp_dir) end
      git.(["init", "--initial-branch=main"])
      git.(["config", "user.name", "T"])
      git.(["config", "user.email", "t@t.com"])
      File.write!(Path.join(tmp_dir, "a.txt"), "a\n")
      git.(["add", "a.txt"])
      git.(["commit", "-m", "add a"])
      on_exit(fn -> Git.TestHelpers.rm_rf(tmp_dir) end)

      %{tmp_dir: tmp_dir, config: Config.new(working_dir: tmp_dir)}
    end

    test "loads a tree into the index (round-trips with write_tree)", %{
      tmp_dir: tmp_dir,
      config: config
    } do
      {head_tree, 0} = System.cmd("git", ["rev-parse", "HEAD^{tree}"], cd: tmp_dir)
      head_tree = String.trim(head_tree)

      # stage a different version, then reset the index back to HEAD's tree
      File.write!(Path.join(tmp_dir, "a.txt"), "changed\n")
      System.cmd("git", ["add", "a.txt"], cd: tmp_dir)

      assert {:ok, :done} = Git.read_tree(trees: ["HEAD"], reset: true, config: config)
      assert {:ok, ^head_tree} = Git.write_tree(config: config)
    end
  end
end
