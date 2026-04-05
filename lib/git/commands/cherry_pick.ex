defmodule Git.Commands.CherryPick do
  @moduledoc """
  Implements the `Git.Command` behaviour for `git cherry-pick`.

  Supports cherry-picking one or more commits, as well as aborting,
  continuing, and skipping in-progress cherry-pick operations.

  ## Unsupported options

  The `--edit` (`-e`) flag is intentionally not supported because it
  requires an interactive editor session, which cannot be driven by a
  non-interactive CLI wrapper.
  """

  @behaviour Git.Command

  alias Git.CherryPickResult

  @type t :: %__MODULE__{
          commits: [String.t()],
          no_commit: boolean(),
          abort: boolean(),
          continue_pick: boolean(),
          skip: boolean(),
          mainline: non_neg_integer() | nil,
          signoff: boolean(),
          allow_empty: boolean(),
          allow_empty_message: boolean(),
          keep_redundant_commits: boolean(),
          strategy: String.t() | nil,
          strategy_option: String.t() | nil
        }

  defstruct commits: [],
            no_commit: false,
            abort: false,
            continue_pick: false,
            skip: false,
            mainline: nil,
            signoff: false,
            allow_empty: false,
            allow_empty_message: false,
            keep_redundant_commits: false,
            strategy: nil,
            strategy_option: nil

  # Process dictionary key used to communicate the operation mode from args/1
  # to parse_output/2. Both are called from the same process inside
  # Git.Command.run/3, so this is safe even with async tests.
  @mode_key :__git_cherry_pick_mode__

  @doc """
  Returns the argument list for `git cherry-pick`.

  When `:abort`, `:continue_pick`, or `:skip` is `true`, builds the
  corresponding control command. Otherwise builds the full cherry-pick command
  with all applicable flags and commit refs.

  ## Examples

      iex> Git.Commands.CherryPick.args(%Git.Commands.CherryPick{abort: true})
      ["cherry-pick", "--abort"]

      iex> Git.Commands.CherryPick.args(%Git.Commands.CherryPick{continue_pick: true})
      ["cherry-pick", "--continue"]

      iex> Git.Commands.CherryPick.args(%Git.Commands.CherryPick{skip: true})
      ["cherry-pick", "--skip"]

      iex> Git.Commands.CherryPick.args(%Git.Commands.CherryPick{commits: ["abc123"]})
      ["cherry-pick", "abc123"]

      iex> Git.Commands.CherryPick.args(%Git.Commands.CherryPick{commits: ["abc123"], no_commit: true})
      ["cherry-pick", "--no-commit", "abc123"]

  """
  @spec args(t()) :: [String.t()]
  @impl true
  def args(%__MODULE__{abort: true}) do
    Process.put(@mode_key, :mutation)
    ["cherry-pick", "--abort"]
  end

  def args(%__MODULE__{continue_pick: true}) do
    Process.put(@mode_key, :mutation)
    ["cherry-pick", "--continue"]
  end

  def args(%__MODULE__{skip: true}) do
    Process.put(@mode_key, :mutation)
    ["cherry-pick", "--skip"]
  end

  def args(%__MODULE__{commits: commits} = command) do
    Process.put(@mode_key, :pick)

    ["cherry-pick"]
    |> maybe_add(command.no_commit, "--no-commit")
    |> maybe_add_value(command.mainline, "-m")
    |> maybe_add(command.signoff, "--signoff")
    |> maybe_add(command.allow_empty, "--allow-empty")
    |> maybe_add(command.allow_empty_message, "--allow-empty-message")
    |> maybe_add(command.keep_redundant_commits, "--keep-redundant-commits")
    |> maybe_add_option(command.strategy, "--strategy")
    |> maybe_add_option(command.strategy_option, "--strategy-option")
    |> Kernel.++(commits)
  end

  @doc """
  Parses the output of `git cherry-pick`.

  For mutation operations (abort, continue, skip) with exit code 0, returns
  `{:ok, :done}`. For normal pick operations, parses into a
  `Git.CherryPickResult` struct. On failure, returns
  `{:error, {stdout, exit_code}}`.
  """
  @spec parse_output(String.t(), non_neg_integer()) ::
          {:ok, CherryPickResult.t()} | {:ok, :done} | {:error, {String.t(), non_neg_integer()}}
  @impl true
  def parse_output(stdout, 0) do
    case Process.get(@mode_key, :pick) do
      :mutation -> {:ok, :done}
      :pick -> {:ok, CherryPickResult.parse(stdout)}
    end
  end

  def parse_output(stdout, exit_code), do: {:error, {stdout, exit_code}}

  defp maybe_add(args, true, flag), do: args ++ [flag]
  defp maybe_add(args, false, _flag), do: args

  defp maybe_add_value(args, nil, _flag), do: args
  defp maybe_add_value(args, value, flag), do: args ++ [flag, to_string(value)]

  defp maybe_add_option(args, nil, _flag), do: args
  defp maybe_add_option(args, value, flag), do: args ++ [flag, value]
end
