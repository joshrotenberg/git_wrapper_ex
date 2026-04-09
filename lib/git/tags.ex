defmodule Git.Tags do
  @moduledoc """
  Higher-level tag management helpers that compose lower-level `Git` functions.

  Provides convenience functions for creating, listing, sorting, and querying
  tags.

  All functions accept an optional keyword list. Use `:config` to specify the
  repository via a `Git.Config` struct; when omitted a default config is built
  from the environment.
  """

  alias Git.Config

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Creates a tag.

  Delegates to `Git.tag/1` with the `:create` option. Supports `:message`
  for annotated tags and `:ref` for tagging a specific commit.

  ## Options

    * `:message` - annotation message (creates an annotated tag)
    * `:ref` - commit to tag (default: HEAD)
    * `:config` - a `Git.Config` struct

  Returns `{:ok, :done}` on success.
  """
  @spec create(String.t(), keyword()) :: {:ok, :done} | {:error, term()}
  def create(name, opts \\ []) do
    {config, rest} = extract_config(opts)
    tag_opts = [{:create, name}, {:config, config} | rest]
    Git.tag(tag_opts)
  end

  @doc """
  Lists all tags with detailed information.

  Delegates to `Git.tag/1` with no create/delete options.

  Returns `{:ok, [Git.Tag.t()]}`.
  """
  @spec list(keyword()) :: {:ok, [Git.Tag.t()]} | {:error, term()}
  def list(opts \\ []) do
    {config, _rest} = extract_config(opts)
    Git.tag(config: config)
  end

  @doc """
  Returns the most recent tag reachable from HEAD.

  Uses `Git.describe(tags: true, abbrev: 0)` to find the latest tag.

  Returns `{:ok, String.t()}` with the tag name, or `{:error, term()}` if
  no tags exist.
  """
  @spec latest(keyword()) :: {:ok, String.t()} | {:error, term()}
  def latest(opts \\ []) do
    {config, _rest} = extract_config(opts)
    Git.describe(tags: true, abbrev: 0, config: config)
  end

  @doc """
  Returns tags sorted by semantic version.

  Lists all tags, then sorts them using `Version.parse/1` where possible.
  Tags that are not valid semver are sorted lexicographically and placed
  after the versioned tags.

  Returns `{:ok, [Git.Tag.t()]}`.
  """
  @spec sorted(keyword()) :: {:ok, [Git.Tag.t()]} | {:error, term()}
  def sorted(opts \\ []) do
    {config, _rest} = extract_config(opts)

    case Git.tag(config: config) do
      {:ok, tags} ->
        {:ok, sort_by_version(tags)}

      error ->
        error
    end
  end

  @doc """
  Deletes a tag.

  Delegates to `Git.tag(delete: name)`.

  Returns `{:ok, :done}` on success.
  """
  @spec delete(String.t(), keyword()) :: {:ok, :done} | {:error, term()}
  def delete(name, opts \\ []) do
    {config, _rest} = extract_config(opts)
    Git.tag(delete: name, config: config)
  end

  @doc """
  Checks whether a tag exists.

  Lists all tags and checks if the given name is present.

  Returns `{:ok, true}` or `{:ok, false}`.
  """
  @spec exists?(String.t(), keyword()) :: {:ok, boolean()} | {:error, term()}
  def exists?(name, opts \\ []) do
    {config, _rest} = extract_config(opts)

    case Git.tag(config: config) do
      {:ok, tags} ->
        {:ok, Enum.any?(tags, fn tag -> tag.name == name end)}

      error ->
        error
    end
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp extract_config(opts) do
    Keyword.pop(opts, :config, Config.new())
  end

  defp sort_by_version(tags) do
    {versioned, non_versioned} =
      Enum.split_with(tags, fn tag ->
        tag.name
        |> strip_v_prefix()
        |> Version.parse()
        |> case do
          {:ok, _} -> true
          :error -> false
        end
      end)

    sorted_versioned =
      Enum.sort_by(versioned, fn tag ->
        {:ok, version} = tag.name |> strip_v_prefix() |> Version.parse()
        version
      end)

    sorted_non_versioned = Enum.sort_by(non_versioned, & &1.name)

    sorted_versioned ++ sorted_non_versioned
  end

  defp strip_v_prefix("v" <> rest), do: rest
  defp strip_v_prefix(name), do: name
end
