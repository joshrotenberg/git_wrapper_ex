if Code.ensure_loaded?(Forcola) do
  defmodule Git.Runner.Forcola do
    @moduledoc """
    Leak-free runner backed by [forcola](https://hex.pm/packages/forcola).

    Runs git in its own process group via a Rust shim and kills the whole
    group (SIGTERM then SIGKILL) on timeout or BEAM death. git and everything
    it spawned (ssh transports, credential helpers, hooks, sign helpers) die
    with the command, so a timed-out command does not leave a git process
    holding `.git/index.lock` or racing the caller.

    This is the default runner (`Git.Config` sets `runner: :forcola`). It only
    compiles when the optional `Forcola` dependency is available; add it to your
    dependencies to get leak-free execution.

    forcola is POSIX-only (macOS and Linux). On other platforms, or when the
    dependency is absent, the runner falls back to `Git.Runner.SystemCmd`.

    ## Feeding stdin

    When the runner opts carry `:input` (a binary or iodata), the bytes are
    written to git's stdin exactly as given and stdin is then closed, so
    commands that read stdin to EOF (`hash-object --stdin`, `mktree`,
    `stripspace`, `patch-id`, `cat-file --batch`) work. `Forcola.run/2` has no
    stdin channel, so the input path drives forcola's shim wire protocol
    (`Forcola.Shim`) directly: SPAWN, one STDIN frame with the raw bytes, then
    EOF. Output and exit handling match the no-input path, including the
    group-kill-on-timeout guarantee. The no-input path stays on
    `Forcola.run/2` unchanged.
    """

    @behaviour Git.Runner

    alias Forcola.Result
    alias Forcola.Shim

    # Elixir-side backstop for the input path, mirroring the margins
    # `Forcola.run/2` uses: the shim enforces `timeout_ms` and confirms group
    # death within its own kill grace before reporting EXIT, so this only
    # fires if the shim itself never reports back.
    @kill_grace_ms 5_000
    @backstop_margin_ms 5_000

    @impl true
    def run(binary, args, opts) do
      {timeout, opts} = Keyword.pop!(opts, :timeout)
      {input, cmd_opts} = Keyword.pop(opts, :input)

      if input do
        run_with_input(binary, args, input, timeout, cmd_opts)
      else
        run_bounded(binary, args, timeout, cmd_opts)
      end
    end

    defp run_bounded(binary, args, timeout, cmd_opts) do
      case Forcola.run([binary | args], spawn_opts(timeout, cmd_opts)) do
        {:ok, %Result{status: status, stdout: stdout}} when is_integer(status) ->
          {:ok, {stdout, status}}

        {:ok, %Result{status: {:signal, signal}}} ->
          {:error, {:signal, signal}}

        {:error, {:timeout, _partial}} ->
          {:error, :timeout}

        {:error, reason} ->
          {:error, reason}
      end
    end

    defp run_with_input(binary, args, input, timeout, cmd_opts) do
      case Shim.open() do
        {:ok, port} ->
          try do
            payload = Shim.encode_spawn([binary | args], spawn_opts(timeout, cmd_opts))
            Shim.send_frame(port, Shim.tag_spawn(), payload)
            Shim.send_frame(port, Shim.tag_stdin(), input)
            Shim.send_frame(port, Shim.tag_eof())

            deadline =
              System.monotonic_time(:millisecond) + timeout + @kill_grace_ms + @backstop_margin_ms

            collect(port, [], deadline)
          after
            close_port(port)
          end

        {:error, :not_found} ->
          {:error, {:spawn, :shim_not_found}}
      end
    end

    defp spawn_opts(timeout, cmd_opts) do
      [timeout_ms: timeout, merge_stderr: true] ++ Keyword.take(cmd_opts, [:cd, :env])
    end

    defp collect(port, stdout_acc, deadline) do
      remaining = deadline - System.monotonic_time(:millisecond)

      receive do
        {^port, {:data, <<tag, payload::binary>>}} ->
          handle_frame(port, tag, payload, stdout_acc, deadline)

        {^port, {:exit_status, _status}} ->
          {:error, {:spawn, {:shim_exited, IO.iodata_to_binary(stdout_acc)}}}
      after
        max(remaining, 0) -> {:error, :timeout}
      end
    end

    defp handle_frame(port, tag, payload, stdout_acc, deadline) do
      cond do
        # merge_stderr routes stderr into the stdout stream, but fold any stray
        # stderr frame in too so the collected output matches the no-input path.
        tag in [Shim.tag_stdout(), Shim.tag_stderr()] ->
          collect(port, [stdout_acc | payload], deadline)

        tag == Shim.tag_exit() ->
          finish(Shim.decode_exit(payload), stdout_acc)

        tag == Shim.tag_error() ->
          {:error, {:spawn, Shim.decode_error(payload)}}

        true ->
          collect(port, stdout_acc, deadline)
      end
    end

    defp finish({_status, true}, _stdout_acc), do: {:error, :timeout}

    defp finish({status, false}, stdout_acc) when is_integer(status) do
      {:ok, {IO.iodata_to_binary(stdout_acc), status}}
    end

    defp finish({{:signal, signal}, false}, _stdout_acc), do: {:error, {:signal, signal}}

    defp close_port(port) do
      if Port.info(port) != nil do
        Port.close(port)
      end
    catch
      :error, :badarg -> :ok
    end
  end
end
