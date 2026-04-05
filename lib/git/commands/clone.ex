defmodule Git.Commands.Clone do
  @moduledoc """
  Implements the `Git.Command` behaviour for `git clone`.

  Supports cloning a repository with optional `--depth` (shallow clone) and
  `--branch` flags. An optional target directory name may also be specified.
  """

  @behaviour Git.Command

  @type t :: %__MODULE__{
          url: String.t(),
          directory: String.t() | nil,
          depth: pos_integer() | nil,
          branch: String.t() | nil
        }

  defstruct url: nil,
            directory: nil,
            depth: nil,
            branch: nil

  @doc """
  Returns the argument list for `git clone`.

  Always includes the repository URL. Optional flags are appended in order:
  `--depth=N`, `--branch=NAME`, and a target directory when set.

  ## Examples

      iex> Git.Commands.Clone.args(%Git.Commands.Clone{url: "https://example.com/repo.git"})
      ["clone", "https://example.com/repo.git"]

      iex> Git.Commands.Clone.args(%Git.Commands.Clone{url: "https://example.com/repo.git", depth: 1})
      ["clone", "--depth=1", "https://example.com/repo.git"]

      iex> Git.Commands.Clone.args(%Git.Commands.Clone{url: "https://example.com/repo.git", branch: "main", depth: 1})
      ["clone", "--depth=1", "--branch=main", "https://example.com/repo.git"]

      iex> Git.Commands.Clone.args(%Git.Commands.Clone{url: "https://example.com/repo.git", directory: "my-repo"})
      ["clone", "https://example.com/repo.git", "my-repo"]

  """
  @spec args(t()) :: [String.t()]
  @impl true
  def args(%__MODULE__{url: url, depth: depth, branch: branch, directory: directory}) do
    flags =
      []
      |> maybe_add("--depth=#{depth}", not is_nil(depth))
      |> maybe_add("--branch=#{branch}", not is_nil(branch))

    positional = if is_binary(directory), do: [directory], else: []

    ["clone"] ++ flags ++ [url] ++ positional
  end

  @doc """
  Parses the output of `git clone`.

  On success (exit code 0), returns `{:ok, :done}`.
  On failure, returns `{:error, {stdout, exit_code}}`.
  """
  @spec parse_output(String.t(), non_neg_integer()) ::
          {:ok, :done} | {:error, {String.t(), non_neg_integer()}}
  @impl true
  def parse_output(_stdout, 0), do: {:ok, :done}
  def parse_output(stdout, exit_code), do: {:error, {stdout, exit_code}}

  defp maybe_add(list, _flag, false), do: list
  defp maybe_add(list, flag, true), do: list ++ [flag]
end
