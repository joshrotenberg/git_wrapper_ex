defmodule Git.Commands.Notes do
  @moduledoc """
  Implements the `Git.Command` behaviour for `git notes`.

  Supports listing notes, showing a note for a specific ref, adding notes,
  appending to existing notes, removing notes, and pruning notes for
  unreachable objects.

  Edit mode (`git notes edit`) is intentionally not supported because it
  launches an interactive editor which cannot be driven programmatically.
  """

  @behaviour Git.Command

  @type t :: %__MODULE__{
          list: boolean(),
          show: String.t() | nil,
          add: boolean(),
          append: boolean(),
          message: String.t() | nil,
          ref: String.t() | nil,
          force: boolean(),
          remove: String.t() | nil,
          prune: boolean(),
          notes_ref: String.t() | nil
        }

  defstruct list: true,
            show: nil,
            add: false,
            append: false,
            message: nil,
            ref: nil,
            force: false,
            remove: nil,
            prune: false,
            notes_ref: nil

  # Process dictionary key used to communicate the operation mode from args/1
  # to parse_output/2. Both are called from the same process inside
  # Git.Command.run/3, so this is safe even with async tests.
  @mode_key :__git_notes_mode__

  @doc """
  Returns the argument list for `git notes`.

  ## Examples

      iex> Git.Commands.Notes.args(%Git.Commands.Notes{})
      ["notes", "list"]

      iex> Git.Commands.Notes.args(%Git.Commands.Notes{show: "HEAD"})
      ["notes", "show", "HEAD"]

      iex> Git.Commands.Notes.args(%Git.Commands.Notes{add: true, message: "my note", ref: "HEAD"})
      ["notes", "add", "-m", "my note", "HEAD"]

      iex> Git.Commands.Notes.args(%Git.Commands.Notes{add: true, message: "note", ref: "HEAD", force: true})
      ["notes", "add", "-f", "-m", "note", "HEAD"]

      iex> Git.Commands.Notes.args(%Git.Commands.Notes{append: true, message: "more", ref: "HEAD"})
      ["notes", "append", "-m", "more", "HEAD"]

      iex> Git.Commands.Notes.args(%Git.Commands.Notes{remove: "HEAD"})
      ["notes", "remove", "HEAD"]

      iex> Git.Commands.Notes.args(%Git.Commands.Notes{prune: true})
      ["notes", "prune"]

      iex> Git.Commands.Notes.args(%Git.Commands.Notes{notes_ref: "custom"})
      ["notes", "--ref=custom", "list"]

  """
  @spec args(t()) :: [String.t()]
  @impl true
  def args(%__MODULE__{add: true} = command) do
    Process.put(@mode_key, :mutation)

    base = ["notes"]
    base = maybe_add_notes_ref(base, command.notes_ref)

    (base ++ ["add"])
    |> maybe_add_flag(command.force, "-f")
    |> maybe_add_message(command.message)
    |> maybe_add_ref(command.ref)
  end

  def args(%__MODULE__{append: true} = command) do
    Process.put(@mode_key, :mutation)

    base = ["notes"]
    base = maybe_add_notes_ref(base, command.notes_ref)

    (base ++ ["append"])
    |> maybe_add_message(command.message)
    |> maybe_add_ref(command.ref)
  end

  def args(%__MODULE__{remove: ref} = command) when is_binary(ref) do
    Process.put(@mode_key, :mutation)

    base = ["notes"]
    base = maybe_add_notes_ref(base, command.notes_ref)
    base ++ ["remove", ref]
  end

  def args(%__MODULE__{prune: true} = command) do
    Process.put(@mode_key, :mutation)

    base = ["notes"]
    base = maybe_add_notes_ref(base, command.notes_ref)
    base ++ ["prune"]
  end

  def args(%__MODULE__{show: ref} = command) when is_binary(ref) do
    Process.put(@mode_key, :show)

    base = ["notes"]
    base = maybe_add_notes_ref(base, command.notes_ref)
    base ++ ["show", ref]
  end

  def args(%__MODULE__{} = command) do
    Process.put(@mode_key, :list)

    base = ["notes"]
    base = maybe_add_notes_ref(base, command.notes_ref)
    base ++ ["list"]
  end

  @doc """
  Parses the output of `git notes`.

  - For `:list` mode, parses lines of "note_sha commit_sha" into a list of maps.
  - For `:show` mode, returns the note content as a string.
  - For mutation modes (add, append, remove, prune), returns `{:ok, :done}`.
  """
  @spec parse_output(String.t(), non_neg_integer()) ::
          {:ok, [map()]}
          | {:ok, String.t()}
          | {:ok, :done}
          | {:error, {String.t(), non_neg_integer()}}
  @impl true
  def parse_output(stdout, 0) do
    mode = Process.get(@mode_key, :list)

    case mode do
      :mutation ->
        {:ok, :done}

      :show ->
        {:ok, String.trim(stdout)}

      :list ->
        if String.trim(stdout) == "" do
          {:ok, []}
        else
          entries =
            stdout
            |> String.split("\n", trim: true)
            |> Enum.map(&parse_list_line/1)
            |> Enum.reject(&is_nil/1)

          {:ok, entries}
        end
    end
  end

  def parse_output(stdout, exit_code), do: {:error, {stdout, exit_code}}

  defp parse_list_line(line) do
    case String.split(String.trim(line), ~r/\s+/, parts: 2) do
      [note_sha, commit_sha] ->
        %{note_sha: note_sha, commit_sha: commit_sha}

      _ ->
        nil
    end
  end

  defp maybe_add_flag(args, true, flag), do: args ++ [flag]
  defp maybe_add_flag(args, false, _flag), do: args

  defp maybe_add_message(args, nil), do: args
  defp maybe_add_message(args, message) when is_binary(message), do: args ++ ["-m", message]

  defp maybe_add_ref(args, nil), do: args
  defp maybe_add_ref(args, ref) when is_binary(ref), do: args ++ [ref]

  defp maybe_add_notes_ref(args, nil), do: args
  defp maybe_add_notes_ref(args, ref) when is_binary(ref), do: args ++ ["--ref=#{ref}"]
end
