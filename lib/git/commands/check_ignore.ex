defmodule Git.Commands.CheckIgnore do
  @moduledoc """
  Implements the `Git.Command` behaviour for `git check-ignore`.

  Checks whether given paths are ignored by `.gitignore` rules. Supports
  verbose output showing which pattern matched and non-matching mode.

  Stdin mode (`--stdin`) is intentionally not supported because it requires
  stdin piping which cannot be driven programmatically via `System.cmd/3`.
  """

  @behaviour Git.Command

  @type t :: %__MODULE__{
          paths: [String.t()],
          verbose: boolean(),
          non_matching: boolean(),
          no_index: boolean(),
          quiet: boolean()
        }

  defstruct paths: [],
            verbose: false,
            non_matching: false,
            no_index: false,
            quiet: false

  # Process dictionary key used to communicate the output mode from args/1
  # to parse_output/2.
  @mode_key :__git_check_ignore_mode__

  @doc """
  Returns the argument list for `git check-ignore`.

  ## Examples

      iex> Git.Commands.CheckIgnore.args(%Git.Commands.CheckIgnore{paths: ["build/", "tmp.log"]})
      ["check-ignore", "build/", "tmp.log"]

      iex> Git.Commands.CheckIgnore.args(%Git.Commands.CheckIgnore{paths: ["foo"], verbose: true})
      ["check-ignore", "-v", "foo"]

      iex> Git.Commands.CheckIgnore.args(%Git.Commands.CheckIgnore{paths: ["foo"], verbose: true, non_matching: true})
      ["check-ignore", "-v", "-n", "foo"]

      iex> Git.Commands.CheckIgnore.args(%Git.Commands.CheckIgnore{paths: ["foo"], no_index: true})
      ["check-ignore", "--no-index", "foo"]

      iex> Git.Commands.CheckIgnore.args(%Git.Commands.CheckIgnore{paths: ["foo"], quiet: true})
      ["check-ignore", "-q", "foo"]

  """
  @spec args(t()) :: [String.t()]
  @impl true
  def args(%__MODULE__{} = command) do
    mode = if command.verbose, do: :verbose, else: :default
    Process.put(@mode_key, mode)

    base = ["check-ignore"]

    base
    |> maybe_add_flag(command.verbose, "-v")
    |> maybe_add_flag(command.non_matching, "-n")
    |> maybe_add_flag(command.no_index, "--no-index")
    |> maybe_add_flag(command.quiet, "-q")
    |> append_paths(command.paths)
  end

  @doc """
  Parses the output of `git check-ignore`.

  - Default mode: returns `{:ok, [String.t()]}` with the list of ignored paths.
  - Verbose mode: returns `{:ok, [map]}` where each map has `:source`,
    `:line_number`, `:pattern`, and `:path` keys.
  - Exit code 1 means no paths matched, which returns `{:ok, []}` (not an error).
  """
  @spec parse_output(String.t(), non_neg_integer()) ::
          {:ok, [String.t()] | [map()]} | {:error, {String.t(), non_neg_integer()}}
  @impl true
  def parse_output(stdout, exit_code) when exit_code in [0, 1] do
    mode = Process.get(@mode_key, :default)

    if exit_code == 1 or String.trim(stdout) == "" do
      {:ok, []}
    else
      case mode do
        :default ->
          paths =
            stdout
            |> String.split("\n", trim: true)
            |> Enum.map(&String.trim/1)

          {:ok, paths}

        :verbose ->
          entries =
            stdout
            |> String.split("\n", trim: true)
            |> Enum.map(&parse_verbose_line/1)
            |> Enum.reject(&is_nil/1)

          {:ok, entries}
      end
    end
  end

  def parse_output(stdout, exit_code), do: {:error, {stdout, exit_code}}

  defp parse_verbose_line(line) do
    # Verbose format: "source:line_number:pattern\tpath"
    # Non-matching (with -n): "::\tpath"
    with [info, path] <- String.split(line, "\t", parts: 2),
         [source, line_num, pattern] <- String.split(info, ":", parts: 3) do
      %{
        source: source,
        line_number: parse_line_number(line_num),
        pattern: pattern,
        path: String.trim(path)
      }
    else
      _ -> nil
    end
  end

  defp parse_line_number(str) do
    case Integer.parse(str) do
      {n, _} -> n
      :error -> 0
    end
  end

  defp maybe_add_flag(args, true, flag), do: args ++ [flag]
  defp maybe_add_flag(args, false, _flag), do: args

  defp append_paths(args, paths), do: args ++ paths
end
