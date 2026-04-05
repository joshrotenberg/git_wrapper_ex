defmodule Git.StatusTest do
  use ExUnit.Case, async: true

  alias Git.Config
  alias Git.Status

  setup do
    tmp_dir =
      Path.join(System.tmp_dir!(), "git_wrapper_test_#{:erlang.unique_integer([:positive])}")

    File.mkdir_p!(tmp_dir)

    System.cmd("git", ["init", "--initial-branch=main"], cd: tmp_dir)

    System.cmd(
      "git",
      [
        "-c",
        "user.name=Test",
        "-c",
        "user.email=test@test.com",
        "commit",
        "--allow-empty",
        "-m",
        "init"
      ],
      cd: tmp_dir
    )

    on_exit(fn -> File.rm_rf!(tmp_dir) end)
    %{tmp_dir: tmp_dir, config: Config.new(working_dir: tmp_dir)}
  end

  describe "clean repository" do
    test "returns ok with empty entries and correct branch", %{config: config} do
      assert {:ok, %Status{} = status} = Git.status(config: config)
      assert status.branch == "main"
      assert status.entries == []
    end
  end

  describe "untracked file" do
    test "shows untracked file with ?? status", %{tmp_dir: tmp_dir, config: config} do
      File.write!(Path.join(tmp_dir, "new_file.txt"), "hello")

      assert {:ok, %Status{} = status} = Git.status(config: config)

      assert [entry] = status.entries
      assert entry.index == "?"
      assert entry.working_tree == "?"
      assert entry.path == "new_file.txt"
    end
  end

  describe "staged file" do
    test "shows staged new file with A index status", %{tmp_dir: tmp_dir, config: config} do
      File.write!(Path.join(tmp_dir, "staged.txt"), "staged content")
      System.cmd("git", ["add", "staged.txt"], cd: tmp_dir)

      assert {:ok, %Status{} = status} = Git.status(config: config)

      assert [entry] = status.entries
      assert entry.index == "A"
      assert entry.working_tree == " "
      assert entry.path == "staged.txt"
    end
  end

  describe "modified file" do
    test "shows modified tracked file with M working_tree status", %{
      tmp_dir: tmp_dir,
      config: config
    } do
      file_path = Path.join(tmp_dir, "tracked.txt")
      File.write!(file_path, "original")
      System.cmd("git", ["add", "tracked.txt"], cd: tmp_dir)

      System.cmd(
        "git",
        ["-c", "user.name=Test", "-c", "user.email=test@test.com", "commit", "-m", "add tracked"],
        cd: tmp_dir
      )

      File.write!(file_path, "modified")

      assert {:ok, %Status{} = status} = Git.status(config: config)

      assert [entry] = status.entries
      assert entry.index == " "
      assert entry.working_tree == "M"
      assert entry.path == "tracked.txt"
    end
  end

  describe "multiple changes" do
    test "shows multiple entries for different states", %{tmp_dir: tmp_dir, config: config} do
      # Create and commit a file
      File.write!(Path.join(tmp_dir, "existing.txt"), "original")
      System.cmd("git", ["add", "existing.txt"], cd: tmp_dir)

      System.cmd(
        "git",
        [
          "-c",
          "user.name=Test",
          "-c",
          "user.email=test@test.com",
          "commit",
          "-m",
          "add existing"
        ],
        cd: tmp_dir
      )

      # Modify the committed file (unstaged modification)
      File.write!(Path.join(tmp_dir, "existing.txt"), "changed")

      # Stage a new file
      File.write!(Path.join(tmp_dir, "new_staged.txt"), "new")
      System.cmd("git", ["add", "new_staged.txt"], cd: tmp_dir)

      # Create an untracked file
      File.write!(Path.join(tmp_dir, "untracked.txt"), "untracked")

      assert {:ok, %Status{} = status} = Git.status(config: config)

      assert length(status.entries) == 3

      paths = Enum.map(status.entries, & &1.path)
      assert "existing.txt" in paths
      assert "new_staged.txt" in paths
      assert "untracked.txt" in paths
    end
  end
end
