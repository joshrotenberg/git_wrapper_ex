defmodule Git.FsckTest do
  use ExUnit.Case, async: true

  alias Git.Commands.Fsck
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
        "git_fsck_test_#{:erlang.unique_integer([:positive])}"
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

  describe "Git.Commands.Fsck args/1" do
    test "builds default args" do
      assert Fsck.args(%Fsck{}) == ["fsck"]
    end

    test "builds args with full and strict" do
      assert Fsck.args(%Fsck{full: true, strict: true}) == ["fsck", "--full", "--strict"]
    end

    test "builds args with unreachable and no_reflogs" do
      assert Fsck.args(%Fsck{unreachable: true, no_reflogs: true}) ==
               ["fsck", "--unreachable", "--no-reflogs"]
    end

    test "builds args with connectivity_only" do
      assert Fsck.args(%Fsck{connectivity_only: true}) == ["fsck", "--connectivity-only"]
    end

    test "builds args with lost_found and name_objects" do
      assert Fsck.args(%Fsck{lost_found: true, name_objects: true}) ==
               ["fsck", "--lost-found", "--name-objects"]
    end

    test "builds args with dangling" do
      assert Fsck.args(%Fsck{dangling: true}) == ["fsck", "--dangling"]
    end

    test "builds args with no_dangling" do
      assert Fsck.args(%Fsck{no_dangling: true}) == ["fsck", "--no-dangling"]
    end

    test "builds args with root" do
      assert Fsck.args(%Fsck{root: true}) == ["fsck", "--root"]
    end

    test "builds args with verbose" do
      assert Fsck.args(%Fsck{verbose: true}) == ["fsck", "--verbose"]
    end

    test "builds args with progress and no_progress" do
      assert Fsck.args(%Fsck{progress: true}) == ["fsck", "--progress"]
      assert Fsck.args(%Fsck{no_progress: true}) == ["fsck", "--no-progress"]
    end
  end

  describe "git fsck" do
    test "runs fsck on a clean repo", %{config: config} do
      {:ok, issues} = Git.fsck(no_progress: true, config: config)
      assert is_list(issues)
    end

    test "runs fsck with full flag", %{config: config} do
      {:ok, issues} = Git.fsck(full: true, no_progress: true, config: config)
      assert is_list(issues)
    end

    test "runs fsck with connectivity_only flag", %{config: config} do
      {:ok, issues} = Git.fsck(connectivity_only: true, no_progress: true, config: config)
      assert is_list(issues)
    end
  end

  describe "parse_output/2" do
    test "parses empty output as empty list" do
      assert Fsck.parse_output("", 0) == {:ok, []}
    end

    test "parses dangling commit line" do
      output = "dangling commit abc1234def5678\n"
      {:ok, [entry]} = Fsck.parse_output(output, 0)
      assert entry.type == "dangling"
      assert entry.object_type == "commit"
      assert entry.sha == "abc1234def5678"
    end

    test "parses multiple issue lines" do
      output = "dangling commit abc1234\nmissing blob def5678\n"
      {:ok, entries} = Fsck.parse_output(output, 0)
      assert length(entries) == 2
      assert Enum.at(entries, 0).type == "dangling"
      assert Enum.at(entries, 1).type == "missing"
    end

    test "returns error on non-zero exit code" do
      assert Fsck.parse_output("error", 1) == {:error, {"error", 1}}
    end
  end
end
