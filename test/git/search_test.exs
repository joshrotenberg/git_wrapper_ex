defmodule Git.SearchTest do
  use ExUnit.Case, async: true

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
        "git_search_test_#{:erlang.unique_integer([:positive])}"
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

    # Second commit adding more content
    File.write!(
      Path.join(tmp_dir, "utils.ex"),
      "defmodule Utils do\n  def helper, do: :ok\nend\n"
    )

    {:ok, :done} = Git.add(all: true, config: cfg)
    {:ok, _} = Git.commit("chore: add utility module", config: cfg)

    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    %{tmp_dir: tmp_dir, config: cfg}
  end

  describe "grep/2" do
    test "finds content in files", %{config: config} do
      {:ok, results} = Git.Search.grep("hello", config: config)

      assert results != []
      files = Enum.map(results, & &1.file) |> Enum.uniq()
      assert "hello.ex" in files
    end
  end

  describe "commits/2" do
    test "searches commit messages", %{config: config} do
      {:ok, commits} = Git.Search.commits("greeting", config: config)

      assert length(commits) == 1
      assert hd(commits).subject =~ "greeting"
    end

    test "returns empty list when no commits match", %{config: config} do
      {:ok, commits} = Git.Search.commits("nonexistent_xyz", config: config)

      assert commits == []
    end
  end

  describe "pickaxe/2" do
    test "finds commits that added a string", %{config: config} do
      {:ok, commits} = Git.Search.pickaxe("hello world", config: config)

      assert commits != []
      subjects = Enum.map(commits, & &1.subject)
      assert Enum.any?(subjects, &(&1 =~ "greeting"))
    end

    test "finds commits with regex mode", %{config: config} do
      {:ok, commits} = Git.Search.pickaxe("hello world", regex: true, config: config)

      assert commits != []
    end
  end

  describe "files/2" do
    test "finds files matching pattern", %{config: config} do
      {:ok, files} = Git.Search.files("*.ex", config: config)

      assert "hello.ex" in files
      assert "goodbye.ex" in files
    end
  end
end
