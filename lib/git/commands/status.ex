defmodule Git.Commands.Status do
  @moduledoc """
  Implements the `Git.Command` behaviour for `git status`.

  Uses `--porcelain=v1 -b` for machine-readable output with branch information.
  The porcelain v1 format and the `-b` flag are always present so the parser in
  `Git.Status` keeps working.
  """

  @behaviour Git.Command

  @type untracked_files :: :no | :normal | :all

  @type t :: %__MODULE__{
          untracked_files: untracked_files() | nil,
          ignored: boolean(),
          ignore_submodules: String.t() | nil,
          renames: boolean(),
          no_renames: boolean(),
          pathspec: [String.t()]
        }

  defstruct [
    :untracked_files,
    :ignore_submodules,
    ignored: false,
    renames: false,
    no_renames: false,
    pathspec: []
  ]

  @doc """
  Returns the argument list for `git status`.

  The base is always `["status", "--porcelain=v1", "-b"]`. Additional flags are
  appended based on the struct fields, and any `:pathspec` entries are added last
  after a `--` separator.
  """
  @spec args(t()) :: [String.t()]
  @impl true
  def args(%__MODULE__{} = command) do
    ["status", "--porcelain=v1", "-b"]
    |> maybe_add_untracked_files(command.untracked_files)
    |> maybe_add_flag(command.ignored, "--ignored")
    |> maybe_add("--ignore-submodules=", command.ignore_submodules)
    |> maybe_add_flag(command.renames, "--renames")
    |> maybe_add_flag(command.no_renames, "--no-renames")
    |> maybe_add_pathspec(command.pathspec)
  end

  @doc """
  Parses the output of `git status --porcelain=v1 -b`.

  On success (exit code 0), returns `{:ok, %Git.Status{}}`.
  On failure, returns `{:error, {stdout, exit_code}}`.
  """
  @spec parse_output(String.t(), non_neg_integer()) ::
          {:ok, Git.Status.t()} | {:error, {String.t(), non_neg_integer()}}
  @impl true
  def parse_output(stdout, 0) do
    {:ok, Git.Status.parse(stdout)}
  end

  def parse_output(stdout, exit_code) do
    {:error, {stdout, exit_code}}
  end

  defp maybe_add(args, _flag, nil), do: args
  defp maybe_add(args, flag, value), do: args ++ ["#{flag}#{value}"]

  defp maybe_add_flag(args, true, flag), do: args ++ [flag]
  defp maybe_add_flag(args, false, _flag), do: args

  defp maybe_add_untracked_files(args, nil), do: args

  defp maybe_add_untracked_files(args, mode) when mode in [:no, :normal, :all],
    do: args ++ ["--untracked-files=#{mode}"]

  defp maybe_add_pathspec(args, []), do: args
  defp maybe_add_pathspec(args, paths) when is_list(paths), do: args ++ ["--" | paths]
end
