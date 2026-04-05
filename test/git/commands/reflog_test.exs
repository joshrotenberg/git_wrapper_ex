defmodule Git.ReflogTest do
  use ExUnit.Case, async: true

  alias Git.{Config, ReflogEntry}
  alias Git.Commands.Reflog

  setup do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "git_wrapper_reflog_test_#{:erlang.unique_integer([:positive])}"
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

  describe "args/1" do
    test "default produces reflog with format" do
      args = Reflog.args(%Reflog{})
      assert hd(args) == "reflog"
      assert Enum.any?(args, &String.starts_with?(&1, "--format="))
    end

    test "max_count adds -n flag" do
      args = Reflog.args(%Reflog{max_count: 5})
      assert "-n5" in args
    end

    test "all adds --all flag" do
      args = Reflog.args(%Reflog{all: true})
      assert "--all" in args
    end

    test "ref is appended at end" do
      args = Reflog.args(%Reflog{ref: "main"})
      assert List.last(args) == "main"
    end

    test "date adds --date option" do
      args = Reflog.args(%Reflog{date: "relative"})
      assert "--date=relative" in args
    end
  end

  describe "reflog entries" do
    test "returns a list of ReflogEntry structs", %{config: config} do
      assert {:ok, entries} =
               Git.Command.run(Reflog, %Reflog{}, config)

      assert is_list(entries)
      assert length(entries) >= 1

      [latest | _] = entries
      assert %ReflogEntry{} = latest
      assert String.length(latest.hash) == 40
      assert String.length(latest.abbreviated_hash) > 0
      assert latest.selector != ""
    end

    test "max_count limits results", %{tmp_dir: tmp_dir, config: config} do
      # Create additional commits to have more reflog entries
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
          "second"
        ],
        cd: tmp_dir
      )

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
          "third"
        ],
        cd: tmp_dir
      )

      assert {:ok, entries} =
               Git.Command.run(Reflog, %Reflog{max_count: 1}, config)

      assert length(entries) == 1
    end

    test "entries have action field populated", %{config: config} do
      assert {:ok, [entry | _]} =
               Git.Command.run(Reflog, %Reflog{}, config)

      # The initial commit reflog entry should have a commit action
      assert entry.action != ""
    end
  end
end
