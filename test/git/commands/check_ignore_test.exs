defmodule Git.CheckIgnoreTest do
  use ExUnit.Case, async: true

  alias Git.Commands.CheckIgnore
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
        "git_check_ignore_test_#{:erlang.unique_integer([:positive])}"
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
    test "builds args with paths" do
      assert CheckIgnore.args(%CheckIgnore{paths: ["build/", "tmp.log"]}) ==
               ["check-ignore", "build/", "tmp.log"]
    end

    test "builds args with verbose flag" do
      assert CheckIgnore.args(%CheckIgnore{paths: ["foo"], verbose: true}) ==
               ["check-ignore", "-v", "foo"]
    end

    test "builds args with verbose and non_matching" do
      assert CheckIgnore.args(%CheckIgnore{paths: ["foo"], verbose: true, non_matching: true}) ==
               ["check-ignore", "-v", "-n", "foo"]
    end

    test "builds args with no_index flag" do
      assert CheckIgnore.args(%CheckIgnore{paths: ["foo"], no_index: true}) ==
               ["check-ignore", "--no-index", "foo"]
    end

    test "builds args with quiet flag" do
      assert CheckIgnore.args(%CheckIgnore{paths: ["foo"], quiet: true}) ==
               ["check-ignore", "-q", "foo"]
    end
  end

  describe "check-ignore with ignored files" do
    test "returns list of ignored paths" do
      {tmp_dir, cfg} = setup_repo()

      File.write!(Path.join(tmp_dir, ".gitignore"), "*.log\nbuild/\n")
      File.write!(Path.join(tmp_dir, "app.log"), "log content")
      File.mkdir_p!(Path.join(tmp_dir, "build"))

      {:ok, paths} = Git.check_ignore(paths: ["app.log", "build/"], config: cfg)
      assert "app.log" in paths
      assert "build/" in paths
    end

    test "returns empty list when no paths are ignored" do
      {tmp_dir, cfg} = setup_repo()

      File.write!(Path.join(tmp_dir, ".gitignore"), "*.log\n")
      File.write!(Path.join(tmp_dir, "main.ex"), "code")

      {:ok, paths} = Git.check_ignore(paths: ["main.ex"], config: cfg)
      assert paths == []
    end
  end

  describe "check-ignore --verbose" do
    test "returns verbose entries with source, line_number, pattern, and path" do
      {tmp_dir, cfg} = setup_repo()

      File.write!(Path.join(tmp_dir, ".gitignore"), "*.log\nbuild/\n")
      File.write!(Path.join(tmp_dir, "app.log"), "log content")

      {:ok, entries} = Git.check_ignore(paths: ["app.log"], verbose: true, config: cfg)
      assert length(entries) == 1
      [entry] = entries
      assert entry.path == "app.log"
      assert entry.pattern == "*.log"
      assert entry.line_number == 1
      assert entry.source =~ ".gitignore"
    end
  end
end
