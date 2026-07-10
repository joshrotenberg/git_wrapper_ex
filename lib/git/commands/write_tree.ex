defmodule Git.Commands.WriteTree do
  @moduledoc """
  Implements the `Git.Command` behaviour for `git write-tree`.

  Records the current index as a tree object and returns its SHA. This is the
  plumbing counterpart to `Git.Commands.CommitTree`: `write-tree` produces the
  tree SHA that `commit-tree` turns into a commit, so together they build a
  commit without touching HEAD or the working tree.
  """

  @behaviour Git.Command

  @type t :: %__MODULE__{
          prefix: String.t() | nil,
          missing_ok: boolean()
        }

  defstruct prefix: nil, missing_ok: false

  @doc """
  Returns the argument list for `git write-tree`.

  ## Examples

      iex> Git.Commands.WriteTree.args(%Git.Commands.WriteTree{})
      ["write-tree"]

      iex> Git.Commands.WriteTree.args(%Git.Commands.WriteTree{prefix: "lib"})
      ["write-tree", "--prefix=lib"]

      iex> Git.Commands.WriteTree.args(%Git.Commands.WriteTree{missing_ok: true})
      ["write-tree", "--missing-ok"]

  """
  @spec args(t()) :: [String.t()]
  @impl true
  def args(%__MODULE__{} = command) do
    ["write-tree"]
    |> maybe_add("--prefix=#{command.prefix}", not is_nil(command.prefix))
    |> maybe_add("--missing-ok", command.missing_ok)
  end

  @doc """
  Parses the output of `git write-tree`.

  On success (exit code 0), returns `{:ok, sha}` with the trimmed tree SHA.
  On failure, returns `{:error, {stdout, exit_code}}`.
  """
  @spec parse_output(String.t(), non_neg_integer()) ::
          {:ok, String.t()} | {:error, {String.t(), non_neg_integer()}}
  @impl true
  def parse_output(stdout, 0), do: {:ok, String.trim(stdout)}
  def parse_output(stdout, exit_code), do: {:error, {stdout, exit_code}}

  defp maybe_add(args, _flag, false), do: args
  defp maybe_add(args, flag, true), do: args ++ [flag]
end
