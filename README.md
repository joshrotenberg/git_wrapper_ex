# Git

[![CI](https://github.com/joshrotenberg/git_wrapper_ex/actions/workflows/ci.yml/badge.svg)](https://github.com/joshrotenberg/git_wrapper_ex/actions/workflows/ci.yml)
[![Hex.pm](https://img.shields.io/hexpm/v/git.svg)](https://hex.pm/packages/git)
[![Documentation](https://img.shields.io/badge/docs-hexdocs-blue.svg)](https://hexdocs.pm/git)

A clean Elixir wrapper for the git CLI. Provides a direct, idiomatic mapping
to git subcommands with fully parsed output structs and higher-level workflow
abstractions. Runs git through a leak-free runner by default that kills the
whole process group on timeout, and falls back to `System.cmd/3` where that
runner is unavailable (see [Execution and timeouts](#execution-and-timeouts)).

## Installation

Add `git` to your dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:git, "~> 0.6"}
  ]
end
```

## Quick start

```elixir
# Check repository status
{:ok, status} = Git.status()
status.branch   #=> "main"
status.entries  #=> [%{index: "M", working_tree: " ", path: "lib/foo.ex"}]

# Stage and commit
{:ok, :done}  = Git.add(all: true)
{:ok, result} = Git.commit("feat: add new feature")
result.hash    #=> "abc1234"

# Branch, push, pull
{:ok, _}     = Git.checkout(branch: "feat/new", create: true)
{:ok, :done} = Git.push(remote: "origin", branch: "feat/new", set_upstream: true)
{:ok, _}     = Git.pull(rebase: true, autostash: true)

# Inspect history
{:ok, commits} = Git.log(max_count: 5)
Enum.each(commits, fn c -> IO.puts("#{c.abbreviated_hash}  #{c.subject}") end)
```

## Configuration

Pass a `Git.Config` struct via the `:config` option to control the working
directory, git binary path, environment variables, timeout, runner, and
per-invocation config:

```elixir
config = Git.Config.new(
  working_dir: "/path/to/repo",
  timeout: 60_000,
  runner: :forcola,
  extra_config: [{"core.autocrlf", "false"}]
)

{:ok, status} = Git.status(config: config)
```

- `:runner` selects how git is executed: `:forcola` (the default, leak-free),
  `:system_cmd`, or any module implementing the `Git.Runner` behaviour. See
  [Execution and timeouts](#execution-and-timeouts).
- `:extra_config` is a list of `{key, value}` pairs emitted as `git -c
  key=value` on every invocation, so you can override config without touching
  the repository's `.git/config`.

### Identity, dates, and a scratch index

Author/committer identity, commit dates, and the index file are set through
`:env` and `:extra_config` (git reads them from the environment and
per-invocation config) rather than dedicated options:

```elixir
# Set identity without mutating repo config
Git.Config.new(extra_config: [
  {"user.name", "A U Thor"},
  {"user.email", "author@example.com"}
])

# Pin author and committer dates (commit --date sets only the author date)
Git.Config.new(env: [
  {"GIT_AUTHOR_DATE", "2020-01-01T00:00:00"},
  {"GIT_COMMITTER_DATE", "2020-01-01T00:00:00"}
])

# Build a commit off to the side against a scratch index
Git.Config.new(env: [{"GIT_INDEX_FILE", "/tmp/scratch.index"}])
```

## Execution and timeouts

Every git command runs through a `Git.Runner`. The default,
`Git.Runner.Forcola`, runs git in its own process group and kills the whole
group (SIGTERM then SIGKILL) on timeout or BEAM death, so a `{:error, :timeout}`
means git is actually gone.

This matters because `System.cmd/3` implements timeouts by closing the Erlang
port, which only closes the stdin/stdout pipes and never signals the git OS
process. Under that model a git command that times out, and anything git
spawned (ssh transports, credential helpers, hooks, sign helpers), can keep
running and hold repository locks such as `.git/index.lock`. The forcola runner
exists to close that gap, so it is the default.

forcola is an optional dependency. It is POSIX-only (macOS and Linux) and ships
precompiled shim binaries, so no Rust toolchain is required on its supported
targets. Add it to your dependencies to get the leak-free default:

```elixir
# mix.exs
{:forcola, "~> 0.3"}
```

When forcola is not installed, or on a platform it does not support (for
example Windows), the runner falls back to `Git.Runner.SystemCmd`, which uses
`System.cmd/3` and works everywhere with no extra dependencies. To select it
explicitly:

```elixir
config = Git.Config.new(runner: :system_cmd)
{:ok, status} = Git.status(config: config)
```

The `:runner` value may also be any module implementing the `Git.Runner`
behaviour.

## Commands

80 git commands with full option support and parsed output.

### Core (snapshotting, branching, sharing)

| Function | git command | Returns |
|---|---|---|
| `status/1` | `git status` | `Git.Status.t()` |
| `log/1` | `git log` | `[Git.Commit.t()]` |
| `commit/2` | `git commit` | `Git.CommitResult.t()` |
| `add/1` | `git add` | `:done` |
| `branch/1` | `git branch` | `[Git.Branch.t()]` or `:done` |
| `checkout/1` | `git checkout` | `Git.Checkout.t()` or `:done` |
| `switch/1` | `git switch` | `Git.Checkout.t()` or `:done` |
| `restore/1` | `git restore` | `:done` |
| `diff/1` | `git diff` | `Git.Diff.t()` |
| `merge/2` | `git merge` | `Git.MergeResult.t()` or `:done` |
| `remote/1` | `git remote` | `[Git.Remote.t()]` or `:done` |
| `tag/1` | `git tag` | `[Git.Tag.t()]` or `:done` |
| `stash/1` | `git stash` | `[Git.StashEntry.t()]` or `:done` |
| `init/1` | `git init` | `:done` |
| `clone/2` | `git clone` | `:done` |
| `reset/1` | `git reset` | `:done` |
| `push/1` | `git push` | `:done` |
| `pull/1` | `git pull` | `Git.PullResult.t()` |
| `fetch/1` | `git fetch` | `:done` |
| `rebase/1` | `git rebase` | `Git.RebaseResult.t()` or `:done` |
| `cherry_pick/1` | `git cherry-pick` | `Git.CherryPickResult.t()` or `:done` |
| `revert/1` | `git revert` | `Git.RevertResult.t()` or `:done` |
| `submodule/1` | `git submodule` | varies |
| `notes/1` | `git notes` | varies |
| `clean/1` | `git clean` | `[String.t()]` |
| `mv/3` | `git mv` | `:done` |
| `rm/1` | `git rm` | `:done` |

### Inspection and comparison

| Function | git command | Returns |
|---|---|---|
| `show/1` | `git show` | `Git.ShowResult.t()` |
| `rev_parse/1` | `git rev-parse` | `String.t()` |
| `blame/2` | `git blame` | `[Git.BlameEntry.t()]` |
| `grep/2` | `git grep` | `[Git.GrepResult.t()]` |
| `describe/1` | `git describe` | `String.t()` |
| `shortlog/1` | `git shortlog` | `[Git.ShortlogEntry.t()]` |
| `range_diff/1` | `git range-diff` | `String.t()` |
| `ls_files/1` | `git ls-files` | `[String.t()]` |
| `ls_remote/1` | `git ls-remote` | `[Git.LsRemoteEntry.t()]` |
| `ls_tree/1` | `git ls-tree` | `[Git.TreeEntry.t()]` |
| `version/1` | `git version` | `Git.Version.t()` |
| `count_objects/1` | `git count-objects` | `Git.CountObjects.t()` |
| `var/1` | `git var` | `map()` or `String.t()` |
| `name_rev/1` | `git name-rev` | `String.t()` |
| `check_ref_format/1` | `git check-ref-format` | `true` or `String.t()` |

### Patching and email

| Function | git command | Returns |
|---|---|---|
| `apply_patch/1` | `git apply` | `:done` or `String.t()` |
| `am/1` | `git am` | `:done` |
| `format_patch/1` | `git format-patch` | `[String.t()]` or `String.t()` |
| `cherry/1` | `git cherry` | `[Git.CherryEntry.t()]` |
| `interpret_trailers/1` | `git interpret-trailers` | `String.t()` |

### Administration and maintenance

| Function | git command | Returns |
|---|---|---|
| `gc/1` | `git gc` | `:done` |
| `fsck/1` | `git fsck` | `[map()]` |
| `reflog/1` | `git reflog` | `[Git.ReflogEntry.t()]` |
| `archive/1` | `git archive` | `:done` |
| `bundle/1` | `git bundle` | varies |
| `maintenance/1` | `git maintenance` | `:done` |
| `git_config/1` | `git config` | `String.t()` or `[{k, v}]` or `:done` |
| `bisect/1` | `git bisect` | `Git.BisectResult.t()` or `:done` |
| `worktree/1` | `git worktree` | `[Git.Worktree.t()]` or `:done` |
| `rerere/1` | `git rerere` | varies |
| `sparse_checkout/1` | `git sparse-checkout` | varies |
| `verify_commit/2` | `git verify-commit` | `map()` |
| `verify_tag/2` | `git verify-tag` | `map()` |
| `check_ignore/1` | `git check-ignore` | `[String.t()]` or `[map()]` |
| `check_attr/1` | `git check-attr` | `[map()]` |

### Plumbing

| Function | git command | Returns |
|---|---|---|
| `cat_file/2` | `git cat-file` | varies |
| `commit_tree/1` | `git commit-tree` | `String.t()` |
| `write_tree/1` | `git write-tree` | `String.t()` |
| `read_tree/1` | `git read-tree` | `:done` |
| `update_index/1` | `git update-index` | `:done` |
| `mktree/1` | `git mktree` | `String.t()` |
| `merge_tree/3` | `git merge-tree` | `Git.MergeTreeResult.t()` |
| `merge_file/4` | `git merge-file` | `non_neg_integer()` |
| `diff_tree/1` | `git diff-tree` | `[Git.DiffRawEntry.t()]` |
| `diff_index/1` | `git diff-index` | `[Git.DiffRawEntry.t()]` or `boolean()` |
| `diff_files/1` | `git diff-files` | `[Git.DiffRawEntry.t()]` |
| `for_each_ref/1` | `git for-each-ref` | `String.t()` |
| `hash_object/1` | `git hash-object` | `String.t()` |
| `symbolic_ref/1` | `git symbolic-ref` | `String.t()` or `:done` |
| `update_ref/1` | `git update-ref` | `:done` |
| `rev_list/1` | `git rev-list` | `[String.t()]` or `integer()` |
| `merge_base/1` | `git merge-base` | `String.t()` or `boolean()` |
| `show_ref/1` | `git show-ref` | varies |

All functions return `{:ok, result}` on success or `{:error, {stdout, exit_code}}` on failure.

## Higher-level modules

### Git.Repo

Stateful repository struct for cleaner API usage:

```elixir
{:ok, repo} = Git.Repo.open("/path/to/repo")

{:ok, status} = Git.Repo.status(repo)
{:ok, :done}  = Git.Repo.add(repo, all: true)
{:ok, result} = Git.Repo.commit(repo, "feat: new feature")
{:ok, :done}  = Git.Repo.push(repo)

# Pipeline helpers
Git.Repo.ok(repo)
|> Git.Repo.run(fn r ->
  File.write!("new.txt", "content")
  {:ok, :done} = Git.Repo.add(r, files: ["new.txt"])
  {:ok, r}
end)
|> Git.Repo.run(fn r ->
  {:ok, _} = Git.Repo.commit(r, "add file")
  {:ok, r}
end)
```

### Git.Workflow

Composable multi-step workflows. Everyday commit helpers:

```elixir
# Stage everything and commit in one call
Git.Workflow.commit_all("fix: patch bug", config: config)

# Amend the last commit; undo it (soft); squash the last N
Git.Workflow.amend(config: config)
Git.Workflow.undo_last_commit(config: config)
Git.Workflow.squash_last(3, "feat: combined change", config: config)

# Discard all uncommitted changes (tracked and untracked)
Git.Workflow.discard_all(config: config)
```

Brackets and combinators (each threads `:config` and cleans up after itself):

```elixir
# Feature branch with automatic merge + cleanup
Git.Workflow.feature_branch("feat/login", fn opts ->
  File.write!("login.ex", "...")
  {:ok, :done} = Git.add(Keyword.merge(opts, files: ["login.ex"]))
  {:ok, _} = Git.commit("feat: add login", opts)
  {:ok, :done}
end, merge: true, delete: true, config: config)

# Check out a ref, run a function, restore the original branch (even on raise)
Git.Workflow.with_branch("main", fn opts -> Git.log(opts) end, config: config)

# Stash, run a function, pop the stash
Git.Workflow.with_stash(fn opts -> Git.pull(opts) end, config: config)

# Run a runtime-built list of steps, short-circuiting on the first error
[
  {:stage, fn o -> Git.add(Keyword.merge(o, all: true)) end},
  {:commit, fn o -> Git.commit("chore: release", o) end}
]
|> Git.Workflow.chain(config: config)
```

Integration, release, and collaboration:

```elixir
# Sync with upstream (fetch + rebase, with autostash)
Git.Workflow.sync(config: config)

# Rebase / merge that rolls back cleanly on conflict
Git.Workflow.safe_rebase(config: config)
Git.Workflow.try_merge("feature-branch", config: config)

# Squash merge a branch
Git.Workflow.squash_merge("feature-branch", message: "feat: all the things", config: config)

# Cut a release, publish the current branch, sync a fork, backport commits
Git.Workflow.release("v1.2.0", config: config)
Git.Workflow.publish(config: config)
Git.Workflow.sync_fork(config: config)
Git.Workflow.backport(["abc1234"], config: config)

# Recreate a branch that was deleted (from the reflog)
Git.Workflow.restore_branch("feat/lost", config: config)
```

### Git.History

Query commit history:

```elixir
{:ok, commits} = Git.History.commits_between("v1.0.0", "v2.0.0", config: config)
{:ok, changelog} = Git.History.changelog("v1.0.0", "v2.0.0", config: config)
# changelog.features, changelog.fixes, changelog.other

{:ok, contributors} = Git.History.contributors(path: "lib/", config: config)
{:ok, true} = Git.History.ancestor?("v1.0.0", "main", config: config)
```

### Git.Changes

Analyze repository changes:

```elixir
{:ok, changes} = Git.Changes.between("HEAD~5", "HEAD", config: config)
# [%{status: :modified, path: "lib/foo.ex"}, %{status: :added, path: "lib/bar.ex"}]

{:ok, uncommitted} = Git.Changes.uncommitted(config: config)
# uncommitted.staged, uncommitted.modified, uncommitted.untracked

{:ok, conflicts} = Git.Changes.conflicts(config: config)
```

### Git.Info

Repository introspection:

```elixir
{:ok, summary} = Git.Info.summary(config: config)
# summary.branch, summary.commit, summary.dirty, summary.ahead, summary.behind, ...

{:ok, true} = Git.Info.dirty?(config: config)
{:ok, head} = Git.Info.head(config: config)
{:ok, root} = Git.Info.root(config: config)
```

### Git.Search

Search content and history:

```elixir
{:ok, results} = Git.Search.grep("TODO", config: config)
# [%Git.GrepResult{file: "lib/foo.ex", line_number: 42, content: "# TODO: refactor"}]

{:ok, commits} = Git.Search.commits("fix:", config: config)
{:ok, commits} = Git.Search.pickaxe("my_function", config: config)
{:ok, files} = Git.Search.files("*.ex", config: config)
```

### Git.Branches

Branch management:

```elixir
{:ok, "main"} = Git.Branches.current(config: config)
{:ok, true} = Git.Branches.exists?("feat/login", config: config)
{:ok, merged} = Git.Branches.merged(config: config)
{:ok, deleted} = Git.Branches.cleanup_merged(exclude: ["main", "develop"], config: config)
{:ok, %{ahead: 3, behind: 0}} = Git.Branches.divergence("feat/x", "main", config: config)
{:ok, recent} = Git.Branches.recent(count: 5, config: config)

# Delete a branch; prune locals whose upstream is gone; find squash-merged branches
{:ok, :done} = Git.Branches.delete_branch("feat/done", config: config)
{:ok, pruned} = Git.Branches.prune_gone(config: config)
{:ok, would_delete} = Git.Branches.delete_squashed(target: "main", config: config)  # dry-run by default
{:ok, deleted} = Git.Branches.delete_squashed(target: "main", dry_run: false, config: config)
```

### Git.Tags

Tag management:

```elixir
{:ok, :done} = Git.Tags.create("v1.0.0", message: "Release 1.0.0", config: config)
{:ok, tags} = Git.Tags.list(config: config)
{:ok, "v1.0.0"} = Git.Tags.latest(config: config)
{:ok, sorted} = Git.Tags.sorted(config: config)  # version-sorted
{:ok, true} = Git.Tags.exists?("v1.0.0", config: config)
{:ok, :done} = Git.Tags.delete("v0.1.0", config: config)
```

### Git.Remotes

Remote management:

```elixir
{:ok, remotes} = Git.Remotes.list_detailed(config: config)
{:ok, :done} = Git.Remotes.add("upstream", "https://github.com/upstream/repo.git", config: config)
{:ok, :done} = Git.Remotes.set_url("origin", "git@github.com:me/repo.git", config: config)
{:ok, :done} = Git.Remotes.prune("origin", config: config)
{:ok, :done} = Git.Remotes.remove("upstream", config: config)
```

### Git.Stashes

Stash management:

```elixir
{:ok, _} = Git.Stashes.save("work in progress", config: config)
{:ok, stashes} = Git.Stashes.list(config: config)
{:ok, _} = Git.Stashes.apply(config: config)
{:ok, _} = Git.Stashes.pop(config: config)
{:ok, :done} = Git.Stashes.drop(config: config)
{:ok, :done} = Git.Stashes.clear(config: config)
```

### Git.Patch

Patch creation and application:

```elixir
{:ok, files} = Git.Patch.create("HEAD~3", output_directory: "/tmp/patches", config: config)
{:ok, :done} = Git.Patch.check("/tmp/patches/0001-fix.patch", config: config)
{:ok, :done} = Git.Patch.apply("/tmp/patches/0001-fix.patch", config: config)
{:ok, :done} = Git.Patch.apply_mailbox(["0001-fix.patch", "0002-feat.patch"], config: config)
```

### Git.Conflicts

Merge conflict helpers:

```elixir
{:ok, false} = Git.Conflicts.detect(config: config)
{:ok, files} = Git.Conflicts.files(config: config)
{:ok, true} = Git.Conflicts.resolved?(config: config)

# Inspect the three sides of a conflicted path
{:ok, base} = Git.Conflicts.base("shared.txt", config: config)
{:ok, ours} = Git.Conflicts.ours("shared.txt", config: config)
{:ok, theirs} = Git.Conflicts.theirs("shared.txt", config: config)

# Resolve by taking one side (single path or a list), then it is staged for you
{:ok, :done} = Git.Conflicts.take_ours("shared.txt", config: config)
{:ok, :done} = Git.Conflicts.take_theirs(["a.txt", "b.txt"], config: config)
{:ok, :done} = Git.Conflicts.resolve("shared.txt", using: :ours, config: config)

# Abort or continue whatever operation is in progress (merge/rebase/cherry-pick/revert)
{:ok, :done} = Git.Conflicts.abort(config: config)
{:ok, _} = Git.Conflicts.continue(config: config)
```

### Git.Hooks

Manage git hooks:

```elixir
{:ok, hooks} = Git.Hooks.list(config: config)
{:ok, path} = Git.Hooks.write("pre-commit", "#!/bin/sh\nmix format --check-formatted", config: config)
{:ok, true} = Git.Hooks.enabled?("pre-commit", config: config)
{:ok, _} = Git.Hooks.disable("pre-commit", config: config)
:ok = Git.Hooks.remove("pre-commit", config: config)
```

### Git.Signing

Configure commit and tag signing (sets the relevant git config keys):

```elixir
# SSH signing (sets gpg.format=ssh, user.signingkey, commit.gpgsign=true)
{:ok, :done} = Git.Signing.use_ssh("/home/me/.ssh/id_ed25519.pub", config: config)

# GPG signing by key id
{:ok, :done} = Git.Signing.use_gpg("ABCD1234", config: config)

# Also sign annotated tags by default
{:ok, :done} = Git.Signing.sign_tags(true, config: config)
```

The actual signing happens when a commit, tag, or merge is created. Once the
config above is set, `Git.commit/2`, `Git.tag/1`, and `Git.merge/2` sign
automatically, or you can request it per call with `:sign` / `:gpg_sign` /
`:local_user`:

```elixir
{:ok, _} = Git.commit("feat: signed change", sign: true, config: config)
{:ok, :done} = Git.tag(create: "v1.0.0", message: "release", sign: true, config: config)
```

## Examples

Runnable scripts live under [`examples/`](examples/):

- [`examples/state_machine.exs`](examples/state_machine.exs) drives git as a
  state machine for agent-driven development: a worktree per issue, a commit
  per phase, JSON metadata in git notes, and mechanical gates (`mix compile` /
  `mix test` exit codes) deciding whether the machine advances or freezes.

```sh
mix run --no-start examples/state_machine.exs
```

## License

MIT
