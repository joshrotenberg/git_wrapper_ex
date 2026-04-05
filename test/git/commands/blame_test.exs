defmodule Git.BlameTest do
  use ExUnit.Case, async: true

  alias Git.BlameEntry
  alias Git.Commands.Blame
  alias Git.Config

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
        "git_wrapper_blame_test_#{:erlang.unique_integer([:positive])}"
      )

    File.mkdir_p!(tmp_dir)
    System.cmd("git", ["init", "--initial-branch=main"], cd: tmp_dir)

    # Create a file and commit it
    File.write!(Path.join(tmp_dir, "hello.txt"), "line one\nline two\n")
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
        "first commit"
      ],
      cd: tmp_dir,
      env: @env
    )

    # Add more lines in a second commit
    File.write!(Path.join(tmp_dir, "hello.txt"), "line one\nline two\nline three\n")
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
        "second commit"
      ],
      cd: tmp_dir,
      env: @env
    )

    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    config = Config.new(working_dir: tmp_dir, env: @env)
    %{tmp_dir: tmp_dir, config: config}
  end

  describe "Git.Commands.Blame args/1" do
    test "builds args with file only" do
      assert Blame.args(%Blame{file: "lib/app.ex"}) ==
               ["blame", "--porcelain", "lib/app.ex"]
    end

    test "builds args with line range" do
      assert Blame.args(%Blame{file: "lib/app.ex", lines: "1,5"}) ==
               ["blame", "--porcelain", "-L", "1,5", "lib/app.ex"]
    end

    test "builds args with revision" do
      assert Blame.args(%Blame{file: "lib/app.ex", rev: "HEAD~1"}) ==
               ["blame", "--porcelain", "HEAD~1", "--", "lib/app.ex"]
    end

    test "builds args with show_email" do
      assert Blame.args(%Blame{file: "lib/app.ex", show_email: true}) ==
               ["blame", "--porcelain", "-e", "lib/app.ex"]
    end

    test "builds args with date format" do
      assert Blame.args(%Blame{file: "lib/app.ex", date: "short"}) ==
               ["blame", "--porcelain", "--date=short", "lib/app.ex"]
    end

    test "builds args with reverse" do
      assert Blame.args(%Blame{file: "lib/app.ex", reverse: true}) ==
               ["blame", "--porcelain", "--reverse", "lib/app.ex"]
    end

    test "builds args with first_parent" do
      assert Blame.args(%Blame{file: "lib/app.ex", first_parent: true}) ==
               ["blame", "--porcelain", "--first-parent", "lib/app.ex"]
    end
  end

  describe "git blame" do
    test "blames a file and returns entries", %{config: config} do
      {:ok, entries} =
        Git.Command.run(Blame, %Blame{file: "hello.txt"}, config)

      assert is_list(entries)
      assert length(entries) == 3

      Enum.each(entries, fn entry ->
        assert %BlameEntry{} = entry
        assert String.match?(entry.commit, ~r/^[0-9a-f]{40}$/)
        assert entry.author_name == "Test User"
        assert is_integer(entry.line_number)
        assert is_integer(entry.original_line_number)
        assert is_binary(entry.content)
      end)
    end

    test "entries have correct line content", %{config: config} do
      {:ok, entries} =
        Git.Command.run(Blame, %Blame{file: "hello.txt"}, config)

      contents = Enum.map(entries, & &1.content)
      assert contents == ["line one", "line two", "line three"]
    end

    test "entries have correct line numbers", %{config: config} do
      {:ok, entries} =
        Git.Command.run(Blame, %Blame{file: "hello.txt"}, config)

      line_numbers = Enum.map(entries, & &1.line_number)
      assert line_numbers == [1, 2, 3]
    end

    test "multiple commits produce different SHAs", %{config: config} do
      {:ok, entries} =
        Git.Command.run(Blame, %Blame{file: "hello.txt"}, config)

      # Lines 1-2 are from the first commit, line 3 from the second
      [entry1, entry2, entry3] = entries
      assert entry1.commit == entry2.commit
      assert entry1.commit != entry3.commit
    end

    test "blame with line range returns subset", %{config: config} do
      {:ok, entries} =
        Git.Command.run(Blame, %Blame{file: "hello.txt", lines: "1,2"}, config)

      assert length(entries) == 2
      contents = Enum.map(entries, & &1.content)
      assert contents == ["line one", "line two"]
    end
  end

  describe "git blame failure" do
    test "returns error for nonexistent file", %{config: config} do
      assert {:error, {_output, exit_code}} =
               Git.Command.run(Blame, %Blame{file: "nonexistent.txt"}, config)

      assert exit_code != 0
    end
  end
end
