defmodule Git.GcTest do
  use ExUnit.Case, async: true

  alias Git.Commands.Gc
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
        "git_gc_test_#{:erlang.unique_integer([:positive])}"
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
    test "builds args with no options" do
      assert Gc.args(%Gc{}) == ["gc"]
    end

    test "builds args with aggressive flag" do
      assert Gc.args(%Gc{aggressive: true}) == ["gc", "--aggressive"]
    end

    test "builds args with auto flag" do
      assert Gc.args(%Gc{auto: true}) == ["gc", "--auto"]
    end

    test "builds args with prune date" do
      assert Gc.args(%Gc{prune: "now"}) == ["gc", "--prune=now"]
    end

    test "builds args with no_prune flag" do
      assert Gc.args(%Gc{no_prune: true}) == ["gc", "--no-prune"]
    end

    test "builds args with quiet and force flags" do
      assert Gc.args(%Gc{quiet: true, force: true}) == ["gc", "--quiet", "--force"]
    end

    test "builds args with keep_largest_pack flag" do
      assert Gc.args(%Gc{keep_largest_pack: true}) == ["gc", "--keep-largest-pack"]
    end
  end

  describe "git gc" do
    test "succeeds on a repository" do
      {_tmp_dir, cfg} = setup_repo()

      assert {:ok, :done} = Git.gc(config: cfg)
    end

    test "succeeds with auto mode" do
      {_tmp_dir, cfg} = setup_repo()

      assert {:ok, :done} = Git.gc(auto: true, config: cfg)
    end
  end
end
