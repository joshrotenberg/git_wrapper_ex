defmodule Git.Commands.Gc do
  @moduledoc """
  Implements the `Git.Command` behaviour for `git gc`.

  Cleans up unnecessary files and optimizes the local repository.
  """

  @behaviour Git.Command

  @type t :: %__MODULE__{
          aggressive: boolean(),
          auto: boolean(),
          prune: String.t() | nil,
          no_prune: boolean(),
          quiet: boolean(),
          force: boolean(),
          keep_largest_pack: boolean()
        }

  defstruct aggressive: false,
            auto: false,
            prune: nil,
            no_prune: false,
            quiet: false,
            force: false,
            keep_largest_pack: false

  @doc """
  Returns the argument list for `git gc`.

  ## Examples

      iex> Git.Commands.Gc.args(%Git.Commands.Gc{})
      ["gc"]

      iex> Git.Commands.Gc.args(%Git.Commands.Gc{aggressive: true})
      ["gc", "--aggressive"]

      iex> Git.Commands.Gc.args(%Git.Commands.Gc{auto: true})
      ["gc", "--auto"]

      iex> Git.Commands.Gc.args(%Git.Commands.Gc{prune: "now"})
      ["gc", "--prune=now"]

      iex> Git.Commands.Gc.args(%Git.Commands.Gc{no_prune: true})
      ["gc", "--no-prune"]

      iex> Git.Commands.Gc.args(%Git.Commands.Gc{quiet: true, force: true})
      ["gc", "--quiet", "--force"]

      iex> Git.Commands.Gc.args(%Git.Commands.Gc{keep_largest_pack: true})
      ["gc", "--keep-largest-pack"]

  """
  @spec args(t()) :: [String.t()]
  @impl true
  def args(%__MODULE__{} = command) do
    ["gc"]
    |> maybe_add_flag(command.aggressive, "--aggressive")
    |> maybe_add_flag(command.auto, "--auto")
    |> maybe_add_prune(command.prune)
    |> maybe_add_flag(command.no_prune, "--no-prune")
    |> maybe_add_flag(command.quiet, "--quiet")
    |> maybe_add_flag(command.force, "--force")
    |> maybe_add_flag(command.keep_largest_pack, "--keep-largest-pack")
  end

  @doc """
  Parses the output of `git gc`.

  On success (exit code 0), returns `{:ok, :done}`. On failure, returns
  `{:error, {stdout, exit_code}}`.
  """
  @spec parse_output(String.t(), non_neg_integer()) ::
          {:ok, :done} | {:error, {String.t(), non_neg_integer()}}
  @impl true
  def parse_output(_stdout, 0), do: {:ok, :done}
  def parse_output(stdout, exit_code), do: {:error, {stdout, exit_code}}

  defp maybe_add_flag(args, false, _flag), do: args
  defp maybe_add_flag(args, true, flag), do: args ++ [flag]

  defp maybe_add_prune(args, nil), do: args
  defp maybe_add_prune(args, date) when is_binary(date), do: args ++ ["--prune=#{date}"]
end
