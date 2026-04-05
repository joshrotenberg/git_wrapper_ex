defmodule Git.Status do
  @moduledoc """
  Parsed representation of `git status --porcelain=v1 -b` output.

  Contains branch tracking information and a list of file entries
  with their index and working tree status codes.
  """

  @type file_entry :: %{
          index: String.t(),
          working_tree: String.t(),
          path: String.t()
        }

  @type t :: %__MODULE__{
          branch: String.t() | nil,
          tracking: String.t() | nil,
          ahead: non_neg_integer(),
          behind: non_neg_integer(),
          entries: [file_entry()]
        }

  defstruct branch: nil, tracking: nil, ahead: 0, behind: 0, entries: []

  @doc """
  Parses porcelain v1 output (with `-b` flag) into a `Git.Status` struct.

  The first line is the branch header: `## branch...tracking [ahead N, behind N]`.
  Subsequent lines are file entries in `XY path` format, where X is the index
  status and Y is the working tree status.

  ## Examples

      iex> Git.Status.parse("## main\\n?? foo.txt\\n")
      %Git.Status{
        branch: "main",
        tracking: nil,
        ahead: 0,
        behind: 0,
        entries: [%{index: "?", working_tree: "?", path: "foo.txt"}]
      }

  """
  @spec parse(String.t()) :: t()
  def parse(output) do
    lines =
      output
      |> String.split("\n", trim: true)

    case lines do
      [] ->
        %__MODULE__{}

      [header | rest] ->
        {branch, tracking, ahead, behind} = parse_branch_header(header)
        entries = Enum.map(rest, &parse_entry/1)

        %__MODULE__{
          branch: branch,
          tracking: tracking,
          ahead: ahead,
          behind: behind,
          entries: entries
        }
    end
  end

  @spec parse_branch_header(String.t()) ::
          {String.t() | nil, String.t() | nil, non_neg_integer(), non_neg_integer()}
  defp parse_branch_header("## " <> rest) do
    # Strip optional tracking info in brackets: [ahead N, behind N]
    {rest_no_bracket, ahead, behind} = parse_ahead_behind(rest)

    case String.split(rest_no_bracket, "...", parts: 2) do
      [branch, tracking] ->
        {String.trim(branch), String.trim(tracking), ahead, behind}

      [branch] ->
        {String.trim(branch), nil, ahead, behind}
    end
  end

  defp parse_branch_header(_), do: {nil, nil, 0, 0}

  @spec parse_ahead_behind(String.t()) :: {String.t(), non_neg_integer(), non_neg_integer()}
  defp parse_ahead_behind(rest) do
    case Regex.run(~r/^(.*?)\s*\[([^\]]+)\]\s*$/, rest) do
      [_, prefix, bracket_content] ->
        ahead = parse_count(bracket_content, ~r/ahead\s+(\d+)/)
        behind = parse_count(bracket_content, ~r/behind\s+(\d+)/)
        {prefix, ahead, behind}

      nil ->
        {rest, 0, 0}
    end
  end

  @spec parse_count(String.t(), Regex.t()) :: non_neg_integer()
  defp parse_count(text, regex) do
    case Regex.run(regex, text) do
      [_, count] -> String.to_integer(count)
      nil -> 0
    end
  end

  @spec parse_entry(String.t()) :: file_entry()
  defp parse_entry(line) do
    case line do
      <<index::binary-size(1), working_tree::binary-size(1), " ", path::binary>> ->
        # Handle renames: "XY orig -> path"
        path =
          case String.split(path, " -> ", parts: 2) do
            [_orig, new_path] -> new_path
            [only_path] -> only_path
          end

        %{index: index, working_tree: working_tree, path: path}

      _ ->
        %{index: "?", working_tree: "?", path: line}
    end
  end
end
