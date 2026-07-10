defmodule Git.Commands.VersionTest do
  use ExUnit.Case, async: true

  alias Git.Commands.Version
  alias Git.Config

  describe "args/1" do
    test "builds the argument list" do
      assert Version.args(%Version{}) == ["--version"]
    end
  end

  describe "parse_output/2" do
    test "parses a standard version line" do
      {:ok, version} = Version.parse_output("git version 2.50.1 (Apple Git-155)\n", 0)

      assert version == %Git.Version{
               major: 2,
               minor: 50,
               patch: 1,
               raw: "git version 2.50.1 (Apple Git-155)"
             }
    end

    test "parses a plain version line" do
      {:ok, version} = Version.parse_output("git version 2.39.5\n", 0)
      assert version == %Git.Version{major: 2, minor: 39, patch: 5, raw: "git version 2.39.5"}
    end

    test "parses a four-component version" do
      {:ok, version} = Version.parse_output("git version 2.42.0.windows.2\n", 0)
      assert %Git.Version{major: 2, minor: 42, patch: 0} = version
    end

    test "non-zero exit returns error" do
      assert Version.parse_output("boom", 1) == {:error, {"boom", 1}}
    end
  end

  describe "Git.version/1 integration" do
    setup do
      tmp =
        Path.join(System.tmp_dir!(), "git_version_test_#{:erlang.unique_integer([:positive])}")

      File.mkdir_p!(tmp)
      cfg = Config.new(working_dir: tmp)
      {:ok, :done} = Git.init(config: cfg)
      on_exit(fn -> Git.TestHelpers.rm_rf(tmp) end)
      %{config: cfg}
    end

    test "reports the installed git version", %{config: config} do
      {:ok, version} = Git.version(config: config)
      assert %Git.Version{} = version
      assert is_integer(version.major) and version.major >= 1
      assert is_integer(version.minor)
      assert is_integer(version.patch)
      assert String.starts_with?(version.raw, "git version ")
    end
  end
end
