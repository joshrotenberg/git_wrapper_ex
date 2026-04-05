defmodule Git.Commands.Shortlog do
  @moduledoc """
  Implements the `Git.Command` behaviour for `git shortlog`.

  Summarizes `git log` output grouped by author. Supports summary mode
  (count only), numbered sorting, email display, and ref ranges.
  """

  @behaviour Git.Command

  alias Git.ShortlogEntry

  @type t :: %__MODULE__{
          numbered: boolean(),
          summary: boolean(),
          email: boolean(),
          group: String.t() | nil,
          ref: String.t() | nil,
          max_count: non_neg_integer() | nil,
          since: String.t() | nil,
          until_date: String.t() | nil,
          all: boolean()
        }

  defstruct numbered: false,
            summary: false,
            email: false,
            group: nil,
            ref: nil,
            max_count: nil,
            since: nil,
            until_date: nil,
            all: false

  @doc """
  Returns the argument list for `git shortlog`.

  ## Examples

      iex> Git.Commands.Shortlog.args(%Git.Commands.Shortlog{})
      ["shortlog"]

      iex> Git.Commands.Shortlog.args(%Git.Commands.Shortlog{summary: true, numbered: true})
      ["shortlog", "-s", "-n"]

      iex> Git.Commands.Shortlog.args(%Git.Commands.Shortlog{email: true, ref: "v1.0..HEAD"})
      ["shortlog", "-e", "v1.0..HEAD"]

      iex> Git.Commands.Shortlog.args(%Git.Commands.Shortlog{max_count: 10, group: "author"})
      ["shortlog", "--max-count=10", "--group=author"]

  """
  @spec args(t()) :: [String.t()]
  @impl true
  def args(%__MODULE__{} = command) do
    ["shortlog"]
    |> maybe_add_flag(command.summary, "-s")
    |> maybe_add_flag(command.numbered, "-n")
    |> maybe_add_flag(command.email, "-e")
    |> maybe_add_flag(command.all, "--all")
    |> maybe_add_value("--max-count=", command.max_count)
    |> maybe_add_value("--since=", command.since)
    |> maybe_add_value("--until=", command.until_date)
    |> maybe_add_value("--group=", command.group)
    |> maybe_add_ref(command.ref)
  end

  @doc """
  Parses the output of `git shortlog`.

  When summary mode is detected (tab-separated count and author), uses
  `ShortlogEntry.parse_summary/1`. Otherwise uses `ShortlogEntry.parse_full/1`.

  Returns `{:ok, [%Git.ShortlogEntry{}]}` on success or
  `{:error, {stdout, exit_code}}` on failure.
  """
  @spec parse_output(String.t(), non_neg_integer()) ::
          {:ok, [ShortlogEntry.t()]} | {:error, {String.t(), non_neg_integer()}}
  @impl true
  def parse_output(stdout, 0) do
    trimmed = String.trim(stdout)

    if trimmed == "" do
      {:ok, []}
    else
      entries =
        if summary_format?(trimmed) do
          ShortlogEntry.parse_summary(stdout)
        else
          ShortlogEntry.parse_full(stdout)
        end

      {:ok, entries}
    end
  end

  def parse_output(stdout, exit_code), do: {:error, {stdout, exit_code}}

  # Summary format lines look like "   count\tAuthor Name"
  defp summary_format?(output) do
    first_line = output |> String.split("\n", parts: 2) |> hd()
    Regex.match?(~r/^\s*\d+\t/, first_line)
  end

  defp maybe_add_flag(args, true, flag), do: args ++ [flag]
  defp maybe_add_flag(args, false, _flag), do: args

  defp maybe_add_value(args, _prefix, nil), do: args
  defp maybe_add_value(args, prefix, value), do: args ++ ["#{prefix}#{value}"]

  defp maybe_add_ref(args, nil), do: args
  defp maybe_add_ref(args, ref), do: args ++ [ref]
end
