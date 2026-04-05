defmodule Git.Commands.Commit do
  @moduledoc """
  Implements the `Git.Command` behaviour for `git commit`.

  Supports the `-m` (message), `-a` (all), `--amend`, and `--allow-empty` flags.
  """

  @behaviour Git.Command

  @enforce_keys [:message]

  @type t :: %__MODULE__{
          message: String.t(),
          all: boolean(),
          amend: boolean(),
          allow_empty: boolean()
        }

  defstruct [
    :message,
    all: false,
    amend: false,
    allow_empty: false
  ]

  @doc """
  Returns the argument list for `git commit`.

  Builds the argument list from the struct fields. The `:message` field is
  required and produces `-m <message>`. Optional flags are appended when set
  to `true`.

  ## Examples

      iex> args = Git.Commands.Commit.args(%Git.Commands.Commit{message: "test", all: true})
      iex> args
      ["commit", "-m", "test", "-a"]

  """
  @spec args(t()) :: [String.t()]
  @impl true
  def args(%__MODULE__{message: message} = command) when is_binary(message) do
    base = ["commit", "-m", message]

    base
    |> maybe_add(command.all, "-a")
    |> maybe_add(command.amend, "--amend")
    |> maybe_add(command.allow_empty, "--allow-empty")
  end

  @doc """
  Parses the output of `git commit`.

  On success (exit code 0), parses the output into a `Git.CommitResult`
  struct. On failure, returns `{:error, {stdout, exit_code}}`.
  """
  @spec parse_output(String.t(), non_neg_integer()) ::
          {:ok, Git.CommitResult.t()} | {:error, {String.t(), non_neg_integer()}}
  @impl true
  def parse_output(stdout, 0), do: {:ok, Git.CommitResult.parse(stdout)}

  def parse_output(stdout, exit_code), do: {:error, {stdout, exit_code}}

  defp maybe_add(args, true, flag), do: args ++ [flag]
  defp maybe_add(args, false, _flag), do: args
end
