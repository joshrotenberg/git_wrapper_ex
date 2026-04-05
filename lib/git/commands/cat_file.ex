defmodule Git.Commands.CatFile do
  @moduledoc """
  Implements the `Git.Command` behaviour for `git cat-file`.

  Provides content or type/size information for repository objects.
  Supports pretty-printing object contents, querying object type or size,
  and checking whether an object exists.

  Interactive and batch modes are intentionally not supported because they
  require stdin interaction which cannot be driven programmatically.
  """

  @behaviour Git.Command

  @type t :: %__MODULE__{
          object: String.t() | nil,
          type: boolean(),
          size: boolean(),
          print: boolean(),
          exists: boolean(),
          textconv: boolean(),
          filters: boolean()
        }

  defstruct object: nil,
            type: false,
            size: false,
            print: false,
            exists: false,
            textconv: false,
            filters: false

  # Process dictionary key used to communicate the output mode from args/1
  # to parse_output/2. Both are called from the same process inside
  # Git.Command.run/3, so this is safe even with async tests.
  @mode_key :__git_cat_file_mode__

  @doc """
  Returns the argument list for `git cat-file`.

  Builds the argument list from the struct fields. Exactly one of the mode
  flags (`:type`, `:size`, `:print`, `:exists`) should be set, or none for
  the default pretty-print behaviour.

  ## Examples

      iex> Git.Commands.CatFile.args(%Git.Commands.CatFile{object: "HEAD", type: true})
      ["cat-file", "-t", "HEAD"]

      iex> Git.Commands.CatFile.args(%Git.Commands.CatFile{object: "HEAD", size: true})
      ["cat-file", "-s", "HEAD"]

      iex> Git.Commands.CatFile.args(%Git.Commands.CatFile{object: "HEAD", print: true})
      ["cat-file", "-p", "HEAD"]

      iex> Git.Commands.CatFile.args(%Git.Commands.CatFile{object: "HEAD", exists: true})
      ["cat-file", "-e", "HEAD"]

      iex> Git.Commands.CatFile.args(%Git.Commands.CatFile{object: "HEAD", textconv: true})
      ["cat-file", "--textconv", "HEAD"]

      iex> Git.Commands.CatFile.args(%Git.Commands.CatFile{object: "HEAD", filters: true})
      ["cat-file", "--filters", "HEAD"]

  """
  @spec args(t()) :: [String.t()]
  @impl true
  def args(%__MODULE__{type: true} = command) do
    Process.put(@mode_key, :type)
    ["cat-file", "-t", command.object]
  end

  def args(%__MODULE__{size: true} = command) do
    Process.put(@mode_key, :size)
    ["cat-file", "-s", command.object]
  end

  def args(%__MODULE__{print: true} = command) do
    Process.put(@mode_key, :print)
    ["cat-file", "-p", command.object]
  end

  def args(%__MODULE__{exists: true} = command) do
    Process.put(@mode_key, :exists)
    ["cat-file", "-e", command.object]
  end

  def args(%__MODULE__{textconv: true} = command) do
    Process.put(@mode_key, :print)
    ["cat-file", "--textconv", command.object]
  end

  def args(%__MODULE__{filters: true} = command) do
    Process.put(@mode_key, :print)
    ["cat-file", "--filters", command.object]
  end

  def args(%__MODULE__{} = command) do
    Process.put(@mode_key, :print)
    ["cat-file", "-p", command.object]
  end

  @doc """
  Parses the output of `git cat-file`.

  - For `:type` mode, returns `{:ok, atom}` where atom is one of
    `:blob`, `:tree`, `:commit`, or `:tag`.
  - For `:size` mode, returns `{:ok, integer}`.
  - For `:print` mode (including textconv and filters), returns
    `{:ok, String.t()}`.
  - For `:exists` mode, exit code 0 returns `{:ok, true}` and exit
    code 1 returns `{:ok, false}` (not an error).
  """
  @spec parse_output(String.t(), non_neg_integer()) ::
          {:ok, atom()}
          | {:ok, integer()}
          | {:ok, String.t()}
          | {:ok, boolean()}
          | {:error, {String.t(), non_neg_integer()}}
  @impl true
  def parse_output(stdout, exit_code) do
    mode = Process.get(@mode_key, :print)

    case {mode, exit_code} do
      {:exists, 0} ->
        {:ok, true}

      {:exists, 1} ->
        {:ok, false}

      {:type, 0} ->
        {:ok, stdout |> String.trim() |> String.to_atom()}

      {:size, 0} ->
        {:ok, stdout |> String.trim() |> String.to_integer()}

      {:print, 0} ->
        {:ok, String.trim(stdout)}

      {_, exit_code} when exit_code != 0 ->
        {:error, {stdout, exit_code}}
    end
  end
end
