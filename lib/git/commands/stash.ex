defmodule Git.Commands.Stash do
  @moduledoc """
  Implements the `Git.Command` behaviour for `git stash`.

  Supports listing stash entries (default), saving (pushing) changes to the
  stash, popping the top stash entry, applying a stash without dropping it,
  dropping a stash entry, clearing all entries, creating a branch from a
  stash, and showing the diff for a stash entry.
  """

  @behaviour Git.Command

  alias Git.StashEntry

  @type t :: %__MODULE__{
          list: boolean(),
          save: boolean(),
          pop: boolean(),
          apply: boolean(),
          drop: boolean(),
          clear: boolean(),
          branch: String.t() | nil,
          show: boolean(),
          message: String.t() | nil,
          index: non_neg_integer() | nil,
          include_untracked: boolean(),
          keep_index: boolean()
        }

  defstruct list: true,
            save: false,
            pop: false,
            apply: false,
            drop: false,
            clear: false,
            branch: nil,
            show: false,
            message: nil,
            index: nil,
            include_untracked: false,
            keep_index: false

  # Process dictionary key used to communicate the operation mode from args/1
  # to parse_output/2. Both are called from the same process inside
  # Git.Command.run/3, so this is safe even with async tests.
  @mode_key :__git_stash_mode__

  @doc """
  Returns the argument list for `git stash`.

  - If `:save` is true, builds `git stash push [-m <message>] [-u] [--keep-index]`.
  - If `:pop` is true, builds `git stash pop [stash@{index}]`.
  - If `:apply` is true, builds `git stash apply [stash@{index}]`.
  - If `:drop` is true, builds `git stash drop [stash@{index}]`.
  - If `:clear` is true, builds `git stash clear`.
  - If `:branch` is a string, builds `git stash branch <name> [stash@{index}]`.
  - If `:show` is true, builds `git stash show [stash@{index}]`.
  - Otherwise, lists stash entries with `git stash list`.

  ## Examples

      iex> Git.Commands.Stash.args(%Git.Commands.Stash{})
      ["stash", "list"]

      iex> Git.Commands.Stash.args(%Git.Commands.Stash{save: true})
      ["stash", "push"]

      iex> Git.Commands.Stash.args(%Git.Commands.Stash{save: true, message: "wip"})
      ["stash", "push", "-m", "wip"]

      iex> Git.Commands.Stash.args(%Git.Commands.Stash{pop: true})
      ["stash", "pop"]

      iex> Git.Commands.Stash.args(%Git.Commands.Stash{drop: true, index: 1})
      ["stash", "drop", "stash@{1}"]

      iex> Git.Commands.Stash.args(%Git.Commands.Stash{apply: true, index: 1})
      ["stash", "apply", "stash@{1}"]

      iex> Git.Commands.Stash.args(%Git.Commands.Stash{clear: true})
      ["stash", "clear"]

      iex> Git.Commands.Stash.args(%Git.Commands.Stash{branch: "recovered"})
      ["stash", "branch", "recovered"]

      iex> Git.Commands.Stash.args(%Git.Commands.Stash{show: true})
      ["stash", "show"]

  """
  @spec args(t()) :: [String.t()]
  @impl true
  def args(%__MODULE__{save: true} = command) do
    Process.put(@mode_key, :mutation)

    base = ["stash", "push"]

    base
    |> maybe_add_message(command.message)
    |> maybe_add_flag(command.include_untracked, "-u")
    |> maybe_add_flag(command.keep_index, "--keep-index")
  end

  def args(%__MODULE__{pop: true} = command) do
    Process.put(@mode_key, :mutation)
    ["stash", "pop"] |> maybe_add_ref(command.index)
  end

  def args(%__MODULE__{apply: true} = command) do
    Process.put(@mode_key, :mutation)
    ["stash", "apply"] |> maybe_add_ref(command.index)
  end

  def args(%__MODULE__{drop: true} = command) do
    Process.put(@mode_key, :mutation)
    ["stash", "drop"] |> maybe_add_ref(command.index)
  end

  def args(%__MODULE__{clear: true}) do
    Process.put(@mode_key, :mutation)
    ["stash", "clear"]
  end

  def args(%__MODULE__{branch: branch} = command) when is_binary(branch) do
    Process.put(@mode_key, :mutation)
    ["stash", "branch", branch] |> maybe_add_ref(command.index)
  end

  def args(%__MODULE__{show: true} = command) do
    Process.put(@mode_key, :show)
    ["stash", "show"] |> maybe_add_ref(command.index)
  end

  def args(%__MODULE__{}) do
    Process.put(@mode_key, :list)
    ["stash", "list"]
  end

  @doc """
  Parses the output of `git stash`.

  For list operations (exit 0), parses each line into a `Git.StashEntry` struct.
  For show operations (exit 0), returns the raw diff as `{:ok, stdout}`.
  For save/pop/apply/drop/clear/branch operations (exit 0), returns `{:ok, :done}`.
  On failure, returns `{:error, {stdout, exit_code}}`.
  """
  @spec parse_output(String.t(), non_neg_integer()) ::
          {:ok, [StashEntry.t()]}
          | {:ok, :done}
          | {:ok, String.t()}
          | {:error, {String.t(), non_neg_integer()}}
  @impl true
  def parse_output(stdout, 0) do
    mode = Process.get(@mode_key, :list)

    case mode do
      :mutation ->
        {:ok, :done}

      :show ->
        {:ok, stdout}

      :list ->
        if String.trim(stdout) == "" do
          {:ok, []}
        else
          {:ok, StashEntry.parse(stdout)}
        end
    end
  end

  def parse_output(stdout, exit_code), do: {:error, {stdout, exit_code}}

  @spec maybe_add_message([String.t()], String.t() | nil) :: [String.t()]
  defp maybe_add_message(args, nil), do: args
  defp maybe_add_message(args, message) when is_binary(message), do: args ++ ["-m", message]

  @spec maybe_add_flag([String.t()], boolean(), String.t()) :: [String.t()]
  defp maybe_add_flag(args, false, _flag), do: args
  defp maybe_add_flag(args, true, flag), do: args ++ [flag]

  @spec maybe_add_ref([String.t()], non_neg_integer() | nil) :: [String.t()]
  defp maybe_add_ref(args, nil), do: args
  defp maybe_add_ref(args, index) when is_integer(index), do: args ++ ["stash@{#{index}}"]
end
