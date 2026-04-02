defmodule GitWrapperEx.MixProject do
  use Mix.Project

  def project do
    [
      app: :git_wrapper_ex,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
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
      {:plug, "~> 1.16"}
    ]
  end
end
