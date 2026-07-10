defmodule Git.Commands.DiffTreeTest do
  use ExUnit.Case, async: true

  alias Git.Commands.DiffTree
  alias Git.Config
  alias Git.DiffRawEntry

  setup do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "git_wrapper_diff_tree_test_#{:erlang.unique_integer([:positive])}"
      )

    File.mkdir_p!(tmp_dir)

    System.cmd("git", ["init", "--initial-branch=main"], cd: tmp_dir)
    System.cmd("git", ["config", "user.name", "Test User"], cd: tmp_dir)
    System.cmd("git", ["config", "user.email", "test@test.com"], cd: tmp_dir)

    File.write!(Path.join(tmp_dir, "a.txt"), "line1\nline2\n")
    File.write!(Path.join(tmp_dir, "c.txt"), "gone\n")
    System.cmd("git", ["add", "-A"], cd: tmp_dir)
    System.cmd("git", ["commit", "-m", "initial"], cd: tmp_dir)

    File.write!(Path.join(tmp_dir, "a.txt"), "line1\nline2\nline3\n")
    File.rm!(Path.join(tmp_dir, "c.txt"))
    File.write!(Path.join(tmp_dir, "d.txt"), "new\n")
    System.cmd("git", ["add", "-A"], cd: tmp_dir)
    System.cmd("git", ["commit", "-m", "second"], cd: tmp_dir)

    on_exit(fn -> Git.TestHelpers.rm_rf(tmp_dir) end)

    %{tmp_dir: tmp_dir, config: Config.new(working_dir: tmp_dir)}
  end

  describe "args/1" do
    test "default targets HEAD with raw -z" do
      assert DiffTree.args(%DiffTree{}) == ["diff-tree", "--raw", "-z", "HEAD"]
    end

    test "recursive adds -r" do
      assert DiffTree.args(%DiffTree{recursive: true}) ==
               ["diff-tree", "--raw", "-z", "-r", "HEAD"]
    end

    test "two tree-ish args" do
      assert DiffTree.args(%DiffTree{tree_ish: "HEAD~1", tree_ish2: "HEAD", recursive: true}) ==
               ["diff-tree", "--raw", "-z", "-r", "HEAD~1", "HEAD"]
    end

    test "find_renames adds -M" do
      assert DiffTree.args(%DiffTree{find_renames: true, recursive: true}) ==
               ["diff-tree", "--raw", "-z", "-r", "-M", "HEAD"]
    end
  end

  describe "integration" do
    test "diffs two commits into raw entries", %{config: config} do
      assert {:ok, entries} =
               Git.diff_tree(
                 tree_ish: "HEAD~1",
                 tree_ish2: "HEAD",
                 recursive: true,
                 config: config
               )

      by_path = Map.new(entries, &{&1.path, &1})

      assert %DiffRawEntry{status: "M"} = by_path["a.txt"]
      assert %DiffRawEntry{status: "D"} = by_path["c.txt"]
      assert %DiffRawEntry{status: "A"} = by_path["d.txt"]
    end

    test "single tree-ish diffs a commit against its parent", %{config: config} do
      assert {:ok, entries} = Git.diff_tree(tree_ish: "HEAD", recursive: true, config: config)

      statuses = entries |> Enum.map(& &1.status) |> Enum.sort()
      assert "M" in statuses
      assert "A" in statuses
      assert "D" in statuses
    end

    test "detects renames with a scored status", %{tmp_dir: tmp_dir, config: config} do
      System.cmd("git", ["mv", "a.txt", "a_renamed.txt"], cd: tmp_dir)
      System.cmd("git", ["commit", "-m", "rename"], cd: tmp_dir)

      assert {:ok, entries} =
               Git.diff_tree(
                 tree_ish: "HEAD~1",
                 tree_ish2: "HEAD",
                 recursive: true,
                 find_renames: true,
                 config: config
               )

      rename = Enum.find(entries, &String.starts_with?(&1.status, "R"))
      assert %DiffRawEntry{path: "a_renamed.txt"} = rename
    end

    test "bad ref returns an error", %{config: config} do
      assert {:error, {stdout, exit_code}} =
               Git.diff_tree(tree_ish: "does-not-exist", config: config)

      assert exit_code != 0
      assert stdout =~ "fatal"
    end
  end
end
