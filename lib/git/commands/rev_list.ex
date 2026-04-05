defmodule Git.Commands.RevList do
  @moduledoc """
  Implements the `Git.Command` behaviour for `git rev-list`.

  Lists commit objects in reverse chronological order. Supports counting,
  left-right comparison, ancestry filtering, and various commit-limiting
  options.
  """

  @behaviour Git.Command

  @mode_key :__output_mode

  @type t :: %__MODULE__{
          ref: String.t() | nil,
          max_count: non_neg_integer() | nil,
          skip: non_neg_integer() | nil,
          count: boolean(),
          left_right: boolean(),
          ancestry_path: boolean(),
          first_parent: boolean(),
          merges: boolean(),
          no_merges: boolean(),
          reverse: boolean(),
          since: String.t() | nil,
          until_date: String.t() | nil,
          author: String.t() | nil,
          all: boolean(),
          objects: boolean(),
          no_walk: boolean()
        }

  defstruct ref: nil,
            max_count: nil,
            skip: nil,
            count: false,
            left_right: false,
            ancestry_path: false,
            first_parent: false,
            merges: false,
            no_merges: false,
            reverse: false,
            since: nil,
            until_date: nil,
            author: nil,
            all: false,
            objects: false,
            no_walk: false

  @doc """
  Builds the argument list for `git rev-list`.

  ## Examples

      iex> Git.Commands.RevList.args(%Git.Commands.RevList{ref: "HEAD"})
      ["rev-list", "HEAD"]

      iex> Git.Commands.RevList.args(%Git.Commands.RevList{ref: "HEAD", count: true})
      ["rev-list", "--count", "HEAD"]

      iex> Git.Commands.RevList.args(%Git.Commands.RevList{ref: "main..feature", left_right: true, count: true})
      ["rev-list", "--count", "--left-right", "main..feature"]

      iex> Git.Commands.RevList.args(%Git.Commands.RevList{ref: "HEAD", max_count: 5})
      ["rev-list", "--max-count=5", "HEAD"]

      iex> Git.Commands.RevList.args(%Git.Commands.RevList{all: true})
      ["rev-list", "--all"]

  """
  @spec args(t()) :: [String.t()]
  @impl true
  def args(%__MODULE__{} = command) do
    set_output_mode(command)
    base = ["rev-list"]

    base
    |> maybe_add("--max-count=", command.max_count)
    |> maybe_add("--skip=", command.skip)
    |> maybe_add_flag(command.count, "--count")
    |> maybe_add_flag(command.left_right, "--left-right")
    |> maybe_add_flag(command.ancestry_path, "--ancestry-path")
    |> maybe_add_flag(command.first_parent, "--first-parent")
    |> maybe_add_flag(command.merges, "--merges")
    |> maybe_add_flag(command.no_merges, "--no-merges")
    |> maybe_add_flag(command.reverse, "--reverse")
    |> maybe_add("--since=", command.since)
    |> maybe_add("--until=", command.until_date)
    |> maybe_add("--author=", command.author)
    |> maybe_add_flag(command.all, "--all")
    |> maybe_add_flag(command.objects, "--objects")
    |> maybe_add_flag(command.no_walk, "--no-walk")
    |> maybe_add_ref(command.ref)
  end

  @doc """
  Parses the output of `git rev-list`.

  The output mode depends on the flags used:

    * Default: returns `{:ok, [String.t()]}` with a list of SHAs
    * With `count: true`: returns `{:ok, integer()}`
    * With `left_right: true` and `count: true`: returns
      `{:ok, %{left: integer(), right: integer()}}`
  """
  @spec parse_output(String.t(), non_neg_integer()) ::
          {:ok, [String.t()] | integer() | map()} | {:error, {String.t(), non_neg_integer()}}
  @impl true
  def parse_output(stdout, 0) do
    {:ok, parse_by_mode(stdout, output_mode())}
  end

  def parse_output(stdout, exit_code), do: {:error, {stdout, exit_code}}

  # Determines the output mode based on Process dictionary state.
  # This is set by the run wrapper before execution.
  defp output_mode do
    Process.get(@mode_key, :list)
  end

  @doc false
  def set_output_mode(%__MODULE__{} = command) do
    mode =
      cond do
        command.left_right and command.count -> :left_right_count
        command.count -> :count
        true -> :list
      end

    Process.put(@mode_key, mode)
    command
  end

  defp parse_by_mode(stdout, :left_right_count) do
    case String.trim(stdout) |> String.split("\t") do
      [left, right] ->
        %{left: String.to_integer(left), right: String.to_integer(right)}

      _ ->
        %{left: 0, right: 0}
    end
  end

  defp parse_by_mode(stdout, :count) do
    case String.trim(stdout) do
      "" -> 0
      n -> String.to_integer(n)
    end
  end

  defp parse_by_mode(stdout, :list) do
    stdout
    |> String.split("\n", trim: true)
    |> Enum.map(&String.trim/1)
  end

  defp maybe_add(args, _flag, nil), do: args
  defp maybe_add(args, flag, value), do: args ++ ["#{flag}#{value}"]

  defp maybe_add_flag(args, true, flag), do: args ++ [flag]
  defp maybe_add_flag(args, false, _flag), do: args

  defp maybe_add_ref(args, nil), do: args
  defp maybe_add_ref(args, ref), do: args ++ [ref]
end
