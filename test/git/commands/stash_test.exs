defmodule Git.Commands.StashTest do
  use ExUnit.Case, async: true

  alias Git.Commands.Stash
  alias Git.Config

  setup do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "git_wrapper_stash_test_#{:erlang.unique_integer([:positive])}"
      )

    File.mkdir_p!(tmp_dir)

    System.cmd("git", ["init", "--initial-branch=main"], cd: tmp_dir)
    System.cmd("git", ["config", "user.name", "Test User"], cd: tmp_dir)
    System.cmd("git", ["config", "user.email", "test@test.com"], cd: tmp_dir)

    # Create a file and make initial commit
    File.write!(Path.join(tmp_dir, "hello.txt"), "hello\n")
    System.cmd("git", ["add", "hello.txt"], cd: tmp_dir)

    System.cmd(
      "git",
      ["commit", "-m", "initial"],
      cd: tmp_dir
    )

    on_exit(fn -> Git.TestHelpers.rm_rf(tmp_dir) end)

    config = Config.new(working_dir: tmp_dir)

    %{tmp_dir: tmp_dir, config: config}
  end

  describe "Commands.Stash.args/1" do
    test "list (default)" do
      assert Stash.args(%Stash{}) == ["stash", "list"]
    end

    test "save (push)" do
      assert Stash.args(%Stash{save: true}) == ["stash", "push"]
    end

    test "save with message" do
      assert Stash.args(%Stash{save: true, message: "wip"}) ==
               ["stash", "push", "-m", "wip"]
    end

    test "save with include_untracked" do
      assert Stash.args(%Stash{save: true, include_untracked: true}) ==
               ["stash", "push", "-u"]
    end

    test "save with keep_index" do
      assert Stash.args(%Stash{save: true, keep_index: true}) ==
               ["stash", "push", "--keep-index"]
    end

    test "pop" do
      assert Stash.args(%Stash{pop: true}) == ["stash", "pop"]
    end

    test "pop with index" do
      assert Stash.args(%Stash{pop: true, index: 0}) ==
               ["stash", "pop", "stash@{0}"]
    end

    test "apply" do
      assert Stash.args(%Stash{apply: true}) == ["stash", "apply"]
    end

    test "apply with index" do
      assert Stash.args(%Stash{apply: true, index: 1}) ==
               ["stash", "apply", "stash@{1}"]
    end

    test "drop" do
      assert Stash.args(%Stash{drop: true}) == ["stash", "drop"]
    end

    test "drop with index" do
      assert Stash.args(%Stash{drop: true, index: 1}) ==
               ["stash", "drop", "stash@{1}"]
    end

    test "clear" do
      assert Stash.args(%Stash{clear: true}) == ["stash", "clear"]
    end

    test "branch" do
      assert Stash.args(%Stash{branch: "recovered"}) ==
               ["stash", "branch", "recovered"]
    end

    test "branch with index" do
      assert Stash.args(%Stash{branch: "recovered", index: 1}) ==
               ["stash", "branch", "recovered", "stash@{1}"]
    end

    test "show" do
      assert Stash.args(%Stash{show: true}) == ["stash", "show"]
    end

    test "show with index" do
      assert Stash.args(%Stash{show: true, index: 0}) ==
               ["stash", "show", "stash@{0}"]
    end
  end

  describe "integration" do
    test "stash and pop changes", %{tmp_dir: tmp_dir, config: config} do
      # Modify a tracked file
      File.write!(Path.join(tmp_dir, "hello.txt"), "modified\n")

      # Stash the changes
      assert {:ok, :done} = Git.stash(save: true, config: config)

      # File should be restored to original content
      assert File.read!(Path.join(tmp_dir, "hello.txt")) == "hello\n"

      # List stash -- should have one entry
      assert {:ok, entries} = Git.stash(config: config)
      assert length(entries) == 1

      # Pop the stash
      assert {:ok, :done} = Git.stash(pop: true, config: config)

      # File should have the modified content again
      assert File.read!(Path.join(tmp_dir, "hello.txt")) == "modified\n"

      # Stash should now be empty
      assert {:ok, []} = Git.stash(config: config)
    end

    test "stash with message", %{tmp_dir: tmp_dir, config: config} do
      File.write!(Path.join(tmp_dir, "hello.txt"), "wip changes\n")

      assert {:ok, :done} =
               Git.stash(save: true, message: "work in progress", config: config)

      assert {:ok, entries} = Git.stash(config: config)
      assert length(entries) == 1
      assert hd(entries).message =~ "work in progress"

      # Clean up: drop the stash
      assert {:ok, :done} = Git.stash(drop: true, config: config)
    end

    test "stash and apply keeps the stash entry", %{tmp_dir: tmp_dir, config: config} do
      # Modify a tracked file
      File.write!(Path.join(tmp_dir, "hello.txt"), "modified\n")

      # Stash the changes
      assert {:ok, :done} = Git.stash(save: true, config: config)

      # File should be restored to original content
      assert File.read!(Path.join(tmp_dir, "hello.txt")) == "hello\n"

      # Apply the stash -- change reappears
      assert {:ok, :done} = Git.stash(apply: true, config: config)
      assert File.read!(Path.join(tmp_dir, "hello.txt")) == "modified\n"

      # Unlike pop, apply leaves the stash entry in place
      assert {:ok, entries} = Git.stash(config: config)
      assert length(entries) == 1

      # Clean up: drop the stash
      assert {:ok, :done} = Git.stash(drop: true, config: config)
    end

    test "clear removes all stash entries", %{tmp_dir: tmp_dir, config: config} do
      # Create two stash entries from successive changes
      File.write!(Path.join(tmp_dir, "hello.txt"), "first\n")
      assert {:ok, :done} = Git.stash(save: true, config: config)

      File.write!(Path.join(tmp_dir, "hello.txt"), "second\n")
      assert {:ok, :done} = Git.stash(save: true, config: config)

      assert {:ok, entries} = Git.stash(config: config)
      assert length(entries) == 2

      # Clear all entries
      assert {:ok, :done} = Git.stash(clear: true, config: config)

      # Stash should now be empty
      assert {:ok, []} = Git.stash(config: config)
    end

    test "show returns the diff for a stash entry", %{tmp_dir: tmp_dir, config: config} do
      File.write!(Path.join(tmp_dir, "hello.txt"), "modified\n")

      assert {:ok, :done} = Git.stash(save: true, config: config)

      assert {:ok, diff} = Git.stash(show: true, config: config)
      assert is_binary(diff)
      assert diff =~ "hello.txt"

      # Clean up: drop the stash
      assert {:ok, :done} = Git.stash(drop: true, config: config)
    end
  end
end
