defmodule Git.Commands.PushTest do
  use ExUnit.Case, async: true

  alias Git.Commands.Push
  alias Git.Config

  # ---------------------------------------------------------------------------
  # args/1 unit tests
  # ---------------------------------------------------------------------------

  describe "args/1" do
    test "builds basic push args with no options" do
      assert Push.args(%Push{}) == ["push"]
    end

    test "adds remote and branch positional args" do
      assert Push.args(%Push{remote: "origin", branch: "main"}) ==
               ["push", "origin", "main"]
    end

    test "adds remote without branch" do
      assert Push.args(%Push{remote: "origin"}) == ["push", "origin"]
    end

    test "adds --force flag" do
      assert Push.args(%Push{force: true}) == ["push", "--force"]
    end

    test "adds --force-with-lease flag" do
      assert Push.args(%Push{force_with_lease: true}) == ["push", "--force-with-lease"]
    end

    test "adds -u flag for set_upstream" do
      assert Push.args(%Push{set_upstream: true, remote: "origin", branch: "feature"}) ==
               ["push", "-u", "origin", "feature"]
    end

    test "adds --tags flag" do
      assert Push.args(%Push{tags: true}) == ["push", "--tags"]
    end

    test "adds --delete flag" do
      assert Push.args(%Push{delete: true, remote: "origin", branch: "old-branch"}) ==
               ["push", "--delete", "origin", "old-branch"]
    end

    test "adds --dry-run flag" do
      assert Push.args(%Push{dry_run: true}) == ["push", "--dry-run"]
    end

    test "adds --all flag" do
      assert Push.args(%Push{all: true}) == ["push", "--all"]
    end

    test "adds --no-verify flag" do
      assert Push.args(%Push{no_verify: true}) == ["push", "--no-verify"]
    end

    test "adds --atomic flag" do
      assert Push.args(%Push{atomic: true}) == ["push", "--atomic"]
    end

    test "adds --prune flag" do
      assert Push.args(%Push{prune: true}) == ["push", "--prune"]
    end

    test "combines multiple flags" do
      assert Push.args(%Push{
               force: true,
               set_upstream: true,
               dry_run: true,
               remote: "origin",
               branch: "feature"
             }) == ["push", "--force", "-u", "--dry-run", "origin", "feature"]
    end
  end

  # ---------------------------------------------------------------------------
  # parse_output/2 unit tests
  # ---------------------------------------------------------------------------

  describe "parse_output/2" do
    test "returns {:ok, :done} on exit code 0" do
      assert {:ok, :done} = Push.parse_output("", 0)
    end

    test "returns {:ok, :done} on exit code 0 with output" do
      assert {:ok, :done} =
               Push.parse_output("To origin\n * [new branch] main -> main\n", 0)
    end

    test "returns {:error, {stdout, exit_code}} on non-zero exit" do
      assert {:error, {"error: failed to push\n", 1}} =
               Push.parse_output("error: failed to push\n", 1)
    end
  end

  # ---------------------------------------------------------------------------
  # Integration tests
  # ---------------------------------------------------------------------------

  setup do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "git_wrapper_push_test_#{:erlang.unique_integer([:positive])}"
      )

    File.mkdir_p!(tmp_dir)

    # Create a bare repo to act as remote
    remote_dir = Path.join(tmp_dir, "remote.git")
    File.mkdir_p!(remote_dir)
    System.cmd("git", ["init", "--bare", "--initial-branch=main"], cd: remote_dir)

    # Create local repo
    local_dir = Path.join(tmp_dir, "local")
    File.mkdir_p!(local_dir)
    System.cmd("git", ["init", "--initial-branch=main"], cd: local_dir)
    System.cmd("git", ["remote", "add", "origin", remote_dir], cd: local_dir)

    # Create an initial commit
    File.write!(Path.join(local_dir, "README.md"), "# Test\n")
    System.cmd("git", ["add", "README.md"], cd: local_dir)

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
      cd: local_dir
    )

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

    %{tmp_dir: tmp_dir, local_dir: local_dir, remote_dir: remote_dir, config: config}
  end

  describe "push integration" do
    test "pushes to a bare remote", %{config: config} do
      assert {:ok, :done} =
               Git.Command.run(
                 Push,
                 %Push{remote: "origin", branch: "main", set_upstream: true},
                 config
               )
    end

    test "push with --dry-run does not actually push", %{
      config: config,
      remote_dir: remote_dir
    } do
      assert {:ok, :done} =
               Git.Command.run(
                 Push,
                 %Push{remote: "origin", branch: "main", dry_run: true},
                 config
               )

      # Verify the remote still has no refs (dry run)
      {output, 0} = System.cmd("git", ["branch"], cd: remote_dir)
      assert output == ""
    end

    test "push --tags pushes tags to remote", %{
      local_dir: local_dir,
      config: config
    } do
      # First push the branch
      Git.Command.run(
        Push,
        %Push{remote: "origin", branch: "main"},
        config
      )

      # Create a tag
      System.cmd("git", ["tag", "v1.0.0"], cd: local_dir)

      assert {:ok, :done} =
               Git.Command.run(
                 Push,
                 %Push{remote: "origin", tags: true},
                 config
               )
    end

    test "push returns error when remote does not exist", %{config: config} do
      assert {:error, {_stdout, _exit_code}} =
               Git.Command.run(
                 Push,
                 %Push{remote: "nonexistent"},
                 config
               )
    end
  end
end
