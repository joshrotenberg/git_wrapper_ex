defmodule Git.Commands.BranchTest do
  use ExUnit.Case, async: true

  alias Git.Commands.Branch
  alias Git.Config

  setup do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "git_wrapper_branch_test_#{:erlang.unique_integer([:positive])}"
      )

    File.mkdir_p!(tmp_dir)

    System.cmd("git", ["init", "--initial-branch=main"], cd: tmp_dir)
    System.cmd("git", ["config", "user.name", "Test User"], cd: tmp_dir)
    System.cmd("git", ["config", "user.email", "test@test.com"], cd: tmp_dir)

    System.cmd(
      "git",
      ["commit", "--allow-empty", "-m", "initial"],
      cd: tmp_dir
    )

    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    config = Config.new(working_dir: tmp_dir)

    %{tmp_dir: tmp_dir, config: config}
  end

  describe "Commands.Branch.args/1" do
    test "list branches (default)" do
      assert Branch.args(%Branch{}) == ["branch", "-vv"]
    end

    test "list all branches" do
      assert Branch.args(%Branch{all: true}) == ["branch", "-vv", "--all"]
    end

    test "create branch" do
      assert Branch.args(%Branch{create: "feat/new"}) == ["branch", "feat/new"]
    end

    test "delete branch" do
      assert Branch.args(%Branch{delete: "old"}) == ["branch", "-d", "old"]
    end

    test "force delete branch" do
      assert Branch.args(%Branch{delete: "old", force_delete: true}) ==
               ["branch", "-D", "old"]
    end

    test "rename branch" do
      assert Branch.args(%Branch{rename: "old-name", rename_to: "new-name"}) ==
               ["branch", "-m", "old-name", "new-name"]
    end

    test "merged filter" do
      assert Branch.args(%Branch{merged: true}) == ["branch", "--merged"]
    end

    test "merged filter with ref" do
      assert Branch.args(%Branch{merged: "HEAD~1"}) ==
               ["branch", "--merged", "HEAD~1"]
    end

    test "no merged filter" do
      assert Branch.args(%Branch{no_merged: true}) == ["branch", "--no-merged"]
    end

    test "no merged filter with ref" do
      assert Branch.args(%Branch{no_merged: "main"}) ==
               ["branch", "--no-merged", "main"]
    end
  end

  describe "integration" do
    test "create, list, and delete a branch", %{config: config} do
      # Create a branch
      assert {:ok, :done} = Git.branch(create: "test-branch", config: config)

      # List branches -- should include both main and test-branch
      assert {:ok, branches} = Git.branch(config: config)
      names = Enum.map(branches, & &1.name)
      assert "main" in names
      assert "test-branch" in names

      # Delete the branch
      assert {:ok, :done} = Git.branch(delete: "test-branch", config: config)

      # Verify deletion
      assert {:ok, branches} = Git.branch(config: config)
      names = Enum.map(branches, & &1.name)
      refute "test-branch" in names
    end

    test "list merged branches", %{tmp_dir: tmp_dir, config: config} do
      System.cmd("git", ["branch", "merged-branch"], cd: tmp_dir)

      assert {:ok, branches} = Git.branch(merged: true, config: config)
      names = Enum.map(branches, & &1.name)
      assert "merged-branch" in names
    end

    test "rename a branch", %{tmp_dir: tmp_dir, config: config} do
      System.cmd("git", ["branch", "old-name"], cd: tmp_dir)

      assert {:ok, :done} =
               Git.branch(rename: "old-name", rename_to: "new-name", config: config)

      assert {:ok, branches} = Git.branch(config: config)
      names = Enum.map(branches, & &1.name)
      assert "new-name" in names
      refute "old-name" in names
    end
  end
end
