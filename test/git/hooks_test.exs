defmodule Git.HooksTest do
  use ExUnit.Case, async: true

  # ---------------------------------------------------------------------------
  # Test helpers
  # ---------------------------------------------------------------------------

  setup do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "git_hooks_test_#{:erlang.unique_integer([:positive])}"
      )

    File.mkdir_p!(tmp_dir)
    System.cmd("git", ["init", "--initial-branch=main"], cd: tmp_dir)
    System.cmd("git", ["config", "user.email", "test@example.com"], cd: tmp_dir)
    System.cmd("git", ["config", "user.name", "Test User"], cd: tmp_dir)

    on_exit(fn -> File.rm_rf!(tmp_dir) end)
    config = Git.Config.new(working_dir: tmp_dir)
    %{tmp_dir: tmp_dir, config: config}
  end

  # ---------------------------------------------------------------------------
  # list/1
  # ---------------------------------------------------------------------------

  describe "list/1" do
    test "returns empty list when no hooks installed", %{config: config} do
      assert {:ok, []} = Git.Hooks.list(config: config)
    end

    test "lists an installed hook", %{config: config} do
      {:ok, _path} = Git.Hooks.write("pre-commit", "#!/bin/sh\nexit 0\n", config: config)

      assert {:ok, hooks} = Git.Hooks.list(config: config)
      assert length(hooks) == 1
      hook = hd(hooks)
      assert hook.name == "pre-commit"
      assert hook.enabled == true
      assert String.ends_with?(hook.path, "/hooks/pre-commit")
    end

    test "does not list .sample files", %{tmp_dir: tmp_dir, config: config} do
      hooks_dir = Path.join([tmp_dir, ".git", "hooks"])
      File.mkdir_p!(hooks_dir)
      File.write!(Path.join(hooks_dir, "pre-commit.sample"), "#!/bin/sh\n")

      assert {:ok, []} = Git.Hooks.list(config: config)
    end
  end

  # ---------------------------------------------------------------------------
  # write/3 and read/2
  # ---------------------------------------------------------------------------

  describe "write/3 and read/2" do
    test "writes and reads back a hook", %{config: config} do
      content = "#!/bin/sh\necho 'hello'\n"
      assert {:ok, path} = Git.Hooks.write("pre-commit", content, config: config)
      assert String.ends_with?(path, "/hooks/pre-commit")

      assert {:ok, ^content} = Git.Hooks.read("pre-commit", config: config)
    end

    test "written hook is executable by default", %{config: config} do
      Git.Hooks.write("pre-commit", "#!/bin/sh\n", config: config)
      assert {:ok, true} = Git.Hooks.enabled?("pre-commit", config: config)
    end

    test "write with executable: false does not set executable bit", %{config: config} do
      Git.Hooks.write("pre-commit", "#!/bin/sh\n", config: config, executable: false)
      assert {:ok, false} = Git.Hooks.enabled?("pre-commit", config: config)
    end
  end

  # ---------------------------------------------------------------------------
  # read/2 errors
  # ---------------------------------------------------------------------------

  describe "read/2" do
    test "returns :not_found for missing hook", %{config: config} do
      assert {:error, :not_found} = Git.Hooks.read("pre-commit", config: config)
    end
  end

  # ---------------------------------------------------------------------------
  # enable/2 and disable/2
  # ---------------------------------------------------------------------------

  describe "enable/2 and disable/2" do
    test "disable removes executable bit, enable restores it", %{config: config} do
      Git.Hooks.write("pre-commit", "#!/bin/sh\n", config: config)

      assert {:ok, true} = Git.Hooks.enabled?("pre-commit", config: config)

      assert {:ok, _path} = Git.Hooks.disable("pre-commit", config: config)
      assert {:ok, false} = Git.Hooks.enabled?("pre-commit", config: config)

      assert {:ok, _path} = Git.Hooks.enable("pre-commit", config: config)
      assert {:ok, true} = Git.Hooks.enabled?("pre-commit", config: config)
    end

    test "enable returns :not_found for missing hook", %{config: config} do
      assert {:error, :not_found} = Git.Hooks.enable("pre-commit", config: config)
    end

    test "disable returns :not_found for missing hook", %{config: config} do
      assert {:error, :not_found} = Git.Hooks.disable("pre-commit", config: config)
    end

    test "disabled hook shows enabled: false in list", %{config: config} do
      Git.Hooks.write("pre-commit", "#!/bin/sh\n", config: config)
      Git.Hooks.disable("pre-commit", config: config)

      assert {:ok, [hook]} = Git.Hooks.list(config: config)
      assert hook.name == "pre-commit"
      assert hook.enabled == false
    end
  end

  # ---------------------------------------------------------------------------
  # exists?/2 and enabled?/2
  # ---------------------------------------------------------------------------

  describe "exists?/2" do
    test "returns false when hook does not exist", %{config: config} do
      assert {:ok, false} = Git.Hooks.exists?("pre-commit", config: config)
    end

    test "returns true when hook exists", %{config: config} do
      Git.Hooks.write("pre-commit", "#!/bin/sh\n", config: config)
      assert {:ok, true} = Git.Hooks.exists?("pre-commit", config: config)
    end
  end

  describe "enabled?/2" do
    test "returns false when hook does not exist", %{config: config} do
      assert {:ok, false} = Git.Hooks.enabled?("pre-commit", config: config)
    end

    test "returns true for executable hook", %{config: config} do
      Git.Hooks.write("pre-commit", "#!/bin/sh\n", config: config)
      assert {:ok, true} = Git.Hooks.enabled?("pre-commit", config: config)
    end

    test "returns false for non-executable hook", %{config: config} do
      Git.Hooks.write("pre-commit", "#!/bin/sh\n", config: config, executable: false)
      assert {:ok, false} = Git.Hooks.enabled?("pre-commit", config: config)
    end
  end

  # ---------------------------------------------------------------------------
  # remove/2
  # ---------------------------------------------------------------------------

  describe "remove/2" do
    test "removes an existing hook", %{config: config} do
      Git.Hooks.write("pre-commit", "#!/bin/sh\n", config: config)
      assert :ok = Git.Hooks.remove("pre-commit", config: config)
      assert {:ok, false} = Git.Hooks.exists?("pre-commit", config: config)
    end

    test "returns :not_found for missing hook", %{config: config} do
      assert {:error, :not_found} = Git.Hooks.remove("pre-commit", config: config)
    end
  end

  # ---------------------------------------------------------------------------
  # Invalid hook names
  # ---------------------------------------------------------------------------

  describe "invalid hook name" do
    test "write rejects invalid hook name", %{config: config} do
      assert {:error, :invalid_hook} =
               Git.Hooks.write("not-a-hook", "#!/bin/sh\n", config: config)
    end

    test "read rejects invalid hook name", %{config: config} do
      assert {:error, :invalid_hook} = Git.Hooks.read("not-a-hook", config: config)
    end

    test "enable rejects invalid hook name", %{config: config} do
      assert {:error, :invalid_hook} = Git.Hooks.enable("not-a-hook", config: config)
    end

    test "disable rejects invalid hook name", %{config: config} do
      assert {:error, :invalid_hook} = Git.Hooks.disable("not-a-hook", config: config)
    end

    test "remove rejects invalid hook name", %{config: config} do
      assert {:error, :invalid_hook} = Git.Hooks.remove("not-a-hook", config: config)
    end

    test "exists? rejects invalid hook name", %{config: config} do
      assert {:error, :invalid_hook} = Git.Hooks.exists?("not-a-hook", config: config)
    end

    test "enabled? rejects invalid hook name", %{config: config} do
      assert {:error, :invalid_hook} = Git.Hooks.enabled?("not-a-hook", config: config)
    end
  end
end
