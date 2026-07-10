defmodule Git.Commands.ReadTree do
  @moduledoc """
  Implements the `Git.Command` behaviour for `git read-tree`.

  Loads tree contents into the index. It is the read side of the index/tree
  pipeline behind `commit_tree`: read a tree into the index, adjust it (for
  example with `update-index`), then `write-tree` it back out. `-m` does a
  two- or three-way merge of up to three trees in the index.
  """

  @behaviour Git.Command

  @type t :: %__MODULE__{
          trees: [String.t()],
          merge: boolean(),
          reset: boolean(),
          update: boolean(),
          prefix: String.t() | nil
        }

  defstruct trees: [], merge: false, reset: false, update: false, prefix: nil

  @doc """
  Returns the argument list for `git read-tree`.

  ## Examples

      iex> Git.Commands.ReadTree.args(%Git.Commands.ReadTree{trees: ["HEAD"]})
      ["read-tree", "HEAD"]

      iex> Git.Commands.ReadTree.args(%Git.Commands.ReadTree{trees: ["a", "b"], merge: true, update: true})
      ["read-tree", "-m", "-u", "a", "b"]

      iex> Git.Commands.ReadTree.args(%Git.Commands.ReadTree{trees: ["t"], prefix: "sub/"})
      ["read-tree", "--prefix=sub/", "t"]

  """
  @spec args(t()) :: [String.t()]
  @impl true
  def args(%__MODULE__{} = command) do
    ["read-tree"]
    |> maybe_add(command.merge, "-m")
    |> maybe_add(command.reset, "--reset")
    |> maybe_add(command.update, "-u")
    |> maybe_add_prefix(command.prefix)
    |> Kernel.++(command.trees)
  end

  @doc """
  Parses the output of `git read-tree`.

  On success (exit code 0), returns `{:ok, :done}`. On failure, returns
  `{:error, {stdout, exit_code}}`.
  """
  @spec parse_output(String.t(), non_neg_integer()) ::
          {:ok, :done} | {:error, {String.t(), non_neg_integer()}}
  @impl true
  def parse_output(_stdout, 0), do: {:ok, :done}
  def parse_output(stdout, exit_code), do: {:error, {stdout, exit_code}}

  defp maybe_add(args, true, flag), do: args ++ [flag]
  defp maybe_add(args, false, _flag), do: args

  defp maybe_add_prefix(args, nil), do: args
  defp maybe_add_prefix(args, prefix), do: args ++ ["--prefix=#{prefix}"]
end
