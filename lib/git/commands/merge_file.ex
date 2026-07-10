defmodule Git.Commands.MergeFile do
  @moduledoc """
  Implements the `Git.Command` behaviour for `git merge-file`.

  `git merge-file` runs a scripted three-way file merge. It incorporates the
  changes that lead from `base` to `other` into `current`, writing the merged
  result (with conflict markers where the two sides overlap) back into the
  `current` file. Nothing in the repository index or history is touched: this
  operates purely on the three files on disk.

  The process exit code carries the number of conflicts as a signal: `0` for a
  clean merge, or the conflict count (clamped by git to `127`). Values of `128`
  and above indicate a real error (bad option, missing file), not a conflict
  count. `parse_output/2` distinguishes the two.
  """

  @behaviour Git.Command

  # git clamps the reported conflict count to this value; anything higher is a
  # real error (usage error, fatal file error), not a conflict-count signal.
  @max_conflict_signal 127

  @type t :: %__MODULE__{
          current: String.t() | nil,
          base: String.t() | nil,
          other: String.t() | nil,
          quiet: boolean(),
          ours: boolean(),
          theirs: boolean(),
          union: boolean(),
          diff3: boolean(),
          zdiff3: boolean(),
          marker_size: pos_integer() | nil,
          labels: [String.t()]
        }

  defstruct current: nil,
            base: nil,
            other: nil,
            quiet: false,
            ours: false,
            theirs: false,
            union: false,
            diff3: false,
            zdiff3: false,
            marker_size: nil,
            labels: []

  @doc """
  Returns the argument list for `git merge-file`.

  ## Examples

      iex> Git.Commands.MergeFile.args(%Git.Commands.MergeFile{current: "a", base: "o", other: "b"})
      ["merge-file", "a", "o", "b"]

      iex> Git.Commands.MergeFile.args(%Git.Commands.MergeFile{current: "a", base: "o", other: "b", ours: true})
      ["merge-file", "--ours", "a", "o", "b"]

      iex> Git.Commands.MergeFile.args(%Git.Commands.MergeFile{current: "a", base: "o", other: "b", labels: ["mine", "orig", "theirs"]})
      ["merge-file", "-L", "mine", "-L", "orig", "-L", "theirs", "a", "o", "b"]

  """
  @spec args(t()) :: [String.t()]
  @impl true
  def args(%__MODULE__{} = cmd) do
    ["merge-file"] ++
      build_flags(cmd) ++ build_labels(cmd.labels) ++ [cmd.current, cmd.base, cmd.other]
  end

  defp build_flags(%__MODULE__{} = cmd) do
    []
    |> maybe_add(cmd.quiet, "-q")
    |> maybe_add(cmd.ours, "--ours")
    |> maybe_add(cmd.theirs, "--theirs")
    |> maybe_add(cmd.union, "--union")
    |> maybe_add(cmd.diff3, "--diff3")
    |> maybe_add(cmd.zdiff3, "--zdiff3")
    |> maybe_add_value(cmd.marker_size, "--marker-size")
  end

  defp build_labels(labels) do
    Enum.flat_map(labels, fn label -> ["-L", label] end)
  end

  defp maybe_add(list, true, flag), do: list ++ [flag]
  defp maybe_add(list, _, _flag), do: list

  defp maybe_add_value(list, nil, _flag), do: list
  defp maybe_add_value(list, value, flag), do: list ++ [flag, to_string(value)]

  @doc """
  Parses the output of `git merge-file`.

  The exit code is the number of conflicts. A clean merge returns `{:ok, 0}`;
  a merge that left conflict markers in the `current` file returns
  `{:ok, count}` with `count > 0`. Exit codes of `128` or greater are real
  errors and return `{:error, {stdout, exit_code}}`.
  """
  @spec parse_output(String.t(), non_neg_integer()) ::
          {:ok, non_neg_integer()} | {:error, {String.t(), non_neg_integer()}}
  @impl true
  def parse_output(_stdout, exit_code) when exit_code in 0..@max_conflict_signal do
    {:ok, exit_code}
  end

  def parse_output(stdout, exit_code), do: {:error, {stdout, exit_code}}
end
