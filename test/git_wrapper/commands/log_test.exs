defmodule GitWrapper.LogTest do
  use ExUnit.Case, async: true

  alias GitWrapper.{Commit, Config}

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
      ["-c", "user.name=Test User", "-c", "user.email=test@test.com",
       "commit", "--allow-empty", "-m", "first commit"],
      cd: tmp_dir
    )

    System.cmd(
      "git",
      ["-c", "user.name=Test User", "-c", "user.email=test@test.com",
       "commit", "--allow-empty", "-m", "second commit"],
      cd: tmp_dir
    )

    System.cmd(
      "git",
      ["-c", "user.name=Test User", "-c", "user.email=test@test.com",
       "commit", "--allow-empty", "-m", "third commit"],
      cd: tmp_dir
    )

    on_exit(fn -> File.rm_rf!(tmp_dir) end)
    %{tmp_dir: tmp_dir, config: Config.new(working_dir: tmp_dir)}
  end

  describe "log/1" do
    test "returns a list of Commit structs", %{config: config} do
      assert {:ok, commits} = GitWrapperEx.log(config: config)
      assert is_list(commits)
      assert length(commits) == 3

      Enum.each(commits, fn commit ->
        assert %Commit{} = commit
      end)
    end

    test "commits have expected fields populated", %{config: config} do
      assert {:ok, [latest | _]} = GitWrapperEx.log(config: config)

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
      assert {:ok, commits} = GitWrapperEx.log(config: config)
      subjects = Enum.map(commits, & &1.subject)
      assert subjects == ["third commit", "second commit", "first commit"]
    end

    test "max_count limits the number of results", %{config: config} do
      assert {:ok, commits} = GitWrapperEx.log(config: config, max_count: 2)
      assert length(commits) == 2
      assert hd(commits).subject == "third commit"
    end

    test "max_count of 1 returns only the latest commit", %{config: config} do
      assert {:ok, [commit]} = GitWrapperEx.log(config: config, max_count: 1)
      assert commit.subject == "third commit"
    end

    test "author filter returns matching commits", %{config: config} do
      assert {:ok, commits} = GitWrapperEx.log(config: config, author: "Test User")
      assert length(commits) == 3

      assert {:ok, commits} = GitWrapperEx.log(config: config, author: "Nonexistent")
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
      assert {:ok, []} = GitWrapperEx.log(config: config)

      File.rm_rf!(tmp_dir)
    end

    test "body field is empty for single-line commit messages", %{config: config} do
      assert {:ok, commits} = GitWrapperEx.log(config: config)

      Enum.each(commits, fn commit ->
        assert commit.body == ""
      end)
    end
  end
end
