defmodule Git.Runner do
  @moduledoc """
  Behaviour describing how git commands are executed.

  `Git.Command.run/3` dispatches every git invocation through a runner. The
  default is `Git.Runner.Forcola`, which runs git in its own process group and
  kills the whole group on timeout, so a timed-out command and its children do
  not leak. It requires the optional [forcola](https://hex.pm/packages/forcola)
  dependency and a supported platform (macOS or Linux), and falls back to
  `Git.Runner.SystemCmd` when forcola is unavailable (for example on Windows or
  when the dependency is not installed).

  `Git.Runner.SystemCmd` uses `System.cmd/3`: no extra dependencies, works on
  every platform, but a timed-out command abandons the OS process rather than
  killing it. To force it explicitly:

      config = Git.Config.new(runner: :system_cmd)
      {:ok, status} = Git.status(config: config)

  `System.cmd/3` implements timeouts by closing the Erlang port, which only
  closes pipes and never signals the OS process. A timed-out git command, and
  anything it spawned (ssh transports, credential helpers, hooks, sign
  helpers), keeps running and can hold repository locks. That leak is why
  `Git.Runner.Forcola` is the default: it kills the whole process group on
  timeout, so a `{:error, :timeout}` means git is actually gone.

  See `Git.Config` for the accepted `:runner` values.

  ## Custom runners

  The `:runner` value may also be any module implementing this behaviour, so a
  test or a consumer can inject its own execution strategy.
  """

  @typedoc """
  Options passed to a runner.

  Includes `:timeout` (milliseconds) plus the `System.cmd/3` options built by
  `Git.Config.cmd_opts/1` (`:stderr_to_stdout`, and optionally `:cd` and
  `:env`).

  May also include `:input`, a binary or iodata written to the command's
  stdin verbatim before stdin is closed, so a command that reads stdin to EOF
  (`hash-object --stdin`, `mktree`, `stripspace`, `patch-id`, `cat-file
  --batch`) receives it. `Git.Runner.Forcola` implements `:input`;
  `Git.Runner.SystemCmd` cannot feed stdin and returns
  `{:error, :stdin_unsupported}` when it is given.
  """
  @type opts :: keyword()

  @doc """
  Runs `binary` with `args` and `opts`, returning the git output.

  Returns `{:ok, {stdout, exit_code}}` on completion (a non-zero exit code is
  still `{:ok, _}`, matching `System.cmd/3`, so the caller decides what the
  code means), or `{:error, reason}` on timeout or a failure to run.
  """
  @callback run(binary :: String.t(), args :: [String.t()], opts :: opts()) ::
              {:ok, {stdout :: String.t(), exit_code :: non_neg_integer()}}
              | {:error, term()}
end
