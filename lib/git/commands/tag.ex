defmodule Git.Commands.Tag do
  @moduledoc """
  Implements the `Git.Command` behaviour for `git tag`.

  Supports listing tags (default), creating a lightweight tag, creating an
  annotated tag, and deleting a tag.
  """

  @behaviour Git.Command

  alias Git.Tag

  @type t :: %__MODULE__{
          list: boolean(),
          create: String.t() | nil,
          delete: String.t() | nil,
          message: String.t() | nil,
          ref: String.t() | nil,
          sort: String.t() | nil
        }

  defstruct list: true,
            create: nil,
            delete: nil,
            message: nil,
            ref: nil,
            sort: nil

  # Process dictionary key used to communicate the operation mode from args/1
  # to parse_output/2. Both are called from the same process inside
  # Git.Command.run/3, so this is safe even with async tests.
  @mode_key :__git_tag_mode__

  @doc """
  Returns the argument list for `git tag`.

  - If `:create` is set with `:message`, builds `git tag -a <name> -m <msg>` (annotated).
  - If `:create` is set without `:message`, builds `git tag <name>` (lightweight).
  - If `:delete` is set, builds `git tag -d <name>`.
  - Otherwise, lists tags with detailed format.

  Both create and delete accept an optional `:ref` to specify the commit.

  ## Examples

      iex> Git.Commands.Tag.args(%Git.Commands.Tag{})
      ["tag", "-l", "--format=" <> Git.Tag.format_string()]

      iex> Git.Commands.Tag.args(%Git.Commands.Tag{create: "v1.0.0"})
      ["tag", "v1.0.0"]

      iex> Git.Commands.Tag.args(%Git.Commands.Tag{create: "v1.0.0", message: "release 1.0"})
      ["tag", "-a", "v1.0.0", "-m", "release 1.0"]

      iex> Git.Commands.Tag.args(%Git.Commands.Tag{delete: "v1.0.0"})
      ["tag", "-d", "v1.0.0"]

  """
  @spec args(t()) :: [String.t()]
  @impl true
  def args(%__MODULE__{create: name, message: message, ref: ref})
      when is_binary(name) and is_binary(message) and is_binary(ref) do
    Process.put(@mode_key, :mutation)
    ["tag", "-a", name, "-m", message, ref]
  end

  def args(%__MODULE__{create: name, message: message})
      when is_binary(name) and is_binary(message) do
    Process.put(@mode_key, :mutation)
    ["tag", "-a", name, "-m", message]
  end

  def args(%__MODULE__{create: name, ref: ref}) when is_binary(name) and is_binary(ref) do
    Process.put(@mode_key, :mutation)
    ["tag", name, ref]
  end

  def args(%__MODULE__{create: name}) when is_binary(name) do
    Process.put(@mode_key, :mutation)
    ["tag", name]
  end

  def args(%__MODULE__{delete: name}) when is_binary(name) do
    Process.put(@mode_key, :mutation)
    ["tag", "-d", name]
  end

  def args(%__MODULE__{sort: sort}) when is_binary(sort) do
    Process.put(@mode_key, :list)
    ["tag", "-l", "--sort=#{sort}", "--format=#{Tag.format_string()}"]
  end

  def args(%__MODULE__{}) do
    Process.put(@mode_key, :list)
    ["tag", "-l", "--format=#{Tag.format_string()}"]
  end

  @doc """
  Parses the output of `git tag`.

  For list operations (exit 0), parses each entry into a `Git.Tag` struct.
  For create/delete operations (exit 0), returns `{:ok, :done}`.
  On failure, returns `{:error, {stdout, exit_code}}`.
  """
  @spec parse_output(String.t(), non_neg_integer()) ::
          {:ok, [Tag.t()]} | {:ok, :done} | {:error, {String.t(), non_neg_integer()}}
  @impl true
  def parse_output(stdout, 0) do
    mode = Process.get(@mode_key, :list)

    case mode do
      :mutation ->
        {:ok, :done}

      :list ->
        if String.trim(stdout) == "" do
          {:ok, []}
        else
          {:ok, Tag.parse_detailed(stdout)}
        end
    end
  end

  def parse_output(stdout, exit_code), do: {:error, {stdout, exit_code}}
end
