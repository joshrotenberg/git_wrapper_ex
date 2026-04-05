defmodule Git.Commands.Bisect do
  @moduledoc """
  Implements the `Git.Command` behaviour for `git bisect`.

  Supports starting, marking good/bad commits, skipping, resetting,
  viewing the bisect log, and replaying a bisect session.

  ## Unsupported subcommands

  - `visualize` - requires a GUI (gitk) and is not suitable for CLI wrapping.
  - `run` - requires script execution which adds complexity beyond simple
    command wrapping. May be added in a future release.
  """

  @behaviour Git.Command

  alias Git.BisectResult

  @type t :: %__MODULE__{
          start: boolean(),
          bad: String.t() | nil | :head,
          good: String.t() | nil | :head,
          new_ref: String.t() | nil,
          old_ref: String.t() | nil,
          reset: boolean(),
          skip: String.t() | nil | :head,
          log: boolean(),
          replay: String.t() | nil
        }

  defstruct start: false,
            bad: nil,
            good: nil,
            new_ref: nil,
            old_ref: nil,
            reset: false,
            skip: nil,
            log: false,
            replay: nil

  # Process dictionary key used to communicate the operation mode from args/1
  # to parse_output/2. Both are called from the same process inside
  # Git.Command.run/3, so this is safe even with async tests.
  @mode_key :__git_bisect_mode__

  @doc """
  Returns the argument list for `git bisect`.

  Builds the subcommand and optional ref argument based on the struct fields.

  ## Examples

      iex> Git.Commands.Bisect.args(%Git.Commands.Bisect{start: true})
      ["bisect", "start"]

      iex> Git.Commands.Bisect.args(%Git.Commands.Bisect{bad: :head})
      ["bisect", "bad"]

      iex> Git.Commands.Bisect.args(%Git.Commands.Bisect{bad: "abc1234"})
      ["bisect", "bad", "abc1234"]

      iex> Git.Commands.Bisect.args(%Git.Commands.Bisect{good: :head})
      ["bisect", "good"]

      iex> Git.Commands.Bisect.args(%Git.Commands.Bisect{reset: true})
      ["bisect", "reset"]

      iex> Git.Commands.Bisect.args(%Git.Commands.Bisect{log: true})
      ["bisect", "log"]

  """
  @spec args(t()) :: [String.t()]
  @impl true
  def args(%__MODULE__{start: true}) do
    Process.put(@mode_key, :start)
    ["bisect", "start"]
  end

  def args(%__MODULE__{bad: :head}) do
    Process.put(@mode_key, :mark)
    ["bisect", "bad"]
  end

  def args(%__MODULE__{bad: ref}) when is_binary(ref) do
    Process.put(@mode_key, :mark)
    ["bisect", "bad", ref]
  end

  def args(%__MODULE__{good: :head}) do
    Process.put(@mode_key, :mark)
    ["bisect", "good"]
  end

  def args(%__MODULE__{good: ref}) when is_binary(ref) do
    Process.put(@mode_key, :mark)
    ["bisect", "good", ref]
  end

  def args(%__MODULE__{new_ref: ref}) when is_binary(ref) do
    Process.put(@mode_key, :mark)
    ["bisect", "new", ref]
  end

  def args(%__MODULE__{old_ref: ref}) when is_binary(ref) do
    Process.put(@mode_key, :mark)
    ["bisect", "old", ref]
  end

  def args(%__MODULE__{skip: :head}) do
    Process.put(@mode_key, :mark)
    ["bisect", "skip"]
  end

  def args(%__MODULE__{skip: ref}) when is_binary(ref) do
    Process.put(@mode_key, :mark)
    ["bisect", "skip", ref]
  end

  def args(%__MODULE__{reset: true}) do
    Process.put(@mode_key, :reset)
    ["bisect", "reset"]
  end

  def args(%__MODULE__{log: true}) do
    Process.put(@mode_key, :log)
    ["bisect", "log"]
  end

  def args(%__MODULE__{replay: file}) when is_binary(file) do
    Process.put(@mode_key, :mark)
    ["bisect", "replay", file]
  end

  @doc """
  Parses the output of `git bisect`.

  Returns `{:ok, %Git.BisectResult{}}` on success. The `status` field
  indicates the current state of the bisect session. On failure, returns
  `{:error, {stdout, exit_code}}`.
  """
  @spec parse_output(String.t(), non_neg_integer()) ::
          {:ok, BisectResult.t()} | {:error, {String.t(), non_neg_integer()}}
  @impl true
  def parse_output(stdout, 0) do
    mode = Process.get(@mode_key, :mark)
    {:ok, parse_bisect_output(stdout, mode)}
  end

  def parse_output(stdout, exit_code), do: {:error, {stdout, exit_code}}

  defp parse_bisect_output(stdout, :start) do
    %BisectResult{status: :started, raw: stdout}
  end

  defp parse_bisect_output(stdout, :reset) do
    %BisectResult{status: :done, raw: stdout}
  end

  defp parse_bisect_output(stdout, :log) do
    %BisectResult{status: :stepping, raw: stdout}
  end

  defp parse_bisect_output(stdout, :mark) do
    trimmed = String.trim(stdout)

    cond do
      String.contains?(trimmed, "is the first bad commit") ->
        commit = extract_bad_commit(trimmed)
        %BisectResult{status: :found, bad_commit: commit, raw: stdout}

      String.contains?(trimmed, "Bisecting:") ->
        commit = extract_current_commit(trimmed)
        %BisectResult{status: :stepping, current_commit: commit, raw: stdout}

      true ->
        %BisectResult{status: :stepping, raw: stdout}
    end
  end

  # Extracts the bad commit SHA from output like:
  # "abc1234... is the first bad commit"
  defp extract_bad_commit(output) do
    case Regex.run(~r/([0-9a-f]{7,40})\S*\s+is the first bad commit/, output) do
      [_, hash] -> hash
      nil -> nil
    end
  end

  # Extracts the current commit from Bisecting output like:
  # "Bisecting: N revisions left to test after this (roughly M steps)\n[abc1234] message"
  defp extract_current_commit(output) do
    case Regex.run(~r/\[([0-9a-f]{7,40})\]/, output) do
      [_, hash] -> hash
      nil -> nil
    end
  end
end
