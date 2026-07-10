defmodule Git.Commands.CountObjectsTest do
  use ExUnit.Case, async: true

  alias Git.Commands.CountObjects
  alias Git.Config

  describe "args/1" do
    test "always uses verbose mode" do
      assert CountObjects.args(%CountObjects{}) == ["count-objects", "-v"]
    end
  end

  describe "parse_output/2" do
    test "parses the full verbose output" do
      output = """
      count: 3
      size: 12
      in-pack: 5
      packs: 2
      size-pack: 4
      prune-packable: 1
      garbage: 0
      size-garbage: 0
      """

      {:ok, stats} = CountObjects.parse_output(output, 0)

      assert stats == %Git.CountObjects{
               count: 3,
               size: 12,
               in_pack: 5,
               packs: 2,
               size_pack: 4,
               prune_packable: 1,
               garbage: 0,
               size_garbage: 0
             }
    end

    test "missing keys default to zero" do
      {:ok, stats} = CountObjects.parse_output("count: 7\nsize: 20\n", 0)
      assert stats == %Git.CountObjects{count: 7, size: 20}
    end

    test "non-zero exit returns error" do
      assert CountObjects.parse_output("boom", 1) == {:error, {"boom", 1}}
    end
  end

  describe "Git.count_objects/1 integration" do
    setup do
      tmp =
        Path.join(
          System.tmp_dir!(),
          "git_count_objects_test_#{:erlang.unique_integer([:positive])}"
        )

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

      File.write!(Path.join(tmp, "a.txt"), "hello")
      System.cmd("git", ["add", "a.txt"], cd: tmp)

      System.cmd(
        "git",
        ["-c", "user.name=T", "-c", "user.email=t@t.com", "commit", "-m", "add a"],
        cd: tmp
      )

      cfg = Config.new(working_dir: tmp)
      on_exit(fn -> Git.TestHelpers.rm_rf(tmp) end)
      %{config: cfg}
    end

    test "returns object statistics", %{config: config} do
      {:ok, stats} = Git.count_objects(config: config)
      assert %Git.CountObjects{} = stats
      assert is_integer(stats.count)
      assert is_integer(stats.in_pack)
      # A repo with commits holds at least one object, loose or packed.
      assert stats.count + stats.in_pack >= 1
    end
  end
end
