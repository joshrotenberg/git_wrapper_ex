defmodule Git.BranchesTest do
  use ExUnit.Case, async: true

  setup do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "git_branches_test_#{:erlang.unique_integer([:positive])}"
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
      Git.Config.new(
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

  # Helper to create an empty commit on the current branch
  defp commit(tmp_dir, message) do
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
        message
      ],
      cd: tmp_dir
    )
  end

  describe "create_and_checkout/2" do
    test "creates and switches to a new branch", %{config: config} do
      assert {:ok, checkout} = Git.Branches.create_and_checkout("feat/new", config: config)
      assert checkout.branch == "feat/new"
      assert checkout.created == true

      assert {:ok, "feat/new"} = Git.Branches.current(config: config)
    end
  end

  describe "current/1" do
    test "returns the current branch name", %{config: config} do
      assert {:ok, "main"} = Git.Branches.current(config: config)
    end

    test "returns the correct branch after switching", %{config: config} do
      Git.Branches.create_and_checkout("feat/other", config: config)
      assert {:ok, "feat/other"} = Git.Branches.current(config: config)
    end
  end

  describe "exists?/2" do
    test "returns true for an existing branch", %{config: config} do
      assert {:ok, true} = Git.Branches.exists?("main", config: config)
    end

    test "returns false for a non-existing branch", %{config: config} do
      assert {:ok, false} = Git.Branches.exists?("nonexistent", config: config)
    end

    test "returns true for a newly created branch", %{config: config} do
      Git.branch(config: config, create: "feat/check")
      assert {:ok, true} = Git.Branches.exists?("feat/check", config: config)
    end
  end

  describe "merged/1" do
    test "lists branches merged into current branch", %{config: config} do
      # Create a branch from main - it's merged by definition
      Git.branch(config: config, create: "already-merged")

      assert {:ok, branches} = Git.Branches.merged(config: config)
      names = Enum.map(branches, & &1.name)
      assert "already-merged" in names
      assert "main" in names
    end

    test "merged with target option", %{config: config} do
      Git.branch(config: config, create: "merged-into-main")

      assert {:ok, branches} = Git.Branches.merged(target: "main", config: config)
      names = Enum.map(branches, & &1.name)
      assert "merged-into-main" in names
    end
  end

  describe "no_merged/1" do
    test "lists branches not merged into current branch", %{tmp_dir: tmp_dir, config: config} do
      # Create a branch and add a commit to it so it diverges
      Git.Branches.create_and_checkout("diverged", config: config)
      commit(tmp_dir, "diverge commit")
      Git.checkout(config: config, branch: "main")

      assert {:ok, branches} = Git.Branches.no_merged(config: config)
      names = Enum.map(branches, & &1.name)
      assert "diverged" in names
    end
  end

  describe "cleanup_merged/1" do
    test "dry_run returns list of branches to delete", %{config: config} do
      Git.branch(config: config, create: "to-clean")

      assert {:ok, to_delete} = Git.Branches.cleanup_merged(dry_run: true, config: config)
      assert "to-clean" in to_delete
      # main should be excluded by default
      refute "main" in to_delete
    end

    test "actually deletes merged branches when not dry_run", %{config: config} do
      Git.branch(config: config, create: "deleteme")

      assert {:ok, deleted} = Git.Branches.cleanup_merged(config: config)
      assert "deleteme" in deleted

      assert {:ok, false} = Git.Branches.exists?("deleteme", config: config)
    end

    test "respects custom exclude list", %{config: config} do
      Git.branch(config: config, create: "keep-this")
      Git.branch(config: config, create: "delete-this")

      assert {:ok, deleted} =
               Git.Branches.cleanup_merged(
                 dry_run: true,
                 exclude: ["main", "master", "develop", "keep-this"],
                 config: config
               )

      refute "keep-this" in deleted
      assert "delete-this" in deleted
    end

    test "never deletes the current branch", %{config: config} do
      assert {:ok, deleted} = Git.Branches.cleanup_merged(dry_run: true, config: config)
      refute "main" in deleted
    end
  end

  describe "divergence/3" do
    test "returns ahead/behind counts between diverged branches", %{
      tmp_dir: tmp_dir,
      config: config
    } do
      # Create a branch, add commits to it
      Git.Branches.create_and_checkout("feature", config: config)
      commit(tmp_dir, "feature commit 1")
      commit(tmp_dir, "feature commit 2")

      # Switch back to main and add a commit
      Git.checkout(config: config, branch: "main")
      commit(tmp_dir, "main commit 1")

      assert {:ok, %{ahead: ahead, behind: behind}} =
               Git.Branches.divergence("main", "feature", config: config)

      assert ahead == 1
      assert behind == 2
    end

    test "returns zeros for identical branches", %{config: config} do
      Git.branch(config: config, create: "same")

      assert {:ok, %{ahead: 0, behind: 0}} =
               Git.Branches.divergence("main", "same", config: config)
    end
  end

  describe "recent/1" do
    test "lists branches sorted by most recent commit", %{tmp_dir: tmp_dir, config: config} do
      # Create branches with commits at different times
      Git.Branches.create_and_checkout("older", config: config)
      commit(tmp_dir, "older commit")

      Git.checkout(config: config, branch: "main")
      Git.Branches.create_and_checkout("newer", config: config)
      commit(tmp_dir, "newer commit")

      assert {:ok, entries} = Git.Branches.recent(config: config)
      assert entries != []

      names = Enum.map(entries, & &1.name)
      # newer should appear before older since it has the most recent commit
      newer_idx = Enum.find_index(names, &(&1 == "newer"))
      older_idx = Enum.find_index(names, &(&1 == "older"))
      assert newer_idx < older_idx
    end

    test "respects the count option", %{tmp_dir: tmp_dir, config: config} do
      Enum.each(1..5, fn i ->
        Git.checkout(config: config, branch: "main")
        Git.Branches.create_and_checkout("branch-#{i}", config: config)
        commit(tmp_dir, "commit #{i}")
      end)

      assert {:ok, entries} = Git.Branches.recent(count: 3, config: config)
      assert length(entries) == 3
    end

    test "entries have expected fields", %{tmp_dir: tmp_dir, config: config} do
      Git.Branches.create_and_checkout("info-branch", config: config)
      commit(tmp_dir, "info commit")

      assert {:ok, [first | _]} = Git.Branches.recent(config: config)
      assert Map.has_key?(first, :name)
      assert Map.has_key?(first, :date)
      assert Map.has_key?(first, :author)
      assert Map.has_key?(first, :subject)
    end
  end

  describe "rename/3" do
    test "renames a branch", %{config: config} do
      Git.branch(config: config, create: "old-name")

      assert {:ok, :done} = Git.Branches.rename("old-name", "new-name", config: config)
      assert {:ok, false} = Git.Branches.exists?("old-name", config: config)
      assert {:ok, true} = Git.Branches.exists?("new-name", config: config)
    end

    test "returns error when renaming non-existent branch", %{config: config} do
      assert {:error, _} = Git.Branches.rename("nope", "also-nope", config: config)
    end
  end
end
