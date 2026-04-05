defmodule Git.Commands.Blame do
  @moduledoc """
  Implements the `Git.Command` behaviour for `git blame`.

  Always uses `--porcelain` output format internally for reliable,
  machine-readable parsing. The output is parsed into a list of
  `Git.BlameEntry` structs.

  Supports line ranges, specific revisions, email display, date formatting,
  reverse blame, first-parent following, encoding, and root commit handling.
  """

  @behaviour Git.Command

  alias Git.BlameEntry

  @type t :: %__MODULE__{
          file: String.t(),
          lines: String.t() | nil,
          rev: String.t() | nil,
          show_email: boolean(),
          show_name: boolean(),
          date: String.t() | nil,
          reverse: boolean(),
          first_parent: boolean(),
          encoding: String.t() | nil,
          root: boolean()
        }

  defstruct file: "",
            lines: nil,
            rev: nil,
            show_email: false,
            show_name: false,
            date: nil,
            reverse: false,
            first_parent: false,
            encoding: nil,
            root: false

  @doc """
  Returns the argument list for `git blame`.

  Always includes `--porcelain` for reliable parsing regardless of the
  `:porcelain` struct field. The `:file` field is required and appended
  at the end of the argument list.

  ## Examples

      iex> Git.Commands.Blame.args(%Git.Commands.Blame{file: "lib/app.ex"})
      ["blame", "--porcelain", "lib/app.ex"]

      iex> Git.Commands.Blame.args(%Git.Commands.Blame{file: "lib/app.ex", lines: "1,5"})
      ["blame", "--porcelain", "-L", "1,5", "lib/app.ex"]

      iex> Git.Commands.Blame.args(%Git.Commands.Blame{file: "lib/app.ex", rev: "HEAD~1"})
      ["blame", "--porcelain", "HEAD~1", "--", "lib/app.ex"]

      iex> Git.Commands.Blame.args(%Git.Commands.Blame{file: "lib/app.ex", show_email: true})
      ["blame", "--porcelain", "-e", "lib/app.ex"]

  """
  @spec args(t()) :: [String.t()]
  @impl true
  def args(%__MODULE__{} = command) do
    base = ["blame", "--porcelain"]

    base
    |> maybe_add_lines(command.lines)
    |> maybe_add_flag(command.show_email, "-e")
    |> maybe_add_flag(command.show_name, "--show-name")
    |> maybe_add_flag(command.reverse, "--reverse")
    |> maybe_add_flag(command.first_parent, "--first-parent")
    |> maybe_add_flag(command.root, "--root")
    |> maybe_add_option(command.date, "--date=")
    |> maybe_add_option(command.encoding, "--encoding=")
    |> maybe_add_rev_and_file(command.rev, command.file)
  end

  @doc """
  Parses the output of `git blame --porcelain`.

  On success (exit code 0), parses the porcelain output into a list of
  `Git.BlameEntry` structs. Each entry contains the commit SHA,
  author information, line numbers, and the actual line content.

  Returns `{:ok, [BlameEntry.t()]}` on success or
  `{:error, {stdout, exit_code}}` on failure.
  """
  @spec parse_output(String.t(), non_neg_integer()) ::
          {:ok, [BlameEntry.t()]} | {:error, {String.t(), non_neg_integer()}}
  @impl true
  def parse_output(stdout, 0) do
    entries = parse_porcelain(stdout)
    {:ok, entries}
  end

  def parse_output(stdout, exit_code), do: {:error, {stdout, exit_code}}

  defp parse_porcelain(stdout) do
    stdout
    |> String.split("\n")
    |> parse_blocks([], %{})
    |> Enum.reverse()
  end

  # commit_cache maps commit SHA -> %{author_name, author_email, author_time}
  # so that repeated references to the same commit (which omit author info
  # in porcelain format) can still populate the entry fields.
  defp parse_blocks([], acc, _commit_cache), do: acc

  defp parse_blocks([line | rest], acc, commit_cache) do
    case parse_header_line(line) do
      {:ok, commit, orig_line, final_line} ->
        {entry_fields, remaining} = consume_entry_fields(rest, %{})

        # Merge cached commit info for fields not present in this block
        cached = Map.get(commit_cache, commit, %{})
        merged = Map.merge(cached, entry_fields)

        entry = %BlameEntry{
          commit: commit,
          author_name: Map.get(merged, :author_name, ""),
          author_email: Map.get(merged, :author_email, ""),
          author_time: Map.get(merged, :author_time, ""),
          line_number: final_line,
          original_line_number: orig_line,
          content: Map.get(merged, :content, "")
        }

        # Update cache with any new info from this block
        new_cache = Map.put(commit_cache, commit, Map.drop(merged, [:content]))

        parse_blocks(remaining, [entry | acc], new_cache)

      :skip ->
        parse_blocks(rest, acc, commit_cache)
    end
  end

  defp parse_header_line(line) do
    parts = String.split(line, " ")

    case parts do
      [sha, orig, final | _] when byte_size(sha) >= 40 ->
        with {orig_num, ""} <- Integer.parse(orig),
             {final_num, ""} <- Integer.parse(final) do
          {:ok, sha, orig_num, final_num}
        else
          _ -> :skip
        end

      _ ->
        :skip
    end
  end

  defp consume_entry_fields([], fields), do: {fields, []}

  defp consume_entry_fields([line | rest], fields) do
    cond do
      String.starts_with?(line, "\t") ->
        content = String.slice(line, 1..-1//1)
        {Map.put(fields, :content, content), rest}

      String.starts_with?(line, "author ") ->
        consume_entry_fields(
          rest,
          Map.put(fields, :author_name, String.trim_leading(line, "author "))
        )

      String.starts_with?(line, "author-mail ") ->
        consume_entry_fields(
          rest,
          Map.put(fields, :author_email, String.trim_leading(line, "author-mail "))
        )

      String.starts_with?(line, "author-time ") ->
        consume_entry_fields(
          rest,
          Map.put(fields, :author_time, String.trim_leading(line, "author-time "))
        )

      true ->
        consume_entry_fields(rest, fields)
    end
  end

  defp maybe_add_flag(args, true, flag), do: args ++ [flag]
  defp maybe_add_flag(args, false, _flag), do: args

  defp maybe_add_lines(args, nil), do: args
  defp maybe_add_lines(args, lines), do: args ++ ["-L", lines]

  defp maybe_add_option(args, nil, _prefix), do: args
  defp maybe_add_option(args, value, prefix), do: args ++ ["#{prefix}#{value}"]

  defp maybe_add_rev_and_file(args, nil, file), do: args ++ [file]
  defp maybe_add_rev_and_file(args, rev, file), do: args ++ [rev, "--", file]
end
