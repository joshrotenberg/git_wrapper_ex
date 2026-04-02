defmodule GitWrapper.Commands.Branch do
  @moduledoc """
  Implements the `GitWrapper.Command` behaviour for `git branch`.

  Supports listing branches (default), creating a new branch, and deleting
  a branch. Branch listing uses `-vv` to include upstream tracking information.
  """

  @behaviour GitWrapper.Command

  alias GitWrapper.Branch

  @type t :: %__MODULE__{
          list: boolean(),
          create: String.t() | nil,
          delete: String.t() | nil,
          force_delete: boolean(),
          all: boolean()
        }

  defstruct list: true,
            create: nil,
            delete: nil,
            force_delete: false,
            all: false

  @doc """
  Returns the argument list for `git branch`.

  - If `:create` is set, builds `git branch <name>`.
  - If `:delete` is set, builds `git branch -d <name>` (or `-D` with `force_delete: true`).
  - Otherwise, lists branches with `-vv` and optionally `--all`.

  ## Examples

      iex> GitWrapper.Commands.Branch.args(%GitWrapper.Commands.Branch{})
      ["branch", "-vv"]

      iex> GitWrapper.Commands.Branch.args(%GitWrapper.Commands.Branch{create: "feat/new"})
      ["branch", "feat/new"]

      iex> GitWrapper.Commands.Branch.args(%GitWrapper.Commands.Branch{delete: "old", force_delete: true})
      ["branch", "-D", "old"]

  """
  @spec args(t()) :: [String.t()]
  @impl true
  def args(%__MODULE__{create: name}) when is_binary(name), do: ["branch", name]

  def args(%__MODULE__{delete: name, force_delete: true}) when is_binary(name),
    do: ["branch", "-D", name]

  def args(%__MODULE__{delete: name}) when is_binary(name), do: ["branch", "-d", name]

  def args(%__MODULE__{all: true}), do: ["branch", "-vv", "--all"]

  def args(%__MODULE__{}), do: ["branch", "-vv"]

  @doc """
  Parses the output of `git branch`.

  For list operations (exit 0), parses each line into a `GitWrapper.Branch` struct.
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
end
