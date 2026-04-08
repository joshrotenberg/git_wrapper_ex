defmodule Git.Commands.Am do
  @moduledoc """
  Implements the `Git.Command` behaviour for `git am`.

  Applies a series of patches from mailbox-formatted files. Supports three-way
  merges, keeping subject prefixes, adding sign-off lines, and controlling
  in-progress am sessions (abort, continue, skip).
  """

  @behaviour Git.Command

  @type t :: %__MODULE__{
          patches: [String.t()],
          directory: String.t() | nil,
          three_way: boolean(),
          keep: boolean(),
          signoff: boolean(),
          abort: boolean(),
          continue_: boolean(),
          skip: boolean(),
          quiet: boolean()
        }

  defstruct patches: [],
            directory: nil,
            three_way: false,
            keep: false,
            signoff: false,
            abort: false,
            continue_: false,
            skip: false,
            quiet: false

  @doc """
  Returns the argument list for `git am`.

  When `:abort`, `:continue_`, or `:skip` is `true`, builds the corresponding
  control command. Otherwise builds the full am command with all applicable
  flags and patch file paths.

  ## Examples

      iex> Git.Commands.Am.args(%Git.Commands.Am{abort: true})
      ["am", "--abort"]

      iex> Git.Commands.Am.args(%Git.Commands.Am{continue_: true})
      ["am", "--continue"]

      iex> Git.Commands.Am.args(%Git.Commands.Am{skip: true})
      ["am", "--skip"]

      iex> Git.Commands.Am.args(%Git.Commands.Am{patches: ["0001-fix.patch"]})
      ["am", "0001-fix.patch"]

      iex> Git.Commands.Am.args(%Git.Commands.Am{patches: ["0001-fix.patch"], three_way: true, signoff: true})
      ["am", "--3way", "--signoff", "0001-fix.patch"]

      iex> Git.Commands.Am.args(%Git.Commands.Am{directory: "/tmp/patches"})
      ["am", "/tmp/patches"]

  """
  @spec args(t()) :: [String.t()]
  @impl true
  def args(%__MODULE__{abort: true}), do: ["am", "--abort"]
  def args(%__MODULE__{continue_: true}), do: ["am", "--continue"]
  def args(%__MODULE__{skip: true}), do: ["am", "--skip"]

  def args(%__MODULE__{} = command) do
    ["am"]
    |> maybe_add(command.three_way, "--3way")
    |> maybe_add(command.keep, "--keep")
    |> maybe_add(command.signoff, "--signoff")
    |> maybe_add(command.quiet, "--quiet")
    |> maybe_add_patches(command.patches, command.directory)
  end

  @doc """
  Parses the output of `git am`.

  On success (exit code 0), returns `{:ok, :done}`.
  On failure, returns `{:error, {stdout, exit_code}}`.
  """
  @spec parse_output(String.t(), non_neg_integer()) ::
          {:ok, :done} | {:error, {String.t(), non_neg_integer()}}
  @impl true
  def parse_output(_stdout, 0), do: {:ok, :done}
  def parse_output(stdout, exit_code), do: {:error, {stdout, exit_code}}

  defp maybe_add(args, true, flag), do: args ++ [flag]
  defp maybe_add(args, false, _flag), do: args

  defp maybe_add_patches(args, [], nil), do: args
  defp maybe_add_patches(args, [], dir) when is_binary(dir), do: args ++ [dir]
  defp maybe_add_patches(args, patches, _dir), do: args ++ patches
end
