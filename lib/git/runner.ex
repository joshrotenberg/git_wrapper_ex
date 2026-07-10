defmodule Git.Runner do
  @moduledoc """
  Behaviour describing how git commands are executed.

  `Git.Command.run/3` dispatches every git invocation through a runner. The
  default is `Git.Runner.SystemCmd`, which uses `System.cmd/3` and matches the
  historical behavior of this library: no extra dependencies, works on every
  platform.

  For leak-free execution, add [forcola](https://hex.pm/packages/forcola) to
  your dependencies and select the forcola runner via `Git.Config`:

      config = Git.Config.new(runner: :forcola)
      {:ok, status} = Git.status(config: config)

  `System.cmd/3` implements timeouts by closing the Erlang port, which only
  closes pipes and never signals the OS process. A timed-out git command, and
  anything it spawned (ssh transports, credential helpers, hooks, sign
  helpers), keeps running and can hold repository locks. `Git.Runner.Forcola`
  runs git in its own process group and kills the whole group on timeout, so a
  `{:error, :timeout}` means git is actually gone.

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
