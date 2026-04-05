defmodule Git.Commands.Merge do
  @moduledoc """
  Implements the `Git.Command` behaviour for `git merge`.

  Supports merging a branch, the `--no-ff` flag to force a merge commit, and
  `--abort` to abort an in-progress merge.
  """

  @behaviour Git.Command

  alias Git.MergeResult

  @type t :: %__MODULE__{
          branch: String.t() | nil,
          no_ff: boolean(),
          abort: boolean()
        }

  defstruct branch: nil,
            no_ff: false,
            abort: false

  # Process dictionary key used to communicate the operation mode from args/1
  # to parse_output/2. Both are called from the same process inside
  # Git.Command.run/3, so this is safe even with async tests.
  @mode_key :__git_merge_mode__

  @doc """
  Returns the argument list for `git merge`.

  - When `:abort` is `true`, builds `git merge --abort`.
  - Otherwise builds `git merge [--no-ff] <branch>`.

  ## Examples

      iex> Git.Commands.Merge.args(%Git.Commands.Merge{branch: "feature"})
      ["merge", "feature"]

      iex> Git.Commands.Merge.args(%Git.Commands.Merge{branch: "feature", no_ff: true})
      ["merge", "--no-ff", "feature"]

      iex> Git.Commands.Merge.args(%Git.Commands.Merge{abort: true})
      ["merge", "--abort"]

  """
  @spec args(t()) :: [String.t()]
  @impl true
  def args(%__MODULE__{abort: true}) do
    Process.put(@mode_key, :abort)
    ["merge", "--abort"]
  end

  def args(%__MODULE__{branch: branch} = command) when is_binary(branch) do
    Process.put(@mode_key, :merge)

    ["merge"]
    |> maybe_add(command.no_ff, "--no-ff")
    |> Kernel.++([branch])
  end

  @doc """
  Parses the output of `git merge`.

  For `--abort` operations (exit code 0), returns `{:ok, :done}`.
  For merge operations (exit code 0), parses into a `Git.MergeResult` struct.
  On failure, returns `{:error, {stdout, exit_code}}`.
  """
  @spec parse_output(String.t(), non_neg_integer()) ::
          {:ok, MergeResult.t()} | {:ok, :done} | {:error, {String.t(), non_neg_integer()}}
  @impl true
  def parse_output(stdout, 0) do
    case Process.get(@mode_key, :merge) do
      :abort -> {:ok, :done}
      :merge -> {:ok, MergeResult.parse(stdout)}
    end
  end

  def parse_output(stdout, exit_code), do: {:error, {stdout, exit_code}}

  defp maybe_add(args, true, flag), do: args ++ [flag]
  defp maybe_add(args, false, _flag), do: args
end
