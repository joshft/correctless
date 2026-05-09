---
title: "/cauto"
parent: "Core Workflow"
grand_parent: Skills
nav_order: 8
---

# /cauto — Semi-Auto Implementation Pipeline

> Orchestrate the full implementation pipeline after spec review. Runs /ctdd, /simplify, /cverify, /cupdate-arch, /cdocs, then creates a PR — with flexible phase resume and autonomous decision-making.

## When to Use

- After `/creview` (or `/creview-spec`) approves a spec — this runs the entire implementation pipeline
- When you want hands-off execution from TDD through PR creation
- When resuming a pipeline that was interrupted (escalation, context overflow, hard stop)
- **Not for:** features that don't have an approved spec yet (run `/cspec` and `/creview` first)

## How It Fits in the Workflow

`/cauto` is the pipeline orchestrator. Instead of manually running `/ctdd` → `/cverify` → `/cdocs` → PR, `/cauto` runs them all in sequence, handling failures, retries, and escalation. It respects the same workflow state machine as manual invocation — skills still run in separate agents with `context: fork`. The orchestrator invokes skills; skills do not auto-continue on their own.

## What It Does

1. **Phase gate** — reads the current workflow phase and computes remaining pipeline steps. Accepts any active phase from `review` through `documented`. Rejects `spec` and `model` (spec must be reviewed first).
2. **Install freshness check** — detects stale hooks before any skill runs. Warns if source files changed since last setup.
3. **Invoke /ctdd** — spawns a sub-agent for the full RED → GREEN → QA → mini-audit cycle. If TDD triggers a spec-update, escalates to the human.
4. **Commit before /simplify** — creates a clean revert point ("TDD complete").
5. **Invoke /simplify** — runs Claude Code's built-in simplification. Post-simplify validation reverts if tests fail or `.correctless/` paths were modified.
6. **Invoke /cverify** — verifies implementation matches spec.
7. **Invoke /cupdate-arch** (high+ intensity only) — updates architecture documentation.
8. **Invoke /cdocs** — updates project documentation.
9. **Consolidation** — scoped commit and push. Only stages known pipeline output paths. Belt-and-suspenders guard prevents committing artifacts.
10. **Create PR** — via `gh pr create` (default), skip, or custom command. PR body includes summary, test plan, QA findings, and verification status.

### Escalation

When a failure persists after N attempts (3 at standard, 2 at high/critical), the pipeline stops and writes a structured escalation file. Re-running `/cauto` after the human resolves the issue resumes from where it left off.

### Phase 2: Tiered Decision Architecture

Decisions are routed through a tiered hierarchy: Policy (deterministic) → Worker (self-resolution) → Decision Agent (ephemeral) → Supervisor (lightweight) → Hard Stop (human). Token and time budgets are enforced with warn at 75% and hard stop at 100%.

### Phase 3: Spec-to-PR Orchestration

When no workflow exists, `/cauto` can start from scratch — running `/cspec` interactively or accepting a provided spec file. Autonomous review with supervisor triage incorporates findings automatically. A mandatory spec approval gate always requires human confirmation before implementation begins.

## Example

```
Agent: Reading workflow state... phase is "review". Full pipeline ahead.
       Checking install freshness... all hooks current.
       Reading preferences... pr_creation: gh, defaults for all others.

       Starting /ctdd...
       [RED → test audit → GREEN → /simplify → QA → mini-audit]
       /ctdd complete. Committing TDD changes.

       Running /simplify... accepted (tests pass, no protected paths modified).

       Starting /cverify...
       Verification complete — 5/5 rules covered, 0 smells.

       Skipping /cupdate-arch (standard intensity).

       Starting /cdocs...
       Documentation updated.

       Consolidation: staging pipeline outputs...
       Pushed to origin/feature/my-feature.

       Creating PR via gh...
       PR #42 created: https://github.com/user/repo/pull/42

       Pipeline Summary:
       ┌──────────────┬──────────┬────────┬────────┐
       │ Step         │ Duration │ Tokens │ Result │
       ├──────────────┼──────────┼────────┼────────┤
       │ ctdd         │ 8m 12s   │ 45,200 │ pass   │
       │ simplify     │ 0m 34s   │ —      │ pass   │
       │ cverify      │ 1m 05s   │ 8,300  │ pass   │
       │ cupdate-arch │ —        │ —      │ skip   │
       │ cdocs        │ 2m 18s   │ 12,100 │ pass   │
       └──────────────┴──────────┴────────┴────────┘
```

## What It Reads / Writes

| Reads | Writes |
|-------|--------|
| Workflow state (`.correctless/artifacts/workflow-state-{slug}.json`) | All artifacts from invoked skills |
| `.correctless/config/workflow-config.json` | `.correctless/artifacts/audit-trail-{slug}.jsonl` |
| `.correctless/preferences.md` | `.correctless/artifacts/escalation-{slug}.md` (on failure) |
| `.correctless/config/auto-policy.json` (Phase 2) | `.correctless/meta/overrides/{slug}-{date}.json` |
| Approved spec | PR on GitHub |

## Intensity Levels

| Aspect | Standard | High | Critical |
|--------|----------|------|----------|
| Pipeline | ctdd → simplify → cverify → cdocs → PR | + cupdate-arch | + cupdate-arch |
| Failure threshold | 3 attempts | 2 attempts | 2 attempts |
| Supervisor activations | Same | Same | Same |

## Common Issues

- **"Run /creview first"**: The spec must be reviewed before `/cauto` can run. Run `/creview` or `/creview-spec` first.
- **Escalation during /ctdd**: Usually a spec issue — the spec contradicts implementation reality. Fix the spec and re-run.
- **Push failure**: Auth or rejected push. The local commit is preserved. Fix the issue and re-run — the phase gate routes to PR-only.
- **"gh CLI not installed"**: Set `pr_creation: skip` in `.correctless/preferences.md` or install `gh`.
- **Context overflow**: Each skill runs in a fresh context via `context: fork`. If the orchestrator itself overflows, re-run — the checkpoint system saves progress.
