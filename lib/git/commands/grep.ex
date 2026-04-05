defmodule Git.Commands.Grep do
  @moduledoc """
  Implements the `Git.Command` behaviour for `git grep`.

  Searches tracked files in a git repository for lines matching a pattern.
  Supports various matching modes, output formats, and context options.
  """

  @behaviour Git.Command

  alias Git.GrepResult

  @type t :: %__MODULE__{
          pattern: String.t(),
          paths: [String.t()],
          line_number: boolean(),
          count: boolean(),
          files_with_matches: boolean(),
          files_without_match: boolean(),
          ignore_case: boolean(),
          word_regexp: boolean(),
          extended_regexp: boolean(),
          fixed_strings: boolean(),
          perl_regexp: boolean(),
          invert_match: boolean(),
          max_count: non_neg_integer() | nil,
          context: non_neg_integer() | nil,
          before_context: non_neg_integer() | nil,
          after_context: non_neg_integer() | nil,
          show_function: boolean(),
          heading: boolean(),
          break: boolean(),
          untracked: boolean(),
          no_index: boolean(),
          recurse_submodules: boolean(),
          quiet: boolean(),
          all_match: boolean(),
          ref: String.t() | nil
        }

  defstruct pattern: "",
            paths: [],
            line_number: true,
            count: false,
            files_with_matches: false,
            files_without_match: false,
            ignore_case: false,
            word_regexp: false,
            extended_regexp: false,
            fixed_strings: false,
            perl_regexp: false,
            invert_match: false,
            max_count: nil,
            context: nil,
            before_context: nil,
            after_context: nil,
            show_function: false,
            heading: false,
            break: false,
            untracked: false,
            no_index: false,
            recurse_submodules: false,
            quiet: false,
            all_match: false,
            ref: nil

  # Track which output mode is active so parse_output knows how to parse.
  @mode_key [:files_with_matches, :files_without_match, :count]

  @doc """
  Returns the argument list for `git grep`.

  ## Examples

      iex> Git.Commands.Grep.args(%Git.Commands.Grep{pattern: "hello"})
      ["grep", "-n", "hello"]

      iex> Git.Commands.Grep.args(%Git.Commands.Grep{pattern: "hello", ignore_case: true})
      ["grep", "-n", "-i", "hello"]

      iex> Git.Commands.Grep.args(%Git.Commands.Grep{pattern: "hello", files_with_matches: true})
      ["grep", "-l", "hello"]

      iex> Git.Commands.Grep.args(%Git.Commands.Grep{pattern: "hello", count: true})
      ["grep", "-c", "hello"]

      iex> Git.Commands.Grep.args(%Git.Commands.Grep{pattern: "hello", ref: "HEAD"})
      ["grep", "-n", "hello", "HEAD"]

      iex> Git.Commands.Grep.args(%Git.Commands.Grep{pattern: "hello", paths: ["lib/"]})
      ["grep", "-n", "hello", "--", "lib/"]

  """
  @spec args(t()) :: [String.t()]
  @impl true
  def args(%__MODULE__{} = command) do
    base = ["grep"]

    base
    |> maybe_add_line_number(command)
    |> maybe_add_flag(command.count, "-c")
    |> maybe_add_flag(command.files_with_matches, "-l")
    |> maybe_add_flag(command.files_without_match, "-L")
    |> maybe_add_flag(command.ignore_case, "-i")
    |> maybe_add_flag(command.word_regexp, "-w")
    |> maybe_add_flag(command.extended_regexp, "-E")
    |> maybe_add_flag(command.fixed_strings, "-F")
    |> maybe_add_flag(command.perl_regexp, "-P")
    |> maybe_add_flag(command.invert_match, "--invert-match")
    |> maybe_add_flag(command.show_function, "-p")
    |> maybe_add_flag(command.heading, "--heading")
    |> maybe_add_flag(command.break, "--break")
    |> maybe_add_flag(command.untracked, "--untracked")
    |> maybe_add_flag(command.no_index, "--no-index")
    |> maybe_add_flag(command.recurse_submodules, "--recurse-submodules")
    |> maybe_add_flag(command.quiet, "-q")
    |> maybe_add_flag(command.all_match, "--all-match")
    |> maybe_add_option("-m", command.max_count)
    |> maybe_add_option("-C", command.context)
    |> maybe_add_option("-B", command.before_context)
    |> maybe_add_option("-A", command.after_context)
    |> append_pattern(command.pattern)
    |> maybe_add_ref(command.ref)
    |> maybe_add_paths(command.paths)
  end

  @doc """
  Parses the output of `git grep`.

  On success (exit code 0), parses results based on the command mode.
  Exit code 1 means no matches were found and returns `{:ok, []}`.
  Other exit codes return `{:error, {stdout, exit_code}}`.
  """
  @spec parse_output(String.t(), non_neg_integer()) ::
          {:ok, [GrepResult.t()] | [String.t()]} | {:error, {String.t(), non_neg_integer()}}
  @impl true
  def parse_output(_stdout, 1), do: {:ok, []}

  def parse_output(stdout, 0) do
    {:ok, parse_default(stdout)}
  end

  def parse_output(stdout, exit_code), do: {:error, {stdout, exit_code}}

  @doc false
  def output_mode(%__MODULE__{} = command) do
    Enum.find(@mode_key, :default, fn key -> Map.get(command, key) end)
  end

  # Only add -n when not in a special mode (files_with_matches, files_without_match, count)
  defp maybe_add_line_number(args, command) do
    in_special_mode =
      command.count or command.files_with_matches or command.files_without_match

    if command.line_number and not in_special_mode do
      args ++ ["-n"]
    else
      args
    end
  end

  defp maybe_add_flag(args, true, flag), do: args ++ [flag]
  defp maybe_add_flag(args, false, _flag), do: args

  defp maybe_add_option(args, _flag, nil), do: args
  defp maybe_add_option(args, flag, value), do: args ++ [flag, to_string(value)]

  defp append_pattern(args, pattern), do: args ++ [pattern]

  defp maybe_add_ref(args, nil), do: args
  defp maybe_add_ref(args, ref), do: args ++ [ref]

  defp maybe_add_paths(args, []), do: args
  defp maybe_add_paths(args, paths), do: args ++ ["--"] ++ paths

  defp parse_default(stdout) do
    stdout
    |> String.split("\n", trim: true)
    |> Enum.flat_map(&parse_line/1)
  end

  defp parse_line(line) do
    # Formats: "file:num:content" (with -n), "file:content" (without -n),
    # "file:count" (with -c), or just "file" (with -l/-L)
    # Context lines use "file-num-content" separator
    # We try to parse file:num:content first, then fall back
    case Regex.run(~r/^(.+?):(\d+):(.*)$/, line) do
      [_, file, num, content] ->
        [%GrepResult{file: file, line_number: String.to_integer(num), content: content}]

      nil ->
        parse_line_fallback(line)
    end
  end

  defp parse_line_fallback(line) do
    # Could be file:count, or filename only
    case Regex.run(~r/^(.+?):(\d+)$/, line) do
      [_, file, count_or_num] ->
        [%GrepResult{file: file, line_number: String.to_integer(count_or_num), content: ""}]

      nil when line == "--" or line == "" ->
        []

      nil ->
        [%GrepResult{file: String.trim(line), line_number: nil, content: ""}]
    end
  end
end
