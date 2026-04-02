defmodule GitWrapperExTest do
  use ExUnit.Case

  alias GitWrapper.Config
  alias GitWrapper.Commands.{Commit, Log}

  # ---------------------------------------------------------------------------
  # Test helpers
  # ---------------------------------------------------------------------------

  defp setup_repo do
    dir = Path.join(System.tmp_dir!(), "git_wrapper_test_#{:rand.uniform(1_000_000)}")
    File.mkdir_p!(dir)

    System.cmd("git", ["init"], cd: dir)
    System.cmd("git", ["config", "user.email", "test@example.com"], cd: dir)
    System.cmd("git", ["config", "user.name", "Test User"], cd: dir)

    Config.new(working_dir: dir)
  end

  defp create_file_and_stage(dir, filename, content \\ "hello\n") do
    path = Path.join(dir, filename)
    File.write!(path, content)
    System.cmd("git", ["add", filename], cd: dir)
    path
  end

  defp make_commit(dir, message) do
    System.cmd("git", ["commit", "-m", message], cd: dir)
  end

  # ---------------------------------------------------------------------------
  # GitWrapper.Status.parse/1 unit tests
  # ---------------------------------------------------------------------------

  describe "GitWrapper.Status.parse/1" do
    test "parses empty output" do
      result = GitWrapper.Status.parse("")
      assert %GitWrapper.Status{branch: nil, entries: []} = result
    end

    test "parses clean repo on main branch" do
      output = "## main\n"
      result = GitWrapper.Status.parse(output)

      assert result.branch == "main"
      assert result.tracking == nil
      assert result.ahead == 0
      assert result.behind == 0
      assert result.entries == []
    end

    test "parses untracked file" do
      output = "## main\n?? foo.txt\n"
      result = GitWrapper.Status.parse(output)

      assert result.branch == "main"
      assert length(result.entries) == 1
      assert hd(result.entries) == %{index: "?", working_tree: "?", path: "foo.txt"}
    end

    test "parses branch with tracking" do
      output = "## main...origin/main\n"
      result = GitWrapper.Status.parse(output)

      assert result.branch == "main"
      assert result.tracking == "origin/main"
      assert result.ahead == 0
      assert result.behind == 0
    end

    test "parses ahead/behind counts" do
      output = "## main...origin/main [ahead 2, behind 3]\n"
      result = GitWrapper.Status.parse(output)

      assert result.ahead == 2
      assert result.behind == 3
    end

    test "parses ahead only" do
      output = "## main...origin/main [ahead 1]\n"
      result = GitWrapper.Status.parse(output)

      assert result.ahead == 1
      assert result.behind == 0
    end

    test "parses staged and unstaged files" do
      output = "## main\nM  staged.txt\n M unstaged.txt\n?? new.txt\n"
      result = GitWrapper.Status.parse(output)

      assert length(result.entries) == 3
      assert Enum.any?(result.entries, &(&1.path == "staged.txt" and &1.index == "M"))
      assert Enum.any?(result.entries, &(&1.path == "unstaged.txt" and &1.working_tree == "M"))
      assert Enum.any?(result.entries, &(&1.path == "new.txt" and &1.index == "?"))
    end

    test "parses renamed file" do
      output = "## main\nR  old.txt -> new.txt\n"
      result = GitWrapper.Status.parse(output)

      assert length(result.entries) == 1
      assert hd(result.entries).path == "new.txt"
    end
  end

  # ---------------------------------------------------------------------------
  # GitWrapper.Commands.Log args/1 unit tests
  # ---------------------------------------------------------------------------

  describe "GitWrapper.Commands.Log args/1" do
    test "builds basic log args" do
      args = Log.args(%Log{})
      assert List.first(args) == "log"
      assert Enum.any?(args, &String.starts_with?(&1, "--format="))
    end

    test "adds max_count flag" do
      args = Log.args(%Log{max_count: 5})
      assert "--max-count=5" in args
    end

    test "adds author flag" do
      args = Log.args(%Log{author: "alice"})
      assert "--author=alice" in args
    end

    test "adds since flag" do
      args = Log.args(%Log{since: "2024-01-01"})
      assert "--since=2024-01-01" in args
    end

    test "adds until flag" do
      args = Log.args(%Log{until_date: "2024-12-31"})
      assert "--until=2024-12-31" in args
    end

    test "adds path with separator" do
      args = Log.args(%Log{path: "lib/"})
      assert "--" in args
      assert "lib/" in args
    end

    test "omits nil fields" do
      args = Log.args(%Log{})
      refute Enum.any?(args, &String.starts_with?(&1, "--max-count="))
      refute Enum.any?(args, &String.starts_with?(&1, "--author="))
    end
  end

  # ---------------------------------------------------------------------------
  # GitWrapper.Commands.Commit args/1 unit tests
  # ---------------------------------------------------------------------------

  describe "GitWrapper.Commands.Commit args/1" do
    test "builds basic commit args" do
      args = Commit.args(%Commit{message: "feat: add feature"})
      assert args == ["commit", "-m", "feat: add feature"]
    end

    test "adds --allow-empty flag when set" do
      args = Commit.args(%Commit{message: "chore: empty", allow_empty: true})
      assert "--allow-empty" in args
    end

    test "does not add --allow-empty when false" do
      args = Commit.args(%Commit{message: "fix: something"})
      refute "--allow-empty" in args
    end

    test "adds -a flag for all when set" do
      args = Commit.args(%Commit{message: "fix: stage all", all: true})
      assert "-a" in args
    end

    test "does not add -a when false" do
      args = Commit.args(%Commit{message: "fix: something"})
      refute "-a" in args
    end

    test "combines all and allow_empty flags" do
      args = Commit.args(%Commit{message: "test", all: true, allow_empty: true})
      assert "-a" in args
      assert "--allow-empty" in args
    end
  end

  # ---------------------------------------------------------------------------
  # GitWrapper.Commands.Commit parse_output/2 unit tests
  # ---------------------------------------------------------------------------

  describe "GitWrapper.Commands.Commit parse_output/2" do
    test "returns ok with CommitResult on exit 0" do
      output = "[main abc1234] the commit message\n 1 file changed, 5 insertions(+), 2 deletions(-)\n"
      assert {:ok, %GitWrapper.CommitResult{} = result} = Commit.parse_output(output, 0)
      assert result.branch == "main"
      assert result.hash == "abc1234"
      assert result.subject == "the commit message"
      assert result.files_changed == 1
      assert result.insertions == 5
      assert result.deletions == 2
    end

    test "returns error tuple on non-zero exit" do
      assert {:error, {"nothing to commit", 1}} = Commit.parse_output("nothing to commit", 1)
    end
  end

  # ---------------------------------------------------------------------------
  # GitWrapperEx.status/1 integration tests
  # ---------------------------------------------------------------------------

  describe "GitWrapperEx.status/1" do
    test "returns ok status struct on clean repo" do
      config = setup_repo()
      # Need at least one commit for HEAD to exist, but on a brand-new repo
      # before any commits git status still succeeds.
      assert {:ok, %GitWrapper.Status{entries: []}} = GitWrapperEx.status(config: config)
    end

    test "shows untracked file in entries" do
      config = setup_repo()
      File.write!(Path.join(config.working_dir, "hello.txt"), "hello\n")

      assert {:ok, status} = GitWrapperEx.status(config: config)
      assert Enum.any?(status.entries, &(&1.path == "hello.txt"))
    end

    test "shows staged file with correct status code" do
      config = setup_repo()
      create_file_and_stage(config.working_dir, "staged.txt")

      assert {:ok, status} = GitWrapperEx.status(config: config)
      entry = Enum.find(status.entries, &(&1.path == "staged.txt"))
      assert entry != nil
      assert entry.index == "A"
    end
  end

  # ---------------------------------------------------------------------------
  # GitWrapperEx.log/1 integration tests
  # ---------------------------------------------------------------------------

  describe "GitWrapperEx.log/1" do
    test "returns empty list on repo with no commits" do
      config = setup_repo()
      assert {:ok, []} = GitWrapperEx.log(config: config)
    end

    test "returns commit struct after one commit" do
      config = setup_repo()
      create_file_and_stage(config.working_dir, "readme.txt")
      make_commit(config.working_dir, "feat: initial commit")

      assert {:ok, [commit]} = GitWrapperEx.log(config: config)
      assert %GitWrapper.Commit{} = commit
      assert commit.subject == "feat: initial commit"
      assert commit.author_email == "test@example.com"
      assert commit.author_name == "Test User"
      assert String.length(commit.hash) == 40
      assert String.length(commit.abbreviated_hash) >= 7
    end

    test "respects max_count option" do
      config = setup_repo()

      for i <- 1..3 do
        create_file_and_stage(config.working_dir, "file_#{i}.txt")
        make_commit(config.working_dir, "feat: commit #{i}")
      end

      assert {:ok, commits} = GitWrapperEx.log(max_count: 2, config: config)
      assert length(commits) == 2
    end

    test "returns multiple commits in reverse chronological order" do
      config = setup_repo()

      create_file_and_stage(config.working_dir, "a.txt")
      make_commit(config.working_dir, "feat: first")

      create_file_and_stage(config.working_dir, "b.txt")
      make_commit(config.working_dir, "feat: second")

      assert {:ok, [latest, oldest]} = GitWrapperEx.log(config: config)
      assert latest.subject == "feat: second"
      assert oldest.subject == "feat: first"
    end
  end

  # ---------------------------------------------------------------------------
  # Module API surface tests
  # ---------------------------------------------------------------------------

  describe "module" do
    test "defines status/1" do
      assert function_exported?(GitWrapperEx, :status, 1)
    end

    test "defines log/1" do
      assert function_exported?(GitWrapperEx, :log, 1)
    end

    test "defines commit/2" do
      assert function_exported?(GitWrapperEx, :commit, 2)
    end
  end
end
