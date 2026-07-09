defmodule Git.ConfigTest do
  use ExUnit.Case, async: true

  alias Git.Config

  describe "cmd_opts/1 environment" do
    test "defaults GIT_TERMINAL_PROMPT=0 so auth-required git cannot hang" do
      env = Config.new() |> Config.cmd_opts() |> Keyword.fetch!(:env)

      assert {"GIT_TERMINAL_PROMPT", "0"} in env
    end

    test "always sets :env even when no caller env is given" do
      opts = Config.cmd_opts(Config.new())

      assert Keyword.has_key?(opts, :env)
      assert opts[:stderr_to_stdout] == true
    end

    test "a caller can override GIT_TERMINAL_PROMPT without a duplicate key" do
      env =
        Config.new(env: [{"GIT_TERMINAL_PROMPT", "1"}])
        |> Config.cmd_opts()
        |> Keyword.fetch!(:env)

      assert {"GIT_TERMINAL_PROMPT", "1"} in env
      assert Enum.count(env, fn {key, _value} -> key == "GIT_TERMINAL_PROMPT" end) == 1
    end

    test "caller env for other keys is preserved alongside the default" do
      env =
        Config.new(env: [{"FOO", "bar"}])
        |> Config.cmd_opts()
        |> Keyword.fetch!(:env)

      assert {"GIT_TERMINAL_PROMPT", "0"} in env
      assert {"FOO", "bar"} in env
    end
  end

  describe "cmd_opts/1 working_dir" do
    test "sets :cd when working_dir is present" do
      opts = Config.cmd_opts(Config.new(working_dir: "/tmp"))

      assert opts[:cd] == "/tmp"
    end

    test "omits :cd when working_dir is nil" do
      opts = Config.cmd_opts(Config.new())

      refute Keyword.has_key?(opts, :cd)
    end
  end

  describe "base_args/1 with extra_config" do
    test "emits a -c key=value pair for each entry" do
      config = Config.new(extra_config: [{"user.name", "X"}, {"gc.auto", "0"}])

      assert Config.base_args(config) == ["-c", "user.name=X", "-c", "gc.auto=0"]
    end

    test "returns [] when extra_config is empty" do
      assert Config.base_args(Config.new()) == []
    end
  end

  describe "extra_config reaches git" do
    setup do
      tmp_dir =
        Path.join(
          System.tmp_dir!(),
          "git_config_test_#{:erlang.unique_integer([:positive])}"
        )

      File.mkdir_p!(tmp_dir)
      base = Config.new(working_dir: tmp_dir)
      {:ok, :done} = Git.init(config: base)
      {:ok, :done} = Git.git_config(set_key: "user.name", set_value: "Repo User", config: base)

      {:ok, :done} =
        Git.git_config(set_key: "user.email", set_value: "repo@example.com", config: base)

      File.write!(Path.join(tmp_dir, "a.txt"), "hi\n")
      on_exit(fn -> Git.TestHelpers.rm_rf(tmp_dir) end)

      %{tmp_dir: tmp_dir}
    end

    test "-c overrides repo config for a commit", %{tmp_dir: tmp_dir} do
      override =
        Config.new(
          working_dir: tmp_dir,
          extra_config: [{"user.name", "Override User"}, {"user.email", "override@example.com"}]
        )

      {:ok, :done} = Git.add(all: true, config: override)
      {:ok, _} = Git.commit("test: extra_config", config: override)
      {:ok, [commit | _]} = Git.log(config: override)

      assert commit.author_name == "Override User"
      assert commit.author_email == "override@example.com"
    end
  end
end
