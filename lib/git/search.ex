defmodule Git.Search do
  @moduledoc """
  Higher-level search helpers that compose lower-level `Git` functions.

  Provides a unified interface for searching repository content, commit
  messages, change history, and tracked file names.

  All functions accept an optional keyword list. Use `:config` to specify the
  repository via a `Git.Config` struct; when omitted a default config is built
  from the environment.
  """

  alias Git.Config

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Searches tracked files for lines matching a pattern.

  Wraps `Git.grep/2` with a consistent interface.

  ## Options

  Accepts all options supported by `Git.grep/2`.

  ## Examples

      {:ok, results} = Git.Search.grep("defmodule")
      {:ok, results} = Git.Search.grep("TODO", ignore_case: true)

  """
  @spec grep(String.t(), keyword()) :: {:ok, [Git.GrepResult.t()]} | {:error, term()}
  def grep(pattern, opts \\ []) do
    Git.grep(pattern, opts)
  end

  @doc """
  Searches commit messages for a query string.

  Uses `git log --grep=<query>` under the hood.

  ## Options

    * `:config` - a `Git.Config` struct
    * `:author` - filter by author
    * `:since` - commits after this date
    * `:until_date` - commits before this date
    * `:max_count` - limit number of results
    * `:all_match` - require all patterns to match (`--all-match`)

  ## Examples

      {:ok, commits} = Git.Search.commits("fix bug")
      {:ok, commits} = Git.Search.commits("feat", author: "Alice")

  """
  @spec commits(String.t(), keyword()) :: {:ok, [Git.Commit.t()]} | {:error, term()}
  def commits(query, opts \\ []) do
    opts = Keyword.put(opts, :grep, query)
    Git.log(opts)
  end

  @doc """
  Finds commits that introduced or removed a string (pickaxe search).

  Uses `git log -S<pattern>` by default, or `git log -G<pattern>` when
  `:regex` is `true`.

  ## Options

    * `:config` - a `Git.Config` struct
    * `:regex` - use `-G` (regex) instead of `-S` (string match)
    * `:author` - filter by author
    * `:since` - commits after this date
    * `:until_date` - commits before this date
    * `:max_count` - limit number of results

  ## Examples

      {:ok, commits} = Git.Search.pickaxe("my_function")
      {:ok, commits} = Git.Search.pickaxe("def \\w+", regex: true)

  """
  @spec pickaxe(String.t(), keyword()) :: {:ok, [Git.Commit.t()]} | {:error, term()}
  def pickaxe(pattern, opts \\ []) do
    {regex, rest} = Keyword.pop(opts, :regex, false)

    rest =
      if regex do
        Keyword.put(rest, :pickaxe_regex, pattern)
      else
        Keyword.put(rest, :pickaxe, pattern)
      end

    Git.log(rest)
  end

  @doc """
  Finds tracked files matching a glob pattern.

  Uses `Git.ls_files/1` with the pattern passed as a path filter.

  ## Options

    * `:config` - a `Git.Config` struct

  ## Examples

      {:ok, files} = Git.Search.files("*.ex")
      {:ok, files} = Git.Search.files("lib/**/*.ex")

  """
  @spec files(String.t(), keyword()) :: {:ok, [String.t()]} | {:error, term()}
  def files(pattern, opts \\ []) do
    {config, _rest} = extract_config(opts)
    Git.ls_files(paths: [pattern], config: config)
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp extract_config(opts) do
    Keyword.pop(opts, :config, Config.new())
  end
end
