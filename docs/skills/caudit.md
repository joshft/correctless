---
title: "/caudit"
parent: "High+ Intensity"
grand_parent: Skills
nav_order: 3
---

# /caudit — Cross-Codebase Quality Audit (Olympics)

> Run convergence-based audits using parallel specialist agents with hostile lenses. The loop runs until no critical or high findings remain.

## When to Use

- After a major feature lands (scope to changed files + dependencies)
- End-of-week sweep (full project scope for systemic issues)
- Pre-release gate (full scope, both QA and Hacker presets)
- After an incident (targeted scope to affected subsystem)
- **Not for:** feature-level bug detection during development — that is `/ctdd`'s job

## How It Fits in the Workflow

Runs independently of the main spec-to-merge pipeline. The TDD cycle catches "does this feature work?" bugs. The Olympics catch "how does this feature break everything else?" and "how does an attacker abuse this feature?" bugs. Operates on a dedicated audit branch; fixes never go directly to main.

**Requires high intensity or above.**

## What It Does

- Creates an audit branch (`audit/{preset}-{date}`) for all fixes
- Spawns 5-7 specialist agents in parallel, each with a hostile lens specific to the preset
- Agents classify findings into confidence tiers (confirmed, probable, suspicious) with bounty incentives for accuracy
- A triage agent deduplicates, validates, and rejects false positives
- Fixes are applied on the audit branch (TDD for non-trivial fixes, direct for one-liners)
- Fresh agents spawn for the next round with no memory of the previous round
- Repeats until convergence: zero critical/high findings and no new medium/low findings
- Writes mandatory regression tests after convergence

## Example

You run `/caudit qa` after landing a connection pool feature.

**Round 1:** 6 agents spawn. The Concurrency Specialist finds a race condition in pool resize (confirmed/critical). The Error Handling Auditor finds 3 silent error swallows in retry paths (confirmed/high). The Resource Lifecycle Tracker finds 2 unclosed connections in error branches (confirmed/high). The Input Boundary Tester finds 2 edge cases with zero-length payloads (probable/medium). The triage agent validates all 8, rejecting 0. You see: "Round 1: 8 findings. Running token cost: ~45k tokens. Continue to round 2?"

**Round 2:** Fresh agents spawn, told the previous round was sloppy. They check whether round 1 fixes introduced new issues. The Concurrency Specialist finds the mutex fix from round 1 created a potential deadlock under shutdown (confirmed/high). The Regression Hunter confirms a previously-fixed error pattern reappeared (confirmed/high, double bounty). Triage validates both. "Round 2: 2 findings."

**Round 3:** Fresh agents find nothing new. "Round 3: 0 findings. Converged." Regression tests are written, antipatterns updated, audit branch merged to main.

## What It Reads / Writes

| Reads | Writes |
|-------|--------|
| Source code (scoped by preset) | Per-round findings (`.correctless/artifacts/findings/audit-{preset}-{date}-round-{N}.json`) |
| `ARCHITECTURE.md` | Persistent history (`.correctless/artifacts/findings/audit-{preset}-history.md`) |
| `AGENT_CONTEXT.md` | Regression tests |
| `.correctless/antipatterns.md` | Updated antipatterns (`.correctless/antipatterns.md`) |
| Previous findings history | Token log (`.correctless/artifacts/token-log-{slug}.json`) |
| QA findings from TDD | Checkpoint (`.correctless/artifacts/checkpoint-caudit-{slug}.json`) |

## Options

Invoke with: `/caudit [preset] [scope]`

| Preset | Purpose | Agents | Max Rounds |
|--------|---------|--------|------------|
| `qa` | Incorrect behavior, silent failures, data corruption | Concurrency, Error Handling, Input Boundary, Resource Lifecycle, API Contract, Architecture Adherence Checker, Regression Hunter | 5 |
| `hacker` | Security vulnerabilities — bypass, escalation, exfiltration, DoS | Encoding/Normalization, Protocol Abuse, Auth/AuthZ, Config Manipulation, Injection, Architecture Adherence Checker, Regression Hunter | 7 |
| `perf` | Performance bottlenecks, memory waste, algorithmic inefficiency | Allocation Hunter, Algorithmic Complexity, I/O Bottleneck, Concurrency Efficiency, Architecture Adherence Checker, Regression Hunter | 5 |
| `ux` | UX failures — silent errors, missing feedback, lost output, broken recovery | First Contact, Upgrade Path, Cleanup/Offboarding, Error Recovery, Cross-Session Continuity, Architecture Adherence Checker, Regression Hunter | 5 |
| `custom` | Project-specific lenses (rate limiting, data integrity, compliance) | User-defined | Configurable |

Scope options: `all`, `changed` (default — git diff against main), or a specific path.

## Architecture Adherence Checker

Every preset includes an Architecture Adherence Checker agent that reads `.correctless/ARCHITECTURE.md` and mechanically checks the codebase against documented architecture entries. It performs four types of checks:

- **Pattern compliance** (PAT-xxx): verifies the code follows documented patterns
- **Abstraction invariant** (ABS-xxx): verifies the code maintains documented abstraction invariants
- **Trust boundary enforcement** (TB-xxx): verifies the code enforces documented trust boundary invariants
- **Undocumented pattern detection**: identifies project-specific conventions appearing in 3+ files that have no PAT-xxx entry

If `.correctless/ARCHITECTURE.md` does not exist or contains only placeholder markers, the Architecture Adherence Checker skips its checks and reports zero findings — architecture adherence checks are skipped. Architecture inference is not attempted; that is `/carchitect`'s job.

If ARCHITECTURE.md is stale (last updated more than 30 days before the most recent source commit), a staleness warning is prepended advising you to run `/cupdate-arch` to refresh the architecture document before trusting adherence findings.

## Common Issues

- **"Why so many rounds?"** The convergence loop runs until no new critical/high findings appear. Each round spawns fresh agents with no memory, told to do better than the previous round. This is deliberate — fixes can introduce new issues, and a single pass misses systemic problems.
- **Oscillation.** If round N reintroduces a finding that round N-1 fixed, the issue is escalated to you for manual resolution rather than looping indefinitely.
- **Cost visibility.** After every round, the skill reports findings, fixes, and cumulative token cost. You decide whether to continue or stop.
- **Max rounds exceeded.** If convergence is not reached within the max (5 for QA, 7 for Hacker), remaining findings go to human triage.
