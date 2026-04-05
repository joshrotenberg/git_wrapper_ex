defmodule Git.VerifyCommitTest do
  use ExUnit.Case, async: true

  alias Git.Commands.VerifyCommit
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
        "git_verify_commit_test_#{:erlang.unique_integer([:positive])}"
      )

    File.mkdir_p!(tmp_dir)
    cfg = Config.new(working_dir: tmp_dir, env: @env)
    {:ok, :done} = Git.init(config: cfg)
    {:ok, :done} = Git.git_config(set_key: "user.name", set_value: "Test User", config: cfg)
    {:ok, :done} = Git.git_config(set_key: "user.email", set_value: "test@test.com", config: cfg)
    {:ok, _} = Git.commit("initial", allow_empty: true, config: cfg)
    on_exit(fn -> File.rm_rf!(tmp_dir) end)
    {tmp_dir, cfg}
  end

  describe "args/1" do
    test "builds args with commit only" do
      assert VerifyCommit.args(%VerifyCommit{commit: "HEAD"}) ==
               ["verify-commit", "HEAD"]
    end

    test "builds args with verbose flag" do
      assert VerifyCommit.args(%VerifyCommit{commit: "HEAD", verbose: true}) ==
               ["verify-commit", "-v", "HEAD"]
    end

    test "builds args with raw flag" do
      assert VerifyCommit.args(%VerifyCommit{commit: "HEAD", raw: true}) ==
               ["verify-commit", "--raw", "HEAD"]
    end

    test "builds args with both verbose and raw flags" do
      assert VerifyCommit.args(%VerifyCommit{commit: "abc123", verbose: true, raw: true}) ==
               ["verify-commit", "-v", "--raw", "abc123"]
    end
  end

  describe "verify-commit on unsigned commit" do
    test "returns valid: false for an unsigned commit" do
      {_tmp_dir, cfg} = setup_repo()

      {:ok, result} = Git.verify_commit("HEAD", config: cfg)
      assert result.valid == false
    end
  end
end
