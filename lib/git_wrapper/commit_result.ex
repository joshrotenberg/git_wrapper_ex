defmodule GitWrapper.CommitResult do
  @moduledoc """
  Represents the parsed result of a `git commit` command.

  Contains the branch name, short commit hash, commit subject, and change
  statistics (files changed, insertions, deletions).
  """

  @type t :: %__MODULE__{
          branch: String.t(),
          hash: String.t(),
          subject: String.t(),
          files_changed: non_neg_integer(),
          insertions: non_neg_integer(),
          deletions: non_neg_integer()
        }

  defstruct branch: "",
            hash: "",
            subject: "",
            files_changed: 0,
            insertions: 0,
            deletions: 0

  @doc """
  Parses the output of `git commit` into a `GitWrapper.CommitResult` struct.

  The expected format is:

      [branch hash] subject
       N file(s) changed, N insertion(s)(+), N deletion(s)(-)

  Also handles root commits:

      [branch (root-commit) hash] subject

  ## Examples

      iex> output = "[main abc1234] the commit message\\n 1 file changed, 5 insertions(+), 2 deletions(-)\\n"
      iex> result = GitWrapper.CommitResult.parse(output)
      iex> result.branch
      "main"
      iex> result.hash
      "abc1234"
      iex> result.subject
      "the commit message"

  """
  @spec parse(String.t()) :: t()
  def parse(output) do
    lines = String.split(output, "\n", trim: true)

    {branch, hash, subject} = parse_header(List.first(lines) || "")
    {files_changed, insertions, deletions} = parse_stats(lines)

    %__MODULE__{
      branch: branch,
      hash: hash,
      subject: subject,
      files_changed: files_changed,
      insertions: insertions,
      deletions: deletions
    }
  end

  defp parse_header(line) do
    # Matches: [branch hash] subject  or  [branch (root-commit) hash] subject
    case Regex.run(~r/^\[(\S+)\s+(?:\(root-commit\)\s+)?(\w+)\]\s+(.+)$/, line) do
      [_, branch, hash, subject] -> {branch, hash, subject}
      _ -> {"", "", ""}
    end
  end

  defp parse_stats(lines) do
    stats_line =
      Enum.find(lines, fn line ->
        String.contains?(line, "changed")
      end)

    case stats_line do
      nil ->
        {0, 0, 0}

      line ->
        files_changed = extract_number(line, ~r/(\d+)\s+files?\s+changed/)
        insertions = extract_number(line, ~r/(\d+)\s+insertions?\(\+\)/)
        deletions = extract_number(line, ~r/(\d+)\s+deletions?\(-\)/)
        {files_changed, insertions, deletions}
    end
  end

  defp extract_number(line, regex) do
    case Regex.run(regex, line) do
      [_, num] -> String.to_integer(num)
      _ -> 0
    end
  end
end
