defmodule Git.Commands.DiffFiles do
  @moduledoc """
  Implements the `Git.Command` behaviour for `git diff-files`.

  Compares the files in the working tree against the index. Output is
  requested with `--raw -z` and parsed into `Git.DiffRawEntry` structs.
  """

  @behaviour Git.Command

  alias Git.DiffRawEntry

  @type t :: %__MODULE__{}

  defstruct []

  @doc """
  Returns the argument list for `git diff-files`.

  ## Examples

      iex> Git.Commands.DiffFiles.args(%Git.Commands.DiffFiles{})
      ["diff-files", "--raw", "-z"]

  """
  @spec args(t()) :: [String.t()]
  @impl true
  def args(%__MODULE__{}) do
    ["diff-files", "--raw", "-z"]
  end

  @doc """
  Parses the output of `git diff-files --raw -z`.

  On success (exit code 0), returns `{:ok, [Git.DiffRawEntry.t()]}`.
  On failure, returns `{:error, {stdout, exit_code}}`.
  """
  @spec parse_output(String.t(), non_neg_integer()) ::
          {:ok, [DiffRawEntry.t()]} | {:error, {String.t(), non_neg_integer()}}
  @impl true
  def parse_output(stdout, 0), do: {:ok, DiffRawEntry.parse(stdout)}

  def parse_output(stdout, exit_code), do: {:error, {stdout, exit_code}}
end
