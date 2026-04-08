defmodule Git.Commands.HashObjectTest do
  use ExUnit.Case, async: true

  alias Git.Commands.HashObject
  alias Git.Config

  defp setup_repo do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "git_hash_object_test_#{:erlang.unique_integer([:positive])}"
      )

    File.mkdir_p!(tmp_dir)
    cfg = Config.new(working_dir: tmp_dir)
    {:ok, :done} = Git.init(config: cfg)
    {:ok, :done} = Git.git_config(set_key: "user.name", set_value: "Test User", config: cfg)
    {:ok, :done} = Git.git_config(set_key: "user.email", set_value: "test@test.com", config: cfg)
    {tmp_dir, cfg}
  end

  setup do
    {tmp_dir, config} = setup_repo()
    on_exit(fn -> File.rm_rf!(tmp_dir) end)
    %{tmp_dir: tmp_dir, config: config}
  end

  describe "args/1" do
    test "with file only" do
      assert HashObject.args(%HashObject{file: "README.md"}) ==
               ["hash-object", "README.md"]
    end

    test "with write flag" do
      assert HashObject.args(%HashObject{file: "README.md", write: true}) ==
               ["hash-object", "-w", "README.md"]
    end

    test "with type" do
      assert HashObject.args(%HashObject{file: "README.md", type: "commit"}) ==
               ["hash-object", "-t", "commit", "README.md"]
    end

    test "with literally" do
      assert HashObject.args(%HashObject{file: "README.md", literally: true}) ==
               ["hash-object", "--literally", "README.md"]
    end

    test "with write and type" do
      assert HashObject.args(%HashObject{file: "README.md", write: true, type: "blob"}) ==
               ["hash-object", "-w", "-t", "blob", "README.md"]
    end
  end

  describe "hash_object integration" do
    test "hashes a file", %{tmp_dir: tmp_dir, config: config} do
      file_path = Path.join(tmp_dir, "hello.txt")
      File.write!(file_path, "hello world\n")

      {:ok, hash} = Git.hash_object(file: file_path, config: config)
      assert Regex.match?(~r/^[0-9a-f]{40,64}$/, hash)
    end

    test "hashes a file with write", %{tmp_dir: tmp_dir, config: config} do
      file_path = Path.join(tmp_dir, "hello.txt")
      File.write!(file_path, "hello world\n")

      {:ok, hash} = Git.hash_object(file: file_path, write: true, config: config)
      assert Regex.match?(~r/^[0-9a-f]{40,64}$/, hash)

      # Verify the object was written by reading it back
      {output, 0} = System.cmd("git", ["cat-file", "-t", hash], cd: tmp_dir)
      assert String.trim(output) == "blob"
    end

    test "same content produces same hash", %{tmp_dir: tmp_dir, config: config} do
      file1 = Path.join(tmp_dir, "file1.txt")
      file2 = Path.join(tmp_dir, "file2.txt")
      File.write!(file1, "identical content\n")
      File.write!(file2, "identical content\n")

      {:ok, hash1} = Git.hash_object(file: file1, config: config)
      {:ok, hash2} = Git.hash_object(file: file2, config: config)
      assert hash1 == hash2
    end
  end
end
