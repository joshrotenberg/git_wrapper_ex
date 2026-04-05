defmodule Git.Commands.VerifyCommit do
  @moduledoc """
  Implements the `Git.Command` behaviour for `git verify-commit`.

  Verifies the GPG signature of a commit object.
  """

  @behaviour Git.Command

  @type t :: %__MODULE__{
          commit: String.t() | nil,
          verbose: boolean(),
          raw: boolean()
        }

  defstruct commit: nil,
            verbose: false,
            raw: false

  @doc """
  Returns the argument list for `git verify-commit`.

  ## Examples

      iex> Git.Commands.VerifyCommit.args(%Git.Commands.VerifyCommit{commit: "HEAD"})
      ["verify-commit", "HEAD"]

      iex> Git.Commands.VerifyCommit.args(%Git.Commands.VerifyCommit{commit: "HEAD", verbose: true})
      ["verify-commit", "-v", "HEAD"]

      iex> Git.Commands.VerifyCommit.args(%Git.Commands.VerifyCommit{commit: "HEAD", raw: true})
      ["verify-commit", "--raw", "HEAD"]

      iex> Git.Commands.VerifyCommit.args(%Git.Commands.VerifyCommit{commit: "abc123", verbose: true, raw: true})
      ["verify-commit", "-v", "--raw", "abc123"]

  """
  @spec args(t()) :: [String.t()]
  @impl true
  def args(%__MODULE__{commit: commit} = command) do
    ["verify-commit"]
    |> maybe_add_flag(command.verbose, "-v")
    |> maybe_add_flag(command.raw, "--raw")
    |> Kernel.++([commit])
  end

  @doc """
  Parses the output of `git verify-commit`.

  Exit code 0 means the commit has a valid GPG signature. Exit code 1 means
  the signature is bad or missing. Other exit codes are treated as errors.
  """
  @spec parse_output(String.t(), non_neg_integer()) ::
          {:ok, map()} | {:error, {String.t(), non_neg_integer()}}
  @impl true
  def parse_output(stdout, 0), do: {:ok, %{valid: true, raw: stdout}}
  def parse_output(stdout, 1), do: {:ok, %{valid: false, raw: stdout}}
  def parse_output(stdout, exit_code), do: {:error, {stdout, exit_code}}

  defp maybe_add_flag(args, false, _flag), do: args
  defp maybe_add_flag(args, true, flag), do: args ++ [flag]
end
