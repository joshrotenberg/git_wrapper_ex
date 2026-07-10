defmodule Git.Commands.CheckRefFormatTest do
  use ExUnit.Case, async: true

  alias Git.Commands.CheckRefFormat
  alias Git.Config

  describe "args/1" do
    test "plain ref" do
      assert CheckRefFormat.args(%CheckRefFormat{ref: "refs/heads/main"}) ==
               ["check-ref-format", "refs/heads/main"]
    end

    test "normalize" do
      assert CheckRefFormat.args(%CheckRefFormat{ref: "refs/heads//main", normalize: true}) ==
               ["check-ref-format", "--normalize", "refs/heads//main"]
    end

    test "branch" do
      assert CheckRefFormat.args(%CheckRefFormat{ref: "main", branch: true}) ==
               ["check-ref-format", "--branch", "main"]
    end

    test "allow_onelevel" do
      assert CheckRefFormat.args(%CheckRefFormat{ref: "HEAD", allow_onelevel: true}) ==
               ["check-ref-format", "--allow-onelevel", "HEAD"]
    end
  end

  describe "parse_output/2" do
    test "valid ref with no output" do
      assert CheckRefFormat.parse_output("", 0) == {:ok, true}
    end

    test "normalized ref returns the printed value" do
      assert CheckRefFormat.parse_output("refs/heads/main\n", 0) == {:ok, "refs/heads/main"}
    end

    test "exit 1 is an invalid ref" do
      assert CheckRefFormat.parse_output("", 1) == {:error, :invalid_ref}
    end

    test "invalid branch-name die (exit 128) is an invalid ref" do
      out = "fatal: 'bad..name' is not a valid branch name"
      assert CheckRefFormat.parse_output(out, 128) == {:error, :invalid_ref}
    end

    test "usage error is a real error, not an invalid-ref signal" do
      out = "usage: git check-ref-format [--normalize] [<options>] <refname>"
      assert CheckRefFormat.parse_output(out, 129) == {:error, {out, 129}}
    end
  end

  describe "Git.check_ref_format/1 integration" do
    setup do
      tmp =
        Path.join(
          System.tmp_dir!(),
          "git_check_ref_format_test_#{:erlang.unique_integer([:positive])}"
        )

      File.mkdir_p!(tmp)
      System.cmd("git", ["init", "--initial-branch=main"], cd: tmp)
      cfg = Config.new(working_dir: tmp)
      on_exit(fn -> Git.TestHelpers.rm_rf(tmp) end)
      %{config: cfg}
    end

    test "valid full ref", %{config: config} do
      assert Git.check_ref_format(ref: "refs/heads/main", config: config) == {:ok, true}
    end

    test "invalid ref", %{config: config} do
      assert Git.check_ref_format(ref: "bad name", config: config) == {:error, :invalid_ref}
    end

    test "single-level ref requires allow_onelevel", %{config: config} do
      assert Git.check_ref_format(ref: "foo", config: config) == {:error, :invalid_ref}

      assert Git.check_ref_format(ref: "foo", allow_onelevel: true, config: config) ==
               {:ok, true}
    end

    test "normalize returns the normalized ref", %{config: config} do
      assert Git.check_ref_format(ref: "refs/heads//main", normalize: true, config: config) ==
               {:ok, "refs/heads/main"}
    end

    test "branch shorthand", %{config: config} do
      assert Git.check_ref_format(ref: "main", branch: true, config: config) == {:ok, "main"}
    end

    test "invalid branch name", %{config: config} do
      assert Git.check_ref_format(ref: "bad..name", branch: true, config: config) ==
               {:error, :invalid_ref}
    end
  end
end
