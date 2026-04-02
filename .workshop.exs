configure(
  backend: AgentWorkshop.Backends.Claude,
  backend_config: ClaudeWrapper.Config.new(working_dir: "."),
  model: "sonnet",
  permission_mode: :bypass_permissions,
  context: """
  git_wrapper_ex - Elixir wrapper for the git CLI.
  Clean, direct mapping to CLI commands with parsed output structs.
  Follow existing patterns from claude_wrapper_ex and codex_wrapper_ex.
  Use conventional commits. Run mix test before considering work done.
  """,
  mcp: [port: 4222]
)

# Profiles for ephemeral agents
profile(:coder, "You write clean, well-tested Elixir code. Always include tests.",
  max_turns: 15
)

profile(:reviewer, "You review code. Do not modify files. Check for correctness, edge cases, and style.",
  model: "opus",
  allowed_tools: ["Read", "Bash"]
)

# The orchestrator - has workshop tools to create and manage agents
agent(:orchestrator,
  """
  You coordinate a team of agents to build software. You have access to Workshop tools.

  Your workflow:
  1. Break down the task into discrete work items
  2. Create agents from profiles (:coder, :reviewer) using from_profile
  3. Assign work via ask or cast
  4. Pipe implementation results to a reviewer
  5. Report final status

  Available profiles: :coder (writes code + tests), :reviewer (read-only review)
  """,
  workshop_tools: true,
  model: "opus",
  max_turns: 30
)
