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
          numstat: boolean(),
          name_only: boolean(),
          name_status: boolean(),
          ignore_all_space: boolean(),
          ignore_space_change: boolean(),
          ignore_space_at_eol: boolean(),
          find_renames: boolean(),
          find_copies: boolean(),
          reverse: boolean(),
          unified: non_neg_integer() | nil,
          diff_filter: String.t() | nil,
          ref: String.t() | nil,
          ref_end: String.t() | nil,
          path: String.t() | nil
        }

  defstruct staged: false,
            stat: false,
            numstat: false,
            name_only: false,
            name_status: false,
            ignore_all_space: false,
            ignore_space_change: false,
            ignore_space_at_eol: false,
            find_renames: false,
            find_copies: false,
            reverse: false,
            unified: nil,
            diff_filter: nil,
            ref: nil,
            ref_end: nil,
            path: nil

  @doc """
  Returns the argument list for `git diff`.

  Options:
  - `:staged` — adds `--cached` to show staged changes
  - `:stat` — adds `--stat` for file-level summary instead of full patch
  - `:numstat` — adds `--numstat` for machine-readable per-file insertion and
    deletion counts (parsed into `files` with exact counts)
  - `:name_only` — adds `--name-only` for listing just file paths
  - `:name_status` — adds `--name-status` for file paths with status letters
  - `:ignore_all_space` — adds `-w`
  - `:ignore_space_change` — adds `-b`
  - `:ignore_space_at_eol` — adds `--ignore-space-at-eol`
  - `:find_renames` — adds `-M`
  - `:find_copies` — adds `-C`
  - `:reverse` — adds `-R` to swap the two sides
  - `:unified` — adds `-U<n>` to set the number of context lines
  - `:diff_filter` — adds `--diff-filter=<value>` (e.g. `"ACMR"`)
  - `:ref` — adds a ref to compare against (e.g., `"HEAD~1"`)
  - `:ref_end` — when set with `:ref`, compares `ref ref_end` (two-ref diff)
  - `:path` — adds `-- <path>` to limit the diff

  ## Examples

      iex> Git.Commands.Diff.args(%Git.Commands.Diff{})
      ["diff"]

      iex> Git.Commands.Diff.args(%Git.Commands.Diff{staged: true, stat: true})
      ["diff", "--cached", "--stat"]

      iex> Git.Commands.Diff.args(%Git.Commands.Diff{numstat: true, ignore_all_space: true})
      ["diff", "--numstat", "-w"]

      iex> Git.Commands.Diff.args(%Git.Commands.Diff{find_renames: true, unified: 0})
      ["diff", "-M", "-U0"]

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
    |> maybe_add(command.numstat, "--numstat")
    |> maybe_add(command.name_only, "--name-only")
    |> maybe_add(command.name_status, "--name-status")
    |> maybe_add(command.ignore_all_space, "-w")
    |> maybe_add(command.ignore_space_change, "-b")
    |> maybe_add(command.ignore_space_at_eol, "--ignore-space-at-eol")
    |> maybe_add(command.find_renames, "-M")
    |> maybe_add(command.find_copies, "-C")
    |> maybe_add(command.reverse, "-R")
    |> maybe_add_unified(command.unified)
    |> maybe_add_diff_filter(command.diff_filter)
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

  defp maybe_add_unified(args, nil), do: args
  defp maybe_add_unified(args, n) when is_integer(n), do: args ++ ["-U#{n}"]

  defp maybe_add_diff_filter(args, nil), do: args
  defp maybe_add_diff_filter(args, value), do: args ++ ["--diff-filter=#{value}"]

  defp maybe_add_ref(args, nil), do: args
  defp maybe_add_ref(args, ref), do: args ++ [ref]

  defp maybe_add_path(args, nil), do: args
  defp maybe_add_path(args, path), do: args ++ ["--", path]
end
