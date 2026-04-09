defmodule Git.Commands.SymbolicRefTest do
  use ExUnit.Case, async: true

  alias Git.Commands.SymbolicRef
  alias Git.Config

  defp setup_repo do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "git_symbolic_ref_test_#{:erlang.unique_integer([:positive])}"
      )

    File.mkdir_p!(tmp_dir)
    cfg = Config.new(working_dir: tmp_dir)
    {:ok, :done} = Git.init(config: cfg)
    {:ok, :done} = Git.git_config(set_key: "user.name", set_value: "Test User", config: cfg)
    {:ok, :done} = Git.git_config(set_key: "user.email", set_value: "test@test.com", config: cfg)
    {:ok, _} = Git.commit("initial", allow_empty: true, config: cfg)
    {tmp_dir, cfg}
  end

  setup do
    {tmp_dir, config} = setup_repo()
    on_exit(fn -> File.rm_rf!(tmp_dir) end)
    %{tmp_dir: tmp_dir, config: config}
  end

  describe "args/1" do
    test "read ref" do
      assert SymbolicRef.args(%SymbolicRef{ref: "HEAD"}) ==
               ["symbolic-ref", "HEAD"]
    end

    test "read ref with short" do
      assert SymbolicRef.args(%SymbolicRef{ref: "HEAD", short: true}) ==
               ["symbolic-ref", "--short", "HEAD"]
    end

    test "write ref" do
      assert SymbolicRef.args(%SymbolicRef{ref: "HEAD", target: "refs/heads/main"}) ==
               ["symbolic-ref", "HEAD", "refs/heads/main"]
    end

    test "delete ref" do
      assert SymbolicRef.args(%SymbolicRef{ref: "HEAD", delete: true}) ==
               ["symbolic-ref", "--delete", "HEAD"]
    end

    test "with quiet" do
      assert SymbolicRef.args(%SymbolicRef{ref: "HEAD", quiet: true}) ==
               ["symbolic-ref", "--quiet", "HEAD"]
    end
  end

  describe "symbolic_ref integration" do
    test "reads HEAD", %{config: config} do
      {:ok, ref} = Git.symbolic_ref(ref: "HEAD", config: config)
      assert ref == "refs/heads/main"
    end

    test "reads HEAD with short", %{config: config} do
      {:ok, ref} = Git.symbolic_ref(ref: "HEAD", short: true, config: config)
      assert ref == "main"
    end

    test "writes and reads a symbolic ref", %{tmp_dir: tmp_dir, config: config} do
      # Create another branch first
      System.cmd("git", ["branch", "feature"], cd: tmp_dir)

      {:ok, :done} =
        Git.symbolic_ref(ref: "HEAD", target: "refs/heads/feature", config: config)

      {:ok, ref} = Git.symbolic_ref(ref: "HEAD", config: config)
      assert ref == "refs/heads/feature"
    end

    test "returns error for non-symbolic ref", %{config: config} do
      assert {:error, _} =
               Git.symbolic_ref(ref: "refs/heads/nonexistent", quiet: true, config: config)
    end
  end
end
