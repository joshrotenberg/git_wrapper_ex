# Workshop Demo: git_wrapper_ex

Building a git CLI wrapper library entirely through Workshop agent orchestration.

## Goal

Start with `mix new`, hand a spec to an orchestrator agent, step back and watch.

## Setup

1. Created project: `mix new git_wrapper_ex`
2. Added deps: agent_workshop (path), claude_wrapper (path), MCP deps
3. Created `.workshop.exs` with:
   - Claude backend, bypass permissions
   - Two profiles: `:coder` (writes code + tests), `:reviewer` (read-only)
   - One orchestrator agent with `workshop_tools: true`
4. Created `.iex.exs` to auto-load Workshop

## The Prompt

```
ask(:orchestrator, """
Build a git CLI wrapper library for Elixir. Here's the spec:
- Layer 1: Direct mapping to git commands (status, log, diff, branch, commit, etc.)
- Layer 2: Parsed output structs (Status, Commit, Branch)
- Start with status, log, and commit. Tests for each.
Create coders from the :coder profile, have them implement, then create a reviewer to check.
""")
```

## Evaluation Criteria

- [ ] Orchestrator breaks down the task
- [ ] Orchestrator creates agents from profiles
- [ ] Agents produce working code
- [ ] Tests pass
- [ ] Reviewer provides feedback
- [ ] Code quality is acceptable
- [ ] Cost is reasonable

## Log

(will be filled in during the demo)

### Pre-demo
- Project created: mix new
- Deps configured: agent_workshop, claude_wrapper, MCP
- .workshop.exs: orchestrator + 2 profiles
- Ready to run

### Demo run
- Start time:
- End time:
- Total cost:
- Agents created:
- Turns used:
- Files produced:
- Tests passing:
- Issues encountered:
