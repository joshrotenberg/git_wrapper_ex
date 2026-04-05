defmodule Git.Commands.GitConfig do
  @moduledoc """
  Implements the `Git.Command` behaviour for `git config`.

  Named `GitConfig` to avoid confusion with `Git.Config` which holds
  wrapper configuration. Supports getting, setting, unsetting, and listing
  git configuration values at local, global, or system scope.
  """

  @behaviour Git.Command

  @type t :: %__MODULE__{
          get: String.t() | nil,
          set_key: String.t() | nil,
          set_value: String.t() | nil,
          unset: String.t() | nil,
          list: boolean(),
          global: boolean(),
          local: boolean(),
          system: boolean(),
          get_regexp: String.t() | nil,
          add: boolean(),
          type: String.t() | nil,
          default: String.t() | nil,
          null_terminated: boolean(),
          name_only: boolean()
        }

  defstruct get: nil,
            set_key: nil,
            set_value: nil,
            unset: nil,
            list: false,
            global: false,
            local: false,
            system: false,
            get_regexp: nil,
            add: false,
            type: nil,
            default: nil,
            null_terminated: false,
            name_only: false

  # Process dictionary key used to communicate the operation mode from args/1
  # to parse_output/2. Both are called from the same process inside
  # Git.Command.run/3, so this is safe even with async tests.
  @mode_key :__git_config_mode__

  @doc """
  Returns the argument list for `git config`.

  - If `:get` is set, builds `git config [--global|--local|--system] [--type] [--default] <key>`.
  - If `:set_key` is set, builds `git config [--global|--local|--system] [--add] [--type] <key> <value>`.
  - If `:unset` is set, builds `git config [--global|--local|--system] --unset <key>`.
  - If `:get_regexp` is set, builds `git config [--global|--local|--system] --get-regexp <pattern>`.
  - If `:list` is true, builds `git config [--global|--local|--system] --list`.

  ## Examples

      iex> Git.Commands.GitConfig.args(%Git.Commands.GitConfig{get: "user.name"})
      ["config", "user.name"]

      iex> Git.Commands.GitConfig.args(%Git.Commands.GitConfig{set_key: "user.name", set_value: "Test"})
      ["config", "user.name", "Test"]

      iex> Git.Commands.GitConfig.args(%Git.Commands.GitConfig{list: true, local: true})
      ["config", "--local", "--list"]

      iex> Git.Commands.GitConfig.args(%Git.Commands.GitConfig{unset: "user.name"})
      ["config", "--unset", "user.name"]

  """
  @spec args(t()) :: [String.t()]
  @impl true
  def args(%__MODULE__{get: key} = command) when is_binary(key) do
    Process.put(@mode_key, :get)

    ["config"]
    |> add_scope_flags(command)
    |> maybe_add_option("--type", command.type)
    |> maybe_add_option("--default", command.default)
    |> Kernel.++([key])
  end

  def args(%__MODULE__{set_key: key, set_value: value} = command)
      when is_binary(key) and is_binary(value) do
    Process.put(@mode_key, :mutation)

    ["config"]
    |> add_scope_flags(command)
    |> maybe_add_flag(command.add, "--add")
    |> maybe_add_option("--type", command.type)
    |> Kernel.++([key, value])
  end

  def args(%__MODULE__{unset: key} = command) when is_binary(key) do
    Process.put(@mode_key, :mutation)

    ["config"]
    |> add_scope_flags(command)
    |> Kernel.++(["--unset", key])
  end

  def args(%__MODULE__{get_regexp: pattern} = command) when is_binary(pattern) do
    Process.put(@mode_key, :list)

    ["config"]
    |> add_scope_flags(command)
    |> maybe_add_flag(command.name_only, "--name-only")
    |> maybe_add_flag(command.null_terminated, "-z")
    |> Kernel.++(["--get-regexp", pattern])
  end

  def args(%__MODULE__{list: true} = command) do
    Process.put(@mode_key, :list)

    ["config"]
    |> add_scope_flags(command)
    |> maybe_add_flag(command.name_only, "--name-only")
    |> maybe_add_flag(command.null_terminated, "-z")
    |> Kernel.++(["--list"])
  end

  @doc """
  Parses the output of `git config`.

  For get operations (exit 0), returns `{:ok, trimmed_value}`.
  For list operations (exit 0), returns `{:ok, [{key, value}]}`.
  For set/unset operations (exit 0), returns `{:ok, :done}`.
  On failure, returns `{:error, {stdout, exit_code}}`.
  """
  @spec parse_output(String.t(), non_neg_integer()) ::
          {:ok, String.t()}
          | {:ok, [{String.t(), String.t()}]}
          | {:ok, :done}
          | {:error, {String.t(), non_neg_integer()}}
  @impl true
  def parse_output(stdout, 0) do
    mode = Process.get(@mode_key, :get)

    case mode do
      :get ->
        {:ok, String.trim(stdout)}

      :list ->
        entries =
          stdout
          |> String.split("\n", trim: true)
          |> Enum.map(&parse_config_line/1)

        {:ok, entries}

      :mutation ->
        {:ok, :done}
    end
  end

  def parse_output(stdout, exit_code), do: {:error, {stdout, exit_code}}

  defp parse_config_line(line) do
    case String.split(line, "=", parts: 2) do
      [key, value] -> {key, value}
      [key] -> {key, ""}
    end
  end

  defp add_scope_flags(args, command) do
    args
    |> maybe_add_flag(command.global, "--global")
    |> maybe_add_flag(command.local, "--local")
    |> maybe_add_flag(command.system, "--system")
  end

  defp maybe_add_flag(args, false, _flag), do: args
  defp maybe_add_flag(args, true, flag), do: args ++ [flag]

  defp maybe_add_option(args, _flag, nil), do: args
  defp maybe_add_option(args, flag, value), do: args ++ [flag, value]
end
