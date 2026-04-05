defmodule Git.Commands.FormatPatch do
  @moduledoc """
  Implements the `Git.Command` behaviour for `git format-patch`.

  Generates patch files from commits. Supports output to files or stdout,
  cover letters, numbering, and various patch formatting options.
  """

  @behaviour Git.Command

  @mode_key :git_format_patch_stdout

  @type t :: %__MODULE__{
          ref: String.t(),
          output_directory: String.t() | nil,
          numbered: boolean(),
          cover_letter: boolean(),
          stdout: boolean(),
          from: String.t() | nil,
          subject_prefix: String.t() | nil,
          no_stat: boolean(),
          start_number: non_neg_integer() | nil,
          signature: String.t() | nil,
          no_signature: boolean(),
          quiet: boolean(),
          zero_commit: boolean(),
          base: String.t() | nil
        }

  defstruct ref: "HEAD~1",
            output_directory: nil,
            numbered: false,
            cover_letter: false,
            stdout: false,
            from: nil,
            subject_prefix: nil,
            no_stat: false,
            start_number: nil,
            signature: nil,
            no_signature: false,
            quiet: false,
            zero_commit: false,
            base: nil

  @doc """
  Returns the argument list for `git format-patch`.

  ## Examples

      iex> Git.Commands.FormatPatch.args(%Git.Commands.FormatPatch{ref: "HEAD~3"})
      ["format-patch", "HEAD~3"]

      iex> Git.Commands.FormatPatch.args(%Git.Commands.FormatPatch{ref: "HEAD~1", stdout: true})
      ["format-patch", "--stdout", "HEAD~1"]

      iex> Git.Commands.FormatPatch.args(%Git.Commands.FormatPatch{ref: "v1.0..v2.0", output_directory: "/tmp/patches", numbered: true})
      ["format-patch", "-n", "-o", "/tmp/patches", "v1.0..v2.0"]

  """
  @spec args(t()) :: [String.t()]
  @impl true
  def args(%__MODULE__{} = command) do
    Process.put(@mode_key, command.stdout)

    ["format-patch"]
    |> maybe_add_flag(command.stdout, "--stdout")
    |> maybe_add_flag(command.numbered, "-n")
    |> maybe_add_flag(command.cover_letter, "--cover-letter")
    |> maybe_add_flag(command.no_stat, "--no-stat")
    |> maybe_add_flag(command.no_signature, "--no-signature")
    |> maybe_add_flag(command.quiet, "-q")
    |> maybe_add_flag(command.zero_commit, "--zero-commit")
    |> maybe_add_output_directory(command.output_directory)
    |> maybe_add_value("--from=", command.from)
    |> maybe_add_value("--subject-prefix=", command.subject_prefix)
    |> maybe_add_value("--start-number=", command.start_number)
    |> maybe_add_value("--signature=", command.signature)
    |> maybe_add_value("--base=", command.base)
    |> Kernel.++([command.ref])
  end

  @doc """
  Parses the output of `git format-patch`.

  When stdout mode is active, returns `{:ok, patch_content}`.
  Otherwise, returns `{:ok, [file_path]}` with the list of generated
  patch file paths.

  On failure, returns `{:error, {stdout, exit_code}}`.
  """
  @spec parse_output(String.t(), non_neg_integer()) ::
          {:ok, String.t()} | {:ok, [String.t()]} | {:error, {String.t(), non_neg_integer()}}
  @impl true
  def parse_output(stdout, 0) do
    if Process.get(@mode_key, false) do
      {:ok, stdout}
    else
      files =
        stdout
        |> String.split("\n", trim: true)
        |> Enum.map(&String.trim/1)

      {:ok, files}
    end
  end

  def parse_output(stdout, exit_code), do: {:error, {stdout, exit_code}}

  defp maybe_add_flag(args, true, flag), do: args ++ [flag]
  defp maybe_add_flag(args, false, _flag), do: args

  defp maybe_add_value(args, _prefix, nil), do: args
  defp maybe_add_value(args, prefix, value), do: args ++ ["#{prefix}#{value}"]

  defp maybe_add_output_directory(args, nil), do: args
  defp maybe_add_output_directory(args, dir), do: args ++ ["-o", dir]
end
