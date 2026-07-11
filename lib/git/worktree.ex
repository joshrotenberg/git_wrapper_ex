defmodule Git.Worktree do
  @moduledoc """
  Parsed representation of a git worktree entry.

  Contains the path, HEAD commit SHA, branch reference, and flags
  indicating whether the worktree is bare or has a detached HEAD.

  Two annotation fields carry the porcelain `locked` and `prunable` markers.
  Each is `nil` when absent and otherwise the reason git reported (the empty
  string when git gave no reason). `prunable` marks a worktree whose directory
  is gone, recoverable with `git worktree prune`.
  """

  @type t :: %__MODULE__{
          path: String.t(),
          head: String.t(),
          branch: String.t() | nil,
          bare: boolean(),
          detached: boolean(),
          locked: String.t() | nil,
          prunable: String.t() | nil
        }

  defstruct [:path, :head, :branch, :locked, :prunable, bare: false, detached: false]

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
      [%Git.Worktree{path: "/tmp/main", head: "abc1234", branch: "refs/heads/main", locked: nil, prunable: nil, bare: false, detached: false}]

      iex> Git.Worktree.parse("worktree /tmp/gone\\nHEAD abc1234\\nbranch refs/heads/wt\\nprunable gitdir file points to non-existent location\\n\\n") |> hd() |> Map.get(:prunable)
      "gitdir file points to non-existent location"

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
    block
    |> String.split("\n", trim: true)
    |> Enum.reduce(%__MODULE__{}, &apply_line/2)
  end

  @spec apply_line(String.t(), t()) :: t()
  defp apply_line("worktree " <> path, acc), do: %{acc | path: path}
  defp apply_line("HEAD " <> head, acc), do: %{acc | head: head}
  defp apply_line("branch " <> branch, acc), do: %{acc | branch: branch}
  defp apply_line("bare", acc), do: %{acc | bare: true}
  defp apply_line("detached", acc), do: %{acc | detached: true}
  defp apply_line("locked " <> reason, acc), do: %{acc | locked: reason}
  defp apply_line("locked", acc), do: %{acc | locked: ""}
  defp apply_line("prunable " <> reason, acc), do: %{acc | prunable: reason}
  defp apply_line("prunable", acc), do: %{acc | prunable: ""}
  defp apply_line(_other, acc), do: acc
end
