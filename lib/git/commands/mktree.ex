defmodule Git.Commands.MkTree do
  @moduledoc """
  Implements the `Git.Command` behaviour for `git mktree`.

  Builds a tree object from `ls-tree`-formatted entries fed on stdin and returns
  its SHA, with no index or working tree. Together with `hash_object` and
  `commit_tree` this lets a consumer synthesize whole trees and commits purely
  from object SHAs (for example generated-content commits).

  Reads stdin, so it needs the default `Git.Runner.Forcola` runner; under
  `Git.Runner.SystemCmd` it returns `{:error, :stdin_unsupported}`.
  """

  @behaviour Git.Command

  @type entry :: %{mode: String.t(), type: String.t(), object: String.t(), path: String.t()}

  @type t :: %__MODULE__{
          entries: [entry()],
          missing: boolean()
        }

  defstruct entries: [], missing: false

  @doc """
  Returns the argument list for `git mktree`.

  ## Examples

      iex> Git.Commands.MkTree.args(%Git.Commands.MkTree{})
      ["mktree"]

      iex> Git.Commands.MkTree.args(%Git.Commands.MkTree{missing: true})
      ["mktree", "--missing"]

  """
  @spec args(t()) :: [String.t()]
  @impl true
  def args(%__MODULE__{missing: true}), do: ["mktree", "--missing"]
  def args(%__MODULE__{missing: false}), do: ["mktree"]

  @doc """
  Formats the entries for `git mktree`'s stdin as `<mode> <type> <object>\\t<path>`
  lines. Empty entries feed empty stdin, which produces the empty tree.
  """
  @spec input(t()) :: iodata()
  @impl true
  def input(%__MODULE__{entries: []}), do: ""

  def input(%__MODULE__{entries: entries}) do
    Enum.map_join(entries, "\n", fn entry ->
      "#{entry.mode} #{entry.type} #{entry.object}\t#{entry.path}"
    end) <> "\n"
  end

  @doc """
  Parses the output of `git mktree`.

  On success (exit code 0), returns `{:ok, sha}` with the trimmed tree SHA. On
  failure, returns `{:error, {stdout, exit_code}}`.
  """
  @spec parse_output(String.t(), non_neg_integer()) ::
          {:ok, String.t()} | {:error, {String.t(), non_neg_integer()}}
  @impl true
  def parse_output(stdout, 0), do: {:ok, String.trim(stdout)}
  def parse_output(stdout, exit_code), do: {:error, {stdout, exit_code}}
end
