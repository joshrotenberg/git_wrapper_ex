defmodule Git.Commands.Init do
  @moduledoc """
  Implements the `Git.Command` behaviour for `git init`.

  Supports initializing a new repository at an optional path, with optional
  `--bare` and `--initial-branch` options.
  """

  @behaviour Git.Command

  @type t :: %__MODULE__{
          path: String.t() | nil,
          bare: boolean(),
          initial_branch: String.t() | nil
        }

  defstruct path: nil, bare: false, initial_branch: nil

  @doc """
  Returns the argument list for `git init`.

  When `:bare` is `true`, passes `--bare`. When `:initial_branch` is set,
  passes `--initial-branch=<name>` (useful because CI runners often have no
  `init.defaultBranch` configured). When `:path` is set, appends it as the
  final argument.

  ## Examples

      iex> Git.Commands.Init.args(%Git.Commands.Init{})
      ["init"]

      iex> Git.Commands.Init.args(%Git.Commands.Init{bare: true})
      ["init", "--bare"]

      iex> Git.Commands.Init.args(%Git.Commands.Init{initial_branch: "main"})
      ["init", "--initial-branch=main"]

      iex> Git.Commands.Init.args(%Git.Commands.Init{path: "/tmp/repo"})
      ["init", "/tmp/repo"]

      iex> Git.Commands.Init.args(%Git.Commands.Init{bare: true, initial_branch: "main", path: "/tmp/repo.git"})
      ["init", "--bare", "--initial-branch=main", "/tmp/repo.git"]

  """
  @spec args(t()) :: [String.t()]
  @impl true
  def args(%__MODULE__{} = command) do
    ["init"]
    |> maybe_add_flag(command.bare, "--bare")
    |> maybe_add_initial_branch(command.initial_branch)
    |> maybe_add_path(command.path)
  end

  defp maybe_add_flag(args, true, flag), do: args ++ [flag]
  defp maybe_add_flag(args, false, _flag), do: args

  defp maybe_add_initial_branch(args, nil), do: args
  defp maybe_add_initial_branch(args, branch), do: args ++ ["--initial-branch=#{branch}"]

  defp maybe_add_path(args, nil), do: args
  defp maybe_add_path(args, path), do: args ++ [path]

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
