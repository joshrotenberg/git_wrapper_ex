defmodule Git do
  @moduledoc """
  An Elixir wrapper for the git CLI.

  Provides functions for common git operations by shelling out to the git
  binary. Each function accepts an options keyword list that can include
  a `:config` key with a `Git.Config` struct to customize behavior.

  All functions return `{:ok, result}` on success or `{:error, reason}` on
  failure. A non-zero exit code from git produces `{:error, {stdout, exit_code}}`.

  ## Configuration

  Pass a `Git.Config` struct via the `:config` option to control the git
  binary, working directory, environment variables, and command timeout:

      config = Git.Config.new(
        working_dir: "/path/to/repo",
        timeout: 60_000
      )

      Git.status(config: config)

  When `:config` is omitted, a default config is built from the environment:
  the git binary is located via `GIT_PATH` or `System.find_executable("git")`,
  the working directory defaults to the current directory, and the timeout is
  30 seconds.

  ## Examples

  ### Repository status

      {:ok, status} = Git.status()
      status.branch   #=> "main"
      status.ahead    #=> 0
      status.entries  #=> [%{index: "M", working_tree: " ", path: "lib/foo.ex"}]

  ### Commit history

      {:ok, commits} = Git.log(max_count: 5)
      hd(commits).subject  #=> "feat: add new feature"
      hd(commits).hash     #=> "e3a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9"

  ### Staging and committing

      {:ok, :done}   = Git.add(all: true)
      {:ok, result}  = Git.commit("feat: ship it")
      result.hash    #=> "abc1234"
      result.subject #=> "feat: ship it"

  ### Branches

      {:ok, branches} = Git.branch()
      Enum.find(branches, & &1.current).name  #=> "main"

      {:ok, :done}     = Git.branch(create: "feat/new-thing")
      {:ok, checkout}  = Git.checkout(branch: "feat/new-thing")
      checkout.created #=> false

  ### Diffs

      {:ok, diff} = Git.diff(stat: true)
      diff.total_insertions  #=> 10
      diff.total_deletions   #=> 3

      {:ok, staged} = Git.diff(staged: true)
      staged.raw  #=> full patch text

  ### Remotes

      {:ok, remotes} = Git.remote()
      hd(remotes).fetch_url  #=> "https://github.com/owner/repo.git"

      {:ok, :done} = Git.remote(add_name: "upstream", add_url: "https://github.com/upstream/repo.git")
      {:ok, :done} = Git.remote(remove: "upstream")

  ### Tags

      {:ok, tags}  = Git.tag()
      {:ok, :done} = Git.tag(create: "v1.0.0", message: "First release")
      {:ok, :done} = Git.tag(delete: "v0.9.0")

  ### Merging

      {:ok, result} = Git.merge("feature-branch")
      result.fast_forward       #=> true
      result.already_up_to_date #=> false

      {:ok, :done} = Git.merge(:abort)

  ### Stashing

      {:ok, :done}    = Git.stash(save: true, message: "wip: half-done feature")
      {:ok, entries}  = Git.stash()
      hd(entries).message  #=> "wip: half-done feature"
      {:ok, :done}    = Git.stash(pop: true)

  ### Repository management

      {:ok, :done} = Git.init(path: "/tmp/new-repo")
      {:ok, :done} = Git.clone("https://github.com/owner/repo.git", depth: 1)
      {:ok, :done} = Git.reset(mode: :soft, ref: "HEAD~1")
  """

  alias Git.Config

  @doc """
  Runs `git status` and returns the parsed output.

  ## Options

    * `:config` - a `Git.Config` struct (default: `Git.Config.new()`)
    * All other options are passed to the underlying command.

  """
  @spec status(keyword()) :: {:ok, Git.Status.t()} | {:error, term()}
  def status(opts \\ []) do
    {config, _rest} = Keyword.pop(opts, :config, Config.new())
    Git.Command.run(Git.Commands.Status, %Git.Commands.Status{}, config)
  end

  @doc """
  Runs `git log` and returns the parsed output.

  ## Options

    * `:config` - a `Git.Config` struct (default: `Git.Config.new()`)
    * All other options are passed to the underlying command.

  """
  @spec log(keyword()) :: {:ok, [Git.Commit.t()]} | {:error, term()}
  def log(opts \\ []) do
    {config, rest} = Keyword.pop(opts, :config, Config.new())
    command = struct!(Git.Commands.Log, rest)
    Git.Command.run(Git.Commands.Log, command, config)
  end

  @doc """
  Runs `git commit` with the given message and returns the parsed output.

  ## Options

    * `:config` - a `Git.Config` struct (default: `Git.Config.new()`)
    * All other options are passed to the underlying command.

  """
  @spec commit(String.t(), keyword()) :: {:ok, Git.CommitResult.t()} | {:error, term()}
  def commit(message, opts \\ []) when is_binary(message) do
    {config, rest} = Keyword.pop(opts, :config, Config.new())
    command = struct!(Git.Commands.Commit, [{:message, message} | rest])
    Git.Command.run(Git.Commands.Commit, command, config)
  end

  @doc """
  Runs `git branch` to list, create, or delete branches.

  ## Options

    * `:config` - a `Git.Config` struct (default: `Git.Config.new()`)
    * `:create` - name of a new branch to create
    * `:delete` - name of a branch to delete
    * `:force_delete` - use `-D` for delete (default `false`)
    * `:all` - include remote-tracking branches in the listing (default `false`)

  """
  @spec branch(keyword()) ::
          {:ok, [Git.Branch.t()]} | {:ok, :done} | {:error, term()}
  def branch(opts \\ []) do
    {config, rest} = Keyword.pop(opts, :config, Config.new())
    command = struct!(Git.Commands.Branch, rest)
    Git.Command.run(Git.Commands.Branch, command, config)
  end

  @doc """
  Runs `git diff` and returns parsed diff output.

  ## Options

    * `:config` - a `Git.Config` struct (default: `Git.Config.new()`)
    * `:staged` - show staged (cached) diff (default `false`)
    * `:stat` - return file-level stats instead of full patch (default `false`)
    * `:ref` - compare against this ref (e.g., `"HEAD~1"`)
    * `:path` - limit the diff to this path

  """
  @spec diff(keyword()) :: {:ok, Git.Diff.t()} | {:error, term()}
  def diff(opts \\ []) do
    {config, rest} = Keyword.pop(opts, :config, Config.new())
    command = struct!(Git.Commands.Diff, rest)
    Git.Command.run(Git.Commands.Diff, command, config)
  end

  @doc """
  Runs `git remote` to list, add, or remove remotes.

  ## Options

    * `:config` - a `Git.Config` struct (default: `Git.Config.new()`)
    * `:add_name` - name for a new remote (requires `:add_url`)
    * `:add_url` - URL for a new remote (requires `:add_name`)
    * `:remove` - name of remote to remove
    * `:verbose` - verbose listing (default `true`)

  """
  @spec remote(keyword()) :: {:ok, [Git.Remote.t()]} | {:ok, :done} | {:error, term()}
  def remote(opts \\ []) do
    {config, rest} = Keyword.pop(opts, :config, Config.new())
    command = struct!(Git.Commands.Remote, rest)
    Git.Command.run(Git.Commands.Remote, command, config)
  end

  @doc """
  Runs `git tag` to list, create, or delete tags.

  ## Options

    * `:config` - a `Git.Config` struct (default: `Git.Config.new()`)
    * `:create` - name of a new tag to create
    * `:message` - annotation message (creates an annotated tag when set with `:create`)
    * `:delete` - name of a tag to delete
    * `:ref` - commit ref to tag (default: HEAD)
    * `:sort` - sort order for listing (e.g., `"-version:refname"`)

  """
  @spec tag(keyword()) ::
          {:ok, [Git.Tag.t()]} | {:ok, :done} | {:error, term()}
  def tag(opts \\ []) do
    {config, rest} = Keyword.pop(opts, :config, Config.new())
    command = struct!(Git.Commands.Tag, rest)
    Git.Command.run(Git.Commands.Tag, command, config)
  end

  @doc """
  Runs `git checkout` to switch branches, create and switch branches, or restore files.

  ## Options

    * `:config` - a `Git.Config` struct (default: `Git.Config.new()`)
    * `:branch` - name of the branch to switch to
    * `:create` - when `true`, creates the branch before switching (`-b` flag, default `false`)
    * `:files` - list of file paths to restore from the index (default `[]`)

  """
  @spec checkout(keyword()) ::
          {:ok, Git.Checkout.t()} | {:ok, :done} | {:error, term()}
  def checkout(opts \\ []) do
    {config, rest} = Keyword.pop(opts, :config, Config.new())
    command = struct!(Git.Commands.Checkout, rest)
    Git.Command.run(Git.Commands.Checkout, command, config)
  end

  @doc """
  Runs `git add` to stage files for the next commit.

  ## Options

    * `:config` - a `Git.Config` struct (default: `Git.Config.new()`)
    * `:files` - list of file paths to stage (default `[]`)
    * `:all` - stage all changes including deletions (`--all` flag, default `false`)

  """
  @spec add(keyword()) :: {:ok, :done} | {:error, term()}
  def add(opts \\ []) do
    {config, rest} = Keyword.pop(opts, :config, Config.new())
    command = struct!(Git.Commands.Add, rest)
    Git.Command.run(Git.Commands.Add, command, config)
  end

  @doc """
  Runs `git merge` to merge a branch or abort an in-progress merge.

  Pass a branch name as the first argument to merge it into the current branch.
  Pass `:abort` to abort an in-progress merge.

  ## Options

    * `:config` - a `Git.Config` struct (default: `Git.Config.new()`)
    * `:no_ff` - when `true`, forces a merge commit even for fast-forward merges
      (`--no-ff` flag, default `false`)

  ## Examples

      Git.merge("feature-branch")
      Git.merge("feature-branch", no_ff: true)
      Git.merge(:abort)

  """
  @spec merge(String.t() | :abort, keyword()) ::
          {:ok, Git.MergeResult.t()} | {:ok, :done} | {:error, term()}
  def merge(branch_or_abort, opts \\ [])

  def merge(:abort, opts) do
    {config, _rest} = Keyword.pop(opts, :config, Config.new())
    command = %Git.Commands.Merge{abort: true}
    Git.Command.run(Git.Commands.Merge, command, config)
  end

  def merge(branch, opts) when is_binary(branch) do
    {config, rest} = Keyword.pop(opts, :config, Config.new())
    command = struct!(Git.Commands.Merge, [{:branch, branch} | rest])
    Git.Command.run(Git.Commands.Merge, command, config)
  end

  @doc """
  Runs `git init` to initialize a new repository.

  ## Options

    * `:config` - a `Git.Config` struct (default: `Git.Config.new()`)
    * `:path` - directory to initialize (default: the working directory)
    * `:bare` - when `true`, initializes a bare repository (`--bare` flag, default `false`)

  """
  @spec init(keyword()) :: {:ok, :done} | {:error, term()}
  def init(opts \\ []) do
    {config, rest} = Keyword.pop(opts, :config, Config.new())
    command = struct!(Git.Commands.Init, rest)
    Git.Command.run(Git.Commands.Init, command, config)
  end

  @doc """
  Runs `git clone` to clone a repository.

  The `:config` working directory determines where the clone is created.

  ## Options

    * `:config` - a `Git.Config` struct (default: `Git.Config.new()`)
    * `:depth` - create a shallow clone with the given number of commits (`--depth` flag)
    * `:branch` - check out the given branch after cloning (`--branch` flag)
    * `:directory` - name of the target directory (default: inferred from the URL)

  ## Examples

      Git.clone("https://github.com/owner/repo.git")
      Git.clone("https://github.com/owner/repo.git", depth: 1)
      Git.clone("https://github.com/owner/repo.git", branch: "main", directory: "my-repo")

  """
  @spec clone(String.t(), keyword()) :: {:ok, :done} | {:error, term()}
  def clone(url, opts \\ []) when is_binary(url) do
    {config, rest} = Keyword.pop(opts, :config, Config.new())
    command = struct!(Git.Commands.Clone, [{:url, url} | rest])
    Git.Command.run(Git.Commands.Clone, command, config)
  end

  @doc """
  Runs `git reset` to move HEAD and optionally modify the index and working tree.

  ## Options

    * `:config` - a `Git.Config` struct (default: `Git.Config.new()`)
    * `:ref` - the ref to reset to (default: `"HEAD"`)
    * `:mode` - one of `:soft`, `:mixed` (default), or `:hard`

  ## Examples

      Git.reset()
      Git.reset(mode: :soft, ref: "HEAD~1")
      Git.reset(mode: :hard)

  """
  @spec reset(keyword()) :: {:ok, :done} | {:error, term()}
  def reset(opts \\ []) do
    {config, rest} = Keyword.pop(opts, :config, Config.new())
    command = struct!(Git.Commands.Reset, rest)
    Git.Command.run(Git.Commands.Reset, command, config)
  end

  @doc """
  Runs `git stash` to list, save, pop, or drop stash entries.

  ## Options

    * `:config` - a `Git.Config` struct (default: `Git.Config.new()`)
    * `:save` - push current changes onto the stash (default `false`)
    * `:pop` - pop the top stash entry (default `false`)
    * `:drop` - drop a stash entry (default `false`)
    * `:message` - message for the stash entry (used with `:save`)
    * `:index` - stash index for `:pop` or `:drop` (e.g., `0` for `stash@{0}`)
    * `:include_untracked` - include untracked files when saving (default `false`)

  """
  @spec stash(keyword()) ::
          {:ok, [Git.StashEntry.t()]} | {:ok, :done} | {:error, term()}
  def stash(opts \\ []) do
    {config, rest} = Keyword.pop(opts, :config, Config.new())
    command = struct!(Git.Commands.Stash, rest)
    Git.Command.run(Git.Commands.Stash, command, config)
  end

  @doc """
  Runs `git push` to push commits to a remote repository.

  ## Options

    * `:config` - a `Git.Config` struct (default: `Git.Config.new()`)
    * `:remote` - remote name (e.g., `"origin"`)
    * `:branch` - branch or refspec to push
    * `:force` - force push (`--force`)
    * `:force_with_lease` - safer force push (`--force-with-lease`)
    * `:set_upstream` - set upstream tracking (`-u`)
    * `:tags` - push tags (`--tags`)
    * `:delete` - delete remote branch (`--delete`)
    * `:dry_run` - dry run (`--dry-run`)
    * `:all` - push all branches (`--all`)
    * `:no_verify` - skip pre-push hooks (`--no-verify`)
    * `:atomic` - atomic push (`--atomic`)
    * `:prune` - prune remote branches (`--prune`)

  ## Examples

      Git.push(remote: "origin", branch: "main")
      Git.push(remote: "origin", branch: "main", force_with_lease: true)
      Git.push(tags: true)

  """
  @spec push(keyword()) :: {:ok, :done} | {:error, term()}
  def push(opts \\ []) do
    {config, rest} = Keyword.pop(opts, :config, Config.new())
    command = struct!(Git.Commands.Push, rest)
    Git.Command.run(Git.Commands.Push, command, config)
  end

  @doc """
  Runs `git pull` to fetch and integrate changes from a remote repository.

  ## Options

    * `:config` - a `Git.Config` struct (default: `Git.Config.new()`)
    * `:remote` - remote name
    * `:branch` - branch to pull
    * `:rebase` - rebase instead of merge (`true`, or a strategy string)
    * `:ff_only` - fast-forward only (`--ff-only`)
    * `:no_ff` - create merge commit (`--no-ff`)
    * `:autostash` - autostash before operation (`--autostash`)
    * `:squash` - squash commits (`--squash`)
    * `:no_commit` - merge without committing (`--no-commit`)
    * `:depth` - limit fetch depth (`--depth`)
    * `:dry_run` - dry run (`--dry-run`)
    * `:tags` / `:no_tags` - fetch tags behavior
    * `:prune` - prune deleted remote branches (`--prune`)
    * `:verbose` / `:quiet` - output verbosity

  ## Examples

      Git.pull()
      Git.pull(remote: "origin", branch: "main")
      Git.pull(rebase: true, autostash: true)

  """
  @spec pull(keyword()) :: {:ok, Git.PullResult.t()} | {:error, term()}
  def pull(opts \\ []) do
    {config, rest} = Keyword.pop(opts, :config, Config.new())
    command = struct!(Git.Commands.Pull, rest)
    Git.Command.run(Git.Commands.Pull, command, config)
  end

  @doc """
  Runs `git fetch` to download objects and refs from a remote repository.

  ## Options

    * `:config` - a `Git.Config` struct (default: `Git.Config.new()`)
    * `:remote` - remote name
    * `:branch` - refspec to fetch
    * `:all` - fetch all remotes (`--all`)
    * `:prune` - prune deleted remote branches (`--prune`)
    * `:prune_tags` - prune tags (`--prune-tags`)
    * `:tags` / `:no_tags` - fetch tags behavior
    * `:depth` - shallow fetch depth (`--depth`)
    * `:unshallow` - convert shallow to complete (`--unshallow`)
    * `:dry_run` - dry run (`--dry-run`)
    * `:force` - force update refs (`--force`)
    * `:verbose` / `:quiet` - output verbosity
    * `:jobs` - number of parallel jobs (`--jobs`)
    * `:recurse_submodules` - recurse into submodules (`true` or strategy string)
    * `:set_upstream` - set upstream tracking (`--set-upstream`)

  ## Examples

      Git.fetch()
      Git.fetch(remote: "origin", prune: true)
      Git.fetch(all: true, tags: true)

  """
  @spec fetch(keyword()) :: {:ok, :done} | {:error, term()}
  def fetch(opts \\ []) do
    {config, rest} = Keyword.pop(opts, :config, Config.new())
    command = struct!(Git.Commands.Fetch, rest)
    Git.Command.run(Git.Commands.Fetch, command, config)
  end

  @doc """
  Runs `git rebase` to reapply commits on top of another base.

  Pass an upstream ref as the first argument, or use keyword options for
  abort/continue/skip operations.

  ## Options

    * `:config` - a `Git.Config` struct (default: `Git.Config.new()`)
    * `:upstream` - the upstream branch to rebase onto
    * `:branch` - the branch to rebase (optional)
    * `:onto` - rebase onto a specific ref (`--onto`)
    * `:abort` - abort in-progress rebase (`--abort`)
    * `:continue_rebase` - continue after conflict resolution (`--continue`)
    * `:skip` - skip current patch (`--skip`)
    * `:autostash` - automatically stash/unstash (`--autostash`)
    * `:autosquash` / `:no_autosquash` - autosquash fixup commits
    * `:keep_empty` / `:no_keep_empty` - keep empty commits
    * `:rebase_merges` - recreate merge commits (`--rebase-merges`)
    * `:force_rebase` - force rebase (`--force-rebase`)
    * `:verbose` / `:quiet` - output verbosity
    * `:stat` / `:no_stat` - show diffstat

  Note: `--interactive` is not supported as it requires an editor.

  ## Examples

      Git.rebase(upstream: "main")
      Git.rebase(upstream: "main", autostash: true)
      Git.rebase(abort: true)

  """
  @spec rebase(keyword()) ::
          {:ok, Git.RebaseResult.t()} | {:ok, :done} | {:error, term()}
  def rebase(opts \\ []) do
    {config, rest} = Keyword.pop(opts, :config, Config.new())
    command = struct!(Git.Commands.Rebase, rest)
    Git.Command.run(Git.Commands.Rebase, command, config)
  end

  @doc """
  Runs `git cherry-pick` to apply commits from another branch.

  ## Options

    * `:config` - a `Git.Config` struct (default: `Git.Config.new()`)
    * `:commits` - list of commit SHAs or refs to cherry-pick
    * `:no_commit` - apply without committing (`--no-commit`)
    * `:abort` - abort in-progress cherry-pick (`--abort`)
    * `:continue_pick` - continue after conflict resolution (`--continue`)
    * `:skip` - skip current commit (`--skip`)
    * `:mainline` - parent number for merge commits (`-m`)
    * `:signoff` - add Signed-off-by (`--signoff`)
    * `:allow_empty` - allow empty commits (`--allow-empty`)
    * `:strategy` - merge strategy (`--strategy`)
    * `:strategy_option` - strategy option (`--strategy-option`)

  Note: `--edit` is not supported as it requires an editor.

  ## Examples

      Git.cherry_pick(commits: ["abc1234"])
      Git.cherry_pick(commits: ["abc1234", "def5678"], no_commit: true)
      Git.cherry_pick(abort: true)

  """
  @spec cherry_pick(keyword()) ::
          {:ok, Git.CherryPickResult.t()} | {:ok, :done} | {:error, term()}
  def cherry_pick(opts \\ []) do
    {config, rest} = Keyword.pop(opts, :config, Config.new())
    command = struct!(Git.Commands.CherryPick, rest)
    Git.Command.run(Git.Commands.CherryPick, command, config)
  end

  @doc """
  Runs `git show` to display information about a git object.

  ## Options

    * `:config` - a `Git.Config` struct (default: `Git.Config.new()`)
    * `:ref` - the object to show (default: `"HEAD"`)
    * `:format` - custom format string (`--format`)
    * `:stat` - show diffstat (`--stat`)
    * `:name_only` - show only file names (`--name-only`)
    * `:name_status` - show file names and status (`--name-status`)
    * `:no_patch` - suppress diff output (`--no-patch`)
    * `:abbrev_commit` - abbreviate commit hash (`--abbrev-commit`)
    * `:oneline` - one-line format (`--oneline`)
    * `:diff_filter` - filter diffs (`--diff-filter`)
    * `:quiet` - suppress output (`--quiet`)

  ## Examples

      Git.show()
      Git.show(ref: "HEAD~1", stat: true)
      Git.show(ref: "v1.0.0", no_patch: true)

  """
  @spec show(keyword()) :: {:ok, Git.ShowResult.t()} | {:error, term()}
  def show(opts \\ []) do
    {config, rest} = Keyword.pop(opts, :config, Config.new())
    command = struct!(Git.Commands.Show, rest)
    Git.Command.run(Git.Commands.Show, command, config)
  end

  @doc """
  Runs `git rev-parse` to resolve refs and query repository information.

  ## Options

    * `:config` - a `Git.Config` struct (default: `Git.Config.new()`)
    * `:ref` - ref to resolve (e.g., `"HEAD"`, `"main"`)
    * `:short` - abbreviate SHA (`--short`, or integer for length)
    * `:verify` - verify ref exists (`--verify`)
    * `:show_toplevel` - show repository root (`--show-toplevel`)
    * `:is_inside_work_tree` - check if inside worktree (`--is-inside-work-tree`)
    * `:is_inside_git_dir` - check if inside .git dir (`--is-inside-git-dir`)
    * `:is_bare_repository` - check if bare repo (`--is-bare-repository`)
    * `:git_dir` - show .git directory (`--git-dir`)
    * `:abbrev_ref` - symbolic ref name (`--abbrev-ref`)
    * `:symbolic_full_name` - full symbolic name (`--symbolic-full-name`)
    * `:show_cdup` - show path to root (`--show-cdup`)
    * `:show_prefix` - show path from root (`--show-prefix`)
    * `:absolute_git_dir` - absolute .git path (`--absolute-git-dir`)
    * `:git_common_dir` - common git dir (`--git-common-dir`)

  ## Examples

      Git.rev_parse(ref: "HEAD")
      Git.rev_parse(show_toplevel: true)
      Git.rev_parse(abbrev_ref: true, ref: "HEAD")

  """
  @spec rev_parse(keyword()) :: {:ok, String.t()} | {:error, term()}
  def rev_parse(opts \\ []) do
    {config, rest} = Keyword.pop(opts, :config, Config.new())
    command = struct!(Git.Commands.RevParse, rest)
    Git.Command.run(Git.Commands.RevParse, command, config)
  end

  @doc """
  Runs `git clean` to remove untracked files from the working tree.

  ## Options

    * `:config` - a `Git.Config` struct (default: `Git.Config.new()`)
    * `:force` - required for actual removal (`-f`)
    * `:directories` - also remove untracked directories (`-d`)
    * `:ignored` - also remove ignored files (`-x`)
    * `:only_ignored` - only remove ignored files (`-X`)
    * `:dry_run` - show what would be removed (`-n`)
    * `:exclude` - exclude pattern (`-e`)
    * `:quiet` - suppress output (`-q`)
    * `:paths` - paths to clean

  ## Examples

      Git.clean(dry_run: true)
      Git.clean(force: true, directories: true)

  """
  @spec clean(keyword()) :: {:ok, [String.t()]} | {:error, term()}
  def clean(opts \\ []) do
    {config, rest} = Keyword.pop(opts, :config, Config.new())
    command = struct!(Git.Commands.Clean, rest)
    Git.Command.run(Git.Commands.Clean, command, config)
  end

  @doc """
  Runs `git blame` to show line-by-line authorship of a file.

  The file path is required as the first argument.

  ## Options

    * `:config` - a `Git.Config` struct (default: `Git.Config.new()`)
    * `:lines` - line range (`-L start,end` or `-L :funcname`)
    * `:rev` - blame at specific revision
    * `:show_email` - show author email (`-e`)
    * `:show_name` - show author name (`--show-name`)
    * `:date` - date format (`--date=format`)
    * `:reverse` - show reverse blame (`--reverse`)
    * `:first_parent` - follow only first parent (`--first-parent`)
    * `:encoding` - output encoding (`--encoding`)
    * `:root` - do not treat root commits specially (`--root`)

  ## Examples

      Git.blame("lib/my_file.ex")
      Git.blame("lib/my_file.ex", lines: "1,10")
      Git.blame("lib/my_file.ex", rev: "HEAD~5")

  """
  @spec blame(String.t(), keyword()) :: {:ok, [Git.BlameEntry.t()]} | {:error, term()}
  def blame(file, opts \\ []) when is_binary(file) do
    {config, rest} = Keyword.pop(opts, :config, Config.new())
    command = struct!(Git.Commands.Blame, [{:file, file} | rest])
    Git.Command.run(Git.Commands.Blame, command, config)
  end

  @doc """
  Runs `git mv` to move or rename a tracked file.

  ## Options

    * `:config` - a `Git.Config` struct (default: `Git.Config.new()`)
    * `:force` - force move (`-f`)
    * `:dry_run` - dry run (`-n`)
    * `:verbose` - verbose output (`-v`)
    * `:skip_errors` - skip errors (`-k`)

  ## Examples

      Git.mv("old_name.ex", "new_name.ex")
      Git.mv("old_name.ex", "new_name.ex", force: true)

  """
  @spec mv(String.t(), String.t(), keyword()) :: {:ok, :done} | {:error, term()}
  def mv(source, destination, opts \\ []) when is_binary(source) and is_binary(destination) do
    {config, rest} = Keyword.pop(opts, :config, Config.new())

    command =
      struct!(Git.Commands.Mv, [{:source, source}, {:destination, destination} | rest])

    Git.Command.run(Git.Commands.Mv, command, config)
  end

  @doc """
  Runs `git rm` to remove files from the working tree and index.

  ## Options

    * `:config` - a `Git.Config` struct (default: `Git.Config.new()`)
    * `:files` - list of files to remove (required)
    * `:cached` - only remove from index (`--cached`)
    * `:force` - force removal (`-f`)
    * `:recursive` - recursive removal (`-r`)
    * `:dry_run` - dry run (`-n`)
    * `:quiet` - suppress output (`-q`)

  ## Examples

      Git.rm(files: ["old_file.ex"])
      Git.rm(files: ["lib/"], recursive: true, cached: true)

  """
  @spec rm(keyword()) :: {:ok, :done} | {:error, term()}
  def rm(opts \\ []) do
    {config, rest} = Keyword.pop(opts, :config, Config.new())
    command = struct!(Git.Commands.Rm, rest)
    Git.Command.run(Git.Commands.Rm, command, config)
  end

  @doc """
  Runs `git revert` to create a commit that undoes a previous commit.

  ## Options

    * `:config` - a `Git.Config` struct (default: `Git.Config.new()`)
    * `:commits` - list of commit refs to revert
    * `:no_commit` - revert without committing (`--no-commit`)
    * `:abort` - abort in-progress revert (`--abort`)
    * `:continue_revert` - continue after conflict resolution (`--continue`)
    * `:skip` - skip current commit (`--skip`)
    * `:mainline` - parent number for merge commits (`-m`)
    * `:signoff` - add Signed-off-by (`--signoff`)
    * `:no_edit` - use default commit message (`--no-edit`)
    * `:strategy` - merge strategy (`--strategy`)
    * `:strategy_option` - strategy option (`--strategy-option`)

  ## Examples

      Git.revert(commits: ["abc1234"])
      Git.revert(commits: ["abc1234"], no_commit: true)
      Git.revert(abort: true)

  """
  @spec revert(keyword()) ::
          {:ok, Git.RevertResult.t()} | {:ok, :done} | {:error, term()}
  def revert(opts \\ []) do
    {config, rest} = Keyword.pop(opts, :config, Config.new())
    command = struct!(Git.Commands.Revert, rest)
    Git.Command.run(Git.Commands.Revert, command, config)
  end

  @doc """
  Runs `git worktree` to manage linked working trees.

  ## Options

    * `:config` - a `Git.Config` struct (default: `Git.Config.new()`)
    * `:list` - list worktrees (default `true`)
    * `:add_path` - path for new worktree
    * `:add_branch` - existing branch for new worktree
    * `:add_new_branch` - create new branch with `-b`
    * `:remove_path` - worktree path to remove
    * `:prune` - prune stale worktree info
    * `:force` - force operation (`-f`)
    * `:detach` - detach HEAD (`--detach`)
    * `:lock` - lock new worktree (`--lock`)

  ## Examples

      Git.worktree()
      Git.worktree(add_path: "/tmp/feature", add_new_branch: "feat/new")
      Git.worktree(remove_path: "/tmp/feature", force: true)

  """
  @spec worktree(keyword()) ::
          {:ok, [Git.Worktree.t()]} | {:ok, :done} | {:error, term()}
  def worktree(opts \\ []) do
    {config, rest} = Keyword.pop(opts, :config, Config.new())
    command = struct!(Git.Commands.Worktree, rest)
    Git.Command.run(Git.Commands.Worktree, command, config)
  end

  @doc """
  Runs `git config` to read or write git configuration values.

  ## Options

    * `:config` - a `Git.Config` struct (default: `Git.Config.new()`)
    * `:get` - key to read
    * `:set_key` - key to set (requires `:set_value`)
    * `:set_value` - value to set (requires `:set_key`)
    * `:unset` - key to unset
    * `:list` - list all config (`--list`)
    * `:global` - use global config (`--global`)
    * `:local` - use local config (`--local`)
    * `:system` - use system config (`--system`)
    * `:get_regexp` - get keys matching pattern (`--get-regexp`)
    * `:add` - add value for multi-valued key (`--add`)
    * `:type` - type constraint (`--type`)
    * `:default` - default value for get (`--default`)
    * `:name_only` - show only key names (`--name-only`)

  ## Examples

      Git.git_config(get: "user.name")
      Git.git_config(set_key: "user.name", set_value: "Test User", local: true)
      Git.git_config(list: true, global: true)

  """
  @spec git_config(keyword()) ::
          {:ok, String.t()} | {:ok, [{String.t(), String.t()}]} | {:ok, :done} | {:error, term()}
  def git_config(opts \\ []) do
    {config, rest} = Keyword.pop(opts, :config, Config.new())
    command = struct!(Git.Commands.GitConfig, rest)
    Git.Command.run(Git.Commands.GitConfig, command, config)
  end

  @doc """
  Runs `git ls-files` to list files in the index and working tree.

  ## Options

    * `:config` - a `Git.Config` struct (default: `Git.Config.new()`)
    * `:cached` - show cached files (`--cached`)
    * `:deleted` - show deleted files (`--deleted`)
    * `:modified` - show modified files (`--modified`)
    * `:others` - show untracked files (`--others`)
    * `:ignored` - show ignored files (`--ignored`)
    * `:stage` - show staged info (`-s`)
    * `:unmerged` - show unmerged files (`-u`)
    * `:exclude_standard` - use standard exclusions (`--exclude-standard`)
    * `:exclude` - exclude pattern (`--exclude`)
    * `:full_name` - show full paths (`--full-name`)
    * `:paths` - filter by paths

  ## Examples

      Git.ls_files()
      Git.ls_files(others: true, exclude_standard: true)
      Git.ls_files(modified: true)

  """
  @spec ls_files(keyword()) :: {:ok, [String.t()]} | {:error, term()}
  def ls_files(opts \\ []) do
    {config, rest} = Keyword.pop(opts, :config, Config.new())
    command = struct!(Git.Commands.LsFiles, rest)
    Git.Command.run(Git.Commands.LsFiles, command, config)
  end

  @doc """
  Runs `git reflog` to show the reference log.

  ## Options

    * `:config` - a `Git.Config` struct (default: `Git.Config.new()`)
    * `:ref` - ref to show reflog for (default: HEAD)
    * `:max_count` - limit number of entries (`-n`)
    * `:all` - show reflog for all refs (`--all`)
    * `:date` - date format (`--date=format`)

  ## Examples

      Git.reflog()
      Git.reflog(max_count: 10)
      Git.reflog(ref: "main")

  """
  @spec reflog(keyword()) :: {:ok, [Git.ReflogEntry.t()]} | {:error, term()}
  def reflog(opts \\ []) do
    {config, rest} = Keyword.pop(opts, :config, Config.new())
    command = struct!(Git.Commands.Reflog, rest)
    Git.Command.run(Git.Commands.Reflog, command, config)
  end

  @doc """
  Runs `git bisect` to find the commit that introduced a bug.

  ## Options

    * `:config` - a `Git.Config` struct (default: `Git.Config.new()`)
    * `:start` - start bisect session
    * `:bad` - mark ref as bad (or current HEAD if `true`)
    * `:good` - mark ref as good (or current HEAD if `true`)
    * `:reset` - end bisect session
    * `:skip` - skip current commit
    * `:log` - show bisect log
    * `:new_ref` - alias for bad (newer git)
    * `:old_ref` - alias for good (newer git)
    * `:replay` - replay bisect from file

  Note: `bisect run` and `bisect visualize` are not supported.

  ## Examples

      Git.bisect(start: true)
      Git.bisect(bad: "HEAD")
      Git.bisect(good: "v1.0.0")
      Git.bisect(reset: true)

  """
  @spec bisect(keyword()) :: {:ok, Git.BisectResult.t()} | {:ok, :done} | {:error, term()}
  def bisect(opts \\ []) do
    {config, rest} = Keyword.pop(opts, :config, Config.new())
    command = struct!(Git.Commands.Bisect, rest)
    Git.Command.run(Git.Commands.Bisect, command, config)
  end
end
