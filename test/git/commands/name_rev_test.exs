defmodule Git.Commands.NameRevTest do
  use ExUnit.Case, async: true

  alias Git.Commands.NameRev
  alias Git.Config

  describe "args/1" do
    test "commit only" do
      assert NameRev.args(%NameRev{commit: "HEAD"}) == ["name-rev", "HEAD"]
    end

    test "name_only" do
      assert NameRev.args(%NameRev{commit: "HEAD", name_only: true}) ==
               ["name-rev", "--name-only", "HEAD"]
    end

    test "name_only and tags" do
      assert NameRev.args(%NameRev{commit: "HEAD", name_only: true, tags: true}) ==
               ["name-rev", "--name-only", "--tags", "HEAD"]
    end
  end

  describe "parse_output/2" do
    test "trims the name" do
      assert NameRev.parse_output("main\n", 0) == {:ok, "main"}
    end

    test "keeps the input prefix in default mode" do
      assert NameRev.parse_output("HEAD main\n", 0) == {:ok, "HEAD main"}
    end

    test "non-zero exit returns error" do
      assert NameRev.parse_output("boom", 1) == {:error, {"boom", 1}}
    end
  end

  describe "Git.name_rev/1 integration" do
    setup do
      tmp =
        Path.join(System.tmp_dir!(), "git_name_rev_test_#{:erlang.unique_integer([:positive])}")

      File.mkdir_p!(tmp)
      System.cmd("git", ["init", "--initial-branch=main"], cd: tmp)

      System.cmd(
        "git",
        [
          "-c",
          "user.name=T",
          "-c",
          "user.email=t@t.com",
          "commit",
          "--allow-empty",
          "-m",
          "init"
        ],
        cd: tmp
      )

      cfg = Config.new(working_dir: tmp)
      on_exit(fn -> Git.TestHelpers.rm_rf(tmp) end)
      %{tmp: tmp, config: cfg}
    end

    test "names HEAD by its branch", %{config: config} do
      {:ok, name} = Git.name_rev(commit: "HEAD", name_only: true, config: config)
      assert name == "main"
    end

    test "default mode includes the input revision", %{config: config} do
      {:ok, name} = Git.name_rev(commit: "HEAD", config: config)
      assert String.contains?(name, "main")
      assert String.contains?(name, "HEAD")
    end

    test "names by tag with tags mode", %{tmp: tmp, config: config} do
      System.cmd("git", ["tag", "v1.0"], cd: tmp)
      {:ok, name} = Git.name_rev(commit: "HEAD", name_only: true, tags: true, config: config)
      assert String.contains?(name, "v1.0")
    end
  end
end
