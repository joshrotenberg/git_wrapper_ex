defmodule GitWrapper.Commands.Log do
  @moduledoc """
  Implements the `GitWrapper.Command` behaviour for `git log`.

  Builds arguments for the git log subcommand and parses the output
  into a list of `GitWrapper.Commit` structs.
  """

  @behaviour GitWrapper.Command

  alias GitWrapper.Commit

  # ASCII record separator and unit separator for reliable parsing.
  @record_sep "\x1e"
  @unit_sep "\x1f"

  @type t :: %__MODULE__{
          max_count: non_neg_integer() | nil,
          author: String.t() | nil,
          since: String.t() | nil,
          until_date: String.t() | nil,
          path: String.t() | nil
        }

  defstruct [
    :max_count,
    :author,
    :since,
    :until_date,
    :path
  ]

  @doc """
  Builds the argument list for `git log`.

  Uses ASCII control characters as delimiters to reliably parse output
  even when commit messages contain newlines or special characters.
  """
  @spec args(t()) :: [String.t()]
  @impl true
  def args(%__MODULE__{} = command) do
    format_str = "#{@record_sep}%H#{@unit_sep}%h#{@unit_sep}%an#{@unit_sep}%ae#{@unit_sep}%aI#{@unit_sep}%s#{@unit_sep}%b"

    base = ["log", "--format=#{format_str}"]

    base
    |> maybe_add("--max-count=", command.max_count)
    |> maybe_add("--author=", command.author)
    |> maybe_add("--since=", command.since)
    |> maybe_add("--until=", command.until_date)
    |> maybe_add_path(command.path)
  end

  @doc """
  Parses the stdout and exit code from `git log` into a result.

  Returns `{:ok, [%GitWrapper.Commit{}]}` on success or
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

  defp maybe_add_path(args, nil), do: args
  defp maybe_add_path(args, path), do: args ++ ["--", path]
end
