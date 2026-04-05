defmodule Git.Commands.Rm do
  @moduledoc """
  Implements the `Git.Command` behaviour for `git rm`.

  Supports removing tracked files from the index and optionally from the
  working tree, with options for cached-only removal, force, recursive,
  dry-run, quiet output, and pathspec-from-file.
  """

  @behaviour Git.Command

  @type t :: %__MODULE__{
          files: [String.t()],
          cached: boolean(),
          force: boolean(),
          recursive: boolean(),
          dry_run: boolean(),
          quiet: boolean(),
          pathspec_from_file: String.t() | nil
        }

  defstruct files: [],
            cached: false,
            force: false,
            recursive: false,
            dry_run: false,
            quiet: false,
            pathspec_from_file: nil

  @doc """
  Returns the argument list for `git rm`.

  Builds `git rm [options] [--] <files>` from the struct fields.

  ## Examples

      iex> Git.Commands.Rm.args(%Git.Commands.Rm{files: ["a.txt"]})
      ["rm", "a.txt"]

      iex> Git.Commands.Rm.args(%Git.Commands.Rm{files: ["a.txt"], cached: true})
      ["rm", "--cached", "a.txt"]

      iex> Git.Commands.Rm.args(%Git.Commands.Rm{files: ["dir/"], recursive: true, force: true})
      ["rm", "-f", "-r", "dir/"]

      iex> Git.Commands.Rm.args(%Git.Commands.Rm{files: [], pathspec_from_file: "paths.txt"})
      ["rm", "--pathspec-from-file", "paths.txt"]

  """
  @spec args(t()) :: [String.t()]
  @impl true
  def args(%__MODULE__{} = command) do
    ["rm"]
    |> maybe_add(command.cached, "--cached")
    |> maybe_add(command.force, "-f")
    |> maybe_add(command.recursive, "-r")
    |> maybe_add(command.dry_run, "-n")
    |> maybe_add(command.quiet, "-q")
    |> maybe_add_option(command.pathspec_from_file, "--pathspec-from-file")
    |> Kernel.++(command.files)
  end

  @doc """
  Parses the output of `git rm`.

  On success (exit code 0), returns `{:ok, :done}`. On failure, returns
  `{:error, {stdout, exit_code}}`.
  """
  @spec parse_output(String.t(), non_neg_integer()) ::
          {:ok, :done} | {:error, {String.t(), non_neg_integer()}}
  @impl true
  def parse_output(_stdout, 0), do: {:ok, :done}
  def parse_output(stdout, exit_code), do: {:error, {stdout, exit_code}}

  defp maybe_add(args, true, flag), do: args ++ [flag]
  defp maybe_add(args, false, _flag), do: args

  defp maybe_add_option(args, nil, _flag), do: args
  defp maybe_add_option(args, value, flag) when is_binary(value), do: args ++ [flag, value]
end
