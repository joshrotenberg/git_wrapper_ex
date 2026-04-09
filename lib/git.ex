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
    * `:name_only` - list only file paths (default `false`)
    * `:name_status` - list file paths with status letters (default `false`)
    * `:ref` - compare against this ref (e.g., `"HEAD~1"`)
    * `:ref_end` - second ref for two-ref comparisons (requires `:ref`)
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
  Runs `git submodule` to manage submodules.

  ## Options

    * `:config` - a `Git.Config` struct (default: `Git.Config.new()`)
    * `:status` - show submodule status (default `true`)
    * `:init` - initialize submodules
    * `:update` - update submodules
    * `:add_url` - URL to add as submodule
    * `:add_path` - path for new submodule
    * `:deinit` - path to deinit
    * `:sync` - sync URLs
    * `:summary` - show summary of changes
    * `:set_branch` - set branch for submodule (requires `:path`)
    * `:set_url` - set URL for submodule (requires `:path`)
    * `:path` - submodule path for set-branch/set-url/init/update
    * `:recursive` - apply recursively (`--recursive`)
    * `:force` - force operation (`--force`)
    * `:remote` - use remote tracking branch (`--remote`)
    * `:merge` - merge into working tree (`--merge`)
    * `:rebase` - rebase onto new commits (`--rebase`)
    * `:depth` - shallow clone depth (`--depth`)
    * `:reference` - reference repository (`--reference`)
    * `:name` - logical name for add (`--name`)
    * `:branch` - branch for add (`-b`)
    * `:quiet` - suppress output (`-q`)
    * `:all` - all submodules for deinit (`--all`)

  The `foreach` subcommand is not supported because it requires an arbitrary
  shell command, which does not fit the structured command model.

  ## Examples

      Git.submodule()
      Git.submodule(add_url: "https://example.com/lib.git", add_path: "vendor/lib")
      Git.submodule(init: true)
      Git.submodule(update: true, recursive: true)
      Git.submodule(deinit: "vendor/lib", force: true)

  """
  @spec submodule(keyword()) ::
          {:ok, [Git.SubmoduleEntry.t()]} | {:ok, :done} | {:ok, String.t()} | {:error, term()}
  def submodule(opts \\ []) do
    {config, rest} = Keyword.pop(opts, :config, Config.new())
    command = struct!(Git.Commands.Submodule, rest)
    Git.Command.run(Git.Commands.Submodule, command, config)
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

  @doc """
  Runs `git grep` to search tracked files for a pattern.

  The search pattern is required as the first argument.

  ## Options

    * `:config` - a `Git.Config` struct (default: `Git.Config.new()`)
    * `:paths` - list of paths to restrict search to
    * `:line_number` - show line numbers (`-n`, default `true`)
    * `:count` - show count per file (`-c`)
    * `:files_with_matches` - show only filenames with matches (`-l`)
    * `:files_without_match` - show only filenames without matches (`-L`)
    * `:ignore_case` - case insensitive search (`-i`)
    * `:word_regexp` - match whole words only (`-w`)
    * `:extended_regexp` - use extended regex (`-E`)
    * `:fixed_strings` - treat pattern as fixed string (`-F`)
    * `:perl_regexp` - use Perl-compatible regex (`-P`)
    * `:invert_match` - show non-matching lines (`--invert-match`)
    * `:max_count` - max matches per file (`-m`)
    * `:context` - show context lines (`-C`)
    * `:before_context` - show lines before match (`-B`)
    * `:after_context` - show lines after match (`-A`)
    * `:show_function` - show surrounding function (`-p`)
    * `:heading` - show filename as heading (`--heading`)
    * `:break` - add blank line between file results (`--break`)
    * `:untracked` - also search untracked files (`--untracked`)
    * `:no_index` - search files not managed by git (`--no-index`)
    * `:recurse_submodules` - search in submodules (`--recurse-submodules`)
    * `:quiet` - suppress output, exit with status (`-q`)
    * `:all_match` - require all patterns to match (`--all-match`)
    * `:ref` - search in a specific ref (e.g. `"HEAD"`, `"v1.0"`)

  ## Examples

      Git.grep("defmodule")
      Git.grep("TODO", ignore_case: true)
      Git.grep("hello", files_with_matches: true)
      Git.grep("pattern", ref: "HEAD~5", paths: ["lib/"])

  """
  @spec grep(String.t(), keyword()) :: {:ok, [Git.GrepResult.t()]} | {:error, term()}
  def grep(pattern, opts \\ []) when is_binary(pattern) do
    {config, rest} = Keyword.pop(opts, :config, Config.new())
    command = struct!(Git.Commands.Grep, [{:pattern, pattern} | rest])
    Git.Command.run(Git.Commands.Grep, command, config)
  end

  @doc """
  Runs `git describe` to find the most recent tag reachable from a commit.

  ## Options

    * `:config` - a `Git.Config` struct (default: `Git.Config.new()`)
    * `:ref` - commit to describe (default: `nil`, describes HEAD)
    * `:tags` - use any tag, not just annotated (`--tags`)
    * `:all` - use any ref (`--all`)
    * `:long` - always use long format (`--long`)
    * `:first_parent` - follow only first parent (`--first-parent`)
    * `:abbrev` - abbreviation length (`--abbrev=N`)
    * `:exact_match` - only output exact matches (`--exact-match`)
    * `:dirty` - describe with dirty suffix (`--dirty` or `--dirty=MARK`)
    * `:always` - show abbreviated commit if no tag found (`--always`)
    * `:match` - only consider tags matching glob (`--match=`)
    * `:exclude` - exclude tags matching glob (`--exclude=`)
    * `:candidates` - number of candidate tags to consider (`--candidates=N`)
    * `:broken` - describe broken working tree as broken (`--broken`)

  ## Examples

      Git.describe(tags: true)
      Git.describe(always: true, abbrev: 7)
      Git.describe(exact_match: true, ref: "v1.0")

  """
  @spec describe(keyword()) :: {:ok, String.t()} | {:error, term()}
  def describe(opts \\ []) do
    {config, rest} = Keyword.pop(opts, :config, Config.new())
    command = struct!(Git.Commands.Describe, rest)
    Git.Command.run(Git.Commands.Describe, command, config)
  end

  @doc """
  Runs `git shortlog` to summarize log output by author.

  ## Options

    * `:config` - a `Git.Config` struct (default: `Git.Config.new()`)
    * `:numbered` - sort by number of commits (`-n`)
    * `:summary` - suppress commit descriptions, show count only (`-s`)
    * `:email` - show email addresses (`-e`)
    * `:group` - group by field (`--group=`, e.g. `"author"`, `"committer"`)
    * `:ref` - ref range (e.g. `"v1.0..HEAD"`)
    * `:max_count` - limit number of commits (`--max-count=N`)
    * `:since` - show commits after date (`--since=`)
    * `:until_date` - show commits before date (`--until=`)
    * `:all` - all branches (`--all`)

  ## Examples

      Git.shortlog(summary: true, numbered: true)
      Git.shortlog(email: true, ref: "v1.0..HEAD")

  """
  @spec shortlog(keyword()) :: {:ok, [Git.ShortlogEntry.t()]} | {:error, term()}
  def shortlog(opts \\ []) do
    {config, rest} = Keyword.pop(opts, :config, Config.new())
    command = struct!(Git.Commands.Shortlog, rest)
    Git.Command.run(Git.Commands.Shortlog, command, config)
  end

  @doc """
  Runs `git format-patch` to generate patch files from commits.

  ## Options

    * `:config` - a `Git.Config` struct (default: `Git.Config.new()`)
    * `:ref` - revision range (required, e.g. `"HEAD~3"`, `"v1.0..v2.0"`)
    * `:output_directory` - output directory (`-o`)
    * `:numbered` - number patches in subject (`-n`)
    * `:cover_letter` - generate cover letter (`--cover-letter`)
    * `:stdout` - output patches to stdout (`--stdout`)
    * `:from` - set From header (`--from=`)
    * `:subject_prefix` - subject prefix (`--subject-prefix=`)
    * `:no_stat` - suppress diffstat (`--no-stat`)
    * `:start_number` - start numbering at N (`--start-number=N`)
    * `:signature` - signature string (`--signature=`)
    * `:no_signature` - suppress signature (`--no-signature`)
    * `:quiet` - suppress output of file names (`-q`)
    * `:zero_commit` - use zero commit hash in From header (`--zero-commit`)
    * `:base` - record base tree info (`--base=`)

  ## Examples

      Git.format_patch(ref: "HEAD~3", output_directory: "/tmp/patches")
      Git.format_patch(ref: "v1.0..v2.0", stdout: true)

  """
  @spec format_patch(keyword()) :: {:ok, [String.t()]} | {:ok, String.t()} | {:error, term()}
  def format_patch(opts \\ []) do
    {config, rest} = Keyword.pop(opts, :config, Config.new())
    command = struct!(Git.Commands.FormatPatch, rest)
    Git.Command.run(Git.Commands.FormatPatch, command, config)
  end

  @doc """
  Runs `git archive` to create an archive of files from a named tree.

  Creates a tar, tar.gz, or zip archive of the repository contents.
  The `output` option is currently required because git writes binary
  archive data to stdout when no output file is specified, which cannot
  be reliably captured as a string.

  ## Options

    * `:config` - a `Git.Config` struct (default: `Git.Config.new()`)
    * `:ref` - tree-ish to archive (default `"HEAD"`)
    * `:format` - archive format: `"tar"`, `"tar.gz"`, or `"zip"` (`--format=`)
    * `:output` - output file path (`--output=`)
    * `:prefix` - prepend prefix to each filename (`--prefix=`)
    * `:paths` - restrict archive to these paths (after `--`)
    * `:remote` - retrieve archive from a remote repository (`--remote=`)
    * `:worktree_attributes` - use worktree attributes (`--worktree-attributes`)
    * `:verbose` - report progress to stderr (`-v`)

  ## Examples

      Git.archive(output: "/tmp/repo.tar.gz", format: "tar.gz")
      Git.archive(output: "/tmp/lib.zip", format: "zip", paths: ["lib/"])
      Git.archive(output: "/tmp/v1.tar", ref: "v1.0.0", prefix: "project/")

  """
  @spec archive(keyword()) :: {:ok, :done} | {:error, term()}
  def archive(opts \\ []) do
    {config, rest} = Keyword.pop(opts, :config, Config.new())
    command = struct!(Git.Commands.Archive, rest)
    Git.Command.run(Git.Commands.Archive, command, config)
  end

  @doc """
  Runs `git ls-remote` to list references in a remote repository.

  Returns a list of `Git.LsRemoteEntry` structs containing the SHA
  and ref name for each reference in the remote.

  ## Options

    * `:config` - a `Git.Config` struct (default: `Git.Config.new()`)
    * `:remote` - remote name or URL (default: origin)
    * `:heads` - show only heads (`--heads`)
    * `:tags` - show only tags (`--tags`)
    * `:refs` - pattern to filter refs
    * `:sort` - sort key (`--sort=`)
    * `:symref` - show underlying ref for symbolic refs (`--symref`)
    * `:quiet` - suppress output, exit with status only (`-q`)
    * `:exit_code` - exit with status 2 when no matching refs (`--exit-code`)

  ## Examples

      Git.ls_remote(remote: "origin")
      Git.ls_remote(heads: true)
      Git.ls_remote(tags: true, remote: "https://github.com/owner/repo.git")

  """
  @spec ls_remote(keyword()) :: {:ok, [Git.LsRemoteEntry.t()]} | {:error, term()}
  def ls_remote(opts \\ []) do
    {config, rest} = Keyword.pop(opts, :config, Config.new())
    command = struct!(Git.Commands.LsRemote, rest)
    Git.Command.run(Git.Commands.LsRemote, command, config)
  end

  @doc """
  Runs `git ls-tree` to list the contents of a tree object.

  Returns a list of `Git.TreeEntry` structs with mode, type, SHA, path,
  and optionally size. When `:name_only` is `true`, returns a list of
  path strings instead.

  ## Options

    * `:config` - a `Git.Config` struct (default: `Git.Config.new()`)
    * `:ref` - tree-ish to list (default `"HEAD"`)
    * `:recursive` - recurse into subtrees (`-r`)
    * `:tree_only` - show only tree entries, not blobs (`-d`)
    * `:long` - include object size (`-l`/`--long`)
    * `:name_only` - show only paths (`--name-only`)
    * `:abbrev` - abbreviate SHA to N characters (`--abbrev=N`)
    * `:full_name` - show full path names (`--full-name`)
    * `:full_tree` - show full tree regardless of current directory (`--full-tree`)
    * `:path` - restrict to this path (after `--`)

  ## Examples

      Git.ls_tree()
      Git.ls_tree(recursive: true)
      Git.ls_tree(name_only: true, ref: "main")
      Git.ls_tree(long: true, path: "lib/")

  """
  @spec ls_tree(keyword()) :: {:ok, [Git.TreeEntry.t()] | [String.t()]} | {:error, term()}
  def ls_tree(opts \\ []) do
    {config, rest} = Keyword.pop(opts, :config, Config.new())
    command = struct!(Git.Commands.LsTree, rest)
    Git.Command.run(Git.Commands.LsTree, command, config)
  end

  @doc """
  Runs `git rev-list` to list commit objects.

  Returns a list of SHAs by default. With `count: true` returns an integer.
  With `left_right: true` and `count: true` returns a map with `:left` and
  `:right` counts.

  ## Options

    * `:config` - a `Git.Config` struct (default: `Git.Config.new()`)
    * `:ref` - rev range (e.g. `"HEAD"`, `"main..feature"`)
    * `:max_count` - limit number of commits (`--max-count=N`)
    * `:skip` - skip N commits (`--skip=N`)
    * `:count` - output a count instead of SHAs (`--count`)
    * `:left_right` - mark which side of a symmetric diff (`--left-right`)
    * `:ancestry_path` - only show commits on the ancestry path (`--ancestry-path`)
    * `:first_parent` - follow only first parent (`--first-parent`)
    * `:merges` - only show merge commits (`--merges`)
    * `:no_merges` - exclude merge commits (`--no-merges`)
    * `:reverse` - reverse output order (`--reverse`)
    * `:since` - show commits after date (`--since=`)
    * `:until_date` - show commits before date (`--until=`)
    * `:author` - filter by author (`--author=`)
    * `:all` - list objects from all refs (`--all`)
    * `:objects` - list objects, not just commits (`--objects`)
    * `:no_walk` - do not traverse ancestors (`--no-walk`)

  ## Examples

      Git.rev_list(ref: "HEAD", max_count: 10)
      Git.rev_list(ref: "main..feature", count: true)
      Git.rev_list(ref: "main...feature", left_right: true, count: true)

  """
  @spec rev_list(keyword()) ::
          {:ok, [String.t()] | integer() | map()} | {:error, term()}
  def rev_list(opts \\ []) do
    {config, rest} = Keyword.pop(opts, :config, Config.new())
    command = struct!(Git.Commands.RevList, rest)
    Git.Command.run(Git.Commands.RevList, command, config)
  end

  @doc """
  Runs `git merge-base` to find the best common ancestor(s).

  By default returns a single ancestor SHA. With `is_ancestor: true`,
  returns a boolean indicating whether the first commit is an ancestor
  of the second. With `all: true` or `independent: true`, returns a
  list of SHAs.

  ## Options

    * `:config` - a `Git.Config` struct (default: `Git.Config.new()`)
    * `:commits` - list of commit refs to compare (two or more)
    * `:is_ancestor` - check if first is ancestor of second (`--is-ancestor`)
    * `:fork_point` - find fork point (`--fork-point`)
    * `:octopus` - find octopus merge base (`--octopus`)
    * `:all` - output all merge bases (`--all`)
    * `:independent` - list independent commits (`--independent`)

  ## Examples

      Git.merge_base(commits: ["main", "feature"])
      Git.merge_base(commits: ["main", "feature"], is_ancestor: true)
      Git.merge_base(commits: ["main", "feature"], all: true)

  """
  @spec merge_base(keyword()) ::
          {:ok, String.t() | boolean() | [String.t()]} | {:error, term()}
  def merge_base(opts \\ []) do
    {config, rest} = Keyword.pop(opts, :config, Config.new())
    command = struct!(Git.Commands.MergeBase, rest)
    Git.Command.run(Git.Commands.MergeBase, command, config)
  end

  @doc """
  Runs `git cherry` to find commits not yet applied upstream.

  Returns a list of `Git.CherryEntry` structs. Each entry indicates
  whether a commit has already been applied upstream and includes the
  SHA (and subject when `verbose: true`).

  ## Options

    * `:config` - a `Git.Config` struct (default: `Git.Config.new()`)
    * `:upstream` - upstream branch (required)
    * `:head` - head branch (default: HEAD)
    * `:limit` - limit ref
    * `:verbose` - include commit subject (`-v`)

  ## Examples

      Git.cherry(upstream: "main")
      Git.cherry(upstream: "main", head: "feature", verbose: true)

  """
  @spec cherry(keyword()) :: {:ok, [Git.CherryEntry.t()]} | {:error, term()}
  def cherry(opts \\ []) do
    {config, rest} = Keyword.pop(opts, :config, Config.new())
    command = struct!(Git.Commands.Cherry, rest)
    Git.Command.run(Git.Commands.Cherry, command, config)
  end

  @doc """
  Runs `git range-diff` to compare two sequences of commits.

  Supports both the two-range form (using `range1` and `range2`) and the
  three-argument form (using `rev1`, `rev2`, and `rev3`).

  ## Options

    * `:config` - a `Git.Config` struct (default: `Git.Config.new()`)
    * `:range1` - first revision range (e.g. `"main..topic-v1"`)
    * `:range2` - second revision range (e.g. `"main..topic-v2"`)
    * `:rev1` - base revision (three-arg form)
    * `:rev2` - first revision (three-arg form)
    * `:rev3` - second revision (three-arg form)
    * `:stat` - show diffstat (`--stat`)
    * `:no_patch` - suppress diff output (`--no-patch`)
    * `:creation_factor` - percentage for matching commits (`--creation-factor=N`)
    * `:no_dual_color` - disable dual-color mode (`--no-dual-color`)
    * `:left_only` - show only left-side commits (`--left-only`)
    * `:right_only` - show only right-side commits (`--right-only`)
    * `:no_notes` - do not show notes (`--no-notes`)

  ## Examples

      Git.range_diff(range1: "main..topic-v1", range2: "main..topic-v2")
      Git.range_diff(rev1: "main", rev2: "topic-v1", rev3: "topic-v2")
      Git.range_diff(range1: "main..v1", range2: "main..v2", stat: true)

  """
  @spec range_diff(keyword()) :: {:ok, String.t()} | {:error, term()}
  def range_diff(opts \\ []) do
    {config, rest} = Keyword.pop(opts, :config, Config.new())
    command = struct!(Git.Commands.RangeDiff, rest)
    Git.Command.run(Git.Commands.RangeDiff, command, config)
  end

  @doc """
  Runs `git sparse-checkout` to manage sparse-checkout patterns.

  ## Options

    * `:config` - a `Git.Config` struct (default: `Git.Config.new()`)
    * `:init` - initialize sparse-checkout
    * `:set` - list of patterns to set
    * `:add` - list of patterns to add
    * `:list` - list current patterns (default `true`)
    * `:disable` - disable sparse-checkout
    * `:reapply` - reapply current sparse-checkout rules
    * `:check_rules` - check sparse-checkout rules
    * `:cone` - use cone mode (`--cone`)
    * `:no_cone` - use non-cone mode (`--no-cone`)
    * `:sparse_index` - use sparse index (`--sparse-index`)
    * `:no_sparse_index` - do not use sparse index (`--no-sparse-index`)

  ## Examples

      Git.sparse_checkout()
      Git.sparse_checkout(init: true, cone: true)
      Git.sparse_checkout(set: ["src/", "docs/"])
      Git.sparse_checkout(disable: true)

  """
  @spec sparse_checkout(keyword()) ::
          {:ok, [String.t()]} | {:ok, :done} | {:error, term()}
  def sparse_checkout(opts \\ []) do
    {config, rest} = Keyword.pop(opts, :config, Config.new())
    command = struct!(Git.Commands.SparseCheckout, rest)
    Git.Command.run(Git.Commands.SparseCheckout, command, config)
  end

  @doc """
  Runs `git cat-file` to provide content or type/size info for repository objects.

  The object (SHA or ref) is required as the first argument.

  ## Options

    * `:config` - a `Git.Config` struct (default: `Git.Config.new()`)
    * `:type` - show object type (`-t`)
    * `:size` - show object size (`-s`)
    * `:print` - pretty-print object content (`-p`)
    * `:exists` - check if object exists (`-e`); returns `{:ok, true}` or `{:ok, false}`
    * `:textconv` - show content with textconv filter (`--textconv`)
    * `:filters` - show content with filters applied (`--filters`)

  ## Examples

      Git.cat_file("HEAD", type: true)
      Git.cat_file("abc1234", size: true)
      Git.cat_file("HEAD", print: true)
      Git.cat_file("deadbeef", exists: true)

  """
  @spec cat_file(String.t(), keyword()) ::
          {:ok, atom()}
          | {:ok, integer()}
          | {:ok, String.t()}
          | {:ok, boolean()}
          | {:error, term()}
  def cat_file(object, opts \\ []) when is_binary(object) do
    {config, rest} = Keyword.pop(opts, :config, Config.new())
    command = struct!(Git.Commands.CatFile, [{:object, object} | rest])
    Git.Command.run(Git.Commands.CatFile, command, config)
  end

  @doc """
  Runs `git check-ignore` to test whether paths are ignored by `.gitignore`.

  ## Options

    * `:config` - a `Git.Config` struct (default: `Git.Config.new()`)
    * `:paths` - list of paths to check (required)
    * `:verbose` - show matching pattern info (`-v`)
    * `:non_matching` - also show non-matching paths (`-n`, requires `-v`)
    * `:no_index` - do not look at the index (`--no-index`)
    * `:quiet` - suppress output, use exit status only (`-q`)

  ## Examples

      Git.check_ignore(paths: ["build/", "tmp.log"])
      Git.check_ignore(paths: ["src/main.ex"], verbose: true)

  """
  @spec check_ignore(keyword()) :: {:ok, [String.t()] | [map()]} | {:error, term()}
  def check_ignore(opts \\ []) do
    {config, rest} = Keyword.pop(opts, :config, Config.new())
    command = struct!(Git.Commands.CheckIgnore, rest)
    Git.Command.run(Git.Commands.CheckIgnore, command, config)
  end

  @doc """
  Runs `git notes` to manage notes attached to objects.

  ## Options

    * `:config` - a `Git.Config` struct (default: `Git.Config.new()`)
    * `:list` - list notes (default `true`)
    * `:show` - show note for a ref (string)
    * `:add` - add a note (boolean)
    * `:append` - append to an existing note (boolean)
    * `:message` - note message (`-m`, for add/append)
    * `:ref` - commit ref for add/append/show
    * `:force` - overwrite existing note (`-f`)
    * `:remove` - remove note from ref (string)
    * `:prune` - prune notes for unreachable objects (boolean)
    * `:notes_ref` - use alternate notes ref (`--ref=`)

  Note: `notes edit` is not supported because it launches an interactive editor.

  ## Examples

      Git.notes()
      Git.notes(show: "HEAD")
      Git.notes(add: true, message: "review passed", ref: "HEAD")
      Git.notes(remove: "HEAD")

  """
  @spec notes(keyword()) ::
          {:ok, [map()]} | {:ok, String.t()} | {:ok, :done} | {:error, term()}
  def notes(opts \\ []) do
    {config, rest} = Keyword.pop(opts, :config, Config.new())
    command = struct!(Git.Commands.Notes, rest)
    Git.Command.run(Git.Commands.Notes, command, config)
  end

  @doc """
  Runs `git verify-commit` to check the GPG signature of a commit.

  ## Options

    * `:config` - a `Git.Config` struct (default: `Git.Config.new()`)
    * `:verbose` - print the contents of the commit object before verifying (`-v`)
    * `:raw` - print the raw gpg status output (`--raw`)

  ## Examples

      Git.verify_commit("HEAD")
      Git.verify_commit("abc123", verbose: true)

  """
  @spec verify_commit(String.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def verify_commit(commit, opts \\ []) when is_binary(commit) do
    {config, rest} = Keyword.pop(opts, :config, Config.new())
    command = struct!(Git.Commands.VerifyCommit, [{:commit, commit} | rest])
    Git.Command.run(Git.Commands.VerifyCommit, command, config)
  end

  @doc """
  Runs `git verify-tag` to check the GPG signature of a tag.

  ## Options

    * `:config` - a `Git.Config` struct (default: `Git.Config.new()`)
    * `:verbose` - print the contents of the tag object before verifying (`-v`)
    * `:raw` - print the raw gpg status output (`--raw`)
    * `:format` - format string for output (`--format=`)

  ## Examples

      Git.verify_tag("v1.0")
      Git.verify_tag("v1.0", verbose: true)

  """
  @spec verify_tag(String.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def verify_tag(tag, opts \\ []) when is_binary(tag) do
    {config, rest} = Keyword.pop(opts, :config, Config.new())
    command = struct!(Git.Commands.VerifyTag, [{:tag, tag} | rest])
    Git.Command.run(Git.Commands.VerifyTag, command, config)
  end

  @doc """
  Runs `git gc` to clean up unnecessary files and optimize the repository.

  ## Options

    * `:config` - a `Git.Config` struct (default: `Git.Config.new()`)
    * `:aggressive` - more aggressive optimization (`--aggressive`)
    * `:auto` - only run if housekeeping is needed (`--auto`)
    * `:prune` - prune loose objects older than date (`--prune=<date>`)
    * `:no_prune` - do not prune any loose objects (`--no-prune`)
    * `:quiet` - suppress progress output (`--quiet`)
    * `:force` - force gc even if another gc may be running (`--force`)
    * `:keep_largest_pack` - keep the largest pack (`--keep-largest-pack`)

  ## Examples

      Git.gc()
      Git.gc(aggressive: true)
      Git.gc(auto: true)
      Git.gc(prune: "now")

  """
  @spec gc(keyword()) :: {:ok, :done} | {:error, term()}
  def gc(opts \\ []) do
    {config, rest} = Keyword.pop(opts, :config, Config.new())
    command = struct!(Git.Commands.Gc, rest)
    Git.Command.run(Git.Commands.Gc, command, config)
  end

  @doc """
  Runs `git rerere` to reuse recorded resolution of conflicted merges.

  ## Options

    * `:config` - a `Git.Config` struct (default: `Git.Config.new()`)
    * `:status` - show files with recorded resolution (default when no subcommand)
    * `:diff` - show diff of current resolution against recorded resolution
    * `:clear` - clear all recorded resolutions
    * `:forget` - forget resolution for a specific path (string)
    * `:gc` - prune old recorded resolutions
    * `:remaining` - show files that still need resolution

  ## Examples

      Git.rerere()
      Git.rerere(status: true)
      Git.rerere(diff: true)
      Git.rerere(clear: true)
      Git.rerere(forget: "path/to/file")
      Git.rerere(gc: true)
      Git.rerere(remaining: true)

  """
  @spec rerere(keyword()) ::
          {:ok, [String.t()]} | {:ok, String.t()} | {:ok, :done} | {:error, term()}
  def rerere(opts \\ []) do
    {config, rest} = Keyword.pop(opts, :config, Config.new())
    command = struct!(Git.Commands.Rerere, rest)
    Git.Command.run(Git.Commands.Rerere, command, config)
  end

  @doc """
  Runs `git fsck` to verify connectivity and validity of objects.

  ## Options

    * `:config` - a `Git.Config` struct (default: `Git.Config.new()`)
    * `:full` - check objects in all packs and alternate objects (`--full`)
    * `:strict` - enable stricter checking (`--strict`)
    * `:unreachable` - report unreachable objects (`--unreachable`)
    * `:dangling` - report dangling objects (`--dangling`)
    * `:no_dangling` - suppress dangling object warnings (`--no-dangling`)
    * `:no_reflogs` - do not consider reflog entries (`--no-reflogs`)
    * `:connectivity_only` - only check connectivity (`--connectivity-only`)
    * `:root` - report root nodes (`--root`)
    * `:lost_found` - write dangling objects into `.git/lost-found` (`--lost-found`)
    * `:name_objects` - name objects for easier identification (`--name-objects`)
    * `:verbose` - be verbose (`--verbose`)
    * `:progress` - show progress (`--progress`)
    * `:no_progress` - suppress progress (`--no-progress`)

  ## Examples

      Git.fsck()
      Git.fsck(full: true, strict: true)
      Git.fsck(unreachable: true, no_reflogs: true)

  """
  @spec fsck(keyword()) :: {:ok, [map()]} | {:error, term()}
  def fsck(opts \\ []) do
    {config, rest} = Keyword.pop(opts, :config, Config.new())
    command = struct!(Git.Commands.Fsck, rest)
    Git.Command.run(Git.Commands.Fsck, command, config)
  end

  @doc """
  Runs `git bundle` to create, verify, list heads of, or unbundle bundles.

  Exactly one of `:create`, `:verify`, `:list_heads`, or `:unbundle` must be
  set to the bundle file path.

  ## Options

    * `:config` - a `Git.Config` struct (default: `Git.Config.new()`)
    * `:create` - output file path for creating a bundle
    * `:verify` - bundle file path to verify
    * `:list_heads` - bundle file path to list heads from
    * `:unbundle` - bundle file path to unbundle
    * `:rev` - revision range for create (e.g. `"HEAD"`, `"v1.0..v2.0"`)
    * `:all` - include all refs (`--all`, for create)
    * `:quiet` - suppress output (`-q`)
    * `:progress` - show progress (`--progress`)

  ## Examples

      Git.bundle(create: "/tmp/repo.bundle", rev: "HEAD")
      Git.bundle(verify: "/tmp/repo.bundle")
      Git.bundle(list_heads: "/tmp/repo.bundle")

  """
  @spec bundle(keyword()) :: {:ok, term()} | {:error, term()}
  def bundle(opts \\ []) do
    {config, rest} = Keyword.pop(opts, :config, Config.new())
    command = struct!(Git.Commands.Bundle, rest)
    Git.Command.run(Git.Commands.Bundle, command, config)
  end

  @doc """
  Runs `git show-ref` to list references in the local repository.

  ## Options

    * `:config` - a `Git.Config` struct (default: `Git.Config.new()`)
    * `:heads` - only show heads (`--heads`)
    * `:tags` - only show tags (`--tags`)
    * `:verify` - verify a specific ref exists (`--verify`)
    * `:hash` - show only the SHA (`--hash`), or an integer for abbreviated hash
    * `:abbrev` - abbreviate object names to N digits (`--abbrev=N`)
    * `:dereference` - dereference tags (`-d`)
    * `:quiet` - suppress output, useful with `:verify` (`-q`)
    * `:exclude_existing` - filter out existing refs (`--exclude-existing`)
    * `:patterns` - list of ref patterns to match

  ## Examples

      Git.show_ref()
      Git.show_ref(heads: true)
      Git.show_ref(tags: true)
      Git.show_ref(verify: true, patterns: ["refs/heads/main"])
      Git.show_ref(verify: true, quiet: true, patterns: ["refs/heads/main"])

  """
  @spec show_ref(keyword()) :: {:ok, term()} | {:error, term()}
  def show_ref(opts \\ []) do
    {config, rest} = Keyword.pop(opts, :config, Config.new())
    command = struct!(Git.Commands.ShowRef, rest)
    Git.Command.run(Git.Commands.ShowRef, command, config)
  end

  @doc """
  Runs `git switch` to change branches.

  `git switch` is the modern (Git 2.23+) replacement for the branch-switching
  role of `git checkout`. It is more focused and prevents accidental file
  operations.

  ## Options

    * `:config` - a `Git.Config` struct (default: `Git.Config.new()`)
    * `:branch` - branch name to switch to
    * `:create` - create a new branch and switch to it (`-c`)
    * `:force_create` - create or reset a branch and switch to it (`-C`)
    * `:detach` - switch to a commit in detached HEAD state (`--detach`)
    * `:force` - force switch even with uncommitted changes (`--force`)
    * `:discard_changes` - discard local changes (`--discard-changes`)
    * `:merge` - merge local changes into new branch (`--merge`)
    * `:orphan` - create a new orphan branch (`--orphan`)
    * `:guess` - enable/disable branch name guessing from remotes (`--guess`/`--no-guess`)
    * `:track` - set upstream tracking branch (`--track`)

  ## Examples

      Git.switch(branch: "main")
      Git.switch(branch: "feat/new", create: true)
      Git.switch(branch: "v1.0.0", detach: true)

  """
  @spec switch(keyword()) ::
          {:ok, Git.Checkout.t()} | {:ok, :done} | {:error, term()}
  def switch(opts \\ []) do
    {config, rest} = Keyword.pop(opts, :config, Config.new())
    command = struct!(Git.Commands.Switch, rest)
    Git.Command.run(Git.Commands.Switch, command, config)
  end

  @doc """
  Runs `git restore` to restore working tree files.

  `git restore` is the modern (Git 2.23+) replacement for the file-restoration
  role of `git checkout`. It provides explicit control over restoring from the
  index (staged) vs a source commit.

  ## Options

    * `:config` - a `Git.Config` struct (default: `Git.Config.new()`)
    * `:files` - list of file paths to restore
    * `:staged` - restore staged files (unstage, `--staged`)
    * `:worktree` - restore working tree files (`--worktree`)
    * `:source` - restore from a specific commit/ref (`--source`)
    * `:ours` - use our version during conflict (`--ours`)
    * `:theirs` - use their version during conflict (`--theirs`)
    * `:patch` - interactively select hunks (`--patch`)

  ## Examples

      Git.restore(files: ["README.md"])
      Git.restore(files: ["lib/foo.ex"], staged: true)
      Git.restore(files: ["lib/foo.ex"], source: "HEAD~1")
      Git.restore(files: ["lib/foo.ex"], staged: true, worktree: true)

  """
  @spec restore(keyword()) :: {:ok, :done} | {:error, term()}
  def restore(opts \\ []) do
    {config, rest} = Keyword.pop(opts, :config, Config.new())
    command = struct!(Git.Commands.Restore, rest)
    Git.Command.run(Git.Commands.Restore, command, config)
  end

  @doc """
  Runs `git apply` to apply a patch to files and/or the index.

  The function is named `apply_patch` to avoid conflicting with `Kernel.apply/2`.

  ## Options

    * `:config` - a `Git.Config` struct (default: `Git.Config.new()`)
    * `:patch` - path to the patch file (required)
    * `:check` - check if patch applies cleanly without applying (`--check`)
    * `:stat` - show diffstat (`--stat`)
    * `:summary` - show summary (`--summary`)
    * `:cached` - apply to index only (`--cached`)
    * `:index` - apply to index and working tree (`--index`)
    * `:reverse` - apply in reverse (`--reverse`)
    * `:three_way` - attempt 3-way merge (`--3way`)
    * `:verbose` - verbose output (`--verbose`)

  ## Examples

      Git.apply_patch(patch: "fix.patch")
      Git.apply_patch(patch: "fix.patch", check: true)
      Git.apply_patch(patch: "fix.patch", stat: true)

  """
  @spec apply_patch(keyword()) :: {:ok, :done} | {:ok, String.t()} | {:error, term()}
  def apply_patch(opts \\ []) do
    {config, rest} = Keyword.pop(opts, :config, Config.new())
    command = struct!(Git.Commands.Apply, rest)
    Git.Command.run(Git.Commands.Apply, command, config)
  end

  @doc """
  Runs `git am` to apply patches from mailbox-formatted files.

  ## Options

    * `:config` - a `Git.Config` struct (default: `Git.Config.new()`)
    * `:patches` - list of paths to mailbox patch files
    * `:directory` - path to directory of patches
    * `:three_way` - 3-way merge on conflict (`--3way`)
    * `:keep` - keep subject prefix (`--keep`)
    * `:signoff` - add Signed-off-by line (`--signoff`)
    * `:abort` - abort current am session (`--abort`)
    * `:continue_` - continue after resolving conflict (`--continue`)
    * `:skip` - skip current patch (`--skip`)
    * `:quiet` - quiet output (`--quiet`)

  ## Examples

      Git.am(patches: ["0001-fix.patch"])
      Git.am(patches: ["0001-fix.patch"], three_way: true)
      Git.am(abort: true)

  """
  @spec am(keyword()) :: {:ok, :done} | {:error, term()}
  def am(opts \\ []) do
    {config, rest} = Keyword.pop(opts, :config, Config.new())
    command = struct!(Git.Commands.Am, rest)
    Git.Command.run(Git.Commands.Am, command, config)
  end

  @doc """
  Runs `git interpret-trailers` to add or parse trailers in commit messages.

  Trailers are key-value metadata lines at the end of commit messages, such
  as "Signed-off-by:" or "Co-authored-by:".

  ## Options

    * `:config` - a `Git.Config` struct (default: `Git.Config.new()`)
    * `:file` - path to a file containing the commit message
    * `:parse` - only output the trailers (`--only-trailers`)
    * `:trailers` - list of trailers to add, each as `"Key: Value"` (`--trailer`)
    * `:in_place` - edit the file in place (`--in-place`)
    * `:trim_empty` - trim empty trailers (`--trim-empty`)
    * `:where` - where to place new trailers: `"after"`, `"before"`, `"end"`, `"start"` (`--where`)
    * `:if_exists` - action if trailer exists: `"addIfDifferentNeighbor"`, `"addIfDifferent"`, `"add"`, `"replace"`, `"doNothing"` (`--if-exists`)
    * `:if_missing` - action if trailer missing: `"add"`, `"doNothing"` (`--if-missing`)
    * `:unfold` - unfold multi-line trailers (`--unfold`)
    * `:no_divider` - do not treat `---` as divider (`--no-divider`)

  ## Examples

      Git.interpret_trailers(file: "msg.txt", trailers: ["Signed-off-by: Name <email>"])
      Git.interpret_trailers(file: "msg.txt", parse: true)
      Git.interpret_trailers(file: "msg.txt", trailers: ["Acked-by: Name"], in_place: true)

  """
  @spec interpret_trailers(keyword()) :: {:ok, String.t()} | {:error, term()}
  def interpret_trailers(opts \\ []) do
    {config, rest} = Keyword.pop(opts, :config, Config.new())
    command = struct!(Git.Commands.InterpretTrailers, rest)
    Git.Command.run(Git.Commands.InterpretTrailers, command, config)
  end

  @doc """
  Runs `git maintenance` to manage repository maintenance tasks.

  Supports running, starting, stopping, registering, and unregistering
  maintenance tasks such as garbage collection and commit-graph updates.

  ## Options

    * `:config` - a `Git.Config` struct (default: `Git.Config.new()`)
    * `:run` - run maintenance tasks (`run` subcommand)
    * `:start` - start background maintenance (`start` subcommand)
    * `:stop` - stop background maintenance (`stop` subcommand)
    * `:register_` - register repo for maintenance (`register` subcommand)
    * `:unregister` - unregister repo from maintenance (`unregister` subcommand)
    * `:task` - specific task to run (`--task`)
    * `:auto` - only run if needed (`--auto`)
    * `:quiet` - suppress output (`--quiet`)
    * `:schedule` - maintenance schedule: `"hourly"`, `"daily"`, `"weekly"` (`--schedule`)

  ## Examples

      Git.maintenance(run: true)
      Git.maintenance(run: true, task: "gc")
      Git.maintenance(run: true, auto: true)
      Git.maintenance(start: true)
      Git.maintenance(stop: true)

  """
  @spec maintenance(keyword()) :: {:ok, :done} | {:error, term()}
  def maintenance(opts \\ []) do
    {config, rest} = Keyword.pop(opts, :config, Config.new())
    command = struct!(Git.Commands.Maintenance, rest)
    Git.Command.run(Git.Commands.Maintenance, command, config)
  end

  @doc """
  Runs `git for-each-ref` to iterate over refs.

  Iterates over all refs matching the given pattern(s) and formats them
  according to the given format string.

  ## Options

    * `:config` - a `Git.Config` struct (default: `Git.Config.new()`)
    * `:format` - output format string (`--format`)
    * `:sort` - sort key or list of keys (`--sort`)
    * `:count` - limit number of results (`--count`)
    * `:pattern` - ref pattern(s) to match (positional args)
    * `:contains` - only refs containing commit (`--contains`)
    * `:merged` - only refs merged into ref (`--merged`)
    * `:no_merged` - only refs not merged into ref (`--no-merged`)
    * `:points_at` - only refs pointing at object (`--points-at`)

  ## Examples

      Git.for_each_ref(pattern: "refs/heads/", format: "%(refname:short)")
      Git.for_each_ref(sort: "-creatordate", count: 5)

  """
  @spec for_each_ref(keyword()) :: {:ok, String.t()} | {:error, term()}
  def for_each_ref(opts \\ []) do
    {config, rest} = Keyword.pop(opts, :config, Config.new())
    command = struct!(Git.Commands.ForEachRef, rest)
    Git.Command.run(Git.Commands.ForEachRef, command, config)
  end

  @doc """
  Runs `git hash-object` to compute the object ID for a file.

  Computes the object ID value for a file and optionally writes it into
  the object database. Only file-based hashing is supported.

  ## Options

    * `:config` - a `Git.Config` struct (default: `Git.Config.new()`)
    * `:file` - path to the file to hash
    * `:write` - write the object into the database (`-w`)
    * `:type` - object type (`-t`, default "blob")
    * `:literally` - allow hashing malformed objects (`--literally`)

  ## Examples

      Git.hash_object(file: "README.md")
      Git.hash_object(file: "README.md", write: true)

  """
  @spec hash_object(keyword()) :: {:ok, String.t()} | {:error, term()}
  def hash_object(opts \\ []) do
    {config, rest} = Keyword.pop(opts, :config, Config.new())
    command = struct!(Git.Commands.HashObject, rest)
    Git.Command.run(Git.Commands.HashObject, command, config)
  end

  @doc """
  Runs `git symbolic-ref` to read, create, or delete symbolic refs.

  A symbolic ref is a ref that points to another ref (e.g., HEAD
  typically points to a branch ref).

  ## Options

    * `:config` - a `Git.Config` struct (default: `Git.Config.new()`)
    * `:ref` - the symbolic ref to read/write (e.g., "HEAD")
    * `:target` - if set, writes the symbolic ref to point to this target
    * `:short` - shorten the ref name (`--short`)
    * `:delete` - delete the symbolic ref (`--delete`)
    * `:quiet` - suppress error messages (`--quiet`)

  ## Examples

      Git.symbolic_ref(ref: "HEAD")
      Git.symbolic_ref(ref: "HEAD", short: true)
      Git.symbolic_ref(ref: "HEAD", target: "refs/heads/main")

  """
  @spec symbolic_ref(keyword()) :: {:ok, String.t() | :done} | {:error, term()}
  def symbolic_ref(opts \\ []) do
    {config, rest} = Keyword.pop(opts, :config, Config.new())
    command = struct!(Git.Commands.SymbolicRef, rest)
    Git.Command.run(Git.Commands.SymbolicRef, command, config)
  end

  @doc """
  Runs `git update-ref` to update the object name stored in a ref.

  Supports conditional updates (compare-and-swap), reflog messages,
  and deletion of refs.

  ## Options

    * `:config` - a `Git.Config` struct (default: `Git.Config.new()`)
    * `:ref` - the ref to update
    * `:new_value` - new value for the ref
    * `:old_value` - expected current value (for CAS)
    * `:delete` - delete the ref (`-d`)
    * `:create_reflog` - create a reflog entry (`--create-reflog`)
    * `:message` - reflog message (`-m`)
    * `:no_deref` - don't dereference symbolic refs (`--no-deref`)

  ## Examples

      Git.update_ref(ref: "refs/heads/main", new_value: "abc123")
      Git.update_ref(ref: "refs/heads/old", delete: true)

  """
  @spec update_ref(keyword()) :: {:ok, :done} | {:error, term()}
  def update_ref(opts \\ []) do
    {config, rest} = Keyword.pop(opts, :config, Config.new())
    command = struct!(Git.Commands.UpdateRef, rest)
    Git.Command.run(Git.Commands.UpdateRef, command, config)
  end
end
