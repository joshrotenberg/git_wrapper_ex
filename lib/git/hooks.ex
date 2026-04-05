defmodule Git.Hooks do
  @moduledoc """
  Helpers for reading, writing, and managing git hooks.

  Operates on the `.git/hooks/` directory of a repository. These functions
  don't map to a single git subcommand but instead provide convenient access
  to hook files.

  All functions accept an optional keyword list with `:config` for specifying
  the repository via a `Git.Config` struct.
  """

  @valid_hooks ~w(
    applypatch-msg commit-msg fsmonitor-watchman post-update pre-applypatch
    pre-commit pre-merge-commit prepare-commit-msg pre-push pre-rebase
    pre-receive push-to-checkout update post-checkout post-commit
    post-merge post-rewrite sendemail-validate reference-transaction
  )

  @doc """
  Returns the list of valid git hook names.
  """
  @spec valid_hooks() :: [String.t()]
  def valid_hooks, do: @valid_hooks

  @doc """
  Lists installed hooks in the repository.

  Returns a list of maps with `:name`, `:enabled`, and `:path` keys.
  A hook is considered enabled if it has the executable bit set.
  Only files matching valid hook names are included (`.sample` files are skipped).

  ## Options

    * `:config` - a `Git.Config` struct (default: `Git.Config.new()`)

  ## Examples

      {:ok, hooks} = Git.Hooks.list()
      # => [%{name: "pre-commit", enabled: true, path: "/repo/.git/hooks/pre-commit"}]

  """
  @spec list(keyword()) ::
          {:ok, [%{name: String.t(), enabled: boolean(), path: String.t()}]} | {:error, term()}
  def list(opts \\ []) do
    with {:ok, dir} <- hooks_dir(opts) do
      {:ok, list_hooks_in_dir(dir)}
    end
  end

  @doc """
  Reads the content of a hook file.

  ## Options

    * `:config` - a `Git.Config` struct (default: `Git.Config.new()`)

  Returns `{:ok, content}` or `{:error, :not_found}`.
  Returns `{:error, :invalid_hook}` if the hook name is not valid.
  """
  @spec read(String.t(), keyword()) ::
          {:ok, String.t()} | {:error, :not_found | :invalid_hook | term()}
  def read(hook_name, opts \\ []) do
    with :ok <- validate_hook(hook_name),
         {:ok, path} <- hook_path(hook_name, opts) do
      case File.read(path) do
        {:ok, content} -> {:ok, content}
        {:error, :enoent} -> {:error, :not_found}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  @doc """
  Writes a hook file.

  By default the file is made executable. Pass `executable: false` to skip
  setting the executable bit.

  ## Options

    * `:config` - a `Git.Config` struct (default: `Git.Config.new()`)
    * `:executable` - whether to chmod +x the file (default: `true`)

  Returns `{:ok, path}` or `{:error, reason}`.
  Returns `{:error, :invalid_hook}` if the hook name is not valid.
  """
  @spec write(String.t(), String.t(), keyword()) ::
          {:ok, String.t()} | {:error, :invalid_hook | term()}
  def write(hook_name, content, opts \\ []) do
    executable = Keyword.get(opts, :executable, true)

    with :ok <- validate_hook(hook_name),
         {:ok, dir} <- hooks_dir(opts) do
      File.mkdir_p!(dir)
      path = Path.join(dir, hook_name)
      write_hook_file(path, content, executable)
    end
  end

  @doc """
  Makes a hook executable (`chmod +x`).

  ## Options

    * `:config` - a `Git.Config` struct (default: `Git.Config.new()`)

  Returns `{:ok, path}` or `{:error, :not_found}`.
  Returns `{:error, :invalid_hook}` if the hook name is not valid.
  """
  @spec enable(String.t(), keyword()) ::
          {:ok, String.t()} | {:error, :not_found | :invalid_hook | term()}
  def enable(hook_name, opts \\ []) do
    with :ok <- validate_hook(hook_name),
         {:ok, path} <- hook_path(hook_name, opts) do
      if File.exists?(path) do
        File.chmod!(path, 0o755)
        {:ok, path}
      else
        {:error, :not_found}
      end
    end
  end

  @doc """
  Removes the executable bit from a hook (`chmod -x`).

  ## Options

    * `:config` - a `Git.Config` struct (default: `Git.Config.new()`)

  Returns `{:ok, path}` or `{:error, :not_found}`.
  Returns `{:error, :invalid_hook}` if the hook name is not valid.
  """
  @spec disable(String.t(), keyword()) ::
          {:ok, String.t()} | {:error, :not_found | :invalid_hook | term()}
  def disable(hook_name, opts \\ []) do
    with :ok <- validate_hook(hook_name),
         {:ok, path} <- hook_path(hook_name, opts) do
      if File.exists?(path) do
        File.chmod!(path, 0o644)
        {:ok, path}
      else
        {:error, :not_found}
      end
    end
  end

  @doc """
  Deletes a hook file.

  ## Options

    * `:config` - a `Git.Config` struct (default: `Git.Config.new()`)

  Returns `:ok` or `{:error, :not_found}`.
  Returns `{:error, :invalid_hook}` if the hook name is not valid.
  """
  @spec remove(String.t(), keyword()) :: :ok | {:error, :not_found | :invalid_hook | term()}
  def remove(hook_name, opts \\ []) do
    with :ok <- validate_hook(hook_name),
         {:ok, path} <- hook_path(hook_name, opts) do
      case File.rm(path) do
        :ok -> :ok
        {:error, :enoent} -> {:error, :not_found}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  @doc """
  Checks whether a hook file exists.

  ## Options

    * `:config` - a `Git.Config` struct (default: `Git.Config.new()`)

  Returns `{:ok, boolean()}`.
  Returns `{:error, :invalid_hook}` if the hook name is not valid.
  """
  @spec exists?(String.t(), keyword()) :: {:ok, boolean()} | {:error, :invalid_hook | term()}
  def exists?(hook_name, opts \\ []) do
    with :ok <- validate_hook(hook_name),
         {:ok, path} <- hook_path(hook_name, opts) do
      {:ok, File.exists?(path)}
    end
  end

  @doc """
  Checks whether a hook file exists and is executable.

  ## Options

    * `:config` - a `Git.Config` struct (default: `Git.Config.new()`)

  Returns `{:ok, boolean()}`.
  Returns `{:error, :invalid_hook}` if the hook name is not valid.
  """
  @spec enabled?(String.t(), keyword()) :: {:ok, boolean()} | {:error, :invalid_hook | term()}
  def enabled?(hook_name, opts \\ []) do
    with :ok <- validate_hook(hook_name),
         {:ok, path} <- hook_path(hook_name, opts) do
      {:ok, File.exists?(path) && executable?(path)}
    end
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp list_hooks_in_dir(dir) do
    if File.dir?(dir) do
      dir
      |> File.ls!()
      |> Enum.filter(&(&1 in @valid_hooks))
      |> Enum.sort()
      |> Enum.map(fn name ->
        path = Path.join(dir, name)

        %{
          name: name,
          enabled: executable?(path),
          path: path
        }
      end)
    else
      []
    end
  end

  defp write_hook_file(path, content, executable) do
    case File.write(path, content) do
      :ok ->
        if executable do
          File.chmod!(path, 0o755)
        end

        {:ok, path}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp hooks_dir(opts) do
    config = Keyword.get(opts, :config, Git.Config.new())

    case Git.rev_parse(git_dir: true, config: config) do
      {:ok, git_dir} ->
        abs_git_dir =
          if Path.type(git_dir) == :relative && config.working_dir do
            Path.expand(git_dir, config.working_dir)
          else
            git_dir
          end

        {:ok, Path.join(abs_git_dir, "hooks")}

      error ->
        error
    end
  end

  defp hook_path(hook_name, opts) do
    with {:ok, dir} <- hooks_dir(opts) do
      {:ok, Path.join(dir, hook_name)}
    end
  end

  defp validate_hook(hook_name) when hook_name in @valid_hooks, do: :ok
  defp validate_hook(_hook_name), do: {:error, :invalid_hook}

  defp executable?(path) do
    case File.stat(path) do
      {:ok, %{access: access}} when access in [:read_write, :read] ->
        # Check the actual mode for the executable bit
        case :file.read_file_info(String.to_charlist(path)) do
          {:ok, info} ->
            mode = elem(info, 7)
            Bitwise.band(mode, 0o111) != 0

          _ ->
            false
        end

      _ ->
        false
    end
  end
end
