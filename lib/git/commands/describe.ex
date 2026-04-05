defmodule Git.Commands.Describe do
  @moduledoc """
  Implements the `Git.Command` behaviour for `git describe`.

  Describes a commit using the most recent tag reachable from it.
  Supports various formatting options for the description output.
  """

  @behaviour Git.Command

  @type t :: %__MODULE__{
          ref: String.t() | nil,
          tags: boolean(),
          all: boolean(),
          long: boolean(),
          first_parent: boolean(),
          abbrev: non_neg_integer() | nil,
          exact_match: boolean(),
          dirty: boolean() | String.t(),
          always: boolean(),
          match: String.t() | nil,
          exclude: String.t() | nil,
          candidates: non_neg_integer() | nil,
          broken: boolean()
        }

  defstruct ref: nil,
            tags: false,
            all: false,
            long: false,
            first_parent: false,
            abbrev: nil,
            exact_match: false,
            dirty: false,
            always: false,
            match: nil,
            exclude: nil,
            candidates: nil,
            broken: false

  @doc """
  Returns the argument list for `git describe`.

  ## Examples

      iex> Git.Commands.Describe.args(%Git.Commands.Describe{})
      ["describe"]

      iex> Git.Commands.Describe.args(%Git.Commands.Describe{tags: true, always: true})
      ["describe", "--tags", "--always"]

      iex> Git.Commands.Describe.args(%Git.Commands.Describe{abbrev: 4, long: true})
      ["describe", "--long", "--abbrev=4"]

      iex> Git.Commands.Describe.args(%Git.Commands.Describe{dirty: true})
      ["describe", "--dirty"]

      iex> Git.Commands.Describe.args(%Git.Commands.Describe{dirty: "-modified"})
      ["describe", "--dirty=-modified"]

  """
  @spec args(t()) :: [String.t()]
  @impl true
  def args(%__MODULE__{} = command) do
    ["describe"]
    |> maybe_add_flag(command.tags, "--tags")
    |> maybe_add_flag(command.all, "--all")
    |> maybe_add_flag(command.long, "--long")
    |> maybe_add_flag(command.first_parent, "--first-parent")
    |> maybe_add_flag(command.exact_match, "--exact-match")
    |> maybe_add_flag(command.always, "--always")
    |> maybe_add_flag(command.broken, "--broken")
    |> maybe_add_value("--abbrev=", command.abbrev)
    |> maybe_add_value("--candidates=", command.candidates)
    |> maybe_add_value("--match=", command.match)
    |> maybe_add_value("--exclude=", command.exclude)
    |> maybe_add_dirty(command.dirty)
    |> maybe_add_ref(command.ref)
  end

  @doc """
  Parses the output of `git describe`.

  On success (exit code 0), returns `{:ok, description}` where `description`
  is the trimmed output string. On failure, returns
  `{:error, {stdout, exit_code}}`.
  """
  @spec parse_output(String.t(), non_neg_integer()) ::
          {:ok, String.t()} | {:error, {String.t(), non_neg_integer()}}
  @impl true
  def parse_output(stdout, 0), do: {:ok, String.trim(stdout)}
  def parse_output(stdout, exit_code), do: {:error, {stdout, exit_code}}

  defp maybe_add_flag(args, true, flag), do: args ++ [flag]
  defp maybe_add_flag(args, false, _flag), do: args

  defp maybe_add_value(args, _prefix, nil), do: args
  defp maybe_add_value(args, prefix, value), do: args ++ ["#{prefix}#{value}"]

  defp maybe_add_dirty(args, false), do: args
  defp maybe_add_dirty(args, true), do: args ++ ["--dirty"]
  defp maybe_add_dirty(args, mark) when is_binary(mark), do: args ++ ["--dirty=#{mark}"]

  defp maybe_add_ref(args, nil), do: args
  defp maybe_add_ref(args, ref), do: args ++ [ref]
end
