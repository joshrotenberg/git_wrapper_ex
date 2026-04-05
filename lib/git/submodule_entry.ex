defmodule Git.SubmoduleEntry do
  @moduledoc """
  Parsed representation of a git submodule status entry.

  Each entry contains the SHA, path, an optional describe string
  (tag describe for the SHA), and a status indicating the submodule state.

  ## Status values

    * `:current` - submodule is checked out at the recorded commit
    * `:modified` - submodule has a different commit checked out
    * `:uninitialized` - submodule is not initialized
    * `:conflict` - submodule has merge conflicts
  """

  @type status :: :current | :modified | :uninitialized | :conflict

  @type t :: %__MODULE__{
          sha: String.t(),
          path: String.t(),
          describe: String.t() | nil,
          status: status()
        }

  defstruct [:sha, :path, :describe, :status]

  @doc """
  Parses the output of `git submodule status` into a list of
  `Git.SubmoduleEntry` structs.

  Each line has the format:

      <status_char><sha> <path> (<describe>)

  where `<status_char>` is a space (current), `+` (modified),
  `-` (uninitialized), or `U` (conflict), and the describe portion
  is optional.

  ## Examples

      iex> Git.SubmoduleEntry.parse(" abc1234 lib/sub (v1.0.0)\\n")
      [%Git.SubmoduleEntry{sha: "abc1234", path: "lib/sub", describe: "v1.0.0", status: :current}]

      iex> Git.SubmoduleEntry.parse("+def5678 vendor/dep\\n")
      [%Git.SubmoduleEntry{sha: "def5678", path: "vendor/dep", describe: nil, status: :modified}]

      iex> Git.SubmoduleEntry.parse("")
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
    case Regex.run(~r/^([ +\-U])([0-9a-f]+)\s+(\S+)(?:\s+\((.+)\))?/, line) do
      [_, status_char, sha, path, describe] ->
        %__MODULE__{
          sha: sha,
          path: path,
          describe: if(describe == "", do: nil, else: describe),
          status: parse_status(status_char)
        }

      [_, status_char, sha, path] ->
        %__MODULE__{
          sha: sha,
          path: path,
          describe: nil,
          status: parse_status(status_char)
        }

      nil ->
        %__MODULE__{sha: "", path: String.trim(line), describe: nil, status: :current}
    end
  end

  @spec parse_status(String.t()) :: status()
  defp parse_status(" "), do: :current
  defp parse_status("+"), do: :modified
  defp parse_status("-"), do: :uninitialized
  defp parse_status("U"), do: :conflict
end
