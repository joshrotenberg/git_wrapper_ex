defmodule Git.Commands.Reset do
  @moduledoc """
  Implements the `Git.Command` behaviour for `git reset`.

  Supports `--soft`, `--mixed` (default), and `--hard` modes against any
  git ref (defaults to `HEAD`).
  """

  @behaviour Git.Command

  @type mode :: :soft | :mixed | :hard

  @type t :: %__MODULE__{
          ref: String.t(),
          mode: mode()
        }

  defstruct ref: "HEAD", mode: :mixed

  @doc """
  Returns the argument list for `git reset`.

  Builds `git reset --<mode> <ref>` from the struct fields. The mode defaults
  to `:mixed` and the ref defaults to `"HEAD"`.

  ## Examples

      iex> Git.Commands.Reset.args(%Git.Commands.Reset{})
      ["reset", "--mixed", "HEAD"]

      iex> Git.Commands.Reset.args(%Git.Commands.Reset{mode: :soft, ref: "HEAD~1"})
      ["reset", "--soft", "HEAD~1"]

      iex> Git.Commands.Reset.args(%Git.Commands.Reset{mode: :hard})
      ["reset", "--hard", "HEAD"]

  """
  @spec args(t()) :: [String.t()]
  @impl true
  def args(%__MODULE__{ref: ref, mode: mode}) do
    ["reset", mode_flag(mode), ref]
  end

  @doc """
  Parses the output of `git reset`.

  On success (exit code 0), returns `{:ok, :done}`. On failure, returns
  `{:error, {stdout, exit_code}}`.
  """
  @spec parse_output(String.t(), non_neg_integer()) ::
          {:ok, :done} | {:error, {String.t(), non_neg_integer()}}
  @impl true
  def parse_output(_stdout, 0), do: {:ok, :done}
  def parse_output(stdout, exit_code), do: {:error, {stdout, exit_code}}

  defp mode_flag(:soft), do: "--soft"
  defp mode_flag(:mixed), do: "--mixed"
  defp mode_flag(:hard), do: "--hard"
end
