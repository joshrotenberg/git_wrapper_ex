defmodule Git.Commands.Fetch do
  @moduledoc """
  Implements the `Git.Command` behaviour for `git fetch`.

  Supports fetching from a remote with options for pruning, tags, depth,
  submodules, and more.
  """

  @behaviour Git.Command

  @type t :: %__MODULE__{
          remote: String.t() | nil,
          branch: String.t() | nil,
          all: boolean(),
          prune: boolean(),
          prune_tags: boolean(),
          tags: boolean(),
          no_tags: boolean(),
          depth: pos_integer() | nil,
          unshallow: boolean(),
          dry_run: boolean(),
          force: boolean(),
          verbose: boolean(),
          quiet: boolean(),
          jobs: pos_integer() | nil,
          recurse_submodules: boolean() | String.t(),
          set_upstream: boolean()
        }

  defstruct remote: nil,
            branch: nil,
            all: false,
            prune: false,
            prune_tags: false,
            tags: false,
            no_tags: false,
            depth: nil,
            unshallow: false,
            dry_run: false,
            force: false,
            verbose: false,
            quiet: false,
            jobs: nil,
            recurse_submodules: false,
            set_upstream: false

  @doc """
  Returns the argument list for `git fetch`.

  Builds the argument list from the struct fields. Boolean flags are appended
  when set to `true`. The `recurse_submodules` field may be `true` (for
  `--recurse-submodules`) or a string such as `"yes"`, `"no"`, or `"on-demand"`
  (for `--recurse-submodules=<value>`). The `remote` and `branch` positional
  arguments are appended at the end when present.

  ## Examples

      iex> Git.Commands.Fetch.args(%Git.Commands.Fetch{})
      ["fetch"]

      iex> Git.Commands.Fetch.args(%Git.Commands.Fetch{remote: "origin"})
      ["fetch", "origin"]

      iex> Git.Commands.Fetch.args(%Git.Commands.Fetch{all: true, prune: true})
      ["fetch", "--all", "--prune"]

      iex> Git.Commands.Fetch.args(%Git.Commands.Fetch{remote: "origin", depth: 1})
      ["fetch", "--depth=1", "origin"]

      iex> Git.Commands.Fetch.args(%Git.Commands.Fetch{recurse_submodules: "on-demand"})
      ["fetch", "--recurse-submodules=on-demand"]

  """
  @spec args(t()) :: [String.t()]
  @impl true
  def args(%__MODULE__{} = command) do
    flags =
      ["fetch"]
      |> maybe_add(command.all, "--all")
      |> maybe_add(command.prune, "--prune")
      |> maybe_add(command.prune_tags, "--prune-tags")
      |> maybe_add(command.tags, "--tags")
      |> maybe_add(command.no_tags, "--no-tags")
      |> maybe_add_depth(command.depth)
      |> maybe_add(command.unshallow, "--unshallow")
      |> maybe_add(command.dry_run, "--dry-run")
      |> maybe_add(command.force, "--force")
      |> maybe_add(command.verbose, "--verbose")
      |> maybe_add(command.quiet, "--quiet")
      |> maybe_add_jobs(command.jobs)
      |> maybe_add_recurse_submodules(command.recurse_submodules)
      |> maybe_add(command.set_upstream, "--set-upstream")

    positional =
      []
      |> maybe_add_value(command.remote)
      |> maybe_add_value(command.branch)

    flags ++ positional
  end

  @doc """
  Parses the output of `git fetch`.

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

  defp maybe_add_depth(args, nil), do: args
  defp maybe_add_depth(args, depth) when is_integer(depth), do: args ++ ["--depth=#{depth}"]

  defp maybe_add_jobs(args, nil), do: args
  defp maybe_add_jobs(args, jobs) when is_integer(jobs), do: args ++ ["--jobs=#{jobs}"]

  defp maybe_add_recurse_submodules(args, false), do: args

  defp maybe_add_recurse_submodules(args, true),
    do: args ++ ["--recurse-submodules"]

  defp maybe_add_recurse_submodules(args, value) when is_binary(value),
    do: args ++ ["--recurse-submodules=#{value}"]

  defp maybe_add_value(args, nil), do: args
  defp maybe_add_value(args, value) when is_binary(value), do: args ++ [value]
end
