defmodule Git.Commands.MergeBaseTest do
  use ExUnit.Case, async: true

  alias Git.Commands.MergeBase
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
    {tmp_dir, cfg} = setup_repo("merge_base")

    # Create a branching history:
    # initial -> second (main) -> third (main)
    #         \-> feature-1 -> feature-2 (feature)
    {:ok, _} = Git.commit("second", allow_empty: true, config: cfg)

    # Get the initial commit SHA for branching
    {initial_sha, 0} = System.cmd("git", ["rev-parse", "HEAD~1"], cd: tmp_dir)
    initial_sha = String.trim(initial_sha)

    System.cmd("git", ["checkout", "-b", "feature", initial_sha],
      cd: tmp_dir,
      env: @env
    )

    {:ok, _} = Git.commit("feature-1", allow_empty: true, config: cfg)
    {:ok, _} = Git.commit("feature-2", allow_empty: true, config: cfg)

    # Go back to main for the third commit
    System.cmd("git", ["checkout", "main"], cd: tmp_dir, env: @env)
    {:ok, _} = Git.commit("third", allow_empty: true, config: cfg)

    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    %{tmp_dir: tmp_dir, config: cfg, initial_sha: initial_sha}
  end

  describe "args/1" do
    test "builds basic args with two commits" do
      assert MergeBase.args(%MergeBase{commits: ["main", "feature"]}) ==
               ["merge-base", "main", "feature"]
    end

    test "builds args with is_ancestor" do
      assert MergeBase.args(%MergeBase{commits: ["main", "feature"], is_ancestor: true}) ==
               ["merge-base", "--is-ancestor", "main", "feature"]
    end

    test "builds args with all" do
      assert MergeBase.args(%MergeBase{commits: ["main", "feature"], all: true}) ==
               ["merge-base", "--all", "main", "feature"]
    end

    test "builds args with octopus" do
      assert MergeBase.args(%MergeBase{commits: ["a", "b", "c"], octopus: true}) ==
               ["merge-base", "--octopus", "a", "b", "c"]
    end

    test "builds args with independent" do
      assert MergeBase.args(%MergeBase{commits: ["a", "b", "c"], independent: true}) ==
               ["merge-base", "--independent", "a", "b", "c"]
    end

    test "builds args with fork_point" do
      assert MergeBase.args(%MergeBase{commits: ["main", "feature"], fork_point: true}) ==
               ["merge-base", "--fork-point", "main", "feature"]
    end
  end

  describe "git merge-base integration" do
    test "finds common ancestor", %{config: config, initial_sha: initial_sha} do
      {:ok, sha} = Git.merge_base(commits: ["main", "feature"], config: config)

      assert sha == initial_sha
    end

    test "is_ancestor returns true when ancestor", %{config: config, initial_sha: initial_sha} do
      {:ok, result} =
        Git.merge_base(
          commits: [initial_sha, "main"],
          is_ancestor: true,
          config: config
        )

      assert result == true
    end

    test "is_ancestor returns false when not ancestor", %{config: config} do
      {:ok, result} =
        Git.merge_base(
          commits: ["main", "feature"],
          is_ancestor: true,
          config: config
        )

      assert result == false
    end

    test "all returns list of merge bases", %{config: config, initial_sha: initial_sha} do
      {:ok, shas} =
        Git.merge_base(
          commits: ["main", "feature"],
          all: true,
          config: config
        )

      assert is_list(shas)
      assert initial_sha in shas
    end
  end
end
