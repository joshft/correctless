# Spec: UX Review Lens

## Metadata
- **Created**: 2026-05-09T14:00:00Z
- **Status**: draft
- **Impacts**: creview-spec, creview, ctdd, caudit
- **Branch**: feature/ux-review-lens
- **Research**: null
- **Recommended-intensity**: high
- **Intensity**: high
- **Intensity reason**: no detection signals triggered (standard), but project floor is high (workflow.intensity = high) — floor raises to high
- **Override**: none

## What

Add a UX review lens to `/creview-spec`, `/creview`, `/ctdd` mini-audit, and `/caudit`. The UX lens checks for silent failures, missing feedback, lost output, broken interaction patterns, recovery paths, and progress visibility — the class of bugs that QA, Hacker, and Performance lenses don't catch. At least 4 of 9 post-merge bugs (PMB-004, PMB-006, PMB-008, PMB-009) are fundamentally UX failures that no existing lens would have caught. The lens uses four sub-lenses for different user journey stages: new user, upgrade/update, offboarding, and recovery/error. `/caudit` adds a fifth sub-lens: cross-session continuity.

## Rules

- **R-001** [unit]: The spec defines a canonical sub-lens enum for UX review. Base sub-lenses (all 4 integration points): `["new-user", "upgrade", "offboarding", "recovery"]`. Extended sub-lenses (`/caudit` UX preset only): `["new-user", "upgrade", "offboarding", "recovery", "cross-session"]`. Sub-lenses are role assignments within the UX agent — they describe focus areas for the UX reviewer, NOT values in the `/ctdd` mini-audit LENS enum (`cross-component|hostile-input|resource-bounds|upgrade-compatibility`). The LENS enum is a separate concept used for finding categorization. Each sub-lens maps to a specific set of check items defined in R-006 and R-007.

- **R-002** [unit]: `/creview-spec` SKILL.md must include a UX Auditor in its agent list, spawned at high+ intensity alongside the existing agents (Red Team, Assumptions Auditor, Testability Auditor, Design Contract Checker, Upgrade Compatibility Auditor). The UX Auditor evaluates the spec through all 4 base sub-lenses. Cascading updates required: the frontmatter `description` field must list the UX Auditor, the progress visibility announcement must reflect the updated agent count, and the task list must include a UX Auditor entry.

- **R-003** [unit]: `/creview` SKILL.md must spawn a UX review subagent. The UX reviewer evaluates the spec through all 4 base sub-lenses. This is the first spawned subagent in `/creview` — the rest of the review remains single-pass. The UX agent runs in parallel with the single-pass review (the UX lens checks different concerns — silent failures, missing feedback, recovery paths — that don't depend on code-level review findings). Cascading updates required: the frontmatter `description` must mention the UX subagent, the progress visibility task list must include a UX agent entry, and the intensity table must reflect the subagent addition. Prerequisite: confirm `/creview`'s `allowed-tools` frontmatter supports subagent spawning — if not, the spec must add the required tool permission.

- **R-004** [unit]: `/ctdd` SKILL.md must include a UX lens agent in the mini-audit section as a 5th agent alongside cross-component interaction, hostile input, resource bounds, and upgrade compatibility. The UX agent evaluates the implementation through all 4 base sub-lenses. Spawned in parallel with the other 4 mini-audit agents. Cascading updates required: the progress announcement text must reflect "5 specialist agents" (currently "4"), the LENS enum in the finding format section must add `ux-review`, the `agent_role` value for token tracking must include the UX agent, and any existing tests checking the LENS enum cardinality (e.g., test-upgrade-compatibility-lens.sh R-003b) must be updated.

- **R-005** [unit]: `/caudit` SKILL.md must define a UX preset with the following agent role table:

  | Role | Lens | What it looks for |
  |------|------|-------------------|
  | First Contact Auditor | "Every new user quits before value" | Zero-state behavior, missing setup guidance, error messages without recovery, undiscoverable features |
  | Upgrade Path Auditor | "Every update breaks something silently" | Silent behavioral changes, missing migration guidance, config schema breaks, artifact format drift |
  | Cleanup/Offboarding Auditor | "Every removal leaves ghosts" | Residual state, orphaned artifacts, graceful degradation when components removed |
  | Error Recovery Auditor | "Every interruption loses work" | Missing resumption paths, lost findings, state inconsistency after failure, missing progress persistence |
  | Cross-Session Continuity Auditor | "Every fresh session forgets everything" | Conversation context dependency, session-boundary state corruption, artifact path hallucination, stale workflow state |

  The UX preset follows the existing preset table format and uses the same agent prompt template, triage agent, and convergence loop as QA/Hacker/Performance presets.

- **R-006** [unit]: Every UX agent prompt (at all 4 integration points) must include a sub-lens checklist with specific check items. Required check items per sub-lens:
  - **new-user**: path discovery without prior context, zero-state behavior (no config, no artifacts, no history), error messages on first run, documentation pointers when features are unavailable
  - **upgrade**: behavioral changes between versions, silent breakage on update, migration path clarity, backward compatibility of artifacts and config
  - **offboarding**: cleanup of generated artifacts, residual state after feature removal, graceful degradation when components are removed
  - **recovery**: error messages on failure, resumption paths after interruption, state consistency after failure, output persistence (no lost findings/results)

- **R-007** [unit]: `/caudit` UX preset agent prompts must include a cross-session continuity sub-lens in addition to the 4 base sub-lenses. Cross-session check items: workflow state persistence across sessions, conversation context dependency (features that only work when prior context exists), fresh-session artifact path resolution, session-boundary state transitions. Acknowledged limitation: cross-session continuity is a semantic property verifiable only through multi-session scenarios. No structural test can verify an agent prompt will actually evaluate these — inherent to the LLM-agent model, shared with all other agent prompt specs.

- **R-008** [unit]: All 4 integration points must include a fail-open instruction for the UX agent. If the UX agent fails to spawn, returns an error, times out, or returns malformed/incomplete output, the skill proceeds without UX findings and notes the absence in its output. The UX lens is advisory — it never gates progression to the next phase. Enforcement: prompt-level — no structural gate exists for advisory agent output. This is a conscious PAT-018 exception: fail-open advisory behavior has no gate to enforce structurally. The fail-open posture matches all other review/audit lenses.

- **R-009** [unit]: Each UX agent prompt must include at least 3 of the 4 PMB UX failures (PMB-004 path hallucination, PMB-006 fork stalling, PMB-008 lost findings, PMB-009 silent truncation) as calibration examples — concrete instances of what the UX lens should catch. These serve as the "what BLOCKING looks like" boundary definition per AP-028 (uncalibrated severity gate).

- **R-010** [unit]: UX agent findings must use the parent skill's structured output format. Explicit format per integration point: In `/creview-spec`: finding ID (UX-xxx) + category + description, matching the adversarial agent pattern (each agent returns findings as structured text with ID prefix, category, and description). In `/ctdd` mini-audit: `MA-xxx` ID format with severity/description/instance_fix/class_fix fields, using `ux-review` as the LENS value. In `/caudit`: confidence-tiered format (confirmed/probable/suspicious) with the standard bounty structure. In `/creview`: finding ID (UX-xxx) + severity + description, structured as a numbered finding list consistent with the single-pass review's output format.

## Won't Do

- **Agent file in `agents/*.md`**: The UX agent uses the inline role description pattern matching the existing review/audit agents (Red Team, Assumptions Auditor, etc.). Only agents needing structural guarantees (parse gates, tool pinning for output contract enforcement) justify extraction per ABS-010. The UX agent's output contract is the same as its sibling agents — no special enforcement needed.
- **Structural enforcement of UX checks**: UX findings are advisory. No gate prevents progression when UX issues are found. This matches the posture of all other review/audit lenses.
- **UX preset as default in `/caudit`**: The UX preset is opt-in (user selects "UX" when running `/caudit`), not added to the default QA/Hacker rotation. Users choose which preset to run.
- **Modifying existing agent behavior**: This feature adds new agents alongside existing ones. No existing agent prompt, output format, or spawning logic is changed.

## Risks

- **Token cost increase**: One additional agent per `/creview-spec` run (~5-10K tokens), one subagent per `/creview` run (~5-10K), one per mini-audit round in `/ctdd` (~5-10K), and N agents per `/caudit` UX preset round. Mitigated: the per-review cost is marginal compared to the cost of PMB-class bugs escaping. Accepted.

- **Overlap with upgrade compatibility agent**: The "upgrade" sub-lens overlaps with the existing Upgrade Compatibility Auditor in `/creview-spec` and `/ctdd` mini-audit. Mitigated: the upgrade compatibility agent checks structural concerns (setup scripts, config keys, schema changes, removed files). The UX "upgrade" sub-lens checks experiential concerns (silent breakage, migration path clarity, behavioral changes a user would notice). Different angles on the same journey. Accepted.

- **Prompt-level enforcement only**: All rules are tested via keyword-presence in SKILL.md files (AP-003 class). The UX agent's behavior depends on the orchestrator following prompt instructions. This is the same limitation as every other review/audit agent — accepted as inherent to skill-modification specs.

## Open Questions

None.

## Review Findings Applied

- **F-001** (MEDIUM): Added concrete role table to R-005. Accepted.
- **F-002** (LOW): Added cascading update requirements to R-004 (agent count, LENS enum, token tracking, test updates). Accepted.
- **F-003** (MEDIUM): Added cascading update requirements to R-003 (frontmatter, progress visibility, intensity table, allowed-tools confirmation). Accepted.
- **F-004** (LOW): Added cascading update requirements to R-002 (description, progress announcement, task list). Accepted.
- **F-005** (LOW): Simplified R-002 to "spawned at high+ intensity" — removed vacuous standard-intensity comparison. Accepted.
- **F-006** (MEDIUM): Added clarification to R-001 that sub-lenses are role assignments, not LENS enum values. Accepted.
- **F-007** (LOW): Added PAT-018 exception acknowledgment to R-008. Accepted.
- **F-008** (LOW): Rejected. PMBs ARE UX failures regardless of root cause — the user-facing symptom was broken experience with no recovery path. Reframing weakens calibration.
- **F-009** (LOW): Added allowed-tools prerequisite check to R-003. Accepted.
- **F-010** (MEDIUM): Specified explicit output format per integration point in R-010. Accepted.
- **F-011** (LOW): Added "malformed or incomplete output" to R-008 fail-open list. Accepted.
- **F-012** (LOW): Rejected. AP-003 class limitation acknowledged in Risks. More distinctive anchors provide marginal improvement without changing the fundamental limitation.
- **F-013** (LOW): Added inherent limitation acknowledgment to R-007. Accepted.
