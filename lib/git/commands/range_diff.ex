defmodule Git.Commands.RangeDiff do
  @moduledoc """
  Implements the `Git.Command` behaviour for `git range-diff`.

  Compares two sequences of commits (revision ranges). Supports both
  the two-range form (`range1 range2`) and the three-argument form
  (`rev1 rev2 rev3`).
  """

  @behaviour Git.Command

  @type t :: %__MODULE__{
          range1: String.t() | nil,
          range2: String.t() | nil,
          rev1: String.t() | nil,
          rev2: String.t() | nil,
          rev3: String.t() | nil,
          stat: boolean(),
          no_patch: boolean(),
          creation_factor: non_neg_integer() | nil,
          no_dual_color: boolean(),
          left_only: boolean(),
          right_only: boolean(),
          no_notes: boolean()
        }

  defstruct range1: nil,
            range2: nil,
            rev1: nil,
            rev2: nil,
            rev3: nil,
            stat: false,
            no_patch: false,
            creation_factor: nil,
            no_dual_color: false,
            left_only: false,
            right_only: false,
            no_notes: false

  @doc """
  Returns the argument list for `git range-diff`.

  Builds `git range-diff [flags] range1 range2` when `range1` and `range2`
  are set, or `git range-diff [flags] rev1 rev2 rev3` when the three-argument
  form is used.

  ## Examples

      iex> Git.Commands.RangeDiff.args(%Git.Commands.RangeDiff{range1: "main..topic-v1", range2: "main..topic-v2"})
      ["range-diff", "main..topic-v1", "main..topic-v2"]

      iex> Git.Commands.RangeDiff.args(%Git.Commands.RangeDiff{rev1: "main", rev2: "topic-v1", rev3: "topic-v2"})
      ["range-diff", "main", "topic-v1", "topic-v2"]

      iex> Git.Commands.RangeDiff.args(%Git.Commands.RangeDiff{range1: "main..v1", range2: "main..v2", stat: true})
      ["range-diff", "--stat", "main..v1", "main..v2"]

      iex> Git.Commands.RangeDiff.args(%Git.Commands.RangeDiff{range1: "a..b", range2: "a..c", creation_factor: 50})
      ["range-diff", "--creation-factor=50", "a..b", "a..c"]

  """
  @spec args(t()) :: [String.t()]
  @impl true
  def args(%__MODULE__{} = command) do
    base = ["range-diff"]

    flags =
      base
      |> maybe_add_flag(command.stat, "--stat")
      |> maybe_add_flag(command.no_patch, "--no-patch")
      |> maybe_add_creation_factor(command.creation_factor)
      |> maybe_add_flag(command.no_dual_color, "--no-dual-color")
      |> maybe_add_flag(command.left_only, "--left-only")
      |> maybe_add_flag(command.right_only, "--right-only")
      |> maybe_add_flag(command.no_notes, "--no-notes")

    flags ++ positional_args(command)
  end

  @doc """
  Parses the output of `git range-diff`.

  On success (exit code 0), returns `{:ok, raw_output}` as a string.
  Range-diff output contains color codes and varying formats, so returning
  the raw string is the practical choice.
  On failure, returns `{:error, {stdout, exit_code}}`.
  """
  @spec parse_output(String.t(), non_neg_integer()) ::
          {:ok, String.t()} | {:error, {String.t(), non_neg_integer()}}
  @impl true
  def parse_output(stdout, 0), do: {:ok, stdout}
  def parse_output(stdout, exit_code), do: {:error, {stdout, exit_code}}

  defp positional_args(%__MODULE__{range1: r1, range2: r2})
       when is_binary(r1) and is_binary(r2) do
    [r1, r2]
  end

  defp positional_args(%__MODULE__{rev1: r1, rev2: r2, rev3: r3})
       when is_binary(r1) and is_binary(r2) and is_binary(r3) do
    [r1, r2, r3]
  end

  defp positional_args(_), do: []

  defp maybe_add_flag(args, false, _flag), do: args
  defp maybe_add_flag(args, true, flag), do: args ++ [flag]

  defp maybe_add_creation_factor(args, nil), do: args

  defp maybe_add_creation_factor(args, n) when is_integer(n),
    do: args ++ ["--creation-factor=#{n}"]
end
