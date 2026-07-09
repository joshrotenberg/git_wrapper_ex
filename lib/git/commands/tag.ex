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
          file: String.t() | nil,
          force: boolean(),
          ref: String.t() | nil,
          sort: String.t() | nil,
          contains: String.t() | nil,
          points_at: String.t() | nil,
          list_glob: String.t() | nil
        }

  defstruct list: true,
            create: nil,
            delete: nil,
            message: nil,
            file: nil,
            force: false,
            ref: nil,
            sort: nil,
            contains: nil,
            points_at: nil,
            list_glob: nil

  # Process dictionary key used to communicate the operation mode from args/1
  # to parse_output/2. Both are called from the same process inside
  # Git.Command.run/3, so this is safe even with async tests.
  @mode_key :__git_tag_mode__

  @doc """
  Returns the argument list for `git tag`.

  - If `:create` is set with `:message`, builds `git tag -a <name> -m <msg>` (annotated).
  - If `:create` is set with `:file`, builds `git tag -a <name> -F <path>` (annotated
    message read from a file). `:file` takes precedence over `:message`.
  - If `:create` is set without `:message` or `:file`, builds `git tag <name>` (lightweight).
  - If `:force` is set on creation, adds `-f` so an existing tag is moved/replaced.
  - If `:delete` is set, builds `git tag -d <name>`.
  - Otherwise, lists tags with detailed format. Listing accepts `:contains`,
    `:points_at`, `:list_glob`, and `:sort` filters.

  Both create and delete accept an optional `:ref` to specify the commit.

  ## Examples

      iex> Git.Commands.Tag.args(%Git.Commands.Tag{})
      ["tag", "-l", "--format=" <> Git.Tag.format_string()]

      iex> Git.Commands.Tag.args(%Git.Commands.Tag{create: "v1.0.0"})
      ["tag", "v1.0.0"]

      iex> Git.Commands.Tag.args(%Git.Commands.Tag{create: "v1.0.0", message: "release 1.0"})
      ["tag", "-a", "v1.0.0", "-m", "release 1.0"]

      iex> Git.Commands.Tag.args(%Git.Commands.Tag{create: "v1.0.0", force: true})
      ["tag", "-f", "v1.0.0"]

      iex> Git.Commands.Tag.args(%Git.Commands.Tag{delete: "v1.0.0"})
      ["tag", "-d", "v1.0.0"]

      iex> Git.Commands.Tag.args(%Git.Commands.Tag{contains: "HEAD"})
      ["tag", "-l", "--contains", "HEAD", "--format=" <> Git.Tag.format_string()]

  """
  @spec args(t()) :: [String.t()]
  @impl true
  def args(%__MODULE__{create: name} = tag) when is_binary(name) do
    Process.put(@mode_key, :mutation)

    ["tag"]
    |> maybe_add("-f", tag.force)
    |> add_create(name, tag)
    |> maybe_add_ref(tag.ref)
  end

  def args(%__MODULE__{delete: name}) when is_binary(name) do
    Process.put(@mode_key, :mutation)
    ["tag", "-d", name]
  end

  def args(%__MODULE__{} = tag) do
    Process.put(@mode_key, :list)

    ["tag", "-l"]
    |> maybe_add_value("--contains", tag.contains)
    |> maybe_add_value("--points-at", tag.points_at)
    |> maybe_add_value("--list", tag.list_glob)
    |> maybe_add_sort(tag.sort)
    |> Kernel.++(["--format=#{Tag.format_string()}"])
  end

  # Builds the create-specific args. `:file` takes precedence over `:message`.
  defp add_create(args, name, %__MODULE__{file: file}) when is_binary(file) do
    args ++ ["-a", name, "-F", file]
  end

  defp add_create(args, name, %__MODULE__{message: message}) when is_binary(message) do
    args ++ ["-a", name, "-m", message]
  end

  defp add_create(args, name, %__MODULE__{}) do
    args ++ [name]
  end

  defp maybe_add(args, _flag, false), do: args
  defp maybe_add(args, flag, true), do: args ++ [flag]

  defp maybe_add_value(args, _flag, nil), do: args
  defp maybe_add_value(args, flag, value) when is_binary(value), do: args ++ [flag, value]

  defp maybe_add_ref(args, nil), do: args
  defp maybe_add_ref(args, ref) when is_binary(ref), do: args ++ [ref]

  defp maybe_add_sort(args, nil), do: args
  defp maybe_add_sort(args, sort) when is_binary(sort), do: args ++ ["--sort=#{sort}"]

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
