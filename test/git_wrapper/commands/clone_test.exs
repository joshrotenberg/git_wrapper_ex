defmodule GitWrapper.Commands.CloneTest do
  use ExUnit.Case, async: true

  alias GitWrapper.Commands.Clone
  alias GitWrapper.Config

  # ---------------------------------------------------------------------------
  # args/1 unit tests
  # ---------------------------------------------------------------------------

  describe "args/1" do
    test "builds basic clone args with only a URL" do
      assert Clone.args(%Clone{url: "https://example.com/repo.git"}) ==
               ["clone", "https://example.com/repo.git"]
    end

    test "adds --depth flag when depth is set" do
      assert Clone.args(%Clone{url: "https://example.com/repo.git", depth: 1}) ==
               ["clone", "--depth=1", "https://example.com/repo.git"]
    end

    test "adds --branch flag when branch is set" do
      assert Clone.args(%Clone{url: "https://example.com/repo.git", branch: "main"}) ==
               ["clone", "--branch=main", "https://example.com/repo.git"]
    end

    test "adds --depth and --branch flags together" do
      assert Clone.args(%Clone{
               url: "https://example.com/repo.git",
               depth: 1,
               branch: "main"
             }) == ["clone", "--depth=1", "--branch=main", "https://example.com/repo.git"]
    end

    test "appends target directory when set" do
      assert Clone.args(%Clone{url: "https://example.com/repo.git", directory: "my-repo"}) ==
               ["clone", "https://example.com/repo.git", "my-repo"]
    end

    test "combines all options" do
      assert Clone.args(%Clone{
               url: "https://example.com/repo.git",
               depth: 5,
               branch: "dev",
               directory: "local-repo"
             }) ==
               ["clone", "--depth=5", "--branch=dev", "https://example.com/repo.git", "local-repo"]
    end
  end

  # ---------------------------------------------------------------------------
  # parse_output/2 unit tests
  # ---------------------------------------------------------------------------

  describe "parse_output/2" do
    test "returns {:ok, :done} on exit code 0" do
      assert {:ok, :done} = Clone.parse_output("", 0)
    end

    test "returns {:ok, :done} on exit code 0 with output" do
      assert {:ok, :done} =
               Clone.parse_output("Cloning into 'repo'...\nremote: Counting objects: 3\n", 0)
    end

    test "returns {:error, {stdout, exit_code}} on non-zero exit" do
      assert {:error, {"fatal: repository 'foo' does not exist\n", 128}} =
               Clone.parse_output("fatal: repository 'foo' does not exist\n", 128)
    end
  end

  # ---------------------------------------------------------------------------
  # Integration tests
  # ---------------------------------------------------------------------------

  defp setup_source_repo do
    src_dir =
      Path.join(
        System.tmp_dir!(),
        "git_clone_src_#{:erlang.unique_integer([:positive])}"
      )

    File.mkdir_p!(src_dir)
    System.cmd("git", ["init", "--initial-branch=main"], cd: src_dir)

    System.cmd(
      "git",
      [
        "-c",
        "user.name=Test",
        "-c",
        "user.email=test@test.com",
        "commit",
        "--allow-empty",
        "-m",
        "init"
      ],
      cd: src_dir
    )

    src_dir
  end

  setup do
    src_dir = setup_source_repo()

    dest_parent =
      Path.join(
        System.tmp_dir!(),
        "git_clone_dest_#{:erlang.unique_integer([:positive])}"
      )

    File.mkdir_p!(dest_parent)

    on_exit(fn ->
      File.rm_rf!(src_dir)
      File.rm_rf!(dest_parent)
    end)

    config = Config.new(working_dir: dest_parent)
    %{src_dir: src_dir, dest_parent: dest_parent, config: config}
  end

  describe "clone integration" do
    test "clones a local repo into the working directory", %{
      src_dir: src_dir,
      dest_parent: dest_parent,
      config: config
    } do
      assert {:ok, :done} = GitWrapperEx.clone(src_dir, config: config)

      repo_name = Path.basename(src_dir)
      cloned_path = Path.join(dest_parent, repo_name)
      assert File.dir?(cloned_path)
      assert File.dir?(Path.join(cloned_path, ".git"))
    end

    test "clones into a custom directory name", %{
      src_dir: src_dir,
      dest_parent: dest_parent,
      config: config
    } do
      assert {:ok, :done} = GitWrapperEx.clone(src_dir, directory: "custom-name", config: config)

      cloned_path = Path.join(dest_parent, "custom-name")
      assert File.dir?(cloned_path)
      assert File.dir?(Path.join(cloned_path, ".git"))
    end

    test "clones with --depth=1 (shallow clone)", %{src_dir: src_dir, config: config} do
      assert {:ok, :done} = GitWrapperEx.clone(src_dir, depth: 1, config: config)
    end

    test "clones with --branch flag", %{src_dir: src_dir, config: config} do
      assert {:ok, :done} = GitWrapperEx.clone(src_dir, branch: "main", config: config)
    end

    test "returns error for invalid URL", %{dest_parent: dest_parent} do
      config = Config.new(working_dir: dest_parent)

      assert {:error, {_stdout, _exit_code}} =
               GitWrapperEx.clone("/nonexistent/path/to/repo", config: config)
    end
  end
end
