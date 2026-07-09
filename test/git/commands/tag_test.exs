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

    on_exit(fn -> Git.TestHelpers.rm_rf(tmp_dir) end)

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

    test "create lightweight tag with force" do
      assert Tag.args(%Tag{create: "v1.0.0", force: true}) == ["tag", "-f", "v1.0.0"]
    end

    test "create annotated tag with force" do
      assert Tag.args(%Tag{create: "v1.0.0", message: "release", force: true}) ==
               ["tag", "-f", "-a", "v1.0.0", "-m", "release"]
    end

    test "create annotated tag from a message file" do
      assert Tag.args(%Tag{create: "v1.0.0", file: "/tmp/msg"}) ==
               ["tag", "-a", "v1.0.0", "-F", "/tmp/msg"]
    end

    test "file takes precedence over message" do
      assert Tag.args(%Tag{create: "v1.0.0", file: "/tmp/msg", message: "ignored"}) ==
               ["tag", "-a", "v1.0.0", "-F", "/tmp/msg"]
    end

    test "create annotated tag from a message file with force and ref" do
      assert Tag.args(%Tag{create: "v1.0.0", file: "/tmp/msg", force: true, ref: "abc123"}) ==
               ["tag", "-f", "-a", "v1.0.0", "-F", "/tmp/msg", "abc123"]
    end

    test "list filtered by contains" do
      assert Tag.args(%Tag{contains: "abc123"}) ==
               ["tag", "-l", "--contains", "abc123", "--format=#{Git.Tag.format_string()}"]
    end

    test "list filtered by points_at" do
      assert Tag.args(%Tag{points_at: "abc123"}) ==
               ["tag", "-l", "--points-at", "abc123", "--format=#{Git.Tag.format_string()}"]
    end

    test "list filtered by glob" do
      assert Tag.args(%Tag{list_glob: "v1.*"}) ==
               ["tag", "-l", "--list", "v1.*", "--format=#{Git.Tag.format_string()}"]
    end

    test "list filters combine with sort" do
      assert Tag.args(%Tag{
               contains: "c",
               points_at: "o",
               list_glob: "v*",
               sort: "-creatordate"
             }) ==
               [
                 "tag",
                 "-l",
                 "--contains",
                 "c",
                 "--points-at",
                 "o",
                 "--list",
                 "v*",
                 "--sort=-creatordate",
                 "--format=#{Git.Tag.format_string()}"
               ]
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

    test "force re-creates (moves) a tag to a new commit", %{config: config, tmp_dir: tmp_dir} do
      assert {:ok, :done} = Git.tag(create: "v1.0.0", config: config)

      System.cmd("git", ["commit", "--allow-empty", "-m", "second"], cd: tmp_dir)
      {sha2, 0} = System.cmd("git", ["rev-parse", "HEAD"], cd: tmp_dir)
      sha2 = String.trim(sha2)

      # Re-creating an existing tag without force fails.
      assert {:error, _} = Git.tag(create: "v1.0.0", config: config)

      # With force it succeeds and moves the tag to the new HEAD.
      assert {:ok, :done} = Git.tag(create: "v1.0.0", force: true, config: config)

      {tagged, 0} = System.cmd("git", ["rev-list", "-n", "1", "v1.0.0"], cd: tmp_dir)
      assert String.trim(tagged) == sha2
    end

    test "create annotated tag from a message file", %{config: config, tmp_dir: tmp_dir} do
      msg_file = Path.join(tmp_dir, "TAG_MSG")
      File.write!(msg_file, "annotated from file\n")

      assert {:ok, :done} = Git.tag(create: "v3.0.0", file: msg_file, config: config)

      assert {:ok, tags} = Git.tag(config: config)
      tag = Enum.find(tags, fn t -> t.name == "v3.0.0" end)
      assert tag != nil
      assert tag.message =~ "annotated from file"
    end

    test "list tags containing a commit", %{config: config, tmp_dir: tmp_dir} do
      {sha1, 0} = System.cmd("git", ["rev-parse", "HEAD"], cd: tmp_dir)
      sha1 = String.trim(sha1)
      assert {:ok, :done} = Git.tag(create: "v1.0.0", config: config)

      System.cmd("git", ["commit", "--allow-empty", "-m", "second"], cd: tmp_dir)
      {sha2, 0} = System.cmd("git", ["rev-parse", "HEAD"], cd: tmp_dir)
      sha2 = String.trim(sha2)
      assert {:ok, :done} = Git.tag(create: "v2.0.0", config: config)

      # The first commit is contained by both tags.
      assert {:ok, tags} = Git.tag(contains: sha1, config: config)
      names = Enum.map(tags, & &1.name)
      assert "v1.0.0" in names
      assert "v2.0.0" in names

      # The second commit is contained only by v2.0.0.
      assert {:ok, tags2} = Git.tag(contains: sha2, config: config)
      names2 = Enum.map(tags2, & &1.name)
      assert "v2.0.0" in names2
      refute "v1.0.0" in names2
    end
  end
end
