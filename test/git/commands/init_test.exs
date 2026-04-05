defmodule Git.InitTest do
  use ExUnit.Case, async: true

  alias Git.Commands.Init
  alias Git.Config

  setup do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "git_wrapper_init_test_#{:erlang.unique_integer([:positive])}"
      )

    File.mkdir_p!(tmp_dir)
    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    config = Config.new(working_dir: tmp_dir)

    %{tmp_dir: tmp_dir, config: config}
  end

  describe "Git.Commands.Init args/1" do
    test "builds basic init args" do
      assert Init.args(%Init{}) == ["init"]
    end

    test "builds args with --bare flag" do
      assert Init.args(%Init{bare: true}) == ["init", "--bare"]
    end

    test "builds args with a path" do
      assert Init.args(%Init{path: "/tmp/repo"}) == ["init", "/tmp/repo"]
    end

    test "builds args with --bare and a path" do
      assert Init.args(%Init{bare: true, path: "/tmp/repo.git"}) ==
               ["init", "--bare", "/tmp/repo.git"]
    end
  end

  describe "Git.Commands.Init parse_output/2" do
    test "returns ok done on exit 0" do
      assert {:ok, :done} = Init.parse_output("Initialized empty Git repository", 0)
    end

    test "returns error tuple on non-zero exit" do
      assert {:error, {"some error", 128}} = Init.parse_output("some error", 128)
    end
  end

  describe "Git.init/1" do
    test "initializes a new repository in the working directory", %{config: config} do
      assert {:ok, :done} = Git.init(config: config)
      assert File.dir?(Path.join(config.working_dir, ".git"))
    end

    test "initializes a bare repository with bare: true", %{tmp_dir: tmp_dir} do
      bare_dir = Path.join(tmp_dir, "bare.git")
      File.mkdir_p!(bare_dir)
      config = Config.new(working_dir: bare_dir)

      assert {:ok, :done} = Git.init(bare: true, config: config)
      assert File.dir?(Path.join(bare_dir, "refs"))
      refute File.dir?(Path.join(bare_dir, ".git"))
    end

    test "initializes a repository at a given path", %{tmp_dir: tmp_dir, config: config} do
      sub_dir = Path.join(tmp_dir, "subrepo")

      assert {:ok, :done} = Git.init(path: sub_dir, config: config)
      assert File.dir?(Path.join(sub_dir, ".git"))
    end

    test "reinitializes an existing repository", %{config: config} do
      System.cmd("git", ["init"], cd: config.working_dir)

      assert {:ok, :done} = Git.init(config: config)
    end
  end
end
