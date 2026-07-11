defmodule Git.ReflogTest do
  use ExUnit.Case, async: true

  alias Git.Commands.Reflog
  alias Git.{Config, ReflogEntry}

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

    on_exit(fn -> Git.TestHelpers.rm_rf(tmp_dir) end)

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

    test "expire builds the expire subcommand" do
      assert Reflog.args(%Reflog{expire: true, expire_time: "now", all: true}) ==
               ["reflog", "expire", "--expire=now", "--all"]
    end

    test "expire with a ref and dry_run" do
      assert Reflog.args(%Reflog{
               expire: true,
               expire_time: "30.days",
               dry_run: true,
               ref: "HEAD"
             }) ==
               ["reflog", "expire", "--expire=30.days", "--dry-run", "HEAD"]
    end
  end

  describe "reflog expire (integration)" do
    test "expiring all reflogs empties the log", %{tmp_dir: tmp_dir, config: config} do
      # a couple more entries so there is something to expire
      System.cmd("git", ["commit", "--allow-empty", "-m", "second"], cd: tmp_dir)
      System.cmd("git", ["commit", "--allow-empty", "-m", "third"], cd: tmp_dir)

      {:ok, before} = Git.reflog(config: config)
      assert before != []

      assert {:ok, :done} =
               Git.reflog(expire: true, expire_time: "now", all: true, config: config)

      {:ok, after_expire} = Git.reflog(config: config)
      assert after_expire == []
    end

    test "dry_run reports without modifying the reflog", %{config: config} do
      {:ok, before} = Git.reflog(config: config)

      assert {:ok, :done} =
               Git.reflog(
                 expire: true,
                 expire_time: "now",
                 all: true,
                 dry_run: true,
                 config: config
               )

      {:ok, after_dry} = Git.reflog(config: config)
      assert length(after_dry) == length(before)
    end
  end

  describe "reflog entries" do
    test "returns a list of ReflogEntry structs", %{config: config} do
      assert {:ok, entries} =
               Git.Command.run(Reflog, %Reflog{}, config)

      assert is_list(entries)
      assert entries != []

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
