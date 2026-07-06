# Verification: Decouple the test-count invariant from the INV-010-protected doc (#219, Option 2)

**Feature slug**: agent-context-count-sync
**Branch**: feature/agent-context-count-sync-affordance
**Intensity**: high
**Verified**: 2026-07-06
**Mode**: autonomous (/cauto pipeline)

## Rule Coverage

| Rule | Test(s) | Status | Notes |
|------|---------|--------|-------|
| INV-001 (deterministic/idempotent artifact) | test-gen-test-inventory.sh | covered | double-run: sha256 + inode/mtime unchanged + `no change` token asserted |
| INV-002 (single shared count command; pinned root/universe) | test-gen-test-inventory.sh, test-ap031-fixture-divergence.sh | covered | resolver-context tests; R-006(c) negative (no other counting primitive); env-pin (env -i) tests |
| INV-003 (generator contract: atomic write, tri-state, fail-loud) | test-gen-test-inventory.sh | covered | all 3 exit states; forced-failure → non-zero + FAILED token + unchanged target + no orphan temp |
| INV-004 (R-006(c) checks artifact == actual, fail-closed) | test-gen-test-inventory.sh, test-test-inventory-wiring.sh, test-ap031-fixture-divergence.sh | covered | full matrix: current→PASS (generator-produced fixture), stale/missing→FAIL, ≥4 malformed shapes + jq-absent, each with remediation string |
| INV-005 (INV-010 unchanged; artifact unprotected) | test-test-inventory-wiring.sh | covered | resolved SFG effective-set check (not just DEFAULTS absence); tracked+not-ignored |
| INV-006 (consumer-scoped, ordered, exit-checked wiring) | test-test-inventory-wiring.sh | covered | real-git mechanism repro (#219): positive arm (correct order→green), negative arm (regen-before-stage→FAIL, ordering load-bearing), consumer-absent no-op; block-scoped ordering assertions |
| INV-007 (AGENT_CONTEXT row informational + pointer, un-scraped) | test-test-inventory-wiring.sh | covered | positive structural test: row starts with `~`, has `test-inventory.json` pointer (MA-H2); no-scrape assertion |
| INV-008 (distribution parity) | test-test-inventory-wiring.sh | covered | sync.sh --check green; no correctless/tests/ mirror of artifact/consumer |
| INV-009 (allowed-tools coverage + Group B unchanged + naming) | test-test-inventory-wiring.sh | covered | glob-covers-invocation for both installed+source forms; Group B disallowed-tools intact |
| PRH-001 (tracked + PR-reaching) | test-test-inventory-wiring.sh, test-gen-test-inventory.sh | covered | ls-files tracked + not-ignored + not under stripped prefixes |
| PRH-002 (no INV-010 relaxation) | test-test-inventory-wiring.sh | covered | behavioral: AGENT_CONTEXT staged → abort; artifact staged → allowed |
| PRH-003 (no divergent count command) | test-ap031-fixture-divergence.sh, test-gen-test-inventory.sh | covered | R-006(c) calls `count`; negative: no other primitive; behavioral parity |
| PRH-004 (deterministic artifact) | test-gen-test-inventory.sh | covered | double-run test (see INV-001) |
| BND-001 (artifact absent) | test-gen-test-inventory.sh | covered | fail-closed with remediation |
| BND-002 (artifact malformed, enumerated) | test-gen-test-inventory.sh | covered | all enumerated shapes incl. fractional/string/schema |
| BND-003 (count decrement) | test-gen-test-inventory.sh | covered | deletion → N-1 → PASS |

**All spec rules covered. Zero UNCOVERED, zero weak, zero wrong-level.** Integration-tagged rules (INV-004, INV-005, INV-006, INV-008) are tested via real-git-fixture mechanism tests, not unit stubs.

### Live parity check
- Artifact `tests/test-inventory.json` = `{"schema_version": 1, "test_file_count": 110}`
- `gen-test-inventory.sh count` = 110; `git ls-files --cached` direct-child `tests/test*.sh` = 110; working-tree find = 110. All consistent.

## Dependencies
- No package manifests changed (bash project; no package.json/go.mod/etc.). No new dependencies.
- Runtime tools used by the generator (git, awk, mktemp, mv, jq) are all pre-existing project dependencies (EA-001); generator fails loud if any are missing.

## Architecture Adherence

- ABS-048 (generated count artifact): **not yet present** — this is expected. Per the spec's ABS-048 deliverable block and the pipeline plan, the ABS-048 entry is added by the upcoming `/cupdate-arch` phase, not by /cverify. No stale reference to ABS-048 exists in ARCHITECTURE.md yet, so no path-missing/test-ID finding.
- No existing ABS/PAT/TB/ENV entry's `Enforced at`/`Test` paths overlap with this feature's changed files in a way that invalidates the entry. The feature adds a new abstraction rather than modifying an enforced one.
- INV-010 (cchores skill invariant) is a skill-level rule, not a registered architecture TB; INV-005 structural test confirms it is byte-unchanged.

0 entries stale, 0 path-missing.

### Drift Debt
- `.correctless/meta/drift-debt.json`: 8 items, all `resolved`/`wont-fix`. No open items reference this feature's rules (INV-001..009) or changed files. Drift-debt surfacing dormant for this feature.

## QA / Mini-Audit Class Fixes Verified
- QA-001 (INV-003 fail-loud on suppressed git error): fixed — `set -o pipefail` + `_fail` on non-zero git exit. Verified in `_compute_count`.
- QA-002 (INV-006 source-form fallback pre-install): fixed — all 3 skill wirings carry both installed and source `bash …gen-test-inventory.sh write` literal forms inside the consumer guard. Verified in cchores/ctdd/cdocs SKILL.md.
- QA-003 / MA-H2 (INV-007 row conversion): fixed — AGENT_CONTEXT.md Tests row now `~110 test scripts (authoritative count: tests/test-inventory.json...)`. Positive structural test added.
- MA-H1 (INV-002 NUL-safety): fixed — count uses `awk 'BEGIN{RS="\0"}'` with `/^tests\/test[^/]*\.sh$/` record filter; no `tr '\0' '\n'` linearization. Class test (embedded-newline fixture) present.
- MA-M1..M4, MA-L1..L5, MA-R2-001: all fixed (see qa-findings JSON). MA-R2-002 accepted (fail-consistent, dev-only).
- Class fixes (structural tests, not just instance patches): INV-006 mechanism repro, INV-007 positive row test, INV-002 env-pin regression test, single-document jq guard — all present in the test suite.

## Antipattern Scan
`scripts/antipattern-scan.sh main`: 54 findings, 0 scanner errors.
- **On this feature's files**: 7 LOW, all `debug-echo` false positives in test files (section-header echoes and fixture-generated `pass()/fail()` helper strings). Benign — standard test-harness pattern.
- **47 HIGH**: all on pre-existing scripts NOT touched by this feature (auto-policy.sh, budget-check.sh, decision-routing.sh, override-scrutiny.sh, security-scan.sh, etc.). Pre-existing tech debt, not attributable to this feature.
- Zero HIGH findings on the new generator or wiring.

## Smells
- None material. `scripts/gen-test-inventory.sh` has no TODO/FIXME/HACK (the one grep hit is the `mktemp XXXXXX` template, not a HACK marker). No debug statements, no commented-out code, no overly-broad catches.

## Drift
- None found. Code uses the abstractions the spec pins (shared count command, index universe, two-layout resolver, atomic dotfile temp). No code path outside spec coverage. All `implemented_in` targets exist.

## Spec Updates
- 0 spec updates during TDD (`spec_updates: null` in workflow state).

## Test Results
- Three feature suites: test-gen-test-inventory.sh (59 pass / 0 fail / 1 skip), test-test-inventory-wiring.sh (29 pass / 0 fail), test-ap031-fixture-divergence.sh (42 pass / 0 fail).
- Full `commands.test` suite: PASS (recorded in test-success sentinel).
- `sync.sh --check`: green.

## Overall: PASS — 0 findings (0 BLOCKING, 0 HIGH attributable to feature)

All 16 spec rules covered with strong (non-weak) tests. Class fixes structurally enforced. ABS-048 correctly deferred to /cupdate-arch. Ready to advance done → verified.
