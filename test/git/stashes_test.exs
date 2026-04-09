defmodule Git.StashesTest do
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
        "git_stashes_test_#{:erlang.unique_integer([:positive])}"
      )

    File.mkdir_p!(tmp_dir)
    System.cmd("git", ["init", "--initial-branch=main"], cd: tmp_dir)
    System.cmd("git", ["config", "user.email", "test@example.com"], cd: tmp_dir)
    System.cmd("git", ["config", "user.name", "Test User"], cd: tmp_dir)

    # Need at least one commit for stash to work
    File.write!(Path.join(tmp_dir, "README.md"), "initial")
    System.cmd("git", ["add", "."], cd: tmp_dir)
    System.cmd("git", ["commit", "-m", "initial commit"], cd: tmp_dir, env: @git_env)

    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    config = Git.Config.new(working_dir: tmp_dir, env: @git_env)

    %{tmp_dir: tmp_dir, config: config}
  end

  defp make_dirty(tmp_dir) do
    File.write!(Path.join(tmp_dir, "dirty.txt"), "uncommitted changes")
    System.cmd("git", ["add", "dirty.txt"], cd: tmp_dir)
  end

  describe "save/2" do
    test "saves current changes with a message", %{tmp_dir: tmp_dir, config: config} do
      make_dirty(tmp_dir)

      assert {:ok, :done} = Git.Stashes.save("work in progress", config: config)

      # Verify stash was created
      assert {:ok, entries} = Git.Stashes.list(config: config)
      assert length(entries) == 1
    end
  end

  describe "list/1" do
    test "returns empty list when no stashes exist", %{config: config} do
      assert {:ok, []} = Git.Stashes.list(config: config)
    end

    test "lists stash entries after save", %{tmp_dir: tmp_dir, config: config} do
      make_dirty(tmp_dir)
      Git.Stashes.save("first stash", config: config)

      # Create another dirty file and stash it
      File.write!(Path.join(tmp_dir, "another.txt"), "more changes")
      System.cmd("git", ["add", "another.txt"], cd: tmp_dir)
      Git.Stashes.save("second stash", config: config)

      assert {:ok, entries} = Git.Stashes.list(config: config)
      assert length(entries) == 2
    end
  end

  describe "pop/1" do
    test "pops the latest stash entry", %{tmp_dir: tmp_dir, config: config} do
      make_dirty(tmp_dir)
      Git.Stashes.save("to pop", config: config)

      # File should be gone after stash
      refute File.exists?(Path.join(tmp_dir, "dirty.txt"))

      assert {:ok, :done} = Git.Stashes.pop(config: config)

      # File should be restored
      assert File.exists?(Path.join(tmp_dir, "dirty.txt"))

      # Stash should be empty
      assert {:ok, []} = Git.Stashes.list(config: config)
    end
  end

  describe "apply/1" do
    test "applies the latest stash without removing it", %{tmp_dir: tmp_dir, config: config} do
      make_dirty(tmp_dir)
      Git.Stashes.save("to apply", config: config)

      refute File.exists?(Path.join(tmp_dir, "dirty.txt"))

      assert {:ok, :done} = Git.Stashes.apply(config: config)

      # File should be restored
      assert File.exists?(Path.join(tmp_dir, "dirty.txt"))

      # Stash should still exist (apply does not remove it)
      assert {:ok, entries} = Git.Stashes.list(config: config)
      assert length(entries) == 1
    end

    test "applies a specific stash by index", %{tmp_dir: tmp_dir, config: config} do
      # Create first stash
      File.write!(Path.join(tmp_dir, "first.txt"), "first")
      System.cmd("git", ["add", "first.txt"], cd: tmp_dir)
      Git.Stashes.save("first", config: config)

      # Create second stash
      File.write!(Path.join(tmp_dir, "second.txt"), "second")
      System.cmd("git", ["add", "second.txt"], cd: tmp_dir)
      Git.Stashes.save("second", config: config)

      # Apply stash@{1} (the first/older stash)
      assert {:ok, :done} = Git.Stashes.apply(index: 1, config: config)

      assert File.exists?(Path.join(tmp_dir, "first.txt"))
    end
  end

  describe "drop/1" do
    test "drops the latest stash entry", %{tmp_dir: tmp_dir, config: config} do
      make_dirty(tmp_dir)
      Git.Stashes.save("to drop", config: config)

      assert {:ok, entries} = Git.Stashes.list(config: config)
      assert length(entries) == 1

      assert {:ok, :done} = Git.Stashes.drop(config: config)

      assert {:ok, []} = Git.Stashes.list(config: config)
    end

    test "drops a specific stash by index", %{tmp_dir: tmp_dir, config: config} do
      # Create two stashes
      File.write!(Path.join(tmp_dir, "a.txt"), "a")
      System.cmd("git", ["add", "a.txt"], cd: tmp_dir)
      Git.Stashes.save("stash a", config: config)

      File.write!(Path.join(tmp_dir, "b.txt"), "b")
      System.cmd("git", ["add", "b.txt"], cd: tmp_dir)
      Git.Stashes.save("stash b", config: config)

      # Drop stash@{1} (the older one)
      assert {:ok, :done} = Git.Stashes.drop(index: 1, config: config)

      assert {:ok, entries} = Git.Stashes.list(config: config)
      assert length(entries) == 1
    end
  end

  describe "clear/1" do
    test "clears all stash entries", %{tmp_dir: tmp_dir, config: config} do
      # Create multiple stashes
      File.write!(Path.join(tmp_dir, "x.txt"), "x")
      System.cmd("git", ["add", "x.txt"], cd: tmp_dir)
      Git.Stashes.save("stash x", config: config)

      File.write!(Path.join(tmp_dir, "y.txt"), "y")
      System.cmd("git", ["add", "y.txt"], cd: tmp_dir)
      Git.Stashes.save("stash y", config: config)

      assert {:ok, entries} = Git.Stashes.list(config: config)
      assert length(entries) == 2

      assert {:ok, :done} = Git.Stashes.clear(config: config)

      assert {:ok, []} = Git.Stashes.list(config: config)
    end
  end
end
