defmodule Git.ShowTest do
  use ExUnit.Case, async: true

  alias Git.Commands.Show
  alias Git.{Commit, Config, ShowResult}

  @env [
    {"GIT_AUTHOR_NAME", "Test User"},
    {"GIT_AUTHOR_EMAIL", "test@test.com"},
    {"GIT_COMMITTER_NAME", "Test User"},
    {"GIT_COMMITTER_EMAIL", "test@test.com"}
  ]

  setup do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "git_wrapper_show_test_#{:erlang.unique_integer([:positive])}"
      )

    File.mkdir_p!(tmp_dir)
    System.cmd("git", ["init", "--initial-branch=main"], cd: tmp_dir)

    File.write!(Path.join(tmp_dir, "hello.txt"), "hello world\n")
    System.cmd("git", ["add", "hello.txt"], cd: tmp_dir)

    System.cmd(
      "git",
      [
        "-c",
        "user.name=Test User",
        "-c",
        "user.email=test@test.com",
        "commit",
        "-m",
        "initial commit"
      ],
      cd: tmp_dir
    )

    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    config = Config.new(working_dir: tmp_dir, env: @env)
    %{tmp_dir: tmp_dir, config: config}
  end

  describe "args/1" do
    test "builds args for default (HEAD)" do
      args = Show.args(%Show{})
      assert List.first(args) == "show"
      assert List.last(args) == "HEAD"
    end

    test "builds args with custom ref" do
      args = Show.args(%Show{ref: "abc123"})
      assert List.last(args) == "abc123"
    end

    test "builds args with --stat" do
      args = Show.args(%Show{stat: true})
      assert "--stat" in args
    end

    test "builds args with --no-patch" do
      args = Show.args(%Show{no_patch: true})
      assert "--no-patch" in args
    end

    test "builds args with --name-only" do
      args = Show.args(%Show{name_only: true})
      assert "--name-only" in args
    end

    test "builds args with --name-status" do
      args = Show.args(%Show{name_status: true})
      assert "--name-status" in args
    end

    test "builds args with --oneline" do
      args = Show.args(%Show{oneline: true})
      assert "--oneline" in args
      # Should not have the control-character format
      refute Enum.any?(args, &String.contains?(&1, "\x1e"))
    end

    test "builds args with custom format" do
      args = Show.args(%Show{format: "%H %s"})
      assert "--format=%H %s" in args
      # Should not have the control-character format
      refute Enum.any?(args, &String.contains?(&1, "\x1e"))
    end

    test "builds args with --abbrev-commit" do
      args = Show.args(%Show{abbrev_commit: true})
      assert "--abbrev-commit" in args
    end

    test "builds args with --diff-filter" do
      args = Show.args(%Show{diff_filter: "AM"})
      assert "--diff-filter=AM" in args
    end

    test "builds args with --quiet" do
      args = Show.args(%Show{quiet: true})
      assert "--quiet" in args
    end
  end

  describe "show HEAD" do
    test "returns a ShowResult with parsed commit", %{config: config} do
      result = Git.Command.run(Show, %Show{}, config)

      assert {:ok, %ShowResult{} = show} = result
      assert %Commit{} = show.commit
      assert show.commit.subject == "initial commit"
      assert show.commit.author_name == "Test User"
      assert show.commit.author_email == "test@test.com"
      assert String.length(show.commit.hash) == 40
      assert is_binary(show.raw)
    end
  end

  describe "show with --no-patch" do
    test "returns commit info without diff", %{config: config} do
      result = Git.Command.run(Show, %Show{no_patch: true}, config)

      assert {:ok, %ShowResult{} = show} = result
      assert %Commit{} = show.commit
      assert show.commit.subject == "initial commit"
    end
  end

  describe "show with --oneline" do
    test "returns raw output without parsed commit", %{config: config} do
      result = Git.Command.run(Show, %Show{oneline: true}, config)

      assert {:ok, %ShowResult{} = show} = result
      assert is_nil(show.commit)
      assert is_binary(show.raw)
      assert String.contains?(show.raw, "initial commit")
    end
  end

  describe "show with custom format" do
    test "returns raw output with custom format", %{config: config} do
      result = Git.Command.run(Show, %Show{format: "%H"}, config)

      assert {:ok, %ShowResult{} = show} = result
      assert is_nil(show.commit)
      assert is_binary(show.raw)
      # The raw output should contain a full SHA
      assert String.match?(String.trim(show.raw), ~r/^[0-9a-f]{40}/)
    end
  end

  describe "show with --stat" do
    test "includes stat information", %{config: config} do
      result = Git.Command.run(Show, %Show{stat: true, no_patch: true}, config)

      assert {:ok, %ShowResult{} = show} = result
      assert %Commit{} = show.commit
      assert is_binary(show.raw)
    end
  end

  describe "show a specific ref" do
    test "shows the specified commit", %{tmp_dir: tmp_dir, config: config} do
      File.write!(Path.join(tmp_dir, "second.txt"), "second\n")
      System.cmd("git", ["add", "second.txt"], cd: tmp_dir)

      System.cmd(
        "git",
        [
          "-c",
          "user.name=Test User",
          "-c",
          "user.email=test@test.com",
          "commit",
          "-m",
          "second commit"
        ],
        cd: tmp_dir
      )

      result = Git.Command.run(Show, %Show{ref: "HEAD~1"}, config)

      assert {:ok, %ShowResult{} = show} = result
      assert show.commit.subject == "initial commit"
    end
  end

  describe "show failure" do
    test "returns an error for nonexistent ref", %{config: config} do
      assert {:error, {output, exit_code}} =
               Git.Command.run(Show, %Show{ref: "nonexistent-ref-abc123"}, config)

      assert exit_code != 0
      assert is_binary(output)
    end
  end
end
