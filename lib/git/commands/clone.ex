defmodule Git.Commands.Clone do
  @moduledoc """
  Implements the `Git.Command` behaviour for `git clone`.

  Supports a shallow (`--depth`) or partial (`--filter`) clone, `--sparse`,
  `--single-branch`, `--no-checkout`, `--bare`, `--mirror`,
  `--recurse-submodules`, a named origin (`--origin`), repo config to set in the
  new clone (`--config`), a specific `--branch`, and an optional target
  directory.
  """

  @behaviour Git.Command

  @type t :: %__MODULE__{
          url: String.t(),
          directory: String.t() | nil,
          depth: pos_integer() | nil,
          branch: String.t() | nil,
          filter: String.t() | nil,
          origin: String.t() | nil,
          sparse: boolean(),
          single_branch: boolean(),
          no_checkout: boolean(),
          bare: boolean(),
          mirror: boolean(),
          recurse_submodules: boolean(),
          set_config: [{String.t(), String.t()}]
        }

  defstruct url: nil,
            directory: nil,
            depth: nil,
            branch: nil,
            filter: nil,
            origin: nil,
            sparse: false,
            single_branch: false,
            no_checkout: false,
            bare: false,
            mirror: false,
            recurse_submodules: false,
            set_config: []

  @doc """
  Returns the argument list for `git clone`.

  Always includes the repository URL. Optional flags are appended before the
  URL, and a target directory (when set) is appended after it.

  ## Examples

      iex> Git.Commands.Clone.args(%Git.Commands.Clone{url: "https://example.com/repo.git"})
      ["clone", "https://example.com/repo.git"]

      iex> Git.Commands.Clone.args(%Git.Commands.Clone{url: "https://example.com/repo.git", depth: 1})
      ["clone", "--depth=1", "https://example.com/repo.git"]

      iex> Git.Commands.Clone.args(%Git.Commands.Clone{url: "https://example.com/repo.git", filter: "blob:none"})
      ["clone", "--filter=blob:none", "https://example.com/repo.git"]

      iex> Git.Commands.Clone.args(%Git.Commands.Clone{url: "https://example.com/repo.git", bare: true})
      ["clone", "--bare", "https://example.com/repo.git"]

      iex> Git.Commands.Clone.args(%Git.Commands.Clone{url: "https://example.com/repo.git", directory: "my-repo"})
      ["clone", "https://example.com/repo.git", "my-repo"]

  """
  @spec args(t()) :: [String.t()]
  @impl true
  def args(%__MODULE__{} = command) do
    flags =
      []
      |> maybe_add("--depth=#{command.depth}", not is_nil(command.depth))
      |> maybe_add("--branch=#{command.branch}", not is_nil(command.branch))
      |> maybe_add("--filter=#{command.filter}", not is_nil(command.filter))
      |> maybe_add("--origin=#{command.origin}", not is_nil(command.origin))
      |> maybe_add("--sparse", command.sparse)
      |> maybe_add("--single-branch", command.single_branch)
      |> maybe_add("--no-checkout", command.no_checkout)
      |> maybe_add("--bare", command.bare)
      |> maybe_add("--mirror", command.mirror)
      |> maybe_add("--recurse-submodules", command.recurse_submodules)
      |> Kernel.++(config_flags(command.set_config))

    positional = if is_binary(command.directory), do: [command.directory], else: []

    ["clone"] ++ flags ++ [command.url] ++ positional
  end

  @doc """
  Parses the output of `git clone`.

  On success (exit code 0), returns `{:ok, :done}`.
  On failure, returns `{:error, {stdout, exit_code}}`.
  """
  @spec parse_output(String.t(), non_neg_integer()) ::
          {:ok, :done} | {:error, {String.t(), non_neg_integer()}}
  @impl true
  def parse_output(_stdout, 0), do: {:ok, :done}
  def parse_output(stdout, exit_code), do: {:error, {stdout, exit_code}}

  defp config_flags(pairs) do
    Enum.flat_map(pairs, fn {key, value} -> ["--config", "#{key}=#{value}"] end)
  end

  defp maybe_add(list, _flag, false), do: list
  defp maybe_add(list, _flag, nil), do: list
  defp maybe_add(list, flag, _condition), do: list ++ [flag]
end
