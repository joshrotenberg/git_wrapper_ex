defmodule Git.Commands.UpdateRefTest do
  use ExUnit.Case, async: true

  alias Git.Commands.UpdateRef
  alias Git.Config

  defp setup_repo do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "git_update_ref_test_#{:erlang.unique_integer([:positive])}"
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
    test "update ref" do
      assert UpdateRef.args(%UpdateRef{ref: "refs/heads/main", new_value: "abc123"}) ==
               ["update-ref", "refs/heads/main", "abc123"]
    end

    test "update ref with old value" do
      assert UpdateRef.args(%UpdateRef{
               ref: "refs/heads/main",
               new_value: "abc123",
               old_value: "def456"
             }) ==
               ["update-ref", "refs/heads/main", "abc123", "def456"]
    end

    test "with message" do
      assert UpdateRef.args(%UpdateRef{
               ref: "refs/heads/main",
               new_value: "abc123",
               message: "reset"
             }) ==
               ["update-ref", "-m", "reset", "refs/heads/main", "abc123"]
    end

    test "delete ref" do
      assert UpdateRef.args(%UpdateRef{ref: "refs/heads/old", delete: true}) ==
               ["update-ref", "-d", "refs/heads/old"]
    end

    test "with no_deref" do
      assert UpdateRef.args(%UpdateRef{
               ref: "HEAD",
               new_value: "abc123",
               no_deref: true
             }) ==
               ["update-ref", "--no-deref", "HEAD", "abc123"]
    end

    test "with create_reflog" do
      assert UpdateRef.args(%UpdateRef{
               ref: "refs/heads/main",
               new_value: "abc123",
               create_reflog: true
             }) ==
               ["update-ref", "--create-reflog", "refs/heads/main", "abc123"]
    end
  end

  describe "update_ref integration" do
    test "creates a new ref", %{tmp_dir: tmp_dir, config: config} do
      {sha, 0} = System.cmd("git", ["rev-parse", "HEAD"], cd: tmp_dir)
      sha = String.trim(sha)

      {:ok, :done} =
        Git.update_ref(ref: "refs/heads/new-branch", new_value: sha, config: config)

      {result, 0} = System.cmd("git", ["rev-parse", "refs/heads/new-branch"], cd: tmp_dir)
      assert String.trim(result) == sha
    end

    test "deletes a ref", %{tmp_dir: tmp_dir, config: config} do
      System.cmd("git", ["branch", "to-delete"], cd: tmp_dir)

      {:ok, :done} =
        Git.update_ref(ref: "refs/heads/to-delete", delete: true, config: config)

      {_output, exit_code} =
        System.cmd("git", ["rev-parse", "--verify", "refs/heads/to-delete"],
          cd: tmp_dir,
          stderr_to_stdout: true
        )

      assert exit_code != 0
    end

    test "updates a ref with message", %{tmp_dir: tmp_dir, config: config} do
      {sha, 0} = System.cmd("git", ["rev-parse", "HEAD"], cd: tmp_dir)
      sha = String.trim(sha)

      {:ok, :done} =
        Git.update_ref(
          ref: "refs/heads/new-ref",
          new_value: sha,
          message: "test update",
          create_reflog: true,
          config: config
        )

      {result, 0} = System.cmd("git", ["rev-parse", "refs/heads/new-ref"], cd: tmp_dir)
      assert String.trim(result) == sha
    end
  end
end
