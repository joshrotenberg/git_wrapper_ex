defmodule Git.MaintenanceTest do
  use ExUnit.Case, async: true

  alias Git.Commands.Maintenance
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
        "git_maintenance_test_#{:erlang.unique_integer([:positive])}"
      )

    File.mkdir_p!(tmp_dir)
    cfg = Config.new(working_dir: tmp_dir, env: @env)
    {:ok, :done} = Git.init(config: cfg)

    {:ok, :done} =
      Git.git_config(set_key: "user.name", set_value: "Test User", config: cfg)

    {:ok, :done} =
      Git.git_config(set_key: "user.email", set_value: "test@test.com", config: cfg)

    {:ok, _} = Git.commit("initial", allow_empty: true, config: cfg)
    on_exit(fn -> File.rm_rf!(tmp_dir) end)
    {tmp_dir, cfg}
  end

  describe "args/1" do
    test "builds args with run subcommand" do
      assert Maintenance.args(%Maintenance{run: true}) == ["maintenance", "run"]
    end

    test "builds args with start subcommand" do
      assert Maintenance.args(%Maintenance{start: true}) == ["maintenance", "start"]
    end

    test "builds args with stop subcommand" do
      assert Maintenance.args(%Maintenance{stop: true}) == ["maintenance", "stop"]
    end

    test "builds args with register subcommand" do
      assert Maintenance.args(%Maintenance{register_: true}) == ["maintenance", "register"]
    end

    test "builds args with unregister subcommand" do
      assert Maintenance.args(%Maintenance{unregister: true}) == ["maintenance", "unregister"]
    end

    test "builds args with task option" do
      assert Maintenance.args(%Maintenance{run: true, task: "gc"}) ==
               ["maintenance", "run", "--task", "gc"]
    end

    test "builds args with auto flag" do
      assert Maintenance.args(%Maintenance{run: true, auto: true}) ==
               ["maintenance", "run", "--auto"]
    end

    test "builds args with quiet flag" do
      assert Maintenance.args(%Maintenance{run: true, quiet: true}) ==
               ["maintenance", "run", "--quiet"]
    end

    test "builds args with schedule option" do
      assert Maintenance.args(%Maintenance{run: true, schedule: "daily"}) ==
               ["maintenance", "run", "--schedule", "daily"]
    end

    test "builds args with multiple options" do
      assert Maintenance.args(%Maintenance{run: true, task: "gc", quiet: true}) ==
               ["maintenance", "run", "--task", "gc", "--quiet"]
    end
  end

  describe "git maintenance" do
    test "runs maintenance on a repository" do
      {_tmp_dir, cfg} = setup_repo()

      assert {:ok, :done} = Git.maintenance(run: true, config: cfg)
    end

    test "runs specific maintenance task" do
      {_tmp_dir, cfg} = setup_repo()

      assert {:ok, :done} = Git.maintenance(run: true, task: "gc", config: cfg)
    end

    test "runs maintenance with auto mode" do
      {_tmp_dir, cfg} = setup_repo()

      assert {:ok, :done} = Git.maintenance(run: true, auto: true, config: cfg)
    end
  end
end
