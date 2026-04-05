defmodule Git.StashEntry do
  @moduledoc """
  Parsed representation of a git stash entry.

  Contains the stash index, the branch the stash was created on,
  and the stash message.
  """

  @type t :: %__MODULE__{
          index: non_neg_integer(),
          branch: String.t() | nil,
          message: String.t()
        }

  defstruct [:index, :branch, :message]

  @doc """
  Parses the output of `git stash list` into a list of `Git.StashEntry` structs.

  Each line has the form:

      stash@{0}: On main: my changes
      stash@{1}: WIP on main: abc1234 commit message

  ## Examples

      iex> Git.StashEntry.parse("stash@{0}: On main: my changes\\n")
      [%Git.StashEntry{index: 0, branch: "main", message: "my changes"}]

      iex> Git.StashEntry.parse("")
      []

  """
  @spec parse(String.t()) :: [t()]
  def parse(output) do
    output
    |> String.split("\n", trim: true)
    |> Enum.map(&parse_line/1)
  end

  @spec parse_line(String.t()) :: t()
  defp parse_line(line) do
    case Regex.run(~r/^stash@\{(\d+)\}:\s+(.*)$/, line) do
      [_, index_str, rest] ->
        index = String.to_integer(index_str)
        {branch, message} = parse_rest(rest)

        %__MODULE__{
          index: index,
          branch: branch,
          message: message
        }

      nil ->
        %__MODULE__{index: 0, branch: nil, message: String.trim(line)}
    end
  end

  # Parses the portion after "stash@{N}: " into branch and message.
  #
  # Formats:
  #   "On <branch>: <message>"
  #   "WIP on <branch>: <hash> <message>"
  @spec parse_rest(String.t()) :: {String.t() | nil, String.t()}
  defp parse_rest(rest) do
    cond do
      # "On <branch>: <message>" (explicit stash save/push with message)
      match = Regex.run(~r/^On\s+(.+?):\s+(.+)$/, rest) ->
        [_, branch, message] = match
        {branch, message}

      # "WIP on <branch>: <hash> <message>" (default stash without message)
      match = Regex.run(~r/^WIP on\s+(.+?):\s+(.+)$/, rest) ->
        [_, branch, message] = match
        {branch, message}

      true ->
        {nil, rest}
    end
  end
end
