defmodule Git.Commands.Log do
  @moduledoc """
  Implements the `Git.Command` behaviour for `git log`.

  Builds arguments for the git log subcommand and parses the output
  into a list of `Git.Commit` structs.
  """

  @behaviour Git.Command

  alias Git.Commit

  # ASCII record separator and unit separator for reliable parsing.
  @record_sep "\x1e"
  @unit_sep "\x1f"

  @type t :: %__MODULE__{
          max_count: non_neg_integer() | nil,
          author: String.t() | nil,
          committer: String.t() | nil,
          since: String.t() | nil,
          until_date: String.t() | nil,
          skip: non_neg_integer() | nil,
          path: String.t() | nil,
          range: String.t() | nil,
          grep: String.t() | nil,
          all_match: boolean(),
          pickaxe: String.t() | nil,
          pickaxe_regex: String.t() | nil,
          follow: boolean(),
          no_merges: boolean(),
          merges: boolean(),
          first_parent: boolean(),
          reverse: boolean(),
          regexp_ignore_case: boolean(),
          extended_regexp: boolean(),
          fixed_strings: boolean(),
          perl_regexp: boolean(),
          invert_grep: boolean(),
          all: boolean(),
          branches: boolean(),
          tags: boolean()
        }

  defstruct [
    :max_count,
    :author,
    :committer,
    :since,
    :until_date,
    :skip,
    :path,
    :range,
    :grep,
    :pickaxe,
    :pickaxe_regex,
    all_match: false,
    follow: false,
    no_merges: false,
    merges: false,
    first_parent: false,
    reverse: false,
    regexp_ignore_case: false,
    extended_regexp: false,
    fixed_strings: false,
    perl_regexp: false,
    invert_grep: false,
    all: false,
    branches: false,
    tags: false
  ]

  @doc """
  Builds the argument list for `git log`.

  Uses ASCII control characters as delimiters to reliably parse output
  even when commit messages contain newlines or special characters.

  In addition to `:max_count`, `:author`, `:since`, `:until_date`, `:grep`,
  `:pickaxe`/`:pickaxe_regex`, `:range`, and `:path`, supports history controls
  that do not change the per-commit output format: `:committer`, `:skip`,
  `:reverse`, `:follow`, `:no_merges`/`:merges`, `:first_parent`, the grep
  modifiers `:regexp_ignore_case` (-i), `:extended_regexp` (-E),
  `:fixed_strings` (-F), `:perl_regexp`, `:invert_grep`, and the ref selectors
  `:all`, `:branches`, and `:tags`.
  """
  @spec args(t()) :: [String.t()]
  @impl true
  def args(%__MODULE__{} = command) do
    format_str =
      "#{@record_sep}%H#{@unit_sep}%h#{@unit_sep}%an#{@unit_sep}%ae#{@unit_sep}%aI#{@unit_sep}%s#{@unit_sep}%b"

    base = ["log", "--format=#{format_str}"]

    base
    |> maybe_add("--max-count=", command.max_count)
    |> maybe_add("--skip=", command.skip)
    |> maybe_add("--author=", command.author)
    |> maybe_add("--committer=", command.committer)
    |> maybe_add("--since=", command.since)
    |> maybe_add("--until=", command.until_date)
    |> maybe_add("--grep=", command.grep)
    |> maybe_add_flag(command.all_match, "--all-match")
    |> maybe_add_flag(command.regexp_ignore_case, "-i")
    |> maybe_add_flag(command.extended_regexp, "-E")
    |> maybe_add_flag(command.fixed_strings, "-F")
    |> maybe_add_flag(command.perl_regexp, "--perl-regexp")
    |> maybe_add_flag(command.invert_grep, "--invert-grep")
    |> maybe_add_pickaxe(command.pickaxe, command.pickaxe_regex)
    |> maybe_add_flag(command.follow, "--follow")
    |> maybe_add_flag(command.no_merges, "--no-merges")
    |> maybe_add_flag(command.merges, "--merges")
    |> maybe_add_flag(command.first_parent, "--first-parent")
    |> maybe_add_flag(command.reverse, "--reverse")
    |> maybe_add_flag(command.all, "--all")
    |> maybe_add_flag(command.branches, "--branches")
    |> maybe_add_flag(command.tags, "--tags")
    |> maybe_add_range(command.range)
    |> maybe_add_path(command.path)
  end

  @doc """
  Parses the stdout and exit code from `git log` into a result.

  Returns `{:ok, [%Git.Commit{}]}` on success or
  `{:error, {stdout, exit_code}}` on failure.
  """
  @spec parse_output(String.t(), non_neg_integer()) ::
          {:ok, [Commit.t()]} | {:error, {String.t(), non_neg_integer()}}
  @impl true
  def parse_output(stdout, 0) do
    commits =
      stdout
      |> String.split(@record_sep, trim: true)
      |> Enum.map(&parse_record/1)

    {:ok, commits}
  end

  def parse_output(stdout, 128) do
    if String.contains?(stdout, "does not have any commits") do
      {:ok, []}
    else
      {:error, {stdout, 128}}
    end
  end

  def parse_output(stdout, exit_code) do
    {:error, {stdout, exit_code}}
  end

  defp parse_record(record) do
    record = String.trim(record)

    case String.split(record, @unit_sep, parts: 7) do
      [hash, abbrev, name, email, date, subject, body] ->
        %Commit{
          hash: String.trim(hash),
          abbreviated_hash: String.trim(abbrev),
          author_name: String.trim(name),
          author_email: String.trim(email),
          date: String.trim(date),
          subject: String.trim(subject),
          body: String.trim(body)
        }

      [hash, abbrev, name, email, date, subject] ->
        %Commit{
          hash: String.trim(hash),
          abbreviated_hash: String.trim(abbrev),
          author_name: String.trim(name),
          author_email: String.trim(email),
          date: String.trim(date),
          subject: String.trim(subject),
          body: ""
        }

      _ ->
        %Commit{
          hash: "",
          abbreviated_hash: "",
          author_name: "",
          author_email: "",
          date: "",
          subject: String.trim(record),
          body: ""
        }
    end
  end

  defp maybe_add(args, _flag, nil), do: args
  defp maybe_add(args, flag, value), do: args ++ ["#{flag}#{value}"]

  defp maybe_add_flag(args, true, flag), do: args ++ [flag]
  defp maybe_add_flag(args, false, _flag), do: args

  defp maybe_add_pickaxe(args, nil, nil), do: args
  defp maybe_add_pickaxe(args, _pickaxe, regex) when is_binary(regex), do: args ++ ["-G#{regex}"]

  defp maybe_add_pickaxe(args, pickaxe, _regex) when is_binary(pickaxe),
    do: args ++ ["-S#{pickaxe}"]

  defp maybe_add_range(args, nil), do: args
  defp maybe_add_range(args, range), do: args ++ [range]

  defp maybe_add_path(args, nil), do: args
  defp maybe_add_path(args, path), do: args ++ ["--", path]
end
