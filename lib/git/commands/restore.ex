defmodule Git.Commands.Restore do
  @moduledoc """
  Implements the `Git.Command` behaviour for `git restore`.

  `git restore` is the modern (Git 2.23+) command for restoring working tree
  files, replacing the file-restoration role of `git checkout`. It provides
  explicit control over restoring from the index (staged) vs a source commit.
  """

  @behaviour Git.Command

  @type t :: %__MODULE__{
          files: [String.t()],
          staged: boolean(),
          worktree: boolean(),
          source: String.t() | nil,
          ours: boolean(),
          theirs: boolean(),
          patch: boolean()
        }

  defstruct files: [],
            staged: false,
            worktree: false,
            source: nil,
            ours: false,
            theirs: false,
            patch: false

  @doc """
  Returns the argument list for `git restore`.

  ## Examples

      iex> Git.Commands.Restore.args(%Git.Commands.Restore{files: ["README.md"]})
      ["restore", "README.md"]

      iex> Git.Commands.Restore.args(%Git.Commands.Restore{files: ["lib/foo.ex"], staged: true})
      ["restore", "--staged", "lib/foo.ex"]

      iex> Git.Commands.Restore.args(%Git.Commands.Restore{files: ["lib/foo.ex"], source: "HEAD~1"})
      ["restore", "--source", "HEAD~1", "lib/foo.ex"]

  """
  @spec args(t()) :: [String.t()]
  @impl true
  def args(%__MODULE__{} = cmd) do
    ["restore"] ++ build_flags(cmd) ++ cmd.files
  end

  defp build_flags(%__MODULE__{} = cmd) do
    []
    |> maybe_add(cmd.staged, "--staged")
    |> maybe_add(cmd.worktree, "--worktree")
    |> maybe_add_value(cmd.source, "--source")
    |> maybe_add(cmd.ours, "--ours")
    |> maybe_add(cmd.theirs, "--theirs")
    |> maybe_add(cmd.patch, "--patch")
  end

  defp maybe_add(list, true, flag), do: list ++ [flag]
  defp maybe_add(list, _, _flag), do: list

  defp maybe_add_value(list, nil, _flag), do: list
  defp maybe_add_value(list, value, flag), do: list ++ [flag, value]

  @doc """
  Parses the output of `git restore`.

  `git restore` produces no stdout on success (exit 0), so we return `{:ok, :done}`.
  """
  @spec parse_output(String.t(), non_neg_integer()) ::
          {:ok, :done} | {:error, {String.t(), non_neg_integer()}}
  @impl true
  def parse_output(_stdout, 0), do: {:ok, :done}
  def parse_output(stdout, exit_code), do: {:error, {stdout, exit_code}}
end
