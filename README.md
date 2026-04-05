# Git

[![CI](https://github.com/joshrotenberg/git_wrapper_ex/actions/workflows/ci.yml/badge.svg)](https://github.com/joshrotenberg/git_wrapper_ex/actions/workflows/ci.yml)
[![Hex.pm](https://img.shields.io/hexpm/v/git_wrapper_ex.svg)](https://hex.pm/packages/git_wrapper_ex)
[![Documentation](https://img.shields.io/badge/docs-hexdocs-blue.svg)](https://hexdocs.pm/git_wrapper_ex)

A clean Elixir wrapper for the git CLI. Provides a direct, idiomatic mapping
to git subcommands with fully parsed output structs. No NIFs, no ports — just
`System.cmd/3` with structured results.

## Installation

Add `git_wrapper_ex` to your dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:git_wrapper_ex, "~> 0.1.0"}
  ]
end
```

Then fetch deps:

```bash
mix deps.get
```

## Quick Start

```elixir
# Check repository status
{:ok, status} = Git.status()
IO.inspect(status.branch)   # "main"
IO.inspect(status.entries)  # [%{index: "M", working_tree: " ", path: "lib/foo.ex"}]

# Stage all changes and commit
{:ok, :done}  = Git.add(all: true)
{:ok, result} = Git.commit("feat: add new feature")
IO.inspect(result.hash)    # "abc1234"
IO.inspect(result.subject) # "feat: add new feature"

# Inspect the last 10 commits
{:ok, commits} = Git.log(max_count: 10)
Enum.each(commits, fn c -> IO.puts("#{c.abbreviated_hash}  #{c.subject}") end)

# Create and switch to a branch
{:ok, :done}    = Git.branch(create: "feat/my-feature")
{:ok, checkout} = Git.checkout(branch: "feat/my-feature")
```

### Using a custom config

Pass a `Git.Config` struct via the `:config` option to set the working
directory, git binary path, environment variables, or timeout:

```elixir
config = Git.Config.new(
  working_dir: "/path/to/repo",
  timeout: 60_000
)

{:ok, status} = Git.status(config: config)
```

## API Reference

All functions are in the `Git` module and follow the same convention:

- Accept an options keyword list; most also accept leading positional arguments.
- Always return `{:ok, result}` on success or `{:error, {stdout, exit_code}}` on failure.
- Accept `:config` as a `Git.Config` struct to override defaults.

| Function | git command | Returns on success |
|---|---|---|
| `status/1` | `git status --porcelain=v1 -b` | `{:ok, Git.Status.t()}` |
| `log/1` | `git log` | `{:ok, [Git.Commit.t()]}` |
| `commit/2` | `git commit` | `{:ok, Git.CommitResult.t()}` |
| `add/1` | `git add` | `{:ok, :done}` |
| `branch/1` | `git branch` | `{:ok, [Git.Branch.t()]}` or `{:ok, :done}` |
| `checkout/1` | `git checkout` | `{:ok, Git.Checkout.t()}` or `{:ok, :done}` |
| `diff/1` | `git diff` | `{:ok, Git.Diff.t()}` |
| `merge/2` | `git merge` | `{:ok, Git.MergeResult.t()}` or `{:ok, :done}` |
| `remote/1` | `git remote` | `{:ok, [Git.Remote.t()]}` or `{:ok, :done}` |
| `tag/1` | `git tag` | `{:ok, [Git.Tag.t()]}` or `{:ok, :done}` |
| `stash/1` | `git stash` | `{:ok, [Git.StashEntry.t()]}` or `{:ok, :done}` |
| `init/1` | `git init` | `{:ok, :done}` |
| `clone/2` | `git clone` | `{:ok, :done}` |
| `reset/1` | `git reset` | `{:ok, :done}` |

### `status/1`

```elixir
{:ok, status} = Git.status()
# status.branch   => "main"
# status.tracking => "origin/main"
# status.ahead    => 2
# status.behind   => 0
# status.entries  => [%{index: "M", working_tree: " ", path: "lib/foo.ex"}]
```

### `log/1`

Options: `:max_count`, `:author`, `:since`, `:until_date`, `:path`

```elixir
{:ok, commits} = Git.log(max_count: 5, author: "alice")
# commits => [%Git.Commit{hash: "...", subject: "...", ...}]
```

### `commit/2`

Options: `:all`, `:amend`, `:allow_empty`

```elixir
{:ok, result} = Git.commit("fix: correct off-by-one", all: true)
# result.branch        => "main"
# result.hash          => "abc1234"
# result.files_changed => 1
# result.insertions    => 3
# result.deletions     => 1
```

### `add/1`

Options: `:files` (list), `:all`

```elixir
{:ok, :done} = Git.add(files: ["lib/foo.ex", "test/foo_test.exs"])
{:ok, :done} = Git.add(all: true)
```

### `branch/1`

Options: `:create`, `:delete`, `:force_delete`, `:all`

```elixir
{:ok, branches} = Git.branch()
{:ok, branches} = Git.branch(all: true)
{:ok, :done}    = Git.branch(create: "feat/new")
{:ok, :done}    = Git.branch(delete: "old-branch")
{:ok, :done}    = Git.branch(delete: "gone", force_delete: true)
```

### `checkout/1`

Options: `:branch`, `:create`, `:files`

```elixir
{:ok, result} = Git.checkout(branch: "main")
{:ok, result} = Git.checkout(branch: "feat/new", create: true)
{:ok, :done}  = Git.checkout(files: ["lib/foo.ex"])
```

### `diff/1`

Options: `:staged`, `:stat`, `:ref`, `:path`

```elixir
{:ok, diff} = Git.diff()
{:ok, diff} = Git.diff(staged: true, stat: true)
{:ok, diff} = Git.diff(ref: "HEAD~1", path: "lib/")
# diff.total_insertions => 5
# diff.total_deletions  => 2
# diff.files            => [%Git.DiffFile{path: "lib/foo.ex", ...}]
```

### `merge/2`

Options: `:no_ff`

```elixir
{:ok, result} = Git.merge("feature-branch")
{:ok, result} = Git.merge("feature-branch", no_ff: true)
{:ok, :done}  = Git.merge(:abort)
# result.fast_forward       => true
# result.already_up_to_date => false
```

### `remote/1`

Options: `:add_name`, `:add_url`, `:remove`, `:verbose`

```elixir
{:ok, remotes} = Git.remote()
{:ok, :done}   = Git.remote(add_name: "upstream", add_url: "https://github.com/upstream/repo.git")
{:ok, :done}   = Git.remote(remove: "upstream")
# hd(remotes).name      => "origin"
# hd(remotes).fetch_url => "https://github.com/owner/repo.git"
```

### `tag/1`

Options: `:create`, `:message`, `:delete`, `:ref`, `:sort`

```elixir
{:ok, tags}  = Git.tag()
{:ok, tags}  = Git.tag(sort: "-version:refname")
{:ok, :done} = Git.tag(create: "v1.0.0")
{:ok, :done} = Git.tag(create: "v1.0.0", message: "First release")
{:ok, :done} = Git.tag(delete: "v0.9.0")
```

### `stash/1`

Options: `:save`, `:pop`, `:drop`, `:message`, `:index`, `:include_untracked`

```elixir
{:ok, :done}   = Git.stash(save: true, message: "wip: my changes")
{:ok, :done}   = Git.stash(save: true, include_untracked: true)
{:ok, entries} = Git.stash()
{:ok, :done}   = Git.stash(pop: true)
{:ok, :done}   = Git.stash(drop: true, index: 1)
```

### `init/1`

Options: `:path`, `:bare`

```elixir
{:ok, :done} = Git.init()
{:ok, :done} = Git.init(path: "/tmp/new-repo")
{:ok, :done} = Git.init(path: "/srv/repos/project.git", bare: true)
```

### `clone/2`

Options: `:depth`, `:branch`, `:directory`

```elixir
{:ok, :done} = Git.clone("https://github.com/owner/repo.git")
{:ok, :done} = Git.clone("https://github.com/owner/repo.git", depth: 1)
{:ok, :done} = Git.clone("https://github.com/owner/repo.git",
                 branch: "main",
                 directory: "my-repo",
                 config: Git.Config.new(working_dir: "/tmp"))
```

### `reset/1`

Options: `:ref`, `:mode` (`:soft`, `:mixed`, `:hard`)

```elixir
{:ok, :done} = Git.reset()
{:ok, :done} = Git.reset(mode: :soft, ref: "HEAD~1")
{:ok, :done} = Git.reset(mode: :hard)
```

## License

MIT
