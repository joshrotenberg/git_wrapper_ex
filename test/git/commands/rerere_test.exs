defmodule Git.RerereTest do
  use ExUnit.Case, async: true

  alias Git.Commands.Rerere
  alias Git.Config

  @env [
    {"GIT_AUTHOR_NAME", "Test User"},
    {"GIT_AUTHOR_EMAIL", "test@test.com"},
    {"GIT_COMMITTER_NAME", "Test User"},
    {"GIT_COMMITTER_EMAIL", "test@test.com"}
  ]

  defp setup_repo do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "git_rerere_test_#{:erlang.unique_integer([:positive])}"
      )

    File.mkdir_p!(tmp_dir)
    cfg = Config.new(working_dir: tmp_dir, env: @env)
    {:ok, :done} = Git.init(config: cfg)
    {:ok, :done} = Git.git_config(set_key: "user.name", set_value: "Test User", config: cfg)
    {:ok, :done} = Git.git_config(set_key: "user.email", set_value: "test@test.com", config: cfg)
    {:ok, :done} = Git.git_config(set_key: "rerere.enabled", set_value: "true", config: cfg)
    {:ok, _} = Git.commit("initial", allow_empty: true, config: cfg)
    on_exit(fn -> File.rm_rf!(tmp_dir) end)
    {tmp_dir, cfg}
  end

  describe "args/1" do
    test "defaults to status subcommand" do
      assert Rerere.args(%Rerere{}) == ["rerere", "status"]
    end

    test "builds args for status" do
      assert Rerere.args(%Rerere{status: true}) == ["rerere", "status"]
    end

    test "builds args for diff" do
      assert Rerere.args(%Rerere{diff: true}) == ["rerere", "diff"]
    end

    test "builds args for clear" do
      assert Rerere.args(%Rerere{clear: true}) == ["rerere", "clear"]
    end

    test "builds args for forget with path" do
      assert Rerere.args(%Rerere{forget: "path/to/file"}) ==
               ["rerere", "forget", "path/to/file"]
    end

    test "builds args for gc" do
      assert Rerere.args(%Rerere{gc: true}) == ["rerere", "gc"]
    end

    test "builds args for remaining" do
      assert Rerere.args(%Rerere{remaining: true}) == ["rerere", "remaining"]
    end
  end

  describe "rerere status" do
    test "returns empty list on repo with no conflicts" do
      {_tmp_dir, cfg} = setup_repo()

      assert {:ok, []} = Git.rerere(config: cfg)
    end
  end

  describe "rerere clear" do
    test "succeeds on a clean repo" do
      {_tmp_dir, cfg} = setup_repo()

      assert {:ok, :done} = Git.rerere(clear: true, config: cfg)
    end
  end
end
