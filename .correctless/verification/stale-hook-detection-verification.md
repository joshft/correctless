# Verification Report: Stale Hook Detection

**Task**: stale-hook-detection
**Date**: 2026-04-14
**Intensity**: high
**Spec rules**: 5 (R-001 through R-005)
**Test suite**: tests/test-stale-hook-detection.sh — 36 tests, 0 failures

## Rule Coverage

### R-001 [integration]: Setup writes .install-manifest.json

| Sub-check | Status | Evidence |
|-----------|--------|----------|
| Manifest created after setup | PASS | test_r001_manifest_created_after_setup (R-001a) |
| Valid JSON with installed_at, source_dir, files | PASS | R-001b/c/d |
| installed_at is ISO timestamp | PASS | R-001e |
| source_dir is absolute path | PASS | R-001f |
| Dynamic scanning — all .sh in hooks/ and scripts/ present | PASS | R-001g |
| installed_hash == source_hash at install time | PASS | R-001h |
| Manifest overwritten on re-run | PASS | R-001i |
| Relative paths include hooks/ or scripts/ prefix | PASS | R-001j |
| Atomic write via temp + mv | PASS | Code review: setup lines 313-355 use `.install-manifest.json.$$` then `mv` |
| Abort on hash failure (partial manifest never written) | PASS | Code review: `manifest_ok=false; break 2` exits both loops, `rm -f "$manifest_tmp"` cleans up |
| Sources $SCRIPT_DIR/scripts/lib.sh (source-tree copy) | PASS | Code review: setup line 311 `source "$SCRIPT_DIR/scripts/lib.sh"` |

### R-002 [unit]: check_install_freshness function

| Sub-check | Status | Evidence |
|-----------|--------|----------|
| ok status when hashes match | PASS | R-002a/b/c |
| No false positives (no modified/missing/source_ahead when all ok) | PASS | R-002d/e/f |
| modified status when installed file differs from manifest | PASS | R-002g |
| Unmodified files still report ok alongside modified | PASS | R-002h |
| missing status when file deleted | PASS | R-002i |
| source_ahead when source file changed | PASS | R-002j |
| Unmodified files still ok alongside source_ahead | PASS | R-002k |
| new_file for files on disk but not in manifest | PASS | R-002l |
| no_manifest when manifest missing | PASS | R-002m |
| Source-ahead skipped when source_dir missing | PASS | R-002n |
| Install-vs-manifest still works without source_dir | PASS | R-002o |
| Output format: status:relative/path per line | PASS | R-002p |
| Bulk jq parse (single jq call) | PASS | Code review: lib.sh lines 313-316 |

### R-003 [integration]: /cauto startup warnings

| Sub-check | Status | Evidence |
|-----------|--------|----------|
| source_ahead detected for warning | PASS | R-003a/b |
| No output when all ok | PASS | R-003c |
| new_file detected for warning | PASS | R-003d |
| Warning text in SKILL.md | PASS | skills/cauto/SKILL.md "Install Freshness Check" section, lines 57-78 |
| Advisory not blocking | PASS | SKILL.md states "All warnings are advisory, not blocking" |
| Audit trail logging specification | PASS | SKILL.md specifies `install_staleness_detected` event type |

### R-004 [unit]: /cstatus install freshness status line

| Sub-check | Status | Evidence |
|-----------|--------|----------|
| Install: current when all ok | PASS | R-004a |
| Install: STALE when source_ahead | PASS | R-004b |
| Install: STALE when modified/missing | PASS | R-004c/d |
| Install: unknown when no_manifest | PASS | R-004e |
| Single line in SKILL.md | PASS | skills/cstatus/SKILL.md section 5: "Install Freshness" |

### R-005 [unit]: Manifest is gitignored

| Sub-check | Status | Evidence |
|-----------|--------|----------|
| .correctless/.install-manifest.json in .gitignore | PASS | R-005a, .gitignore line 34 |

## Architecture Compliance

| Check | Status | Evidence |
|-------|--------|----------|
| ABS-022 in ARCHITECTURE.md | PASS | Documents sole writer (setup), sole reader (check_install_freshness), lifecycle, gitignore |
| ABS-022 test reference | PASS | "Test: test-stale-hook-detection.sh -- R-001, R-002" |
| No new trust boundaries introduced | PASS | No new TB-xxx needed; manifest is local state, not cross-trust |
| No new dependencies | PASS | Uses existing sha256sum/shasum/openssl fallback chain already in lib.sh |
| Shared library placement | PASS | check_install_freshness added to scripts/lib.sh alongside sha256_hash_file |

## Undocumented Dependencies

None found. The feature uses:
- `jq` — already a project-wide dependency
- `sha256sum`/`shasum`/`openssl` — already used by sha256_hash_file (Auto Mode Phase 3 extracted this to lib.sh)
- Bash associative arrays (`local -A`) — Bash 4+ requirement already established by existing lib.sh code (`${var,,}` in classify_file)

## Smells

None detected:
- No hardcoded file lists — dynamic scanning via glob
- No duplicated logic — sha256_hash_file shared between setup and check_install_freshness
- Atomic write pattern consistent with locked_update_state pattern
- Fail-safe design: hash failure aborts manifest (no partial state), missing source_dir degrades gracefully

## Deferred Items

None.

## Summary

All 5 spec rules verified with 36 passing tests. Implementation is clean, uses established patterns (shared lib, atomic writes, dynamic scanning), and introduces no new dependencies or trust boundaries. ABS-022 properly documented in ARCHITECTURE.md.
