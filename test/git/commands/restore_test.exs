defmodule Git.RestoreTest do
  use ExUnit.Case, async: true

  alias Git.Commands.Restore
  alias Git.Config

  setup do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "git_wrapper_restore_test_#{:erlang.unique_integer([:positive])}"
      )

    File.mkdir_p!(tmp_dir)

    System.cmd("git", ["init", "--initial-branch=main"], cd: tmp_dir)
    System.cmd("git", ["config", "user.name", "Test User"], cd: tmp_dir)
    System.cmd("git", ["config", "user.email", "test@test.com"], cd: tmp_dir)

    # Create and commit a file
    File.write!(Path.join(tmp_dir, "file.txt"), "original\n")
    System.cmd("git", ["add", "file.txt"], cd: tmp_dir)
    System.cmd("git", ["commit", "-m", "initial"], cd: tmp_dir)

    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    config = Config.new(working_dir: tmp_dir)

    %{tmp_dir: tmp_dir, config: config}
  end

  describe "restore working tree files" do
    test "restores a modified file to its committed state", %{tmp_dir: tmp_dir, config: config} do
      file_path = Path.join(tmp_dir, "file.txt")
      File.write!(file_path, "modified\n")

      assert {:ok, :done} = Git.restore(files: ["file.txt"], config: config)
      assert File.read!(file_path) == "original\n"
    end

    test "restores multiple files", %{tmp_dir: tmp_dir, config: config} do
      File.write!(Path.join(tmp_dir, "second.txt"), "second\n")
      System.cmd("git", ["add", "second.txt"], cd: tmp_dir)
      System.cmd("git", ["commit", "-m", "add second"], cd: tmp_dir)

      File.write!(Path.join(tmp_dir, "file.txt"), "changed\n")
      File.write!(Path.join(tmp_dir, "second.txt"), "changed\n")

      assert {:ok, :done} =
               Git.restore(files: ["file.txt", "second.txt"], config: config)

      assert File.read!(Path.join(tmp_dir, "file.txt")) == "original\n"
      assert File.read!(Path.join(tmp_dir, "second.txt")) == "second\n"
    end
  end

  describe "restore --staged (unstage)" do
    test "unstages a file", %{tmp_dir: tmp_dir, config: config} do
      file_path = Path.join(tmp_dir, "file.txt")
      File.write!(file_path, "staged change\n")
      System.cmd("git", ["add", "file.txt"], cd: tmp_dir)

      assert {:ok, :done} =
               Git.restore(files: ["file.txt"], staged: true, config: config)

      # File should still be modified in the working tree
      assert File.read!(file_path) == "staged change\n"

      # But no longer staged
      {status_output, 0} = System.cmd("git", ["status", "--porcelain"], cd: tmp_dir)
      assert String.contains?(status_output, " M file.txt")
    end
  end

  describe "restore --source" do
    test "restores from a specific commit", %{tmp_dir: tmp_dir, config: config} do
      file_path = Path.join(tmp_dir, "file.txt")

      # Make a second commit
      File.write!(file_path, "second version\n")
      System.cmd("git", ["add", "file.txt"], cd: tmp_dir)
      System.cmd("git", ["commit", "-m", "second"], cd: tmp_dir)

      # Restore from the first commit
      assert {:ok, :done} =
               Git.restore(files: ["file.txt"], source: "HEAD~1", config: config)

      assert File.read!(file_path) == "original\n"
    end
  end

  describe "restore --staged --worktree" do
    test "restores both staged and working tree", %{tmp_dir: tmp_dir, config: config} do
      file_path = Path.join(tmp_dir, "file.txt")
      File.write!(file_path, "changed\n")
      System.cmd("git", ["add", "file.txt"], cd: tmp_dir)

      assert {:ok, :done} =
               Git.restore(
                 files: ["file.txt"],
                 staged: true,
                 worktree: true,
                 config: config
               )

      assert File.read!(file_path) == "original\n"

      {status_output, 0} = System.cmd("git", ["status", "--porcelain"], cd: tmp_dir)
      assert status_output == ""
    end
  end

  describe "restore failure" do
    test "returns error for nonexistent file", %{config: config} do
      assert {:error, {output, exit_code}} =
               Git.restore(files: ["nonexistent.txt"], config: config)

      assert exit_code != 0
      assert is_binary(output)
    end
  end

  describe "Commands.Restore.args/1" do
    test "builds args for basic restore" do
      assert Restore.args(%Restore{files: ["README.md"]}) ==
               ["restore", "README.md"]
    end

    test "builds args for staged restore" do
      assert Restore.args(%Restore{
               files: ["lib/foo.ex"],
               staged: true
             }) == ["restore", "--staged", "lib/foo.ex"]
    end

    test "builds args with source" do
      assert Restore.args(%Restore{
               files: ["lib/foo.ex"],
               source: "HEAD~1"
             }) == ["restore", "--source", "HEAD~1", "lib/foo.ex"]
    end

    test "builds args for staged and worktree" do
      assert Restore.args(%Restore{
               files: ["lib/foo.ex"],
               staged: true,
               worktree: true
             }) == ["restore", "--staged", "--worktree", "lib/foo.ex"]
    end

    test "builds args with --ours" do
      assert Restore.args(%Restore{
               files: ["conflict.txt"],
               ours: true
             }) == ["restore", "--ours", "conflict.txt"]
    end

    test "builds args with --theirs" do
      assert Restore.args(%Restore{
               files: ["conflict.txt"],
               theirs: true
             }) == ["restore", "--theirs", "conflict.txt"]
    end
  end
end
