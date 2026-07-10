defmodule Git.CheckAttrTest do
  use ExUnit.Case, async: true

  alias Git.Commands.CheckAttr
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
        "git_check_attr_test_#{:erlang.unique_integer([:positive])}"
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
    test "builds args with a single attr and path" do
      assert CheckAttr.args(%CheckAttr{attrs: ["diff"], paths: ["foo.ex"]}) ==
               ["check-attr", "-z", "diff", "--", "foo.ex"]
    end

    test "builds args with multiple attrs and paths" do
      assert CheckAttr.args(%CheckAttr{attrs: ["diff", "text"], paths: ["foo.ex", "bar.png"]}) ==
               ["check-attr", "-z", "diff", "text", "--", "foo.ex", "bar.png"]
    end

    test "builds args with the all flag" do
      assert CheckAttr.args(%CheckAttr{all: true, paths: ["foo.ex"]}) ==
               ["check-attr", "-z", "-a", "--", "foo.ex"]
    end

    test "all takes precedence over attrs" do
      assert CheckAttr.args(%CheckAttr{all: true, attrs: ["diff"], paths: ["foo.ex"]}) ==
               ["check-attr", "-z", "-a", "--", "foo.ex"]
    end

    test "builds args with the cached flag" do
      assert CheckAttr.args(%CheckAttr{attrs: ["diff"], paths: ["foo.ex"], cached: true}) ==
               ["check-attr", "-z", "--cached", "diff", "--", "foo.ex"]
    end

    test "omits the separator when there are no paths" do
      assert CheckAttr.args(%CheckAttr{attrs: ["diff"], paths: []}) ==
               ["check-attr", "-z", "diff"]
    end
  end

  describe "parse_output/2" do
    test "parses NUL-delimited triples into maps" do
      stdout = "foo.ex\0diff\0elixir\0bar.png\0text\0unset\0"

      assert {:ok, records} = CheckAttr.parse_output(stdout, 0)

      assert records == [
               %{path: "foo.ex", attr: "diff", value: "elixir"},
               %{path: "bar.png", attr: "text", value: "unset"}
             ]
    end

    test "returns an empty list for empty output" do
      assert {:ok, []} = CheckAttr.parse_output("", 0)
    end

    test "returns an error for a non-zero exit code" do
      assert {:error, {"boom", 129}} = CheckAttr.parse_output("boom", 129)
    end
  end

  describe "check-attr against real git" do
    setup do
      {tmp_dir, cfg} = setup_repo()

      File.write!(
        Path.join(tmp_dir, ".gitattributes"),
        "*.ex diff=elixir\n*.png -text\n*.txt text\n"
      )

      for name <- ["foo.ex", "bar.png", "baz.txt", "other.rb"] do
        File.write!(Path.join(tmp_dir, name), "")
      end

      {:ok, tmp_dir: tmp_dir, cfg: cfg}
    end

    test "reports a set value attribute", %{cfg: cfg} do
      {:ok, records} = Git.check_attr(attrs: ["diff"], paths: ["foo.ex"], config: cfg)
      assert records == [%{path: "foo.ex", attr: "diff", value: "elixir"}]
    end

    test "reports set, unset, and unspecified across attrs and paths", %{cfg: cfg} do
      {:ok, records} =
        Git.check_attr(
          attrs: ["diff", "text"],
          paths: ["foo.ex", "bar.png", "baz.txt"],
          config: cfg
        )

      assert %{path: "foo.ex", attr: "diff", value: "elixir"} in records
      assert %{path: "foo.ex", attr: "text", value: "unspecified"} in records
      assert %{path: "bar.png", attr: "text", value: "unset"} in records
      assert %{path: "baz.txt", attr: "text", value: "set"} in records
    end

    test "all reports every set attribute for a path", %{cfg: cfg} do
      {:ok, records} = Git.check_attr(all: true, paths: ["foo.ex"], config: cfg)
      assert records == [%{path: "foo.ex", attr: "diff", value: "elixir"}]
    end

    test "all returns an empty list for a path with no attributes", %{cfg: cfg} do
      {:ok, records} = Git.check_attr(all: true, paths: ["other.rb"], config: cfg)
      assert records == []
    end

    test "handles paths containing spaces", %{tmp_dir: tmp_dir, cfg: cfg} do
      File.write!(Path.join(tmp_dir, "a file.ex"), "")

      {:ok, records} = Git.check_attr(attrs: ["diff"], paths: ["a file.ex"], config: cfg)
      assert records == [%{path: "a file.ex", attr: "diff", value: "elixir"}]
    end

    test "cached reads attributes from the index", %{cfg: cfg} do
      # Before staging the working-tree .gitattributes, --cached sees nothing.
      {:ok, before} =
        Git.check_attr(attrs: ["diff"], paths: ["foo.ex"], cached: true, config: cfg)

      assert before == [%{path: "foo.ex", attr: "diff", value: "unspecified"}]

      {:ok, _} = Git.add(files: [".gitattributes"], config: cfg)

      {:ok, after_add} =
        Git.check_attr(attrs: ["diff"], paths: ["foo.ex"], cached: true, config: cfg)

      assert after_add == [%{path: "foo.ex", attr: "diff", value: "elixir"}]
    end

    test "returns an error when no attribute is specified", %{cfg: cfg} do
      assert {:error, {output, code}} = Git.check_attr(paths: ["foo.ex"], config: cfg)
      assert code != 0
      assert output =~ "No attribute specified"
    end
  end
end
