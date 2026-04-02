defmodule GitWrapperEx do
  @moduledoc """
  An Elixir wrapper for the git CLI.

  Provides functions for common git operations by shelling out to the git
  binary. Each function accepts an options keyword list that can include
  a `:config` key with a `GitWrapper.Config` struct to customize behavior.
  """

  alias GitWrapper.Config

  @doc """
  Runs `git status` and returns the parsed output.

  ## Options

    * `:config` - a `GitWrapper.Config` struct (default: `GitWrapper.Config.new()`)
    * All other options are passed to the underlying command.

  """
  @spec status(keyword()) :: {:ok, GitWrapper.Status.t()} | {:error, term()}
  def status(opts \\ []) do
    {config, _rest} = Keyword.pop(opts, :config, Config.new())
    GitWrapper.Command.run(GitWrapper.Commands.Status, %GitWrapper.Commands.Status{}, config)
  end

  @doc """
  Runs `git log` and returns the parsed output.

  ## Options

    * `:config` - a `GitWrapper.Config` struct (default: `GitWrapper.Config.new()`)
    * All other options are passed to the underlying command.

  """
  @spec log(keyword()) :: {:ok, [GitWrapper.Commit.t()]} | {:error, term()}
  def log(opts \\ []) do
    {config, rest} = Keyword.pop(opts, :config, Config.new())
    command = struct!(GitWrapper.Commands.Log, rest)
    GitWrapper.Command.run(GitWrapper.Commands.Log, command, config)
  end

  @doc """
  Runs `git commit` with the given message and returns the parsed output.

  ## Options

    * `:config` - a `GitWrapper.Config` struct (default: `GitWrapper.Config.new()`)
    * All other options are passed to the underlying command.

  """
  @spec commit(String.t(), keyword()) :: {:ok, GitWrapper.CommitResult.t()} | {:error, term()}
  def commit(message, opts \\ []) when is_binary(message) do
    {config, rest} = Keyword.pop(opts, :config, Config.new())
    command = struct!(GitWrapper.Commands.Commit, [{:message, message} | rest])
    GitWrapper.Command.run(GitWrapper.Commands.Commit, command, config)
  end

  @doc """
  Runs `git branch` to list, create, or delete branches.

  ## Options

    * `:config` - a `GitWrapper.Config` struct (default: `GitWrapper.Config.new()`)
    * `:create` - name of a new branch to create
    * `:delete` - name of a branch to delete
    * `:force_delete` - use `-D` for delete (default `false`)
    * `:all` - include remote-tracking branches in the listing (default `false`)

  """
  @spec branch(keyword()) ::
          {:ok, [GitWrapper.Branch.t()]} | {:ok, :done} | {:error, term()}
  def branch(opts \\ []) do
    {config, rest} = Keyword.pop(opts, :config, Config.new())
    command = struct!(GitWrapper.Commands.Branch, rest)
    GitWrapper.Command.run(GitWrapper.Commands.Branch, command, config)
  end

  @doc """
  Runs `git diff` and returns parsed diff output.

  ## Options

    * `:config` - a `GitWrapper.Config` struct (default: `GitWrapper.Config.new()`)
    * `:staged` - show staged (cached) diff (default `false`)
    * `:stat` - return file-level stats instead of full patch (default `false`)
    * `:ref` - compare against this ref (e.g., `"HEAD~1"`)
    * `:path` - limit the diff to this path

  """
  @spec diff(keyword()) :: {:ok, GitWrapper.Diff.t()} | {:error, term()}
  def diff(opts \\ []) do
    {config, rest} = Keyword.pop(opts, :config, Config.new())
    command = struct!(GitWrapper.Commands.Diff, rest)
    GitWrapper.Command.run(GitWrapper.Commands.Diff, command, config)
  end

  @doc """
  Runs `git remote` to list, add, or remove remotes.

  ## Options

    * `:config` - a `GitWrapper.Config` struct (default: `GitWrapper.Config.new()`)
    * `:add_name` - name for a new remote (requires `:add_url`)
    * `:add_url` - URL for a new remote (requires `:add_name`)
    * `:remove` - name of remote to remove
    * `:verbose` - verbose listing (default `true`)

  """
  @spec remote(keyword()) :: {:ok, [GitWrapper.Remote.t()]} | {:ok, :done} | {:error, term()}
  def remote(opts \\ []) do
    {config, rest} = Keyword.pop(opts, :config, Config.new())
    command = struct!(GitWrapper.Commands.Remote, rest)
    GitWrapper.Command.run(GitWrapper.Commands.Remote, command, config)
  end

  @doc """
  Runs `git tag` to list, create, or delete tags.

  ## Options

    * `:config` - a `GitWrapper.Config` struct (default: `GitWrapper.Config.new()`)
    * `:create` - name of a new tag to create
    * `:message` - annotation message (creates an annotated tag when set with `:create`)
    * `:delete` - name of a tag to delete
    * `:ref` - commit ref to tag (default: HEAD)
    * `:sort` - sort order for listing (e.g., `"-version:refname"`)

  """
  @spec tag(keyword()) ::
          {:ok, [GitWrapper.Tag.t()]} | {:ok, :done} | {:error, term()}
  def tag(opts \\ []) do
    {config, rest} = Keyword.pop(opts, :config, Config.new())
    command = struct!(GitWrapper.Commands.Tag, rest)
    GitWrapper.Command.run(GitWrapper.Commands.Tag, command, config)
  end

  @doc """
  Runs `git stash` to list, save, pop, or drop stash entries.

  ## Options

    * `:config` - a `GitWrapper.Config` struct (default: `GitWrapper.Config.new()`)
    * `:save` - push current changes onto the stash (default `false`)
    * `:pop` - pop the top stash entry (default `false`)
    * `:drop` - drop a stash entry (default `false`)
    * `:message` - message for the stash entry (used with `:save`)
    * `:index` - stash index for `:pop` or `:drop` (e.g., `0` for `stash@{0}`)
    * `:include_untracked` - include untracked files when saving (default `false`)

  """
  @spec stash(keyword()) ::
          {:ok, [GitWrapper.StashEntry.t()]} | {:ok, :done} | {:error, term()}
  def stash(opts \\ []) do
    {config, rest} = Keyword.pop(opts, :config, Config.new())
    command = struct!(GitWrapper.Commands.Stash, rest)
    GitWrapper.Command.run(GitWrapper.Commands.Stash, command, config)
  end
end
