defmodule Git.Commands.MergeTree do
  @moduledoc """
  Implements the `Git.Command` behaviour for `git merge-tree --write-tree`.

  Performs a three-way merge of two commits entirely in the object database
  and returns the resulting tree SHA plus the list of conflicted paths, with no
  checkout, index, or working tree involvement. This answers "do these two
  branches merge cleanly, and what conflicts?" for CI mergeability checks and
  server-side merges.

  Requires git 2.38 or newer (the `--write-tree` mode). Always passes
  `--name-only`, so conflicts are reported as plain paths.
  """

  @behaviour Git.Command

  alias Git.MergeTreeResult

  @enforce_keys [:branch1, :branch2]

  @type t :: %__MODULE__{
          branch1: String.t(),
          branch2: String.t()
        }

  defstruct [:branch1, :branch2]

  @doc """
  Returns the argument list for `git merge-tree`.

  ## Examples

      iex> Git.Commands.MergeTree.args(%Git.Commands.MergeTree{branch1: "main", branch2: "feature"})
      ["merge-tree", "--write-tree", "--name-only", "main", "feature"]

  """
  @spec args(t()) :: [String.t()]
  @impl true
  def args(%__MODULE__{branch1: branch1, branch2: branch2})
      when is_binary(branch1) and is_binary(branch2) do
    ["merge-tree", "--write-tree", "--name-only", branch1, branch2]
  end

  @doc """
  Parses the output of `git merge-tree --write-tree --name-only`.

  Exit code 0 is a clean merge and exit code 1 is a merge with conflicts (a
  signal, not a failure); both return `{:ok, %Git.MergeTreeResult{}}`. Any other
  case is a real error and returns `{:error, {stdout, exit_code}}`.

  git also exits 1 for a bad ref ("not something we can merge"), which is not a
  conflict, so exit 1 is only treated as a conflict when the first output line
  is a valid object id; otherwise it is surfaced as an error.

  The first output line is always the merged tree SHA. On a conflict, the lines
  between it and the first blank line are the conflicted paths.
  """
  @spec parse_output(String.t(), non_neg_integer()) ::
          {:ok, MergeTreeResult.t()} | {:error, {String.t(), non_neg_integer()}}
  @impl true
  def parse_output(stdout, 0) do
    {tree, _conflicts} = split_output(stdout)
    {:ok, %MergeTreeResult{tree: tree, clean: true, conflicts: []}}
  end

  def parse_output(stdout, 1) do
    {tree, conflicts} = split_output(stdout)

    if valid_oid?(tree) do
      {:ok, %MergeTreeResult{tree: tree, clean: false, conflicts: conflicts}}
    else
      {:error, {stdout, 1}}
    end
  end

  def parse_output(stdout, exit_code), do: {:error, {stdout, exit_code}}

  defp split_output(stdout) do
    case String.split(stdout, "\n") do
      [tree | rest] -> {String.trim(tree), Enum.take_while(rest, &(&1 != ""))}
      [] -> {"", []}
    end
  end

  # A SHA-1 (40) or SHA-256 (64) object id in lowercase hex.
  defp valid_oid?(line), do: line =~ ~r/^[0-9a-f]{40}$|^[0-9a-f]{64}$/
end
