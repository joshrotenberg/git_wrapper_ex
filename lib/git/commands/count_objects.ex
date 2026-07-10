defmodule Git.Commands.CountObjects do
  @moduledoc """
  Implements the `Git.Command` behaviour for `git count-objects`.

  Always runs in verbose mode (`-v`) so the full set of statistics is
  available for parsing into a `Git.CountObjects` struct.
  """

  @behaviour Git.Command

  @type t :: %__MODULE__{}

  defstruct []

  @doc """
  Returns the argument list for `git count-objects -v`.

  ## Examples

      iex> Git.Commands.CountObjects.args(%Git.Commands.CountObjects{})
      ["count-objects", "-v"]

  """
  @spec args(t()) :: [String.t()]
  @impl true
  def args(%__MODULE__{}), do: ["count-objects", "-v"]

  @doc """
  Parses the output of `git count-objects -v` into a `Git.CountObjects` struct.

  On a non-zero exit code, returns `{:error, {stdout, exit_code}}`.
  """
  @spec parse_output(String.t(), non_neg_integer()) ::
          {:ok, Git.CountObjects.t()} | {:error, {String.t(), non_neg_integer()}}
  @impl true
  def parse_output(stdout, 0), do: {:ok, Git.CountObjects.parse(stdout)}
  def parse_output(stdout, exit_code), do: {:error, {stdout, exit_code}}
end
