defmodule Git.Commands.LsFiles do
  @moduledoc """
  Implements the `Git.Command` behaviour for `git ls-files`.

  Lists information about files in the index and working tree.
  Supports filtering by cached, deleted, modified, untracked (others),
  ignored, staged, unmerged, and killed files.
  """

  @behaviour Git.Command

  @type t :: %__MODULE__{
          cached: boolean(),
          deleted: boolean(),
          modified: boolean(),
          others: boolean(),
          ignored: boolean(),
          stage: boolean(),
          unmerged: boolean(),
          killed: boolean(),
          exclude_standard: boolean(),
          exclude: String.t() | nil,
          exclude_from: String.t() | nil,
          error_unmatch: boolean(),
          full_name: boolean(),
          abbrev: boolean() | non_neg_integer() | nil,
          debug: boolean(),
          deduplicate: boolean(),
          paths: [String.t()]
        }

  defstruct cached: false,
            deleted: false,
            modified: false,
            others: false,
            ignored: false,
            stage: false,
            unmerged: false,
            killed: false,
            exclude_standard: false,
            exclude: nil,
            exclude_from: nil,
            error_unmatch: false,
            full_name: false,
            abbrev: nil,
            debug: false,
            deduplicate: false,
            paths: []

  @doc """
  Returns the argument list for `git ls-files`.

  Builds the argument list from the struct fields, appending boolean flags
  and string options as needed. Path patterns are appended after `--`.

  ## Examples

      iex> Git.Commands.LsFiles.args(%Git.Commands.LsFiles{})
      ["ls-files"]

      iex> Git.Commands.LsFiles.args(%Git.Commands.LsFiles{others: true, exclude_standard: true})
      ["ls-files", "--others", "--exclude-standard"]

      iex> Git.Commands.LsFiles.args(%Git.Commands.LsFiles{modified: true, paths: ["src/"]})
      ["ls-files", "--modified", "--", "src/"]

  """
  @spec args(t()) :: [String.t()]
  @impl true
  def args(%__MODULE__{} = command) do
    base = ["ls-files"]

    base
    |> maybe_add_flag(command.cached, "--cached")
    |> maybe_add_flag(command.deleted, "--deleted")
    |> maybe_add_flag(command.modified, "--modified")
    |> maybe_add_flag(command.others, "--others")
    |> maybe_add_flag(command.ignored, "--ignored")
    |> maybe_add_flag(command.stage, "--stage")
    |> maybe_add_flag(command.unmerged, "--unmerged")
    |> maybe_add_flag(command.killed, "--killed")
    |> maybe_add_flag(command.exclude_standard, "--exclude-standard")
    |> maybe_add_option("--exclude", command.exclude)
    |> maybe_add_option("--exclude-from", command.exclude_from)
    |> maybe_add_flag(command.error_unmatch, "--error-unmatch")
    |> maybe_add_flag(command.full_name, "--full-name")
    |> maybe_add_abbrev(command.abbrev)
    |> maybe_add_flag(command.debug, "--debug")
    |> maybe_add_flag(command.deduplicate, "--deduplicate")
    |> maybe_add_paths(command.paths)
  end

  @doc """
  Parses the output of `git ls-files`.

  On success (exit 0), returns `{:ok, list_of_file_paths}`.
  On failure, returns `{:error, {stdout, exit_code}}`.
  """
  @spec parse_output(String.t(), non_neg_integer()) ::
          {:ok, [String.t()]} | {:error, {String.t(), non_neg_integer()}}
  @impl true
  def parse_output(stdout, 0) do
    files =
      stdout
      |> String.split("\n", trim: true)
      |> Enum.map(&String.trim/1)

    {:ok, files}
  end

  def parse_output(stdout, exit_code), do: {:error, {stdout, exit_code}}

  defp maybe_add_flag(args, false, _flag), do: args
  defp maybe_add_flag(args, true, flag), do: args ++ [flag]

  defp maybe_add_option(args, _flag, nil), do: args
  defp maybe_add_option(args, flag, value), do: args ++ [flag, value]

  defp maybe_add_abbrev(args, nil), do: args
  defp maybe_add_abbrev(args, true), do: args ++ ["--abbrev"]
  defp maybe_add_abbrev(args, n) when is_integer(n), do: args ++ ["--abbrev=#{n}"]

  defp maybe_add_paths(args, []), do: args
  defp maybe_add_paths(args, paths), do: args ++ ["--"] ++ paths
end
