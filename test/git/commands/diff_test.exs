defmodule Git.Commands.DiffTest do
  use ExUnit.Case, async: true

  alias Git.Commands.Diff
  alias Git.Config

  setup do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "git_wrapper_diff_test_#{:erlang.unique_integer([:positive])}"
      )

    File.mkdir_p!(tmp_dir)

    System.cmd("git", ["init", "--initial-branch=main"], cd: tmp_dir)
    System.cmd("git", ["config", "user.name", "Test User"], cd: tmp_dir)
    System.cmd("git", ["config", "user.email", "test@test.com"], cd: tmp_dir)

    # Create a file and make initial commit
    File.write!(Path.join(tmp_dir, "hello.txt"), "hello\n")
    System.cmd("git", ["add", "hello.txt"], cd: tmp_dir)

    System.cmd(
      "git",
      ["commit", "-m", "initial"],
      cd: tmp_dir
    )

    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    config = Config.new(working_dir: tmp_dir)

    %{tmp_dir: tmp_dir, config: config}
  end

  describe "Commands.Diff.args/1" do
    test "default (no args)" do
      assert Diff.args(%Diff{}) == ["diff"]
    end

    test "staged" do
      assert Diff.args(%Diff{staged: true}) == ["diff", "--cached"]
    end

    test "stat mode" do
      assert Diff.args(%Diff{stat: true}) == ["diff", "--stat"]
    end

    test "name only" do
      assert Diff.args(%Diff{name_only: true}) == ["diff", "--name-only"]
    end

    test "name status" do
      assert Diff.args(%Diff{name_status: true}) == ["diff", "--name-status"]
    end

    test "ref" do
      assert Diff.args(%Diff{ref: "HEAD~1"}) == ["diff", "HEAD~1"]
    end

    test "two-ref diff" do
      assert Diff.args(%Diff{ref: "main", ref_end: "feat"}) ==
               ["diff", "main", "feat"]
    end

    test "with path" do
      assert Diff.args(%Diff{path: "lib/"}) == ["diff", "--", "lib/"]
    end

    test "staged with stat" do
      assert Diff.args(%Diff{staged: true, stat: true}) ==
               ["diff", "--cached", "--stat"]
    end

    test "ref with path" do
      assert Diff.args(%Diff{ref: "HEAD~1", path: "lib/"}) ==
               ["diff", "HEAD~1", "--", "lib/"]
    end
  end

  describe "integration" do
    test "diff shows working tree changes", %{tmp_dir: tmp_dir, config: config} do
      # Modify the file
      File.write!(Path.join(tmp_dir, "hello.txt"), "hello world\n")

      assert {:ok, diff} = Git.diff(config: config)
      assert diff.raw =~ "hello world"
    end

    test "diff with staged shows cached changes", %{tmp_dir: tmp_dir, config: config} do
      # Modify and stage the file
      File.write!(Path.join(tmp_dir, "hello.txt"), "staged change\n")
      System.cmd("git", ["add", "hello.txt"], cd: tmp_dir)

      assert {:ok, diff} = Git.diff(staged: true, config: config)
      assert diff.raw =~ "staged change"
    end

    test "diff with name_only lists changed files", %{tmp_dir: tmp_dir, config: config} do
      File.write!(Path.join(tmp_dir, "hello.txt"), "changed\n")

      assert {:ok, diff} = Git.diff(name_only: true, config: config)
      assert diff.raw =~ "hello.txt"
    end

    test "empty diff when no changes", %{config: config} do
      assert {:ok, diff} = Git.diff(config: config)
      assert diff.raw == ""
    end
  end
end
