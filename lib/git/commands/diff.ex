defmodule Git.Commands.Diff do
  @moduledoc """
  Implements the `Git.Command` behaviour for `git diff`.

  Supports working-tree diffs, staged (cached) diffs, stat-only output,
  comparing against a specific ref, and limiting to a path.
  """

  @behaviour Git.Command

  alias Git.Diff

  @type t :: %__MODULE__{
          staged: boolean(),
          stat: boolean(),
          name_only: boolean(),
          name_status: boolean(),
          ref: String.t() | nil,
          ref_end: String.t() | nil,
          path: String.t() | nil
        }

  defstruct staged: false,
            stat: false,
            name_only: false,
            name_status: false,
            ref: nil,
            ref_end: nil,
            path: nil

  @doc """
  Returns the argument list for `git diff`.

  Options:
  - `:staged` — adds `--cached` to show staged changes
  - `:stat` — adds `--stat` for file-level summary instead of full patch
  - `:name_only` — adds `--name-only` for listing just file paths
  - `:name_status` — adds `--name-status` for file paths with status letters
  - `:ref` — adds a ref to compare against (e.g., `"HEAD~1"`)
  - `:ref_end` — when set with `:ref`, compares `ref ref_end` (two-ref diff)
  - `:path` — adds `-- <path>` to limit the diff

  ## Examples

      iex> Git.Commands.Diff.args(%Git.Commands.Diff{})
      ["diff"]

      iex> Git.Commands.Diff.args(%Git.Commands.Diff{staged: true, stat: true})
      ["diff", "--cached", "--stat"]

      iex> Git.Commands.Diff.args(%Git.Commands.Diff{ref: "HEAD~1", path: "lib/"})
      ["diff", "HEAD~1", "--", "lib/"]

  """
  @spec args(t()) :: [String.t()]
  @impl true
  def args(%__MODULE__{} = command) do
    base = ["diff"]

    base
    |> maybe_add(command.staged, "--cached")
    |> maybe_add(command.stat, "--stat")
    |> maybe_add(command.name_only, "--name-only")
    |> maybe_add(command.name_status, "--name-status")
    |> maybe_add_ref(command.ref)
    |> maybe_add_ref(command.ref_end)
    |> maybe_add_path(command.path)
  end

  @doc """
  Parses the output of `git diff`.

  On success (exit code 0), returns `{:ok, %Git.Diff{}}`.
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
