defmodule GitWrapper.TagTest do
  use ExUnit.Case, async: true

  alias GitWrapper.Tag
  alias GitWrapper.Commands.Tag, as: TagCmd

  # ---------------------------------------------------------------------------
  # Test helpers
  # ---------------------------------------------------------------------------

  defp setup_repo do
    dir =
      Path.join(
        System.tmp_dir!(),
        "git_wrapper_tag_test_#{:erlang.unique_integer([:positive])}"
      )

    File.mkdir_p!(dir)
    System.cmd("git", ["init", "--initial-branch=main"], cd: dir)
    System.cmd("git", ["config", "user.email", "test@example.com"], cd: dir)
    System.cmd("git", ["config", "user.name", "Test User"], cd: dir)
    System.cmd("git", ["commit", "--allow-empty", "-m", "init"], cd: dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    {GitWrapper.Config.new(working_dir: dir), dir}
  end

  # ---------------------------------------------------------------------------
  # Unit tests: Tag.parse_list/1
  # ---------------------------------------------------------------------------

  describe "Tag.parse_list/1" do
    test "empty output returns empty list" do
      assert Tag.parse_list("") == []
    end

    test "parses single tag" do
      assert [%Tag{name: "v1.0.0"}] = Tag.parse_list("v1.0.0\n")
    end

    test "parses multiple tags" do
      output = "v1.0.0\nv1.1.0\nv2.0.0\n"
      tags = Tag.parse_list(output)
      assert length(tags) == 3
      assert Enum.map(tags, & &1.name) == ["v1.0.0", "v1.1.0", "v2.0.0"]
    end
  end

  # ---------------------------------------------------------------------------
  # Unit tests: Tag.parse_detailed/1
  # ---------------------------------------------------------------------------

  describe "Tag.parse_detailed/1" do
    test "empty output returns empty list" do
      assert Tag.parse_detailed("") == []
    end

    test "parses lightweight tag" do
      rs = "\x1e"
      us = "\x1f"
      output = "#{rs}v1.0.0#{us}commit#{us}#{us}#{us}#{us}init"
      tags = Tag.parse_detailed(output)
      assert length(tags) == 1
      tag = hd(tags)
      assert tag.name == "v1.0.0"
      assert tag.annotated == false
      assert tag.tagger_name == nil
      assert tag.message == nil
    end

    test "parses annotated tag" do
      rs = "\x1e"
      us = "\x1f"

      output =
        "#{rs}v2.0.0#{us}tag#{us}Test User#{us}<test@example.com>#{us}2026-01-01T00:00:00+00:00#{us}release 2.0"

      tags = Tag.parse_detailed(output)
      assert length(tags) == 1
      tag = hd(tags)
      assert tag.name == "v2.0.0"
      assert tag.annotated == true
      assert tag.tagger_name == "Test User"
      assert tag.tagger_email == "test@example.com"
      assert tag.date == "2026-01-01T00:00:00+00:00"
      assert tag.message == "release 2.0"
    end

    test "parses mixed lightweight and annotated tags" do
      rs = "\x1e"
      us = "\x1f"

      output =
        "#{rs}v1.0.0#{us}commit#{us}#{us}#{us}#{us}init" <>
          "#{rs}v2.0.0#{us}tag#{us}Test User#{us}<test@example.com>#{us}2026-01-01T00:00:00+00:00#{us}release 2.0"

      tags = Tag.parse_detailed(output)
      assert length(tags) == 2
      lightweight = Enum.find(tags, &(&1.name == "v1.0.0"))
      annotated = Enum.find(tags, &(&1.name == "v2.0.0"))
      assert lightweight.annotated == false
      assert annotated.annotated == true
    end
  end

  # ---------------------------------------------------------------------------
  # Unit tests: Commands.Tag.args/1
  # ---------------------------------------------------------------------------

  describe "Commands.Tag.args/1" do
    test "default struct produces list args" do
      args = TagCmd.args(%TagCmd{})
      assert ["tag", "-l", "--format=" <> _format] = args
    end

    test "create lightweight tag" do
      assert TagCmd.args(%TagCmd{create: "v1.0.0"}) == ["tag", "v1.0.0"]
    end

    test "create annotated tag" do
      assert TagCmd.args(%TagCmd{create: "v1.0.0", message: "release 1.0"}) ==
               ["tag", "-a", "v1.0.0", "-m", "release 1.0"]
    end

    test "create annotated tag at specific ref" do
      assert TagCmd.args(%TagCmd{create: "v1.0.0", message: "release 1.0", ref: "abc1234"}) ==
               ["tag", "-a", "v1.0.0", "-m", "release 1.0", "abc1234"]
    end

    test "create lightweight tag at specific ref" do
      assert TagCmd.args(%TagCmd{create: "v1.0.0", ref: "abc1234"}) ==
               ["tag", "v1.0.0", "abc1234"]
    end

    test "delete tag" do
      assert TagCmd.args(%TagCmd{delete: "v1.0.0"}) == ["tag", "-d", "v1.0.0"]
    end

    test "list with sort" do
      args = TagCmd.args(%TagCmd{sort: "-version:refname"})
      assert ["tag", "-l", "--sort=-version:refname", "--format=" <> _] = args
    end
  end

  # ---------------------------------------------------------------------------
  # Unit tests: Commands.Tag.parse_output/2
  # ---------------------------------------------------------------------------

  describe "Commands.Tag.parse_output/2" do
    test "empty list output returns empty list" do
      # Set up list mode
      TagCmd.args(%TagCmd{})
      assert {:ok, []} = TagCmd.parse_output("", 0)
    end

    test "non-zero exit returns error tuple" do
      assert {:error, {"error msg", 1}} = TagCmd.parse_output("error msg", 1)
    end
  end

  # ---------------------------------------------------------------------------
  # Integration tests
  # ---------------------------------------------------------------------------

  describe "GitWrapperEx.tag/1 integration" do
    test "lists tags in empty repo" do
      {config, _dir} = setup_repo()
      assert {:ok, []} = GitWrapperEx.tag(config: config)
    end

    test "create lightweight tag returns :done" do
      {config, _dir} = setup_repo()
      assert {:ok, :done} = GitWrapperEx.tag(config: config, create: "v1.0.0")
    end

    test "created lightweight tag appears in listing" do
      {config, _dir} = setup_repo()
      GitWrapperEx.tag(config: config, create: "v1.0.0")

      assert {:ok, tags} = GitWrapperEx.tag(config: config)
      names = Enum.map(tags, & &1.name)
      assert "v1.0.0" in names
    end

    test "lightweight tag is not annotated" do
      {config, _dir} = setup_repo()
      GitWrapperEx.tag(config: config, create: "v1.0.0")

      assert {:ok, tags} = GitWrapperEx.tag(config: config)
      tag = Enum.find(tags, &(&1.name == "v1.0.0"))
      assert tag.annotated == false
    end

    test "create annotated tag returns :done" do
      {config, _dir} = setup_repo()
      assert {:ok, :done} = GitWrapperEx.tag(config: config, create: "v2.0.0", message: "release 2.0")
    end

    test "annotated tag appears with metadata" do
      {config, _dir} = setup_repo()
      GitWrapperEx.tag(config: config, create: "v2.0.0", message: "release 2.0")

      assert {:ok, tags} = GitWrapperEx.tag(config: config)
      tag = Enum.find(tags, &(&1.name == "v2.0.0"))
      assert tag.annotated == true
      assert tag.tagger_name == "Test User"
      assert tag.tagger_email == "test@example.com"
      assert tag.message == "release 2.0"
    end

    test "delete tag returns :done" do
      {config, _dir} = setup_repo()
      GitWrapperEx.tag(config: config, create: "v1.0.0")

      assert {:ok, :done} = GitWrapperEx.tag(config: config, delete: "v1.0.0")
    end

    test "deleted tag no longer appears in listing" do
      {config, _dir} = setup_repo()
      GitWrapperEx.tag(config: config, create: "v1.0.0")
      GitWrapperEx.tag(config: config, delete: "v1.0.0")

      assert {:ok, tags} = GitWrapperEx.tag(config: config)
      names = Enum.map(tags, & &1.name)
      refute "v1.0.0" in names
    end

    test "deleting non-existent tag returns error" do
      {config, _dir} = setup_repo()
      assert {:error, _} = GitWrapperEx.tag(config: config, delete: "nonexistent")
    end

    test "multiple tags all appear in listing" do
      {config, _dir} = setup_repo()
      GitWrapperEx.tag(config: config, create: "v1.0.0")
      GitWrapperEx.tag(config: config, create: "v2.0.0", message: "release 2.0")
      GitWrapperEx.tag(config: config, create: "v3.0.0")

      assert {:ok, tags} = GitWrapperEx.tag(config: config)
      names = Enum.map(tags, & &1.name)
      assert "v1.0.0" in names
      assert "v2.0.0" in names
      assert "v3.0.0" in names
    end

    test "create tag at specific ref" do
      {config, dir} = setup_repo()
      # Create a second commit
      System.cmd("git", ["commit", "--allow-empty", "-m", "second"], cd: dir)

      # Get the first commit hash
      {hash, 0} = System.cmd("git", ["rev-parse", "HEAD~1"], cd: dir)
      hash = String.trim(hash)

      assert {:ok, :done} = GitWrapperEx.tag(config: config, create: "v0.1.0", ref: hash)

      # Verify the tag points to the right commit
      {tagged_hash, 0} = System.cmd("git", ["rev-parse", "v0.1.0"], cd: dir)
      assert String.trim(tagged_hash) == hash
    end
  end
end
