defmodule Git.Commands.LsTree do
  @moduledoc """
  Implements the `Git.Command` behaviour for `git ls-tree`.

  Lists the contents of a tree object, showing the mode, type, name,
  and optionally size of each object. Parses output into a list of
  `Git.TreeEntry` structs or plain path strings when `--name-only` is used.
  """

  @behaviour Git.Command

  alias Git.TreeEntry

  @type t :: %__MODULE__{
          ref: String.t(),
          recursive: boolean(),
          tree_only: boolean(),
          long: boolean(),
          name_only: boolean(),
          abbrev: non_neg_integer() | nil,
          full_name: boolean(),
          full_tree: boolean(),
          path: String.t() | nil
        }

  defstruct ref: "HEAD",
            recursive: false,
            tree_only: false,
            long: false,
            name_only: false,
            abbrev: nil,
            full_name: false,
            full_tree: false,
            path: nil

  @doc """
  Returns the argument list for `git ls-tree`.

  The tree-ish ref is placed after flags. An optional path filter is
  appended after `--`.

  ## Examples

      iex> Git.Commands.LsTree.args(%Git.Commands.LsTree{})
      ["ls-tree", "HEAD"]

      iex> Git.Commands.LsTree.args(%Git.Commands.LsTree{recursive: true, long: true})
      ["ls-tree", "-r", "-l", "HEAD"]

      iex> Git.Commands.LsTree.args(%Git.Commands.LsTree{name_only: true, ref: "main"})
      ["ls-tree", "--name-only", "main"]

      iex> Git.Commands.LsTree.args(%Git.Commands.LsTree{path: "lib/"})
      ["ls-tree", "HEAD", "--", "lib/"]

      iex> Git.Commands.LsTree.args(%Git.Commands.LsTree{abbrev: 8})
      ["ls-tree", "--abbrev=8", "HEAD"]

  """
  @spec args(t()) :: [String.t()]
  @impl true
  def args(%__MODULE__{} = command) do
    base = ["ls-tree"]

    base
    |> maybe_add_flag(command.recursive, "-r")
    |> maybe_add_flag(command.tree_only, "-d")
    |> maybe_add_flag(command.long, "-l")
    |> maybe_add_flag(command.name_only, "--name-only")
    |> maybe_add_abbrev(command.abbrev)
    |> maybe_add_flag(command.full_name, "--full-name")
    |> maybe_add_flag(command.full_tree, "--full-tree")
    |> Kernel.++([command.ref])
    |> maybe_add_path(command.path)
  end

  @doc """
  Parses the output of `git ls-tree`.

  On success (exit code 0), parses each line into a `Git.TreeEntry` struct.
  When `name_only` mode was used (detected by the absence of tabs in output),
  returns `{:ok, [String.t()]}` with just the path names.

  The default format is `mode type sha\\tpath`.
  With `--long`, the format is `mode type sha    size\\tpath` where size
  is right-justified with spaces.

  Returns `{:error, {stdout, exit_code}}` on failure.
  """
  @spec parse_output(String.t(), non_neg_integer()) ::
          {:ok, [TreeEntry.t()] | [String.t()]} | {:error, {String.t(), non_neg_integer()}}
  @impl true
  def parse_output(stdout, 0) do
    lines = String.split(stdout, "\n", trim: true)

    case lines do
      [] ->
        {:ok, []}

      [first | _] ->
        if String.contains?(first, "\t") do
          {:ok, Enum.map(lines, &parse_tree_line/1)}
        else
          {:ok, Enum.map(lines, &String.trim/1)}
        end
    end
  end

  def parse_output(stdout, exit_code), do: {:error, {stdout, exit_code}}

  defp parse_tree_line(line) do
    # Format: "mode type sha\tpath" or "mode type sha    size\tpath"
    [meta, path] = String.split(line, "\t", parts: 2)
    parts = String.split(meta, ~r/\s+/, trim: true)

    case parts do
      [mode, type, sha, size] ->
        %TreeEntry{
          mode: mode,
          type: parse_type(type),
          sha: sha,
          path: path,
          size: parse_size(size)
        }

      [mode, type, sha] ->
        %TreeEntry{
          mode: mode,
          type: parse_type(type),
          sha: sha,
          path: path,
          size: nil
        }
    end
  end

  defp parse_type("blob"), do: :blob
  defp parse_type("tree"), do: :tree
  defp parse_type("commit"), do: :commit
  defp parse_type(other), do: String.to_atom(other)

  defp parse_size("-"), do: nil

  defp parse_size(size_str) do
    case Integer.parse(size_str) do
      {size, _} -> size
      :error -> nil
    end
  end

  defp maybe_add_flag(args, true, flag), do: args ++ [flag]
  defp maybe_add_flag(args, false, _flag), do: args

  defp maybe_add_abbrev(args, nil), do: args
  defp maybe_add_abbrev(args, n) when is_integer(n), do: args ++ ["--abbrev=#{n}"]

  defp maybe_add_path(args, nil), do: args
  defp maybe_add_path(args, path), do: args ++ ["--", path]
end
