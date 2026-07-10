defmodule Git.Runner.SystemCmd do
  @moduledoc """
  Fallback runner backed by `System.cmd/3`.

  Used when the optional `:forcola` dependency is unavailable or on non-POSIX
  platforms. Runs git under a `Task` and bounds it with `Task.yield/2` plus
  `Task.shutdown/1`. This is the historical behavior of this library and needs
  no extra dependencies.

  On timeout it returns `{:error, :timeout}`, but be aware that
  `Task.shutdown/1` only closes the Erlang port: it does not signal the git OS
  process or anything git spawned, so those may keep running after the timeout.
  Use `Git.Runner.Forcola` for group-kill semantics.

  ## Stdin is not supported

  `System.cmd/3` cannot write to a child's stdin, and a plain Erlang port
  (`Port.open({:spawn_executable, _}, _)`) has no way to half-close stdin: the
  child never sees EOF while its stdout pipe stays open, so a command that
  reads stdin to EOF before producing output (`hash-object --stdin`, `mktree`,
  `stripspace`, `patch-id`, `cat-file --batch`) deadlocks. Rather than ship a
  broken stdin path, this runner returns `{:error, :stdin_unsupported}` when
  the runner opts carry `:input`. Feeding stdin requires the forcola runner
  (`Git.Config.new(runner: :forcola)`), which drives git's stdin over its shim
  wire protocol.
  """

  @behaviour Git.Runner

  @impl true
  def run(binary, args, opts) do
    {timeout, cmd_opts} = Keyword.pop!(opts, :timeout)

    case Keyword.pop(cmd_opts, :input) do
      {nil, cmd_opts} -> run_without_input(binary, args, timeout, cmd_opts)
      {_input, _cmd_opts} -> {:error, :stdin_unsupported}
    end
  end

  defp run_without_input(binary, args, timeout, cmd_opts) do
    task = Task.async(fn -> System.cmd(binary, args, cmd_opts) end)

    case Task.yield(task, timeout) || Task.shutdown(task) do
      {:ok, result} -> {:ok, result}
      nil -> {:error, :timeout}
    end
  end
end
