defmodule Git.Commands.Pull do
  @moduledoc """
  Implements the `Git.Command` behaviour for `git pull`.

  Supports pulling from a remote with options for rebase, fast-forward,
  autostash, squash, depth, and more.
  """

  @behaviour Git.Command

  alias Git.PullResult

  @type t :: %__MODULE__{
          remote: String.t() | nil,
          branch: String.t() | nil,
          rebase: boolean() | String.t(),
          ff_only: boolean(),
          no_ff: boolean(),
          autostash: boolean(),
          no_autostash: boolean(),
          squash: boolean(),
          no_commit: boolean(),
          depth: pos_integer() | nil,
          dry_run: boolean(),
          tags: boolean(),
          no_tags: boolean(),
          prune: boolean(),
          verbose: boolean(),
          quiet: boolean()
        }

  defstruct remote: nil,
            branch: nil,
            rebase: false,
            ff_only: false,
            no_ff: false,
            autostash: false,
            no_autostash: false,
            squash: false,
            no_commit: false,
            depth: nil,
            dry_run: false,
            tags: false,
            no_tags: false,
            prune: false,
            verbose: false,
            quiet: false

  @doc """
  Returns the argument list for `git pull`.

  Builds the argument list from the struct fields. Boolean flags are appended
  when set to `true`. The `rebase` field may be `true` (for `--rebase`) or a
  string such as `"interactive"` or `"merges"` (for `--rebase=<value>`). The
  `remote` and `branch` positional arguments are appended at the end when
  present.

  ## Examples

      iex> Git.Commands.Pull.args(%Git.Commands.Pull{})
      ["pull"]

      iex> Git.Commands.Pull.args(%Git.Commands.Pull{remote: "origin", branch: "main"})
      ["pull", "origin", "main"]

      iex> Git.Commands.Pull.args(%Git.Commands.Pull{rebase: true})
      ["pull", "--rebase"]

      iex> Git.Commands.Pull.args(%Git.Commands.Pull{rebase: "merges"})
      ["pull", "--rebase=merges"]

      iex> Git.Commands.Pull.args(%Git.Commands.Pull{ff_only: true, prune: true})
      ["pull", "--ff-only", "--prune"]

  """
  @spec args(t()) :: [String.t()]
  @impl true
  def args(%__MODULE__{} = command) do
    flags =
      ["pull"]
      |> maybe_add_rebase(command.rebase)
      |> maybe_add(command.ff_only, "--ff-only")
      |> maybe_add(command.no_ff, "--no-ff")
      |> maybe_add(command.autostash, "--autostash")
      |> maybe_add(command.no_autostash, "--no-autostash")
      |> maybe_add(command.squash, "--squash")
      |> maybe_add(command.no_commit, "--no-commit")
      |> maybe_add_depth(command.depth)
      |> maybe_add(command.dry_run, "--dry-run")
      |> maybe_add(command.tags, "--tags")
      |> maybe_add(command.no_tags, "--no-tags")
      |> maybe_add(command.prune, "--prune")
      |> maybe_add(command.verbose, "--verbose")
      |> maybe_add(command.quiet, "--quiet")

    positional =
      []
      |> maybe_add_value(command.remote)
      |> maybe_add_value(command.branch)

    flags ++ positional
  end

  @doc """
  Parses the output of `git pull`.

  On success (exit code 0), parses the output into a `Git.PullResult`
  struct. On failure, returns `{:error, {stdout, exit_code}}`.
  """
  @spec parse_output(String.t(), non_neg_integer()) ::
          {:ok, PullResult.t()} | {:error, {String.t(), non_neg_integer()}}
  @impl true
  def parse_output(stdout, 0), do: {:ok, PullResult.parse(stdout)}
  def parse_output(stdout, exit_code), do: {:error, {stdout, exit_code}}

  defp maybe_add(args, true, flag), do: args ++ [flag]
  defp maybe_add(args, false, _flag), do: args

  defp maybe_add_rebase(args, false), do: args
  defp maybe_add_rebase(args, true), do: args ++ ["--rebase"]
  defp maybe_add_rebase(args, value) when is_binary(value), do: args ++ ["--rebase=#{value}"]

  defp maybe_add_depth(args, nil), do: args
  defp maybe_add_depth(args, depth) when is_integer(depth), do: args ++ ["--depth=#{depth}"]

  defp maybe_add_value(args, nil), do: args
  defp maybe_add_value(args, value) when is_binary(value), do: args ++ [value]
end
