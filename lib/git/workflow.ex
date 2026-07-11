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

  Returns `{:ok, commit_result}` on success. When `:delete` is requested but
  the source branch cannot be deleted (for example it is still checked out in a
  worktree), returns `{:error, {:branch_not_deleted, reason}}` rather than
  reporting success over a branch that still exists. The squash commit itself
  has already landed at that point.
  """
  @spec squash_merge(String.t(), keyword()) :: {:ok, Git.CommitResult.t()} | {:error, term()}
  def squash_merge(branch, opts \\ []) when is_binary(branch) do
    {config_kw, rest} = Keyword.split(opts, [:config])
    message = Keyword.fetch!(rest, :message)
    delete? = Keyword.get(rest, :delete, false)

    with {:ok, _merge_result} <- Git.merge(branch, Keyword.merge(config_kw, squash: true)),
         {:ok, commit_result} <- Git.commit(message, config_kw),
         :ok <- delete_source_branch(branch, delete?, config_kw) do
      {:ok, commit_result}
    end
  end

  # Deletes the merged source branch when requested. `git branch -D` fails when
  # the branch is checked out in a worktree; surface that as an error instead of
  # discarding it and reporting success over a branch that still exists.
  defp delete_source_branch(_branch, false, _config_kw), do: :ok

  defp delete_source_branch(branch, true, config_kw) do
    case Git.branch(Keyword.merge(config_kw, delete: branch, force_delete: true)) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, {:branch_not_deleted, reason}}
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

  @typedoc "A workflow step: a 1-arity function receiving the config keyword list."
  @type step :: (keyword() -> {:ok, term()} | {:error, term()})

  @typedoc "A step, optionally labeled so a failure can name it."
  @type labeled_step :: step() | {atom(), step()}

  @doc """
  Runs a list of steps in order, threading `:config` into each and
  short-circuiting on the first `{:error, _}`.

  Each step is a 1-arity function receiving the config keyword list (the same
  contract as `feature_branch/3`'s function), or a `{name, fun}` tuple. With a
  tuple, a failure is reported as `{:error, {name, reason}}`; otherwise the raw
  `{:error, reason}` is returned. Returns the last step's `{:ok, result}`; an
  empty list returns `{:ok, nil}`.

  Steps do not receive each other's results. Prefer a plain `with` for a fixed
  sequence or when a later step needs an earlier step's output; reach for
  `chain/2` when the step list is built at runtime.

  ## Examples

      [
        {:stage, fn o -> Git.add(Keyword.merge(o, all: true)) end},
        {:commit, fn o -> Git.commit("chore: release", o) end}
      ]
      |> Git.Workflow.chain(config: cfg)

  """
  @spec chain([labeled_step()], keyword()) :: {:ok, term()} | {:error, term()}
  def chain(steps, opts \\ []) when is_list(steps) do
    {config_kw, _rest} = Keyword.split(opts, [:config])

    Enum.reduce_while(steps, {:ok, nil}, fn step, _acc ->
      {name, fun} = normalize_step(step)

      case fun.(config_kw) do
        {:ok, _} = ok -> {:cont, ok}
        {:error, reason} -> {:halt, tag_error(name, reason)}
      end
    end)
  end

  @doc """
  Checks out `ref`, runs `fun` on it, then restores the original branch.

  The original branch is restored even if `fun` raises. Pass `create: true` to
  create the branch first. Returns `fun`'s result. This is the reusable bracket
  underneath `feature_branch/3`.

  ## Options

    * `:create` - create `ref` as a new branch before running (default `false`)
    * `:config` - a `Git.Config` struct

  """
  @spec with_branch(String.t(), step(), keyword()) :: {:ok, term()} | {:error, term()}
  def with_branch(ref, fun, opts \\ []) when is_binary(ref) and is_function(fun, 1) do
    {config_kw, rest} = Keyword.split(opts, [:config])
    create? = Keyword.get(rest, :create, false)

    with {:ok, original} <- Git.Branches.current(config_kw),
         {:ok, _} <- checkout_ref(ref, create?, config_kw) do
      bracket(
        fn -> fun.(config_kw) end,
        fn -> Git.checkout(Keyword.merge(config_kw, branch: original)) end
      )
    end
  end

  @doc """
  Stashes uncommitted tracked changes (only if the tree is dirty), runs `fun`,
  then pops the stash.

  The stash is popped even if `fun` raises. Returns `fun`'s result. A pop that
  fails (for example a conflict) is surfaced as the error rather than hidden.
  This is the `:autostash` behavior of `sync/1`, made reusable.

  ## Options

    * `:config` - a `Git.Config` struct

  """
  @spec with_stash(step(), keyword()) :: {:ok, term()} | {:error, term()}
  def with_stash(fun, opts \\ []) when is_function(fun, 1) do
    {config_kw, _rest} = Keyword.split(opts, [:config])
    stashed? = stash_if_dirty(config_kw)

    bracket(
      fn -> fun.(config_kw) end,
      fn -> if stashed?, do: Git.stash(Keyword.merge(config_kw, pop: true)) end
    )
  end

  @doc """
  Merges `branch` into the current branch, cleaning up on conflict.

  Runs `Git.merge/2`. A conflict (or any merge failure) leaves the working tree
  mid-merge, so this aborts it with `Git.merge(:abort, ...)` before returning the
  original `{:error, reason}`. The abort is best-effort: when the failure left no
  merge to abort, the abort's own error is ignored and the original merge error
  is still returned.

  Extra options (for example `:no_ff` or `:strategy`) are forwarded to the merge.

  ## Options

    * `:config` - a `Git.Config` struct
    * All other options are forwarded to `Git.merge/2`.

  Returns `{:ok, %Git.MergeResult{}}` on a clean merge.
  """
  @spec try_merge(String.t(), keyword()) :: {:ok, Git.MergeResult.t()} | {:error, term()}
  def try_merge(branch, opts \\ []) when is_binary(branch) do
    {config_kw, rest} = Keyword.split(opts, [:config])

    case Git.merge(branch, Keyword.merge(config_kw, rest)) do
      {:ok, _} = ok ->
        ok

      {:error, _} = error ->
        Git.merge(:abort, config_kw)
        error
    end
  end

  @doc """
  Rebases onto an upstream, cleaning up on conflict.

  Runs `Git.rebase/1` with `:upstream` (and optional `:onto`) taken from `opts`.
  A conflict (or any rebase failure) leaves the rebase in progress, so this
  aborts it with `Git.rebase(abort: true, ...)` before returning the original
  `{:error, reason}`. The abort is best-effort.

  ## Options

    * `:upstream` - the upstream ref to rebase onto
    * `:onto` - rebase onto this ref instead of the upstream's base
    * `:config` - a `Git.Config` struct

  Returns `{:ok, %Git.RebaseResult{}}` on a clean rebase.
  """
  @spec safe_rebase(keyword()) :: {:ok, Git.RebaseResult.t()} | {:error, term()}
  def safe_rebase(opts \\ []) do
    {config_kw, rest} = Keyword.split(opts, [:config])
    rebase_opts = Keyword.take(rest, [:upstream, :onto])

    case Git.rebase(Keyword.merge(config_kw, rebase_opts)) do
      {:ok, _} = ok ->
        ok

      {:error, _} = error ->
        Git.rebase(Keyword.merge(config_kw, abort: true))
        error
    end
  end

  @doc """
  Creates an annotated release tag and, optionally, pushes it.

  Refuses to clobber an existing tag: when `version` already exists the tag is
  left untouched and `{:error, {:tag_exists, version}}` is returned. Publishing
  is opt-in, so nothing is pushed unless `:push` is `true`.

  ## Options

    * `:message` - annotation message (default: `version`)
    * `:sign` - create a GPG-signed tag (`-s`, default `false`)
    * `:ref` - commit to tag (default `"HEAD"`)
    * `:push` - push the tag after creating it (default `false`)
    * `:remote` - remote to push the tag to (default `"origin"`)
    * `:config` - a `Git.Config` struct

  Returns `{:ok, version}` once the tag exists (and, with `:push`, is pushed).
  """
  @spec release(String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def release(version, opts \\ []) when is_binary(version) do
    {config_kw, rest} = Keyword.split(opts, [:config])
    message = Keyword.get(rest, :message, version)
    sign? = Keyword.get(rest, :sign, false)
    ref = Keyword.get(rest, :ref, "HEAD")
    push? = Keyword.get(rest, :push, false)
    remote = Keyword.get(rest, :remote, "origin")

    tag_opts = Keyword.merge(config_kw, create: version, message: message, ref: ref)
    tag_opts = if sign?, do: Keyword.put(tag_opts, :sign, sign?), else: tag_opts

    with :ok <- ensure_tag_absent(version, config_kw),
         {:ok, :done} <- Git.tag(tag_opts),
         {:ok, _} <- maybe_push_branch(push?, remote, version, config_kw) do
      {:ok, version}
    end
  end

  @doc """
  Pushes the current branch to a remote, setting its upstream.

  Runs `git push -u <remote> <current-branch>`. With `:force`, uses
  `--force-with-lease` rather than a plain push, so a remote that moved on is not
  overwritten blindly.

  ## Options

    * `:remote` - remote to push to (default `"origin"`)
    * `:force` - force with lease (default `false`)
    * `:config` - a `Git.Config` struct

  Returns `{:ok, :done}` on success.
  """
  @spec publish(keyword()) :: {:ok, :done} | {:error, term()}
  def publish(opts \\ []) do
    {config_kw, rest} = Keyword.split(opts, [:config])
    remote = Keyword.get(rest, :remote, "origin")
    force? = Keyword.get(rest, :force, false)

    with {:ok, current} <- Git.Branches.current(config_kw) do
      push_opts =
        config_kw
        |> Keyword.merge(set_upstream: true, remote: remote, branch: current)
        |> maybe_force_with_lease(force?)

      Git.push(push_opts)
    end
  end

  @doc """
  Syncs a fork: fetches the upstream and integrates it into the current branch.

  Fetches `:upstream`, then fast-forwards the current branch onto
  `<upstream>/<branch>` (a `--ff-only` merge, the default) or rebases onto it
  when `strategy: :rebase`. With `:push`, the result is pushed to `:origin`.

  ## Options

    * `:upstream` - remote to sync from (default `"upstream"`)
    * `:origin` - remote to push to when `:push` (default `"origin"`)
    * `:branch` - branch to track on the upstream (default: the current branch)
    * `:strategy` - `:merge` (fast-forward only, default) or `:rebase`
    * `:push` - push to `:origin` after integrating (default `false`)
    * `:config` - a `Git.Config` struct

  Returns `{:ok, :synced}` on success.
  """
  @spec sync_fork(keyword()) :: {:ok, :synced} | {:error, term()}
  def sync_fork(opts \\ []) do
    {config_kw, rest} = Keyword.split(opts, [:config])
    upstream = Keyword.get(rest, :upstream, "upstream")
    origin = Keyword.get(rest, :origin, "origin")
    strategy = Keyword.get(rest, :strategy, :merge)
    push? = Keyword.get(rest, :push, false)

    with {:ok, branch} <- resolve_branch(Keyword.get(rest, :branch), config_kw),
         {:ok, :done} <- Git.fetch(Keyword.merge(config_kw, remote: upstream)),
         {:ok, _} <- integrate_fork(strategy, "#{upstream}/#{branch}", config_kw),
         {:ok, _} <- maybe_push_branch(push?, origin, branch, config_kw) do
      {:ok, :synced}
    end
  end

  @doc """
  Cherry-picks commits onto another branch, then returns to where you started.

  `commits` is a single sha/ref or a list of them, applied in order. The current
  branch is remembered, `:target` is checked out (created from `:base` when
  given), and the commits are cherry-picked. On a conflict the cherry-pick is
  aborted; the original branch is always restored afterward, even if a step
  raises. With `:push`, the target is pushed to `:remote` after a clean pick.

  ## Options

    * `:target` - branch to apply the commits on (required)
    * `:base` - create `:target` from this ref first (default: `:target` must exist)
    * `:push` - push `:target` to `:remote` after a clean pick (default `false`)
    * `:remote` - remote to push to (default `"origin"`)
    * `:config` - a `Git.Config` struct

  Returns `{:ok, %Git.CherryPickResult{}}` on success, or the error.
  """
  @spec backport(String.t() | [String.t()], keyword()) ::
          {:ok, Git.CherryPickResult.t()} | {:error, term()}
  def backport(commits, opts \\ []) do
    {config_kw, rest} = Keyword.split(opts, [:config])
    commits = List.wrap(commits)
    target = Keyword.fetch!(rest, :target)
    base = Keyword.get(rest, :base)
    push? = Keyword.get(rest, :push, false)
    remote = Keyword.get(rest, :remote, "origin")

    with {:ok, original} <- Git.Branches.current(config_kw),
         {:ok, _} <- checkout_target(target, base, config_kw) do
      bracket(
        fn -> do_backport(commits, push?, remote, target, config_kw) end,
        fn -> Git.checkout(Keyword.merge(config_kw, branch: original)) end
      )
    end
  end

  @doc """
  Recreates a deleted branch.

  With `:sha`, simply creates `name` at that commit. Otherwise scans the reflog
  for the last commit `name` pointed at (the value HEAD held just before the
  branch was last left) and recreates it there, or returns
  `{:error, :not_found}` when the reflog has no record of the branch. Pass
  `checkout: true` to switch to the restored branch.

  ## Options

    * `:sha` - recreate the branch at this commit instead of consulting the reflog
    * `:checkout` - check the branch out after recreating it (default `false`)
    * `:config` - a `Git.Config` struct

  Returns `{:ok, sha}` with the commit the branch was recreated at.
  """
  @spec restore_branch(String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def restore_branch(name, opts \\ []) when is_binary(name) do
    {config_kw, rest} = Keyword.split(opts, [:config])
    checkout? = Keyword.get(rest, :checkout, false)

    with {:ok, sha} <- resolve_restore_sha(Keyword.get(rest, :sha), name, config_kw),
         {:ok, _} <- Git.branch(Keyword.merge(config_kw, create: name, start_point: sha)),
         {:ok, _} <- maybe_checkout_restored(checkout?, name, config_kw) do
      {:ok, sha}
    end
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp normalize_step({name, fun}) when is_atom(name) and is_function(fun, 1), do: {name, fun}
  defp normalize_step(fun) when is_function(fun, 1), do: {nil, fun}

  defp tag_error(nil, reason), do: {:error, reason}
  defp tag_error(name, reason), do: {:error, {name, reason}}

  defp checkout_ref(ref, true, config_kw), do: Git.Branches.create_and_checkout(ref, config_kw)

  defp checkout_ref(ref, false, config_kw),
    do: Git.checkout(Keyword.merge(config_kw, branch: ref))

  # Runs body, then always runs cleanup (even on a raise). On the ok path a
  # cleanup failure is surfaced rather than dropped; on the error/raise path the
  # original result/exception wins and cleanup is best-effort.
  defp bracket(body, cleanup) do
    result = body.()

    case {result, cleanup.()} do
      {{:ok, _} = ok, {:error, _} = cleanup_error} -> keep_cleanup_error(ok, cleanup_error)
      {result, _} -> result
    end
  rescue
    e ->
      cleanup.()
      reraise e, __STACKTRACE__
  end

  defp keep_cleanup_error(_ok, cleanup_error), do: cleanup_error

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

  defp ensure_tag_absent(version, config_kw) do
    case Git.Tags.exists?(version, config_kw) do
      {:ok, true} -> {:error, {:tag_exists, version}}
      {:ok, false} -> :ok
      {:error, _} = error -> error
    end
  end

  # Pushes `ref` (a branch or tag name) to `remote`, or reports it was skipped
  # when publishing was not requested. Shared by `release/2`, `sync_fork/1`, and
  # `backport/2`.
  defp maybe_push_branch(false, _remote, _ref, _config_kw), do: {:ok, :not_pushed}

  defp maybe_push_branch(true, remote, ref, config_kw),
    do: Git.push(Keyword.merge(config_kw, remote: remote, refspecs: [ref]))

  defp maybe_force_with_lease(opts, true), do: Keyword.put(opts, :force_with_lease, true)
  defp maybe_force_with_lease(opts, false), do: opts

  defp resolve_branch(nil, config_kw), do: Git.Branches.current(config_kw)
  defp resolve_branch(branch, _config_kw) when is_binary(branch), do: {:ok, branch}

  defp integrate_fork(:merge, upstream_ref, config_kw),
    do: Git.merge(upstream_ref, Keyword.merge(config_kw, ff_only: true))

  defp integrate_fork(:rebase, upstream_ref, config_kw),
    do: Git.rebase(Keyword.merge(config_kw, upstream: upstream_ref))

  defp checkout_target(target, nil, config_kw),
    do: Git.checkout(Keyword.merge(config_kw, branch: target))

  defp checkout_target(target, base, config_kw) when is_binary(base),
    do: Git.checkout(Keyword.merge(config_kw, branch: target, create: true, start_point: base))

  # Runs the cherry-pick on the already-checked-out target. On a conflict the
  # pick is aborted so the caller's branch restore lands on a clean tree; the
  # original error is returned. On success the target is optionally pushed.
  defp do_backport(commits, push?, remote, target, config_kw) do
    case Git.cherry_pick(Keyword.merge(config_kw, commits: commits)) do
      {:ok, _} = ok ->
        case maybe_push_branch(push?, remote, target, config_kw) do
          {:ok, _} -> ok
          {:error, _} = error -> error
        end

      {:error, _} = error ->
        Git.cherry_pick(Keyword.merge(config_kw, abort: true))
        error
    end
  end

  defp resolve_restore_sha(sha, _name, _config_kw) when is_binary(sha), do: {:ok, sha}

  defp resolve_restore_sha(nil, name, config_kw) do
    case Git.reflog(config_kw) do
      {:ok, entries} -> branch_tip_from_reflog(name, entries)
      {:error, _} = error -> error
    end
  end

  # The HEAD reflog (newest first) records HEAD's value after each action. The
  # entry that checks out *away* from `name` records the destination branch's
  # tip, so the entry immediately older than it holds `name`'s tip: the value
  # HEAD had just before the branch was last left.
  defp branch_tip_from_reflog(name, entries) do
    leave = "moving from #{name} to "

    case Enum.find_index(entries, fn entry ->
           entry.action == "checkout" and String.starts_with?(entry.message, leave)
         end) do
      nil -> {:error, :not_found}
      index -> tip_after(entries, index)
    end
  end

  defp tip_after(entries, index) do
    case Enum.at(entries, index + 1) do
      %Git.ReflogEntry{hash: hash} when is_binary(hash) and hash != "" -> {:ok, hash}
      _ -> {:error, :not_found}
    end
  end

  defp maybe_checkout_restored(false, _name, _config_kw), do: {:ok, :not_checked_out}

  defp maybe_checkout_restored(true, name, config_kw),
    do: Git.checkout(Keyword.merge(config_kw, branch: name))
end
