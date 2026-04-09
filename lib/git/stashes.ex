defmodule Git.Stashes do
  @moduledoc """
  Higher-level stash management operations that compose the lower-level
  `Git.stash/1` command.

  All functions accept an optional keyword list. Use `:config` to specify the
  repository via a `Git.Config` struct; when omitted a default config is built
  from the environment.
  """

  alias Git.Config

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Saves current changes to the stash with a message.

  Delegates to `Git.stash(save: true, message: message)`.

  ## Options

    * `:config` - a `Git.Config` struct

  ## Examples

      {:ok, :done} = Git.Stashes.save("work in progress")

  """
  @spec save(String.t(), keyword()) :: {:ok, :done} | {:error, term()}
  def save(message, opts \\ []) do
    {config, rest} = extract_config(opts)
    Git.stash([{:save, true}, {:message, message}, {:config, config} | rest])
  end

  @doc """
  Pops the latest stash entry, applying it and removing it from the stash list.

  Delegates to `Git.stash(pop: true)`.

  ## Options

    * `:config` - a `Git.Config` struct

  ## Examples

      {:ok, :done} = Git.Stashes.pop()

  """
  @spec pop(keyword()) :: {:ok, :done} | {:error, term()}
  def pop(opts \\ []) do
    {config, rest} = extract_config(opts)
    Git.stash([{:pop, true}, {:config, config} | rest])
  end

  @doc """
  Applies the latest stash (or a specific stash by index) without removing it.

  Uses raw `git stash apply` since the underlying command module does not
  support the apply subcommand directly.

  ## Options

    * `:config` - a `Git.Config` struct
    * `:index` - stash index to apply (e.g., `1` for `stash@{1}`)

  ## Examples

      {:ok, :done} = Git.Stashes.apply()
      {:ok, :done} = Git.Stashes.apply(index: 2)

  """
  @spec apply(keyword()) :: {:ok, :done} | {:error, term()}
  def apply(opts \\ []) do
    {config, rest} = extract_config(opts)
    {index, _rest} = Keyword.pop(rest, :index)

    args = ["stash", "apply"] ++ stash_ref(index)
    cmd_opts = Config.cmd_opts(config)

    case System.cmd(config.binary, args, cmd_opts) do
      {_stdout, 0} -> {:ok, :done}
      {stdout, exit_code} -> {:error, {stdout, exit_code}}
    end
  end

  @doc """
  Lists all stash entries.

  Delegates to `Git.stash(list: true)`.

  ## Options

    * `:config` - a `Git.Config` struct

  ## Examples

      {:ok, entries} = Git.Stashes.list()

  """
  @spec list(keyword()) :: {:ok, [Git.StashEntry.t()]} | {:error, term()}
  def list(opts \\ []) do
    {config, _rest} = extract_config(opts)
    Git.stash(list: true, config: config)
  end

  @doc """
  Drops a specific stash entry.

  Delegates to `Git.stash(drop: true)`.

  ## Options

    * `:config` - a `Git.Config` struct
    * `:index` - stash index to drop (e.g., `1` for `stash@{1}`)

  ## Examples

      {:ok, :done} = Git.Stashes.drop()
      {:ok, :done} = Git.Stashes.drop(index: 1)

  """
  @spec drop(keyword()) :: {:ok, :done} | {:error, term()}
  def drop(opts \\ []) do
    {config, rest} = extract_config(opts)
    {index, _rest} = Keyword.pop(rest, :index)
    Git.stash([{:drop, true}, {:config, config}] ++ stash_index(index))
  end

  @doc """
  Clears all stash entries.

  Uses raw `git stash clear` since the underlying command module does not
  support the clear subcommand directly.

  ## Options

    * `:config` - a `Git.Config` struct

  ## Examples

      {:ok, :done} = Git.Stashes.clear()

  """
  @spec clear(keyword()) :: {:ok, :done} | {:error, term()}
  def clear(opts \\ []) do
    {config, _rest} = extract_config(opts)

    cmd_opts = Config.cmd_opts(config)

    case System.cmd(config.binary, ["stash", "clear"], cmd_opts) do
      {_stdout, 0} -> {:ok, :done}
      {stdout, exit_code} -> {:error, {stdout, exit_code}}
    end
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp extract_config(opts) do
    Keyword.pop(opts, :config, Config.new())
  end

  defp stash_ref(nil), do: []
  defp stash_ref(index) when is_integer(index), do: ["stash@{#{index}}"]

  defp stash_index(nil), do: []
  defp stash_index(index) when is_integer(index), do: [{:index, index}]
end
