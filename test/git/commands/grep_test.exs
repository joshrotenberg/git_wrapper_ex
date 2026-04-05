defmodule Git.Commands.GrepTest do
  use ExUnit.Case, async: true

  alias Git.Commands.Grep
  alias Git.Config
  alias Git.GrepResult

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
        "git_wrapper_grep_test_#{:erlang.unique_integer([:positive])}"
      )

    File.mkdir_p!(tmp_dir)
    cfg = Config.new(working_dir: tmp_dir, env: @env)
    {:ok, :done} = Git.init(config: cfg)
    {:ok, :done} = Git.git_config(set_key: "user.name", set_value: "Test User", config: cfg)
    {:ok, :done} = Git.git_config(set_key: "user.email", set_value: "test@test.com", config: cfg)

    File.write!(
      Path.join(tmp_dir, "hello.ex"),
      "defmodule Hello do\n  def greet, do: \"hello world\"\nend\n"
    )

    File.write!(
      Path.join(tmp_dir, "goodbye.ex"),
      "defmodule Goodbye do\n  def farewell, do: \"goodbye world\"\nend\n"
    )

    {:ok, :done} = Git.add(all: true, config: cfg)
    {:ok, _} = Git.commit("feat: add greeting modules", config: cfg)

    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    %{tmp_dir: tmp_dir, config: cfg}
  end

  describe "args/1" do
    test "builds basic args with pattern" do
      assert Grep.args(%Grep{pattern: "hello"}) == ["grep", "-n", "hello"]
    end

    test "builds args with ignore_case" do
      assert Grep.args(%Grep{pattern: "hello", ignore_case: true}) ==
               ["grep", "-n", "-i", "hello"]
    end

    test "builds args with files_with_matches" do
      assert Grep.args(%Grep{pattern: "hello", files_with_matches: true}) ==
               ["grep", "-l", "hello"]
    end

    test "builds args with count" do
      assert Grep.args(%Grep{pattern: "hello", count: true}) ==
               ["grep", "-c", "hello"]
    end

    test "builds args with ref" do
      assert Grep.args(%Grep{pattern: "hello", ref: "HEAD"}) ==
               ["grep", "-n", "hello", "HEAD"]
    end

    test "builds args with paths" do
      assert Grep.args(%Grep{pattern: "hello", paths: ["lib/"]}) ==
               ["grep", "-n", "hello", "--", "lib/"]
    end

    test "builds args with context options" do
      assert Grep.args(%Grep{pattern: "hello", context: 3}) ==
               ["grep", "-n", "-C", "3", "hello"]
    end

    test "builds args with max_count" do
      assert Grep.args(%Grep{pattern: "hello", max_count: 5}) ==
               ["grep", "-n", "-m", "5", "hello"]
    end

    test "builds args with multiple flags" do
      args =
        Grep.args(%Grep{
          pattern: "hello",
          ignore_case: true,
          word_regexp: true,
          extended_regexp: true
        })

      assert args == ["grep", "-n", "-i", "-w", "-E", "hello"]
    end
  end

  describe "git grep integration" do
    test "basic grep finds matches", %{config: config} do
      {:ok, results} = Git.grep("hello", config: config)

      assert is_list(results)
      assert results != []

      hello_match = Enum.find(results, fn r -> r.file == "hello.ex" end)
      assert %GrepResult{} = hello_match
      assert hello_match.line_number != nil
      assert String.contains?(hello_match.content, "hello")
    end

    test "case insensitive search", %{config: config} do
      {:ok, results} = Git.grep("HELLO", ignore_case: true, config: config)

      assert results != []
      files = Enum.map(results, & &1.file) |> Enum.uniq()
      assert "hello.ex" in files
    end

    test "files only mode", %{config: config} do
      {:ok, results} = Git.grep("defmodule", files_with_matches: true, config: config)

      files = Enum.map(results, & &1.file)
      assert "hello.ex" in files
      assert "goodbye.ex" in files
    end

    test "count mode", %{config: config} do
      {:ok, results} = Git.grep("def", count: true, config: config)

      hello = Enum.find(results, fn r -> r.file == "hello.ex" end)
      assert hello != nil
      # hello.ex has "defmodule" and "def greet" = 2 matches
      assert hello.line_number == 2
    end

    test "no matches returns empty list", %{config: config} do
      {:ok, results} = Git.grep("nonexistent_pattern_xyz", config: config)

      assert results == []
    end

    test "search in specific ref", %{config: config} do
      {:ok, results} = Git.grep("hello", ref: "HEAD", config: config)

      assert results != []
    end

    test "path filtering", %{config: config} do
      {:ok, results} = Git.grep("def", paths: ["hello.ex"], config: config)

      files = Enum.map(results, & &1.file) |> Enum.uniq()
      assert files == ["hello.ex"]
    end
  end
end
