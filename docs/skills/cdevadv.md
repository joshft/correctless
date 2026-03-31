# /cdevadv — Devil's Advocate (10th Man Rule)

> Challenge the assumptions, architecture, and strategies that every other agent accepts as true.

## When to Use

- Monthly health check on accumulated assumptions
- Pre-release, before anything ships to production
- After a milestone when early assumptions become load-bearing at scale
- After a production incident to determine if it reveals a deeper design flaw
- When things feel too smooth: Olympics converging quickly, zero spec revisions, no reviewer pushback
- **Not for:** finding code-level bugs — that is `/caudit`'s job. This skill operates at the assumption/architecture/strategy level.

## How It Fits in the Workflow

Runs periodically, not per-feature. Every other agent in the pipeline (spec author, reviewer, test writer, QA, auditor) operates within the frame of "this project's design is fundamentally sound." The devil's advocate questions whether the frame itself is correct. It checks whether the spec is pointing in the wrong direction, not whether the code matches the spec.

**Full mode only.** This skill is not available in Lite mode.

## What It Does

- Scans project metadata, architecture docs, antipatterns, drift debt, findings history, and dependency manifests
- Identifies unquestioned assumptions that every agent shares (same model, same training data, same blind spots)
- Produces 2-5 deep findings with concrete evidence from the codebase, not speculation
- Categorizes findings by severity: paradigm (core assumption is wrong), architecture (abstraction is inadequate), strategy (testing/security approach has a blind spot)
- Presents findings to the human for disposition: accepted, deferred (tracked in drift debt), or rejected with reasoning

## Example

You run `/cdevadv layers` after a quarter of development.

**Pass 1 (Dependencies):** The agent reads `package.json` and finds the caching library has not been updated in 14 months and its README warns it is "designed for single-process use."

**Pass 2 (Architecture):** ARCHITECTURE.md documents a caching abstraction (ABS-003) but says nothing about deployment topology. The agent notes that 4 specs reference ABS-003 and all implicitly assume cache coherence.

**Pass 3 (Strategy):** Antipatterns show 3 cache-related entries in the last 2 months. Olympics findings history shows a cache invalidation bug was found and fixed twice — different symptoms, same root cause.

**Pass 4 (Deep Dive):** The agent reads the caching module source and confirms: the library uses in-process memory with no invalidation protocol. In a multi-server deployment, each server has its own cache state with no coordination.

**Finding DA-012:** "The caching strategy assumes single-server deployment. Every spec, review, and test has accepted this because the dev environment is single-server. In production with 3+ servers, cache staleness will cause silent data inconsistency. The recurring cache bugs in Olympics are symptoms of this architectural gap, not isolated issues."

**Recommended action:** Replace the in-process cache with a shared cache (Redis) or add an invalidation protocol, and add an ENV-xxx entry to ARCHITECTURE.md documenting the deployment topology assumption.

## What It Reads / Writes

| Reads | Writes |
|-------|--------|
| `ARCHITECTURE.md` | Report (`.claude/artifacts/devadv/report-{date}.md`) |
| `AGENT_CONTEXT.md` | Drift debt updates (`.claude/meta/drift-debt.json`) |
| `.claude/antipatterns.md` | Token log (`.claude/artifacts/token-log-{slug}.json`) |
| `.claude/meta/drift-debt.json` | |
| `.claude/meta/workflow-effectiveness.json` | |
| `.claude/artifacts/findings/audit-*-history.md` | |
| Dependency manifests (go.mod, package.json, etc.) | |
| Source code (targeted, Pass 4 only) | |

## Options

Invoke with: `/cdevadv [mode] [argument]`

| Mode | Usage | What It Does |
|------|-------|-------------|
| `theme` | `/cdevadv theme "the auth model is sound"` | Challenges one specific area of consensus. You provide a thesis to disprove. |
| `signals` | `/cdevadv signals` | Spawns an explorer subagent to scan for "where things smell wrong," then deep-dives the top signals. |
| `layers` | `/cdevadv layers` | Four passes at increasing abstraction cost: Dependencies, Architecture, Strategy, Deep Dive. Context-efficient. |

## Common Issues

- **"This is just an Olympics finding."** The devil's advocate operates at the assumption level. "This function has a race condition" is an Olympics finding. "This project's approach to concurrency is fundamentally inadequate" is a devil's advocate finding. The agent is penalized for surface observations disguised as deep insights.
- **Evidence required.** Every claim must reference actual files, code paths, or patterns. Speculation without proof ("might not scale") is penalized.
- **Findings require disposition.** Every finding must be accepted, deferred, or rejected with specific reasoning. Silence is not acceptable — a future devil's advocate run will check whether deferred items still hold.
