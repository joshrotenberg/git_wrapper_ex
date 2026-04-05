defmodule Git.Commands.Fsck do
  @moduledoc """
  Implements the `Git.Command` behaviour for `git fsck`.

  Verifies the connectivity and validity of objects in the database.
  Parses fsck output into a list of issue maps describing dangling,
  missing, or broken objects.
  """

  @behaviour Git.Command

  @type t :: %__MODULE__{
          full: boolean(),
          strict: boolean(),
          unreachable: boolean(),
          dangling: boolean(),
          no_dangling: boolean(),
          no_reflogs: boolean(),
          connectivity_only: boolean(),
          root: boolean(),
          lost_found: boolean(),
          name_objects: boolean(),
          verbose: boolean(),
          progress: boolean(),
          no_progress: boolean()
        }

  defstruct full: false,
            strict: false,
            unreachable: false,
            dangling: false,
            no_dangling: false,
            no_reflogs: false,
            connectivity_only: false,
            root: false,
            lost_found: false,
            name_objects: false,
            verbose: false,
            progress: false,
            no_progress: false

  @doc """
  Returns the argument list for `git fsck`.

  ## Examples

      iex> Git.Commands.Fsck.args(%Git.Commands.Fsck{})
      ["fsck"]

      iex> Git.Commands.Fsck.args(%Git.Commands.Fsck{full: true, strict: true})
      ["fsck", "--full", "--strict"]

      iex> Git.Commands.Fsck.args(%Git.Commands.Fsck{unreachable: true, no_reflogs: true})
      ["fsck", "--unreachable", "--no-reflogs"]

      iex> Git.Commands.Fsck.args(%Git.Commands.Fsck{connectivity_only: true})
      ["fsck", "--connectivity-only"]

      iex> Git.Commands.Fsck.args(%Git.Commands.Fsck{lost_found: true, name_objects: true})
      ["fsck", "--lost-found", "--name-objects"]

  """
  @spec args(t()) :: [String.t()]
  @impl true
  def args(%__MODULE__{} = command) do
    ["fsck"]
    |> maybe_add_flag(command.full, "--full")
    |> maybe_add_flag(command.strict, "--strict")
    |> maybe_add_flag(command.unreachable, "--unreachable")
    |> maybe_add_flag(command.dangling, "--dangling")
    |> maybe_add_flag(command.no_dangling, "--no-dangling")
    |> maybe_add_flag(command.no_reflogs, "--no-reflogs")
    |> maybe_add_flag(command.connectivity_only, "--connectivity-only")
    |> maybe_add_flag(command.root, "--root")
    |> maybe_add_flag(command.lost_found, "--lost-found")
    |> maybe_add_flag(command.name_objects, "--name-objects")
    |> maybe_add_flag(command.verbose, "--verbose")
    |> maybe_add_flag(command.progress, "--progress")
    |> maybe_add_flag(command.no_progress, "--no-progress")
  end

  @doc """
  Parses the output of `git fsck`.

  On success (exit code 0), parses each line into an issue map with
  `:type`, `:object_type`, and `:sha` keys. Lines that do not match the
  expected format (e.g. informational messages) are silently ignored.

  Returns `{:ok, [map()]}` on success or `{:error, {stdout, exit_code}}`
  on failure.
  """
  @spec parse_output(String.t(), non_neg_integer()) ::
          {:ok, [map()]} | {:error, {String.t(), non_neg_integer()}}
  @impl true
  def parse_output(stdout, 0) do
    issues =
      stdout
      |> String.split("\n", trim: true)
      |> Enum.map(&parse_fsck_line/1)
      |> Enum.reject(&is_nil/1)

    {:ok, issues}
  end

  def parse_output(stdout, exit_code), do: {:error, {stdout, exit_code}}

  defp parse_fsck_line(line) do
    line = String.trim(line)

    case String.split(line, " ", parts: 3) do
      [type, object_type, sha] ->
        %{type: type, object_type: object_type, sha: sha}

      _ ->
        nil
    end
  end

  defp maybe_add_flag(args, true, flag), do: args ++ [flag]
  defp maybe_add_flag(args, false, _flag), do: args
end
