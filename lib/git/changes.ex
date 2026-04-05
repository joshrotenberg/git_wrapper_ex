defmodule Git.Changes do
  @moduledoc """
  Higher-level change analysis helpers that compose lower-level `Git` functions.

  Provides structured views of file changes between refs, uncommitted work,
  merge conflicts, and change summaries.

  All functions accept an optional keyword list. Use `:config` to specify the
  repository via a `Git.Config` struct; when omitted a default config is built
  from the environment.
  """

  alias Git.Config

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Returns structured file changes between two refs.

  Uses `git diff --name-status ref1 ref2` to get per-file status. Each entry
  is a map with `:status`, `:path`, and `:old_path` (non-nil for renames and
  copies).

  ## Options

    * `:config` - a `Git.Config` struct
    * `:stat` - when `true`, also includes line-level stats per file

  ## Examples

      {:ok, changes} = Git.Changes.between("v1.0.0", "v2.0.0")
      hd(changes).status  #=> :added
      hd(changes).path    #=> "lib/new_file.ex"

  """
  @spec between(String.t(), String.t(), keyword()) ::
          {:ok, [map()]} | {:error, term()}
  def between(ref1, ref2, opts \\ []) do
    {config, rest} = extract_config(opts)
    include_stat = Keyword.get(rest, :stat, false)

    case Git.diff(config: config, ref: ref1, ref_end: ref2, name_status: true) do
      {:ok, diff} ->
        files = parse_name_status(diff.raw)

        if include_stat do
          enrich_with_stats(files, ref1, ref2, config)
        else
          {:ok, files}
        end

      error ->
        error
    end
  end

  @doc """
  Returns structured info about all uncommitted changes.

  Groups status entries into `:staged` (files in the index), `:modified`
  (tracked files with working tree changes), and `:untracked` files.

  ## Options

    * `:config` - a `Git.Config` struct

  ## Examples

      {:ok, uncommitted} = Git.Changes.uncommitted()
      uncommitted.staged    #=> [%{path: "lib/foo.ex", status: :modified}]
      uncommitted.untracked #=> ["new_file.ex"]

  """
  @spec uncommitted(keyword()) :: {:ok, map()} | {:error, term()}
  def uncommitted(opts \\ []) do
    {config, _rest} = extract_config(opts)

    case Git.status(config: config) do
      {:ok, status} ->
        grouped = group_status_entries(status.entries)
        {:ok, grouped}

      error ->
        error
    end
  end

  @doc """
  Detects files with merge conflicts.

  Uses `git ls-files --unmerged` to reliably detect conflicted files, then
  deduplicates paths since each conflicted file appears multiple times in
  the unmerged listing.

  ## Options

    * `:config` - a `Git.Config` struct

  ## Examples

      {:ok, conflicts} = Git.Changes.conflicts()
      conflicts  #=> ["lib/conflicted.ex"]

  """
  @spec conflicts(keyword()) :: {:ok, [String.t()]} | {:error, term()}
  def conflicts(opts \\ []) do
    {config, _rest} = extract_config(opts)

    case Git.ls_files(config: config, unmerged: true) do
      {:ok, files} ->
        # Unmerged output includes stage info: "<mode> <hash> <stage>\t<path>"
        # Extract just the paths and deduplicate.
        paths =
          files
          |> Enum.map(&extract_unmerged_path/1)
          |> Enum.uniq()

        {:ok, paths}

      error ->
        error
    end
  end

  @doc """
  Returns a one-call summary of changes between two refs.

  Includes the number of files changed, total insertions and deletions,
  and per-file details.

  ## Options

    * `:config` - a `Git.Config` struct

  ## Examples

      {:ok, summary} = Git.Changes.summary("v1.0.0", "v2.0.0")
      summary.files_changed  #=> 3
      summary.insertions     #=> 42
      summary.deletions      #=> 10

  """
  @spec summary(String.t(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def summary(ref1, ref2, opts \\ []) do
    {config, _rest} = extract_config(opts)

    with {:ok, diff} <- Git.diff(config: config, ref: ref1, ref_end: ref2, stat: true),
         {:ok, files} <- between(ref1, ref2, config: config) do
      {:ok,
       %{
         files_changed: length(files),
         insertions: diff.total_insertions,
         deletions: diff.total_deletions,
         files: files
       }}
    end
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp extract_config(opts) do
    Keyword.pop(opts, :config, Config.new())
  end

  @status_map %{
    "A" => :added,
    "M" => :modified,
    "D" => :deleted,
    "R" => :renamed,
    "C" => :copied
  }

  defp parse_name_status(raw) do
    raw
    |> String.split("\n", trim: true)
    |> Enum.map(&parse_name_status_line/1)
    |> Enum.reject(&is_nil/1)
  end

  defp parse_name_status_line(line) do
    line = String.trim(line)

    case String.split(line, "\t") do
      [status_code, old_path, new_path] ->
        letter = String.at(status_code, 0)

        %{
          status: Map.get(@status_map, letter, :unknown),
          path: new_path,
          old_path: old_path
        }

      [status_code, path] ->
        letter = String.at(status_code, 0)

        %{
          status: Map.get(@status_map, letter, :unknown),
          path: path,
          old_path: nil
        }

      _ ->
        nil
    end
  end

  defp enrich_with_stats(files, ref1, ref2, config) do
    case Git.diff(config: config, ref: ref1, ref_end: ref2, stat: true) do
      {:ok, diff} ->
        stat_map = build_stat_map(diff.files)
        {:ok, Enum.map(files, &merge_stats(&1, stat_map))}

      error ->
        error
    end
  end

  defp build_stat_map(diff_files) do
    Map.new(diff_files, fn f ->
      {f.path, %{insertions: f.insertions, deletions: f.deletions}}
    end)
  end

  defp merge_stats(file, stat_map) do
    case Map.get(stat_map, file.path) do
      nil -> file
      stats -> Map.merge(file, stats)
    end
  end

  defp group_status_entries(entries) do
    staged = extract_staged(entries)
    modified = extract_modified(entries)
    untracked = extract_untracked(entries)

    %{staged: staged, modified: modified, untracked: untracked}
  end

  defp extract_staged(entries) do
    entries
    |> Enum.filter(&staged_entry?/1)
    |> Enum.map(fn e -> %{path: e.path, status: status_atom(e.index)} end)
  end

  defp extract_modified(entries) do
    entries
    |> Enum.filter(fn e -> e.working_tree == "M" end)
    |> Enum.map(fn e -> %{path: e.path, status: status_atom(e.working_tree)} end)
  end

  defp extract_untracked(entries) do
    entries
    |> Enum.filter(fn e -> e.index == "?" and e.working_tree == "?" end)
    |> Enum.map(& &1.path)
  end

  defp staged_entry?(%{index: index}) when index in [" ", "?"], do: false
  defp staged_entry?(_entry), do: true

  @index_status_map %{
    "M" => :modified,
    "A" => :added,
    "D" => :deleted,
    "R" => :renamed,
    "C" => :copied
  }

  defp status_atom(code), do: Map.get(@index_status_map, code, :unknown)

  defp extract_unmerged_path(line) do
    # ls-files --unmerged output: "<mode> <hash> <stage>\t<path>"
    case String.split(line, "\t", parts: 2) do
      [_info, path] -> String.trim(path)
      _ -> String.trim(line)
    end
  end
end
