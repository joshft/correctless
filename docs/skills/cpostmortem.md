# /cpostmortem — Post-Merge Bug Analysis

> Analyze why a bug escaped the workflow and strengthen the process so the entire class of bug cannot recur.

## When to Use

- A bug is found in merged/production code that the workflow should have caught
- A previously fixed bug has reappeared in a different feature
- You want to understand which workflow phase is underperforming
- **Not for:** fixing the bug itself — that is a separate `/ctdd` cycle

## How It Fits in the Workflow

Runs outside the normal pipeline, triggered by a production bug or post-merge discovery. Does not touch code. Analyzes the gap in the process (spec, review, TDD, QA, audit) and produces class-level corrective actions that prevent the entire category of bug from recurring. Feeds learnings back into CLAUDE.md so every future agent session benefits.

**Full mode only.** This skill is not available in Lite mode.

## What It Does

- Gathers facts from the human: what broke, severity, which feature, which phases ran
- Traces the bug to a specific workflow gap: missing spec invariant, insufficient review, weak QA lens, skipped phase
- Determines class-level corrective actions (not instance fixes): new antipatterns, structural tests, invariant template updates, drift debt entries
- Writes a PMB (Post-Merge Bug) entry to `.claude/meta/workflow-effectiveness.json`
- Appends a learning to the `## Correctless Learnings` section of `CLAUDE.md` so all future agents know what escaped testing

## Example

Users report that logging in from two devices simultaneously causes one session to silently lose write permissions. The bug is in merged code.

You run `/cpostmortem`.

The agent reads the spec for the auth feature and finds INV-009: "each user may have at most 3 active sessions." The invariant exists but says nothing about what happens to an existing session's permissions when a new session is created. The test suite verifies session count limits but never tests concurrent session creation.

**Trace:** The spec phase (`/cspec`) missed the concurrent-session edge case. The review phase (`/creview-spec`) had an Assumptions Auditor that flagged "assumes sequential session creation" but the finding was marked low-severity and deferred.

**Corrective actions:**
1. **New antipattern (AP-014):** "Session lifecycle specs must define behavior under concurrent creation, not just count limits."
2. **Structural test:** A test that enumerates all session state transitions and verifies each is tested under both sequential and concurrent conditions.
3. **Invariant template update:** The auth-lifecycle template now requires a concurrency invariant for any state-bounded resource.

The PMB entry is written, phase effectiveness counters are updated (review-spec gets a "should have caught" increment), and a learning is appended to CLAUDE.md.

## What It Reads / Writes

| Reads | Writes |
|-------|--------|
| `.claude/meta/workflow-effectiveness.json` | `.claude/meta/workflow-effectiveness.json` (PMB entry) |
| `.claude/antipatterns.md` | `.claude/antipatterns.md` (new AP-xxx entry) |
| Spec artifact (`docs/specs/{slug}.md`) | `.claude/templates/invariants/` (template updates) |
| Verification report (`docs/verification/`) | `CLAUDE.md` (Correctless Learnings section) |
| Debug investigations (`.claude/artifacts/debug-investigation-*.md`) | Token log (`.claude/artifacts/token-log-{slug}.json`) |

## Corrective Action Types

| Action | What It Does | When to Use |
|--------|-------------|-------------|
| New antipattern (AP-xxx) | Adds a class-level bug pattern to `.claude/antipatterns.md` | The bug class is not yet tracked |
| Structural test | Automated test that catches all current and future instances | Highest-value action — turns a process gap into a CI check |
| Invariant template update | Adds a rule to spec templates so future specs include it | The spec domain template should have required this invariant |
| Drift debt (DRIFT-xxx) | Tracks unresolved architectural drift | The bug reveals a gap between docs and reality |

## Lite vs Full

This skill is **Full mode only**. In Lite mode, post-merge bug analysis is done manually. The structured tracing across workflow phases and automatic learning propagation require the full agent pipeline.

## Common Issues

- **"This was unpreventable."** The agent pushes back on this conclusion. It will ask whether a structural test, template update, or different test approach would have caught it. You must explicitly confirm if you truly believe it was unpreventable.
- **Instance fix vs. class fix.** The agent rejects instance-level corrective actions ("add the missing call"). Every corrective action must prevent the entire category from recurring, not just this specific bug.
- **Narrow QA fixes from prior rounds.** If a previous QA round found and fixed one instance of this bug class but the bug recurred in another feature, the postmortem flags the original corrective action as too narrow and specifies what the class fix should have been.
- **Does not fix the bug.** The postmortem analyzes and improves the process. The actual bug fix is a separate `/ctdd` cycle.
