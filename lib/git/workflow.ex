defmodule Git.Workflow do
  @moduledoc """
  Composable helpers for common multi-step git workflows.

  Each function orchestrates several lower-level `Git` commands into a
  single logical operation. All functions accept a keyword list where the
  `:config` key, when present, must be a `Git.Config` struct and is
  forwarded to every underlying git invocation.

  ## Examples

      # Stage everything and commit in one call
      {:ok, result} = Git.Workflow.commit_all("feat: ship it", config: cfg)

      # Work on a feature branch, then return to the original branch
      {:ok, result} = Git.Workflow.feature_branch("feat/cool", fn opts ->
        File.write!("cool.txt", "cool")
        {:ok, :done} = Git.add(files: ["cool.txt"], config: opts[:config])
        {:ok, _} = Git.commit("feat: cool", Keyword.take(opts, [:config]))
        {:ok, :worked}
      end, merge: true, config: cfg)

  """

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Creates a feature branch, runs a function on it, and returns to the original
  branch.

  The function `fun` receives a keyword list containing the `:config` key
  (when one was provided in `opts`). It must return `{:ok, result}` or
  `{:error, reason}`.

  After `fun` completes (successfully or not), the original branch is checked
  out to ensure cleanup.

  ## Options

    * `:merge` - when `true`, merge the feature branch back into the original
      branch after `fun` succeeds (default `false`)
    * `:delete` - when `true`, delete the feature branch after a successful
      merge (default `false`; requires `:merge` to be `true`)
    * `:config` - a `Git.Config` struct

  Returns `{:ok, result}` where `result` is the return value of `fun`, or
  the merge result when `:merge` is `true`.
  """
  @spec feature_branch(String.t(), (keyword() -> {:ok, term()} | {:error, term()}), keyword()) ::
          {:ok, term()} | {:error, term()}
  def feature_branch(name, fun, opts \\ []) when is_binary(name) and is_function(fun, 1) do
    {config_kw, rest} = Keyword.split(opts, [:config])
    merge? = Keyword.get(rest, :merge, false)
    delete? = Keyword.get(rest, :delete, false)

    with {:ok, original_branch} <- Git.Branches.current(config_kw),
         {:ok, _checkout} <- Git.Branches.create_and_checkout(name, config_kw) do
      fun_result = run_on_branch(fun, config_kw, original_branch)
      finalize_feature_branch(fun_result, name, original_branch, merge?, delete?, config_kw)
    end
  end

  @doc """
  Fetches from a remote and integrates changes using rebase or merge.

  ## Options

    * `:strategy` - `:rebase` (default) or `:merge`
    * `:autostash` - stash uncommitted changes before syncing and pop after
      (default `true`)
    * `:remote` - remote name (default `"origin"`)
    * `:branch` - branch to sync with (defaults to the upstream tracking branch)
    * `:config` - a `Git.Config` struct

  Returns `{:ok, :synced}` on success.
  """
  @spec sync(keyword()) :: {:ok, :synced} | {:error, term()}
  def sync(opts \\ []) do
    {config_kw, rest} = Keyword.split(opts, [:config])
    strategy = Keyword.get(rest, :strategy, :rebase)
    autostash = Keyword.get(rest, :autostash, true)
    remote = Keyword.get(rest, :remote, "origin")
    branch = Keyword.get(rest, :branch)

    stashed = if autostash, do: stash_if_dirty(config_kw), else: false

    fetch_opts = Keyword.merge(config_kw, remote: remote)

    result =
      with {:ok, :done} <- Git.fetch(fetch_opts) do
        integrate(strategy, remote, branch, config_kw)
      end

    if stashed do
      Git.stash(Keyword.merge(config_kw, pop: true))
    end

    case result do
      {:ok, _} -> {:ok, :synced}
      {:error, _} = error -> error
    end
  end

  @doc """
  Merges a branch with `--squash` and commits with the given message.

  ## Options

    * `:message` - commit message (required)
    * `:delete` - when `true`, delete the source branch after merge
      (default `false`)
    * `:config` - a `Git.Config` struct

  Returns `{:ok, commit_result}` on success.
  """
  @spec squash_merge(String.t(), keyword()) :: {:ok, Git.CommitResult.t()} | {:error, term()}
  def squash_merge(branch, opts \\ []) when is_binary(branch) do
    {config_kw, rest} = Keyword.split(opts, [:config])
    message = Keyword.fetch!(rest, :message)
    delete? = Keyword.get(rest, :delete, false)

    with {:ok, _merge_result} <- Git.merge(branch, Keyword.merge(config_kw, squash: true)),
         {:ok, commit_result} <- Git.commit(message, config_kw) do
      if delete? do
        Git.branch(Keyword.merge(config_kw, delete: branch, force_delete: true))
      end

      {:ok, commit_result}
    end
  end

  @doc """
  Stages all changes and commits with the given message.

  Any additional keyword options (e.g., `:allow_empty`) are forwarded to
  `Git.commit/2`.

  ## Options

    * `:config` - a `Git.Config` struct
    * All other options are passed to `Git.commit/2`.

  Returns `{:ok, commit_result}` on success.
  """
  @spec commit_all(String.t(), keyword()) :: {:ok, Git.CommitResult.t()} | {:error, term()}
  def commit_all(message, opts \\ []) when is_binary(message) do
    {config_kw, rest} = Keyword.split(opts, [:config])

    with {:ok, :done} <- Git.add(Keyword.merge(config_kw, all: true)) do
      Git.commit(message, Keyword.merge(config_kw, rest))
    end
  end

  @doc """
  Amends the last commit.

  When no `:message` is provided, the existing commit message is reused.
  When `:all` is `true`, all changes are staged before amending.

  ## Options

    * `:message` - new commit message (default: reuse existing message)
    * `:all` - stage all changes before amending (default `false`)
    * `:config` - a `Git.Config` struct

  Returns `{:ok, commit_result}` on success.
  """
  @spec amend(keyword()) :: {:ok, Git.CommitResult.t()} | {:error, term()}
  def amend(opts \\ []) do
    {config_kw, rest} = Keyword.split(opts, [:config])
    message = Keyword.get(rest, :message)
    stage_all = Keyword.get(rest, :all, false)

    with :ok <- maybe_stage_all(stage_all, config_kw),
         {:ok, resolved_message} <- resolve_message(message, config_kw) do
      Git.commit(resolved_message, Keyword.merge(config_kw, amend: true))
    end
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp run_on_branch(fun, config_kw, original_branch) do
    case fun.(config_kw) do
      {:ok, _} = ok ->
        {:ok, _} = Git.checkout(Keyword.merge(config_kw, branch: original_branch))
        ok

      {:error, _} = error ->
        Git.checkout(Keyword.merge(config_kw, branch: original_branch))
        error
    end
  rescue
    e ->
      Git.checkout(Keyword.merge(config_kw, branch: original_branch))
      reraise e, __STACKTRACE__
  end

  defp finalize_feature_branch(
         {:ok, _result},
         name,
         _original,
         true = _merge?,
         delete?,
         config_kw
       ) do
    case Git.merge(name, config_kw) do
      {:ok, merge_result} ->
        if delete?, do: Git.branch(Keyword.merge(config_kw, delete: name))
        {:ok, merge_result}

      {:error, _} = error ->
        error
    end
  end

  defp finalize_feature_branch({:ok, result}, _name, _original, false, _delete?, _config_kw) do
    {:ok, result}
  end

  defp finalize_feature_branch({:error, _} = error, _name, _original, _merge?, _delete?, _cfg) do
    error
  end

  defp maybe_stage_all(true, config_kw) do
    case Git.add(Keyword.merge(config_kw, all: true)) do
      {:ok, :done} -> :ok
      {:error, _} = error -> error
    end
  end

  defp maybe_stage_all(false, _config_kw), do: :ok

  defp resolve_message(nil, config_kw) do
    case Git.log(Keyword.merge(config_kw, max_count: 1)) do
      {:ok, [commit | _]} -> {:ok, commit.subject}
      {:ok, []} -> {:error, :no_commits}
      {:error, _} = error -> error
    end
  end

  defp resolve_message(message, _config_kw) when is_binary(message), do: {:ok, message}

  defp stash_if_dirty(config_kw) do
    with {:ok, status} <- Git.status(config_kw),
         true <- status.entries != [],
         stash_opts = Keyword.merge(config_kw, save: true, message: "git_wrapper_ex autostash"),
         {:ok, :done} <- Git.stash(stash_opts) do
      true
    else
      _ -> false
    end
  end

  defp integrate(:rebase, remote, branch, config_kw) do
    upstream = if branch, do: "#{remote}/#{branch}", else: "#{remote}/HEAD"

    Git.rebase(Keyword.merge(config_kw, upstream: upstream))
  end

  defp integrate(:merge, remote, branch, config_kw) do
    upstream = if branch, do: "#{remote}/#{branch}", else: "#{remote}/HEAD"

    Git.merge(upstream, config_kw)
  end
end
