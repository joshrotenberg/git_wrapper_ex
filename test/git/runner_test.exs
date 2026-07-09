defmodule Git.RunnerTest do
  use ExUnit.Case, async: true

  alias Git.Command
  alias Git.Config
  alias Git.Runner.Forcola
  alias Git.Runner.SystemCmd

  defmodule StubRunner do
    @moduledoc false
    @behaviour Git.Runner

    @impl true
    def run(binary, args, opts) do
      send(self(), {:stub_runner, binary, args, opts})
      {:ok, {"STUB OUTPUT", 0}}
    end
  end

  defmodule ErrorRunner do
    @moduledoc false
    @behaviour Git.Runner

    @impl true
    def run(_binary, _args, _opts), do: {:error, :timeout}
  end

  defmodule EchoCommand do
    @moduledoc false
    @behaviour Git.Command

    defstruct []

    @impl true
    def args(%__MODULE__{}), do: ["echo-command"]

    @impl true
    def parse_output(stdout, exit_code), do: {:ok, {stdout, exit_code}}
  end

  describe "Config default" do
    test "runner defaults to :system_cmd" do
      assert Config.new().runner == :system_cmd
    end

    test "runner is settable" do
      assert Config.new(runner: :forcola).runner == :forcola
    end
  end

  describe "Command.runner/1 resolution" do
    test ":system_cmd resolves to SystemCmd" do
      assert Command.runner(Config.new(runner: :system_cmd)) == SystemCmd
    end

    test "a custom module resolves to itself" do
      assert Command.runner(Config.new(runner: StubRunner)) == StubRunner
    end

    test ":forcola resolves to the forcola runner when available, else falls back" do
      resolved = Command.runner(Config.new(runner: :forcola))

      if Code.ensure_loaded?(Forcola) do
        assert resolved == Forcola
      else
        assert resolved == SystemCmd
      end
    end
  end

  describe "Command.run/3 dispatch" do
    test "routes execution through the configured runner" do
      config = Config.new(runner: StubRunner, working_dir: "/some/dir", timeout: 1234)

      assert {:ok, {"STUB OUTPUT", 0}} =
               Command.run(EchoCommand, %EchoCommand{}, config)

      assert_received {:stub_runner, binary, ["echo-command"], opts}
      assert String.ends_with?(binary, "git")
      assert opts[:timeout] == 1234
      assert opts[:cd] == "/some/dir"
    end

    test "propagates a runner error to the caller" do
      config = Config.new(runner: ErrorRunner)
      assert {:error, :timeout} = Command.run(EchoCommand, %EchoCommand{}, config)
    end
  end

  describe "SystemCmd" do
    test "returns {:ok, {stdout, exit_code}} on completion" do
      assert {:ok, {stdout, 0}} =
               SystemCmd.run("git", ["--version"],
                 timeout: 5000,
                 stderr_to_stdout: true
               )

      assert stdout =~ "git version"
    end

    test "returns {:error, :timeout} when the command exceeds the timeout" do
      assert {:error, :timeout} =
               SystemCmd.run("sleep", ["2"], timeout: 50, stderr_to_stdout: true)
    end
  end

  describe "Forcola" do
    @describetag :forcola

    setup do
      unless Code.ensure_loaded?(Forcola) do
        raise "forcola runner not available; run with `mix test` and forcola installed"
      end

      :ok
    end

    test "returns {:ok, {stdout, exit_code}} on completion" do
      assert {:ok, {stdout, 0}} =
               Forcola.run("git", ["--version"], timeout: 5000, stderr_to_stdout: true)

      assert stdout =~ "git version"
    end

    test "returns {:error, :timeout} when the command exceeds the timeout" do
      assert {:error, :timeout} =
               Forcola.run("sleep", ["2"], timeout: 50, stderr_to_stdout: true)
    end
  end
end
