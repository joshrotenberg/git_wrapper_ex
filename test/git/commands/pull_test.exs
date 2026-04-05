defmodule Git.Commands.PullTest do
  use ExUnit.Case, async: true

  alias Git.Commands.Pull
  alias Git.Config
  alias Git.PullResult

  # ---------------------------------------------------------------------------
  # args/1 unit tests
  # ---------------------------------------------------------------------------

  describe "args/1" do
    test "builds basic pull args with no options" do
      assert Pull.args(%Pull{}) == ["pull"]
    end

    test "adds remote and branch positional args" do
      assert Pull.args(%Pull{remote: "origin", branch: "main"}) ==
               ["pull", "origin", "main"]
    end

    test "adds remote without branch" do
      assert Pull.args(%Pull{remote: "origin"}) == ["pull", "origin"]
    end

    test "adds --rebase flag when rebase is true" do
      assert Pull.args(%Pull{rebase: true}) == ["pull", "--rebase"]
    end

    test "adds --rebase=interactive when rebase is a string" do
      assert Pull.args(%Pull{rebase: "interactive"}) == ["pull", "--rebase=interactive"]
    end

    test "adds --rebase=merges when rebase is merges string" do
      assert Pull.args(%Pull{rebase: "merges"}) == ["pull", "--rebase=merges"]
    end

    test "adds --ff-only flag" do
      assert Pull.args(%Pull{ff_only: true}) == ["pull", "--ff-only"]
    end

    test "adds --no-ff flag" do
      assert Pull.args(%Pull{no_ff: true}) == ["pull", "--no-ff"]
    end

    test "adds --autostash flag" do
      assert Pull.args(%Pull{autostash: true}) == ["pull", "--autostash"]
    end

    test "adds --no-autostash flag" do
      assert Pull.args(%Pull{no_autostash: true}) == ["pull", "--no-autostash"]
    end

    test "adds --squash flag" do
      assert Pull.args(%Pull{squash: true}) == ["pull", "--squash"]
    end

    test "adds --no-commit flag" do
      assert Pull.args(%Pull{no_commit: true}) == ["pull", "--no-commit"]
    end

    test "adds --depth flag" do
      assert Pull.args(%Pull{depth: 5}) == ["pull", "--depth=5"]
    end

    test "adds --dry-run flag" do
      assert Pull.args(%Pull{dry_run: true}) == ["pull", "--dry-run"]
    end

    test "adds --tags flag" do
      assert Pull.args(%Pull{tags: true}) == ["pull", "--tags"]
    end

    test "adds --no-tags flag" do
      assert Pull.args(%Pull{no_tags: true}) == ["pull", "--no-tags"]
    end

    test "adds --prune flag" do
      assert Pull.args(%Pull{prune: true}) == ["pull", "--prune"]
    end

    test "adds --verbose flag" do
      assert Pull.args(%Pull{verbose: true}) == ["pull", "--verbose"]
    end

    test "adds --quiet flag" do
      assert Pull.args(%Pull{quiet: true}) == ["pull", "--quiet"]
    end

    test "combines multiple flags with positional args" do
      assert Pull.args(%Pull{
               rebase: true,
               autostash: true,
               prune: true,
               remote: "origin",
               branch: "main"
             }) == ["pull", "--rebase", "--autostash", "--prune", "origin", "main"]
    end
  end

  # ---------------------------------------------------------------------------
  # parse_output/2 unit tests
  # ---------------------------------------------------------------------------

  describe "parse_output/2" do
    test "parses already up to date output" do
      assert {:ok, %PullResult{already_up_to_date: true}} =
               Pull.parse_output("Already up to date.\n", 0)
    end

    test "parses fast-forward output" do
      output = "Updating abc1234..def5678\nFast-forward\n file.txt | 1 +\n 1 file changed\n"

      assert {:ok, %PullResult{fast_forward: true, already_up_to_date: false}} =
               Pull.parse_output(output, 0)
    end

    test "parses merge commit output" do
      output = "Merge made by the 'ort' strategy.\n file.txt | 1 +\n 1 file changed\n"

      assert {:ok, %PullResult{merge_commit: true}} =
               Pull.parse_output(output, 0)
    end

    test "parses conflict output" do
      output = "CONFLICT (content): Merge conflict in file.txt\nAutomatic merge failed\n"

      assert {:ok, %PullResult{conflicts: true}} =
               Pull.parse_output(output, 0)
    end

    test "preserves raw output" do
      output = "Already up to date.\n"

      assert {:ok, %PullResult{raw: ^output}} =
               Pull.parse_output(output, 0)
    end

    test "returns error on non-zero exit code" do
      assert {:error, {"fatal: no remote configured\n", 1}} =
               Pull.parse_output("fatal: no remote configured\n", 1)
    end
  end

  # ---------------------------------------------------------------------------
  # PullResult.parse/1 unit tests
  # ---------------------------------------------------------------------------

  describe "PullResult.parse/1" do
    test "parses already up to date" do
      result = PullResult.parse("Already up to date.\n")
      assert result.already_up_to_date == true
      assert result.fast_forward == false
      assert result.merge_commit == false
      assert result.conflicts == false
    end

    test "parses fast-forward" do
      result = PullResult.parse("Updating abc..def\nFast-forward\n")
      assert result.fast_forward == true
      assert result.already_up_to_date == false
    end

    test "parses merge made by" do
      result = PullResult.parse("Merge made by the 'ort' strategy.\n")
      assert result.merge_commit == true
    end

    test "parses CONFLICT" do
      result = PullResult.parse("CONFLICT (content): Merge conflict in file.txt\n")
      assert result.conflicts == true
    end
  end

  # ---------------------------------------------------------------------------
  # Integration tests
  # ---------------------------------------------------------------------------

  setup do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "git_wrapper_pull_test_#{:erlang.unique_integer([:positive])}"
      )

    File.mkdir_p!(tmp_dir)

    # Create a bare repo to act as remote
    remote_dir = Path.join(tmp_dir, "remote.git")
    File.mkdir_p!(remote_dir)
    System.cmd("git", ["init", "--bare", "--initial-branch=main"], cd: remote_dir)

    # Create local repo and push initial commit
    local_dir = Path.join(tmp_dir, "local")
    File.mkdir_p!(local_dir)
    System.cmd("git", ["init", "--initial-branch=main"], cd: local_dir)
    System.cmd("git", ["remote", "add", "origin", remote_dir], cd: local_dir)

    git_opts = [cd: local_dir]

    File.write!(Path.join(local_dir, "README.md"), "# Test\n")
    System.cmd("git", ["add", "README.md"], git_opts)

    System.cmd(
      "git",
      [
        "-c",
        "user.name=Test User",
        "-c",
        "user.email=test@test.com",
        "commit",
        "-m",
        "initial commit"
      ],
      git_opts
    )

    System.cmd("git", ["push", "-u", "origin", "main"], git_opts)

    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    config =
      Config.new(
        working_dir: local_dir,
        env: [
          {"GIT_AUTHOR_NAME", "Test User"},
          {"GIT_AUTHOR_EMAIL", "test@test.com"},
          {"GIT_COMMITTER_NAME", "Test User"},
          {"GIT_COMMITTER_EMAIL", "test@test.com"}
        ]
      )

    %{
      tmp_dir: tmp_dir,
      local_dir: local_dir,
      remote_dir: remote_dir,
      config: config
    }
  end

  describe "pull integration" do
    test "pull with no new changes returns already up to date", %{config: config} do
      assert {:ok, %PullResult{already_up_to_date: true}} =
               Git.Command.run(
                 Pull,
                 %Pull{remote: "origin", branch: "main"},
                 config
               )
    end

    test "pull with new changes from remote", %{
      local_dir: local_dir,
      remote_dir: remote_dir,
      config: config
    } do
      # Clone a second working copy, make a change, and push it
      second_dir = Path.join(Path.dirname(local_dir), "second")
      System.cmd("git", ["clone", "--branch", "main", remote_dir, second_dir])

      File.write!(Path.join(second_dir, "new_file.txt"), "new content\n")
      System.cmd("git", ["add", "new_file.txt"], cd: second_dir)

      System.cmd(
        "git",
        [
          "-c",
          "user.name=Test User",
          "-c",
          "user.email=test@test.com",
          "commit",
          "-m",
          "add new file"
        ],
        cd: second_dir
      )

      System.cmd("git", ["push", "origin", "main"], cd: second_dir)

      # Now pull from the original local repo
      assert {:ok, %PullResult{already_up_to_date: false}} =
               Git.Command.run(
                 Pull,
                 %Pull{remote: "origin", branch: "main"},
                 config
               )

      # Verify the file was pulled
      assert File.exists?(Path.join(local_dir, "new_file.txt"))
    end

    test "pull returns error when remote does not exist", %{config: config} do
      assert {:error, {_stdout, _exit_code}} =
               Git.Command.run(
                 Pull,
                 %Pull{remote: "nonexistent", branch: "main"},
                 config
               )
    end
  end
end
