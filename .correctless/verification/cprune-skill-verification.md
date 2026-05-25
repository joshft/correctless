# Verification: Documentation and Artifact Pruning Skill (/cprune)

## Rule Coverage
| Rule | Test | Status | Notes |
|------|------|--------|-------|
| INV-001 | INV-001-a,b,c | covered | Mode detection logic verified in SKILL.md |
| INV-002 | INV-002-a,b,cat-*,f1-f7,lib,e,e2 | covered | 21 tests: JSON output, required fields, lib.sh sourcing, error handling |
| INV-003 | INV-003-a,b,c,d,e,f,g,h,real,types | covered | 10 tests: dead/live refs, prose entries, backtick paths, Enforced-at, See-links, Test fields, sub-entries, real ABS-001 entry (AP-031), PAT/TB/ENV types |
| INV-004 | INV-004-a,b,c | covered | Archive file references in SKILL.md |
| INV-005 | INV-005-a,b,c,d | covered | Orphaned artifact detection, --branches-file, risk classification |
| INV-006 | INV-006-a,a2,b,c | covered | Count mismatch detection, correct counts not flagged, label-anchored matching |
| INV-007 | INV-007-a,a2,b | covered | Cross-reference staleness, does not cause archiving |
| INV-008 | INV-008-a,a2,b,c,d,e,f | covered | Learning staleness, general-principle exclusion, Convention confirmed/introduced/Postmortem exclusion, body text "always"/"All" does not prevent flagging |
| INV-009 | INV-009-a,b,c | covered | Merged branch 30+ days flagged, unmerged not flagged, fail-closed on missing date |
| INV-010 | INV-010-a,a2,b,c | covered | Dead source_file flagged, non-open skipped, risk classification |
| INV-011 | INV-011-a,b,kw-*,c | covered | Instance vs class-level AP detection, all class keywords, body text "All" |
| INV-012 | INV-012-a,b | covered | /cauto references cprune, not in canonical step enum |
| INV-013 | INV-013-a,b,c,d,e | covered | /cstatus pruning signal, threshold values, dormant behavior |
| INV-014 | INV-014-a,a2,b,c | covered | Resolved drift debt >90 days, wont-fix, open not flagged, <90 days not flagged |
| INV-015 | INV-015-a,b | covered | Persist-before-present artifact reference |
| INV-016 | INV-016-a,b,c,d,e | covered | SFG protects all 5 required paths |
| INV-017 | INV-017-a,b,c | covered | /cauto consolidation allowlist includes all 3 archive files |
| INV-018 | INV-018-a,b,c,d,e | covered | Progress display, disposition options, un-archive documentation |
| INV-019 | INV-019-a,b | covered | sync.sh includes cprune, says 32 skills |
| PRH-001 | PRH-001-a | covered | Archive-before-remove ordering |
| PRH-002 | PRH-002-a | covered | CLAUDE.md excluded from autonomous mode |
| PRH-003 | PRH-003-a | covered | Entry with live refs not flagged |
| PRH-004 | PRH-004-a | covered | No Write access to deferred-findings.json |
| BND-001 | BND-001-a | covered | Archive file creation with header |
| BND-002 | BND-002-a,b | covered | bulk_warning true >50%, false <50% |
| BND-003 | BND-003-a | covered | Scanner works with no remote |
| BND-004 | BND-004-a,b | covered | Lockfile references |
| ABS-038 | ABS-038-a,b,c,d | covered | Sole-writer declaration, allowed-tools for all 3 archive files |
| DET-001 | DET-001 | covered | Scanner determinism |
| EDGE-001-003 | EDGE-001,002,002b,003 | covered | Invalid category, empty ARCHITECTURE.md, missing --base |

**116 tests, all passing. 0 uncovered rules.**

## Dependencies
No new dependencies introduced. The scanner script uses only bash builtins, jq (existing dependency), and git (existing dependency).

## Architecture Adherence

- ABS-038: **valid** — new entry, all paths verified on disk (skills/cprune/SKILL.md, hooks/sensitive-file-guard.sh, tests/test-cprune.sh)
- ABS-001: valid — scripts/lib.sh sourced by scanner per convention
- ABS-010: valid — no new agents introduced (scanner is a script, not an agent)
- ABS-031: valid — cprune is NOT in the canonical step name enum (verified by INV-012-b)

### AGENT_CONTEXT.md Count Drift (FINDING)

**AGENT_CONTEXT.md has 2 remaining "31 skill" references that were not updated to "32":**
- Line 13: `31 skill definitions` in the Skills table row
- Line 19: `Single 31-skill distribution target` in the Distribution table row

The spec explicitly listed "AGENT_CONTEXT.md x2" as requiring updates. The first paragraph (line 7) was correctly updated to "32 skills", but the table rows were missed.

**Severity: MEDIUM (advisory for /cdocs)**

### Drift Debt
No open drift-debt items reference files changed by this feature. All 8 existing drift-debt entries are resolved/wont-fix.

## QA Class Fixes Verified
No QA findings artifact exists for this feature (qa-findings-cprune*.json not found). The workflow state shows 2 QA rounds.

## Antipattern Scan

The deterministic scanner reports findings in `scripts/prune-scan.sh` and `hooks/sensitive-file-guard.sh`, but all are pre-existing patterns in the codebase:
- `|| true` error suppression in grep pipelines (standard project pattern for optional matches)
- `echo` statements in scanner scripts (expected for JSON output and stderr warnings)

No new antipattern classes introduced by this feature.

## Smells
- None detected. No TODO/FIXME/HACK comments, no debug statements, no commented-out code in the new files.

## Drift

### AGENT_CONTEXT.md count drift
Two references to "31 skill" remain at lines 13 and 19 of `.correctless/AGENT_CONTEXT.md`. The spec (Complexity Budget section) explicitly called for updating "AGENT_CONTEXT.md x2" -- the paragraph-level mention was updated but the two table rows were missed.

**This is a NON-BLOCKING drift item** -- the counts are advisory prose, not gating logic. /cdocs should fix this.

## Spec Updates
- No spec updates recorded during TDD (the spec was used as-is)

### AGENT_CONTEXT.md scripts inventory missing prune-scan.sh
Line 16 of `.correctless/AGENT_CONTEXT.md` lists all 24 scripts by name but does not include `prune-scan.sh`. The script exists at `scripts/prune-scan.sh` and is included in the "24 shared scripts" count (the count is correct, but the prose inventory is missing the entry). This means agents reading AGENT_CONTEXT.md for script discovery won't find the scanner.

**Severity: LOW (advisory for /cdocs)**

## Overall: PASS with 2 findings

- **1 MEDIUM finding**: AGENT_CONTEXT.md has 2 stale "31 skill" references at lines 13 and 19 (should be "32"). Non-blocking advisory for /cdocs.
- **1 LOW finding**: AGENT_CONTEXT.md scripts inventory on line 16 does not mention `prune-scan.sh`. Non-blocking advisory for /cdocs.
- **116 tests pass** across all 19 invariants, 4 prohibitions, 4 boundary conditions, 1 architecture entry, determinism, and edge cases.
- **Distribution sync is clean** (sync.sh --check exits 0).
- **All modified test suites pass**: test-cprune.sh (116/116), test-architecture-drift.sh (110/110), test-skill-path-discovery.sh (64/64), test-sensitive-file-guard.sh (168/168).
- **Independent re-verification**: 2026-05-24 — all test runs, architecture path checks, SFG coverage, frontmatter compliance (interaction_mode: hybrid, no context: fork), and allowed-tools contract independently confirmed.
