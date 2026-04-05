defmodule Git.Command do
  @moduledoc """
  Behaviour and runner for git commands.

  Modules implementing this behaviour define how to build argument lists
  for a specific git subcommand and how to parse the resulting output.
  """

  alias Git.Config

  @doc """
  Returns the argument list for this command.
  """
  @callback args(command :: struct()) :: [String.t()]

  @doc """
  Parses the stdout and exit code from the git process into a result.
  """
  @callback parse_output(stdout :: String.t(), exit_code :: non_neg_integer()) ::
              {:ok, term()} | {:error, term()}

  @doc """
  Runs a git command.

  Takes a module implementing the `Git.Command` behaviour, a command
  struct, and a `Git.Config`. Builds the full argument list, executes
  git via `System.cmd/3`, and delegates parsing to the command module.

  If the command exceeds the configured timeout, returns `{:error, :timeout}`.

  ## Examples

      Git.Command.run(Git.Commands.Status, %Git.Commands.Status{}, config)

  """
  @spec run(module(), struct(), Config.t()) :: {:ok, term()} | {:error, term()}
  def run(mod, command, %Config{} = config) do
    all_args = Config.base_args(config) ++ mod.args(command)
    opts = Config.cmd_opts(config)

    task =
      Task.async(fn ->
        System.cmd(config.binary, all_args, opts)
      end)

    case Task.yield(task, config.timeout) || Task.shutdown(task) do
      {:ok, {stdout, exit_code}} ->
        mod.parse_output(stdout, exit_code)

      nil ->
        {:error, :timeout}
    end
  end
end
