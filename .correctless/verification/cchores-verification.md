# Verification: /cchores — Autonomous Issue-Resolution Pipeline

**Verified**: 2026-06-17 · **Intensity**: high · **Branch**: feature/cchores · **Phase**: done (pipeline)
**Verifier lens**: did the implementation satisfy the spec, or merely the test cases?

## Rule Coverage

All 19 invariants, 4 prohibitions, 3 boundary conditions have ≥1 referencing test. Spot-checked the
highest-risk security rules (INV-001/003/006/009/010/013/017) for non-triviality — each test would fail
if the rule were violated (not trivial assertions).

| Rule | Test | Status | Notes |
|------|------|--------|-------|
| INV-001 (explicit-invocation positive gate) | test-cchores.sh | covered | manifest-sourced routing + denylist |
| INV-002 (highest-severity suitable selection) | test-cchores.sh | covered [int] | pagination/RS-028 guard asserted |
| INV-003 (suitability gate, injection-resistant) | test-cchores.sh | covered [int] | verdict tripwire + read-only frontmatter |
| INV-004 (idempotent, exact-ref match) | test-cchores.sh | covered [int] | QA-001 `--limit 100` guard added |
| INV-005 (fresh-default branch, ahead-guard) | test-cchores.sh | covered [int] | dirty/ahead/resolution-disagree fixtures |
| INV-006 (/cdebug autonomous contract a–f) | test-cdebug-autonomous.sh | covered [int] | per-phase mode-guard co-occurrence + non-regression |
| INV-007 (chore-run manifest, ABS-043) | test-cchores.sh | covered [int] | consumer (/cstatus) wired |
| INV-008 (regression oracle, CI-superset) | test-cchores-regression-oracle.sh | covered [int] | real-output fixture + empty-diff abort |
| INV-009 (nonce-fence, untrusted issue) | test-cchores-fence.sh, test-cchores.sh, test-cdebug-autonomous.sh | covered [int] | sentinel-effect + nonce-variance + hop survival |
| INV-010 (scoped honest PR, diff-verified) | test-cchores.sh, test-cdebug-autonomous.sh | covered [int] | QA-002 Phase-5 suppression guard |
| INV-011 (fail-closed abort, persist-first) | test-cchores.sh, test-redact-secrets.sh | covered [int] | local-store-before-comment ordering |
| INV-012 (autonomous decisions logged, ABS-030) | test-cchores.sh, test-cchores-infra.sh, test-autonomous-skill-contract.sh | covered [int] | R-006d allowlist + write-through assertion |
| INV-013 (outbound redaction, all sinks) | test-redact-secrets.sh, test-cchores-emit.sh, test-cchores.sh | covered [int] | per-pattern enumeration + fail-closed + 4-sink |
| INV-014 (distribution + docs parity) | test-cchores.sh | covered [struct] | byte-equality + count surfaces |
| INV-015 (shared global worktree lock) | test-cchores.sh, test-cchores-infra.sh | covered [int] | cross-skill mutual-exclusion + stale recovery |
| INV-016 (run report + /cstatus surfacing) | test-cchores.sh | covered [int] | every-terminal-state report |
| INV-017 (tool allowlist + push-branch guard) | test-cchores.sh | covered [struct+int] | pinned gh subcommands + protected-branch refusal |
| INV-018 (charset-bounded slug) | test-cchores.sh | covered [int] | QA-005 empty-slug fallback fixture |
| INV-019 (cross-run re-selection store, ABS-044) | test-cchores.sh | covered [int] | aborted-issue skipped next run, no marker comment |
| PRH-001 (no PR on unverified/regressing/CI-dirty) | test-cchores.sh, test-cchores-regression-oracle.sh | covered | per-failure-mode |
| PRH-002 (no action on observed content) | test-cchores.sh | covered | injection sentinel + denylist |
| PRH-003 (no SFG auto-lift in v1) | test-cchores.sh | covered | pre-selection + post-cdebug diff check |
| PRH-004 (no merge/close/relabel) | test-cchores.sh | covered | INV-017 structural allowlist |
| BND-001 (issue ingestion) | test-cchores.sh | covered | fail-closed empty/oversized |
| BND-002 (preflight env validation) | test-cchores.sh, test-cchores-regression-oracle.sh | covered | empty test_fail_pattern → preflight abort |
| BND-003 (empty candidate set, non-silent no-op) | test-cchores.sh | covered | manifest+report on no-op |

**0 uncovered rules. 0 weak. 0 wrong-level.** Integration-tagged rules are tested via stubbed `gh`/`git`
fixtures driving real script paths, not unit-shaped greps.

## Dependencies
- None added. Bash/POSIX project; no `package.json`/`go.mod`/etc. changed.
- New bundled data file `templates/secret-patterns.txt` (POSIX-ERE pattern set, INV-013 fallback) — in-repo, not an external dependency.

## Architecture Adherence

5 entries authored/revised during the build; all affected by the feature diff.

- TB-009 (untrusted issue content → autonomous orchestrator): valid — full TB field set + stronger no-human-checkpoint acknowledged-gap; Enforced-at/Test paths exist; drift test green.
- TB-004d (autonomous issue-selection authority): valid — scoped sub-boundary widening TB-004 with revisit constraint; covered via INV-002/003/012/019 (no literal `TB-004d` token in test, see advisory below).
- ABS-043 (chore-run manifest, .correctless/artifacts/): valid — sole-writer `/cchores`, consumer `/cstatus`, all Enforced-at paths exist.
- ABS-044 (cross-run re-selection store, .correctless/meta/): valid — sole-writer via `locked_update_file`, gitignored/durable, prune-exempt.
- ABS-030 (revision): valid — sole-writer wording correctly changed to "the `scripts/autonomous-decision-writer.sh` script, invoked by `/cauto` OR `/cchores`"; R-006d allowlist adds `cchores` (test-autonomous-skill-contract.sh: 76 passed).

`tests/test-architecture-drift.sh`: 111 passed, 0 failed (enumerates `TB-[0-9]+`/`ABS-[0-9]+` coverage).

**Advisory (MEDIUM, non-blocking, for /cdocs):** TB-004d's `Test` field cites `tests/test-cchores.sh (INV-002/003/012/019)`
but no test references the literal `TB-004d` ID. Coverage is real (via the named INVs) but indirect. Consider adding a
`# TB-004d` comment marker to one selection-authority test so the boundary ID is greppable. Not a coverage gap — the
behavior is tested; only the ID-traceability link is implicit.

5 entries checked, 0 stale, 0 path-missing, 0 drift-debt items.

### Drift Debt
- None. No open drift-debt items reference cchores files or the 5 entries.

## QA Class Fixes Verified
- QA-001 (INV-004): `gh pr list --limit 100` + truncation guard → structural test INV-002e/f present ✓ (class: no un-limited `gh list` reaches a gating decision)
- QA-002 (INV-010): /cdebug Phase-5 antipatterns.md write mode-gated → test-cdebug-autonomous.sh asserts Write-bearing phase co-occurs with mode guard ✓
- QA-003 (INV-013): JWT floor restored to spec-pinned `{8,}`; fixture corrected ✓
- QA-005 (INV-018): empty-slug fallback for pure-unicode/punctuation titles → INV-018e behavioral fixture present ✓
- QA-006 (INV-008): `--diff <range>` made load-bearing in coded oracle (aborts on empty-resolving range) → F-DIFF-EMPTY test present ✓
- QA-004 (INV-009): DEFERRED — `agents/cdebug-fix.md` unconstrained Bash. Legitimate human-review tool-surface decision (debugging agent needs varied repro commands). Carried to pipeline-end escalation, not a /cverify blocker.

## Mini-Audit Class Fixes Verified
- MA-S1 (INV-009): coded fence-builder `scripts/cchores-fence-issue.sh` (was prose-only) → test-cchores-fence.sh 21 passed ✓
- MA-S2 (INV-013): coded egress chokepoint `scripts/cchores-emit.sh` (multi-line/PEM-safe) → test-cchores-emit.sh 13 passed ✓
- MA-S3 (INV-013): `setup` installs secret-patterns.txt + gitignore entries → test-cchores-infra.sh ✓
- MA-S7 (INV-013): redactor fails closed on non-ERE/PCRE patterns (gitleaks dialect mismatch) → redact-secrets.sh STEP 3b + test-redact-secrets.sh ✓

## Antipattern Scan
`scripts/antipattern-scan.sh main` — 275 findings (mirror-duplicated: `scripts/` + `correctless/scripts/`), 0 scanner errors.

| Pattern | Sev | Disposition |
|---------|-----|-------------|
| debug-echo | low | False positive — new cchores scripts write to stdout by contract (redactor/emitter/fence/selector all have "writes on stdout" APIs) |
| error-suppression | high | Concentrated in `cauto-lock.sh` (idiomatic lock `2>/dev/null`) + oracle:221 `|| true` on a redundant filter — not security paths |
| dead-security-fn | high | `prune-scan.sh` pattern-string literals matching the scanner's own rules — pre-existing, not cchores code |
| gnu-grep-ext | medium | redact-secrets.sh:131 — match is inside a COMMENT explaining the PCRE/ERE distinction, not executable code |

No actionable smells in new cchores code. Semantic ai-antipatterns checklist: no new instances.

## Smells
- None. No TODO/FIXME/HACK in new scripts; no commented-out code; no hardcoded secrets (the redactor is the point).

## Drift
- None found. Code uses the spec's abstractions: coded fence (INV-009), coded redactor chokepoint (INV-013),
  shared `worktree.lock` via `cauto-lock.sh` (INV-015), `locked_update_file` for the re-selection store (INV-019),
  `branch_slug()` for manifest naming (INV-007). No spec rule references a missing file/function.

## Spec Updates
- Spec frozen at review round 4 (5 consistency findings folded). No TDD-phase spec edits recorded
  (workflow state `spec_updates` absent → 0).

## Test Suite Summary
- test-cchores.sh: 204 passed, 0 failed, 1 skipped
- test-cchores-emit.sh: 13 passed
- test-cchores-fence.sh: 21 passed
- test-cchores-infra.sh: 30 passed
- test-cchores-regression-oracle.sh: 41 passed
- test-redact-secrets.sh: 36 passed
- test-cdebug-autonomous.sh: 36 passed
- test-architecture-drift.sh: 111 passed
- test-autonomous-skill-contract.sh: 76 passed
- **Total: 568 passed, 0 failed, 1 skipped**

SFG-lift sentinel: absent (clean). `check-no-pending-sfg-lift.sh`: rc=0.

## Overall: PASS with 1 advisory (MEDIUM, non-blocking)

All 26 spec rules covered with substantive tests. All BLOCKING QA/mini-audit findings fixed and verified.
Architecture entries valid. No drift, no dependency surprises, no actionable antipattern findings in new code.
The single advisory (TB-004d ID-traceability) is for /cdocs prioritization and does not gate advancement.
QA-004 (cdebug-fix Bash scope) remains a deferred human-review tool-surface decision.
