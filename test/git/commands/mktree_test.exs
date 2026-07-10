defmodule Git.Commands.MkTreeTest do
  use ExUnit.Case, async: true

  alias Git.Commands.MkTree
  alias Git.Config

  describe "args/1 and input/1" do
    test "builds the argv" do
      assert MkTree.args(%MkTree{}) == ["mktree"]
      assert MkTree.args(%MkTree{missing: true}) == ["mktree", "--missing"]
    end

    test "formats entries for stdin" do
      entry = %{mode: "100644", type: "blob", object: "abc123", path: "a.txt"}
      assert MkTree.input(%MkTree{entries: [entry]}) == "100644 blob abc123\ta.txt\n"
    end

    test "empty entries produce empty input" do
      assert MkTree.input(%MkTree{entries: []}) == ""
    end
  end

  describe "mktree integration (stdin via the forcola runner)" do
    setup do
      tmp_dir =
        Path.join(
          System.tmp_dir!(),
          "git_wrapper_mktree_test_#{:erlang.unique_integer([:positive])}"
        )

      File.mkdir_p!(tmp_dir)
      System.cmd("git", ["init", "--initial-branch=main"], cd: tmp_dir)
      on_exit(fn -> Git.TestHelpers.rm_rf(tmp_dir) end)

      %{tmp_dir: tmp_dir, config: Config.new(working_dir: tmp_dir)}
    end

    test "builds a tree from a blob fed on stdin", %{tmp_dir: tmp_dir, config: config} do
      File.write!(Path.join(tmp_dir, "hello.txt"), "hi\n")
      {blob, 0} = System.cmd("git", ["hash-object", "-w", "hello.txt"], cd: tmp_dir)
      blob = String.trim(blob)

      entry = %{mode: "100644", type: "blob", object: blob, path: "hello.txt"}
      assert {:ok, tree} = Git.mktree(entries: [entry], config: config)
      assert tree =~ ~r/^[0-9a-f]{40}$/

      {listing, 0} = System.cmd("git", ["ls-tree", tree], cd: tmp_dir)
      assert listing =~ "hello.txt"
      assert listing =~ blob
    end

    test "empty entries produce the empty tree", %{config: config} do
      assert {:ok, "4b825dc642cb6eb9a060e54bf8d69288fbee4904"} = Git.mktree(config: config)
    end
  end
end
