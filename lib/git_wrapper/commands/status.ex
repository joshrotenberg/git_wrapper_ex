defmodule GitWrapper.Commands.Status do
  @moduledoc """
  Implements the `GitWrapper.Command` behaviour for `git status`.

  Uses `--porcelain=v1 -b` for machine-readable output with branch information.
  """

  @behaviour GitWrapper.Command

  defstruct []

  @type t :: %__MODULE__{}

  @doc """
  Returns the argument list for `git status --porcelain=v1 -b`.
  """
  @spec args(t()) :: [String.t()]
  @impl true
  def args(%__MODULE__{}), do: ["status", "--porcelain=v1", "-b"]

  @doc """
  Parses the output of `git status --porcelain=v1 -b`.

  On success (exit code 0), returns `{:ok, %GitWrapper.Status{}}`.
  On failure, returns `{:error, {stdout, exit_code}}`.
  """
  @spec parse_output(String.t(), non_neg_integer()) ::
          {:ok, GitWrapper.Status.t()} | {:error, {String.t(), non_neg_integer()}}
  @impl true
  def parse_output(stdout, 0) do
    {:ok, GitWrapper.Status.parse(stdout)}
  end

  def parse_output(stdout, exit_code) do
    {:error, {stdout, exit_code}}
  end
end
