defmodule GitWrapper.StashTest do
  use ExUnit.Case, async: true

  alias GitWrapper.StashEntry
  alias GitWrapper.Commands.Stash, as: StashCmd

  # ---------------------------------------------------------------------------
  # Test helpers
  # ---------------------------------------------------------------------------

  defp setup_repo do
    dir =
      Path.join(
        System.tmp_dir!(),
        "git_wrapper_stash_test_#{:erlang.unique_integer([:positive])}"
      )

    File.mkdir_p!(dir)
    System.cmd("git", ["init", "--initial-branch=main"], cd: dir)
    System.cmd("git", ["config", "user.email", "test@example.com"], cd: dir)
    System.cmd("git", ["config", "user.name", "Test User"], cd: dir)
    # Create an initial commit so stash has a base
    File.write!(Path.join(dir, "init.txt"), "init\n")
    System.cmd("git", ["add", "."], cd: dir)
    System.cmd("git", ["commit", "-m", "init"], cd: dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    {GitWrapper.Config.new(working_dir: dir), dir}
  end

  # ---------------------------------------------------------------------------
  # Unit tests: StashEntry.parse/1
  # ---------------------------------------------------------------------------

  describe "StashEntry.parse/1" do
    test "empty output returns empty list" do
      assert StashEntry.parse("") == []
    end

    test "parses a single stash entry with explicit message" do
      output = "stash@{0}: On main: my changes\n"
      assert [%StashEntry{index: 0, branch: "main", message: "my changes"}] = StashEntry.parse(output)
    end

    test "parses a WIP stash entry" do
      output = "stash@{0}: WIP on main: abc1234 commit message\n"
      assert [%StashEntry{index: 0, branch: "main", message: "abc1234 commit message"}] = StashEntry.parse(output)
    end

    test "parses multiple stash entries" do
      output = "stash@{0}: On main: latest\nstash@{1}: On main: earlier\nstash@{2}: WIP on feat: def5678 wip\n"
      entries = StashEntry.parse(output)
      assert length(entries) == 3
      assert Enum.at(entries, 0).index == 0
      assert Enum.at(entries, 0).message == "latest"
      assert Enum.at(entries, 1).index == 1
      assert Enum.at(entries, 1).message == "earlier"
      assert Enum.at(entries, 2).index == 2
      assert Enum.at(entries, 2).branch == "feat"
    end

    test "parses entry on branch with slashes" do
      output = "stash@{0}: On feat/my-branch: some work\n"

      assert [%StashEntry{index: 0, branch: "feat/my-branch", message: "some work"}] =
               StashEntry.parse(output)
    end
  end

  # ---------------------------------------------------------------------------
  # Unit tests: Commands.Stash.args/1
  # ---------------------------------------------------------------------------

  describe "Commands.Stash.args/1" do
    test "default struct produces list args" do
      assert StashCmd.args(%StashCmd{}) == ["stash", "list"]
    end

    test "save produces push args" do
      assert StashCmd.args(%StashCmd{save: true}) == ["stash", "push"]
    end

    test "save with message" do
      assert StashCmd.args(%StashCmd{save: true, message: "wip"}) == ["stash", "push", "-m", "wip"]
    end

    test "save with include_untracked" do
      assert StashCmd.args(%StashCmd{save: true, include_untracked: true}) == ["stash", "push", "-u"]
    end

    test "save with message and include_untracked" do
      assert StashCmd.args(%StashCmd{save: true, message: "wip", include_untracked: true}) ==
               ["stash", "push", "-m", "wip", "-u"]
    end

    test "pop without index" do
      assert StashCmd.args(%StashCmd{pop: true}) == ["stash", "pop"]
    end

    test "pop with index" do
      assert StashCmd.args(%StashCmd{pop: true, index: 1}) == ["stash", "pop", "stash@{1}"]
    end

    test "drop without index" do
      assert StashCmd.args(%StashCmd{drop: true}) == ["stash", "drop"]
    end

    test "drop with index" do
      assert StashCmd.args(%StashCmd{drop: true, index: 2}) == ["stash", "drop", "stash@{2}"]
    end
  end

  # ---------------------------------------------------------------------------
  # Unit tests: Commands.Stash.parse_output/2
  # ---------------------------------------------------------------------------

  describe "Commands.Stash.parse_output/2" do
    test "empty list output returns empty list" do
      StashCmd.args(%StashCmd{})
      assert {:ok, []} = StashCmd.parse_output("", 0)
    end

    test "mutation mode returns :done" do
      StashCmd.args(%StashCmd{save: true})
      assert {:ok, :done} = StashCmd.parse_output("Saved working directory", 0)
    end

    test "non-zero exit returns error tuple" do
      assert {:error, {"error msg", 1}} = StashCmd.parse_output("error msg", 1)
    end
  end

  # ---------------------------------------------------------------------------
  # Integration tests
  # ---------------------------------------------------------------------------

  describe "GitWrapperEx.stash/1 integration" do
    test "lists stash in clean repo" do
      {config, _dir} = setup_repo()
      assert {:ok, []} = GitWrapperEx.stash(config: config)
    end

    test "save stashes tracked changes" do
      {config, dir} = setup_repo()
      File.write!(Path.join(dir, "init.txt"), "modified\n")

      assert {:ok, :done} = GitWrapperEx.stash(config: config, save: true)

      # Working tree should be clean after stash
      assert {:ok, status} = GitWrapperEx.status(config: config)
      assert status.entries == []
    end

    test "save with message" do
      {config, dir} = setup_repo()
      File.write!(Path.join(dir, "init.txt"), "modified\n")

      assert {:ok, :done} = GitWrapperEx.stash(config: config, save: true, message: "my stash")

      assert {:ok, entries} = GitWrapperEx.stash(config: config)
      assert length(entries) == 1
      assert hd(entries).message == "my stash"
    end

    test "saved stash appears in listing" do
      {config, dir} = setup_repo()
      File.write!(Path.join(dir, "init.txt"), "modified\n")
      GitWrapperEx.stash(config: config, save: true, message: "test stash")

      assert {:ok, entries} = GitWrapperEx.stash(config: config)
      assert length(entries) == 1
      assert hd(entries).index == 0
      assert hd(entries).branch == "main"
    end

    test "pop restores stashed changes" do
      {config, dir} = setup_repo()
      file_path = Path.join(dir, "init.txt")
      File.write!(file_path, "modified\n")
      GitWrapperEx.stash(config: config, save: true)

      assert {:ok, :done} = GitWrapperEx.stash(config: config, pop: true)

      # File should be modified again
      assert File.read!(file_path) == "modified\n"

      # Stash list should be empty
      assert {:ok, []} = GitWrapperEx.stash(config: config)
    end

    test "drop removes stash entry" do
      {config, dir} = setup_repo()
      File.write!(Path.join(dir, "init.txt"), "modified\n")
      GitWrapperEx.stash(config: config, save: true, message: "to drop")

      assert {:ok, :done} = GitWrapperEx.stash(config: config, drop: true, index: 0)

      assert {:ok, []} = GitWrapperEx.stash(config: config)
    end

    test "multiple stashes maintain correct ordering" do
      {config, dir} = setup_repo()
      file_path = Path.join(dir, "init.txt")

      File.write!(file_path, "first\n")
      GitWrapperEx.stash(config: config, save: true, message: "first stash")

      File.write!(file_path, "second\n")
      GitWrapperEx.stash(config: config, save: true, message: "second stash")

      assert {:ok, entries} = GitWrapperEx.stash(config: config)
      assert length(entries) == 2
      # Most recent stash is at index 0
      assert Enum.at(entries, 0).index == 0
      assert Enum.at(entries, 0).message == "second stash"
      assert Enum.at(entries, 1).index == 1
      assert Enum.at(entries, 1).message == "first stash"
    end

    test "pop with specific index" do
      {config, dir} = setup_repo()
      file_path = Path.join(dir, "init.txt")

      File.write!(file_path, "first\n")
      GitWrapperEx.stash(config: config, save: true, message: "first stash")

      File.write!(file_path, "second\n")
      GitWrapperEx.stash(config: config, save: true, message: "second stash")

      # Pop the older stash (index 1)
      assert {:ok, :done} = GitWrapperEx.stash(config: config, pop: true, index: 1)

      # Only one stash should remain
      assert {:ok, entries} = GitWrapperEx.stash(config: config)
      assert length(entries) == 1
      assert hd(entries).message == "second stash"
    end

    test "save with include_untracked stashes new files" do
      {config, dir} = setup_repo()
      File.write!(Path.join(dir, "new_file.txt"), "untracked\n")

      assert {:ok, :done} =
               GitWrapperEx.stash(config: config, save: true, include_untracked: true)

      # Untracked file should be gone
      refute File.exists?(Path.join(dir, "new_file.txt"))

      # Pop to restore
      GitWrapperEx.stash(config: config, pop: true)
      assert File.exists?(Path.join(dir, "new_file.txt"))
    end

    test "pop on empty stash returns error" do
      {config, _dir} = setup_repo()
      assert {:error, _} = GitWrapperEx.stash(config: config, pop: true)
    end

    test "drop on empty stash returns error" do
      {config, _dir} = setup_repo()
      assert {:error, _} = GitWrapperEx.stash(config: config, drop: true)
    end
  end
end
