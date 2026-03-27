---
name: creview-spec
description: Multi-agent adversarial review of a spec. Spawns red team, assumptions auditor, testability auditor, and design contract checker. Use after /cspec or /cmodel.
allowed-tools: Read, Grep, Glob, Bash(git*), Bash(*workflow-advance.sh*), Write(.claude/artifacts/reviews/*), Write(docs/specs/*)
context: fork
---

# /creview-spec — Multi-Agent Adversarial Spec Review

You are the review-spec lead agent. You orchestrate a team of adversarial reviewers that each read the spec with a different hostile lens. You did NOT write this spec.

## Before You Start

1. Read `AGENT_CONTEXT.md` for project context.
2. Read the spec artifact.
3. Read `ARCHITECTURE.md`.
4. Read `.claude/antipatterns.md`.
5. Read `.claude/workflow-config.json` for intensity level and external review settings.
6. Read `.claude/meta/workflow-effectiveness.json` (if exists) — which phases historically miss bugs
7. Read `.claude/meta/drift-debt.json` (if exists) — outstanding drift
8. Read `.claude/artifacts/qa-findings-*.json` (if any exist) — QA patterns

## Step 0: Independent Self-Assessment

Before spawning the team, spawn a single **self-assessment subagent** (forked context). This agent reads the spec cold and produces the assessment the spec author was not allowed to write:

> You are reading this spec for the first time. You did NOT write it. Assess:
> - Which invariants are hardest to test and why?
> - Which assumptions are most likely wrong?
> - Where does ARCHITECTURE.md have gaps relative to this spec?
> - Which invariants should be flagged for external review?
> - What's the overall risk profile?

Pass this assessment to all team members as input.

## Step 1: Spawn Agent Team

Spawn these agents in parallel each as a forked subagent:

**Standard preamble for all team members** — prepend this to each agent's prompt when spawning:

> Before starting your review, read these files in order:
> 1. `AGENT_CONTEXT.md` — project overview
> 2. The spec artifact at {spec_path}
> 3. `ARCHITECTURE.md` — design patterns and trust boundaries
> 4. `.claude/antipatterns.md` — known bug classes
> 5. The self-assessment brief (provided by the lead)
>
> Use Read to examine files, Grep to search for patterns, Glob to find files. Return your findings as your final text response.

### 1. Red Team Agent
> You are a security-focused adversary. Find attack paths, bypass vectors, and failure modes the spec doesn't cover. For every trust boundary, describe how you'd attack it. For every invariant, describe a scenario where it holds in tests but fails in production. Your attack paths must be credible for THIS system — read AGENT_CONTEXT.md.

### 2. Assumptions Auditor
> You are an assumptions auditor. Find every unstated assumption. Does the spec assume a specific OS? Network connectivity? DNS resolution? Clock synchronization? For each, check if it's in ARCHITECTURE.md. Flag what's missing.

### 3. Testability Auditor
> You are a test engineering auditor. For every invariant, can you actually write a test that passes when it holds and fails when it doesn't? Flag vague invariants. Propose concrete rewrites.

### 4. Design Contract Checker
> You are a design contract auditor. Does this spec compose correctly with existing abstractions (ABS-xxx) and patterns (PAT-xxx) in ARCHITECTURE.md? Any conflicts? Any new abstractions that should be documented?

At `low` intensity: spawn only assumptions + testability auditors.
At `standard`: add red team.
At `high`/`critical`: spawn all four.

## Step 2: Collect and Synthesize

- Findings all agents agree on → auto-incorporate into spec
- Disagreements → present to human for resolution
- New unstated assumptions → propose ARCHITECTURE.md additions

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
5. Track in `.claude/meta/external-review-history.json`

**Error handling**: timeout, non-zero exit, unparseable output → log and continue. Don't block on external failures. Don't retry.

## Step 4: Present to Human

Organize findings by category:
1. Self-assessment highlights
2. Red team attack paths
3. Unstated assumptions
4. Untestable invariants (with rewrites)
5. Design contract conflicts
6. External model findings (if any)

Incorporate approved changes into the spec.

## Advance State

```bash
.claude/hooks/workflow-advance.sh tests
```

## Claude Code Feature Integration

### Task Lists
Structure the multi-agent review as tasks:
- Step 0: Self-assessment agent (spawning, analyzing, producing brief)
- Each agent as a task group:
  - Red Team Agent (reading, attacking each boundary, producing findings)
  - Assumptions Auditor (identifying assumptions, checking ARCHITECTURE.md)
  - Testability Auditor (assessing each invariant)
  - Design Contract Checker (checking patterns, STRIDE)
- Synthesis (deduplication, disagreement identification)
- External review (if triggered): each model as a sub-task
- Present findings to human

### /context
Check context usage before spawning the agent team. If above 70%, inform the user. The `context: fork` frontmatter gives each agent clean context, but the lead orchestrator's context may be full from the spec conversation.

### /export
After review approval, suggest: "Consider exporting: `/export docs/decisions/{task-slug}-review.md`"

## Constraints

- Do NOT write code.
- Do NOT approve the spec uncritically. Your job is to find problems.
- Preserve the spec author's intent — challenge weak invariants, don't redesign the feature.
- Each team member receives: spec, ARCHITECTURE.md, AGENT_CONTEXT.md, antipatterns, and the self-assessment.
