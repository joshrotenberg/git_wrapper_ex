defmodule Git.SubmoduleTest do
  use ExUnit.Case, async: true

  alias Git.Commands.Submodule, as: SubmoduleCmd
  alias Git.{Config, SubmoduleEntry}

  # Environment variables to allow the file:// transport protocol in newer
  # git versions (>= 2.38) and set committer identity for tests.
  @test_env [
    {"GIT_CONFIG_COUNT", "1"},
    {"GIT_CONFIG_KEY_0", "protocol.file.allow"},
    {"GIT_CONFIG_VALUE_0", "always"},
    {"GIT_AUTHOR_NAME", "Test User"},
    {"GIT_AUTHOR_EMAIL", "test@test.com"},
    {"GIT_COMMITTER_NAME", "Test User"},
    {"GIT_COMMITTER_EMAIL", "test@test.com"}
  ]

  defp setup_repos(name) do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "git_submodule_#{name}_#{:erlang.unique_integer([:positive])}"
      )

    File.mkdir_p!(tmp_dir)

    # Create the "library" repo to use as submodule source
    lib_dir = Path.join(tmp_dir, "library")
    File.mkdir_p!(lib_dir)
    lib_cfg = Config.new(working_dir: lib_dir, env: @test_env)
    {:ok, :done} = Git.init(config: lib_cfg)
    {:ok, :done} = Git.git_config(set_key: "user.name", set_value: "Test User", config: lib_cfg)

    {:ok, :done} =
      Git.git_config(set_key: "user.email", set_value: "test@test.com", config: lib_cfg)

    File.write!(Path.join(lib_dir, "lib.txt"), "library content\n")
    {:ok, :done} = Git.add(all: true, config: lib_cfg)
    {:ok, _} = Git.commit("initial library commit", config: lib_cfg)

    # Create the "project" repo
    project_dir = Path.join(tmp_dir, "project")
    File.mkdir_p!(project_dir)
    proj_cfg = Config.new(working_dir: project_dir, env: @test_env)
    {:ok, :done} = Git.init(config: proj_cfg)

    {:ok, :done} =
      Git.git_config(set_key: "user.name", set_value: "Test User", config: proj_cfg)

    {:ok, :done} =
      Git.git_config(set_key: "user.email", set_value: "test@test.com", config: proj_cfg)

    {:ok, _} = Git.commit("initial project commit", allow_empty: true, config: proj_cfg)

    {tmp_dir, lib_dir, project_dir, proj_cfg}
  end

  describe "args/1" do
    test "default status mode" do
      assert SubmoduleCmd.args(%SubmoduleCmd{}) == ["submodule", "status"]
    end

    test "status with recursive" do
      cmd = %SubmoduleCmd{recursive: true}
      assert SubmoduleCmd.args(cmd) == ["submodule", "status", "--recursive"]
    end

    test "status with path" do
      cmd = %SubmoduleCmd{path: "vendor/lib"}
      assert SubmoduleCmd.args(cmd) == ["submodule", "status", "vendor/lib"]
    end

    test "init mode" do
      cmd = %SubmoduleCmd{init: true}
      assert SubmoduleCmd.args(cmd) == ["submodule", "init"]
    end

    test "init with path" do
      cmd = %SubmoduleCmd{init: true, path: "vendor/lib"}
      assert SubmoduleCmd.args(cmd) == ["submodule", "init", "vendor/lib"]
    end

    test "update mode" do
      cmd = %SubmoduleCmd{update: true}
      assert SubmoduleCmd.args(cmd) == ["submodule", "update"]
    end

    test "update with all flags" do
      cmd = %SubmoduleCmd{
        update: true,
        force: true,
        remote: true,
        merge: true,
        rebase: true,
        recursive: true,
        depth: 1,
        reference: "/tmp/ref"
      }

      assert SubmoduleCmd.args(cmd) == [
               "submodule",
               "update",
               "--force",
               "--remote",
               "--merge",
               "--rebase",
               "--recursive",
               "--depth",
               "1",
               "--reference",
               "/tmp/ref"
             ]
    end

    test "add mode with url only" do
      cmd = %SubmoduleCmd{add_url: "https://example.com/lib.git"}
      assert SubmoduleCmd.args(cmd) == ["submodule", "add", "https://example.com/lib.git"]
    end

    test "add mode with url and path" do
      cmd = %SubmoduleCmd{add_url: "https://example.com/lib.git", add_path: "vendor/lib"}

      assert SubmoduleCmd.args(cmd) == [
               "submodule",
               "add",
               "https://example.com/lib.git",
               "vendor/lib"
             ]
    end

    test "add mode with branch and name" do
      cmd = %SubmoduleCmd{
        add_url: "https://example.com/lib.git",
        add_path: "vendor/lib",
        branch: "develop",
        name: "mylib"
      }

      assert SubmoduleCmd.args(cmd) == [
               "submodule",
               "add",
               "--name",
               "mylib",
               "-b",
               "develop",
               "https://example.com/lib.git",
               "vendor/lib"
             ]
    end

    test "deinit mode" do
      cmd = %SubmoduleCmd{deinit: "vendor/lib"}
      assert SubmoduleCmd.args(cmd) == ["submodule", "deinit", "vendor/lib"]
    end

    test "deinit with force" do
      cmd = %SubmoduleCmd{deinit: "vendor/lib", force: true}
      assert SubmoduleCmd.args(cmd) == ["submodule", "deinit", "--force", "vendor/lib"]
    end

    test "sync mode" do
      cmd = %SubmoduleCmd{sync: true}
      assert SubmoduleCmd.args(cmd) == ["submodule", "sync"]
    end

    test "sync with recursive" do
      cmd = %SubmoduleCmd{sync: true, recursive: true}
      assert SubmoduleCmd.args(cmd) == ["submodule", "sync", "--recursive"]
    end

    test "summary mode" do
      cmd = %SubmoduleCmd{summary: true}
      assert SubmoduleCmd.args(cmd) == ["submodule", "summary"]
    end

    test "set-branch mode" do
      cmd = %SubmoduleCmd{set_branch: "develop", path: "vendor/lib"}
      assert SubmoduleCmd.args(cmd) == ["submodule", "set-branch", "-b", "develop", "vendor/lib"]
    end

    test "set-url mode" do
      cmd = %SubmoduleCmd{set_url: "https://new.example.com/lib.git", path: "vendor/lib"}

      assert SubmoduleCmd.args(cmd) == [
               "submodule",
               "set-url",
               "vendor/lib",
               "https://new.example.com/lib.git"
             ]
    end
  end

  describe "SubmoduleEntry.parse/1" do
    test "parses current status line" do
      output = " abc1234def5678 lib/sub (v1.0.0)\n"
      [entry] = SubmoduleEntry.parse(output)

      assert %SubmoduleEntry{
               sha: "abc1234def5678",
               path: "lib/sub",
               describe: "v1.0.0",
               status: :current
             } = entry
    end

    test "parses modified status line" do
      output = "+def5678abc1234 vendor/dep\n"
      [entry] = SubmoduleEntry.parse(output)

      assert %SubmoduleEntry{
               sha: "def5678abc1234",
               path: "vendor/dep",
               describe: nil,
               status: :modified
             } = entry
    end

    test "parses uninitialized status line" do
      output = "-aaa1111bbb2222 lib/uninit\n"
      [entry] = SubmoduleEntry.parse(output)

      assert %SubmoduleEntry{
               sha: "aaa1111bbb2222",
               path: "lib/uninit",
               describe: nil,
               status: :uninitialized
             } = entry
    end

    test "parses conflict status line" do
      output = "Uccc3333ddd4444 lib/conflict (v2.0)\n"
      [entry] = SubmoduleEntry.parse(output)

      assert %SubmoduleEntry{
               sha: "ccc3333ddd4444",
               path: "lib/conflict",
               describe: "v2.0",
               status: :conflict
             } = entry
    end

    test "parses multiple entries" do
      output = """
       abc1234 path/a (v1.0)
      +def5678 path/b
      -111aaaa path/c
      """

      entries = SubmoduleEntry.parse(output)
      assert length(entries) == 3
      assert Enum.map(entries, & &1.status) == [:current, :modified, :uninitialized]
    end

    test "parses empty output" do
      assert SubmoduleEntry.parse("") == []
    end
  end

  describe "status on repo with no submodules" do
    test "returns empty list" do
      {tmp_dir, _lib_dir, _project_dir, proj_cfg} = setup_repos("empty_status")
      on_exit(fn -> File.rm_rf!(tmp_dir) end)

      assert {:ok, []} = Git.submodule(config: proj_cfg)
    end
  end

  describe "add and status" do
    test "adds a submodule and shows it in status" do
      {tmp_dir, lib_dir, _project_dir, proj_cfg} = setup_repos("add_status")
      on_exit(fn -> File.rm_rf!(tmp_dir) end)

      # Add the library as a submodule
      assert {:ok, :done} =
               Git.submodule(add_url: lib_dir, add_path: "vendor/library", config: proj_cfg)

      # Status should show the submodule
      assert {:ok, entries} = Git.submodule(config: proj_cfg)
      assert length(entries) == 1

      [entry] = entries
      assert entry.path == "vendor/library"
      assert entry.sha != ""
    end
  end

  describe "init and update" do
    test "initializes and updates submodules" do
      {tmp_dir, lib_dir, project_dir, proj_cfg} = setup_repos("init_update")
      on_exit(fn -> File.rm_rf!(tmp_dir) end)

      # Add submodule and commit
      assert {:ok, :done} =
               Git.submodule(add_url: lib_dir, add_path: "vendor/library", config: proj_cfg)

      {:ok, :done} = Git.add(all: true, config: proj_cfg)
      {:ok, _} = Git.commit("add submodule", config: proj_cfg)

      # Clone the project to simulate a fresh checkout
      clone_dir = Path.join(tmp_dir, "clone")
      File.mkdir_p!(clone_dir)

      System.cmd("git", ["clone", project_dir, clone_dir], env: @test_env)

      clone_cfg = Config.new(working_dir: clone_dir, env: @test_env)

      # Submodule should be uninitialized in the clone
      assert {:ok, entries} = Git.submodule(config: clone_cfg)
      assert length(entries) == 1
      assert hd(entries).status == :uninitialized

      # Init the submodule
      assert {:ok, :done} = Git.submodule(init: true, config: clone_cfg)

      # Update the submodule
      assert {:ok, :done} = Git.submodule(update: true, config: clone_cfg)

      # Now check that the submodule file exists
      assert File.exists?(Path.join(clone_dir, "vendor/library/lib.txt"))
    end
  end

  describe "deinit" do
    test "deinitializes a submodule" do
      {tmp_dir, lib_dir, _project_dir, proj_cfg} = setup_repos("deinit")
      on_exit(fn -> File.rm_rf!(tmp_dir) end)

      # Add submodule and commit
      assert {:ok, :done} =
               Git.submodule(add_url: lib_dir, add_path: "vendor/library", config: proj_cfg)

      {:ok, :done} = Git.add(all: true, config: proj_cfg)
      {:ok, _} = Git.commit("add submodule", config: proj_cfg)

      # Deinit the submodule
      assert {:ok, :done} =
               Git.submodule(deinit: "vendor/library", force: true, config: proj_cfg)
    end
  end

  describe "sync" do
    test "syncs submodule URLs" do
      {tmp_dir, lib_dir, _project_dir, proj_cfg} = setup_repos("sync")
      on_exit(fn -> File.rm_rf!(tmp_dir) end)

      # Add submodule and commit
      assert {:ok, :done} =
               Git.submodule(add_url: lib_dir, add_path: "vendor/library", config: proj_cfg)

      {:ok, :done} = Git.add(all: true, config: proj_cfg)
      {:ok, _} = Git.commit("add submodule", config: proj_cfg)

      # Sync should succeed
      assert {:ok, :done} = Git.submodule(sync: true, config: proj_cfg)
    end
  end
end
