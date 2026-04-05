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

  # ---------------------------------------------------------------------------
  # feature_branch
  # ---------------------------------------------------------------------------

  describe "feature_branch/3" do
    test "creates branch, runs function, returns to original branch" do
      {tmp_dir, cfg} = setup_repo("fb_basic")
      on_exit(fn -> File.rm_rf!(tmp_dir) end)

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
      on_exit(fn -> File.rm_rf!(tmp_dir) end)

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
      on_exit(fn -> File.rm_rf!(tmp_dir) end)

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
      on_exit(fn -> File.rm_rf!(tmp_dir) end)

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
      on_exit(fn -> File.rm_rf!(tmp_dir) end)

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
  end

  # ---------------------------------------------------------------------------
  # squash_merge
  # ---------------------------------------------------------------------------

  describe "squash_merge/2" do
    test "squash merges a branch into a single commit" do
      {tmp_dir, cfg} = setup_repo("squash")
      on_exit(fn -> File.rm_rf!(tmp_dir) end)

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
      on_exit(fn -> File.rm_rf!(tmp_dir) end)

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
  end

  # ---------------------------------------------------------------------------
  # commit_all
  # ---------------------------------------------------------------------------

  describe "commit_all/2" do
    test "stages and commits all changes" do
      {tmp_dir, cfg} = setup_repo("commit_all")
      on_exit(fn -> File.rm_rf!(tmp_dir) end)

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
      on_exit(fn -> File.rm_rf!(tmp_dir) end)

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
      on_exit(fn -> File.rm_rf!(tmp_dir) end)

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
      on_exit(fn -> File.rm_rf!(tmp_dir) end)

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
end
