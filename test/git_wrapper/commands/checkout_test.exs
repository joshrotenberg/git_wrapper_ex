defmodule GitWrapper.CheckoutTest do
  use ExUnit.Case, async: true

  alias GitWrapper.Checkout
  alias GitWrapper.Config

  setup do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "git_wrapper_checkout_test_#{:erlang.unique_integer([:positive])}"
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

  describe "checkout existing branch" do
    test "switches to the target branch", %{tmp_dir: tmp_dir, config: config} do
      System.cmd("git", ["branch", "other"], cd: tmp_dir)

      assert {:ok, %Checkout{} = result} =
               GitWrapperEx.checkout(branch: "other", config: config)

      assert result.branch == "other"
      assert result.created == false
    end

    test "returns already-on result when checking out the current branch", %{config: config} do
      assert {:ok, %Checkout{} = result} =
               GitWrapperEx.checkout(branch: "main", config: config)

      assert result.branch == "main"
      assert result.created == false
    end
  end

  describe "checkout -b (create and switch)" do
    test "creates and switches to a new branch", %{config: config} do
      assert {:ok, %Checkout{} = result} =
               GitWrapperEx.checkout(branch: "feat/new-thing", create: true, config: config)

      assert result.branch == "feat/new-thing"
      assert result.created == true
    end

    test "returns error when branch already exists", %{tmp_dir: tmp_dir, config: config} do
      System.cmd("git", ["branch", "existing"], cd: tmp_dir)

      assert {:error, {output, exit_code}} =
               GitWrapperEx.checkout(branch: "existing", create: true, config: config)

      assert exit_code != 0
      assert is_binary(output)
    end
  end

  describe "checkout -- files (restore)" do
    test "restores a modified tracked file", %{tmp_dir: tmp_dir, config: config} do
      file_path = Path.join(tmp_dir, "tracked.txt")
      File.write!(file_path, "original\n")

      System.cmd(
        "git",
        [
          "-c",
          "user.name=Test User",
          "-c",
          "user.email=test@test.com",
          "add",
          "tracked.txt"
        ],
        cd: tmp_dir
      )

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

      assert {:ok, :done} =
               GitWrapperEx.checkout(files: ["tracked.txt"], config: config)

      assert File.read!(file_path) == "original\n"
    end
  end

  describe "checkout failure" do
    test "returns error for nonexistent branch", %{config: config} do
      assert {:error, {output, exit_code}} =
               GitWrapperEx.checkout(branch: "nonexistent-branch-xyz", config: config)

      assert exit_code != 0
      assert is_binary(output)
    end
  end

  describe "Checkout.parse/1" do
    test "parses switch to existing branch" do
      output = "Switched to branch 'main'\n"
      result = Checkout.parse(output)

      assert result.branch == "main"
      assert result.created == false
    end

    test "parses switch to new branch" do
      output = "Switched to a new branch 'feat/awesome'\n"
      result = Checkout.parse(output)

      assert result.branch == "feat/awesome"
      assert result.created == true
    end

    test "parses already-on output" do
      output = "Already on 'main'\n"
      result = Checkout.parse(output)

      assert result.branch == "main"
      assert result.created == false
    end

    test "returns empty struct for unrecognized output" do
      result = Checkout.parse("")

      assert result.branch == nil
      assert result.created == false
    end
  end

  describe "Commands.Checkout.args/1" do
    test "builds args for branch switch" do
      assert GitWrapper.Commands.Checkout.args(%GitWrapper.Commands.Checkout{branch: "main"}) ==
               ["checkout", "main"]
    end

    test "builds args for branch create and switch" do
      assert GitWrapper.Commands.Checkout.args(%GitWrapper.Commands.Checkout{
               branch: "feat/new",
               create: true
             }) == ["checkout", "-b", "feat/new"]
    end

    test "builds args for file restore" do
      assert GitWrapper.Commands.Checkout.args(%GitWrapper.Commands.Checkout{
               files: ["README.md", "lib/foo.ex"]
             }) == ["checkout", "--", "README.md", "lib/foo.ex"]
    end
  end
end
