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

    on_exit(fn -> File.rm_rf!(tmp_dir) end)

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

    test "pop" do
      assert Stash.args(%Stash{pop: true}) == ["stash", "pop"]
    end

    test "pop with index" do
      assert Stash.args(%Stash{pop: true, index: 0}) ==
               ["stash", "pop", "stash@{0}"]
    end

    test "drop" do
      assert Stash.args(%Stash{drop: true}) == ["stash", "drop"]
    end

    test "drop with index" do
      assert Stash.args(%Stash{drop: true, index: 1}) ==
               ["stash", "drop", "stash@{1}"]
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
  end
end
