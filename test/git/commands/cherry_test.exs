defmodule Git.Commands.CherryTest do
  use ExUnit.Case, async: true

  alias Git.CherryEntry
  alias Git.Commands.Cherry
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
    {tmp_dir, cfg} = setup_repo("cherry")

    # Create feature branch with unique commits
    System.cmd("git", ["checkout", "-b", "feature"], cd: tmp_dir, env: @env)

    File.write!(Path.join(tmp_dir, "a.txt"), "a content\n")
    {:ok, :done} = Git.add(all: true, config: cfg)
    {:ok, _} = Git.commit("add a.txt", config: cfg)

    File.write!(Path.join(tmp_dir, "b.txt"), "b content\n")
    {:ok, :done} = Git.add(all: true, config: cfg)
    {:ok, _} = Git.commit("add b.txt", config: cfg)

    # Go back to main
    System.cmd("git", ["checkout", "main"], cd: tmp_dir, env: @env)

    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    %{tmp_dir: tmp_dir, config: cfg}
  end

  describe "args/1" do
    test "builds basic args with upstream" do
      assert Cherry.args(%Cherry{upstream: "main"}) == ["cherry", "main"]
    end

    test "builds args with verbose" do
      assert Cherry.args(%Cherry{upstream: "main", verbose: true}) ==
               ["cherry", "-v", "main"]
    end

    test "builds args with upstream and head" do
      assert Cherry.args(%Cherry{upstream: "main", head: "feature"}) ==
               ["cherry", "main", "feature"]
    end

    test "builds args with upstream, head, and limit" do
      assert Cherry.args(%Cherry{upstream: "main", head: "feature", limit: "v1.0"}) ==
               ["cherry", "main", "feature", "v1.0"]
    end
  end

  describe "git cherry integration" do
    test "finds unapplied commits between branches", %{config: config} do
      {:ok, entries} =
        Git.cherry(upstream: "main", head: "feature", config: config)

      assert is_list(entries)
      assert length(entries) == 2
      assert Enum.all?(entries, fn e -> %CherryEntry{} = e end)
      # Both commits are unique to feature, so not applied upstream
      assert Enum.all?(entries, fn e -> e.applied == false end)
    end

    test "verbose mode includes subjects", %{config: config} do
      {:ok, entries} =
        Git.cherry(upstream: "main", head: "feature", verbose: true, config: config)

      assert length(entries) == 2
      subjects = Enum.map(entries, & &1.subject)
      assert "add a.txt" in subjects
      assert "add b.txt" in subjects
    end

    test "applied detection after cherry-pick", %{config: config, tmp_dir: tmp_dir} do
      # Add a third commit on feature so we have more to work with
      System.cmd("git", ["checkout", "feature"], cd: tmp_dir, env: @env)
      File.write!(Path.join(tmp_dir, "c.txt"), "c content\n")
      {:ok, :done} = Git.add(all: true, config: config)
      {:ok, _} = Git.commit("add c.txt", config: config)

      # Get the SHA of the middle feature commit (add b.txt)
      {sha, 0} = System.cmd("git", ["rev-parse", "feature~1"], cd: tmp_dir)
      sha = String.trim(sha)

      # Cherry-pick it onto main
      System.cmd("git", ["checkout", "main"], cd: tmp_dir, env: @env)
      {_, 0} = System.cmd("git", ["cherry-pick", sha], cd: tmp_dir, env: @env)

      {:ok, entries} =
        Git.cherry(upstream: "main", head: "feature", config: config)

      assert length(entries) == 3

      # The cherry-picked commit should be marked as applied
      applied = Enum.filter(entries, & &1.applied)
      not_applied = Enum.reject(entries, & &1.applied)
      assert length(applied) == 1
      assert length(not_applied) == 2
    end
  end
end
