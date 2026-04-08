defmodule Git.Commands.HashObject do
  @moduledoc """
  Implements the `Git.Command` behaviour for `git hash-object`.

  Computes the object ID for a file and optionally writes it into the
  object database. Only file-based hashing is supported (no stdin).
  """

  @behaviour Git.Command

  @type t :: %__MODULE__{
          file: String.t() | nil,
          write: boolean(),
          type: String.t() | nil,
          literally: boolean()
        }

  defstruct file: nil,
            write: false,
            type: nil,
            literally: false

  @doc """
  Returns the argument list for `git hash-object`.

  ## Examples

      iex> Git.Commands.HashObject.args(%Git.Commands.HashObject{file: "README.md"})
      ["hash-object", "README.md"]

      iex> Git.Commands.HashObject.args(%Git.Commands.HashObject{file: "README.md", write: true})
      ["hash-object", "-w", "README.md"]

      iex> Git.Commands.HashObject.args(%Git.Commands.HashObject{file: "README.md", type: "commit"})
      ["hash-object", "-t", "commit", "README.md"]

      iex> Git.Commands.HashObject.args(%Git.Commands.HashObject{file: "README.md", literally: true})
      ["hash-object", "--literally", "README.md"]

  """
  @spec args(t()) :: [String.t()]
  @impl true
  def args(%__MODULE__{} = command) do
    ["hash-object"]
    |> maybe_add_flag(command.write, "-w")
    |> maybe_add_type(command.type)
    |> maybe_add_flag(command.literally, "--literally")
    |> maybe_add_file(command.file)
  end

  @doc """
  Parses the output of `git hash-object`.

  On success (exit code 0), returns `{:ok, hash}` where hash is the
  trimmed SHA string. On failure, returns `{:error, {stdout, exit_code}}`.
  """
  @spec parse_output(String.t(), non_neg_integer()) ::
          {:ok, String.t()} | {:error, {String.t(), non_neg_integer()}}
  @impl true
  def parse_output(stdout, 0), do: {:ok, String.trim(stdout)}
  def parse_output(stdout, exit_code), do: {:error, {stdout, exit_code}}

  defp maybe_add_flag(args, true, flag), do: args ++ [flag]
  defp maybe_add_flag(args, false, _flag), do: args

  defp maybe_add_type(args, nil), do: args
  defp maybe_add_type(args, type), do: args ++ ["-t", type]

  defp maybe_add_file(args, nil), do: args
  defp maybe_add_file(args, file), do: args ++ [file]
end
