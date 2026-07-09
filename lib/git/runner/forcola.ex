if Code.ensure_loaded?(Forcola) do
  defmodule Git.Runner.Forcola do
    @moduledoc """
    Leak-free runner backed by [forcola](https://hex.pm/packages/forcola).

    Runs git in its own process group via a Rust shim and kills the whole
    group (SIGTERM then SIGKILL) on timeout or BEAM death. git and everything
    it spawned (ssh transports, credential helpers, hooks, sign helpers) die
    with the command, so a timed-out command does not leave a git process
    holding `.git/index.lock` or racing the caller.

    This module only compiles when `Forcola` is available. Add it to your
    dependencies and select this runner with `Git.Config.new(runner: :forcola)`.

    forcola is POSIX-only (macOS and Linux). On other platforms keep the
    default `Git.Runner.SystemCmd`.
    """

    @behaviour Git.Runner

    @impl true
    def run(binary, args, opts) do
      {timeout, cmd_opts} = Keyword.pop!(opts, :timeout)

      forcola_opts =
        [timeout_ms: timeout, merge_stderr: true] ++ Keyword.take(cmd_opts, [:cd, :env])

      case Forcola.run([binary | args], forcola_opts) do
        {:ok, %Forcola.Result{status: status, stdout: stdout}} when is_integer(status) ->
          {:ok, {stdout, status}}

        {:ok, %Forcola.Result{status: {:signal, signal}}} ->
          {:error, {:signal, signal}}

        {:error, {:timeout, _partial}} ->
          {:error, :timeout}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end
end
