defmodule Git.MixProject do
  use Mix.Project

  def project do
    [
      app: :git,
      version: "0.3.0",
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
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
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
          Git.Workflow,
          Git.Branches,
          Git.Tags,
          Git.Remotes,
          Git.Stashes,
          Git.Changes,
          Git.Conflicts,
          Git.Patch,
          Git.History,
          Git.Info,
          Git.Search,
          Git.Hooks
        ],
        "Data Structures": [
          Git.BisectResult,
          Git.BlameEntry,
          Git.Branch,
          Git.Checkout,
          Git.CherryEntry,
          Git.CherryPickResult,
          Git.Commit,
          Git.CommitResult,
          Git.Diff,
          Git.DiffFile,
          Git.GrepResult,
          Git.LsRemoteEntry,
          Git.MergeResult,
          Git.PullResult,
          Git.RebaseResult,
          Git.ReflogEntry,
          Git.Remote,
          Git.RevertResult,
          Git.ShortlogEntry,
          Git.ShowResult,
          Git.StashEntry,
          Git.Status,
          Git.SubmoduleEntry,
          Git.Tag,
          Git.TreeEntry,
          Git.Worktree
        ],
        Commands: [
          Git.Commands.Add,
          Git.Commands.Am,
          Git.Commands.Apply,
          Git.Commands.Archive,
          Git.Commands.Bisect,
          Git.Commands.Blame,
          Git.Commands.Branch,
          Git.Commands.Bundle,
          Git.Commands.CatFile,
          Git.Commands.CheckIgnore,
          Git.Commands.Checkout,
          Git.Commands.Cherry,
          Git.Commands.CherryPick,
          Git.Commands.Clean,
          Git.Commands.Clone,
          Git.Commands.Commit,
          Git.Commands.Describe,
          Git.Commands.Diff,
          Git.Commands.Fetch,
          Git.Commands.ForEachRef,
          Git.Commands.FormatPatch,
          Git.Commands.Fsck,
          Git.Commands.Gc,
          Git.Commands.GitConfig,
          Git.Commands.Grep,
          Git.Commands.HashObject,
          Git.Commands.Init,
          Git.Commands.InterpretTrailers,
          Git.Commands.Log,
          Git.Commands.LsFiles,
          Git.Commands.LsRemote,
          Git.Commands.LsTree,
          Git.Commands.Maintenance,
          Git.Commands.Merge,
          Git.Commands.MergeBase,
          Git.Commands.Mv,
          Git.Commands.Notes,
          Git.Commands.Pull,
          Git.Commands.Push,
          Git.Commands.RangeDiff,
          Git.Commands.Rebase,
          Git.Commands.Reflog,
          Git.Commands.Remote,
          Git.Commands.Rerere,
          Git.Commands.Reset,
          Git.Commands.Restore,
          Git.Commands.RevList,
          Git.Commands.RevParse,
          Git.Commands.Revert,
          Git.Commands.Rm,
          Git.Commands.Shortlog,
          Git.Commands.Show,
          Git.Commands.ShowRef,
          Git.Commands.SparseCheckout,
          Git.Commands.Stash,
          Git.Commands.Status,
          Git.Commands.Submodule,
          Git.Commands.Switch,
          Git.Commands.SymbolicRef,
          Git.Commands.Tag,
          Git.Commands.UpdateRef,
          Git.Commands.VerifyCommit,
          Git.Commands.VerifyTag,
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
