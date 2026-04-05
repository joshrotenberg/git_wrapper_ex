defmodule Git.ResetTest do
  use ExUnit.Case, async: true

  alias Git.Commands.Reset
  alias Git.Config

  @env [
    {"GIT_AUTHOR_NAME", "Test User"},
    {"GIT_AUTHOR_EMAIL", "test@test.com"},
    {"GIT_COMMITTER_NAME", "Test User"},
    {"GIT_COMMITTER_EMAIL", "test@test.com"}
  ]

  setup do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "git_wrapper_reset_test_#{:erlang.unique_integer([:positive])}"
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
        "initial commit"
      ],
      cd: tmp_dir
    )

    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    config = Config.new(working_dir: tmp_dir, env: @env)
    %{tmp_dir: tmp_dir, config: config}
  end

  describe "Git.Commands.Reset args/1" do
    test "builds args for default mixed mode to HEAD" do
      assert Reset.args(%Reset{}) == ["reset", "--mixed", "HEAD"]
    end

    test "builds args for soft mode" do
      assert Reset.args(%Reset{mode: :soft}) == ["reset", "--soft", "HEAD"]
    end

    test "builds args for hard mode" do
      assert Reset.args(%Reset{mode: :hard}) == ["reset", "--hard", "HEAD"]
    end

    test "builds args with custom ref" do
      assert Reset.args(%Reset{ref: "HEAD~1", mode: :soft}) == ["reset", "--soft", "HEAD~1"]
    end

    test "builds args with mixed mode and custom ref" do
      assert Reset.args(%Reset{ref: "HEAD~2", mode: :mixed}) == ["reset", "--mixed", "HEAD~2"]
    end
  end

  describe "git reset --mixed (default)" do
    test "unstages a staged file", %{tmp_dir: tmp_dir, config: config} do
      File.write!(Path.join(tmp_dir, "hello.txt"), "hello\n")
      System.cmd("git", ["add", "hello.txt"], cd: tmp_dir)

      assert {:ok, :done} = Git.reset(config: config)
    end

    test "succeeds on a clean working tree", %{config: config} do
      assert {:ok, :done} = Git.reset(config: config)
    end
  end

  describe "git reset --soft" do
    test "moves HEAD back but keeps changes staged", %{tmp_dir: tmp_dir, config: config} do
      File.write!(Path.join(tmp_dir, "file.txt"), "content\n")
      System.cmd("git", ["add", "file.txt"], cd: tmp_dir)

      System.cmd(
        "git",
        [
          "-c",
          "user.name=Test User",
          "-c",
          "user.email=test@test.com",
          "commit",
          "-m",
          "second commit"
        ],
        cd: tmp_dir,
        env: @env
      )

      assert {:ok, :done} = Git.reset(mode: :soft, ref: "HEAD~1", config: config)
    end
  end

  describe "git reset --hard" do
    test "discards staged changes", %{tmp_dir: tmp_dir, config: config} do
      File.write!(Path.join(tmp_dir, "dirty.txt"), "dirty\n")
      System.cmd("git", ["add", "dirty.txt"], cd: tmp_dir)

      assert {:ok, :done} = Git.reset(mode: :hard, config: config)
    end

    test "discards unstaged changes", %{tmp_dir: tmp_dir, config: config} do
      File.write!(Path.join(tmp_dir, "file.txt"), "content\n")
      System.cmd("git", ["add", "file.txt"], cd: tmp_dir)

      System.cmd(
        "git",
        [
          "-c",
          "user.name=Test User",
          "-c",
          "user.email=test@test.com",
          "commit",
          "-m",
          "tracked file"
        ],
        cd: tmp_dir,
        env: @env
      )

      File.write!(Path.join(tmp_dir, "file.txt"), "modified\n")

      assert {:ok, :done} = Git.reset(mode: :hard, config: config)
    end
  end

  describe "reset failure" do
    test "returns error for invalid ref", %{config: config} do
      assert {:error, {output, exit_code}} =
               Git.reset(ref: "nonexistent-sha-abc123", config: config)

      assert exit_code != 0
      assert is_binary(output)
    end
  end
end
