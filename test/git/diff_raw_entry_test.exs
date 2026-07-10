defmodule Git.DiffRawEntryTest do
  use ExUnit.Case, async: true

  alias Git.DiffRawEntry

  @zero "0000000000000000000000000000000000000000"

  describe "parse/1" do
    test "empty input yields no entries" do
      assert DiffRawEntry.parse("") == []
    end

    test "parses a single modified record" do
      raw = ":100644 100644 aaaa1111 bbbb2222 M\0lib/foo.ex\0"

      assert [
               %DiffRawEntry{
                 old_mode: "100644",
                 new_mode: "100644",
                 old_sha: "aaaa1111",
                 new_sha: "bbbb2222",
                 status: "M",
                 path: "lib/foo.ex"
               }
             ] = DiffRawEntry.parse(raw)
    end

    test "parses added, deleted, and modified records in order" do
      raw =
        ":100644 100644 aaaa bbbb M\0a.txt\0" <>
          ":100644 #{@zero} cccc #{@zero} D\0c.txt\0" <>
          ":#{@zero} 100644 #{@zero} dddd A\0d.txt\0"

      assert [
               %DiffRawEntry{status: "M", path: "a.txt"},
               %DiffRawEntry{status: "D", path: "c.txt", new_sha: @zero},
               %DiffRawEntry{status: "A", path: "d.txt", old_sha: @zero}
             ] = DiffRawEntry.parse(raw)
    end

    test "rename record keeps the destination path and the scored status" do
      raw = ":100644 100644 aaaa aaaa R100\0old.txt\0renamed.txt\0"

      assert [
               %DiffRawEntry{
                 status: "R100",
                 path: "renamed.txt"
               }
             ] = DiffRawEntry.parse(raw)
    end

    test "copy record keeps the destination path and the scored status" do
      raw = ":100644 100644 aaaa aaaa C75\0src.txt\0copy.txt\0"

      assert [%DiffRawEntry{status: "C75", path: "copy.txt"}] = DiffRawEntry.parse(raw)
    end

    test "skips a leading bare commit-id header (single-arg diff-tree)" do
      raw =
        "c653c4a1b015415b733ffb6092fb0985a5141a74\0" <>
          ":100644 #{@zero} b15c #{@zero} D\0old.txt\0"

      assert [%DiffRawEntry{status: "D", path: "old.txt"}] = DiffRawEntry.parse(raw)
    end

    test "skips combined-diff records prefixed with double colon" do
      raw = "::100644 100644 100644 aaaa bbbb cccc MM\0merged.txt\0"

      assert DiffRawEntry.parse(raw) == []
    end
  end
end
