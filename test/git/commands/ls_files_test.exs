defmodule Git.LsFilesTest do
  use ExUnit.Case, async: true

  alias Git.Commands.LsFiles
  alias Git.Config

  setup do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "git_wrapper_ls_files_test_#{:erlang.unique_integer([:positive])}"
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

  describe "args/1" do
    test "default produces minimal args" do
      assert LsFiles.args(%LsFiles{}) == ["ls-files"]
    end

    test "others with exclude_standard" do
      cmd = %LsFiles{others: true, exclude_standard: true}
      assert LsFiles.args(cmd) == ["ls-files", "--others", "--exclude-standard"]
    end

    test "modified with paths" do
      cmd = %LsFiles{modified: true, paths: ["src/"]}
      assert LsFiles.args(cmd) == ["ls-files", "--modified", "--", "src/"]
    end

    test "stage flag" do
      cmd = %LsFiles{stage: true}
      assert LsFiles.args(cmd) == ["ls-files", "--stage"]
    end

    test "abbrev as boolean" do
      cmd = %LsFiles{abbrev: true}
      assert LsFiles.args(cmd) == ["ls-files", "--abbrev"]
    end

    test "abbrev as integer" do
      cmd = %LsFiles{abbrev: 8}
      assert LsFiles.args(cmd) == ["ls-files", "--abbrev=8"]
    end

    test "exclude option" do
      cmd = %LsFiles{others: true, exclude: "*.log"}
      assert LsFiles.args(cmd) == ["ls-files", "--others", "--exclude", "*.log"]
    end
  end

  describe "ls-files with cached files" do
    test "lists tracked files", %{tmp_dir: tmp_dir, config: config} do
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

      cmd = %LsFiles{cached: true}
      assert {:ok, files} = Git.Command.run(LsFiles, cmd, config)
      assert "tracked.txt" in files
    end
  end

  describe "ls-files with untracked files" do
    test "lists untracked files with --others --exclude-standard", %{
      tmp_dir: tmp_dir,
      config: config
    } do
      File.write!(Path.join(tmp_dir, "untracked.txt"), "content\n")

      cmd = %LsFiles{others: true, exclude_standard: true}
      assert {:ok, files} = Git.Command.run(LsFiles, cmd, config)
      assert "untracked.txt" in files
    end
  end

  describe "ls-files with modified files" do
    test "lists modified tracked files", %{tmp_dir: tmp_dir, config: config} do
      file = Path.join(tmp_dir, "modify_me.txt")
      File.write!(file, "original\n")
      System.cmd("git", ["add", "modify_me.txt"], cd: tmp_dir)

      System.cmd(
        "git",
        [
          "-c",
          "user.name=Test User",
          "-c",
          "user.email=test@test.com",
          "commit",
          "-m",
          "add file"
        ],
        cd: tmp_dir
      )

      File.write!(file, "modified\n")

      cmd = %LsFiles{modified: true}
      assert {:ok, files} = Git.Command.run(LsFiles, cmd, config)
      assert "modify_me.txt" in files
    end
  end

  describe "ls-files empty result" do
    test "returns empty list when no files match", %{config: config} do
      cmd = %LsFiles{others: true, exclude_standard: true}
      assert {:ok, []} = Git.Command.run(LsFiles, cmd, config)
    end
  end
end
