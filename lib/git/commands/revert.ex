defmodule Git.Commands.Revert do
  @moduledoc """
  Implements the `Git.Command` behaviour for `git revert`.

  Supports reverting one or more commits, aborting an in-progress revert,
  continuing after conflict resolution, and skipping a commit during a
  multi-commit revert.
  """

  @behaviour Git.Command

  alias Git.RevertResult

  @type t :: %__MODULE__{
          commits: [String.t()],
          no_commit: boolean(),
          abort: boolean(),
          continue_revert: boolean(),
          skip: boolean(),
          mainline: non_neg_integer() | nil,
          signoff: boolean(),
          no_edit: boolean(),
          strategy: String.t() | nil,
          strategy_option: String.t() | nil
        }

  defstruct commits: [],
            no_commit: false,
            abort: false,
            continue_revert: false,
            skip: false,
            mainline: nil,
            signoff: false,
            no_edit: false,
            strategy: nil,
            strategy_option: nil

  # Process dictionary key used to communicate the operation mode from args/1
  # to parse_output/2. Both are called from the same process inside
  # Git.Command.run/3, so this is safe even with async tests.
  @mode_key :__git_revert_mode__

  @doc """
  Returns the argument list for `git revert`.

  - When `:abort` is `true`, builds `git revert --abort`.
  - When `:continue_revert` is `true`, builds `git revert --continue`.
  - When `:skip` is `true`, builds `git revert --skip`.
  - Otherwise builds `git revert [options] <commits>`.

  ## Examples

      iex> Git.Commands.Revert.args(%Git.Commands.Revert{commits: ["HEAD"]})
      ["revert", "HEAD"]

      iex> Git.Commands.Revert.args(%Git.Commands.Revert{commits: ["HEAD"], no_commit: true})
      ["revert", "--no-commit", "HEAD"]

      iex> Git.Commands.Revert.args(%Git.Commands.Revert{abort: true})
      ["revert", "--abort"]

      iex> Git.Commands.Revert.args(%Git.Commands.Revert{continue_revert: true})
      ["revert", "--continue"]

      iex> Git.Commands.Revert.args(%Git.Commands.Revert{skip: true})
      ["revert", "--skip"]

  """
  @spec args(t()) :: [String.t()]
  @impl true
  def args(%__MODULE__{abort: true}) do
    Process.put(@mode_key, :control)
    ["revert", "--abort"]
  end

  def args(%__MODULE__{continue_revert: true}) do
    Process.put(@mode_key, :control)
    ["revert", "--continue"]
  end

  def args(%__MODULE__{skip: true}) do
    Process.put(@mode_key, :control)
    ["revert", "--skip"]
  end

  def args(%__MODULE__{} = command) do
    Process.put(@mode_key, :revert)

    ["revert"]
    |> maybe_add(command.no_commit, "--no-commit")
    |> maybe_add(command.signoff, "--signoff")
    |> maybe_add(command.no_edit, "--no-edit")
    |> maybe_add_option(command.mainline, "-m")
    |> maybe_add_option(command.strategy, "--strategy")
    |> maybe_add_option(command.strategy_option, "--strategy-option")
    |> Kernel.++(command.commits)
  end

  @doc """
  Parses the output of `git revert`.

  For `--abort`, `--continue`, and `--skip` operations (exit code 0), returns
  `{:ok, :done}`. For normal revert operations (exit code 0), parses into a
  `Git.RevertResult` struct. On failure, returns
  `{:error, {stdout, exit_code}}`.
  """
  @spec parse_output(String.t(), non_neg_integer()) ::
          {:ok, RevertResult.t()} | {:ok, :done} | {:error, {String.t(), non_neg_integer()}}
  @impl true
  def parse_output(stdout, 0) do
    case Process.get(@mode_key, :revert) do
      :control -> {:ok, :done}
      :revert -> {:ok, RevertResult.parse(stdout)}
    end
  end

  def parse_output(stdout, exit_code), do: {:error, {stdout, exit_code}}

  defp maybe_add(args, true, flag), do: args ++ [flag]
  defp maybe_add(args, false, _flag), do: args

  defp maybe_add_option(args, nil, _flag), do: args

  defp maybe_add_option(args, value, flag) when is_integer(value),
    do: args ++ [flag, Integer.to_string(value)]

  defp maybe_add_option(args, value, flag) when is_binary(value),
    do: args ++ [flag, value]
end
