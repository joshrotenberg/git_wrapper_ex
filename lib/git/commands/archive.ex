defmodule Git.Commands.Archive do
  @moduledoc """
  Implements the `Git.Command` behaviour for `git archive`.

  Creates an archive of files from a named tree. Supports tar, tar.gz,
  and zip formats.

  **Limitation:** The `output` option is currently required. When git archive
  runs without `--output`, it writes binary data to stdout which cannot be
  reliably captured as a string by `System.cmd/3`. When `output` is specified,
  git writes directly to the file and stdout is empty.
  """

  @behaviour Git.Command

  @type t :: %__MODULE__{
          ref: String.t(),
          format: String.t() | nil,
          output: String.t() | nil,
          prefix: String.t() | nil,
          paths: [String.t()],
          remote: String.t() | nil,
          worktree_attributes: boolean(),
          verbose: boolean()
        }

  defstruct ref: "HEAD",
            format: nil,
            output: nil,
            prefix: nil,
            paths: [],
            remote: nil,
            worktree_attributes: false,
            verbose: false

  @doc """
  Returns the argument list for `git archive`.

  The tree-ish ref is placed after all flags. Paths are appended after `--`.

  ## Examples

      iex> Git.Commands.Archive.args(%Git.Commands.Archive{})
      ["archive", "HEAD"]

      iex> Git.Commands.Archive.args(%Git.Commands.Archive{format: "zip", output: "out.zip"})
      ["archive", "--format=zip", "--output=out.zip", "HEAD"]

      iex> Git.Commands.Archive.args(%Git.Commands.Archive{prefix: "project/", paths: ["lib/"]})
      ["archive", "--prefix=project/", "HEAD", "--", "lib/"]

      iex> Git.Commands.Archive.args(%Git.Commands.Archive{verbose: true, worktree_attributes: true})
      ["archive", "-v", "--worktree-attributes", "HEAD"]

  """
  @spec args(t()) :: [String.t()]
  @impl true
  def args(%__MODULE__{} = command) do
    base = ["archive"]

    base
    |> maybe_add_flag(command.verbose, "-v")
    |> maybe_add_option(command.format, "--format=")
    |> maybe_add_option(command.output, "--output=")
    |> maybe_add_option(command.prefix, "--prefix=")
    |> maybe_add_option(command.remote, "--remote=")
    |> maybe_add_flag(command.worktree_attributes, "--worktree-attributes")
    |> Kernel.++([command.ref])
    |> maybe_add_paths(command.paths)
  end

  @doc """
  Parses the output of `git archive`.

  On success (exit code 0), returns `{:ok, :done}` since the archive
  content is written to the output file.
  On failure, returns `{:error, {stdout, exit_code}}`.
  """
  @spec parse_output(String.t(), non_neg_integer()) ::
          {:ok, :done} | {:error, {String.t(), non_neg_integer()}}
  @impl true
  def parse_output(_stdout, 0), do: {:ok, :done}
  def parse_output(stdout, exit_code), do: {:error, {stdout, exit_code}}

  defp maybe_add_flag(args, true, flag), do: args ++ [flag]
  defp maybe_add_flag(args, false, _flag), do: args

  defp maybe_add_option(args, nil, _prefix), do: args
  defp maybe_add_option(args, value, prefix), do: args ++ ["#{prefix}#{value}"]

  defp maybe_add_paths(args, []), do: args
  defp maybe_add_paths(args, paths), do: args ++ ["--"] ++ paths
end
