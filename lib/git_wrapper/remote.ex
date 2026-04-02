defmodule GitWrapper.Remote do
  @moduledoc """
  Represents a git remote with its name, fetch URL, and push URL.

  Parsed from `git remote -v` output via `parse_verbose/1`.
  """

  @type t :: %__MODULE__{
          name: String.t(),
          fetch_url: String.t() | nil,
          push_url: String.t() | nil
        }

  defstruct [:name, :fetch_url, :push_url]

  @doc """
  Parses the output of `git remote -v` into a list of `%GitWrapper.Remote{}` structs.

  Each remote appears twice in the output (once for fetch, once for push).
  Lines are grouped by remote name so each remote becomes a single struct.

  ## Examples

      iex> output = "origin\\thttps://github.com/user/repo.git (fetch)\\norigin\\thttps://github.com/user/repo.git (push)\\n"
      iex> GitWrapper.Remote.parse_verbose(output)
      [%GitWrapper.Remote{name: "origin", fetch_url: "https://github.com/user/repo.git", push_url: "https://github.com/user/repo.git"}]

  """
  @spec parse_verbose(String.t()) :: [t()]
  def parse_verbose(""), do: []

  def parse_verbose(output) do
    output
    |> String.split("\n", trim: true)
    |> Enum.reduce(%{}, fn line, acc ->
      case parse_line(line) do
        {name, url, :fetch} ->
          remote = Map.get(acc, name, %__MODULE__{name: name})
          Map.put(acc, name, %{remote | fetch_url: url})

        {name, url, :push} ->
          remote = Map.get(acc, name, %__MODULE__{name: name})
          Map.put(acc, name, %{remote | push_url: url})

        nil ->
          acc
      end
    end)
    |> Map.values()
    |> Enum.sort_by(& &1.name)
  end

  defp parse_line(line) do
    case String.split(line, "\t", parts: 2) do
      [name, rest] ->
        case Regex.run(~r/^(.*)\s+\((fetch|push)\)$/, String.trim(rest)) do
          [_, url, "fetch"] -> {name, url, :fetch}
          [_, url, "push"] -> {name, url, :push}
          _ -> nil
        end

      _ ->
        nil
    end
  end
end
