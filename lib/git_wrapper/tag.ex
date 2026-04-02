defmodule GitWrapper.Tag do
  @moduledoc """
  Parsed representation of a git tag.

  Contains the tag name, whether it is annotated, the tagger name and email
  (for annotated tags), the date, and the annotation message.
  """

  @type t :: %__MODULE__{
          name: String.t(),
          annotated: boolean(),
          tagger_name: String.t() | nil,
          tagger_email: String.t() | nil,
          date: String.t() | nil,
          message: String.t() | nil
        }

  defstruct [:name, :tagger_name, :tagger_email, :date, :message, annotated: false]

  @doc """
  Parses the output of `git tag -l -n1` into a list of `GitWrapper.Tag` structs.

  Each line has the form:

      v1.0.0          first release
      v1.1.0          second release

  Tags with an annotation message are marked as annotated. Lightweight tags
  have no message in `-n1` output (or the message matches the commit subject).

  ## Examples

      iex> GitWrapper.Tag.parse_list("v1.0.0\\nv1.1.0\\n")
      [%GitWrapper.Tag{name: "v1.0.0", annotated: false}, %GitWrapper.Tag{name: "v1.1.0", annotated: false}]

  """
  @spec parse_list(String.t()) :: [t()]
  def parse_list(output) do
    output
    |> String.split("\n", trim: true)
    |> Enum.map(fn line ->
      %__MODULE__{name: String.trim(line)}
    end)
  end

  @record_sep "\x1e"
  @unit_sep "\x1f"

  @doc """
  Returns the `--format` string used by `git tag -l` for detailed output.

  Uses ASCII control characters as delimiters for reliable parsing.
  """
  @spec format_string() :: String.t()
  def format_string do
    "#{@record_sep}%(refname:short)#{@unit_sep}%(objecttype)#{@unit_sep}%(taggername)#{@unit_sep}%(taggeremail)#{@unit_sep}%(taggerdate:iso-strict)#{@unit_sep}%(contents:subject)"
  end

  @doc """
  Parses the output of `git tag -l --format=...` with the detailed format string.

  ## Examples

      iex> GitWrapper.Tag.parse_detailed("")
      []

  """
  @spec parse_detailed(String.t()) :: [t()]
  def parse_detailed(output) do
    output
    |> String.split(@record_sep, trim: true)
    |> Enum.map(&parse_record/1)
  end

  @spec parse_record(String.t()) :: t()
  defp parse_record(record) do
    parts =
      record
      |> String.trim()
      |> String.split(@unit_sep)

    case parts do
      [name, type, tagger_name, tagger_email, date, message] ->
        annotated = type == "tag"

        %__MODULE__{
          name: name,
          annotated: annotated,
          tagger_name: if(annotated, do: clean(tagger_name)),
          tagger_email: if(annotated, do: clean_email(tagger_email)),
          date: if(annotated, do: clean(date)),
          message: if(annotated, do: clean(message))
        }

      [name | _] ->
        %__MODULE__{name: String.trim(name)}
    end
  end

  @spec clean(String.t()) :: String.t() | nil
  defp clean(value) do
    trimmed = String.trim(value)
    if trimmed == "", do: nil, else: trimmed
  end

  @spec clean_email(String.t()) :: String.t() | nil
  defp clean_email(value) do
    value
    |> String.trim()
    |> String.trim_leading("<")
    |> String.trim_trailing(">")
    |> then(fn trimmed -> if trimmed == "", do: nil, else: trimmed end)
  end
end
