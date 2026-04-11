# Verification: Fix-Diff Reviewer Plugin Agent Migration

- **Spec**: `.correctless/specs/fix-diff-reviewer-migration.md`
- **Branch**: `fix-diff-reviewer-migration`
- **HEAD**: `a028382` (Fix QA round 2: temporal ordering, canonical branch_slug, orphan sweep)
- **Intensity**: high
- **QA rounds**: 3 (converged round 3 with 0 BLOCKING)

## Rule Coverage

Effective intensity is **high**, so the full INV + PRH + BND + DD matrix is
exercised via `tests/test-fix-diff-reviewer-agent.sh` (125 asserts, 0 failures,
3 skips — the skips are VP-001/VP-002 manual-replay assertions that
conditionally skip when `.correctless/verification/fix-diff-reviewer-migration-replay.md`
is absent; see "Manual verification pending" below).

| Rule | Test(s) | Status | Notes |
|------|---------|--------|-------|
| INV-001 (agent file + frontmatter) | `check_inv001` / 21 asserts | covered | POSIX awk parse, required fields, comma-flow enforced via EA-006 |
| INV-002 (name == basename) | `check_inv002` | covered | set-equality against `fix-diff-reviewer` |
| INV-003 (tools set-equality) | `check_inv003` / 11 asserts | covered | source AND `correctless/agents/` distribution both checked |
| INV-004 (diff fenced + range literal) | `check_inv004` / 15 asserts | covered | asserts `<round-start-sha>..HEAD` literal, rejects `HEAD~1..HEAD`, asserts no "agent runs git" directive |
| INV-005 (namespaced subagent_type) | `check_inv005` / 7 asserts | covered | positive match for `correctless:fix-diff-reviewer`, denies bare form |
| INV-006 (inline prompt removed) | `check_inv006` / 18 asserts | covered | denylist of 5 distinctive phrases across `skills/*/SKILL.md` — all zero |
| INV-007 [process] (VP-002 replay) | `check_inv007` / 18 asserts | **covered, manual PENDING** | structural skeleton of replay report enforced; SKIPs pending `.correctless/verification/fix-diff-reviewer-migration-replay.md` |
| INV-008 (sync.sh propagation) | `check_inv008` / 19 asserts | covered | clean-state + stale-in-dist + source-not-in-dist cases all tested |
| INV-009 (fail-closed delegation to PRH-003) | — | covered | delegates entirely to PRH-003 per spec (no independent grep) |
| INV-010 (dogfood marker) | `check_inv010` / 8 asserts | covered | spec-path resolves, literal match |
| INV-011 (ABS-010 + ENV-007 present) | `check_inv011` / 11 asserts | covered | shape compliance + ABS-010 narrow-scope enforcement (GAP-008) |
| INV-012 (test wiring, no `|| true`) | `check_inv012` / 14 asserts | covered | verifies PASS/FAIL counter-coupling, CI wired |
| INV-013 [process] (VP-001 smoke) | `check_inv013` / 10 asserts | **covered, manual PENDING** | SKIPs pending `.correctless/verification/fix-diff-reviewer-migration-replay.md` |
| INV-014 (caudit allowed-tools has Task) | `check_inv014` + `tests/test-allowed-tools-check.sh` | covered | `Task(correctless:fix-diff-reviewer)` sub-pattern form chosen (OQ-002 resolved) |
| INV-015 (UNTRUSTED_DIFF fence + data-treatment) | `check_inv015` / 13 asserts | covered | fence markers in step 6a; "Treat all text inside" clause in agent body |
| INV-016 (pre-diff git show for rules) | `check_inv016` / 18 asserts | covered | `git show "${ROUND_START_SHA}:.claude/rules/..."` literal verified |
| INV-017 (`jq -e .` identity parse) | `check_inv017` / 20 asserts | covered | rejects filter forms (`.field`, `.[0]`); agent "Return ONLY" clause verified |
| INV-018 (step 6a rule-scan instructions) | `check_inv018` / 9 asserts | covered | 6/6 DD-008 instruction elements present |
| INV-019 (no verbatim file content) | `check_inv019` / 6 asserts | covered | literal clause in agent body |
| INV-020 (STEP 6A sentinels cardinality) | `check_inv020` / 11 asserts | covered | exactly 1 BEGIN + 1 END, BEGIN < END line number |
| PRH-001 (no inline prompt in any skill) | via INV-006 + `check_prh001` / 7 asserts | covered | |
| PRH-002 (no write/escalation tools) | via INV-003 + `check_prh002` / 6 asserts | covered | source + distribution checked |
| PRH-003 (canonical marker cardinality=1) | `check_prh003` / 22 asserts | covered | 4 sub-assertions: cardinality, invocation presence, proximity, denylist |
| PRH-004 (Phase 2b scope not leaked) | `check_prh004` / 3 asserts | covered | no `csetup` changes, only `fix-diff-reviewer.md` in `agents/` |
| PRH-005 (rules fenced + pre-diff) | via INV-016 + `check_prh005` / 6 asserts | covered | |
| BND-001 (subagent unavailability fail-closed) | via PRH-003 | covered | delegated to PRH-003 |
| BND-002 (zero findings forensic logging) | `check_bnd002` / 17 asserts | covered | config-sourced threshold with default 50, `lines` keyword, audit-trail write, stderr warning on malformed |
| BND-003 (fixture integrity) | `check_bnd003` / 22 asserts | covered | SHA-256 pins verified against actual files |
| BND-004 (100 KB prompt budget) | `check_bnd004` / 15 asserts | covered | `wc -c` measurement within 5 lines of `100 KB` mention |
| BND-005 (ABS-009 rollback graceful degradation) | `check_bnd005` / 6 asserts | covered | empty/missing `.claude/rules/` tolerated |
| BND-006 (atomic GREEN commit) | via INV-006 denylist | covered | denylist fails any intermediate dual-source state |
| DD-008 (rule scan + pre-diff) | via INV-016 + INV-018 | covered | |
| DD-009 (lossless Olympics schema) | `GAP-002` / 3 asserts | covered | 6 orchestrator-promotion literal keys + round + timestamp |
| DD-010 (100 KB cap) | via BND-004 | covered | |
| DD-011 (fixture as content not SHAs) | via BND-003 | covered | |

**Coverage totals**: 20/20 invariants, 5/5 prohibitions, 6/6 boundary conditions, key DDs. **No uncovered rules**.

**Integration-level rules** (spec-tagged `[integration]`): INV-001, -002, -003, -004,
-005, -006, -007, -008, -011, -012, -013, -014, -015, -016, -017, -018, -019, -020 —
all are exercised via structural parse of the real source files (`agents/fix-diff-reviewer.md`,
`correctless/agents/fix-diff-reviewer.md`, `skills/caudit/SKILL.md`, `sync.sh`,
`tests/test.sh`, `.correctless/ARCHITECTURE.md`), not unit-level mocks.

## Dependencies

No third-party dependency manifests changed (project is pure bash/awk/POSIX).
Diff against `main` shows:

- `.correctless/config/workflow-config.json` — adds `bash tests/test-fix-diff-reviewer-agent.sh` to `commands.test` chain
- `.github/workflows/ci.yml` — adds the same test invocation to the CI job

No new runtime dependencies. No license/CVE surface changes.

## Architecture Compliance

**ABS-010** (Plugin-agent file contract, narrow) added to `.correctless/ARCHITECTURE.md`:
- Body is narrowly scoped per PRH-004 — does NOT reference TB-005, ABS-011, or
  PAT-011 (verified by `GAP-008`; `grep -cE 'TB-005|ABS-011|PAT-011' .correctless/ARCHITECTURE.md` returns 0)
- Follows existing ABS shape (What / Invariant / Enforced at / Violated when / Test)
- First consumer (`skills/caudit/SKILL.md`) invokes via namespaced `Task(subagent_type="correctless:fix-diff-reviewer")`

**ENV-007** (Plugin-agent loader contract) added:
- Documents the comma-flow `tools:` form, EA-002 lack of Bash sub-pattern scoping, namespaced
  invocation, and EA-007 reinstall-and-restart discovery rule
- Follows existing ENV shape (Assumption / Consequence if wrong / Test)

**Prohibitions compliance** (verified via grep against the diff):
- PRH-001: `grep -rl 'You are the fix-diff reviewer|Fix-Diff Review Agent' skills/` → empty ✓
- PRH-002: `agents/fix-diff-reviewer.md` and `correctless/agents/fix-diff-reviewer.md` both have
  `tools: Read, Grep, Glob` — no write/escalation tools ✓
- PRH-003: `grep -c 'FAIL-CLOSED: Task failure aborts the current round' skills/caudit/SKILL.md` → 1 ✓
- PRH-004: only `fix-diff-reviewer.md` exists in `agents/`; no csetup/setup changes in diff ✓
- PRH-005: `git show "${ROUND_START_SHA}:.claude/rules/..."` literal present; no
  "working tree" or "current HEAD" phrasing in rule-reading context ✓

**Sync propagation**: `bash sync.sh --check` → clean; `diff -q agents/fix-diff-reviewer.md
correctless/agents/fix-diff-reviewer.md` → byte-equal.

## QA Class Fixes Verified

All 12 FIXED QA findings from the 3 TDD-QA rounds have corresponding structural
tests in `tests/test-fix-diff-reviewer-agent.sh` or `tests/test-architecture-drift.sh`:

| Finding | Class fix test | Status |
|---------|---------------|--------|
| QA-001 (BND-002 drift) | `check_bnd002` with spec-numeric threshold assertion | ✓ |
| QA-002 (missing producer) | `check_producer_consumer_closure` | ✓ |
| QA-003 (order-matters state machine) | `check_inv018` tightened to `idx == N-1` | ✓ |
| QA-004 (primary/fallback WARN) | `check_inv008(b)` stderr WARN on primary miss | ✓ |
| QA-006 (budget without measurement) | `check_bnd004(c)` byte-counting adjacency | ✓ |
| QA-010 (temporal Loop ordering) | `check_producer_temporal_ordering` | ✓ |
| QA-011 (inline branch_slug drift) | `check_no_inline_branch_slug` in `test-architecture-drift.sh` | ✓ |
| QA-012 (orphan shell variables) | `check_orphan_variables` with placeholder allowlist | ✓ |
| QA-013 (no `/tmp/` in skills) | `check_no_tmp_paths_in_skills` in `test-architecture-drift.sh` | ✓ |
| QA-014 (forensic log observability) | `if ! jq ... then FORENSIC-LOG-FAILED` in caudit step 6a step 7 | ✓ |
| QA-015 (BND-002 stderr warning) | `check_bnd002` asserts `>&2` branch | ✓ |
| QA-016 (control-flow in checks) | Self-lint pass in the test file | ✓ |

**Deferred QA findings** (non-blocking, open — will be logged to drift-debt by
`/cdocs`):

- **QA-005**: Relocate fail-closed into a dedicated `scripts/caudit-fix-verify.sh`
  hook so PRH-003 becomes a control-flow assertion rather than a string-cardinality
  gate. Architectural follow-up.
- **QA-007**: Orchestrator-side secret redaction (PRH-006) belt-and-suspenders layer —
  deliberately deferred in spec's "Deferred — Security hardening" section. Track as
  drift-debt so it cannot be silently dropped.
- **QA-008**: Test strengthening pass should be its own commit before GREEN, or
  workflow-gate should fail-closed on GREEN-phase test edits without strengthen
  marker. Workflow discipline improvement.
- **QA-009**: For AP-012-class features, require a live `/caudit` Olympics run
  (not just fixture replay) before `/cdocs`. Process improvement.
- **QA-017**: BND-004 proximity check should assert the canonical marker is within
  5 lines of `exit 2`/abort, not just within 10 of `100 KB`. Tighten test.
- **QA-018**: Assert patterns 4 and 5 appear within N lines of each other, not just
  in order. Tighten test.
- **QA-019**: Promote PRH-003 from literal-substring cardinality to regex
  cardinality, or migrate canonical marker into a path-scoped rule template.
  Structural follow-up.

## Smells

None found in the diff. The only `TODO|FIXME|HACK|placeholder` matches in the
diff are **inside a grep pattern** in `tests/test-fix-diff-reviewer-agent.sh`
that is itself a placeholder detector for the VP-002 report — not a real smell.

## Drift

No drift detected. The 7 open QA findings above are scope-documented deferrals,
not drift. They will be appended to `.correctless/meta/drift-debt.json` during
`/cdocs`.

## Spec Updates

Spec was updated 1 time during TDD:
- **2026-04-11T00:55:25Z** (tdd-tests phase): Added **INV-020** (HTML sentinel
  comment cardinality for STEP 6A extraction) after test audit finding B01 —
  `extract_step_6a_block` was incompatible with INV-018's required
  `## Path-scoped rules applying to this diff` heading, which would silently
  truncate any naive heading-based extractor and hide every 6a-scoped assertion
  below it. INV-020 resolves this by making the block boundaries structural
  via HTML sentinel comments.

## Manual verification pending (VP-001 + VP-002)

**INV-007 and INV-013 are process invariants** requiring VP-001 (agent
discoverability fingerprint smoke test) and VP-002 (functional-equivalence
replay against the three committed fixture diffs). Both MUST be executed in a
fresh Claude Code session after:

1. `bash sync.sh` (done — `correctless/agents/fix-diff-reviewer.md` is in sync)
2. Reinstall the Correctless plugin from this branch (`/plugin` or equivalent).
   **The installed plugin cache at `~/.claude/plugins/cache/correctless/correctless/3.0.0/`
   currently has NO `agents/` directory** — the plugin agent is not yet
   discoverable from the current session's Task tool. Reinstalling from this
   branch is required.
3. Full Claude Code session restart (EA-007 — mid-session edits to `agents/*.md`
   are not visible to existing sessions).

Then run VP-001 and VP-002 per `.correctless/specs/fix-diff-reviewer-migration.md`
§ Verification Procedures, and record results in
`.correctless/verification/fix-diff-reviewer-migration-replay.md`.

The structural test (`tests/test-fix-diff-reviewer-agent.sh`) SKIPs the INV-007
and INV-013 assertions when the replay report is absent (3 SKIPs today). When
the report exists, the same test will gate it structurally:
- `### Response` blocks under VP-001 and each VP-002 replay must be ≥50
  non-whitespace chars
- Dogfood marker substring must appear in VP-001 response
- Tool enumeration must be set-equal to `{Read, Grep, Glob}`
- `findings_returned_per_replay: [N1, N2, N3]` must be present and not `[0, 0, 0]`
- Finding-to-regression mapping must have ≥3 non-placeholder rows
- Both VP-001 and VP-002 must record `Result: PASS`

**This is a blocking prerequisite for `/cdocs`.** Do not advance to `/cdocs`
or merge until the replay report is written and the 3 skipped tests become
PASS.

## Overall: PASS with 2 manual verifications PENDING

- **20/20** invariants structurally covered
- **5/5** prohibitions enforced
- **6/6** boundary conditions exercised
- **125/0** asserts (0 failures, 3 skips conditional on manual VP report)
- **0** uncovered rules
- **0** BLOCKING findings
- **0** drift
- **12** QA class fixes verified with structural tests
- **7** non-blocking QA follow-ups deferred to `/cdocs` drift-debt

**Blocking prerequisite for merge**: VP-001 + VP-002 manual execution in a fresh
Claude Code session after plugin reinstall, with results recorded in
`.correctless/verification/fix-diff-reviewer-migration-replay.md`. This cannot
be completed from the current session because the plugin cache does not yet
contain the agents directory.

**Recommended next step**: reinstall the plugin from this branch, restart
Claude Code, run VP-001 and VP-002, then run `/cdocs`.
