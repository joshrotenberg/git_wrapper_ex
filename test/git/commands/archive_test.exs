defmodule Git.ArchiveTest do
  use ExUnit.Case, async: true

  alias Git.Commands.Archive

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
        "git_archive_test_#{:erlang.unique_integer([:positive])}"
      )

    File.mkdir_p!(tmp_dir)
    cfg = Git.Config.new(working_dir: tmp_dir, env: @env)
    {:ok, :done} = Git.init(config: cfg)
    {:ok, :done} = Git.git_config(set_key: "user.name", set_value: "Test User", config: cfg)
    {:ok, :done} = Git.git_config(set_key: "user.email", set_value: "test@test.com", config: cfg)

    # Create some files
    File.write!(Path.join(tmp_dir, "hello.txt"), "hello world\n")
    File.mkdir_p!(Path.join(tmp_dir, "lib"))
    File.write!(Path.join(tmp_dir, "lib/app.ex"), "defmodule App do\nend\n")
    {:ok, :done} = Git.add(all: true, config: cfg)
    {:ok, _} = Git.commit("initial commit", config: cfg)

    {tmp_dir, cfg}
  end

  setup do
    {tmp_dir, config} = setup_repo()
    on_exit(fn -> File.rm_rf!(tmp_dir) end)
    %{tmp_dir: tmp_dir, config: config}
  end

  describe "args/1" do
    test "builds default args" do
      assert Archive.args(%Archive{}) == ["archive", "HEAD"]
    end

    test "builds args with format and output" do
      assert Archive.args(%Archive{format: "zip", output: "out.zip"}) ==
               ["archive", "--format=zip", "--output=out.zip", "HEAD"]
    end

    test "builds args with prefix and paths" do
      assert Archive.args(%Archive{prefix: "project/", paths: ["lib/"]}) ==
               ["archive", "--prefix=project/", "HEAD", "--", "lib/"]
    end

    test "builds args with verbose and worktree_attributes" do
      assert Archive.args(%Archive{verbose: true, worktree_attributes: true}) ==
               ["archive", "-v", "--worktree-attributes", "HEAD"]
    end

    test "builds args with remote" do
      assert Archive.args(%Archive{remote: "origin"}) ==
               ["archive", "--remote=origin", "HEAD"]
    end

    test "builds args with custom ref" do
      assert Archive.args(%Archive{ref: "v1.0"}) ==
               ["archive", "v1.0"]
    end
  end

  describe "git archive" do
    test "creates a tar archive", %{tmp_dir: tmp_dir, config: config} do
      output_path = Path.join(tmp_dir, "archive.tar")

      {:ok, :done} =
        Git.Command.run(Archive, %Archive{output: output_path, format: "tar"}, config)

      assert File.exists?(output_path)
      assert File.stat!(output_path).size > 0
    end

    test "creates a zip archive", %{tmp_dir: tmp_dir, config: config} do
      output_path = Path.join(tmp_dir, "archive.zip")

      {:ok, :done} =
        Git.Command.run(Archive, %Archive{output: output_path, format: "zip"}, config)

      assert File.exists?(output_path)
      assert File.stat!(output_path).size > 0
    end

    test "creates archive with prefix", %{tmp_dir: tmp_dir, config: config} do
      output_path = Path.join(tmp_dir, "prefixed.tar")

      {:ok, :done} =
        Git.Command.run(
          Archive,
          %Archive{output: output_path, format: "tar", prefix: "myproject/"},
          config
        )

      assert File.exists?(output_path)

      # Verify the prefix is present by listing tar contents
      {tar_output, 0} = System.cmd("tar", ["tf", output_path])
      assert String.contains?(tar_output, "myproject/")
    end

    test "creates archive with path filter", %{tmp_dir: tmp_dir, config: config} do
      output_path = Path.join(tmp_dir, "lib_only.tar")

      {:ok, :done} =
        Git.Command.run(
          Archive,
          %Archive{output: output_path, format: "tar", paths: ["lib/"]},
          config
        )

      assert File.exists?(output_path)

      {tar_output, 0} = System.cmd("tar", ["tf", output_path])
      assert String.contains?(tar_output, "lib/app.ex")
      refute String.contains?(tar_output, "hello.txt")
    end
  end
end
