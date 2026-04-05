defmodule Git.RmTest do
  use ExUnit.Case, async: true

  alias Git.Commands.Rm
  alias Git.Config

  setup do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "git_wrapper_rm_test_#{:erlang.unique_integer([:positive])}"
      )

    File.mkdir_p!(tmp_dir)

    System.cmd("git", ["init", "--initial-branch=main"], cd: tmp_dir)

    System.cmd(
      "git",
      [
        "-c",
        "user.name=Test User",
        "-c",
        "user.email=test@test.com",
        "commit",
        "--allow-empty",
        "-m",
        "initial"
      ],
      cd: tmp_dir
    )

    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    config =
      Config.new(
        working_dir: tmp_dir,
        env: [
          {"GIT_AUTHOR_NAME", "Test User"},
          {"GIT_AUTHOR_EMAIL", "test@test.com"},
          {"GIT_COMMITTER_NAME", "Test User"},
          {"GIT_COMMITTER_EMAIL", "test@test.com"}
        ]
      )

    %{tmp_dir: tmp_dir, config: config}
  end

  describe "Git.Commands.Rm args/1" do
    test "builds args for removing files" do
      assert Rm.args(%Rm{files: ["a.txt"]}) == ["rm", "a.txt"]
    end

    test "builds args with cached flag" do
      assert Rm.args(%Rm{files: ["a.txt"], cached: true}) == ["rm", "--cached", "a.txt"]
    end

    test "builds args with force and recursive flags" do
      assert Rm.args(%Rm{files: ["dir/"], recursive: true, force: true}) ==
               ["rm", "-f", "-r", "dir/"]
    end

    test "builds args with dry_run and quiet flags" do
      assert Rm.args(%Rm{files: ["a.txt"], dry_run: true, quiet: true}) ==
               ["rm", "-n", "-q", "a.txt"]
    end

    test "builds args with pathspec_from_file" do
      assert Rm.args(%Rm{files: [], pathspec_from_file: "paths.txt"}) ==
               ["rm", "--pathspec-from-file", "paths.txt"]
    end

    test "builds args with multiple files" do
      assert Rm.args(%Rm{files: ["a.txt", "b.txt", "c.txt"]}) ==
               ["rm", "a.txt", "b.txt", "c.txt"]
    end
  end

  describe "rm --cached" do
    test "removes a file from the index but keeps it on disk", %{tmp_dir: tmp_dir, config: config} do
      File.write!(Path.join(tmp_dir, "tracked.txt"), "content\n")
      System.cmd("git", ["add", "tracked.txt"], cd: tmp_dir)

      System.cmd(
        "git",
        [
          "-c",
          "user.name=Test User",
          "-c",
          "user.email=test@test.com",
          "commit",
          "-m",
          "add tracked"
        ],
        cd: tmp_dir
      )

      assert {:ok, :done} =
               Git.Command.run(
                 Rm,
                 %Rm{files: ["tracked.txt"], cached: true},
                 config
               )

      # File should still exist on disk
      assert File.exists?(Path.join(tmp_dir, "tracked.txt"))

      # File should be removed from the index (shown as untracked)
      {status_output, 0} = System.cmd("git", ["status", "--porcelain"], cd: tmp_dir)
      assert String.contains?(status_output, "tracked.txt")
    end
  end

  describe "rm failure" do
    test "returns error for a non-existent file", %{config: config} do
      assert {:error, {output, exit_code}} =
               Git.Command.run(
                 Rm,
                 %Rm{files: ["nonexistent.txt"]},
                 config
               )

      assert exit_code != 0
      assert is_binary(output)
    end
  end
end
