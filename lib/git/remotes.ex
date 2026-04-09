defmodule Git.Remotes do
  @moduledoc """
  Higher-level remote management helpers that compose lower-level `Git` functions.

  Provides convenience functions for listing, adding, removing, and updating
  git remotes.

  All functions accept an optional keyword list. Use `:config` to specify the
  repository via a `Git.Config` struct; when omitted a default config is built
  from the environment.
  """

  alias Git.Config

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Lists remotes with their URLs.

  Delegates to `Git.remote/1` which returns verbose output by default.

  Returns `{:ok, [Git.Remote.t()]}`.
  """
  @spec list_detailed(keyword()) :: {:ok, [Git.Remote.t()]} | {:error, term()}
  def list_detailed(opts \\ []) do
    {config, _rest} = extract_config(opts)
    Git.remote(config: config)
  end

  @doc """
  Adds a remote.

  Uses `Git.remote(add_name: name, add_url: url)`.

  Returns `{:ok, :done}` on success.
  """
  @spec add(String.t(), String.t(), keyword()) :: {:ok, :done} | {:error, term()}
  def add(name, url, opts \\ []) do
    {config, _rest} = extract_config(opts)
    Git.remote(add_name: name, add_url: url, config: config)
  end

  @doc """
  Removes a remote.

  Uses `Git.remote(remove: name)`.

  Returns `{:ok, :done}` on success.
  """
  @spec remove(String.t(), keyword()) :: {:ok, :done} | {:error, term()}
  def remove(name, opts \\ []) do
    {config, _rest} = extract_config(opts)
    Git.remote(remove: name, config: config)
  end

  @doc """
  Updates the URL of an existing remote.

  Uses `git remote set-url` via raw `System.cmd` since the command module
  does not expose a set-url option.

  Returns `{:ok, :done}` on success.
  """
  @spec set_url(String.t(), String.t(), keyword()) :: {:ok, :done} | {:error, term()}
  def set_url(name, url, opts \\ []) do
    {config, _rest} = extract_config(opts)

    args = ["remote", "set-url", name, url]
    cmd_opts = Config.cmd_opts(config)

    case System.cmd(config.binary, args, cmd_opts) do
      {_stdout, 0} -> {:ok, :done}
      {stdout, exit_code} -> {:error, {stdout, exit_code}}
    end
  end

  @doc """
  Prunes stale remote-tracking branches for a remote.

  Uses `Git.fetch(remote: name, prune: true)`.

  Returns `{:ok, :done}` on success.
  """
  @spec prune(String.t(), keyword()) :: {:ok, :done} | {:error, term()}
  def prune(name, opts \\ []) do
    {config, _rest} = extract_config(opts)
    Git.fetch(remote: name, prune: true, config: config)
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp extract_config(opts) do
    Keyword.pop(opts, :config, Config.new())
  end
end
