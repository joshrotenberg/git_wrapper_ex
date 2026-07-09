defmodule Git.Config do
  @moduledoc """
  Configuration for the git CLI wrapper.

  Holds the path to the git binary, working directory, environment variables,
  and timeout settings used when executing git commands.
  """

  @default_timeout 30_000
  @default_runner :system_cmd

  # Environment defaults applied to every git invocation, overridable via the
  # `:env` config option. `GIT_TERMINAL_PROMPT=0` makes git fail fast instead of
  # blocking on a credential prompt it can never receive under `System.cmd/3`.
  @default_env [{"GIT_TERMINAL_PROMPT", "0"}]

  @typedoc """
  How git commands are executed.

    * `:system_cmd` - the default, `System.cmd/3` via `Git.Runner.SystemCmd`.
    * `:forcola` - `Git.Runner.Forcola`, which kills the git process group on
      timeout. Requires the optional `:forcola` dependency; falls back to
      `:system_cmd` when it is not available.
    * any module implementing the `Git.Runner` behaviour.
  """
  @type runner :: :system_cmd | :forcola | module()

  @type t :: %__MODULE__{
          binary: String.t(),
          working_dir: String.t() | nil,
          env: [{String.t(), String.t()}],
          timeout: pos_integer(),
          runner: runner()
        }

  @enforce_keys [:binary]
  defstruct [:binary, :working_dir, env: [], timeout: @default_timeout, runner: @default_runner]

  @doc """
  Creates a new `Git.Config` struct.

  ## Options

    * `:binary` - path to the git executable (default: auto-detected)
    * `:working_dir` - working directory for git commands (default: `nil`, uses current directory)
    * `:env` - list of `{key, value}` tuples for environment variables (default: `[]`)
    * `:timeout` - command timeout in milliseconds (default: `#{@default_timeout}`)
    * `:runner` - how commands are executed (default: `#{inspect(@default_runner)}`).
      See the `t:runner/0` type.

  ## Examples

      iex> config = Git.Config.new()
      iex> String.ends_with?(config.binary, "git")
      true

      iex> config = Git.Config.new(working_dir: "/tmp", timeout: 10_000)
      iex> config.working_dir
      "/tmp"
      iex> config.timeout
      10_000

      iex> config = Git.Config.new(runner: :forcola)
      iex> config.runner
      :forcola

  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    %__MODULE__{
      binary: Keyword.get(opts, :binary, find_binary()),
      working_dir: Keyword.get(opts, :working_dir),
      env: Keyword.get(opts, :env, []),
      timeout: Keyword.get(opts, :timeout, @default_timeout),
      runner: Keyword.get(opts, :runner, @default_runner)
    }
  end

  @doc """
  Returns the base arguments for all git commands.

  Git does not require any global flags, so this returns an empty list.
  """
  @spec base_args(t()) :: [String.t()]
  def base_args(%__MODULE__{}), do: []

  @doc """
  Builds the options keyword list for `System.cmd/3`.

  Includes `:cd`, `:env`, and `:stderr_to_stdout` based on the config. The
  environment always defaults `GIT_TERMINAL_PROMPT=0` so an auth-required
  command fails fast instead of hanging on a credential prompt; entries in the
  config's `:env` override the defaults on a key collision.
  """
  @spec cmd_opts(t()) :: keyword()
  def cmd_opts(%__MODULE__{} = config) do
    opts = [stderr_to_stdout: true, env: build_env(config)]

    if config.working_dir do
      Keyword.put(opts, :cd, config.working_dir)
    else
      opts
    end
  end

  # Merges the config's `:env` over the defaults, so a caller can override any
  # default (e.g. set GIT_TERMINAL_PROMPT back to "1") without duplicate keys.
  defp build_env(%__MODULE__{env: env}) do
    override_keys = Enum.map(env, fn {key, _value} -> key end)

    Enum.reject(@default_env, fn {key, _value} -> key in override_keys end) ++ env
  end

  @doc """
  Finds the git binary on the system.

  Checks the `GIT_PATH` environment variable first, then falls back to
  `System.find_executable("git")`.

  Raises if git cannot be found.
  """
  @spec find_binary() :: String.t()
  def find_binary do
    case System.get_env("GIT_PATH") do
      nil ->
        case System.find_executable("git") do
          nil -> raise "git executable not found on PATH"
          path -> path
        end

      path ->
        path
    end
  end
end
