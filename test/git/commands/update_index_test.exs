defmodule Git.Commands.UpdateIndexTest do
  use ExUnit.Case, async: true

  alias Git.Commands.UpdateIndex
  alias Git.Config

  describe "args/1 and input/1" do
    test "builds flags and pathspec" do
      assert UpdateIndex.args(%UpdateIndex{add: true, files: ["a.txt"]}) ==
               ["update-index", "--add", "--", "a.txt"]

      assert UpdateIndex.args(%UpdateIndex{skip_worktree: true, files: ["cfg"]}) ==
               ["update-index", "--skip-worktree", "--", "cfg"]
    end

    test "builds --cacheinfo entries" do
      assert UpdateIndex.args(%UpdateIndex{cacheinfo: [{"100644", "abc123", "f.txt"}]}) ==
               ["update-index", "--cacheinfo", "100644,abc123,f.txt"]
    end

    test "input is the stdin payload only in --index-info mode" do
      assert UpdateIndex.input(%UpdateIndex{index_info: true, stdin: "x"}) == "x"
      assert UpdateIndex.input(%UpdateIndex{stdin: "x"}) == nil
    end
  end

  describe "update-index integration" do
    setup do
      tmp_dir =
        Path.join(
          System.tmp_dir!(),
          "git_wrapper_update_index_test_#{:erlang.unique_integer([:positive])}"
        )

      File.mkdir_p!(tmp_dir)
      System.cmd("git", ["init", "--initial-branch=main"], cd: tmp_dir)
      on_exit(fn -> Git.TestHelpers.rm_rf(tmp_dir) end)

      %{tmp_dir: tmp_dir, config: Config.new(working_dir: tmp_dir)}
    end

    defp write_blob(tmp_dir, content) do
      File.write!(Path.join(tmp_dir, "blob.tmp"), content)
      {blob, 0} = System.cmd("git", ["hash-object", "-w", "blob.tmp"], cd: tmp_dir)
      File.rm!(Path.join(tmp_dir, "blob.tmp"))
      String.trim(blob)
    end

    test "cacheinfo inserts an index entry from a blob sha", %{tmp_dir: tmp_dir, config: config} do
      blob = write_blob(tmp_dir, "content\n")

      assert {:ok, :done} =
               Git.update_index(
                 add: true,
                 cacheinfo: [{"100644", blob, "from_cacheinfo.txt"}],
                 config: config
               )

      {listing, 0} = System.cmd("git", ["ls-files"], cd: tmp_dir)
      assert listing =~ "from_cacheinfo.txt"
    end

    test "index_info populates the index from stdin (via forcola)", %{
      tmp_dir: tmp_dir,
      config: config
    } do
      blob = write_blob(tmp_dir, "via stdin\n")
      payload = "100644 #{blob} 0\tfrom_stdin.txt\n"

      assert {:ok, :done} = Git.update_index(index_info: true, stdin: payload, config: config)

      {listing, 0} = System.cmd("git", ["ls-files"], cd: tmp_dir)
      assert listing =~ "from_stdin.txt"
    end

    test "skip_worktree sets the skip-worktree bit", %{tmp_dir: tmp_dir, config: config} do
      File.write!(Path.join(tmp_dir, "tracked.txt"), "x\n")
      System.cmd("git", ["add", "tracked.txt"], cd: tmp_dir)

      assert {:ok, :done} =
               Git.update_index(skip_worktree: true, files: ["tracked.txt"], config: config)

      {listing, 0} = System.cmd("git", ["ls-files", "-v"], cd: tmp_dir)
      assert listing =~ ~r/^S tracked\.txt/m
    end
  end
end
