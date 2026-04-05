defmodule Git.WorkflowsTest do
  use ExUnit.Case, async: true

  alias Git.Config
  alias Git.Repo

  defp setup_repo(name) do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "git_workflow_#{name}_#{:erlang.unique_integer([:positive])}"
      )

    File.mkdir_p!(tmp_dir)
    System.cmd("git", ["init", "--initial-branch=main"], cd: tmp_dir)
    System.cmd("git", ["config", "user.name", "Test User"], cd: tmp_dir)
    System.cmd("git", ["config", "user.email", "test@test.com"], cd: tmp_dir)
    System.cmd("git", ["commit", "--allow-empty", "-m", "initial"], cd: tmp_dir)
    tmp_dir
  end

  defp setup_remote_repo(name) do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "git_workflow_#{name}_#{:erlang.unique_integer([:positive])}"
      )

    File.mkdir_p!(tmp_dir)

    remote_dir = Path.join(tmp_dir, "remote.git")
    File.mkdir_p!(remote_dir)
    System.cmd("git", ["init", "--bare", "--initial-branch=main"], cd: remote_dir)

    local_dir = Path.join(tmp_dir, "local")
    File.mkdir_p!(local_dir)
    System.cmd("git", ["init", "--initial-branch=main"], cd: local_dir)
    System.cmd("git", ["config", "user.name", "Test User"], cd: local_dir)
    System.cmd("git", ["config", "user.email", "test@test.com"], cd: local_dir)
    System.cmd("git", ["remote", "add", "origin", remote_dir], cd: local_dir)
    File.write!(Path.join(local_dir, "README.md"), "# Test\n")
    System.cmd("git", ["add", "."], cd: local_dir)
    System.cmd("git", ["commit", "-m", "initial"], cd: local_dir)
    System.cmd("git", ["push", "-u", "origin", "main"], cd: local_dir)

    {tmp_dir, local_dir, remote_dir}
  end

  defp config(dir) do
    Config.new(working_dir: dir)
  end

  # ---------------------------------------------------------------------------
  # 1. Basic development workflow
  # ---------------------------------------------------------------------------

  describe "basic development workflow" do
    test "create, add, commit, then modify and commit again" do
      dir = setup_repo("basic_dev")
      on_exit(fn -> File.rm_rf!(dir) end)
      cfg = config(dir)

      # Create a file, add, commit
      File.write!(Path.join(dir, "hello.txt"), "hello world\n")
      assert {:ok, :done} = Git.add(files: ["hello.txt"], config: cfg)
      assert {:ok, result} = Git.commit("feat: add hello file", config: cfg)
      assert result.subject == "feat: add hello file"
      assert result.files_changed == 1

      # Modify file, check status, add, commit
      File.write!(Path.join(dir, "hello.txt"), "hello world\nupdated\n")
      {:ok, status} = Git.status(config: cfg)
      modified_paths = Enum.map(status.entries, & &1.path)
      assert "hello.txt" in modified_paths

      assert {:ok, :done} = Git.add(files: ["hello.txt"], config: cfg)
      assert {:ok, _} = Git.commit("fix: update hello file", config: cfg)

      # Verify log has 3 commits: initial + 2
      {:ok, commits} = Git.log(config: cfg)
      assert length(commits) == 3
      subjects = Enum.map(commits, & &1.subject)
      assert hd(subjects) == "fix: update hello file"
      assert Enum.at(subjects, 1) == "feat: add hello file"
      assert Enum.at(subjects, 2) == "initial"
    end
  end

  # ---------------------------------------------------------------------------
  # 2. Branch and merge workflow
  # ---------------------------------------------------------------------------

  describe "branch and merge workflow" do
    test "create feature branch, commit, merge back to main" do
      dir = setup_repo("branch_merge")
      on_exit(fn -> File.rm_rf!(dir) end)
      cfg = config(dir)

      # Create and checkout feature branch
      assert {:ok, _} = Git.checkout(branch: "feature/add-file", create: true, config: cfg)

      # Add file and commit on feature branch
      File.write!(Path.join(dir, "feature.txt"), "feature content\n")
      assert {:ok, :done} = Git.add(files: ["feature.txt"], config: cfg)
      assert {:ok, _} = Git.commit("feat: add feature file", config: cfg)

      # Checkout main, verify file doesn't exist
      assert {:ok, _} = Git.checkout(branch: "main", config: cfg)
      refute File.exists?(Path.join(dir, "feature.txt"))

      # Merge feature branch, verify file exists
      assert {:ok, merge_result} = Git.merge("feature/add-file", config: cfg)
      assert merge_result.fast_forward == true
      assert File.exists?(Path.join(dir, "feature.txt"))

      # Verify log shows the feature commit
      {:ok, commits} = Git.log(config: cfg)
      subjects = Enum.map(commits, & &1.subject)
      assert "feat: add feature file" in subjects
    end
  end

  # ---------------------------------------------------------------------------
  # 3. Remote push and clone workflow
  # ---------------------------------------------------------------------------

  describe "remote push and clone workflow" do
    test "push to remote, clone elsewhere, verify content" do
      {tmp_dir, local_dir, remote_dir} = setup_remote_repo("push_clone")
      on_exit(fn -> File.rm_rf!(tmp_dir) end)
      cfg = config(local_dir)

      # Create file, add, commit, push
      File.write!(Path.join(local_dir, "pushed.txt"), "pushed content\n")
      assert {:ok, :done} = Git.add(files: ["pushed.txt"], config: cfg)
      assert {:ok, _} = Git.commit("feat: add pushed file", config: cfg)
      assert {:ok, :done} = Git.push(config: cfg)

      # Clone the remote into a second directory
      clone_dir = Path.join(tmp_dir, "clone")

      assert {:ok, repo} =
               Repo.clone(remote_dir, clone_dir, branch: "main")

      # Verify the cloned repo has the file and commit
      assert File.exists?(Path.join(clone_dir, "pushed.txt"))
      assert File.read!(Path.join(clone_dir, "pushed.txt")) == "pushed content\n"

      {:ok, commits} = Repo.log(repo)
      subjects = Enum.map(commits, & &1.subject)
      assert "feat: add pushed file" in subjects
    end
  end

  # ---------------------------------------------------------------------------
  # 4. Fetch and pull workflow
  # ---------------------------------------------------------------------------

  describe "fetch and pull workflow" do
    test "push from second clone, fetch and pull in first" do
      {tmp_dir, local_dir, remote_dir} = setup_remote_repo("fetch_pull")
      on_exit(fn -> File.rm_rf!(tmp_dir) end)

      # Clone to a second local dir
      second_dir = Path.join(tmp_dir, "second")

      System.cmd("git", ["clone", "--branch", "main", remote_dir, second_dir])
      System.cmd("git", ["config", "user.name", "Test User"], cd: second_dir)
      System.cmd("git", ["config", "user.email", "test@test.com"], cd: second_dir)

      # In second dir: create file, commit, push
      File.write!(Path.join(second_dir, "from_second.txt"), "second content\n")
      System.cmd("git", ["add", "."], cd: second_dir)
      System.cmd("git", ["commit", "-m", "feat: from second"], cd: second_dir)
      System.cmd("git", ["push"], cd: second_dir)

      # In first dir: fetch
      cfg = config(local_dir)
      assert {:ok, :done} = Git.fetch(config: cfg)

      # Verify remote tracking is updated (the file isn't in working tree yet)
      refute File.exists?(Path.join(local_dir, "from_second.txt"))

      # Pull and verify file exists
      assert {:ok, _pull_result} = Git.pull(config: cfg)
      assert File.exists?(Path.join(local_dir, "from_second.txt"))
      assert File.read!(Path.join(local_dir, "from_second.txt")) == "second content\n"
    end
  end

  # ---------------------------------------------------------------------------
  # 5. Rebase workflow
  # ---------------------------------------------------------------------------

  describe "rebase workflow" do
    test "rebase feature branch onto main for linear history" do
      dir = setup_repo("rebase")
      on_exit(fn -> File.rm_rf!(dir) end)
      cfg = config(dir)

      # Create feature branch and add a commit
      assert {:ok, _} = Git.checkout(branch: "feature/rebase-test", create: true, config: cfg)
      File.write!(Path.join(dir, "feature.txt"), "feature\n")
      assert {:ok, :done} = Git.add(files: ["feature.txt"], config: cfg)
      assert {:ok, _} = Git.commit("feat: feature commit", config: cfg)

      # Switch to main, add a different commit (diverge)
      assert {:ok, _} = Git.checkout(branch: "main", config: cfg)
      File.write!(Path.join(dir, "main.txt"), "main\n")
      assert {:ok, :done} = Git.add(files: ["main.txt"], config: cfg)
      assert {:ok, _} = Git.commit("feat: main commit", config: cfg)

      # Switch to feature, rebase onto main
      assert {:ok, _} = Git.checkout(branch: "feature/rebase-test", config: cfg)
      assert {:ok, rebase_result} = Git.rebase(upstream: "main", config: cfg)
      refute rebase_result.conflicts

      # Verify both files exist
      assert File.exists?(Path.join(dir, "feature.txt"))
      assert File.exists?(Path.join(dir, "main.txt"))

      # Verify linear history (no merge commits) - all commits should have single parents
      {:ok, commits} = Git.log(config: cfg)
      # Should have: feature commit, main commit, initial = 3 commits (linear)
      assert length(commits) == 3
      subjects = Enum.map(commits, & &1.subject)
      assert hd(subjects) == "feat: feature commit"
      assert Enum.at(subjects, 1) == "feat: main commit"
    end
  end

  # ---------------------------------------------------------------------------
  # 6. Stash workflow
  # ---------------------------------------------------------------------------

  describe "stash workflow" do
    test "stash save and pop round-trip" do
      dir = setup_repo("stash")
      on_exit(fn -> File.rm_rf!(dir) end)
      cfg = config(dir)

      # Create and commit a file so it's tracked
      File.write!(Path.join(dir, "tracked.txt"), "original\n")
      assert {:ok, :done} = Git.add(files: ["tracked.txt"], config: cfg)
      assert {:ok, _} = Git.commit("feat: add tracked file", config: cfg)

      # Modify it (don't stage)
      File.write!(Path.join(dir, "tracked.txt"), "modified\n")

      # Stash save
      assert {:ok, :done} = Git.stash(save: true, message: "wip changes", config: cfg)

      # Verify working tree is clean
      {:ok, status} = Git.status(config: cfg)
      assert status.entries == []

      # File should have original content
      assert File.read!(Path.join(dir, "tracked.txt")) == "original\n"

      # Stash pop
      assert {:ok, :done} = Git.stash(pop: true, config: cfg)

      # Verify file is back with modifications
      assert File.read!(Path.join(dir, "tracked.txt")) == "modified\n"

      # Verify stash list is empty after pop
      {:ok, stash_list} = Git.stash(config: cfg)
      assert stash_list == []
    end
  end

  # ---------------------------------------------------------------------------
  # 7. Tag and release workflow
  # ---------------------------------------------------------------------------

  describe "tag and release workflow" do
    test "conventional commits with tags and changelog" do
      dir = setup_repo("tag_release")
      on_exit(fn -> File.rm_rf!(dir) end)
      cfg = config(dir)

      # First feature commit
      File.write!(Path.join(dir, "login.txt"), "login feature\n")
      assert {:ok, :done} = Git.add(files: ["login.txt"], config: cfg)
      assert {:ok, _} = Git.commit("feat: add login", config: cfg)

      # Tag v1.0.0
      assert {:ok, :done} = Git.tag(create: "v1.0.0", message: "Release v1.0.0", config: cfg)

      # Fix commit
      File.write!(Path.join(dir, "login.txt"), "login feature\nhandle nil\n")
      assert {:ok, :done} = Git.add(files: ["login.txt"], config: cfg)
      assert {:ok, _} = Git.commit("fix: handle nil", config: cfg)

      # Docs commit
      File.write!(Path.join(dir, "readme.txt"), "updated readme\n")
      assert {:ok, :done} = Git.add(files: ["readme.txt"], config: cfg)
      assert {:ok, _} = Git.commit("docs: update readme", config: cfg)

      # Tag v1.1.0
      assert {:ok, :done} = Git.tag(create: "v1.1.0", message: "Release v1.1.0", config: cfg)

      # Verify commits between tags
      {:ok, commits} = Git.History.commits_between("v1.0.0", "v1.1.0", config: cfg)
      assert length(commits) == 2
      subjects = Enum.map(commits, & &1.subject)
      assert "fix: handle nil" in subjects
      assert "docs: update readme" in subjects

      # Verify changelog grouping
      {:ok, changelog} = Git.History.changelog("v1.0.0", "v1.1.0", config: cfg)
      assert length(changelog.fixes) == 1
      assert hd(changelog.fixes).subject == "fix: handle nil"
      assert length(changelog.other) == 1
      assert hd(changelog.other).subject == "docs: update readme"
      assert changelog.features == []
    end
  end

  # ---------------------------------------------------------------------------
  # 8. Branch management workflow
  # ---------------------------------------------------------------------------

  describe "branch management workflow" do
    test "create branches, merge some, clean up merged" do
      dir = setup_repo("branch_mgmt")
      on_exit(fn -> File.rm_rf!(dir) end)
      cfg = config(dir)

      # Create several branches with commits
      for name <- ["feature/a", "feature/b", "feature/c"] do
        assert {:ok, _} = Git.checkout(branch: name, create: true, config: cfg)
        File.write!(Path.join(dir, "#{Path.basename(name)}.txt"), "content\n")
        assert {:ok, :done} = Git.add(all: true, config: cfg)
        assert {:ok, _} = Git.commit("feat: add #{Path.basename(name)}", config: cfg)
        assert {:ok, _} = Git.checkout(branch: "main", config: cfg)
      end

      # Merge feature/a and feature/b into main
      assert {:ok, _} = Git.merge("feature/a", config: cfg)
      assert {:ok, _} = Git.merge("feature/b", config: cfg)

      # List merged branches
      {:ok, merged} = Git.Branches.merged(config: cfg)
      merged_names = Enum.map(merged, & &1.name)
      assert "feature/a" in merged_names
      assert "feature/b" in merged_names
      refute "feature/c" in merged_names

      # Preview cleanup (dry run)
      {:ok, dry_run_list} =
        Git.Branches.cleanup_merged(config: cfg, dry_run: true)

      assert "feature/a" in dry_run_list
      assert "feature/b" in dry_run_list
      refute "feature/c" in dry_run_list

      # Actually clean up
      {:ok, deleted} = Git.Branches.cleanup_merged(config: cfg)
      assert "feature/a" in deleted
      assert "feature/b" in deleted

      # Verify deleted branches no longer exist
      {:ok, false} = Git.Branches.exists?("feature/a", config: cfg)
      {:ok, false} = Git.Branches.exists?("feature/b", config: cfg)
      {:ok, true} = Git.Branches.exists?("feature/c", config: cfg)
    end
  end

  # ---------------------------------------------------------------------------
  # 9. Git.Repo pipeline workflow
  # ---------------------------------------------------------------------------

  describe "Git.Repo pipeline workflow" do
    test "open, add, commit, verify via log" do
      dir = setup_repo("repo_pipeline")
      on_exit(fn -> File.rm_rf!(dir) end)

      # Open the repo
      assert {:ok, repo} = Repo.open(dir)

      # Create a file
      File.write!(Path.join(dir, "pipeline.txt"), "pipeline content\n")

      # Chain: add -> commit -> verify
      assert {:ok, :done} = Repo.add(repo, files: ["pipeline.txt"])
      assert {:ok, commit_result} = Repo.commit(repo, "feat: pipeline commit")
      assert commit_result.subject == "feat: pipeline commit"

      {:ok, commits} = Repo.log(repo)
      assert length(commits) == 2
      assert hd(commits).subject == "feat: pipeline commit"
    end

    test "Repo.run pipeline short-circuits on error" do
      dir = setup_repo("repo_pipeline_error")
      on_exit(fn -> File.rm_rf!(dir) end)

      result =
        Repo.open(dir)
        |> Repo.run(fn repo ->
          # Commit with nothing staged should fail
          Repo.commit(repo, "should fail")
        end)
        |> Repo.run(fn repo ->
          # This should never execute
          Repo.commit(repo, "should not reach here")
        end)

      assert {:error, _} = result
    end
  end

  # ---------------------------------------------------------------------------
  # 10. Blame and show workflow
  # ---------------------------------------------------------------------------

  describe "blame and show workflow" do
    test "blame maps lines to correct commits, show displays commit" do
      dir = setup_repo("blame_show")
      on_exit(fn -> File.rm_rf!(dir) end)
      cfg = config(dir)

      # Create file with content, commit
      File.write!(Path.join(dir, "blamed.txt"), "line one\n")
      assert {:ok, :done} = Git.add(files: ["blamed.txt"], config: cfg)
      assert {:ok, first_commit} = Git.commit("feat: first version", config: cfg)

      # Modify file, commit with different message
      File.write!(Path.join(dir, "blamed.txt"), "line one\nline two\n")
      assert {:ok, :done} = Git.add(files: ["blamed.txt"], config: cfg)
      assert {:ok, second_commit} = Git.commit("feat: add second line", config: cfg)

      # Blame the file
      {:ok, blame_entries} = Git.blame("blamed.txt", config: cfg)
      assert length(blame_entries) == 2

      # First line should be from the first commit
      first_entry = Enum.at(blame_entries, 0)
      assert first_entry.content =~ "line one"
      assert String.starts_with?(first_commit.hash, String.slice(first_entry.commit, 0, 7))

      # Second line should be from the second commit
      second_entry = Enum.at(blame_entries, 1)
      assert second_entry.content =~ "line two"
      assert String.starts_with?(second_commit.hash, String.slice(second_entry.commit, 0, 7))

      # Show a specific commit
      {:ok, show_result} = Git.show(ref: second_commit.hash, config: cfg)
      assert show_result.commit != nil
      assert show_result.commit.subject == "feat: add second line"
    end
  end

  # ---------------------------------------------------------------------------
  # 11. Conflict detection workflow
  # ---------------------------------------------------------------------------

  describe "conflict detection workflow" do
    test "detect merge conflict and abort" do
      dir = setup_repo("conflict")
      on_exit(fn -> File.rm_rf!(dir) end)
      cfg = config(dir)

      # Create a file on main
      File.write!(Path.join(dir, "conflict.txt"), "original\n")
      assert {:ok, :done} = Git.add(files: ["conflict.txt"], config: cfg)
      assert {:ok, _} = Git.commit("feat: add conflict file", config: cfg)

      # Create feature branch, modify the file, commit
      assert {:ok, _} = Git.checkout(branch: "feature/conflict", create: true, config: cfg)
      File.write!(Path.join(dir, "conflict.txt"), "feature change\n")
      assert {:ok, :done} = Git.add(files: ["conflict.txt"], config: cfg)
      assert {:ok, _} = Git.commit("feat: feature change", config: cfg)

      # Switch to main, modify same file differently, commit
      assert {:ok, _} = Git.checkout(branch: "main", config: cfg)
      File.write!(Path.join(dir, "conflict.txt"), "main change\n")
      assert {:ok, :done} = Git.add(files: ["conflict.txt"], config: cfg)
      assert {:ok, _} = Git.commit("feat: main change", config: cfg)

      # Attempt merge - should fail with conflict
      result = Git.merge("feature/conflict", config: cfg)
      assert {:error, _} = result

      # Abort merge, verify clean state
      assert {:ok, :done} = Git.merge(:abort, config: cfg)
      {:ok, status} = Git.status(config: cfg)
      assert status.entries == []
      assert File.read!(Path.join(dir, "conflict.txt")) == "main change\n"
    end
  end

  # ---------------------------------------------------------------------------
  # 12. Hooks lifecycle workflow
  # ---------------------------------------------------------------------------

  describe "hooks lifecycle workflow" do
    test "write, enable, disable, remove a hook" do
      dir = setup_repo("hooks")
      on_exit(fn -> File.rm_rf!(dir) end)
      cfg = config(dir)

      hook_content = """
      #!/bin/sh
      touch "#{dir}/hook-marker"
      """

      # Write a pre-commit hook
      {:ok, hook_path} =
        Git.Hooks.write("pre-commit", hook_content, config: cfg)

      assert File.exists?(hook_path)

      # Verify hook exists and is enabled
      {:ok, true} = Git.Hooks.exists?("pre-commit", config: cfg)
      {:ok, true} = Git.Hooks.enabled?("pre-commit", config: cfg)

      # Verify it appears in the list
      {:ok, hooks} = Git.Hooks.list(config: cfg)
      hook_entry = Enum.find(hooks, &(&1.name == "pre-commit"))
      assert hook_entry != nil
      assert hook_entry.enabled == true

      # Disable the hook
      {:ok, _} = Git.Hooks.disable("pre-commit", config: cfg)
      {:ok, false} = Git.Hooks.enabled?("pre-commit", config: cfg)

      # Re-enable
      {:ok, _} = Git.Hooks.enable("pre-commit", config: cfg)
      {:ok, true} = Git.Hooks.enabled?("pre-commit", config: cfg)

      # Remove the hook
      :ok = Git.Hooks.remove("pre-commit", config: cfg)
      {:ok, false} = Git.Hooks.exists?("pre-commit", config: cfg)

      # Verify it's gone from the list
      {:ok, hooks_after} = Git.Hooks.list(config: cfg)
      assert Enum.find(hooks_after, &(&1.name == "pre-commit")) == nil
    end
  end
end
