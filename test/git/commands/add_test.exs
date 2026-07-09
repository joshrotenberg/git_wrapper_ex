defmodule Git.AddTest do
  use ExUnit.Case, async: true

  alias Git.Commands.Add
  alias Git.Config

  setup do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "git_wrapper_add_test_#{:erlang.unique_integer([:positive])}"
      )

    File.mkdir_p!(tmp_dir)

    System.cmd("git", ["init", "--initial-branch=main"], cd: tmp_dir)

    on_exit(fn -> Git.TestHelpers.rm_rf(tmp_dir) end)

    config = Config.new(working_dir: tmp_dir)

    %{tmp_dir: tmp_dir, config: config}
  end

  describe "Git.Commands.Add args/1" do
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

    test "composes --all with a pathspec instead of dropping the files" do
      assert Add.args(%Add{all: true, files: ["lib"]}) == ["add", "--all", "lib"]
    end

    test "builds args for --update with a pathspec" do
      assert Add.args(%Add{update: true, files: ["lib"]}) == ["add", "--update", "lib"]
    end

    test "builds args for --force with a pathspec" do
      assert Add.args(%Add{force: true, files: ["ignored.txt"]}) ==
               ["add", "--force", "ignored.txt"]
    end

    test "builds args for --intent-to-add" do
      assert Add.args(%Add{intent_to_add: true, files: ["new.ex"]}) ==
               ["add", "--intent-to-add", "new.ex"]
    end

    test "builds args for --dry-run combined with --all" do
      assert Add.args(%Add{all: true, dry_run: true}) == ["add", "--all", "--dry-run"]
    end

    test "builds args for --renormalize" do
      assert Add.args(%Add{renormalize: true}) == ["add", "--renormalize"]
    end

    test "builds args for --chmod" do
      assert Add.args(%Add{chmod: "+x", files: ["run.sh"]}) == ["add", "--chmod=+x", "run.sh"]
    end
  end

  describe "add specific files" do
    test "stages a single file", %{tmp_dir: tmp_dir, config: config} do
      File.write!(Path.join(tmp_dir, "hello.txt"), "hello\n")

      assert {:ok, :done} = Git.add(files: ["hello.txt"], config: config)
    end

    test "stages multiple files", %{tmp_dir: tmp_dir, config: config} do
      File.write!(Path.join(tmp_dir, "a.txt"), "a\n")
      File.write!(Path.join(tmp_dir, "b.txt"), "b\n")

      assert {:ok, :done} = Git.add(files: ["a.txt", "b.txt"], config: config)
    end
  end

  describe "add all" do
    test "stages all changes", %{tmp_dir: tmp_dir, config: config} do
      File.write!(Path.join(tmp_dir, "all.txt"), "all\n")

      assert {:ok, :done} = Git.add(all: true, config: config)
    end
  end

  describe "add flags" do
    test "intent-to-add records the path in the index without staging content",
         %{tmp_dir: tmp_dir, config: config} do
      File.write!(Path.join(tmp_dir, "new.ex"), "defmodule New do\nend\n")

      assert {:ok, :done} = Git.add(intent_to_add: true, files: ["new.ex"], config: config)

      {tracked, 0} = System.cmd("git", ["ls-files"], cd: tmp_dir)
      assert String.contains?(tracked, "new.ex")
    end

    test "update stages tracked modifications but not untracked files",
         %{tmp_dir: tmp_dir, config: config} do
      File.write!(Path.join(tmp_dir, "tracked.txt"), "v1\n")
      System.cmd("git", ["add", "tracked.txt"], cd: tmp_dir)

      System.cmd(
        "git",
        ["-c", "user.name=T", "-c", "user.email=t@t.com", "commit", "-m", "init"],
        cd: tmp_dir
      )

      File.write!(Path.join(tmp_dir, "tracked.txt"), "v2\n")
      File.write!(Path.join(tmp_dir, "untracked.txt"), "new\n")

      assert {:ok, :done} = Git.add(update: true, config: config)

      {status, 0} = System.cmd("git", ["status", "--porcelain"], cd: tmp_dir)
      assert String.contains?(status, "M  tracked.txt")
      assert String.contains?(status, "?? untracked.txt")
    end
  end

  describe "add failure" do
    test "returns error for a non-existent file", %{config: config} do
      assert {:error, {output, exit_code}} =
               Git.add(files: ["nonexistent.txt"], config: config)

      assert exit_code != 0
      assert is_binary(output)
    end
  end
end
