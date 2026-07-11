defmodule Git.NotesTest do
  use ExUnit.Case, async: true

  alias Git.Commands.Notes
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
        "git_notes_test_#{:erlang.unique_integer([:positive])}"
      )

    File.mkdir_p!(tmp_dir)
    cfg = Config.new(working_dir: tmp_dir, env: @env)
    {:ok, :done} = Git.init(config: cfg)
    {:ok, :done} = Git.git_config(set_key: "user.name", set_value: "Test User", config: cfg)
    {:ok, :done} = Git.git_config(set_key: "user.email", set_value: "test@test.com", config: cfg)
    {:ok, _} = Git.commit("initial", allow_empty: true, config: cfg)
    on_exit(fn -> Git.TestHelpers.rm_rf(tmp_dir) end)
    {tmp_dir, cfg}
  end

  describe "args/1" do
    test "builds args for list (default)" do
      assert Notes.args(%Notes{}) == ["notes", "list"]
    end

    test "builds args for show" do
      assert Notes.args(%Notes{show: "HEAD"}) == ["notes", "show", "HEAD"]
    end

    test "builds args for add with message" do
      assert Notes.args(%Notes{add: true, message: "my note", ref: "HEAD"}) ==
               ["notes", "add", "-m", "my note", "HEAD"]
    end

    test "builds args for add with force" do
      assert Notes.args(%Notes{add: true, message: "note", ref: "HEAD", force: true}) ==
               ["notes", "add", "-f", "-m", "note", "HEAD"]
    end

    test "builds args for append" do
      assert Notes.args(%Notes{append: true, message: "more", ref: "HEAD"}) ==
               ["notes", "append", "-m", "more", "HEAD"]
    end

    test "builds args for remove" do
      assert Notes.args(%Notes{remove: "HEAD"}) == ["notes", "remove", "HEAD"]
    end

    test "builds args for prune" do
      assert Notes.args(%Notes{prune: true}) == ["notes", "prune"]
    end

    test "builds args for copy" do
      assert Notes.args(%Notes{copy: {"HEAD~1", "HEAD"}}) == ["notes", "copy", "HEAD~1", "HEAD"]
    end

    test "builds args for copy with force" do
      assert Notes.args(%Notes{copy: {"a", "b"}, force: true}) ==
               ["notes", "copy", "-f", "a", "b"]
    end

    test "builds args for merge with strategy" do
      assert Notes.args(%Notes{merge: "refs/notes/other", strategy: "union"}) ==
               ["notes", "merge", "-s", "union", "refs/notes/other"]
    end

    test "builds args for copy honoring notes_ref" do
      assert Notes.args(%Notes{copy: {"a", "b"}, notes_ref: "agents/metadata"}) ==
               ["notes", "--ref=agents/metadata", "copy", "a", "b"]
    end

    test "builds args with notes_ref" do
      assert Notes.args(%Notes{notes_ref: "custom"}) == ["notes", "--ref=custom", "list"]
    end
  end

  describe "notes copy and merge (integration)" do
    test "copies a note from one commit to another" do
      {_tmp_dir, cfg} = setup_repo()
      {:ok, _} = Git.commit("second", allow_empty: true, config: cfg)

      {:ok, first} = Git.rev_parse(ref: "HEAD~1", config: cfg)
      {:ok, second} = Git.rev_parse(ref: "HEAD", config: cfg)

      {:ok, :done} =
        Git.notes(add: true, message: ~s({"phase":"prep"}), ref: first, config: cfg)

      # Squash-like: the note does not exist on the new SHA until copied.
      assert {:error, _} = Git.notes(show: second, config: cfg)

      {:ok, :done} = Git.notes(copy: {first, second}, config: cfg)
      assert {:ok, ~s({"phase":"prep"})} = Git.notes(show: second, config: cfg)
    end

    test "merges a separate notes ref into another" do
      {_tmp_dir, cfg} = setup_repo()

      {:ok, :done} =
        Git.notes(add: true, message: "from-a", ref: "HEAD", notes_ref: "agents/a", config: cfg)

      {:ok, :done} =
        Git.notes(merge: "refs/notes/agents/a", notes_ref: "agents/merged", config: cfg)

      assert {:ok, "from-a"} = Git.notes(show: "HEAD", notes_ref: "agents/merged", config: cfg)
    end
  end

  describe "notes add and show" do
    test "adds a note and shows it" do
      {_tmp_dir, cfg} = setup_repo()

      {:ok, :done} = Git.notes(add: true, message: "review passed", ref: "HEAD", config: cfg)
      {:ok, content} = Git.notes(show: "HEAD", config: cfg)
      assert content == "review passed"
    end
  end

  describe "notes list" do
    test "lists notes after adding one" do
      {_tmp_dir, cfg} = setup_repo()

      {:ok, :done} = Git.notes(add: true, message: "a note", ref: "HEAD", config: cfg)
      {:ok, entries} = Git.notes(config: cfg)
      assert length(entries) == 1
      [entry] = entries
      assert is_binary(entry.note_sha)
      assert is_binary(entry.commit_sha)
    end

    test "returns empty list when no notes exist" do
      {_tmp_dir, cfg} = setup_repo()

      {:ok, entries} = Git.notes(config: cfg)
      assert entries == []
    end
  end

  describe "notes remove" do
    test "removes a note" do
      {_tmp_dir, cfg} = setup_repo()

      {:ok, :done} = Git.notes(add: true, message: "temp note", ref: "HEAD", config: cfg)
      {:ok, entries_before} = Git.notes(config: cfg)
      assert length(entries_before) == 1

      {:ok, :done} = Git.notes(remove: "HEAD", config: cfg)
      {:ok, entries_after} = Git.notes(config: cfg)
      assert entries_after == []
    end
  end

  describe "notes append" do
    test "appends to an existing note" do
      {_tmp_dir, cfg} = setup_repo()

      {:ok, :done} = Git.notes(add: true, message: "first line", ref: "HEAD", config: cfg)
      {:ok, :done} = Git.notes(append: true, message: "second line", ref: "HEAD", config: cfg)
      {:ok, content} = Git.notes(show: "HEAD", config: cfg)
      assert content =~ "first line"
      assert content =~ "second line"
    end
  end
end
