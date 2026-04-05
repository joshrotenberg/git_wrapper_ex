defmodule Git.Commands.FetchTest do
  use ExUnit.Case, async: true

  alias Git.Commands.Fetch
  alias Git.Config

  # ---------------------------------------------------------------------------
  # args/1 unit tests
  # ---------------------------------------------------------------------------

  describe "args/1" do
    test "builds basic fetch args with no options" do
      assert Fetch.args(%Fetch{}) == ["fetch"]
    end

    test "adds remote positional arg" do
      assert Fetch.args(%Fetch{remote: "origin"}) == ["fetch", "origin"]
    end

    test "adds remote and branch positional args" do
      assert Fetch.args(%Fetch{remote: "origin", branch: "main"}) ==
               ["fetch", "origin", "main"]
    end

    test "adds --all flag" do
      assert Fetch.args(%Fetch{all: true}) == ["fetch", "--all"]
    end

    test "adds --prune flag" do
      assert Fetch.args(%Fetch{prune: true}) == ["fetch", "--prune"]
    end

    test "adds --prune-tags flag" do
      assert Fetch.args(%Fetch{prune_tags: true}) == ["fetch", "--prune-tags"]
    end

    test "adds --tags flag" do
      assert Fetch.args(%Fetch{tags: true}) == ["fetch", "--tags"]
    end

    test "adds --no-tags flag" do
      assert Fetch.args(%Fetch{no_tags: true}) == ["fetch", "--no-tags"]
    end

    test "adds --depth flag" do
      assert Fetch.args(%Fetch{depth: 1}) == ["fetch", "--depth=1"]
    end

    test "adds --unshallow flag" do
      assert Fetch.args(%Fetch{unshallow: true}) == ["fetch", "--unshallow"]
    end

    test "adds --dry-run flag" do
      assert Fetch.args(%Fetch{dry_run: true}) == ["fetch", "--dry-run"]
    end

    test "adds --force flag" do
      assert Fetch.args(%Fetch{force: true}) == ["fetch", "--force"]
    end

    test "adds --verbose flag" do
      assert Fetch.args(%Fetch{verbose: true}) == ["fetch", "--verbose"]
    end

    test "adds --quiet flag" do
      assert Fetch.args(%Fetch{quiet: true}) == ["fetch", "--quiet"]
    end

    test "adds --jobs flag" do
      assert Fetch.args(%Fetch{jobs: 4}) == ["fetch", "--jobs=4"]
    end

    test "adds --recurse-submodules flag when true" do
      assert Fetch.args(%Fetch{recurse_submodules: true}) == ["fetch", "--recurse-submodules"]
    end

    test "adds --recurse-submodules=on-demand when string" do
      assert Fetch.args(%Fetch{recurse_submodules: "on-demand"}) ==
               ["fetch", "--recurse-submodules=on-demand"]
    end

    test "adds --set-upstream flag" do
      assert Fetch.args(%Fetch{set_upstream: true}) == ["fetch", "--set-upstream"]
    end

    test "combines multiple flags with positional args" do
      assert Fetch.args(%Fetch{
               all: true,
               prune: true,
               tags: true,
               verbose: true
             }) == ["fetch", "--all", "--prune", "--tags", "--verbose"]
    end

    test "combines flags with remote and branch" do
      assert Fetch.args(%Fetch{
               depth: 1,
               force: true,
               remote: "upstream",
               branch: "main"
             }) == ["fetch", "--depth=1", "--force", "upstream", "main"]
    end
  end

  # ---------------------------------------------------------------------------
  # parse_output/2 unit tests
  # ---------------------------------------------------------------------------

  describe "parse_output/2" do
    test "returns {:ok, :done} on exit code 0" do
      assert {:ok, :done} = Fetch.parse_output("", 0)
    end

    test "returns {:ok, :done} on exit code 0 with output" do
      assert {:ok, :done} =
               Fetch.parse_output(
                 "From /tmp/remote\n * branch main -> FETCH_HEAD\n",
                 0
               )
    end

    test "returns {:error, {stdout, exit_code}} on non-zero exit" do
      assert {:error, {"fatal: 'nonexistent' does not appear to be a git repository\n", 128}} =
               Fetch.parse_output(
                 "fatal: 'nonexistent' does not appear to be a git repository\n",
                 128
               )
    end
  end

  # ---------------------------------------------------------------------------
  # Integration tests
  # ---------------------------------------------------------------------------

  setup do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "git_wrapper_fetch_test_#{:erlang.unique_integer([:positive])}"
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

  describe "fetch integration" do
    test "fetches from remote with no new changes", %{config: config} do
      assert {:ok, :done} =
               Git.Command.run(
                 Fetch,
                 %Fetch{remote: "origin"},
                 config
               )
    end

    test "fetches new changes from remote", %{
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

      # Fetch from origin
      assert {:ok, :done} =
               Git.Command.run(
                 Fetch,
                 %Fetch{remote: "origin"},
                 config
               )

      # Verify the fetch updated the remote tracking branch
      {log_output, 0} =
        System.cmd("git", ["log", "--oneline", "origin/main"], cd: local_dir)

      assert String.contains?(log_output, "add new file")
    end

    test "fetch with --prune removes stale tracking branches", %{
      local_dir: local_dir,
      remote_dir: remote_dir,
      config: config
    } do
      # Create a second working copy, create a branch, push it
      second_dir = Path.join(Path.dirname(local_dir), "second")
      System.cmd("git", ["clone", "--branch", "main", remote_dir, second_dir])

      System.cmd("git", ["checkout", "-b", "temp-branch"], cd: second_dir)

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
          "temp"
        ],
        cd: second_dir
      )

      System.cmd("git", ["push", "origin", "temp-branch"], cd: second_dir)

      # Fetch from local repo so it knows about the branch
      System.cmd("git", ["fetch", "origin"], cd: local_dir)

      # Delete the branch from remote
      System.cmd("git", ["push", "origin", "--delete", "temp-branch"], cd: second_dir)

      # Fetch with prune should remove the stale tracking branch
      assert {:ok, :done} =
               Git.Command.run(
                 Fetch,
                 %Fetch{remote: "origin", prune: true},
                 config
               )

      # Verify the tracking branch was removed
      {branch_output, 0} = System.cmd("git", ["branch", "-r"], cd: local_dir)
      refute String.contains?(branch_output, "temp-branch")
    end

    test "fetch --dry-run does not actually fetch", %{
      local_dir: local_dir,
      remote_dir: remote_dir,
      config: config
    } do
      # Clone a second working copy, make a change, and push it
      second_dir = Path.join(Path.dirname(local_dir), "second")
      System.cmd("git", ["clone", "--branch", "main", remote_dir, second_dir])

      File.write!(Path.join(second_dir, "new_file.txt"), "content\n")
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
          "new file"
        ],
        cd: second_dir
      )

      System.cmd("git", ["push", "origin", "main"], cd: second_dir)

      # Get the current origin/main ref before dry-run fetch
      {before_ref, 0} =
        System.cmd("git", ["rev-parse", "origin/main"], cd: local_dir)

      assert {:ok, :done} =
               Git.Command.run(
                 Fetch,
                 %Fetch{remote: "origin", dry_run: true},
                 config
               )

      # Verify origin/main did not change
      {after_ref, 0} =
        System.cmd("git", ["rev-parse", "origin/main"], cd: local_dir)

      assert before_ref == after_ref
    end

    test "fetch returns error when remote does not exist", %{config: config} do
      assert {:error, {_stdout, _exit_code}} =
               Git.Command.run(
                 Fetch,
                 %Fetch{remote: "nonexistent"},
                 config
               )
    end
  end
end
