defmodule Git.Commands.RevListTest do
  use ExUnit.Case, async: true

  alias Git.Commands.RevList
  alias Git.Config

  @env [
    {"GIT_AUTHOR_NAME", "Test User"},
    {"GIT_AUTHOR_EMAIL", "test@test.com"},
    {"GIT_COMMITTER_NAME", "Test User"},
    {"GIT_COMMITTER_EMAIL", "test@test.com"}
  ]

  defp setup_repo(name) do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "git_#{name}_test_#{:erlang.unique_integer([:positive])}"
      )

    File.mkdir_p!(tmp_dir)
    cfg = Config.new(working_dir: tmp_dir, env: @env)
    {:ok, :done} = Git.init(config: cfg)
    {:ok, :done} = Git.git_config(set_key: "user.name", set_value: "Test User", config: cfg)
    {:ok, :done} = Git.git_config(set_key: "user.email", set_value: "test@test.com", config: cfg)
    {:ok, _} = Git.commit("initial", allow_empty: true, config: cfg)
    {tmp_dir, cfg}
  end

  setup do
    {tmp_dir, cfg} = setup_repo("rev_list")
    on_exit(fn -> File.rm_rf!(tmp_dir) end)
    %{tmp_dir: tmp_dir, config: cfg}
  end

  describe "args/1" do
    test "builds basic args with ref" do
      assert RevList.args(%RevList{ref: "HEAD"}) == ["rev-list", "HEAD"]
    end

    test "builds args with count" do
      assert RevList.args(%RevList{ref: "HEAD", count: true}) ==
               ["rev-list", "--count", "HEAD"]
    end

    test "builds args with left-right and count" do
      assert RevList.args(%RevList{ref: "main..feature", left_right: true, count: true}) ==
               ["rev-list", "--count", "--left-right", "main..feature"]
    end

    test "builds args with max_count" do
      assert RevList.args(%RevList{ref: "HEAD", max_count: 5}) ==
               ["rev-list", "--max-count=5", "HEAD"]
    end

    test "builds args with no_merges" do
      assert RevList.args(%RevList{ref: "HEAD", no_merges: true}) ==
               ["rev-list", "--no-merges", "HEAD"]
    end

    test "builds args with all" do
      assert RevList.args(%RevList{all: true}) == ["rev-list", "--all"]
    end

    test "builds args with since and until" do
      assert RevList.args(%RevList{ref: "HEAD", since: "2024-01-01", until_date: "2024-12-31"}) ==
               ["rev-list", "--since=2024-01-01", "--until=2024-12-31", "HEAD"]
    end

    test "builds args with author" do
      assert RevList.args(%RevList{ref: "HEAD", author: "Test"}) ==
               ["rev-list", "--author=Test", "HEAD"]
    end

    test "builds args with skip" do
      assert RevList.args(%RevList{ref: "HEAD", skip: 3}) ==
               ["rev-list", "--skip=3", "HEAD"]
    end

    test "builds args with first_parent" do
      assert RevList.args(%RevList{ref: "HEAD", first_parent: true}) ==
               ["rev-list", "--first-parent", "HEAD"]
    end

    test "builds args with reverse" do
      assert RevList.args(%RevList{ref: "HEAD", reverse: true}) ==
               ["rev-list", "--reverse", "HEAD"]
    end

    test "builds args with ancestry_path" do
      assert RevList.args(%RevList{ref: "HEAD", ancestry_path: true}) ==
               ["rev-list", "--ancestry-path", "HEAD"]
    end

    test "builds args with objects" do
      assert RevList.args(%RevList{ref: "HEAD", objects: true}) ==
               ["rev-list", "--objects", "HEAD"]
    end

    test "builds args with no_walk" do
      assert RevList.args(%RevList{ref: "HEAD", no_walk: true}) ==
               ["rev-list", "--no-walk", "HEAD"]
    end
  end

  describe "git rev-list integration" do
    test "lists SHAs", %{config: config} do
      {:ok, shas} = Git.rev_list(ref: "HEAD", config: config)

      assert is_list(shas)
      assert length(shas) == 1
      assert Enum.all?(shas, &String.match?(&1, ~r/^[0-9a-f]{40}$/))
    end

    test "lists multiple SHAs", %{config: config} do
      {:ok, _} = Git.commit("second", allow_empty: true, config: config)
      {:ok, _} = Git.commit("third", allow_empty: true, config: config)

      {:ok, shas} = Git.rev_list(ref: "HEAD", config: config)

      assert length(shas) == 3
    end

    test "count mode returns integer", %{config: config} do
      {:ok, _} = Git.commit("second", allow_empty: true, config: config)

      {:ok, count} = Git.rev_list(ref: "HEAD", count: true, config: config)

      assert is_integer(count)
      assert count == 2
    end

    test "left-right count with diverged branches", %{config: config, tmp_dir: tmp_dir} do
      # Create a second commit on main
      {:ok, _} = Git.commit("second on main", allow_empty: true, config: config)

      # Create a branch from the initial commit
      System.cmd("git", ["checkout", "-b", "feature", "HEAD~1"],
        cd: tmp_dir,
        env: @env
      )

      {:ok, _} = Git.commit("first on feature", allow_empty: true, config: config)
      {:ok, _} = Git.commit("second on feature", allow_empty: true, config: config)

      {:ok, result} =
        Git.rev_list(
          ref: "main...feature",
          left_right: true,
          count: true,
          config: config
        )

      assert is_map(result)
      assert result.left == 1
      assert result.right == 2
    end

    test "max_count limits results", %{config: config} do
      {:ok, _} = Git.commit("second", allow_empty: true, config: config)
      {:ok, _} = Git.commit("third", allow_empty: true, config: config)

      {:ok, shas} = Git.rev_list(ref: "HEAD", max_count: 2, config: config)

      assert length(shas) == 2
    end

    test "no_merges excludes merge commits", %{config: config} do
      {:ok, shas} = Git.rev_list(ref: "HEAD", no_merges: true, config: config)

      assert is_list(shas)
      assert length(shas) == 1
    end
  end
end
