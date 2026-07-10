defmodule Git.Branches do
  @moduledoc """
  Higher-level branch workflow operations that compose multiple lower-level
  `Git` commands.

  All functions accept an optional keyword list. The `:config` key, when
  present, must be a `Git.Config` struct and is forwarded to every underlying
  git invocation.
  """

  alias Git.Config

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Creates a new branch and checks it out in one call.

  Equivalent to `git checkout -b <branch_name>`.

  Returns `{:ok, Git.Checkout.t()}` on success.
  """
  @spec create_and_checkout(String.t(), keyword()) ::
          {:ok, Git.Checkout.t()} | {:error, term()}
  def create_and_checkout(branch_name, opts \\ []) do
    Git.checkout(Keyword.merge(opts, branch: branch_name, create: true))
  end

  @doc """
  Returns the name of the current branch.

  Uses `git rev-parse --abbrev-ref HEAD`.

  Returns `{:ok, String.t()}` on success.
  """
  @spec current(keyword()) :: {:ok, String.t()} | {:error, term()}
  def current(opts \\ []) do
    Git.rev_parse(Keyword.merge(opts, abbrev_ref: true, ref: "HEAD"))
  end

  @doc """
  Checks whether a branch exists locally.

  Uses `git rev-parse --verify refs/heads/<branch_name>`.

  Returns `{:ok, true}` when the branch exists, `{:ok, false}` otherwise.
  """
  @spec exists?(String.t(), keyword()) :: {:ok, boolean()} | {:error, term()}
  def exists?(branch_name, opts \\ []) do
    case Git.rev_parse(Keyword.merge(opts, verify: true, ref: "refs/heads/#{branch_name}")) do
      {:ok, _} -> {:ok, true}
      {:error, _} -> {:ok, false}
    end
  end

  @doc """
  Lists branches that have been merged into the current branch or a specified
  target.

  ## Options

    * `:target` - branch to check against (default: current branch)

  Returns `{:ok, [Git.Branch.t()]}`.
  """
  @spec merged(keyword()) :: {:ok, [Git.Branch.t()]} | {:error, term()}
  def merged(opts \\ []) do
    {target, opts} = Keyword.pop(opts, :target)
    config = Keyword.get(opts, :config, Config.new())

    merged_val = if target, do: target, else: true
    command = %Git.Commands.Branch{merged: merged_val}
    args = Git.Commands.Branch.args(command)
    cmd_opts = Config.cmd_opts(config)

    {stdout, exit_code} = System.cmd(config.binary, args, cmd_opts)
    Git.Commands.Branch.parse_merged_output(stdout, exit_code)
  end

  @doc """
  Lists branches that have NOT been merged into the current branch or a
  specified target.

  ## Options

    * `:target` - branch to check against (default: current branch)

  Returns `{:ok, [Git.Branch.t()]}`.
  """
  @spec no_merged(keyword()) :: {:ok, [Git.Branch.t()]} | {:error, term()}
  def no_merged(opts \\ []) do
    {target, opts} = Keyword.pop(opts, :target)
    config = Keyword.get(opts, :config, Config.new())

    no_merged_val = if target, do: target, else: true
    command = %Git.Commands.Branch{no_merged: no_merged_val}
    args = Git.Commands.Branch.args(command)
    cmd_opts = Config.cmd_opts(config)

    {stdout, exit_code} = System.cmd(config.binary, args, cmd_opts)
    Git.Commands.Branch.parse_merged_output(stdout, exit_code)
  end

  @doc """
  Finds branches merged into a target and deletes them.

  ## Options

    * `:target` - branch to check against (default: current branch)
    * `:force` - use force delete, `-D` (default: `false`)
    * `:exclude` - list of branch names to never delete
      (default: `["main", "master", "develop"]`)
    * `:dry_run` - just return the list without deleting (default: `false`)

  The current branch and any branches in the `:exclude` list are always
  skipped.

  Returns `{:ok, [String.t()]}` with the list of deleted (or would-be-deleted)
  branch names.
  """
  @spec cleanup_merged(keyword()) :: {:ok, [String.t()]} | {:error, term()}
  def cleanup_merged(opts \\ []) do
    {target, opts} = Keyword.pop(opts, :target)
    {force, opts} = Keyword.pop(opts, :force, false)
    {exclude, opts} = Keyword.pop(opts, :exclude, ["main", "master", "develop"])
    {dry_run, opts} = Keyword.pop(opts, :dry_run, false)

    merged_opts = if target, do: Keyword.put(opts, :target, target), else: opts

    with {:ok, current_name} <- current(opts),
         {:ok, branches} <- merged(merged_opts) do
      to_delete =
        branches
        |> Enum.map(& &1.name)
        |> Enum.reject(&(&1 == current_name or &1 in exclude))

      if dry_run do
        {:ok, to_delete}
      else
        delete_branches(to_delete, opts, force)
      end
    end
  end

  @doc """
  Returns ahead/behind counts between two branches.

  Uses `git rev-list --count --left-right branch1...branch2`.

  Returns `{:ok, %{ahead: non_neg_integer(), behind: non_neg_integer()}}`.
  """
  @spec divergence(String.t(), String.t(), keyword()) ::
          {:ok, %{ahead: non_neg_integer(), behind: non_neg_integer()}} | {:error, term()}
  def divergence(branch1, branch2, opts \\ []) do
    config = Keyword.get(opts, :config, Config.new())

    case Git.rev_list(
           ref: "#{branch1}...#{branch2}",
           count: true,
           left_right: true,
           config: config
         ) do
      {:ok, %{left: ahead, right: behind}} ->
        {:ok, %{ahead: ahead, behind: behind}}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Lists branches sorted by most recent commit.

  ## Options

    * `:count` - maximum number of branches to return (default: `10`)

  Uses `git for-each-ref` with `--sort=-committerdate`.

  Returns `{:ok, [%{name: String.t(), date: String.t(), author: String.t(), subject: String.t()}]}`.
  """
  @spec recent(keyword()) ::
          {:ok, [%{name: String.t(), date: String.t(), author: String.t(), subject: String.t()}]}
          | {:error, term()}
  # NOTE: Uses raw System.cmd since there is no Git.Commands.ForEachRef module yet.
  # See https://github.com/joshrotenberg/git_wrapper_ex/issues/56 for tracking.
  def recent(opts \\ []) do
    {count, opts} = Keyword.pop(opts, :count, 10)
    config = Keyword.get(opts, :config, Config.new())

    format = "%(refname:short)\t%(committerdate:relative)\t%(authorname)\t%(subject)"

    args = [
      "for-each-ref",
      "--sort=-committerdate",
      "refs/heads/",
      "--format=#{format}",
      "--count=#{count}"
    ]

    cmd_opts = Config.cmd_opts(config)
    {stdout, exit_code} = System.cmd(config.binary, args, cmd_opts)

    if exit_code == 0 do
      {:ok, parse_recent_entries(stdout)}
    else
      {:error, {stdout, exit_code}}
    end
  end

  @doc """
  Renames a branch.

  Uses `git branch -m <old_name> <new_name>`.

  Returns `{:ok, :done}` on success.
  """
  @spec rename(String.t(), String.t(), keyword()) :: {:ok, :done} | {:error, term()}
  def rename(old_name, new_name, opts \\ []) do
    config = Keyword.get(opts, :config, Config.new())

    command = %Git.Commands.Branch{rename: old_name, rename_to: new_name}
    args = Git.Commands.Branch.args(command)
    cmd_opts = Config.cmd_opts(config)

    case System.cmd(config.binary, args, cmd_opts) do
      {_stdout, 0} -> {:ok, :done}
      {stdout, exit_code} -> {:error, {stdout, exit_code}}
    end
  end

  @doc """
  Deletes local branches whose upstream tracking branch was deleted on the
  remote.

  Fetches with `--prune` (so gone upstreams are detected), then deletes every
  local branch reported as `[gone]`. This is orthogonal to `cleanup_merged/1`:
  a gone branch may still be unmerged, and a merged branch may still have a live
  upstream.

  ## Options

    * `:remote` - remote to prune against (default `"origin"`)
    * `:exclude` - branch names to never delete (default `["main", "master", "develop"]`)
    * `:force` - use `-D` instead of `-d` (default `false`)
    * `:dry_run` - return the branches that would be deleted without deleting
      (default `false`)
    * `:config` - a `Git.Config` struct

  Returns `{:ok, deleted_names}` (or the would-be-deleted names under
  `:dry_run`). The current branch is always skipped.
  """
  @spec prune_gone(keyword()) :: {:ok, [String.t()]} | {:error, term()}
  def prune_gone(opts \\ []) do
    {remote, opts} = Keyword.pop(opts, :remote, "origin")
    {exclude, opts} = Keyword.pop(opts, :exclude, ["main", "master", "develop"])
    {force, opts} = Keyword.pop(opts, :force, false)
    {dry_run, opts} = Keyword.pop(opts, :dry_run, false)

    with {:ok, :done} <- Git.fetch(Keyword.merge(opts, remote: remote, prune: true)),
         {:ok, current_name} <- current(opts),
         {:ok, gone} <- gone_branches(opts) do
      to_delete = Enum.reject(gone, &(&1 == current_name or &1 in exclude))

      if dry_run do
        {:ok, to_delete}
      else
        delete_branches(to_delete, opts, force)
      end
    end
  end

  @doc """
  Deletes a branch locally and, when `:remote` is given, on the remote too.

  ## Options

    * `:remote` - remote to also delete the branch from, e.g. `"origin"`;
      `true` is shorthand for `"origin"`. When omitted, only the local branch is
      deleted.
    * `:force` - use `-D` instead of `-d` for the local delete (default `false`)
    * `:config` - a `Git.Config` struct

  Returns `{:ok, :done}` when the requested deletions succeed.
  """
  @spec delete_branch(String.t(), keyword()) :: {:ok, :done} | {:error, term()}
  def delete_branch(name, opts \\ []) when is_binary(name) do
    {remote, opts} = Keyword.pop(opts, :remote, nil)
    {force, opts} = Keyword.pop(opts, :force, false)

    with {:ok, _} <- Git.branch(Keyword.merge(opts, delete: name, force_delete: force)),
         {:ok, _} <- delete_remote_branch(remote_name(remote), name, opts) do
      {:ok, :done}
    end
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp delete_branches(to_delete, opts, force) do
    Enum.each(to_delete, fn name ->
      Git.branch(Keyword.merge(opts, delete: name, force_delete: force))
    end)

    {:ok, to_delete}
  end

  defp gone_branches(opts) do
    config = Keyword.get(opts, :config, Config.new())
    args = ["for-each-ref", "--format=%(refname:short) %(upstream:track)", "refs/heads/"]
    {stdout, exit_code} = System.cmd(config.binary, args, Config.cmd_opts(config))

    if exit_code == 0 do
      gone =
        stdout
        |> String.split("\n", trim: true)
        |> Enum.filter(&String.contains?(&1, "[gone]"))
        |> Enum.map(fn line -> line |> String.split(" ", parts: 2) |> hd() end)

      {:ok, gone}
    else
      {:error, {stdout, exit_code}}
    end
  end

  defp remote_name(true), do: "origin"
  defp remote_name(name) when is_binary(name), do: name
  defp remote_name(_), do: nil

  defp delete_remote_branch(nil, _name, _opts), do: {:ok, :skipped}

  defp delete_remote_branch(remote, name, opts) do
    Git.push(Keyword.merge(opts, remote: remote, branch: name, delete: true))
  end

  defp parse_recent_entries(stdout) do
    stdout
    |> String.split("\n", trim: true)
    |> Enum.map(fn line ->
      case String.split(line, "\t", parts: 4) do
        [name, date, author, subject] ->
          %{name: name, date: date, author: author, subject: subject}

        [name, date, author] ->
          %{name: name, date: date, author: author, subject: ""}

        _ ->
          %{name: line, date: "", author: "", subject: ""}
      end
    end)
  end
end
