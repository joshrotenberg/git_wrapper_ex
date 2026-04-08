defmodule Git.SwitchTest do
  use ExUnit.Case, async: true

  alias Git.Checkout
  alias Git.Commands.Switch
  alias Git.Config

  setup do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "git_wrapper_switch_test_#{:erlang.unique_integer([:positive])}"
      )

    File.mkdir_p!(tmp_dir)

    System.cmd("git", ["init", "--initial-branch=main"], cd: tmp_dir)
    System.cmd("git", ["config", "user.name", "Test User"], cd: tmp_dir)
    System.cmd("git", ["config", "user.email", "test@test.com"], cd: tmp_dir)

    System.cmd(
      "git",
      ["commit", "--allow-empty", "-m", "initial"],
      cd: tmp_dir
    )

    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    config = Config.new(working_dir: tmp_dir)

    %{tmp_dir: tmp_dir, config: config}
  end

  describe "switch to existing branch" do
    test "switches to the target branch", %{tmp_dir: tmp_dir, config: config} do
      System.cmd("git", ["branch", "other"], cd: tmp_dir)

      assert {:ok, %Checkout{} = result} =
               Git.switch(branch: "other", config: config)

      assert result.branch == "other"
      assert result.created == false
    end

    test "returns already-on result for current branch", %{config: config} do
      assert {:ok, %Checkout{} = result} =
               Git.switch(branch: "main", config: config)

      assert result.branch == "main"
      assert result.created == false
    end
  end

  describe "switch -c (create and switch)" do
    test "creates and switches to a new branch", %{config: config} do
      assert {:ok, %Checkout{} = result} =
               Git.switch(branch: "feat/new-thing", create: true, config: config)

      assert result.branch == "feat/new-thing"
      assert result.created == true
    end

    test "returns error when branch already exists", %{tmp_dir: tmp_dir, config: config} do
      System.cmd("git", ["branch", "existing"], cd: tmp_dir)

      assert {:error, {output, exit_code}} =
               Git.switch(branch: "existing", create: true, config: config)

      assert exit_code != 0
      assert is_binary(output)
    end
  end

  describe "switch -C (force create)" do
    test "creates or resets a branch and switches to it", %{tmp_dir: tmp_dir, config: config} do
      System.cmd("git", ["branch", "existing"], cd: tmp_dir)

      assert {:ok, %Checkout{} = result} =
               Git.switch(branch: "existing", force_create: true, config: config)

      assert result.branch == "existing"
    end
  end

  describe "switch --detach" do
    test "switches to detached HEAD", %{tmp_dir: tmp_dir, config: config} do
      {hash, 0} = System.cmd("git", ["rev-parse", "HEAD"], cd: tmp_dir)
      hash = String.trim(hash)

      assert {:ok, %Checkout{}} =
               Git.switch(branch: hash, detach: true, config: config)
    end
  end

  describe "switch failure" do
    test "returns error for nonexistent branch", %{config: config} do
      assert {:error, {output, exit_code}} =
               Git.switch(branch: "nonexistent-branch-xyz", config: config)

      assert exit_code != 0
      assert is_binary(output)
    end
  end

  describe "Commands.Switch.args/1" do
    test "builds args for branch switch" do
      assert Switch.args(%Switch{branch: "main"}) ==
               ["switch", "main"]
    end

    test "builds args for branch create and switch" do
      assert Switch.args(%Switch{branch: "feat/new", create: true}) ==
               ["switch", "-c", "feat/new"]
    end

    test "builds args for force create" do
      assert Switch.args(%Switch{
               branch: "feat/new",
               force_create: true
             }) == ["switch", "-C", "feat/new"]
    end

    test "builds args for detached HEAD" do
      assert Switch.args(%Switch{branch: "abc123", detach: true}) ==
               ["switch", "--detach", "abc123"]
    end

    test "builds args for orphan branch" do
      assert Switch.args(%Switch{branch: "gh-pages", orphan: true}) ==
               ["switch", "--orphan", "gh-pages"]
    end

    test "builds args with --no-guess" do
      assert Switch.args(%Switch{branch: "feat", guess: false}) ==
               ["switch", "--no-guess", "feat"]
    end

    test "builds args with track" do
      assert Switch.args(%Switch{
               branch: "feat",
               create: true,
               track: "origin/feat"
             }) == ["switch", "-c", "--track", "origin/feat", "feat"]
    end
  end
end
