defmodule Git.RevParseTest do
  use ExUnit.Case, async: true

  alias Git.Commands.RevParse
  alias Git.Config

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
        "git_wrapper_rev_parse_test_#{:erlang.unique_integer([:positive])}"
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

  describe "Git.Commands.RevParse args/1" do
    test "builds args with ref only" do
      assert RevParse.args(%RevParse{ref: "HEAD"}) == ["rev-parse", "HEAD"]
    end

    test "builds args with --show-toplevel" do
      assert RevParse.args(%RevParse{show_toplevel: true}) == ["rev-parse", "--show-toplevel"]
    end

    test "builds args with --verify and ref" do
      assert RevParse.args(%RevParse{verify: true, ref: "HEAD"}) ==
               ["rev-parse", "--verify", "HEAD"]
    end

    test "builds args with --short boolean" do
      assert RevParse.args(%RevParse{short: true, ref: "HEAD"}) ==
               ["rev-parse", "--short", "HEAD"]
    end

    test "builds args with --short=N integer" do
      assert RevParse.args(%RevParse{short: 8, ref: "HEAD"}) ==
               ["rev-parse", "--short=8", "HEAD"]
    end

    test "builds args with --abbrev-ref" do
      assert RevParse.args(%RevParse{abbrev_ref: true, ref: "HEAD"}) ==
               ["rev-parse", "--abbrev-ref", "HEAD"]
    end

    test "builds args with --is-inside-work-tree" do
      assert RevParse.args(%RevParse{is_inside_work_tree: true}) ==
               ["rev-parse", "--is-inside-work-tree"]
    end

    test "builds args with --git-dir" do
      assert RevParse.args(%RevParse{git_dir: true}) == ["rev-parse", "--git-dir"]
    end
  end

  describe "git rev-parse HEAD" do
    test "resolves HEAD to a full SHA", %{config: config} do
      {:ok, sha} =
        Git.Command.run(RevParse, %RevParse{ref: "HEAD"}, config)

      assert String.match?(sha, ~r/^[0-9a-f]{40}$/)
    end
  end

  describe "git rev-parse --show-toplevel" do
    test "returns the repository root directory", %{tmp_dir: tmp_dir, config: config} do
      {:ok, toplevel} =
        Git.Command.run(RevParse, %RevParse{show_toplevel: true}, config)

      # On macOS, /tmp and /var are symlinks into /private. Git resolves
      # symlinks so it may return /private/var/... while tmp_dir uses /var/...
      # We strip any /private prefix from both sides to compare reliably.
      strip_private = fn path ->
        String.replace_prefix(path, "/private", "")
      end

      assert strip_private.(toplevel) == strip_private.(tmp_dir)
    end
  end

  describe "git rev-parse --is-inside-work-tree" do
    test "returns true inside a work tree", %{config: config} do
      {:ok, result} =
        Git.Command.run(RevParse, %RevParse{is_inside_work_tree: true}, config)

      assert result == "true"
    end
  end

  describe "git rev-parse --abbrev-ref" do
    test "returns the branch name for HEAD", %{config: config} do
      {:ok, branch} =
        Git.Command.run(RevParse, %RevParse{abbrev_ref: true, ref: "HEAD"}, config)

      assert branch == "main"
    end
  end

  describe "git rev-parse --verify" do
    test "succeeds for a valid ref", %{config: config} do
      {:ok, sha} =
        Git.Command.run(RevParse, %RevParse{verify: true, ref: "HEAD"}, config)

      assert String.match?(sha, ~r/^[0-9a-f]{40}$/)
    end

    test "returns error for an invalid ref", %{config: config} do
      assert {:error, {_output, exit_code}} =
               Git.Command.run(
                 RevParse,
                 %RevParse{verify: true, ref: "nonexistent-ref-abc123"},
                 config
               )

      assert exit_code != 0
    end
  end
end
