defmodule Git.Commands.ForEachRefTest do
  use ExUnit.Case, async: true

  alias Git.Commands.ForEachRef
  alias Git.Config

  defp setup_repo do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "git_for_each_ref_test_#{:erlang.unique_integer([:positive])}"
      )

    File.mkdir_p!(tmp_dir)
    cfg = Config.new(working_dir: tmp_dir)
    {:ok, :done} = Git.init(config: cfg)
    {:ok, :done} = Git.git_config(set_key: "user.name", set_value: "Test User", config: cfg)
    {:ok, :done} = Git.git_config(set_key: "user.email", set_value: "test@test.com", config: cfg)
    {:ok, _} = Git.commit("initial", allow_empty: true, config: cfg)
    {tmp_dir, cfg}
  end

  setup do
    {tmp_dir, config} = setup_repo()
    on_exit(fn -> File.rm_rf!(tmp_dir) end)
    %{tmp_dir: tmp_dir, config: config}
  end

  describe "args/1" do
    test "default args" do
      assert ForEachRef.args(%ForEachRef{}) == ["for-each-ref"]
    end

    test "with format" do
      assert ForEachRef.args(%ForEachRef{format: "%(refname)"}) ==
               ["for-each-ref", "--format=%(refname)"]
    end

    test "with sort string" do
      assert ForEachRef.args(%ForEachRef{sort: "-creatordate"}) ==
               ["for-each-ref", "--sort=-creatordate"]
    end

    test "with sort list" do
      assert ForEachRef.args(%ForEachRef{sort: ["-creatordate", "refname"]}) ==
               ["for-each-ref", "--sort=-creatordate", "--sort=refname"]
    end

    test "with count" do
      assert ForEachRef.args(%ForEachRef{count: 5}) ==
               ["for-each-ref", "--count=5"]
    end

    test "with single pattern" do
      assert ForEachRef.args(%ForEachRef{pattern: "refs/heads/"}) ==
               ["for-each-ref", "refs/heads/"]
    end

    test "with multiple patterns" do
      assert ForEachRef.args(%ForEachRef{pattern: ["refs/heads/", "refs/tags/"]}) ==
               ["for-each-ref", "refs/heads/", "refs/tags/"]
    end

    test "with contains" do
      assert ForEachRef.args(%ForEachRef{contains: "abc123"}) ==
               ["for-each-ref", "--contains=abc123"]
    end

    test "with merged" do
      assert ForEachRef.args(%ForEachRef{merged: "main"}) ==
               ["for-each-ref", "--merged=main"]
    end

    test "with no_merged" do
      assert ForEachRef.args(%ForEachRef{no_merged: "main"}) ==
               ["for-each-ref", "--no-merged=main"]
    end

    test "with points_at" do
      assert ForEachRef.args(%ForEachRef{points_at: "HEAD"}) ==
               ["for-each-ref", "--points-at=HEAD"]
    end
  end

  describe "for_each_ref integration" do
    test "lists refs with format", %{config: config} do
      {:ok, output} =
        Git.for_each_ref(format: "%(refname:short)", pattern: "refs/heads/", config: config)

      assert output == "main"
    end

    test "lists refs with default format", %{tmp_dir: tmp_dir, config: config} do
      System.cmd("git", ["tag", "v1.0"], cd: tmp_dir)

      {:ok, output} =
        Git.for_each_ref(format: "%(refname:short)", pattern: "refs/tags/", config: config)

      assert output == "v1.0"
    end

    test "returns empty string when no refs match", %{config: config} do
      {:ok, output} =
        Git.for_each_ref(pattern: "refs/nonexistent/", config: config)

      assert output == ""
    end

    test "count limits results", %{tmp_dir: tmp_dir, config: config} do
      System.cmd("git", ["tag", "v1.0"], cd: tmp_dir)
      System.cmd("git", ["tag", "v2.0"], cd: tmp_dir)

      {:ok, output} =
        Git.for_each_ref(
          format: "%(refname:short)",
          pattern: "refs/tags/",
          count: 1,
          config: config
        )

      # Only one tag should be returned
      lines = String.split(output, "\n", trim: true)
      assert length(lines) == 1
    end
  end
end
