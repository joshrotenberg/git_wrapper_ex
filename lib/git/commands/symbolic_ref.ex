defmodule Git.Commands.SymbolicRef do
  @moduledoc """
  Implements the `Git.Command` behaviour for `git symbolic-ref`.

  Reads, creates, or deletes symbolic refs. A symbolic ref is a ref
  that points to another ref (e.g., HEAD typically points to a branch).
  """

  @behaviour Git.Command

  @type t :: %__MODULE__{
          ref: String.t() | nil,
          target: String.t() | nil,
          short: boolean(),
          delete: boolean(),
          quiet: boolean()
        }

  defstruct ref: nil,
            target: nil,
            short: false,
            delete: false,
            quiet: false

  @doc """
  Returns the argument list for `git symbolic-ref`.

  ## Examples

      iex> Git.Commands.SymbolicRef.args(%Git.Commands.SymbolicRef{ref: "HEAD"})
      ["symbolic-ref", "HEAD"]

      iex> Git.Commands.SymbolicRef.args(%Git.Commands.SymbolicRef{ref: "HEAD", short: true})
      ["symbolic-ref", "--short", "HEAD"]

      iex> Git.Commands.SymbolicRef.args(%Git.Commands.SymbolicRef{ref: "HEAD", target: "refs/heads/main"})
      ["symbolic-ref", "HEAD", "refs/heads/main"]

      iex> Git.Commands.SymbolicRef.args(%Git.Commands.SymbolicRef{ref: "HEAD", delete: true})
      ["symbolic-ref", "--delete", "HEAD"]

      iex> Git.Commands.SymbolicRef.args(%Git.Commands.SymbolicRef{ref: "HEAD", quiet: true})
      ["symbolic-ref", "--quiet", "HEAD"]

  """
  @spec args(t()) :: [String.t()]
  @impl true
  def args(%__MODULE__{} = command) do
    ["symbolic-ref"]
    |> maybe_add_flag(command.short, "--short")
    |> maybe_add_flag(command.delete, "--delete")
    |> maybe_add_flag(command.quiet, "--quiet")
    |> maybe_add_ref(command.ref)
    |> maybe_add_target(command.target)
  end

  @doc """
  Parses the output of `git symbolic-ref`.

  For reads (exit code 0 with output), returns `{:ok, ref_string}` trimmed.
  For writes and deletes (exit code 0 with no output), returns `{:ok, :done}`.
  On failure, returns `{:error, {stdout, exit_code}}`.
  """
  @spec parse_output(String.t(), non_neg_integer()) ::
          {:ok, String.t() | :done} | {:error, {String.t(), non_neg_integer()}}
  @impl true
  def parse_output(stdout, 0) do
    case String.trim(stdout) do
      "" -> {:ok, :done}
      ref -> {:ok, ref}
    end
  end

  def parse_output(stdout, exit_code), do: {:error, {stdout, exit_code}}

  defp maybe_add_flag(args, true, flag), do: args ++ [flag]
  defp maybe_add_flag(args, false, _flag), do: args

  defp maybe_add_ref(args, nil), do: args
  defp maybe_add_ref(args, ref), do: args ++ [ref]

  defp maybe_add_target(args, nil), do: args
  defp maybe_add_target(args, target), do: args ++ [target]
end
