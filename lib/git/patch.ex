defmodule Git.Patch do
  @moduledoc """
  Higher-level patch workflow operations that compose `Git.format_patch/1`,
  `Git.apply_patch/1`, and `Git.am/1`.

  All functions accept an optional keyword list. Use `:config` to specify the
  repository via a `Git.Config` struct; when omitted a default config is built
  from the environment.
  """

  alias Git.Config

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Creates patch files from commits starting at a ref.

  Delegates to `Git.format_patch/1`.

  ## Options

    * `:config` - a `Git.Config` struct
    * `:output_directory` - directory to write patch files to

  ## Examples

      {:ok, files} = Git.Patch.create("HEAD~3")
      {:ok, files} = Git.Patch.create("HEAD~1", output_directory: "/tmp/patches")

  """
  @spec create(String.t(), keyword()) ::
          {:ok, [String.t()]} | {:ok, String.t()} | {:error, term()}
  def create(ref, opts \\ []) do
    {config, rest} = extract_config(opts)
    Git.format_patch([{:ref, ref}, {:config, config} | rest])
  end

  @doc """
  Applies a patch file to the working tree.

  Delegates to `Git.apply_patch/1`.

  ## Options

    * `:config` - a `Git.Config` struct

  ## Examples

      {:ok, :done} = Git.Patch.apply("0001-fix.patch")

  """
  @spec apply(String.t(), keyword()) :: {:ok, :done} | {:ok, String.t()} | {:error, term()}
  def apply(patch_file, opts \\ []) do
    {config, rest} = extract_config(opts)
    Git.apply_patch([{:patch, patch_file}, {:config, config} | rest])
  end

  @doc """
  Applies mailbox-formatted patches (git am).

  Delegates to `Git.am/1`.

  ## Options

    * `:config` - a `Git.Config` struct

  ## Examples

      {:ok, :done} = Git.Patch.apply_mailbox(["0001-fix.patch"])

  """
  @spec apply_mailbox([String.t()], keyword()) :: {:ok, :done} | {:error, term()}
  def apply_mailbox(patches, opts \\ []) do
    {config, rest} = extract_config(opts)
    Git.am([{:patches, patches}, {:config, config} | rest])
  end

  @doc """
  Checks whether a patch applies cleanly without actually applying it.

  Uses `Git.apply_patch/1` with the `:check` option.

  ## Options

    * `:config` - a `Git.Config` struct

  ## Examples

      {:ok, _output} = Git.Patch.check("0001-fix.patch")

  """
  @spec check(String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def check(patch_file, opts \\ []) do
    {config, rest} = extract_config(opts)
    Git.apply_patch([{:patch, patch_file}, {:check, true}, {:config, config} | rest])
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp extract_config(opts) do
    Keyword.pop(opts, :config, Config.new())
  end
end
