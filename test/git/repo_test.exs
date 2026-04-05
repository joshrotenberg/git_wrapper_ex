defmodule Git.RepoTest do
  use ExUnit.Case

  alias Git.Repo

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  # On macOS, /tmp is a symlink to /private/var/..., so git rev-parse
  # --show-toplevel returns the resolved path. This helper gets the
  # canonical path for comparison.
  defp resolve_path(path) do
    {resolved, 0} = System.cmd("realpath", [path])
    String.trim(resolved)
  end

  defp tmp_dir do
    Path.join(System.tmp_dir!(), "git_repo_test_#{:erlang.unique_integer([:positive])}")
  end

  defp init_repo(dir) do
    File.mkdir_p!(dir)
    System.cmd("git", ["init", "--initial-branch=main"], cd: dir)
    System.cmd("git", ["config", "user.name", "Test User"], cd: dir)
    System.cmd("git", ["config", "user.email", "test@test.com"], cd: dir)
    System.cmd("git", ["commit", "--allow-empty", "-m", "initial"], cd: dir)

    dir
  end

  setup do
    dir = tmp_dir()
    init_repo(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    %{tmp_dir: dir}
  end

  # ---------------------------------------------------------------------------
  # open/1 and open!/1
  # ---------------------------------------------------------------------------

  describe "open/1" do
    test "opens a valid git repository", %{tmp_dir: dir} do
      assert {:ok, %Repo{} = repo} = Repo.open(dir)
      # rev-parse resolves symlinks (e.g., /tmp -> /private/var on macOS)
      resolved = resolve_path(dir)
      assert repo.path == resolved
      assert repo.config.working_dir == resolved
    end

    test "returns error for non-existent path" do
      assert {:error, _} =
               Repo.open("/tmp/nonexistent_path_#{:erlang.unique_integer([:positive])}")
    end

    test "returns error for non-repo directory" do
      dir = tmp_dir() <> "_nonrepo"
      File.mkdir_p!(dir)
      on_exit(fn -> File.rm_rf!(dir) end)

      assert {:error, _} = Repo.open(dir)
    end
  end

  describe "open!/1" do
    test "opens a valid repository", %{tmp_dir: dir} do
      repo = Repo.open!(dir)
      assert %Repo{} = repo
      assert repo.path == resolve_path(dir)
    end

    test "raises on invalid path" do
      assert_raise RuntimeError, ~r/failed to open repository/, fn ->
        Repo.open!("/tmp/nonexistent_path_#{:erlang.unique_integer([:positive])}")
      end
    end
  end

  # ---------------------------------------------------------------------------
  # init/1
  # ---------------------------------------------------------------------------

  describe "init/1" do
    test "initializes a new repository" do
      dir = tmp_dir() <> "_init"
      on_exit(fn -> File.rm_rf!(dir) end)

      assert {:ok, %Repo{} = repo} = Repo.init(dir)
      assert repo.path == dir
      assert File.dir?(Path.join(dir, ".git"))
    end

    test "initializes a bare repository" do
      dir = tmp_dir() <> "_bare"
      on_exit(fn -> File.rm_rf!(dir) end)

      assert {:ok, %Repo{} = repo} = Repo.init(dir, bare: true)
      assert repo.path == dir
      # Bare repos have HEAD directly in the directory
      assert File.exists?(Path.join(dir, "HEAD"))
    end
  end

  # ---------------------------------------------------------------------------
  # clone/3
  # ---------------------------------------------------------------------------

  describe "clone/3" do
    test "clones a local repository", %{tmp_dir: dir} do
      clone_dir = tmp_dir() <> "_clone"
      on_exit(fn -> File.rm_rf!(clone_dir) end)

      assert {:ok, %Repo{} = repo} = Repo.clone(dir, clone_dir)
      assert repo.path == clone_dir
      assert File.dir?(Path.join(clone_dir, ".git"))
    end
  end

  # ---------------------------------------------------------------------------
  # Wrapper functions
  # ---------------------------------------------------------------------------

  describe "status/2" do
    test "returns status for a repo", %{tmp_dir: dir} do
      {:ok, repo} = Repo.open(dir)
      assert {:ok, status} = Repo.status(repo)
      assert status.branch == "main"
    end
  end

  describe "log/2" do
    test "returns log entries", %{tmp_dir: dir} do
      {:ok, repo} = Repo.open(dir)
      assert {:ok, commits} = Repo.log(repo)
      assert commits != []
      assert hd(commits).subject == "initial"
    end
  end

  describe "commit/3" do
    test "creates a commit", %{tmp_dir: dir} do
      {:ok, repo} = Repo.open(dir)

      # Create and stage a file
      File.write!(Path.join(dir, "test.txt"), "hello")
      System.cmd("git", ["add", "test.txt"], cd: dir)

      assert {:ok, result} = Repo.commit(repo, "test commit", [])
      assert result.subject == "test commit"
    end
  end

  describe "add/2" do
    test "stages files", %{tmp_dir: dir} do
      {:ok, repo} = Repo.open(dir)
      File.write!(Path.join(dir, "new_file.txt"), "content")

      assert {:ok, :done} = Repo.add(repo, files: ["new_file.txt"])

      # Verify it was staged
      {:ok, status} = Repo.status(repo)
      assert Enum.any?(status.entries, fn e -> e.path == "new_file.txt" end)
    end
  end

  describe "branch/2" do
    test "lists branches", %{tmp_dir: dir} do
      {:ok, repo} = Repo.open(dir)
      assert {:ok, branches} = Repo.branch(repo)
      assert Enum.any?(branches, fn b -> b.name == "main" end)
    end

    test "creates a branch", %{tmp_dir: dir} do
      {:ok, repo} = Repo.open(dir)
      assert {:ok, :done} = Repo.branch(repo, create: "test-branch")
      {:ok, branches} = Repo.branch(repo)
      assert Enum.any?(branches, fn b -> b.name == "test-branch" end)
    end
  end

  describe "rev_parse/2" do
    test "resolves HEAD", %{tmp_dir: dir} do
      {:ok, repo} = Repo.open(dir)
      assert {:ok, sha} = Repo.rev_parse(repo, ref: "HEAD")
      assert String.length(String.trim(sha)) == 40
    end
  end

  describe "ls_files/2" do
    test "lists tracked files", %{tmp_dir: dir} do
      {:ok, repo} = Repo.open(dir)
      File.write!(Path.join(dir, "tracked.txt"), "content")
      System.cmd("git", ["add", "tracked.txt"], cd: dir)

      System.cmd(
        "git",
        [
          "-c",
          "user.name=Test User",
          "-c",
          "user.email=test@test.com",
          "commit",
          "-m",
          "add file"
        ],
        cd: dir
      )

      assert {:ok, files} = Repo.ls_files(repo)
      assert "tracked.txt" in files
    end
  end

  # ---------------------------------------------------------------------------
  # Pipeline pattern
  # ---------------------------------------------------------------------------

  describe "pipeline" do
    test "ok/1 wraps repo in ok tuple", %{tmp_dir: dir} do
      {:ok, repo} = Repo.open(dir)
      assert {:ok, ^repo} = Repo.ok(repo)
    end

    test "run/2 passes repo to function on success", %{tmp_dir: dir} do
      {:ok, repo} = Repo.open(dir)

      result =
        Repo.ok(repo)
        |> Repo.run(fn r ->
          {:ok, _} = Repo.status(r)
          {:ok, r}
        end)

      assert {:ok, %Repo{}} = result
    end

    test "run/2 short-circuits on error" do
      result =
        {:error, "something went wrong"}
        |> Repo.run(fn _repo ->
          flunk("should not be called")
        end)

      assert {:error, "something went wrong"} = result
    end

    test "chained pipeline", %{tmp_dir: dir} do
      {:ok, repo} = Repo.open(dir)

      result =
        Repo.ok(repo)
        |> Repo.run(fn r ->
          File.write!(Path.join(dir, "pipeline.txt"), "pipeline test")
          {:ok, :done} = Repo.add(r, files: ["pipeline.txt"])
          {:ok, r}
        end)
        |> Repo.run(fn r ->
          {:ok, _} = Repo.commit(r, "pipeline commit")
          {:ok, r}
        end)
        |> Repo.run(fn r ->
          {:ok, commits} = Repo.log(r, max_count: 1)
          assert hd(commits).subject == "pipeline commit"
          {:ok, r}
        end)

      assert {:ok, %Repo{}} = result
    end
  end
end
