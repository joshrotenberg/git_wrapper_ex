defmodule Git.Commands.NameRev do
  @moduledoc """
  Implements the `Git.Command` behaviour for `git name-rev`.

  Finds a symbolic name for a given commit. With `:name_only` the output is
  just the name; otherwise git prints the input followed by the name. With
  `:tags` only tags are used to name the commit.
  """

  @behaviour Git.Command

  @type t :: %__MODULE__{
          commit: String.t() | nil,
          name_only: boolean(),
          tags: boolean()
        }

  defstruct commit: nil,
            name_only: false,
            tags: false

  @doc """
  Returns the argument list for `git name-rev`.

  ## Examples

      iex> Git.Commands.NameRev.args(%Git.Commands.NameRev{commit: "HEAD"})
      ["name-rev", "HEAD"]

      iex> Git.Commands.NameRev.args(%Git.Commands.NameRev{commit: "HEAD", name_only: true})
      ["name-rev", "--name-only", "HEAD"]

      iex> Git.Commands.NameRev.args(%Git.Commands.NameRev{commit: "HEAD", name_only: true, tags: true})
      ["name-rev", "--name-only", "--tags", "HEAD"]

  """
  @spec args(t()) :: [String.t()]
  @impl true
  def args(%__MODULE__{commit: commit} = command) do
    ["name-rev"]
    |> maybe_add_flag(command.name_only, "--name-only")
    |> maybe_add_flag(command.tags, "--tags")
    |> Kernel.++([commit])
  end

  @doc """
  Parses the output of `git name-rev`.

  On success, returns `{:ok, name}` with the trimmed output string. On a
  non-zero exit code, returns `{:error, {stdout, exit_code}}`.
  """
  @spec parse_output(String.t(), non_neg_integer()) ::
          {:ok, String.t()} | {:error, {String.t(), non_neg_integer()}}
  @impl true
  def parse_output(stdout, 0), do: {:ok, String.trim(stdout)}
  def parse_output(stdout, exit_code), do: {:error, {stdout, exit_code}}

  defp maybe_add_flag(args, true, flag), do: args ++ [flag]
  defp maybe_add_flag(args, false, _flag), do: args
end
