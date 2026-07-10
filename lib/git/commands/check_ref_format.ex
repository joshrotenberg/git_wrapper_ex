defmodule Git.Commands.CheckRefFormat do
  @moduledoc """
  Implements the `Git.Command` behaviour for `git check-ref-format`.

  Validates (and optionally normalizes) a ref name. This command uses its exit
  code as data: `0` means the ref is well-formed, a non-zero code means it is
  not. That signal is translated into `{:ok, _}` / `{:error, :invalid_ref}`
  rather than a generic error.

  ## Modes

    * `:normalize` normalizes the ref and prints it on success
    * `:branch` validates a branch-name shorthand and prints its expansion
    * `:allow_onelevel` accepts single-level refs (e.g. `HEAD`)
  """

  @behaviour Git.Command

  @type t :: %__MODULE__{
          ref: String.t() | nil,
          normalize: boolean(),
          branch: boolean(),
          allow_onelevel: boolean()
        }

  defstruct ref: nil,
            normalize: false,
            branch: false,
            allow_onelevel: false

  @doc """
  Returns the argument list for `git check-ref-format`.

  ## Examples

      iex> Git.Commands.CheckRefFormat.args(%Git.Commands.CheckRefFormat{ref: "refs/heads/main"})
      ["check-ref-format", "refs/heads/main"]

      iex> Git.Commands.CheckRefFormat.args(%Git.Commands.CheckRefFormat{ref: "refs/heads//main", normalize: true})
      ["check-ref-format", "--normalize", "refs/heads//main"]

      iex> Git.Commands.CheckRefFormat.args(%Git.Commands.CheckRefFormat{ref: "main", branch: true})
      ["check-ref-format", "--branch", "main"]

      iex> Git.Commands.CheckRefFormat.args(%Git.Commands.CheckRefFormat{ref: "HEAD", allow_onelevel: true})
      ["check-ref-format", "--allow-onelevel", "HEAD"]

  """
  @spec args(t()) :: [String.t()]
  @impl true
  def args(%__MODULE__{ref: ref} = command) do
    ["check-ref-format"]
    |> maybe_add_flag(command.normalize, "--normalize")
    |> maybe_add_flag(command.allow_onelevel, "--allow-onelevel")
    |> maybe_add_flag(command.branch, "--branch")
    |> Kernel.++([ref])
  end

  @doc """
  Parses the output of `git check-ref-format`.

  - Exit `0` with output (normalize/branch modes) returns `{:ok, normalized}`.
  - Exit `0` with no output returns `{:ok, true}`.
  - Exit `1` (and the `--branch` invalid-name die at exit `128`) returns
    `{:error, :invalid_ref}`.
  - Any other non-zero exit (e.g. a usage error) returns
    `{:error, {stdout, exit_code}}`.
  """
  @spec parse_output(String.t(), non_neg_integer()) ::
          {:ok, true | String.t()} | {:error, :invalid_ref | {String.t(), non_neg_integer()}}
  @impl true
  def parse_output(stdout, 0) do
    case String.trim(stdout) do
      "" -> {:ok, true}
      normalized -> {:ok, normalized}
    end
  end

  def parse_output(_stdout, 1), do: {:error, :invalid_ref}

  def parse_output(stdout, exit_code) do
    if invalid_branch_name?(stdout) do
      {:error, :invalid_ref}
    else
      {:error, {stdout, exit_code}}
    end
  end

  # `git check-ref-format --branch <bad>` dies with exit 128 and this message,
  # which is still the "ref is not valid" signal rather than a usage error.
  defp invalid_branch_name?(stdout) do
    String.contains?(stdout, "is not a valid branch name")
  end

  defp maybe_add_flag(args, true, flag), do: args ++ [flag]
  defp maybe_add_flag(args, false, _flag), do: args
end
