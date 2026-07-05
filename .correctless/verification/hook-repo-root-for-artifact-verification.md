# Verification: audit-trail file-repo attribution (narrowed #244)

Spec: `.correctless/specs/hook-repo-root-for.md` — Intensity: high (fail-open telemetry, deliberately small)
Branch: `feature/hook-repo-root-for-artifact` — Phase: done — QA rounds: 2
Verified: 2026-07-05

## Rule Coverage

| Rule | Test(s) | Status | Notes |
|------|---------|--------|-------|
| R-001 (local resolver, no hardening) | R-001-in-repo, R-001-non-repo, R-001-nearest | covered | Functional: evals extracted `_resolve_file_repo` body against two real `git init` repos; cwd=A resolves `$B/f`→B, non-repo→rc1, nonexistent leaf→nearest ancestor |
| R-002 (attribute to F; no-op otherwise) | R-002-cell1, R-002-cell2, R-002-cell3, R-002-adh | covered | Full 3-cell matrix over real repos + `.branch` field assertion. Adherence cell uses A=low/B=high (QA-003) to prove config read from F, not cwd |
| R-003 (branch from F, empty→cwd guard) | R-003, R-003-noleak | covered | Detached-HEAD B → no attribution under cwd/A AND nothing written under B (QA-002 class fix) |
| R-004 (same-target for cwd==F) | R-004 | covered | Same inode assertion (not string equality), both runs append to R's trail |
| R-005 (fail-open preserved) | R-005a, R-005b, R-005c | covered | corrupt state→exit0; git PATH-absent→exit0/no-stderr; no-repo file→exit0/no-misattribution |
| R-006 (cross-repo MultiEdit per target) | R-006, R-006-nested, R-006-newline | covered | Grouped/ordered per repo; nested-repo (QA-001) lands innermost; newline injection (MA-001) no-ops |
| R-007 (Bash target == Edit target) | R-007 | covered | Bash `touch $B/foo.sh`→B, cross-checked against Edit to same path |
| R-008 (resolver local, not lib.sh; hook not SFG-protected) | R-008-local, R-008-notlib, R-008-unprotected | covered | Structural greps: defined in audit-trail.sh, absent from lib.sh, absent from SFG DEFAULTS |

All 8 rules covered. No uncovered rules. No weak tests. Integration-tagged rules (R-002..R-007) use real `git init` fixtures (AP-031 / spec R-3), tested at integration level.

Test result: `tests/test-audit-trail.sh` 29 passed / 0 failed. Full suite (`commands.test`): all test files green (exit 0). Pre-existing INV-015 session-field tests preserved (additive; diff only appends after line 188).

## Dependencies
No package-manifest changes (bash-only project). No new dependencies.

## Architecture Adherence

- ABS-001 (shared script library): valid — audit-trail.sh still sources `scripts/lib.sh` and uses shared `branch_slug`, `get_target_file`, `classify_file`. New `_resolve_file_repo` is deliberately local (R-008) — a documented, accepted ABS-001 deferral (duplicates #242's walk idiom in workflow-gate.sh; dedup to `try_repo_root_for` in lib.sh is a tracked follow-up).
- PAT-005 (PostToolUse hook conventions): valid — no `set -euo pipefail`; `command -v jq … || exit 0` (fail-open, not exit 2); guards degrade to exit 0; final `exit 0`. The R-1-accepted change (stdin parse + resolve F before the artifacts-dir fast-path) is spec-documented; latency is bounded (memoized `git rev-parse` per unique nearest-existing dir), fail-open, correctness-preserving.

No ARCHITECTURE.md entry references `audit-trail.sh` by path; no entry's Enforced-at/Test path was invalidated. Mirror `correctless/hooks/audit-trail.sh` is byte-identical to `hooks/audit-trail.sh` (in sync).

### Drift Debt
`.correctless/meta/drift-debt.json` — no open items referencing this feature. (none)

## QA / Mini-Audit Class Fixes Verified
- QA-001 (nested-repo misattribution): FIXED — `_resolve_cached` memoizes by nearest-existing directory (per-dir git authority returns innermost repo), replacing the prefix-cache. Class test `R-006-nested` (real parent+nested `git init`, parent-file-first) present and passing. ✓
- QA-002 (no-op contract only asserted one sink): FIXED — `R-003-noleak` asserts B's trail is empty too. ✓
- QA-003 (both-high adherence fixture masks F-vs-cwd config): FIXED — `R-002-adh` uses A=low/B=high. ✓
- MA-001 (hostile-input newline/TAB cross-repo forge): FIXED — delimiter-collision guards at the pre-split boundary (non-MultiEdit newline/TAB → exit 0) and at the PAIRS buffer boundary (skip pathological pairs). Class test `R-006-newline` present and passing. ✓
- Accepted (non-gating, documented): QA-004/QA-005, MA-002..MA-007 — all LOW/NON-BLOCKING, mostly doc-note follow-ups and pre-existing out-of-scope items (token-tracking.sh cwd attribution divergence, Bash get_target_file not write-aware). None are BLOCKING.

## Smells (Antipattern Scan)
Scanner reported findings on audit-trail.sh: error-suppression (`|| true`, `2>/dev/null`) at lines 159/205/285/336 and debug-echo at the `echo ⚠/📝/🔍 … >&2` adherence alerts. These are the standard PostToolUse fail-open idioms (PAT-005 mandates them) and the hook's intentional adherence-feedback output — pre-existing to this hook class, not regressions introduced by this feature. No TODO/FIXME/HACK, no commented-out code introduced.

## Drift
None found. Code uses the abstractions the spec prescribes (lib.sh shared functions retained; local resolver per R-008). No spec rule's `implemented_in` target is missing.

## Spec Updates
Spec was re-scoped once during authoring (v5 protection-perimeter edifice → narrow audit-trail attribution fix, per PMB-020/AP-040 mechanism-honesty). No further spec updates during TDD.

## Overall: PASS — 0 BLOCKING findings

All 8 rules covered by real-fixture tests, full suite green, mirror in sync, QA/mini-audit class fixes implemented with class-level regression tests, architecture (ABS-001/PAT-005) honored. Feature is fail-open telemetry with no security dimension; residual findings are all accepted LOW/NON-BLOCKING doc-note follow-ups.
