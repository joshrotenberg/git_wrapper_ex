defmodule Git.Commands.Mv do
  @moduledoc """
  Implements the `Git.Command` behaviour for `git mv`.

  Supports moving or renaming a tracked file, with options for force,
  dry-run, verbose output, and skipping errors.
  """

  @behaviour Git.Command

  @type t :: %__MODULE__{
          source: String.t(),
          destination: String.t(),
          force: boolean(),
          dry_run: boolean(),
          verbose: boolean(),
          skip_errors: boolean()
        }

  @enforce_keys [:source, :destination]
  defstruct source: "",
            destination: "",
            force: false,
            dry_run: false,
            verbose: false,
            skip_errors: false

  @doc """
  Returns the argument list for `git mv`.

  Builds `git mv [options] <source> <destination>` from the struct fields.

  ## Examples

      iex> Git.Commands.Mv.args(%Git.Commands.Mv{source: "a.txt", destination: "b.txt"})
      ["mv", "a.txt", "b.txt"]

      iex> Git.Commands.Mv.args(%Git.Commands.Mv{source: "a.txt", destination: "b.txt", force: true})
      ["mv", "-f", "a.txt", "b.txt"]

      iex> Git.Commands.Mv.args(%Git.Commands.Mv{source: "a.txt", destination: "b.txt", dry_run: true, verbose: true})
      ["mv", "-n", "-v", "a.txt", "b.txt"]

  """
  @spec args(t()) :: [String.t()]
  @impl true
  def args(%__MODULE__{} = command) do
    ["mv"]
    |> maybe_add(command.force, "-f")
    |> maybe_add(command.dry_run, "-n")
    |> maybe_add(command.verbose, "-v")
    |> maybe_add(command.skip_errors, "-k")
    |> Kernel.++([command.source, command.destination])
  end

  @doc """
  Parses the output of `git mv`.

  On success (exit code 0), returns `{:ok, :done}`. On failure, returns
  `{:error, {stdout, exit_code}}`.
  """
  @spec parse_output(String.t(), non_neg_integer()) ::
          {:ok, :done} | {:error, {String.t(), non_neg_integer()}}
  @impl true
  def parse_output(_stdout, 0), do: {:ok, :done}
  def parse_output(stdout, exit_code), do: {:error, {stdout, exit_code}}

  defp maybe_add(args, true, flag), do: args ++ [flag]
  defp maybe_add(args, false, _flag), do: args
end
