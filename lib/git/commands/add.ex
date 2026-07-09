defmodule Git.Commands.Add do
  @moduledoc """
  Implements the `Git.Command` behaviour for `git add`.

  Builds `git add [flags] [-- <paths>]`. Flags and a pathspec compose, so a
  path can be staged together with any of `--all`, `--update`, `--force`,
  `--dry-run`, `--intent-to-add`, `--renormalize`, and `--chmod`.
  """

  @behaviour Git.Command

  @type t :: %__MODULE__{
          files: [String.t()],
          all: boolean(),
          update: boolean(),
          force: boolean(),
          dry_run: boolean(),
          intent_to_add: boolean(),
          renormalize: boolean(),
          chmod: String.t() | nil
        }

  defstruct files: [],
            all: false,
            update: false,
            force: false,
            dry_run: false,
            intent_to_add: false,
            renormalize: false,
            chmod: nil

  @doc """
  Returns the argument list for `git add`.

  Emits the enabled flags followed by the pathspec, so flags and files compose
  (unlike the previous behavior, where `:all` dropped `:files`).

  ## Examples

      iex> Git.Commands.Add.args(%Git.Commands.Add{all: true})
      ["add", "--all"]

      iex> Git.Commands.Add.args(%Git.Commands.Add{files: ["foo.txt", "bar.txt"]})
      ["add", "foo.txt", "bar.txt"]

      iex> Git.Commands.Add.args(%Git.Commands.Add{update: true, files: ["lib"]})
      ["add", "--update", "lib"]

      iex> Git.Commands.Add.args(%Git.Commands.Add{intent_to_add: true, files: ["new.ex"]})
      ["add", "--intent-to-add", "new.ex"]

      iex> Git.Commands.Add.args(%Git.Commands.Add{chmod: "+x", files: ["run.sh"]})
      ["add", "--chmod=+x", "run.sh"]

  """
  @spec args(t()) :: [String.t()]
  @impl true
  def args(%__MODULE__{} = command) do
    ["add"] ++ flags(command) ++ command.files
  end

  @doc """
  Parses the output of `git add`.

  On success (exit code 0), returns `{:ok, :done}`. On failure, returns
  `{:error, {stdout, exit_code}}`.
  """
  @spec parse_output(String.t(), non_neg_integer()) ::
          {:ok, :done} | {:error, {String.t(), non_neg_integer()}}
  @impl true
  def parse_output(_stdout, 0), do: {:ok, :done}

  def parse_output(stdout, exit_code), do: {:error, {stdout, exit_code}}

  defp flags(%__MODULE__{} = command) do
    [
      {command.all, "--all"},
      {command.update, "--update"},
      {command.force, "--force"},
      {command.dry_run, "--dry-run"},
      {command.intent_to_add, "--intent-to-add"},
      {command.renormalize, "--renormalize"}
    ]
    |> Enum.filter(fn {enabled?, _flag} -> enabled? end)
    |> Enum.map(fn {_enabled?, flag} -> flag end)
    |> maybe_chmod(command.chmod)
  end

  defp maybe_chmod(flags, nil), do: flags
  defp maybe_chmod(flags, chmod), do: flags ++ ["--chmod=#{chmod}"]
end
