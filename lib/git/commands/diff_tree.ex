defmodule Git.Commands.DiffTree do
  @moduledoc """
  Implements the `Git.Command` behaviour for `git diff-tree`.

  Compares the content and mode of blobs found via two tree-ish arguments,
  or (with a single tree-ish) a commit against its first parent. Output is
  requested with `--raw -z` and parsed into `Git.DiffRawEntry` structs.
  """

  @behaviour Git.Command

  alias Git.DiffRawEntry

  @type t :: %__MODULE__{
          tree_ish: String.t(),
          tree_ish2: String.t() | nil,
          recursive: boolean(),
          find_renames: boolean()
        }

  defstruct tree_ish: "HEAD",
            tree_ish2: nil,
            recursive: false,
            find_renames: false

  @doc """
  Returns the argument list for `git diff-tree`.

  Options:
  - `:tree_ish` - the first (or only) tree-ish to diff (default `"HEAD"`)
  - `:tree_ish2` - a second tree-ish; when set, diffs `tree_ish tree_ish2`
  - `:recursive` - adds `-r` to recurse into subtrees (default `false`)
  - `:find_renames` - adds `-M` to detect renames (default `false`)

  ## Examples

      iex> Git.Commands.DiffTree.args(%Git.Commands.DiffTree{})
      ["diff-tree", "--raw", "-z", "HEAD"]

      iex> Git.Commands.DiffTree.args(%Git.Commands.DiffTree{recursive: true})
      ["diff-tree", "--raw", "-z", "-r", "HEAD"]

      iex> Git.Commands.DiffTree.args(%Git.Commands.DiffTree{tree_ish: "HEAD~1", tree_ish2: "HEAD", recursive: true})
      ["diff-tree", "--raw", "-z", "-r", "HEAD~1", "HEAD"]

      iex> Git.Commands.DiffTree.args(%Git.Commands.DiffTree{find_renames: true, recursive: true})
      ["diff-tree", "--raw", "-z", "-r", "-M", "HEAD"]

  """
  @spec args(t()) :: [String.t()]
  @impl true
  def args(%__MODULE__{} = command) do
    ["diff-tree", "--raw", "-z"]
    |> maybe_add_flag(command.recursive, "-r")
    |> maybe_add_flag(command.find_renames, "-M")
    |> append_tree_ish(command.tree_ish)
    |> append_tree_ish(command.tree_ish2)
  end

  @doc """
  Parses the output of `git diff-tree --raw -z`.

  On success (exit code 0), returns `{:ok, [Git.DiffRawEntry.t()]}`.
  On failure, returns `{:error, {stdout, exit_code}}`.
  """
  @spec parse_output(String.t(), non_neg_integer()) ::
          {:ok, [DiffRawEntry.t()]} | {:error, {String.t(), non_neg_integer()}}
  @impl true
  def parse_output(stdout, 0), do: {:ok, DiffRawEntry.parse(stdout)}

  def parse_output(stdout, exit_code), do: {:error, {stdout, exit_code}}

  defp maybe_add_flag(args, true, flag), do: args ++ [flag]
  defp maybe_add_flag(args, false, _flag), do: args

  defp append_tree_ish(args, nil), do: args
  defp append_tree_ish(args, tree_ish), do: args ++ [tree_ish]
end
