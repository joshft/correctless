# Verification: carchitect Phase 4 — Mechanical Architecture Checks in PR Review

**Verified**: 2026-05-07
**Spec**: `.correctless/specs/carchitect-phase-4-review.md`
**Branch**: feature/carchitect-phase-4-review

## Rule Coverage

| Rule | Status | Evidence |
|------|--------|----------|
| R-001 | COVERED | `skills/cpr-review/SKILL.md:145-151` — Step 3 spawns agent, runs parallel with Steps 4-8, collects before presenting. No intensity gate. Tests: R-001a through R-001d in `test-carchitect-phase4.sh`. |
| R-002 | COVERED | `agents/architecture-compliance-reviewer.md:1-6` — frontmatter has `name: architecture-compliance-reviewer`, `tools: Read, Grep, Glob`, `model: inherit`. SKILL.md:4 has `Task(correctless:architecture-compliance-reviewer)` in allowed-tools. Tests: R-002a through R-002e. |
| R-003 | COVERED | Agent prompt lines 20-34 — PAT-xxx extraction with See-link follow, ABS-xxx invariant checking (sole-writer, contract, violated-when), TB-xxx boundary checking. Diff-scoped: "findings must reference diff files only" (line 32). Trust model: "workflow-gate phase restrictions" (line 16), NOT sensitive-file-guard/TB-005. Tests: R-003a through R-003i. |
| R-004 | COVERED | Agent prompt lines 36-41 — sub-entry pattern `TB-\d{3}[a-z]`, example distinguishing TB-001a from TB-010, "do not submit — it is a known exception, not a violation." Tests: R-004a through R-004c. |
| R-005 | COVERED | Agent prompt lines 42-44 — dormant-signal fallback with PAT-019 reference, placeholder markers, zero findings, "do not attempt to infer architecture." Tests: R-005a through R-005d. |
| R-006 | COVERED | `skills/cpr-review/SKILL.md:147` — staleness computed in parent via `git log -1 --format='%ai'`, 30-day threshold, LOW severity, suggests /cupdate-arch. Agent prompt contains NO git log commands. Tests: R-006a through R-006e. |
| R-007 | COVERED | Agent prompt lines 46-57 — four check types (pattern compliance, abstraction invariant, trust boundary enforcement, new pattern introduction). Calibration for new-pattern detection: "project-specific convention...not standard language idioms." Tests: R-007a through R-007e. |
| R-008 | COVERED | Agent prompt lines 59-74 — finding format: severity, architecture_ref (null for new-pattern), file path, one-sentence description, why-it-matters, suggested fix. Default severities: TB-xxx ≥ HIGH, PAT/ABS MEDIUM, new-pattern LOW. Tests: R-008a through R-008g. |
| R-009 | COVERED | SKILL.md Step 3 replaced: old 5-bullet prose removed, replaced with agent spawn + staleness. `Task(correctless:architecture-compliance-reviewer)` in allowed-tools (line 4). Progress Visibility item 4: "Spawn Architecture Compliance Agent" (line 23). Present Findings merges agent output (line 151). Tests: R-009a through R-009d. |
| R-010 | COVERED | SKILL.md lines 250, 262 — complementarity notes in both Trust Boundary Analysis and Drift Detection sections: "The Architecture Compliance Agent handles mechanical TB-xxx/PAT-xxx checking. This section adds semantic analysis beyond what mechanical extraction can catch." Tests: R-010a through R-010c. |
| R-011 | COVERED | SKILL.md line 134 — dep bump lens replaces Steps 3-8: "don't run architecture compliance, security checklist, etc." No special agent handling needed. Tests: R-011a, R-011b. |
| R-012 | COVERED | `correctless/agents/architecture-compliance-reviewer.md` exists and is byte-equal to `agents/architecture-compliance-reviewer.md` (verified via `diff`). Tests: R-012a through R-012d. |
| R-013 | COVERED | `docs/skills/cpr-review.md:62-72` — describes four check types, dormant-signal fallback, staleness warning. Tests: R-013a through R-013d. |
| R-014 | COVERED | `.correctless/ARCHITECTURE.md` ABS-010 entry updated: consumer list includes `skills/cpr-review/SKILL.md`, invariant includes `architecture-compliance-reviewer` in read-only roles, enforced-at includes `tests/test-carchitect-phase4.sh`. Tests: R-014a through R-014c. |
| R-015 | COVERED | `tests/test-carchitect-phase4.sh` — 617 lines, 66 assertions covering all 6 categories (frontmatter, distribution parity, prompt content, no inline prose, allowed-tools, staleness in parent). Registered in `workflow-config.json` commands.test and `.github/workflows/ci.yml`. Tests: R-015a, R-015b. |

## Summary

15/15 rules covered. All tests pass (66/66 phase 4 assertions, 107/0 architecture drift assertions). No gaps found.
