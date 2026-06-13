# Verification: AP-031 Fixture Divergence Prevention

- **Spec**: `.correctless/specs/ap031-fixture-divergence-prevention.md`
- **Branch**: `feature/ap031-fixture-divergence-prevention`
- **Effective intensity**: high (project=high, feature=high)
- **Verified**: 2026-06-13 by /cverify (autonomous, /cauto pipeline)
- **Note**: Spec was amended post-review-approval to incorporate mini-audit findings MA-117 (R-002 trigger-detection block) and MA-211 (language-aware `Source:` citation). Amendments were human-approved escalations; the current spec text is authoritative and the implementation matches it.

## Rule Coverage

| Rule | Test | Status | Notes |
|------|------|--------|-------|
| R-001 [unit] | test-ap031-fixture-divergence.sh R-001(a)–(h) | covered | 8 block-scoped assertions on cspec Step 3 block (AP-031 ref, format-pinning language, producer citation, detection heuristics, negative-trigger exclusion, `Example:`/`Not:` contrast, SKILL.md cross-ref). Placement verified: directive at line 371 sits inside `### Step 3` (225) before `### Step 3a` (385). |
| R-002 [unit] | test-ap031-fixture-divergence.sh R-002(a)–(g) | covered (weak note) | 7 assertions: real artifact, `# Source:` token, dormant behavior, verbatim form, hermetic/CI concern, alternative live-read limitation, 25-line co-location window (TA-007). **Weak note**: the post-review amended clauses — trigger-detection block, producer-to-artifact table, and `// Source:`/`-- Source:` language-aware forms — are implemented in `agents/ctdd-red.md` (verified by direct read) but have no structural-test assertion in the ctdd-red.md scope; R-004's contract (which defines the required keywords) was not amended to require them, so this matches the spec as written. Advisory only. |
| R-003 [unit] | test-ap031-fixture-divergence.sh R-003(a)–(q) | covered | 15 assertions: check-11 name/BLOCKING/real-artifact/dormant/producer-mapping/fixture-following; orchestrator non-blockquote `git diff` + `git status --porcelain` + "passes both lists" (TA-003 blockquote exclusion); 8 pinned class fixes (see QA Class Fixes below). |
| R-004 [unit] | test-ap031-fixture-divergence.sh R-004(a),(b) | covered | Meta-test: file exists, uses awk state-machine block extraction. All R-001/2/3/6 assertions are block-scoped (AP-003 mitigation) — verified by reading the test: no file-wide grep used for keyword assertions. |
| R-005 [unit] | test-ap031-fixture-divergence.sh R-005(a)–(c) + `sync.sh --check` | covered | diff-based byte-parity for all 3 file pairs. Fresh `bash sync.sh --check` run in this verification: clean. |
| R-006 [unit] | test-ap031-fixture-divergence.sh R-006(a)–(c) | covered | AP-031 + real-fixture reference in Design Patterns section (block-scoped); test count check is exact-match with anti-inflation bound (TA-008): documented 93 == actual 93. CONTRIBUTING.md also updated 92→93. |

**Uncovered rules: 0. BLOCKING coverage findings: 0.**

Branch structural test result (fresh run): **39 passed, 0 failed**.

## Test Suite

Full suite (93 files): **all files pass**. Evidence: per-file sweep run — 92/93 passed in-sweep; the single sweep failure (`tests/test-qa-severity-calibration.sh`) passed on isolated re-run. Three additional full-suite runs each tripped a *different* pre-existing roaming flake (`tests/test-architecture-drift.sh` INV-009(b) twice, `tests/test-cprune.sh` INV-013-d once); every implicated file passes 100% in isolation and none is touched by this branch. Root cause confirmed by code inspection: `printf '%s' "$x" | grep -qF ...` pipelines — `grep -q` exits on first match, `printf` receives SIGPIPE, pipeline reports 141 under pipefail despite correct content. This flake is already documented in the workflow state override history ("pre-existing pipefail/SIGPIPE suite flake"). See Smells for the follow-up recommendation.

## Dependencies

- No package manifests in this repo (bash project); `git diff main...HEAD` introduces no new dependencies. ✓

## Architecture Adherence

8 entries affected (reference changed files `skills/cspec/SKILL.md`, `skills/ctdd/SKILL.md`, `agents/ctdd-red.md`):

- TB-007: valid — cspec orchestrator change is additive (Step 3 directive); research-agent trust boundary untouched
- ABS-005: valid — calibration sole-writer contract intact; cspec calibration prose untouched by this feature
- ABS-010: valid — `agents/ctdd-red.md` body-only addition, frontmatter unchanged; source/dist byte-equal (`sync.sh --check` clean)
- ABS-024: valid — check 11 is additive to the test audit; Entry/Through/Exit fields and tiers unchanged
- ABS-027: valid — cspec Step 0 fingerprint invocation untouched
- ABS-034: valid — ctdd probe-round writer section untouched
- ABS-036: valid — lens recommendation consumer section untouched (integration-depth agent's check list reference updated 5,6,9,10 → +11, consistent)
- ABS-037: valid — cspec brief-consumer section untouched

All `Enforced at`/`Test` paths exist (every referenced test file executed in the suite sweep). No invariant conflicts. No new ARCHITECTURE.md entry required — the spec's Won't Do explicitly declines PAT-020 promotion; the pattern is documented in AGENT_CONTEXT.md Design Patterns and AP-031's "Prevention implemented" note.

8 entries checked, 0 stale, 0 drift-debt items.

### Drift Debt
- `.correctless/meta/drift-debt.json`: no open items (dormant per PAT-019). No new drift found; no entries created.

## Antipattern Scan

`bash .correctless/scripts/antipattern-scan.sh main` — valid JSON, 0 errors, 0 summaries, 1 finding:

| File:Line | Category | Assessment |
|-----------|----------|------------|
| tests/test-ap031-fixture-divergence.sh:15 | debug-logging | False positive — test banner `echo` (`"AP-031 Fixture Divergence Prevention Tests"`), the standard harness output pattern used by every test file in the suite. Not a debug statement. |

Semantic checklist (`.correctless/checklists/ai-antipatterns.md`) reviewed against the diff: no TODO/FIXME/HACK, no commented-out code, no broad catches. The implementation directly targets AP-003 (block-scoped keyword tests) and AP-031 (its own subject).

## QA Class Fixes Verified

`qa-findings-ap031-fixture-divergence-prevention.json`: 50 findings (8 QA across 4 rounds, 21 MA round-1, 21 MA round-2), 0 open, 18 fixed, 32 accepted. Both BLOCKING findings fixed with pinned regression assertions:

- QA-004 (BLOCKING, /cdocs producer row wrong artifact) → R-003(j) bare-directory-glob class check ✓
- QA-006 (BLOCKING, cost-cache collision) → R-003(k) `cost-*.json` + `cost-cache-*` exclusion pinned ✓
- MA-104 (anti-anchoring TB-003 fence) → R-003(l) ✓
- MA-112 (absent-list sentinel) → R-003(m) ✓
- MA-209 (fixture budget cap) → R-003(n) ✓
- MA-216 (live-read exclusion) → R-003(o) ✓
- MA-220 (retroactive-retrofit scope) → R-003(p) ✓
- MA-211 (language-aware citation) → R-003(q) — pinned in the check-11 copy; see R-002 weak note for the ctdd-red.md copy ✓

Each assertion pins the class keyword in the directive text, so removal/regression of the fix fails the structural test — class coverage, not instance coverage, is appropriate here since the "implementation" is prose.

## Smells

- **Pre-existing (not this branch)**: roaming full-suite flake from `printf | grep -q` SIGPIPE under pipefail — observed in `tests/test-architecture-drift.sh` (INV-009(b)), `tests/test-cprune.sh` (INV-013-d), `tests/test-qa-severity-calibration.sh` across 4 suite runs; each passes in isolation. Recommend a class fix sprint item: replace `printf '%s' "$x" | grep -q` with herestring form (`grep -q <<< "$x"`) or tolerate exit 141 — same shape as AP-011 (environment-dependent shell semantics). Out of scope for this feature's verification verdict.
- **Advisory**: R-002's amended clauses (trigger-detection block, producer table, `// Source:` form in `agents/ctdd-red.md`) lack structural-test pins (see Rule Coverage weak note). `agents/ctdd-red.md` is sensitive-file-guard protected; the clauses are present and correct on direct read. A future hardening pass could extend R-004's keyword contract.
- Trivial wording deviation: spec R-002 says `# Source:` in shell/Python "(canonical for this repo)"; the implemented directive omits the parenthetical. Semantics unchanged — not drift.

## Drift

- None found. No DRIFT-NNN entries created.

## Spec Updates

- 1 post-review amendment (human-approved escalation): R-002 gained the language-aware `Source:` citation clause (MA-211) and the trigger-detection block + producer table (MA-117). Workflow emitted the spec-mutation advisory; current spec hash recorded in workflow state. Implementation matches the amended text.
- Workflow state has no `spec_updates` field; calibration entry records `actual_spec_updates: 0` per the mechanical field-source rule — the amendment above is recorded here in prose.

## Calibration Entry

**BLOCKED — not written.** The Edit append to `.correctless/meta/intensity-calibration.json` was blocked by `sensitive-file-guard.sh` (protected pattern `.correctless/meta/intensity-calibration.json`). Per the autonomous-run constraint, the gate was NOT bypassed (no Bash redirect, no override). Note: ABS-005 names /cverify as the sole writer of this file, so the guard blocking the sole writer's own skill mechanism (allowed-tools includes `Write(.correctless/meta/intensity-calibration.json)`) looks like a guard/allowlist misalignment worth a human look — possibly the protected pattern needs a writer-exception path like ABS-029's audit-record.sh pattern.

The computed entry, ready to append verbatim once the write path is unblocked:

```json
{
  "feature_slug": "ap031-fixture-divergence-prevention",
  "recommended_intensity": "high",
  "actual_intensity": "high",
  "actual_qa_rounds": 4,
  "actual_findings_count": 2,
  "actual_tokens": 5232619,
  "actual_spec_updates": 0,
  "harness_version": 1,
  "fix_rounds_triggered": 5,
  "file_paths_touched": [
    ".correctless/AGENT_CONTEXT.md",
    ".correctless/antipatterns.md",
    ".correctless/specs/ap031-fixture-divergence-prevention.md",
    "CONTRIBUTING.md",
    "agents/ctdd-red.md",
    "correctless/agents/ctdd-red.md",
    "correctless/skills/cspec/SKILL.md",
    "correctless/skills/ctdd/SKILL.md",
    "skills/cspec/SKILL.md",
    "skills/ctdd/SKILL.md",
    "tests/test-ap031-fixture-divergence.sh"
  ],
  "timestamp": "2026-06-13T00:53:10Z"
}
```

Field derivations: fix_rounds_triggered = max(0, qa_rounds−1)=3 + mini_audit_fix_rounds=2 (MA round 1: 4 fixed; MA round 2: 8 fixed — each round triggered a fix loop). actual_tokens summed deterministically from `token-log-feature-ap031-fixture-divergence-prevention-80b1f3.jsonl` via the SKILL.md jq command. actual_cost_usd omitted (no cost artifact — /cdocs has not run).

## Overall: PASS with 0 BLOCKING findings

All 6 rules covered (1 weak-coverage advisory note on R-002's amended clauses). Full test suite passes (93/93 files, accounting for the documented pre-existing roaming flake). Distribution sync clean. Architecture entries valid. 0 open QA findings. Next step: `/cdocs` is NOT yet run — proceed with `/cupdate-arch` then `/cdocs` per the high-intensity pipeline before any merge.
