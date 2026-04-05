defmodule Git.BisectTest do
  use ExUnit.Case, async: true

  alias Git.{BisectResult, Config}
  alias Git.Commands.Bisect

  setup do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "git_wrapper_bisect_test_#{:erlang.unique_integer([:positive])}"
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
    test "start produces correct args" do
      assert Bisect.args(%Bisect{start: true}) == ["bisect", "start"]
    end

    test "bad with :head produces correct args" do
      assert Bisect.args(%Bisect{bad: :head}) == ["bisect", "bad"]
    end

    test "bad with ref produces correct args" do
      assert Bisect.args(%Bisect{bad: "abc1234"}) == ["bisect", "bad", "abc1234"]
    end

    test "good with :head produces correct args" do
      assert Bisect.args(%Bisect{good: :head}) == ["bisect", "good"]
    end

    test "good with ref produces correct args" do
      assert Bisect.args(%Bisect{good: "abc1234"}) == ["bisect", "good", "abc1234"]
    end

    test "reset produces correct args" do
      assert Bisect.args(%Bisect{reset: true}) == ["bisect", "reset"]
    end

    test "log produces correct args" do
      assert Bisect.args(%Bisect{log: true}) == ["bisect", "log"]
    end

    test "skip with :head produces correct args" do
      assert Bisect.args(%Bisect{skip: :head}) == ["bisect", "skip"]
    end

    test "skip with ref produces correct args" do
      assert Bisect.args(%Bisect{skip: "abc1234"}) == ["bisect", "skip", "abc1234"]
    end

    test "replay produces correct args" do
      assert Bisect.args(%Bisect{replay: "/tmp/log"}) == ["bisect", "replay", "/tmp/log"]
    end

    test "new_ref produces correct args" do
      assert Bisect.args(%Bisect{new_ref: "abc1234"}) == ["bisect", "new", "abc1234"]
    end

    test "old_ref produces correct args" do
      assert Bisect.args(%Bisect{old_ref: "abc1234"}) == ["bisect", "old", "abc1234"]
    end
  end

  describe "bisect start and reset" do
    test "starts and resets a bisect session", %{config: config} do
      assert {:ok, %BisectResult{status: :started}} =
               Git.Command.run(Bisect, %Bisect{start: true}, config)

      assert {:ok, %BisectResult{status: :done}} =
               Git.Command.run(Bisect, %Bisect{reset: true}, config)
    end
  end

  describe "bisect marking" do
    test "marks bad and good commits", %{tmp_dir: tmp_dir, config: config} do
      # Create several commits so bisect has something to work with
      for i <- 1..5 do
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
            "commit #{i}"
          ],
          cd: tmp_dir
        )
      end

      # Get the first commit hash
      {first_hash, 0} = System.cmd("git", ["rev-list", "--max-parents=0", "HEAD"], cd: tmp_dir)
      first_hash = String.trim(first_hash)

      # Start bisect
      {:ok, %BisectResult{status: :started}} =
        Git.Command.run(Bisect, %Bisect{start: true}, config)

      # Mark HEAD as bad
      assert {:ok, %BisectResult{}} =
               Git.Command.run(Bisect, %Bisect{bad: :head}, config)

      # Mark first commit as good - this should trigger stepping
      assert {:ok, %BisectResult{} = result} =
               Git.Command.run(Bisect, %Bisect{good: first_hash}, config)

      assert result.status in [:stepping, :found]

      # Reset to clean up
      {:ok, _} = Git.Command.run(Bisect, %Bisect{reset: true}, config)
    end
  end

  describe "BisectResult parsing" do
    test "parse_output detects stepping" do
      stdout =
        "Bisecting: 2 revisions left to test after this (roughly 2 steps)\n[abc1234def] some message\n"

      assert {:ok, %BisectResult{status: :stepping, current_commit: "abc1234def"}} =
               Bisect.parse_output(stdout, 0)
    end

    test "parse_output detects found" do
      stdout = "abc1234def5678 is the first bad commit\ncommit abc1234def5678\n"

      # Need to set up the process dict mode
      Process.put(:__git_bisect_mode__, :mark)

      assert {:ok, %BisectResult{status: :found, bad_commit: "abc1234def5678"}} =
               Bisect.parse_output(stdout, 0)
    end

    test "parse_output handles errors" do
      assert {:error, {"error msg", 1}} = Bisect.parse_output("error msg", 1)
    end
  end
end
