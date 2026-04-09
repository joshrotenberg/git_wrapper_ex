defmodule Git.TagsTest do
  use ExUnit.Case, async: true

  @git_env [
    {"GIT_AUTHOR_NAME", "Test User"},
    {"GIT_AUTHOR_EMAIL", "test@example.com"},
    {"GIT_COMMITTER_NAME", "Test User"},
    {"GIT_COMMITTER_EMAIL", "test@example.com"}
  ]

  defp setup_repo(name) do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "git_#{name}_test_#{:erlang.unique_integer([:positive])}"
      )

    File.mkdir_p!(tmp_dir)
    System.cmd("git", ["init", "--initial-branch=main"], cd: tmp_dir)
    System.cmd("git", ["config", "user.name", "Test User"], cd: tmp_dir)
    System.cmd("git", ["config", "user.email", "test@test.com"], cd: tmp_dir)

    System.cmd("git", ["commit", "--allow-empty", "-m", "initial"],
      cd: tmp_dir,
      env: @git_env
    )

    cfg = Git.Config.new(working_dir: tmp_dir, env: @git_env)

    on_exit(fn -> File.rm_rf!(tmp_dir) end)
    {tmp_dir, cfg}
  end

  defp write_and_commit(dir, filename, content, msg) do
    File.write!(Path.join(dir, filename), content)
    System.cmd("git", ["add", filename], cd: dir)
    System.cmd("git", ["commit", "-m", msg], cd: dir, env: @git_env)
  end

  # ---------------------------------------------------------------------------
  # create/2
  # ---------------------------------------------------------------------------

  describe "create/2" do
    test "creates a lightweight tag" do
      {dir, cfg} = setup_repo("tags_create_light")
      write_and_commit(dir, "file.txt", "content\n", "add file")

      assert {:ok, :done} = Git.Tags.create("v1.0.0", config: cfg)

      {output, 0} = System.cmd("git", ["tag", "-l"], cd: dir)
      assert String.contains?(output, "v1.0.0")
    end

    test "creates an annotated tag with message" do
      {dir, cfg} = setup_repo("tags_create_annotated")
      write_and_commit(dir, "file.txt", "content\n", "add file")

      assert {:ok, :done} = Git.Tags.create("v1.0.0", message: "release 1.0", config: cfg)

      {output, 0} = System.cmd("git", ["tag", "-l", "-n1"], cd: dir)
      assert String.contains?(output, "v1.0.0")
      assert String.contains?(output, "release 1.0")
    end

    test "creates a tag on a specific ref" do
      {dir, cfg} = setup_repo("tags_create_ref")
      write_and_commit(dir, "file.txt", "first\n", "first")
      {sha1, 0} = System.cmd("git", ["rev-parse", "HEAD"], cd: dir)
      sha1 = String.trim(sha1)

      write_and_commit(dir, "file.txt", "second\n", "second")

      assert {:ok, :done} = Git.Tags.create("v0.1.0", ref: sha1, config: cfg)

      {tagged_sha, 0} = System.cmd("git", ["rev-parse", "v0.1.0"], cd: dir)
      assert String.trim(tagged_sha) == sha1
    end
  end

  # ---------------------------------------------------------------------------
  # list/1
  # ---------------------------------------------------------------------------

  describe "list/1" do
    test "returns empty list when no tags" do
      {_dir, cfg} = setup_repo("tags_list_empty")

      assert {:ok, []} = Git.Tags.list(config: cfg)
    end

    test "returns all tags" do
      {dir, cfg} = setup_repo("tags_list")
      write_and_commit(dir, "file.txt", "content\n", "add file")

      System.cmd("git", ["tag", "v1.0.0"], cd: dir)
      System.cmd("git", ["tag", "v2.0.0"], cd: dir)

      assert {:ok, tags} = Git.Tags.list(config: cfg)
      names = Enum.map(tags, & &1.name)
      assert "v1.0.0" in names
      assert "v2.0.0" in names
    end
  end

  # ---------------------------------------------------------------------------
  # latest/1
  # ---------------------------------------------------------------------------

  describe "latest/1" do
    test "returns the most recent tag" do
      {dir, cfg} = setup_repo("tags_latest")
      write_and_commit(dir, "file.txt", "v1\n", "v1")
      System.cmd("git", ["tag", "v1.0.0"], cd: dir)

      write_and_commit(dir, "file.txt", "v2\n", "v2")
      System.cmd("git", ["tag", "v2.0.0"], cd: dir)

      assert {:ok, "v2.0.0"} = Git.Tags.latest(config: cfg)
    end

    test "returns error when no tags exist" do
      {_dir, cfg} = setup_repo("tags_latest_none")

      assert {:error, _} = Git.Tags.latest(config: cfg)
    end
  end

  # ---------------------------------------------------------------------------
  # sorted/1
  # ---------------------------------------------------------------------------

  describe "sorted/1" do
    test "sorts tags by semantic version" do
      {dir, cfg} = setup_repo("tags_sorted")
      write_and_commit(dir, "file.txt", "content\n", "add file")

      System.cmd("git", ["tag", "v2.0.0"], cd: dir)
      System.cmd("git", ["tag", "v1.0.0"], cd: dir)
      System.cmd("git", ["tag", "v1.1.0"], cd: dir)
      System.cmd("git", ["tag", "v0.1.0"], cd: dir)

      assert {:ok, tags} = Git.Tags.sorted(config: cfg)
      names = Enum.map(tags, & &1.name)
      assert names == ["v0.1.0", "v1.0.0", "v1.1.0", "v2.0.0"]
    end

    test "non-semver tags are placed after versioned tags" do
      {dir, cfg} = setup_repo("tags_sorted_mixed")
      write_and_commit(dir, "file.txt", "content\n", "add file")

      System.cmd("git", ["tag", "v1.0.0"], cd: dir)
      System.cmd("git", ["tag", "beta"], cd: dir)
      System.cmd("git", ["tag", "v0.1.0"], cd: dir)

      assert {:ok, tags} = Git.Tags.sorted(config: cfg)
      names = Enum.map(tags, & &1.name)
      assert names == ["v0.1.0", "v1.0.0", "beta"]
    end
  end

  # ---------------------------------------------------------------------------
  # delete/2
  # ---------------------------------------------------------------------------

  describe "delete/2" do
    test "deletes an existing tag" do
      {dir, cfg} = setup_repo("tags_delete")
      write_and_commit(dir, "file.txt", "content\n", "add file")
      System.cmd("git", ["tag", "v1.0.0"], cd: dir)

      assert {:ok, :done} = Git.Tags.delete("v1.0.0", config: cfg)

      {output, 0} = System.cmd("git", ["tag", "-l"], cd: dir)
      refute String.contains?(output, "v1.0.0")
    end
  end

  # ---------------------------------------------------------------------------
  # exists?/2
  # ---------------------------------------------------------------------------

  describe "exists?/2" do
    test "returns true when tag exists" do
      {dir, cfg} = setup_repo("tags_exists_true")
      write_and_commit(dir, "file.txt", "content\n", "add file")
      System.cmd("git", ["tag", "v1.0.0"], cd: dir)

      assert {:ok, true} = Git.Tags.exists?("v1.0.0", config: cfg)
    end

    test "returns false when tag does not exist" do
      {_dir, cfg} = setup_repo("tags_exists_false")

      assert {:ok, false} = Git.Tags.exists?("v1.0.0", config: cfg)
    end
  end
end
