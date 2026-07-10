defmodule Git.Config do
  @moduledoc """
  Configuration for the git CLI wrapper.

  Holds the path to the git binary, working directory, environment variables,
  and timeout settings used when executing git commands.

  ## Controlling identity, dates, and the index

  Per-call author/committer identity and dates, and the index file, are set
  through the `:env` and `:extra_config` fields rather than dedicated options,
  since git reads them from the environment and per-invocation config:

    * Author/committer **dates** (note `commit --date` sets only the author date,
      while the committer date is separate):

          Git.Config.new(env: [
            {"GIT_AUTHOR_DATE", "2020-01-01T00:00:00"},
            {"GIT_COMMITTER_DATE", "2020-01-01T00:00:00"}
          ])

    * Author/committer **identity**, either via the environment or, without
      mutating repo config, via `-c` using `:extra_config`:

          Git.Config.new(extra_config: [
            {"user.name", "A U Thor"},
            {"user.email", "author@example.com"}
          ])

    * A scratch **index** for building commits off to the side (pairs with
      `write_tree/1` and `commit_tree/1`):

          Git.Config.new(env: [{"GIT_INDEX_FILE", "/tmp/scratch.index"}])

  Any `GIT_*` variable can be passed through `:env`; entries there override the
  built-in defaults.
  """

  @default_timeout 30_000
  @default_runner :forcola

  # Environment defaults applied to every git invocation, overridable via the
  # `:env` config option. `GIT_TERMINAL_PROMPT=0` makes git fail fast instead of
  # blocking on a credential prompt it can never receive under `System.cmd/3`.
  @default_env [{"GIT_TERMINAL_PROMPT", "0"}]

  @typedoc """
  How git commands are executed.

    * `:forcola` - the default, `Git.Runner.Forcola`, which runs git in its own
      process group and kills the whole group on timeout, so a timed-out command
      and its children (hooks, credential helpers, transports) do not leak.
      Requires the optional `:forcola` dependency and a supported platform
      (macOS or Linux); it falls back to `:system_cmd` when forcola is not
      loaded (for example on Windows or when the dependency is absent).
    * `:system_cmd` - `System.cmd/3` via `Git.Runner.SystemCmd`. No extra
      dependency and works everywhere, but a timed-out command abandons the OS
      process rather than killing it.
    * any module implementing the `Git.Runner` behaviour.
  """
  @type runner :: :system_cmd | :forcola | module()

  @type t :: %__MODULE__{
          binary: String.t(),
          working_dir: String.t() | nil,
          env: [{String.t(), String.t()}],
          timeout: pos_integer(),
          runner: runner(),
          extra_config: [{String.t(), String.t()}]
        }

  @enforce_keys [:binary]
  defstruct [
    :binary,
    :working_dir,
    env: [],
    timeout: @default_timeout,
    runner: @default_runner,
    extra_config: []
  ]

  @doc """
  Creates a new `Git.Config` struct.

  ## Options

    * `:binary` - path to the git executable (default: auto-detected)
    * `:working_dir` - working directory for git commands (default: `nil`, uses current directory)
    * `:env` - list of `{key, value}` tuples for environment variables (default: `[]`)
    * `:timeout` - command timeout in milliseconds (default: `#{@default_timeout}`)
    * `:runner` - how commands are executed (default: `#{inspect(@default_runner)}`).
      See the `t:runner/0` type.
    * `:extra_config` - list of `{key, value}` tuples emitted as `git -c key=value`
      before every subcommand, to set config per-invocation without mutating repo
      config (default: `[]`)

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

      iex> config = Git.Config.new(extra_config: [{"merge.conflictStyle", "diff3"}])
      iex> Git.Config.base_args(config)
      ["-c", "merge.conflictStyle=diff3"]

  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    %__MODULE__{
      binary: Keyword.get(opts, :binary, find_binary()),
      working_dir: Keyword.get(opts, :working_dir),
      env: Keyword.get(opts, :env, []),
      timeout: Keyword.get(opts, :timeout, @default_timeout),
      runner: Keyword.get(opts, :runner, @default_runner),
      extra_config: Keyword.get(opts, :extra_config, [])
    }
  end

  @doc """
  Returns the base arguments prepended to every git command.

  Emits a `-c key=value` pair for each entry in the config's `:extra_config`, so
  a caller can set config per-invocation (for example `merge.conflictStyle` or
  `commit.gpgsign`) without mutating repo config. Returns `[]` when
  `:extra_config` is empty.
  """
  @spec base_args(t()) :: [String.t()]
  def base_args(%__MODULE__{extra_config: extra_config}) do
    Enum.flat_map(extra_config, fn {key, value} -> ["-c", "#{key}=#{value}"] end)
  end

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
