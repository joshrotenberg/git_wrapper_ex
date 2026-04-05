defmodule Git.BranchTest do
  use ExUnit.Case, async: true

  alias Git.Branch
  alias Git.Commands.Branch, as: BranchCmd

  # ---------------------------------------------------------------------------
  # Test helpers
  # ---------------------------------------------------------------------------

  defp setup_repo do
    dir =
      Path.join(
        System.tmp_dir!(),
        "git_wrapper_branch_test_#{:erlang.unique_integer([:positive])}"
      )

    File.mkdir_p!(dir)
    System.cmd("git", ["init", "--initial-branch=main"], cd: dir)
    System.cmd("git", ["config", "user.email", "test@example.com"], cd: dir)
    System.cmd("git", ["config", "user.name", "Test User"], cd: dir)
    # Create an initial commit so branches are valid
    System.cmd("git", ["commit", "--allow-empty", "-m", "init"], cd: dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    {Git.Config.new(working_dir: dir), dir}
  end

  # ---------------------------------------------------------------------------
  # Unit tests: Branch.parse/1
  # ---------------------------------------------------------------------------

  describe "Branch.parse/1" do
    test "empty output returns empty list" do
      assert Branch.parse("") == []
    end

    test "parses a single current branch" do
      output = "* main abc1234 initial commit\n"
      assert [%Branch{name: "main", current: true, remote: false}] = Branch.parse(output)
    end

    test "parses a non-current branch" do
      output = "  feature/foo def5678 add feature\n"
      assert [%Branch{name: "feature/foo", current: false, remote: false}] = Branch.parse(output)
    end

    test "parses current and non-current branches together" do
      output = "* main abc1234 subject\n  other def5678 subject\n"
      branches = Branch.parse(output)
      assert length(branches) == 2
      main = Enum.find(branches, &(&1.name == "main"))
      other = Enum.find(branches, &(&1.name == "other"))
      assert main.current == true
      assert other.current == false
    end

    test "parses upstream tracking info" do
      output = "* main abc1234 [origin/main] commit\n"
      assert [%Branch{upstream: "origin/main"}] = Branch.parse(output)
    end

    test "parses ahead/behind counts" do
      output = "* main abc1234 [origin/main: ahead 2, behind 3] commit\n"
      assert [%Branch{ahead: 2, behind: 3}] = Branch.parse(output)
    end

    test "parses ahead only" do
      output = "* main abc1234 [origin/main: ahead 1] commit\n"
      assert [%Branch{ahead: 1, behind: 0}] = Branch.parse(output)
    end

    test "parses behind only" do
      output = "* main abc1234 [origin/main: behind 4] commit\n"
      assert [%Branch{ahead: 0, behind: 4}] = Branch.parse(output)
    end

    test "no tracking info produces nil upstream and zero counts" do
      output = "* main abc1234 commit\n"
      assert [%Branch{upstream: nil, ahead: 0, behind: 0}] = Branch.parse(output)
    end

    test "skips HEAD symbolic ref lines" do
      output = "  remotes/origin/HEAD -> origin/main\n  remotes/origin/main abc1234 commit\n"
      branches = Branch.parse(output)
      assert length(branches) == 1
      assert hd(branches).name == "remotes/origin/main"
    end

    test "remote-tracking branch has remote: true" do
      output = "  remotes/origin/main abc1234 commit\n"
      assert [%Branch{remote: true, name: "remotes/origin/main"}] = Branch.parse(output)
    end
  end

  # ---------------------------------------------------------------------------
  # Unit tests: Commands.Branch.args/1
  # ---------------------------------------------------------------------------

  describe "Commands.Branch.args/1" do
    test "default struct produces list args with -vv" do
      assert BranchCmd.args(%BranchCmd{}) == ["branch", "-vv"]
    end

    test "all: true adds --all flag" do
      assert BranchCmd.args(%BranchCmd{all: true}) == ["branch", "-vv", "--all"]
    end

    test "create produces create args" do
      assert BranchCmd.args(%BranchCmd{create: "feat/new"}) == ["branch", "feat/new"]
    end

    test "delete produces -d args" do
      assert BranchCmd.args(%BranchCmd{delete: "old-branch"}) == ["branch", "-d", "old-branch"]
    end

    test "force_delete produces -D args" do
      assert BranchCmd.args(%BranchCmd{delete: "old-branch", force_delete: true}) ==
               ["branch", "-D", "old-branch"]
    end
  end

  # ---------------------------------------------------------------------------
  # Unit tests: Commands.Branch.parse_output/2
  # ---------------------------------------------------------------------------

  describe "Commands.Branch.parse_output/2" do
    test "empty output returns :done" do
      assert {:ok, :done} = BranchCmd.parse_output("", 0)
    end

    test "branch list output returns parsed branches" do
      output = "* main abc1234 commit\n"
      assert {:ok, [%Branch{name: "main"}]} = BranchCmd.parse_output(output, 0)
    end

    test "non-zero exit returns error tuple" do
      assert {:error, {"error msg", 1}} = BranchCmd.parse_output("error msg", 1)
    end
  end

  # ---------------------------------------------------------------------------
  # Integration tests
  # ---------------------------------------------------------------------------

  describe "Git.branch/1 integration" do
    test "lists the initial branch" do
      {config, _dir} = setup_repo()
      assert {:ok, branches} = Git.branch(config: config)
      assert length(branches) == 1
      assert hd(branches).name == "main"
      assert hd(branches).current == true
    end

    test "create branch returns :done" do
      {config, _dir} = setup_repo()
      assert {:ok, :done} = Git.branch(config: config, create: "feat/new")
    end

    test "created branch appears in listing" do
      {config, _dir} = setup_repo()
      Git.branch(config: config, create: "feat/new")

      assert {:ok, branches} = Git.branch(config: config)
      names = Enum.map(branches, & &1.name)
      assert "feat/new" in names
    end

    test "delete branch returns :done" do
      {config, _dir} = setup_repo()
      Git.branch(config: config, create: "to-delete")

      assert {:ok, :done} = Git.branch(config: config, delete: "to-delete")
    end

    test "deleted branch no longer appears in listing" do
      {config, _dir} = setup_repo()
      Git.branch(config: config, create: "to-delete")
      Git.branch(config: config, delete: "to-delete")

      assert {:ok, branches} = Git.branch(config: config)
      names = Enum.map(branches, & &1.name)
      refute "to-delete" in names
    end

    test "deleting non-existent branch returns error" do
      {config, _dir} = setup_repo()
      assert {:error, _} = Git.branch(config: config, delete: "nonexistent")
    end

    test "multiple branches all appear in listing" do
      {config, _dir} = setup_repo()
      Git.branch(config: config, create: "feat/a")
      Git.branch(config: config, create: "feat/b")

      assert {:ok, branches} = Git.branch(config: config)
      names = Enum.map(branches, & &1.name)
      assert "main" in names
      assert "feat/a" in names
      assert "feat/b" in names
    end
  end
end
