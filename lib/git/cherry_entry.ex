defmodule Git.CherryEntry do
  @moduledoc """
  Parsed representation of a `git cherry` output line.

  Each entry indicates whether a commit has been applied upstream
  (cherry-picked) and includes the commit SHA and optionally the
  subject line when verbose mode is used.
  """

  @type t :: %__MODULE__{
          applied: boolean(),
          sha: String.t(),
          subject: String.t() | nil
        }

  defstruct applied: false,
            sha: "",
            subject: nil

  @doc """
  Parses the output of `git cherry` into a list of `Git.CherryEntry` structs.

  Each line starts with `+` (not applied upstream) or `-` (already applied),
  followed by a SHA. With `-v`, a subject line follows the SHA.

  ## Examples

      iex> Git.CherryEntry.parse("+ abc1234\\n- def5678\\n")
      [
        %Git.CherryEntry{applied: false, sha: "abc1234", subject: nil},
        %Git.CherryEntry{applied: true, sha: "def5678", subject: nil}
      ]

      iex> Git.CherryEntry.parse("+ abc1234 add feature\\n- def5678 fix bug\\n")
      [
        %Git.CherryEntry{applied: false, sha: "abc1234", subject: "add feature"},
        %Git.CherryEntry{applied: true, sha: "def5678", subject: "fix bug"}
      ]

      iex> Git.CherryEntry.parse("")
      []

  """
  @spec parse(String.t()) :: [t()]
  def parse(output) do
    output
    |> String.split("\n", trim: true)
    |> Enum.map(&parse_line/1)
  end

  @spec parse_line(String.t()) :: t()
  defp parse_line(line) do
    case Regex.run(~r/^([+-])\s+(\S+)(?:\s+(.+))?$/, String.trim(line)) do
      [_, sign, sha, subject] ->
        %__MODULE__{
          applied: sign == "-",
          sha: sha,
          subject: subject
        }

      [_, sign, sha] ->
        %__MODULE__{
          applied: sign == "-",
          sha: sha,
          subject: nil
        }

      _ ->
        %__MODULE__{sha: String.trim(line)}
    end
  end
end
