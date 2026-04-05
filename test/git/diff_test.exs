defmodule Git.DiffTest do
  use ExUnit.Case, async: true

  alias Git.Commands.Diff, as: DiffCmd
  alias Git.Diff

  # ---------------------------------------------------------------------------
  # Test helpers
  # ---------------------------------------------------------------------------

  defp setup_repo do
    dir =
      Path.join(
        System.tmp_dir!(),
        "git_wrapper_diff_test_#{:erlang.unique_integer([:positive])}"
      )

    File.mkdir_p!(dir)
    System.cmd("git", ["init", "--initial-branch=main"], cd: dir)
    System.cmd("git", ["config", "user.email", "test@example.com"], cd: dir)
    System.cmd("git", ["config", "user.name", "Test User"], cd: dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    {Git.Config.new(working_dir: dir), dir}
  end

  defp make_commit(dir, msg \\ "feat: initial") do
    env = [
      {"GIT_AUTHOR_NAME", "Test User"},
      {"GIT_AUTHOR_EMAIL", "test@example.com"},
      {"GIT_COMMITTER_NAME", "Test User"},
      {"GIT_COMMITTER_EMAIL", "test@example.com"}
    ]

    System.cmd("git", ["commit", "--allow-empty", "-m", msg], cd: dir, env: env)
  end

  # ---------------------------------------------------------------------------
  # Unit tests: Diff.parse/1
  # ---------------------------------------------------------------------------

  describe "Diff.parse/1" do
    test "empty string returns empty Diff" do
      assert %Diff{files: [], total_insertions: 0, total_deletions: 0} = Diff.parse("")
    end

    test "parses stat output with single file" do
      output = " lib/foo.ex | 2 +-\n 1 file changed, 1 insertion(+), 1 deletion(-)\n"
      diff = Diff.parse(output)

      assert diff.total_insertions == 1
      assert diff.total_deletions == 1
      assert length(diff.files) == 1
      assert hd(diff.files).path == "lib/foo.ex"
    end

    test "parses stat output with multiple files" do
      output = """
       lib/foo.ex |  5 +++++
       lib/bar.ex | 10 +++++++---
       2 files changed, 9 insertions(+), 3 deletions(-)
      """

      diff = Diff.parse(output)
      assert length(diff.files) == 2
      assert diff.total_insertions == 9
      assert diff.total_deletions == 3

      paths = Enum.map(diff.files, & &1.path)
      assert "lib/foo.ex" in paths
      assert "lib/bar.ex" in paths
    end

    test "parses summary line for insertions only" do
      output = " lib/foo.ex | 5 +++++\n 1 file changed, 5 insertions(+)\n"
      diff = Diff.parse(output)
      assert diff.total_insertions == 5
      assert diff.total_deletions == 0
    end

    test "parses summary line for deletions only" do
      output = " lib/foo.ex | 3 ---\n 1 file changed, 3 deletions(-)\n"
      diff = Diff.parse(output)
      assert diff.total_insertions == 0
      assert diff.total_deletions == 3
    end

    test "marks binary files correctly" do
      output = " image.png | Bin 0 -> 1234 bytes\n 1 file changed\n"
      diff = Diff.parse(output)

      assert length(diff.files) == 1
      file = hd(diff.files)
      assert file.path == "image.png"
      assert file.binary == true
    end

    test "stores raw output in raw field" do
      output = " lib/foo.ex | 2 +-\n 1 file changed, 1 insertion(+), 1 deletion(-)\n"
      diff = Diff.parse(output)
      assert diff.raw == output
    end

    test "full patch output (no stat) stores raw and has empty files list" do
      patch = "diff --git a/foo.ex b/foo.ex\nindex abc..def 100644\n--- a/foo.ex\n+++ b/foo.ex\n"
      diff = Diff.parse(patch)
      assert diff.files == []
      assert diff.raw == patch
    end
  end

  # ---------------------------------------------------------------------------
  # Unit tests: Commands.Diff.args/1
  # ---------------------------------------------------------------------------

  describe "Commands.Diff.args/1" do
    test "default struct produces bare diff args" do
      assert DiffCmd.args(%DiffCmd{}) == ["diff"]
    end

    test "staged: true adds --cached" do
      assert DiffCmd.args(%DiffCmd{staged: true}) == ["diff", "--cached"]
    end

    test "stat: true adds --stat" do
      assert DiffCmd.args(%DiffCmd{stat: true}) == ["diff", "--stat"]
    end

    test "staged and stat together" do
      assert DiffCmd.args(%DiffCmd{staged: true, stat: true}) == ["diff", "--cached", "--stat"]
    end

    test "ref adds the ref arg" do
      assert DiffCmd.args(%DiffCmd{ref: "HEAD~1"}) == ["diff", "HEAD~1"]
    end

    test "path adds -- separator and path" do
      assert DiffCmd.args(%DiffCmd{path: "lib/"}) == ["diff", "--", "lib/"]
    end

    test "ref and path together" do
      assert DiffCmd.args(%DiffCmd{ref: "HEAD~1", path: "lib/"}) == [
               "diff",
               "HEAD~1",
               "--",
               "lib/"
             ]
    end

    test "all options combined" do
      cmd = %DiffCmd{staged: true, stat: true, ref: "HEAD~1", path: "lib/"}
      assert DiffCmd.args(cmd) == ["diff", "--cached", "--stat", "HEAD~1", "--", "lib/"]
    end
  end

  # ---------------------------------------------------------------------------
  # Unit tests: Commands.Diff.parse_output/2
  # ---------------------------------------------------------------------------

  describe "Commands.Diff.parse_output/2" do
    test "returns ok Diff on exit 0" do
      output = " foo.ex | 1 +\n 1 file changed, 1 insertion(+)\n"
      assert {:ok, %Diff{}} = DiffCmd.parse_output(output, 0)
    end

    test "returns ok empty Diff on empty output" do
      assert {:ok, %Diff{files: [], raw: ""}} = DiffCmd.parse_output("", 0)
    end

    test "returns error tuple on non-zero exit" do
      assert {:error, {"bad revision", 128}} = DiffCmd.parse_output("bad revision", 128)
    end
  end

  # ---------------------------------------------------------------------------
  # Integration tests
  # ---------------------------------------------------------------------------

  describe "Git.diff/1 integration" do
    test "no changes returns empty diff" do
      {config, dir} = setup_repo()
      make_commit(dir)

      assert {:ok, %Diff{files: [], total_insertions: 0, total_deletions: 0}} =
               Git.diff(config: config)
    end

    test "unstaged changes appear in working-tree diff" do
      {config, dir} = setup_repo()
      make_commit(dir)
      File.write!(Path.join(dir, "tracked.txt"), "line1\n")
      System.cmd("git", ["add", "tracked.txt"], cd: dir)
      make_commit(dir, "feat: add tracked")

      File.write!(Path.join(dir, "tracked.txt"), "line1\nline2\n")

      assert {:ok, diff} = Git.diff(config: config)
      assert diff.raw != ""
    end

    test "staged diff with stat: true returns file stats" do
      {config, dir} = setup_repo()
      make_commit(dir)

      File.write!(Path.join(dir, "new.txt"), "hello\nworld\n")
      System.cmd("git", ["add", "new.txt"], cd: dir)

      assert {:ok, diff} = Git.diff(config: config, staged: true, stat: true)
      assert diff.total_insertions > 0
      assert Enum.any?(diff.files, &(&1.path == "new.txt"))
    end

    test "staged diff with no staged changes returns empty diff" do
      {config, dir} = setup_repo()
      make_commit(dir)

      assert {:ok, %Diff{files: [], total_insertions: 0}} =
               Git.diff(config: config, staged: true, stat: true)
    end

    test "diff with ref compares against that ref" do
      {config, dir} = setup_repo()
      make_commit(dir, "feat: first")

      File.write!(Path.join(dir, "a.txt"), "content\n")
      System.cmd("git", ["add", "a.txt"], cd: dir)
      make_commit(dir, "feat: second")

      assert {:ok, diff} = Git.diff(config: config, ref: "HEAD~1", stat: true)
      assert diff.total_insertions > 0
    end
  end
end
