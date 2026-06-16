# Verification: Fix-diff reviewer class-shaped bug lens

**Verified-by**: /cverify (autonomous mode)
**Date**: 2026-06-15
**Spec**: .correctless/specs/fix-diff-reviewer-class.md
**Branch**: feature/fix-diff-reviewer-class-shaped-bugs
**Intensity**: high
**Workflow phase at verification time**: `done` (advanced via override — /cverify had NOT been run in the pipeline; see Findings)

## Rule Coverage

All 21 CS-NNN invariants (CS-001..CS-021; CS-008 inherited from migration infra) are enforced by `check_class_shaped_bug_detection` in `tests/test-fix-diff-reviewer-agent.sh`, plus the CS-007 cardinality checklist (`EXPECTED_SUB_ASSERTION_IDS`, 20 IDs, membership equality). Full suite: **188 pass / 0 fail / 1 skip**.

| Rule | Test (sub-assertion) | Status | Notes |
|------|----------------------|--------|-------|
| CS-001 | CS-001 (heading before Output contract) | covered | lens section at L89-268, before L269 Output contract |
| CS-002 | CS-002 (two-signal, two seed lists, non-exhaustive) | covered | code-pattern + keyword seeds kept distinct (RS-016) |
| CS-003 | CS-003 (sibling-grep imperative, anti-negation/hedge) | covered | positive imperative, names ≥2 of Read/Grep/Glob |
| CS-004 | CS-004 (SIBLING-DEFERRED regex, comment styles) | covered | optional `:line`, ≥6 comment styles, excludes `"""` |
| CS-005 | CS-005 (HIGH+LOW worked examples, aggressive default) | covered | calibration contrast present |
| CS-006 | CS-006 (PMB-019/#144/#124 citation, word-boundary) | covered | narrative-context anchored |
| CS-007 | CS-007 + CS-007(cardinality) | covered | membership equality on 20-ID set |
| CS-008 | existing INV-008 / distribution-parity | covered | agent mirror byte-equal (verified by diff -q) |
| CS-009 | CS-009 (LENS_REQUIRED_PHRASES literal + data-treatment) | covered | 3 literal phrases via grep -qF; `<UNTRUSTED_*>` wildcard form |
| CS-010 | CS-010 (scope EXCEPT clause within 5 lines) | covered | exception at L66, proximity-anchored |
| CS-011 | CS-011 (Step 6a fence, flat path, JSON-array, degrade) | covered | production producer = build-caudit-prompt.sh |
| CS-012 | CS-012 (SFG final-state + SKIP sentinel) | covered | DEFAULTS restored both hooks; sentinel in DEFAULTS |
| CS-012a | CS-018(behavioral) | covered | run-the-script present/absent/deactivated |
| CS-013 | CS-013 (a-h) prompt-composition fixtures | covered | 3 fixtures + PR#124 byte-match provenance |
| CS-014 | CS-014 (4096/16384 caps, emitted-bytes, byte primitive) | covered | escape-byte + multibyte fixtures pass |
| CS-015 | CS-015 (closed allow-list + deny-list + PAT-018) | covered | `.env`/autonomous-decisions/`.git/objects`/preferences |
| CS-016 | CS-016 (diff-fence-only, PR-base provenance, MEDIUM) | covered | + nonce-bearing fence hardening (MA-H3, beyond spec) |
| CS-017 | CS-017 (class_fix verbatim marker example) | covered | annotated example marker present |
| CS-018 | CS-018(a-d) + behavioral | covered | CI job + needs-edge + /cauto Step 8 + cmd_done gate |
| CS-019 | CS-019 (done-gate HEAD-SHA sentinel, reachable refusal) | covered | reader+writer+refusal behaviorally proven |
| CS-020 | CS-020 (downstream rule-file + cmd_done gate floor) | covered | sync→correctless/rules, setup→.correctless/rules |
| CS-021 | CS-021 (ABS-041 + drift coverage) | covered | ABS-041 at ARCHITECTURE.md:385, all 5 fields |

**Prohibitions**: PRH-001 (no new tools) covered by `check_tools_set_equality`; PRH-002/003 (seed lists non-exhaustive) covered by CS-002; PRH-004 (FD-NNN output contract) inherited. No uncovered rules. No BLOCKING coverage gaps.

## Dependencies

No package manifest changes (`package.json`/`go.mod`/`Cargo.toml`/`requirements.txt`/`pyproject.toml` — none touched). Feature is shell + markdown only. **No new third-party dependencies.**

## Architecture Adherence

- ABS-041: valid — `### ABS-041: SFG lift-and-restore sentinel + final-state backstop` present at ARCHITECTURE.md:385 with What/Invariant/Enforced-at/Violated-when/Test fields; covered by `tests/test-architecture-drift.sh` (110/0 pass).
- ABS-010: valid — agent file + mirror byte-equal; SFG hook mirror differs only by `# Rule: ` comment-strip (intentional sync.sh transformation per INV-021, not a violation).
- AP-037 / SFG-write surface: valid — `agents/fix-diff-reviewer.md` restored to DEFAULTS in both `hooks/` and `correctless/hooks/`; sentinel `.correctless/.sfg-lift-active` absent from tree (lift fully reversed) AND added to DEFAULTS.

3 affected entries checked, 0 stale, 0 path-missing.

### Drift Debt
- No open items in `.correctless/meta/drift-debt.json`. No new drift detected.
- Deferred findings DF-027 (lens kill-switch) and DF-028 (UNTRUSTED_* fence catalog ABS) properly recorded per spec OQ-001/OQ-008/OQ-009 deferrals.

## QA Class Fixes Verified

QA converged at round 3 (R1: 2 BLOCKING fixed, R2: 2 BLOCKING fixed, R3 clean) + mini-audit 2 rounds. All class fixes have backing structural tests:
- QA-001/QA2-001 (done-gate refusal reachable) → CS-019 reader+writer+refusal behavioral assertion present.
- QA2-002 (fence producer real, not prose) → CS-011 production-producer (`build-caudit-prompt.sh`) asserted.
- MA-H1 (220KB desc / ≥2MB corpus, no ARG_MAX) → CS-013(f-scale) present.
- MA-H3 (fence injection / nonce neutralization) → CS-013(h-fence-injection) present.

## Antipattern Scan

Ran `scripts/antipattern-scan.sh main` (the `.correctless/scripts/` copy is stale — April build — and exits non-zero; the canonical `scripts/` copy is current). Feature-touched scripts only:

| Severity | Pattern | File:line | Verdict |
|----------|---------|-----------|---------|
| low | debug-echo | build-caudit-prompt.sh (8 sites) | false positive — legitimate prompt-text emission |
| low | debug-echo | check-no-pending-sfg-lift.sh (7 sites) | false positive — remediation-message echoes |
| high | error-suppression | build-pre-pr-base-markers.sh:37,56 | false positive — `: > file ... \|\| true` init; `git grep ... \|\| true` tolerates no-match (git grep exits 1) |

No substantive antipattern defects in feature code.

## Smells

None blocking. The debug-echo flags above are the scanner mistaking intended stdout for debug output.

## Drift

None found. Code uses the abstractions the spec requires (UNTRUSTED_* fence pattern, ABS-029 cmd_* gate convention, PAT-018 prompt-level fallback, ABS-041 sentinel lifecycle).

## Findings

1. **[HIGH — process] /cverify was skipped in the pipeline.** Workflow state is at phase `done`, advanced via `workflow-advance.sh override` (`override_count: 3`), not through a clean `verified → documented → done` progression. No verification report existed for this feature before this run. The override reason cites QA + mini-audit completion but verification (rule-coverage matrix, dependency check, architecture adherence) had not been performed. This verification report now backfills that gap. Per the spec's own CS-019 / AP-023 concern, repeated override-to-advance is the exact escalation pattern flagged on PR #180 (`override_count: 3` matches). The implementation itself is sound; the process gap is the finding.

2. **[LOW — flaky test] INV-007(b) is order/state-dependent.** On the first full-suite run during this verification, `INV-007(b)` (migration-spec check: `^Result: PASS$` inside the `## VP-002` section of `fix-diff-reviewer-migration-replay.md`) FAILED, while passing in isolation and on all subsequent full-suite runs. The report file md5 is unchanged before/after. On `main` the full suite is 140/0 with INV-007(b) passing. This is a pre-existing flaky/transient check (its function `check_inv007` is unchanged by this feature), not a regression — but it can produce spurious red on a single run. Worth a separate hardening pass (the awk-extract + grep is sensitive to something transient in the run environment).

3. **[INFO] actual_tokens = 0 — token log absent.** No `token-log-feature-fix-diff-reviewer-class-shaped-bugs-9453a4.jsonl` exists. Consistent with the known silent-telemetry token-tracking gap. Calibration entry records 0.

## Spec Updates

Spec was amended twice during the workflow (both pre-TDD, recorded in the Amendment Log): 2026-06-15 PR #180 descope correction (re-locked CS-018/CS-009a/CS-019), and 2026-06-15 creview-spec round 2 (31 findings, INV→CS renamespace). No mid-TDD rule rewording recorded in workflow state (`spec_updates` not incremented during TDD).

## Overall: PASS with 1 HIGH process finding + 2 advisory

Implementation fully satisfies all 21 CS-NNN invariants with backing structural + behavioral tests (188/0/1). No uncovered rules, no new dependencies, architecture (ABS-041) compliant, no code-level antipattern defects. The single HIGH finding is **process, not implementation**: /cverify was bypassed via override and is only now being run post-`done`. The implementation is merge-quality; the workflow hygiene (override-to-advance, `override_count: 3`) should be noted.
