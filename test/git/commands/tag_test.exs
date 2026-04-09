defmodule Git.Commands.TagTest do
  use ExUnit.Case, async: true

  alias Git.Commands.Tag
  alias Git.Config

  setup do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "git_wrapper_tag_test_#{:erlang.unique_integer([:positive])}"
      )

    File.mkdir_p!(tmp_dir)

    System.cmd("git", ["init", "--initial-branch=main"], cd: tmp_dir)
    System.cmd("git", ["config", "user.name", "Test User"], cd: tmp_dir)
    System.cmd("git", ["config", "user.email", "test@test.com"], cd: tmp_dir)

    System.cmd(
      "git",
      ["commit", "--allow-empty", "-m", "initial"],
      cd: tmp_dir
    )

    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    config = Config.new(working_dir: tmp_dir)

    %{tmp_dir: tmp_dir, config: config}
  end

  describe "Commands.Tag.args/1" do
    test "list (default)" do
      assert Tag.args(%Tag{}) ==
               ["tag", "-l", "--format=#{Git.Tag.format_string()}"]
    end

    test "list with sort" do
      assert Tag.args(%Tag{sort: "-creatordate"}) ==
               ["tag", "-l", "--sort=-creatordate", "--format=#{Git.Tag.format_string()}"]
    end

    test "create lightweight tag" do
      assert Tag.args(%Tag{create: "v1.0.0"}) == ["tag", "v1.0.0"]
    end

    test "create annotated tag" do
      assert Tag.args(%Tag{create: "v1.0.0", message: "release 1.0"}) ==
               ["tag", "-a", "v1.0.0", "-m", "release 1.0"]
    end

    test "create tag at specific ref" do
      assert Tag.args(%Tag{create: "v1.0.0", ref: "abc123"}) ==
               ["tag", "v1.0.0", "abc123"]
    end

    test "create annotated tag at specific ref" do
      assert Tag.args(%Tag{create: "v1.0.0", message: "release", ref: "abc123"}) ==
               ["tag", "-a", "v1.0.0", "-m", "release", "abc123"]
    end

    test "delete tag" do
      assert Tag.args(%Tag{delete: "v1.0.0"}) == ["tag", "-d", "v1.0.0"]
    end
  end

  describe "integration" do
    test "create, list, and delete a lightweight tag", %{config: config} do
      # Create a tag
      assert {:ok, :done} = Git.tag(create: "v1.0.0", config: config)

      # List tags
      assert {:ok, tags} = Git.tag(config: config)
      names = Enum.map(tags, & &1.name)
      assert "v1.0.0" in names

      # Delete the tag
      assert {:ok, :done} = Git.tag(delete: "v1.0.0", config: config)

      # Verify deletion
      assert {:ok, tags} = Git.tag(config: config)
      names = Enum.map(tags, & &1.name)
      refute "v1.0.0" in names
    end

    test "create and list an annotated tag", %{config: config} do
      assert {:ok, :done} =
               Git.tag(create: "v2.0.0", message: "release 2.0", config: config)

      assert {:ok, tags} = Git.tag(config: config)
      tag = Enum.find(tags, fn t -> t.name == "v2.0.0" end)
      assert tag != nil
      assert tag.message =~ "release 2.0"
    end

    test "empty tag list on fresh repo", %{config: config} do
      assert {:ok, []} = Git.tag(config: config)
    end
  end
end
