defmodule Git.Commands.Show do
  @moduledoc """
  Implements the `Git.Command` behaviour for `git show`.

  When no custom `:format` or `:oneline` option is provided, uses ASCII
  control-character delimiters (the same technique as `Git.Commands.Log`)
  to reliably parse the commit header into a `Git.Commit` struct, with
  the remaining output captured as diff and stat text.

  When a custom format is provided or `--oneline` is used, the raw output is
  returned without structured commit parsing.
  """

  @behaviour Git.Command

  alias Git.{Commit, ShowResult}

  # ASCII record separator and unit separator for reliable parsing.
  @record_sep "\x1e"
  @unit_sep "\x1f"

  @type t :: %__MODULE__{
          ref: String.t(),
          format: String.t() | nil,
          stat: boolean(),
          name_only: boolean(),
          name_status: boolean(),
          no_patch: boolean(),
          abbrev_commit: boolean(),
          oneline: boolean(),
          diff_filter: String.t() | nil,
          quiet: boolean()
        }

  defstruct ref: "HEAD",
            format: nil,
            stat: false,
            name_only: false,
            name_status: false,
            no_patch: false,
            abbrev_commit: false,
            oneline: false,
            diff_filter: nil,
            quiet: false

  # Process dictionary key used to communicate the format mode from args/1
  # to parse_output/2 so we know whether to parse the commit header.
  @mode_key :__git_show_mode__

  @doc """
  Builds the argument list for `git show`.

  When no custom format or oneline flag is set, injects a control-character
  format string to enable structured parsing of the commit header.

  ## Examples

      iex> Git.Commands.Show.args(%Git.Commands.Show{})
      ["show", "--format=\\x1e%H\\x1f%h\\x1f%an\\x1f%ae\\x1f%aI\\x1f%s\\x1f%b\\x1e", "HEAD"]

      iex> Git.Commands.Show.args(%Git.Commands.Show{ref: "abc123", stat: true})
      ["show", "--format=\\x1e%H\\x1f%h\\x1f%an\\x1f%ae\\x1f%aI\\x1f%s\\x1f%b\\x1e", "--stat", "abc123"]

      iex> Git.Commands.Show.args(%Git.Commands.Show{oneline: true})
      ["show", "--oneline", "HEAD"]

      iex> Git.Commands.Show.args(%Git.Commands.Show{format: "%H %s"})
      ["show", "--format=%H %s", "HEAD"]

  """
  @spec args(t()) :: [String.t()]
  @impl true
  def args(%__MODULE__{} = command) do
    custom_format = command.format != nil or command.oneline

    if custom_format do
      Process.put(@mode_key, :raw)
    else
      Process.put(@mode_key, :structured)
    end

    base =
      if custom_format do
        ["show"]
        |> maybe_add_option(command.format, "--format")
        |> maybe_add(command.oneline, "--oneline")
      else
        format_str =
          "#{@record_sep}%H#{@unit_sep}%h#{@unit_sep}%an#{@unit_sep}%ae#{@unit_sep}%aI#{@unit_sep}%s#{@unit_sep}%b#{@record_sep}"

        ["show", "--format=#{format_str}"]
      end

    base
    |> maybe_add(command.stat, "--stat")
    |> maybe_add(command.name_only, "--name-only")
    |> maybe_add(command.name_status, "--name-status")
    |> maybe_add(command.no_patch, "--no-patch")
    |> maybe_add(command.abbrev_commit, "--abbrev-commit")
    |> maybe_add_option(command.diff_filter, "--diff-filter")
    |> maybe_add(command.quiet, "--quiet")
    |> Kernel.++([command.ref])
  end

  @doc """
  Parses the output of `git show`.

  When structured mode is active (no custom format), parses the commit header
  using control-character delimiters and captures the remaining output as
  diff/stat text. In raw mode, wraps the full output in the result struct.

  On failure, returns `{:error, {stdout, exit_code}}`.
  """
  @spec parse_output(String.t(), non_neg_integer()) ::
          {:ok, ShowResult.t()} | {:error, {String.t(), non_neg_integer()}}
  @impl true
  def parse_output(stdout, 0) do
    case Process.get(@mode_key, :structured) do
      :raw ->
        {:ok, %ShowResult{raw: stdout}}

      :structured ->
        {:ok, parse_structured(stdout)}
    end
  end

  def parse_output(stdout, exit_code), do: {:error, {stdout, exit_code}}

  defp parse_structured(stdout) do
    # The format wraps the commit header between two record separators.
    # Everything after the second record separator is the diff/stat output.
    case String.split(stdout, @record_sep, trim: true) do
      [header | rest] ->
        commit = parse_commit_header(header)
        remaining = Enum.join(rest, @record_sep) |> String.trim_leading()

        stat_text =
          if String.contains?(remaining, "file changed") or
               String.contains?(remaining, "files changed") do
            remaining
          else
            nil
          end

        %ShowResult{
          commit: commit,
          diff: remaining,
          stat: stat_text,
          raw: stdout
        }

      [] ->
        %ShowResult{raw: stdout}
    end
  end

  defp parse_commit_header(header) do
    header = String.trim(header)

    case String.split(header, @unit_sep, parts: 7) do
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
        nil
    end
  end

  defp maybe_add(args, true, flag), do: args ++ [flag]
  defp maybe_add(args, false, _flag), do: args

  defp maybe_add_option(args, nil, _flag), do: args
  defp maybe_add_option(args, value, flag), do: args ++ ["#{flag}=#{value}"]
end
