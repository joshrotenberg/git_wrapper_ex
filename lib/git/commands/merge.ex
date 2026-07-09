defmodule Git.Commands.Merge do
  @moduledoc """
  Implements the `Git.Command` behaviour for `git merge`.

  Merges a branch, with `--no-ff`, `--ff-only`, `--squash`, `--no-commit`,
  `--no-edit`, `--allow-unrelated-histories`, a message (`-m`), a strategy
  (`-s`), and strategy options (`-X`, repeatable). Also drives the in-progress
  merge with `--abort`, `--continue`, and `--quit`.
  """

  @behaviour Git.Command

  alias Git.MergeResult

  @type t :: %__MODULE__{
          branch: String.t() | nil,
          no_ff: boolean(),
          ff_only: boolean(),
          squash: boolean(),
          no_commit: boolean(),
          no_edit: boolean(),
          allow_unrelated_histories: boolean(),
          message: String.t() | nil,
          strategy: String.t() | nil,
          strategy_option: [String.t()],
          abort: boolean(),
          continue: boolean(),
          quit: boolean()
        }

  defstruct branch: nil,
            no_ff: false,
            ff_only: false,
            squash: false,
            no_commit: false,
            no_edit: false,
            allow_unrelated_histories: false,
            message: nil,
            strategy: nil,
            strategy_option: [],
            abort: false,
            continue: false,
            quit: false

  # Process dictionary key used to communicate the operation mode from args/1
  # to parse_output/2. Both are called from the same process inside
  # Git.Command.run/3, so this is safe even with async tests.
  @mode_key :__git_merge_mode__

  @doc """
  Returns the argument list for `git merge`.

  - `:abort`/`:continue`/`:quit` build the corresponding in-progress-merge form.
  - Otherwise builds `git merge [flags] <branch>`.

  ## Examples

      iex> Git.Commands.Merge.args(%Git.Commands.Merge{branch: "feature"})
      ["merge", "feature"]

      iex> Git.Commands.Merge.args(%Git.Commands.Merge{branch: "feature", no_ff: true})
      ["merge", "--no-ff", "feature"]

      iex> Git.Commands.Merge.args(%Git.Commands.Merge{abort: true})
      ["merge", "--abort"]

      iex> Git.Commands.Merge.args(%Git.Commands.Merge{branch: "feature", squash: true})
      ["merge", "--squash", "feature"]

      iex> Git.Commands.Merge.args(%Git.Commands.Merge{branch: "f", strategy_option: ["ours", "ignore-all-space"]})
      ["merge", "--strategy-option", "ours", "--strategy-option", "ignore-all-space", "f"]

  """
  @spec args(t()) :: [String.t()]
  @impl true
  def args(%__MODULE__{abort: true}) do
    Process.put(@mode_key, :done)
    ["merge", "--abort"]
  end

  def args(%__MODULE__{quit: true}) do
    Process.put(@mode_key, :done)
    ["merge", "--quit"]
  end

  def args(%__MODULE__{continue: true}) do
    Process.put(@mode_key, :done)
    # Conclude the in-progress merge non-interactively. `git merge --continue`
    # rejects `--no-edit`/`-m` ("expects no arguments") and opens an editor for
    # the merge message, which fails with no TTY/editor. `git commit --no-edit`
    # is git's documented equivalent: it concludes the merge using the prepared
    # MERGE_MSG without an editor.
    ["commit", "--no-edit"]
  end

  def args(%__MODULE__{branch: branch} = command) when is_binary(branch) do
    Process.put(@mode_key, :merge)

    ["merge"]
    |> merge_flags(command)
    |> Kernel.++([branch])
  end

  @doc """
  Parses the output of `git merge`.

  For `--abort`/`--continue`/`--quit` (exit code 0), returns `{:ok, :done}`.
  For a branch merge (exit code 0), parses into a `Git.MergeResult` struct.
  On failure, returns `{:error, {stdout, exit_code}}`.
  """
  @spec parse_output(String.t(), non_neg_integer()) ::
          {:ok, MergeResult.t()} | {:ok, :done} | {:error, {String.t(), non_neg_integer()}}
  @impl true
  def parse_output(stdout, 0) do
    case Process.get(@mode_key, :merge) do
      :done -> {:ok, :done}
      :merge -> {:ok, MergeResult.parse(stdout)}
    end
  end

  def parse_output(stdout, exit_code), do: {:error, {stdout, exit_code}}

  defp merge_flags(args, command) do
    args
    |> maybe_add(command.no_ff, "--no-ff")
    |> maybe_add(command.ff_only, "--ff-only")
    |> maybe_add(command.squash, "--squash")
    |> maybe_add(command.no_commit, "--no-commit")
    |> maybe_add(command.no_edit, "--no-edit")
    |> maybe_add(command.allow_unrelated_histories, "--allow-unrelated-histories")
    |> maybe_add_value(command.strategy, "--strategy")
    |> add_strategy_options(command.strategy_option)
    |> maybe_add_value(command.message, "-m")
  end

  defp add_strategy_options(args, []), do: args

  defp add_strategy_options(args, options) when is_list(options) do
    Enum.reduce(options, args, fn option, acc -> acc ++ ["--strategy-option", option] end)
  end

  defp maybe_add(args, true, flag), do: args ++ [flag]
  defp maybe_add(args, false, _flag), do: args

  defp maybe_add_value(args, nil, _flag), do: args
  defp maybe_add_value(args, value, flag) when is_binary(value), do: args ++ [flag, value]
end
