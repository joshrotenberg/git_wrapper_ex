defmodule Git.Commands.WriteTreeTest do
  use ExUnit.Case, async: true

  alias Git.Commands.WriteTree
  alias Git.Config

  @env [
    {"GIT_AUTHOR_NAME", "T"},
    {"GIT_AUTHOR_EMAIL", "t@t.com"},
    {"GIT_COMMITTER_NAME", "T"},
    {"GIT_COMMITTER_EMAIL", "t@t.com"}
  ]

  describe "args/1" do
    test "defaults to a bare write-tree" do
      assert WriteTree.args(%WriteTree{}) == ["write-tree"]
    end

    test "adds --prefix" do
      assert WriteTree.args(%WriteTree{prefix: "lib"}) == ["write-tree", "--prefix=lib"]
    end

    test "adds --missing-ok" do
      assert WriteTree.args(%WriteTree{missing_ok: true}) == ["write-tree", "--missing-ok"]
    end
  end

  describe "write-tree integration" do
    setup do
      tmp_dir =
        Path.join(
          System.tmp_dir!(),
          "git_wrapper_write_tree_test_#{:erlang.unique_integer([:positive])}"
        )

      File.mkdir_p!(tmp_dir)
      System.cmd("git", ["init", "--initial-branch=main"], cd: tmp_dir)
      on_exit(fn -> Git.TestHelpers.rm_rf(tmp_dir) end)

      %{tmp_dir: tmp_dir, config: Config.new(working_dir: tmp_dir)}
    end

    test "records the staged index as a tree object", %{tmp_dir: tmp_dir, config: config} do
      File.write!(Path.join(tmp_dir, "hello.txt"), "hello\n")
      System.cmd("git", ["add", "hello.txt"], cd: tmp_dir)

      assert {:ok, tree} = Git.write_tree(config: config)
      assert tree =~ ~r/^[0-9a-f]{40}$/

      {listing, 0} = System.cmd("git", ["ls-tree", tree], cd: tmp_dir)
      assert listing =~ "hello.txt"
    end

    test "round-trips with commit_tree to build a commit with no HEAD",
         %{tmp_dir: tmp_dir} do
      config = Config.new(working_dir: tmp_dir, env: @env)
      File.write!(Path.join(tmp_dir, "a.txt"), "a\n")
      System.cmd("git", ["add", "a.txt"], cd: tmp_dir)

      assert {:ok, tree} = Git.write_tree(config: config)

      assert {:ok, commit} =
               Git.commit_tree(tree: tree, message: "from write-tree", config: config)

      assert commit =~ ~r/^[0-9a-f]{40}$/
    end

    test "prefix writes the tree of a subdirectory", %{tmp_dir: tmp_dir, config: config} do
      File.mkdir_p!(Path.join(tmp_dir, "sub"))
      File.write!(Path.join([tmp_dir, "sub", "nested.txt"]), "n\n")
      System.cmd("git", ["add", "sub/nested.txt"], cd: tmp_dir)

      assert {:ok, tree} = Git.write_tree(prefix: "sub", config: config)

      {listing, 0} = System.cmd("git", ["ls-tree", tree], cd: tmp_dir)
      assert listing =~ "nested.txt"
    end
  end
end
