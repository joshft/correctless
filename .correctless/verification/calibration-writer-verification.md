# Verification: Sanctioned sole-writer for SFG-protected meta artifacts (calibration-writer)

**Spec**: `.correctless/specs/calibration-writer.md` — Intensity: high — HEAD `9970542`
**Verifier**: /cverify (autonomous, /cauto pipeline) — 2026-07-04

## Rule Coverage

17/17 rules covered. All spec rules (INV-001..010, PRH-001..006, BND-001) have a
test that references the rule ID AND the implementation satisfies it (verified by
running the suites below). Cross-file rules (INV-004 allowed-tools, INV-005 SFG
protection, PRH-003 target-file protection) are covered in the SFG /
allowed-tools / harness-fingerprint test files rather than `test-meta-record.sh`.

| Rule | Test | Status | Notes |
|------|------|--------|-------|
| INV-001 (sole append-only, deep-equal preservation) | test-meta-record.sh | covered | deep-equal on `[:-1]` prior slice + order-preservation on multi-entry fixture |
| INV-002 (schema validation under lock, permissive unknown) | test-meta-record.sh | covered | malformed-shape rejection + unknown-field-preserved cases |
| INV-003 (fail-loud FAILED stdout token, never silent no-op) | test-meta-record.sh + integration | covered | failure-injection asserts non-zero + exact `meta-record: FAILED` token |
| INV-004 (skills write via sanctioned Bash path, shell-safe) | test-meta-record.sh, test-allowed-tools-check.sh, test-harness-fingerprint.sh | covered | allowed-tools grant flip + Bash(*meta-record.sh*); 127 remediation |
| INV-005 (writer script SFG-protected, Edit/Write-blocked) | test-sensitive-file-guard.sh:1927+ | covered | all 3 forms in DEFAULTS; Bash write allowed (AP-040 honesty); lift-aware skip |
| INV-006 (class closure — every protected meta json → registered writer) | test-meta-record.sh | covered | anchored `^\.correctless/meta/[^/]+\.json$` regex rejects `credentials.json`; verbatim DEFAULTS fixture |
| INV-007 (concurrent-safe atomic write via reused lock helpers) | test-meta-record.sh, test-lib-locking.sh | covered | no-lost-update: entries == exit-0 successes; valid JSON throughout |
| INV-008 (calibration schema pinned to /cverify producer shape) | test-meta-record.sh | covered | typed fixture + PAT-015 content-pairing drift check |
| INV-009 (pat001 present-null-only/single-file; baselines key-merge) | test-meta-record.sh + integration | covered | {absent→no-op, present-null→set, non-null→no-op, corrupt→fail}; sibling-untouched (#226); baselines new/replace/schema-mismatch |
| INV-010 (bounded input, symlink-refusing fail-closed realpath) | test-meta-record.sh | covered | oversize reject, symlinked target/parent refuse, realpath-absent fail-loud, NUL-safe |
| PRH-001 (never mutate existing entries) | test-meta-record.sh | covered | prior-entry/key JSON-value comparison across append/merge |
| PRH-002 (skills never fall back to Write/Edit) | test-meta-record.sh, test-allowed-tools-check.sh | covered | grep + allowed-tools cross-check |
| PRH-003 (never lift SFG on the 3 target meta files) | test-sensitive-file-guard.sh:1983+ | covered | all three assert Edit/Write-blocked |
| PRH-004 (never success after attempted-but-unlanded write) | test-meta-record.sh | covered | failure-injection + exit-code table |
| PRH-005 (destination never derived from input) | test-meta-record.sh | covered | hostile stdin/argv cannot redirect; unknown-op fail-loud |
| PRH-006 (reuse ABS-003 lock helpers, no bespoke lock) | test-meta-record.sh, test-lib-locking.sh | covered | sources lib.sh, references `_acquire_state_lock`; no bespoke `.lock`/`rm -rf`/`locked_update_file` |
| BND-001 (meta-write input & target initialization) | test-meta-record.sh | covered | absent/zero-byte create; corrupt fail-loud; hex-SHA argv |

**Test suite results at HEAD 9970542:**
- `test-meta-record.sh`: 146 passed, 0 failed
- `test-lib-locking.sh`: 28 passed, 0 failed
- `test-sensitive-file-guard.sh`: 222 passed, 0 failed
- `test-allowed-tools-check.sh`: 20 passed, 0 failed
- `test-harness-fingerprint.sh`: 120 passed, 0 failed
- `test-intensity-calibration.sh`: 67 passed, 0 failed

## Dependencies
- No new package-manifest dependencies (bash/jq only). New *environment* dependency
  EA-004: `realpath` OR `readlink -f` for the INV-010 symlink verdict — probed
  fail-closed via `_realpath_tool_available` (writer fails loud if absent, never a
  lexical fallback). Consistent with the spec.

## Architecture Adherence

- ABS-047: valid — new sanctioned-meta-writer contract; Enforced-at paths (meta-record.sh, mirror, registry TSV, SFG hook, 3 rewired skills, lib.sh, sfg-deliverable.md, tests) all exist on disk.
- ABS-005: valid — cverify sole-writer invariant amended to route through `meta-record.sh calibration-append`; enforced-at + test paths present.
- ABS-027: valid — cmodelupgrade baselines write amended to `meta-record.sh baselines-write` (key-merge, schema_version preserved); direct Write grant dropped; enforced-at paths present.
- ABS-045: valid — SFG capability boundary (guardrail not perimeter) consistent with the mechanism-honesty note in the spec (PMB-020/AP-040).

3 primary entries checked, 0 stale, 0 drift-debt items.

Advisory (MEDIUM, non-blocking, for /cdocs): `test-meta-record.sh` references the
spec rule IDs (INV-001..010) but not the literal string `ABS-047`, so a bare
grep-for-entry-ID over the Test field would not match. Functional coverage is
complete; this is a cross-reference-string nicety only.

### Drift Debt
- (none — `.correctless/meta/drift-debt.json` has 0 open items referencing this feature)

## QA Class Fixes Verified

QA ran 2 rounds (round 1 QA, round 2 mini-audit / 8 lenses). Mini-audit findings
(MA-M1, MA-M2, MA-L2, MA-L3, MA-M6, MA-M7) are all reflected structurally in the
implementation and covered by tests:
- MA-M1 (bounded ingest): `head -c $((MAX_BYTES+1))` before `wc -c` — never buffers an unbounded stream ✓
- MA-M2/QA-003 (multi-document stdin): `jq -s (length==1)` guard on both calibration and baselines ✓
- MA-L3 (jq exit 1 vs ≥2): pat001 decision-read distinguishes predicate-false no-op from runtime-error fail-loud ✓
- MA-M6/EXT-005 (creation-order re-check): full `_guard_dest` re-run under the lock immediately before every `mv` ✓
- MA-M7 (lift-aware SFG test): INV-005 assertion skips when the sentinel names meta-record.sh ✓

## Antipattern Scan
`bash scripts/antipattern-scan.sh main` → exit 0, valid JSON, 205 findings total,
`errors: none`. Findings touching this feature's files:

| Sev | File:Line | Pattern | Disposition |
|-----|-----------|---------|-------------|
| high | scripts/meta-record.sh:228, :334 | AP-014 `jq -s` slurp "malformed lines cause total parse failure" | FALSE POSITIVE — `--slurpfile` reads a single-document temp file already guarded by an explicit `jq -s (length==1)` check; not a JSONL stream. Intentional exactly-one-document contract (QA-003). |
| high | scripts/meta-record.sh:357 | error-suppression `shift \|\| true` | FALSE POSITIVE — deliberate dispatch guard; unknown/empty op still fails loud in the `case`. |
| high | tests/test-meta-record.sh:1031 | error-suppression | test scaffolding, not production. |
| low | tests/*:several | debug echo | test scaffolding. |

No true-positive antipattern findings in this feature's code.

## Smells
- None load-bearing. The three "high" scanner hits on `meta-record.sh` are
  mechanical false positives (documented above): the `--slurpfile` usage is
  paired with a `length==1` single-document guard, and the `shift || true` is an
  intentional dispatch guard whose unknown-op path fails loud.

## Drift
- (none found)

## Spec Updates
- `spec_updates` = null in workflow state → 0 spec updates during TDD.

## Overall: PASS — 0 BLOCKING findings, 17/17 rules covered
