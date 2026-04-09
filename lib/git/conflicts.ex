defmodule Git.Conflicts do
  @moduledoc """
  Merge conflict detection and resolution helpers that compose `Git.status/1`
  and `Git.merge/2`.

  All functions accept an optional keyword list. Use `:config` to specify the
  repository via a `Git.Config` struct; when omitted a default config is built
  from the environment.
  """

  alias Git.Config

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

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp extract_config(opts) do
    Keyword.pop(opts, :config, Config.new())
  end

  defp unmerged?(%{index: index, working_tree: working_tree}) do
    MapSet.member?(@unmerged_pairs, {index, working_tree})
  end
end
