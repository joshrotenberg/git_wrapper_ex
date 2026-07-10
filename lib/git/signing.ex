defmodule Git.Signing do
  @moduledoc """
  Higher-level helpers for configuring commit and tag signing.

  These thin wrappers set the relevant git config keys through
  `Git.git_config/1` so callers do not have to remember the individual key
  names. They configure how the repository signs; the actual signing happens
  when a commit, tag, or merge is created with the corresponding `:sign`,
  `:local_user`, or `:gpg_sign` option (or automatically once
  `commit.gpgsign`/`tag.gpgsign` is enabled).

  All functions accept an optional keyword list:

    * `:config` - a `Git.Config` struct forwarded to every git invocation
    * `:global`/`:local`/`:system` - the config scope to write. When no scope
      is given, the values are written to the local repository config.

  ## Examples

      # SSH signing with a generated key
      Git.Signing.use_ssh("/home/me/.ssh/id_ed25519.pub", config: cfg)

      # GPG signing with a key id
      Git.Signing.use_gpg("ABCD1234", config: cfg)

      # Also sign annotated tags by default
      Git.Signing.sign_tags(true, config: cfg)

  """

  alias Git.Config

  @scope_keys [:global, :local, :system]

  @doc """
  Configures SSH-based signing.

  Sets `gpg.format=ssh`, `user.signingkey` to `key_path`, and
  `commit.gpgsign=true` so commits are signed by default.

  Returns `{:ok, :done}` when every key was written, or the first
  `{:error, term()}` encountered.
  """
  @spec use_ssh(String.t(), keyword()) :: {:ok, :done} | {:error, term()}
  def use_ssh(key_path, opts \\ []) when is_binary(key_path) do
    with {:ok, :done} <- set("gpg.format", "ssh", opts),
         {:ok, :done} <- set("user.signingkey", key_path, opts) do
      set("commit.gpgsign", "true", opts)
    end
  end

  @doc """
  Configures GPG-based signing.

  Sets `user.signingkey` to `keyid` and `commit.gpgsign=true` so commits are
  signed by default.

  Returns `{:ok, :done}` when every key was written, or the first
  `{:error, term()}` encountered.
  """
  @spec use_gpg(String.t(), keyword()) :: {:ok, :done} | {:error, term()}
  def use_gpg(keyid, opts \\ []) when is_binary(keyid) do
    with {:ok, :done} <- set("user.signingkey", keyid, opts) do
      set("commit.gpgsign", "true", opts)
    end
  end

  @doc """
  Sets `tag.gpgsign` so annotated tags are signed by default.

  Returns `{:ok, :done}` on success or `{:error, term()}` on failure.
  """
  @spec sign_tags(boolean(), keyword()) :: {:ok, :done} | {:error, term()}
  def sign_tags(enabled, opts \\ []) when is_boolean(enabled) do
    set("tag.gpgsign", to_string(enabled), opts)
  end

  # Writes a single config key/value at the requested scope (local by default).
  defp set(key, value, opts) do
    {config, rest} = Keyword.pop(opts, :config, Config.new())

    scope =
      case Keyword.take(rest, @scope_keys) do
        [] -> [local: true]
        given -> given
      end

    Git.git_config([{:set_key, key}, {:set_value, value}, {:config, config} | scope])
  end
end
