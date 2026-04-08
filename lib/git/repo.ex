defmodule Git.Repo do
  @moduledoc """
  A stateful repository abstraction for the git CLI wrapper.

  `Git.Repo` holds a `Git.Config` struct and the resolved repository path,
  providing a cleaner API for working with a specific repository. Instead of
  passing `config: config` to every `Git` function, you create a `Repo` and
  call functions on it.

  ## Opening an existing repository

      {:ok, repo} = Git.Repo.open("/path/to/repo")
      {:ok, status} = Git.Repo.status(repo)
      {:ok, commits} = Git.Repo.log(repo, max_count: 5)

  ## Initializing a new repository

      {:ok, repo} = Git.Repo.init("/tmp/new-repo")

  ## Cloning a repository

      {:ok, repo} = Git.Repo.clone("https://github.com/owner/repo.git", "/tmp/clone")

  ## Pipeline pattern

      Git.Repo.open("/path/to/repo")
      |> Git.Repo.run(fn repo ->
        Git.Repo.add(repo, all: true)
        Git.Repo.commit(repo, "feat: new feature")
        {:ok, repo}
      end)
  """

  alias Git.Config

  @type t :: %__MODULE__{
          config: Config.t(),
          path: String.t()
        }

  defstruct [:config, :path]

  # ---------------------------------------------------------------------------
  # Constructors
  # ---------------------------------------------------------------------------

  @doc """
  Opens an existing git repository at `path`.

  Validates that the path exists and is a git repository by calling
  `git rev-parse --show-toplevel`. The resolved toplevel path is stored in
  both the struct and the config's `working_dir`.

  Returns `{:ok, %Git.Repo{}}` on success or `{:error, reason}` on failure.

  ## Examples

      {:ok, repo} = Git.Repo.open("/path/to/repo")
      repo.path  #=> "/path/to/repo"

  """
  @spec open(String.t()) :: {:ok, t()} | {:error, term()}
  def open(path) when is_binary(path) do
    config = Config.new(working_dir: path)

    case Git.rev_parse(show_toplevel: true, config: config) do
      {:ok, toplevel} ->
        toplevel = String.trim(toplevel)
        config = %{config | working_dir: toplevel}
        {:ok, %__MODULE__{config: config, path: toplevel}}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Opens an existing git repository at `path`, raising on error.

  Same as `open/1` but raises on failure.

  ## Examples

      repo = Git.Repo.open!("/path/to/repo")

  """
  @spec open!(String.t()) :: t()
  def open!(path) when is_binary(path) do
    case open(path) do
      {:ok, repo} -> repo
      {:error, reason} -> raise "failed to open repository at #{path}: #{inspect(reason)}"
    end
  end

  @doc """
  Initializes a new git repository at `path`.

  Creates the directory if it does not exist, runs `git init`, and returns
  a `Git.Repo` pointing at the new repository.

  ## Options

    * `:bare` - when `true`, initializes a bare repository (default `false`)

  ## Examples

      {:ok, repo} = Git.Repo.init("/tmp/new-repo")
      {:ok, repo} = Git.Repo.init("/tmp/bare-repo", bare: true)

  """
  @spec init(String.t(), keyword()) :: {:ok, t()} | {:error, term()}
  def init(path, opts \\ []) when is_binary(path) do
    File.mkdir_p!(path)
    bare = Keyword.get(opts, :bare, false)
    config = Config.new(working_dir: path)

    init_opts = [config: config]
    init_opts = if bare, do: Keyword.put(init_opts, :bare, true), else: init_opts

    case Git.init(init_opts) do
      {:ok, :done} ->
        config = %{config | working_dir: path}
        {:ok, %__MODULE__{config: config, path: path}}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Clones a repository from `url` into `path`.

  Runs `git clone` and returns a `Git.Repo` pointing at the cloned directory.

  ## Options

    * `:depth` - create a shallow clone with the given number of commits
    * `:branch` - check out the given branch after cloning
    * `:directory` - name of the target directory (default: inferred from URL)

  ## Examples

      {:ok, repo} = Git.Repo.clone("https://github.com/owner/repo.git", "/tmp/clone")
      {:ok, repo} = Git.Repo.clone("https://github.com/owner/repo.git", "/tmp/clone", depth: 1)

  """
  @spec clone(String.t(), String.t(), keyword()) :: {:ok, t()} | {:error, term()}
  def clone(url, path, opts \\ []) when is_binary(url) and is_binary(path) do
    parent = Path.dirname(path)
    directory = Path.basename(path)
    File.mkdir_p!(parent)

    clone_opts =
      opts
      |> Keyword.put(:config, Config.new(working_dir: parent))
      |> Keyword.put(:directory, directory)

    case Git.clone(url, clone_opts) do
      {:ok, :done} ->
        config = Config.new(working_dir: path)
        {:ok, %__MODULE__{config: config, path: path}}

      {:error, _} = error ->
        error
    end
  end

  # ---------------------------------------------------------------------------
  # Pipeline helpers
  # ---------------------------------------------------------------------------

  @doc """
  Wraps a repo in an ok tuple for use as the start of a pipeline.

  ## Examples

      Git.Repo.ok(repo)
      |> Git.Repo.run(fn repo -> ... end)

  """
  @spec ok(t()) :: {:ok, t()}
  def ok(%__MODULE__{} = repo), do: {:ok, repo}

  @doc """
  Runs a function in a pipeline, halting on error.

  If given `{:ok, repo}`, calls `fun.(repo)`. If given `{:error, _}`,
  passes the error through unchanged.

  ## Examples

      Git.Repo.open("/path/to/repo")
      |> Git.Repo.run(fn repo ->
        Git.Repo.add(repo, all: true)
        {:ok, repo}
      end)

  """
  @spec run({:ok, t()} | {:error, term()}, (t() -> {:ok, t()} | {:error, term()})) ::
          {:ok, t()} | {:error, term()}
  def run({:ok, repo}, fun) when is_function(fun, 1), do: fun.(repo)
  def run({:error, _} = error, _fun), do: error

  # ---------------------------------------------------------------------------
  # Wrapped git commands
  # ---------------------------------------------------------------------------

  @doc """
  Runs `git status` on the repository.

  See `Git.status/1` for available options.
  """
  @spec status(t(), keyword()) :: {:ok, Git.Status.t()} | {:error, term()}
  def status(%__MODULE__{} = repo, opts \\ []) do
    Git.status(Keyword.put(opts, :config, repo.config))
  end

  @doc """
  Runs `git log` on the repository.

  See `Git.log/1` for available options.
  """
  @spec log(t(), keyword()) :: {:ok, [Git.Commit.t()]} | {:error, term()}
  def log(%__MODULE__{} = repo, opts \\ []) do
    Git.log(Keyword.put(opts, :config, repo.config))
  end

  @doc """
  Runs `git commit` on the repository.

  See `Git.commit/2` for available options.
  """
  @spec commit(t(), String.t(), keyword()) :: {:ok, Git.CommitResult.t()} | {:error, term()}
  def commit(%__MODULE__{} = repo, message, opts \\ []) do
    Git.commit(message, Keyword.put(opts, :config, repo.config))
  end

  @doc """
  Runs `git branch` on the repository.

  See `Git.branch/1` for available options.
  """
  @spec branch(t(), keyword()) ::
          {:ok, [Git.Branch.t()]} | {:ok, :done} | {:error, term()}
  def branch(%__MODULE__{} = repo, opts \\ []) do
    Git.branch(Keyword.put(opts, :config, repo.config))
  end

  @doc """
  Runs `git diff` on the repository.

  See `Git.diff/1` for available options.
  """
  @spec diff(t(), keyword()) :: {:ok, Git.Diff.t()} | {:error, term()}
  def diff(%__MODULE__{} = repo, opts \\ []) do
    Git.diff(Keyword.put(opts, :config, repo.config))
  end

  @doc """
  Runs `git remote` on the repository.

  See `Git.remote/1` for available options.
  """
  @spec remote(t(), keyword()) ::
          {:ok, [Git.Remote.t()]} | {:ok, :done} | {:error, term()}
  def remote(%__MODULE__{} = repo, opts \\ []) do
    Git.remote(Keyword.put(opts, :config, repo.config))
  end

  @doc """
  Runs `git tag` on the repository.

  See `Git.tag/1` for available options.
  """
  @spec tag(t(), keyword()) ::
          {:ok, [Git.Tag.t()]} | {:ok, :done} | {:error, term()}
  def tag(%__MODULE__{} = repo, opts \\ []) do
    Git.tag(Keyword.put(opts, :config, repo.config))
  end

  @doc """
  Runs `git checkout` on the repository.

  See `Git.checkout/1` for available options.
  """
  @spec checkout(t(), keyword()) ::
          {:ok, Git.Checkout.t()} | {:ok, :done} | {:error, term()}
  def checkout(%__MODULE__{} = repo, opts \\ []) do
    Git.checkout(Keyword.put(opts, :config, repo.config))
  end

  @doc """
  Runs `git add` on the repository.

  See `Git.add/1` for available options.
  """
  @spec add(t(), keyword()) :: {:ok, :done} | {:error, term()}
  def add(%__MODULE__{} = repo, opts \\ []) do
    Git.add(Keyword.put(opts, :config, repo.config))
  end

  @doc """
  Runs `git merge` on the repository.

  See `Git.merge/2` for available options.
  """
  @spec merge(t(), String.t() | :abort, keyword()) ::
          {:ok, Git.MergeResult.t()} | {:ok, :done} | {:error, term()}
  def merge(%__MODULE__{} = repo, branch_or_abort, opts \\ []) do
    Git.merge(branch_or_abort, Keyword.put(opts, :config, repo.config))
  end

  @doc """
  Runs `git reset` on the repository.

  See `Git.reset/1` for available options.
  """
  @spec reset(t(), keyword()) :: {:ok, :done} | {:error, term()}
  def reset(%__MODULE__{} = repo, opts \\ []) do
    Git.reset(Keyword.put(opts, :config, repo.config))
  end

  @doc """
  Runs `git stash` on the repository.

  See `Git.stash/1` for available options.
  """
  @spec stash(t(), keyword()) ::
          {:ok, [Git.StashEntry.t()]} | {:ok, :done} | {:error, term()}
  def stash(%__MODULE__{} = repo, opts \\ []) do
    Git.stash(Keyword.put(opts, :config, repo.config))
  end

  @doc """
  Runs `git push` on the repository.

  See `Git.push/1` for available options.
  """
  @spec push(t(), keyword()) :: {:ok, :done} | {:error, term()}
  def push(%__MODULE__{} = repo, opts \\ []) do
    Git.push(Keyword.put(opts, :config, repo.config))
  end

  @doc """
  Runs `git pull` on the repository.

  See `Git.pull/1` for available options.
  """
  @spec pull(t(), keyword()) :: {:ok, Git.PullResult.t()} | {:error, term()}
  def pull(%__MODULE__{} = repo, opts \\ []) do
    Git.pull(Keyword.put(opts, :config, repo.config))
  end

  @doc """
  Runs `git fetch` on the repository.

  See `Git.fetch/1` for available options.
  """
  @spec fetch(t(), keyword()) :: {:ok, :done} | {:error, term()}
  def fetch(%__MODULE__{} = repo, opts \\ []) do
    Git.fetch(Keyword.put(opts, :config, repo.config))
  end

  @doc """
  Runs `git rebase` on the repository.

  See `Git.rebase/1` for available options.
  """
  @spec rebase(t(), keyword()) ::
          {:ok, Git.RebaseResult.t()} | {:ok, :done} | {:error, term()}
  def rebase(%__MODULE__{} = repo, opts \\ []) do
    Git.rebase(Keyword.put(opts, :config, repo.config))
  end

  @doc """
  Runs `git cherry-pick` on the repository.

  See `Git.cherry_pick/1` for available options.
  """
  @spec cherry_pick(t(), keyword()) ::
          {:ok, Git.CherryPickResult.t()} | {:ok, :done} | {:error, term()}
  def cherry_pick(%__MODULE__{} = repo, opts \\ []) do
    Git.cherry_pick(Keyword.put(opts, :config, repo.config))
  end

  @doc """
  Runs `git show` on the repository.

  See `Git.show/1` for available options.
  """
  @spec show(t(), keyword()) :: {:ok, Git.ShowResult.t()} | {:error, term()}
  def show(%__MODULE__{} = repo, opts \\ []) do
    Git.show(Keyword.put(opts, :config, repo.config))
  end

  @doc """
  Runs `git rev-parse` on the repository.

  See `Git.rev_parse/1` for available options.
  """
  @spec rev_parse(t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def rev_parse(%__MODULE__{} = repo, opts \\ []) do
    Git.rev_parse(Keyword.put(opts, :config, repo.config))
  end

  @doc """
  Runs `git clean` on the repository.

  See `Git.clean/1` for available options.
  """
  @spec clean(t(), keyword()) :: {:ok, [String.t()]} | {:error, term()}
  def clean(%__MODULE__{} = repo, opts \\ []) do
    Git.clean(Keyword.put(opts, :config, repo.config))
  end

  @doc """
  Runs `git blame` on the repository.

  See `Git.blame/2` for available options.
  """
  @spec blame(t(), String.t(), keyword()) :: {:ok, [Git.BlameEntry.t()]} | {:error, term()}
  def blame(%__MODULE__{} = repo, file, opts \\ []) do
    Git.blame(file, Keyword.put(opts, :config, repo.config))
  end

  @doc """
  Runs `git mv` on the repository.

  See `Git.mv/3` for available options.
  """
  @spec mv(t(), String.t(), String.t(), keyword()) :: {:ok, :done} | {:error, term()}
  def mv(%__MODULE__{} = repo, source, destination, opts \\ []) do
    Git.mv(source, destination, Keyword.put(opts, :config, repo.config))
  end

  @doc """
  Runs `git rm` on the repository.

  See `Git.rm/1` for available options.
  """
  @spec rm(t(), keyword()) :: {:ok, :done} | {:error, term()}
  def rm(%__MODULE__{} = repo, opts \\ []) do
    Git.rm(Keyword.put(opts, :config, repo.config))
  end

  @doc """
  Runs `git revert` on the repository.

  See `Git.revert/1` for available options.
  """
  @spec revert(t(), keyword()) ::
          {:ok, Git.RevertResult.t()} | {:ok, :done} | {:error, term()}
  def revert(%__MODULE__{} = repo, opts \\ []) do
    Git.revert(Keyword.put(opts, :config, repo.config))
  end

  @doc """
  Runs `git worktree` on the repository.

  See `Git.worktree/1` for available options.
  """
  @spec worktree(t(), keyword()) ::
          {:ok, [Git.Worktree.t()]} | {:ok, :done} | {:error, term()}
  def worktree(%__MODULE__{} = repo, opts \\ []) do
    Git.worktree(Keyword.put(opts, :config, repo.config))
  end

  @doc """
  Runs `git submodule` on the repository.

  See `Git.submodule/1` for available options.
  """
  @spec submodule(t(), keyword()) ::
          {:ok, [Git.SubmoduleEntry.t()]} | {:ok, :done} | {:ok, String.t()} | {:error, term()}
  def submodule(%__MODULE__{} = repo, opts \\ []) do
    Git.submodule(Keyword.put(opts, :config, repo.config))
  end

  @doc """
  Runs `git config` on the repository.

  See `Git.git_config/1` for available options.
  """
  @spec git_config(t(), keyword()) ::
          {:ok, String.t()} | {:ok, [{String.t(), String.t()}]} | {:ok, :done} | {:error, term()}
  def git_config(%__MODULE__{} = repo, opts \\ []) do
    Git.git_config(Keyword.put(opts, :config, repo.config))
  end

  @doc """
  Runs `git ls-files` on the repository.

  See `Git.ls_files/1` for available options.
  """
  @spec ls_files(t(), keyword()) :: {:ok, [String.t()]} | {:error, term()}
  def ls_files(%__MODULE__{} = repo, opts \\ []) do
    Git.ls_files(Keyword.put(opts, :config, repo.config))
  end

  @doc """
  Runs `git reflog` on the repository.

  See `Git.reflog/1` for available options.
  """
  @spec reflog(t(), keyword()) :: {:ok, [Git.ReflogEntry.t()]} | {:error, term()}
  def reflog(%__MODULE__{} = repo, opts \\ []) do
    Git.reflog(Keyword.put(opts, :config, repo.config))
  end

  @doc """
  Runs `git bisect` on the repository.

  See `Git.bisect/1` for available options.
  """
  @spec bisect(t(), keyword()) ::
          {:ok, Git.BisectResult.t()} | {:ok, :done} | {:error, term()}
  def bisect(%__MODULE__{} = repo, opts \\ []) do
    Git.bisect(Keyword.put(opts, :config, repo.config))
  end

  @doc """
  Runs `git grep` on the repository.

  See `Git.grep/2` for available options.
  """
  @spec grep(t(), String.t(), keyword()) :: {:ok, [Git.GrepResult.t()]} | {:error, term()}
  def grep(%__MODULE__{} = repo, pattern, opts \\ []) do
    Git.grep(pattern, Keyword.put(opts, :config, repo.config))
  end

  @doc """
  Runs `git describe` on the repository.

  See `Git.describe/1` for available options.
  """
  @spec describe(t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def describe(%__MODULE__{} = repo, opts \\ []) do
    Git.describe(Keyword.put(opts, :config, repo.config))
  end

  @doc """
  Runs `git shortlog` on the repository.

  See `Git.shortlog/1` for available options.
  """
  @spec shortlog(t(), keyword()) :: {:ok, [Git.ShortlogEntry.t()]} | {:error, term()}
  def shortlog(%__MODULE__{} = repo, opts \\ []) do
    Git.shortlog(Keyword.put(opts, :config, repo.config))
  end

  @doc """
  Runs `git format-patch` on the repository.

  See `Git.format_patch/1` for available options.
  """
  @spec format_patch(t(), keyword()) ::
          {:ok, [String.t()]} | {:ok, String.t()} | {:error, term()}
  def format_patch(%__MODULE__{} = repo, opts \\ []) do
    Git.format_patch(Keyword.put(opts, :config, repo.config))
  end

  @doc """
  Runs `git archive` on the repository.

  See `Git.archive/1` for available options.
  """
  @spec archive(t(), keyword()) :: {:ok, :done} | {:error, term()}
  def archive(%__MODULE__{} = repo, opts \\ []) do
    Git.archive(Keyword.put(opts, :config, repo.config))
  end

  @doc """
  Runs `git ls-remote` on the repository.

  See `Git.ls_remote/1` for available options.
  """
  @spec ls_remote(t(), keyword()) :: {:ok, [Git.LsRemoteEntry.t()]} | {:error, term()}
  def ls_remote(%__MODULE__{} = repo, opts \\ []) do
    Git.ls_remote(Keyword.put(opts, :config, repo.config))
  end

  @doc """
  Runs `git ls-tree` on the repository.

  See `Git.ls_tree/1` for available options.
  """
  @spec ls_tree(t(), keyword()) ::
          {:ok, [Git.TreeEntry.t()] | [String.t()]} | {:error, term()}
  def ls_tree(%__MODULE__{} = repo, opts \\ []) do
    Git.ls_tree(Keyword.put(opts, :config, repo.config))
  end

  @doc """
  Runs `git range-diff` on the repository.

  See `Git.range_diff/1` for available options.
  """
  @spec range_diff(t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def range_diff(%__MODULE__{} = repo, opts \\ []) do
    Git.range_diff(Keyword.put(opts, :config, repo.config))
  end

  @doc """
  Runs `git sparse-checkout` on the repository.

  See `Git.sparse_checkout/1` for available options.
  """
  @spec sparse_checkout(t(), keyword()) ::
          {:ok, [String.t()]} | {:ok, :done} | {:error, term()}
  def sparse_checkout(%__MODULE__{} = repo, opts \\ []) do
    Git.sparse_checkout(Keyword.put(opts, :config, repo.config))
  end

  @doc """
  Runs `git rev-list` on the repository.

  See `Git.rev_list/1` for available options.
  """
  @spec rev_list(t(), keyword()) ::
          {:ok, [String.t()] | integer() | map()} | {:error, term()}
  def rev_list(%__MODULE__{} = repo, opts \\ []) do
    Git.rev_list(Keyword.put(opts, :config, repo.config))
  end

  @doc """
  Runs `git merge-base` on the repository.

  See `Git.merge_base/1` for available options.
  """
  @spec merge_base(t(), keyword()) ::
          {:ok, String.t() | boolean() | [String.t()]} | {:error, term()}
  def merge_base(%__MODULE__{} = repo, opts \\ []) do
    Git.merge_base(Keyword.put(opts, :config, repo.config))
  end

  @doc """
  Runs `git cherry` on the repository.

  See `Git.cherry/1` for available options.
  """
  @spec cherry(t(), keyword()) :: {:ok, [Git.CherryEntry.t()]} | {:error, term()}
  def cherry(%__MODULE__{} = repo, opts \\ []) do
    Git.cherry(Keyword.put(opts, :config, repo.config))
  end

  @doc """
  Runs `git cat-file` on the repository.

  See `Git.cat_file/2` for available options.
  """
  @spec cat_file(t(), String.t(), keyword()) ::
          {:ok, atom()}
          | {:ok, integer()}
          | {:ok, String.t()}
          | {:ok, boolean()}
          | {:error, term()}
  def cat_file(%__MODULE__{} = repo, object, opts \\ []) do
    Git.cat_file(object, Keyword.put(opts, :config, repo.config))
  end

  @doc """
  Runs `git check-ignore` on the repository.

  See `Git.check_ignore/1` for available options.
  """
  @spec check_ignore(t(), keyword()) :: {:ok, [String.t()] | [map()]} | {:error, term()}
  def check_ignore(%__MODULE__{} = repo, opts \\ []) do
    Git.check_ignore(Keyword.put(opts, :config, repo.config))
  end

  @doc """
  Runs `git notes` on the repository.

  See `Git.notes/1` for available options.
  """
  @spec notes(t(), keyword()) ::
          {:ok, [map()]} | {:ok, String.t()} | {:ok, :done} | {:error, term()}
  def notes(%__MODULE__{} = repo, opts \\ []) do
    Git.notes(Keyword.put(opts, :config, repo.config))
  end

  @doc """
  Runs `git verify-commit` on the repository.

  See `Git.verify_commit/2` for available options.
  """
  @spec verify_commit(t(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def verify_commit(%__MODULE__{} = repo, commit, opts \\ []) do
    Git.verify_commit(commit, Keyword.put(opts, :config, repo.config))
  end

  @doc """
  Runs `git verify-tag` on the repository.

  See `Git.verify_tag/2` for available options.
  """
  @spec verify_tag(t(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def verify_tag(%__MODULE__{} = repo, tag, opts \\ []) do
    Git.verify_tag(tag, Keyword.put(opts, :config, repo.config))
  end

  @doc """
  Runs `git gc` on the repository.

  See `Git.gc/1` for available options.
  """
  @spec gc(t(), keyword()) :: {:ok, :done} | {:error, term()}
  def gc(%__MODULE__{} = repo, opts \\ []) do
    Git.gc(Keyword.put(opts, :config, repo.config))
  end

  @doc """
  Runs `git rerere` on the repository.

  See `Git.rerere/1` for available options.
  """
  @spec rerere(t(), keyword()) ::
          {:ok, [String.t()]} | {:ok, String.t()} | {:ok, :done} | {:error, term()}
  def rerere(%__MODULE__{} = repo, opts \\ []) do
    Git.rerere(Keyword.put(opts, :config, repo.config))
  end

  @doc """
  Runs `git fsck` on the repository.

  See `Git.fsck/1` for available options.
  """
  @spec fsck(t(), keyword()) :: {:ok, [map()]} | {:error, term()}
  def fsck(%__MODULE__{} = repo, opts \\ []) do
    Git.fsck(Keyword.put(opts, :config, repo.config))
  end

  @doc """
  Runs `git bundle` on the repository.

  See `Git.bundle/1` for available options.
  """
  @spec bundle(t(), keyword()) :: {:ok, term()} | {:error, term()}
  def bundle(%__MODULE__{} = repo, opts \\ []) do
    Git.bundle(Keyword.put(opts, :config, repo.config))
  end

  @doc """
  Runs `git show-ref` on the repository.

  See `Git.show_ref/1` for available options.
  """
  @spec show_ref(t(), keyword()) :: {:ok, term()} | {:error, term()}
  def show_ref(%__MODULE__{} = repo, opts \\ []) do
    Git.show_ref(Keyword.put(opts, :config, repo.config))
  end

  @doc """
  Runs `git switch` on the repository.

  See `Git.switch/1` for available options.
  """
  @spec switch(t(), keyword()) ::
          {:ok, Git.Checkout.t()} | {:ok, :done} | {:error, term()}
  def switch(%__MODULE__{} = repo, opts \\ []) do
    Git.switch(Keyword.put(opts, :config, repo.config))
  end

  @doc """
  Runs `git restore` on the repository.

  See `Git.restore/1` for available options.
  """
  @spec restore(t(), keyword()) :: {:ok, :done} | {:error, term()}
  def restore(%__MODULE__{} = repo, opts \\ []) do
    Git.restore(Keyword.put(opts, :config, repo.config))
  end

  @doc """
  Runs `git apply` on the repository.

  See `Git.apply_patch/1` for available options.
  """
  @spec apply_patch(t(), keyword()) :: {:ok, :done} | {:ok, String.t()} | {:error, term()}
  def apply_patch(%__MODULE__{} = repo, opts \\ []) do
    Git.apply_patch(Keyword.put(opts, :config, repo.config))
  end

  @doc """
  Runs `git am` on the repository.

  See `Git.am/1` for available options.
  """
  @spec am(t(), keyword()) :: {:ok, :done} | {:error, term()}
  def am(%__MODULE__{} = repo, opts \\ []) do
    Git.am(Keyword.put(opts, :config, repo.config))
  end
end
