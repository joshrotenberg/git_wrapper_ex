defmodule Git.CleanTest do
  use ExUnit.Case, async: true

  alias Git.Commands.Clean
  alias Git.Config

  @env [
    {"GIT_AUTHOR_NAME", "Test User"},
    {"GIT_AUTHOR_EMAIL", "test@test.com"},
    {"GIT_COMMITTER_NAME", "Test User"},
    {"GIT_COMMITTER_EMAIL", "test@test.com"}
  ]

  setup do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "git_wrapper_clean_test_#{:erlang.unique_integer([:positive])}"
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
        "initial commit"
      ],
      cd: tmp_dir
    )

    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    config = Config.new(working_dir: tmp_dir, env: @env)
    %{tmp_dir: tmp_dir, config: config}
  end

  describe "Git.Commands.Clean args/1" do
    test "builds args for dry run" do
      assert Clean.args(%Clean{dry_run: true}) == ["clean", "-n"]
    end

    test "builds args for force" do
      assert Clean.args(%Clean{force: true}) == ["clean", "-f"]
    end

    test "builds args for force with directories" do
      assert Clean.args(%Clean{force: true, directories: true}) == ["clean", "-f", "-d"]
    end

    test "builds args for force with ignored files" do
      assert Clean.args(%Clean{force: true, ignored: true}) == ["clean", "-f", "-x"]
    end

    test "builds args for force with only ignored files" do
      assert Clean.args(%Clean{force: true, only_ignored: true}) == ["clean", "-f", "-X"]
    end

    test "builds args with exclude pattern" do
      assert Clean.args(%Clean{force: true, exclude: "*.log"}) ==
               ["clean", "-f", "-e", "*.log"]
    end

    test "builds args with quiet flag" do
      assert Clean.args(%Clean{force: true, quiet: true}) == ["clean", "-f", "-q"]
    end

    test "builds args with paths" do
      assert Clean.args(%Clean{force: true, paths: ["src/", "tmp/"]}) ==
               ["clean", "-f", "--", "src/", "tmp/"]
    end
  end

  describe "git clean --dry-run" do
    test "reports files that would be removed", %{tmp_dir: tmp_dir, config: config} do
      File.write!(Path.join(tmp_dir, "untracked.txt"), "untracked\n")
      File.write!(Path.join(tmp_dir, "another.txt"), "another\n")

      {:ok, paths} =
        Git.Command.run(Clean, %Clean{dry_run: true}, config)

      assert "untracked.txt" in paths
      assert "another.txt" in paths

      # Files should still exist after dry run
      assert File.exists?(Path.join(tmp_dir, "untracked.txt"))
      assert File.exists?(Path.join(tmp_dir, "another.txt"))
    end

    test "returns empty list when no untracked files exist", %{config: config} do
      {:ok, paths} =
        Git.Command.run(Clean, %Clean{dry_run: true}, config)

      assert paths == []
    end
  end

  describe "git clean --force" do
    test "removes untracked files", %{tmp_dir: tmp_dir, config: config} do
      File.write!(Path.join(tmp_dir, "untracked.txt"), "untracked\n")

      {:ok, paths} =
        Git.Command.run(Clean, %Clean{force: true}, config)

      assert "untracked.txt" in paths
      refute File.exists?(Path.join(tmp_dir, "untracked.txt"))
    end

    test "does not remove tracked files", %{tmp_dir: tmp_dir, config: config} do
      File.write!(Path.join(tmp_dir, "tracked.txt"), "tracked\n")
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
          "add tracked file"
        ],
        cd: tmp_dir
      )

      {:ok, paths} =
        Git.Command.run(Clean, %Clean{force: true}, config)

      assert paths == []
      assert File.exists?(Path.join(tmp_dir, "tracked.txt"))
    end
  end

  describe "git clean --force --directories" do
    test "removes untracked directories", %{tmp_dir: tmp_dir, config: config} do
      subdir = Path.join(tmp_dir, "subdir")
      File.mkdir_p!(subdir)
      File.write!(Path.join(subdir, "file.txt"), "content\n")

      {:ok, paths} =
        Git.Command.run(Clean, %Clean{force: true, directories: true}, config)

      assert "subdir/" in paths
      refute File.exists?(subdir)
    end
  end
end
