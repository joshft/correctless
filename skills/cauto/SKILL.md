---
name: cauto
description: Semi-auto mode. Orchestrates the full implementation pipeline after human-approved spec review. Runs ctdd, simplify, cverify, cupdate-arch, cdocs, then creates a PR. After /cauto completes, verify the workflow reached the expected end state — if it didn't, re-invoke /cauto to resume.
allowed-tools: Read, Grep, Glob, Bash(*), Write(.correctless/artifacts/*), Write(.correctless/meta/overrides/*), Edit, Task
interaction_mode: hybrid
---

# /cauto — Semi-Auto Implementation Pipeline

> **Shared constraints apply.** Before executing, read `_shared/constraints.md` from the parent of this skill's base directory. All constraints there apply to this skill.

You are the pipeline orchestrator. You invoke skills in sequence, monitor for failures, and escalate to the human when autonomous resolution is not possible. You do not write tests or production code yourself — each skill handles its own domain. You are the orchestrator that invokes skills; skills do not auto-continue on their own.

## Phase Gate — Flexible Phase Entry (R-002)

Before doing anything, read the current workflow state by running `bash .correctless/hooks/workflow-advance.sh status` and check the current phase.

`/cauto` accepts any active workflow phase and computes the remaining pipeline steps using a fixed phase-to-step mapping. The implementation pipeline mapping is:

| Current Phase | Remaining Pipeline Steps |
|---|---|
| `review` / `review-spec` | Full pipeline: `ctdd` → `simplify` → `cverify` → `cupdate-arch` → `cdocs` → consolidation → PR |
| `tdd-tests` | Resume from `ctdd` (handles internal TDD phases) → `simplify` → `cverify` → `cupdate-arch` → `cdocs` → consolidation → PR |
| `tdd-impl` | Resume from `ctdd` (handles internal TDD phases) → `simplify` → `cverify` → `cupdate-arch` → `cdocs` → consolidation → PR |
| `tdd-qa` | Resume from `ctdd` (handles internal TDD phases) → `simplify` → `cverify` → `cupdate-arch` → `cdocs` → consolidation → PR |
| `tdd-audit` | Resume from `ctdd` (handles internal TDD phases) → `simplify` → `cverify` → `cupdate-arch` → `cdocs` → consolidation → PR |
| `done` | `simplify` → `cverify` → `cupdate-arch` → `cdocs` → consolidation → PR |
| `verified` | `cupdate-arch` (if high+ intensity) → `cdocs` → consolidation → PR |
| `documented` | Consolidation → PR only |

**Rejected phases**: `spec` and `model` are rejected — the spec must be reviewed before the implementation pipeline can run. The `spec` rejection message: **"Run `/creview` or `/creview-spec` first — /cauto starts after spec review."**

Mid-TDD resume semantics are delegated to `/ctdd` — `/cauto` trusts `/ctdd` to handle the internal TDD state machine from wherever it currently is. `/ctdd` has its own internal phase-aware logic and will not restart from `tdd-tests` if the workflow is already at `tdd-impl` or `tdd-qa`.

When no workflow exists, `/cauto` delegates to Phase 3 entry logic (INV-019), which transitions through spec creation and review before entering this phase-to-step mapping at `review`/`review-spec`.

### Artifact Validation for Skipped Phases (R-002 supplement)

Before skipping a phase that is *behind* the current phase (already completed), `/cauto` validates that the phase's artifacts exist. For the current phase, `/cauto` invokes the corresponding skill directly without validation — validation only applies to phases being skipped, not phases being resumed.

Validation checks per phase:

- **(a) `ctdd` complete** → test suite passes. Execute `commands.test` from workflow-config.json using the Bash tool's `timeout` parameter, defaulting to 300 seconds. The timeout is configurable via `commands.test_timeout` in workflow-config.json (integer, seconds). Exit code 0 = validation pass. Non-zero or timeout = validation fail; `/cauto` re-runs the phase.
- **(b) `simplify`** → no validation needed (optional step).
- **(c) `cverify` complete** → verification report exists at `.correctless/verification/{task-slug}-verification.md`.
- **(d) `cupdate-arch`** → no validation needed (advisory).
- **(e) `cdocs`** → no validation needed (advisory).

If validation fails 2 consecutive times, skip validation and proceed — the phase's own skill will re-verify.

The validation failure is logged in the audit trail with type `artifact_validation_failed`.

## Canonical Step Name Enum (R-010)

The canonical step name enum is the single source of truth for `expected_steps` and `completed_steps` values in the pipeline manifest.

At **high+ intensity**: `["ctdd", "simplify", "cverify", "cupdate-arch", "cdocs", "consolidation", "pr"]`

At **standard intensity**: `["ctdd", "simplify", "cverify", "cdocs", "consolidation", "pr"]` (cupdate-arch excluded — skipped at standard intensity per R-009)

These names correspond to pipeline Steps 1–9. Internal orchestration actions (pre-simplify commit, post-simplify validation, override-log preservation, pipeline summary) are excluded — they are not pipeline steps.

## Pipeline Manifest (R-001, R-002, R-003, R-006, R-008)

### Writing the Manifest (R-001)

As the FIRST action after the phase gate — before any skill invocation — write a pipeline manifest to `.correctless/artifacts/pipeline-manifest-{branch_slug}.json`. The manifest must contain:

```json
{
  "expected_steps": ["ctdd", "simplify", "cverify", "cupdate-arch", "cdocs", "consolidation", "pr"],
  "expected_end_phase": "documented",
  "completed_steps": [],
  "started_at": "2026-05-08T00:00:00Z",
  "branch": "feature/example-feature",
  "status": "in_progress"
}
```

- `expected_steps`: array of canonical step names from the step name enum (R-010), filtered by the current effective intensity. At standard intensity, `expected_steps` reflects the reduced pipeline without `cupdate-arch`.
- `expected_end_phase`: the workflow phase that indicates pipeline completion — `documented` for full runs, or the appropriate phase for partial runs.
- `completed_steps`: array, initially empty.
- `started_at`: ISO 8601 timestamp.
- `branch`: current branch name.

### Tracking Step Completion (R-002)

After each pipeline step completes successfully, append the current step name to `completed_steps` in the manifest. The append must happen AFTER the step completes but BEFORE the next step begins. Enforcement: prompt-level — SKILL.md instruction ordering.

### Marking Pipeline Complete (R-003)

As the FINAL action — after Step 10 (pipeline summary) — write `"status": "complete"` to the manifest. A manifest without `"status": "complete"` indicates truncation. This is how truncation is detected: if `/cauto` was interrupted or its context exhausted, the manifest will exist but `status` will not be `"complete"`.

### Manifest is Ephemeral (R-006)

The pipeline manifest is an ephemeral artifact — it is NOT committed during consolidation (Step 8). The manifest lives under `.correctless/artifacts/` which is already excluded from consolidation staging by Step 8.2's belt-and-suspenders guard.

## Effective Intensity

Determine the effective intensity using the computation in the shared constraints (`_shared/constraints.md`). The effective intensity controls pipeline behavior including attempt thresholds and skill activation.

## Install Freshness Check

Before any skill invocation, at pipeline startup (after the phase gate, before invoking any skill), check for stale hooks:

```bash
source .correctless/scripts/lib.sh
output="$(check_install_freshness "$(pwd)/.correctless" 2>/dev/null)"
```

Parse the output and emit warnings by status, in order of severity:

- **`source_ahead`**: "WARNING: {N} source file(s) changed since last setup: {list}. Installed hooks are STALE. Run `setup` to update — you are running outdated hooks that may not include recent fixes." This is the strongest warning (PR #63 failure class).
- **`modified`**: "WARNING: {N} installed file(s) differ from their install-time checksums: {list}. Run `setup` to re-install, or ignore if intentionally modified."
- **`missing`**: "WARNING: {N} installed file(s) are missing: {list}. Run `setup` to re-install."
- **`new_file`**: "WARNING: {N} file(s) in installed directories not in manifest: {list}. These were added after setup."
- **`no_manifest`**: "Install manifest not found — run `setup` to enable stale-hook detection."

All warnings are advisory, not blocking — the pipeline proceeds. If any non-ok statuses are found, log to the audit trail:
```json
{"type": "install_staleness_detected", "timestamp": "...", "skill": "orchestrator", "affected_files": [...], "statuses": {...}}
```

If all files are `ok`, no output.

## Upfront Tool Availability Check (R-018)

Before any skill invocation, at pipeline startup, verify tool availability for configured operations:

- If the `pr_creation` preference is `gh` (the default), check `command -v gh`. If `gh` is not found, fail fast with: **"gh CLI not installed. Set `pr_creation: skip` in preferences.md or install gh."** This upfront check prevents hours of implementation followed by a PR creation failure.

## Read Preferences (R-003)

Read `.correctless/preferences.md` if it exists. This file contains project-level preferences that guide autonomous decisions. If the file does not exist, proceed with built-in defaults — do not fail or abort when preferences.md is absent.

Built-in defaults when preferences.md is missing:
- QA finding triage: auto-fix CRITICAL and HIGH, surface MEDIUM and LOW
- Documentation scope: update all standard docs
- Commit granularity: one commit per skill phase
- Escalation sensitivity: escalate on any architectural decision
- PR creation: `gh` (create PR via `gh pr create`)

Log a `preference_applied` audit event for each non-default preference loaded from `preferences.md`. If all preferences match the built-in defaults (or the file is absent), no `preference_applied` events are logged.

## Resumption Check (R-016, R-004)

On invocation, check for an existing escalation file at `.correctless/artifacts/escalation-{branch_slug}.md`. If present:

1. Parse the YAML frontmatter to extract `completed_skills`, `failed_skill`, `failed_at_phase`, and other fields.
2. Check phase consistency: verify `failed_at_phase` matches the current workflow phase.
3. Verify completed skill artifacts still exist (tests pass, verification report present if applicable).
4. If both checks pass, resume from the failed skill — skip completed skills in the pipeline.
5. If either check fails (phase inconsistent or artifacts missing), delete the stale escalation file and start fresh with a clean pipeline run.

### Pipeline Manifest Truncation Detection (R-004)

Also read any existing pipeline manifest at `.correctless/artifacts/pipeline-manifest-{branch_slug}.json`. If the manifest exists but `status` is not `"complete"`, report which steps were missed:

> "Pipeline was truncated at step {last_completed}. Missing steps: {list}. Resuming from {next_step}."

The workflow state is authoritative (queried via `workflow-advance.sh`). The manifest is advisory — when the two conflict, workflow state wins. R-004 reports the divergence as a diagnostic signal, not as a superseding mechanism.

## Pipeline Order (R-001)

The pipeline invokes skills in this exact order: `/ctdd` -> `/simplify` -> `/cverify` -> `/cupdate-arch` -> `/cdocs`.

The orchestrator spawns a sub-agent for each skill, giving each a fresh context. Each skill must complete successfully before the next begins.

### Intensity-Aware Pipeline (R-009)

The effective intensity computation from shared constraints determines which skills are active:

- At **standard** intensity: skip `/cupdate-arch` (it has its own intensity gate requiring high+ intensity). The pipeline becomes: `/ctdd` -> `/simplify` -> `/cverify` -> `/cdocs` -> PR.
- At **high** or **critical** intensity: run the full pipeline including `/cupdate-arch`.

`cupdate-arch` has an independent intensity gate in its own SKILL.md — it will refuse to run at standard intensity regardless of whether `/cauto` invokes it.

When `/cupdate-arch` is skipped due to standard intensity, log a `preference_applied` audit event with the reason "cupdate-arch skipped: standard intensity".

### Autonomous Mode Dispatch (R-005, ABS-030)

When dispatching each skill via Task, the orchestrator must include `mode: autonomous` in the first 10 lines of the task prompt. Example:

```
mode: autonomous
You are running as part of the /cauto pipeline. Use your Autonomous Defaults section for all decision points instead of pausing for human input. Return your autonomous decisions as structured output at the end of your response in this format:

AUTONOMOUS_DECISIONS_START
{"decision_id": "AD-001", "default_applied": "...", "rationale": "...", "escalation_deferred": false, "original_escalation_reason": null}
{"decision_id": "AD-002", "default_applied": "...", "rationale": "...", "escalation_deferred": true, "original_escalation_reason": "..."}
AUTONOMOUS_DECISIONS_END
```

Skills detect `mode: autonomous` by checking their prompt context. When absent, skills run interactively (fail-open — the failure mode "pipeline stalls" is safer than "skill silently applies defaults when user expected to be asked").

**Sole-Writer Contract (ABS-030)**: `/cauto` is the sole writer of `.correctless/artifacts/autonomous-decisions-{branch_slug}.jsonl`. Skills do NOT write to this file directly. After each skill completes, `/cauto` parses the `AUTONOMOUS_DECISIONS_START`/`AUTONOMOUS_DECISIONS_END` block from the skill's output and writes each decision via the writer script:

```bash
bash scripts/autonomous-decision-writer.sh append "<skill-name>" '<json-line>'
```

The writer script handles branch_slug derivation, directory creation, and JSONL append internally — the SFG permits this because the Bash command contains no direct redirect to the protected path (same pattern as ABS-029/audit-record.sh). Each entry has fields: `skill` (string), `decision_id` (AD-xxx or AD-UNLISTED-N), `default_applied` (string), `rationale` (string), `timestamp` (ISO 8601), `escalation_deferred` (boolean, default false), `original_escalation_reason` (string, null unless escalation_deferred is true).

**JSONL Growth Verification**: After each skill invocation, verify the JSONL grew. For skills with `interaction_mode: autonomous` or `hybrid` that have known decision points in their `## Autonomous Defaults` section, if the skill's response contains no parseable decisions, log a warning in the pipeline summary (advisory, not blocking — first iteration).

**AD-UNLISTED Fallback (R-014)**: When a skill in autonomous mode encounters a decision point not listed in its `## Autonomous Defaults` section, it applies the first option (the recommended default) and returns it with `decision_id: AD-UNLISTED-{N}` and `escalation_deferred: true`. Unlisted decisions are highlighted separately in the end-of-pipeline summary under the Deferred Escalations heading.

### Workflow State Machine Transitions (R-010)

The orchestrator advances the workflow state machine through all required transitions using `workflow-advance.sh`. It must not skip transitions or write to the state file directly — always use `workflow-advance.sh` commands.

The full transition sequence for a clean run uses these actual phase names in order:

1. `tdd-tests` — RED phase: write failing tests from spec rules
2. `tdd-impl` — GREEN phase: implement to make tests pass
3. `tdd-qa` — QA phase: independent review of implementation
4. (loop: `tdd-impl` -> `tdd-qa` if QA finds issues, via the `fix` command which transitions back to `tdd-impl`)
5. `tdd-audit` — Mini-audit phase: adversarial specialist review (cross-component, hostile input, resource bounds)
6. `done` — TDD complete, ready for simplification and verification
7. `verified` — Post-implementation verification passed
8. `documented` — Documentation updated, pipeline complete

At high+ intensity, the optional `tdd-verify` phase may occur between `tdd-qa` and `tdd-audit` (handled internally by `/ctdd`). The `tdd-audit` phase runs at all intensity levels.

These transitions are managed by `/ctdd` internally for phases 1-5, and by `/cverify` and `/cdocs` for phases 6-7. The orchestrator monitors the phase after each skill completes.

## Pipeline Execution

### Step 1: Invoke `/ctdd`

Spawn a sub-agent to execute `/ctdd`. This skill manages the RED -> GREEN -> QA -> mini-audit cycle internally and advances the workflow through `tdd-tests`, `tdd-impl`, `tdd-qa`, `tdd-audit`, and `done` phases.

Log a `skill_started` audit trail entry before invocation.

If `/ctdd` triggers a spec-update (the spec was found to be wrong during TDD), escalate to the human immediately (R-017). The escalation summary must state which spec rule is unsatisfiable and the problematic rule that cannot be satisfied. This resets the phase back to `spec`, and the pipeline halts on spec-update. After the human fixes the spec and re-approves review, they re-invoke `/cauto` — the resumption check (R-016) detects `review`/`review-spec` phase and starts the pipeline fresh.

Log a `skill_completed` audit trail entry after successful completion.

### Step 2: Commit before `/simplify` (R-015)

After `/ctdd` completes, commit all TDD changes with the message "TDD complete" to establish a clean revert point. This commit before simplify ensures atomic rollback is possible.

### Step 3: Invoke `/simplify` (R-012)

`/simplify` is a Claude Code built-in command that operates outside the Correctless trust model. It has no SKILL.md, no allowed-tools, no context: fork, and no audit trail integration. It is treated as an untrusted contributor whose changes are validated post-hoc.

`/simplify` runs after `/ctdd` completes (the workflow is in `done` phase) and before `/cverify`. There is no workflow-advance.sh transition for `/simplify` — it runs during the `done` phase with no phase change.

### Step 4: Post-simplify validation (R-015)

After `/simplify` completes:

1. **Check the diff for `.correctless/` path modifications**: Run `git diff HEAD` and inspect for changes to any `.correctless/` paths or config files. If found, revert with `git reset --hard HEAD` and continue without simplification. Log the revert as `simplify_reverted` in the audit trail but do not escalate — continue without the simplification changes.

2. **Re-run the project's test suite**: If tests fail after simplify, revert with `git reset --hard HEAD` and continue without simplification. Log as `simplify_reverted` but do not escalate.

3. If tests pass and no protected paths were modified, accept the simplification and create a post-simplify commit.

### Step 5: Invoke `/cverify`

Spawn a sub-agent to execute `/cverify`. Log `skill_started` before, `skill_completed` after.

### Step 6: Invoke `/cupdate-arch` (high+ intensity only)

At high or critical intensity, spawn a sub-agent to execute `/cupdate-arch`. Skip at standard intensity (cupdate-arch requires high+ intensity). Log `skill_started` before, `skill_completed` after.

### Step 6.5: Invoke `/cprune` (autonomous, non-blocking)

Invoke `/cprune` in autonomous mode as an internal orchestration action (not a canonical pipeline step — excluded from the ABS-031 step name enum). At **high+ intensity**, this runs after `/cupdate-arch` (Step 6). At **standard intensity**, this runs after `/cverify` (Step 5) — since `/cupdate-arch` is skipped at standard, orphaned artifacts and count corrections would otherwise never run.

Pass `mode: autonomous` in the Task prompt. `/cprune` executes low-risk actions (orphaned artifact cleanup, count corrections, 90+ day spec archiving) and returns a summary. Include the summary under a "Pruning" heading in the end-of-pipeline summary. `/cprune` failure is non-blocking — if it fails, log the failure and continue the pipeline.

### Step 7: Invoke `/cdocs`

Spawn a sub-agent to execute `/cdocs`. Log `skill_started` before, `skill_completed` after.

After `/cdocs` completes, run `git diff --name-only HEAD` and check if CLAUDE.md appears in the changed files. If it does, trigger R-006(e) escalation — CLAUDE.md changes require human approval. Write the escalation file and halt the pipeline; do not proceed to PR creation until the human approves the CLAUDE.md changes.

### Step 7.5: Backlog Sweep (advisory, non-blocking)

Between `/cdocs` and consolidation, sweep the deferred findings backlog. Read `.correctless/meta/deferred-findings.json` — if the file exists, present ALL findings with status `open` to the user. In autonomous mode: log open findings as advisory in the pipeline summary; do not block. If the backlog file does not exist, the sweep is a no-op. Sweep failure is non-blocking — if it fails, consolidation proceeds normally.

This is an internal orchestration action, not a canonical pipeline step (excluded from the ABS-031 step enum).

### Step 8: Consolidation — Scoped Commit and Push (R-003, F-001)

Between `/cdocs` completion and PR creation, `/cauto` runs a consolidation step. This step uses scoped staging to prevent accidental commit of secrets or unintended files.

**Step 8.1: Stage known pipeline output paths only.** The staging set is the union of:
- Files changed on the branch: `git diff main...HEAD --name-only`
- Uncommitted pipeline outputs matching the explicit path list below

The explicit pipeline output path list is a constant — future additions to pipeline outputs must be added here. Unknown untracked files are never staged.

```
.correctless/verification/{task-slug}-verification.md
.correctless/ARCHITECTURE.md
.correctless/AGENT_CONTEXT.md
.correctless/ARCHITECTURE_DEPRECATED.md
.correctless/antipatterns-archived.md
.correctless/CLAUDE_LEARNINGS_ARCHIVED.md
.correctless/artifacts/probe-results-{branch-slug}.json
README.md
CONTRIBUTING.md
docs/workflow-history.md
docs/features/*.md
```

**Step 8.2: Belt-and-suspenders artifact guard.** Verify nothing under `.correctless/artifacts/` was staged — if anything was, unstage it, **except** probe-results files (TB-004c allowlist exception for committed probe data):
```bash
# Unstage artifacts except probe-results (probe-results excluded from unstaging per TB-004c)
git diff --cached --name-only | grep '^\.correctless/artifacts/' | grep -v 'probe-results' | xargs -r git reset HEAD --
```

**Step 8.3: Commit.** If there are uncommitted changes after steps 8.1–8.2, commit with message: `"Add pipeline artifacts for {task-slug}"`. If there are no uncommitted changes after steps 8.1–8.2, skip steps 8.3–8.4 (no-op).

**Step 8.4: Push.** Derive remote name from `git config --get branch.$(git branch --show-current).remote` for tracked branches. If unset (fresh branch), use the first remote from `git remote | head -1` with `--set-upstream`. If `git remote` returns nothing, abort with: **"No git remote configured. Push manually or add a remote."**

R-003 must not push to branches matching `main`, `master`, `develop`, or `release/*` — abort with an error if the current branch matches any of these.

If `git push` fails (auth failure, rejected push), `/cauto` aborts with a clear error message including the git error output. The local commit is preserved but the PR step is skipped. Re-running `/cauto` after fixing the push issue resumes at the PR step (the phase is `documented`, so the phase-to-step mapping routes to PR-only).

### Autonomous Decisions Summary (R-007, R-013)

After `/cdocs` completes and before PR creation, read `.correctless/artifacts/autonomous-decisions-{branch_slug}.jsonl` and present a summary to the human.

**Summary format**:
- Group decisions by skill
- Show each default that was applied with its rationale
- Normal autonomous decisions (escalation_deferred: false) are informational — not a gate
- Deferred escalations (escalation_deferred: true) are presented under a separate **"Deferred Escalations"** heading

**Deferred Escalation Confirmation Gate (R-013)**: If any deferred escalations exist, present them as a confirmation prompt before PR creation. List each deferred escalation with its default and original escalation reason, then: "{N} deferred escalations were made autonomously. Review above and confirm to proceed with PR creation, or request re-run of specific skills interactively." The human must confirm before the PR is created. Normal autonomous decisions (non-deferred) do not gate PR creation.

### Step 9: Create PR (R-008)

Create a PR according to the `pr_creation` preference from `preferences.md`:

- **`gh`** (default): Create a PR via `gh pr create`. The PR title is derived from the spec task name. The PR body must include:
  - **Summary** section: auto-generated from spec and implementation
  - **Test plan** section: derived from spec rules
  - **QA findings** summary: rounds completed, findings fixed
  - **Verification status**: pass/fail from `/cverify`
- **`skip`**: Skip PR creation, just report pipeline completion.
- **Custom command**: Execute the specified custom PR command via shell (TB-001b: custom PR commands follow the same trust model as TB-001a test runner commands — the file is local, under the project owner's control, and protected by the sensitive-file-guard).

Log a `preference_applied` audit event with the selected PR creation mode (e.g., "pr_creation: gh", "pr_creation: skip", or "pr_creation: custom").

Log `pipeline_completed` in the audit trail.

### Step 9.5: Preserve Override Log (R-001)

On any terminal state (pipeline completed, escalation, or failure), preserve the override log for cross-run pattern detection. Run:

```bash
source scripts/override-scrutiny.sh && preserve_override_log "$(git rev-parse --show-toplevel)" "{task-slug}" "$(git branch --show-current)"
```

This copies override entries for the current branch from `.correctless/artifacts/override-log.json` to `.correctless/meta/overrides/{task-slug}-{YYYYMMDD}.json` with a metadata wrapper. Zero-override runs are preserved (they are data, not absence of data). The 50-file cap (R-006) is enforced automatically by the function.

### Step 10: Pipeline Summary

After PR creation (or after the last pipeline step if `pr_creation: skip`), print a structured summary with three sections. Also include a **Pipeline Completeness** line showing `{completed_count}/{expected_count} steps completed`. If all expected steps completed AND `status` is `"complete"`, show "(all steps completed)". If steps are missing, show "(incomplete — {missing_steps})".

#### (a) Findings & Decisions

Every QA finding, review decision, override, and architectural decision from the pipeline, each with its disposition (fixed, deferred, accepted). Includes findings from the verification report. Deferred items are always shown with their reason.

Items from sources without a severity field (verification findings, override activity) are always shown inline — they are not subject to severity-based truncation.

**Data sources** (per R-006): The Findings & Decisions section reads from these sources:
- `.correctless/artifacts/qa-findings-{task-slug}.json` — QA findings and their dispositions
- `.correctless/verification/{task-slug}-verification.md` — verification findings (parse Rule Coverage and Smells sections)
- `.correctless/artifacts/review-decisions-{task-slug}.json` — review triage decisions (if Phase 3 review ran)
- `.correctless/artifacts/override-log-{branch-slug}.json` — override activity (if any overrides were issued)
- `.correctless/artifacts/audit-trail-{branch-slug}.jsonl` — escalation events, simplify reverts, and architectural decision events

If a source file doesn't exist, that source is omitted from the summary (not an error).

Note: QA findings and the verification report use `{task-slug}` (the feature name from workflow init). Override log, audit trail, and token log use `{branch-slug}` (derived from the branch name via `branch_slug()` in scripts/lib.sh). These are different values — task-slug is e.g. `scanner-expansion`, branch-slug is e.g. `feature-scanner-expansion-0c9277`.

**Truncation rule**: If the Findings & Decisions section has more than 20 items from severity-bearing sources, truncation applies:
1. All items with severity HIGH or CRITICAL are always shown inline
2. All items with explicit disposition `deferred` are always shown inline (the user needs to see what got punted regardless of severity)
3. All override activity is always shown inline
4. All items from non-severity sources (verification findings) are always shown inline

Items not matching any of these four criteria go into a count-and-reference summary, e.g.: "QA Findings: 47 total — 3 HIGH + 2 deferred shown below, see qa-findings-{task-slug}.json for full list"

#### (b) Phase Breakdown

A table with one row per pipeline step. Use **skill names** (ctdd, simplify, cverify, cupdate-arch, cdocs) as row identifiers, not workflow phase names (tdd-tests, tdd-impl, etc.). No phase-to-skill name mapping is needed — the table shows what was invoked, which is what humans care about.

Each row shows: step name, duration, token count, and result (pass/fail/skipped/reverted/incomplete).

**Duration**: last `skill_completed` elapsed_ms minus first `skill_started` elapsed_ms for that skill name (clock-independent, uses audit trail's authoritative time representation). For skills with multiple attempts (retries, QA rounds), the span covers all attempts. The orchestrator logs `skill_started`/`skill_completed` for all pipeline steps including `/simplify`, which does not log its own entries. Phases that never completed (pipeline aborted mid-run, detected by `skill_started` without matching `skill_completed`) appear with duration up to the abort point and result `(incomplete)`.

**Token count**: computed by summing `total_tokens` from `.correctless/artifacts/token-log-{branch-slug}.jsonl` entries where the `skill` field matches the row's skill name. If the token log doesn't exist or has no entries for a skill, the token column shows `—`.

#### (c) Artifacts

File paths for: spec, verification report, QA findings file, audit trail, and PR URL. Documentation and architecture changes get a one-line summary each (e.g., "README, AGENT_CONTEXT updated; PAT-014, PAT-015 added").

## Escalation (R-005)

When a failure persists after N attempts within a single skill, stop the pipeline and write a structured escalation summary to `.correctless/artifacts/escalation-{branch_slug}.md`.

### Attempt Thresholds by Intensity

The attempt threshold varies by effective intensity (matching /ctdd failure thresholds):

| Intensity | Threshold |
|-----------|-----------|
| standard  | 3         |
| high      | 2         |
| critical  | 2         |

### Escalation File Format

The escalation file uses YAML frontmatter for machine-parseable fields with human-readable prose below:

```yaml
---
completed_skills:
  - ctdd
  - simplify
failed_skill: cverify
failed_at_phase: verified
failed_at_substep: null
attempts_before_escalation: 2
pipeline_config:
  intensity: high
  preferences_snapshot:
    pr_creation: gh
    escalation_sensitivity: default
---

## Escalation Summary

[Human-readable explanation of what failed and why]

## Context

[Relevant error output, test failures, or architectural conflicts]
```

Required frontmatter fields: `completed_skills` (list), `failed_skill` (string), `failed_at_phase` (string), `failed_at_substep` (string, nullable — for inter-skill operations like post-simplify test run), `attempts_before_escalation` (integer), `pipeline_config` (object with intensity and preferences snapshot).

Log `escalation_triggered` in the audit trail and then `pipeline_failed`.

## Architectural Decision Escalation (R-006)

When the orchestrator detects a potential architectural decision during any skill execution, it must escalate to the human rather than making the decision autonomously. Detection heuristics:

1. **(a)** The skill determines that a new ABS-xxx or TB-xxx entry is needed in the architecture doc — any new trust boundary or abstraction is an architectural decision.
2. **(b)** The gate hook blocks a modification to `.correctless/ARCHITECTURE.md` outside the `cupdate-arch` phase — treat any gate-blocked architecture doc change as an architectural escalation.
3. **(c)** A spec rule cannot be satisfied without changing the spec — if the spec contradicts the implementation reality, the human must decide.
4. **(d)** A new dependency is required that is not already in the project — adding dependencies changes the project's supply chain.
5. **(e)** The skill modifies CLAUDE.md — changes to CLAUDE.md require human approval because they alter the system's own instructions.

Detection is best-effort for heuristics (a), (c), (d) — these are LLM judgment calls. The mechanical backstop is R-005: if an undetected architectural decision causes a skill to fail, the failure threshold catches it.

## Override Mechanism (R-007)

The shared constraint "Never auto-invoke the next skill" remains the default behavior for all skills. `/cauto` leaves `constraints.md` untouched and preserves the auto-invoke boundary as-is. Instead, `/cauto` is the orchestrator that invokes skills — each skill still tells its caller "what comes next" and stops. The orchestrator, not the skill, decides to proceed. Skills invoked outside of `/cauto` continue to respect the no-auto-invoke boundary.

## Audit Trail (R-011)

Log orchestration decisions to the audit trail at `.correctless/artifacts/audit-trail-{branch_slug}.jsonl`. Each orchestration entry must have:

- `type`: one of the 8 event types:
  - `skill_started` — before invoking a pipeline skill
  - `skill_completed` — after a skill finishes successfully
  - `preference_applied` — when a preference from preferences.md influences a decision
  - `escalation_triggered` — when escalation to human is initiated
  - `simplify_reverted` — when simplify changes are reverted (R-015)
  - `artifact_validation_failed` — when a skipped phase's artifact validation fails (R-002). Includes additional fields: `phase` (which phase failed validation), `expected_artifact` (what was checked), and `validation_error` (why it failed)
  - `pipeline_completed` — successful pipeline completion
  - `pipeline_failed` — pipeline stopped due to escalation or unrecoverable error
- `timestamp`: ISO 8601 format
- `skill`: skill name (e.g., `ctdd`, `cverify`) or `orchestrator` for pipeline-level events
- `elapsed_ms`: milliseconds since pipeline start

## Progress Updates (R-014) [advisory]

Emit progress updates between each skill invocation. Progress is observable via the audit trail entries which include `elapsed_ms` and skill transition data. Conversational progress updates to the user (e.g., "Starting /cverify...") are best-effort and not mechanically enforced. The audit trail provides the reliable progress record.

## Autonomous Defaults

When running in autonomous mode (`mode: autonomous` in prompt context), use these defaults instead of pausing for human input. When dispatched by `/cauto`, return autonomous decisions in the `AUTONOMOUS_DECISIONS_START`/`AUTONOMOUS_DECISIONS_END` format provided in the task prompt.

- **AD-001**: Pipeline order — follow R-001 standard order: /ctdd → /simplify → /cverify → /cupdate-arch → /cdocs (default). No human input required.
- **AD-002**: Preference loading — use built-in defaults when preferences.md is absent (default). Rationale: fail-open preserves pipeline flow.
- **AD-003**: Escalation sensitivity — escalate on any architectural decision per R-006 heuristics (default). Rationale: conservative default is safer.
- **AD-004**: Spec approval gate (INV-023) — `escalate: always`. Default if deferred: halt pipeline. Rationale: human spec approval is non-negotiable (PRH-001).
- **AD-005**: CLAUDE.md change detection (R-006(e)) — `escalate: always`. Default if deferred: halt pipeline. Rationale: CLAUDE.md changes alter system instructions.
- **AD-006**: Deferred escalation confirmation (R-013) — `escalate: always`. Default if deferred: halt pipeline. Rationale: deferred escalations may contain architectural decisions that need human review before PR creation.

---

## Phase 2: Tiered Decision Architecture

Phase 2 extends the pipeline with a policy-driven decision engine that resolves most runtime decisions without human intervention.

### Decision Tiers

Decisions are routed through a tiered hierarchy — no tier may be skipped:

- **Tier 0 (Policy)**: Deterministic evaluation against `auto-policy.json`. Same inputs always produce the same output. No LLM reasoning. Dual-pass: pre-routing and post-Tier-2 validation.
- **Tier 1 (Worker)**: Self-resolution for within-domain decisions. Logged as DD-xxx.
- **Tier 2 (Decision Agent)**: Ephemeral agent via `Task(subagent_type="correctless:decision-agent")` with minimal context per INV-006. Tools pinned to Read, Grep, Glob only.
- **Tier 3 (Supervisor)**: Lightweight supervisor via `Task(subagent_type="correctless:supervisor")`. Activates on escalation, phase transitions, and budget warnings.
- **Tier 4 (Hard Stop)**: Pipeline pauses for human input with structured escalation file.

### Supervisor Response Handling

The supervisor returns structured JSON with `decision`, `reasoning`, and `flags`. Valid terminal decisions: `approve`, `reject`, `hard_stop`. If the supervisor returns an unexpected or unrecognized decision value, treat it as `hard_stop` (default to hard_stop on unrecognized responses). If the supervisor returns `redirect`, treat it as `hard_stop` — redirect is not a valid terminal decision.

### Budget Enforcement (INV-008)

Token and time budgets are checked before and after each skill invocation:
- **warn** threshold: 75% of max_tokens or warn_at_hours exceeded
- **hard_stop** threshold: 100% of max_tokens or max_duration_hours exceeded (non-negotiable)
- Before spawning Tier 2: if remaining budget < 5%, escalate to Tier 3 instead

### Hard Stop + Resume (INV-010, INV-015)

When Tier 4 fires, write structured escalation to `.correctless/artifacts/escalation-{slug}.md` with:
- Phase where work stopped
- Specific condition that triggered hard stop
- Numbered options with recommendation
- Resume command: `/cauto resume "decision"`

All pipeline progress is preserved — no work is lost on hard stop.

**Priority ordering** for multiple simultaneous hard-stop conditions (highest priority first):
1. Integrity violations (decision record tamper, intent tampered, policy tampered)
2. Security (CLAUDE.md changes, PRH-001 security constraint)
3. Budget/time exceeded
4. Supervisor cap exceeded (>= 20 activations)
5. Other escalations (policy conflict, attempt threshold)

When multiple hard-stop conditions exist simultaneously, log all active conditions as a DD-xxx entry with tier "system" and category "hard_stop_multiplex."

### Resume from Hard Stop (INV-015)

On `/cauto resume "decision"`:
1. Re-hash intent summary and compare against stored hash — mismatch triggers hard stop (intent tampered)
2. Re-hash auto-policy.json and compare against stored hash — mismatch triggers hard stop (policy tampered)
3. Parse escalation file
4. Parse human decision — try numeric option first, fall back to text interpretation
5. Apply human decision to decision record as DD-xxx with tier "human"
6. Resume pipeline from exact phase where it paused

Stale escalation (phase mismatch) triggers a fresh start, not a crash.

### Intent Hash Verification (INV-013)

Before each supervisor activation, verify the intent hash against the stored value in workflow state. Intent mismatch triggers immediate hard stop with reason "intent summary tampered."

### Prohibitions

- **Never delete tests** autonomously (PRH-003). If a test deletion is needed, escalate to the human. Test removal requires human approval.
- **Never override the workflow gate** (PRH-004). The gate override mechanism is reserved for human-interactive use only. Never use override in auto mode.
- **Never merge to main** (PRH-002). Auto mode completes on a feature branch. The human reviews and merges.

---

## Phase 3: Spec-to-PR Orchestration and Supervisor Mandate Expansion

Phase 3 extends `/cauto` to handle the full workflow from prompt to PR, including spec creation and review.

### Phase Gate Extension — No-Workflow Invocation (INV-019)

When `/cauto` is invoked and no active workflow exists on the current branch (no existing workflow state), `/cauto` accepts the invocation and enters the spec phase. It initializes the workflow via `bash .correctless/hooks/workflow-advance.sh init` and proceeds to spec creation.

When invoked with an active workflow in `review` or `review-spec` phase, existing Phase 2 behavior is preserved unchanged (INV-027 backward compatibility).

**Branch guard (BND-005)**: Before initializing, check the current branch. If on main or master branch, refuse invocation with: **"Error: /cauto cannot run on main/master. Create a feature branch first."** The pipeline must not run on main or master.

### Two Entry Modes (INV-020)

When starting from no workflow, `/cauto` supports two entry modes:

1. **Interactive entry mode**: Invoke `/cspec` to run the Socratic brainstorm with the human, producing a spec interactively.
2. **Provided spec mode**: The human supplies a pre-written spec file path. `/cauto` validates the provided spec file exists and is non-empty (BND-003), then installs it as the workflow spec and skips `/cspec`.

In both modes, the spec must exist and be non-empty before review begins. If a provided spec file does not exist or is empty, abort with an error message including the path (BND-003).

### Autonomous Review with Supervisor Triage (INV-021, INV-032)

After the spec exists, invoke the review skill (`/creview-spec` at high+ intensity, `/creview` at standard). Review agents produce findings.

All review findings are passed to the supervisor agent for triage via `Task(subagent_type="correctless:supervisor")` with `activation_type: review_triage`. The supervisor evaluates each finding and returns `accept`, `reject`, or `hard_stop` per finding.

- **Accepted findings**: Auto-incorporated into the spec.
- **Rejected findings**: Logged to the review decisions artifact.
- **Hard-stopped findings**: Escalated to the human during the mandatory spec approval gate.

Review triage always goes through the supervisor agent — never inline triage logic (PRH-004). Supervisor responses must come from the supervisor agent's actual output — never from default values, pattern matching, or boilerplate auto-answers (PRH-005). If a supervisor response is malformed, treat all findings as hard-stopped (BND-004).

**Supervisor unavailable fallback (BND-002)**: If the supervisor invocation fails (Task returns error), fall back to treating all findings as hard-stopped — present all findings to the human during the spec approval gate.

### Mandatory Spec Approval Gate (INV-023, PRH-001)

After autonomous review completes and findings are incorporated, `/cauto` pauses and presents the spec to the human for approval. The mandatory spec approval gate is non-negotiable — the human must always approve before implementation begins.

Present to the human:
1. The final spec with all accepted findings incorporated
2. A summary of review decisions (N accepted, M rejected, K hard-stopped)
3. A link to the review decisions artifact

The human's options: **approve** (proceed to implementation), **reject** (abort pipeline), or **revise** (human edits spec, then re-approve).

When the human approves, record `spec_approved_by: "human"` and `spec_approved_at: <ISO timestamp>` in workflow state (INV-025). Providing a spec does not imply approval — explicit human confirmation is always required.
