defmodule Git.Commands.Reflog do
  @moduledoc """
  Implements the `Git.Command` behaviour for `git reflog`.

  Uses ASCII control characters as delimiters in `--format` for reliable
  parsing of reflog entries into `Git.ReflogEntry` structs.
  """

  @behaviour Git.Command

  alias Git.ReflogEntry

  # ASCII record separator and unit separator for reliable parsing.
  @record_sep "\x1e"
  @unit_sep "\x1f"

  @type t :: %__MODULE__{
          ref: String.t() | nil,
          max_count: non_neg_integer() | nil,
          all: boolean(),
          date: String.t() | nil
        }

  defstruct ref: nil,
            max_count: nil,
            all: false,
            date: nil

  @doc """
  Returns the argument list for `git reflog`.

  Uses `--format` with ASCII control characters for reliable structured
  parsing. The format string produces records separated by RS (\\x1e)
  with fields separated by US (\\x1f).

  ## Examples

      iex> args = Git.Commands.Reflog.args(%Git.Commands.Reflog{})
      iex> hd(args)
      "reflog"

      iex> args = Git.Commands.Reflog.args(%Git.Commands.Reflog{max_count: 5})
      iex> Enum.member?(args, "-n5")
      true

  """
  @spec args(t()) :: [String.t()]
  @impl true
  def args(%__MODULE__{} = command) do
    format_str = "#{@record_sep}%H#{@unit_sep}%h#{@unit_sep}%gD#{@unit_sep}%gs"

    base = ["reflog", "--format=#{format_str}"]

    base
    |> maybe_add_max_count(command.max_count)
    |> maybe_add_flag(command.all, "--all")
    |> maybe_add_option("--date", command.date)
    |> maybe_add_ref(command.ref)
  end

  @doc """
  Parses the output of `git reflog`.

  Returns `{:ok, [%Git.ReflogEntry{}]}` on success or
  `{:error, {stdout, exit_code}}` on failure.
  """
  @spec parse_output(String.t(), non_neg_integer()) ::
          {:ok, [ReflogEntry.t()]} | {:error, {String.t(), non_neg_integer()}}
  @impl true
  def parse_output(stdout, 0) do
    if String.trim(stdout) == "" do
      {:ok, []}
    else
      entries =
        stdout
        |> String.split(@record_sep, trim: true)
        |> Enum.map(&parse_record/1)

      {:ok, entries}
    end
  end

  def parse_output(stdout, exit_code), do: {:error, {stdout, exit_code}}

  defp parse_record(record) do
    record = String.trim(record)

    case String.split(record, @unit_sep, parts: 4) do
      [hash, abbrev, selector, subject] ->
        {action, message} = parse_subject(subject)

        %ReflogEntry{
          hash: String.trim(hash),
          abbreviated_hash: String.trim(abbrev),
          selector: String.trim(selector),
          action: action,
          message: message
        }

      _ ->
        %ReflogEntry{
          hash: "",
          abbreviated_hash: "",
          selector: "",
          action: "",
          message: String.trim(record)
        }
    end
  end

  # Parses the reflog subject into action and message.
  # The subject format is typically "action: message", e.g.:
  #   "commit: add hello file"
  #   "checkout: moving from main to feature"
  #   "commit (initial): initial commit"
  defp parse_subject(subject) do
    subject = String.trim(subject)

    case String.split(subject, ": ", parts: 2) do
      [action, message] -> {action, message}
      [single] -> {single, ""}
    end
  end

  defp maybe_add_max_count(args, nil), do: args
  defp maybe_add_max_count(args, n) when is_integer(n), do: args ++ ["-n#{n}"]

  defp maybe_add_flag(args, false, _flag), do: args
  defp maybe_add_flag(args, true, flag), do: args ++ [flag]

  defp maybe_add_option(args, _flag, nil), do: args
  defp maybe_add_option(args, flag, value), do: args ++ ["#{flag}=#{value}"]

  defp maybe_add_ref(args, nil), do: args
  defp maybe_add_ref(args, ref), do: args ++ [ref]
end
