# Spec: Pipeline Completeness Verification

## Metadata
- **Created**: 2026-05-08T22:00:00Z
- **Status**: draft
- **Impacts**: semi-auto-mode, autonomous-skill-contract, cstatus
- **Branch**: feature/pipeline-completeness-verification
- **Research**: null
- **Recommended-intensity**: high
- **Intensity**: high
- **Intensity reason**: no detection signals triggered (standard), but project floor is high (workflow.intensity = high) — floor raises to high
- **Override**: none

## What

`/cauto` pipeline silently truncates when the execution context exhausts mid-pipeline (PMB-009). The pipeline ran 2 of 7 steps, the Skill tool reported "completed," and no artifact indicated truncation. This feature adds two layers of completeness verification: (1) a pipeline manifest artifact that tracks expected vs. completed steps, and (2) a post-return auto-resume convention so the main conversation re-invokes `/cauto` when truncation is detected.

## Rules

- **R-001** [unit]: `/cauto` SKILL.md must instruct the orchestrator to write a pipeline manifest as the FIRST action after the phase gate (before any skill invocation). The manifest path is `.correctless/artifacts/pipeline-manifest-{branch_slug}.json` (uses `branch_slug` convention — matching audit-trail, escalation, and override-log artifacts per AP-009). The manifest must contain: `expected_steps` (array of canonical step names from R-010), `expected_end_phase` (the workflow phase that indicates pipeline completion — `documented` for full runs, or the appropriate phase for partial runs), `completed_steps` (array, initially empty), `started_at` (ISO 8601 timestamp), and `branch` (current branch name).

- **R-002** [unit]: `/cauto` SKILL.md must instruct the orchestrator to append the current step name to `completed_steps` in the manifest after each pipeline step completes successfully. The append must happen AFTER the step completes but BEFORE the next step begins. Enforcement: prompt-level — SKILL.md instruction ordering. No structural mechanism exists to verify runtime ordering of manifest updates.

- **R-003** [unit]: `/cauto` SKILL.md must instruct the orchestrator to write `"status": "complete"` to the manifest as its FINAL action — after Step 10 (pipeline summary). A manifest without `"status": "complete"` indicates truncation.

- **R-004** [unit]: `/cauto` SKILL.md must instruct the orchestrator, during the resumption check (R-016 in semi-auto-mode), to read any existing pipeline manifest and report which steps were missed if the manifest exists but `status` is not `"complete"`. The report format: "Pipeline was truncated at step {last_completed}. Missing steps: {list}. Resuming from {next_step}." The workflow state (via `workflow-advance.sh`) is authoritative. The manifest is advisory — when the two conflict, the workflow state wins. R-004 reports the divergence as a diagnostic signal, not as an override of workflow state.

- **R-005** [unit]: `/cauto` SKILL.md Step 10 (pipeline summary) must include a `Pipeline Completeness` line showing `{completed_count}/{expected_count} steps completed`. If all expected steps completed AND `status` is `"complete"`, show "(all steps completed)". If steps are missing, show "(incomplete — {missing_steps})".

- **R-006** [unit]: The pipeline manifest must be an ephemeral artifact — it is NOT committed during consolidation (Step 8). The manifest lives under `.correctless/artifacts/` which is already excluded from consolidation staging by Step 8.2's belt-and-suspenders guard.

- **R-007** [unit]: `/cauto` SKILL.md description (the frontmatter `description:` field) must include the sentence: "After /cauto completes, verify the workflow reached the expected end state — if it didn't, re-invoke /cauto to resume." This is the post-return auto-resume convention — the main conversation reads the skill description and knows to check. Test: grep the description field for the sentence. The behavioral contract (main conversation reads and acts on it) is prompt-level and untestable — acknowledged as a limitation.

- **R-008** [unit]: The manifest must handle the intensity-aware pipeline correctly. At standard intensity, `cupdate-arch` is skipped — `expected_steps` must reflect the actual pipeline for the current intensity, not the full pipeline. The step list is derived from the canonical step name enum (R-010) filtered by the current intensity.

- **R-009** [unit]: `/cstatus` SKILL.md must instruct the agent to check for a pipeline manifest at `.correctless/artifacts/pipeline-manifest-{branch_slug}.json` (deriving `branch_slug` via `workflow-advance.sh status` or `scripts/lib.sh`). If the manifest exists and `status` is not `"complete"`, report: "**Incomplete pipeline detected.** Last completed step: {last_completed}. Missing steps: {list}. Expected end phase: {expected_end_phase}, current phase: {current_phase}. Run `/cauto` to resume." If the manifest does not exist or `status` is `"complete"`, no output (dormant — PAT-019). The workflow state is authoritative — the manifest report is a diagnostic signal, not an override.

- **R-010** [unit]: The spec defines a canonical step name enum for pipeline steps. At high+ intensity: `["ctdd", "simplify", "cverify", "cupdate-arch", "cdocs", "consolidation", "pr"]`. At standard intensity: `["ctdd", "simplify", "cverify", "cdocs", "consolidation", "pr"]`. These names correspond to the pipeline steps in `/cauto` SKILL.md Steps 1-9. Internal orchestration actions (pre-simplify commit, post-simplify validation, override-log preservation, pipeline summary) are excluded — they are not pipeline steps. The enum is the single source of truth for `expected_steps` and `completed_steps` values.

- **R-011** [unit]: An ABS-031 entry must be added to `.correctless/ARCHITECTURE.md` documenting the pipeline manifest artifact contract. Fields: artifact path (`.correctless/artifacts/pipeline-manifest-{branch_slug}.json`), sole writer (`/cauto`), consumers (`/cauto` R-004 resumption, `/cstatus` R-009), invariant (manifest is ephemeral — not committed during consolidation, covered by Step 8.2 unstage guard), enforcement (dormant when absent per PAT-019).

## Won't Do

- **Structural enforcement of post-return check**: The post-return auto-resume relies on the main conversation reading the skill description and acting on it. This is prompt-level, not structural. A structural mechanism (e.g., a hook that fires after Skill tool completion) doesn't exist in Claude Code's plugin model. The manifest artifact is the structural part; the re-invocation convention is prompt-level.
- **Context budget management**: We can't control the Skill tool's fork context budget. Prevention (making `/cauto` fit within the budget) is out of scope — this feature is about detection and recovery.
- **Persistent pipeline progress across sessions**: The manifest is ephemeral and branch-scoped. If the workflow state is reset, the manifest becomes stale. No cross-session persistence mechanism.

## Risks

- **Manifest write fails silently**: If the manifest write fails (disk full, permissions), the truncation detection degrades to the current state (no detection). Mitigation: the manifest is a simple JSON write under `.correctless/artifacts/` which already exists for other artifacts. Accepted — the risk is low and the degradation is graceful.

- **Main conversation doesn't read the skill description**: The post-return auto-resume relies on the main conversation noticing the description. If it doesn't, the user discovers truncation via `/cstatus` (R-009) or by re-running `/cauto` (R-004). Accepted — three detection paths (description, `/cstatus`, re-invocation) provide sufficient coverage.

- **Step naming drift**: If step names change in the phase-to-step mapping, the manifest's `expected_steps` and `completed_steps` could use inconsistent names. Mitigated by R-010's canonical step name enum — single source of truth.

## Open Questions

None — OQ-001 resolved (added as R-009).

## Review Findings Applied

- **F-001** (MEDIUM): Added ABS-031 entry as R-011. Accepted.
- **F-002** (MEDIUM): Added canonical step name enum as R-010. Accepted.
- **F-003** (LOW): Removed "not via Write or Edit" instruction from R-002 — SFG doesn't protect `.correctless/artifacts/`. Accepted.
- **F-004** (LOW): Added untestability acknowledgment to R-007. Accepted.
- **F-005** (LOW): Added prompt-level enforcement note to R-002. Accepted.
- **F-006** (LOW): Added "workflow state is authoritative" notes to R-004 and R-009. Accepted.
