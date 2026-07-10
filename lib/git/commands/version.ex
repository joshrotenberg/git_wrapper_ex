defmodule Git.Commands.Version do
  @moduledoc """
  Implements the `Git.Command` behaviour for `git --version`.

  Reports the installed git version, useful for gating on capabilities.
  """

  @behaviour Git.Command

  @type t :: %__MODULE__{}

  defstruct []

  @doc """
  Returns the argument list for `git --version`.

  ## Examples

      iex> Git.Commands.Version.args(%Git.Commands.Version{})
      ["--version"]

  """
  @spec args(t()) :: [String.t()]
  @impl true
  def args(%__MODULE__{}), do: ["--version"]

  @doc """
  Parses the output of `git --version` into a `Git.Version` struct.

  On a non-zero exit code, returns `{:error, {stdout, exit_code}}`.
  """
  @spec parse_output(String.t(), non_neg_integer()) ::
          {:ok, Git.Version.t()} | {:error, {String.t(), non_neg_integer()}}
  @impl true
  def parse_output(stdout, 0), do: {:ok, Git.Version.parse(stdout)}
  def parse_output(stdout, exit_code), do: {:error, {stdout, exit_code}}
end
