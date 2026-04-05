defmodule Git.ShowRefTest do
  use ExUnit.Case, async: true

  alias Git.Commands.ShowRef
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
        "git_show_ref_test_#{:erlang.unique_integer([:positive])}"
      )

    File.mkdir_p!(tmp_dir)
    cfg = Config.new(working_dir: tmp_dir, env: @env)
    {:ok, :done} = Git.init(config: cfg)
    {:ok, :done} = Git.git_config(set_key: "user.name", set_value: "Test User", config: cfg)
    {:ok, :done} = Git.git_config(set_key: "user.email", set_value: "test@test.com", config: cfg)
    {:ok, _} = Git.commit("initial", allow_empty: true, config: cfg)
    {tmp_dir, cfg}
  end

  setup do
    {tmp_dir, config} = setup_repo()
    on_exit(fn -> File.rm_rf!(tmp_dir) end)
    %{tmp_dir: tmp_dir, config: config}
  end

  describe "Git.Commands.ShowRef args/1" do
    test "builds default args" do
      assert ShowRef.args(%ShowRef{}) == ["show-ref"]
    end

    test "builds args with heads" do
      assert ShowRef.args(%ShowRef{heads: true}) == ["show-ref", "--heads"]
    end

    test "builds args with tags" do
      assert ShowRef.args(%ShowRef{tags: true}) == ["show-ref", "--tags"]
    end

    test "builds args with verify and patterns" do
      assert ShowRef.args(%ShowRef{verify: true, patterns: ["refs/heads/main"]}) ==
               ["show-ref", "--verify", "refs/heads/main"]
    end

    test "builds args with hash boolean" do
      assert ShowRef.args(%ShowRef{hash: true}) == ["show-ref", "--hash"]
    end

    test "builds args with hash integer" do
      assert ShowRef.args(%ShowRef{hash: 8}) == ["show-ref", "--hash=8"]
    end

    test "builds args with abbrev" do
      assert ShowRef.args(%ShowRef{abbrev: 8}) == ["show-ref", "--abbrev=8"]
    end

    test "builds args with dereference" do
      assert ShowRef.args(%ShowRef{dereference: true}) == ["show-ref", "-d"]
    end

    test "builds args with quiet and verify" do
      assert ShowRef.args(%ShowRef{quiet: true, verify: true, patterns: ["refs/heads/main"]}) ==
               ["show-ref", "--verify", "-q", "refs/heads/main"]
    end
  end

  describe "git show-ref" do
    test "lists all refs", %{config: config} do
      {:ok, refs} = Git.show_ref(config: config)
      assert [ref | _] = refs
      assert is_binary(ref.sha)
      assert is_binary(ref.ref)
    end

    test "lists only heads", %{config: config} do
      {:ok, refs} = Git.show_ref(heads: true, config: config)
      assert is_list(refs)

      Enum.each(refs, fn ref ->
        assert String.starts_with?(ref.ref, "refs/heads/")
      end)
    end

    test "lists only tags", %{config: config} do
      {:ok, refs} = Git.show_ref(tags: true, config: config)
      # No tags in a fresh repo
      assert refs == []
    end

    test "verifies an existing ref", %{config: config} do
      {:ok, refs} =
        Git.show_ref(verify: true, patterns: ["refs/heads/main"], config: config)

      assert is_list(refs)
      assert length(refs) == 1
      assert List.first(refs).ref == "refs/heads/main"
    end

    test "verifies a nonexistent ref returns empty", %{config: config} do
      {:ok, result} =
        Git.show_ref(verify: true, patterns: ["refs/heads/nonexistent"], config: config)

      assert result == []
    end

    test "quiet verify returns true for existing ref", %{config: config} do
      {:ok, result} =
        Git.show_ref(
          verify: true,
          quiet: true,
          patterns: ["refs/heads/main"],
          config: config
        )

      assert result == true
    end

    test "quiet verify returns false for nonexistent ref", %{config: config} do
      {:ok, result} =
        Git.show_ref(
          verify: true,
          quiet: true,
          patterns: ["refs/heads/nonexistent"],
          config: config
        )

      assert result == false
    end

    test "hash mode returns list of shas", %{config: config} do
      {:ok, shas} = Git.show_ref(hash: true, config: config)
      assert [_ | _] = shas
      assert Enum.all?(shas, &is_binary/1)
    end
  end

  describe "parse_output/2" do
    test "parses sha ref lines in default mode" do
      Process.put(:__git_show_ref_mode__, :default)
      output = "abc123 refs/heads/main\ndef456 refs/tags/v1.0\n"
      {:ok, entries} = ShowRef.parse_output(output, 0)
      assert length(entries) == 2
      assert Enum.at(entries, 0) == %{sha: "abc123", ref: "refs/heads/main"}
      assert Enum.at(entries, 1) == %{sha: "def456", ref: "refs/tags/v1.0"}
    end

    test "parses hash-only output" do
      Process.put(:__git_show_ref_mode__, :hash)
      output = "abc123\ndef456\n"
      {:ok, shas} = ShowRef.parse_output(output, 0)
      assert shas == ["abc123", "def456"]
    end

    test "quiet verify returns true on exit 0" do
      Process.put(:__git_show_ref_mode__, :quiet_verify)
      assert ShowRef.parse_output("", 0) == {:ok, true}
    end

    test "quiet verify returns false on exit 1" do
      Process.put(:__git_show_ref_mode__, :quiet_verify)
      assert ShowRef.parse_output("", 1) == {:ok, false}
    end

    test "default mode returns empty list on exit 1" do
      Process.put(:__git_show_ref_mode__, :default)
      assert ShowRef.parse_output("", 1) == {:ok, []}
    end
  end
end
