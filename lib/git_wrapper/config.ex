defmodule GitWrapper.Config do
  @moduledoc """
  Configuration for the git CLI wrapper.

  Holds the path to the git binary, working directory, environment variables,
  and timeout settings used when executing git commands.
  """

  @default_timeout 30_000

  @type t :: %__MODULE__{
          binary: String.t(),
          working_dir: String.t() | nil,
          env: [{String.t(), String.t()}],
          timeout: pos_integer()
        }

  @enforce_keys [:binary]
  defstruct [:binary, :working_dir, env: [], timeout: @default_timeout]

  @doc """
  Creates a new `GitWrapper.Config` struct.

  ## Options

    * `:binary` - path to the git executable (default: auto-detected)
    * `:working_dir` - working directory for git commands (default: `nil`, uses current directory)
    * `:env` - list of `{key, value}` tuples for environment variables (default: `[]`)
    * `:timeout` - command timeout in milliseconds (default: `#{@default_timeout}`)

  ## Examples

      iex> config = GitWrapper.Config.new()
      iex> String.ends_with?(config.binary, "git")
      true

      iex> config = GitWrapper.Config.new(working_dir: "/tmp", timeout: 10_000)
      iex> config.working_dir
      "/tmp"
      iex> config.timeout
      10_000

  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    %__MODULE__{
      binary: Keyword.get(opts, :binary, find_binary()),
      working_dir: Keyword.get(opts, :working_dir),
      env: Keyword.get(opts, :env, []),
      timeout: Keyword.get(opts, :timeout, @default_timeout)
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

  Includes `:cd`, `:env`, and `:stderr_to_stdout` based on the config.
  """
  @spec cmd_opts(t()) :: keyword()
  def cmd_opts(%__MODULE__{} = config) do
    opts = [stderr_to_stdout: true]

    opts =
      if config.working_dir do
        Keyword.put(opts, :cd, config.working_dir)
      else
        opts
      end

    opts =
      if config.env != [] do
        Keyword.put(opts, :env, config.env)
      else
        opts
      end

    opts
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
