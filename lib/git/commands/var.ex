defmodule Git.Commands.Var do
  @moduledoc """
  Implements the `Git.Command` behaviour for `git var`.

  Two modes are supported:

    * list mode (`git var -l`) parses the `NAME=value` lines into a map
    * single-variable mode (`git var <NAME>`) returns the trimmed value string

  Set `:name` to look up a single variable; leave it `nil` to list all.
  """

  @behaviour Git.Command

  @type t :: %__MODULE__{name: String.t() | nil}

  defstruct name: nil

  # Process dictionary key used to communicate the output mode from args/1
  # to parse_output/2.
  @mode_key :__git_var_mode__

  @doc """
  Returns the argument list for `git var`.

  ## Examples

      iex> Git.Commands.Var.args(%Git.Commands.Var{})
      ["var", "-l"]

      iex> Git.Commands.Var.args(%Git.Commands.Var{name: "GIT_EDITOR"})
      ["var", "GIT_EDITOR"]

  """
  @spec args(t()) :: [String.t()]
  @impl true
  def args(%__MODULE__{name: nil}) do
    Process.put(@mode_key, :list)
    ["var", "-l"]
  end

  def args(%__MODULE__{name: name}) do
    Process.put(@mode_key, :single)
    ["var", name]
  end

  @doc """
  Parses the output of `git var`.

  In list mode, returns `{:ok, map}` mapping each variable name to its value.
  In single-variable mode, returns `{:ok, value}` with the trimmed string. On a
  non-zero exit code, returns `{:error, {stdout, exit_code}}`.
  """
  @spec parse_output(String.t(), non_neg_integer()) ::
          {:ok, map() | String.t()} | {:error, {String.t(), non_neg_integer()}}
  @impl true
  def parse_output(stdout, 0) do
    case Process.get(@mode_key, :list) do
      :list -> {:ok, parse_list(stdout)}
      :single -> {:ok, String.trim(stdout)}
    end
  end

  def parse_output(stdout, exit_code), do: {:error, {stdout, exit_code}}

  defp parse_list(stdout) do
    stdout
    |> String.split("\n", trim: true)
    |> Enum.reduce(%{}, fn line, acc ->
      case String.split(line, "=", parts: 2) do
        [name, value] -> Map.put(acc, name, value)
        _ -> acc
      end
    end)
  end
end
