defmodule Git.Commands.Commit do
  @moduledoc """
  Implements the `Git.Command` behaviour for `git commit`.

  Supports the message (`-m`) or message-from-file (`-F`) forms, the `-a`,
  `--amend`, `--allow-empty`, `--no-verify`, `--no-edit`, and `--signoff`
  flags, the `--author`, `--date`, `--fixup`, `--squash`, `-C`, and
  `--cleanup` value options, and `--only` with a pathspec.

  The message is optional: with `--amend --no-edit` (or `-F`), no `-m` is
  emitted.
  """

  @behaviour Git.Command

  @type t :: %__MODULE__{
          message: String.t() | nil,
          all: boolean(),
          amend: boolean(),
          allow_empty: boolean(),
          no_verify: boolean(),
          no_edit: boolean(),
          signoff: boolean(),
          author: String.t() | nil,
          date: String.t() | nil,
          fixup: String.t() | nil,
          squash: String.t() | nil,
          file: String.t() | nil,
          reuse_message: String.t() | nil,
          cleanup: String.t() | nil,
          only: [String.t()]
        }

  defstruct message: nil,
            all: false,
            amend: false,
            allow_empty: false,
            no_verify: false,
            no_edit: false,
            signoff: false,
            author: nil,
            date: nil,
            fixup: nil,
            squash: nil,
            file: nil,
            reuse_message: nil,
            cleanup: nil,
            only: []

  @doc """
  Returns the argument list for `git commit`.

  Emits the message source (`-F <file>` when `:file` is set, otherwise
  `-m <message>` when `:message` is set), followed by the enabled flags, the
  value options, and the `--only` pathspec.

  ## Examples

      iex> Git.Commands.Commit.args(%Git.Commands.Commit{message: "test", all: true})
      ["commit", "-m", "test", "-a"]

      iex> Git.Commands.Commit.args(%Git.Commands.Commit{amend: true, no_edit: true})
      ["commit", "--amend", "--no-edit"]

      iex> Git.Commands.Commit.args(%Git.Commands.Commit{message: "m", signoff: true, author: "A U <a@u>"})
      ["commit", "-m", "m", "--signoff", "--author", "A U <a@u>"]

      iex> Git.Commands.Commit.args(%Git.Commands.Commit{fixup: "HEAD~1"})
      ["commit", "--fixup", "HEAD~1"]

  """
  @spec args(t()) :: [String.t()]
  @impl true
  def args(%__MODULE__{} = command) do
    ["commit"]
    |> add_message(command)
    |> maybe_add(command.all, "-a")
    |> maybe_add(command.amend, "--amend")
    |> maybe_add(command.allow_empty, "--allow-empty")
    |> maybe_add(command.no_verify, "--no-verify")
    |> maybe_add(command.no_edit, "--no-edit")
    |> maybe_add(command.signoff, "--signoff")
    |> maybe_add_value(command.author, "--author")
    |> maybe_add_value(command.date, "--date")
    |> maybe_add_value(command.fixup, "--fixup")
    |> maybe_add_value(command.squash, "--squash")
    |> maybe_add_value(command.reuse_message, "-C")
    |> maybe_add_value(command.cleanup, "--cleanup")
    |> add_only(command.only)
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

  defp add_message(args, %__MODULE__{file: file}) when is_binary(file), do: args ++ ["-F", file]

  defp add_message(args, %__MODULE__{message: message}) when is_binary(message),
    do: args ++ ["-m", message]

  defp add_message(args, %__MODULE__{}), do: args

  defp add_only(args, []), do: args
  defp add_only(args, paths) when is_list(paths), do: args ++ ["--only", "--"] ++ paths

  defp maybe_add(args, true, flag), do: args ++ [flag]
  defp maybe_add(args, false, _flag), do: args

  defp maybe_add_value(args, nil, _flag), do: args
  defp maybe_add_value(args, value, flag) when is_binary(value), do: args ++ [flag, value]
end
