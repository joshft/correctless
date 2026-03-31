# /creview-spec — Multi-Agent Adversarial Spec Review

> Spawn 4 adversarial agents in parallel to tear apart a spec before any code is written.

## When to Use

- After `/cspec` or `/cmodel` on any feature going through the Full pipeline
- When a spec has security-relevant invariants, trust boundaries, or cross-cutting concerns
- **Not for:** quick, low-risk features — use `/creview` (single-pass, 3 min) instead

## How It Fits in the Workflow

Sits between spec/model and TDD. This is the last gate before code gets written. Four hostile reviewers examine the spec simultaneously, each looking through a different lens. The goal is to find problems in the design, not in code that does not exist yet.

**Full mode only.** This skill is not available in Lite mode.

## What It Does

- Spawns a self-assessment subagent that reads the spec cold (independent of the author)
- Launches 4 adversarial agents in parallel, each with the self-assessment as input:
  - **Red Team Agent** — finds attack paths, bypass vectors, and failure modes the spec ignores
  - **Assumptions Auditor** — surfaces every unstated assumption (OS, network, clock, DNS)
  - **Testability Auditor** — flags vague invariants that cannot be turned into pass/fail tests
  - **Design Contract Checker** — verifies the spec composes correctly with ARCHITECTURE.md abstractions and patterns
- Synthesizes findings: unanimous agreement is auto-incorporated; disagreements go to the human
- Optionally routes flagged invariants to external models for cross-validation

## Example

You wrote a spec for a webhook delivery system. You run `/creview-spec`.

The self-assessment subagent flags INV-004 ("webhooks are delivered exactly once") as the hardest invariant to test. The 4 agents launch in parallel.

The Assumptions Auditor completes first, reporting 3 unstated assumptions: (1) the spec assumes webhook endpoints respond within 30 seconds but never states a timeout, (2) the retry policy assumes idempotent receivers but the spec does not require idempotency keys, (3) the spec assumes DNS resolution is stable during retry sequences.

The Red Team Agent finds that the signature verification in the spec does not account for replay attacks — an attacker who captures a signed payload can re-deliver it indefinitely.

The Testability Auditor flags INV-004 as untestable as written ("exactly once" across network partitions requires distributed consensus) and proposes a rewrite: "at-least-once delivery with idempotency key, deduplicated within a 24-hour window."

The Design Contract Checker notes a conflict with ABS-003 (the existing HTTP client abstraction), which does not expose retry metadata needed by the webhook system.

You approve the timeout, idempotency key, and replay protection additions. The spec is revised and you advance to `/ctdd`.

## What It Reads / Writes

| Reads | Writes |
|-------|--------|
| Spec artifact (`docs/specs/{slug}.md`) | Updated spec (incorporated findings) |
| `ARCHITECTURE.md` | Checkpoint (`.claude/artifacts/checkpoint-creview-spec-{slug}.json`) |
| `AGENT_CONTEXT.md` | Token log (`.claude/artifacts/token-log-{slug}.json`) |
| `.claude/antipatterns.md` | |
| `.claude/workflow-config.json` | |
| `.claude/meta/workflow-effectiveness.json` | |

## Options

Intensity scales with risk:

| Intensity | Agents Spawned | Duration |
|-----------|---------------|----------|
| `low` | Assumptions + Testability only | ~5 min |
| `standard` | + Red Team | ~10 min |
| `high` / `critical` | All 4 agents | 10-20 min |

Intensity is set in `.claude/workflow-config.json`.

## Common Issues

- **Long runtime (10-20 min).** The skill announces each agent's completion as it happens. You do not need to wait silently.
- **Checkpoint recovery.** If interrupted, re-running `/creview-spec` checks for a checkpoint less than 24 hours old. If agent outputs are not recoverable from the checkpoint, agents are re-spawned from scratch.
- **External review failures.** If an external model times out or returns unparseable output, the skill logs a warning and continues. External failures never block the review.
