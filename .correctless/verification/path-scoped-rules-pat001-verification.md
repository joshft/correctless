# Verification: Migrate PAT-001 to path-scoped rule file

## Metadata
- **Feature**: path-scoped-rules-pat001-migration
- **Branch**: feature/path-scoped-rules-pat001-migration
- **Intensity**: high
- **Spec**: `.correctless/specs/path-scoped-rules-pat001.md`
- **Verification date**: 2026-04-10
- **Verifier**: /cverify (forked verification agent)
- **Canary report**: `.correctless/verification/path-scoped-rules-pat001-canary.md`

## Rule Coverage

### Summary
- Total invariants: 24 (INV-001..011, INV-015..027)
- Covered (genuine): 22
- Covered (weak): 0
- Uncovered: 0
- Deferred (manual/post-merge): 2 (INV-015 canary verified pre-merge; INV-022 idempotency is GREEN-phase shell fixture per spec)

### Matrix

| Invariant | Test location | Status | Notes |
|-----------|---------------|--------|-------|
| INV-001 | `tests/test-architecture-drift.sh::check_inv001` | covered | File existence + frontmatter validity + set equality on the two expected paths |
| INV-002 | `check_inv002` (a–e) | covered | All 5 clauses anchored with two verbatim substrings each; (b) violated-when, (c) QA-R1-004+QA-R1-005, (d) three test refs, (e) PAT-005/PAT-006 present + PAT-002/TB-001a absent |
| INV-003 | `check_inv003` + `check_inv003_real` | covered | Parser shape check PLUS dedicated real-file extraction asserting `see_count==1 && total_nonblank==1` for PAT-001; vacuous-pass cheat structurally blocked |
| INV-004 | `check_inv004` | covered | Uses `extract_see_link_paths` + `[ -f ]` (distinct treatment of broken symlinks); INV-011 case-2 proves detection |
| INV-005 | `check_inv005` | covered | Per-See-link frontmatter check via `check_rule_frontmatter`; INV-011 cases 3a/3b prove detection |
| INV-006 | `check_inv006` marker + INV-011 negative cases | covered | Fail-closed posture proven indirectly via 10-case harness (all assert non-zero exit + specific stderr diagnostic) |
| INV-007 | `check_inv007` | covered | awk state machine extracts `run:` blocks from `ci.yml`, `strip_shell_comments` strips `#`-lines in both CI and `tests/test.sh` paths; commented invocations do not count |
| INV-008 | `check_inv008` (b)(c) | covered | Scoped to 2026-04-05 and 2026-04-07 learning sections via `get_learning_entry_section`; (a) substring check was subsumed by INV-018 and removed per /simplify QUAL-003 |
| INV-009 | `check_inv009` + `check_inv009_prose` | covered | awk extracts mermaid code fence; asserts 4 tier node labels inside `[...]`/`(...)` brackets, no L5, no CLAUDE.md node, ≥1 arrow; prose scoped outside mermaid blocks |
| INV-010 | `check_inv010_self_scan` | covered | Strips heredoc bodies + comment-only lines before scanning for GNU-only extensions |
| INV-011 | `run_negative_cases` | covered | 8 negative fixtures + 2 F19 edge cases + positive-case anchor (clean fixture emits `migrated sections checked: N>=1`); each invokes real detection function and asserts class-specific stderr diagnostic |
| INV-015 | (manual canary) | deferred | Procedure executed pre-GREEN; evidence in `.correctless/verification/path-scoped-rules-pat001-canary.md` — three independent signals (native `Loaded .claude/rules/canary-*.md` UI indicator, unprompted UUID surfacing, verbatim recall). EA-003/ENV-005 verified. Canary file deleted. |
| INV-016 | `check_inv016` (a)(b) | covered | (a) `/cstatus` SKILL.md contains both `pat001-measurement-due.json` and `Measurement overdue`; (b) meta file regex-matches `"due_at_pr_count": 3` with trailing `[,}]` so `30`/`300` cannot false-match (QA-002 PERF fix A-012) |
| INV-017 | `check_inv017` | covered | `enumerate_pretooluse_hooks` + `parse_paths_list` → sorted set equality, catches both missing and extra entries |
| INV-018 | `check_inv018` | covered | Exact-phrase + broader awk line-based `/PAT-001/ && /\.correctless\/ARCHITECTURE\.md/` co-occurrence scan; narrowly self-excludes the drift test file only |
| INV-019 | `check_inv019` (a)(c)(d) | covered | (a) exact `exit 2 on unexpected input`; (c) single-line co-occurrence `persisted|persistence|persisting` + `20(24-27)` + `PR`/`pull request`; (d) 5 prohibited substrings asserted absent. (b) QA-R1 IDs check removed per /simplify QUAL-004 (covered by INV-002(c)) |
| INV-020 | `check_inv010_self_scan` | covered | Asserts `source lib.sh` + scans for local re-definition of 12 lib.sh function names |
| INV-021 | `check_inv021` | covered | Per scoped file: `head -20` + exact comment match including em-dash U+2014 |
| INV-022 | (GREEN-phase fixture) | deferred | Documented at drift test lines 22–25 as a GREEN-phase shell fixture per spec; not a merge-time drift check |
| INV-023 | `check_inv023` | covered | Full YAML frontmatter extraction (continuation-aware) + `Write(.claude/rules/` grep across every `skills/*/SKILL.md`; set equality against exact `{cspec, cdocs, cupdate-arch}` |
| INV-024 | `check_inv024` (a)(b) | covered | (a) literal `grep -F` + (b) `strip_shell_comments` + awk for any `.claude/` reference |
| INV-025 | `check_inv025` (a–e) | covered | Exact header (em-dash U+2014) + PAT-001/rule file + MG-001\|MG-002 + PRH-002 + exact Source attribution |
| INV-026 | `check_inv026` | covered | Exact dogfood marker substring |
| INV-027 | `check_inv027` (a–d) | covered | ABS-009/ENV-005/ENV-006 headings + awk state machine asserting ABS-009 blockquote is STRICTLY between `## Patterns` and `### PAT-001:` |

**Cheat paths evaluated**: INV-003 vacuous pass, INV-009 keyword-only file scan, INV-007 comment-match, INV-002 missing clauses 3/4, INV-019 hedge-around-anchor — all structurally blocked by the test strengthening applied during the test audit (BLOCKING findings A-001..A-004) and the /simplify pass.

## Prohibitions

| Prohibition | Verified | Evidence |
|-------------|----------|----------|
| PRH-001 | PASS | PAT-001 clause text lives only in `.claude/rules/hooks-pretooluse.md`. `.correctless/ARCHITECTURE.md` PAT-001 section is the 2-line index (heading + See-link) |
| PRH-002 | PASS | Rollback procedure documented in spec (items a–j); procedural, not merge-time executable |
| PRH-003 | PASS | `git diff main -- ARCHITECTURE.md` (root) empty — untouched |
| PRH-004 | PASS | PAT-002..PAT-010 section bodies byte-identical between main and HEAD (precise per-PAT awk diff returns empty). The spec's naive awk example has false positives on content after PAT-010 but the semantic intent is satisfied |
| PRH-005 | PASS | No new hook files, no `setup` modifications, no `skills/cwtf/` changes. Only additions to `hooks/workflow-gate.sh` and `hooks/sensitive-file-guard.sh` are the 1-line rule pointer comments (INV-021) |

## Dependencies

Correctless is a shell-only project — no language-level dependency file. `git diff main -- package.json go.mod Cargo.toml requirements.txt pyproject.toml` empty (expected).

Config changes: `.correctless/config/workflow-config.json` adds `bash tests/test-architecture-drift.sh` to the `commands.test` chain (required by `test-ci-hook-wiring.sh` PRH-002 — every test on disk must appear in commands.test). Change is minimal and consistent with INV-007 wiring.

## Architecture Compliance

- ✓ Rule file structure: frontmatter first, dogfood HTML comment, rule body with 5 verbatim clauses, Violated when, rationale with QA-R1 citations, Tests section, Related section (PAT-005 + PAT-006 only)
- ✓ ABS-009 follows ABS template matching ABS-001..ABS-008
- ✓ ENV-005, ENV-006 follow ENV template matching ENV-001..ENV-004
- ✓ Reader-note blockquote at line 117 references `**ABS-009**` and appears strictly between `## Patterns` and `### PAT-001:`
- ✓ `hooks/workflow-gate.sh` line 5 and `hooks/sensitive-file-guard.sh` line 5 each contain the exact rule pointer comment with em-dash U+2014
- ✓ `CLAUDE.md` line 95: new 2026-04-10 learning entry with exact header and all required components
- ✓ README Defense-in-Depth mermaid has 4 tiers (L1 Gate, L2 Audit Trail, L3 Path-scoped rules, L4 Skill Instructions); no L5, no CLAUDE.md node; prose line 157 updated to "four independent layers"
- ✓ `skills/cstatus/SKILL.md` measurement-overdue instruction block with required warning phrasing
- ✓ `skills/cspec/SKILL.md`, `skills/cdocs/SKILL.md`, `skills/cupdate-arch/SKILL.md` each have `Write(.claude/rules/*.md)` in allowed-tools (and no other skill does)
- ✓ `.gitattributes` LF enforcement for `.claude/rules/*.md` and `.correctless/ARCHITECTURE.md`

## QA Class Fixes Verified

- **QA-001** (circular self-reference): class check `check_qa_001_class` uses an awk scanner that for every `### YYYY-MM-DD — ... (PAT-NNN)` learning header records `cur_pat` and checks every body line for `See <cur_pat>`. Structural — catches any future self-referential learning entry. Instance fix: CLAUDE.md line 79 trailing `See PAT-005 for the PostToolUse counterpart.` removed. ✓
- **QA-002** (stalled back-fill): class check `check_qa_002_class` requires `skills/cdocs/SKILL.md` to contain all three anchors: `.correctless/meta/`, `created_at_commit`, `back-fill`. Structural — catches removal of the instruction for any future dormant-gate feature. Instance fix: `skills/cdocs/SKILL.md` "Back-fill Deferred Meta Fields" section with 4-step procedure using `git rev-parse HEAD`. ✓

Both class fixes are genuinely structural, not instance-patched.

## Smells

No TODO/FIXME/HACK/XXX in the new rule file or drift test. No debug statements. No commented-out code. The drift test uses `set -uo pipefail` (not `-e`) intentionally — the accumulate-failures pattern runs all checks and sums the FAIL count rather than aborting on the first failure (matches `tests/test-hook-sync.sh` style).

Stringly-typed literals (`PAT-001`, rule file path, etc.) flagged by /simplify QUAL-006 as deferred polish — not blocking, documented as optional follow-up.

## Drift

None found. Every spec-referenced file exists on disk:
- `.claude/rules/hooks-pretooluse.md`
- `.correctless/meta/pat001-measurement-due.json`
- `.correctless/verification/path-scoped-rules-pat001-canary.md`
- `tests/test-architecture-drift.sh`
- All 3 scoped skill SKILL.md files with updated allowed-tools

No `.correctless/meta/drift-debt.json` entries created for this feature.

## Spec Updates

Count: 0. Spec was not modified during TDD/QA.

## Test Suite Results

| Test file | Pass | Fail |
|-----------|------|------|
| `test-architecture-drift.sh` | 55 | 0 |
| `test-workflow-gate.sh` | 86 | 0 |
| `test-sensitive-file-guard.sh` | 101 | 0 |
| `test-hook-sync.sh` | 121 | 0 |
| `test-ci-hook-wiring.sh` | 71 | 0 |
| `test-token-aware-intensity.sh` | 63 | 0 |
| `test-token-tracking.sh` | 75 | 0 |
| `test-antipattern-scan.sh` | 224 | 0 |
| `test-lib.sh` | 41 | 0 |
| `test-allowed-tools-check.sh` | 11 | 0 |
| **Total** | **848** | **0** |

**Distribution mirror sync**: source ↔ `correctless/` mirror are byte-identical. `diff -q` on the 6 mirrored source files (2 hooks + 4 skills) returns empty. Running `bash sync.sh` produces no new changes.

The forked verifier initially flagged the mirror as stale because `git diff --exit-code -- correctless/` against the uncommitted working tree returned dirty — but that reflects the expected uncommitted state of a feature branch (source changes and their mirror changes must both land in the same commit). Re-verification after the verifier's own `sync.sh` run confirmed source and dist are in sync. The CI `Verify sync` step runs on committed state and will pass once source + mirror are committed together.

## Canary Evidence (INV-015)

`.correctless/verification/path-scoped-rules-pat001-canary.md` exists with a PASS verdict. Three independent evidence pieces: (1) native Claude Code `Loaded .claude/rules/canary-139ba453-...md` UI indicator, (2) unprompted UUID marker surfacing in the fresh-session agent's file summary, (3) explicit verbatim recall of `CANARY-MARKER-139ba453-87a1-490e-875a-e14eaa3eba16-END` on direct ask. EA-003 and ENV-005 verified. Canary file deleted before GREEN advanced.

## Overall

**PASS** — all 22 testable invariants covered by genuine non-vacuous tests, 2 deferred invariants documented with rationale, all 5 prohibitions hold, all 848 tests across 10 suites pass, QA class fixes are structural, source ↔ mirror byte-identical. No BLOCKING findings.

### Notes for downstream (/cdocs)

1. `.correctless/meta/pat001-measurement-due.json` has `created_at_commit: null` and requires back-filling at merge time per QA-002 instance fix. The new "Back-fill Deferred Meta Fields" section in `skills/cdocs/SKILL.md` has the procedure.
2. The 6 `correctless/` distribution mirror files (2 hooks + 4 skills) must be committed together with their source counterparts so the CI `Verify sync` step passes on the merge commit.
