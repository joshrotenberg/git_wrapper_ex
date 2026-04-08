defmodule Git.Commands.Maintenance do
  @moduledoc """
  Implements the `Git.Command` behaviour for `git maintenance`.

  Runs, starts, stops, registers, or unregisters repository maintenance tasks
  such as garbage collection, commit-graph updates, and prefetching.
  """

  @behaviour Git.Command

  @type t :: %__MODULE__{
          run: boolean(),
          start: boolean(),
          stop: boolean(),
          register_: boolean(),
          unregister: boolean(),
          task: String.t() | nil,
          auto: boolean(),
          quiet: boolean(),
          schedule: String.t() | nil
        }

  defstruct run: false,
            start: false,
            stop: false,
            register_: false,
            unregister: false,
            task: nil,
            auto: false,
            quiet: false,
            schedule: nil

  @doc """
  Returns the argument list for `git maintenance`.

  ## Examples

      iex> Git.Commands.Maintenance.args(%Git.Commands.Maintenance{run: true})
      ["maintenance", "run"]

      iex> Git.Commands.Maintenance.args(%Git.Commands.Maintenance{start: true})
      ["maintenance", "start"]

      iex> Git.Commands.Maintenance.args(%Git.Commands.Maintenance{stop: true})
      ["maintenance", "stop"]

      iex> Git.Commands.Maintenance.args(%Git.Commands.Maintenance{register_: true})
      ["maintenance", "register"]

      iex> Git.Commands.Maintenance.args(%Git.Commands.Maintenance{unregister: true})
      ["maintenance", "unregister"]

      iex> Git.Commands.Maintenance.args(%Git.Commands.Maintenance{run: true, task: "gc"})
      ["maintenance", "run", "--task", "gc"]

      iex> Git.Commands.Maintenance.args(%Git.Commands.Maintenance{run: true, auto: true})
      ["maintenance", "run", "--auto"]

      iex> Git.Commands.Maintenance.args(%Git.Commands.Maintenance{run: true, quiet: true})
      ["maintenance", "run", "--quiet"]

      iex> Git.Commands.Maintenance.args(%Git.Commands.Maintenance{run: true, schedule: "daily"})
      ["maintenance", "run", "--schedule", "daily"]

  """
  @spec args(t()) :: [String.t()]
  @impl true
  def args(%__MODULE__{} = command) do
    ["maintenance"]
    |> add_subcommand(command)
    |> maybe_add_option(command.task, "--task")
    |> maybe_add_flag(command.auto, "--auto")
    |> maybe_add_flag(command.quiet, "--quiet")
    |> maybe_add_option(command.schedule, "--schedule")
  end

  @doc """
  Parses the output of `git maintenance`.

  On success (exit code 0), returns `{:ok, :done}`. On failure, returns
  `{:error, {stdout, exit_code}}`.
  """
  @spec parse_output(String.t(), non_neg_integer()) ::
          {:ok, :done} | {:error, {String.t(), non_neg_integer()}}
  @impl true
  def parse_output(_stdout, 0), do: {:ok, :done}
  def parse_output(stdout, exit_code), do: {:error, {stdout, exit_code}}

  defp add_subcommand(args, %{run: true}), do: args ++ ["run"]
  defp add_subcommand(args, %{start: true}), do: args ++ ["start"]
  defp add_subcommand(args, %{stop: true}), do: args ++ ["stop"]
  defp add_subcommand(args, %{register_: true}), do: args ++ ["register"]
  defp add_subcommand(args, %{unregister: true}), do: args ++ ["unregister"]
  defp add_subcommand(args, _command), do: args

  defp maybe_add_flag(args, false, _flag), do: args
  defp maybe_add_flag(args, true, flag), do: args ++ [flag]

  defp maybe_add_option(args, nil, _flag), do: args
  defp maybe_add_option(args, value, flag), do: args ++ [flag, value]
end
