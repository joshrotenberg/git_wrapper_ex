defmodule Git.Runner.SystemCmd do
  @moduledoc """
  Default runner backed by `System.cmd/3`.

  Runs git under a `Task` and bounds it with `Task.yield/2` plus
  `Task.shutdown/1`. This is the historical behavior of this library and needs
  no extra dependencies.

  On timeout it returns `{:error, :timeout}`, but be aware that
  `Task.shutdown/1` only closes the Erlang port: it does not signal the git OS
  process or anything git spawned, so those may keep running after the timeout.
  Use `Git.Runner.Forcola` for group-kill semantics.
  """

  @behaviour Git.Runner

  @impl true
  def run(binary, args, opts) do
    {timeout, cmd_opts} = Keyword.pop!(opts, :timeout)

    task = Task.async(fn -> System.cmd(binary, args, cmd_opts) end)

    case Task.yield(task, timeout) || Task.shutdown(task) do
      {:ok, result} -> {:ok, result}
      nil -> {:error, :timeout}
    end
  end
end
