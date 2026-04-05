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
      {:jason, "~> 1.4"},
      # Workshop + Claude backend (path deps for development)
      {:agent_workshop, path: "../agent_workshop"},
      {:claude_wrapper, path: "../claude_wrapper_ex", override: true},
      # MCP server deps
      {:anubis_mcp, "~> 1.0"},
      {:bandit, "~> 1.0"},
      {:plug, "~> 1.16"},
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
        "Data Structures": [
          Git.Branch,
          Git.Checkout,
          Git.Commit,
          Git.CommitResult,
          Git.Diff,
          Git.DiffFile,
          Git.MergeResult,
          Git.Remote,
          Git.StashEntry,
          Git.Status,
          Git.Tag
        ],
        Commands: [
          Git.Commands.Add,
          Git.Commands.Branch,
          Git.Commands.Checkout,
          Git.Commands.Clone,
          Git.Commands.Commit,
          Git.Commands.Diff,
          Git.Commands.Init,
          Git.Commands.Log,
          Git.Commands.Merge,
          Git.Commands.Remote,
          Git.Commands.Reset,
          Git.Commands.Stash,
          Git.Commands.Status,
          Git.Commands.Tag
        ],
        Internals: [
          Git.Command,
          Git.Config
        ]
      ]
    ]
  end
end
