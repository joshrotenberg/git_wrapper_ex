defmodule Git.Commands.Switch do
  @moduledoc """
  Implements the `Git.Command` behaviour for `git switch`.

  `git switch` is the modern (Git 2.23+) command for switching branches,
  replacing the branch-switching role of `git checkout`. It is more focused
  and less error-prone than `checkout` for branch operations.
  """

  @behaviour Git.Command

  alias Git.Checkout

  @type t :: %__MODULE__{
          branch: String.t() | nil,
          create: boolean(),
          force_create: boolean(),
          detach: boolean(),
          force: boolean(),
          discard_changes: boolean(),
          merge: boolean(),
          orphan: boolean(),
          guess: boolean() | nil,
          track: String.t() | nil
        }

  defstruct branch: nil,
            create: false,
            force_create: false,
            detach: false,
            force: false,
            discard_changes: false,
            merge: false,
            orphan: false,
            guess: nil,
            track: nil

  @doc """
  Returns the argument list for `git switch`.

  ## Examples

      iex> Git.Commands.Switch.args(%Git.Commands.Switch{branch: "main"})
      ["switch", "main"]

      iex> Git.Commands.Switch.args(%Git.Commands.Switch{branch: "feat/new", create: true})
      ["switch", "-c", "feat/new"]

      iex> Git.Commands.Switch.args(%Git.Commands.Switch{branch: "abc123", detach: true})
      ["switch", "--detach", "abc123"]

  """
  @spec args(t()) :: [String.t()]
  @impl true
  def args(%__MODULE__{} = cmd) do
    ["switch"] ++ build_flags(cmd) ++ build_branch(cmd)
  end

  defp build_flags(%__MODULE__{} = cmd) do
    []
    |> maybe_add(cmd.create, "-c")
    |> maybe_add(cmd.force_create, "-C")
    |> maybe_add(cmd.detach, "--detach")
    |> maybe_add(cmd.force, "--force")
    |> maybe_add(cmd.discard_changes, "--discard-changes")
    |> maybe_add(cmd.merge, "--merge")
    |> maybe_add(cmd.orphan, "--orphan")
    |> maybe_add(cmd.guess == true, "--guess")
    |> maybe_add(cmd.guess == false, "--no-guess")
    |> maybe_add_value(cmd.track, "--track")
  end

  defp build_branch(%__MODULE__{branch: nil}), do: []
  defp build_branch(%__MODULE__{branch: branch}), do: [branch]

  defp maybe_add(list, true, flag), do: list ++ [flag]
  defp maybe_add(list, _, _flag), do: list

  defp maybe_add_value(list, nil, _flag), do: list
  defp maybe_add_value(list, value, flag), do: list ++ [flag, value]

  @doc """
  Parses the output of `git switch`.

  Reuses `Git.Checkout` parsing since the output format is the same
  (e.g. "Switched to branch 'main'").
  """
  @spec parse_output(String.t(), non_neg_integer()) ::
          {:ok, Checkout.t()} | {:ok, :done} | {:error, {String.t(), non_neg_integer()}}
  @impl true
  def parse_output(stdout, 0) do
    {:ok, Checkout.parse(stdout)}
  end

  def parse_output(stdout, exit_code), do: {:error, {stdout, exit_code}}
end
