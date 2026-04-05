defmodule Git.Commands.Submodule do
  @moduledoc """
  Implements the `Git.Command` behaviour for `git submodule`.

  Supports status (default), init, update, add, deinit, sync, summary,
  set-branch, and set-url subcommands.

  The `foreach` subcommand is intentionally not supported because it requires
  an arbitrary shell command string, which does not fit the structured command
  model and would introduce shell injection concerns.
  """

  @behaviour Git.Command

  alias Git.SubmoduleEntry

  @type t :: %__MODULE__{
          status: boolean(),
          init: boolean(),
          update: boolean(),
          add_url: String.t() | nil,
          add_path: String.t() | nil,
          deinit: String.t() | nil,
          sync: boolean(),
          summary: boolean(),
          set_branch: String.t() | nil,
          set_url: String.t() | nil,
          path: String.t() | nil,
          recursive: boolean(),
          force: boolean(),
          remote: boolean(),
          merge: boolean(),
          rebase: boolean(),
          depth: non_neg_integer() | nil,
          reference: String.t() | nil,
          name: String.t() | nil,
          branch: String.t() | nil,
          quiet: boolean(),
          all: boolean()
        }

  defstruct status: true,
            init: false,
            update: false,
            add_url: nil,
            add_path: nil,
            deinit: nil,
            sync: false,
            summary: false,
            set_branch: nil,
            set_url: nil,
            path: nil,
            recursive: false,
            force: false,
            remote: false,
            merge: false,
            rebase: false,
            depth: nil,
            reference: nil,
            name: nil,
            branch: nil,
            quiet: false,
            all: false

  # Process dictionary key used to communicate the operation mode from args/1
  # to parse_output/2. Both are called from the same process inside
  # Git.Command.run/3, so this is safe even with async tests.
  @mode_key :__git_submodule_mode__

  @doc """
  Returns the argument list for `git submodule`.

  - If `:add_url` is set, builds `git submodule add [options] <url> [<path>]`.
  - If `:deinit` is set, builds `git submodule deinit [--force] [--all] <path>`.
  - If `:init` is true, builds `git submodule init [<path>]`.
  - If `:update` is true, builds `git submodule update [options] [<path>]`.
  - If `:sync` is true, builds `git submodule sync [--recursive] [<path>]`.
  - If `:summary` is true, builds `git submodule summary [<path>]`.
  - If `:set_branch` is set, builds `git submodule set-branch -b <branch> <path>`.
  - If `:set_url` is set, builds `git submodule set-url <path> <url>`.
  - Otherwise, shows status with `git submodule status [--recursive] [<path>]`.

  ## Examples

      iex> Git.Commands.Submodule.args(%Git.Commands.Submodule{})
      ["submodule", "status"]

      iex> Git.Commands.Submodule.args(%Git.Commands.Submodule{init: true})
      ["submodule", "init"]

      iex> Git.Commands.Submodule.args(%Git.Commands.Submodule{update: true, recursive: true})
      ["submodule", "update", "--recursive"]

      iex> Git.Commands.Submodule.args(%Git.Commands.Submodule{add_url: "https://example.com/lib.git", add_path: "vendor/lib"})
      ["submodule", "add", "https://example.com/lib.git", "vendor/lib"]

      iex> Git.Commands.Submodule.args(%Git.Commands.Submodule{deinit: "vendor/lib", force: true})
      ["submodule", "deinit", "--force", "vendor/lib"]

      iex> Git.Commands.Submodule.args(%Git.Commands.Submodule{sync: true, recursive: true})
      ["submodule", "sync", "--recursive"]

  """
  @spec args(t()) :: [String.t()]
  @impl true
  def args(%__MODULE__{add_url: url} = command) when is_binary(url) do
    Process.put(@mode_key, :mutation)

    base = ["submodule", "add"]

    base
    |> maybe_add_flag(command.quiet, "-q")
    |> maybe_add_flag(command.force, "--force")
    |> maybe_add_option("--depth", command.depth)
    |> maybe_add_option("--reference", command.reference)
    |> maybe_add_option("--name", command.name)
    |> maybe_add_option("-b", command.branch)
    |> Kernel.++([url])
    |> maybe_add_value(command.add_path)
  end

  def args(%__MODULE__{deinit: path} = command) when is_binary(path) do
    Process.put(@mode_key, :mutation)

    ["submodule", "deinit"]
    |> maybe_add_flag(command.quiet, "-q")
    |> maybe_add_flag(command.force, "--force")
    |> maybe_add_flag(command.all, "--all")
    |> Kernel.++([path])
  end

  def args(%__MODULE__{set_branch: branch_name} = command) when is_binary(branch_name) do
    Process.put(@mode_key, :mutation)

    ["submodule", "set-branch", "-b", branch_name]
    |> maybe_add_value(command.path)
  end

  def args(%__MODULE__{set_url: url} = command) when is_binary(url) do
    Process.put(@mode_key, :mutation)

    ["submodule", "set-url"]
    |> maybe_add_value(command.path)
    |> Kernel.++([url])
  end

  def args(%__MODULE__{init: true} = command) do
    Process.put(@mode_key, :mutation)

    ["submodule", "init"]
    |> maybe_add_flag(command.quiet, "-q")
    |> maybe_add_value(command.path)
  end

  def args(%__MODULE__{update: true} = command) do
    Process.put(@mode_key, :mutation)

    ["submodule", "update"]
    |> maybe_add_flag(command.quiet, "-q")
    |> maybe_add_flag(command.force, "--force")
    |> maybe_add_flag(command.remote, "--remote")
    |> maybe_add_flag(command.merge, "--merge")
    |> maybe_add_flag(command.rebase, "--rebase")
    |> maybe_add_flag(command.recursive, "--recursive")
    |> maybe_add_option("--depth", command.depth)
    |> maybe_add_option("--reference", command.reference)
    |> maybe_add_value(command.path)
  end

  def args(%__MODULE__{sync: true} = command) do
    Process.put(@mode_key, :mutation)

    ["submodule", "sync"]
    |> maybe_add_flag(command.quiet, "-q")
    |> maybe_add_flag(command.recursive, "--recursive")
    |> maybe_add_value(command.path)
  end

  def args(%__MODULE__{summary: true} = command) do
    Process.put(@mode_key, :summary)

    ["submodule", "summary"]
    |> maybe_add_value(command.path)
  end

  def args(%__MODULE__{} = command) do
    Process.put(@mode_key, :list)

    ["submodule", "status"]
    |> maybe_add_flag(command.recursive, "--recursive")
    |> maybe_add_value(command.path)
  end

  @doc """
  Parses the output of `git submodule`.

  For status operations (exit 0), parses each line into a `Git.SubmoduleEntry`
  struct. For mutation operations (exit 0), returns `{:ok, :done}`. For summary
  operations (exit 0), returns `{:ok, stdout}` with the raw summary text.
  On failure, returns `{:error, {stdout, exit_code}}`.
  """
  @spec parse_output(String.t(), non_neg_integer()) ::
          {:ok, [SubmoduleEntry.t()]}
          | {:ok, :done}
          | {:ok, String.t()}
          | {:error, {String.t(), non_neg_integer()}}
  @impl true
  def parse_output(stdout, 0) do
    mode = Process.get(@mode_key, :list)

    case mode do
      :mutation ->
        {:ok, :done}

      :summary ->
        {:ok, stdout}

      :list ->
        if String.trim(stdout) == "" do
          {:ok, []}
        else
          {:ok, SubmoduleEntry.parse(stdout)}
        end
    end
  end

  def parse_output(stdout, exit_code), do: {:error, {stdout, exit_code}}

  @spec maybe_add_flag([String.t()], boolean(), String.t()) :: [String.t()]
  defp maybe_add_flag(args, false, _flag), do: args
  defp maybe_add_flag(args, true, flag), do: args ++ [flag]

  @spec maybe_add_option([String.t()], String.t(), term()) :: [String.t()]
  defp maybe_add_option(args, _flag, nil), do: args

  defp maybe_add_option(args, flag, value) when is_integer(value),
    do: args ++ [flag, Integer.to_string(value)]

  defp maybe_add_option(args, flag, value) when is_binary(value),
    do: args ++ [flag, value]

  @spec maybe_add_value([String.t()], String.t() | nil) :: [String.t()]
  defp maybe_add_value(args, nil), do: args
  defp maybe_add_value(args, value), do: args ++ [value]
end
