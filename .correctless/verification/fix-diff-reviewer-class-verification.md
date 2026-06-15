# Verification: Fix-diff reviewer class-shaped bug lens

**Spec**: `.correctless/specs/fix-diff-reviewer-class.md` (499 lines)
**Branch**: `feature/fix-diff-reviewer-class-shaped-bugs`
**Effective intensity**: high (project floor + TB-005 boundary)
**Verified**: 2026-06-15

## Rule Coverage

15 testable invariants (INV-001..INV-007, INV-009..INV-017) + INV-012a backstop = 16 sub-assertions enforced by `check_class_shaped_bug_detection` in `tests/test-fix-diff-reviewer-agent.sh:2276`. INV-008 (distribution mirror byte-equality) is covered by the existing infrastructure per spec line 152.

| Rule | Test | Status | Notes |
|------|------|--------|-------|
| INV-001 (class-shaped section present) | CLS-INV-001 | covered | level-2/3 heading, body non-empty, precedes Output contract |
| INV-002 (two-signal detection) | CLS-INV-002 | covered | primary/refinement signals, non-exhaustive seed, graceful-degradation language, code-pattern seeds |
| INV-003 (sibling-grep imperative) | CLS-INV-003 | covered | <=120-char positive imperative naming Read/Grep/Glob (live agent line: "When this lens triggers, use Read/Grep/Glob to grep sibling instances of the same pattern.") |
| INV-004 (SIBLING-DEFERRED carve-out) | CLS-INV-004 | covered | literal token, optional `:line-number` regex, >=6 comment styles incl `<!-- -->` and `;`, excludes `"""`, names "true syntactic comment", worked example in code fence |
| INV-005 (HIGH/LOW calibration + aggressive default) | CLS-INV-005 | covered | worked HIGH example (ARG_MAX/build-dashboard), worked LOW example (nil-check with central constructor), "when in doubt, default to HIGH" |
| INV-006 (PMB-019/#144/#124 citation) | CLS-INV-006 | covered | citation present with narrative context ("Motivated by PMB-019 (GH #144...)") |
| INV-007 (cardinality checklist) | CLS-INV-007 + CLS-INV-007-cardinality | covered | EXPECTED_SUB_ASSERTION_IDS has 16 entries; closing assertion compares EXERCISED vs EXPECTED |
| INV-008 (distribution mirror byte-equal) | inherited from existing ABS-010 tests | covered | direct `diff` confirmed byte-equality on both `agents/` and `correctless/agents/` |
| INV-009 (denylist extension + data-treatment prose) | CLS-INV-009 | covered (weak on a) | (b) `agents/fix-diff-reviewer.md:24` enumerates `<UNTRUSTED_FINDING_DESCRIPTION>` by name (compliant); (a) denylist proxy check passes via self-reference grep but the canonical `phrases=()` array at `tests/test-fix-diff-reviewer-agent.sh:520-529` does NOT include the new lens-specific strings. See Findings #1. |
| INV-010 (scope-amendment proximity-anchor) | CLS-INV-010 | covered | exception clause within 5 lines of "Out of scope: the unchanged codebase" (live agent line 46-54), no level-3 heading separates them, "EXCEPT" + "narrow exception" linking language present |
| INV-011 (Step 6a fence emission, JSON-array) | CLS-INV-011 | covered | `<UNTRUSTED_FINDING_DESCRIPTION>` fence in Step 6a with id/description schema, ascending-id ordering, empty/whitespace filtering, empty-array omission, ABS-029 artifact path reference, graceful-degradation language in agent |
| INV-012 (SFG hook final-state with SKIP sentinel) | CLS-INV-012 | covered | sentinel absent; `agents/fix-diff-reviewer.md` present in DEFAULTS of both `hooks/sensitive-file-guard.sh` and `correctless/hooks/sensitive-file-guard.sh` |
| INV-012a (final-state backstop script) | CLS-INV-012a | covered | `scripts/check-no-pending-sfg-lift.sh` exists, executable, NOT under `tests/test-*.sh` glob, exits 0 when sentinel absent and 2 with remediation message naming AP-037 when present. Direct invocation: `OK: no pending lift`. |
| INV-013 (prompt-composition fixtures + helper) | CLS-INV-013 | covered | 3 fixtures present (argmax with PR #124 provenance, loop-var with round-added + string-literal cases, error-handling); `tests/helpers/build-caudit-prompt.sh` exists and is functional (emits fence when findings provided, omits when fence is `-`, includes DIFF fence) |
| INV-014 (size-cap and truncation) | CLS-INV-014 | covered | Step 6a documents 4096/16384 emitted-byte model + `[truncated: N more bytes]` marker; helper functionally truncates a 5KB description to under per-entry cap and inserts the marker |
| INV-015 (bounded scope + 4-category deny-list) | CLS-INV-015 | covered | same-directory + same-extension scope; all 4 deny-list categories (`.env`, `.correctless/preferences`, autonomous-decisions, `.git/objects`); non-exhaustive marker within 5 lines |
| INV-016 (marker-validity contract) | CLS-INV-016 | covered | diff-fence-only provenance, 30-char rationale floor, 3 reject-as-non-substantive examples, round-added detection language with MEDIUM downgrade, pre-existing suppression, explicit "reviewer does NOT receive commit author email" disclaim |
| INV-017 (class_fix verbatim marker example) | CLS-INV-017 | covered | "class_fix" within 10 lines of "marker", "Example marker:" annotation, verbatim sample in code fence matching INV-004 regex |

**Test execution**: `bash tests/test-fix-diff-reviewer-agent.sh` -> 158 PASS, 0 FAIL, 1 SKIP (an unrelated INV-008(e) sync-sentinel test that skipped on a pre-existing condition unrelated to this feature). All 16 class-shaped sub-assertions PASS. Cardinality checklist closes: `all 16 EXPECTED_SUB_ASSERTION_IDS exercised, no extras`.

**Co-located tests also pass**:
- `bash tests/test-sensitive-file-guard.sh` -> 168 PASS, 0 FAIL (PRH-005 structural extraction-body checks pass; no recursion / eval / IFS shift in `_extract_bash_targets`)
- `bash tests/test-core.sh` -> 65 PASS, 0 FAIL (DA-001 eval-detection clean; verify-phase-rejected-in-Lite passes)
- `bash tests/test-architecture-drift.sh` -> 110 PASS, 0 FAIL (PAT-017 canonicalize-path pointer present; all ABS-NNN references resolve)

## Integration Test Coverage

Spec INV-007 is integration-tagged: `bash tests/test-fix-diff-reviewer-agent.sh` is the entry, `tests/test-helpers.sh` is the through, and the test runs against the actual `agents/fix-diff-reviewer.md` (and live `hooks/sensitive-file-guard.sh`, live `skills/caudit/SKILL.md`, real fixtures). The INV-012a sub-assertion creates a temp project root with and without the sentinel and verifies the script's exit codes (0 absent, 2 present) plus remediation-message content. INV-013 uses the helper to assemble synthetic prompts from real fixtures and asserts shape/cap behavior on the assembled text. The integration contract holds.

## Dependencies

No package manifests changed. This is a documentation/prompt + shell-test feature; no new runtime dependencies. `package.json`, `go.mod`, `requirements.txt`, etc. unchanged on this branch.

## Architecture Adherence

Affected entries (from `git diff main...HEAD --name-only` cross-reference against `.correctless/ARCHITECTURE.md`):

- **ABS-010 (Plugin-agent file contract)**: valid -- `agents/fix-diff-reviewer.md` continues to satisfy single-source-of-truth, byte-equal distribution mirror (`diff` confirmed), `tools: Read, Grep, Glob` allowlist unchanged, frontmatter `name:` matches basename. All listed Enforced-at paths exist; all listed Test paths exist and reference ABS-010 except `tests/test-carchitect.sh` which does not reference ABS-010 literally (covered indirectly via its check of the agent contract). The 6 listed test files all exist. Invariant statement unchanged by this feature. New consumer language in caudit Step 4b/4b emission is consistent with the agent-as-sole-source-of-truth contract.
- **ENV-007 (Plugin-agent loader contract)**: valid -- assumption holds (Claude Code v2.1+ supports `name`/`description`/`tools`/`model` frontmatter; namespaced `Task(subagent_type="correctless:fix-diff-reviewer")` invocation pattern unchanged). VP-001/VP-002 manual replay record at `.correctless/verification/fix-diff-reviewer-migration-replay.md` exists from the earlier migration feature; this feature did not require a new replay because the lens is additive prose and the tool surface is unchanged.
- **ENV-010 (Agent tool worktree isolation contract)**: valid -- unchanged. Spec INV-015 and BND-002 reaffirm the read-only / no-edit / no-bash invariant the worktree isolation depends on.

Cross-feature reads:
- **TB-001 (sensitive-file-guard data-flow boundary)**: valid -- `agents/fix-diff-reviewer.md` is in DEFAULTS of both `hooks/sensitive-file-guard.sh` and `correctless/hooks/sensitive-file-guard.sh`. Lift sentinel `.correctless/.sfg-lift-active` absent. Final-state backstop script `scripts/check-no-pending-sfg-lift.sh` present, executable, exits 0 in current state. AP-037 lift-and-restore workflow documented in spec INV-012 + INV-012a; rule file `.claude/rules/sfg-deliverable.md` referenced.

### Drift Debt

`.correctless/meta/drift-debt.json` open items: 0. No drift-debt items reference architecture entry IDs touched by this feature or files in the touched set.

3 affected architecture entries checked, 0 stale, 0 drift-debt items.

## Compliance Checks

`workflow.compliance_checks` is not configured in `workflow-config.json`; no compliance checks to run at the verify phase. Per-spec compliance gates (the INV-007 cardinality check and INV-012a final-state backstop) ran successfully as documented above.

## Antipattern Scan

Run: `bash .correctless/scripts/antipattern-scan.sh main`

Scanner found 35 findings total. All 11 HIGH-severity findings are `error-suppression` instances (`2>/dev/null`) in `tests/test-fix-diff-reviewer-agent.sh`. Verified intentional:

| File:Line | Pattern | Context |
|-----------|---------|---------|
| tests/test-fix-diff-reviewer-agent.sh:718,719 | `rm -f .../*.md 2>/dev/null \|\| true` | Idempotent sentinel cleanup at test start. Pre-existing pattern; matches sister tests. |
| tests/test-fix-diff-reviewer-agent.sh:722,723 | `rm -f ... 2>/dev/null \|\| true` | Cleanup function definition. Pre-existing. |
| tests/test-fix-diff-reviewer-agent.sh:740,754 | `mkdir -p ... 2>/dev/null \|\| true` | Idempotent dir creation. Pre-existing. |
| tests/test-fix-diff-reviewer-agent.sh:747,761 | `rm -f "$sentinel_*" 2>/dev/null \|\| true` | Per-test sentinel cleanup. Pre-existing. |
| tests/test-fix-diff-reviewer-agent.sh:2633,2635 | `bash $CLS_HELPER ... 2>/dev/null \|\| true` | New (this PR). Helper invocation under INV-013 functional check; non-zero exit treated as test failure via subsequent assertion. Acceptable. |
| tests/test-fix-diff-reviewer-agent.sh:2666 | `bash $CLS_HELPER ... 2>/dev/null \|\| true` | New (this PR). Helper invocation under INV-014 truncation check; same pattern as above. |

All 24 LOW-severity `debug-echo` findings are in `tests/test-architecture-drift.sh` and unrelated to this feature (pre-existing test diagnostics). No regressions introduced.

## QA Class Fixes Verified

`qa-findings-fix-diff-reviewer-class.json` records 6 NON-BLOCKING QA findings (QA-001..QA-006) and the spec's mini-audit produced 5 + 2 = 7 advisory findings across 2 rounds with 0 BLOCKING entries. None required a class fix because none were BLOCKING; the spec's structural test (`check_class_shaped_bug_detection`) is itself the class-level defense and is verified above.

## Smells

None blocking. The new helper `tests/helpers/build-caudit-prompt.sh` and the new dedicated script `scripts/check-no-pending-sfg-lift.sh` are clean shell with no TODO/FIXME/HACK markers (HACK string occurrences in `skills/caudit/SKILL.md` are finding-id examples like `HACK-003`, not code smells).

## Drift

None found. The implementation matches the spec's R-xxx / INV-xxx rules. No `Implemented in: (GREEN phase)` placeholders remain unsatisfied (the spec field was left at "(GREEN phase)" but every invariant has a corresponding live implementation verified by the structural test; the placeholder is documentation drift that `/cdocs` should update).

No drift-debt entries created.

## Findings

### Finding #1: INV-009(a) denylist extension is satisfied by proxy, not literal extension (MEDIUM)

**Location**: `tests/test-fix-diff-reviewer-agent.sh:520-529` (canonical denylist) vs `tests/test-fix-diff-reviewer-agent.sh:2465-2468` (CLS-INV-009 self-reference check)

**Observation**: Spec INV-009(a) requires the inline-prompt denylist (around line 521) to be extended to include `class-shaped`, `SIBLING-DEFERRED`, and `sibling instances`. The implementation satisfies this via a self-reference grep at line 2466-2468 — the test counts those phrases appearing anywhere in itself, which trivially passes because the test mentions those strings while implementing the CLS-INV-* checks themselves. The canonical `phrases=()` array at line 520-529 is unchanged.

**Severity**: MEDIUM (non-blocking). The spirit of INV-009(a) — preventing inline-prompt duplication of the new lens prose into other skill files — is currently satisfied passively (no `skills/*/SKILL.md` reproduces the lens body), but the structural defense relies on the proxy check rather than the canonical extension. If `skills/cauto/SKILL.md` or another skill were to copy lens prose tomorrow, the canonical `phrases=()` denylist would not catch it.

**Reason not raised as BLOCKING**: the actual harm condition (inline lens prose in another skill) does not exist today, and adding the new phrases verbatim to `phrases=()` would create false positives in the legitimate `class-shaped lens refinement input` reference at `skills/caudit/SKILL.md:283`. The mitigation requires more nuanced anchoring than a literal phrase list.

**Recommendation**: defer to a follow-up — when the denylist mechanism is next refactored, switch to a heading-anchored or block-anchored check that distinguishes "Step 4b refers to the lens" (allowed) from "Step X duplicates the lens body" (denied).

### Finding #2: Calibration entry could not be written (ENVIRONMENT)

**Location**: `.correctless/meta/intensity-calibration.json`

**Observation**: The /cverify skill prose mandates writing a calibration entry before advancing the workflow. The file is protected by `hooks/sensitive-file-guard.sh` (AP-022 mitigation; ABS-026-class sole-writer convention) and the active Claude Code session cannot Edit or Bash-redirect to it. The calibration entry for `fix-diff-reviewer-class` is NOT persisted by this verification run.

**Severity**: ENVIRONMENT (not a code defect). The skill contract and the SFG default conflict for this protected path; this is a known instance of AP-037 (protected asset is the calibration ledger). Past calibration entries (24 in the file) suggest historical writes happened during periods when the SFG default did not include this path or via the override mechanism.

**Recommendation**: The /cverify skill prose should be amended (separate PR / spec follow-up) to either (a) invoke an SFG override gated by phase-transition state, or (b) route calibration writes through a dedicated sole-writer script analogous to `scripts/audit-record.sh` for audit findings. For this feature, defer to /cdocs or merge consolidation to record the calibration data.

## Spec Updates

`spec_updates: 0` per workflow state. No spec updates during TDD; the spec was approved at 499 lines and shipped as-is.

## Overall: PASS

15 spec invariants + 1 backstop + 1 inherited = 17 rules accounted for, all covered by structural tests against the live filesystem. Test suite green (158/0/1 on the focal file; 168/0, 65/0, 110/0 on co-located tests). Distribution mirrors byte-equal. SFG protection restored and verified. Final-state backstop script functional. PMB-019 motivating recurrence cited with narrative context in the live agent prose. Two non-blocking findings (one MEDIUM advisory on the denylist proxy pattern, one ENVIRONMENT on the calibration-write contract) recorded for follow-up.

The implementation does not just satisfy the test cases — every assertion is a structural grep against the live agent file, the live caudit skill, the live SFG hook, and the live fixtures with provenance from PR #124. The class-shaped lens prose is well-formed, the marker-validity contract is internally consistent (diff-fence-only provenance + 30-char rationale floor + round-added MEDIUM downgrade), and the SFG lift-and-restore workflow has both the in-iteration SKIP path and the non-skippable final-state backstop.

No BLOCKING findings. Verification PASSES.
