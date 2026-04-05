defmodule Git.Commands.SparseCheckout do
  @moduledoc """
  Implements the `Git.Command` behaviour for `git sparse-checkout`.

  Supports initializing, setting, adding, listing, disabling, reapplying,
  and checking rules for sparse-checkout.
  """

  @behaviour Git.Command

  @type t :: %__MODULE__{
          init: boolean(),
          set: [String.t()],
          add: [String.t()],
          list: boolean(),
          disable: boolean(),
          reapply: boolean(),
          check_rules: boolean(),
          cone: boolean(),
          no_cone: boolean(),
          sparse_index: boolean(),
          no_sparse_index: boolean()
        }

  defstruct init: false,
            set: [],
            add: [],
            list: true,
            disable: false,
            reapply: false,
            check_rules: false,
            cone: false,
            no_cone: false,
            sparse_index: false,
            no_sparse_index: false

  # Process dictionary key used to communicate the operation mode from args/1
  # to parse_output/2. Both are called from the same process inside
  # Git.Command.run/3, so this is safe even with async tests.
  @mode_key :__git_sparse_checkout_mode__

  @doc """
  Returns the argument list for `git sparse-checkout`.

  - If `:init` is true, builds `git sparse-checkout init [--cone] [--sparse-index]`.
  - If `:set` is non-empty, builds `git sparse-checkout set [--cone] [--no-cone] <patterns...>`.
  - If `:add` is non-empty, builds `git sparse-checkout add [--cone] [--no-cone] <patterns...>`.
  - If `:disable` is true, builds `git sparse-checkout disable`.
  - If `:reapply` is true, builds `git sparse-checkout reapply`.
  - If `:check_rules` is true, builds `git sparse-checkout check-rules`.
  - Otherwise, lists current patterns with `git sparse-checkout list`.

  ## Examples

      iex> Git.Commands.SparseCheckout.args(%Git.Commands.SparseCheckout{})
      ["sparse-checkout", "list"]

      iex> Git.Commands.SparseCheckout.args(%Git.Commands.SparseCheckout{init: true, cone: true})
      ["sparse-checkout", "init", "--cone"]

      iex> Git.Commands.SparseCheckout.args(%Git.Commands.SparseCheckout{set: ["src/", "docs/"], cone: true})
      ["sparse-checkout", "set", "--cone", "src/", "docs/"]

      iex> Git.Commands.SparseCheckout.args(%Git.Commands.SparseCheckout{add: ["tests/"]})
      ["sparse-checkout", "add", "tests/"]

      iex> Git.Commands.SparseCheckout.args(%Git.Commands.SparseCheckout{disable: true})
      ["sparse-checkout", "disable"]

      iex> Git.Commands.SparseCheckout.args(%Git.Commands.SparseCheckout{reapply: true})
      ["sparse-checkout", "reapply"]

  """
  @spec args(t()) :: [String.t()]
  @impl true
  def args(%__MODULE__{init: true} = command) do
    Process.put(@mode_key, :mutation)

    ["sparse-checkout", "init"]
    |> maybe_add_flag(command.cone, "--cone")
    |> maybe_add_flag(command.no_cone, "--no-cone")
    |> maybe_add_flag(command.sparse_index, "--sparse-index")
    |> maybe_add_flag(command.no_sparse_index, "--no-sparse-index")
  end

  def args(%__MODULE__{set: patterns} = command) when patterns != [] do
    Process.put(@mode_key, :mutation)

    ["sparse-checkout", "set"]
    |> maybe_add_flag(command.cone, "--cone")
    |> maybe_add_flag(command.no_cone, "--no-cone")
    |> Kernel.++(patterns)
  end

  def args(%__MODULE__{add: patterns} = command) when patterns != [] do
    Process.put(@mode_key, :mutation)

    ["sparse-checkout", "add"]
    |> maybe_add_flag(command.cone, "--cone")
    |> maybe_add_flag(command.no_cone, "--no-cone")
    |> Kernel.++(patterns)
  end

  def args(%__MODULE__{disable: true}) do
    Process.put(@mode_key, :mutation)
    ["sparse-checkout", "disable"]
  end

  def args(%__MODULE__{reapply: true}) do
    Process.put(@mode_key, :mutation)
    ["sparse-checkout", "reapply"]
  end

  def args(%__MODULE__{check_rules: true}) do
    Process.put(@mode_key, :mutation)
    ["sparse-checkout", "check-rules"]
  end

  def args(%__MODULE__{}) do
    Process.put(@mode_key, :list)
    ["sparse-checkout", "list"]
  end

  @doc """
  Parses the output of `git sparse-checkout`.

  For list operations (exit 0), returns `{:ok, [pattern]}` with one pattern
  per line. For all mutation operations (exit 0), returns `{:ok, :done}`.
  On failure, returns `{:error, {stdout, exit_code}}`.
  """
  @spec parse_output(String.t(), non_neg_integer()) ::
          {:ok, [String.t()]} | {:ok, :done} | {:error, {String.t(), non_neg_integer()}}
  @impl true
  def parse_output(stdout, 0) do
    mode = Process.get(@mode_key, :list)

    case mode do
      :mutation ->
        {:ok, :done}

      :list ->
        patterns =
          stdout
          |> String.split("\n", trim: true)
          |> Enum.map(&String.trim/1)

        {:ok, patterns}
    end
  end

  def parse_output(stdout, exit_code), do: {:error, {stdout, exit_code}}

  defp maybe_add_flag(args, false, _flag), do: args
  defp maybe_add_flag(args, true, flag), do: args ++ [flag]
end
