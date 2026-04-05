defmodule Git.CatFileTest do
  use ExUnit.Case, async: true

  alias Git.Commands.CatFile
  alias Git.Config

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
        "git_cat_file_test_#{:erlang.unique_integer([:positive])}"
      )

    File.mkdir_p!(tmp_dir)
    cfg = Config.new(working_dir: tmp_dir, env: @env)
    {:ok, :done} = Git.init(config: cfg)
    {:ok, :done} = Git.git_config(set_key: "user.name", set_value: "Test User", config: cfg)
    {:ok, :done} = Git.git_config(set_key: "user.email", set_value: "test@test.com", config: cfg)
    {:ok, _} = Git.commit("initial", allow_empty: true, config: cfg)
    on_exit(fn -> File.rm_rf!(tmp_dir) end)
    {tmp_dir, cfg}
  end

  describe "args/1" do
    test "builds args for type query" do
      assert CatFile.args(%CatFile{object: "HEAD", type: true}) ==
               ["cat-file", "-t", "HEAD"]
    end

    test "builds args for size query" do
      assert CatFile.args(%CatFile{object: "HEAD", size: true}) ==
               ["cat-file", "-s", "HEAD"]
    end

    test "builds args for pretty-print" do
      assert CatFile.args(%CatFile{object: "HEAD", print: true}) ==
               ["cat-file", "-p", "HEAD"]
    end

    test "builds args for exists check" do
      assert CatFile.args(%CatFile{object: "HEAD", exists: true}) ==
               ["cat-file", "-e", "HEAD"]
    end

    test "builds args for textconv" do
      assert CatFile.args(%CatFile{object: "HEAD", textconv: true}) ==
               ["cat-file", "--textconv", "HEAD"]
    end

    test "builds args for filters" do
      assert CatFile.args(%CatFile{object: "HEAD", filters: true}) ==
               ["cat-file", "--filters", "HEAD"]
    end

    test "defaults to pretty-print when no flag set" do
      assert CatFile.args(%CatFile{object: "HEAD"}) ==
               ["cat-file", "-p", "HEAD"]
    end
  end

  describe "cat-file -t (type)" do
    test "returns :commit for a commit object" do
      {_tmp_dir, cfg} = setup_repo()

      {:ok, type} = Git.cat_file("HEAD", type: true, config: cfg)
      assert type == :commit
    end
  end

  describe "cat-file -s (size)" do
    test "returns an integer size for a commit object" do
      {_tmp_dir, cfg} = setup_repo()

      {:ok, size} = Git.cat_file("HEAD", size: true, config: cfg)
      assert is_integer(size)
      assert size > 0
    end
  end

  describe "cat-file -p (print)" do
    test "returns commit content as a string" do
      {_tmp_dir, cfg} = setup_repo()

      {:ok, content} = Git.cat_file("HEAD", print: true, config: cfg)
      assert is_binary(content)
      assert content =~ "initial"
    end
  end

  describe "cat-file -e (exists)" do
    test "returns true for an existing object" do
      {_tmp_dir, cfg} = setup_repo()

      {:ok, exists} = Git.cat_file("HEAD", exists: true, config: cfg)
      assert exists == true
    end

    test "returns false for a non-existing object" do
      {_tmp_dir, cfg} = setup_repo()

      {:ok, exists} =
        Git.cat_file("deadbeefdeadbeefdeadbeefdeadbeefdeadbeef", exists: true, config: cfg)

      assert exists == false
    end
  end
end
