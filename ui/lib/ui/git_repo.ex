defmodule GitUI.GitRepo do
  @moduledoc """
  Provides a configured `Git.Config` for the target repository.

  The repo path is configured via:
    - `GIT_REPO_PATH` environment variable
    - `config :ui, :repo_path` in config
    - Defaults to the parent of the ui/ directory (the git_wrapper_ex repo itself)
  """

  @doc """
  Returns a `Git.Config` for the configured repository path.
  """
  def config do
    Git.Config.new(working_dir: repo_path())
  end

  @doc """
  Returns the configured repository path.
  """
  def repo_path do
    Application.get_env(:ui, :repo_path, Path.expand("../.."))
  end
end
