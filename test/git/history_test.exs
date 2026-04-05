defmodule Git.HistoryTest do
  use ExUnit.Case, async: true

  # ---------------------------------------------------------------------------
  # Test helpers
  # ---------------------------------------------------------------------------

  @git_env [
    {"GIT_AUTHOR_NAME", "Test User"},
    {"GIT_AUTHOR_EMAIL", "test@example.com"},
    {"GIT_COMMITTER_NAME", "Test User"},
    {"GIT_COMMITTER_EMAIL", "test@example.com"}
  ]

  defp setup_repo do
    dir =
      Path.join(
        System.tmp_dir!(),
        "git_history_test_#{:erlang.unique_integer([:positive])}"
      )

    File.mkdir_p!(dir)
    System.cmd("git", ["init", "--initial-branch=main"], cd: dir)
    System.cmd("git", ["config", "user.email", "test@example.com"], cd: dir)
    System.cmd("git", ["config", "user.name", "Test User"], cd: dir)

    on_exit(fn -> File.rm_rf!(dir) end)
    config = Git.Config.new(working_dir: dir, env: @git_env)
    {config, dir}
  end

  defp git_commit(dir, msg) do
    System.cmd("git", ["commit", "--allow-empty", "-m", msg], cd: dir, env: @git_env)
  end

  defp write_and_commit(dir, filename, content, msg) do
    File.write!(Path.join(dir, filename), content)
    System.cmd("git", ["add", filename], cd: dir)
    git_commit(dir, msg)
  end

  defp create_tag(dir, tag) do
    System.cmd("git", ["tag", tag], cd: dir)
  end

  # ---------------------------------------------------------------------------
  # commits_between/3
  # ---------------------------------------------------------------------------

  describe "commits_between/3" do
    test "returns commits between two tags" do
      {config, dir} = setup_repo()
      git_commit(dir, "feat: initial commit")
      create_tag(dir, "v1.0.0")

      git_commit(dir, "feat: add feature A")
      git_commit(dir, "fix: correct typo")
      create_tag(dir, "v2.0.0")

      assert {:ok, commits} = Git.History.commits_between("v1.0.0", "v2.0.0", config: config)
      assert length(commits) == 2
      subjects = Enum.map(commits, & &1.subject)
      assert "feat: add feature A" in subjects
      assert "fix: correct typo" in subjects
    end

    test "returns empty list when refs are identical" do
      {config, dir} = setup_repo()
      git_commit(dir, "feat: initial commit")
      create_tag(dir, "v1.0.0")

      assert {:ok, []} = Git.History.commits_between("v1.0.0", "v1.0.0", config: config)
    end
  end

  # ---------------------------------------------------------------------------
  # files_changed_since/2
  # ---------------------------------------------------------------------------

  describe "files_changed_since/2" do
    test "lists files changed since a ref" do
      {config, dir} = setup_repo()
      write_and_commit(dir, "first.txt", "hello\n", "feat: add first")
      create_tag(dir, "v1.0.0")

      write_and_commit(dir, "second.txt", "world\n", "feat: add second")
      write_and_commit(dir, "third.txt", "foo\n", "feat: add third")

      assert {:ok, files} = Git.History.files_changed_since("v1.0.0", config: config)
      assert "second.txt" in files
      assert "third.txt" in files
      refute "first.txt" in files
    end

    test "returns empty list when nothing changed" do
      {config, dir} = setup_repo()
      write_and_commit(dir, "file.txt", "content\n", "feat: add file")
      create_tag(dir, "v1.0.0")

      assert {:ok, []} = Git.History.files_changed_since("v1.0.0", config: config)
    end
  end

  # ---------------------------------------------------------------------------
  # contributors/1
  # ---------------------------------------------------------------------------

  describe "contributors/1" do
    test "returns unique contributors with commit counts" do
      {config, dir} = setup_repo()
      git_commit(dir, "feat: first")
      git_commit(dir, "feat: second")

      # Add a commit with a different author
      System.cmd(
        "git",
        ["commit", "--allow-empty", "-m", "feat: other work"],
        cd: dir,
        env: [
          {"GIT_AUTHOR_NAME", "Other Dev"},
          {"GIT_AUTHOR_EMAIL", "other@example.com"},
          {"GIT_COMMITTER_NAME", "Other Dev"},
          {"GIT_COMMITTER_EMAIL", "other@example.com"}
        ]
      )

      assert {:ok, contributors} = Git.History.contributors(config: config)
      assert length(contributors) == 2

      test_user = Enum.find(contributors, &(&1.email == "test@example.com"))
      other_user = Enum.find(contributors, &(&1.email == "other@example.com"))

      assert test_user.commit_count == 2
      assert test_user.name == "Test User"
      assert other_user.commit_count == 1
      assert other_user.name == "Other Dev"
    end

    test "respects :path filter" do
      {config, dir} = setup_repo()
      File.mkdir_p!(Path.join(dir, "lib"))
      write_and_commit(dir, "lib/app.ex", "defmodule App, do: :ok\n", "feat: add app")
      write_and_commit(dir, "README.md", "# Hello\n", "docs: add readme")

      assert {:ok, contributors} = Git.History.contributors(config: config, path: "lib/")
      assert length(contributors) == 1
      assert hd(contributors).commit_count == 1
    end

    test "respects :since filter" do
      {config, dir} = setup_repo()
      git_commit(dir, "feat: old commit")

      assert {:ok, contributors} =
               Git.History.contributors(config: config, since: "1 second ago")

      total = Enum.reduce(contributors, 0, fn c, acc -> acc + c.commit_count end)
      assert total >= 1
    end
  end

  # ---------------------------------------------------------------------------
  # changelog/3
  # ---------------------------------------------------------------------------

  describe "changelog/3" do
    test "groups commits by conventional type" do
      {config, dir} = setup_repo()
      git_commit(dir, "chore: init")
      create_tag(dir, "v1.0.0")

      git_commit(dir, "feat: add user auth")
      git_commit(dir, "feat: add dashboard")
      git_commit(dir, "fix: login redirect")
      git_commit(dir, "docs: update readme")
      git_commit(dir, "refactor: clean up utils")
      create_tag(dir, "v2.0.0")

      assert {:ok, changelog} = Git.History.changelog("v1.0.0", "v2.0.0", config: config)
      assert length(changelog.features) == 2
      assert length(changelog.fixes) == 1
      # docs + refactor land in other
      assert length(changelog.other) == 2
    end

    test "returns empty groups when no commits in range" do
      {config, dir} = setup_repo()
      git_commit(dir, "feat: init")
      create_tag(dir, "v1.0.0")

      assert {:ok, changelog} = Git.History.changelog("v1.0.0", "v1.0.0", config: config)
      assert changelog.features == []
      assert changelog.fixes == []
      assert changelog.other == []
    end
  end

  # ---------------------------------------------------------------------------
  # ancestor?/3
  # ---------------------------------------------------------------------------

  describe "ancestor?/3" do
    test "returns true when ref1 is an ancestor of ref2" do
      {config, dir} = setup_repo()
      git_commit(dir, "feat: first")
      create_tag(dir, "v1.0.0")
      git_commit(dir, "feat: second")
      create_tag(dir, "v2.0.0")

      assert {:ok, true} = Git.History.ancestor?("v1.0.0", "v2.0.0", config: config)
    end

    test "returns false when ref1 is not an ancestor of ref2" do
      {config, dir} = setup_repo()
      git_commit(dir, "feat: first")
      create_tag(dir, "v1.0.0")
      git_commit(dir, "feat: second")
      create_tag(dir, "v2.0.0")

      assert {:ok, false} = Git.History.ancestor?("v2.0.0", "v1.0.0", config: config)
    end

    test "returns true when refs are the same" do
      {config, dir} = setup_repo()
      git_commit(dir, "feat: first")
      create_tag(dir, "v1.0.0")

      assert {:ok, true} = Git.History.ancestor?("v1.0.0", "v1.0.0", config: config)
    end
  end

  # ---------------------------------------------------------------------------
  # file_history/2
  # ---------------------------------------------------------------------------

  describe "file_history/2" do
    test "returns commits that touched a specific file" do
      {config, dir} = setup_repo()
      write_and_commit(dir, "app.ex", "v1\n", "feat: add app")
      write_and_commit(dir, "other.ex", "v1\n", "feat: add other")
      write_and_commit(dir, "app.ex", "v2\n", "fix: update app")

      assert {:ok, commits} = Git.History.file_history("app.ex", config: config)
      assert length(commits) == 2
      subjects = Enum.map(commits, & &1.subject)
      assert "feat: add app" in subjects
      assert "fix: update app" in subjects
      refute "feat: add other" in subjects
    end

    test "returns empty list for file with no history" do
      {config, dir} = setup_repo()
      git_commit(dir, "feat: init")

      assert {:ok, []} = Git.History.file_history("nonexistent.ex", config: config)
    end

    test "respects :max_count option" do
      {config, dir} = setup_repo()
      write_and_commit(dir, "app.ex", "v1\n", "feat: add app")
      write_and_commit(dir, "app.ex", "v2\n", "fix: update app")
      write_and_commit(dir, "app.ex", "v3\n", "feat: improve app")

      assert {:ok, commits} =
               Git.History.file_history("app.ex", config: config, max_count: 2)

      assert length(commits) == 2
    end
  end
end
