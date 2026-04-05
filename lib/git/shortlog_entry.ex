defmodule Git.ShortlogEntry do
  @moduledoc """
  Parsed representation of a git shortlog entry.

  Contains the author name, optional email, commit count, and list of
  commit subjects (empty when `summary: true` is used).
  """

  @type t :: %__MODULE__{
          author: String.t(),
          email: String.t() | nil,
          count: non_neg_integer(),
          commits: [String.t()]
        }

  defstruct author: "",
            email: nil,
            count: 0,
            commits: []

  @doc """
  Parses the output of `git shortlog` into a list of `Git.ShortlogEntry` structs.

  Handles both summary mode (`-s`) and full mode output.

  Summary mode lines have the form:

      count\\tAuthor Name
      count\\tAuthor Name <email>

  Full mode output has the form:

      Author Name (count):
            commit subject 1
            commit subject 2

  ## Examples

      iex> Git.ShortlogEntry.parse_summary("     3\\tAlice\\n     1\\tBob\\n")
      [
        %Git.ShortlogEntry{author: "Alice", email: nil, count: 3, commits: []},
        %Git.ShortlogEntry{author: "Bob", email: nil, count: 1, commits: []}
      ]

      iex> Git.ShortlogEntry.parse_summary("")
      []

  """
  @spec parse_summary(String.t()) :: [t()]
  def parse_summary(output) do
    output
    |> String.split("\n", trim: true)
    |> Enum.map(&parse_summary_line/1)
  end

  @doc """
  Parses full (non-summary) shortlog output into entries with commit lists.
  """
  @spec parse_full(String.t()) :: [t()]
  def parse_full(output) do
    output
    |> String.split("\n")
    |> parse_full_lines([])
    |> Enum.reverse()
  end

  defp parse_summary_line(line) do
    trimmed = String.trim(line)

    case Regex.run(~r/^(\d+)\t(.+)$/, trimmed) do
      [_, count_str, rest] ->
        count = String.to_integer(count_str)
        {author, email} = parse_author_email(rest)
        %__MODULE__{author: author, email: email, count: count, commits: []}

      nil ->
        %__MODULE__{author: trimmed, count: 0, commits: []}
    end
  end

  defp parse_full_lines([], acc), do: acc

  defp parse_full_lines([line | rest], acc) do
    case Regex.run(~r/^(.+?)\s+\((\d+)\):$/, line) do
      [_, author_part, count_str] ->
        {author, email} = parse_author_email(author_part)
        count = String.to_integer(count_str)
        {commits, remaining} = collect_commits(rest, [])

        entry = %__MODULE__{
          author: author,
          email: email,
          count: count,
          commits: Enum.reverse(commits)
        }

        parse_full_lines(remaining, [entry | acc])

      nil ->
        # Skip blank or unparseable lines
        parse_full_lines(rest, acc)
    end
  end

  defp collect_commits([], acc), do: {acc, []}

  defp collect_commits([line | rest] = lines, acc) do
    trimmed = String.trim(line)

    if trimmed == "" or not String.starts_with?(line, "      ") do
      {acc, lines}
    else
      collect_commits(rest, [trimmed | acc])
    end
  end

  defp parse_author_email(str) do
    case Regex.run(~r/^(.+?)\s+<([^>]+)>$/, str) do
      [_, author, email] -> {author, email}
      nil -> {str, nil}
    end
  end
end
