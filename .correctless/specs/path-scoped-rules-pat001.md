# Spec: Migrate PAT-001 to path-scoped rule file

## Metadata
- **Created**: 2026-04-10
- **Status**: reviewed
- **Impacts**: none at merge time (dogfood migration — user-project rule generation is Feature B, deferred). Future-coupled with Feature B (see FUTURE-001) and FUTURE-005 (runtime rule-file write gate).
- **Branch**: feature/path-scoped-rules-pat001-migration
- **Research**: null (Anthropic `.claude/rules/` mechanism verified directly against https://code.claude.com/docs/en/memory during proposal review; runtime behavior verified via canary test per INV-015)
- **Recommended-intensity**: high
- **Intensity**: high
- **Intensity reason**: file path (rule file scopes `hooks/workflow-gate.sh` + `hooks/sensitive-file-guard.sh`) + TB-xxx ref (TB-001 via INV-019) + antipattern overlap (6 APs) + QA history (3+ prior features in adjacent areas) — project floor is high
- **Override**: none
- **Review findings**: 30 findings, all accepted (see Review Findings Summary)

## Context

Migrate `PAT-001: PreToolUse hook conventions` from `.correctless/ARCHITECTURE.md` into a new path-scoped rule file `.claude/rules/hooks-pretooluse.md` with YAML `paths:` frontmatter scoping to `hooks/workflow-gate.sh` and `hooks/sensitive-file-guard.sh`. The rule file becomes the canonical location for PAT-001's rule text; ARCHITECTURE.md retains only a fixed-shape index entry pointing at the rule file. A new structural drift test (`tests/test-architecture-drift.sh`) enforces the index-line shape and blocks merges on drift. The README's Defense in Depth diagram gets one new tier (L3 = path-scoped rules) slotted between audit trail (L2) and skill instructions (renumbered L4) — 4 tiers total, not 5.

This is the dogfood prototype for the broader rules-canonical / ARCHITECTURE-index pattern. It migrates exactly one PAT entry to validate the mechanism against a concrete baseline before expanding to other entries or to user-project rule generation (Feature B / product feature).

## Scope

**In scope:**

1. **Create `.claude/rules/hooks-pretooluse.md`** with `paths:` frontmatter and the full PAT-001 rule body — rule text verbatim, "Violated when" list, rationale section citing QA-R1-004/005 with dates and persistence duration, test references, related-PAT cross-references (PAT-005, PAT-006 only — see INV-002(e) and F9), dogfood marker HTML comment at top.

2. **Replace `.correctless/ARCHITECTURE.md`'s PAT-001 section** with a fixed-shape index entry: `### PAT-001: {title}` + blank line + `` See `.claude/rules/hooks-pretooluse.md`. `` + nothing else before the next heading.

3. **Add new entries to `.correctless/ARCHITECTURE.md`:**
   - **ABS-009** — Path-scoped rule files (.claude/rules/) abstraction
   - **ENV-005** — Claude Code `.claude/rules/` with `paths:` frontmatter mechanism
   - **ENV-006** — POSIX-portable external tool usage (grep/sed/awk)
   - A **reader note block** at the top of the `## Patterns` section explaining that some entries are migrated index lines pointing to `.claude/rules/`, with a reference to ABS-009.

4. **Create `tests/test-architecture-drift.sh`** — AP-005 structural test with the following checks:
   - Index-line shape for migrated PAT entries (state machine parser, skips fenced code blocks, handles nested headings correctly per F19)
   - See-link target existence (follows symlinks via `[ -f ]`, rejects broken symlinks per F20)
   - `paths:` frontmatter presence in every referenced rule file
   - Set equality between `HOOK_TYPE: PreToolUse` hooks in `hooks/*.sh` and the `paths:` list in `hooks-pretooluse.md` (INV-017)
   - Zero occurrences of stale "See PAT-001 in `.correctless/ARCHITECTURE.md`" across `hooks/`, `tests/`, and `CLAUDE.md` (INV-018)
   - Semantic integrity anchors in rule file body: literal clause-5 string, QA finding IDs, year + `persisted`/`persistence` (INV-019)
   - In-file rule pointer comments present in each scoped hook file (INV-021)
   - Allowed-tools allowlist check: only `/cspec`, `/cdocs`, `/cupdate-arch` have `Write(.claude/rules/...)` (INV-023)
   - `sync.sh` does not reference `.claude/rules/` (INV-024)
   - CLAUDE.md has the new 2026-04-10 learning entry (INV-025)
   - Rule file has dogfood marker HTML comment (INV-026)
   - Negative-case verification for 6 drift patterns (INV-011, F17)
   - Test sources `scripts/lib.sh` for `repo_root` (INV-020)
   - POSIX-portable external tools only (INV-010, F12 fold-in)

5. **Wire the new test into both CI and local test runner:**
   - `.github/workflows/ci.yml` — add drift test to `Run tests` step (INV-007)
   - `tests/test.sh` (or whichever file is the local test aggregator) — add drift test invocation (INV-007, F24)

6. **Update `CLAUDE.md`:**
   - Line 74: "See PAT-001 in `.correctless/ARCHITECTURE.md`" → "See `.claude/rules/hooks-pretooluse.md`"
   - Line 79: preserve "Contrast with PAT-001" structure, augment to cite `.claude/rules/hooks-pretooluse.md` alongside existing PAT-005 reference
   - **Add new learning entry** dated 2026-04-10 recording the rules-canonical / ARCHITECTURE.md index convention (INV-025)

7. **Update `README.md` Defense in Depth diagram** to 4 tiers (NOT 5):
   - L1 = Gate (PreToolUse hook, enforced)
   - L2 = Audit Trail (PostToolUse hook, enforced)
   - L3 = **Path-scoped rules (new, higher-adherence advisory)**
   - L4 = Skill instructions (formerly L3, subject to context fade)
   - **No L5.** CLAUDE.md is not a separate tier in the diagram. Adding one is scope creep the spec author introduced by accident — see F5.
   - Update README prose line 157: "three independent layers" → "four independent layers"

8. **Update scoped hook files with in-file rule pointer comments** (F14a, INV-021):
   - `hooks/workflow-gate.sh` — add header comment: `# Rule: .claude/rules/hooks-pretooluse.md (PAT-001 — fail-closed posture)`
   - `hooks/sensitive-file-guard.sh` — same comment

9. **Update source-file PAT-001 references** (F4, INV-018):
   - `hooks/token-tracking.sh` line 7 — update "NOT PAT-001 PreToolUse" reference to cite `.claude/rules/hooks-pretooluse.md` as the canonical location
   - `tests/test-hook-sync.sh` lines 544, 616 — same update
   - Any other file discovered during grep sweep

10. **Add `.gitattributes` entry** (F21) — enforce LF line endings for `.claude/rules/*.md` and `.correctless/ARCHITECTURE.md` to prevent CRLF edge cases in the drift test parser.

11. **Day-0 canary verification of `.claude/rules/` loading mechanism** (F1, INV-015):
    - Before implementation: create `.claude/rules/canary-{uuid}.md` with `paths: ["hooks/workflow-gate.sh"]` and a unique UUID marker in the body
    - Open `hooks/workflow-gate.sh` in a fresh Claude Code session
    - Verify the UUID marker is observable in the agent's context (agent can repeat it on request)
    - Record the session transcript hash or observation evidence in the feature's verification report
    - Delete the canary file before TDD RED phase completes
    - **If the canary fails, the feature does not proceed — EA-003 / ENV-005 is wrong and the whole mechanism must be reconsidered.**

**Out of scope (explicit):**

- PAT-002 through PAT-010 remain in `.correctless/ARCHITECTURE.md` unchanged. Only PAT-001 migrates in this feature.
- All other ABS-xxx, TB-xxx, and ENV-xxx entries remain in ARCHITECTURE.md unchanged (except the three new entries added in scope item 3).
- **Root `ARCHITECTURE.md`'s PAT-001 ("Source → Distribution Sync")** is a separate entry in a separate file with a separate namespace. Do not touch it. Namespace deduplication is a separate future feature if it becomes necessary.
- Historical verification reports in `.correctless/verification/*.md` are frozen artifacts. Do not rewrite them even if they reference PAT-001 by its pre-migration location.
- **The `InstructionsLoaded` hook and `/cwtf` correlation logic** are Feature B — separate spec, separate merge, gated on this feature's measurement (see MG-001). Without Feature B, the primary measurement signal (MG-001) cannot be directly measured at runtime and falls back to an indirect proxy. This is a known limitation; see OQ-001.
- `/csetup` user-project rule generation is the product version of this feature, also deferred and gated on this feature's measurement success (FUTURE-003).
- `setup`'s `register_hooks()` is not modified in this feature (no InstructionsLoaded hook to register yet — Feature B touches it).
- **Runtime write protection of `.claude/rules/` via `sensitive-file-guard.sh`** is deferred to FUTURE-005. Feature A ships with a static allowed-tools allowlist check (INV-023) as the convention-enforcement mechanism. Runtime hooks-based enforcement requires a chicken-and-egg-safe design that is out of scope for this feature.
- Bash-mediated write bypasses (`git apply`, `sed -i`, heredoc writes) to scoped hook files are NOT blocked by this feature. A runtime bash-write prohibition is deferred to FUTURE-006. Feature A mitigates the concern via in-file rule pointer comments (INV-021), which give non-Claude-Code editors visibility to the rule location.
- `/cpostmortem` SKILL.md is not modified in this feature. If future postmortems land on a 2-line ARCHITECTURE.md index entry, they will see the See-link and need to follow it. Update to `/cpostmortem` is deferred to a separate feature gated on the measurement result (OQ-005).

## Complexity Budget

- **Estimated LOC**: ~700 total (up from ~350 — review findings expanded scope substantially)
  - `.claude/rules/hooks-pretooluse.md`: ~100 lines (rule body + rationale + cross-references + dogfood marker + semantic integrity anchors)
  - `.correctless/ARCHITECTURE.md`: net -3 lines (5-line PAT-001 entry → 2-line index, plus ~30 lines added for ABS-009 + ENV-005 + ENV-006 + Patterns reader note)
  - `tests/test-architecture-drift.sh`: ~450 lines (16 invariant checks including set equality, semantic anchors, negative-case verification with 6 cases, nested heading + fenced code block handling, POSIX portability self-check, lib.sh sourcing)
  - `.github/workflows/ci.yml`: +1 line
  - `tests/test.sh` (or equivalent): +1 line
  - `CLAUDE.md`: 3 edits (lines 74, 79, new 2026-04-10 entry ~5 lines)
  - `README.md`: ~15 line diff (4-tier mermaid diagram + prose update)
  - `hooks/workflow-gate.sh`: +1 line (rule pointer comment)
  - `hooks/sensitive-file-guard.sh`: +1 line (rule pointer comment)
  - `hooks/token-tracking.sh`: 1 line edit
  - `tests/test-hook-sync.sh`: 2 line edits
  - `.gitattributes`: +2 lines (LF enforcement for .claude/rules/*.md and ARCHITECTURE.md)
  - `skills/cspec/SKILL.md`, `skills/cdocs/SKILL.md`, `skills/cupdate-arch/SKILL.md`: may need `Write(.claude/rules/hooks-pretooluse.md)` added to allowed-tools frontmatter (verify during GREEN)

- **Files touched**: ~13 (create 2, edit 11)

- **New abstractions**: 1 — `.claude/rules/` directory as a new canonical location for path-scoped rule content, formalized as **ABS-009** in ARCHITECTURE.md per F6.

- **Trust boundaries touched**: 0 direct. One indirect reference (the rule file's "Related" section mentions TB-001 as the boundary that PAT-001's fail-closed posture enforces at runtime — documentation only, no behavior change). Note: TB-001a is explicitly NOT referenced in the rule file per F9 (semantically unrelated to PreToolUse hooks).

- **Risk surface delta**: low-medium. Low runtime: no hook control-flow changes, no state machine changes. Medium structural: the feature introduces a new abstraction (ABS-009) and a new test file that will be consumed by FUTURE-002 migrations. If the shape check in the drift test has a bug, multiple future features inherit it.

## Evidence & Baseline

Day-0 baseline (computed 2026-04-10 before this feature began):

The last 5 hook-touching merged PRs on main were **#47, #46, #45, #44, #39**. PR #47 was a QA Olympics audit that caught two PAT-001 clause-5 violations in `hooks/workflow-gate.sh`:

- **QA-R1-005**: `workflow-gate.sh` had `|| exit 0` on the stdin `jq` parse failure path. Fail-open on unexpected input in a PreToolUse hook is a clause-5 violation — fail-closed means exit 2 on unexpected input, not exit 0. The finding's exact title: *"workflow-gate.sh fails closed on malformed stdin JSON (PAT-001)"*.
- **QA-R1-004**: Corrupted `workflow-config.json` defaulted `fail_closed_when_no_state` to `false`, silently degrading fail-closed posture to fail-open. Parallel clause-5 violation in the same file.

**Persistence metric (the gate this spec stakes its falsifiability on):**

Git archaeology (`git log -G'exit 0' -- hooks/workflow-gate.sh`) confirmed the `|| exit 0` pattern was present from PR #33 (commit `04666b0`, "Consolidate hook config") and persisted through PRs #35, #37, #38, #39, #45, #46 — **at least 7 hook-touching PRs where reviewers looked at the code and did not catch the violation**. Only PR #47's hostile-lens Olympics audit caught it. The clause-5 violation sat in main for ~4 days. Both violations are documented in `.correctless/artifacts/findings/audit-qa-2026-04-09-round-1.json`.

**Why the introduction-based metric was rejected:** only 2 PreToolUse hooks exist, recent PRs touched them only cosmetically, and the actual failure mode observed in the baseline is violations **persisting**, not violations being introduced frequently. A persistence-based metric matches the mechanism.

**Falsifiable gate: this feature succeeds only if the post-migration measurement (see MG-001, MG-002, MG-003) shows both a prevention signal (rule-in-context) and a persistence reduction (review-catch reaction time) relative to the ≥7-PR baseline.**

## Review Findings Summary

30 findings from `/creview-spec` (4-agent adversarial review 2026-04-10). All 30 accepted with one modification (F16 implemented as static allowed-tools allowlist instead of runtime sensitive-file-guard, to avoid chicken-and-egg bootstrap problem; runtime protection deferred to FUTURE-005).

| ID | Finding | Severity | Disposition | Resolution |
|----|---------|----------|-------------|------------|
| F1 | No day-0 canary verification of rules-load mechanism | CRITICAL | Accept | INV-015 (pre-merge canary test) |
| F2 | INV-012/013/014 mislabeled as invariants | CRITICAL | Accept | Reclassified to MG-001/002/003; new INV-016 dormant `/cstatus` check |
| F3 | Paths list is static allowlist, no drift check | CRITICAL | Accept | INV-017 (set equality with PreToolUse hooks) |
| F4 | Source-file PAT-001 references carve-out defeats mechanism | CRITICAL | Accept | Exemption removed; INV-018 (zero stale refs) |
| F5 | INV-009 diagram bundling — 4 tiers, not 5 | CRITICAL | Accept | INV-009 rewritten; CLAUDE.md L5 dropped |
| F6 | Missing ABS-009 entry | HIGH | Accept | ABS-009 added to ARCHITECTURE.md (scope item 3) |
| F7 | Missing ENV-005 | HIGH | Accept | ENV-005 added to ARCHITECTURE.md |
| F8 | Missing ENV-006 | HIGH | Accept | ENV-006 added to ARCHITECTURE.md |
| F9 | TB-001a cross-reference semantically wrong | HIGH | Accept | TB-001a and PAT-002 dropped from INV-002(e); TB-001 added in INV-019 rationale |
| F10 | PRH-004 line-number anchor brittle | HIGH | Accept | PRH-004 rewritten with content-based section delimiter |
| F11 | Rule content semantic integrity | HIGH | Accept | INV-019 (clause-5 literal + QA IDs + persistence year anchors) |
| F12 | Drift test should source scripts/lib.sh | HIGH | Accept | INV-020 (lib.sh sourcing) |
| F13 | INV-008 line 79 precision | HIGH | Accept | INV-008 rewritten for end-state assertion |
| F14a | In-file rule pointer comments | HIGH | Accept | INV-021 |
| F14b | Bash-write bypass prohibition | HIGH | Defer | FUTURE-006 |
| F15 | Migration idempotency test | HIGH | Accept | INV-022 |
| F16 | Rule file authorship enforcement | HIGH | Accept (modified) | INV-023 (static allowed-tools check); runtime gate → FUTURE-005 |
| F17 | Negative cases 3 → 6 | HIGH | Accept | INV-011 rewritten with 6 enumerated cases + positive-case assertion |
| F18 | TOCTOU atomic snapshot | MEDIUM | Defer | Documented as accepted risk in R1a |
| F19 | Nested heading + fenced code block parser | MEDIUM | Accept | BND-001 updated; INV-011 cases 7-8 added |
| F20 | BND-002 symlink self-contradiction | MEDIUM | Accept | BND-002 rewritten |
| F21 | Case sensitivity + CRLF edge cases | MEDIUM | Accept (modified) | EA-005 added; `.gitattributes` enforces LF |
| F22 | /cpostmortem consumer gap + reader note | MEDIUM | Accept | Reader note in ARCHITECTURE.md `## Patterns` section (scope item 3); OQ-005 documents skill-update deferral |
| F23 | Rule file size budget | MEDIUM | Defer | FUTURE-004 |
| F24 | Local test.sh invocation | MEDIUM | Accept | INV-007 updated |
| F25 | sync.sh exclusion regression test | MEDIUM | Accept | INV-024 |
| F26 | paths: matching semantics | MEDIUM | Accept | Folded into INV-015 canary test |
| F27 | CI ratchet for measurement gate | LOW | Defer | Dormant check in INV-016 is the lighter version; revisit if insufficient |
| F28 | New CLAUDE.md learning entry | LOW | Accept | INV-025 |
| F29 | OQ-005 future PAT destination | LOW | Accept | OQ-005 added |
| F30 | Dogfood marker in rule file | LOW | Accept | INV-026 (HTML comment); runtime enforcement → FUTURE-005 |

## Invariants

### INV-001: Rule file exists with path-scoped frontmatter
- **Type**: must
- **Category**: functional
- **Statement**: `.claude/rules/hooks-pretooluse.md` exists, is valid markdown, has YAML frontmatter as its first block, and the frontmatter contains a `paths:` key listing exactly two entries: `hooks/workflow-gate.sh` and `hooks/sensitive-file-guard.sh`.
- **Violated when**: the file is missing, the frontmatter is absent or malformed, the `paths:` key is missing, or the path list is wrong.
- **Guards against**: null
- **Test approach**: unit (structural file check + frontmatter grep in `tests/test-architecture-drift.sh`)
- **Risk**: medium

### INV-002: Rule file content is complete
- **Type**: must
- **Category**: functional
- **Statement**: The rule file body contains (a) the full PAT-001 rule text with all five clauses verbatim from the pre-migration ARCHITECTURE.md, (b) a "Violated when" list that names clause-5 fail-open as an explicit violation class, (c) a "Why clause 5 is strict about fail-closed" rationale section citing QA-R1-004 and QA-R1-005 with dates and persistence duration, (d) a "Tests" section referencing `tests/test-sensitive-file-guard.sh`, `tests/test-workflow-gate.sh`, and `tests/test-dynamic-rigor.sh`, (e) a "Related" section cross-referencing PAT-005 and PAT-006 (no PAT-002, no TB-001a — removed per F9). Semantic integrity anchors inside sections (a) and (c) are enforced separately by INV-019.
- **Violated when**: any of (a)–(e) is missing from the rule file body, OR unwanted cross-references to PAT-002 / TB-001a appear.
- **Guards against**: null (section presence only; content integrity is INV-019)
- **Test approach**: unit (structural section-presence grep in `tests/test-architecture-drift.sh`)
- **Risk**: medium

### INV-003: ARCHITECTURE.md PAT-001 entry matches index-line shape
- **Type**: must
- **Category**: functional
- **Statement**: The `### PAT-001:` section in `.correctless/ARCHITECTURE.md` contains exactly two non-blank lines between the heading and the next `###` / `##` / EOF: the `### PAT-001: {title}` heading line itself, and a single `` See `.claude/rules/hooks-pretooluse.md`. `` line. The awk parser must skip fenced code blocks (`` ``` ``) and must NOT treat `####` sub-headings as section boundaries (per F19). Any additional non-blank content between the heading and the next section boundary is a violation.
- **Violated when**: the section contains bullet points, paragraphs, code blocks, sub-headings, or any other content beyond the title heading and the See-link line.
- **Guards against**: AP-005, AP-006
- **Test approach**: unit (awk state-machine section-shape check in `tests/test-architecture-drift.sh`)
- **Risk**: high

### INV-004: See-link target exists
- **Type**: must
- **Category**: functional
- **Statement**: For every `` See `.claude/rules/{file}.md`. `` line in `.correctless/ARCHITECTURE.md` (excluding matches inside fenced code blocks), the target file exists at the referenced path relative to repo root. `[ -f ]` semantics apply — symlinks to real files pass, broken symlinks fail.
- **Violated when**: a See-link references a file that does not exist, or references a broken symlink.
- **Guards against**: AP-005
- **Test approach**: unit (file existence check in `tests/test-architecture-drift.sh`)
- **Risk**: medium

### INV-005: Referenced rule files have path-scoped frontmatter
- **Type**: must
- **Category**: functional
- **Statement**: For every rule file referenced from ARCHITECTURE.md via a See-link, the target file must have YAML frontmatter containing a `paths:` key.
- **Violated when**: a referenced rule file has no frontmatter, has frontmatter but no `paths:` key, or has malformed YAML in the frontmatter block.
- **Guards against**: null (structural prevention of a silent failure mode)
- **Test approach**: unit (frontmatter presence check)
- **Risk**: high

### INV-006: Drift test fails closed on drift
- **Type**: must
- **Category**: functional
- **Statement**: `tests/test-architecture-drift.sh` exits with code 1 (non-zero) when any of INV-003, INV-004, or INV-005 is violated. The test must NOT warn-and-pass. CI must block merges that violate these invariants.
- **Violated when**: the test exits 0 despite detectable drift.
- **Guards against**: AP-003
- **Test approach**: integration (negative-case verification per INV-011)
- **Risk**: critical

### INV-007: Drift test wired into CI and local test runner
- **Type**: must
- **Category**: functional
- **Statement**: `tests/test-architecture-drift.sh` is invoked by BOTH `.github/workflows/ci.yml`'s `Run tests` step (covering both jq matrix legs since it is shell-only, not jq-dependent) AND the project's local aggregate test runner (`tests/test.sh` or equivalent — verify which file serves this role during GREEN). Local contributors must catch drift before CI.
- **Violated when**: the test is wired only to CI and not to the local runner, or vice versa, or behind a conditional that prevents it from running on all code paths.
- **Guards against**: AP-007
- **Test approach**: integration (parse ci.yml and the local runner for the test invocation)
- **Risk**: high

### INV-008: CLAUDE.md PAT-001 references are accurate post-migration
- **Type**: must
- **Category**: functional
- **Statement**: After migration, `CLAUDE.md` has: (a) zero occurrences of the substring `` See PAT-001 in `.correctless/ARCHITECTURE.md` `` (case-insensitive); (b) line 74's Correctless Learning (2026-04-05 PreToolUse convention) rewritten to cite `.claude/rules/hooks-pretooluse.md`; (c) line 79's Correctless Learning (2026-04-07 PostToolUse convention) preserves its "Contrast with PAT-001" structure but augments the parenthetical to include the new rule-file location; (d) exactly two occurrences of the substring `` See `.claude/rules/hooks-pretooluse.md` `` attributable to the rewrites plus any new learning entry added by INV-025. The learning metadata (dates, observed-in counts) is unchanged.
- **Violated when**: any stale reference remains, or the rewrite changes learning content beyond the location update.
- **Guards against**: AP-005
- **Test approach**: unit (grep for stale and new substrings; count occurrences)
- **Risk**: medium

### INV-009: README Defense in Depth diagram has 4 tiers
- **Type**: must
- **Category**: functional
- **Statement**: The README's "Defense in Depth" mermaid diagram contains node labels for **four** distinct tiers in the following order: (L1) Gate / PreToolUse hook, (L2) Audit Trail / PostToolUse hook, (L3) Path-scoped rules (**new**, labeled as "higher-adherence advisory"), (L4) Skill instructions (formerly L3, labeled as "subject to context fade"). **No L5.** CLAUDE.md is NOT a separate tier in the diagram — adding one is out of scope for this feature (F5). The enforced-vs-advisory distinction must remain visually clear: L1 and L2 have solid edges / colored fills; L3 and L4 have dashed edges / differentiated fills (L3 warmer color to signal higher adherence, L4 gray to signal context fade). The README prose line 157 must be updated from "three independent layers" to "four independent layers."
- **Violated when**: the diagram has fewer than 4 or more than 4 tiers, is missing the L3 path-scoped rules node, adds an L5 CLAUDE.md tier, loses the enforced-vs-advisory visual distinction, or the prose line 157 still says "three."
- **Guards against**: AP-005
- **Test approach**: unit (grep the README mermaid block for the four required node labels AND the updated prose line)
- **Risk**: medium

### INV-010: Drift test uses POSIX-portable external tools
- **Type**: must
- **Category**: functional
- **Statement**: `tests/test-architecture-drift.sh` uses only POSIX-compatible `grep`, `sed`, and `awk` — no `grep -P` (Perl regex), no `\b` (word boundary) outside bracket expressions, no `\s` outside bracket expressions, no GNU-only `sed -i` without backup arg, no GNU `awk` extensions (`gensub`, `PROCINFO`, `length(array)`, etc.). Bash 4+ constructs (`${var,,}`, `[[ =~ ]]`, arrays, `local`) are permitted per EA-001. The drift test sources `scripts/lib.sh` for `repo_root` and must NOT locally re-implement lib.sh functions (INV-020).
- **Violated when**: the test file contains any GNU-only extension OR any local re-implementation of lib.sh functions.
- **Guards against**: AP-001, AP-011, ABS-001 violation
- **Test approach**: unit (tests/test-antipattern-scan.sh or self-check — scan excludes `#`-prefixed comment lines and heredoc bodies to avoid false positives on documented-but-not-used patterns)
- **Risk**: high

### INV-011: Drift test includes six negative-case verifications plus a positive assertion
- **Type**: must
- **Category**: functional
- **Statement**: `tests/test-architecture-drift.sh` includes at least **six** negative-case verification tests that construct synthetic drifted inputs and assert the drift-detection functions return non-zero. Each negative case must (a) invoke the real detection function against the synthetic input, (b) assert exit code is non-zero, (c) assert stderr contains a specific diagnostic substring matching the drift class being tested. The six cases are:
  1. PAT-NNN section with a See-link AND additional bullet-list body content (shape violation)
  2. See-link pointing at a nonexistent rule file (broken target)
  3. Rule file missing the `paths:` frontmatter (missing frontmatter)
  4. Malformed See-link line (valid target path, wrong line shape — e.g., `See .claude/rules/foo.md` without backticks)
  5. Non-migrated PAT section with "See" prose in the body — the parser must NOT trigger on this (false-positive guard)
  6. Multi-migration fixture: two migrated PAT sections, first clean, second drifted — parser must catch the second without short-circuiting on the first
- **Plus two F19 edge cases:**
  7. PAT section containing a `####` sub-heading — parser must not treat it as a section boundary
  8. See-link format example inside a fenced code block — parser must skip fenced blocks and not treat the example as a real See-link
- **Plus a mandatory positive-case assertion:** the clean-state test must confirm at least one migrated section was actually checked (not just "zero violations found"). Emit `migrated sections checked: N` on stdout or stderr and assert `N >= 1`.
- **Violated when**: fewer than 6 negative cases exist, any negative case is structural-only (keyword scan without function invocation), the exit-code assertion is missing, the stderr-substring assertion is missing, OR the positive-case count assertion is missing.
- **Guards against**: AP-003, AP-007
- **Test approach**: integration (the drift test IS the test — its own run executes the negative and positive cases)
- **Risk**: critical

### INV-015: Pre-merge canary verification of rules-load mechanism (F1)
- **Type**: must
- **Category**: functional
- **Statement**: Before this feature's GREEN phase is considered complete, a canary test must verify that Claude Code's `.claude/rules/` + `paths:` frontmatter mechanism actually loads rule content into the agent's editing context. Procedure: (1) create `.claude/rules/canary-{UUID}.md` with `paths: ["hooks/workflow-gate.sh"]` and a unique UUID marker string in the body; (2) start a fresh Claude Code session; (3) open `hooks/workflow-gate.sh` for editing (any Edit/Write/MultiEdit tool invocation); (4) verify the UUID marker is observable in the agent's context (agent can repeat the string when asked); (5) record the session evidence (transcript hash, agent response excerpt, or screenshot) in `.correctless/verification/path-scoped-rules-pat001-canary.md`; (6) delete the canary file before merge. This canary also verifies F26 (paths matching semantics — exact string vs glob) by testing the literal exact-path form.
- **Violated when**: the canary is not executed, the UUID is not observable, the canary file persists past merge, or the verification report is missing.
- **Guards against**: null (this is the primary EA-003/ENV-005 verification — without it, the feature ships on an unverified assumption)
- **Test approach**: integration (manual procedure with artifact evidence; automated enforcement via GREEN-phase checklist)
- **Risk**: critical — if the canary fails, the feature does not proceed; the mechanism assumption is wrong and the whole approach must be reconsidered

### INV-016: Dormant `/cstatus` measurement-overdue check (F2)
- **Type**: must
- **Category**: functional
- **Statement**: `skills/cstatus/SKILL.md` contains instructions to check for a measurement-overdue condition and emit a warning banner. The condition: if `.correctless/meta/pat001-measurement-due.json` exists AND its `due_at_pr_count` field has been reached (hook-touching PR count since feature merge) AND no corresponding measurement report exists at `.correctless/verification/path-scoped-rules-pat001-measurement.md`, emit a warning: "Measurement overdue: path-scoped-rules-pat001 — run measurement gate per MG-003 or roll back per PRH-002." The file `.correctless/meta/pat001-measurement-due.json` is created in the same GREEN commit as the rule file, with `due_at_pr_count: 3` (matching MG-002).
- **Violated when**: the `/cstatus` instruction is missing, the meta file is not created, or the warning phrasing is absent.
- **Guards against**: null (forcing function for MG-001/002/003)
- **Test approach**: unit (grep `skills/cstatus/SKILL.md` for the required instruction block + verify `.correctless/meta/pat001-measurement-due.json` exists post-GREEN)
- **Risk**: high — this is the only merge-time-testable enforcement for the measurement gate

### INV-017: Paths list set equality with PreToolUse hook discovery (F3)
- **Type**: must
- **Category**: functional
- **Statement**: The `paths:` list in `.claude/rules/hooks-pretooluse.md` must be set-equal to the set of `hooks/*.sh` files whose first 10 lines contain `# HOOK_TYPE: PreToolUse` (per ABS-004 / PAT-006). Every entry in the paths list must resolve to an existing PreToolUse hook, and every PreToolUse hook must appear in the paths list. The drift test enumerates both sets and asserts equality.
- **Violated when**: a new PreToolUse hook is added to `hooks/` without updating the rule file's paths list, OR the paths list contains a filename that is not a PreToolUse hook.
- **Guards against**: null (structural prevention of the hook-allowlist drift class, cf. ABS-001 origin)
- **Test approach**: unit (enumerate HOOK_TYPE headers across `hooks/*.sh`, parse the paths list from the rule file frontmatter, assert set equality)
- **Risk**: critical

### INV-018: Zero stale PAT-001 ARCHITECTURE.md references across hooks and tests (F4)
- **Type**: must
- **Category**: functional
- **Statement**: After migration, grep across `hooks/*.sh`, `tests/*.sh`, and `CLAUDE.md` for the substring `PAT-001 in .correctless/ARCHITECTURE.md` (case-insensitive) must return zero matches. The exemption of source-file references from INV-008 is explicitly REMOVED — every file that cites PAT-001's old location must be updated to cite the new rule file location. Files that cite PAT-001 as a stable ID anchor (e.g., `# PAT-005 PostToolUse conventions (NOT PAT-001 PreToolUse)` in `hooks/token-tracking.sh`) must be updated to also reference `.claude/rules/hooks-pretooluse.md` when they include location context — the bare ID anchor is still permitted, but any sentence that says "in ARCHITECTURE.md" must be updated.
- **Violated when**: any file contains `PAT-001 in .correctless/ARCHITECTURE.md` post-migration.
- **Guards against**: AP-005
- **Test approach**: unit (repository-wide grep)
- **Risk**: critical — without this, the dogfood mechanism fails in exactly the files it is supposed to protect (F4)

### INV-019: Rule file semantic integrity anchors (F11)
- **Type**: must
- **Category**: functional
- **Statement**: `.claude/rules/hooks-pretooluse.md` contains three literal text anchors that the drift test greps for: (a) the exact string `exit 2 on unexpected input` — must appear as part of clause 5's verbatim text, no carve-outs or environment-gated exceptions permitted in the surrounding paragraph; (b) the exact strings `QA-R1-004` and `QA-R1-005` — historical audit finding IDs must be preserved; (c) the exact string `persisted` or `persistence` appearing within ~200 characters of a 4-digit year — the failure story must retain its concrete persistence duration. Additionally, the rule file must NOT contain any of the following prohibited substrings (which would indicate a semantic weakening rewrite): `except in development`, `unless $`, `can exit 0`, `may exit 0`, `weakened for debuggability`. This is a **cheap anchor grep**, not a content hash — intentionally tolerant of whitespace and reordering but hostile to semantic erosion.
- **Violated when**: any required anchor is missing OR any prohibited substring is present.
- **Guards against**: AP-005 (rule body drift via semantic rewrite)
- **Test approach**: unit (static grep in `tests/test-architecture-drift.sh`)
- **Risk**: critical — without semantic anchors, structural presence checks would permit silent rule weakening (Red Team Attack A1/B1)

### INV-020: Drift test sources scripts/lib.sh for shared helpers (F12)
- **Type**: must
- **Category**: functional
- **Statement**: `tests/test-architecture-drift.sh` sources `scripts/lib.sh` at the top (after `set -euo pipefail`) and uses its helpers (`repo_root`, `classify_file`, etc.) rather than reimplementing them locally. Any local definition of a function that also exists in `scripts/lib.sh` is a violation.
- **Violated when**: the test file defines `repo_root()`, `branch_slug()`, or any other lib.sh function locally OR does not source lib.sh.
- **Guards against**: ABS-001 violation
- **Test approach**: unit (grep the test file for `source.*lib.sh` presence AND for local definitions of known lib.sh function names)
- **Risk**: high (same class as the 4-way hook allowlist duplication that ABS-001 was created to fix)

### INV-021: In-file rule pointer comments in scoped hook files (F14a)
- **Type**: must
- **Category**: functional
- **Statement**: Each file listed in `.claude/rules/hooks-pretooluse.md`'s `paths:` list contains a comment within the first 20 lines referencing the rule file. Exact format: `# Rule: .claude/rules/hooks-pretooluse.md (PAT-001 — fail-closed posture)`. This comment is visible in git diffs, GitHub file views, plain editors, and agent Read contexts — it is a belt-and-suspenders defense against `InstructionsLoaded` failing or bash-mediated edits (F14b, deferred).
- **Violated when**: any scoped hook file lacks the rule pointer comment in its first 20 lines.
- **Guards against**: null (mitigation for F14b deferral and for non-Claude-Code editing paths)
- **Test approach**: unit (head -20 on each scoped file, grep for the required comment format)
- **Risk**: medium

### INV-022: Migration idempotency (F15)
- **Type**: must
- **Category**: functional
- **Statement**: Running the migration steps twice produces the same end-state as running them once. Specifically: after the GREEN phase commit, reverting ONLY `.correctless/ARCHITECTURE.md` to its pre-migration content and re-running the migration must produce byte-identical output to the GREEN commit (modulo timestamps in verification reports). Tested by a shell fixture during GREEN.
- **Violated when**: re-running the migration produces different output, duplicate content, or fails.
- **Guards against**: AP-002 (silent conditional-update failure), AP-004 (partial migration state), PAT-008 violation
- **Test approach**: integration (shell fixture in GREEN phase, diffs the result)
- **Risk**: medium

### INV-023: Rule file authorship allowlist check (F16, modified)
- **Type**: must
- **Category**: functional
- **Statement**: Exactly three skill files contain `Write(.claude/rules/hooks-pretooluse.md)` (or equivalent glob) in their `allowed-tools` frontmatter: `skills/cspec/SKILL.md`, `skills/cdocs/SKILL.md`, `skills/cupdate-arch/SKILL.md`. No other skill file has Write permission on `.claude/rules/`. This is a **static check** — no runtime enforcement via sensitive-file-guard is added in this feature (to avoid chicken-and-egg bootstrap problem; runtime enforcement is deferred to FUTURE-005). The static allowlist is the convention enforcement for Feature A.
- **Violated when**: any other skill file has Write permission on `.claude/rules/`, OR any of the three allowed skills lacks the permission (if they need it).
- **Guards against**: abstraction erosion (ABS-009 integrity)
- **Test approach**: unit (grep skill frontmatters for `Write(.claude/rules/` patterns, assert allowlist)
- **Risk**: high (without this, any future skill could silently author rule files without following the experimental-validity discipline of DD-004)

### INV-024: sync.sh exclusion regression test (F25)
- **Type**: must
- **Category**: functional
- **Statement**: `grep -F ".claude/rules" sync.sh` returns zero matches, AND `grep -F ".claude/" sync.sh` returns matches ONLY inside comments (not in active sync target lists). A future edit to `sync.sh` that propagates `.claude/rules/` into the `correctless/` distribution would fail this check.
- **Violated when**: `sync.sh` references `.claude/rules/` or uncommented `.claude/` in its sync logic.
- **Guards against**: EA-004 violation (propagating dogfood rules to user distributions)
- **Test approach**: unit (grep `sync.sh`)
- **Risk**: medium

### INV-025: New CLAUDE.md learning entry for migration convention (F28)
- **Type**: must
- **Category**: functional
- **Statement**: After the GREEN phase, `CLAUDE.md`'s `## Correctless Learnings` section contains a new entry with these exact components: (a) a dated header `### 2026-04-10 — Convention introduced: rules-canonical / ARCHITECTURE.md index` (exact date), (b) bullet text stating that PAT-001 was migrated to `.claude/rules/hooks-pretooluse.md` as the first dogfood prototype, (c) a reference to the measurement gate MG-001/MG-002, (d) a reference to PRH-002 rollback, (e) source attribution `Source: /cspec after path-scoped-rules-pat001`.
- **Violated when**: the entry is missing, has a wrong date, or is missing any required component.
- **Guards against**: AP-005 (future agents losing awareness of the convention's provisional status)
- **Test approach**: unit (grep `CLAUDE.md` for the required components)
- **Risk**: medium

### INV-026: Dogfood marker HTML comment in rule file (F30)
- **Type**: must
- **Category**: functional
- **Statement**: `.claude/rules/hooks-pretooluse.md` contains a leading HTML comment before the YAML frontmatter... wait, frontmatter must be first. So the marker is a comment in the body, after the frontmatter, near the top: `<!-- DOGFOOD: Correctless-internal rule. Do not copy as a user-project template; see FUTURE-003. This rule references Correctless-specific audit finding IDs (QA-R1-004/005) that are meaningless outside this project. -->`. This marker warns Feature B implementers (FUTURE-003) against using the dogfood file as a verbatim template.
- **Violated when**: the marker is missing, has the wrong wording, or appears in a non-dogfood rule file (future Feature B user-project rules must NOT have this marker).
- **Guards against**: null (mitigation for Red Team Attack D2)
- **Test approach**: unit (grep the rule file for the required marker substring)
- **Risk**: low

### INV-027: ARCHITECTURE.md contains ABS-009, ENV-005, ENV-006, and Patterns reader note (F6/F7/F8/F22)
- **Type**: must
- **Category**: functional
- **Statement**: After migration, `.correctless/ARCHITECTURE.md` contains four new structured entries:
  1. **ABS-009** in the Abstractions section, documenting path-scoped rule files as a formal abstraction (What / Invariant / Enforced at / Violated when / Test fields, per the ABS template used by ABS-001 through ABS-008).
  2. **ENV-005** in the Environment Assumptions section, documenting Claude Code's `.claude/rules/` + `paths:` frontmatter mechanism (Assumption / Consequence if wrong / Test fields, per the ENV template).
  3. **ENV-006** in the Environment Assumptions section, documenting POSIX-portable grep/sed/awk usage (Assumption / Consequence if wrong / Test fields).
  4. A **reader note block** at the top of the `## Patterns` section (before `### PAT-001:`), formatted as a blockquote, explaining that some PAT entries are migrated index lines with See-links and referencing ABS-009 for the governing contract.
- **Violated when**: any of the four entries is missing or malformed.
- **Guards against**: null (structural documentation of the new abstraction)
- **Test approach**: unit (grep for the required headings and anchor substrings in ARCHITECTURE.md)
- **Risk**: medium

## Post-Merge Measurement Gate

This section describes falsifiability commitments that **cannot be tested at merge time**. They are NOT invariants. They will be evaluated during a scheduled post-merge measurement cycle enforced by INV-016's dormant `/cstatus` check. They do not gate the merge of Feature A; they gate the feature's **continued acceptance** and the decision to proceed to Feature B (FUTURE-001) and to the product-level rollout (FUTURE-003).

### MG-001: Primary measurement signal — rule-in-context prevention (formerly INV-012)
- **Measurable**: only after Feature B (`InstructionsLoaded` hook, FUTURE-001) ships
- **Evaluator**: `/cverify` post-Feature-B, run during the measurement cycle
- **Falsification criterion**: if a future Olympics audit finds a PAT-001 clause-5 violation in `hooks/workflow-gate.sh` or `hooks/sensitive-file-guard.sh`, AND the instructions-loaded log for the session where the violation was introduced shows the rule file was successfully loaded at the time of the edit, then the primary signal has failed. The rule was in context and did not prevent the violation.
- **At merge time**: this commitment is recorded; not checked. Feature A's merge does not depend on MG-001 passing.
- **Indirect proxy available pre-Feature-B**: before Feature B ships, MG-001 can only be measured via git archaeology — check whether the rule file existed at the time of each hook edit, and whether a violation was introduced. This is weaker but available.

### MG-002: Safety-net signal — persistence ceiling (formerly INV-013)
- **Measurable**: after 3+ hook-touching merged PRs have landed post-Feature-A
- **Evaluator**: manual git-archaeology audit
- **Falsification criterion**: any PAT-001, PAT-005, or PAT-006 violation that persists across 3 or more merged PRs touching `hooks/*.sh` fails this signal. The 3-PR ceiling is roughly half the observed baseline (7+ PRs) rounded down. At the project's current rate of ~2-3 hook PRs/quarter, this gate can fire within 1-2 quarters.
- **At merge time**: this commitment is recorded; not checked.

### MG-003: Measurement gate procedure (formerly INV-014)
- **Trigger**: hook-touching PR count since merge reaches `due_at_pr_count` (3) per `.correctless/meta/pat001-measurement-due.json`. Enforced by INV-016's dormant `/cstatus` check.
- **Procedure**:
  1. For each touched hook file, run `git log -G` searches for fail-open patterns (`|| exit 0`, `exit 0` on jq parse failure, etc.) across all PRs since Feature A merge.
  2. If any violations are found, cross-reference against the instructions-loaded.jsonl log (once Feature B ships) to classify as primary-signal failure (MG-001) or safety-net failure (MG-002).
  3. Classify result as one of: `prevention_observed` (MG-001 passed), `safety_net_observed` (MG-001 not evaluable, MG-002 passed), `inconclusive` (neither signal could be meaningfully evaluated — reset the ratchet for another window, up to 3 cycles / 9 PRs max before auto-rollback), or `fail` (any violation that is not safely caught by the next hook-touching PR).
  4. If the result is `fail`, execute PRH-002 rollback.
  5. If the result is `prevention_observed` or `safety_net_observed`, record in `.correctless/verification/path-scoped-rules-pat001-measurement.md` and update `.correctless/meta/pat001-measurement-due.json` with `measurement_completed_at: <commit>` and the result. Delete the dormant trigger.
  6. If the result is `inconclusive`, reset the PR counter and extend the window. Cap at 3 consecutive inconclusive cycles.
- **At merge time**: MG-003 is not directly testable. The merge-time-testable artifact is INV-016 (dormant check presence) and the creation of `.correctless/meta/pat001-measurement-due.json` by the GREEN phase.

## Prohibitions

### PRH-001: No PAT-NNN content duplication between ARCHITECTURE.md and rules
- **Statement**: For any PAT-NNN ID, the rule text MUST exist in exactly one of two locations: `.correctless/ARCHITECTURE.md` (full-body entry for non-migrated PATs) OR `.claude/rules/{file}.md` (full-body rule file for migrated PATs, with ARCHITECTURE.md containing only the index-line entry). Duplication is strictly prohibited.
- **Detection**: `tests/test-architecture-drift.sh` — INV-003 shape check.
- **Consequence**: Duplication invites drift (AP-005).

### PRH-002: Rollback procedure if measurement gate fails
- **Statement**: If MG-001 or MG-002 fails during the post-merge measurement cycle, the feature MUST be rolled back to the pre-migration state. Rollback procedure: (a) restore the full PAT-001 rule text to `.correctless/ARCHITECTURE.md`; (b) delete `.claude/rules/hooks-pretooluse.md`; (c) revert `CLAUDE.md`'s learning entry rewrites to cite ARCHITECTURE.md as the PAT-001 location; (d) revert the 2026-04-10 Convention introduced learning entry (per INV-025); (e) revert the README Defense in Depth diagram to 3 tiers; (f) revert the in-file rule pointer comments in scoped hooks; (g) revert the source-comment updates in `hooks/token-tracking.sh` and `tests/test-hook-sync.sh`; (h) remove the four ARCHITECTURE.md additions (ABS-009, ENV-005, ENV-006, Patterns reader note); (i) remove `.correctless/meta/pat001-measurement-due.json`; (j) **leave `tests/test-architecture-drift.sh` in place** as inert infrastructure — with no migrated PAT entries remaining, all checks become no-ops, and the infrastructure is preserved for a future retry.
- **Detection**: procedural — triggered by MG-003's gate procedure finding a violation.
- **Consequence**: Without rollback, a failed experiment leaves the project in a half-migrated state.

### PRH-003: Root ARCHITECTURE.md is untouchable
- **Statement**: Root-level `ARCHITECTURE.md` (the repo-root file, NOT `.correctless/ARCHITECTURE.md`) MUST NOT be modified in this feature. Its PAT-001 is a separate entry ("Source → Distribution Sync") in a separate namespace.
- **Detection**: `git diff main...HEAD -- ARCHITECTURE.md` must return empty.
- **Consequence**: Namespace-collision resolution is a separate feature.

### PRH-004: No migration of PAT-002 through PAT-010 (content-anchored, not line-anchored)
- **Statement**: PAT-002 through PAT-010 entries in `.correctless/ARCHITECTURE.md` MUST remain in their current full-body form. Only PAT-001 migrates in this feature.
- **Detection**: Use an awk content-anchored check, not line numbers. Run `awk '/^### PAT-[0-9]+:/{id=$2} id && id != "PAT-001:" {print}' .correctless/ARCHITECTURE.md` on both main and the feature branch; the outputs must be byte-identical. This is robust to upstream edits elsewhere in the file.
- **Consequence**: Migrating multiple PATs simultaneously destroys the day-0 baseline's experimental validity.

### PRH-005: No InstructionsLoaded hook in this feature
- **Statement**: This feature MUST NOT add an `InstructionsLoaded` hook, MUST NOT modify `setup`'s `register_hooks()` to support `InstructionsLoaded`, and MUST NOT introduce `/cwtf` correlation logic. All belong to Feature B (FUTURE-001).
- **Detection**: `git diff main...HEAD` shows no new files in `hooks/`, no modifications to `setup` or `skills/cwtf/`.
- **Consequence**: Bundling Feature B violates the "one migration + one gate" discipline.

## Boundary Conditions

### BND-001: Drift test input — ARCHITECTURE.md may contain mixed migration state, nested headings, and fenced code blocks
- **Boundary**: `tests/test-architecture-drift.sh` input is `.correctless/ARCHITECTURE.md`, which may contain: zero or more migrated PAT entries, zero or more non-migrated entries, `####` sub-headings within sections (F19), fenced code blocks (`` ``` ``) containing example See-link syntax (F19), and arbitrary prose.
- **Input from**: the repository working tree
- **Validation required**: the awk state-machine parser must (a) correctly identify `### PAT-NNN:` headings as section starts, (b) delimit each section at the next `###` or `##` heading OR EOF (NOT at `####` sub-headings), (c) skip fenced code blocks entirely when scanning for See-link substrings, (d) classify each section as migrated (contains a real See-link) or non-migrated, (e) apply the shape check only to migrated sections. The parser must emit a diagnostic and fail-closed on any section it cannot classify.
- **Failure mode**: fail-closed — unclassifiable input → exit 1 with diagnostic.

### BND-002: Drift test file-system boundary — See-link targets (rewritten per F20)
- **Boundary**: For every See-link in ARCHITECTURE.md, the referenced rule file must exist on disk at the referenced path relative to the repo root.
- **Input from**: the repository working tree
- **Validation required**: resolve the See-link path relative to repo root and verify via `[ -f "$path" ]`. `[ -f ]` follows symlinks to real files (this is intentional — Claude Code docs explicitly support symlinked rule files for sharing across projects) and returns false for broken symlinks. The spec's earlier "do NOT follow symlinks silently" wording was self-contradictory and is removed.
- **Failure mode**: fail-closed — `[ -f ]` returns false → exit 1 with diagnostic indicating whether the path is missing or is a broken symlink.

### BND-003: Drift test frontmatter boundary — rule file YAML
- **Boundary**: For every referenced rule file, the file must have YAML frontmatter with a `paths:` key on LF line endings (CRLF is prohibited; `.gitattributes` enforces).
- **Input from**: the repository working tree
- **Validation required**: verify line 1 is exactly `---` (LF-only, no `\r`), scan forward for closing `---` within the first 20 lines, grep for `^paths:` inside the frontmatter block. Presence-check only; full YAML parsing is out of scope.
- **Failure mode**: fail-closed — any missing delimiter, missing key, CRLF endings, or malformed block → exit 1 with diagnostic.

## STRIDE Analysis

This feature does not touch any trust boundary directly. The STRIDE analysis is minimal — included because the spec is at high intensity and PAT-001 governs PreToolUse hooks which are the runtime enforcement of TB-001.

**For TB-001 (config-sourced commands, governed by PAT-001's fail-closed posture):**

- **Spoofing**: N/A — the migration does not change identity assertion.
- **Tampering**: The migration moves rule text from one file to another. An attacker with write access to the repo could tamper with either location, but they already had write access before the migration. Mitigations added by this feature: INV-019 semantic anchors (catch silent rewrites), INV-021 in-file pointer comments (visible in non-Claude contexts), INV-023 static allowed-tools allowlist (convention enforcement). Runtime tampering mitigations are deferred to FUTURE-005 (sensitive-file-guard addition) and FUTURE-006 (bash-write prohibition).
- **Repudiation**: N/A.
- **Information Disclosure**: N/A — rule text is public convention, not secret.
- **Denial of Service**: The drift test runs in CI. A malformed rule file could, in principle, cause the awk parser to infinite-loop. Mitigation: awk is line-oriented by default and the parser has a bounded state machine (BND-001 enforces fail-closed on unclassifiable input). Not a realistic DoS vector.
- **Elevation of Privilege**: N/A.

**Summary**: the feature's security impact is meta — it tightens the loop between PAT-001's written form and the agent's in-context exposure to it. Semantic integrity anchors (INV-019) and in-file pointer comments (INV-021) strengthen the defense-in-depth at multiple layers. Runtime protections for the rule file itself (FUTURE-005/006) are deferred.

## Environment Assumptions

- **EA-001**: Bash 4+ for hooks, scripts, and the drift test — refs ENV-001. Bash 4+ constructs (`${var,,}`, `[[ =~ ]]`, arrays, `local`) are permitted; consequence if wrong: silent failure on macOS default Bash 3.2.
- **EA-002**: POSIX-compatible `grep`/`sed`/`awk` external tools — refs the new ENV-006 added by this feature (INV-027). Consequence if wrong: GNU extensions silently fail on macOS BSD tools. INV-010 enforces at the drift-test level.
- **EA-003**: Claude Code version supporting `.claude/rules/` with `paths:` frontmatter — refs the new ENV-005 added by this feature. Consequence if wrong: the rule file is ignored and the migration becomes inert documentation. Verified pre-merge by the canary test (INV-015).
- **EA-004**: `.claude/rules/` is NOT synced by `sync.sh` to the `correctless/` distribution. Enforced by INV-024.
- **EA-005** (new, per F21): The host filesystem is case-sensitive for the purposes of `.claude/rules/` path resolution AND rule files use LF line endings only. Consequence if wrong: macOS HFS+/APFS default case-insensitivity could make `.claude/Rules/` and `.claude/rules/` indistinguishable; CRLF could break BND-003's `head -1 == "---"` check. Enforced via `.gitattributes` (LF) and documented as a project prerequisite (case-sensitive FS — Linux CI enforces naturally; macOS contributors must use a case-sensitive volume or be aware).

## Design Decisions

### DD-001: Rules canonical, ARCHITECTURE.md index (over ARCHITECTURE.md canonical + rules mirror)
- **Decision**: Rule file is canonical. ARCHITECTURE.md is the index.
- **Rationale**: Duplication invites drift. AP-005 has recurred multiple times. Single source of truth, enforced by INV-003 structural drift test, makes drift impossible rather than merely unlikely.

### DD-002: Mixed measurement gate (over pure prevention or pure review-catch)
- **Decision**: Falsifiability combines MG-001 (prevention) + MG-002 (persistence ceiling).
- **Rationale**: Prevention matches the mechanism; safety net is robust to measurement-method failures.

### DD-003: Drift test survives rollback as inert infrastructure
- **Decision**: PRH-002 leaves `tests/test-architecture-drift.sh` in place.
- **Rationale**: Test infrastructure is reusable for retries. Cost is negligible (no migrated entries = no-op).

### DD-004: Migrate exactly one PAT entry in this feature
- **Decision**: Only PAT-001. Multi-migration confounds the day-0 baseline measurement.
- **Rationale**: Experimental validity.

### DD-005: Historical violation citations in the rule file body
- **Decision**: The rule file cites QA-R1-004 and QA-R1-005 with dates and persistence duration.
- **Rationale**: A rule with a concrete failure story is memorable; bare rules are forgettable. The audience is future agents editing hooks under time pressure.
- **Elevated**: this decision is codified as a feedback memory (`memory/feedback_rule_file_historical_citations.md`) for all future rule files and is validated by INV-019's semantic integrity anchors.

### DD-006 (new, per F16): Rule file write protection is convention + static allowlist in Feature A, runtime enforcement deferred
- **Decision**: INV-023 enforces rule file authorship via a static allowed-tools allowlist check (only `/cspec`, `/cdocs`, `/cupdate-arch` have Write permission). Runtime enforcement via `sensitive-file-guard.sh` pattern addition is deferred to FUTURE-005.
- **Alternative considered**: Add `.claude/rules/*.md` to sensitive-file-guard.sh in this feature, the same way `preferences.md` is protected.
- **Rationale**: sensitive-file-guard is fail-closed with no exceptions. Adding `.claude/rules/` to its patterns would block the GREEN phase itself from creating the rule file — chicken-and-egg. A same-commit ordering (create file, then add pattern in the same commit) would work for Feature A but would create the same bootstrap problem for every future rule file migration (FUTURE-002), requiring a temporary override each time. The cleanest design requires a skill-aware or phase-aware exception mechanism, which is a substantial new feature unto itself. For Feature A's experimental scope, the static allowed-tools check is sufficient: it catches any future skill accidentally acquiring Write permission, at test time rather than runtime.
- **Deferred to FUTURE-005**: design and ship a runtime rule-file write gate that works for all rule files without bootstrap problems.

### DD-007 (new, per F5): Defense in Depth diagram adds exactly one tier, not two
- **Decision**: INV-009 requires 4 tiers (L1 Gate, L2 Audit Trail, L3 Path-scoped rules [new], L4 Skill instructions [formerly L3]). No L5 CLAUDE.md tier is added.
- **Alternative considered**: Add both a path-scoped rules tier AND a CLAUDE.md tier to make the advisory spectrum more complete (5 tiers total).
- **Rationale**: The current diagram has 3 tiers. The feature's scope is to add path-scoped rules. Adding a CLAUDE.md tier is an independent conceptual change that was not in the proposal or the Evidence & Baseline analysis. The spec author (me) introduced the L5 CLAUDE.md tier while drafting INV-009 without realizing it was out of scope. The Design Contract reviewer caught it. Feature A ships with exactly one new tier; CLAUDE.md's role as a loaded-every-session context file is documented in the README prose but not elevated to a numbered defense tier.

## Open Questions

- **OQ-001**: MG-001's primary measurement signal requires Feature B (`InstructionsLoaded` hook) to directly observe rule-load events. Until Feature B ships, MG-001 can only be measured via indirect proxy. **Decision:** Feature A ships with the indirect-proxy fallback. Feature B is FUTURE-001.

- **OQ-002**: The 3-PR persistence ceiling in MG-002 is a judgment call. **Decision:** accept 3 as a starting value. MG-003 allows up to 3 inconclusive cycles before auto-rollback.

- **OQ-003**: `sync.sh` does not currently sync `.claude/rules/` to the `correctless/` distribution. For Feature B / FUTURE-003 (user-project rule generation), the question of how rule templates reach user projects is deferred.

- **OQ-004** (new, per F22 / Design Contract): ABS-004 currently scopes metadata-header requirements to PreToolUse/PostToolUse hooks. Feature B will add an `InstructionsLoaded` hook — a new hook type. Whether ABS-004's header convention extends to new hook types, or whether `InstructionsLoaded` is registered via a different mechanism (hardcoded like `workflow-advance.sh` and `statusline.sh`), is a Feature B design question. **Decision deferred:** not blocking Feature A.

- **OQ-005** (new, per F29 + Design Contract Part 7): After this feature merges, where do NEW PAT entries (PAT-011+) land? **Options**: (1) always in ARCHITECTURE.md as full-body entries — rule-file migration is a deliberate one-off per PAT; (2) always in `.claude/rules/` — the new default; (3) author's choice based on whether the PAT is path-scopable. **Decision:** default to (1) until Feature A's measurement gate passes (MG-003). New PATs land in ARCHITECTURE.md as full-body entries. If the gate succeeds and ABS-009 is promoted to a mature convention, the default switches to (2) in a follow-up feature that updates `/cpostmortem` SKILL.md accordingly.

## Future Work (explicitly deferred)

- **FUTURE-001**: **Feature B — `InstructionsLoaded` hook + `/cwtf` correlation.** Required for MG-001's primary signal. Scope: add `hooks/instructions-loaded.sh`; extend `setup register_hooks()`; specify `/cwtf` join logic. Day-1 constraint confirmed (hook emits only successful loads, not skip events). **Gated on:** Feature A's measurement gate showing non-negative signal.

- **FUTURE-002**: **Subsequent PAT migrations.** PAT-005 (PostToolUse hook conventions) is the next candidate. Each subsequent migration reuses `tests/test-architecture-drift.sh` verbatim (test is PAT-agnostic).

- **FUTURE-003**: **`/csetup` user-project rule generation (product feature).** Gated on Feature A's measurement gate passing AND the pattern proving reusable across FUTURE-002.

- **FUTURE-004** (new, per F23): **Rule file size budget enforcement.** Add a size ceiling to the drift test (e.g., 200 lines per rule file) if any rule file approaches bloat. Not needed at Feature A's ~100-line scale.

- **FUTURE-005** (new, per F16/DD-006): **Runtime rule file write gate.** Add `.claude/rules/*.md` to `sensitive-file-guard.sh` with a skill-aware exception mechanism (allow writes only from `/cspec`, `/cdocs`, `/cupdate-arch`). Design must handle the bootstrap problem (creating the first rule file while protection is in place). Possibly requires a new hook event type or a per-phase permission system.

- **FUTURE-006** (new, per F14b): **Bash-mediated write prohibition for scoped hook files.** Extend `sensitive-file-guard.sh` or add a new hook to block `Bash` tool invocations that write to `hooks/workflow-gate.sh` or `hooks/sensitive-file-guard.sh` via `sed -i`, heredoc redirection, `git apply`, `patch`, etc. Mitigation for F14b's deferred concern. Independent of FUTURE-005.

## Risks

- **R1**: Drift test has a subtle bug in edge cases.
  - **Mitigation**: INV-011 mandates 6 negative-case verifications including nested headings, fenced code blocks, multi-migration fixtures, and false-positive guards.

- **R1a** (new, per F18 deferral): TOCTOU race between drift-test reads (file-1 → file-2 swap by a concurrent process).
  - **Mitigation**: accepted risk. Low probability in CI (single-threaded, no concurrent writers). Not mitigated in Feature A. Revisit if CI introduces parallel test execution or external file-watcher processes.

- **R2**: Hook-touching PRs are rare (2-3/quarter); measurement gate feedback loop is slow.
  - **Mitigation**: MG-003's 3-PR ceiling is calibrated to the observed rate. INV-016's dormant `/cstatus` check surfaces overdue measurements. MG-003 caps at 3 inconclusive cycles before auto-rollback.

- **R3**: Rule file grows over time as new failure stories are added.
  - **Mitigation**: Current rule file is ~100 lines. FUTURE-004 adds a size budget if bloat becomes a concern.

- **R4**: Root ARCHITECTURE.md's unrelated PAT-001 namespace collision causes future confusion.
  - **Mitigation**: PRH-003 prohibits touching it in this feature. Namespace deduplication is a separate feature.

- **R5**: Semantic integrity anchors (INV-019) could false-positive on a legitimate rewrite that uses different wording for clause 5 but preserves the semantic meaning.
  - **Mitigation**: The anchors are cheap literal-string greps tolerant of whitespace but hostile to weakening. If a future rewrite legitimately needs to change the exact string "exit 2 on unexpected input", INV-019 must be updated in the same PR — which is loud and reviewable.

- **R6** (new, per F15): Migration is not idempotent and partial GREEN commits produce inconsistent state.
  - **Mitigation**: INV-022 requires the migration steps to be tested for idempotency during GREEN.

- **R7** (new, per F16/DD-006): Rule file write protection relies on a static allowed-tools allowlist, not runtime enforcement. A malicious or buggy skill edit could bypass the allowlist between PRs.
  - **Mitigation**: INV-023 catches the allowlist violation at CI time. Runtime enforcement is deferred to FUTURE-005 but is a known gap.

## Packages Affected

N/A — not a monorepo.
