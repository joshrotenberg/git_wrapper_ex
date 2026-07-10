defmodule Git.Commands.DiffFilesTest do
  use ExUnit.Case, async: true

  alias Git.Commands.DiffFiles
  alias Git.Config
  alias Git.DiffRawEntry

  setup do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "git_wrapper_diff_files_test_#{:erlang.unique_integer([:positive])}"
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
    test "always emits raw -z" do
      assert DiffFiles.args(%DiffFiles{}) == ["diff-files", "--raw", "-z"]
    end
  end

  describe "integration" do
    test "reports unstaged working-tree changes", %{tmp_dir: tmp_dir, config: config} do
      File.write!(Path.join(tmp_dir, "a.txt"), "line1\nline2\nline3\n")
      File.rm!(Path.join(tmp_dir, "c.txt"))

      assert {:ok, entries} = Git.diff_files(config: config)

      by_path = Map.new(entries, &{&1.path, &1})
      assert %DiffRawEntry{status: "M"} = by_path["a.txt"]
      assert %DiffRawEntry{status: "D"} = by_path["c.txt"]
    end

    test "clean working tree yields an empty list", %{config: config} do
      assert {:ok, []} = Git.diff_files(config: config)
    end

    test "staged-but-unmodified changes do not appear (index vs working tree)", %{
      tmp_dir: tmp_dir,
      config: config
    } do
      File.write!(Path.join(tmp_dir, "a.txt"), "line1\nline2\nline3\n")
      System.cmd("git", ["add", "a.txt"], cd: tmp_dir)

      assert {:ok, []} = Git.diff_files(config: config)
    end
  end
end
