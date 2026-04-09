defmodule Git.Commands.InterpretTrailers do
  @moduledoc """
  Implements the `Git.Command` behaviour for `git interpret-trailers`.

  Adds or parses trailers in commit messages. Trailers are key-value pairs
  that appear at the end of a commit message, such as "Signed-off-by:" or
  "Co-authored-by:".
  """

  @behaviour Git.Command

  @type t :: %__MODULE__{
          file: String.t() | nil,
          parse: boolean(),
          trailers: [String.t()],
          in_place: boolean(),
          trim_empty: boolean(),
          where: String.t() | nil,
          if_exists: String.t() | nil,
          if_missing: String.t() | nil,
          unfold: boolean(),
          no_divider: boolean()
        }

  defstruct file: nil,
            parse: false,
            trailers: [],
            in_place: false,
            trim_empty: false,
            where: nil,
            if_exists: nil,
            if_missing: nil,
            unfold: false,
            no_divider: false

  @doc """
  Returns the argument list for `git interpret-trailers`.

  ## Examples

      iex> Git.Commands.InterpretTrailers.args(%Git.Commands.InterpretTrailers{})
      ["interpret-trailers"]

      iex> Git.Commands.InterpretTrailers.args(%Git.Commands.InterpretTrailers{parse: true})
      ["interpret-trailers", "--only-trailers"]

      iex> Git.Commands.InterpretTrailers.args(%Git.Commands.InterpretTrailers{trailers: ["Signed-off-by: A"]})
      ["interpret-trailers", "--trailer", "Signed-off-by: A"]

      iex> Git.Commands.InterpretTrailers.args(%Git.Commands.InterpretTrailers{in_place: true, file: "msg.txt"})
      ["interpret-trailers", "--in-place", "msg.txt"]

      iex> Git.Commands.InterpretTrailers.args(%Git.Commands.InterpretTrailers{where: "end"})
      ["interpret-trailers", "--where", "end"]

      iex> Git.Commands.InterpretTrailers.args(%Git.Commands.InterpretTrailers{if_exists: "replace"})
      ["interpret-trailers", "--if-exists", "replace"]

      iex> Git.Commands.InterpretTrailers.args(%Git.Commands.InterpretTrailers{if_missing: "doNothing"})
      ["interpret-trailers", "--if-missing", "doNothing"]

  """
  @spec args(t()) :: [String.t()]
  @impl true
  def args(%__MODULE__{} = command) do
    ["interpret-trailers"]
    |> maybe_add_flag(command.parse, "--only-trailers")
    |> maybe_add_flag(command.in_place, "--in-place")
    |> maybe_add_flag(command.trim_empty, "--trim-empty")
    |> maybe_add_flag(command.unfold, "--unfold")
    |> maybe_add_flag(command.no_divider, "--no-divider")
    |> maybe_add_option(command.where, "--where")
    |> maybe_add_option(command.if_exists, "--if-exists")
    |> maybe_add_option(command.if_missing, "--if-missing")
    |> maybe_add_trailers(command.trailers)
    |> maybe_add_file(command.file)
  end

  @doc """
  Parses the output of `git interpret-trailers`.

  On success (exit code 0), returns `{:ok, output}` with the processed
  message or trailer text. On failure, returns `{:error, {stdout, exit_code}}`.
  """
  @spec parse_output(String.t(), non_neg_integer()) ::
          {:ok, String.t()} | {:error, {String.t(), non_neg_integer()}}
  @impl true
  def parse_output(stdout, 0), do: {:ok, stdout}
  def parse_output(stdout, exit_code), do: {:error, {stdout, exit_code}}

  defp maybe_add_flag(args, false, _flag), do: args
  defp maybe_add_flag(args, true, flag), do: args ++ [flag]

  defp maybe_add_option(args, nil, _flag), do: args
  defp maybe_add_option(args, value, flag), do: args ++ [flag, value]

  defp maybe_add_trailers(args, []), do: args

  defp maybe_add_trailers(args, trailers) do
    Enum.reduce(trailers, args, fn trailer, acc ->
      acc ++ ["--trailer", trailer]
    end)
  end

  defp maybe_add_file(args, nil), do: args
  defp maybe_add_file(args, file), do: args ++ [file]
end
