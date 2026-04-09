defmodule Git.PatchTest do
  use ExUnit.Case, async: true

  @git_env [
    {"GIT_AUTHOR_NAME", "Test User"},
    {"GIT_AUTHOR_EMAIL", "test@example.com"},
    {"GIT_COMMITTER_NAME", "Test User"},
    {"GIT_COMMITTER_EMAIL", "test@example.com"}
  ]

  setup do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "git_patch_test_#{:erlang.unique_integer([:positive])}"
      )

    File.mkdir_p!(tmp_dir)
    System.cmd("git", ["init", "--initial-branch=main"], cd: tmp_dir)
    System.cmd("git", ["config", "user.email", "test@example.com"], cd: tmp_dir)
    System.cmd("git", ["config", "user.name", "Test User"], cd: tmp_dir)

    # Initial commit
    File.write!(Path.join(tmp_dir, "README.md"), "initial")
    System.cmd("git", ["add", "."], cd: tmp_dir)
    System.cmd("git", ["commit", "-m", "initial commit"], cd: tmp_dir, env: @git_env)

    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    config = Git.Config.new(working_dir: tmp_dir, env: @git_env)

    %{tmp_dir: tmp_dir, config: config}
  end

  defp write_and_commit(tmp_dir, filename, content, message) do
    File.write!(Path.join(tmp_dir, filename), content)
    System.cmd("git", ["add", filename], cd: tmp_dir)
    System.cmd("git", ["commit", "-m", message], cd: tmp_dir, env: @git_env)
  end

  describe "create/2" do
    test "creates patch files from commits", %{tmp_dir: tmp_dir, config: config} do
      write_and_commit(tmp_dir, "feature.ex", "defmodule Feature, do: end", "feat: add feature")

      patch_dir = Path.join(tmp_dir, "patches")
      File.mkdir_p!(patch_dir)

      assert {:ok, files} =
               Git.Patch.create("HEAD~1", output_directory: patch_dir, config: config)

      assert length(files) == 1
      [patch_file] = files
      assert File.exists?(patch_file)
    end

    test "creates multiple patches for multiple commits", %{tmp_dir: tmp_dir, config: config} do
      write_and_commit(tmp_dir, "a.ex", "a", "feat: add a")
      write_and_commit(tmp_dir, "b.ex", "b", "feat: add b")

      patch_dir = Path.join(tmp_dir, "patches")
      File.mkdir_p!(patch_dir)

      assert {:ok, files} =
               Git.Patch.create("HEAD~2", output_directory: patch_dir, config: config)

      assert length(files) == 2
    end
  end

  describe "apply/2" do
    test "applies a patch file", %{tmp_dir: tmp_dir, config: config} do
      write_and_commit(tmp_dir, "patched.ex", "original", "feat: add file")

      patch_dir = Path.join(tmp_dir, "patches")
      File.mkdir_p!(patch_dir)

      {:ok, [patch_file]} =
        Git.Patch.create("HEAD~1", output_directory: patch_dir, config: config)

      # Reset to before the commit to apply the patch
      System.cmd("git", ["reset", "--hard", "HEAD~1"], cd: tmp_dir)

      refute File.exists?(Path.join(tmp_dir, "patched.ex"))

      assert {:ok, :done} = Git.Patch.apply(patch_file, config: config)

      assert File.exists?(Path.join(tmp_dir, "patched.ex"))
    end
  end

  describe "apply_mailbox/2" do
    test "applies mailbox-formatted patches", %{tmp_dir: tmp_dir, config: config} do
      write_and_commit(tmp_dir, "am_file.ex", "content", "feat: add am file")

      patch_dir = Path.join(tmp_dir, "patches")
      File.mkdir_p!(patch_dir)

      {:ok, [patch_file]} =
        Git.Patch.create("HEAD~1", output_directory: patch_dir, config: config)

      # Reset to before the commit
      System.cmd("git", ["reset", "--hard", "HEAD~1"], cd: tmp_dir)

      assert {:ok, :done} = Git.Patch.apply_mailbox([patch_file], config: config)

      assert File.exists?(Path.join(tmp_dir, "am_file.ex"))
    end
  end

  describe "check/2" do
    test "returns ok when patch applies cleanly", %{tmp_dir: tmp_dir, config: config} do
      write_and_commit(tmp_dir, "check_file.ex", "check content", "feat: add check file")

      patch_dir = Path.join(tmp_dir, "patches")
      File.mkdir_p!(patch_dir)

      {:ok, [patch_file]} =
        Git.Patch.create("HEAD~1", output_directory: patch_dir, config: config)

      # Reset to before the commit
      System.cmd("git", ["reset", "--hard", "HEAD~1"], cd: tmp_dir)

      assert {:ok, _output} = Git.Patch.check(patch_file, config: config)
    end

    test "returns error when patch does not apply cleanly", %{tmp_dir: tmp_dir, config: config} do
      write_and_commit(tmp_dir, "conflict.ex", "original", "feat: add file")

      patch_dir = Path.join(tmp_dir, "patches")
      File.mkdir_p!(patch_dir)

      {:ok, [patch_file]} =
        Git.Patch.create("HEAD~1", output_directory: patch_dir, config: config)

      # Modify the file so the patch won't apply cleanly
      File.write!(Path.join(tmp_dir, "conflict.ex"), "completely different content")
      System.cmd("git", ["add", "conflict.ex"], cd: tmp_dir)
      System.cmd("git", ["commit", "-m", "change file"], cd: tmp_dir, env: @git_env)

      assert {:error, _reason} = Git.Patch.check(patch_file, config: config)
    end
  end
end
