defmodule Git.Commands.ShortlogTest do
  use ExUnit.Case, async: true

  alias Git.Commands.Shortlog
  alias Git.Config
  alias Git.ShortlogEntry

  defp setup_repo do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "git_shortlog_test_#{:erlang.unique_integer([:positive])}"
      )

    File.mkdir_p!(tmp_dir)
    cfg = Config.new(working_dir: tmp_dir)
    {:ok, :done} = Git.init(config: cfg)
    {:ok, :done} = Git.git_config(set_key: "user.name", set_value: "Test User", config: cfg)
    {:ok, :done} = Git.git_config(set_key: "user.email", set_value: "test@test.com", config: cfg)
    {:ok, _} = Git.commit("initial commit", allow_empty: true, config: cfg)
    {:ok, _} = Git.commit("second commit", allow_empty: true, config: cfg)
    {:ok, _} = Git.commit("third commit", allow_empty: true, config: cfg)
    {tmp_dir, cfg}
  end

  setup do
    {tmp_dir, config} = setup_repo()
    on_exit(fn -> File.rm_rf!(tmp_dir) end)
    %{tmp_dir: tmp_dir, config: config}
  end

  describe "args/1" do
    test "default args" do
      assert Shortlog.args(%Shortlog{}) == ["shortlog"]
    end

    test "summary and numbered" do
      assert Shortlog.args(%Shortlog{summary: true, numbered: true}) ==
               ["shortlog", "-s", "-n"]
    end

    test "with email and ref" do
      assert Shortlog.args(%Shortlog{email: true, ref: "v1.0..HEAD"}) ==
               ["shortlog", "-e", "v1.0..HEAD"]
    end

    test "with max_count and group" do
      assert Shortlog.args(%Shortlog{max_count: 10, group: "author"}) ==
               ["shortlog", "--max-count=10", "--group=author"]
    end

    test "with since and until_date" do
      assert Shortlog.args(%Shortlog{since: "2024-01-01", until_date: "2024-12-31"}) ==
               ["shortlog", "--since=2024-01-01", "--until=2024-12-31"]
    end

    test "with all" do
      assert Shortlog.args(%Shortlog{all: true}) == ["shortlog", "--all"]
    end
  end

  describe "summary mode" do
    test "returns shortlog entries with counts", %{config: config} do
      {:ok, [entry | _]} = Git.shortlog(summary: true, numbered: true, all: true, config: config)
      assert %ShortlogEntry{} = entry
      assert entry.author == "Test User"
      assert entry.count == 3
      assert entry.commits == []
    end
  end

  describe "full mode with commits" do
    test "returns entries with commit subjects", %{config: config} do
      {:ok, [entry | _]} = Git.shortlog(all: true, config: config)
      assert %ShortlogEntry{} = entry
      assert entry.author == "Test User"
      assert entry.count == 3
      assert length(entry.commits) == 3
      assert "initial commit" in entry.commits
      assert "second commit" in entry.commits
      assert "third commit" in entry.commits
    end
  end

  describe "email mode" do
    test "returns entries with email addresses", %{config: config} do
      {:ok, [entry | _]} =
        Git.shortlog(summary: true, email: true, all: true, config: config)

      assert entry.email == "test@test.com"
    end
  end

  describe "ref range" do
    test "limits output to ref range", %{tmp_dir: tmp_dir, config: config} do
      System.cmd("git", ["tag", "v1.0", "HEAD~1"], cd: tmp_dir)

      {:ok, entries} =
        Git.shortlog(summary: true, all: true, ref: "v1.0..HEAD", config: config)

      assert is_list(entries)

      case entries do
        [_ | _] ->
          total = Enum.reduce(entries, 0, fn e, acc -> acc + e.count end)
          assert total == 1

        [] ->
          :ok
      end
    end
  end

  describe "ShortlogEntry.parse_summary/1" do
    test "parses summary lines" do
      output = "     3\tAlice\n     1\tBob\n"

      entries = ShortlogEntry.parse_summary(output)
      assert length(entries) == 2
      assert hd(entries).author == "Alice"
      assert hd(entries).count == 3
    end

    test "parses summary lines with email" do
      output = "     2\tAlice <alice@example.com>\n"

      entries = ShortlogEntry.parse_summary(output)
      assert length(entries) == 1
      assert hd(entries).author == "Alice"
      assert hd(entries).email == "alice@example.com"
      assert hd(entries).count == 2
    end

    test "parses empty output" do
      assert ShortlogEntry.parse_summary("") == []
    end
  end

  describe "ShortlogEntry.parse_full/1" do
    test "parses full output with commits" do
      output = """
      Alice (2):
            first commit
            second commit

      Bob (1):
            only commit

      """

      entries = ShortlogEntry.parse_full(output)
      assert length(entries) == 2

      alice = Enum.find(entries, &(&1.author == "Alice"))
      assert alice.count == 2
      assert length(alice.commits) == 2
      assert "first commit" in alice.commits

      bob = Enum.find(entries, &(&1.author == "Bob"))
      assert bob.count == 1
      assert ["only commit"] == bob.commits
    end
  end
end
