defmodule GitWrapper.Commands.Reset do
  @moduledoc """
  Implements the `GitWrapper.Command` behaviour for `git reset`.

  Supports `--soft`, `--mixed` (default), and `--hard` modes against any
  git ref (defaults to `HEAD`).
  """

  @behaviour GitWrapper.Command

  @type mode :: :soft | :mixed | :hard

  @type t :: %__MODULE__{
          ref: String.t(),
          mode: mode()
        }

  defstruct ref: "HEAD", mode: :mixed

  @spec args(t()) :: [String.t()]
  @impl true
  def args(%__MODULE__{ref: ref, mode: mode}) do
    ["reset", mode_flag(mode), ref]
  end

  @spec parse_output(String.t(), non_neg_integer()) ::
          {:ok, :done} | {:error, {String.t(), non_neg_integer()}}
  @impl true
  def parse_output(_stdout, 0), do: {:ok, :done}
  def parse_output(stdout, exit_code), do: {:error, {stdout, exit_code}}

  defp mode_flag(:soft), do: "--soft"
  defp mode_flag(:mixed), do: "--mixed"
  defp mode_flag(:hard), do: "--hard"
end
