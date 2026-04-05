defmodule Git.LsTreeTest do
  use ExUnit.Case, async: true

  alias Git.Commands.LsTree
  alias Git.Config
  alias Git.TreeEntry

  @env [
    {"GIT_AUTHOR_NAME", "Test User"},
    {"GIT_AUTHOR_EMAIL", "test@test.com"},
    {"GIT_COMMITTER_NAME", "Test User"},
    {"GIT_COMMITTER_EMAIL", "test@test.com"}
  ]

  defp setup_repo do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "git_ls_tree_test_#{:erlang.unique_integer([:positive])}"
      )

    File.mkdir_p!(tmp_dir)
    cfg = Config.new(working_dir: tmp_dir, env: @env)
    {:ok, :done} = Git.init(config: cfg)
    {:ok, :done} = Git.git_config(set_key: "user.name", set_value: "Test User", config: cfg)
    {:ok, :done} = Git.git_config(set_key: "user.email", set_value: "test@test.com", config: cfg)

    # Create files and directories
    File.write!(Path.join(tmp_dir, "README.md"), "# Test Project\n")
    File.write!(Path.join(tmp_dir, "mix.exs"), "defmodule Mix do\nend\n")
    File.mkdir_p!(Path.join(tmp_dir, "lib"))
    File.write!(Path.join(tmp_dir, "lib/app.ex"), "defmodule App do\nend\n")
    File.mkdir_p!(Path.join(tmp_dir, "lib/sub"))
    File.write!(Path.join(tmp_dir, "lib/sub/nested.ex"), "defmodule Nested do\nend\n")
    {:ok, :done} = Git.add(all: true, config: cfg)
    {:ok, _} = Git.commit("initial commit", config: cfg)

    {tmp_dir, cfg}
  end

  setup do
    {tmp_dir, config} = setup_repo()
    on_exit(fn -> File.rm_rf!(tmp_dir) end)
    %{tmp_dir: tmp_dir, config: config}
  end

  describe "args/1" do
    test "builds default args" do
      assert LsTree.args(%LsTree{}) == ["ls-tree", "HEAD"]
    end

    test "builds args with recursive and long" do
      assert LsTree.args(%LsTree{recursive: true, long: true}) ==
               ["ls-tree", "-r", "-l", "HEAD"]
    end

    test "builds args with name_only and custom ref" do
      assert LsTree.args(%LsTree{name_only: true, ref: "main"}) ==
               ["ls-tree", "--name-only", "main"]
    end

    test "builds args with path filter" do
      assert LsTree.args(%LsTree{path: "lib/"}) ==
               ["ls-tree", "HEAD", "--", "lib/"]
    end

    test "builds args with abbrev" do
      assert LsTree.args(%LsTree{abbrev: 8}) ==
               ["ls-tree", "--abbrev=8", "HEAD"]
    end

    test "builds args with tree_only" do
      assert LsTree.args(%LsTree{tree_only: true}) ==
               ["ls-tree", "-d", "HEAD"]
    end

    test "builds args with full_name and full_tree" do
      assert LsTree.args(%LsTree{full_name: true, full_tree: true}) ==
               ["ls-tree", "--full-name", "--full-tree", "HEAD"]
    end
  end

  describe "git ls-tree" do
    test "lists files at HEAD", %{config: config} do
      {:ok, entries} =
        Git.Command.run(LsTree, %LsTree{}, config)

      assert is_list(entries)
      assert entries != []

      paths = Enum.map(entries, & &1.path)
      assert "README.md" in paths
      assert "mix.exs" in paths
      assert "lib" in paths

      Enum.each(entries, fn entry ->
        assert %TreeEntry{} = entry
        assert entry.mode in ["100644", "040000"]
        assert entry.type in [:blob, :tree]
        assert String.match?(entry.sha, ~r/^[0-9a-f]+$/)
      end)
    end

    test "recursive lists all files", %{config: config} do
      {:ok, entries} =
        Git.Command.run(LsTree, %LsTree{recursive: true}, config)

      paths = Enum.map(entries, & &1.path)
      assert "README.md" in paths
      assert "mix.exs" in paths
      assert "lib/app.ex" in paths
      assert "lib/sub/nested.ex" in paths

      # With recursive, all entries should be blobs (trees are expanded)
      Enum.each(entries, fn entry ->
        assert entry.type == :blob
      end)
    end

    test "name_only returns strings", %{config: config} do
      {:ok, entries} =
        Git.Command.run(LsTree, %LsTree{name_only: true}, config)

      assert is_list(entries)
      assert Enum.all?(entries, &is_binary/1)
      assert "README.md" in entries
      assert "lib" in entries
    end

    test "long format includes sizes", %{config: config} do
      {:ok, entries} =
        Git.Command.run(LsTree, %LsTree{recursive: true, long: true}, config)

      blob_entries = Enum.filter(entries, &(&1.type == :blob))

      Enum.each(blob_entries, fn entry ->
        assert is_integer(entry.size)
        assert entry.size > 0
      end)
    end

    test "tree_only shows only directories", %{config: config} do
      {:ok, entries} =
        Git.Command.run(LsTree, %LsTree{tree_only: true}, config)

      Enum.each(entries, fn entry ->
        assert entry.type == :tree
        assert entry.mode == "040000"
      end)

      paths = Enum.map(entries, & &1.path)
      assert "lib" in paths
    end

    test "path filter restricts output", %{config: config} do
      {:ok, entries} =
        Git.Command.run(LsTree, %LsTree{path: "lib"}, config)

      paths = Enum.map(entries, & &1.path)
      # ls-tree HEAD -- lib shows the "lib" tree entry itself
      assert paths == ["lib"]

      # Use trailing slash to see contents of the directory
      {:ok, contents} =
        Git.Command.run(LsTree, %LsTree{path: "lib/"}, config)

      content_paths = Enum.map(contents, & &1.path)
      assert "lib/app.ex" in content_paths
      assert "lib/sub" in content_paths
    end
  end

  describe "git ls-tree failure" do
    test "returns error for invalid ref", %{config: config} do
      assert {:error, {_output, exit_code}} =
               Git.Command.run(LsTree, %LsTree{ref: "nonexistent-ref"}, config)

      assert exit_code != 0
    end
  end
end
