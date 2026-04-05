defmodule Git.MixProject do
  use Mix.Project

  def project do
    [
      app: :git,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      description: "A clean Elixir wrapper for the git CLI with parsed output structs",
      source_url: "https://github.com/joshrotenberg/git_wrapper_ex",
      homepage_url: "https://github.com/joshrotenberg/git_wrapper_ex",
      package: package(),
      docs: docs(),
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/joshrotenberg/git_wrapper_ex"}
    ]
  end

  defp docs do
    [
      main: "Git",
      source_url: "https://github.com/joshrotenberg/git_wrapper_ex",
      extras: ["README.md"],
      groups_for_modules: [
        "Higher-Level": [
          Git.Repo,
          Git.History,
          Git.Hooks,
          Git.Branches
        ],
        "Data Structures": [
          Git.BisectResult,
          Git.BlameEntry,
          Git.Branch,
          Git.Checkout,
          Git.CherryPickResult,
          Git.Commit,
          Git.CommitResult,
          Git.Diff,
          Git.DiffFile,
          Git.MergeResult,
          Git.PullResult,
          Git.RebaseResult,
          Git.ReflogEntry,
          Git.Remote,
          Git.RevertResult,
          Git.ShowResult,
          Git.StashEntry,
          Git.Status,
          Git.Tag,
          Git.Worktree
        ],
        Commands: [
          Git.Commands.Add,
          Git.Commands.Bisect,
          Git.Commands.Blame,
          Git.Commands.Branch,
          Git.Commands.Checkout,
          Git.Commands.CherryPick,
          Git.Commands.Clean,
          Git.Commands.Clone,
          Git.Commands.Commit,
          Git.Commands.Diff,
          Git.Commands.Fetch,
          Git.Commands.GitConfig,
          Git.Commands.Init,
          Git.Commands.Log,
          Git.Commands.LsFiles,
          Git.Commands.Merge,
          Git.Commands.Mv,
          Git.Commands.Pull,
          Git.Commands.Push,
          Git.Commands.Rebase,
          Git.Commands.Reflog,
          Git.Commands.Remote,
          Git.Commands.Reset,
          Git.Commands.RevParse,
          Git.Commands.Revert,
          Git.Commands.Rm,
          Git.Commands.Show,
          Git.Commands.Stash,
          Git.Commands.Status,
          Git.Commands.Tag,
          Git.Commands.Worktree
        ],
        Internals: [
          Git.Command,
          Git.Config
        ]
      ]
    ]
  end
end
