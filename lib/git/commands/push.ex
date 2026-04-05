defmodule Git.Commands.Push do
  @moduledoc """
  Implements the `Git.Command` behaviour for `git push`.

  Supports pushing to a remote with options for force push, upstream tracking,
  tags, delete, dry run, and more.
  """

  @behaviour Git.Command

  @type t :: %__MODULE__{
          remote: String.t() | nil,
          branch: String.t() | nil,
          force: boolean(),
          force_with_lease: boolean(),
          set_upstream: boolean(),
          tags: boolean(),
          delete: boolean(),
          dry_run: boolean(),
          all: boolean(),
          no_verify: boolean(),
          atomic: boolean(),
          prune: boolean()
        }

  defstruct remote: nil,
            branch: nil,
            force: false,
            force_with_lease: false,
            set_upstream: false,
            tags: false,
            delete: false,
            dry_run: false,
            all: false,
            no_verify: false,
            atomic: false,
            prune: false

  @doc """
  Returns the argument list for `git push`.

  Builds the argument list from the struct fields. Boolean flags are appended
  when set to `true`. The `remote` and `branch` positional arguments are
  appended at the end when present.

  ## Examples

      iex> Git.Commands.Push.args(%Git.Commands.Push{})
      ["push"]

      iex> Git.Commands.Push.args(%Git.Commands.Push{remote: "origin", branch: "main"})
      ["push", "origin", "main"]

      iex> Git.Commands.Push.args(%Git.Commands.Push{remote: "origin", set_upstream: true, branch: "feature"})
      ["push", "-u", "origin", "feature"]

      iex> Git.Commands.Push.args(%Git.Commands.Push{force: true, tags: true})
      ["push", "--force", "--tags"]

  """
  @spec args(t()) :: [String.t()]
  @impl true
  def args(%__MODULE__{} = command) do
    flags =
      ["push"]
      |> maybe_add(command.force, "--force")
      |> maybe_add(command.force_with_lease, "--force-with-lease")
      |> maybe_add(command.set_upstream, "-u")
      |> maybe_add(command.tags, "--tags")
      |> maybe_add(command.delete, "--delete")
      |> maybe_add(command.dry_run, "--dry-run")
      |> maybe_add(command.all, "--all")
      |> maybe_add(command.no_verify, "--no-verify")
      |> maybe_add(command.atomic, "--atomic")
      |> maybe_add(command.prune, "--prune")

    positional =
      []
      |> maybe_add_value(command.remote)
      |> maybe_add_value(command.branch)

    flags ++ positional
  end

  @doc """
  Parses the output of `git push`.

  On success (exit code 0), returns `{:ok, :done}`. On failure, returns
  `{:error, {stdout, exit_code}}`.
  """
  @spec parse_output(String.t(), non_neg_integer()) ::
          {:ok, :done} | {:error, {String.t(), non_neg_integer()}}
  @impl true
  def parse_output(_stdout, 0), do: {:ok, :done}
  def parse_output(stdout, exit_code), do: {:error, {stdout, exit_code}}

  defp maybe_add(args, true, flag), do: args ++ [flag]
  defp maybe_add(args, false, _flag), do: args

  defp maybe_add_value(args, nil), do: args
  defp maybe_add_value(args, value) when is_binary(value), do: args ++ [value]
end
