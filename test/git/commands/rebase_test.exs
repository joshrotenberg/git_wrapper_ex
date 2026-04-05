defmodule Git.RebaseTest do
  use ExUnit.Case, async: true

  alias Git.Commands.Rebase
  alias Git.Config
  alias Git.RebaseResult

  @env [
    {"GIT_AUTHOR_NAME", "Test User"},
    {"GIT_AUTHOR_EMAIL", "test@test.com"},
    {"GIT_COMMITTER_NAME", "Test User"},
    {"GIT_COMMITTER_EMAIL", "test@test.com"}
  ]

  setup do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "git_wrapper_rebase_test_#{:erlang.unique_integer([:positive])}"
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
        "initial commit"
      ],
      cd: tmp_dir
    )

    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    config = Config.new(working_dir: tmp_dir, env: @env)
    %{tmp_dir: tmp_dir, config: config}
  end

  describe "args/1" do
    test "builds args for abort" do
      assert Rebase.args(%Rebase{abort: true}) == ["rebase", "--abort"]
    end

    test "builds args for continue" do
      assert Rebase.args(%Rebase{continue_rebase: true}) == ["rebase", "--continue"]
    end

    test "builds args for skip" do
      assert Rebase.args(%Rebase{skip: true}) == ["rebase", "--skip"]
    end

    test "builds args with upstream" do
      assert Rebase.args(%Rebase{upstream: "main"}) == ["rebase", "main"]
    end

    test "builds args with upstream and branch" do
      assert Rebase.args(%Rebase{upstream: "main", branch: "feat"}) ==
               ["rebase", "main", "feat"]
    end

    test "builds args with --onto" do
      assert Rebase.args(%Rebase{onto: "main", upstream: "feature"}) ==
               ["rebase", "--onto", "main", "feature"]
    end

    test "builds args with boolean flags" do
      assert Rebase.args(%Rebase{upstream: "main", autostash: true, verbose: true}) ==
               ["rebase", "--autostash", "--verbose", "main"]
    end

    test "builds args with force-rebase" do
      assert Rebase.args(%Rebase{upstream: "main", force_rebase: true}) ==
               ["rebase", "--force-rebase", "main"]
    end
  end

  describe "rebase up to date" do
    test "returns up_to_date when already on the upstream", %{config: config} do
      result = Git.Command.run(Rebase, %Rebase{upstream: "main"}, config)

      assert {:ok, %RebaseResult{up_to_date: true}} = result
    end
  end

  describe "rebase fast-forward" do
    test "fast-forwards when behind upstream", %{tmp_dir: tmp_dir, config: config} do
      # Create a commit on main, then a branch from the parent
      System.cmd("git", ["checkout", "-b", "feature"], cd: tmp_dir)
      System.cmd("git", ["checkout", "main"], cd: tmp_dir)

      File.write!(Path.join(tmp_dir, "main.txt"), "main content\n")
      System.cmd("git", ["add", "main.txt"], cd: tmp_dir)

      System.cmd(
        "git",
        [
          "-c",
          "user.name=Test User",
          "-c",
          "user.email=test@test.com",
          "commit",
          "-m",
          "main advance"
        ],
        cd: tmp_dir
      )

      System.cmd("git", ["checkout", "feature"], cd: tmp_dir)

      result = Git.Command.run(Rebase, %Rebase{upstream: "main"}, config)

      assert {:ok, %RebaseResult{} = rebase_result} = result
      assert rebase_result.fast_forward == true or rebase_result.up_to_date == false
    end
  end

  describe "rebase with diverged branches" do
    test "rebases a diverged branch successfully", %{tmp_dir: tmp_dir, config: config} do
      # Create diverged branches
      System.cmd("git", ["checkout", "-b", "feature"], cd: tmp_dir)
      File.write!(Path.join(tmp_dir, "feature.txt"), "feature content\n")
      System.cmd("git", ["add", "feature.txt"], cd: tmp_dir)

      System.cmd(
        "git",
        [
          "-c",
          "user.name=Test User",
          "-c",
          "user.email=test@test.com",
          "commit",
          "-m",
          "feature commit"
        ],
        cd: tmp_dir
      )

      System.cmd("git", ["checkout", "main"], cd: tmp_dir)
      File.write!(Path.join(tmp_dir, "main.txt"), "main content\n")
      System.cmd("git", ["add", "main.txt"], cd: tmp_dir)

      System.cmd(
        "git",
        [
          "-c",
          "user.name=Test User",
          "-c",
          "user.email=test@test.com",
          "commit",
          "-m",
          "main commit"
        ],
        cd: tmp_dir
      )

      System.cmd("git", ["checkout", "feature"], cd: tmp_dir)

      result = Git.Command.run(Rebase, %Rebase{upstream: "main"}, config)
      assert {:ok, %RebaseResult{}} = result
    end
  end

  describe "rebase abort" do
    test "aborts an in-progress rebase and returns :done", %{tmp_dir: tmp_dir, config: config} do
      # Create conflicting branches
      System.cmd("git", ["checkout", "-b", "conflict-branch"], cd: tmp_dir)
      File.write!(Path.join(tmp_dir, "conflict.txt"), "branch version\n")
      System.cmd("git", ["add", "conflict.txt"], cd: tmp_dir)

      System.cmd(
        "git",
        [
          "-c",
          "user.name=Test User",
          "-c",
          "user.email=test@test.com",
          "commit",
          "-m",
          "branch change"
        ],
        cd: tmp_dir
      )

      System.cmd("git", ["checkout", "main"], cd: tmp_dir)
      File.write!(Path.join(tmp_dir, "conflict.txt"), "main version\n")
      System.cmd("git", ["add", "conflict.txt"], cd: tmp_dir)

      System.cmd(
        "git",
        [
          "-c",
          "user.name=Test User",
          "-c",
          "user.email=test@test.com",
          "commit",
          "-m",
          "main change"
        ],
        cd: tmp_dir
      )

      System.cmd("git", ["checkout", "conflict-branch"], cd: tmp_dir)

      # Trigger a conflicting rebase (expect failure)
      {:error, _} = Git.Command.run(Rebase, %Rebase{upstream: "main"}, config)

      # Now abort it
      assert {:ok, :done} = Git.Command.run(Rebase, %Rebase{abort: true}, config)
    end
  end

  describe "rebase failure" do
    test "returns an error for nonexistent upstream", %{config: config} do
      assert {:error, {output, exit_code}} =
               Git.Command.run(Rebase, %Rebase{upstream: "nonexistent-branch"}, config)

      assert exit_code != 0
      assert is_binary(output)
    end
  end

  describe "RebaseResult.parse/1" do
    test "parses up to date output" do
      output = "Current branch main is up to date.\n"
      result = RebaseResult.parse(output)

      assert result.up_to_date == true
      assert result.fast_forward == false
      assert result.conflicts == false
      assert result.raw == output
    end

    test "parses fast-forward output" do
      output = "Successfully rebased and updated refs/heads/feat.\nFast-forwarded main to feat.\n"
      result = RebaseResult.parse(output)

      assert result.fast_forward == true
      assert result.up_to_date == false
    end

    test "parses conflict output" do
      output = "CONFLICT (content): Merge conflict in file.txt\n"
      result = RebaseResult.parse(output)

      assert result.conflicts == true
      assert result.fast_forward == false
      assert result.up_to_date == false
    end
  end
end
