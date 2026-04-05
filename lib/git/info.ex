defmodule Git.Info do
  @moduledoc """
  One-call repository introspection helpers that compose lower-level `Git` functions.

  Provides convenient summaries of repository state, HEAD information, and
  remote details without requiring multiple manual calls.

  All functions accept an optional keyword list. Use `:config` to specify the
  repository via a `Git.Config` struct; when omitted a default config is built
  from the environment.
  """

  alias Git.Config

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Returns a comprehensive repository overview.

  Composes status, rev-parse, remote, and log to produce a single map
  describing the current state of the repository.

  ## Options

    * `:config` - a `Git.Config` struct

  ## Examples

      {:ok, info} = Git.Info.summary()
      info.branch    #=> "main"
      info.dirty     #=> false
      info.ahead     #=> 0

  """
  @spec summary(keyword()) :: {:ok, map()} | {:error, term()}
  def summary(opts \\ []) do
    {config, _rest} = extract_config(opts)

    with {:ok, status} <- Git.status(config: config),
         {:ok, sha} <- get_head_sha(config),
         {:ok, remote_info} <- get_primary_remote(config),
         {:ok, last_commit} <- get_last_commit(config) do
      {:ok,
       %{
         branch: status.branch,
         commit: sha,
         dirty: status.entries != [],
         ahead: status.ahead,
         behind: status.behind,
         staged: count_staged(status.entries),
         modified: count_modified(status.entries),
         untracked: count_untracked(status.entries),
         remote: remote_info.name,
         remote_url: remote_info.url,
         last_commit_subject: last_commit.subject,
         last_commit_date: last_commit.date
       }}
    end
  end

  @doc """
  Returns current HEAD information.

  Includes the branch name, full SHA, and whether HEAD is detached.

  ## Options

    * `:config` - a `Git.Config` struct

  ## Examples

      {:ok, head} = Git.Info.head()
      head.branch   #=> "main"
      head.detached #=> false

  """
  @spec head(keyword()) :: {:ok, map()} | {:error, term()}
  def head(opts \\ []) do
    {config, _rest} = extract_config(opts)

    with {:ok, sha} <- Git.rev_parse(ref: "HEAD", config: config),
         {:ok, branch_name} <- Git.rev_parse(abbrev_ref: true, ref: "HEAD", config: config) do
      detached = branch_name == "HEAD"

      {:ok,
       %{
         branch: if(detached, do: nil, else: branch_name),
         sha: sha,
         detached: detached
       }}
    end
  end

  @doc """
  Returns whether the repository has any uncommitted changes.

  Checks for staged, modified, or untracked files.

  ## Options

    * `:config` - a `Git.Config` struct

  ## Examples

      {:ok, false} = Git.Info.dirty?()

  """
  @spec dirty?(keyword()) :: {:ok, boolean()} | {:error, term()}
  def dirty?(opts \\ []) do
    {config, _rest} = extract_config(opts)

    case Git.status(config: config) do
      {:ok, status} -> {:ok, status.entries != []}
      error -> error
    end
  end

  @doc """
  Returns the repository root path.

  Wraps `git rev-parse --show-toplevel`.

  ## Options

    * `:config` - a `Git.Config` struct

  ## Examples

      {:ok, "/home/user/project"} = Git.Info.root()

  """
  @spec root(keyword()) :: {:ok, String.t()} | {:error, term()}
  def root(opts \\ []) do
    {config, _rest} = extract_config(opts)
    Git.rev_parse(show_toplevel: true, config: config)
  end

  @doc """
  Returns enriched remote information.

  Lists all remotes with their fetch and push URLs via `git remote -v`.

  ## Options

    * `:config` - a `Git.Config` struct

  ## Examples

      {:ok, remotes} = Git.Info.remotes_detailed()
      hd(remotes).name       #=> "origin"
      hd(remotes).fetch_url  #=> "https://github.com/owner/repo.git"

  """
  @spec remotes_detailed(keyword()) ::
          {:ok, [%{name: String.t(), fetch_url: String.t(), push_url: String.t()}]}
          | {:error, term()}
  def remotes_detailed(opts \\ []) do
    {config, _rest} = extract_config(opts)

    case Git.remote(verbose: true, config: config) do
      {:ok, remotes} ->
        detailed =
          Enum.map(remotes, fn r ->
            %{name: r.name, fetch_url: r.fetch_url, push_url: r.push_url}
          end)

        {:ok, detailed}

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

  defp get_head_sha(config) do
    case Git.rev_parse(ref: "HEAD", config: config) do
      {:ok, sha} -> {:ok, sha}
      {:error, _} -> {:ok, nil}
    end
  end

  defp get_primary_remote(config) do
    case Git.remote(verbose: true, config: config) do
      {:ok, [first | _]} ->
        {:ok, %{name: first.name, url: first.fetch_url}}

      {:ok, []} ->
        {:ok, %{name: nil, url: nil}}

      {:error, _} ->
        {:ok, %{name: nil, url: nil}}
    end
  end

  defp get_last_commit(config) do
    case Git.log(max_count: 1, config: config) do
      {:ok, [commit | _]} ->
        {:ok, %{subject: commit.subject, date: commit.date}}

      {:ok, []} ->
        {:ok, %{subject: nil, date: nil}}

      {:error, _} ->
        {:ok, %{subject: nil, date: nil}}
    end
  end

  defp count_staged(entries) do
    Enum.count(entries, fn e -> e.index not in [" ", "?"] end)
  end

  defp count_modified(entries) do
    Enum.count(entries, fn e -> e.working_tree == "M" end)
  end

  defp count_untracked(entries) do
    Enum.count(entries, fn e -> e.index == "?" and e.working_tree == "?" end)
  end
end
