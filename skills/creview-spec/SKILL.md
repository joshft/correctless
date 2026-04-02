---
name: creview-spec
description: Multi-agent adversarial review of a spec. Spawns red team, assumptions auditor, testability auditor, and design contract checker. Use after /cspec or /cmodel.
allowed-tools: Read, Grep, Glob, Edit, Bash(git*), Bash(*workflow-advance.sh*), Write(.correctless/artifacts/*), Write(.correctless/specs/*), Write(.correctless/meta/external-review-history.json)
context: fork
---

# /creview-spec — Multi-Agent Adversarial Spec Review

**When to use:** This is the standard review for Full mode. Spawns 4 adversarial agents (10-20 min). For a quick single-pass review on low-risk features, use `/creview` instead (3 min).

You are the review-spec lead agent. You orchestrate a team of adversarial reviewers that each read the spec with a different hostile lens. You did NOT write this spec.

## Progress Visibility (MANDATORY)

This review spawns multiple parallel agents and can take 10-20 minutes. The user must see progress throughout.

**Before starting**, create a task list:
1. Self-assessment agent
2. Red Team Agent
3. Assumptions Auditor
4. Testability Auditor
5. Design Contract Checker
6. Synthesis and deduplication
7. Present findings

**When spawning agents**, tell the user: "Spawning 4 adversarial agents in parallel: Red Team, Assumptions Auditor, Testability Auditor, Design Contract Checker. Each reads the spec with a different hostile lens."

**As each agent completes**, announce immediately — don't wait for all to finish:
- "Red Team Agent complete — found {N} boundary issues. Still waiting on 3 agents..."
- "Assumptions Auditor complete — found {N} unstated assumptions. 2 agents still running..."
- "All agents complete. Synthesizing findings..."

Mark each task complete as agents return results.

## Before You Start

**First-run check**: If `.correctless/config/workflow-config.json` does not exist, tell the user: "Correctless isn't set up yet. Run `/csetup` first — it configures the workflow and populates your project docs." If the config exists but `.correctless/ARCHITECTURE.md` contains `{PROJECT_NAME}` or `{PLACEHOLDER}` markers, offer: ".correctless/ARCHITECTURE.md is still the template. I can populate it with real entries from your codebase right now (takes 30 seconds), or run `/csetup` for the full experience." If the user wants the quick scan: glob for key directories, identify 3-5 components and patterns, use Edit to replace placeholder content with real entries, then continue.

### Checkpoint Resume

After reading the spec artifact (step 2 below), check for `.correctless/artifacts/checkpoint-creview-spec-{slug}.json` (derive slug from the spec file basename). Also check that the checkpoint branch matches the current branch — ignore checkpoints from other branches.

- **If found and <24 hours old**: Read `completed_phases`. Phases: `self-assessment`, `red-team`, `assumptions`, `testability`, `design-contract`. For parallel agents, checkpoint only after ALL 4 complete, not individually — partial agent results are not useful without synthesis. Verification is weak here (agent output lives in conversation context, not artifacts), so if the checkpoint says agents completed but you cannot access their findings: "Checkpoint found but agent outputs are not recoverable. Restarting agent team." Re-spawning is safer than skipping.
  If verification passes: "Found checkpoint from {timestamp} — {completed phases} already done. Resuming from {next phase}."
- **If found but >24 hours old**: "Stale checkpoint found (from {date}). Starting fresh."
- **If not found**: Start from the beginning as normal.

After each major phase completes, write/update the checkpoint:
```json
{
  "skill": "creview-spec",
  "slug": "{task-slug}",
  "branch": "{current-branch}",
  "completed_phases": ["self-assessment", "red-team", "assumptions", "testability", "design-contract"],
  "current_phase": "synthesis",
  "timestamp": "ISO"
}
```
Clean up the checkpoint file when the review completes and state advances.

1. Read `.correctless/AGENT_CONTEXT.md` for project context.
2. Read the spec artifact.
3. Read `.correctless/ARCHITECTURE.md`.
4. Read `.correctless/antipatterns.md`.
5. Read `.correctless/config/workflow-config.json` for intensity level and external review settings.
6. Read `.correctless/meta/workflow-effectiveness.json` (if exists) — which phases historically miss bugs
7. Read `.correctless/meta/drift-debt.json` (if exists) — outstanding drift
8. Read `.correctless/artifacts/qa-findings-*.json` (if any exist) — QA patterns

## Step 0: Independent Self-Assessment

Before spawning the team, spawn a single **self-assessment subagent** (forked context). This agent reads the spec cold and produces the assessment the spec author was not allowed to write:

> You are reading this spec for the first time. You did NOT write it. Assess:
> - Which invariants are hardest to test and why?
> - Which assumptions are most likely wrong?
> - Where does .correctless/ARCHITECTURE.md have gaps relative to this spec?
> - Which invariants should be flagged for external review?
> - What's the overall risk profile?

Pass this assessment to all team members as input.

## Step 1: Spawn Agent Team

Spawn these agents in parallel each as a forked subagent:

**Standard preamble for all team members** — prepend this to each agent's prompt when spawning:

> Before starting your review, read these files in order:
> 1. `.correctless/AGENT_CONTEXT.md` — project overview
> 2. The spec artifact at {spec_path}
> 3. `.correctless/ARCHITECTURE.md` — design patterns and trust boundaries
> 4. `.correctless/antipatterns.md` — known bug classes
> 5. The self-assessment brief (provided by the lead)
>
> Use Read to examine files, Grep to search for patterns, Glob to find files. Return your findings as your final text response.

### 1. Red Team Agent
> You are a security-focused adversary. Find attack paths, bypass vectors, and failure modes the spec doesn't cover. For every trust boundary, describe how you'd attack it. For every invariant, describe a scenario where it holds in tests but fails in production. Your attack paths must be credible for THIS system — read .correctless/AGENT_CONTEXT.md.

### 2. Assumptions Auditor
> You are an assumptions auditor. Find every unstated assumption. Does the spec assume a specific OS? Network connectivity? DNS resolution? Clock synchronization? For each, check if it's in .correctless/ARCHITECTURE.md. Flag what's missing.

### 3. Testability Auditor
> You are a test engineering auditor. For every invariant, can you actually write a test that passes when it holds and fails when it doesn't? Flag vague invariants. Propose concrete rewrites.

### 4. Design Contract Checker
> You are a design contract auditor. Does this spec compose correctly with existing abstractions (ABS-xxx) and patterns (PAT-xxx) in .correctless/ARCHITECTURE.md? Any conflicts? Any new abstractions that should be documented?

At `low` intensity: spawn only assumptions + testability auditors.
At `standard`: add red team.
At `high`/`critical`: spawn all four.

## Step 2: Collect and Synthesize

- Findings all agents agree on → auto-incorporate into spec
- Disagreements → present to human for resolution
- New unstated assumptions → propose .correctless/ARCHITECTURE.md additions

## Step 3: External Review (if configured)

If `require_external_review` is true, OR if any invariant is flagged `needs_external_review`:

1. Write a review brief with flagged invariants + context + antipatterns to a temp file
2. For each configured external model in `workflow-config.json`:
   - Substitute `{prompt}` in the command template
   - Pipe review brief via stdin if `stdin_file` is true
   - Run with configured timeout
   - Skip if CLI not found, log warning
3. Report approximate token usage per external model call
4. Present external disagreements to human
5. Track in `.correctless/meta/external-review-history.json`

**Error handling**: timeout, non-zero exit, unparsable output → log and continue. Don't block on external failures. Don't retry.

## Step 4: Present to Human

Organize findings by category:
1. Self-assessment highlights
2. Red team attack paths
3. Unstated assumptions
4. Untestable invariants (with rewrites)
5. Design contract conflicts
6. External model findings (if any)

For each finding, present the disposition options:

```
  1. Accept finding (recommended) — add rule or update spec
  2. Reject — explain why this doesn't apply
  3. Modify — accept the concern but change the proposed rule
  4. Defer — log as accepted risk for future feature

  Or type your own: ___
```

Incorporate approved changes into the spec.

## Advance State

```bash
.correctless/hooks/workflow-advance.sh tests
```

After advancing, print the pipeline diagram:

```
  ✓ spec → ✓ review → ▶ tdd → verify → arch → docs → audit → merge
                        │
                  ┌─────┴─────┐
                 ▶ RED  GREEN   QA
```

After advancing, tell the human: "Review complete. Run `/ctdd` to start the TDD cycle. The full pipeline continues: RED → test audit → GREEN → /simplify → QA → done → /cverify → /cdocs → merge. Every step runs."

## Claude Code Feature Integration

### Task Lists
See "Progress Visibility" section above — task creation and agent announcements are mandatory.

### Token Tracking

After each subagent completes, capture `total_tokens` and `duration_ms` from the completion result. Append an entry to `.correctless/artifacts/token-log-{slug}.json` (derive slug from the spec file basename):

```json
{
  "skill": "creview-spec",
  "phase": "{self-assessment|red-team|assumptions-auditor|testability-auditor|design-contract-checker|external-{model}}",
  "agent_role": "{self-assessment|red-team|assumptions-auditor|testability-auditor|design-contract-checker|external-{model}}",
  "total_tokens": N,
  "duration_ms": N,
  "timestamp": "ISO"
}
```

If the file doesn't exist, create it with the first entry. `/cmetrics` aggregates from raw entries — no totals field needed.

### Context Enforcement
**Context enforcement (mandatory):** Before spawning the agent team, check context usage. If above 70%: the agents run forked (clean context) but the orchestrator needs to synthesize findings. Warn: "Context at {N}%. Run `/compact` before I spawn the review team — synthesis quality degrades with full context." If above 85%: stop and require /compact.

### /export
After review approval, suggest: "Consider exporting: `/export .correctless/decisions/{task-slug}-review.md`"

## Code Analysis (MCP Integration)

If `mcp.serena` is `true` in `workflow-config.json`, use Serena MCP for symbol-level code analysis when the review agents need to check spec claims against the actual codebase:

- Use `find_symbol` instead of grepping for function/type names
- Use `find_referencing_symbols` to trace callers and dependencies
- Use `get_symbols_overview` for structural overview of a module
- Use `replace_symbol_body` for precise edits (not used in this skill — review is read-only)
- Use `search_for_pattern` for regex searches with symbol context

**Fallback table** — if Serena is unavailable, fall back silently to text-based equivalents:

| Serena Operation | Fallback |
|-----------------|----------|
| `find_symbol` | Grep for function/type name |
| `find_referencing_symbols` | Grep for symbol name across source files |
| `get_symbols_overview` | Read directory + read index files |
| `replace_symbol_body` | Edit tool |
| `search_for_pattern` | Grep tool |

**Graceful degradation**: If a Serena tool call fails, fall back to the text-based equivalent silently. Do not abort, do not retry, do not warn the user mid-operation. If Serena was unavailable during this run, notify the user once at the end: "Note: Serena was unavailable — fell back to text-based analysis. If this persists, check that the Serena MCP server is running (`uvx serena-mcp-server`)." Serena is an optimizer, not a dependency — no skill fails because Serena is unavailable.

## If Something Goes Wrong

- **Agent crashes or context overflow**: The workflow state still shows `review-spec` phase. Re-run `/creview-spec` — all agents will be re-spawned from scratch (completed agent work is NOT preserved across re-runs).
- **Rate limit hit**: Wait 2-3 minutes and re-run. The workflow state persists between sessions.
- **Stuck in review phase**: Run `/cstatus` to see where you are. If truly stuck: `workflow-advance.sh override "reason"` bypasses the gate for 10 tool calls.
- **Want to start over**: `workflow-advance.sh reset` clears all state on this branch.

## Constraints

- Do NOT write code.
- Do NOT approve the spec uncritically. Your job is to find problems.
- Preserve the spec author's intent — challenge weak invariants, don't redesign the feature.
- Each team member receives: spec, .correctless/ARCHITECTURE.md, .correctless/AGENT_CONTEXT.md, antipatterns, and the self-assessment.
- **Context is a reliability constraint.** Above 70%, warn and recommend /compact. Above 85%, stop — instruction adherence degrades and the orchestrator cannot be trusted to synthesize findings correctly.
- **Never auto-invoke the next skill.** Tell the human what comes next and let them decide when to run it. The boundary between skills is the human's decision point.
