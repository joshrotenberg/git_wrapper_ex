# Git

[![CI](https://github.com/joshrotenberg/git_wrapper_ex/actions/workflows/ci.yml/badge.svg)](https://github.com/joshrotenberg/git_wrapper_ex/actions/workflows/ci.yml)
[![Hex.pm](https://img.shields.io/hexpm/v/git.svg)](https://hex.pm/packages/git)
[![Documentation](https://img.shields.io/badge/docs-hexdocs-blue.svg)](https://hexdocs.pm/git)

A clean Elixir wrapper for the git CLI. Provides a direct, idiomatic mapping
to git subcommands with fully parsed output structs and higher-level workflow
abstractions. No NIFs, no ports -- just `System.cmd/3` with structured results.

## Installation

Add `git` to your dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:git, "~> 0.4.0"}
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
directory, git binary path, environment variables, or timeout:

```elixir
config = Git.Config.new(
  working_dir: "/path/to/repo",
  timeout: 60_000
)

{:ok, status} = Git.status(config: config)
```

## Commands

65 git commands with full option support and parsed output.

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

### Plumbing

| Function | git command | Returns |
|---|---|---|
| `cat_file/2` | `git cat-file` | varies |
| `commit_tree/1` | `git commit-tree` | `String.t()` |
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

Composable multi-step workflows:

```elixir
# Feature branch with automatic cleanup
Git.Workflow.feature_branch("feat/login", fn opts ->
  File.write!("login.ex", "...")
  {:ok, :done} = Git.add(Keyword.merge(opts, files: ["login.ex"]))
  {:ok, _} = Git.commit("feat: add login", opts)
  {:ok, :done}
end, merge: true, delete: true, config: config)

# Stage everything and commit in one call
Git.Workflow.commit_all("fix: patch bug", config: config)

# Sync with upstream (fetch + rebase, with autostash)
Git.Workflow.sync(config: config)

# Squash merge a branch
Git.Workflow.squash_merge("feature-branch", message: "feat: all the things", config: config)
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
{:ok, :done} = Git.Conflicts.abort_merge(config: config)
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

## License

MIT
