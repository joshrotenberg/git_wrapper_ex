defmodule Git.Commands.Reset do
  @moduledoc """
  Implements the `Git.Command` behaviour for `git reset`.

  Supports two forms:

    * whole-tree reset, `git reset --<mode> <ref>`, with `:mode` one of
      `:soft`, `:mixed` (default), `:hard`, `:merge`, or `:keep`
    * pathspec reset, `git reset <ref> -- <paths>`, selected by giving `:files`.
      This unstages the listed paths; `:mode` does not apply to this form (git
      rejects a mode flag together with a pathspec).
  """

  @behaviour Git.Command

  @type mode :: :soft | :mixed | :hard | :merge | :keep

  @type t :: %__MODULE__{
          ref: String.t(),
          mode: mode(),
          files: [String.t()],
          quiet: boolean()
        }

  defstruct ref: "HEAD", mode: :mixed, files: [], quiet: false

  @doc """
  Returns the argument list for `git reset`.

  With `:files`, builds the pathspec form `git reset [-q] <ref> -- <paths>`.
  Otherwise builds the whole-tree form `git reset --<mode> [-q] <ref>`. The mode
  defaults to `:mixed` and the ref defaults to `"HEAD"`.

  ## Examples

      iex> Git.Commands.Reset.args(%Git.Commands.Reset{})
      ["reset", "--mixed", "HEAD"]

      iex> Git.Commands.Reset.args(%Git.Commands.Reset{mode: :soft, ref: "HEAD~1"})
      ["reset", "--soft", "HEAD~1"]

      iex> Git.Commands.Reset.args(%Git.Commands.Reset{mode: :hard})
      ["reset", "--hard", "HEAD"]

      iex> Git.Commands.Reset.args(%Git.Commands.Reset{files: ["a.ex", "b.ex"]})
      ["reset", "HEAD", "--", "a.ex", "b.ex"]

      iex> Git.Commands.Reset.args(%Git.Commands.Reset{mode: :keep, quiet: true})
      ["reset", "--keep", "-q", "HEAD"]

  """
  @spec args(t()) :: [String.t()]
  @impl true
  def args(%__MODULE__{files: [_ | _] = files, ref: ref, quiet: quiet}) do
    ["reset"] ++ quiet_flag(quiet) ++ [ref, "--"] ++ files
  end

  def args(%__MODULE__{ref: ref, mode: mode, quiet: quiet}) do
    ["reset", mode_flag(mode)] ++ quiet_flag(quiet) ++ [ref]
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
  defp mode_flag(:merge), do: "--merge"
  defp mode_flag(:keep), do: "--keep"

  defp quiet_flag(true), do: ["-q"]
  defp quiet_flag(false), do: []
end
