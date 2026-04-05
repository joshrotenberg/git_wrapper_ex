defmodule Git.Commands.Rerere do
  @moduledoc """
  Implements the `Git.Command` behaviour for `git rerere`.

  Reuse recorded resolution of conflicted merges. Supports the `status`,
  `diff`, `clear`, `forget`, `gc`, and `remaining` subcommands.
  """

  @behaviour Git.Command

  @type t :: %__MODULE__{
          status: boolean(),
          diff: boolean(),
          clear: boolean(),
          forget: String.t() | nil,
          gc: boolean(),
          remaining: boolean()
        }

  defstruct status: false,
            diff: false,
            clear: false,
            forget: nil,
            gc: false,
            remaining: false

  # Process dictionary key used to communicate the operation mode from args/1
  # to parse_output/2. Both are called from the same process inside
  # Git.Command.run/3, so this is safe even with async tests.
  @mode_key :__git_rerere_mode__

  @doc """
  Returns the argument list for `git rerere`.

  ## Examples

      iex> Git.Commands.Rerere.args(%Git.Commands.Rerere{})
      ["rerere", "status"]

      iex> Git.Commands.Rerere.args(%Git.Commands.Rerere{status: true})
      ["rerere", "status"]

      iex> Git.Commands.Rerere.args(%Git.Commands.Rerere{diff: true})
      ["rerere", "diff"]

      iex> Git.Commands.Rerere.args(%Git.Commands.Rerere{clear: true})
      ["rerere", "clear"]

      iex> Git.Commands.Rerere.args(%Git.Commands.Rerere{forget: "path/to/file"})
      ["rerere", "forget", "path/to/file"]

      iex> Git.Commands.Rerere.args(%Git.Commands.Rerere{gc: true})
      ["rerere", "gc"]

      iex> Git.Commands.Rerere.args(%Git.Commands.Rerere{remaining: true})
      ["rerere", "remaining"]

  """
  @spec args(t()) :: [String.t()]
  @impl true
  def args(%__MODULE__{diff: true}) do
    Process.put(@mode_key, :diff)
    ["rerere", "diff"]
  end

  def args(%__MODULE__{clear: true}) do
    Process.put(@mode_key, :mutation)
    ["rerere", "clear"]
  end

  def args(%__MODULE__{forget: path}) when is_binary(path) do
    Process.put(@mode_key, :mutation)
    ["rerere", "forget", path]
  end

  def args(%__MODULE__{gc: true}) do
    Process.put(@mode_key, :mutation)
    ["rerere", "gc"]
  end

  def args(%__MODULE__{remaining: true}) do
    Process.put(@mode_key, :paths)
    ["rerere", "remaining"]
  end

  def args(%__MODULE__{}) do
    Process.put(@mode_key, :paths)
    ["rerere", "status"]
  end

  @doc """
  Parses the output of `git rerere`.

  - For `status` and `remaining` modes, returns `{:ok, [String.t()]}` with
    a list of file paths.
  - For `diff` mode, returns `{:ok, String.t()}` with raw diff output.
  - For `clear`, `forget`, and `gc` modes, returns `{:ok, :done}`.
  """
  @spec parse_output(String.t(), non_neg_integer()) ::
          {:ok, [String.t()]}
          | {:ok, String.t()}
          | {:ok, :done}
          | {:error, {String.t(), non_neg_integer()}}
  @impl true
  def parse_output(stdout, 0) do
    mode = Process.get(@mode_key, :paths)

    case mode do
      :paths ->
        paths =
          stdout
          |> String.trim()
          |> case do
            "" -> []
            text -> String.split(text, "\n", trim: true)
          end

        {:ok, paths}

      :diff ->
        {:ok, String.trim(stdout)}

      :mutation ->
        {:ok, :done}
    end
  end

  def parse_output(stdout, exit_code), do: {:error, {stdout, exit_code}}
end
