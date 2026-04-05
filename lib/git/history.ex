defmodule Git.History do
  @moduledoc """
  Higher-level history query helpers that compose lower-level `Git` functions.

  All functions accept an optional keyword list. Use `:config` to specify the
  repository via a `Git.Config` struct; when omitted a default config is built
  from the environment.
  """

  alias Git.Config

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Returns commits between two refs (tags, branches, SHAs).

  Uses `git log ref1..ref2` under the hood.

  ## Options

    * `:config` - a `Git.Config` struct

  ## Examples

      {:ok, commits} = Git.History.commits_between("v1.0.0", "v2.0.0")

  """
  @spec commits_between(String.t(), String.t(), keyword()) ::
          {:ok, [Git.Commit.t()]} | {:error, term()}
  def commits_between(ref1, ref2, opts \\ []) do
    {config, rest} = extract_config(opts)
    Git.log([{:range, "#{ref1}..#{ref2}"}, {:config, config} | rest])
  end

  @doc """
  Lists files changed since a given ref.

  Uses `git diff --name-only <ref>` under the hood and splits the result into
  a list of file paths.

  ## Options

    * `:config` - a `Git.Config` struct

  ## Examples

      {:ok, files} = Git.History.files_changed_since("v1.0.0")

  """
  @spec files_changed_since(String.t(), keyword()) ::
          {:ok, [String.t()]} | {:error, term()}
  def files_changed_since(ref, opts \\ []) do
    {config, _rest} = extract_config(opts)

    case Git.diff(config: config, ref: ref, name_only: true) do
      {:ok, diff} ->
        files =
          diff.raw
          |> String.split("\n", trim: true)
          |> Enum.map(&String.trim/1)
          |> Enum.reject(&(&1 == ""))

        {:ok, files}

      error ->
        error
    end
  end

  @doc """
  Returns unique contributors from the commit log.

  Each contributor is a map with `:name`, `:email`, and `:commit_count` keys,
  deduplicated by email address.

  ## Options

    * `:config` - a `Git.Config` struct
    * `:path` - limit to commits touching files under this path
    * `:since` - limit to commits after this date (e.g., `"2025-01-01"`)

  ## Examples

      {:ok, contributors} = Git.History.contributors(since: "2025-01-01")

  """
  @spec contributors(keyword()) ::
          {:ok, [%{name: String.t(), email: String.t(), commit_count: non_neg_integer()}]}
          | {:error, term()}
  def contributors(opts \\ []) do
    {config, rest} = extract_config(opts)
    log_opts = [{:config, config} | rest]

    case Git.log(log_opts) do
      {:ok, commits} ->
        grouped =
          commits
          |> Enum.group_by(& &1.author_email)
          |> Enum.map(fn {email, group} ->
            %{
              name: hd(group).author_name,
              email: email,
              commit_count: length(group)
            }
          end)
          |> Enum.sort_by(& &1.commit_count, :desc)

        {:ok, grouped}

      error ->
        error
    end
  end

  @doc """
  Generates a changelog-style grouping of commits between two refs.

  Commits are grouped by conventional commit type prefix (`feat:`, `fix:`,
  `docs:`, etc.). Commits without a recognized prefix land in `:other`.

  ## Options

    * `:config` - a `Git.Config` struct

  ## Examples

      {:ok, changelog} = Git.History.changelog("v1.0.0", "v2.0.0")
      changelog.features  #=> [%Git.Commit{...}, ...]
      changelog.fixes     #=> [%Git.Commit{...}, ...]

  """
  @spec changelog(String.t(), String.t(), keyword()) ::
          {:ok, %{features: [Git.Commit.t()], fixes: [Git.Commit.t()], other: [Git.Commit.t()]}}
          | {:error, term()}
  def changelog(from_ref, to_ref, opts \\ []) do
    case commits_between(from_ref, to_ref, opts) do
      {:ok, commits} ->
        grouped = Enum.group_by(commits, &classify_commit/1)

        result = %{
          features: Map.get(grouped, :feature, []),
          fixes: Map.get(grouped, :fix, []),
          other: Map.get(grouped, :other, [])
        }

        {:ok, result}

      error ->
        error
    end
  end

  @doc """
  Checks whether `ref1` is an ancestor of `ref2`.

  Runs `git merge-base --is-ancestor ref1 ref2` directly.

  ## Options

    * `:config` - a `Git.Config` struct

  ## Examples

      {:ok, true} = Git.History.ancestor?("v1.0.0", "main")

  """
  @spec ancestor?(String.t(), String.t(), keyword()) ::
          {:ok, boolean()} | {:error, term()}
  def ancestor?(ref1, ref2, opts \\ []) do
    {config, _rest} = extract_config(opts)
    Git.merge_base(commits: [ref1, ref2], is_ancestor: true, config: config)
  end

  @doc """
  Returns commits that touched a specific file.

  ## Options

    * `:config` - a `Git.Config` struct
    * `:max_count` - limit the number of commits returned

  ## Examples

      {:ok, commits} = Git.History.file_history("lib/git.ex")

  """
  @spec file_history(String.t(), keyword()) ::
          {:ok, [Git.Commit.t()]} | {:error, term()}
  def file_history(file, opts \\ []) do
    {config, rest} = extract_config(opts)
    Git.log([{:path, file}, {:config, config} | rest])
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp extract_config(opts) do
    Keyword.pop(opts, :config, Config.new())
  end

  @conventional_prefixes %{
    "feat" => :feature,
    "feat!" => :feature,
    "fix" => :fix,
    "fix!" => :fix
  }

  defp classify_commit(%Git.Commit{subject: subject}) do
    case Regex.run(~r/^(\w+!?):\s/, subject) do
      [_, prefix] -> Map.get(@conventional_prefixes, prefix, :other)
      _ -> :other
    end
  end
end
