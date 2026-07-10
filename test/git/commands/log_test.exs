defmodule Git.LogTest do
  use ExUnit.Case, async: true

  alias Git.Commands.Log
  alias Git.{Commit, Config}

  setup do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "git_wrapper_log_test_#{:erlang.unique_integer([:positive])}"
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
        "first commit"
      ],
      cd: tmp_dir
    )

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
        "second commit"
      ],
      cd: tmp_dir
    )

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
        "third commit"
      ],
      cd: tmp_dir
    )

    on_exit(fn -> Git.TestHelpers.rm_rf(tmp_dir) end)
    %{tmp_dir: tmp_dir, config: Config.new(working_dir: tmp_dir)}
  end

  describe "log/1" do
    test "returns a list of Commit structs", %{config: config} do
      assert {:ok, commits} = Git.log(config: config)
      assert is_list(commits)
      assert length(commits) == 3

      Enum.each(commits, fn commit ->
        assert %Commit{} = commit
      end)
    end

    test "commits have expected fields populated", %{config: config} do
      assert {:ok, [latest | _]} = Git.log(config: config)

      assert latest.subject == "third commit"
      assert String.length(latest.hash) == 40
      assert String.match?(latest.hash, ~r/^[0-9a-f]{40}$/)
      assert String.length(latest.abbreviated_hash) > 0
      assert latest.author_name == "Test User"
      assert latest.author_email == "test@test.com"
      # ISO 8601 date format
      assert String.match?(latest.date, ~r/^\d{4}-\d{2}-\d{2}T/)
    end

    test "commits are in reverse chronological order", %{config: config} do
      assert {:ok, commits} = Git.log(config: config)
      subjects = Enum.map(commits, & &1.subject)
      assert subjects == ["third commit", "second commit", "first commit"]
    end

    test "max_count limits the number of results", %{config: config} do
      assert {:ok, commits} = Git.log(config: config, max_count: 2)
      assert length(commits) == 2
      assert hd(commits).subject == "third commit"
    end

    test "max_count of 1 returns only the latest commit", %{config: config} do
      assert {:ok, [commit]} = Git.log(config: config, max_count: 1)
      assert commit.subject == "third commit"
    end

    test "author filter returns matching commits", %{config: config} do
      assert {:ok, commits} = Git.log(config: config, author: "Test User")
      assert length(commits) == 3

      assert {:ok, commits} = Git.log(config: config, author: "Nonexistent")
      assert commits == []
    end

    test "empty result returns ok with empty list" do
      tmp_dir =
        Path.join(
          System.tmp_dir!(),
          "git_wrapper_log_empty_#{:erlang.unique_integer([:positive])}"
        )

      File.mkdir_p!(tmp_dir)
      System.cmd("git", ["init", "--initial-branch=main"], cd: tmp_dir)

      config = Config.new(working_dir: tmp_dir)

      # Empty repo with no commits -- returns empty list
      assert {:ok, []} = Git.log(config: config)

      Git.TestHelpers.rm_rf(tmp_dir)
    end

    test "body field is empty for single-line commit messages", %{config: config} do
      assert {:ok, commits} = Git.log(config: config)

      Enum.each(commits, fn commit ->
        assert commit.body == ""
      end)
    end
  end

  describe "Git.Commands.Log args/1" do
    test "adds --follow, --no-merges, and --first-parent" do
      args = Log.args(%Log{follow: true, no_merges: true, first_parent: true})

      assert "--follow" in args
      assert "--no-merges" in args
      assert "--first-parent" in args
    end

    test "adds grep modifiers and --committer" do
      args =
        Log.args(%Log{
          grep: "fix",
          regexp_ignore_case: true,
          invert_grep: true,
          committer: "alice"
        })

      assert "--grep=fix" in args
      assert "-i" in args
      assert "--invert-grep" in args
      assert "--committer=alice" in args
    end

    test "adds --skip, --reverse, and ref selectors" do
      args = Log.args(%Log{skip: 5, reverse: true, all: true, branches: true, tags: true})

      assert "--skip=5" in args
      assert "--reverse" in args
      assert "--all" in args
      assert "--branches" in args
      assert "--tags" in args
    end
  end

  describe "log history controls (integration)" do
    test "reverse returns commits oldest first", %{config: config} do
      assert {:ok, commits} = Git.log(config: config, reverse: true)
      assert Enum.map(commits, & &1.subject) == ["first commit", "second commit", "third commit"]
    end

    test "skip omits the newest commits", %{config: config} do
      assert {:ok, all} = Git.log(config: config)
      assert {:ok, skipped} = Git.log(config: config, skip: 1)

      assert length(skipped) == length(all) - 1
      assert hd(skipped).subject == "second commit"
    end

    test "no_merges excludes a merge commit", %{tmp_dir: tmp_dir, config: config} do
      System.cmd("git", ["checkout", "-b", "feature"], cd: tmp_dir)

      System.cmd(
        "git",
        [
          "-c",
          "user.name=T",
          "-c",
          "user.email=t@t.com",
          "commit",
          "--allow-empty",
          "-m",
          "on feature"
        ],
        cd: tmp_dir
      )

      System.cmd("git", ["checkout", "main"], cd: tmp_dir)

      System.cmd(
        "git",
        [
          "-c",
          "user.name=T",
          "-c",
          "user.email=t@t.com",
          "merge",
          "--no-ff",
          "-m",
          "merge feature",
          "feature"
        ],
        cd: tmp_dir
      )

      {:ok, with_merge} = Git.log(config: config)
      {:ok, without_merge} = Git.log(config: config, no_merges: true)

      assert "merge feature" in Enum.map(with_merge, & &1.subject)
      refute "merge feature" in Enum.map(without_merge, & &1.subject)
    end
  end
end
