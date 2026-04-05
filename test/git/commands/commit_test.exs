defmodule Git.CommitTest do
  use ExUnit.Case, async: true

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
