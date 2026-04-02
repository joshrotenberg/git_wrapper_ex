defmodule GitWrapper.Diff do
  @moduledoc """
  Parsed representation of `git diff` output.

  When used with `--stat`, contains a list of per-file stats. The `raw` field
  always holds the full stdout from git, regardless of whether `--stat` was used.
  """

  alias GitWrapper.DiffFile

  @type t :: %__MODULE__{
          files: [DiffFile.t()],
          total_insertions: non_neg_integer(),
          total_deletions: non_neg_integer(),
          raw: String.t()
        }

  defstruct files: [], total_insertions: 0, total_deletions: 0, raw: ""

  @doc """
  Parses the output of `git diff --stat` into a `GitWrapper.Diff` struct.

  The stat format looks like:

      lib/foo.ex | 10 ++++------
      lib/bar.ex |  5 +++++
      2 files changed, 7 insertions(+), 5 deletions(-)

  Binary files appear as:

      image.png | Bin 0 -> 1234 bytes

  The summary line is used for `total_insertions` and `total_deletions`.
  If the output is a full patch (no `--stat`), the `files` list will be empty
  and `raw` will contain the patch text.

  ## Examples

      iex> output = " foo.ex | 2 +-\\n 1 file changed, 1 insertion(+), 1 deletion(-)\\n"
      iex> diff = GitWrapper.Diff.parse(output)
      iex> diff.total_insertions
      1

  """
  @spec parse(String.t()) :: t()
  def parse(""), do: %__MODULE__{}

  def parse(output) do
    lines = String.split(output, "\n", trim: true)

    # Stat output has lines with " | " — detect by presence
    if Enum.any?(lines, &String.contains?(&1, " | ")) do
      parse_stat(lines, output)
    else
      # Full patch output: no file-level parsing, store raw
      %__MODULE__{raw: output}
    end
  end

  @spec parse_stat([String.t()], String.t()) :: t()
  defp parse_stat(lines, raw) do
    file_lines = Enum.filter(lines, &String.contains?(&1, " | "))
    summary_line = Enum.find(lines, &String.contains?(&1, "changed"))

    files = Enum.map(file_lines, &parse_file_line/1)

    {total_ins, total_del} =
      case summary_line do
        nil -> {0, 0}
        line -> parse_summary(line)
      end

    %__MODULE__{
      files: files,
      total_insertions: total_ins,
      total_deletions: total_del,
      raw: raw
    }
  end

  @spec parse_file_line(String.t()) :: DiffFile.t()
  defp parse_file_line(line) do
    [path_part, stat_part] = String.split(line, " | ", parts: 2)
    path = String.trim(path_part)

    if String.contains?(stat_part, "Bin") do
      %DiffFile{path: path, binary: true}
    else
      # stat_part looks like "10 ++++------" or " 5 +++++"
      {ins, del} = count_hunk_chars(stat_part)
      %DiffFile{path: path, insertions: ins, deletions: del}
    end
  end

  # Counts `+` and `-` chars in the hunk graphic portion of a stat line.
  @spec count_hunk_chars(String.t()) :: {non_neg_integer(), non_neg_integer()}
  defp count_hunk_chars(stat) do
    # Drop the number prefix, keep only the graphic chars
    graphic =
      stat
      |> String.trim()
      |> String.replace(~r/^\d+\s*/, "")

    ins = graphic |> String.graphemes() |> Enum.count(&(&1 == "+"))
    del = graphic |> String.graphemes() |> Enum.count(&(&1 == "-"))
    {ins, del}
  end

  @spec parse_summary(String.t()) :: {non_neg_integer(), non_neg_integer()}
  defp parse_summary(line) do
    ins =
      case Regex.run(~r/(\d+) insertions?\(\+\)/, line) do
        [_, n] -> String.to_integer(n)
        nil -> 0
      end

    del =
      case Regex.run(~r/(\d+) deletions?\(-\)/, line) do
        [_, n] -> String.to_integer(n)
        nil -> 0
      end

    {ins, del}
  end
end
