defmodule Git.Commands.LsRemote do
  @moduledoc """
  Implements the `Git.Command` behaviour for `git ls-remote`.

  Lists references in a remote repository. Parses the output into
  a list of `Git.LsRemoteEntry` structs containing the SHA and ref name.

  Symref lines (from `--symref`) are included with `sha` set to `nil`.
  """

  @behaviour Git.Command

  alias Git.LsRemoteEntry

  @type t :: %__MODULE__{
          remote: String.t() | nil,
          heads: boolean(),
          tags: boolean(),
          refs: String.t() | nil,
          sort: String.t() | nil,
          symref: boolean(),
          quiet: boolean(),
          exit_code: boolean()
        }

  defstruct remote: nil,
            heads: false,
            tags: false,
            refs: nil,
            sort: nil,
            symref: false,
            quiet: false,
            exit_code: false

  @doc """
  Returns the argument list for `git ls-remote`.

  The remote name/URL is placed after flags. The refs pattern, if given,
  is appended at the end.

  ## Examples

      iex> Git.Commands.LsRemote.args(%Git.Commands.LsRemote{})
      ["ls-remote"]

      iex> Git.Commands.LsRemote.args(%Git.Commands.LsRemote{heads: true, tags: true})
      ["ls-remote", "--heads", "--tags"]

      iex> Git.Commands.LsRemote.args(%Git.Commands.LsRemote{remote: "origin", refs: "refs/heads/main"})
      ["ls-remote", "origin", "refs/heads/main"]

      iex> Git.Commands.LsRemote.args(%Git.Commands.LsRemote{symref: true, sort: "version:refname"})
      ["ls-remote", "--symref", "--sort=version:refname"]

  """
  @spec args(t()) :: [String.t()]
  @impl true
  def args(%__MODULE__{} = command) do
    base = ["ls-remote"]

    base
    |> maybe_add_flag(command.heads, "--heads")
    |> maybe_add_flag(command.tags, "--tags")
    |> maybe_add_flag(command.symref, "--symref")
    |> maybe_add_flag(command.quiet, "-q")
    |> maybe_add_flag(command.exit_code, "--exit-code")
    |> maybe_add_option(command.sort, "--sort=")
    |> maybe_add_remote(command.remote)
    |> maybe_add_refs(command.refs)
  end

  @doc """
  Parses the output of `git ls-remote`.

  On success (exit code 0), parses tab-separated `SHA\\tref` lines into
  a list of `Git.LsRemoteEntry` structs. Symref lines (prefixed with
  `ref:`) are included with `sha` set to `nil`.

  Exit code 2 with `--exit-code` means no matching refs and returns
  `{:ok, []}`.

  Returns `{:error, {stdout, exit_code}}` on other failures.
  """
  @spec parse_output(String.t(), non_neg_integer()) ::
          {:ok, [LsRemoteEntry.t()]} | {:error, {String.t(), non_neg_integer()}}
  @impl true
  def parse_output(stdout, 0), do: {:ok, parse_lines(stdout)}
  def parse_output(_stdout, 2), do: {:ok, []}
  def parse_output(stdout, exit_code), do: {:error, {stdout, exit_code}}

  defp parse_lines(stdout) do
    stdout
    |> String.split("\n", trim: true)
    |> Enum.map(&parse_line/1)
  end

  defp parse_line(line) do
    case String.split(line, "\t", parts: 2) do
      ["ref: " <> symref_target, ref] ->
        %LsRemoteEntry{sha: nil, ref: "ref: #{symref_target}\t#{ref}"}

      [sha, ref] ->
        %LsRemoteEntry{sha: sha, ref: ref}

      _ ->
        %LsRemoteEntry{sha: nil, ref: line}
    end
  end

  defp maybe_add_flag(args, true, flag), do: args ++ [flag]
  defp maybe_add_flag(args, false, _flag), do: args

  defp maybe_add_option(args, nil, _prefix), do: args
  defp maybe_add_option(args, value, prefix), do: args ++ ["#{prefix}#{value}"]

  defp maybe_add_remote(args, nil), do: args
  defp maybe_add_remote(args, remote), do: args ++ [remote]

  defp maybe_add_refs(args, nil), do: args
  defp maybe_add_refs(args, refs), do: args ++ [refs]
end
