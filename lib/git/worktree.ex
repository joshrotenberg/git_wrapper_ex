defmodule Git.Worktree do
  @moduledoc """
  Parsed representation of a git worktree entry.

  Contains the path, HEAD commit SHA, branch reference, and flags
  indicating whether the worktree is bare or has a detached HEAD.
  """

  @type t :: %__MODULE__{
          path: String.t(),
          head: String.t(),
          branch: String.t() | nil,
          bare: boolean(),
          detached: boolean()
        }

  defstruct [:path, :head, :branch, bare: false, detached: false]

  @doc """
  Parses the porcelain output of `git worktree list --porcelain` into a list
  of `Git.Worktree` structs.

  The porcelain format separates entries with blank lines. Each entry has
  key-value lines like:

      worktree /path/to/main
      HEAD abc1234
      branch refs/heads/main

  ## Examples

      iex> Git.Worktree.parse("worktree /tmp/main\\nHEAD abc1234\\nbranch refs/heads/main\\n\\n")
      [%Git.Worktree{path: "/tmp/main", head: "abc1234", branch: "refs/heads/main", bare: false, detached: false}]

      iex> Git.Worktree.parse("")
      []

  """
  @spec parse(String.t()) :: [t()]
  def parse(output) do
    output
    |> String.split("\n\n", trim: true)
    |> Enum.map(&parse_entry/1)
    |> Enum.reject(&is_nil/1)
  end

  @spec parse_entry(String.t()) :: t() | nil
  defp parse_entry(block) do
    lines = String.split(block, "\n", trim: true)

    Enum.reduce(lines, %__MODULE__{}, fn line, acc ->
      cond do
        String.starts_with?(line, "worktree ") ->
          %{acc | path: String.trim_leading(line, "worktree ")}

        String.starts_with?(line, "HEAD ") ->
          %{acc | head: String.trim_leading(line, "HEAD ")}

        String.starts_with?(line, "branch ") ->
          %{acc | branch: String.trim_leading(line, "branch ")}

        line == "bare" ->
          %{acc | bare: true}

        line == "detached" ->
          %{acc | detached: true}

        true ->
          acc
      end
    end)
  end
end
