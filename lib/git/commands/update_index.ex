defmodule Git.Commands.UpdateIndex do
  @moduledoc """
  Implements the `Git.Command` behaviour for `git update-index`.

  Populates and modifies the index directly. `:cacheinfo` inserts a
  `{mode, object, path}` entry without a working-tree file (pairs with
  `write-tree`/`mktree` to assemble arbitrary trees), and the
  `:assume_unchanged` / `:skip_worktree` bits hide local changes to tracked
  files.

  `:index_info` reads the bulk index-info format on stdin, so that mode needs
  the default `Git.Runner.Forcola` runner; under `Git.Runner.SystemCmd` it
  returns `{:error, :stdin_unsupported}`.
  """

  @behaviour Git.Command

  @type cacheinfo :: {String.t(), String.t(), String.t()}

  @type t :: %__MODULE__{
          cacheinfo: [cacheinfo()],
          add: boolean(),
          remove: boolean(),
          refresh: boolean(),
          chmod: String.t() | nil,
          assume_unchanged: boolean(),
          skip_worktree: boolean(),
          index_info: boolean(),
          stdin: iodata() | nil,
          files: [String.t()]
        }

  defstruct cacheinfo: [],
            add: false,
            remove: false,
            refresh: false,
            chmod: nil,
            assume_unchanged: false,
            skip_worktree: false,
            index_info: false,
            stdin: nil,
            files: []

  @doc """
  Returns the argument list for `git update-index`.

  ## Examples

      iex> Git.Commands.UpdateIndex.args(%Git.Commands.UpdateIndex{add: true, files: ["a.txt"]})
      ["update-index", "--add", "--", "a.txt"]

      iex> Git.Commands.UpdateIndex.args(%Git.Commands.UpdateIndex{cacheinfo: [{"100644", "abc123", "f.txt"}]})
      ["update-index", "--cacheinfo", "100644,abc123,f.txt"]

      iex> Git.Commands.UpdateIndex.args(%Git.Commands.UpdateIndex{skip_worktree: true, files: ["cfg"]})
      ["update-index", "--skip-worktree", "--", "cfg"]

      iex> Git.Commands.UpdateIndex.args(%Git.Commands.UpdateIndex{index_info: true})
      ["update-index", "--index-info"]

  """
  @spec args(t()) :: [String.t()]
  @impl true
  def args(%__MODULE__{} = command) do
    ["update-index"]
    |> maybe_add(command.add, "--add")
    |> maybe_add(command.remove, "--remove")
    |> maybe_add(command.refresh, "--refresh")
    |> maybe_add(command.assume_unchanged, "--assume-unchanged")
    |> maybe_add(command.skip_worktree, "--skip-worktree")
    |> maybe_add(command.index_info, "--index-info")
    |> maybe_add_chmod(command.chmod)
    |> add_cacheinfo(command.cacheinfo)
    |> add_files(command.files)
  end

  @doc """
  Returns the `--index-info` stdin payload when set, otherwise `nil`.
  """
  @spec input(t()) :: iodata() | nil
  @impl true
  def input(%__MODULE__{index_info: true, stdin: stdin}) when not is_nil(stdin), do: stdin
  def input(%__MODULE__{}), do: nil

  @doc """
  Parses the output of `git update-index`.

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

  defp maybe_add_chmod(args, nil), do: args
  defp maybe_add_chmod(args, mode), do: args ++ ["--chmod=#{mode}"]

  defp add_cacheinfo(args, []), do: args

  defp add_cacheinfo(args, cacheinfo) do
    Enum.reduce(cacheinfo, args, fn {mode, object, path}, acc ->
      acc ++ ["--cacheinfo", "#{mode},#{object},#{path}"]
    end)
  end

  defp add_files(args, []), do: args
  defp add_files(args, files), do: args ++ ["--"] ++ files
end
