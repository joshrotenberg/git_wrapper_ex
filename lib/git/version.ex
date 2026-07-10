defmodule Git.Version do
  @moduledoc """
  Parsed representation of the installed git version.

  Holds the numeric `major`, `minor`, and `patch` components along with the
  full `raw` version line as reported by `git --version`.
  """

  @type t :: %__MODULE__{
          major: non_neg_integer(),
          minor: non_neg_integer(),
          patch: non_neg_integer(),
          raw: String.t()
        }

  defstruct major: 0,
            minor: 0,
            patch: 0,
            raw: ""

  @doc """
  Parses the output of `git --version` into a `Git.Version` struct.

  The version number is the third whitespace-delimited field. Its first three
  dot-separated numeric components become `major`, `minor`, and `patch`; any
  missing component defaults to `0`. The full trimmed line is kept in `raw`.

  ## Examples

      iex> Git.Version.parse("git version 2.50.1 (Apple Git-155)\\n")
      %Git.Version{major: 2, minor: 50, patch: 1, raw: "git version 2.50.1 (Apple Git-155)"}

      iex> Git.Version.parse("git version 2.42.0.windows.2")
      %Git.Version{major: 2, minor: 42, patch: 0, raw: "git version 2.42.0.windows.2"}

  """
  @spec parse(String.t()) :: t()
  def parse(output) do
    raw = String.trim(output)

    {major, minor, patch} =
      raw
      |> version_field()
      |> split_components()

    %__MODULE__{major: major, minor: minor, patch: patch, raw: raw}
  end

  defp version_field(raw) do
    case String.split(raw, ~r/\s+/, trim: true) do
      [_git, _version, field | _rest] -> field
      _ -> ""
    end
  end

  defp split_components(field) do
    parts = String.split(field, ".")

    {
      component(Enum.at(parts, 0)),
      component(Enum.at(parts, 1)),
      component(Enum.at(parts, 2))
    }
  end

  defp component(nil), do: 0

  defp component(str) do
    case Integer.parse(str) do
      {n, _rest} -> n
      :error -> 0
    end
  end
end
