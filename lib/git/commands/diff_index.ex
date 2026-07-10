defmodule Git.Commands.DiffIndex do
  @moduledoc """
  Implements the `Git.Command` behaviour for `git diff-index`.

  Compares a tree-ish to the index and the working tree (or, with `:cached`,
  to the index only). Output is requested with `--raw -z` and parsed into
  `Git.DiffRawEntry` structs.

  With `:quiet` the command runs as a dirty-check: git exits 1 when there are
  differences, which is treated as a signal rather than an error. In that mode
  the wrapper returns a boolean instead of a list of entries.
  """

  @behaviour Git.Command

  alias Git.DiffRawEntry

  @type t :: %__MODULE__{
          tree_ish: String.t(),
          cached: boolean(),
          quiet: boolean()
        }

  defstruct tree_ish: "HEAD",
            cached: false,
            quiet: false

  # Process dictionary key used to communicate the output mode from args/1 to
  # parse_output/2 (which only receives stdout and the exit code).
  @mode_key :__git_diff_index_mode__

  @doc """
  Returns the argument list for `git diff-index`.

  Options:
  - `:tree_ish` - the tree-ish to compare against (default `"HEAD"`)
  - `:cached` - adds `--cached` to compare against the index only
  - `:quiet` - adds `--quiet` for a dirty-check (exit 1 = differences)

  ## Examples

      iex> Git.Commands.DiffIndex.args(%Git.Commands.DiffIndex{})
      ["diff-index", "--raw", "-z", "HEAD"]

      iex> Git.Commands.DiffIndex.args(%Git.Commands.DiffIndex{cached: true})
      ["diff-index", "--raw", "-z", "--cached", "HEAD"]

      iex> Git.Commands.DiffIndex.args(%Git.Commands.DiffIndex{quiet: true})
      ["diff-index", "--quiet", "HEAD"]

  """
  @spec args(t()) :: [String.t()]
  @impl true
  def args(%__MODULE__{} = command) do
    Process.put(@mode_key, if(command.quiet, do: :quiet, else: :raw))

    mode_flags = if command.quiet, do: ["--quiet"], else: ["--raw", "-z"]

    (["diff-index"] ++ mode_flags)
    |> maybe_add_flag(command.cached, "--cached")
    |> Kernel.++([command.tree_ish])
  end

  @doc """
  Parses the output of `git diff-index`.

  In raw mode (the default), returns `{:ok, [Git.DiffRawEntry.t()]}` on exit
  code 0 and `{:error, {stdout, exit_code}}` otherwise.

  In quiet mode, exit code 0 means no differences (`{:ok, false}`) and exit
  code 1 means differences were found (`{:ok, true}`). Any other exit code is
  a real git error and returns `{:error, {stdout, exit_code}}`.
  """
  @spec parse_output(String.t(), non_neg_integer()) ::
          {:ok, [DiffRawEntry.t()] | boolean()}
          | {:error, {String.t(), non_neg_integer()}}
  @impl true
  def parse_output(stdout, exit_code) do
    case Process.get(@mode_key, :raw) do
      :quiet -> parse_quiet(stdout, exit_code)
      :raw -> parse_raw(stdout, exit_code)
    end
  end

  defp parse_quiet(_stdout, 0), do: {:ok, false}
  defp parse_quiet(_stdout, 1), do: {:ok, true}
  defp parse_quiet(stdout, exit_code), do: {:error, {stdout, exit_code}}

  defp parse_raw(stdout, 0), do: {:ok, DiffRawEntry.parse(stdout)}
  defp parse_raw(stdout, exit_code), do: {:error, {stdout, exit_code}}

  defp maybe_add_flag(args, true, flag), do: args ++ [flag]
  defp maybe_add_flag(args, false, _flag), do: args
end
