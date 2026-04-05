defmodule Git.Commands.MergeBase do
  @moduledoc """
  Implements the `Git.Command` behaviour for `git merge-base`.

  Finds the best common ancestor(s) between two or more commits for use
  in a three-way merge. Also supports checking ancestor relationships
  and finding fork points.
  """

  @behaviour Git.Command

  @mode_key :__merge_base_output_mode

  @type t :: %__MODULE__{
          commits: [String.t()],
          is_ancestor: boolean(),
          fork_point: boolean(),
          octopus: boolean(),
          all: boolean(),
          independent: boolean()
        }

  defstruct commits: [],
            is_ancestor: false,
            fork_point: false,
            octopus: false,
            all: false,
            independent: false

  @doc """
  Builds the argument list for `git merge-base`.

  ## Examples

      iex> Git.Commands.MergeBase.args(%Git.Commands.MergeBase{commits: ["main", "feature"]})
      ["merge-base", "main", "feature"]

      iex> Git.Commands.MergeBase.args(%Git.Commands.MergeBase{commits: ["main", "feature"], is_ancestor: true})
      ["merge-base", "--is-ancestor", "main", "feature"]

      iex> Git.Commands.MergeBase.args(%Git.Commands.MergeBase{commits: ["main", "feature"], all: true})
      ["merge-base", "--all", "main", "feature"]

      iex> Git.Commands.MergeBase.args(%Git.Commands.MergeBase{commits: ["a", "b", "c"], octopus: true})
      ["merge-base", "--octopus", "a", "b", "c"]

      iex> Git.Commands.MergeBase.args(%Git.Commands.MergeBase{commits: ["a", "b", "c"], independent: true})
      ["merge-base", "--independent", "a", "b", "c"]

      iex> Git.Commands.MergeBase.args(%Git.Commands.MergeBase{commits: ["main", "feature"], fork_point: true})
      ["merge-base", "--fork-point", "main", "feature"]

  """
  @spec args(t()) :: [String.t()]
  @impl true
  def args(%__MODULE__{} = command) do
    set_output_mode(command)
    base = ["merge-base"]

    base
    |> maybe_add_flag(command.is_ancestor, "--is-ancestor")
    |> maybe_add_flag(command.fork_point, "--fork-point")
    |> maybe_add_flag(command.octopus, "--octopus")
    |> maybe_add_flag(command.all, "--all")
    |> maybe_add_flag(command.independent, "--independent")
    |> Kernel.++(command.commits)
  end

  @doc """
  Parses the output of `git merge-base`.

  The output mode depends on the flags used:

    * Default: returns `{:ok, String.t()}` with the ancestor SHA
    * With `is_ancestor: true`: exit 0 = `{:ok, true}`, exit 1 = `{:ok, false}`
    * With `all: true` or `independent: true`: returns `{:ok, [String.t()]}`
  """
  @spec parse_output(String.t(), non_neg_integer()) ::
          {:ok, String.t() | boolean() | [String.t()]}
          | {:error, {String.t(), non_neg_integer()}}
  @impl true
  def parse_output(stdout, exit_code) do
    parse_by_mode(stdout, exit_code, output_mode())
  end

  defp output_mode do
    Process.get(@mode_key, :single)
  end

  @doc false
  def set_output_mode(%__MODULE__{} = command) do
    mode =
      cond do
        command.is_ancestor -> :is_ancestor
        command.all -> :multi
        command.independent -> :multi
        true -> :single
      end

    Process.put(@mode_key, mode)
    command
  end

  defp parse_by_mode(_stdout, 0, :is_ancestor), do: {:ok, true}
  defp parse_by_mode(_stdout, 1, :is_ancestor), do: {:ok, false}

  defp parse_by_mode(stdout, 0, :multi) do
    shas =
      stdout
      |> String.split("\n", trim: true)
      |> Enum.map(&String.trim/1)

    {:ok, shas}
  end

  defp parse_by_mode(stdout, 0, :single) do
    {:ok, String.trim(stdout)}
  end

  defp parse_by_mode(stdout, exit_code, _mode), do: {:error, {stdout, exit_code}}

  defp maybe_add_flag(args, true, flag), do: args ++ [flag]
  defp maybe_add_flag(args, false, _flag), do: args
end
