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
end
