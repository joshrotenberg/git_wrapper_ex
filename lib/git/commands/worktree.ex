defmodule Git.Commands.Worktree do
  @moduledoc """
  Implements the `Git.Command` behaviour for `git worktree`.

  Supports listing worktrees (default), adding a new worktree, removing,
  moving, unlocking, repairing, and pruning worktrees. List output is
  always parsed from `--porcelain` format for reliable structured data.

  When adding with a new branch (`:add_new_branch`), `:start_point` names the
  commit-ish the branch starts from; `:add_branch` alone checks out an existing
  branch. `:repair` (with no directory noise) is the companion to `:prune` for
  recovering worktrees whose administrative files moved.
  """

  @behaviour Git.Command

  alias Git.Worktree

  @type t :: %__MODULE__{
          list: boolean(),
          add_path: String.t() | nil,
          add_branch: String.t() | nil,
          add_new_branch: String.t() | nil,
          start_point: String.t() | nil,
          remove_path: String.t() | nil,
          move: {String.t(), String.t()} | nil,
          unlock: String.t() | nil,
          repair: boolean(),
          prune: boolean(),
          expire: String.t() | nil,
          force: boolean(),
          detach: boolean(),
          lock: boolean(),
          porcelain: boolean()
        }

  defstruct list: true,
            add_path: nil,
            add_branch: nil,
            add_new_branch: nil,
            start_point: nil,
            remove_path: nil,
            move: nil,
            unlock: nil,
            repair: false,
            prune: false,
            expire: nil,
            force: false,
            detach: false,
            lock: false,
            porcelain: true

  # Process dictionary key used to communicate the operation mode from args/1
  # to parse_output/2. Both are called from the same process inside
  # Git.Command.run/3, so this is safe even with async tests.
  @mode_key :__git_worktree_mode__

  @doc """
  Returns the argument list for `git worktree`.

  - If `:add_path` is set, builds `git worktree add [options] <path> [<commit-ish>]`.
  - If `:remove_path` is set, builds `git worktree remove [--force] <path>`.
  - If `:move` is a `{from, to}` tuple, builds `git worktree move [--force] <from> <to>`.
  - If `:unlock` is set, builds `git worktree unlock <path>`.
  - If `:repair` is true, builds `git worktree repair`.
  - If `:prune` is true, builds `git worktree prune [--expire <time>]`.
  - Otherwise, lists worktrees with `git worktree list --porcelain`.

  ## Examples

      iex> Git.Commands.Worktree.args(%Git.Commands.Worktree{})
      ["worktree", "list", "--porcelain"]

      iex> Git.Commands.Worktree.args(%Git.Commands.Worktree{add_path: "/tmp/wt", add_branch: "main"})
      ["worktree", "add", "/tmp/wt", "main"]

      iex> Git.Commands.Worktree.args(%Git.Commands.Worktree{add_path: "/tmp/wt", add_new_branch: "feat", start_point: "main"})
      ["worktree", "add", "-b", "feat", "/tmp/wt", "main"]

      iex> Git.Commands.Worktree.args(%Git.Commands.Worktree{remove_path: "/tmp/wt", force: true})
      ["worktree", "remove", "--force", "/tmp/wt"]

      iex> Git.Commands.Worktree.args(%Git.Commands.Worktree{move: {"/tmp/wt", "/tmp/moved"}})
      ["worktree", "move", "/tmp/wt", "/tmp/moved"]

      iex> Git.Commands.Worktree.args(%Git.Commands.Worktree{unlock: "/tmp/wt"})
      ["worktree", "unlock", "/tmp/wt"]

      iex> Git.Commands.Worktree.args(%Git.Commands.Worktree{repair: true})
      ["worktree", "repair"]

      iex> Git.Commands.Worktree.args(%Git.Commands.Worktree{prune: true, expire: "now"})
      ["worktree", "prune", "--expire", "now"]

  """
  @spec args(t()) :: [String.t()]
  @impl true
  def args(%__MODULE__{add_path: path} = command) when is_binary(path) do
    Process.put(@mode_key, :mutation)

    base = ["worktree", "add"]

    base
    |> maybe_add_flag(command.force, "--force")
    |> maybe_add_flag(command.detach, "--detach")
    |> maybe_add_flag(command.lock, "--lock")
    |> maybe_add_option("-b", command.add_new_branch)
    |> Kernel.++([path])
    |> maybe_add_value(command.start_point || command.add_branch)
  end

  def args(%__MODULE__{remove_path: path} = command) when is_binary(path) do
    Process.put(@mode_key, :mutation)

    ["worktree", "remove"]
    |> maybe_add_flag(command.force, "--force")
    |> Kernel.++([path])
  end

  def args(%__MODULE__{move: {from, to}} = command) do
    Process.put(@mode_key, :mutation)

    ["worktree", "move"]
    |> maybe_add_flag(command.force, "--force")
    |> Kernel.++([from, to])
  end

  def args(%__MODULE__{unlock: path}) when is_binary(path) do
    Process.put(@mode_key, :mutation)
    ["worktree", "unlock", path]
  end

  def args(%__MODULE__{repair: true}) do
    Process.put(@mode_key, :mutation)
    ["worktree", "repair"]
  end

  def args(%__MODULE__{prune: true} = command) do
    Process.put(@mode_key, :mutation)

    ["worktree", "prune"]
    |> maybe_add_option("--expire", command.expire)
  end

  def args(%__MODULE__{}) do
    Process.put(@mode_key, :list)
    ["worktree", "list", "--porcelain"]
  end

  @doc """
  Parses the output of `git worktree`.

  For list operations (exit 0), parses porcelain output into a list of
  `Git.Worktree` structs. For add/remove/prune operations (exit 0),
  returns `{:ok, :done}`. On failure, returns `{:error, {stdout, exit_code}}`.
  """
  @spec parse_output(String.t(), non_neg_integer()) ::
          {:ok, [Worktree.t()]} | {:ok, :done} | {:error, {String.t(), non_neg_integer()}}
  @impl true
  def parse_output(stdout, 0) do
    mode = Process.get(@mode_key, :list)

    case mode do
      :mutation ->
        {:ok, :done}

      :list ->
        {:ok, Worktree.parse(stdout)}
    end
  end

  def parse_output(stdout, exit_code), do: {:error, {stdout, exit_code}}

  defp maybe_add_flag(args, false, _flag), do: args
  defp maybe_add_flag(args, true, flag), do: args ++ [flag]

  defp maybe_add_option(args, _flag, nil), do: args
  defp maybe_add_option(args, flag, value), do: args ++ [flag, value]

  defp maybe_add_value(args, nil), do: args
  defp maybe_add_value(args, value), do: args ++ [value]
end
