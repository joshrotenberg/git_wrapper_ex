defmodule Git.RangeDiffTest do
  use ExUnit.Case, async: true

  alias Git.Commands.RangeDiff
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
        "git_range_diff_test_#{:erlang.unique_integer([:positive])}"
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
    {tmp_dir, config} = setup_repo()
    on_exit(fn -> File.rm_rf!(tmp_dir) end)
    %{tmp_dir: tmp_dir, config: config}
  end

  describe "Git.Commands.RangeDiff args/1" do
    test "builds args for two-range form" do
      assert RangeDiff.args(%RangeDiff{range1: "main..topic-v1", range2: "main..topic-v2"}) ==
               ["range-diff", "main..topic-v1", "main..topic-v2"]
    end

    test "builds args for three-arg form" do
      assert RangeDiff.args(%RangeDiff{rev1: "main", rev2: "topic-v1", rev3: "topic-v2"}) ==
               ["range-diff", "main", "topic-v1", "topic-v2"]
    end

    test "builds args with stat flag" do
      assert RangeDiff.args(%RangeDiff{range1: "a..b", range2: "a..c", stat: true}) ==
               ["range-diff", "--stat", "a..b", "a..c"]
    end

    test "builds args with no_patch flag" do
      assert RangeDiff.args(%RangeDiff{range1: "a..b", range2: "a..c", no_patch: true}) ==
               ["range-diff", "--no-patch", "a..b", "a..c"]
    end

    test "builds args with creation_factor" do
      assert RangeDiff.args(%RangeDiff{range1: "a..b", range2: "a..c", creation_factor: 50}) ==
               ["range-diff", "--creation-factor=50", "a..b", "a..c"]
    end

    test "builds args with no_dual_color flag" do
      assert RangeDiff.args(%RangeDiff{range1: "a..b", range2: "a..c", no_dual_color: true}) ==
               ["range-diff", "--no-dual-color", "a..b", "a..c"]
    end

    test "builds args with left_only flag" do
      assert RangeDiff.args(%RangeDiff{range1: "a..b", range2: "a..c", left_only: true}) ==
               ["range-diff", "--left-only", "a..b", "a..c"]
    end

    test "builds args with right_only flag" do
      assert RangeDiff.args(%RangeDiff{range1: "a..b", range2: "a..c", right_only: true}) ==
               ["range-diff", "--right-only", "a..b", "a..c"]
    end

    test "builds args with no_notes flag" do
      assert RangeDiff.args(%RangeDiff{range1: "a..b", range2: "a..c", no_notes: true}) ==
               ["range-diff", "--no-notes", "a..b", "a..c"]
    end

    test "builds args with multiple flags" do
      assert RangeDiff.args(%RangeDiff{
               rev1: "base",
               rev2: "v1",
               rev3: "v2",
               stat: true,
               no_dual_color: true,
               creation_factor: 75
             }) ==
               [
                 "range-diff",
                 "--stat",
                 "--creation-factor=75",
                 "--no-dual-color",
                 "base",
                 "v1",
                 "v2"
               ]
    end
  end

  describe "git range-diff integration" do
    test "compares two versions of a branch", %{tmp_dir: tmp_dir, config: config} do
      # Create a commit on main
      File.write!(Path.join(tmp_dir, "base.txt"), "base content\n")
      {:ok, :done} = Git.add(files: ["base.txt"], config: config)
      {:ok, _} = Git.commit("add base file", config: config)

      # Create topic-v1 branch with a commit
      {:ok, _} = Git.checkout(branch: "topic-v1", create: true, config: config)
      File.write!(Path.join(tmp_dir, "feature.txt"), "feature v1\n")
      {:ok, :done} = Git.add(files: ["feature.txt"], config: config)
      {:ok, _} = Git.commit("add feature", config: config)

      # Go back to main and create topic-v2 with similar commit
      {:ok, _} = Git.checkout(branch: "main", config: config)
      {:ok, _} = Git.checkout(branch: "topic-v2", create: true, config: config)
      File.write!(Path.join(tmp_dir, "feature.txt"), "feature v2\n")
      {:ok, :done} = Git.add(files: ["feature.txt"], config: config)
      {:ok, _} = Git.commit("add feature", config: config)

      # Run range-diff
      assert {:ok, output} =
               Git.range_diff(
                 range1: "main..topic-v1",
                 range2: "main..topic-v2",
                 config: config
               )

      assert is_binary(output)
    end

    test "compares using three-arg form", %{tmp_dir: tmp_dir, config: config} do
      # Create a commit on main
      File.write!(Path.join(tmp_dir, "base.txt"), "base content\n")
      {:ok, :done} = Git.add(files: ["base.txt"], config: config)
      {:ok, _} = Git.commit("add base file", config: config)

      # Create topic-v1 branch with a commit
      {:ok, _} = Git.checkout(branch: "topic-v1", create: true, config: config)
      File.write!(Path.join(tmp_dir, "feature.txt"), "feature v1\n")
      {:ok, :done} = Git.add(files: ["feature.txt"], config: config)
      {:ok, _} = Git.commit("add feature", config: config)

      # Go back to main and create topic-v2 with similar commit
      {:ok, _} = Git.checkout(branch: "main", config: config)
      {:ok, _} = Git.checkout(branch: "topic-v2", create: true, config: config)
      File.write!(Path.join(tmp_dir, "feature.txt"), "feature v2\n")
      {:ok, :done} = Git.add(files: ["feature.txt"], config: config)
      {:ok, _} = Git.commit("add feature", config: config)

      # Run range-diff using three-arg form
      assert {:ok, output} =
               Git.range_diff(
                 rev1: "main",
                 rev2: "topic-v1",
                 rev3: "topic-v2",
                 config: config
               )

      assert is_binary(output)
    end
  end
end
