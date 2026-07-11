# Verification — design-contract-lens-sync

- **Spec**: `.correctless/specs/design-contract-lens-sync.md`
- **Date**: 2026-07-10
- **Verifier**: /cverify (read-only on source)
- **Feature test**: `tests/test-design-contract-lens-sync.sh` — **70 passed, 0 failed** (exit 0)

## 1. Summary

**Verdict: PASS.**

Every invariant (INV-001..010), prohibition (PRH-001/002), and boundary
condition (BND-001) in the spec is **satisfied** with concrete, real-file
evidence and a live enforcing test assertion. The feature test passes 70/70,
including the full RS-004 negative-fixture rejection suite (a–o), both
non-vacuity (test-the-test) traps, the two-extractor scope-divergence proof,
and the registry-driven INV-005 substance loop that iterates the LIVE registry
past the 8 seeds. The registry↔agent set-equality binding holds, the mirror is
byte-identical, and the registry is confirmed absent from the distribution tree.

One architecture item is **PENDING by design** (the new ABS entry, authored
during /cupdate-arch — DD-005). No stale existing architecture entries. No new
dependencies.

## 2. Rule Coverage

| Rule | Status | Evidence (file:line + enforcing test) |
|------|--------|----------------------------------------|
| **INV-001** Registry→agent completeness | satisfied | `check_setequality` L486-501 diffs `registry_lens_ids` vs section-scoped ids, guarded by `>=8` floor. Registry `agents/design-contract-lenses.tsv:2-9` (8 rows) ↔ agent `agents/review-spec-design-contract.md:53-60` (8 bullets). Test PASS `INV-001(complete)`. |
| **INV-002** Agent→registry (no orphans) | satisfied | `check_setequality` L504-516 `comm -13` over **full-file** extractor (`extract_dcl_full`) catches out-of-section orphans (CX-001). Test PASS `INV-002(no-orphans)`; TTT `check_ttt_scopes` proves the full scope surfaces an injected `DCL-999`. |
| **INV-003** Registry well-formedness | satisfied | `validate_registry` L135-178 (BOM/CR/header/NF==4/non-empty/`^DCL-[0-9][0-9][0-9]$`/`^PMB-[0-9][0-9][0-9]$`/dup/≥1 row). Real-file PASS `INV-003(real)`; 15 negative fixtures (a–o) all rejected; no-final-newline positive reads all 8 rows (`INV-003(no-nl:count)`). |
| **INV-004** Seed completeness (8 anchored rows) | satisfied | `check_inv004_seed` L435-454 uses `awk -F'\t'` field equality + `NF==4` (CX-007). Registry rows verbatim match the 8-row `SEED` array (DCL-001/cardinality/PMB-013 … DCL-008/mechanism-capability-mismatch/PMB-020). Test PASS `INV-004(DCL-001..008)`. |
| **INV-005** Anchored, keyword-bound, condition + body floor | satisfied | `check_inv005` L523-566 iterates `registry_lens_pairs` (the **LIVE** registry, not the hard-coded seed — QA-003) via `lens_bullet_ok` L233-245: exactly-once (full scope), in-section bullet, keyword verbatim, directive `{BLOCKING,flag}` (excl. keyword span), condition `{when,if}`, post-strip body `≥24`. DCL-002 dual-marker pinned L560-565. All 8 agent bullets (L53-60) single-line and pass. Test PASS `INV-005(DCL-001..008)` + `INV-005(DCL-002-dual)`. |
| **INV-006** cpostmortem convention at point-of-use | satisfied | `check_inv006` L572-605 anchors on `^### Step 3:`, requires path `agents/design-contract-lenses.tsv` + phrase `Design Contract Checker lens` within Step 3, ≤10 lines apart. `skills/cpostmortem/SKILL.md:74` (Step 3 heading) + `:78` (both substrings co-located) → 4 lines apart. Test PASS `INV-006(proximity)`. |
| **INV-007** No CLAUDE.md coupling | satisfied | (a) `grep -c 'CLAUDE.md' agents/review-spec-design-contract.md` = 0; (b) `preamble_region_ok` L614-626 anchors the file-load list, fail-closed on missing anchor. `skills/creview-spec/SKILL.md` preamble clean. TTT injection + no-anchor cases both PASS. Test PASS `INV-007(a)`, `INV-007(b)`, `INV-007(b:inject)`, `INV-007(b:closed)`. |
| **INV-008** Non-vacuous extraction (≥8 floor) | satisfied | `check_setequality` L469-483 asserts `>=8` on registry, agent-full, and agent-section extractors BEFORE any comparison; `count_unique_ids` L124-128 empty-safe (INV-008b). Vacuity TTT `check_ttt_vacuity` proves renamed heading → 0. Test PASS `INV-008(registry>=8/agent-full>=8/agent-section>=8)`. |
| **INV-009** Registry source-only (property-general) | satisfied | `check_inv009` L684-692 `find correctless/ -name 'design-contract-lenses.tsv'`. Independently confirmed empty. Test PASS `INV-009(source-only)`. |
| **INV-010** Mirror DCL-set parity (own guard) | satisfied | `check_inv010` L698-717 section-scoped DCL-set diff with its OWN `>=8` guard (RS-010). Mirror `correctless/agents/review-spec-design-contract.md` confirmed **byte-identical** to source (`diff -q` IDENTICAL). Test PASS `INV-010(parity)`. |
| **PRH-001** No prose-scanning CLAUDE.md | satisfied | `check_prh001_selfscan` L995-1025 self-scans this test's source; the only permitted `CLAUDE.md` occurrence is the single-quoted grep needle. Test PASS `PRH-001(selfscan)` — all 2 tokens whitelisted. |
| **PRH-002** Agent must not load CLAUDE.md | satisfied | Enforced via INV-007(a)+(b) (scoped, not whole-file — RS-003). Agent tool allowlist unchanged `Read, Grep, Glob` (`agents/review-spec-design-contract.md:4`). |
| **BND-001** Missing/malformed registry fails closed | satisfied | Test runs `set -eo pipefail` (helpers add `-u`); `check_preflight` L296-310 asserts registry+agent existence up front; `>=8` guards + `validate_registry` negative suite prove rejection branches are live, not dead. Actionable per-failure messages present. |

## 3. Architecture Adherence

- **New ABS entry — PENDING (expected).** DD-005/RS-006 specify a new
  primary-SSOT `ABS-0xx: Design Contract lens registry` entry, authored during
  **/cupdate-arch** (index line in `.correctless/ARCHITECTURE.md` + full body in
  `docs/architecture/abstractions.md`). Not yet present — this is the correct
  state at /cverify time, **not a gap** (workflow task #24).
- **No stale existing entries.** The one existing entry whose `Enforced at` set
  covers a touched path is **ABS-010** (`agents/{name}.md` sole-source +
  byte-equal mirror; `docs/architecture/abstractions.md:70-71`). Its invariants
  all still hold post-change: the agent's frontmatter `name:`==basename, the
  tool allowlist is unchanged (`Read, Grep, Glob` — no write/escalation tool
  added), and the source↔`correctless/agents/` mirror is byte-equal (confirmed).
  Expanding the agent body does not invalidate ABS-010; no edit required.

## 4. Smells / Accepted Residuals

- **R-A (semantic-correctness residual, accepted).** INV-005 binds
  id+keyword+directive+condition+body-floor but **cannot verify the lens body is
  semantically correct** (a plausible-but-wrong condition passes). Backstop: PR
  review + mini-audit `lens-body-anti-gaming` lens. Named honestly per
  AP-040/PMB-020.
- **QA-004 (DCL-less-bullet migration seam, accepted).** A `## PMB-derived
  lenses` bullet with no DCL token passes the sync test vacuously. Documented as
  a reviewer-reject item in the agent's migration-seam note
  (`agents/review-spec-design-contract.md:51`). Residual is prompt-level by
  design (structural closure would require the same over-scan this feature
  avoids).
- **R-C (bogus PMB residual, accepted).** Registry accepts any `PMB-[0-9]{3}`;
  it does not verify the PMB exists (verifying would require scanning CLAUDE.md,
  PRH-001). PR-review catch.
- **MA-001 (duplicate-token directive leg, LOW).** The directive/keyword
  matching is whole-word set membership; a pathological future keyword could
  interact with the directive set — mitigated by the RS-002c exclude-span in
  `awk_has_word` (L188-200). Low severity, accepted.
- **Scope observation (not a defect): `tests/test-cross-feature-intel.sh`** was
  also modified in this branch to replace three hardcoded PMB fixture dates with
  `date -d 'N days ago'` relative dates — an incidental AP-024/bound-drift fix
  (PMB-001's `2026-04-10` crossed the intel script's 90-day recency window on
  ~2026-07-09, reddening INV-016e). This is unrelated to the lens-sync feature
  but is a legitimate keep-the-suite-green fix; noted for the reviewer's
  awareness. `_typos.toml` additions (8 keywords + registry exclude) implement
  EA-003 correctly. `CONTRIBUTING.md` 111→112 and `tests/test-inventory.json`
  111→112 are the required companion bumps (CX2-1/CX-008); actual `find tests`
  count confirmed **112**.

## 5. New Dependencies

**None.** The test uses only POSIX-portable externals (`grep`, `awk`, `sed`,
`sort`, `diff`, `od`, `find`) per EA-002/ENV-006 — no `\b`, `grep -P/-o/-w`.
The agent tool allowlist is unchanged (`Read, Grep, Glob`). No new hooks,
scripts, runtime data paths, or trust-boundary crossings (STRIDE TB-005: no
identity/data-sensitivity change).

## 6. Verification Status

**PASS.** All 13 spec rules (INV-001..010, PRH-001/002, BND-001) satisfied with
real-file evidence and live test enforcement; feature suite 70/70 green; mirror
byte-identical; registry source-only confirmed. The only outstanding architecture
item (the new ABS entry) is deferred to /cupdate-arch by design. No drift debt to
record beyond the pending ABS authorship.

## Cross-Model Verification (codex gpt-5.5)

An independent codex (GPT-5.5, xhigh reasoning) verification pass was run alongside the Claude verification.

- **Confirmed resolved** (with file:line citations against the real tree): the three earlier codex QA findings — DCL-004 broadened to a non-exhaustive primitive list incl. `find` (agent:56), DCL-005 broadened to guard/isolation/validation-gate + file/component/asset (agent:57), and INV-005 substance loop now iterating the live registry via `registry_lens_pairs` with a DCL-009 test-the-test (test:940-958).
- **New finding CV-001 (HIGH), FIXED in this feature commit**: the PRH-001 self-scan whitelist matched any line with `grep` + the single-quoted `CLAUDE.md` needle without pinning the trailing file argument, so a prohibited `grep '<needle>' CLAUDE.md` (reading CLAUDE.md — the coupling PRH-001 forbids) would have passed. Tightened to strip the needle and reject any residual guidance-file token; refactored into a callable `prh001_scan_source` with three new test-the-test assertions (`ttt:neg-trailingarg`, `ttt:neg-read`, `ttt:pos`). Feature test now **73 passed / 0 failed**.

Post-fix status: **no BLOCKING/HIGH outstanding** across both models.
