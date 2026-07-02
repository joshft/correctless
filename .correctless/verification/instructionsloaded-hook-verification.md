# Verification: InstructionsLoaded hook — direct rule-load observability for PAT-001 (Feature B / FUTURE-001)

- **Task**: instructionsloaded-hook
- **Branch**: feature/instructionsloaded-pat001-measurement-gate
- **HEAD**: 33396bc9e9d077c685293a92b157822c3066bde2
- **Intensity**: high
- **Verified by**: /cverify (autonomous, /cauto pipeline)
- **Date**: 2026-07-01
- **Full suite**: PASS (all `tests/test-*.sh` green at HEAD; sentinel `.correctless/artifacts/test-success.sha` = HEAD)

## Rule Coverage

| Rule | Test | Status | Notes |
|------|------|--------|-------|
| INV-001 fail-open | test-instructions-loaded.sh, test-ci-hook-wiring.sh | covered | empty/malformed/missing-jq/unwritable-dir/missing-lib.sh matrix; `set -f` present, `set -e` absent |
| INV-002 rule-file scope + path resolution | test-instructions-loaded.sh, test-ci-hook-wiring.sh | covered | rule-file writes; CLAUDE.md/traversal/non-rule no-write; canonicalize_path prefix-check |
| INV-003 JSONL schema | test-audit-trail.sh, test-instructions-loaded.sh, test-ci-hook-wiring.sh | covered | `jq -e .` per line, field presence, `ts` regex, no `transcript_path` |
| INV-004 safe extraction + jq -n serialization | test-instructions-loaded.sh, test-ci-hook-wiring.sh | covered | metachar literal, embedded-newline → exactly one line, jq -n grep assertion |
| INV-005 absent/malformed → null logging | test-instructions-loaded.sh, test-ci-hook-wiring.sh | covered | path_glob_match null-write vs non-reason drop |
| INV-006 registration emits entry [integration] | test-ci-hook-wiring.sh | covered | IL-INV-006: entry present, command path, type=command, matcher=`*`, timeout_ms present+positive |
| INV-007 HOOK_TYPE header + generalized type→timeout + widened grammar | test-ci-hook-wiring.sh | covered | KNOWN_HOOK_TYPES set, no bespoke case arm, no per-type literal, auto_hooks iterated, matcher grammar admits `_`/`*` |
| INV-008 /cwtf read-only present, JSONL-safe, no verdict [integration] | test-instructions-loaded-cwtf.sh, test-ci-hook-wiring.sh | covered | `fromjson? \| objects`, `.ts // .timestamp`, session grouping by edit-sessions, malformed-line skip, no MG token |
| INV-009 dormant + empty-vs-all-null | test-ci-hook-wiring.sh, test-instructions-loaded-cwtf.sh | covered | advisory line exit 0; all-null field-drift note |
| INV-010 gitignored telemetry | test-instructions-loaded.sh | covered | `git check-ignore` confirmed at HEAD |
| INV-011 append-only O(1) | test-instructions-loaded.sh | covered | behavioral: file grows by one line, first N byte-identical |
| INV-012a real payload fixture (mechanical) | test-instructions-loaded.sh | covered | key presence + round-trip through hook |
| INV-012b real payload provenance (attestation) | — (this report) | **covered here** | see "Provenance Attestation (INV-012b)" below |
| INV-013 all-seam registration [integration] | test-ci-hook-wiring.sh | covered | fresh / existing / drift-repair / regeneration + mirror parity |
| INV-014 mirror parity | test-instructions-loaded.sh + `sync.sh --check` | covered | `sync.sh --check` clean at HEAD |
| INV-015 audit-trail session_id field | test-audit-trail.sh, test-instructions-loaded-cwtf.sh | covered | session_id from harness stdin; real-fixture parse |
| INV-016 liveness / self-diagnostic | test-instructions-loaded-cwtf.sh | covered | denominator line for empty/all-null/populated |
| PRH-001 no block / non-zero | test-ci-hook-wiring.sh | covered | exit 0 across input matrix |
| PRH-002 not in SFG DEFAULTS | test-instructions-loaded.sh, test-ci-hook-wiring.sh | covered | grep confirms absence at HEAD |
| PRH-003 no re-open of measurement | — (diff check) | covered here | measurement + due files unchanged in `main...HEAD` |
| PRH-004 no gate depends on log | test-instructions-loaded.sh | covered | log path absent from workflow-advance / hooks / wf scripts |
| PRH-005 no automated MG verdict | test-instructions-loaded-cwtf.sh | covered | no `MG-001`/`MG-002` token in SKILL |

**Result: 22/22 rules accounted for, 0 uncovered, 0 weak.** INV-012b and PRH-003 are correctly not CI-enforced (attestation / diff-based) and are discharged in this report.

## Dependencies

No package-manifest changes (`git diff main...HEAD` over package.json/go.mod/Cargo.toml/requirements.txt/pyproject.toml is empty). This is a bash/markdown plugin; no new third-party dependency introduced. Runtime deps unchanged: `jq`, `git`, coreutils (all pre-existing).

## Provenance Attestation (INV-012b)

**Attested: the INV-012a fixture `tests/fixtures/instructionsloaded-real-payload.json` is genuine harness-captured, not hand-authored.**

- **Harness version**: Claude Code 2.1.185 (≥2.1.69 required by INV-012a / EA-001). ✓
- **Capture date**: 2026-07-01.
- **Capture method**: a temporary stdin-dump `command` hook was registered on the `InstructionsLoaded` event in `.claude/settings.local.json` (`matcher: "*"`), rule-governed source files were opened mid-session to trigger `path_glob_match` loads, and the emitted JSON was saved. The dump hook was de-registered immediately after capture (settings.local.json restored from backup).
- **Firing model confirmed (the make-or-break DD-004 / EA-002 confirmation)**: **per-open, first-load firing — NOT session-batched.** Opening a `.claude/rules/`-scoped source file mid-session emits a fresh `InstructionsLoaded` event with `load_reason: "path_glob_match"`, naming the opened file in `trigger_file_path` and the loaded rule in `file_path`. Observed across three triggers:
  - Reading `hooks/sensitive-file-guard.sh` → fired `hooks-pretooluse.md` load (rule not previously in context).
  - Reading `scripts/lib.sh` → fired `canonicalize-path.md` load (rule not previously in context).
  - Reading `agents/fix-diff-reviewer.md` → **no fire**, because its governing rule `sfg-deliverable.md` was already resident at session start.
  - Interpretation: the event fires when a rule *transitions into context* (first load), keyed on the trigger-file open. A rule already resident at session start does not re-fire. This strengthens the human-judged framing and is exactly why PRH-005 (no automated classifier) is correct — an automated correlator would misread an already-resident rule as "never loaded."
- **Captured field set (real 2.1.185 shape, 9 keys)**: `session_id, transcript_path, cwd, hook_event_name, file_path, memory_type, load_reason, globs, trigger_file_path`. Required-by-INV-003/INV-012a keys (`file_path`, `trigger_file_path`, `load_reason`, `session_id`) all present. Extra real-world keys validate RS-029 (assert key *presence*, not exact-key equality). `file_path`/`trigger_file_path` are absolute paths.
- **Committed-fixture policy**: the committed fixture preserves the exact 9-key set and value shapes verbatim while sanitizing personal values (placeholder UUID session_id, generic absolute paths) per repo redaction policy. The AP-031 realness property under test — field set and shapes — is preserved. CI (INV-012a) proves only schema + round-trip, never harness-origin; this attestation is the human-readable provenance.
- **Source record**: originally captured to `.correctless/artifacts/dd004-capture-record.md` (raw byte-exact capture at `.correctless/artifacts/dd004-raw-capture.json`, gitignored — retains real session_id / `/home/...` paths, never committed). This verification report is the durable in-`.correctless/verification/` copy satisfying the INV-012b attestation gate.

## EA-004 — Timeout field disposition

- **Emitted field**: `timeout_ms` (matches the existing `setup:532` convention). InstructionsLoaded flows through the generalized `_upsert_command_hook` type→timeout map: PostToolUse gets `1000`, every other type (PreToolUse, InstructionsLoaded, future types) gets `timeout_ms: 5000`. No per-type literal is duplicated (INV-007 / AP-024 / PMB-003).
- **Verified at registration (INV-006)**: `test-ci-hook-wiring.sh` IL-INV-006 asserts the registered InstructionsLoaded entry carries a `timeout_ms` field with a positive value (5000). Emission is CI-enforced.
- **Whether the harness *honors* `timeout_ms` for InstructionsLoaded — accepted latent unknown.** The live-registration capture (DD-004) did not exercise timeout behavior (the dump hook carried no timeout field), and CI cannot observe harness honoring (RS-015). Per the EA-004 disposition this is acceptable to ship as-is rather than switch to docs-`timeout` (seconds), for three reinforcing reasons: (1) InstructionsLoaded exit codes are ignored by the harness (EA-003), so the hook is fail-open and O(1)-append — a timeout is largely moot; (2) `timeout_ms` may already be silently ignored for the existing Pre/Post hooks (noted latent unknown — not a regression this feature introduces); (3) keeping one field convention across all hook types avoids a per-type field split. **Disposition: verified-at-registration (field+value emitted and asserted); harness-honoring recorded as an accepted latent unknown.**

## Architecture Adherence

Per QA-003 (status: deferred), the ARCHITECTURE.md entries for this feature are intentionally landed in **/cupdate-arch**, not in TDD. No affected ARCHITECTURE.md entry's structural claims are contradicted by the implementation. Items for /cupdate-arch to create/amend:

- **ABS-004** (amend): two-type → generalized type set — `register_hooks()` now discovers hooks via `KNOWN_HOOK_TYPES` + metadata headers with a single type→timeout map (verified in `setup`, INV-007).
- **ENV-012** (new): InstructionsLoaded hook availability (Claude Code ≥2.1.69; confirmed 2.1.185).
- **TB-010** (new): Claude Code harness → hook stdin JSON trust boundary (referenced by BND-001/INV-004).
- **new ABS** (audit-trail JSONL producer/consumer contract): schema now has downstream readers; must enumerate real producers/consumers and mixed record shapes (RS-024e / RS-028).
- **ENV-005** reconcile: only if the direct signal changes its text.

### Carry-forward findings for /cupdate-arch (from mini-audit; do NOT fix in /cverify)

- **MA-011 / MA-R2 (INV-002 wording, MEDIUM)**: the hook's absolute-path scope uses an infix `*/.claude/rules/*` arm while INV-002 states "prefix-checked, substring prohibited (AP-032)." Correctly rejects the boundary-substring and traversal attacks; over-matches non-project trees (vendor/, /tmp) — low practical exposure (harness controls emitted file_paths). Spec/impl wording drift — reconcile INV-002 wording to "prefix OR project-rooted `.claude/rules/` component" (AP-020/PMB-013 class).
- **MA-012 (DD-005 phantom /cprune reaper, MEDIUM)**: DD-005/BND-002 claim log trimming is "delegated to /cprune", but `prune-scan.sh` never references `.correctless/meta/instructions-loaded.jsonl`. Phantom reaper — the log grows unbounded (non-breaking: gitignored/local). Either wire the log into a /cprune meta size-cap sweep OR amend DD-005/BND-002 to "unbounded linear growth accepted; manual truncation" (honest). Add a structural test that the reaper's scan set covers the artifact path (PMB-016 shape).
- **INV-008 "write-tool" wording clarification (from MA-R2-003 MA-CC-03)**: the /cwtf hook-edit filter now additionally gates on write tools (`test("^(Edit|Write|MultiEdit|NotebookEdit|CreateFile|Bash)$")`) so Read/Grep of `hooks/` is not miscounted as an edit. INV-008's wording should be updated to reflect the tool-gate, not just the path anchor.

### File-separately item (pre-existing, NOT this feature's regression)

- **MA-014 (MEDIUM)**: `scripts/compute-session-cost.sh:185-199` extracts `{timestamp: .timestamp}` from audit-trail, but audit-trail entries carry `ts`, not `timestamp` — phase-attribution degrades (timestamp null). Predates this feature; spec RS-028 over-states this consumer's correctness. Fix: read `.ts // .timestamp` and sweep the RS-030 mixed-shape normalization across every audit-trail content consumer. Recommend filing as a standalone issue.

### Drift Debt

`.correctless/meta/drift-debt.json` open items: none. No new drift detected.

## QA / Mini-Audit Class Fixes Verified

The round-2 findings snapshot records 7 HIGH findings with `status: open`; all 7 are the known **review-finding-status-gap** (status not swept to "fixed" after implementation). Each fix is confirmed **present in `skills/cwtf/SKILL.md` at HEAD**, and the full suite is green:

- **MA-001** (`fromjson? | objects` guard on every jq over IL_LOG/AUDIT_TRAIL) — present at SKILL.md:164-169, 236, 240, 245-246, 259, 314. ✓
- **MA-002 / MA-R2-002 / MA-R3-001** (hook-edit filter: repo-relative canonicalization via `ltrimstr($root + "/")` before anchoring `^hooks/` or `^\.correctless/hooks/`; handles mixed absolute/relative `.file`; excludes `src/hooks`, `.git/hooks`, `node_modules/**/hooks`) — present at SKILL.md:157-181, 236, 240, 314. ✓
- **MA-004 / MA-R2-001 / MA-R3-002 / MA-R3-003** (audit-trail located by current-branch slug using the full `${br//[^a-zA-Z0-9]/-}` char class truncated to 80, with terminal-hash glob anchor `[0-9a-f]{6}\.jsonl$` to reject prefix-sibling branches; honest "not located" when absent) — present at SKILL.md:208-219, 295. ✓
- **MA-R2-003 tool-gate** (write-tool filter) — present at SKILL.md:236/240/314. ✓
- **MA-005** (`jq -Rr` for human-facing last_written) — present at SKILL.md:248. ✓
- **QA-001** (canonical empty/null session_id representation) — audit-trail emits canonical null; /cwtf folds `""` → unattributed. ✓
- **QA-002** (behavioral tests for INV-009/016, not prose greps) — executable cwtf harness over empty/all-null/populated logs. ✓

Accepted/deferred findings (MA-009, MA-010, MA-013, MA-R2-004, MA-R3-004) reviewed — all correctly dispositioned as accepted residuals within the advisory/forgeable-log envelope (PRH-002 / PMB-020) or speculative double-drift; none are BLOCKING.

## Antipattern Scan

`scripts/antipattern-scan.sh main` → exit 0, valid JSON, 92 findings project-wide, 0 scanner errors, no summaries. Feature-file findings reviewed — all are expected non-issues:

| File | Line(s) | Pattern | Disposition |
|------|---------|---------|-------------|
| hooks/instructions-loaded.sh, hooks/audit-trail.sh (+mirrors) | various | "Error suppression with `2>/dev/null`" | Expected — the mandated fail-open hook posture (INV-001, PostToolUse convention PAT-005). Not a defect. |
| hooks/audit-trail.sh (+mirror) | 148-163, 213 | "Debug echo statement" | False positive — these are the hook's normal JSONL/status emissions, not debug. |
| tests/test-instructions-loaded*.sh | various | "Debug echo", "Error suppression" | Test scaffolding (progress echos, tolerant assertions). Not shipped code. |
| tests/test-instructions-loaded-cwtf.sh | 209, 425, 448 | "jq -s (slurp) on JSONL (AP-014)" | False positive — the `jq -s 'length'` is the **test's own** line-counting assertion scaffolding. The `/cwtf` SKILL consumer path contains **no** `jq -s` (INV-008 verified clean). |

No actionable antipattern findings in the feature diff.

## Drift

None found. The implementation uses the abstractions the spec prescribes (generalized type→timeout map, `canonicalize_path`/PAT-017, `jq -n` serialization, `fromjson? | objects` consumer contract). All rules map to implementation and tests.

## Spec Updates

Workflow state `spec_updates` for this branch: none recorded during TDD (all spec shaping happened across review rounds 1-5 pre-implementation).

## Overall: PASS — 0 BLOCKING findings

All 22 rules covered (INV-012b and PRH-003 discharged in this report). Full suite green. INV-012b provenance attested (harness 2.1.185, per-open firing confirmed). EA-004 disposition recorded (emit `timeout_ms: 5000`, verified at registration; harness-honoring an accepted latent unknown). 3 findings carried forward to /cupdate-arch (MA-011, MA-012, INV-008 wording) and 1 file-separately item (MA-014) — none blocking. No dependency, drift, or architecture-conflict issues.

Next MANDATORY step: /cdocs.
