defmodule Git.TestHelpers do
  @moduledoc false

  # Number of removal attempts before giving up. Each attempt after the first
  # is separated by `@retry_delay_ms`.
  @attempts 10
  @retry_delay_ms 20

  @doc """
  Removes a directory tree, tolerating the transient races that show up when
  cleaning temporary git repositories.

  Test `on_exit` callbacks run right after a git command returns. A background
  git process (for example the `gc --auto`/`maintenance --auto` run that a
  `commit` can spawn) may still be writing into the repository, so a plain
  `File.rm_rf!/1` occasionally raises `:eexist`/`:enotempty` while it walks a
  directory that a sibling process is repopulating.

  This retries `File.rm_rf/1` a few times on those transient errors and never
  raises, so a lost cleanup race cannot fail an otherwise-passing test.
  """
  @spec rm_rf(Path.t()) :: :ok
  def rm_rf(path), do: rm_rf(path, @attempts)

  defp rm_rf(path, attempts) when attempts <= 1 do
    _ = File.rm_rf(path)
    :ok
  end

  defp rm_rf(path, attempts) do
    case File.rm_rf(path) do
      {:ok, _removed} ->
        :ok

      {:error, reason, _file} when reason in [:eexist, :enotempty, :ebusy] ->
        Process.sleep(@retry_delay_ms)
        rm_rf(path, attempts - 1)

      {:error, _reason, _file} ->
        # A non-transient error (permissions, and so on) will not be fixed by
        # retrying; nothing more can be done safely during teardown.
        :ok
    end
  end
end
