defmodule Git.WorkflowTest do
  use ExUnit.Case, async: true

  alias Git.Config

  defp setup_repo(name) do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "git_workflow_mod_#{name}_#{:erlang.unique_integer([:positive])}"
      )

    File.mkdir_p!(tmp_dir)
    cfg = Config.new(working_dir: tmp_dir)
    {:ok, :done} = Git.init(config: cfg)
    {:ok, :done} = Git.git_config(set_key: "user.name", set_value: "Test User", config: cfg)
    {:ok, :done} = Git.git_config(set_key: "user.email", set_value: "test@test.com", config: cfg)
    {:ok, _} = Git.commit("initial", allow_empty: true, config: cfg)
    {tmp_dir, cfg}
  end

  defp setup_remote_repo(name) do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "git_workflow_mod_#{name}_#{:erlang.unique_integer([:positive])}"
      )

    File.mkdir_p!(tmp_dir)

    remote_dir = Path.join(tmp_dir, "remote.git")
    File.mkdir_p!(remote_dir)
    System.cmd("git", ["init", "--bare", "--initial-branch=main"], cd: remote_dir)

    local_dir = Path.join(tmp_dir, "local")
    File.mkdir_p!(local_dir)
    cfg = Config.new(working_dir: local_dir)
    {:ok, :done} = Git.init(config: cfg)
    {:ok, :done} = Git.git_config(set_key: "user.name", set_value: "Test User", config: cfg)
    {:ok, :done} = Git.git_config(set_key: "user.email", set_value: "test@test.com", config: cfg)
    {:ok, :done} = Git.remote(add_name: "origin", add_url: remote_dir, config: cfg)
    File.write!(Path.join(local_dir, "README.md"), "# Test\n")
    {:ok, :done} = Git.add(files: ["README.md"], config: cfg)
    {:ok, _} = Git.commit("initial", config: cfg)
    {:ok, :done} = Git.push(remote: "origin", branch: "main", set_upstream: true, config: cfg)

    {tmp_dir, local_dir, remote_dir, cfg}
  end

  # Clones the remote into a throwaway dir, writes the given {file, content}
  # changes, commits, and pushes, so the caller's local repo has something to
  # sync down.
  defp push_via_second_clone(tmp_dir, remote_dir, changes) do
    second_dir = Path.join(tmp_dir, "second_#{:erlang.unique_integer([:positive])}")
    File.mkdir_p!(second_dir)
    second_cfg = Config.new(working_dir: second_dir)
    System.cmd("git", ["clone", remote_dir, second_dir])

    {:ok, :done} =
      Git.git_config(set_key: "user.name", set_value: "Test User", config: second_cfg)

    {:ok, :done} =
      Git.git_config(set_key: "user.email", set_value: "test@test.com", config: second_cfg)

    Enum.each(changes, fn {file, content} ->
      File.write!(Path.join(second_dir, file), content)
    end)

    {:ok, :done} = Git.add(all: true, config: second_cfg)
    {:ok, _} = Git.commit("feat: remote change", config: second_cfg)
    {:ok, :done} = Git.push(config: second_cfg)
  end

  # ---------------------------------------------------------------------------
  # feature_branch
  # ---------------------------------------------------------------------------

  describe "feature_branch/3" do
    test "creates branch, runs function, returns to original branch" do
      {tmp_dir, cfg} = setup_repo("fb_basic")
      on_exit(fn -> Git.TestHelpers.rm_rf(tmp_dir) end)

      {:ok, result} =
        Git.Workflow.feature_branch(
          "feat/test",
          fn opts ->
            # We should be on the feature branch
            {:ok, current} = Git.Branches.current(opts)
            assert current == "feat/test"

            File.write!(Path.join(tmp_dir, "feature.txt"), "feature content\n")
            {:ok, :done} = Git.add(Keyword.merge(opts, files: ["feature.txt"]))
            {:ok, _} = Git.commit("feat: add feature file", Keyword.take(opts, [:config]))
            {:ok, :worked}
          end,
          config: cfg
        )

      assert result == :worked

      # Should be back on original branch
      {:ok, current} = Git.Branches.current(config: cfg)
      assert current == "main"
    end

    test "with :merge merges feature branch back" do
      {tmp_dir, cfg} = setup_repo("fb_merge")
      on_exit(fn -> Git.TestHelpers.rm_rf(tmp_dir) end)

      {:ok, merge_result} =
        Git.Workflow.feature_branch(
          "feat/merge-test",
          fn opts ->
            File.write!(Path.join(tmp_dir, "merged.txt"), "merged content\n")
            {:ok, :done} = Git.add(Keyword.merge(opts, files: ["merged.txt"]))
            {:ok, _} = Git.commit("feat: add merged file", Keyword.take(opts, [:config]))
            {:ok, :done_work}
          end,
          merge: true,
          config: cfg
        )

      # Result should be the merge result (not the fun's return)
      assert %Git.MergeResult{} = merge_result

      # Should be on main with the file present
      {:ok, current} = Git.Branches.current(config: cfg)
      assert current == "main"
      assert File.exists?(Path.join(tmp_dir, "merged.txt"))
    end

    test "with :delete removes the feature branch after merge" do
      {tmp_dir, cfg} = setup_repo("fb_delete")
      on_exit(fn -> Git.TestHelpers.rm_rf(tmp_dir) end)

      {:ok, _} =
        Git.Workflow.feature_branch(
          "feat/delete-test",
          fn opts ->
            File.write!(Path.join(tmp_dir, "deleted.txt"), "content\n")
            {:ok, :done} = Git.add(Keyword.merge(opts, files: ["deleted.txt"]))
            {:ok, _} = Git.commit("feat: add file", Keyword.take(opts, [:config]))
            {:ok, :done_work}
          end,
          merge: true,
          delete: true,
          config: cfg
        )

      # Feature branch should be gone
      {:ok, false} = Git.Branches.exists?("feat/delete-test", config: cfg)

      # File should be present on main
      assert File.exists?(Path.join(tmp_dir, "deleted.txt"))
    end

    test "returns to original branch on error" do
      {tmp_dir, cfg} = setup_repo("fb_error")
      on_exit(fn -> Git.TestHelpers.rm_rf(tmp_dir) end)

      {:error, :something_went_wrong} =
        Git.Workflow.feature_branch(
          "feat/error-test",
          fn _opts ->
            {:error, :something_went_wrong}
          end,
          config: cfg
        )

      # Should still be back on original branch
      {:ok, current} = Git.Branches.current(config: cfg)
      assert current == "main"
    end
  end

  # ---------------------------------------------------------------------------
  # sync
  # ---------------------------------------------------------------------------

  describe "sync/1" do
    test "syncs with remote using rebase strategy" do
      {tmp_dir, local_dir, remote_dir, cfg} = setup_remote_repo("sync_rebase")
      on_exit(fn -> Git.TestHelpers.rm_rf(tmp_dir) end)

      # Create a second clone that pushes a new commit
      second_dir = Path.join(tmp_dir, "second")
      File.mkdir_p!(second_dir)
      second_cfg = Config.new(working_dir: second_dir)
      System.cmd("git", ["clone", remote_dir, second_dir])

      {:ok, :done} =
        Git.git_config(set_key: "user.name", set_value: "Test User", config: second_cfg)

      {:ok, :done} =
        Git.git_config(set_key: "user.email", set_value: "test@test.com", config: second_cfg)

      File.write!(Path.join(second_dir, "remote_change.txt"), "from remote\n")
      {:ok, :done} = Git.add(files: ["remote_change.txt"], config: second_cfg)
      {:ok, _} = Git.commit("feat: remote change", config: second_cfg)
      {:ok, :done} = Git.push(config: second_cfg)

      # Now sync the first local repo
      assert {:ok, :synced} =
               Git.Workflow.sync(
                 strategy: :rebase,
                 remote: "origin",
                 branch: "main",
                 config: cfg
               )

      # The remote change should now be in the local repo
      assert File.exists?(Path.join(local_dir, "remote_change.txt"))
    end

    test "autostash stashes tracked changes and restores them on a clean pop" do
      {tmp_dir, local_dir, remote_dir, cfg} = setup_remote_repo("sync_autostash_ok")
      on_exit(fn -> Git.TestHelpers.rm_rf(tmp_dir) end)

      # Remote adds a new, unrelated file.
      push_via_second_clone(tmp_dir, remote_dir, [{"remote_change.txt", "from remote\n"}])

      # Local has an uncommitted tracked change to a different file.
      File.write!(Path.join(local_dir, "README.md"), "# Test\nlocal wip\n")

      assert {:ok, :synced} =
               Git.Workflow.sync(strategy: :rebase, remote: "origin", branch: "main", config: cfg)

      # Remote change pulled in AND the local WIP restored by the stash pop.
      assert File.exists?(Path.join(local_dir, "remote_change.txt"))
      assert File.read!(Path.join(local_dir, "README.md")) == "# Test\nlocal wip\n"
    end

    test "surfaces an autostash pop conflict instead of reporting :synced" do
      {tmp_dir, local_dir, remote_dir, cfg} = setup_remote_repo("sync_autostash_conflict")
      on_exit(fn -> Git.TestHelpers.rm_rf(tmp_dir) end)

      # Remote changes README on the line the local WIP also changes.
      push_via_second_clone(tmp_dir, remote_dir, [{"README.md", "# Test\nremote line\n"}])

      # Local has a conflicting uncommitted change to the same spot.
      File.write!(Path.join(local_dir, "README.md"), "# Test\nlocal line\n")

      assert {:error, {:autostash_pop_failed, _reason}} =
               Git.Workflow.sync(strategy: :rebase, remote: "origin", branch: "main", config: cfg)
    end

    test "an untracked-only working tree syncs without a pointless stash" do
      {tmp_dir, local_dir, remote_dir, cfg} = setup_remote_repo("sync_untracked_only")
      on_exit(fn -> Git.TestHelpers.rm_rf(tmp_dir) end)

      push_via_second_clone(tmp_dir, remote_dir, [{"remote_change.txt", "from remote\n"}])

      # Only an untracked file present (never git-added): not "dirty" for autostash.
      File.write!(Path.join(local_dir, "untracked.txt"), "keep me\n")

      assert {:ok, :synced} =
               Git.Workflow.sync(strategy: :rebase, remote: "origin", branch: "main", config: cfg)

      # The untracked file is untouched and the remote change arrived.
      assert File.read!(Path.join(local_dir, "untracked.txt")) == "keep me\n"
      assert File.exists?(Path.join(local_dir, "remote_change.txt"))
    end
  end

  # ---------------------------------------------------------------------------
  # squash_merge
  # ---------------------------------------------------------------------------

  describe "squash_merge/2" do
    test "squash merges a branch into a single commit" do
      {tmp_dir, cfg} = setup_repo("squash")
      on_exit(fn -> Git.TestHelpers.rm_rf(tmp_dir) end)

      # Create feature branch with multiple commits
      {:ok, _} = Git.checkout(branch: "feat/squash-test", create: true, config: cfg)
      File.write!(Path.join(tmp_dir, "file1.txt"), "content1\n")
      {:ok, :done} = Git.add(files: ["file1.txt"], config: cfg)
      {:ok, _} = Git.commit("feat: first commit", config: cfg)

      File.write!(Path.join(tmp_dir, "file2.txt"), "content2\n")
      {:ok, :done} = Git.add(files: ["file2.txt"], config: cfg)
      {:ok, _} = Git.commit("feat: second commit", config: cfg)

      # Go back to main
      {:ok, _} = Git.checkout(branch: "main", config: cfg)

      # Squash merge
      {:ok, commit_result} =
        Git.Workflow.squash_merge("feat/squash-test",
          message: "feat: squashed feature",
          config: cfg
        )

      assert commit_result.subject == "feat: squashed feature"

      # Both files should exist
      assert File.exists?(Path.join(tmp_dir, "file1.txt"))
      assert File.exists?(Path.join(tmp_dir, "file2.txt"))

      # History on main should have only 2 commits: initial + squashed
      {:ok, commits} = Git.log(config: cfg)
      assert length(commits) == 2
      assert hd(commits).subject == "feat: squashed feature"
    end

    test "squash merge with :delete removes the source branch" do
      {tmp_dir, cfg} = setup_repo("squash_delete")
      on_exit(fn -> Git.TestHelpers.rm_rf(tmp_dir) end)

      {:ok, _} = Git.checkout(branch: "feat/to-delete", create: true, config: cfg)
      File.write!(Path.join(tmp_dir, "squash_del.txt"), "content\n")
      {:ok, :done} = Git.add(files: ["squash_del.txt"], config: cfg)
      {:ok, _} = Git.commit("feat: commit", config: cfg)

      {:ok, _} = Git.checkout(branch: "main", config: cfg)

      {:ok, _} =
        Git.Workflow.squash_merge("feat/to-delete",
          message: "feat: squashed",
          delete: true,
          config: cfg
        )

      {:ok, false} = Git.Branches.exists?("feat/to-delete", config: cfg)
    end

    test "squash merge with :delete errors when the branch is held by a worktree" do
      {tmp_dir, cfg} = setup_repo("squash_del_held")
      on_exit(fn -> Git.TestHelpers.rm_rf(tmp_dir) end)

      {:ok, _} = Git.checkout(branch: "feat/held", create: true, config: cfg)
      File.write!(Path.join(tmp_dir, "held.txt"), "content\n")
      {:ok, :done} = Git.add(files: ["held.txt"], config: cfg)
      {:ok, _} = Git.commit("feat: work on held", config: cfg)

      {:ok, _} = Git.checkout(branch: "main", config: cfg)

      # Hold feat/held in a separate worktree so git refuses to delete it.
      wt = Path.join(tmp_dir, "wt-held")
      System.cmd("git", ["worktree", "add", wt, "feat/held"], cd: tmp_dir)

      assert {:error, {:branch_not_deleted, _reason}} =
               Git.Workflow.squash_merge("feat/held",
                 message: "feat: squashed",
                 delete: true,
                 config: cfg
               )

      # The squash commit still landed on main, and the branch was not deleted.
      {:ok, commits} = Git.log(config: cfg)
      assert hd(commits).subject == "feat: squashed"
      assert {:ok, true} = Git.Branches.exists?("feat/held", config: cfg)
    end
  end

  # ---------------------------------------------------------------------------
  # commit_all
  # ---------------------------------------------------------------------------

  describe "commit_all/2" do
    test "stages and commits all changes" do
      {tmp_dir, cfg} = setup_repo("commit_all")
      on_exit(fn -> Git.TestHelpers.rm_rf(tmp_dir) end)

      # Create multiple files without staging
      File.write!(Path.join(tmp_dir, "a.txt"), "aaa\n")
      File.write!(Path.join(tmp_dir, "b.txt"), "bbb\n")

      # Need to add them to the index first since `git commit -a` only
      # stages tracked file modifications (not new untracked files).
      # So commit_all with `add --all` handles this.
      {:ok, result} = Git.Workflow.commit_all("feat: add all files", config: cfg)

      assert result.subject == "feat: add all files"
      assert result.files_changed == 2

      # Verify files are committed
      {:ok, status} = Git.status(config: cfg)
      assert status.entries == []
    end
  end

  # ---------------------------------------------------------------------------
  # amend
  # ---------------------------------------------------------------------------

  describe "amend/1" do
    test "amends last commit with a new message" do
      {tmp_dir, cfg} = setup_repo("amend_msg")
      on_exit(fn -> Git.TestHelpers.rm_rf(tmp_dir) end)

      # Create a commit to amend
      File.write!(Path.join(tmp_dir, "amend.txt"), "content\n")
      {:ok, :done} = Git.add(files: ["amend.txt"], config: cfg)
      {:ok, _} = Git.commit("feat: original message", config: cfg)

      # Amend with new message
      {:ok, result} = Git.Workflow.amend(message: "feat: amended message", config: cfg)
      assert result.subject == "feat: amended message"

      # Verify log shows amended message
      {:ok, [latest | _]} = Git.log(max_count: 1, config: cfg)
      assert latest.subject == "feat: amended message"
    end

    test "amend without message reuses the existing message" do
      {tmp_dir, cfg} = setup_repo("amend_no_msg")
      on_exit(fn -> Git.TestHelpers.rm_rf(tmp_dir) end)

      File.write!(Path.join(tmp_dir, "amend2.txt"), "content\n")
      {:ok, :done} = Git.add(files: ["amend2.txt"], config: cfg)
      {:ok, _} = Git.commit("feat: keep this message", config: cfg)

      # Modify and stage a file, then amend without message
      File.write!(Path.join(tmp_dir, "amend2.txt"), "updated content\n")
      {:ok, :done} = Git.add(files: ["amend2.txt"], config: cfg)

      {:ok, result} = Git.Workflow.amend(config: cfg)
      assert result.subject == "feat: keep this message"
    end

    test "amend with :all stages all changes before amending" do
      {tmp_dir, cfg} = setup_repo("amend_all")
      on_exit(fn -> Git.TestHelpers.rm_rf(tmp_dir) end)

      # Create and commit a tracked file
      File.write!(Path.join(tmp_dir, "tracked.txt"), "original\n")
      {:ok, :done} = Git.add(files: ["tracked.txt"], config: cfg)
      {:ok, _} = Git.commit("feat: original", config: cfg)

      # Modify the tracked file without staging
      File.write!(Path.join(tmp_dir, "tracked.txt"), "modified\n")

      {:ok, result} =
        Git.Workflow.amend(message: "feat: amended with all", all: true, config: cfg)

      assert result.subject == "feat: amended with all"

      # Working tree should be clean
      {:ok, status} = Git.status(config: cfg)
      assert status.entries == []
    end
  end

  describe "undo_last_commit/1" do
    test "moves HEAD back one commit and keeps changes staged (soft)" do
      {tmp_dir, cfg} = setup_repo("undo_soft")
      on_exit(fn -> Git.TestHelpers.rm_rf(tmp_dir) end)

      File.write!(Path.join(tmp_dir, "a.txt"), "a\n")
      {:ok, :done} = Git.add(files: ["a.txt"], config: cfg)
      {:ok, _} = Git.commit("feat: add a", config: cfg)

      assert {:ok, [undone]} = Git.Workflow.undo_last_commit(config: cfg)
      assert undone.subject == "feat: add a"

      {:ok, commits} = Git.log(config: cfg)
      assert length(commits) == 1
      assert hd(commits).subject == "initial"

      {:ok, status} = Git.status(config: cfg)
      assert Enum.any?(status.entries, &(&1.path == "a.txt" and &1.index == "A"))
    end

    test "hard mode discards the changes" do
      {tmp_dir, cfg} = setup_repo("undo_hard")
      on_exit(fn -> Git.TestHelpers.rm_rf(tmp_dir) end)

      File.write!(Path.join(tmp_dir, "b.txt"), "b\n")
      {:ok, :done} = Git.add(files: ["b.txt"], config: cfg)
      {:ok, _} = Git.commit("feat: add b", config: cfg)

      assert {:ok, [_]} = Git.Workflow.undo_last_commit(mode: :hard, config: cfg)
      refute File.exists?(Path.join(tmp_dir, "b.txt"))
    end

    test "returns cannot_undo_root when there is not enough history" do
      {tmp_dir, cfg} = setup_repo("undo_root")
      on_exit(fn -> Git.TestHelpers.rm_rf(tmp_dir) end)

      assert {:error, :cannot_undo_root} = Git.Workflow.undo_last_commit(config: cfg)
    end
  end

  describe "squash_last/3" do
    test "collapses the last N commits into one" do
      {tmp_dir, cfg} = setup_repo("squash_last")
      on_exit(fn -> Git.TestHelpers.rm_rf(tmp_dir) end)

      File.write!(Path.join(tmp_dir, "1.txt"), "1\n")
      {:ok, :done} = Git.add(files: ["1.txt"], config: cfg)
      {:ok, _} = Git.commit("wip: one", config: cfg)
      File.write!(Path.join(tmp_dir, "2.txt"), "2\n")
      {:ok, :done} = Git.add(files: ["2.txt"], config: cfg)
      {:ok, _} = Git.commit("wip: two", config: cfg)

      assert {:ok, result} = Git.Workflow.squash_last(2, "feat: combined", config: cfg)
      assert result.subject == "feat: combined"

      {:ok, commits} = Git.log(config: cfg)
      assert Enum.map(commits, & &1.subject) == ["feat: combined", "initial"]
      assert File.exists?(Path.join(tmp_dir, "1.txt"))
      assert File.exists?(Path.join(tmp_dir, "2.txt"))
    end
  end

  describe "discard_all/1" do
    test "resets tracked changes and removes untracked files" do
      {tmp_dir, cfg} = setup_repo("discard")
      on_exit(fn -> Git.TestHelpers.rm_rf(tmp_dir) end)

      File.write!(Path.join(tmp_dir, "tracked.txt"), "v1\n")
      {:ok, :done} = Git.add(files: ["tracked.txt"], config: cfg)
      {:ok, _} = Git.commit("add tracked", config: cfg)

      File.write!(Path.join(tmp_dir, "tracked.txt"), "v2\n")
      File.write!(Path.join(tmp_dir, "untracked.txt"), "u\n")

      assert {:ok, :discarded} = Git.Workflow.discard_all(config: cfg)

      assert File.read!(Path.join(tmp_dir, "tracked.txt")) == "v1\n"
      refute File.exists?(Path.join(tmp_dir, "untracked.txt"))
    end

    test "dry_run reports what would be removed without changing anything" do
      {tmp_dir, cfg} = setup_repo("discard_dry")
      on_exit(fn -> Git.TestHelpers.rm_rf(tmp_dir) end)

      File.write!(Path.join(tmp_dir, "keep.txt"), "u\n")

      assert {:ok, {:dry_run, paths}} = Git.Workflow.discard_all(dry_run: true, config: cfg)
      assert Enum.any?(paths, &(&1 =~ "keep.txt"))
      assert File.exists?(Path.join(tmp_dir, "keep.txt"))
    end
  end

  describe "chain/2" do
    test "runs steps in order threading config and returns the last result" do
      {tmp_dir, cfg} = setup_repo("chain_ok")
      on_exit(fn -> Git.TestHelpers.rm_rf(tmp_dir) end)

      File.write!(Path.join(tmp_dir, "a.txt"), "a\n")

      assert {:ok, result} =
               Git.Workflow.chain(
                 [
                   fn o -> Git.add(Keyword.merge(o, all: true)) end,
                   fn o -> Git.commit("feat: via chain", o) end
                 ],
                 config: cfg
               )

      assert result.subject == "feat: via chain"
    end

    test "short-circuits on the first error and names a labeled step" do
      {_tmp_dir, cfg} = setup_repo("chain_err")

      assert {:error, {:boom, :nope}} =
               Git.Workflow.chain(
                 [
                   {:ok_step, fn _ -> {:ok, 1} end},
                   {:boom, fn _ -> {:error, :nope} end},
                   {:never, fn _ -> raise "should not run" end}
                 ],
                 config: cfg
               )
    end

    test "an empty list returns {:ok, nil}" do
      assert {:ok, nil} = Git.Workflow.chain([])
    end
  end

  describe "with_branch/3" do
    test "runs on the branch and restores the original branch" do
      {tmp_dir, cfg} = setup_repo("with_branch")
      on_exit(fn -> Git.TestHelpers.rm_rf(tmp_dir) end)

      assert {:ok, :ran} =
               Git.Workflow.with_branch(
                 "feat/wb",
                 fn o ->
                   {:ok, current} = Git.Branches.current(o)
                   assert current == "feat/wb"
                   {:ok, :ran}
                 end,
                 create: true,
                 config: cfg
               )

      assert {:ok, "main"} = Git.Branches.current(config: cfg)
    end

    test "restores the original branch even when the function raises" do
      {tmp_dir, cfg} = setup_repo("with_branch_raise")
      on_exit(fn -> Git.TestHelpers.rm_rf(tmp_dir) end)

      assert_raise RuntimeError, fn ->
        Git.Workflow.with_branch("feat/boom", fn _ -> raise "boom" end, create: true, config: cfg)
      end

      assert {:ok, "main"} = Git.Branches.current(config: cfg)
    end
  end

  describe "with_stash/2" do
    test "stashes tracked changes, runs on a clean tree, and restores them" do
      {tmp_dir, cfg} = setup_repo("with_stash")
      on_exit(fn -> Git.TestHelpers.rm_rf(tmp_dir) end)

      File.write!(Path.join(tmp_dir, "f.txt"), "v1\n")
      {:ok, :done} = Git.add(files: ["f.txt"], config: cfg)
      {:ok, _} = Git.commit("add f", config: cfg)
      # dirty the tracked file
      File.write!(Path.join(tmp_dir, "f.txt"), "v2\n")

      assert {:ok, :clean} =
               Git.Workflow.with_stash(
                 fn o ->
                   {:ok, status} = Git.status(o)
                   assert status.entries == []
                   {:ok, :clean}
                 end,
                 config: cfg
               )

      # the WIP change is restored after the stash pop
      assert File.read!(Path.join(tmp_dir, "f.txt")) == "v2\n"
    end
  end

  # Commits a modification to an already-tracked file.
  defp commit_change(cfg, tmp_dir, file, content, message) do
    File.write!(Path.join(tmp_dir, file), content)
    {:ok, :done} = Git.add(files: [file], config: cfg)
    {:ok, _} = Git.commit(message, config: cfg)
  end

  # ---------------------------------------------------------------------------
  # try_merge
  # ---------------------------------------------------------------------------

  describe "try_merge/2" do
    test "merges a branch cleanly and returns the merge result" do
      {tmp_dir, cfg} = setup_repo("try_merge_ok")
      on_exit(fn -> Git.TestHelpers.rm_rf(tmp_dir) end)

      {:ok, _} = Git.checkout(branch: "feature", create: true, config: cfg)
      commit_change(cfg, tmp_dir, "feature.txt", "x\n", "feat: add feature file")
      {:ok, _} = Git.checkout(branch: "main", config: cfg)

      assert {:ok, %Git.MergeResult{}} = Git.Workflow.try_merge("feature", config: cfg)
      assert File.exists?(Path.join(tmp_dir, "feature.txt"))
    end

    test "aborts a conflicting merge and returns the error on a clean tree" do
      {tmp_dir, cfg} = setup_repo("try_merge_conflict")
      on_exit(fn -> Git.TestHelpers.rm_rf(tmp_dir) end)

      commit_change(cfg, tmp_dir, "c.txt", "base\n", "add c")
      {:ok, _} = Git.checkout(branch: "other", create: true, config: cfg)
      commit_change(cfg, tmp_dir, "c.txt", "other\n", "other change")
      {:ok, _} = Git.checkout(branch: "main", config: cfg)
      commit_change(cfg, tmp_dir, "c.txt", "main\n", "main change")

      assert {:error, _reason} = Git.Workflow.try_merge("other", config: cfg)

      # The merge was aborted: the tree is clean and we are still on main.
      {:ok, status} = Git.status(config: cfg)
      assert status.entries == []
      assert {:ok, "main"} = Git.Branches.current(config: cfg)
    end
  end

  # ---------------------------------------------------------------------------
  # safe_rebase
  # ---------------------------------------------------------------------------

  describe "safe_rebase/1" do
    test "rebases cleanly onto the upstream and returns the rebase result" do
      {tmp_dir, cfg} = setup_repo("safe_rebase_ok")
      on_exit(fn -> Git.TestHelpers.rm_rf(tmp_dir) end)

      commit_change(cfg, tmp_dir, "base.txt", "base\n", "base")
      {:ok, _} = Git.checkout(branch: "topic", create: true, config: cfg)
      commit_change(cfg, tmp_dir, "topic.txt", "t\n", "topic")
      {:ok, _} = Git.checkout(branch: "main", config: cfg)
      commit_change(cfg, tmp_dir, "main.txt", "m\n", "main")
      {:ok, _} = Git.checkout(branch: "topic", config: cfg)

      assert {:ok, %Git.RebaseResult{}} = Git.Workflow.safe_rebase(upstream: "main", config: cfg)
      assert File.exists?(Path.join(tmp_dir, "main.txt"))
    end

    test "aborts a conflicting rebase and returns the error on a clean tree" do
      {tmp_dir, cfg} = setup_repo("safe_rebase_conflict")
      on_exit(fn -> Git.TestHelpers.rm_rf(tmp_dir) end)

      commit_change(cfg, tmp_dir, "c.txt", "base\n", "base")
      {:ok, _} = Git.checkout(branch: "topic", create: true, config: cfg)
      commit_change(cfg, tmp_dir, "c.txt", "topic\n", "topic change")
      {:ok, _} = Git.checkout(branch: "main", config: cfg)
      commit_change(cfg, tmp_dir, "c.txt", "main\n", "main change")
      {:ok, _} = Git.checkout(branch: "topic", config: cfg)

      assert {:error, _reason} = Git.Workflow.safe_rebase(upstream: "main", config: cfg)

      # The rebase was aborted: the tree is clean and we are back on topic.
      {:ok, status} = Git.status(config: cfg)
      assert status.entries == []
      assert {:ok, "topic"} = Git.Branches.current(config: cfg)
    end
  end

  # ---------------------------------------------------------------------------
  # release
  # ---------------------------------------------------------------------------

  describe "release/2" do
    test "creates an annotated tag without pushing by default" do
      {tmp_dir, cfg} = setup_repo("release_tag")
      on_exit(fn -> Git.TestHelpers.rm_rf(tmp_dir) end)

      assert {:ok, "v1.0.0"} =
               Git.Workflow.release("v1.0.0", message: "first release", config: cfg)

      assert {:ok, true} = Git.Tags.exists?("v1.0.0", config: cfg)

      # The tag is annotated (carries a tagger), not lightweight.
      {out, 0} =
        System.cmd("git", ["for-each-ref", "--format=%(objecttype)", "refs/tags/v1.0.0"],
          cd: tmp_dir
        )

      assert String.trim(out) == "tag"
    end

    test "refuses to clobber an existing tag" do
      {tmp_dir, cfg} = setup_repo("release_exists")
      on_exit(fn -> Git.TestHelpers.rm_rf(tmp_dir) end)

      {:ok, "v1.0.0"} = Git.Workflow.release("v1.0.0", message: "first", config: cfg)

      assert {:error, {:tag_exists, "v1.0.0"}} =
               Git.Workflow.release("v1.0.0", message: "second", config: cfg)
    end

    test "pushes the tag to the remote when :push is set" do
      {tmp_dir, _local_dir, remote_dir, cfg} = setup_remote_repo("release_push")
      on_exit(fn -> Git.TestHelpers.rm_rf(tmp_dir) end)

      assert {:ok, "v2.0.0"} =
               Git.Workflow.release("v2.0.0",
                 message: "rel",
                 push: true,
                 remote: "origin",
                 config: cfg
               )

      {out, 0} = System.cmd("git", ["ls-remote", "--tags", remote_dir])
      assert out =~ "v2.0.0"
    end
  end

  # ---------------------------------------------------------------------------
  # publish
  # ---------------------------------------------------------------------------

  describe "publish/1" do
    test "pushes the current branch to origin and sets its upstream" do
      {tmp_dir, local_dir, remote_dir, cfg} = setup_remote_repo("publish")
      on_exit(fn -> Git.TestHelpers.rm_rf(tmp_dir) end)

      {:ok, _} = Git.checkout(branch: "feature/pub", create: true, config: cfg)
      File.write!(Path.join(local_dir, "p.txt"), "p\n")
      {:ok, :done} = Git.add(files: ["p.txt"], config: cfg)
      {:ok, _} = Git.commit("feat: pub", config: cfg)

      assert {:ok, :done} = Git.Workflow.publish(config: cfg)

      {out, 0} = System.cmd("git", ["ls-remote", "--heads", remote_dir])
      assert out =~ "feature/pub"
    end
  end

  # ---------------------------------------------------------------------------
  # sync_fork
  # ---------------------------------------------------------------------------

  describe "sync_fork/1" do
    test "fetches the upstream and fast-forwards the current branch" do
      {tmp_dir, local_dir, remote_dir, cfg} = setup_remote_repo("sync_fork_merge")
      on_exit(fn -> Git.TestHelpers.rm_rf(tmp_dir) end)

      push_via_second_clone(tmp_dir, remote_dir, [{"remote_change.txt", "from upstream\n"}])

      assert {:ok, :synced} =
               Git.Workflow.sync_fork(upstream: "origin", branch: "main", config: cfg)

      assert File.exists?(Path.join(local_dir, "remote_change.txt"))
    end

    test "rebases local work onto the upstream with strategy: :rebase" do
      {tmp_dir, local_dir, remote_dir, cfg} = setup_remote_repo("sync_fork_rebase")
      on_exit(fn -> Git.TestHelpers.rm_rf(tmp_dir) end)

      push_via_second_clone(tmp_dir, remote_dir, [{"remote_change.txt", "from upstream\n"}])

      File.write!(Path.join(local_dir, "local.txt"), "local\n")
      {:ok, :done} = Git.add(files: ["local.txt"], config: cfg)
      {:ok, _} = Git.commit("feat: local work", config: cfg)

      assert {:ok, :synced} =
               Git.Workflow.sync_fork(
                 upstream: "origin",
                 branch: "main",
                 strategy: :rebase,
                 config: cfg
               )

      assert File.exists?(Path.join(local_dir, "remote_change.txt"))
      assert File.exists?(Path.join(local_dir, "local.txt"))
    end
  end

  # ---------------------------------------------------------------------------
  # backport
  # ---------------------------------------------------------------------------

  describe "backport/2" do
    test "cherry-picks a commit onto a new branch and returns to the original" do
      {tmp_dir, cfg} = setup_repo("backport_ok")
      on_exit(fn -> Git.TestHelpers.rm_rf(tmp_dir) end)

      commit_change(cfg, tmp_dir, "base.txt", "base\n", "base")
      {:ok, _} = Git.checkout(branch: "feature", create: true, config: cfg)
      commit_change(cfg, tmp_dir, "fix.txt", "fix\n", "fix: important")
      {:ok, fix_sha} = Git.rev_parse(ref: "HEAD", config: cfg)
      {:ok, _} = Git.checkout(branch: "main", config: cfg)

      assert {:ok, %Git.CherryPickResult{}} =
               Git.Workflow.backport(fix_sha, target: "release/1.x", base: "main", config: cfg)

      # Returned to the original branch.
      assert {:ok, "main"} = Git.Branches.current(config: cfg)

      # The fix landed on the release branch.
      {:ok, _} = Git.checkout(branch: "release/1.x", config: cfg)
      assert File.exists?(Path.join(tmp_dir, "fix.txt"))
    end

    test "aborts a conflicting cherry-pick and restores the original branch" do
      {tmp_dir, cfg} = setup_repo("backport_conflict")
      on_exit(fn -> Git.TestHelpers.rm_rf(tmp_dir) end)

      commit_change(cfg, tmp_dir, "c.txt", "base\n", "base")
      {:ok, _} = Git.checkout(branch: "feature", create: true, config: cfg)
      commit_change(cfg, tmp_dir, "c.txt", "feature\n", "feat: change c")
      {:ok, fix_sha} = Git.rev_parse(ref: "HEAD", config: cfg)
      {:ok, _} = Git.checkout(branch: "main", config: cfg)

      # A pre-existing release branch with a conflicting change to the same file.
      {:ok, _} = Git.checkout(branch: "release", create: true, config: cfg)
      commit_change(cfg, tmp_dir, "c.txt", "release\n", "release change")
      {:ok, _} = Git.checkout(branch: "main", config: cfg)

      assert {:error, _reason} = Git.Workflow.backport(fix_sha, target: "release", config: cfg)

      # The cherry-pick was aborted and we are back on main with a clean tree.
      assert {:ok, "main"} = Git.Branches.current(config: cfg)
      {:ok, status} = Git.status(config: cfg)
      assert status.entries == []
    end
  end

  # ---------------------------------------------------------------------------
  # restore_branch
  # ---------------------------------------------------------------------------

  describe "restore_branch/2" do
    test "recreates a deleted branch from the reflog at its last tip" do
      {tmp_dir, cfg} = setup_repo("restore_reflog")
      on_exit(fn -> Git.TestHelpers.rm_rf(tmp_dir) end)

      {:ok, _} = Git.checkout(branch: "feature", create: true, config: cfg)
      commit_change(cfg, tmp_dir, "f.txt", "f\n", "feat: work")
      {:ok, feature_sha} = Git.rev_parse(ref: "HEAD", config: cfg)
      {:ok, _} = Git.checkout(branch: "main", config: cfg)
      {:ok, _} = Git.branch(delete: "feature", force_delete: true, config: cfg)
      {:ok, false} = Git.Branches.exists?("feature", config: cfg)

      assert {:ok, ^feature_sha} = Git.Workflow.restore_branch("feature", config: cfg)
      assert {:ok, true} = Git.Branches.exists?("feature", config: cfg)
      assert {:ok, ^feature_sha} = Git.rev_parse(ref: "feature", config: cfg)
    end

    test "checks out the restored branch when :checkout is set" do
      {tmp_dir, cfg} = setup_repo("restore_checkout")
      on_exit(fn -> Git.TestHelpers.rm_rf(tmp_dir) end)

      {:ok, _} = Git.checkout(branch: "feature", create: true, config: cfg)
      commit_change(cfg, tmp_dir, "f.txt", "f\n", "feat: work")
      {:ok, _} = Git.checkout(branch: "main", config: cfg)
      {:ok, _} = Git.branch(delete: "feature", force_delete: true, config: cfg)

      assert {:ok, _sha} = Git.Workflow.restore_branch("feature", checkout: true, config: cfg)
      assert {:ok, "feature"} = Git.Branches.current(config: cfg)
    end

    test "recreates a branch at an explicit :sha" do
      {tmp_dir, cfg} = setup_repo("restore_sha")
      on_exit(fn -> Git.TestHelpers.rm_rf(tmp_dir) end)

      commit_change(cfg, tmp_dir, "a.txt", "a\n", "add a")
      {:ok, head_sha} = Git.rev_parse(ref: "HEAD", config: cfg)

      assert {:ok, ^head_sha} =
               Git.Workflow.restore_branch("rescued", sha: head_sha, config: cfg)

      assert {:ok, ^head_sha} = Git.rev_parse(ref: "rescued", config: cfg)
    end

    test "returns :not_found when the reflog has no record of the branch" do
      {tmp_dir, cfg} = setup_repo("restore_notfound")
      on_exit(fn -> Git.TestHelpers.rm_rf(tmp_dir) end)

      assert {:error, :not_found} = Git.Workflow.restore_branch("never-existed", config: cfg)
    end
  end
end
