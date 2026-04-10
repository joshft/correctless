---
name: cauto
description: Semi-auto mode. Orchestrates the full implementation pipeline after human-approved spec review. Runs ctdd, simplify, cverify, cupdate-arch, cdocs, then creates a PR.
allowed-tools: Read, Grep, Glob, Bash(*), Write(.correctless/artifacts/*), Edit
context: fork
---

# /cauto — Semi-Auto Implementation Pipeline

> **Shared constraints apply.** Before executing, read `_shared/constraints.md` from the parent of this skill's base directory. All constraints there apply to this skill.

You are the pipeline orchestrator. You invoke skills in sequence, monitor for failures, and escalate to the human when autonomous resolution is not possible. You do not write tests or production code yourself — each skill handles its own domain. You are the orchestrator that invokes skills; skills do not auto-continue on their own.

## Phase Gate (R-002)

Before doing anything, read the current workflow state by running `bash .correctless/hooks/workflow-advance.sh status` and check the current phase.

`/cauto` is only invocable when the workflow phase is `review` (standard intensity) or `review-spec` (high+ intensity). If the current phase is not one of these, produce an error: **"Error: /cauto requires the workflow phase to be `review` or `review-spec`. Current phase is `{phase}`. Complete the current phase before invoking /cauto."** and abort. The phase must be `review` or `review-spec` — any other phase (including `spec` and all implementation/post-implementation phases) is not valid and must be refused.

## Effective Intensity

Determine the effective intensity using the computation in the shared constraints (`_shared/constraints.md`). The effective intensity controls pipeline behavior including attempt thresholds and skill activation.

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

## Resumption Check (R-016)

On invocation, check for an existing escalation file at `.correctless/artifacts/escalation-{branch_slug}.md`. If present:

1. Parse the YAML frontmatter to extract `completed_skills`, `failed_skill`, `failed_at_phase`, and other fields.
2. Check phase consistency: verify `failed_at_phase` matches the current workflow phase.
3. Verify completed skill artifacts still exist (tests pass, verification report present if applicable).
4. If both checks pass, resume from the failed skill — skip completed skills in the pipeline.
5. If either check fails (phase inconsistent or artifacts missing), delete the stale escalation file and start fresh with a clean pipeline run.

## Pipeline Order (R-001)

The pipeline invokes skills in this exact order: `/ctdd` -> `/simplify` -> `/cverify` -> `/cupdate-arch` -> `/cdocs`.

Each skill runs in a fresh context (`context: fork`) — the orchestrator spawns a sub-agent for each skill. Each skill must complete successfully before the next begins.

### Intensity-Aware Pipeline (R-009)

The effective intensity computation from shared constraints determines which skills are active:

- At **standard** intensity: skip `/cupdate-arch` (it has its own intensity gate requiring high+ intensity). The pipeline becomes: `/ctdd` -> `/simplify` -> `/cverify` -> `/cdocs` -> PR.
- At **high** or **critical** intensity: run the full pipeline including `/cupdate-arch`.

`cupdate-arch` has an independent intensity gate in its own SKILL.md — it will refuse to run at standard intensity regardless of whether `/cauto` invokes it.

When `/cupdate-arch` is skipped due to standard intensity, log a `preference_applied` audit event with the reason "cupdate-arch skipped: standard intensity".

### Workflow State Machine Transitions (R-010)

The orchestrator advances the workflow state machine through all required transitions using `workflow-advance.sh`. It must not skip transitions or write to the state file directly — always use `workflow-advance.sh` commands.

The full transition sequence for a clean run uses these actual phase names in order:

1. `tdd-tests` — RED phase: write failing tests from spec rules
2. `tdd-impl` — GREEN phase: implement to make tests pass
3. `tdd-qa` — QA phase: independent review of implementation
4. (loop: `tdd-impl` -> `tdd-qa` if QA finds issues, via the `fix` command which transitions back to `tdd-impl`)
5. `done` — TDD complete, ready for simplification and verification
6. `verified` — Post-implementation verification passed
7. `documented` — Documentation updated, pipeline complete

At high+ intensity, the optional `tdd-verify` phase may occur between `tdd-qa` and `done` (handled internally by `/ctdd`).

These transitions are managed by `/ctdd` internally for phases 1-5, and by `/cverify` and `/cdocs` for phases 6-7. The orchestrator monitors the phase after each skill completes.

## Pipeline Execution

### Step 1: Invoke `/ctdd`

Spawn a sub-agent to execute `/ctdd`. This skill manages the RED -> GREEN -> QA cycle internally and advances the workflow through `tdd-tests`, `tdd-impl`, `tdd-qa`, and `done` phases.

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

### Step 7: Invoke `/cdocs`

Spawn a sub-agent to execute `/cdocs`. Log `skill_started` before, `skill_completed` after.

After `/cdocs` completes, run `git diff --name-only HEAD` and check if CLAUDE.md appears in the changed files. If it does, trigger R-006(e) escalation — CLAUDE.md changes require human approval. Write the escalation file and halt the pipeline; do not proceed to PR creation until the human approves the CLAUDE.md changes.

### Step 8: Create PR (R-008)

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

- `type`: one of the 7 event types:
  - `skill_started` — before invoking a pipeline skill
  - `skill_completed` — after a skill finishes successfully
  - `preference_applied` — when a preference from preferences.md influences a decision
  - `escalation_triggered` — when escalation to human is initiated
  - `simplify_reverted` — when simplify changes are reverted (R-015)
  - `pipeline_completed` — successful pipeline completion
  - `pipeline_failed` — pipeline stopped due to escalation or unrecoverable error
- `timestamp`: ISO 8601 format
- `skill`: skill name (e.g., `ctdd`, `cverify`) or `orchestrator` for pipeline-level events
- `elapsed_ms`: milliseconds since pipeline start

## Progress Updates (R-014) [advisory]

Emit progress updates between each skill invocation. Progress is observable via the audit trail entries which include `elapsed_ms` and skill transition data. Conversational progress updates to the user (e.g., "Starting /cverify...") are best-effort and not mechanically enforced. The audit trail provides the reliable progress record.
