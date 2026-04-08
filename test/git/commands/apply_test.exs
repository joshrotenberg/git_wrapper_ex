defmodule Git.ApplyTest do
  use ExUnit.Case, async: true

  alias Git.Commands.Apply
  alias Git.Config

  setup do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "git_wrapper_apply_test_#{:erlang.unique_integer([:positive])}"
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
    test "builds args with patch only" do
      assert Apply.args(%Apply{patch: "fix.patch"}) == ["apply", "fix.patch"]
    end

    test "builds args with --check" do
      assert Apply.args(%Apply{patch: "fix.patch", check: true}) ==
               ["apply", "--check", "fix.patch"]
    end

    test "builds args with --stat" do
      assert Apply.args(%Apply{patch: "fix.patch", stat: true}) ==
               ["apply", "--stat", "fix.patch"]
    end

    test "builds args with --summary" do
      assert Apply.args(%Apply{patch: "fix.patch", summary: true}) ==
               ["apply", "--summary", "fix.patch"]
    end

    test "builds args with --cached" do
      assert Apply.args(%Apply{patch: "fix.patch", cached: true}) ==
               ["apply", "--cached", "fix.patch"]
    end

    test "builds args with --index" do
      assert Apply.args(%Apply{patch: "fix.patch", index: true}) ==
               ["apply", "--index", "fix.patch"]
    end

    test "builds args with --reverse" do
      assert Apply.args(%Apply{patch: "fix.patch", reverse: true}) ==
               ["apply", "--reverse", "fix.patch"]
    end

    test "builds args with --3way" do
      assert Apply.args(%Apply{patch: "fix.patch", three_way: true}) ==
               ["apply", "--3way", "fix.patch"]
    end

    test "builds args with --verbose" do
      assert Apply.args(%Apply{patch: "fix.patch", verbose: true}) ==
               ["apply", "--verbose", "fix.patch"]
    end

    test "builds args with multiple flags" do
      assert Apply.args(%Apply{patch: "fix.patch", stat: true, summary: true}) ==
               ["apply", "--stat", "--summary", "fix.patch"]
    end
  end

  describe "apply a patch" do
    test "applies a patch file to the working tree", %{tmp_dir: tmp_dir, config: config} do
      # Generate a patch by making a change
      File.write!(Path.join(tmp_dir, "hello.txt"), "hello world\n")

      {patch_content, 0} = System.cmd("git", ["diff"], cd: tmp_dir)
      patch_path = Path.join(tmp_dir, "change.patch")
      File.write!(patch_path, patch_content)

      # Reset the change so we can apply the patch
      System.cmd("git", ["checkout", "--", "hello.txt"], cd: tmp_dir)

      assert {:ok, :done} = Git.apply_patch(patch: patch_path, config: config)

      assert File.read!(Path.join(tmp_dir, "hello.txt")) == "hello world\n"
    end

    test "checks if a patch applies cleanly", %{tmp_dir: tmp_dir, config: config} do
      File.write!(Path.join(tmp_dir, "hello.txt"), "hello world\n")

      {patch_content, 0} = System.cmd("git", ["diff"], cd: tmp_dir)
      patch_path = Path.join(tmp_dir, "change.patch")
      File.write!(patch_path, patch_content)

      System.cmd("git", ["checkout", "--", "hello.txt"], cd: tmp_dir)

      assert {:ok, _output} = Git.apply_patch(patch: patch_path, check: true, config: config)
    end

    test "returns stat output", %{tmp_dir: tmp_dir, config: config} do
      File.write!(Path.join(tmp_dir, "hello.txt"), "hello world\n")

      {patch_content, 0} = System.cmd("git", ["diff"], cd: tmp_dir)
      patch_path = Path.join(tmp_dir, "change.patch")
      File.write!(patch_path, patch_content)

      assert {:ok, output} = Git.apply_patch(patch: patch_path, stat: true, config: config)
      assert is_binary(output)
      assert output =~ "hello.txt"
    end

    test "applies a patch in reverse", %{tmp_dir: tmp_dir, config: config} do
      # Make a change and generate a forward patch
      File.write!(Path.join(tmp_dir, "hello.txt"), "hello world\n")

      {patch_content, 0} = System.cmd("git", ["diff"], cd: tmp_dir)
      patch_path = Path.join(tmp_dir, "change.patch")
      File.write!(patch_path, patch_content)

      # Stage the change so we have the modified file
      System.cmd("git", ["add", "hello.txt"], cd: tmp_dir)
      System.cmd("git", ["commit", "-m", "modify hello"], cd: tmp_dir)

      # Now apply the patch in reverse to undo the change
      assert {:ok, :done} = Git.apply_patch(patch: patch_path, reverse: true, config: config)

      assert File.read!(Path.join(tmp_dir, "hello.txt")) == "hello\n"
    end

    test "applies a patch to the index with --cached", %{tmp_dir: tmp_dir, config: config} do
      File.write!(Path.join(tmp_dir, "hello.txt"), "hello world\n")

      {patch_content, 0} = System.cmd("git", ["diff"], cd: tmp_dir)
      patch_path = Path.join(tmp_dir, "change.patch")
      File.write!(patch_path, patch_content)

      System.cmd("git", ["checkout", "--", "hello.txt"], cd: tmp_dir)

      assert {:ok, :done} = Git.apply_patch(patch: patch_path, cached: true, config: config)

      # The index should have the change but working tree should not
      {staged, 0} = System.cmd("git", ["diff", "--cached", "--name-only"], cd: tmp_dir)
      assert staged =~ "hello.txt"
    end
  end

  describe "apply failure" do
    test "returns error for a patch that does not apply", %{tmp_dir: tmp_dir, config: config} do
      # Create a patch that won't apply
      bad_patch = """
      --- a/nonexistent.txt
      +++ b/nonexistent.txt
      @@ -1 +1 @@
      -old content
      +new content
      """

      patch_path = Path.join(tmp_dir, "bad.patch")
      File.write!(patch_path, bad_patch)

      assert {:error, {output, exit_code}} =
               Git.apply_patch(patch: patch_path, config: config)

      assert exit_code != 0
      assert is_binary(output)
    end
  end
end
