# Git as a state machine for agent-driven development.
#
# Run from the repository root:
#
#     mix run --no-start examples/state_machine.exs
#
# The model: an issue's lifecycle is a sequence of phases (prep -> implement ->
# review). Git is the state substrate:
#
#   * State      = an immutable commit per phase milestone
#   * Phase      = a branch, namespaced per issue (agent/issue-N/work)
#   * Isolation  = an ephemeral worktree per issue
#   * Metadata   = JSON in git notes (refs/notes/agents/metadata)
#   * Transition = a mechanical gate: a shell exit code decides whether the
#                  machine commits and advances (0) or freezes and halts (!= 0)
#
# Between phases, an agent (human or LLM) mutates the worktree; the machine
# never trusts the agent's self-report, only the gate's exit code.
#
# The script also documents where the naive version of this design breaks,
# discovered by driving it end to end:
#
#   * Branches are repo-global across all worktrees. Two concurrent issues
#     cannot both use "phase-prep"; per-issue namespacing is a hard
#     requirement, not hygiene.
#   * Notes are durable, repo-global state. They do not vanish with the
#     worktree, they do not follow squash-merges or cherry-picks (new SHAs
#     carry no notes; see #163 for `notes copy`), and concurrent writers to
#     one notes ref silently lose updates. Treat them as a per-issue journal
#     with a single writer, and delete the ref explicitly at teardown.
#   * Cleanup is itself an ordered, gated transition: worktree remove FIRST,
#     branch delete SECOND. The reverse fails, and squash_merge(delete: true)
#     currently swallows that failure (#161).
#   * Only uncommitted worktree state is ephemeral. Everything ref-based
#     (commits, branches, notes, stashes) survives worktree removal; after
#     branch deletion the phase commits become unreachable and gc-fodder, so
#     tag them or keep the branch if the audit trail must outlive the issue.

defmodule StateMachine.Support do
  @moduledoc false

  def step(name, fun) do
    t0 = System.monotonic_time(:millisecond)
    result = fun.()
    dt = System.monotonic_time(:millisecond) - t0
    Process.put(:timings, [{name, dt} | Process.get(:timings, [])])
    IO.puts("[#{String.pad_leading(Integer.to_string(dt), 6)} ms] #{name}")
    result
  end

  # The mechanical gate: run a command in the worktree, return its exit code.
  # The state machine advances only on 0.
  def gate(dir, cmd, args) do
    {out, code} = System.cmd(cmd, args, cd: dir, stderr_to_stdout: true)
    {code, out}
  end

  def assert!(true, _msg), do: :ok
  def assert!(other, msg), do: raise("ASSERT FAILED: #{msg} -- got #{inspect(other)}")

  def ok!({:ok, value}, _msg), do: value
  def ok!(other, msg), do: raise("EXPECTED {:ok, _} for #{msg} -- got #{inspect(other)}")

  def timings, do: Process.get(:timings, []) |> Enum.reverse()
end

alias StateMachine.Support, as: S

# ---------------------------------------------------------------------------
# Layout. A fixed temp path, pre-cleaned on every run, left in place afterwards
# so you can explore the result (git log, git notes, worktree list) by hand.
# ---------------------------------------------------------------------------
base = Path.join(System.tmp_dir!(), "git_wrapper_state_machine_demo")
repo = Path.join(base, "repo")
wt = Path.join(base, "worktrees/issue-123")
branch = "agent/issue-123/work"
notes_ref = "agents/metadata"

File.rm_rf!(base)
File.mkdir_p!(Path.join(repo, "lib"))
File.mkdir_p!(Path.join(repo, "test"))

# ---------------------------------------------------------------------------
# A tiny real mix project so the gates are real compiles and test runs.
# _build/ and deps/ must be gitignored: worktree removal refuses untracked
# files but tolerates ignored ones, so the .gitignore is what keeps the
# teardown force-free.
# ---------------------------------------------------------------------------
File.write!(Path.join(repo, "mix.exs"), """
defmodule Demo.MixProject do
  use Mix.Project

  def project do
    [app: :demo, version: "0.1.0", elixir: "~> 1.14", deps: []]
  end
end
""")

File.write!(Path.join(repo, ".gitignore"), """
/_build/
/deps/
""")

File.write!(Path.join(repo, "lib/demo.ex"), """
defmodule Demo do
  def greet(name), do: "Hello, " <> name
end
""")

File.write!(Path.join(repo, "test/test_helper.exs"), "ExUnit.start()\n")

File.write!(Path.join(repo, "test/demo_test.exs"), """
defmodule DemoTest do
  use ExUnit.Case

  test "greet" do
    assert Demo.greet("agent") == "Hello, agent"
  end
end
""")

# Git.init has no :initial_branch option yet (#162), so init is the one raw
# git call in the whole lifecycle.
{_, 0} = System.cmd("git", ["init", "--initial-branch=main"], cd: repo, stderr_to_stdout: true)

cfg = Git.Config.new(working_dir: repo)
S.ok!(Git.git_config(set_key: "user.name", set_value: "State Machine", config: cfg), "user.name")

S.ok!(
  Git.git_config(set_key: "user.email", set_value: "sm@example.com", config: cfg),
  "user.email"
)

S.step("initial commit on main", fn ->
  S.ok!(Git.Workflow.commit_all("chore: initial demo project", config: cfg), "initial commit")
end)

# ---------------------------------------------------------------------------
# Issue starts: one worktree + one namespaced branch. Branches are repo-global,
# so the issue number in the branch name is what lets a second issue run
# concurrently.
# ---------------------------------------------------------------------------
S.step("worktree add (#{branch})", fn ->
  S.ok!(Git.worktree(add_path: wt, add_new_branch: branch, config: cfg), "worktree add")
end)

wcfg = Git.Config.new(working_dir: wt)

# ---------------------------------------------------------------------------
# PREP phase. Ingress: drop the issue context into the worktree. Then the
# phase rhythm: gate -> commit -> note.
# ---------------------------------------------------------------------------
File.write!(
  Path.join(wt, "github_context.json"),
  JSON.encode!(%{issue: 123, title: "Add Demo.shout/1", labels: ["enhancement"]})
)

{prep_code, _} = S.step("GATE prep: mix compile", fn -> S.gate(wt, "mix", ["compile"]) end)
S.assert!(prep_code == 0, "prep gate exit 0")

S.step("commit state(prep)", fn ->
  S.ok!(
    Git.Workflow.commit_all("state(prep): capture context for issue-123", config: wcfg),
    "prep commit"
  )
end)

S.step("note state(prep)", fn ->
  S.ok!(
    Git.notes(
      add: true,
      message: JSON.encode!(%{phase: "prep", issue: 123, gate: "mix compile", exit: 0}),
      ref: "HEAD",
      notes_ref: notes_ref,
      config: wcfg
    ),
    "prep note"
  )
end)

prep_sha = S.ok!(Git.rev_parse(ref: "HEAD", config: wcfg), "prep sha")

# ---------------------------------------------------------------------------
# IMPLEMENT phase, failure path first. The "agent" produces broken code; the
# gate fails; the machine freezes with the tree dirty and HEAD unmoved.
# Nothing advances on a red gate.
# ---------------------------------------------------------------------------
File.write!(Path.join(wt, "lib/demo.ex"), """
defmodule Demo do
  def greet(name), do: "Hello, " <> name
  def shout(name) do
    String.upcase(greet(name)
  end
end
""")

{fail_code, _} =
  S.step("GATE implement (broken): mix compile", fn -> S.gate(wt, "mix", ["compile"]) end)

S.assert!(fail_code != 0, "broken gate must be nonzero")

{:ok, frozen} = Git.status(config: wcfg)
S.assert!(frozen.branch == branch, "still on the issue branch")
S.assert!(Enum.any?(frozen.entries, &String.contains?(&1.path, "demo.ex")), "dirty file visible")
head_after_fail = S.ok!(Git.rev_parse(ref: "HEAD", config: wcfg), "HEAD after failed gate")
S.assert!(head_after_fail == prep_sha, "HEAD unmoved: the machine did not advance")

IO.puts(
  "HALT verified: gate exit #{fail_code}, tree frozen, HEAD still #{String.slice(prep_sha, 0, 8)}"
)

# The "agent" fixes the code; the same gate now passes and the machine advances.
File.write!(Path.join(wt, "lib/demo.ex"), """
defmodule Demo do
  def greet(name), do: "Hello, " <> name
  def shout(name), do: String.upcase(greet(name))
end
""")

File.write!(Path.join(wt, "test/demo_test.exs"), """
defmodule DemoTest do
  use ExUnit.Case

  test "greet" do
    assert Demo.greet("agent") == "Hello, agent"
  end

  test "shout" do
    assert Demo.shout("agent") == "HELLO, AGENT"
  end
end
""")

{impl_code, _} =
  S.step("GATE implement (fixed): mix compile", fn -> S.gate(wt, "mix", ["compile"]) end)

S.assert!(impl_code == 0, "fixed gate exit 0")

S.step("commit state(implement)", fn ->
  S.ok!(
    Git.Workflow.commit_all("state(implement): add Demo.shout/1", config: wcfg),
    "implement commit"
  )
end)

S.step("note state(implement)", fn ->
  S.ok!(
    Git.notes(
      add: true,
      message:
        JSON.encode!(%{
          phase: "implement",
          issue: 123,
          gate: "mix compile",
          exit: 0,
          halted_once: true
        }),
      ref: "HEAD",
      notes_ref: notes_ref,
      config: wcfg
    ),
    "implement note"
  )
end)

# ---------------------------------------------------------------------------
# REVIEW phase: a stronger gate (mix test), and context ingestion reads the
# previous phase's note in one call.
# ---------------------------------------------------------------------------
{:ok, prev_note} = Git.notes(show: "HEAD~1", notes_ref: notes_ref, config: wcfg)
S.assert!(JSON.decode!(prev_note)["phase"] == "prep", "previous phase context readable")

{review_code, review_out} = S.step("GATE review: mix test", fn -> S.gate(wt, "mix", ["test"]) end)
S.assert!(review_code == 0, "review gate exit 0")

IO.puts(
  "mix test: " <>
    (review_out |> String.split("\n", trim: true) |> Enum.at(-2, "") |> String.trim())
)

File.write!(Path.join(wt, "REVIEW.md"), "Reviewed issue-123: compile and tests green.\n")

S.step("commit state(review)", fn ->
  S.ok!(
    Git.Workflow.commit_all("state(review): tests green, approved", config: wcfg),
    "review commit"
  )
end)

S.step("note state(review)", fn ->
  S.ok!(
    Git.notes(
      add: true,
      message: JSON.encode!(%{phase: "review", issue: 123, gate: "mix test", exit: 0}),
      ref: "HEAD",
      notes_ref: notes_ref,
      config: wcfg
    ),
    "review note"
  )
end)

# Claim check: every phase milestone is an immutable, addressable commit.
S.assert!(
  prep_sha == S.ok!(Git.rev_parse(ref: prep_sha, config: wcfg), "prep re-resolve"),
  "prep commit stable"
)

{:ok, phase_log} = Git.log(config: wcfg)
IO.puts("issue branch log: #{inspect(Enum.map(phase_log, & &1.subject))}")

# ---------------------------------------------------------------------------
# Issue complete: squash-merge back to main from the MAIN repo config.
# Note: delete: true would silently fail here because the worktree still holds
# the branch (#161), so the cleanup below does it properly instead.
# ---------------------------------------------------------------------------
S.step("squash_merge #{branch} -> main", fn ->
  S.ok!(
    Git.Workflow.squash_merge(branch, message: "feat: issue-123 shout (squashed)", config: cfg),
    "squash merge"
  )
end)

{:ok, main_log} = Git.log(config: cfg)
S.assert!(hd(main_log).subject =~ "squashed", "squash commit on main")
S.assert!(File.read!(Path.join(repo, "lib/demo.ex")) =~ "shout", "merged code present on main")

# ---------------------------------------------------------------------------
# Teardown, in the only order that works: worktree remove FIRST (the branch
# cannot be deleted while a worktree holds it), branch delete SECOND. The
# metadata journal in refs/notes/agents/metadata survives all of this; delete
# the ref explicitly if vanish-with-the-issue semantics are wanted:
#
#     Git.update_ref(ref: "refs/notes/agents/metadata", delete: true, config: cfg)
# ---------------------------------------------------------------------------
S.step("worktree remove", fn ->
  S.ok!(Git.worktree(remove_path: wt, config: cfg), "worktree remove")
end)

S.step("branch delete", fn ->
  S.ok!(Git.branch(delete: branch, force_delete: true, config: cfg), "branch -D")
end)

{:ok, notes_after} = Git.notes(list: true, notes_ref: notes_ref, config: cfg)
IO.puts("notes surviving teardown (durable by design): #{length(notes_after)}")

# ---------------------------------------------------------------------------
# Timings: git's cost per transition vs the gates'. The substrate is cheap;
# the gates dominate even on a trivial project.
# ---------------------------------------------------------------------------
IO.puts("\n=== timings (ms) ===")

for {name, ms} <- S.timings(),
    do: IO.puts("#{String.pad_leading(Integer.to_string(ms), 6)}  #{name}")

{gates, transitions} =
  Enum.split_with(S.timings(), fn {name, _} -> String.starts_with?(name, "GATE") end)

sum = fn pairs -> pairs |> Enum.map(&elem(&1, 1)) |> Enum.sum() end
IO.puts("git transitions: #{sum.(transitions)} ms total; gates: #{sum.(gates)} ms total")

IO.puts("\nAll assertions passed. Explore the result at #{base}")
