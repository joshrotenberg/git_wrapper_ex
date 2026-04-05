defmodule Git.Commands.DescribeTest do
  use ExUnit.Case, async: true

  alias Git.Commands.Describe
  alias Git.Config

  defp setup_repo do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "git_describe_test_#{:erlang.unique_integer([:positive])}"
      )

    File.mkdir_p!(tmp_dir)
    cfg = Config.new(working_dir: tmp_dir)
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

  describe "args/1" do
    test "default args" do
      assert Describe.args(%Describe{}) == ["describe"]
    end

    test "with tags and always" do
      assert Describe.args(%Describe{tags: true, always: true}) ==
               ["describe", "--tags", "--always"]
    end

    test "with abbrev and long" do
      assert Describe.args(%Describe{abbrev: 4, long: true}) ==
               ["describe", "--long", "--abbrev=4"]
    end

    test "with dirty boolean" do
      assert Describe.args(%Describe{dirty: true}) == ["describe", "--dirty"]
    end

    test "with dirty mark string" do
      assert Describe.args(%Describe{dirty: "-modified"}) ==
               ["describe", "--dirty=-modified"]
    end

    test "with exact_match and ref" do
      assert Describe.args(%Describe{exact_match: true, ref: "v1.0"}) ==
               ["describe", "--exact-match", "v1.0"]
    end

    test "with match and exclude patterns" do
      assert Describe.args(%Describe{match: "v*", exclude: "v0.*"}) ==
               ["describe", "--match=v*", "--exclude=v0.*"]
    end

    test "with first_parent and candidates" do
      assert Describe.args(%Describe{first_parent: true, candidates: 5}) ==
               ["describe", "--first-parent", "--candidates=5"]
    end

    test "with broken" do
      assert Describe.args(%Describe{broken: true}) == ["describe", "--broken"]
    end
  end

  describe "describe with tags" do
    test "describes a tagged commit", %{tmp_dir: tmp_dir, config: config} do
      System.cmd("git", ["tag", "v1.0"], cd: tmp_dir)

      assert {:ok, "v1.0"} = Git.describe(tags: true, config: config)
    end

    test "describes a commit after a tag", %{tmp_dir: tmp_dir, config: config} do
      System.cmd("git", ["tag", "v1.0"], cd: tmp_dir)
      {:ok, _} = Git.commit("second", allow_empty: true, config: config)

      {:ok, description} = Git.describe(tags: true, config: config)
      assert String.starts_with?(description, "v1.0-1-g")
    end
  end

  describe "describe with --always" do
    test "returns abbreviated hash when no tags exist", %{config: config} do
      {:ok, description} = Git.describe(always: true, config: config)
      assert String.length(description) > 0
      assert Regex.match?(~r/^[0-9a-f]+$/, description)
    end
  end

  describe "exact-match failure" do
    test "returns error when no tag matches exactly", %{config: config} do
      assert {:error, {_output, 128}} = Git.describe(exact_match: true, config: config)
    end
  end
end
