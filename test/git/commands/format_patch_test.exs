defmodule Git.Commands.FormatPatchTest do
  use ExUnit.Case, async: true

  alias Git.Commands.FormatPatch
  alias Git.Config

  defp setup_repo do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "git_format_patch_test_#{:erlang.unique_integer([:positive])}"
      )

    File.mkdir_p!(tmp_dir)
    cfg = Config.new(working_dir: tmp_dir)
    {:ok, :done} = Git.init(config: cfg)
    {:ok, :done} = Git.git_config(set_key: "user.name", set_value: "Test User", config: cfg)
    {:ok, :done} = Git.git_config(set_key: "user.email", set_value: "test@test.com", config: cfg)
    {:ok, _} = Git.commit("initial", allow_empty: true, config: cfg)

    file_path = Path.join(tmp_dir, "hello.txt")
    File.write!(file_path, "hello world\n")
    System.cmd("git", ["add", "hello.txt"], cd: tmp_dir)
    {:ok, _} = Git.commit("add hello", config: cfg)

    {tmp_dir, cfg}
  end

  setup do
    {tmp_dir, config} = setup_repo()
    on_exit(fn -> File.rm_rf!(tmp_dir) end)
    %{tmp_dir: tmp_dir, config: config}
  end

  describe "args/1" do
    test "default args" do
      assert FormatPatch.args(%FormatPatch{ref: "HEAD~3"}) ==
               ["format-patch", "HEAD~3"]
    end

    test "with stdout" do
      assert FormatPatch.args(%FormatPatch{ref: "HEAD~1", stdout: true}) ==
               ["format-patch", "--stdout", "HEAD~1"]
    end

    test "with output_directory and numbered" do
      assert FormatPatch.args(%FormatPatch{
               ref: "v1.0..v2.0",
               output_directory: "/tmp/patches",
               numbered: true
             }) ==
               ["format-patch", "-n", "-o", "/tmp/patches", "v1.0..v2.0"]
    end

    test "with cover_letter and subject_prefix" do
      assert FormatPatch.args(%FormatPatch{
               ref: "HEAD~2",
               cover_letter: true,
               subject_prefix: "RFC"
             }) ==
               ["format-patch", "--cover-letter", "--subject-prefix=RFC", "HEAD~2"]
    end

    test "with no_stat and no_signature" do
      assert FormatPatch.args(%FormatPatch{ref: "HEAD~1", no_stat: true, no_signature: true}) ==
               ["format-patch", "--no-stat", "--no-signature", "HEAD~1"]
    end

    test "with start_number and signature" do
      assert FormatPatch.args(%FormatPatch{
               ref: "HEAD~1",
               start_number: 5,
               signature: "My Project"
             }) ==
               ["format-patch", "--start-number=5", "--signature=My Project", "HEAD~1"]
    end

    test "with quiet and zero_commit" do
      assert FormatPatch.args(%FormatPatch{ref: "HEAD~1", quiet: true, zero_commit: true}) ==
               ["format-patch", "-q", "--zero-commit", "HEAD~1"]
    end

    test "with from and base" do
      assert FormatPatch.args(%FormatPatch{ref: "HEAD~1", from: "Author", base: "main"}) ==
               ["format-patch", "--from=Author", "--base=main", "HEAD~1"]
    end
  end

  describe "generate patches to directory" do
    test "creates patch files in output directory", %{tmp_dir: tmp_dir, config: config} do
      patch_dir = Path.join(tmp_dir, "patches")
      File.mkdir_p!(patch_dir)

      {:ok, files} =
        Git.format_patch(ref: "HEAD~1", output_directory: patch_dir, config: config)

      assert is_list(files)
      assert length(files) == 1

      patch_file = hd(files)
      assert String.ends_with?(patch_file, ".patch")
      assert File.exists?(patch_file)
    end
  end

  describe "stdout mode" do
    test "returns patch content as string", %{config: config} do
      {:ok, content} = Git.format_patch(ref: "HEAD~1", stdout: true, config: config)

      assert is_binary(content)
      assert String.contains?(content, "add hello")
      assert String.contains?(content, "hello world")
    end
  end
end
