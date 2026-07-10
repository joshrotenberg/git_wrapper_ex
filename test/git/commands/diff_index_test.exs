defmodule Git.Commands.DiffIndexTest do
  use ExUnit.Case, async: true

  alias Git.Commands.DiffIndex
  alias Git.Config
  alias Git.DiffRawEntry

  setup do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "git_wrapper_diff_index_test_#{:erlang.unique_integer([:positive])}"
      )

    File.mkdir_p!(tmp_dir)

    System.cmd("git", ["init", "--initial-branch=main"], cd: tmp_dir)
    System.cmd("git", ["config", "user.name", "Test User"], cd: tmp_dir)
    System.cmd("git", ["config", "user.email", "test@test.com"], cd: tmp_dir)

    File.write!(Path.join(tmp_dir, "a.txt"), "line1\nline2\n")
    File.write!(Path.join(tmp_dir, "c.txt"), "gone\n")
    System.cmd("git", ["add", "-A"], cd: tmp_dir)
    System.cmd("git", ["commit", "-m", "initial"], cd: tmp_dir)

    on_exit(fn -> Git.TestHelpers.rm_rf(tmp_dir) end)

    %{tmp_dir: tmp_dir, config: Config.new(working_dir: tmp_dir)}
  end

  describe "args/1" do
    test "default raw mode targets HEAD" do
      assert DiffIndex.args(%DiffIndex{}) == ["diff-index", "--raw", "-z", "HEAD"]
    end

    test "cached adds --cached" do
      assert DiffIndex.args(%DiffIndex{cached: true}) ==
               ["diff-index", "--raw", "-z", "--cached", "HEAD"]
    end

    test "quiet mode omits raw formatting" do
      assert DiffIndex.args(%DiffIndex{quiet: true}) == ["diff-index", "--quiet", "HEAD"]
    end

    test "quiet with cached" do
      assert DiffIndex.args(%DiffIndex{quiet: true, cached: true}) ==
               ["diff-index", "--quiet", "--cached", "HEAD"]
    end

    test "custom tree-ish" do
      assert DiffIndex.args(%DiffIndex{tree_ish: "main"}) ==
               ["diff-index", "--raw", "-z", "main"]
    end
  end

  describe "cached raw mode" do
    test "reports staged add, modify, and delete", %{tmp_dir: tmp_dir, config: config} do
      File.write!(Path.join(tmp_dir, "a.txt"), "line1\nline2\nline3\n")
      File.rm!(Path.join(tmp_dir, "c.txt"))
      File.write!(Path.join(tmp_dir, "d.txt"), "new\n")
      System.cmd("git", ["add", "-A"], cd: tmp_dir)

      assert {:ok, entries} = Git.diff_index(cached: true, config: config)

      by_path = Map.new(entries, &{&1.path, &1})
      assert %DiffRawEntry{status: "M"} = by_path["a.txt"]
      assert %DiffRawEntry{status: "D"} = by_path["c.txt"]
      assert %DiffRawEntry{status: "A"} = by_path["d.txt"]
    end

    test "no staged changes yields an empty list", %{config: config} do
      assert {:ok, []} = Git.diff_index(cached: true, config: config)
    end
  end

  describe "quiet dirty-check" do
    test "returns false when the working tree matches HEAD", %{config: config} do
      assert {:ok, false} = Git.diff_index(quiet: true, config: config)
    end

    test "returns true when the working tree differs from HEAD", %{
      tmp_dir: tmp_dir,
      config: config
    } do
      File.write!(Path.join(tmp_dir, "a.txt"), "changed\n")

      assert {:ok, true} = Git.diff_index(quiet: true, config: config)
    end

    test "cached quiet returns true when there are staged changes", %{
      tmp_dir: tmp_dir,
      config: config
    } do
      File.write!(Path.join(tmp_dir, "a.txt"), "staged\n")
      System.cmd("git", ["add", "a.txt"], cd: tmp_dir)

      assert {:ok, true} = Git.diff_index(quiet: true, cached: true, config: config)
    end
  end

  describe "errors" do
    test "bad tree-ish returns an error", %{config: config} do
      assert {:error, {stdout, exit_code}} = Git.diff_index(tree_ish: "nope", config: config)
      assert exit_code != 0
      assert stdout =~ "fatal"
    end
  end
end
