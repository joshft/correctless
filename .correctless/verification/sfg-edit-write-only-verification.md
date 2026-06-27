# Verification: Reduce sensitive-file-guard to Edit/Write-tool-path only

**Branch**: feature/sfg-edit-write-only — **Intensity**: high — **Phase at entry**: done (from /cauto Step 5)
**Spec**: .correctless/specs/sfg-edit-write-only.md
**Verified**: 2026-06-26

## Summary

This feature deletes the entire Bash write-target extraction path from
`hooks/sensitive-file-guard.sh` (~550 net LOC removed; 761-line diff on the
hook), reducing SFG to a pure Edit/Write tool-path guard. The implementation
matches the spec faithfully across all 10 invariants and 3 prohibitions. The
full test suite passes (exit 0). No BLOCKING findings.

## Rule Coverage

| Rule | Test(s) | Status | Notes |
|------|---------|--------|-------|
| INV-001 (Bash never inspected/blocked) | `test_inv001_bash_never_blocked_to_sensitive_files` (test-sensitive-file-guard.sh:158) | covered | Inverts the #205 must-block corpus: `> .env`, `tee`, `cp`, `mv`, `>>`, `sed -i`, `> api.secret` all assert exit 0. Hook STEP 3 fast-paths `Bash) exit 0` before lib.sh/config. |
| INV-002 (Edit/Write blocking UNCHANGED) | entire Edit/Write/MultiEdit corpus (test-sensitive-file-guard.sh) | covered | 205/205 pass; the MUST-PASS-UNCHANGED set is green. |
| INV-003 (canonical-form matching preserved) | canonical-matching tests + traversal cases | covered | `canonicalize_path` (PAT-017) still applied at matcher; traversal `subdir/../.env` still blocks. |
| INV-004 (lib.sh + workflow-gate unaffected) | `git diff` empty on `scripts/lib.sh` and `hooks/workflow-gate.sh`; test-hook-sync.sh + test-workflow-gate.sh green | covered | Confirmed: neither file changed by the branch. INV-004(a)+(b) both hold. |
| INV-005 (extraction code fully removed, no dead code) | `test_inv005_extraction_path_removed` (test-sensitive-file-guard.sh:~1769) | covered | Verified all 10 helpers + `_SFG_LENGTH_CAP` + `COMMAND=`/`${#COMMAND}` + the `Bash) _extract_bash_targets` arm absent from the hook. |
| INV-006 (input-parse failure fails closed) | malformed-JSON test + `test_ma_r2_h1_fail_closed_on_non_string_tool_name` (:1051) | covered | Malformed stdin → exit 2 for all tools including Bash (fast-path applies only AFTER successful parse). Non-string `tool_name` (array/object/number/null/absent) → jq `error()` → empty `$_PARSED` → exit 2 (no exit-127 crash). |
| INV-007 (doc coherence; pinned reject-list) | test-sfg-doc-coherence.sh (130/0) | covered | All 5 reject-substrings absent from current-state corpus; enumerated entries amended; dangling-ref check (test-sfg-rescope / _extract_bash_targets) zero in current-state surfaces (PMB ledger + the two structural test files correctly excluded). |
| INV-008 (PAT-001 carve-out removed; narrow exception documented) | test-sfg-doc-coherence.sh INV-008 checks | covered | Extraction carve-out gone from `.claude/rules/hooks-pretooluse.md`; DEFAULTS-only-on-unparsable-custom_patterns narrow exception documented ("never fully open"). |
| INV-009 (ABS-027/012/016 + TB-001b + R-019 + conventions amended; downgrade marker) | test-sfg-doc-coherence.sh INV-009 + test-architecture-drift.sh + test-semi-auto-mode.sh | covered | All entries reframed to Edit/Write-tool-path-only; durable downgrade marker present in ABS-027 and ABS-045 ("Bash-redirect structural leg removed 2026-06 by sfg-edit-write-only"). CLAUDE.md conventions name the `cmd_*` gate as the structural leg. |
| INV-010 (BLOCKED message + CHANGELOG honest) | message-content test + CHANGELOG body assertion | covered | Hook message says "this Edit/Write tool target '<path>'"; no "this command writes" / Bash framing. ("command" appears only on the `jq not found` line, unrelated.) |
| PRH-001 (never re-introduce Bash inspection) | INV-005 structural test | covered | No tokenizer/extractor in the hook; Bash fast-path is unconditional. |
| PRH-002 (never allow previously-blocked Edit/Write) | full Edit/Write corpus unchanged | covered | 205/205. |
| PRH-003 (never modify lib.sh `_has_write_pattern`/`get_target_file`) | `git diff scripts/lib.sh` empty | covered | lib.sh unchanged. |

**Uncovered rules: none.** All INV-001..010 and PRH-001..003 are covered by tests that actually probe the rule.

### Harness-fingerprint / semi-auto inversions (Test Corpus Migration)
- `test-harness-fingerprint.sh`: PRH-002e/f/g all inverted to exit 0 (Bash redirect/tee → fingerprint/baseline now ALLOWED); Edit-block assertions retained at exit 2; PRH-002c/d filename-mention strings preserved. 119/0.
- `test-semi-auto-mode.sh`: R-019 `cat data > preferences.md` inverted to exit 0; Edit-block + `test_pre006` DEFAULTS-membership retained. 204/0.
- `test-hook-sync.sh`: SFG-no-longer-calls-`_has_write_pattern` assertion + `test_qa002` Bash-write case handled; workflow-gate still-calls + neither-defines-locally retained. PASS.
- `test-sfg-rescope.sh`: DELETED (tested the removed Bash extraction path in its entirety).

## Dependencies
- No package-manifest changes (shell-only project). No new dependencies introduced.

## Architecture Adherence

- ABS-045: valid — narrowed to the authoritative capability-boundary entry (Edit/Write tool-path only; ALL Bash-mediated writes accepted non-goals). Enforced-at `hooks/sensitive-file-guard.sh` exists; durable downgrade marker present.
- ABS-027: valid — harness-fingerprint/model-baselines sole-writer clause reframed to Edit/Write-tool-path-only + residual-accepted note + downgrade marker.
- ABS-012: valid — intent-summary SHA-256 integrity leg retained; SFG clause reframed to Edit/Write tool-path only.
- ABS-016: valid — auto-policy SHA-256 integrity leg retained; SFG clause reframed.
- ABS-029 / ABS-041: valid — Tier 1 (`cmd_*` content gate detects forge); SFG downgrade is a no-op for integrity. Unchanged structural leg.
- ABS-030 / ABS-035 / ABS-038 / ABS-040 / ABS-042: valid — Tier 2 accepted residuals; each See-links ABS-045 and names its actual surviving (non-runtime-write-prevention) leg.
- TB-001a / TB-001b: valid — `preferences.md` + `workflow-config.json` → eval residual documented as accepted (owner-scaffolded, human-approved; Bash leg always evadable per PMB-020/AP-040). TB-001b prose reframed to Edit/Write-tool-path-only.
- AP-040: valid — superseded-annotation applied to AP-037 fix-layer-4 / AP-040 prescription in antipatterns.md (per QA-002).

All Enforced-at paths for affected entries exist on disk. No path-missing, no invariant-conflict. The deleted `_extract_bash_targets` and `tests/test-sfg-rescope.sh` references were stripped from the ABS-045 Enforced-at/Test fields.

### Drift Debt
- No new drift introduced. The code uses exactly the abstractions the spec prescribes (Edit/Write tool-path match via `canonicalize_path` + `config_file`; `_has_write_pattern` call site deleted, function retained in lib.sh for `workflow-gate.sh`). No DRIFT-NNN entries created.

**12 architecture entries checked, 0 stale, 0 drift-debt items.**

## QA Class Fixes Verified
- MA-R2-H1 (non-string `tool_name` → exit-127 crash): CLASS FIX present — jq filter coerces `tool_name` to scalar string and `error()`s on non-string; `file_path`/`edits` coerced to scalar. Regression test `test_ma_r2_h1_fail_closed_on_non_string_tool_name` present and registered. Covers the class (array/object/number/null/absent), not just the instance.
- MA-001 / MA-002 / MA-R2-CC-001/002 (doc-coherence allowlist misses): CLASS FIX present — reject-substring corpus generalized from an enumerated allowlist to a `git ls-files '*.md'`-derived corpus (minus excluded surfaces) + skills/scripts narrow leg; `gates every Bash` / `no direct redirect` pinned as reject literals. Verified in test-sfg-doc-coherence.sh.
- MA-003 (harness-fingerprint.sh comment): instance fix applied (line 39-40 now states Edit/Write-tool-path-only).

## Antipattern Scan
`bash scripts/antipattern-scan.sh main` — 195 findings repo-wide, 1 scanner error, 1 summary.
- **Scanner error** (`Failed to scan tests/test-sfg-rescope.sh: file not found (deleted?)`): benign — the deleted file appears in the diff name-list; the scanner reports it as an error, not a finding. Expected for a file-deletion diff.
- Findings on the changed hook (`hooks/sensitive-file-guard.sh`, 9): all `error-suppression` (`|| true` / `2>/dev/null` / `|| CUSTOM_PATTERNS=""`) — these are the deliberate, spec-justified fail-closed (INV-006) and DEFAULTS-only-degradation (INV-008) patterns in a fail-closed PreToolUse hook. Pre-existing pattern shape, not new for this feature.
- The 195 total is dominated by pre-existing patterns across the whole codebase (consistent with prior baselines), not this diff.

## Smells
- None introduced. The hook's inline rationale comment (~L31-35) was correctly rewritten to drop the deleted-extraction-path reference (EA-001 cleanup) while keeping `set -f` + `LC_ALL=C` directives.

## Test Suite
Full `commands.test` suite: **PASS (exit 0)**. Key impacted files: test-sensitive-file-guard 205/0, test-sfg-doc-coherence 130/0, test-harness-fingerprint 119/0, test-semi-auto-mode 204/0, test-hook-sync 0 fail, test-architecture-drift 0 fail.

Test-count consistency: `find tests` = 103, CONTRIBUTING.md claims 103, AGENT_CONTEXT.md = 103 — consistent (the spec's planned 103→102 decrement was offset by the newly-added `test-sfg-doc-coherence.sh`, net unchanged; the drift test compares claimed-vs-actual and passes).

## Spec Updates
- 1 spec update recorded (`spec_updates: 1`): a from-`tdd-tests` revert ("review complete, awaiting user go-ahead") — workflow bookkeeping, not a rule change.

## Overall: PASS with 0 BLOCKING findings

All 13 spec rules covered, full suite green, architecture coherently amended, mirror in sync (the one-line `# Rule:` difference is the intentional sync.sh transformation). One deferred non-blocking finding (MA-DEFER-001, a pre-existing vacuous assertion in `test_da004_hook_allowlist_sync`, independent of this feature).
