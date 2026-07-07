# Verification: /cchores Protected-File Affordance (PRH-003 v2)

- **Task**: cchores-protected-affordance
- **Branch**: feature/cchores-protected-affordance
- **Intensity**: high (recommended: high; no override)
- **Verified**: 2026-07-06 (autonomous, /cauto pipeline)
- **Verifier lens**: did the implementation satisfy the spec, or only the test cases?

## Rule Coverage

All 15 invariants and 3 prohibitions are referenced by name in `tests/test-cchores-protected-affordance.sh` and probe real deliverables (the real hook over `git init` fixtures, the real `chores-authorize.sh` writer, the real `cchores-diff-check.sh`/`cchores-emit.sh`). No uncovered rules.

| Rule | Test cells (representative) | Status | Notes |
|------|------|--------|-------|
| INV-001 Mode-gated activation | writer `--issue` contract; no-arg tripwire | covered | structural leg = writer refuses without `--issue`/branch match |
| INV-002 Branch+file-scoped allowlist | INV-002-a..i (incl. AP-035 cross-worktree cell, INV-002-i custom-overlap) | covered | real-marker fixture; QA-006/MA-012 hardened custom_patterns overlap |
| INV-003 Secret-class hard floor | credentials.json, id_rsa, `secrets/../.env`, uppercase ID_RSA w/ valid marker | covered | floor checked first, deny-first |
| INV-004 Marker provenance | agent frontmatter allowlist (glob-coverage) + DEFAULTS membership | covered | MA-010 corrected vacuous parenthesized-only grep |
| INV-005 Marker lifecycle / run_id | QA-003-a/b/c two-run replay; run_id mismatch → BLOCK | covered | crash-window honestly scoped (MA-011); see Open Items (QA-004) |
| INV-006 Pre-selection SFG check | mode × {infra,secret} via `cchores-diff-check.sh --mode` | covered | advisory; INV-007 is authoritative |
| INV-007 Post-cdebug diff gate | {explicit,no-arg} × {affordance,out-of-scope,secret-floor,shared-doc} | covered | QA-005 made every abort path exit non-zero (fail-closed) |
| INV-008 3-way DEFAULTS classification | anchored-parse structural + runtime allow/deny cells (untagged→BLOCK) | covered | single-source tags; QA-001 deleted the duplicate mirror |
| INV-009 Floor-immutability | set-equality over anchored classification; anchor-moved→abort | covered | leg (b) trust-dep closure is corollary of `# other-floor` |
| INV-010 PR review banner | `cchores-emit.sh` base + escalated guard-self-edit banner | covered | unit-tested against real emitter |
| INV-011 Marker parse fails closed | behavioral trigger enumeration (git absent, detached, bare, corrupt marker/manifest) + guard-pattern lint | covered | exits ∈ {0,2} on every failure path |
| INV-012 Skill↔hook handshake | `check-capability` behavioral probe; degrade cells | covered | MA-009 extended to probe cchores-diff-check.sh presence |
| INV-013 Legible failure messages | per-leg block messages; additive AP-037 signpost (MA-002/005/007) | covered | remediation is achievable (`/cchores <N>`, no path arg) |
| INV-014 Marker sole-writer | DEFAULTS three-form + registry + disallowed-tools frontmatter | covered | QA-002 moved marker exclusion to real disallowed-tools |
| INV-015 Test-substrate fidelity | real-marker fixture; no-arg golden regression; script count-parity | covered | shared `setup_git_test_env`; count 40==40 |
| PRH-001 No affordance in no-arg | golden byte-identity + behavioral abort | covered | |
| PRH-002 Never relaxes floor/custom/guards | INV-003/008/009/014 cells | covered | |
| PRH-003 Never merge / ≤1 comment | inherited cchores tests | covered | unchanged |

## Dependencies

No package-manifest changes (bash project). One new runtime dependency introduced by design: the hook now calls `git` on the affordance path (EA-006). Guarded (`2>/dev/null || true`) so absence → BLOCK; the 99% non-affordance path is unaffected. This is specced, not undocumented.

## Architecture Adherence

All affected entries validated. Enforced-at and Test paths exist on disk; sync mirror parity holds.

- ABS-045: valid — capability boundary rewritten (Capability→conditional-allow, TWO non-strict postures, Violated-when updated); See-links ABS-029/030/042/047/027/035 present with the "exception is none under conservative set" note.
- ABS-049: valid — new entry present in `.correctless/ARCHITECTURE.md` index + full body in `docs/architecture/abstractions.md`; Enforced-at paths (hook, chores-authorize.sh, cchores-diff-check.sh, cchores-emit.sh, sanctioned-chores-writers.tsv, SKILL.md, both rule files) all exist; Test path exists and references INV-001..015/PRH-001..003.
- PAT-001 (`.claude/rules/hooks-pretooluse.md`): valid — second carve-out added, worded to NOT loosen clause 5 (every failure/ambiguity path stays exit-2), cross-links INV-011.
- `.claude/rules/sfg-deliverable.md`: valid — `chores-authorize.sh` (three-form) added to the "When this rule applies" enumeration.
- SFG capability sentinel `# SFG_AFFORDANCE_VERSION: 1` present in the hook.

`0 stale entries, 0 drift-debt items.`

### Drift Debt
None created.

## QA Class Fixes Verified

- QA-001: `_SFG_LEGACY_EXACT_LINE_MIRROR` deleted; single-source tagged DEFAULTS; 4 sibling matchers retargeted to strip the tag suffix — verified in the hook and in test-meta-record/test-sensitive-file-guard/test-fix-diff-reviewer/test-audit-findings-persistence. Structural test enforces "protected set defined exactly once." ✓
- QA-002: marker exclusion moved to the real `disallowed-tools` frontmatter; INV-014-c parses the field, not a whole-file grep. ✓
- QA-003: `do_write` always mints a fresh run_id; `do_clear` rotates run_id out of the manifest; two-run replay regression present. ✓
- QA-005: every `do_diff_check` abort path returns non-zero (uniform fail-closed coded-gate contract) + structural awk lint. ✓
- QA-006 / MA-012: custom_patterns forced to floor in the affordance ALLOW branch, incl. wrong-type (non-array) config degrade → fail-closed. ✓
- MA-001: shared `require_canonicalize_or_die` guards both the hook STEP-4a and cchores-diff-check.sh against a missing/stale lib.sh (fail-closed exit 3). ✓

## Antipattern Scan

`bash .correctless/scripts/antipattern-scan.sh main` — all findings are known by-design false positives inherent to a PreToolUse security hook, not defects:

| Finding class | Lines | Disposition |
|---|---|---|
| error-suppression `\|\| true` | correctless/hooks/sensitive-file-guard.sh 427/445/550 | REQUIRED fail-closed guards on git/jq/lib reads (INV-011 / EA-002 — the guard is load-bearing) |
| debug-echo | correctless/hooks/sensitive-file-guard.sh (block-message lines) | INV-013 legible block messages to stderr, not debug output |

No actionable antipattern findings.

## Smells

None. No TODO/FIXME/HACK, debug statements (the flagged echoes are block messages), or commented-out code introduced.

## Drift

None found. Code uses the abstractions the spec specifies (single-source tag classification, shared `canonicalize_path`/matcher primitive, coded diff-check gate, sanctioned writer).

## Spec Updates

INV-005 Enforcement wording was scoped during the mini-audit (MA-011) to "inert against a later /cchores run" and to name the crash-window as an accepted residual (documentation/honesty change, no mechanism change). Workflow state carries no `spec_updates` counter for this run.

## Test Suite

Full suite (`commands.test`, 111 files) green after regenerating the stale `tests/test-inventory.json` (count 110→111 — the feature added `test-cchores-protected-affordance.sh`; INV-015 count-parity artifact was not regenerated during TDD; fixed here via `bash scripts/gen-test-inventory.sh write`). One transient failure in `tests/test-lib-locking.sh` under loaded parallel scheduling; passes cleanly in isolation (28/0). It is the known-flaky flock concurrency stress test, unrelated to this feature (the only lib.sh change is the `require_canonicalize_or_die` helper). test-success sentinel recorded at HEAD.

## Open Items (escalated — human review)

- **QA-004 (UNCERTAIN, ESCALATED)**: The cheap path-alignment is done — `chores-authorize.sh` and the hook now derive the run-manifest filename via `branch_slug()` (matching `/cchores`'s real `chore-run-{branch_slug}.json`), and `do_write` MERGES `run_id` clobber-safely. The deferred, architectural part: `/cchores`'s documented INV-007 manifest schema in `skills/cchores/SKILL.md` (`{schema_version, selected_issue, status, attempts, ...}`) does not declare a `run_id` field, and minting ownership is unratified. Human decision needed: (1) document `run_id` in the INV-007 schema and assign minting ownership to `/cchores`, or (2) ratify `chores-authorize.sh` as the `run_id` owner and document that in INV-007 + INV-005. The affordance works and binds to the correct file today; only the cross-skill schema contract is undocumented. Non-blocking for this feature's rule coverage; carried forward for human adjudication.

## Overall: PASS — 0 uncovered rules, 0 outstanding BLOCKING findings (QA-001 fixed), 1 escalated cross-skill schema item (QA-004) for human review.
