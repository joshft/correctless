# Verification: Cross-Model Spec Review via codex

**Spec**: `.correctless/specs/cross-model-spec-review.md` (242 lines, intensity: high)
**Branch**: `feature/fix-diff-reviewer-class-shaped-bugs` (git branch reused; workflow task = `cross-model-spec-review`)
**Merge-base with main**: `14e71eb` (the prior fix-diff-reviewer-class feature is already merged to main; this branch carries 2 commits on top: `6885858` impl + `d2756e3` mini-audit fixes)
**Verified-by**: /cverify (autonomous mode)

> NOTE: The git branch name and the stale `workflow-state-feature-fix-diff-reviewer-class-shaped-bugs-9453a4.json`
> reference the already-merged fix-diff feature. The feature actually under verification is
> `cross-model-spec-review` (its own state file shows phase `done`, qa_rounds 1). All checks below
> target the cross-model-spec-review diff (`git diff 14e71eb..HEAD`).

## Rule Coverage

All 23 invariants are referenced by tests; behavioral (not merely grep-existence) tests confirmed for
all security/data-integrity invariants. 22 dedicated `test_inv_0NN` behavioral functions present.

| Rule | Test | Status | Notes |
|------|------|--------|-------|
| INV-001 codex structured output | test_inv_001 (test-external-review.sh) | covered | argv carries both flags + schema path; file wins over stdout |
| INV-002 parse-gate+bound+namespace+coerce | test_inv_002 | covered | malformed JSON, RS-id renamespace, severity coerce, fence-delimiter neutralize |
| INV-003 no artifact data on argv (outbound) | test_inv_003 + 200KB stdin scale fixture | covered | spec on stdin, no ARG_MAX |
| INV-004 read-only bounds writes only | test_inv_004 | covered | git status parity, banned-flag absence; egress caveat is EA |
| INV-005 tri-state activation | test_inv_005 + matrix | covered | template ships absent; no `{prompt}`/`codex exec` literal in skill |
| INV-006 graceful degradation | test_inv_006 (failure modes) | covered | skipped vs error distinguished |
| INV-007 sole-writer locked record | test_inv_007 | covered | self-seed, locked_update_file, run_id-keyed, concurrent preserve |
| INV-008 disposition back-fill/pending | test_inv_008 | covered | 5-value enum, set-disposition round-trip, pending listing, attribution |
| INV-009 nonce-fence + neutralize | test_inv_009 | covered | reuses build-caudit-prompt.sh; forged `</UNTRUSTED_EXTERNAL_REVIEW>` neutralized |
| INV-010 SFG-safe paths, 3-form DEFAULTS | test-external-review + test-sensitive-file-guard | covered | both writers in all 3 path forms; block-both-paths |
| INV-011 external cost from --json usage | test_inv_011 + real fixture drift pin | covered | turn.completed / .usage.input_tokens pinned to committed fixture |
| INV-012 whole-spec payload | test_inv_012 | covered | stdin capture asserts full body + flagged/unflagged invariants |
| INV-013 producer reachable; Write removed | test-allowed-tools-check.sh (INV-013-01/02/03) | covered | Bash grant present AND history Write absent (negative assert); csetup grant present |
| INV-014 egress disclosed | test_inv_014 | covered | secrets/.env/git-history named in csetup disclosure block |
| INV-015 argv array, no shell | test_inv_015 + antipattern-scan shell-injection | covered | argv-capture seam, no eval-family over config |
| INV-016 config merge no-clobber | test_inv_016 (AP-004 matrix + jq-injection) | covered | creates missing keys, siblings survive, --arg/--argjson |
| INV-017 closed-allowlist validation | test_inv_017 | covered | rejects /bin/sh bin, symlink, --cd /, --proxy, danger-full-access, timeout clamp |
| INV-018 codex stub seam | make_fake_codex helper + all behavioral tests | covered | offline, no network |
| INV-019 bound+neutralize return path | test_inv_019 | covered | 200KB desc, 10^4 array, NUL/escape, ../../etc/passwd location |
| INV-020 lift-and-restore N deliverables | test-external-review + test-sensitive-file-guard | covered | multi-deliverable: lift A restore B still FAILs backstop |
| INV-021 real-fixture RED gate | fixtures committed w/ PROVENANCE.md + drift test | covered | real codex 0.139.0 output + JSONL stream |
| INV-022 consolidated status surface | test_inv_022 | covered | ran/skipped/error block, send-time egress line, disable hint |
| INV-023 upgrade migration | test_inv_023 | covered | old-default false migration, set-require-external-review round-trip |

**Prohibitions**: PRH-001..007 all referenced (5/2/6/3/6/3/5 test hits).
**Boundary conditions**: BND-001/003/004 referenced; BND-002 covered functionally via INV-015/INV-017.

No UNCOVERED rules. No weak tests identified.

## Dependencies
- No package manifest in this project (bash). No new external dependencies introduced.
- New runtime dependency on `codex` CLI is OPTIONAL and auto-off-when-absent (INV-005/006). jq 1.7+ already a project dependency (EA-005).

## Architecture Adherence

- ABS-042 (sole-writer external-review producer): valid — `scripts/external-review-run.sh` exists; Test field references `tests/test-external-review.sh` which exists and references the entry; invocation-coupled + locked + self-seed confirmed in code.
- TB-008 (external model output → synthesis → spec): valid — added to ARCHITECTURE.md; invariant text (nonce-fence, parse-gate, advisory-only) consistent with implementation.
- TB-001c (structured external-tool config → argv no eval): valid — added; INV-015/017 implement the bin-realpath + closed flag-allowlist.
- AGENT_CONTEXT.md counts updated: scripts 27→29, tests 94→95 — consistent with 2 new scripts + 1 new test file.

3 new architecture entries checked, 0 stale, 0 path-missing.

### Drift Debt
- No open drift-debt items. No new drift detected — implementation uses the spec's abstractions
  (lib.sh locked_update_file, build-caudit-prompt.sh nonce-fence reuse, config-update.sh as sole config writer).

## QA Class Fixes Verified

qa-findings-cross-model-spec-review.json records 15 findings (1 QA round + 1 mini-audit round, 11 lenses).
The BLOCKING findings were fixed in commit `d2756e3`. All fixes verified present in source:

- QA-001 / MA-001 (CRITICAL: --sandbox not producer-injected) — FIXED: `cmd_review` unconditionally appends `argv+=("--sandbox" "read-only")` (L567); `_validate_invocation` strips any config-supplied --sandbox (L289-307). ✓
- MA-002 (output flags as bare tokens corrupt argv) — FIXED: `--output-schema|--output-last-message` fail-closed `return 1` (L281-288). ✓
- MA-003 (schema temp-file leak via wiped EXIT trap) — FIXED: explicit `rm -f ... "$schema_file"` on all 4 return paths (L602/609/619/643). ✓
- MA-004 / QA-004 (jq OOM on attacker-sized output file) — FIXED: `_within_size_ceiling` 4MiB guard before first whole-file jq parse, applied to both output file (L367) and JSONL cost stream (L440). ✓
- MA-005 (pending not surfaced in /cstatus) — FIXED: test MA-005 passes confirming cstatus invokes `external-review-run.sh pending`. ✓
- MA-006 / QA-002 (macOS realpath → misleading skip cause) — FIXED: canonicalize_path fallback + distinct `VAL_SKIP_CAUSE` (L230-244). ✓
- MA-007 (dead config key external_review_threshold) — FIXED: test MA-007 passes confirming removal from template. ✓
- MA-008 (tests write into real artifacts dir) — FIXED: CORRECTLESS_ARTIFACTS isolated in 10 test sites. ✓

The fixes are class-shaped (e.g. MA-001 closes AP-022 dead-code-in-security-paths by unconditional
injection + strip, not an instance patch), consistent with the project's structural-enforcement convention.

## Antipattern Scan

Scanner ran clean (`errors: []`). 0 BLOCKING/structural findings. Feature-file findings are the
project's known advisory false-positive classes:
- "Debug echo statement" (low) — these are intentional status/error `echo`/`printf` lines, not debug output.
- "Error suppression with || true / 2>/dev/null" (high label, advisory) — intentional fail-open per INV-006
  graceful-degradation design (the producer must NEVER block the Claude review on external failure).

Both classes match established codebase conventions (PAT-005 fail-open, INV-006). No action required.

## Smells
- None beyond the advisory antipattern classes above. No TODO/FIXME/HACK, no commented-out code,
  no hardcoded secrets in the new scripts.

## Drift
- None found. No DRIFT-NNN entries created.

## Spec Updates
- Spec records codex rounds 1–3 (19 findings) + Claude /creview-spec (30 findings RS-001–RS-030) all
  applied pre-implementation. No mid-TDD spec mutations recorded in workflow state.

## Test Suite
- Full suite GREEN: every `tests/test-*.sh` file exits RC=0 with 0 failures.
- test-external-review.sh: 110 passed, 0 failed.
- test-sensitive-file-guard.sh: 186 passed, 0 failed.
- test-allowed-tools-check.sh: 19 passed, 0 failed.
- test-fix-diff-reviewer-agent.sh: 188 passed, 0 failed, 1 skipped (SFG-lift sentinel SKIP path — sentinel absent, expected).
- SFG lift backstop (`check-no-pending-sfg-lift.sh`): exit 0 (no pending lift; restore landed).

## Overall: PASS with 0 BLOCKING findings

All 23 invariants covered by behavioral tests. All QA/mini-audit BLOCKING findings fixed and verified
in source. Architecture entries added and consistent. Full test suite green. Antipattern scan clean
(only project-standard advisory classes). No drift, no uncovered rules, no new dependencies.
