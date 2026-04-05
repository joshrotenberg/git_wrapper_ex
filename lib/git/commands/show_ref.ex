defmodule Git.Commands.ShowRef do
  @moduledoc """
  Implements the `Git.Command` behaviour for `git show-ref`.

  Lists references in a local repository. Supports filtering by heads or tags,
  verifying specific refs, abbreviated hashes, and dereferencing tags.

  Uses the process dictionary to communicate the output mode from `args/1`
  to `parse_output/2`.
  """

  @behaviour Git.Command

  @type t :: %__MODULE__{
          heads: boolean(),
          tags: boolean(),
          verify: boolean(),
          hash: boolean() | non_neg_integer(),
          abbrev: non_neg_integer() | nil,
          dereference: boolean(),
          quiet: boolean(),
          exclude_existing: boolean(),
          patterns: [String.t()]
        }

  defstruct heads: false,
            tags: false,
            verify: false,
            hash: false,
            abbrev: nil,
            dereference: false,
            quiet: false,
            exclude_existing: false,
            patterns: []

  @mode_key :__git_show_ref_mode__

  @doc """
  Returns the argument list for `git show-ref`.

  ## Examples

      iex> Git.Commands.ShowRef.args(%Git.Commands.ShowRef{})
      ["show-ref"]

      iex> Git.Commands.ShowRef.args(%Git.Commands.ShowRef{heads: true})
      ["show-ref", "--heads"]

      iex> Git.Commands.ShowRef.args(%Git.Commands.ShowRef{tags: true})
      ["show-ref", "--tags"]

      iex> Git.Commands.ShowRef.args(%Git.Commands.ShowRef{verify: true, patterns: ["refs/heads/main"]})
      ["show-ref", "--verify", "refs/heads/main"]

      iex> Git.Commands.ShowRef.args(%Git.Commands.ShowRef{hash: true})
      ["show-ref", "--hash"]

      iex> Git.Commands.ShowRef.args(%Git.Commands.ShowRef{hash: 8})
      ["show-ref", "--hash=8"]

      iex> Git.Commands.ShowRef.args(%Git.Commands.ShowRef{abbrev: 8})
      ["show-ref", "--abbrev=8"]

      iex> Git.Commands.ShowRef.args(%Git.Commands.ShowRef{dereference: true})
      ["show-ref", "-d"]

      iex> Git.Commands.ShowRef.args(%Git.Commands.ShowRef{quiet: true, verify: true, patterns: ["refs/heads/main"]})
      ["show-ref", "--verify", "-q", "refs/heads/main"]

  """
  @spec args(t()) :: [String.t()]
  @impl true
  def args(%__MODULE__{} = command) do
    mode =
      cond do
        command.quiet and command.verify -> :quiet_verify
        command.verify -> :verify
        command.hash != false -> :hash
        true -> :default
      end

    Process.put(@mode_key, mode)

    ["show-ref"]
    |> maybe_add_flag(command.heads, "--heads")
    |> maybe_add_flag(command.tags, "--tags")
    |> maybe_add_flag(command.verify, "--verify")
    |> maybe_add_hash(command.hash)
    |> maybe_add_abbrev(command.abbrev)
    |> maybe_add_flag(command.dereference, "-d")
    |> maybe_add_flag(command.quiet, "-q")
    |> maybe_add_flag(command.exclude_existing, "--exclude-existing")
    |> maybe_add_patterns(command.patterns)
  end

  @doc """
  Parses the output of `git show-ref`.

  - Default mode (exit 0): parses "sha ref" lines into `{:ok, [%{sha, ref}]}`
  - Hash mode (exit 0): returns `{:ok, [String.t()]}` of SHA values
  - Verify mode (exit 0): parses "sha ref" lines; (exit 1/128): `{:ok, []}`
  - Quiet+verify mode (exit 0): `{:ok, true}`; (exit 1/128): `{:ok, false}`
  - Exit code 1 without verify: no matching refs = `{:ok, []}`
  """
  @spec parse_output(String.t(), non_neg_integer()) ::
          {:ok, term()} | {:error, {String.t(), non_neg_integer()}}
  @impl true
  def parse_output(stdout, exit_code) do
    mode = Process.get(@mode_key, :default)

    case {mode, exit_code} do
      {:quiet_verify, 0} ->
        {:ok, true}

      {:quiet_verify, exit} when exit in [1, 128] ->
        {:ok, false}

      {:verify, 0} ->
        entries =
          stdout
          |> String.split("\n", trim: true)
          |> Enum.map(&parse_ref_line/1)
          |> Enum.reject(&is_nil/1)

        {:ok, entries}

      {:verify, exit} when exit in [1, 128] ->
        {:ok, []}

      {:hash, 0} ->
        shas =
          stdout
          |> String.split("\n", trim: true)
          |> Enum.map(&String.trim/1)

        {:ok, shas}

      {:default, 0} ->
        entries =
          stdout
          |> String.split("\n", trim: true)
          |> Enum.map(&parse_ref_line/1)
          |> Enum.reject(&is_nil/1)

        {:ok, entries}

      {_mode, 1} ->
        {:ok, []}

      _ ->
        {:error, {stdout, exit_code}}
    end
  end

  defp parse_ref_line(line) do
    case String.split(String.trim(line), ~r/\s+/, parts: 2) do
      [sha, ref] -> %{sha: sha, ref: ref}
      _ -> nil
    end
  end

  defp maybe_add_flag(args, true, flag), do: args ++ [flag]
  defp maybe_add_flag(args, false, _flag), do: args

  defp maybe_add_hash(args, true), do: args ++ ["--hash"]
  defp maybe_add_hash(args, n) when is_integer(n), do: args ++ ["--hash=#{n}"]
  defp maybe_add_hash(args, false), do: args

  defp maybe_add_abbrev(args, nil), do: args
  defp maybe_add_abbrev(args, n) when is_integer(n), do: args ++ ["--abbrev=#{n}"]

  defp maybe_add_patterns(args, []), do: args
  defp maybe_add_patterns(args, patterns), do: args ++ patterns
end
