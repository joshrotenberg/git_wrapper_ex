defmodule GitWrapper.Commands.Checkout do
  @moduledoc """
  Implements the `GitWrapper.Command` behaviour for `git checkout`.

  Supports switching to an existing branch, creating and switching to a new
  branch (`-b`), and restoring files from the index.
  """

  @behaviour GitWrapper.Command

  alias GitWrapper.Checkout

  @type t :: %__MODULE__{
          branch: String.t() | nil,
          create: boolean(),
          files: [String.t()]
        }

  defstruct branch: nil,
            create: false,
            files: []

  # Process dictionary key used to communicate the operation mode from args/1
  # to parse_output/2. Both are called from the same process inside
  # GitWrapper.Command.run/3, so this is safe even with async tests.
  @mode_key :__git_checkout_mode__

  @doc """
  Returns the argument list for `git checkout`.

  - If `:files` is non-empty, builds `git checkout -- <files...>`.
  - If `:branch` is set and `:create` is true, builds `git checkout -b <branch>`.
  - If `:branch` is set, builds `git checkout <branch>`.

  ## Examples

      iex> GitWrapper.Commands.Checkout.args(%GitWrapper.Commands.Checkout{branch: "main"})
      ["checkout", "main"]

      iex> GitWrapper.Commands.Checkout.args(%GitWrapper.Commands.Checkout{branch: "feat/new", create: true})
      ["checkout", "-b", "feat/new"]

      iex> GitWrapper.Commands.Checkout.args(%GitWrapper.Commands.Checkout{files: ["README.md", "lib/foo.ex"]})
      ["checkout", "--", "README.md", "lib/foo.ex"]

  """
  @spec args(t()) :: [String.t()]
  @impl true
  def args(%__MODULE__{files: [_ | _] = files}) do
    Process.put(@mode_key, :files)
    ["checkout", "--"] ++ files
  end

  def args(%__MODULE__{branch: branch, create: true}) when is_binary(branch) do
    Process.put(@mode_key, :branch)
    ["checkout", "-b", branch]
  end

  def args(%__MODULE__{branch: branch}) when is_binary(branch) do
    Process.put(@mode_key, :branch)
    ["checkout", branch]
  end

  @doc """
  Parses the output of `git checkout`.

  For file restore operations (exit 0), returns `{:ok, :done}`.
  For branch operations (exit 0), parses into a `GitWrapper.Checkout` struct.
  On failure, returns `{:error, {stdout, exit_code}}`.
  """
  @spec parse_output(String.t(), non_neg_integer()) ::
          {:ok, Checkout.t()} | {:ok, :done} | {:error, {String.t(), non_neg_integer()}}
  @impl true
  def parse_output(stdout, 0) do
    case Process.get(@mode_key, :branch) do
      :files -> {:ok, :done}
      :branch -> {:ok, Checkout.parse(stdout)}
    end
  end

  def parse_output(stdout, exit_code), do: {:error, {stdout, exit_code}}
end
