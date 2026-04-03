defmodule GitWrapper.Commands.Init do
  @moduledoc """
  Implements the `GitWrapper.Command` behaviour for `git init`.

  Supports initializing a new repository at an optional path, with an optional
  `--bare` flag for creating a bare repository.
  """

  @behaviour GitWrapper.Command

  @type t :: %__MODULE__{
          path: String.t() | nil,
          bare: boolean()
        }

  defstruct path: nil, bare: false

  @doc """
  Returns the argument list for `git init`.

  When `:bare` is `true`, passes `--bare`. When `:path` is set, appends it
  as the final argument.

  ## Examples

      iex> GitWrapper.Commands.Init.args(%GitWrapper.Commands.Init{})
      ["init"]

      iex> GitWrapper.Commands.Init.args(%GitWrapper.Commands.Init{bare: true})
      ["init", "--bare"]

      iex> GitWrapper.Commands.Init.args(%GitWrapper.Commands.Init{path: "/tmp/repo"})
      ["init", "/tmp/repo"]

      iex> GitWrapper.Commands.Init.args(%GitWrapper.Commands.Init{bare: true, path: "/tmp/repo.git"})
      ["init", "--bare", "/tmp/repo.git"]

  """
  @spec args(t()) :: [String.t()]
  @impl true
  def args(%__MODULE__{bare: bare, path: path}) do
    base = ["init"]
    base = if bare, do: base ++ ["--bare"], else: base
    if path, do: base ++ [path], else: base
  end

  @doc """
  Parses the output of `git init`.

  On success (exit code 0), returns `{:ok, :done}`. On failure, returns
  `{:error, {stdout, exit_code}}`.
  """
  @spec parse_output(String.t(), non_neg_integer()) ::
          {:ok, :done} | {:error, {String.t(), non_neg_integer()}}
  @impl true
  def parse_output(_stdout, 0), do: {:ok, :done}

  def parse_output(stdout, exit_code), do: {:error, {stdout, exit_code}}
end
