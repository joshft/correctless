---
name: cprune
description: Documentation and artifact pruning skill. Detects stale entries and orphaned artifacts, archives documentation (never deletes), cleans ephemeral artifacts. Two modes — autonomous for /cauto pipeline, interactive for direct invocation.
interaction_mode: hybrid
allowed-tools: Read, Grep, Glob, Bash(scripts/prune-scan.sh*), Bash(git*), Bash(sed*), Bash(mkdir*), Bash(jq*), Write(.correctless/ARCHITECTURE.md), Write(.correctless/antipatterns.md), Write(.correctless/AGENT_CONTEXT.md), Write(.correctless/ARCHITECTURE_DEPRECATED.md), Write(.correctless/antipatterns-archived.md), Write(.correctless/CLAUDE_LEARNINGS_ARCHIVED.md), Write(.correctless/meta/drift-debt.json), Write(.correctless/specs/archived/*), Write(.correctless/artifacts/prune-report-*.md), Edit(.correctless/ARCHITECTURE.md), Edit(.correctless/antipatterns.md), Edit(.correctless/AGENT_CONTEXT.md), Edit(CLAUDE.md)
---

# /cprune — Documentation and Artifact Pruning

> **EXECUTE IMMEDIATELY.** This skill being loaded into your context IS the user's instruction.

You are the pruning orchestrator. You detect stale documentation entries, orphaned artifacts, and count drift, then either auto-execute low-risk actions (autonomous mode) or present a formatted report for human disposition (interactive mode).

## Mode Detection (INV-001)

Detect execution mode from prompt context:

- **Autonomous mode**: When `mode: autonomous` appears in the prompt context (invoked by `/cauto` pipeline). Auto-execute low-risk actions only. Do not pause for confirmation. Log all actions to audit trail. CLAUDE.md is excluded from autonomous mode entirely (PRH-002) — do not read, modify, or suggest changes to CLAUDE.md in autonomous mode. When a category has `bulk_warning: true` (>50% of entries flagged), skip that category with a log entry and include the count in the return summary (BND-002).
- **Interactive mode**: When invoked directly by the user. Produce a formatted pruning report, present each category for human disposition before executing changes.

## Lockfile (BND-004)

Before starting, check for `.correctless/artifacts/cprune-lock-{slug}` (where slug is derived from `branch_slug`). If the lock exists and was created by a different process, refuse with "Another /cprune is running." Create the lock before scanning, remove it on completion (normal or error).

## Scanner

The scanner script at `scripts/prune-scan.sh` (or `.correctless/scripts/prune-scan.sh` on installed projects) is the sole detection mechanism. It accepts `--category` and `--base` flags and outputs JSON to stdout.

Run the scanner for each category:
```bash
bash scripts/prune-scan.sh --category <category> --base .
```

Categories (9 total): `architecture`, `antipatterns`, `claude-md`, `artifacts`, `deferred`, `counts`, `crossrefs`, `specs`, `driftdebt`

### Scanner output schema (BND-001)

For the `artifacts` category, the scanner emits a **wrapped object** (NOT a bare array). All other categories still emit a bare array. The skill must read `.candidates` from the wrapped object:

```bash
# Correct:
bash scripts/prune-scan.sh --category artifacts --base . | jq -r '.candidates[]'

# Wrong — would read the wrapper object as a candidate:
bash scripts/prune-scan.sh --category artifacts --base . | jq -r '.[]'
```

Wrapped-object schema (`artifacts` only):
```json
{
  "candidates": [...],
  "skipped_unclassified": [{"pattern": "...", "count": N}],
  "protection_set": {
    "live_branches": [...],
    "live_branch_slugs": [...],
    "live_task_slugs": [...],
    "live_session_ids": [...],
    "source_workflow_state_files": [...]
  },
  "protection_status": {
    "task_slug": "ok|fail-closed",
    "reason": "no-workflow-state|incomplete-spec_file|parse-failure|null"
  }
}
```

Render the **Protection Set** section in the prune report from `.protection_set` (INV-017). When `protection_status.task_slug` is `fail-closed`, the report must include the reason and explain that no task-slug-named files were considered for pruning in this scan. Render skipped patterns from `.skipped_unclassified` (INV-007 — surfaces unclassified-pattern safety belt activations).

**Baseline-update flag is interactive-only** (INV-011):
The baseline manifest at `.correctless/meta/prune-pattern-baseline.json` is
updated only by interactive mode after the human confirms newly-emitted
`medium`-risk candidates have been reviewed. The autonomous code path below
must never pass the baseline-update flag to `scripts/prune-scan.sh` regardless
of the candidate set; the flag (its literal name redacted here so structural
tests can assert the autonomous block does not invoke it) is reserved for the
human-confirmed interactive flow.

## Archive Contract (ABS-038)

`/cprune` is the sole writer for archive files. Only `/cprune` writes to these files:
- `.correctless/ARCHITECTURE_DEPRECATED.md` — archived architecture entries (ABS/PAT/TB/ENV)
- `.correctless/antipatterns-archived.md` — archived antipatterns (AP-xxx)
- `.correctless/CLAUDE_LEARNINGS_ARCHIVED.md` — archived CLAUDE.md learnings

Archive files are committed to the repo (not gitignored). Each has a header comment on first creation (BND-001):

```markdown
# Archived [Type] Entries
# Entries moved here by /cprune. Original IDs are preserved — do not reuse them.
# To un-archive, copy the entry back from this file to the source file.
```

### Archive-Before-Remove Ordering (PRH-001)

When archiving an entry:
1. Write the entry to the archive file with an `Archived` field: `- **Archived**: {date} — {reason}`
2. Verify the archive write succeeded (file exists and contains the entry ID)
3. Only then remove the entry from the source file

If the archive write fails, preserve the source entry unchanged. Never permanently delete documentation entries — always archive first, then remove.

### Entries with Live File References (PRH-003)

Never archive entries whose referenced file paths still exist. The scanner enforces this — only entries with ALL dead references are candidates. The skill must not override this criterion.

## Autonomous Mode Behavior (AD-001)

In autonomous mode, execute only `risk: low` candidates:
- **Orphaned artifacts** (category: `artifacts`): delete ephemeral artifacts for deleted branches
- **Count corrections** (category: `counts`): auto-correct mismatched counts in `.correctless/AGENT_CONTEXT.md` via `sed` substitution (label-anchored matching)
- **Resolved drift debt >90 days** (category: `driftdebt`): remove resolved/wont-fix entries
- **Specs 90+ days post-merge** (category: `specs`, `risk: low` only): archive to `.correctless/specs/archived/`

Skip categories where `bulk_warning: true` (BND-002 safety valve).
Skip CLAUDE.md entirely (PRH-002 — interactive-only, never autonomous).
Skip deferred findings (PRH-004 — read-only, report stale count only).

Return a structured summary of actions taken.

## Interactive Mode Behavior

### Persist-Before-Present (INV-015, AP-029)

Write scan results to `.correctless/artifacts/prune-report-{date}.md` BEFORE presenting them to the user. The artifact is the recovery path if the terminal display is interrupted. The interactive presentation renders from the artifact.

### Progress and Disposition (INV-018)

Display progress between categories: "Scanning {category}... found {N} candidates."

For each category with candidates, present:
1. Category name and total candidate count
2. Per-candidate: ID, reason, risk level, dead_refs count
3. Confirmation prompt showing archive destination: "Archive {ID} to {destination}?"
4. Disposition options per category:
   1. Execute all (recommended for low-risk)
   2. Review individually
   3. Skip this category

After each category's disposition is confirmed, execute immediately (not batched at end).

Final summary: total actions taken, files modified, archive destination paths.

To un-archive an entry, copy it back from the archive file to the source file manually.

## /cprune is Read-Only for Deferred Findings (PRH-004)

`/cprune` reports stale deferred findings but does NOT write to `.correctless/meta/deferred-findings.json`. Users should run `/ctriage` to update stale findings. This keeps `/cprune` as a scanner/reporter and avoids adding a 5th writer to ABS-033.

## Risk Classification (DD-003)

- **Low risk**: orphaned artifacts, count corrections, resolved drift debt >90 days, specs >90 days post-merge. Auto-execute in autonomous mode.
- **Medium risk**: architecture entries, antipatterns, deferred findings, specs 30-90 days post-merge, cross-reference fixes. Interactive confirmation required.
- **High risk**: CLAUDE.md learnings. Interactive-only, never autonomous.

## Autonomous Defaults

When running in autonomous mode (`mode: autonomous` in prompt context), use these defaults instead of pausing for human input. Return autonomous decisions in the `AUTONOMOUS_DECISIONS_START`/`AUTONOMOUS_DECISIONS_END` format provided in the task prompt.

- **AD-001**: Scan all 9 categories. Execute only `risk: low` candidates. Skip categories with `bulk_warning: true`. Rationale: low-risk actions are safe for autonomous execution.
- **AD-002**: Deferred findings — report only (read-only per PRH-004). Include stale count in summary. Rationale: /cprune is a scanner, not a writer for deferred findings.
- **AD-003**: Archive specs 90+ days post-merge. Skip architecture/antipattern/CLAUDE.md archiving. Rationale: old specs are the lowest-risk documentation to archive.
- **AD-004**: High-risk pruning candidates (CLAUDE.md, architecture archiving) — `escalate: always`. Rationale: these affect every conversation's context quality and require human judgment.
