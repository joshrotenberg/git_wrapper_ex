defmodule Git.Commands.RevParse do
  @moduledoc """
  Implements the `Git.Command` behaviour for `git rev-parse`.

  Supports resolving refs, querying repository properties such as the
  top-level directory, git directory, and various boolean checks like
  whether the current directory is inside a work tree.
  """

  @behaviour Git.Command

  @type t :: %__MODULE__{
          ref: String.t() | nil,
          short: boolean() | non_neg_integer() | nil,
          verify: boolean(),
          show_toplevel: boolean(),
          is_inside_work_tree: boolean(),
          is_inside_git_dir: boolean(),
          is_bare_repository: boolean(),
          git_dir: boolean(),
          abbrev_ref: boolean(),
          symbolic_full_name: boolean(),
          show_cdup: boolean(),
          show_prefix: boolean(),
          absolute_git_dir: boolean(),
          git_common_dir: boolean()
        }

  defstruct ref: nil,
            short: nil,
            verify: false,
            show_toplevel: false,
            is_inside_work_tree: false,
            is_inside_git_dir: false,
            is_bare_repository: false,
            git_dir: false,
            abbrev_ref: false,
            symbolic_full_name: false,
            show_cdup: false,
            show_prefix: false,
            absolute_git_dir: false,
            git_common_dir: false

  @doc """
  Returns the argument list for `git rev-parse`.

  Builds the argument list from the struct fields, appending flags for
  each enabled boolean option and the ref (if provided) at the end.

  ## Examples

      iex> Git.Commands.RevParse.args(%Git.Commands.RevParse{ref: "HEAD"})
      ["rev-parse", "HEAD"]

      iex> Git.Commands.RevParse.args(%Git.Commands.RevParse{show_toplevel: true})
      ["rev-parse", "--show-toplevel"]

      iex> Git.Commands.RevParse.args(%Git.Commands.RevParse{verify: true, ref: "HEAD"})
      ["rev-parse", "--verify", "HEAD"]

      iex> Git.Commands.RevParse.args(%Git.Commands.RevParse{short: true, ref: "HEAD"})
      ["rev-parse", "--short", "HEAD"]

      iex> Git.Commands.RevParse.args(%Git.Commands.RevParse{short: 8, ref: "HEAD"})
      ["rev-parse", "--short=8", "HEAD"]

      iex> Git.Commands.RevParse.args(%Git.Commands.RevParse{abbrev_ref: true, ref: "HEAD"})
      ["rev-parse", "--abbrev-ref", "HEAD"]

  """
  @spec args(t()) :: [String.t()]
  @impl true
  def args(%__MODULE__{} = command) do
    base = ["rev-parse"]

    base
    |> maybe_add_short(command.short)
    |> maybe_add_flag(command.verify, "--verify")
    |> maybe_add_flag(command.show_toplevel, "--show-toplevel")
    |> maybe_add_flag(command.is_inside_work_tree, "--is-inside-work-tree")
    |> maybe_add_flag(command.is_inside_git_dir, "--is-inside-git-dir")
    |> maybe_add_flag(command.is_bare_repository, "--is-bare-repository")
    |> maybe_add_flag(command.git_dir, "--git-dir")
    |> maybe_add_flag(command.abbrev_ref, "--abbrev-ref")
    |> maybe_add_flag(command.symbolic_full_name, "--symbolic-full-name")
    |> maybe_add_flag(command.show_cdup, "--show-cdup")
    |> maybe_add_flag(command.show_prefix, "--show-prefix")
    |> maybe_add_flag(command.absolute_git_dir, "--absolute-git-dir")
    |> maybe_add_flag(command.git_common_dir, "--git-common-dir")
    |> maybe_add_ref(command.ref)
  end

  @doc """
  Parses the output of `git rev-parse`.

  On success (exit code 0), returns `{:ok, trimmed_output}` where the output
  is the trimmed stdout string. On failure, returns
  `{:error, {stdout, exit_code}}`.
  """
  @spec parse_output(String.t(), non_neg_integer()) ::
          {:ok, String.t()} | {:error, {String.t(), non_neg_integer()}}
  @impl true
  def parse_output(stdout, 0), do: {:ok, String.trim(stdout)}

  def parse_output(stdout, exit_code), do: {:error, {stdout, exit_code}}

  defp maybe_add_short(args, nil), do: args
  defp maybe_add_short(args, false), do: args
  defp maybe_add_short(args, true), do: args ++ ["--short"]
  defp maybe_add_short(args, n) when is_integer(n), do: args ++ ["--short=#{n}"]

  defp maybe_add_flag(args, true, flag), do: args ++ [flag]
  defp maybe_add_flag(args, false, _flag), do: args

  defp maybe_add_ref(args, nil), do: args
  defp maybe_add_ref(args, ref), do: args ++ [ref]
end
