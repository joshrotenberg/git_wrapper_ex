defmodule Git.Commands.MergeFileTest do
  use ExUnit.Case, async: true

  alias Git.Commands.MergeFile
  alias Git.Config

  defp setup_dir do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "git_merge_file_test_#{:erlang.unique_integer([:positive])}"
      )

    File.mkdir_p!(tmp_dir)
    on_exit(fn -> Git.TestHelpers.rm_rf(tmp_dir) end)
    {tmp_dir, Config.new(working_dir: tmp_dir)}
  end

  describe "args/1" do
    test "builds basic three-file args" do
      assert MergeFile.args(%MergeFile{current: "a", base: "o", other: "b"}) ==
               ["merge-file", "a", "o", "b"]
    end

    test "builds args with ours" do
      assert MergeFile.args(%MergeFile{current: "a", base: "o", other: "b", ours: true}) ==
               ["merge-file", "--ours", "a", "o", "b"]
    end

    test "builds args with theirs" do
      assert MergeFile.args(%MergeFile{current: "a", base: "o", other: "b", theirs: true}) ==
               ["merge-file", "--theirs", "a", "o", "b"]
    end

    test "builds args with union" do
      assert MergeFile.args(%MergeFile{current: "a", base: "o", other: "b", union: true}) ==
               ["merge-file", "--union", "a", "o", "b"]
    end

    test "builds args with quiet, diff3 and marker size" do
      assert MergeFile.args(%MergeFile{
               current: "a",
               base: "o",
               other: "b",
               quiet: true,
               diff3: true,
               marker_size: 10
             }) ==
               ["merge-file", "-q", "--diff3", "--marker-size", "10", "a", "o", "b"]
    end

    test "builds args with zdiff3" do
      assert MergeFile.args(%MergeFile{current: "a", base: "o", other: "b", zdiff3: true}) ==
               ["merge-file", "--zdiff3", "a", "o", "b"]
    end

    test "builds args with labels in order" do
      assert MergeFile.args(%MergeFile{
               current: "a",
               base: "o",
               other: "b",
               labels: ["mine", "orig", "theirs"]
             }) ==
               ["merge-file", "-L", "mine", "-L", "orig", "-L", "theirs", "a", "o", "b"]
    end
  end

  describe "parse_output/2" do
    test "clean merge returns zero conflicts" do
      assert MergeFile.parse_output("", 0) == {:ok, 0}
    end

    test "conflict count is returned as the signal" do
      assert MergeFile.parse_output("", 3) == {:ok, 3}
    end

    test "exit codes at or above 128 are errors" do
      assert MergeFile.parse_output("error: bad", 129) == {:error, {"error: bad", 129}}
      assert MergeFile.parse_output("fatal: nope", 255) == {:error, {"fatal: nope", 255}}
    end
  end

  describe "git merge-file integration" do
    test "clean merge of well-separated changes writes result and returns 0" do
      {tmp_dir, config} = setup_dir()

      File.write!(Path.join(tmp_dir, "base"), "a\nb\nc\nd\ne\nf\ng\n")
      File.write!(Path.join(tmp_dir, "current"), "OURS\nb\nc\nd\ne\nf\ng\n")
      File.write!(Path.join(tmp_dir, "other"), "a\nb\nc\nd\ne\nf\nOTHER\n")

      assert {:ok, 0} = Git.merge_file("current", "base", "other", config: config)

      assert File.read!(Path.join(tmp_dir, "current")) == "OURS\nb\nc\nd\ne\nf\nOTHER\n"
    end

    test "conflicting merge returns conflict count and writes markers" do
      {tmp_dir, config} = setup_dir()

      File.write!(Path.join(tmp_dir, "base"), "line1\nline2\nline3\n")
      File.write!(Path.join(tmp_dir, "current"), "line1\nOURS\nline3\n")
      File.write!(Path.join(tmp_dir, "other"), "line1\nTHEIRS\nline3\n")

      assert {:ok, count} = Git.merge_file("current", "base", "other", config: config)
      assert count > 0

      merged = File.read!(Path.join(tmp_dir, "current"))
      assert String.contains?(merged, "<<<<<<<")
      assert String.contains?(merged, "=======")
      assert String.contains?(merged, ">>>>>>>")
      assert String.contains?(merged, "OURS")
      assert String.contains?(merged, "THEIRS")
    end

    test "ours resolves conflicts in favor of current with no markers" do
      {tmp_dir, config} = setup_dir()

      File.write!(Path.join(tmp_dir, "base"), "line1\nline2\nline3\n")
      File.write!(Path.join(tmp_dir, "current"), "line1\nOURS\nline3\n")
      File.write!(Path.join(tmp_dir, "other"), "line1\nTHEIRS\nline3\n")

      assert {:ok, 0} = Git.merge_file("current", "base", "other", ours: true, config: config)

      assert File.read!(Path.join(tmp_dir, "current")) == "line1\nOURS\nline3\n"
    end

    test "returns an error for a missing input file" do
      {_tmp_dir, config} = setup_dir()

      assert {:error, {_stdout, exit_code}} =
               Git.merge_file("nope", "missing", "gone", config: config)

      assert exit_code >= 128
    end
  end
end
