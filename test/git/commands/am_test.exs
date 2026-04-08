defmodule Git.AmTest do
  use ExUnit.Case, async: true

  alias Git.Commands.Am
  alias Git.Config

  setup do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "git_wrapper_am_test_#{:erlang.unique_integer([:positive])}"
      )

    File.mkdir_p!(tmp_dir)
    System.cmd("git", ["init", "--initial-branch=main"], cd: tmp_dir)
    System.cmd("git", ["config", "user.name", "Test User"], cd: tmp_dir)
    System.cmd("git", ["config", "user.email", "test@test.com"], cd: tmp_dir)

    # Create initial file and commit
    File.write!(Path.join(tmp_dir, "hello.txt"), "hello\n")
    System.cmd("git", ["add", "hello.txt"], cd: tmp_dir)
    System.cmd("git", ["commit", "-m", "initial commit"], cd: tmp_dir)

    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    config = Config.new(working_dir: tmp_dir)
    %{tmp_dir: tmp_dir, config: config}
  end

  describe "args/1" do
    test "builds args for abort" do
      assert Am.args(%Am{abort: true}) == ["am", "--abort"]
    end

    test "builds args for continue" do
      assert Am.args(%Am{continue_: true}) == ["am", "--continue"]
    end

    test "builds args for skip" do
      assert Am.args(%Am{skip: true}) == ["am", "--skip"]
    end

    test "builds args with a single patch" do
      assert Am.args(%Am{patches: ["0001-fix.patch"]}) == ["am", "0001-fix.patch"]
    end

    test "builds args with multiple patches" do
      assert Am.args(%Am{patches: ["0001-fix.patch", "0002-feat.patch"]}) ==
               ["am", "0001-fix.patch", "0002-feat.patch"]
    end

    test "builds args with --3way" do
      assert Am.args(%Am{patches: ["0001-fix.patch"], three_way: true}) ==
               ["am", "--3way", "0001-fix.patch"]
    end

    test "builds args with --keep" do
      assert Am.args(%Am{patches: ["0001-fix.patch"], keep: true}) ==
               ["am", "--keep", "0001-fix.patch"]
    end

    test "builds args with --signoff" do
      assert Am.args(%Am{patches: ["0001-fix.patch"], signoff: true}) ==
               ["am", "--signoff", "0001-fix.patch"]
    end

    test "builds args with --quiet" do
      assert Am.args(%Am{patches: ["0001-fix.patch"], quiet: true}) ==
               ["am", "--quiet", "0001-fix.patch"]
    end

    test "builds args with directory" do
      assert Am.args(%Am{directory: "/tmp/patches"}) == ["am", "/tmp/patches"]
    end

    test "builds args with multiple flags" do
      assert Am.args(%Am{patches: ["0001-fix.patch"], three_way: true, signoff: true}) ==
               ["am", "--3way", "--signoff", "0001-fix.patch"]
    end
  end

  describe "am a patch" do
    test "applies a format-patch mailbox file", %{tmp_dir: tmp_dir, config: config} do
      # Create a commit on a branch, then format-patch it
      System.cmd("git", ["checkout", "-b", "feature"], cd: tmp_dir)
      File.write!(Path.join(tmp_dir, "hello.txt"), "hello world\n")
      System.cmd("git", ["add", "hello.txt"], cd: tmp_dir)
      System.cmd("git", ["commit", "-m", "update hello"], cd: tmp_dir)

      # Generate a mailbox patch
      {patch_output, 0} = System.cmd("git", ["format-patch", "-1", "--stdout"], cd: tmp_dir)
      patch_path = Path.join(tmp_dir, "0001-update-hello.patch")
      File.write!(patch_path, patch_output)

      # Go back to main and apply with am
      System.cmd("git", ["checkout", "main"], cd: tmp_dir)

      assert {:ok, :done} = Git.am(patches: [patch_path], config: config)

      assert File.read!(Path.join(tmp_dir, "hello.txt")) == "hello world\n"
    end

    test "applies a patch with --signoff", %{tmp_dir: tmp_dir, config: config} do
      System.cmd("git", ["checkout", "-b", "feature"], cd: tmp_dir)
      File.write!(Path.join(tmp_dir, "hello.txt"), "hello signoff\n")
      System.cmd("git", ["add", "hello.txt"], cd: tmp_dir)
      System.cmd("git", ["commit", "-m", "signoff change"], cd: tmp_dir)

      {patch_output, 0} = System.cmd("git", ["format-patch", "-1", "--stdout"], cd: tmp_dir)
      patch_path = Path.join(tmp_dir, "0001-signoff.patch")
      File.write!(patch_path, patch_output)

      System.cmd("git", ["checkout", "main"], cd: tmp_dir)

      assert {:ok, :done} = Git.am(patches: [patch_path], signoff: true, config: config)

      # Check that Signed-off-by was added
      {log, 0} = System.cmd("git", ["log", "-1", "--format=%B"], cd: tmp_dir)
      assert log =~ "Signed-off-by:"
    end
  end

  describe "am failure" do
    test "returns error for invalid patch", %{tmp_dir: tmp_dir, config: config} do
      bad_patch_path = Path.join(tmp_dir, "bad.patch")
      File.write!(bad_patch_path, "this is not a valid mbox patch\n")

      assert {:error, {output, exit_code}} =
               Git.am(patches: [bad_patch_path], config: config)

      assert exit_code != 0
      assert is_binary(output)
    end
  end
end
