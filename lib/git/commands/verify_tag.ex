defmodule Git.Commands.VerifyTag do
  @moduledoc """
  Implements the `Git.Command` behaviour for `git verify-tag`.

  Verifies the GPG signature of a tag object.
  """

  @behaviour Git.Command

  @type t :: %__MODULE__{
          tag: String.t() | nil,
          verbose: boolean(),
          raw: boolean(),
          format: String.t() | nil
        }

  defstruct tag: nil,
            verbose: false,
            raw: false,
            format: nil

  @doc """
  Returns the argument list for `git verify-tag`.

  ## Examples

      iex> Git.Commands.VerifyTag.args(%Git.Commands.VerifyTag{tag: "v1.0"})
      ["verify-tag", "v1.0"]

      iex> Git.Commands.VerifyTag.args(%Git.Commands.VerifyTag{tag: "v1.0", verbose: true})
      ["verify-tag", "-v", "v1.0"]

      iex> Git.Commands.VerifyTag.args(%Git.Commands.VerifyTag{tag: "v1.0", raw: true})
      ["verify-tag", "--raw", "v1.0"]

      iex> Git.Commands.VerifyTag.args(%Git.Commands.VerifyTag{tag: "v1.0", format: "%(objectname)"})
      ["verify-tag", "--format=%(objectname)", "v1.0"]

  """
  @spec args(t()) :: [String.t()]
  @impl true
  def args(%__MODULE__{tag: tag} = command) do
    ["verify-tag"]
    |> maybe_add_flag(command.verbose, "-v")
    |> maybe_add_flag(command.raw, "--raw")
    |> maybe_add_format(command.format)
    |> Kernel.++([tag])
  end

  @doc """
  Parses the output of `git verify-tag`.

  Exit code 0 means the tag has a valid GPG signature. Exit code 1 means
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

  defp maybe_add_format(args, nil), do: args
  defp maybe_add_format(args, format) when is_binary(format), do: args ++ ["--format=#{format}"]
end
