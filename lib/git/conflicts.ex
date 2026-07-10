defmodule Git.Conflicts do
  @moduledoc """
  Merge conflict detection and resolution helpers that compose `Git.status/1`
  and `Git.merge/2`.

  All functions accept an optional keyword list. Use `:config` to specify the
  repository via a `Git.Config` struct; when omitted a default config is built
  from the environment.
  """

  alias Git.{Config, ShowResult}

  # Unmerged status code combinations per git-status porcelain v1:
  # DD (both deleted), AU (added by us), UD (deleted by them),
  # UA (added by them), DU (deleted by us), AA (both added), UU (both modified)
  @unmerged_pairs MapSet.new([
                    {"D", "D"},
                    {"A", "U"},
                    {"U", "D"},
                    {"U", "A"},
                    {"D", "U"},
                    {"A", "A"},
                    {"U", "U"}
                  ])

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Checks whether the repository is in a conflicted state.

  Uses `Git.status/1` and inspects entries for unmerged status codes.

  Returns `{:ok, true}` when conflicts exist, `{:ok, false}` otherwise.

  ## Options

    * `:config` - a `Git.Config` struct

  ## Examples

      {:ok, false} = Git.Conflicts.detect()

  """
  @spec detect(keyword()) :: {:ok, boolean()} | {:error, term()}
  def detect(opts \\ []) do
    {config, _rest} = extract_config(opts)

    case Git.status(config: config) do
      {:ok, status} ->
        {:ok, Enum.any?(status.entries, &unmerged?/1)}

      error ->
        error
    end
  end

  @doc """
  Lists file paths that have merge conflicts.

  Uses `Git.status/1` and filters for entries with unmerged status codes.

  Returns `{:ok, [String.t()]}`.

  ## Options

    * `:config` - a `Git.Config` struct

  ## Examples

      {:ok, files} = Git.Conflicts.files()

  """
  @spec files(keyword()) :: {:ok, [String.t()]} | {:error, term()}
  def files(opts \\ []) do
    {config, _rest} = extract_config(opts)

    case Git.status(config: config) do
      {:ok, status} ->
        conflicted =
          status.entries
          |> Enum.filter(&unmerged?/1)
          |> Enum.map(& &1.path)

        {:ok, conflicted}

      error ->
        error
    end
  end

  @doc """
  Checks whether all conflicts have been resolved.

  This is the inverse of `detect/1` -- returns `{:ok, true}` when no unmerged
  files exist.

  ## Options

    * `:config` - a `Git.Config` struct

  ## Examples

      {:ok, true} = Git.Conflicts.resolved?()

  """
  @spec resolved?(keyword()) :: {:ok, boolean()} | {:error, term()}
  def resolved?(opts \\ []) do
    case detect(opts) do
      {:ok, conflicted} -> {:ok, not conflicted}
      error -> error
    end
  end

  @doc """
  Aborts an in-progress conflicted merge.

  Delegates to `Git.merge(:abort)`.

  ## Options

    * `:config` - a `Git.Config` struct

  ## Examples

      {:ok, :done} = Git.Conflicts.abort_merge()

  """
  @spec abort_merge(keyword()) :: {:ok, :done} | {:error, term()}
  def abort_merge(opts \\ []) do
    {config, _rest} = extract_config(opts)
    Git.merge(:abort, config: config)
  end

  @doc """
  Returns the base (merge stage 1) content of a conflicted path.

  Reads the common-ancestor version via `git show :1:<path>`. Returns
  `{:ok, content}` with the raw file content, or `{:error, _}` when stage 1
  does not exist (for example an add/add conflict has no common ancestor).

  ## Options

    * `:config` - a `Git.Config` struct

  ## Examples

      {:ok, content} = Git.Conflicts.base("shared.txt")

  """
  @spec base(String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def base(path, opts \\ []) when is_binary(path), do: show_stage(1, path, opts)

  @doc """
  Returns our (merge stage 2) content of a conflicted path.

  Reads our side via `git show :2:<path>`. Returns `{:ok, content}` with the
  raw file content, or `{:error, _}` when stage 2 does not exist.

  ## Options

    * `:config` - a `Git.Config` struct

  ## Examples

      {:ok, content} = Git.Conflicts.ours("shared.txt")

  """
  @spec ours(String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def ours(path, opts \\ []) when is_binary(path), do: show_stage(2, path, opts)

  @doc """
  Returns their (merge stage 3) content of a conflicted path.

  Reads the other side via `git show :3:<path>`. Returns `{:ok, content}` with
  the raw file content, or `{:error, _}` when stage 3 does not exist.

  ## Options

    * `:config` - a `Git.Config` struct

  ## Examples

      {:ok, content} = Git.Conflicts.theirs("shared.txt")

  """
  @spec theirs(String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def theirs(path, opts \\ []) when is_binary(path), do: show_stage(3, path, opts)

  @doc """
  Resolves conflicts by choosing our side, then stages the result.

  Delegates to `Git.restore(files: ..., ours: true)` to write our version into
  the working tree, then `Git.add/1` to collapse the merge stages and mark the
  path resolved. Accepts a single path or a list of paths.

  Returns `{:ok, :done}` on success.

  ## Options

    * `:config` - a `Git.Config` struct

  ## Examples

      {:ok, :done} = Git.Conflicts.take_ours("shared.txt")
      {:ok, :done} = Git.Conflicts.take_ours(["a.txt", "b.txt"])

  """
  @spec take_ours(String.t() | [String.t()], keyword()) :: {:ok, :done} | {:error, term()}
  def take_ours(paths, opts \\ []), do: take_side(:ours, paths, opts)

  @doc """
  Resolves conflicts by choosing their side, then stages the result.

  Delegates to `Git.restore(files: ..., theirs: true)` to write their version
  into the working tree, then `Git.add/1` to collapse the merge stages and mark
  the path resolved. Accepts a single path or a list of paths.

  Returns `{:ok, :done}` on success.

  ## Options

    * `:config` - a `Git.Config` struct

  ## Examples

      {:ok, :done} = Git.Conflicts.take_theirs("shared.txt")
      {:ok, :done} = Git.Conflicts.take_theirs(["a.txt", "b.txt"])

  """
  @spec take_theirs(String.t() | [String.t()], keyword()) :: {:ok, :done} | {:error, term()}
  def take_theirs(paths, opts \\ []), do: take_side(:theirs, paths, opts)

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp show_stage(stage, path, opts) do
    {config, _rest} = extract_config(opts)

    case Git.show(ref: ":#{stage}:#{path}", config: config) do
      {:ok, %ShowResult{raw: content}} -> {:ok, content}
      error -> error
    end
  end

  defp take_side(side, paths, opts) do
    {config, _rest} = extract_config(opts)
    files = List.wrap(paths)

    with {:ok, :done} <- Git.restore([{:files, files}, {side, true}, {:config, config}]) do
      Git.add(files: files, config: config)
    end
  end

  defp extract_config(opts) do
    Keyword.pop(opts, :config, Config.new())
  end

  defp unmerged?(%{index: index, working_tree: working_tree}) do
    MapSet.member?(@unmerged_pairs, {index, working_tree})
  end
end
