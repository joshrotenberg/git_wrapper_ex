defmodule GitWrapper.Commands.Add do
  @moduledoc """
  Implements the `GitWrapper.Command` behaviour for `git add`.

  Supports adding specific files or all changes with `--all`.
  """

  @behaviour GitWrapper.Command

  @type t :: %__MODULE__{
          files: [String.t()],
          all: boolean()
        }

  defstruct files: [], all: false

  @doc """
  Returns the argument list for `git add`.

  When `:all` is `true`, passes `--all`. Otherwise, appends the list of
  file paths to the argument list.

  ## Examples

      iex> GitWrapper.Commands.Add.args(%GitWrapper.Commands.Add{all: true})
      ["add", "--all"]

      iex> GitWrapper.Commands.Add.args(%GitWrapper.Commands.Add{files: ["foo.txt", "bar.txt"]})
      ["add", "foo.txt", "bar.txt"]

  """
  @spec args(t()) :: [String.t()]
  @impl true
  def args(%__MODULE__{all: true}), do: ["add", "--all"]

  def args(%__MODULE__{files: files}), do: ["add" | files]

  @doc """
  Parses the output of `git add`.

  On success (exit code 0), returns `{:ok, :done}`. On failure, returns
  `{:error, {stdout, exit_code}}`.
  """
  @spec parse_output(String.t(), non_neg_integer()) ::
          {:ok, :done} | {:error, {String.t(), non_neg_integer()}}
  @impl true
  def parse_output(_stdout, 0), do: {:ok, :done}

  def parse_output(stdout, exit_code), do: {:error, {stdout, exit_code}}
end
