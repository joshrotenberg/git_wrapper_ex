defmodule Git.Commands.Remote do
  @moduledoc """
  Implements the `Git.Command` behaviour for `git remote`.

  Supports listing remotes (with or without verbose URL output), adding a new
  remote, and removing an existing remote.
  """

  @behaviour Git.Command

  alias Git.Remote

  @type t :: %__MODULE__{
          list: boolean(),
          add_name: String.t() | nil,
          add_url: String.t() | nil,
          remove: String.t() | nil,
          verbose: boolean()
        }

  defstruct list: true, add_name: nil, add_url: nil, remove: nil, verbose: true

  # Process dictionary key used to communicate the operation mode from args/1
  # to parse_output/2. Both are called from the same process inside
  # Git.Command.run/3, so this is safe even with async tests.
  @mode_key :__git_remote_mode__

  @doc """
  Builds the argument list for `git remote`.

  - If `add_name` is set (with `add_url`): produces `["remote", "add", name, url]`
  - If `remove` is set: produces `["remote", "remove", name]`
  - Otherwise (list mode): produces `["remote"]`, plus `"-v"` when `verbose: true`
  """
  @spec args(t()) :: [String.t()]
  @impl true
  def args(%__MODULE__{add_name: name, add_url: url}) when not is_nil(name) and not is_nil(url) do
    Process.put(@mode_key, :mutation)
    ["remote", "add", name, url]
  end

  def args(%__MODULE__{remove: name}) when not is_nil(name) do
    Process.put(@mode_key, :mutation)
    ["remote", "remove", name]
  end

  def args(%__MODULE__{verbose: true}) do
    Process.put(@mode_key, :list)
    ["remote", "-v"]
  end

  def args(%__MODULE__{}) do
    Process.put(@mode_key, :list)
    ["remote"]
  end

  @doc """
  Parses stdout and exit code from `git remote` into a result.

  - List with exit code 0: `{:ok, [%Git.Remote{}]}` (empty list when no remotes)
  - Add/remove with exit code 0: `{:ok, :done}`
  - Non-zero exit code: `{:error, {stdout, exit_code}}`
  """
  @spec parse_output(String.t(), non_neg_integer()) ::
          {:ok, [Remote.t()]} | {:ok, :done} | {:error, {String.t(), non_neg_integer()}}
  @impl true
  def parse_output(stdout, 0) do
    mode = Process.get(@mode_key, :list)

    case mode do
      :mutation ->
        {:ok, :done}

      :list ->
        parse_list_output(stdout)
    end
  end

  def parse_output(stdout, exit_code) do
    {:error, {stdout, exit_code}}
  end

  defp parse_list_output(""), do: {:ok, []}

  defp parse_list_output(stdout) do
    if String.contains?(stdout, "\t") do
      {:ok, Remote.parse_verbose(stdout)}
    else
      remotes =
        stdout
        |> String.split("\n", trim: true)
        |> Enum.map(fn name -> %Remote{name: String.trim(name)} end)

      {:ok, remotes}
    end
  end
end
