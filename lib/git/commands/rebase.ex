defmodule Git.Commands.Rebase do
  @moduledoc """
  Implements the `Git.Command` behaviour for `git rebase`.

  Supports rebasing a branch onto an upstream ref, as well as aborting,
  continuing, and skipping in-progress rebases.

  ## Unsupported options

  The `--interactive` (`-i`) flag is intentionally not supported because it
  requires an interactive editor session, which cannot be driven by a
  non-interactive CLI wrapper.
  """

  @behaviour Git.Command

  alias Git.RebaseResult

  @type t :: %__MODULE__{
          upstream: String.t() | nil,
          branch: String.t() | nil,
          onto: String.t() | nil,
          abort: boolean(),
          continue_rebase: boolean(),
          skip: boolean(),
          autostash: boolean(),
          no_autostash: boolean(),
          autosquash: boolean(),
          no_autosquash: boolean(),
          keep_empty: boolean(),
          no_keep_empty: boolean(),
          rebase_merges: boolean(),
          force_rebase: boolean(),
          verbose: boolean(),
          quiet: boolean(),
          stat: boolean(),
          no_stat: boolean()
        }

  defstruct upstream: nil,
            branch: nil,
            onto: nil,
            abort: false,
            continue_rebase: false,
            skip: false,
            autostash: false,
            no_autostash: false,
            autosquash: false,
            no_autosquash: false,
            keep_empty: false,
            no_keep_empty: false,
            rebase_merges: false,
            force_rebase: false,
            verbose: false,
            quiet: false,
            stat: false,
            no_stat: false

  # Process dictionary key used to communicate the operation mode from args/1
  # to parse_output/2. Both are called from the same process inside
  # Git.Command.run/3, so this is safe even with async tests.
  @mode_key :__git_rebase_mode__

  @doc """
  Returns the argument list for `git rebase`.

  When `:abort`, `:continue_rebase`, or `:skip` is `true`, builds the
  corresponding mutation command. Otherwise builds the full rebase command
  with all applicable flags.

  ## Examples

      iex> Git.Commands.Rebase.args(%Git.Commands.Rebase{abort: true})
      ["rebase", "--abort"]

      iex> Git.Commands.Rebase.args(%Git.Commands.Rebase{continue_rebase: true})
      ["rebase", "--continue"]

      iex> Git.Commands.Rebase.args(%Git.Commands.Rebase{skip: true})
      ["rebase", "--skip"]

      iex> Git.Commands.Rebase.args(%Git.Commands.Rebase{upstream: "main"})
      ["rebase", "main"]

      iex> Git.Commands.Rebase.args(%Git.Commands.Rebase{upstream: "main", branch: "feat"})
      ["rebase", "main", "feat"]

      iex> Git.Commands.Rebase.args(%Git.Commands.Rebase{onto: "main", upstream: "feature"})
      ["rebase", "--onto", "main", "feature"]

  """
  @spec args(t()) :: [String.t()]
  @impl true
  def args(%__MODULE__{abort: true}) do
    Process.put(@mode_key, :mutation)
    ["rebase", "--abort"]
  end

  def args(%__MODULE__{continue_rebase: true}) do
    Process.put(@mode_key, :mutation)
    ["rebase", "--continue"]
  end

  def args(%__MODULE__{skip: true}) do
    Process.put(@mode_key, :mutation)
    ["rebase", "--skip"]
  end

  def args(%__MODULE__{} = command) do
    Process.put(@mode_key, :rebase)

    ["rebase"]
    |> maybe_add_option(command.onto, "--onto")
    |> maybe_add(command.autostash, "--autostash")
    |> maybe_add(command.no_autostash, "--no-autostash")
    |> maybe_add(command.autosquash, "--autosquash")
    |> maybe_add(command.no_autosquash, "--no-autosquash")
    |> maybe_add(command.keep_empty, "--keep-empty")
    |> maybe_add(command.no_keep_empty, "--no-keep-empty")
    |> maybe_add(command.rebase_merges, "--rebase-merges")
    |> maybe_add(command.force_rebase, "--force-rebase")
    |> maybe_add(command.verbose, "--verbose")
    |> maybe_add(command.quiet, "--quiet")
    |> maybe_add(command.stat, "--stat")
    |> maybe_add(command.no_stat, "--no-stat")
    |> maybe_add_value(command.upstream)
    |> maybe_add_value(command.branch)
  end

  @doc """
  Parses the output of `git rebase`.

  For mutation operations (abort, continue, skip) with exit code 0, returns
  `{:ok, :done}`. For normal rebase operations, parses into a
  `Git.RebaseResult` struct. On failure, returns
  `{:error, {stdout, exit_code}}`.
  """
  @spec parse_output(String.t(), non_neg_integer()) ::
          {:ok, RebaseResult.t()} | {:ok, :done} | {:error, {String.t(), non_neg_integer()}}
  @impl true
  def parse_output(stdout, 0) do
    case Process.get(@mode_key, :rebase) do
      :mutation -> {:ok, :done}
      :rebase -> {:ok, RebaseResult.parse(stdout)}
    end
  end

  def parse_output(stdout, exit_code), do: {:error, {stdout, exit_code}}

  defp maybe_add(args, true, flag), do: args ++ [flag]
  defp maybe_add(args, false, _flag), do: args

  defp maybe_add_value(args, nil), do: args
  defp maybe_add_value(args, value), do: args ++ [value]

  defp maybe_add_option(args, nil, _flag), do: args
  defp maybe_add_option(args, value, flag), do: args ++ [flag, value]
end
