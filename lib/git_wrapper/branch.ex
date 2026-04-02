defmodule GitWrapper.Branch do
  @moduledoc """
  Parsed representation of a git branch entry.

  Contains the branch name, whether it is the currently checked-out branch,
  whether it is a remote-tracking branch, its upstream tracking reference,
  and the ahead/behind commit counts relative to the upstream.
  """

  @type t :: %__MODULE__{
          name: String.t(),
          current: boolean(),
          remote: boolean(),
          upstream: String.t() | nil,
          ahead: non_neg_integer(),
          behind: non_neg_integer()
        }

  defstruct [:name, :upstream, current: false, remote: false, ahead: 0, behind: 0]

  @doc """
  Parses the output of `git branch -vv` into a list of `GitWrapper.Branch` structs.

  Each line has the form:

      * main                abc1234 [origin/main: ahead 1] subject
        feature/foo         def5678 [origin/feature/foo] subject
        remotes/origin/HEAD -> origin/main

  Lines beginning with `remotes/` are remote-tracking refs. Lines containing
  ` -> ` are symbolic refs (e.g. `HEAD -> main`) and are skipped.

  ## Examples

      iex> GitWrapper.Branch.parse("* main abc1234 subject\\n")
      [%GitWrapper.Branch{name: "main", current: true, remote: false}]

  """
  @spec parse(String.t()) :: [t()]
  def parse(output) do
    output
    |> String.split("\n", trim: true)
    |> Enum.reject(&String.contains?(&1, " -> "))
    |> Enum.map(&parse_line/1)
  end

  @spec parse_line(String.t()) :: t()
  defp parse_line(line) do
    {current, rest} =
      case line do
        "* " <> rest -> {true, rest}
        "  " <> rest -> {false, rest}
        _ -> {false, line}
      end

    # Name is the first whitespace-delimited token
    name = rest |> String.split() |> List.first() || ""
    remote = String.starts_with?(name, "remotes/")

    {upstream, ahead, behind} = extract_tracking(rest)

    %__MODULE__{
      name: name,
      current: current,
      remote: remote,
      upstream: upstream,
      ahead: ahead,
      behind: behind
    }
  end

  # Extracts [upstream: ahead N, behind N] bracket from a branch line.
  @spec extract_tracking(String.t()) ::
          {String.t() | nil, non_neg_integer(), non_neg_integer()}
  defp extract_tracking(line) do
    case Regex.run(~r/\[([^\]]+)\]/, line) do
      [_, content] ->
        upstream =
          content
          |> String.split(":")
          |> List.first()
          |> String.trim()

        ahead = extract_count(content, ~r/ahead\s+(\d+)/)
        behind = extract_count(content, ~r/behind\s+(\d+)/)
        {upstream, ahead, behind}

      nil ->
        {nil, 0, 0}
    end
  end

  @spec extract_count(String.t(), Regex.t()) :: non_neg_integer()
  defp extract_count(text, regex) do
    case Regex.run(regex, text) do
      [_, n] -> String.to_integer(n)
      nil -> 0
    end
  end
end
