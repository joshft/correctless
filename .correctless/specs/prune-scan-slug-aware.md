# Spec: Slug-type-aware artifact classification in prune-scan.sh

## Metadata
- **Task**: prune-scan-slug-aware-matching
- **Created**: 2026-06-13
- **Status**: draft (revised post /creview-spec)
- **Branch**: feature/prune-scan-slug-aware-matching
- **Impacts**:
  - New ABS-xxx entry in `.correctless/ARCHITECTURE.md` for the slug-type classification mapping (sole writer: `_classify_artifact_pattern` in `scripts/prune-scan.sh`)
  - `.correctless/antipatterns.md`: AP-032 frequency 1 → 2; promotion threshold ("3rd instance → promote to PAT-xxx-class structural rule")
  - `skills/cprune/SKILL.md`: consume new `skipped_unclassified` and `protection_set` JSON fields; render in prune report; **schema migration: scanner now emits a wrapped object `{candidates: [...], ...}` instead of bare array — consumer must read `.candidates` instead of `.`**
  - `skills/cstatus/SKILL.md`: same schema migration — consumer must read `.candidates` instead of bare array
  - `scripts/antipattern-scan.sh`: new `prune-scan-substring-match` rule detecting `grep -F "$slug"` and unquoted `=~ $slug` patterns
  - `hooks/sensitive-file-guard.sh`: add `.correctless/meta/prune-pattern-baseline.json` to protected patterns (sole writer per INV-011 is `scripts/prune-scan.sh` invoked with explicit `--update-baseline` flag — see INV-011)
- **Research**: null
- **Intensity**: high
- **Recommended-intensity**: high
- **Intensity reason**: project floor (workflow.intensity = high); data-integrity sensitivity (autonomous /cprune acts on `low`-risk → false positives become data-loss vector); 2nd instance of AP-032; **/creview-spec multi-agent review found 4 CRITICAL + 8 HIGH findings, all accepted**
- **Override**: none
- **Issue**: #153

## Context

`scripts/prune-scan.sh`'s `scan_artifacts` function scans `.correctless/artifacts/` for "orphaned artifacts for deleted/unknown branches" by matching each filename against the set of current branch slugs (`feature-<name>-<md5[:6]>`). The scanner treats two different naming conventions as one: branch-slug-named patterns (workflow-state, token-log, audit-trail, pipeline-manifest, autonomous-decisions, etc., which actually use the branch slug) AND task-slug-named patterns (qa-findings uses the bare task slug — no `feature-` prefix, no hash). When a task-slug-named file is matched against branch slugs, the match fails and the live file gets emitted as a `low`-risk deletion candidate. UX-R2-014 patched the qa-findings instance by removing it from the patterns list, but the bug class (AP-032 — extraction correct, resolution incomplete) is unaddressed and a secondary symptom (stale-hash mismatch on genuinely-branch-slug-named artifacts) was left in place. This is the 2nd observed AP-032 instance.

The /creview-spec multi-agent review also surfaced a third slug-naming convention not covered by the original spec: **session-slug-named artifacts** (`harness-notified-{SESSION_ID}.flag`), and several silent-failure paths where the safety belt collapses entirely (non-git BASE_DIR, lib.sh sourcing failure, mid-write workflow-state TOCTOU, empty-set vs never-populated indistinguishability). The revised spec covers all three slug naming conventions plus fail-closed posture for every safety-belt fall-through path.

Note: verification reports (`.correctless/verification/{task-slug}-verification.md`) are also task-slug-named, but they live under a different directory that `scan_artifacts` does not currently scan. They are out of scope for this spec — if a future scanner extension covers `.correctless/verification/`, it will need the same slug-type-aware classification.

## Scope

**In scope**:
- `scripts/prune-scan.sh` scanner classification logic + safety-belt completion + **JSON schema migration from bare array to wrapped object `{candidates: [...], protection_set: {...}, ...}`**
- `scripts/antipattern-scan.sh` new `prune-scan-substring-match` rule
- `skills/cprune/SKILL.md` consume new JSON fields and migrate to wrapped-object schema (read `.candidates` not bare array)
- `skills/cstatus/SKILL.md` migrate to wrapped-object schema (same consumer migration as /cprune)
- `hooks/sensitive-file-guard.sh` add `.correctless/meta/prune-pattern-baseline.json` to protected patterns
- `.correctless/ARCHITECTURE.md` new ABS-xxx for slug-type mapping
- `.correctless/antipatterns.md` AP-032 frequency + promotion threshold
- New structural tests under `tests/test-prune-scan-*` (or extension of existing `tests/test-cprune.sh`)
- Distribution sync via `correctless/scripts/prune-scan.sh`, `correctless/scripts/antipattern-scan.sh`, `correctless/skills/cprune/SKILL.md`, `correctless/skills/cstatus/SKILL.md`, `correctless/hooks/sensitive-file-guard.sh`

**Out of scope**:
- Risk-tier policy (autonomous-eligibility rules in `/cprune` SKILL.md — the consumer-side rule that `low` = auto-eligible is unchanged)
- Any other tool that consumes prune-scan.sh output (only `/cprune` and `/cstatus` reference the candidates JSON)
- Pruning of non-artifacts (specs, antipatterns, crossrefs — different scanner branches not affected by this bug class)
- Verification reports under `.correctless/verification/` (separate directory, scanner does not cover it)
- Path-traversal cleanup outside `.correctless/artifacts/` (out-of-scope guard: scanner only operates within that directory)

## Complexity Budget
- **Estimated LOC**: ~250–350 in `scripts/prune-scan.sh`; ~50 in `scripts/antipattern-scan.sh`; ~50 in `skills/cprune/SKILL.md` (schema migration + new fields rendering); ~20 in `skills/cstatus/SKILL.md` (schema migration only); ~10 in `hooks/sensitive-file-guard.sh` (one pattern addition); ~600–800 in tests; one new ABS-xxx in ARCHITECTURE.md
- **Files touched**: 7 source files total — 5 with distribution copies (`scripts/prune-scan.sh`, `scripts/antipattern-scan.sh`, `skills/cprune/SKILL.md`, `skills/cstatus/SKILL.md`, `hooks/sensitive-file-guard.sh` — each synced to its `correctless/...` counterpart via `sync.sh`) + 2 in-tree-only docs (`.correctless/ARCHITECTURE.md`, `.correctless/antipatterns.md` — no distribution copy; both live under `.correctless/` which is the consumer-facing tree) + new tracked test fixture `tests/fixtures/prune-scan/workflow-state-real.json` + test files under `tests/test-prune-scan-*`; sensitive-file-guard protects `prune-scan.sh` and `sensitive-file-guard.sh` itself, so each edit to those two will need human-apply per AP-031 precedent
- **New abstractions**: 2 — slug-type classification mapping (`_classify_artifact_pattern`) and live-set composition (`_build_live_slug_sets` helper for branch-slug and task-slug)
- **Trust boundaries touched**: 1 (TB-004 — orchestrator autonomy boundary; `/cprune` autonomous mode is the consumer-side surface; INV-002 / INV-003 / INV-004 / INV-004a / INV-014 are the structural backstop)
- **Risk surface delta**: high (reduces existing data-loss risk in autonomous mode; introduces new failure modes if classification mapping or fail-closed gates are themselves wrong — mitigated by structural tests at every gate)

## Invariants

### INV-001: Slug-type classification of artifact patterns
- **Type**: must
- **Category**: data-integrity
- **Statement**: Every pattern in `scripts/prune-scan.sh`'s `artifact_patterns` list must be classified into exactly one of four slug types via the function `_classify_artifact_pattern`: `branch-slug` (filename embeds `feature-<name>-<md5[:6]>`), `task-slug` (filename embeds the bare task slug), `session-slug` (filename embeds a Claude Code session ID — never live-pruned), or `unclassified` (no slug component, global-scoped, or new pattern pending review). Classification is a property of the *pattern*, not the file. There must be exactly one function definition of `_classify_artifact_pattern` in `prune-scan.sh`.
- **Boundary**: AP-032 (extraction correct, resolution incomplete); TB-004
- **Violated when**: A pattern is added to `artifact_patterns` without a classification mapping; OR `_classify_artifact_pattern` returns a value other than the four enum members for any pattern; OR two function definitions exist.
- **Enforcement**: structural — `tests/test-prune-scan-slug-classification.sh` greps `scripts/prune-scan.sh` for exactly one function definition matching `^_classify_artifact_pattern\(\)`, parses every glob token from the `artifact_patterns=` assignment line (via sed pinned to that variable name), and asserts `_classify_artifact_pattern "<token>"` prints one of {`branch-slug`, `task-slug`, `session-slug`, `unclassified`} with `exit 0`. Any other return value, missing function, or duplicate definition fails.
- **Guards against**: AP-032
- **Test approach**: unit + structural
- **Risk**: high
- **Implemented in**: (filled during GREEN)

### INV-002: Unclassified patterns are never flagged for deletion (fail-safe)
- **Type**: must-not
- **Category**: data-integrity
- **Statement**: When `_classify_artifact_pattern "$pattern"` returns `unclassified`, files matching that pattern are NOT emitted as deletion candidates. The skip is observable, not silent (per INV-007).
- **Boundary**: BND-001; TB-004
- **Violated when**: An unclassified pattern produces a deletion candidate; OR the scanner falls back to branch-slug matching when classification is `unclassified`.
- **Enforcement**: structural — two tests: (a) unit — call `_classify_artifact_pattern "prune-test-synthetic-*.json"` directly; assert returns `unclassified`. (b) integration — stages a tmpdir-copied `prune-scan.sh` with one injected synthetic pattern `prune-test-unclassified-*.json` appended to `artifact_patterns` and ZERO classification entry. Runs the scanner against fixture files matching that pattern. Asserts (i) no candidate emitted for the synthetic pattern, (ii) the INV-007 advisory appears on stderr AND in the JSON `skipped_unclassified` field, (iii) `_classify_artifact_pattern` returns `unclassified` for the injected pattern. Pre-assertion: the synthetic injection IS the precondition (not the live list) — guaranteed non-vacuous because tmpdir-copy mutation is under test control.
- **Guards against**: AP-032 silent regression on future pattern additions
- **Test approach**: unit (helper) + integration (scanner pipeline)
- **Risk**: high
- **Implemented in**: (filled during GREEN)

### INV-003: Live-branch artifacts are never flagged (safety belt, all live branches)
- **Type**: must-not
- **Category**: data-integrity
- **Statement**: For every branch in the live branch set (computed via `load_branches` inside `cd "$BASE_DIR"` per EA-001), compute its branch slug via `branch_slug()`. Any artifact whose filename embeds a slug in this live-branch-slug set as a delimited token (per INV-005) must NOT be emitted as an orphaned-artifact deletion candidate, regardless of which pattern matched it. The protection covers EVERY live branch's workflow, not only the current branch. If `branch_slug` computation fails for ANY branch in the live set, the scanner aborts the artifacts category entirely (per INV-014) — `|| continue` silent drops are prohibited.
- **Boundary**: BND-001; TB-004
- **Violated when**: A file containing any live branch's slug (delimited token) is emitted with kind `artifacts` and reason `Artifact for deleted/unknown branch`; OR a `branch_slug` failure is silently swallowed by `|| continue`.
- **Enforcement**: structural — (a) Behavioral test: sets up a tmpdir git repo with three branches (`main`, current-feature, `feature/sibling-live`), computes both feature branch slugs via `branch_slug()` from lib.sh, asserts both differ, creates fixture artifacts `audit-trail-{slug1}.jsonl` and `audit-trail-{slug2}.jsonl`, runs `scan_artifacts` with `BASE_DIR` pointed at the tmpdir, and asserts `.candidates` (per wrapped-object schema) contains neither slug. Precondition: `command -v jq` (skip with explicit message if absent — do not pass silently). (b) Structural assertion (production-environment-independent): grep `scripts/prune-scan.sh` to assert the branch loop body contains NO `branch_slug "$branch" ... || continue` pattern (or any other `... || continue` for `branch_slug` invocations). Manufacturing a real branch name that fails `branch_slug` is brittle across git versions and locales; the structural assertion catches the regression class without depending on fragile fixture construction.
- **Guards against**: AP-032 instance recurrence across any workflow on any live branch
- **Test approach**: integration
- **Risk**: critical
- **Implemented in**: (filled during GREEN)

### INV-004: Live-task artifacts are never flagged (safety belt, all live branches)
- **Type**: must-not
- **Category**: data-integrity
- **Statement**: The scanner must build a **live-task-slug set** by iterating over every `workflow-state-*.json` file under `.correctless/artifacts/` whose `.branch` field still appears in the live branch set. Task slug derivation: **`basename(.spec_file, ".md")` ONLY when `.spec_file` is present, non-empty, and non-null. No fallback to `.task`** (per RS-002). If ANY live workflow-state file has missing/null/empty `.spec_file`, the scanner aborts task-slug pattern emission entirely (per INV-004a fail-closed). Per-file silent skipping is prohibited — the per-file degradation IS the safety belt for that branch. Any artifact whose filename embeds any slug in the live-task-slug set as a delimited token (per INV-005) must NOT be emitted as a deletion candidate.
- **Boundary**: BND-001; TB-004
- **Violated when**: A file matching any live task slug is emitted as a deletion candidate; OR task slug derivation falls back to `.task` for ANY workflow-state file; OR a workflow-state file with empty/null `.spec_file` is silently skipped without triggering INV-004a fail-closed.
- **Enforcement**: structural — test creates fixture workflow-state files: (a) live-branch + present `.spec_file` (protected case); (b) stale-branch + present `.spec_file` (eligible case); (c) live-branch + empty `.spec_file` (fail-closed-triggering case per INV-004a); creates artifacts with matching slugs; runs the scanner; asserts only the stale-branch task slug's artifacts appear in the candidates array. **Real-fixture requirement (AP-031)**: because `.correctless/artifacts/` is gitignored, the test cannot import a committed workflow-state JSON from there. Instead, the test ships a tracked fixture at `tests/fixtures/prune-scan/workflow-state-real.json` — created by copying a real local `workflow-state-feature-*.json` produced by `scripts/wf/utility.sh` at the time the fixture was authored, with a header comment `# Source: derived from .correctless/artifacts/workflow-state-{slug}.json at commit {sha}` citing the producing commit. Synthetic variants for stale-branch / missing-spec_file scenarios are derived from that tracked real fixture by field mutation, not hand-rolled. (See AP-031 — the prevention class is "tests that parse another tool's output must source ≥1 fixture from a real artifact at authoring time, even if storage is moved to a tracked location.")
- **Guards against**: AP-032 instance recurrence for task-slug-named artifacts (qa-findings); EA-003 collision-suffix divergence (RS-002)
- **Test approach**: integration
- **Risk**: critical
- **Implemented in**: (filled during GREEN)

### INV-004a: Fail-closed when live-task-slug set cannot be derived
- **Type**: must
- **Category**: data-integrity
- **Statement**: The scanner activates fail-closed for `task-slug`-classified patterns under TWO distinct conditions: (1) **no-evidence**: zero `workflow-state-*.json` files exist under `.correctless/artifacts/`; (2) **incomplete-evidence**: any extant `workflow-state-*.json` file has missing/null/empty `.spec_file` (per RS-002, no `.task` fallback is permitted). The gating signal is `count(workflow-state-*.json) == 0` for case (1) AND `any(missing-spec_file)` for case (2) — not the derived live-task-slug set being empty (which is the legitimate "all task-slug-named files ARE orphans" case after a project closes all workflows). When fail-closed activates, the scanner emits a stderr advisory `# prune-scan: task-slug protection unavailable ({reason}); skipping {N} task-slug patterns` AND a JSON `.protection_status` field with `task_slug: "fail-closed"` and `reason`. Task-slug-classified patterns produce zero candidates of any risk tier — neither `low` nor `medium`/`high`.
- **Boundary**: BND-001; TB-004
- **Violated when**: A `task-slug`-classified pattern emits any candidate while either fail-closed condition holds; OR the scanner gates on derived-set emptiness instead of file-count / missing-spec_file; OR fail-closed activates without the stderr advisory + JSON field.
- **Enforcement**: structural — test runs the scanner with three scenarios: (a) zero workflow-state files → no task-slug candidates + stderr advisory `reason=no-workflow-state`; (b) workflow-state with empty `.spec_file` → no task-slug candidates + stderr advisory `reason=incomplete-spec_file`; (c) workflow-state files exist with present `.spec_file` but all `.branch` are stale → task-slug candidates emitted normally (this is the legitimate-orphans case, NOT fail-closed). Asserts JSON `protection_status.task_slug` is `"fail-closed"` in (a)+(b), `"ok"` in (c).
- **Guards against**: silent data-loss when protection mechanism is dormant (RS-004); PMB-005 silent-telemetry-failure class
- **Test approach**: integration
- **Risk**: critical
- **Implemented in**: (filled during GREEN)

### INV-005: Slug match is delimited-token, not substring (branch, task, AND session slugs)
- **Type**: must
- **Category**: data-integrity
- **Statement**: When matching ANY slug (branch, task, or session) against an artifact filename, the comparison must verify the filename embeds the slug as a delimited token — preceded and followed by `-`, `.`, or string boundary — not as an arbitrary substring. **Pinned implementation primitive**: bash `[[` regex with character class `[-.]` (hyphen first to avoid range-operator interpretation) OR explicit equality on extracted token segments. Substring primitives (`grep -F "$slug"`, unquoted `[[ $f =~ $slug ]]`, `case "$f" in *"$slug"*)`) are prohibited.
- **Boundary**: BND-002; TB-004
- **Violated when**: Any slug-vs-filename comparison uses substring search; specifically, when `foo` matches an artifact named with `foo-2` (collision-suffix) or `feature-foo-abc` matches a sibling `feature-foo-def` (branch-hash prefix collision).
- **Enforcement**: structural — three test fixtures: (a) branch-slug prefix-share (`audit-trail-feature-foo-abc123.jsonl` vs `audit-trail-feature-foo-def456.jsonl`); (b) task-slug collision (`qa-findings-foo.json` vs `qa-findings-foo-2.json`); (c) regex-edge fixture (`qa-findings-foo.json` vs `qa-findings-foo.bar.json`) verifying `.` is recognized as a delimiter not a regex wildcard. All three assert only the exact-token match is treated as live. **Antipattern-scan rule**: a new `prune-scan-substring-match` rule in `scripts/antipattern-scan.sh check_shell()` detects `grep -F "$slug"`, unquoted `=~ $slug`, and `case "$f" in *"$slug"*)` patterns inside `scripts/prune-scan.sh`. Structural CI detection, not just behavioral tests.
- **Guards against**: stale-hash false positive (branch-slug case, RS-007); collision-suffix false positive (task-slug case, RS-002); regex-edge boundary failure (RS-010)
- **Test approach**: unit + antipattern-scan structural
- **Risk**: high
- **Implemented in**: (filled during GREEN)

### INV-006: Slug-type mapping is structurally enumerated
- **Type**: must
- **Category**: parity
- **Statement**: A structural test enumerates every pattern in `prune-scan.sh`'s `artifact_patterns` list and asserts a classification mapping exists. The test must parse the `artifact_patterns=` assignment line **directly via sed/grep**, NOT by sourcing the script and reading the variable. This catches conditional-append code paths that bypass the source-of-truth list. If a new pattern is added without classification, the test fails — surfacing the omission at CI time, not at /cprune runtime.
- **Boundary**: PAT-018 (structural enforcement over prompt-level)
- **Violated when**: A pattern is added to `artifact_patterns` (in any code path — main assignment, conditional append, dynamic construction) without a corresponding `_classify_artifact_pattern` case.
- **Enforcement**: structural — test extracts patterns by sed-pinning to the `^artifact_patterns=` line (anchored, single source-of-truth assignment), splits by whitespace, and calls `_classify_artifact_pattern` for each. Also asserts no other `artifact_patterns=` or `artifact_patterns+=` assignment exists anywhere in `prune-scan.sh`.
- **Guards against**: drift between pattern list and classification mapping
- **Test approach**: structural
- **Risk**: medium
- **Implemented in**: (filled during GREEN)

### INV-007: Unclassified-pattern emission is observable
- **Type**: must
- **Category**: functional
- **Statement**: The scanner JSON output is a wrapped object `{candidates: [...], skipped_unclassified: [...], protection_set: {...}, protection_status: {...}}`. When the scanner encounters a pattern matching files but the pattern is classified as `unclassified`, it emits TWO observability signals: (1) a stderr advisory line in the form `# prune-scan: '{pattern}' has no slug-type mapping — skipping {N} files to avoid mistakenly flagging live artifacts (safety belt INV-002). If these files are stale, prune manually. See docs/skills/cprune.md#classification.` (2) a JSON `skipped_unclassified` field within the wrapped object — array of `{pattern, count}` objects. The schema migration from bare array to wrapped object is a breaking change for consumers; `/cprune` and `/cstatus` are migrated as part of this feature (Scope section).
- **Boundary**: PAT-019 (dormant-signal graceful degradation); TB-004
- **Violated when**: Unclassified patterns silently produce no output; OR the stderr advisory uses jargon without remediation; OR the JSON field is absent from the wrapped object; OR the scanner emits a bare array instead of the wrapped object.
- **Enforcement**: structural — test asserts (a) the exact advisory text appears on stderr (regex match for the pinned message format), (b) `jq -e 'type == "object" and has("candidates") and has("skipped_unclassified")' <(prune-scan-output)` succeeds, (c) the `skipped_unclassified` array contains the expected pattern + count. Stderr-only or JSON-only is a test failure. Bare-array output is a test failure.
- **Guards against**: silent telemetry failure (PMB-005 class); user-hostile jargon (RS-026)
- **Test approach**: unit
- **Risk**: medium
- **Implemented in**: (filled during GREEN)

### INV-008: Pattern inventory matches an explicit producer-pattern table
- **Type**: must
- **Category**: parity
- **Statement**: The spec maintains an explicit producer-pattern table (below) enumerating every pattern in `artifact_patterns` with its slug type and producer reference. The structural test cross-references `artifact_patterns` against this table directly — NOT against an ad-hoc grep over ARCHITECTURE.md prose (which would itself be AP-032 in the test). Every pattern must appear in the table; every table entry must appear in `artifact_patterns` OR explicitly in the allowlist (cap ≤5).

**Producer-pattern table** (authoritative — INV-008 enforcer reads this):

| Pattern | Slug type | Producer ABS / source | Notes |
|---|---|---|---|
| `workflow-state-*.json` | branch-slug | ABS (workflow state, `scripts/wf/utility.sh`) | per-branch state file |
| `token-log-*.jsonl` | branch-slug | `hooks/token-tracking.sh` | per-branch token log |
| `audit-trail-*.jsonl` | branch-slug | `hooks/audit-trail.sh` | per-branch audit trail |
| `pipeline-manifest-*.json` | branch-slug | ABS-031 (`/cauto` pipeline manifest) | per-branch manifest |
| `autonomous-decisions-*.jsonl` | branch-slug | ABS-030 (sole writer: `scripts/autonomous-decision-writer.sh`) | per-branch decisions |
| `escalation-*.md` | branch-slug | ABS-007 area (escalation file) | **CORRECTED from `escalation-*.json`** |
| `adherence-*.json` | branch-slug | ABS-032 (carchitect Phase 3) | per-branch adherence report |
| `antipattern-findings-*.json` | branch-slug | `scripts/antipattern-scan.sh` | per-branch findings |
| `cost-*.json` | branch-slug | ABS-026 (`scripts/compute-session-cost.sh`) | **ADDED — `cost-{branch-slug}.json`** |
| `cost-cache-*.json` | branch-slug | ABS-026 (ephemeral cache) | per-branch cost cache |
| `review-decisions-*.json` | branch-slug | `/creview-spec` review-decisions log | per-branch |
| `lens-recommendations-*.json` | branch-slug | ABS-036 (review skills) | per-branch |
| `probe-results-*.json` | branch-slug | ABS-034 (adversarial probes) | per-branch |
| `wtf-report-*.md` | branch-slug | `/cwtf` skill | per-branch |
| `coverage-baseline-*.out` | branch-slug | `/cverify` baseline | per-branch |
| `cprune-lock-*-*` | branch-slug | `/cprune` skill (BND-004 lockfile) | **TIGHTENED in this spec from `cprune-lock-*` per INV-012** |
| `qa-findings-*.json` | task-slug | `/ctdd` QA phase | per-task; **PROTECTED via INV-004** |
| `harness-notified-*.flag` | session-slug | `scripts/harness-fingerprint.sh` | per-session; **NEVER LIVE-PRUNED** |

**Allowlist** (cap ≤5, exceeding forces spec discussion):
- (currently empty — every pattern resolves to a slug type)

- **Boundary**: PAT-018; AP-032 root class
- **Violated when**: A pattern's extension or prefix in `artifact_patterns` diverges from its producer-pattern table entry; OR a pattern exists in `artifact_patterns` without a table entry AND without an allowlist entry; OR a table entry has no corresponding `artifact_patterns` entry.
- **Enforcement**: structural — test parses the producer-pattern table from this spec (sed-pinned to the exact markdown header `| Pattern | Slug type | Producer ABS / source | Notes |` followed by the separator row; the parser uses literal-string match on the header line, not a permissive regex), cross-references against `artifact_patterns` extracted from `prune-scan.sh` (sed-pinned per INV-006), and asserts (a) every `artifact_patterns` entry has a matching table row OR allowlist row, (b) every table row has a matching `artifact_patterns` entry, (c) every pattern's `_classify_artifact_pattern` return matches the table's "Slug type" column. The allowlist cap is enforced (>5 entries fails the test). Header drift between spec and test (a pull request changing the header would break the parser immediately) is the intended structural lock.
- **Guards against**: AP-005 (stale documentation drift) applied to producer/scanner pairing; AP-032 recurrence; INV-008 itself being class-incomplete (RS-009)
- **Test approach**: structural
- **Risk**: high
- **Implemented in**: (filled during GREEN)

### INV-009: lib.sh sourcing must define `branch_slug` before scan_artifacts runs
- **Type**: must
- **Category**: data-integrity / distribution
- **Statement**: After sourcing `lib.sh` (per the source-or-fallback chain at lines 39-45), `prune-scan.sh` must verify `command -v branch_slug` succeeds before any `scan_artifacts` invocation. If `branch_slug` is not a defined function, the scanner exits non-zero with stderr advisory `# prune-scan: branch_slug helper unavailable (lib.sh sourcing failed or incomplete) — cannot compute safety belt; aborting` BEFORE any output is emitted.
- **Boundary**: BND-001; TB-004
- **Violated when**: `prune-scan.sh` proceeds to `scan_artifacts` with `branch_slug` undefined.
- **Enforcement**: structural — test stages a tmpdir containing a copy of `scripts/prune-scan.sh` (renamed to a non-SFG-protected basename for the test, e.g., `prune-scan-test-copy.sh`) but WITHOUT a `lib.sh` alongside it, AND with `BASE_DIR` pointed at a directory that contains no `scripts/lib.sh` fallback. Runs the copied script (which computes its own `SCRIPT_DIR` from `${BASH_SOURCE[0]}` correctly because we run the copy, not the original). Asserts (a) non-zero exit, (b) stderr advisory matches the pinned message, (c) stdout emits no JSON candidates structure. This avoids the failed `SCRIPT_DIR=/tmp/empty` injection (the original computes SCRIPT_DIR internally from BASH_SOURCE and ignores env overrides).
- **Guards against**: RS-011 (downstream user with stale `.correctless/scripts/lib.sh` silently collapses safety belt)
- **Test approach**: unit
- **Risk**: high
- **Implemented in**: (filled during GREEN)

### INV-010: Symlink and path-traversal rejection in scan_artifacts
- **Type**: must-not
- **Category**: security
- **Statement**: For every file iterated in `scan_artifacts`, the scanner must (1) reject symlinks with `[ -L "$artifact" ] && continue` (with stderr advisory naming the rejected link); (2) compute the canonical path via `canonicalize_path "$artifact"` (PAT-017) and verify it is under `BASE_DIR/.correctless/artifacts/` (string-prefix match after canonicalization); (3) reject and advise on any artifact whose canonical path escapes the directory.
- **Boundary**: TB-004; PAT-017
- **Violated when**: A symlink in `.correctless/artifacts/` is included in the iteration; OR an artifact with a `..`-bearing or absolute-path filename is processed without canonical-path validation.
- **Enforcement**: structural — four test fixtures: (a) symlink at `.correctless/artifacts/qa-findings-foo.json` whose target is `/etc/passwd` — assert rejected, advisory present, no candidate emitted (forward slash exists in the target path, not the filename — the filename is a normal `qa-findings-foo.json`); (b) symlink at `.correctless/artifacts/qa-findings-traversal.json` whose target is `../../etc/passwd` (relative traversal target) — assert rejected after canonicalization confirms the resolved path escapes `BASE_DIR/.correctless/artifacts/`; (c) **helper-level canonicalize_path unit test**: directly invoke `canonicalize_path` (PAT-017) with inputs `/correctless/artifacts/../passwd`, `/correctless/artifacts/./foo`, `/correctless/artifacts/foo/../bar`, assert the resolved path either stays under the prefix (case 2 → `/correctless/artifacts/foo`, case 3 → `/correctless/artifacts/bar`) or escapes (case 1) — covers the traversal class without manufacturing literal filenames containing `/` (which the filesystem would not accept anyway); (d) hardlink to a legitimate file in the artifacts dir — assert NOT rejected (hardlinks share inode but stay within the dir).
- **Guards against**: RS-008 (symlink traversal); defense-in-depth for AP-022-class boundary
- **Test approach**: unit + integration
- **Risk**: high
- **Implemented in**: (filled during GREEN)

### INV-011: First-run-after-pattern-correction emits at `medium` risk; baseline update is explicit
- **Type**: must
- **Category**: data-integrity / upgrade compat
- **Statement**: The scanner reads a pattern-baseline manifest at `.correctless/meta/prune-pattern-baseline.json` containing the previously-known pattern set. For any pattern present in the current `artifact_patterns` list but absent from the baseline, candidates emitted via that pattern carry `risk: "medium"` (interactive-only) instead of `low`, with reason text `Newly added pattern '{pattern}' — first scan after upgrade; review before deletion`. **The scanner does NOT update the baseline as a side effect of scanning** — autonomous runs, /cstatus runs, and default-mode /cprune runs all leave the baseline untouched. Baseline update happens only when the scanner is invoked with an explicit `--update-baseline` flag, which is set by `/cprune` SKILL.md only AFTER interactive human confirmation that the newly-emitted `medium`-risk candidates have been reviewed. This prevents the auto-promotion path where an autonomous run emits `medium`, silently updates the baseline, then the next autonomous run emits `low` without human review (RS-012-followup-1). The baseline file is sole-written by `prune-scan.sh --update-baseline` and protected by sensitive-file-guard.
- **Boundary**: TB-004; BND-001
- **Violated when**: A newly-added pattern (not in baseline) emits a `low`-risk candidate; OR the scanner updates the baseline without the explicit `--update-baseline` flag; OR `/cprune` passes `--update-baseline` in autonomous mode without human confirmation; OR the baseline file is missing/corrupt and the scanner proceeds as if baseline equaled current set; OR the baseline is updated by any tool other than `prune-scan.sh --update-baseline`.
- **Enforcement**: structural — five tests: (a) absent baseline file → all patterns treated as new → all candidates `medium` + stderr `# prune-scan: no baseline manifest — first run, emitting at medium risk`; (b) baseline lags current by one pattern → only that pattern's candidates are `medium`, others normal; (c) baseline matches current → normal classification; (d) baseline-update gating: run scanner WITHOUT `--update-baseline` against a fixture where baseline lags current, assert baseline file is unchanged after the run; (e) `/cprune` autonomous mode (`mode: autonomous` prompt context) NEVER passes `--update-baseline` to the scanner — structural assertion via grep on `skills/cprune/SKILL.md` autonomous code path. Also assert baseline file is added to `hooks/sensitive-file-guard.sh` protected paths (test via `grep -q "prune-pattern-baseline.json" hooks/sensitive-file-guard.sh`).
- **Guards against**: RS-012 first-run-after-upgrade data-loss; RS-027 silent pattern-correction surprise; auto-promotion of newly-added patterns to `low` risk without human review
- **Test approach**: integration + structural
- **Risk**: high
- **Implemented in**: (filled during GREEN)

### INV-012: cprune-lock pattern requires slug suffix
- **Type**: must
- **Category**: pattern precision
- **Statement**: The `cprune-lock-*` pattern in `artifact_patterns` is tightened to `cprune-lock-*-*` (matching the slug hash component). A filename `cprune-lock-evil` (no slug structure) does NOT match the pattern and is not processed.
- **Boundary**: BND-001
- **Violated when**: A non-slug-bearing filename starting `cprune-lock-` is matched by the pattern.
- **Enforcement**: structural — unit test asserts pattern `cprune-lock-*-*` matches `cprune-lock-feature-foo-abc123` but NOT `cprune-lock-evil` or `cprune-lock-`.
- **Guards against**: RS-021 (unbounded glob exploit)
- **Test approach**: unit
- **Risk**: medium
- **Implemented in**: (filled during GREEN)

### INV-013: workflow-state find glob requires `.json` extension
- **Type**: must
- **Category**: pattern precision
- **Statement**: When the scanner enumerates workflow-state files for live-task-slug derivation, the `find` glob is `workflow-state-*.json` with explicit extension, not `workflow-state-*`. Backup files (`*.json.bak`), no-extension variants, and other suffixes are excluded.
- **Boundary**: BND-001
- **Violated when**: The `find -name` argument lacks `.json` suffix; OR a non-`.json` file is parsed by jq.
- **Enforcement**: structural — unit test creates `workflow-state-feature-foo.json` AND `workflow-state-feature-foo.json.bak` in fixture dir; asserts only the `.json` file contributes to the live-task-slug set.
- **Guards against**: RS-022 (silent jq parse failure on non-JSON workflow-state matches)
- **Test approach**: unit
- **Risk**: medium
- **Implemented in**: (filled during GREEN)

### INV-014: jq parse failure on workflow-state aborts artifacts category
- **Type**: must
- **Category**: concurrency / fail-closed
- **Statement**: When the scanner reads a `workflow-state-*.json` file and jq parse fails (mid-write TOCTOU, corruption, malformed input), the scanner does NOT silently skip that file (which would silently remove its task slug from protection per RS-003). Instead, the artifacts category aborts: no candidates emitted, stderr advisory `# prune-scan: workflow-state {path} parse failure — aborting artifacts scan (fail-closed). Re-run after concurrent writes complete.`, JSON `.protection_status` field with `task_slug: "fail-closed", reason: "parse-failure"`, exit 0 (the scanner itself succeeds; the artifacts category emits empty).
- **Boundary**: BND-001; TB-004
- **Violated when**: jq parse failure on any workflow-state file is silently swallowed (`|| continue`); OR artifacts candidates are emitted despite a parse failure.
- **Enforcement**: structural — test creates a workflow-state fixture with malformed JSON (mid-line truncation simulating TOCTOU), runs the scanner, asserts (a) no artifacts candidates emitted, (b) stderr advisory present, (c) JSON `protection_status.task_slug = "fail-closed"`. Second test: valid workflow-state alongside corrupt one — asserts ALL artifacts candidates suppressed (category-level, not per-file).
- **Guards against**: RS-003 (TOCTOU mid-write); concurrent /cauto worktree races
- **Test approach**: integration
- **Risk**: critical
- **Implemented in**: (filled during GREEN)

### INV-015: `--branches-file` line validation
- **Type**: must
- **Category**: security
- **Statement**: When `--branches-file` is provided, each line of the file is validated against the regex `^[a-zA-Z0-9/_.-]+$` before use. Malformed lines (empty, containing shell metacharacters, control chars) cause non-zero exit with stderr advisory naming the offending line number.
- **Boundary**: BND-001
- **Violated when**: A line containing shell metacharacters or control chars is fed into `branch_slug` or `sed` without validation.
- **Enforcement**: structural — unit test: branches-file containing one valid line and one line with `$(rm -rf)` → asserts non-zero exit, error names line 2.
- **Guards against**: RS-028 (branches-file injection)
- **Test approach**: unit
- **Risk**: low
- **Implemented in**: (filled during GREEN)

### INV-016: Candidate JSON includes slug_type and match_method
- **Type**: must
- **Category**: observability
- **Statement**: Every candidate inside the wrapped object's `.candidates` array carries two additional fields: `slug_type` (one of `branch-slug` / `task-slug` / `session-slug` / `unclassified`) and `match_method` (`exact-token` / `unclassified-skip` / `safety-belt-fail-closed`). The `reason` field is differentiated by slug type: `Artifact for deleted/unknown branch` (branch-slug-orphan), `Artifact for unknown task slug` (task-slug-orphan), `Artifact for ended session` (session-slug — should never appear in practice given INV-001's never-prune rule, but exists for completeness).
- **Boundary**: BND-001
- **Violated when**: A candidate is missing `slug_type` or `match_method`; OR the `reason` text doesn't differentiate by slug type.
- **Enforcement**: structural — test runs scanner against fixtures, asserts every candidate has both fields populated with valid enum values, asserts `reason` text matches the slug-type-specific template.
- **Guards against**: RS-016 (misleading reason text for task-slug files)
- **Test approach**: integration
- **Risk**: medium
- **Implemented in**: (filled during GREEN)

### INV-017: Prune report includes protection-set composition
- **Type**: must
- **Category**: observability / recovery
- **Statement**: The wrapped-object scanner JSON output carries a `.protection_set` field: `{ "live_branches": [...], "live_branch_slugs": [...], "live_task_slugs": [...], "live_session_ids": [...], "source_workflow_state_files": [...] }`. The `/cprune` SKILL.md prune-report-{date}.md artifact renders this set as a "Protection Set" header section. Users have a post-hoc audit trail showing which workflow-state files contributed to the protection set, enabling recovery investigation for any false-positive deletion.
- **Boundary**: BND-001
- **Violated when**: The JSON output lacks the `.protection_set` field; OR the prune report artifact doesn't include the Protection Set section.
- **Enforcement**: structural — (a) test asserts scanner JSON contains `.protection_set` with all five subfields populated; (b) test runs `/cprune` against fixtures, parses the generated `prune-report-{date}.md`, asserts the Protection Set section exists with non-empty content.
- **Guards against**: RS-017 (no recovery path for false-positive deletions)
- **Test approach**: integration
- **Risk**: medium
- **Implemented in**: (filled during GREEN)

### INV-018: Workflow-state and dependent task-slug artifacts deleted as a group (separate stale-task set)
- **Type**: must
- **Category**: lifecycle
- **Statement**: Within a single scanner run, the scanner derives TWO disjoint task-slug sets: (1) the **live-task-slug set** (per INV-004 — workflow-state files whose `.branch` IS in the live branch set) which protects matching artifacts, and (2) the **stale-task-slug set** (workflow-state files whose `.branch` is NOT in the live branch set) which is used solely for the group-deletion gate below. The two sets are disjoint by construction. For any artifact whose filename matches a task slug in the stale set, the candidate is emitted ONLY IF the corresponding workflow-state file is ALSO emitted in the same run's candidates array; conversely, the workflow-state is emitted ONLY IF its dependent task-slug-named artifacts are also emitted. The pair (workflow-state + dependents) is atomic — both in candidates or neither — preventing the RS-015 race where workflow-state deletion in run N un-protects qa-findings in run N+1.
- **Boundary**: BND-001
- **Violated when**: A workflow-state's task slug is added to the LIVE set (which would over-protect — distinguishes from the original wording); OR a stale workflow-state is emitted as a candidate while its dependents are absent from candidates; OR a stale workflow-state's dependents are emitted while the workflow-state itself is absent.
- **Enforcement**: structural — three tests: (a) live-branch workflow-state + matching qa-findings → live-task-slug set protects qa-findings; only no candidates emitted; (b) stale-branch workflow-state + matching qa-findings → BOTH workflow-state AND qa-findings appear in candidates (atomic group); (c) stale-branch workflow-state alone (no matching qa-findings) → only workflow-state in candidates (no dependent group). The scenario where only one of the pair is flagged when both exist is the test failure.
- **Guards against**: RS-015 (two-step deletion race); original INV-018 contradiction where "contribute to live set" wording protected dependents and made workflow-state-only flagging the bug
- **Test approach**: integration
- **Risk**: medium
- **Implemented in**: (filled during GREEN)

## Prohibitions

### PRH-001: No autonomous deletion of live-branch, live-task, or session artifacts
- **Statement**: The scanner must never emit any candidate with `risk: "low"` for any file whose slug component resolves to a live branch (from the live branch set) OR to any task slug in the live-task-slug set (built per INV-004) OR to a session-slug-classified pattern (INV-001 — session-slug is never live-prunable). INV-018's stale-task-slug set is a separate atomic-group gate — it does NOT make stale-task artifacts protected; it only requires the workflow-state and its dependents to be emitted together or not at all. The autonomous /cprune pipeline relies on `low` risk being safe to delete; allowing any protected artifact into that tier is the data-loss path.
- **Detection**: tests in `tests/test-prune-scan-*` exercising the safety belts (INV-003, INV-004, INV-004a, INV-014); /cprune autonomous-mode dry-run test verifying protected artifacts are absent from `low`-risk lists. **Each test must assert specifically that no PROTECTED fixture appears at `risk == "low"`** — filtered by id/path/slug, not a blanket low-risk count: `assert_eq 0 "$(jq --arg protected "$PROTECTED_ID" '[.candidates[] | select(.risk == "low" and .id == $protected)] | length' <output)"` (or filter by filename via `.path` / by slug via `.slug` depending on which field the fixture is identified by). The fixture may legitimately include stale artifacts at `low` risk — those must NOT cause the assertion to fail; only the protected fixtures must be zero-low-risk. Asserting only "not in candidates" is weaker because medium/high risk would still violate if the safety belt fails partway; asserting "no low-risk candidates at all" is wrong because it forbids legitimate stale-orphan candidates.
- **Consequence**: silent data loss during /cauto pipelines — live qa-findings, audit-trail, pipeline-manifest, or harness-notified flags for any branch with an active workflow could be deleted without human review.

### PRH-002: No substring-only slug matching (branch, task, OR session slugs)
- **Statement**: The scanner must not use plain substring search to match any slug against filenames. Substring matching produces three false-positive classes: (a) branch-slug case — stale-hash mismatch where one branch's slug satisfies another branch's file with a similar prefix (issue #153); (b) task-slug case — collision-suffixed task slugs where `foo` matches an artifact named with `foo-2` from `scripts/wf/utility.sh` collision handling; (c) session-slug case — session IDs share prefixes across sessions.
- **Detection**: INV-005 tests — three fixtures: branch-slug prefix-sharing pair, task-slug collision pair, regex-edge `.` delimiter pair. Also: antipattern-scan `prune-scan-substring-match` rule (structural CI-level detection of substring primitives in `prune-scan.sh`).
- **Consequence**: false positives on genuinely branch-slug-named artifacts (audit-trail, pipeline-manifest), task-slug-named artifacts (qa-findings), and session-slug-named artifacts (harness-notified flags); reduces autonomous-mode trust even when slug-type classification is correct.

## Boundary Conditions

### BND-001: Scanner output → /cprune autonomous deletion eligibility
- **Boundary**: `scripts/prune-scan.sh` (producer) → `skills/cprune/SKILL.md` and `skills/cstatus/SKILL.md` (consumers)
- **Input from**: scanner emits a wrapped JSON object: `{ "candidates": [{id, category, reason, risk, slug_type, match_method, dead_refs, live_refs, bulk_warning, ...}, ...], "skipped_unclassified": [...], "protection_set": {...}, "protection_status": {...} }`. Schema migration from prior bare-array form is part of this feature; both consumers are updated in Scope.
- **Validation required**: scanner contract — only `low`-risk candidates in `.candidates` are auto-eligible; `medium`/`high` go to interactive triage. Safety belts (INV-003, INV-004, INV-014, INV-018) and fail-safe (INV-002, INV-004a) operate within the scanner, before the contract. Consumer contract: `/cprune` and `/cstatus` must read `.candidates`, never the top-level value as an array.
- **Failure mode**: fail-closed — classification failure, lib.sh sourcing failure, jq parse failure, branch_slug failure all result in the scanner aborting the artifacts category (no `low`-risk emission) with observable stderr advisory + JSON `.protection_status` field. The wrapped object is still emitted with `.candidates: []` and the populated status fields.
- **Contract test**: `tests/test-prune-scan-bnd001.sh` runs `scan_artifacts` against a fixture with one live-branch artifact, one truly-stale artifact, one newly-added-pattern artifact (per INV-011), parses JSON, asserts (a) output passes `jq -e 'type == "object" and has("candidates")'`, (b) live-branch artifact absent from `.candidates` entirely, (c) stale artifact appears in `.candidates` with `risk: "low"`, (d) newly-added-pattern artifact appears in `.candidates` with `risk: "medium"`, (e) every `risk: "low"` candidate survives a re-validation pass that recomputes live sets. Separate consumer-contract tests for `/cprune` and `/cstatus` assert each consumer reads `.candidates` (grep for the literal `.candidates` jq expression in each SKILL.md, NOT bare `.[]`).

### BND-002: Artifact pattern → slug type classification
- **Boundary**: `artifact_patterns` list (input) → `_classify_artifact_pattern` function (mapping)
- **Input from**: hardcoded list in prune-scan.sh
- **Validation required**: INV-006 structural test — every pattern is mapped, no pattern is silently unclassified by mapping omission.
- **Failure mode**: fail-safe (INV-002) — when classification returns `unclassified`, files are skipped + observable (INV-007).
- **Contract test**: assert `_classify_artifact_pattern` is total over `artifact_patterns` (no empty/null output) and idempotent (calling twice returns same value).

## Environment Assumptions

- **EA-001 (extended)**: Every `git` invocation in `prune-scan.sh` must run inside `(cd "$BASE_DIR" && ...)`. This includes `current_branch` (`git symbolic-ref --short HEAD`), `load_branches` (`git branch -a`), and any future helper. Without uniform `cd "$BASE_DIR"` scoping, scanner invocations from a different cwd (test fixtures from `tests/tmp/`, any non-root caller) read the caller's git state and apply the wrong safety belt. Consequence: silent data-loss in scanned repo. **Additional**: when BASE_DIR is non-git (no `.git` directory or file) OR is a bare repo, the scanner exits non-zero with stderr advisory `# prune-scan: BASE_DIR '{dir}' is not a git work tree — aborting` before any output is emitted (no fall-through to vacuous empty live-branch set). Refs ENV-007.
- **EA-002**: `branch_slug()` from `scripts/lib.sh` is the canonical source for branch-slug computation — refs ABS-001. The scanner sources `lib.sh` per the source-or-fallback chain (lines 39-45) and verifies `branch_slug` is defined per INV-009 before scan_artifacts runs.
- **EA-003 (revised — fallback removed per RS-002)**: Task slug derivation from a workflow-state JSON file: `basename(.spec_file, ".md")` ONLY when `.spec_file` is present, non-empty, and non-null. **No fallback to `.task` is permitted.** If `.spec_file` is missing/null/empty for ANY workflow-state file in the live branch set, INV-004a fail-closed activates for the entire task-slug category. The `.task` field can diverge from the spec basename (verified: in this branch's workflow-state, `.task = "prune-scan-slug-aware-matching"` but spec basename = `"prune-scan-slug-aware"`); using it as fallback would silently misalign with on-disk filenames. Collision suffixes from `scripts/wf/utility.sh` (e.g., `foo-2`) ARE captured in `basename(.spec_file, ".md")` because the producer writes the suffix to both `spec_file` and the artifact filenames at workflow init.
- **EA-004**: Live-task-slug set is derived from all `workflow-state-{branch-slug}.json` files whose `.branch` field is in the live branch set. Multiple workflows may be active across branches simultaneously; the safety belt covers all of them. Per INV-018, workflow-state files whose `.branch` is NOT in the live branch set contribute to the disjoint **stale-task-slug set** (NOT the live set) — that set drives the atomic-deletion group gate, ensuring the stale workflow-state and its task-slug dependents appear in `.candidates` together or not at all.
- **EA-005 (new — RS-029)**: `load_branches` output is computed once at scanner startup. Subsequent branch mutations (concurrent `git branch -D`, `git push --prune`) during the scan are NOT reflected. Single-snapshot semantics — the scanner operates on a consistent view of the branch set throughout the run.

## AP-031 Real-Fixture Citations

Per AP-031 (PMB-010, PMB-011 lessons), tests that parse another tool's output must source at least one fixture from a real artifact in the repo.

| Test | Real fixture source | Why |
|---|---|---|
| INV-004 task-slug derivation | `tests/fixtures/prune-scan/workflow-state-real.json` — tracked fixture derived from a real local `workflow-state-feature-*.json` at authoring time (with `# Source:` citation in header). `.correctless/artifacts/` is gitignored so direct import isn't possible. | Validates `.spec_file` field shape and JSON structure matches producer (`scripts/wf/utility.sh`) |
| INV-008 producer-pattern table parity | This spec's table (above) — single source-of-truth maintained alongside `artifact_patterns` | The table IS the contract; no prose-grep over heterogeneous ABS entries (RS-009) |
| INV-014 jq parse failure | Real workflow-state file truncated mid-line (simulates TOCTOU) | Validates parse failure path mirrors real concurrent-write scenario |

Each test file containing the synthesized fixture must carry a `# Source: <path>` citation pointing to the committed artifact it was derived from.

## Risks

- **Wrong classification in the mapping itself**: If a pattern is classified as `branch-slug` when it's actually `task-slug` (or vice versa), false negatives occur (live files flagged). Mitigation: INV-003 + INV-004 + INV-018 safety belts catch the case regardless of classification; INV-006 structural test pins the mapping; INV-008 producer-pattern table cross-references. **Accepted** — safety belt is the meaningful defense.

- **Workflow state corruption / missing slug fields**: If a workflow-state file exists but `.spec_file` is absent/null/empty, INV-004a fail-closed activates entirely (per RS-002 strengthened position) — no `low`-risk task-slug emission until the corrupt state is resolved. **Accepted** — fail-closed is the meaningful defense; the per-file path no longer silently skips.

- **Sensitive-file-guard friction**: `scripts/prune-scan.sh` is SFG-protected. Every edit during GREEN + fix rounds requires the human-apply pattern (AP-031 / PR #150 precedent). Mitigation: proposals written to `.correctless/artifacts/`, validated by tests before apply. **Accepted** — SFG protection is correct; process friction is the cost.

- **Distribution parity (sync.sh)**: `sync.sh` copies `scripts/*.sh` to `correctless/scripts/`. Skills that consume the installed scanner read from `.correctless/scripts/prune-scan.sh`. Mitigation: `sync.sh --check` is part of the GREEN gate. **Accepted** — existing dist-parity gate covers this.

- **lib.sh sourcing fallback** (RS-011): Downstream user with stale `.correctless/scripts/lib.sh` could collapse the entire safety belt. Mitigation: INV-009 explicit `command -v branch_slug` check before scan_artifacts runs. **Mitigated** — strict fail-closed posture.

- **First-run-after-upgrade one-shot risk** (RS-012): Pattern corrections + legacy workflow-state schemas combine for elevated risk on first post-upgrade scan. Mitigation: INV-011 baseline manifest emits newly-added-pattern candidates at `medium` risk (interactive-only) for the first run; INV-004a fail-closed catches legacy workflow-state with missing `.spec_file`. **Mitigated** — both structural gates active.

- **TOCTOU between workflow-state write and scanner read** (RS-003): Concurrent /cauto runs across worktrees could read partial JSON. Mitigation: INV-014 category-level fail-closed on jq parse failure; per-file silent skip prohibited. **Mitigated**.

- **INV-008 producer-pattern table goes stale**: The table in this spec must stay aligned with both `artifact_patterns` and the actual producers. Mitigation: INV-008 structural test forces sync at CI time. **Accepted** — drift detected at CI, not at runtime.

## Won't Do

- Changing the orchestrator (`skills/cprune/SKILL.md`) autonomous-mode policy: out of scope; the scanner-side fix is sufficient because PRH-001 prevents the misclassified-as-low data-loss vector at the source. (The /cprune SKILL.md is updated only to consume new JSON fields per INV-007/INV-011/INV-016/INV-017, not to change policy.)
- Promoting AP-032 to a PAT-xxx entry: 2 instances is below the 3+ frequency threshold; will revisit if a 3rd instance surfaces. **Promotion threshold documented in antipatterns.md per RS-019.**
- Migrating to runtime classification inference (checking each file against branch_slug/task slug instead of explicit mapping): more complex than the explicit pattern→type mapping; explicit mapping is documented and CI-enforced via INV-006/INV-008.
- Adding a `dry-run` mode or autonomous-deletion-disabled flag to prune-scan.sh: the safety belt + fail-safe + fail-closed gates address the root cause directly.
- Amending the 9 ABS entries in ARCHITECTURE.md to add machine-readable `Artifact-pattern:` fields (alternative considered in RS-009): the explicit producer-pattern table in this spec is the lower-cost path; ABS entries remain prose. If a third AP-032 instance surfaces, revisit (the ABS-field amendment becomes the PAT-promotion enforcer).

## Open Questions

- None — all 29 /creview-spec findings dispositioned; RS-027 merged into RS-012 per user disposition. Six follow-up corrections from the external review round (scanner JSON schema migration, INV-011 baseline gating, INV-018 contradiction, cprune-lock table parity, SFG scope expansion, INV-009/INV-003 brittle-test cleanup) applied in this revision.
