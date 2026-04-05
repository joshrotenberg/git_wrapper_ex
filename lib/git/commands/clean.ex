defmodule Git.Commands.Clean do
  @moduledoc """
  Implements the `Git.Command` behaviour for `git clean`.

  Removes untracked files from the working tree. Supports force, dry-run,
  directory cleaning, ignored file cleaning, exclusion patterns, and quiet
  mode.

  Interactive mode (`-i`) is intentionally not supported because it requires
  interactive terminal input which cannot be driven programmatically.
  """

  @behaviour Git.Command

  @type t :: %__MODULE__{
          force: boolean(),
          directories: boolean(),
          ignored: boolean(),
          only_ignored: boolean(),
          dry_run: boolean(),
          exclude: String.t() | nil,
          quiet: boolean(),
          paths: [String.t()]
        }

  defstruct force: false,
            directories: false,
            ignored: false,
            only_ignored: false,
            dry_run: false,
            exclude: nil,
            quiet: false,
            paths: []

  @doc """
  Returns the argument list for `git clean`.

  Builds the argument list from the struct fields. At least one of `:force`
  or `:dry_run` should be set, as git requires `-f` for actual cleaning
  unless `clean.requireForce` is set to false.

  ## Examples

      iex> Git.Commands.Clean.args(%Git.Commands.Clean{dry_run: true})
      ["clean", "-n"]

      iex> Git.Commands.Clean.args(%Git.Commands.Clean{force: true, directories: true})
      ["clean", "-f", "-d"]

      iex> Git.Commands.Clean.args(%Git.Commands.Clean{force: true, ignored: true})
      ["clean", "-f", "-x"]

      iex> Git.Commands.Clean.args(%Git.Commands.Clean{force: true, exclude: "*.log"})
      ["clean", "-f", "-e", "*.log"]

      iex> Git.Commands.Clean.args(%Git.Commands.Clean{force: true, paths: ["src/", "tmp/"]})
      ["clean", "-f", "--", "src/", "tmp/"]

  """
  @spec args(t()) :: [String.t()]
  @impl true
  def args(%__MODULE__{} = command) do
    base = ["clean"]

    base
    |> maybe_add_flag(command.force, "-f")
    |> maybe_add_flag(command.dry_run, "-n")
    |> maybe_add_flag(command.directories, "-d")
    |> maybe_add_flag(command.ignored, "-x")
    |> maybe_add_flag(command.only_ignored, "-X")
    |> maybe_add_flag(command.quiet, "-q")
    |> maybe_add_exclude(command.exclude)
    |> maybe_add_paths(command.paths)
  end

  @doc """
  Parses the output of `git clean`.

  On success (exit code 0), parses the output into a list of file paths
  that were removed or would be removed. Lines from git clean look like
  `"Removing file.txt"` or `"Would remove file.txt"`.

  Returns `{:ok, [String.t()]}` on success or
  `{:error, {stdout, exit_code}}` on failure.
  """
  @spec parse_output(String.t(), non_neg_integer()) ::
          {:ok, [String.t()]} | {:error, {String.t(), non_neg_integer()}}
  @impl true
  def parse_output(stdout, 0) do
    paths =
      stdout
      |> String.split("\n", trim: true)
      |> Enum.map(&parse_clean_line/1)
      |> Enum.reject(&is_nil/1)

    {:ok, paths}
  end

  def parse_output(stdout, exit_code), do: {:error, {stdout, exit_code}}

  defp parse_clean_line(line) do
    line = String.trim(line)

    cond do
      String.starts_with?(line, "Removing ") ->
        String.trim_leading(line, "Removing ")

      String.starts_with?(line, "Would remove ") ->
        String.trim_leading(line, "Would remove ")

      true ->
        nil
    end
  end

  defp maybe_add_flag(args, true, flag), do: args ++ [flag]
  defp maybe_add_flag(args, false, _flag), do: args

  defp maybe_add_exclude(args, nil), do: args
  defp maybe_add_exclude(args, pattern), do: args ++ ["-e", pattern]

  defp maybe_add_paths(args, []), do: args
  defp maybe_add_paths(args, paths), do: args ++ ["--" | paths]
end
