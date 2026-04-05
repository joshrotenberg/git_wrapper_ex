defmodule Git.MvTest do
  use ExUnit.Case, async: true

  alias Git.Commands.Mv
  alias Git.Config

  setup do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "git_wrapper_mv_test_#{:erlang.unique_integer([:positive])}"
      )

    File.mkdir_p!(tmp_dir)

    System.cmd("git", ["init", "--initial-branch=main"], cd: tmp_dir)

    System.cmd(
      "git",
      [
        "-c",
        "user.name=Test User",
        "-c",
        "user.email=test@test.com",
        "commit",
        "--allow-empty",
        "-m",
        "initial"
      ],
      cd: tmp_dir
    )

    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    config =
      Config.new(
        working_dir: tmp_dir,
        env: [
          {"GIT_AUTHOR_NAME", "Test User"},
          {"GIT_AUTHOR_EMAIL", "test@test.com"},
          {"GIT_COMMITTER_NAME", "Test User"},
          {"GIT_COMMITTER_EMAIL", "test@test.com"}
        ]
      )

    %{tmp_dir: tmp_dir, config: config}
  end

  describe "Git.Commands.Mv args/1" do
    test "builds args for a basic move" do
      assert Mv.args(%Mv{source: "a.txt", destination: "b.txt"}) == ["mv", "a.txt", "b.txt"]
    end

    test "builds args with force flag" do
      assert Mv.args(%Mv{source: "a.txt", destination: "b.txt", force: true}) ==
               ["mv", "-f", "a.txt", "b.txt"]
    end

    test "builds args with dry_run and verbose flags" do
      assert Mv.args(%Mv{source: "a.txt", destination: "b.txt", dry_run: true, verbose: true}) ==
               ["mv", "-n", "-v", "a.txt", "b.txt"]
    end

    test "builds args with skip_errors flag" do
      assert Mv.args(%Mv{source: "a.txt", destination: "b.txt", skip_errors: true}) ==
               ["mv", "-k", "a.txt", "b.txt"]
    end
  end

  describe "mv a tracked file" do
    test "moves a file and stages the change", %{tmp_dir: tmp_dir, config: config} do
      File.write!(Path.join(tmp_dir, "original.txt"), "content\n")
      System.cmd("git", ["add", "original.txt"], cd: tmp_dir)

      System.cmd(
        "git",
        [
          "-c",
          "user.name=Test User",
          "-c",
          "user.email=test@test.com",
          "commit",
          "-m",
          "add original"
        ],
        cd: tmp_dir
      )

      assert {:ok, :done} =
               Git.Command.run(
                 Mv,
                 %Mv{source: "original.txt", destination: "renamed.txt"},
                 config
               )

      refute File.exists?(Path.join(tmp_dir, "original.txt"))
      assert File.exists?(Path.join(tmp_dir, "renamed.txt"))
    end
  end

  describe "mv failure" do
    test "returns error for a non-existent file", %{config: config} do
      assert {:error, {output, exit_code}} =
               Git.Command.run(
                 Mv,
                 %Mv{source: "nonexistent.txt", destination: "dest.txt"},
                 config
               )

      assert exit_code != 0
      assert is_binary(output)
    end
  end
end
