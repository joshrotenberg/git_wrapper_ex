defmodule GitWrapper.AddTest do
  use ExUnit.Case, async: true

  alias GitWrapper.Commands.Add
  alias GitWrapper.Config

  setup do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "git_wrapper_add_test_#{:erlang.unique_integer([:positive])}"
      )

    File.mkdir_p!(tmp_dir)

    System.cmd("git", ["init", "--initial-branch=main"], cd: tmp_dir)

    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    config = Config.new(working_dir: tmp_dir)

    %{tmp_dir: tmp_dir, config: config}
  end

  describe "GitWrapper.Commands.Add args/1" do
    test "builds args for --all" do
      assert Add.args(%Add{all: true}) == ["add", "--all"]
    end

    test "builds args for specific files" do
      assert Add.args(%Add{files: ["foo.txt", "bar.txt"]}) == ["add", "foo.txt", "bar.txt"]
    end

    test "builds args for a single file" do
      assert Add.args(%Add{files: ["foo.txt"]}) == ["add", "foo.txt"]
    end

    test "builds args for empty files list" do
      assert Add.args(%Add{}) == ["add"]
    end
  end

  describe "add specific files" do
    test "stages a single file", %{tmp_dir: tmp_dir, config: config} do
      File.write!(Path.join(tmp_dir, "hello.txt"), "hello\n")

      assert {:ok, :done} = GitWrapperEx.add(files: ["hello.txt"], config: config)
    end

    test "stages multiple files", %{tmp_dir: tmp_dir, config: config} do
      File.write!(Path.join(tmp_dir, "a.txt"), "a\n")
      File.write!(Path.join(tmp_dir, "b.txt"), "b\n")

      assert {:ok, :done} = GitWrapperEx.add(files: ["a.txt", "b.txt"], config: config)
    end
  end

  describe "add all" do
    test "stages all changes", %{tmp_dir: tmp_dir, config: config} do
      File.write!(Path.join(tmp_dir, "all.txt"), "all\n")

      assert {:ok, :done} = GitWrapperEx.add(all: true, config: config)
    end
  end

  describe "add failure" do
    test "returns error for a non-existent file", %{config: config} do
      assert {:error, {output, exit_code}} =
               GitWrapperEx.add(files: ["nonexistent.txt"], config: config)

      assert exit_code != 0
      assert is_binary(output)
    end
  end
end
