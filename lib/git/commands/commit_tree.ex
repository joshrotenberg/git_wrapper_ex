defmodule Git.Commands.CommitTree do
  @moduledoc """
  Implements the `Git.Command` behaviour for `git commit-tree`.

  Builds a commit object directly from a tree object, with zero or
  more parents, a message, and optional GPG signing. Returns the new
  commit's SHA.

  Unlike `git commit`, this is a plumbing command: it does not touch
  the index, working tree, or HEAD. It is the building block for
  free-floating commits, e.g. commits attached only to a non-branch
  ref with no presence on any branch.
  """

  @behaviour Git.Command

  @enforce_keys [:tree]

  @type t :: %__MODULE__{
          tree: String.t(),
          parents: [String.t()],
          message: String.t() | nil,
          messages: [String.t()],
          sign: boolean() | String.t(),
          no_gpg_sign: boolean()
        }

  defstruct [
    :tree,
    parents: [],
    message: nil,
    messages: [],
    sign: false,
    no_gpg_sign: false
  ]

  @doc """
  Returns the argument list for `git commit-tree`.

  ## Examples

      iex> Git.Commands.CommitTree.args(%Git.Commands.CommitTree{tree: "abc123", message: "init"})
      ["commit-tree", "-m", "init", "abc123"]

      iex> Git.Commands.CommitTree.args(%Git.Commands.CommitTree{tree: "abc123", parents: ["def456"], message: "next"})
      ["commit-tree", "-p", "def456", "-m", "next", "abc123"]

      iex> Git.Commands.CommitTree.args(%Git.Commands.CommitTree{tree: "abc123", parents: ["a", "b"], message: "merge"})
      ["commit-tree", "-p", "a", "-p", "b", "-m", "merge", "abc123"]

      iex> Git.Commands.CommitTree.args(%Git.Commands.CommitTree{tree: "abc123", message: "x", sign: true})
      ["commit-tree", "-S", "-m", "x", "abc123"]

      iex> Git.Commands.CommitTree.args(%Git.Commands.CommitTree{tree: "abc123", message: "x", sign: "ABCD1234"})
      ["commit-tree", "-SABCD1234", "-m", "x", "abc123"]

      iex> Git.Commands.CommitTree.args(%Git.Commands.CommitTree{tree: "abc123", message: "x", no_gpg_sign: true})
      ["commit-tree", "--no-gpg-sign", "-m", "x", "abc123"]

      iex> Git.Commands.CommitTree.args(%Git.Commands.CommitTree{tree: "abc123", messages: ["subject", "body"]})
      ["commit-tree", "-m", "subject", "-m", "body", "abc123"]

      iex> Git.Commands.CommitTree.args(%Git.Commands.CommitTree{tree: "abc123", message: "subject", messages: ["body"]})
      ["commit-tree", "-m", "subject", "-m", "body", "abc123"]

  """
  @spec args(t()) :: [String.t()]
  @impl true
  def args(%__MODULE__{tree: tree} = command) when is_binary(tree) do
    ["commit-tree"]
    |> add_parents(command.parents)
    |> add_sign(command.sign)
    |> maybe_add_flag(command.no_gpg_sign, "--no-gpg-sign")
    |> add_messages(command.message, command.messages)
    |> Kernel.++([tree])
  end

  @doc """
  Parses the output of `git commit-tree`.

  On success (exit code 0), returns `{:ok, sha}` where sha is the
  trimmed SHA of the new commit. On failure, returns
  `{:error, {stdout, exit_code}}`.
  """
  @spec parse_output(String.t(), non_neg_integer()) ::
          {:ok, String.t()} | {:error, {String.t(), non_neg_integer()}}
  @impl true
  def parse_output(stdout, 0), do: {:ok, String.trim(stdout)}
  def parse_output(stdout, exit_code), do: {:error, {stdout, exit_code}}

  defp add_parents(args, []), do: args

  defp add_parents(args, parents) when is_list(parents) do
    args ++ Enum.flat_map(parents, fn p -> ["-p", p] end)
  end

  defp add_sign(args, false), do: args
  defp add_sign(args, true), do: args ++ ["-S"]
  defp add_sign(args, keyid) when is_binary(keyid), do: args ++ ["-S" <> keyid]

  defp add_messages(args, nil, []), do: args

  defp add_messages(args, message, []) when is_binary(message) do
    args ++ ["-m", message]
  end

  defp add_messages(args, nil, messages) when is_list(messages) do
    args ++ Enum.flat_map(messages, fn m -> ["-m", m] end)
  end

  defp add_messages(args, message, messages)
       when is_binary(message) and is_list(messages) do
    args ++ ["-m", message] ++ Enum.flat_map(messages, fn m -> ["-m", m] end)
  end

  defp maybe_add_flag(args, true, flag), do: args ++ [flag]
  defp maybe_add_flag(args, false, _flag), do: args
end
