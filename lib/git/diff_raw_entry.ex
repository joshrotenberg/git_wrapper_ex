defmodule Git.DiffRawEntry do
  @moduledoc """
  A single record from git's raw diff format, as produced by
  `git diff-tree`, `git diff-index`, and `git diff-files` with `--raw -z`.

  Each record describes one changed path:

      :<old_mode> <new_mode> <old_sha> <new_sha> <status>\\0<path>\\0

  `status` is a single letter for the common cases:

    * `"A"` - added
    * `"D"` - deleted
    * `"M"` - modified
    * `"T"` - type changed (e.g. file to symlink)

  For renames (`R`) and copies (`C`) git appends a similarity score to the
  status letter (e.g. `"R100"`) and emits a SECOND NUL-terminated path. In that
  case `status` holds the raw token including the score, and `path` holds the
  destination (new) path. The source path is not retained in this struct.

  `old_sha` / `new_sha` are all-zero when the corresponding side does not exist
  (for example `old_sha` is zeroed for an added file).
  """

  @type t :: %__MODULE__{
          old_mode: String.t(),
          new_mode: String.t(),
          old_sha: String.t(),
          new_sha: String.t(),
          status: String.t(),
          path: String.t()
        }

  defstruct [:old_mode, :new_mode, :old_sha, :new_sha, :status, :path]

  @doc """
  Parses NUL-delimited raw diff output into a list of `Git.DiffRawEntry` structs.

  Any leading token that is not a metadata record is skipped. This handles the
  bare commit-id header (a SHA followed by NUL) that single-argument
  `git diff-tree` emits before its records.

  Combined-diff records (merge output prefixed with `::`) do not match the
  expected five-field shape and are skipped rather than mis-parsed.

  Returns `[]` for empty input.
  """
  @spec parse(String.t()) :: [t()]
  def parse(""), do: []

  def parse(stdout) do
    stdout
    |> String.split("\0")
    |> take_entries([])
    |> Enum.reverse()
  end

  # A trailing empty token (or an exhausted stream) ends parsing.
  defp take_entries([], acc), do: acc
  defp take_entries(["" | _rest], acc), do: acc

  defp take_entries([token | rest], acc) do
    case parse_meta(token) do
      {:ok, meta} -> consume_paths(meta, rest, acc)
      :skip -> take_entries(rest, acc)
    end
  end

  # meta is {old_mode, new_mode, old_sha, new_sha, status}. Rename/copy records
  # carry a source and a destination path; all other records carry one path.
  defp consume_paths({om, nm, os, ns, status}, rest, acc) do
    if rename_or_copy?(status) do
      case rest do
        [_src, dest | rest2] ->
          take_entries(rest2, [build(om, nm, os, ns, status, dest) | acc])

        _ ->
          acc
      end
    else
      case rest do
        [path | rest2] ->
          take_entries(rest2, [build(om, nm, os, ns, status, path) | acc])

        _ ->
          acc
      end
    end
  end

  defp parse_meta(":" <> rest) do
    case String.split(rest) do
      [om, nm, os, ns, status] -> {:ok, {om, nm, os, ns, status}}
      _ -> :skip
    end
  end

  defp parse_meta(_token), do: :skip

  defp rename_or_copy?(status) do
    String.starts_with?(status, "R") or String.starts_with?(status, "C")
  end

  defp build(old_mode, new_mode, old_sha, new_sha, status, path) do
    %__MODULE__{
      old_mode: old_mode,
      new_mode: new_mode,
      old_sha: old_sha,
      new_sha: new_sha,
      status: status,
      path: path
    }
  end
end
