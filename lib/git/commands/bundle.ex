defmodule Git.Commands.Bundle do
  @moduledoc """
  Implements the `Git.Command` behaviour for `git bundle`.

  Supports creating, verifying, listing heads of, and unbundling git bundles.
  Uses the process dictionary to communicate the operation mode from `args/1`
  to `parse_output/2`.
  """

  @behaviour Git.Command

  @type t :: %__MODULE__{
          create: String.t() | nil,
          verify: String.t() | nil,
          list_heads: String.t() | nil,
          unbundle: String.t() | nil,
          rev: String.t() | nil,
          quiet: boolean(),
          progress: boolean(),
          all: boolean()
        }

  defstruct create: nil,
            verify: nil,
            list_heads: nil,
            unbundle: nil,
            rev: nil,
            quiet: false,
            progress: false,
            all: false

  @mode_key :__git_bundle_mode__

  @doc """
  Returns the argument list for `git bundle`.

  ## Examples

      iex> Git.Commands.Bundle.args(%Git.Commands.Bundle{create: "/tmp/test.bundle", rev: "HEAD"})
      ["bundle", "create", "/tmp/test.bundle", "HEAD"]

      iex> Git.Commands.Bundle.args(%Git.Commands.Bundle{create: "/tmp/test.bundle", all: true})
      ["bundle", "create", "/tmp/test.bundle", "--all"]

      iex> Git.Commands.Bundle.args(%Git.Commands.Bundle{verify: "/tmp/test.bundle"})
      ["bundle", "verify", "/tmp/test.bundle"]

      iex> Git.Commands.Bundle.args(%Git.Commands.Bundle{list_heads: "/tmp/test.bundle"})
      ["bundle", "list-heads", "/tmp/test.bundle"]

      iex> Git.Commands.Bundle.args(%Git.Commands.Bundle{unbundle: "/tmp/test.bundle"})
      ["bundle", "unbundle", "/tmp/test.bundle"]

      iex> Git.Commands.Bundle.args(%Git.Commands.Bundle{create: "/tmp/test.bundle", rev: "HEAD", quiet: true})
      ["bundle", "create", "-q", "/tmp/test.bundle", "HEAD"]

  """
  @spec args(t()) :: [String.t()]
  @impl true
  def args(%__MODULE__{create: path} = command) when is_binary(path) do
    Process.put(@mode_key, :create)

    base = ["bundle", "create"]

    base
    |> maybe_add_flag(command.quiet, "-q")
    |> maybe_add_flag(command.progress, "--progress")
    |> Kernel.++([path])
    |> maybe_add_rev(command.rev, command.all)
  end

  def args(%__MODULE__{verify: path}) when is_binary(path) do
    Process.put(@mode_key, :verify)
    ["bundle", "verify", path]
  end

  def args(%__MODULE__{list_heads: path}) when is_binary(path) do
    Process.put(@mode_key, :list_heads)
    ["bundle", "list-heads", path]
  end

  def args(%__MODULE__{unbundle: path}) when is_binary(path) do
    Process.put(@mode_key, :unbundle)
    ["bundle", "unbundle", path]
  end

  @doc """
  Parses the output of `git bundle`.

  - create (exit 0): `{:ok, :done}`
  - verify (exit 0): `{:ok, %{valid: true, raw: stdout}}`
  - verify (exit 1): `{:ok, %{valid: false, raw: stdout}}`
  - list-heads (exit 0): `{:ok, [%{sha: String.t(), ref: String.t()}]}`
  - unbundle (exit 0): `{:ok, :done}`
  """
  @spec parse_output(String.t(), non_neg_integer()) ::
          {:ok, term()} | {:error, {String.t(), non_neg_integer()}}
  @impl true
  def parse_output(stdout, exit_code) do
    mode = Process.get(@mode_key, :create)

    case {mode, exit_code} do
      {:create, 0} ->
        {:ok, :done}

      {:verify, 0} ->
        {:ok, %{valid: true, raw: stdout}}

      {:verify, 1} ->
        {:ok, %{valid: false, raw: stdout}}

      {:list_heads, 0} ->
        entries =
          stdout
          |> String.split("\n", trim: true)
          |> Enum.map(&parse_ref_line/1)
          |> Enum.reject(&is_nil/1)

        {:ok, entries}

      {:unbundle, 0} ->
        {:ok, :done}

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

  defp maybe_add_rev(args, nil, true), do: args ++ ["--all"]
  defp maybe_add_rev(args, rev, _all) when is_binary(rev), do: args ++ [rev]
  defp maybe_add_rev(args, nil, false), do: args
end
