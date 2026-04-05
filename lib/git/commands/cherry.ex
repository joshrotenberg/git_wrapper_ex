defmodule Git.Commands.Cherry do
  @moduledoc """
  Implements the `Git.Command` behaviour for `git cherry`.

  Finds commits in the current branch (or `head`) that have not yet been
  applied to `upstream`. Each commit is marked with `+` (not applied) or
  `-` (already applied upstream, i.e. an equivalent patch exists).
  """

  @behaviour Git.Command

  alias Git.CherryEntry

  @type t :: %__MODULE__{
          upstream: String.t() | nil,
          head: String.t() | nil,
          limit: String.t() | nil,
          verbose: boolean()
        }

  defstruct upstream: nil,
            head: nil,
            limit: nil,
            verbose: false

  @doc """
  Builds the argument list for `git cherry`.

  ## Examples

      iex> Git.Commands.Cherry.args(%Git.Commands.Cherry{upstream: "main"})
      ["cherry", "main"]

      iex> Git.Commands.Cherry.args(%Git.Commands.Cherry{upstream: "main", verbose: true})
      ["cherry", "-v", "main"]

      iex> Git.Commands.Cherry.args(%Git.Commands.Cherry{upstream: "main", head: "feature"})
      ["cherry", "main", "feature"]

      iex> Git.Commands.Cherry.args(%Git.Commands.Cherry{upstream: "main", head: "feature", limit: "v1.0"})
      ["cherry", "main", "feature", "v1.0"]

  """
  @spec args(t()) :: [String.t()]
  @impl true
  def args(%__MODULE__{} = command) do
    base = ["cherry"]

    base
    |> maybe_add_flag(command.verbose, "-v")
    |> maybe_add_positional(command.upstream)
    |> maybe_add_positional(command.head)
    |> maybe_add_positional(command.limit)
  end

  @doc """
  Parses the output of `git cherry`.

  Returns `{:ok, [%Git.CherryEntry{}]}` on success (exit code 0).
  An empty output produces an empty list.
  """
  @spec parse_output(String.t(), non_neg_integer()) ::
          {:ok, [CherryEntry.t()]} | {:error, {String.t(), non_neg_integer()}}
  @impl true
  def parse_output(stdout, 0) do
    {:ok, CherryEntry.parse(stdout)}
  end

  def parse_output(stdout, exit_code), do: {:error, {stdout, exit_code}}

  defp maybe_add_flag(args, true, flag), do: args ++ [flag]
  defp maybe_add_flag(args, false, _flag), do: args

  defp maybe_add_positional(args, nil), do: args
  defp maybe_add_positional(args, value), do: args ++ [value]
end
