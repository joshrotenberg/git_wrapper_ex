defmodule Git.VerifyTagTest do
  use ExUnit.Case, async: true

  alias Git.Commands.VerifyTag
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
        "git_verify_tag_test_#{:erlang.unique_integer([:positive])}"
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
    test "builds args with tag only" do
      assert VerifyTag.args(%VerifyTag{tag: "v1.0"}) ==
               ["verify-tag", "v1.0"]
    end

    test "builds args with verbose flag" do
      assert VerifyTag.args(%VerifyTag{tag: "v1.0", verbose: true}) ==
               ["verify-tag", "-v", "v1.0"]
    end

    test "builds args with raw flag" do
      assert VerifyTag.args(%VerifyTag{tag: "v1.0", raw: true}) ==
               ["verify-tag", "--raw", "v1.0"]
    end

    test "builds args with format option" do
      assert VerifyTag.args(%VerifyTag{tag: "v1.0", format: "%(objectname)"}) ==
               ["verify-tag", "--format=%(objectname)", "v1.0"]
    end
  end

  describe "verify-tag on unsigned tag" do
    test "returns valid: false for an unsigned annotated tag" do
      {_tmp_dir, cfg} = setup_repo()

      {:ok, :done} = Git.tag(create: "v1.0", message: "release", config: cfg)
      {:ok, result} = Git.verify_tag("v1.0", config: cfg)
      assert result.valid == false
    end
  end
end
