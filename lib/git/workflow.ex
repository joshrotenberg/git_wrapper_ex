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
      (default `true`). Like git's own `rebase.autostash`, only tracked changes
      are stashed; an untracked-only working tree is not stashed.
    * `:remote` - remote name (default `"origin"`)
    * `:branch` - branch to sync with (defaults to the upstream tracking branch)
    * `:config` - a `Git.Config` struct

  Returns `{:ok, :synced}` on success.

  When autostash is active and integration succeeds but popping the stash
  conflicts with the freshly integrated changes, returns
  `{:error, {:autostash_pop_failed, reason}}` (the working tree is left with the
  popped stash and its conflict markers) rather than reporting success over it.

  When integration itself fails (for example a rebase or merge conflict), the
  autostash is left in place; recover it with `git stash pop` after resolving
  the integration, since popping onto a mid-conflict tree would compound it.
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

    finish_sync(result, stashed, config_kw)
  end

  # On a successful integration, pop the autostash and surface a pop conflict as
  # an error rather than reporting {:ok, :synced} over a tree left with conflict
  # markers. On a failed integration, leave the autostash in place (popping onto
  # a mid-conflict tree would compound the problem).
  defp finish_sync({:error, _} = error, _stashed, _config_kw), do: error
  defp finish_sync({:ok, _}, false, _config_kw), do: {:ok, :synced}

  defp finish_sync({:ok, _}, true, config_kw) do
    case Git.stash(Keyword.merge(config_kw, pop: true)) do
      {:ok, _} -> {:ok, :synced}
      {:error, reason} -> {:error, {:autostash_pop_failed, reason}}
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

  @doc """
  Moves `HEAD` back by `:count` commits, returning the commits that were undone.

  This is the "I did not mean to commit that" helper. It captures the commits
  being undone first, then resets. `:mode` controls what happens to their
  changes:

    * `:soft` (default) - keep the changes staged
    * `:mixed` - keep the changes in the working tree, unstaged
    * `:hard` - discard the changes (irreversible beyond the reflog)

  ## Options

    * `:count` - number of commits to undo (default `1`)
    * `:mode` - `:soft` (default), `:mixed`, or `:hard`
    * `:config` - a `Git.Config` struct

  Returns `{:ok, undone_commits}` where `undone_commits` is the list of
  `Git.Commit` structs that were on top of the new `HEAD`, or
  `{:error, :cannot_undo_root}` when there is not enough history to move back
  that far (you cannot reset past the root commit).
  """
  @spec undo_last_commit(keyword()) :: {:ok, [Git.Commit.t()]} | {:error, term()}
  def undo_last_commit(opts \\ []) do
    {config_kw, rest} = Keyword.split(opts, [:config])
    count = Keyword.get(rest, :count, 1)
    mode = Keyword.get(rest, :mode, :soft)

    with {:ok, undone} <- undoable_commits(count, config_kw),
         {:ok, :done} <-
           Git.reset(Keyword.merge(config_kw, mode: mode, ref: "HEAD~#{count}")) do
      {:ok, undone}
    end
  end

  @doc """
  Collapses the last `count` commits on the current branch into a single new
  commit with `message`.

  Soft-resets to `HEAD~count` (keeping all their changes staged) and commits
  them as one. This is the only in-place squash in the library, since
  interactive rebase is intentionally not wrapped. `count` must be at least 2.

  Rewrites current-branch history; recover the originals from the reflog if
  needed.

  ## Options

    * `:config` - a `Git.Config` struct
    * All other options are forwarded to `Git.commit/2`.

  Returns `{:ok, commit_result}`, or `{:error, :cannot_undo_root}` when there
  are not enough commits to squash that many.
  """
  @spec squash_last(pos_integer(), String.t(), keyword()) ::
          {:ok, Git.CommitResult.t()} | {:error, term()}
  def squash_last(count, message, opts \\ [])
      when is_integer(count) and count >= 2 and is_binary(message) do
    {config_kw, rest} = Keyword.split(opts, [:config])

    with {:ok, _undone} <- undoable_commits(count, config_kw),
         {:ok, :done} <- Git.reset(Keyword.merge(config_kw, mode: :soft, ref: "HEAD~#{count}")) do
      Git.commit(message, Keyword.merge(config_kw, rest))
    end
  end

  @doc """
  Returns the working tree to a pristine committed state.

  Hard-resets tracked changes and removes untracked files and directories, so
  both halves of a dirty tree are cleared (a `reset --hard` leaves untracked
  files, a `clean` leaves tracked modifications; you need both).

  Destructive: discarded untracked and ignored files are not recoverable.
  Preview first with `dry_run: true`.

  ## Options

    * `:ignored` - also remove ignored files (`clean -x`, default `false`)
    * `:dry_run` - do not change anything; return the untracked/ignored files
      that would be removed (default `false`)
    * `:config` - a `Git.Config` struct

  Returns `{:ok, :discarded}` after clearing the tree, or
  `{:ok, {:dry_run, paths}}` when `:dry_run` is set.
  """
  @spec discard_all(keyword()) ::
          {:ok, :discarded} | {:ok, {:dry_run, [String.t()]}} | {:error, term()}
  def discard_all(opts \\ []) do
    {config_kw, rest} = Keyword.split(opts, [:config])
    ignored = Keyword.get(rest, :ignored, false)
    dry_run = Keyword.get(rest, :dry_run, false)

    discard(dry_run, ignored, config_kw)
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  # Needs count+1 commits so HEAD~count is a valid reset target; returns the top
  # `count` commits (the ones that will be moved off HEAD).
  defp undoable_commits(count, config_kw) do
    case Git.log(Keyword.merge(config_kw, max_count: count + 1)) do
      {:ok, commits} when length(commits) >= count + 1 -> {:ok, Enum.take(commits, count)}
      {:ok, _too_few} -> {:error, :cannot_undo_root}
      {:error, _} = error -> error
    end
  end

  defp discard(true, ignored, config_kw) do
    case Git.clean(Keyword.merge(config_kw, dry_run: true, directories: true, ignored: ignored)) do
      {:ok, paths} -> {:ok, {:dry_run, paths}}
      {:error, _} = error -> error
    end
  end

  defp discard(false, ignored, config_kw) do
    with {:ok, :done} <- Git.reset(Keyword.merge(config_kw, mode: :hard)),
         {:ok, _removed} <-
           Git.clean(Keyword.merge(config_kw, force: true, directories: true, ignored: ignored)) do
      {:ok, :discarded}
    end
  end

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
         true <- tracked_changes?(status),
         stash_opts = Keyword.merge(config_kw, save: true, message: "git_wrapper_ex autostash"),
         {:ok, :done} <- Git.stash(stash_opts) do
      true
    else
      _ -> false
    end
  end

  # Autostash mirrors git's `rebase.autostash`: only tracked changes are stashed.
  # An untracked-only working tree is not dirty for this purpose (a plain
  # `git stash` stashes nothing without --include-untracked), so treating it as
  # dirty previously produced a no-op stash and a later "no stash entries" pop.
  # An untracked entry is reported by `git status --porcelain` as `?` in the
  # index column.
  defp tracked_changes?(%{entries: entries}) do
    Enum.any?(entries, fn entry -> entry.index != "?" end)
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
