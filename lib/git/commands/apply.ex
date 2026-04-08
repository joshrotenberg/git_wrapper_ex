defmodule Git.Commands.Apply do
  @moduledoc """
  Implements the `Git.Command` behaviour for `git apply`.

  Applies a patch to files and/or to the index. Supports checking whether a
  patch applies cleanly, showing diffstat/summary, applying to the index or
  working tree, reverse application, and three-way merges.
  """

  @behaviour Git.Command

  @mode_key :__git_apply_mode__

  @type t :: %__MODULE__{
          patch: String.t() | nil,
          check: boolean(),
          stat: boolean(),
          summary: boolean(),
          cached: boolean(),
          index: boolean(),
          reverse: boolean(),
          three_way: boolean(),
          verbose: boolean()
        }

  defstruct patch: nil,
            check: false,
            stat: false,
            summary: false,
            cached: false,
            index: false,
            reverse: false,
            three_way: false,
            verbose: false

  @doc """
  Returns the argument list for `git apply`.

  ## Examples

      iex> Git.Commands.Apply.args(%Git.Commands.Apply{patch: "fix.patch"})
      ["apply", "fix.patch"]

      iex> Git.Commands.Apply.args(%Git.Commands.Apply{patch: "fix.patch", check: true})
      ["apply", "--check", "fix.patch"]

      iex> Git.Commands.Apply.args(%Git.Commands.Apply{patch: "fix.patch", stat: true, summary: true})
      ["apply", "--stat", "--summary", "fix.patch"]

      iex> Git.Commands.Apply.args(%Git.Commands.Apply{patch: "fix.patch", cached: true})
      ["apply", "--cached", "fix.patch"]

      iex> Git.Commands.Apply.args(%Git.Commands.Apply{patch: "fix.patch", reverse: true})
      ["apply", "--reverse", "fix.patch"]

      iex> Git.Commands.Apply.args(%Git.Commands.Apply{patch: "fix.patch", three_way: true})
      ["apply", "--3way", "fix.patch"]

  """
  @spec args(t()) :: [String.t()]
  @impl true
  def args(%__MODULE__{} = command) do
    info_mode = command.stat or command.summary or command.check
    Process.put(@mode_key, info_mode)

    ["apply"]
    |> maybe_add(command.check, "--check")
    |> maybe_add(command.stat, "--stat")
    |> maybe_add(command.summary, "--summary")
    |> maybe_add(command.cached, "--cached")
    |> maybe_add(command.index, "--index")
    |> maybe_add(command.reverse, "--reverse")
    |> maybe_add(command.three_way, "--3way")
    |> maybe_add(command.verbose, "--verbose")
    |> maybe_add_patch(command.patch)
  end

  @doc """
  Parses the output of `git apply`.

  For stat, summary, or check modes, returns `{:ok, output}` with the
  informational text. For normal apply operations, returns `{:ok, :done}`.
  On failure, returns `{:error, {stdout, exit_code}}`.
  """
  @spec parse_output(String.t(), non_neg_integer()) ::
          {:ok, :done} | {:ok, String.t()} | {:error, {String.t(), non_neg_integer()}}
  @impl true
  def parse_output(stdout, 0) do
    if Process.get(@mode_key, false) do
      {:ok, stdout}
    else
      {:ok, :done}
    end
  end

  def parse_output(stdout, exit_code), do: {:error, {stdout, exit_code}}

  defp maybe_add(args, true, flag), do: args ++ [flag]
  defp maybe_add(args, false, _flag), do: args

  defp maybe_add_patch(args, nil), do: args
  defp maybe_add_patch(args, patch), do: args ++ [patch]
end
