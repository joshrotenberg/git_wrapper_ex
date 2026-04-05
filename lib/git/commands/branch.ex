defmodule Git.Commands.Branch do
  @moduledoc """
  Implements the `Git.Command` behaviour for `git branch`.

  Supports listing branches (default), creating a new branch, and deleting
  a branch. Branch listing uses `-vv` to include upstream tracking information.
  """

  @behaviour Git.Command

  alias Git.Branch

  @type t :: %__MODULE__{
          list: boolean(),
          create: String.t() | nil,
          delete: String.t() | nil,
          force_delete: boolean(),
          all: boolean(),
          merged: String.t() | true | nil,
          no_merged: String.t() | true | nil,
          rename: String.t() | nil,
          rename_to: String.t() | nil
        }

  defstruct list: true,
            create: nil,
            delete: nil,
            force_delete: false,
            all: false,
            merged: nil,
            no_merged: nil,
            rename: nil,
            rename_to: nil

  @doc """
  Returns the argument list for `git branch`.

  - If `:create` is set, builds `git branch <name>`.
  - If `:delete` is set, builds `git branch -d <name>` (or `-D` with `force_delete: true`).
  - Otherwise, lists branches with `-vv` and optionally `--all`.

  ## Examples

      iex> Git.Commands.Branch.args(%Git.Commands.Branch{})
      ["branch", "-vv"]

      iex> Git.Commands.Branch.args(%Git.Commands.Branch{create: "feat/new"})
      ["branch", "feat/new"]

      iex> Git.Commands.Branch.args(%Git.Commands.Branch{delete: "old", force_delete: true})
      ["branch", "-D", "old"]

  """
  @spec args(t()) :: [String.t()]
  @impl true
  def args(%__MODULE__{create: name}) when is_binary(name), do: ["branch", name]

  def args(%__MODULE__{delete: name, force_delete: true}) when is_binary(name),
    do: ["branch", "-D", name]

  def args(%__MODULE__{delete: name}) when is_binary(name), do: ["branch", "-d", name]

  def args(%__MODULE__{rename: old_name, rename_to: new_name})
      when is_binary(old_name) and is_binary(new_name),
      do: ["branch", "-m", old_name, new_name]

  def args(%__MODULE__{merged: true}), do: ["branch", "--merged"]

  def args(%__MODULE__{merged: ref}) when is_binary(ref), do: ["branch", "--merged", ref]

  def args(%__MODULE__{no_merged: true}), do: ["branch", "--no-merged"]

  def args(%__MODULE__{no_merged: ref}) when is_binary(ref), do: ["branch", "--no-merged", ref]

  def args(%__MODULE__{all: true}), do: ["branch", "-vv", "--all"]

  def args(%__MODULE__{}), do: ["branch", "-vv"]

  @doc """
  Parses the output of `git branch`.

  For list operations (exit 0), parses each line into a `Git.Branch` struct.
  For create/delete operations (exit 0, empty output), returns `{:ok, :done}`.
  On failure, returns `{:error, {stdout, exit_code}}`.
  """
  @spec parse_output(String.t(), non_neg_integer()) ::
          {:ok, [Branch.t()]} | {:ok, :done} | {:error, {String.t(), non_neg_integer()}}
  @impl true
  def parse_output(stdout, 0) do
    trimmed = String.trim(stdout)

    # Create produces empty output; delete produces "Deleted branch <name>...";
    # list output contains branch entries starting with "* " or "  ".
    if trimmed == "" or String.starts_with?(trimmed, "Deleted branch") do
      {:ok, :done}
    else
      {:ok, Branch.parse(stdout)}
    end
  end

  def parse_output(stdout, exit_code), do: {:error, {stdout, exit_code}}

  # --merged / --no-merged output is simpler: just branch names with * / space prefix.
  # We parse these into Branch structs with only :name and :current populated.
  @doc false
  def parse_merged_output(stdout, 0) do
    branches =
      stdout
      |> String.split("\n", trim: true)
      |> Enum.map(fn line ->
        {current, worktree, name} =
          case line do
            "* " <> rest -> {true, false, String.trim(rest)}
            "+ " <> rest -> {false, true, String.trim(rest)}
            "  " <> rest -> {false, false, String.trim(rest)}
            _ -> {false, false, String.trim(line)}
          end

        %Branch{name: name, current: current, worktree: worktree}
      end)

    {:ok, branches}
  end

  def parse_merged_output(stdout, exit_code), do: {:error, {stdout, exit_code}}
end
