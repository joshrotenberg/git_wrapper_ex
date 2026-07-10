defmodule Git.CommitTest do
  use ExUnit.Case, async: true

  alias Git.Commands.Commit
  alias Git.CommitResult
  alias Git.Config

  setup do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "git_wrapper_commit_test_#{:erlang.unique_integer([:positive])}"
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

  describe "commit with staged file" do
    test "returns a CommitResult with correct fields", %{tmp_dir: tmp_dir, config: config} do
      file_path = Path.join(tmp_dir, "hello.txt")
      File.write!(file_path, "hello world\n")
      System.cmd("git", ["add", "hello.txt"], cd: tmp_dir)

      assert {:ok, %CommitResult{} = result} =
               Git.commit("add hello file", config: config)

      assert result.branch == "main"
      assert String.length(result.hash) > 0
      assert result.subject == "add hello file"
      assert result.files_changed == 1
      assert result.insertions == 1
      assert result.deletions == 0
    end
  end

  describe "commit with all: true" do
    test "commits tracked modified files without explicit staging", %{
      tmp_dir: tmp_dir,
      config: config
    } do
      file_path = Path.join(tmp_dir, "tracked.txt")
      File.write!(file_path, "original\n")
      System.cmd("git", ["add", "tracked.txt"], cd: tmp_dir)

      System.cmd(
        "git",
        [
          "-c",
          "user.name=Test User",
          "-c",
          "user.email=test@test.com",
          "commit",
          "-m",
          "add tracked"
        ],
        cd: tmp_dir
      )

      File.write!(file_path, "modified\n")

      assert {:ok, %CommitResult{} = result} =
               Git.commit("update tracked file", config: config, all: true)

      assert result.subject == "update tracked file"
      assert result.files_changed == 1
    end
  end

  describe "commit with allow_empty: true" do
    test "creates a commit with no file changes", %{config: config} do
      assert {:ok, %CommitResult{} = result} =
               Git.commit("empty commit", config: config, allow_empty: true)

      assert result.subject == "empty commit"
      assert result.files_changed == 0
      assert result.insertions == 0
      assert result.deletions == 0
    end
  end

  describe "commit with amend: true" do
    test "amends the previous commit", %{tmp_dir: tmp_dir, config: config} do
      file_path = Path.join(tmp_dir, "amend.txt")
      File.write!(file_path, "content\n")
      System.cmd("git", ["add", "amend.txt"], cd: tmp_dir)

      {:ok, _} = Git.commit("original message", config: config)

      assert {:ok, %CommitResult{} = result} =
               Git.commit("amended message",
                 config: config,
                 amend: true,
                 allow_empty: true
               )

      assert result.subject == "amended message"
    end
  end

  describe "Git.Commands.Commit args/1" do
    test "builds -m and -a (unchanged output)" do
      assert Commit.args(%Commit{message: "test", all: true}) == ["commit", "-m", "test", "-a"]
    end

    test "omits -m for a message-less amend --no-edit" do
      assert Commit.args(%Commit{amend: true, no_edit: true}) ==
               ["commit", "--amend", "--no-edit"]
    end

    test "uses -F instead of -m when a file is given" do
      assert Commit.args(%Commit{file: "/tmp/msg", message: "ignored"}) ==
               ["commit", "-F", "/tmp/msg"]
    end

    test "emits value options" do
      command = %Commit{message: "m", signoff: true, author: "A U <a@u>", date: "2020-01-01"}

      assert Commit.args(command) ==
               ["commit", "-m", "m", "--signoff", "--author", "A U <a@u>", "--date", "2020-01-01"]
    end

    test "emits --no-verify" do
      assert Commit.args(%Commit{message: "m", no_verify: true}) ==
               ["commit", "-m", "m", "--no-verify"]
    end

    test "emits --fixup without a message" do
      assert Commit.args(%Commit{fixup: "HEAD~1"}) == ["commit", "--fixup", "HEAD~1"]
    end

    test "emits --only with a pathspec" do
      assert Commit.args(%Commit{message: "m", only: ["a.ex", "b.ex"]}) ==
               ["commit", "-m", "m", "--only", "--", "a.ex", "b.ex"]
    end

    test "emits -S when sign is true" do
      assert Commit.args(%Commit{message: "m", sign: true}) == ["commit", "-m", "m", "-S"]
    end

    test "emits -S<keyid> when sign is a keyid string" do
      assert Commit.args(%Commit{message: "m", sign: "ABCD1234"}) ==
               ["commit", "-m", "m", "-SABCD1234"]
    end

    test "omits -S when sign is false" do
      assert Commit.args(%Commit{message: "m", sign: false}) == ["commit", "-m", "m"]
    end
  end

  describe "commit flags reach git" do
    test "amend --no-edit keeps the previous message", %{tmp_dir: tmp_dir, config: config} do
      File.write!(Path.join(tmp_dir, "f.txt"), "v1\n")
      System.cmd("git", ["add", "f.txt"], cd: tmp_dir)
      {:ok, _} = Git.commit("keep this subject", config: config)

      File.write!(Path.join(tmp_dir, "f.txt"), "v2\n")
      System.cmd("git", ["add", "f.txt"], cd: tmp_dir)

      assert {:ok, %CommitResult{} = result} =
               Git.commit(nil, config: config, amend: true, no_edit: true)

      assert result.subject == "keep this subject"
    end

    test "no_verify skips a failing pre-commit hook", %{tmp_dir: tmp_dir, config: config} do
      # Use a repo-local hooksPath so this is deterministic regardless of any
      # global core.hooksPath on the machine running the test.
      hooks_dir = Path.join(tmp_dir, "hooks")
      File.mkdir_p!(hooks_dir)
      hook = Path.join(hooks_dir, "pre-commit")
      File.write!(hook, "#!/bin/sh\nexit 1\n")
      File.chmod!(hook, 0o755)
      System.cmd("git", ["config", "core.hooksPath", hooks_dir], cd: tmp_dir)

      File.write!(Path.join(tmp_dir, "g.txt"), "x\n")
      System.cmd("git", ["add", "g.txt"], cd: tmp_dir)

      # the hook rejects a normal commit
      assert {:error, _} = Git.commit("blocked", config: config)
      # but --no-verify bypasses it
      assert {:ok, %CommitResult{}} = Git.commit("bypassed", config: config, no_verify: true)
    end

    test "author overrides the recorded author", %{tmp_dir: tmp_dir, config: config} do
      File.write!(Path.join(tmp_dir, "h.txt"), "x\n")
      System.cmd("git", ["add", "h.txt"], cd: tmp_dir)

      assert {:ok, _} =
               Git.commit("with author",
                 config: config,
                 author: "Custom Author <custom@example.com>"
               )

      {out, 0} = System.cmd("git", ["log", "-1", "--format=%an <%ae>"], cd: tmp_dir)
      assert String.trim(out) == "Custom Author <custom@example.com>"
    end
  end

  describe "commit failure" do
    test "returns error when nothing to commit", %{config: config} do
      assert {:error, {output, exit_code}} =
               Git.commit("should fail", config: config)

      assert exit_code != 0
      assert is_binary(output)
    end
  end

  describe "CommitResult.parse/1" do
    test "parses standard commit output" do
      output =
        "[main abc1234] the commit message\n 1 file changed, 5 insertions(+), 2 deletions(-)\n"

      result = CommitResult.parse(output)

      assert result.branch == "main"
      assert result.hash == "abc1234"
      assert result.subject == "the commit message"
      assert result.files_changed == 1
      assert result.insertions == 5
      assert result.deletions == 2
    end

    test "parses root-commit output" do
      output =
        "[main (root-commit) abc1234] initial commit\n 1 file changed, 0 insertions(+), 0 deletions(-)\n create mode 100644 file.txt\n"

      result = CommitResult.parse(output)

      assert result.branch == "main"
      assert result.hash == "abc1234"
      assert result.subject == "initial commit"
      assert result.files_changed == 1
    end

    test "parses output with only insertions" do
      output = "[main def5678] add stuff\n 3 files changed, 10 insertions(+)\n"
      result = CommitResult.parse(output)

      assert result.files_changed == 3
      assert result.insertions == 10
      assert result.deletions == 0
    end

    test "parses output with only deletions" do
      output = "[main def5678] remove stuff\n 2 files changed, 5 deletions(-)\n"
      result = CommitResult.parse(output)

      assert result.files_changed == 2
      assert result.insertions == 0
      assert result.deletions == 5
    end
  end
end
