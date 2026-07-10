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

    on_exit(fn -> Git.TestHelpers.rm_rf(tmp_dir) end)

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

  # Adds a bare remote to the setup repo and pushes main to it.
  defp with_remote(tmp_dir) do
    remote_dir = Path.join(tmp_dir, "remote.git")
    System.cmd("git", ["init", "--bare", "--initial-branch=main", remote_dir])
    System.cmd("git", ["remote", "add", "origin", remote_dir], cd: tmp_dir)
    System.cmd("git", ["push", "-u", "origin", "main"], cd: tmp_dir)
    remote_dir
  end

  # Branches off `target`, commits each file in `changes`, then squash-merges
  # the branch back into `target`. Leaves the checkout on `target`.
  defp squash_merge_into(tmp_dir, config, target, branch, changes) do
    Git.Branches.create_and_checkout(branch, config: config)

    Enum.each(changes, fn file ->
      File.write!(Path.join(tmp_dir, file), "#{file}\n")
      System.cmd("git", ["add", file], cd: tmp_dir)
      commit(tmp_dir, "work on #{file}")
    end)

    Git.checkout(config: config, branch: target)
    System.cmd("git", ["merge", "--squash", branch], cd: tmp_dir)

    System.cmd(
      "git",
      [
        "-c",
        "user.name=Test User",
        "-c",
        "user.email=test@test.com",
        "commit",
        "-m",
        "squash #{branch}"
      ],
      cd: tmp_dir
    )
  end

  # Squash-merges a new branch into main (the default target).
  defp squash_merge(tmp_dir, config, branch, changes) do
    squash_merge_into(tmp_dir, config, "main", branch, changes)
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

  describe "delete_branch/2" do
    test "deletes only the local branch when no remote is given", %{
      tmp_dir: tmp_dir,
      config: config
    } do
      System.cmd("git", ["branch", "gone-local"], cd: tmp_dir)

      assert {:ok, :done} = Git.Branches.delete_branch("gone-local", config: config)
      assert {:ok, false} = Git.Branches.exists?("gone-local", config: config)
    end

    test "deletes the branch locally and on the remote", %{tmp_dir: tmp_dir, config: config} do
      remote_dir = with_remote(tmp_dir)
      System.cmd("git", ["branch", "feature"], cd: tmp_dir)
      System.cmd("git", ["push", "origin", "feature"], cd: tmp_dir)

      assert {:ok, :done} =
               Git.Branches.delete_branch("feature", remote: "origin", config: config)

      assert {:ok, false} = Git.Branches.exists?("feature", config: config)
      {out, 0} = System.cmd("git", ["ls-remote", "--heads", remote_dir, "feature"], cd: tmp_dir)
      assert out == ""
    end
  end

  describe "prune_gone/1" do
    test "deletes local branches whose upstream is gone", %{tmp_dir: tmp_dir, config: config} do
      remote_dir = with_remote(tmp_dir)
      System.cmd("git", ["checkout", "-b", "feature"], cd: tmp_dir)
      System.cmd("git", ["push", "-u", "origin", "feature"], cd: tmp_dir)
      System.cmd("git", ["checkout", "main"], cd: tmp_dir)
      # delete the branch directly on the bare remote so the upstream goes away
      System.cmd("git", ["update-ref", "-d", "refs/heads/feature"], cd: remote_dir)

      assert {:ok, deleted} = Git.Branches.prune_gone(config: config)
      assert "feature" in deleted
      assert {:ok, false} = Git.Branches.exists?("feature", config: config)
    end

    test "dry_run reports gone branches without deleting them", %{
      tmp_dir: tmp_dir,
      config: config
    } do
      remote_dir = with_remote(tmp_dir)
      System.cmd("git", ["checkout", "-b", "feature"], cd: tmp_dir)
      System.cmd("git", ["push", "-u", "origin", "feature"], cd: tmp_dir)
      System.cmd("git", ["checkout", "main"], cd: tmp_dir)
      System.cmd("git", ["update-ref", "-d", "refs/heads/feature"], cd: remote_dir)

      assert {:ok, ["feature"]} = Git.Branches.prune_gone(dry_run: true, config: config)
      assert {:ok, true} = Git.Branches.exists?("feature", config: config)
    end
  end

  describe "delete_squashed/1" do
    test "detects a squash-merged branch (dry_run by default)", %{
      tmp_dir: tmp_dir,
      config: config
    } do
      squash_merge(tmp_dir, config, "feat-squash", ["one.txt", "two.txt"])

      assert {:ok, squashed} = Git.Branches.delete_squashed(config: config)
      assert "feat-squash" in squashed
      # Default dry_run leaves the branch in place.
      assert {:ok, true} = Git.Branches.exists?("feat-squash", config: config)
    end

    test "does not flag a normally-merged branch", %{tmp_dir: tmp_dir, config: config} do
      Git.Branches.create_and_checkout("feat-merge", config: config)
      File.write!(Path.join(tmp_dir, "merged.txt"), "merged\n")
      System.cmd("git", ["add", "merged.txt"], cd: tmp_dir)
      commit(tmp_dir, "normal merge work")
      Git.checkout(config: config, branch: "main")
      System.cmd("git", ["merge", "--no-ff", "-m", "merge feat-merge", "feat-merge"], cd: tmp_dir)

      assert {:ok, squashed} = Git.Branches.delete_squashed(config: config)
      refute "feat-merge" in squashed
    end

    test "does not flag a truly-unmerged branch", %{tmp_dir: tmp_dir, config: config} do
      Git.Branches.create_and_checkout("feat-unmerged", config: config)
      File.write!(Path.join(tmp_dir, "wip.txt"), "wip\n")
      System.cmd("git", ["add", "wip.txt"], cd: tmp_dir)
      commit(tmp_dir, "unmerged work")
      Git.checkout(config: config, branch: "main")

      assert {:ok, squashed} = Git.Branches.delete_squashed(config: config)
      refute "feat-unmerged" in squashed
    end

    test "deletes squashed branches when dry_run is false", %{tmp_dir: tmp_dir, config: config} do
      squash_merge(tmp_dir, config, "feat-gone", ["gone.txt"])

      assert {:ok, deleted} = Git.Branches.delete_squashed(dry_run: false, config: config)
      assert "feat-gone" in deleted
      assert {:ok, false} = Git.Branches.exists?("feat-gone", config: config)
    end

    test "never deletes the current branch", %{tmp_dir: tmp_dir, config: config} do
      # Squash-merge feat into main, then switch onto feat itself so it is the
      # current branch. It must never be reported even though it is squashed.
      squash_merge(tmp_dir, config, "feat-current", ["cur.txt"])
      Git.checkout(config: config, branch: "feat-current")

      assert {:ok, squashed} = Git.Branches.delete_squashed(config: config)
      refute "feat-current" in squashed
    end

    test "respects a custom target", %{tmp_dir: tmp_dir, config: config} do
      # Squash feat into a release branch, not the current branch (main).
      Git.branch(config: config, create: "release")
      Git.checkout(config: config, branch: "release")
      squash_merge_into(tmp_dir, config, "release", "feat-rel", ["rel.txt"])
      Git.checkout(config: config, branch: "main")

      # Against main (current, the default) it is not squashed...
      assert {:ok, default_squashed} = Git.Branches.delete_squashed(config: config)
      refute "feat-rel" in default_squashed

      # ...but against the release target it is detected.
      assert {:ok, target_squashed} =
               Git.Branches.delete_squashed(target: "release", config: config)

      assert "feat-rel" in target_squashed
    end

    test "respects the exclude list", %{tmp_dir: tmp_dir, config: config} do
      squash_merge(tmp_dir, config, "feat-keep", ["keep.txt"])

      assert {:ok, squashed} =
               Git.Branches.delete_squashed(
                 exclude: ["main", "master", "develop", "feat-keep"],
                 config: config
               )

      refute "feat-keep" in squashed
    end
  end
end
