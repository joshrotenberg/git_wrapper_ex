defmodule GitWrapper.Commands.Diff do
  @moduledoc """
  Implements the `GitWrapper.Command` behaviour for `git diff`.

  Supports working-tree diffs, staged (cached) diffs, stat-only output,
  comparing against a specific ref, and limiting to a path.
  """

  @behaviour GitWrapper.Command

  alias GitWrapper.Diff

  @type t :: %__MODULE__{
          staged: boolean(),
          stat: boolean(),
          ref: String.t() | nil,
          path: String.t() | nil
        }

  defstruct staged: false, stat: false, ref: nil, path: nil

  @doc """
  Returns the argument list for `git diff`.

  Options:
  - `:staged` — adds `--cached` to show staged changes
  - `:stat` — adds `--stat` for file-level summary instead of full patch
  - `:ref` — adds a ref to compare against (e.g., `"HEAD~1"`)
  - `:path` — adds `-- <path>` to limit the diff

  ## Examples

      iex> GitWrapper.Commands.Diff.args(%GitWrapper.Commands.Diff{})
      ["diff"]

      iex> GitWrapper.Commands.Diff.args(%GitWrapper.Commands.Diff{staged: true, stat: true})
      ["diff", "--cached", "--stat"]

      iex> GitWrapper.Commands.Diff.args(%GitWrapper.Commands.Diff{ref: "HEAD~1", path: "lib/"})
      ["diff", "HEAD~1", "--", "lib/"]

  """
  @spec args(t()) :: [String.t()]
  @impl true
  def args(%__MODULE__{} = command) do
    base = ["diff"]

    base
    |> maybe_add(command.staged, "--cached")
    |> maybe_add(command.stat, "--stat")
    |> maybe_add_ref(command.ref)
    |> maybe_add_path(command.path)
  end

  @doc """
  Parses the output of `git diff`.

  On success (exit code 0), returns `{:ok, %GitWrapper.Diff{}}`.
  On failure, returns `{:error, {stdout, exit_code}}`.
  """
  @spec parse_output(String.t(), non_neg_integer()) ::
          {:ok, Diff.t()} | {:error, {String.t(), non_neg_integer()}}
  @impl true
  def parse_output(stdout, 0), do: {:ok, Diff.parse(stdout)}

  def parse_output(stdout, exit_code), do: {:error, {stdout, exit_code}}

  defp maybe_add(args, true, flag), do: args ++ [flag]
  defp maybe_add(args, false, _flag), do: args

  defp maybe_add_ref(args, nil), do: args
  defp maybe_add_ref(args, ref), do: args ++ [ref]

  defp maybe_add_path(args, nil), do: args
  defp maybe_add_path(args, path), do: args ++ ["--", path]
end
