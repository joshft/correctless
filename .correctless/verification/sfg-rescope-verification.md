# Verification: Re-scope sensitive-file-guard from perimeter to write-target-only guardrail

**Task**: sfg-rescope | **Branch**: feature/sfg-rescope | **Intensity**: high | **HEAD**: 4ad1856
**Verifier**: /cverify (autonomous, /cauto pipeline) | **Date**: 2026-06-25

## Rule Coverage

Test approach is **hook-integration** for all behavioral INVs (stdin JSON envelope → process exit code via `run_hook_capture`), per the spec's mandated approach. Function-level calls to `_extract_bash_targets` are forbidden by the spec and none are used.

| Rule | Test(s) | Status | Notes |
|------|---------|--------|-------|
| INV-001 (reads/invocations not targets) | test_inv001_reads_invocations_not_targets | covered | includes a reaches-extraction `bash hf.sh` fixture per spec |
| INV-002 (redirect dests block, incl. glued, `&>`, `<>`) | test_inv002_redirect_destinations_block; test_class_write_redirect_operator_completeness | covered | 16-operator oracle-derived completeness sweep |
| INV-003 (writer-command dests) | test_inv003_writer_destinations_block | covered | tee/cp/mv/install/ln/sed -i/perl -i/dd of=/truncate; source-read allow |
| INV-004 (git worktree not targets) | test_inv004_git_worktree_allowed | covered | |
| INV-005 (interpreter/eval/process-sub opaque) | test_inv005_interpreter_opaque | covered | `cat <<< x > .env` outside-redirect still blocks |
| INV-006 (sink devices excluded) | test_inv006_sink_devices_excluded | covered | + structural tripwire for early-return branch |
| INV-007 (ambiguity fails open) | test_inv007_ambiguity_fails_open; test_inv007_structural_tripwire | covered | witness corpus + PRH-001 `*)`-arm tripwire |
| INV-008 (input-parse fails closed) | test_inv008_input_parse_fails_closed | covered | malformed JSON → exit 2; valid-JSON unparsable-shell → allow (boundary at JSON layer) |
| INV-009 (Edit/Write target unchanged) | test-sensitive-file-guard.sh Edit/Write corpus (PRH-003) | covered | 188/188 pass, corpus intact |
| INV-010 (canonical-form matching preserved) | test_inv010_canonical_writer_destination | covered | traversal-encoded `cp x subdir/../.env` blocks |
| INV-011 (`_has_write_pattern`/`get_target_file` frozen) | test_inv011_lib_functions_frozen | covered | golden-hash on both bodies + workflow-gate reference present |
| INV-012 (doc coherence: guardrail not perimeter) | test_inv012_doc_coherence_no_perimeter | covered | greps full ARCHITECTURE/CLAUDE/AGENT_CONTEXT/README/docs corpus |
| INV-013 (PAT-001 clause-5 carve-out documented) | test_inv013_rule_carveout | covered | cites PMB-020 + INV-007/INV-008 |
| INV-014 (BLOCKED message guardrail framing) | test_inv014_blocked_message_guardrail | covered | points to sfg-deliverable.md; no custom_patterns suggestion |
| INV-015 (re-scope announced in CHANGELOG) | test_inv015_changelog_announced | covered | |
| INV-016 (prefilter firing ⊇ emit) | test_inv016_prefilter_superset | covered | every INV-002/003 must-block form driven through full hook |
| INV-017 (permissive monotonicity, both directions) | test_inv017_half_a_newly_allowed; test_inv017_half_b_still_blocked | covered | Half-A = 6 cchores + 9 review real false-blocks (AP-031 fixtures); Half-B = full write corpus |
| INV-018 (DEFAULTS pattern classes still block) | test_inv018_defaults_classes_block; test_inv018_structural_class_coverage | covered | representative per class + structural CX-005 coverage check |
| INV-019 (LC_ALL=C at hook scope) | test_inv019_lc_all_c_structural; test_inv019_cross_locale_behavioral | covered | hook L27 verified; cross-locale SKIPs cleanly if no UTF-8 locale |
| INV-020 (per-segment positional detection) | test_inv020_per_segment_positional | covered | compound-command fixtures across full writer set + `&>` survives segmentation |
| PRH-001 (no extract-every-token) | test_inv007_structural_tripwire (tripwire) + INV-001/INV-017A (behavior-primary) | covered | behavior is the proof; grep is labeled tripwire |
| PRH-002 (no perimeter re-framing) | test_inv012_doc_coherence_no_perimeter | covered | mechanical CI grep (converted from review-time) |
| PRH-003 (no previously-blocked Edit/Write now passing) | test-sensitive-file-guard.sh Edit/Write corpus | covered | must-pass-unchanged set green |
| EA-006 (raw-length cap, >cap fail-open) | test_ma_r2_operator_filled_span_no_hang; test_perf_large_command_no_hang; test_ma_dense_trigger_no_hang | covered | `_SFG_LENGTH_CAP=12288` O(1) check at top of extractor |

**Uncovered rules: 0. Weak tests: 0. Wrong-level: 0.** Every INV/PRH plus the TDD-added `&>>`/`<>` operators and EA-006 size cap is covered by a hook-integration test at the deployed-gate level.

## Dependencies

No package manifests changed (bash project; no package.json/go.mod/Cargo.toml/requirements.txt). No new dependencies introduced.

## Architecture Adherence

Affected entries (changed files: `hooks/sensitive-file-guard.sh` + mirror, `.correctless/ARCHITECTURE.md`, `.claude/rules/hooks-pretooluse.md`, `CLAUDE.md`, `AGENT_CONTEXT.md`, `README.md`, `docs/skills/cmodelupgrade.md`, `CHANGELOG.md`, `antipatterns.md`):

- ABS-045 (NEW): valid — single authoritative SFG capability-boundary entry; write-target guardrail, accepted-non-goals enumerated, fail-open extraction / fail-closed input-parse posture documented. This is the doc-only abstraction the spec required (INV-012/RS-019).
- ABS-029/030/035/038/040/041/042: valid — each SFG-leaning enforcement clause scoped to "tool-target + direct redirect/writer-command destinations; interpreter/git-mediated out-of-band writes are accepted non-goals (AP-040)" and See-links ABS-045. ABS-030 (most-exposed, its only structural leg was SFG redirect-block) explicitly scoped down.
- ABS-012/016 generic SFG references (preferences.md, supervisor-mandate): valid — re-framed to "write-target guardrail … interpreter/git-mediated writes are accepted non-goals per AP-040; see ABS-045".
- AP-040 (antipatterns.md): valid — premise-validation antipattern entry present with full how-to-catch defenses (/cspec Step 0 mechanism-capability, /creview-spec mechanism-capability-mismatch lens, /cdevadv product-category coherence, friction-as-signal).
- PAT-001 rule file: valid — clause-5 carve-out subsection added, scoped to SFG extraction path only, input-parse path stays fail-closed.

Structural validation: `tests/test-architecture-drift.sh` 111/111 PASS — all Enforced-at/Test paths exist and reference entry IDs.

### Drift Debt

`.correctless/meta/drift-debt.json` — no open items referencing SFG entries or changed files. No new drift detected: the implementation uses the abstractions the spec names (`canonicalize_path` preserved as sole normalizer, `_has_write_pattern` frozen, destination-driven extraction). No new drift-debt entries created.

## Antipattern Scan

`bash .correctless/scripts/antipattern-scan.sh main` — exit 0, valid JSON, 0 scanner errors, 105 findings (1 file summary cap).

| File | Findings | Disposition |
|------|----------|-------------|
| hooks/sensitive-file-guard.sh (+ mirror) | 9 + 9 | error-suppression idioms (`\|\| true` on jq parse / lib.sh source, `2>/dev/null` on config read) — these are the PAT-001-mandated fail-closed/fail-open idioms, not defects |
| tests/test-sfg-rescope.sh, test-sensitive-file-guard.sh | 20 + 20 | test-harness suppressions (expected) |
| 13 other unchanged scripts | 1-9 each | pre-existing project-wide accepted idioms, not touched by this feature |

All findings are advisory mechanical matches on accepted idioms. None are introduced by this feature's logic. No BLOCKING antipattern.

## QA Class Fixes Verified

From `qa-findings-sfg-rescope.json` (round 2; 13 findings, all fixed or accepted):

- QA-001/QA-002 (quoted/comment operator masking) → test_qa001_quoted_and_comment_operators_not_targets ✓ (structural, class-level)
- QA-003/QA-005 (backslash escape-context parity) → test_qa003_backslash_escape_context_parity ✓ (full outside/single/double matrix)
- QA-006 (backslash×operator glued-prefix) → test_qa006_backslash_operator_parity_sweep ✓ (48-row oracle-pinned cross-product)
- QA-004 → accepted (orchestrator decision, glued-operator-after-quoted-word fixtures); not a fix-blocker
- MA-001/MA-201/MA-102 (O(n²) byte-walk + heredoc/comment cap bypass) → EA-006 raw-length cap + test_ma_r2_operator_filled_span_no_hang + test_ma_r2_heredoc_body_does_not_shield ✓ (class fix: content-agnostic size cap, not a trigger-count proxy)
- MA-002/MA-101 (operator enumeration drift `&>>`/`<>`) → test_ma_append_both_redirect_block + test_ma_r2_readwrite_redirect_block + cross-linked GLUED-REDIRECT OPERATOR SET comments + completeness sweep ✓ (class fix: two operator sites cross-referenced; future operator additions caught)
- MA-003 (`cp -d` command-specific flag semantics) → test_ma_cp_d_flag_not_relocation ✓
- MA-004 → covered by INV-012 doc-coherence corpus

Every class fix has a corresponding structural test that covers the bug class, not just the instance.

## Smells

- hooks/sensitive-file-guard.sh: error-suppression idioms are intentional (PAT-001 fail-closed/fail-open contract) — not smells.
- No TODO/FIXME/HACK, debug statements, or commented-out code introduced.

## Drift

None found. No DRIFT-NNN entries created.

## Spec Updates

Spec workflow state reports `spec_updates` accounting; the spec itself records TDD-phase additions in-body: `&>>`/`<>` redirect operators (MA-002/MA-101, INV-002), EA-006 raw-length size cap (MA-201/MA-102), `cp -d` command-specific flag handling (MA-003). All are documented in the spec's INV-002/INV-003/EA-006 and in qa-findings round 2. These are GREEN-phase hardening within spec authority (RS-004 test corpus migration), not scope creep.

## Out-of-Scope File Notes (advisory, non-blocking)

These changed files are not part of the SFG rewrite and appear to be incidental branch state (config/setup tooling, unrelated to the guard logic):
- `.correctless/config/workflow-config.json` — `test_file_marker: ""` field add + duplicate `test_file` glob token; cosmetic.
- `.gitignore` — removed a duplicate `.claude/artifacts/` entry.
- `CONTRIBUTING.md` — test-file count 102→103 (reflects the new test-sfg-rescope.sh; correct).
- `.claude/settings.json` — unrelated harness settings.
None affect spec rule coverage or the guard's behavior; flagged for /cdocs awareness only.

## Test Suite

- tests/test-sfg-rescope.sh: 234/234 PASS
- tests/test-sensitive-file-guard.sh: 188/188 PASS (PRH-003 Edit/Write corpus intact; RS-004 Bash inversions applied)
- tests/test-architecture-drift.sh: 111/111 PASS
- Full suite (105 test files via commands.test): green (see test-success sentinel)

Sync mirror `correctless/hooks/sensitive-file-guard.sh` is in sync — the sole diff is the `# Rule:` header line that `sync.sh` deliberately strips when copying.

## Overall: PASS with 0 BLOCKING findings

All 20 INVs + 3 PRHs + EA-006 covered by deployed-gate hook-integration tests. Architecture entries scoped down coherently with the new ABS-045 capability boundary as the single source of truth. AP-040 antipattern recorded. No uncovered rules, no drift, no BLOCKING antipatterns. Advisory items: out-of-scope incidental file changes (flagged for /cdocs), accepted-idiom antipattern matches (PAT-001-mandated).
