defmodule Git.Commands.CommitTreeTest do
  use ExUnit.Case, async: true

  alias Git.Commands.CommitTree
  alias Git.Config

  defp setup_repo do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "git_commit_tree_test_#{:erlang.unique_integer([:positive])}"
      )

    File.mkdir_p!(tmp_dir)
    cfg = Config.new(working_dir: tmp_dir)
    {:ok, :done} = Git.init(config: cfg)
    {:ok, :done} = Git.git_config(set_key: "user.name", set_value: "Test User", config: cfg)

    {:ok, :done} =
      Git.git_config(set_key: "user.email", set_value: "test@test.com", config: cfg)

    # Tests should not pick up an ambient commit.gpgSign that would force
    # signing on every commit-tree call.
    {:ok, :done} = Git.git_config(set_key: "commit.gpgSign", set_value: "false", config: cfg)
    {tmp_dir, cfg}
  end

  defp write_tree(tmp_dir, filename, contents) do
    File.write!(Path.join(tmp_dir, filename), contents)
    {_, 0} = System.cmd("git", ["add", filename], cd: tmp_dir)
    {sha, 0} = System.cmd("git", ["write-tree"], cd: tmp_dir)
    String.trim(sha)
  end

  setup do
    {tmp_dir, config} = setup_repo()
    on_exit(fn -> File.rm_rf!(tmp_dir) end)
    %{tmp_dir: tmp_dir, config: config}
  end

  describe "args/1" do
    test "minimal: tree and message" do
      assert CommitTree.args(%CommitTree{tree: "abc123", message: "init"}) ==
               ["commit-tree", "-m", "init", "abc123"]
    end

    test "with one parent" do
      assert CommitTree.args(%CommitTree{tree: "abc123", parents: ["p1"], message: "x"}) ==
               ["commit-tree", "-p", "p1", "-m", "x", "abc123"]
    end

    test "with multiple parents (merge commit)" do
      assert CommitTree.args(%CommitTree{tree: "abc123", parents: ["p1", "p2"], message: "x"}) ==
               ["commit-tree", "-p", "p1", "-p", "p2", "-m", "x", "abc123"]
    end

    test "with sign true" do
      assert CommitTree.args(%CommitTree{tree: "abc123", message: "x", sign: true}) ==
               ["commit-tree", "-S", "-m", "x", "abc123"]
    end

    test "with sign keyid" do
      assert CommitTree.args(%CommitTree{tree: "abc123", message: "x", sign: "ABCD1234"}) ==
               ["commit-tree", "-SABCD1234", "-m", "x", "abc123"]
    end

    test "with no_gpg_sign" do
      assert CommitTree.args(%CommitTree{tree: "abc123", message: "x", no_gpg_sign: true}) ==
               ["commit-tree", "--no-gpg-sign", "-m", "x", "abc123"]
    end

    test "with multiple messages" do
      assert CommitTree.args(%CommitTree{tree: "abc123", messages: ["subject", "body"]}) ==
               ["commit-tree", "-m", "subject", "-m", "body", "abc123"]
    end

    test "message and messages combine, message first" do
      assert CommitTree.args(%CommitTree{
               tree: "abc123",
               message: "subject",
               messages: ["body"]
             }) ==
               ["commit-tree", "-m", "subject", "-m", "body", "abc123"]
    end

    test "no message at all (would read from stdin if invoked, valid arg list)" do
      assert CommitTree.args(%CommitTree{tree: "abc123"}) ==
               ["commit-tree", "abc123"]
    end
  end

  describe "commit_tree integration" do
    test "creates a root commit (no parents)", %{tmp_dir: tmp_dir, config: config} do
      tree = write_tree(tmp_dir, "a.txt", "hello")

      {:ok, sha} = Git.commit_tree(tree: tree, message: "root", config: config)

      assert is_binary(sha)
      assert String.length(sha) == 40

      {body, 0} = System.cmd("git", ["cat-file", "-p", sha], cd: tmp_dir)
      assert body =~ "tree #{tree}"
      refute body =~ "parent "
      assert body =~ "root"
    end

    test "creates a commit with one parent", %{tmp_dir: tmp_dir, config: config} do
      tree1 = write_tree(tmp_dir, "a.txt", "a")
      {:ok, parent} = Git.commit_tree(tree: tree1, message: "root", config: config)

      tree2 = write_tree(tmp_dir, "b.txt", "b")

      {:ok, child} =
        Git.commit_tree(tree: tree2, parents: [parent], message: "child", config: config)

      {body, 0} = System.cmd("git", ["cat-file", "-p", child], cd: tmp_dir)
      assert body =~ "tree #{tree2}"
      assert body =~ "parent #{parent}"
      assert body =~ "child"
    end

    test "creates a merge commit with multiple parents", %{tmp_dir: tmp_dir, config: config} do
      tree = write_tree(tmp_dir, "x.txt", "x")
      {:ok, p1} = Git.commit_tree(tree: tree, message: "p1", config: config)
      {:ok, p2} = Git.commit_tree(tree: tree, message: "p2", config: config)

      {:ok, merge} =
        Git.commit_tree(tree: tree, parents: [p1, p2], message: "merge", config: config)

      {body, 0} = System.cmd("git", ["cat-file", "-p", merge], cd: tmp_dir)
      assert body =~ "parent #{p1}"
      assert body =~ "parent #{p2}"
    end

    test "multiple messages produce a multi-paragraph commit", %{tmp_dir: tmp_dir, config: config} do
      tree = write_tree(tmp_dir, "a.txt", "x")

      {:ok, sha} =
        Git.commit_tree(
          tree: tree,
          messages: ["subject", "body line"],
          config: config
        )

      {body, 0} = System.cmd("git", ["cat-file", "-p", sha], cd: tmp_dir)
      assert body =~ "subject"
      assert body =~ "body line"
    end

    test "errors on a non-existent tree SHA", %{config: config} do
      assert {:error, _} =
               Git.commit_tree(
                 tree: "0000000000000000000000000000000000000000",
                 message: "x",
                 config: config
               )
    end

    test "no commit lands on any branch (free-floating object)", %{
      tmp_dir: tmp_dir,
      config: config
    } do
      tree = write_tree(tmp_dir, "a.txt", "x")
      {:ok, sha} = Git.commit_tree(tree: tree, message: "floating", config: config)

      # The new commit exists as an object...
      {_body, 0} = System.cmd("git", ["cat-file", "-p", sha], cd: tmp_dir)

      # ...but is not reachable from any branch.
      {refs, 0} =
        System.cmd("git", ["branch", "--contains", sha], cd: tmp_dir, stderr_to_stdout: true)

      assert refs == "" or refs =~ ~r/error|no such commit/
    end
  end
end
