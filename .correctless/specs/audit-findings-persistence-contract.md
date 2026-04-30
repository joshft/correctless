# Spec: Audit Findings Persistence Contract

## Metadata
- **Created**: 2026-04-29
- **Status**: draft
- **Impacts**: caudit (writer + self-verify), cmetrics (multi-signal consumer), workflow-advance (cmd_audit_done gate)
- **Branch**: feature/audit-findings-persistence-contract
- **Research**: null (no external library or protocol; project-internal contract)
- **Recommended-intensity**: high
- **Intensity**: high
- **Intensity reason**: file path signal (hooks/workflow-advance.sh — phase-gate change in security-script family), antipattern overlap (AP-022 dead-code-in-security-paths, AP-023 override-as-routine, AP-026 advisory-prose-artifact-write-contract — 3+ matches), TB-001 reference (workflow-gate enforcement boundary), keyword signal ("fail-closed", "phase-transition gate")
- **Override**: none

## Context

Corrective action for PMB-005. /caudit's persistence step (writing per-round-JSON to `.correctless/artifacts/findings/audit-{preset}-{date}-round-{N}.json` and appending a run summary to `audit-{preset}-history.md`) is described in the skill's "Findings Artifacts" and "After Convergence" sections as advisory prose. There is no tool-enforced check that the artifacts exist before `cmd_audit_done` transitions the workflow phase to `done`. On 2026-04-26 the orchestrator ran `/caudit hacker`, produced ~22 findings (C-1, C-2, H-1..H-6, M-1..M-10, L-1..L-5, S-1) which were addressed by the harness-fingerprint R2 hardening, called `audit-done`, and the phase transitioned cleanly — but neither the round-JSON nor the history append was written. The findings exist only as commit-message prose on the squash-deleted audit branch. /cmetrics derives "days since last Olympics" from the history.md mtime; with no append, mtime stayed at 2026-04-04 and /cmetrics reported the audit as 16 days stale when it had run 1 day prior.

Same shape as silent-telemetry-failure: the persistence step looks completed in the orchestrator's mental model but is never structurally verified.

## Scope

### In scope

1. **`cmd_audit_done` precondition gate** in `hooks/workflow-advance.sh` — refuse the transition to `done` unless at least one file matching `.correctless/artifacts/findings/audit-{preset}-*-round-*.json` exists AND contains a `started_at` JSON field whose value equals the workflow state's `started_at`. Content-based matching, not mtime-based — survives `git checkout`, `git clone`, and other ops that touch filesystem timestamps (per ENV-003). Fail-closed with a remediation message naming the expected path and the `started_at` reference. The verify logic lives INSIDE `cmd_audit_done` (the gate is a hook-side function, not a PAT-003 phase-transition script — different convention applies).
2. **`audit-record.sh` script** in `scripts/` — sole writer for round-JSON files and history.md append. Invoked by /caudit as a phase-transition CLI per PAT-003 (lives in `scripts/`, accepts CLI arguments, exits 0 on success non-zero on failure, sources `lib.sh`). Two subcommands: `write-round` and `append-history`. Both exit 0 informationally on success per PAT-003. The "verify whether artifacts exist" check is NOT a subcommand of this script — it's part of `cmd_audit_done`'s gate logic (see scope #1).
3. **`audit-record.sh` added to sensitive-file-guard DEFAULTS** — per the 2026-04-26 sole-writer convention (CLAUDE.md learning: "Structurally-enforced sole-writer for meta files"), the writer script itself must be sensitive-file-guard protected against autonomous Edit/Write to prevent the dead-code-in-security-paths failure mode (AP-022). Mirrors the harness-fingerprint.sh pattern. Add `scripts/audit-record.sh` and `.correctless/scripts/audit-record.sh` to the DEFAULTS block in `hooks/sensitive-file-guard.sh`.
4. **`/caudit` SKILL.md updates** — replace the prose write instructions with `bash scripts/audit-record.sh write-round {preset} {round} {findings.json}` and `bash scripts/audit-record.sh append-history {preset} {summary.md}`. The skill must read the workflow state's `started_at` and pass it as a positional argument to `write-round` so the JSON includes it. No client-side verify step — `cmd_audit_done` is the verification point.
5. **Zero-finding contract** — clean audit runs (zero findings after Round 1) MUST still write `audit-{preset}-{date}-round-1.json` with `findings: []` and `rejected: []`. The empty-findings file IS the audit's evidence; the gate must not accept absence as "clean."
6. **Round-JSON schema alignment** — match the existing schema observed in `audit-qa-2026-04-09-round-1.json`, `audit-perf-2026-04-04-round-1.json`, etc.: required fields are `preset` (string), `date` (ISO-8601 `YYYY-MM-DD`), `round` (positive integer), `findings` (array), `rejected` (array). Add ONE new required field for ABS-029: `started_at` (ISO-8601 timestamp matching workflow state). Optional fields (`specialist_lenses`, `deferred`, `findings_count`, etc.) remain unchanged. Existing round-JSONs without `started_at` are legacy; gate matches strictly on the new field, so legacy files cannot satisfy the gate (correct behavior — they're from runs before the contract).
7. **`/cmetrics` SKILL.md update** — replace single-mtime staleness signal with `max(history.md mtime, latest round-JSON mtime)` for "days since last Olympics" and per-preset staleness reporting.
8. **ABS-029 entry in `.correctless/ARCHITECTURE.md`** — sole-writer contract for `audit-{preset}-history.md` and `audit-{preset}-{date}-round-{N}.json`. ABS-029 lands in this PR alongside the gate that enforces it, not before — writing the contract before the enforcement is itself an instance of AP-026.
9. **`tests/test-audit-findings-persistence.sh`** — covers the gate (pre/post artifacts, content-based `started_at` match), the script's two subcommands, the zero-finding contract, the consumer multi-signal mtime, the sensitive-file-guard protection of the writer script, and a structural test that grep of `skills/*/SKILL.md` for round-JSON write patterns returns only `caudit` (or `audit-record.sh` invocations).

### Migration and ship-order constraints

- **Legacy round-JSONs (M-4)**: existing files at `.correctless/artifacts/findings/audit-*-round-*.json` predate this contract and lack the `started_at` field. They CANNOT satisfy the new gate (correct behavior — they're from runs before the contract). Developers with an in-flight audit at the time this PR lands must either (a) re-run `/caudit` to produce a contract-compliant round-JSON, or (b) use the standard `--override` escape hatch once. The override log captures the reason for traceability. No reconstruction or `started_at`-backfill of legacy files is offered or supported (per Q2 brainstorm — fabricated history is worse than acknowledged gap).
- **Ship-order (M-11, L-7)**: `scripts/audit-record.sh` and the `cmd_audit_done` gate change MUST land in a single commit (or in two commits with the script committed first). Shipping the gate before the script would block every audit-done with no remediation. Shipping the SKILL.md edit before the script would direct `/caudit` to invoke a missing executable. The single-commit form is preferred; if split, the script lands first.
- **Directory creation (L-8)**: `audit-record.sh write-round` MUST `mkdir -p .correctless/artifacts/findings/` before its first write — the directory may not exist on fresh projects.

### Out of scope

- **Reconstruction of the 2026-04-26 audit record.** Per Q2 brainstorm decision: a record marked `reconstructed: true` from commit-message parsing is worse than no record. The gap is self-documenting — "why is there no record for 2026-04-26?" answers itself with "because we didn't have persistence yet, that's why we built it."
- **PMB audit reference signal** in /cmetrics' staleness calculation. Per Q3 brainstorm: PMB references are sparse (most audits don't generate PMBs), the two-signal max already provides the multi-signal property, and adding a third signal is defensive bloat.
- **Sensitive-file-guard protection** of round-JSON paths. The threat is omission (silent telemetry), not tampering — gate-level enforcement closes the omission class. Adding sensitive-file-guard protection here would close a different threat class (agent forges fake findings) which has not been observed and is out of scope.
- **Token-tracking telemetry fix** (separate silent-telemetry instance, different feature).
- **/cdevadv recurring-pattern detection updates** — downstream consumer; if its expectations need updating, defer to follow-up.
- **Backfill of /cdocs / /cverify / similar artifacts** that may have analogous prose-only persistence contracts. This spec hardens the audit case only; if AP-026 generalizes, future specs handle each instance explicitly.
- **PAT-016 / sensitive-file-guard DEFAULTS as enumerated list** (M-8 from /creview-spec MEDIUM batch). The DEFAULTS block in `hooks/sensitive-file-guard.sh` is itself an enumerated list growing over time — same AP-024 pattern that PAT-016 was promoted to address. Refactoring DEFAULTS to a config-driven list with a count-match drift test is its own architectural feature; deferred to follow-up spec.
- **ABS-029 entrypoints YAML coverage** (M-12 from /creview-spec MEDIUM batch). `cmd_audit_done` is a phase-transition entrypoint that arguably belongs in `.correctless/ARCHITECTURE.md`'s entrypoints YAML per ABS-023. Adding entrypoints requires `/carchitect` review of the gate's `scope`/`test_via` fields — separate scope.

## Complexity Budget

- **Estimated LOC**: ~270 (audit-record.sh ~80, cmd_audit_done extension ~35 — content-based match with jq read, caudit SKILL.md edits ~20, cmetrics SKILL.md edits ~15, sensitive-file-guard DEFAULTS ~2, tests ~120)
- **Files touched**: 9 (hooks/workflow-advance.sh, hooks/sensitive-file-guard.sh, scripts/audit-record.sh [new], skills/caudit/SKILL.md, skills/cmetrics/SKILL.md, .correctless/ARCHITECTURE.md, tests/test-audit-findings-persistence.sh [new], tests/test-architecture-drift.sh [test-registration entry for the new test file — ABS-029 is not a path-scoped rule, so no `paths:` frontmatter coverage is needed], correctless/* mirrors via sync.sh)
- **New abstractions**: 1 (ABS-029 — audit findings persistence contract)
- **Trust boundaries touched**: TB-001 (phase-gate decision boundary in workflow-advance.sh + writer-script sensitive-file-guard protection)
- **Risk surface delta**: medium. A too-strict gate could block legitimate audit-done transitions; a too-loose gate misses the omission class. Mitigation: gate failure produces an explicit remediation message naming the missing file, plus the standard `override` escape hatch exists for emergencies. The script is small and CLI-only — easily auditable. Content-based matching (vs mtime-based) eliminates the ENV-003 git-op-timestamp-drift class entirely.

## Invariants

### INV-001: cmd_audit_done refuses without current-run round-JSON
- **Type**: must
- **Category**: data-integrity
- **Statement**: When `cmd_audit_done` is invoked, it MUST verify that at least one file matching `.correctless/artifacts/findings/audit-{preset}-*-round-*.json` exists AND contains a `started_at` JSON field whose value EQUALS the workflow state's `started_at`, where `{preset}` is read from `.audit.type` in the state file. The match is content-based, not mtime-based — string equality on the ISO-8601 `started_at` field. If `.audit.type` or `.started_at` is missing, null, or empty in the state file, `cmd_audit_done` exits non-zero with a diagnostic naming the missing field — it MUST NOT proceed with a literal `null` substitution that would produce a glob like `audit-null-*-round-*.json`. If the verification fails, `cmd_audit_done` exits non-zero and does NOT update the phase. The phase remains `audit`.
- **Boundary**: refs TB-001 (workflow-advance.sh phase-gate boundary)
- **Violated when**: `cmd_audit_done` updates the phase to `done` while no qualifying round-JSON exists; the matching uses mtime against `started_at` (filesystem timestamps lie after `git checkout`/`git clone` per ENV-003); the matching uses date-string comparison; the matching uses `phase_entered_at` (which can shift if the audit gets re-entered) instead of `started_at`; the JSON read uses anything other than `jq -r '.started_at'` exact-string equality; missing/null `.audit.type` is silently substituted (would let a corrupt state file pass the gate)
- **Guards against**: AP-026 (advisory-prose artifact-write contract); ENV-003 (filesystem mtime unreliable after git ops)
- **Test approach**: integration — fixture creates a workflow state in `audit` phase with a known `started_at`, runs `cmd_audit_done` without artifacts (expect non-zero + phase still `audit`), creates a round-JSON whose `started_at` field matches state, runs again (expect zero + phase = `done`). Plus a regression test: round-JSON exists with mtime newer than state but with a DIFFERENT `started_at` value (e.g., from a previous audit) — gate must reject it. Plus a missing-field test: state file with null `.audit.type` causes gate to exit non-zero with a diagnostic rather than constructing `audit-null-*` glob. Target tests: `tests/test-audit-findings-persistence.sh` `test_inv001_gate_blocks_without_artifact`, `test_inv001_gate_passes_with_matching_started_at`, `test_inv001_gate_rejects_mismatched_started_at`, `test_inv001_gate_rejects_null_audit_type`.
- **Risk**: critical
- **Implemented in**: hooks/workflow-advance.sh `cmd_audit_done` (filled during GREEN)

### INV-001a: cmd_audit_done remediation message names the expected path
- **Type**: must
- **Category**: functional
- **Statement**: When `cmd_audit_done` blocks for missing artifacts, the stderr message MUST include (a) the literal string `Audit findings missing`, (b) the expected glob `audit-{preset}-*-round-*.json` with the actual `{preset}` substituted from state, and (c) the `started_at` ISO timestamp from state. Vague errors like "audit not done" or "missing artifact" are forbidden — the user must be able to fix the gap from the message alone.
- **Boundary**: refs TB-001
- **Violated when**: the stderr lacks any of the three named elements; the message says "audit not complete" without naming the file
- **Guards against**: AP-026 — clear remediation prevents the user from working around the gate via override
- **Test approach**: integration — assert exit non-zero AND stderr contains all three required substrings. Target test: `tests/test-audit-findings-persistence.sh` `test_inv001a_remediation_message_explicit`.
- **Risk**: high

### INV-002: round-JSON files use the canonical path format and schema
- **Type**: must
- **Category**: data-integrity
- **Statement**: `audit-record.sh write-round` writes round-JSON files at exactly `.correctless/artifacts/findings/audit-{preset}-{date}-round-{N}.json` where `{preset}` matches `^[a-z][a-z0-9-]{0,31}$` (lowercase alpha-numeric + hyphen, 1-32 chars), `{date}` matches `^[0-9]{4}-[0-9]{2}-[0-9]{2}$` exactly (no path-traversal byte sequences), and `{N}` is a positive integer. The written JSON contains required fields: `preset` (string, matches the path's `{preset}`), `date` (string, matches the path's `{date}`), `round` (integer, matches the path's `{N}`), `findings` (array, may be empty), `rejected` (array, may be empty), `started_at` (ISO-8601 UTC timestamp matching workflow state — exact format `YYYY-MM-DDTHH:MM:SSZ` with literal `Z`, never `+00:00`). Existing optional fields (`specialist_lenses`, `deferred`, `findings_count`, etc.) are preserved if present in the input. Path format and schema anchored so `cmd_audit_done`'s content-based check has a stable contract to match against.
- **Violated when**: the script writes to a different path (e.g., `audit-{preset}-round-{N}.json` without date, or `findings/{preset}/round-{N}.json`); `{preset}` contains uppercase or special characters; `{preset}` exceeds 32 chars; `{date}` contains anything other than the literal `YYYY-MM-DD` regex (`../foo`, `2026-04-29/extra`, etc. are rejected); `{N}` is zero or negative; the written JSON is missing any of the 6 required fields; `started_at` uses non-UTC timezone notation (`+00:00` instead of `Z`); the path's `{preset}/{date}/{N}` disagree with the corresponding JSON fields
- **Test approach**: unit + structural — unit: invoke `audit-record.sh write-round qa 1 fixture.json` with valid input, assert the output file exists at the canonical path AND contains all 6 required fields with correct values. Plus negative cases: input missing `findings` exits non-zero, input with `{N}=0` exits non-zero, input with `preset=QA` (uppercase) exits non-zero. Structural: grep `skills/caudit/SKILL.md` for round-JSON references, assert all use the canonical pattern. Target tests: `test_inv002_canonical_path_and_schema`, `test_inv002_rejects_invalid_inputs`, `test_inv002_skill_references_canonical`.
- **Risk**: medium

### INV-002a: zero-finding audits write a non-empty JSON marker
- **Type**: must
- **Category**: data-integrity
- **Statement**: For a clean audit run (zero findings after Round 1 specialists), `/caudit` MUST invoke `audit-record.sh write-round {preset} 1 -` (with `started_at` and `date` resolved by the script from workflow state and current date) with stdin set to a JSON document containing at minimum `{"findings": [], "rejected": []}`. The script merges this with the schema-required fields (`preset`, `date`, `round`, `started_at`) and writes the canonical path. `started_at` is in canonical UTC `Z` form (per INV-002). The empty-findings file is the audit's evidence of having run; absence is NOT evidence of "no findings." When stdin is `-`, `audit-record.sh` MUST verify stdin is not a TTY (`[ ! -t 0 ]`) and exit non-zero with a clear "stdin must be piped" message if invoked interactively — prevents the script from blocking forever in interactive testing.
- **Boundary**: refs TB-001
- **Violated when**: a clean audit transitions to audit-done without writing the round-1 JSON; the round-1 JSON omits the `findings: []` or `rejected: []` field; `audit-record.sh write-round` accepts a stdin payload missing the `findings` array (then synthesizes it as empty — silently absorbing the contract violation); `started_at` is written as `+00:00` instead of `Z`; stdin reads block when stdin is a TTY
- **Guards against**: silent-telemetry variant where "no findings → no file" appears clean from upstream but indistinguishable from "audit didn't run" downstream
- **Test approach**: behavioral + structural. **Behavioral (load-bearing)**: invoke `audit-record.sh write-round qa 1 -` directly with stdin `{"findings": [], "rejected": []}` and a fixture workflow state file, assert the file at the canonical path contains all 6 required fields including `findings: []` and `rejected: []` and `started_at` matches the fixture's value byte-for-byte (no timezone reformatting). Plus unit: stdin missing `findings` exits non-zero with stderr identifying the missing field. Plus TTY test: invoke with no stdin redirection, assert exit non-zero with the "stdin must be piped" message rather than blocking. **Structural** (best-effort secondary signal — same AP-003 limitation as INV-006): grep `skills/caudit/SKILL.md` for the clean-audit handling block and assert it references `write-round` and `findings: []`; load-bearing enforcement is the behavioral test above. Target tests: `test_inv002a_clean_marker_written_with_required_schema`, `test_inv002a_started_at_canonical_utc_form`, `test_inv002a_script_rejects_missing_findings`, `test_inv002a_script_rejects_tty_stdin`, `test_inv002a_skill_handles_clean_audit_grep`.
- **Risk**: high

### INV-003: gate match is content-based and date-suffix-agnostic
- **Type**: must
- **Category**: functional
- **Statement**: The `cmd_audit_done` artifact-presence check MUST anchor its qualification on the round-JSON's `started_at` field equaling the workflow state's `started_at` field (string equality on the ISO-8601 timestamp). The check MUST NOT use the round-JSON's `date` field (the `YYYY-MM-DD` suffix in the filename), `phase_entered_at`, file mtime, or "today's date" as the matching key. An audit started at 23:55 on 2026-04-29 and completed at 00:05 on 2026-04-30 is accepted regardless of whether the round-JSON's `date` field reads `2026-04-29` or `2026-04-30` — the `started_at` content match is the load-bearing signal.
- **Boundary**: refs TB-001
- **Violated when**: the gate uses `date +%Y-%m-%d` to construct the expected glob and rejects files with a different `date` suffix; the gate uses file mtime as a fallback when `started_at` field is missing (legacy files MUST be rejected, not silently mtime-fallback-matched); the gate compares `started_at` to `phase_entered_at`
- **Guards against**: midnight-rollover false-negative gate failure; ENV-003 mtime unreliability after git ops; legacy-file false-positive (a pre-ABS-029 round-JSON without `started_at` must not satisfy the gate)
- **Test approach**: integration — three cases: (a) round-JSON dated yesterday but `started_at` matching state's started_at (today's audit) → gate accepts; (b) round-JSON dated today but `started_at` from a prior audit → gate rejects; (c) legacy round-JSON with no `started_at` field → gate rejects. Target tests: `test_inv003_gate_accepts_yesterday_dated_with_matching_started_at`, `test_inv003_gate_rejects_today_dated_with_stale_started_at`, `test_inv003_gate_rejects_legacy_files_without_started_at`.
- **Risk**: medium

### INV-004: history.md staleness is not a gate signal
- **Type**: must-not
- **Category**: functional
- **Statement**: `cmd_audit_done` MUST NOT check the existence, mtime, or content of `audit-{preset}-history.md`. The history file is an advisory append; its absence does not block the gate, and its presence does not satisfy the gate. The round-JSON is the load-bearing artifact.
- **Boundary**: refs TB-001
- **Violated when**: `cmd_audit_done` reads, stats, or globs the history file; a passing gate state requires history.md to have been appended
- **Guards against**: brittle-coupling failure mode where a failed history.md append blocks audit-done despite all round-JSONs being present
- **Test approach**: structural + integration — structural: extract `cmd_audit_done` body via awk (between function declaration and matching close brace), strip comment lines (`grep -v '^[[:space:]]*#'`), grep for `history.md` — expect zero matches on non-comment lines. Comments mentioning history.md (e.g., "see PRH-004 for history append behavior") are explicitly allowed. Integration: run `cmd_audit_done` with round-JSON present and history.md missing, assert phase transitions to done. Target tests: `test_inv004_no_history_check_in_gate_body` and `test_inv004_history_absent_gate_passes`.
- **Risk**: medium

### INV-005: /cmetrics multi-signal staleness uses max of two sources
- **Type**: must
- **Category**: functional
- **Statement**: When /cmetrics computes "days since last Olympics" for a preset, it MUST take the maximum of (a) the mtime of `audit-{preset}-history.md` if the file exists, (b) the mtime of the most recent file matching `audit-{preset}-*-round-*.json` if any match. The comparison is strictly mtime-based — /cmetrics is the advisory consumer side and intentionally does NOT cross-check the round-JSON's `started_at` content (that's the gate's job; mixing layers blurs the separation). If neither signal exists, the staleness reading is "no data" — never silently zero or "infinite" without the explicit "no data" label. Additionally, /cmetrics MUST count `audit-done` overrides separately from total overrides — a routine `audit-done` override is the AP-023 recurrence pattern for this gate specifically and warrants its own counter in the Override Health section.
- **Boundary**: refs TB-001 (consumer side of the persistence contract)
- **Violated when**: /cmetrics uses only history.md mtime and reports "16 days stale" when round-JSON files are newer; /cmetrics returns 0 days when both signals are missing instead of "no data"; /cmetrics introduces content-based logic (e.g., reading `started_at`) into the staleness computation — that belongs to the gate, not the consumer; the Override Health section conflates audit-done overrides with other override types
- **Guards against**: PMB-005 recurrence — the original bug class; AP-023 (override-as-routine) recurrence on the new gate
- **Acknowledged residual risk (L-17)**: ENV-003 says filesystem mtime is unreliable after git ops. The consumer side accepts this — /cmetrics is advisory and fail-open; a stale mtime produces a slightly-wrong staleness number but does not corrupt workflow state. The gate (INV-001) is content-based and immune to the same drift. Layer separation is intentional.
- **Test approach**: structural + behavioral. **Behavioral (load-bearing)**: fixture creates `audit-qa-history.md` with mtime 30 days ago and `audit-qa-2026-04-29-round-1.json` with mtime today; invoke /cmetrics' staleness computation; assert the result uses today's date (newer mtime wins). Plus a fixture with both signals missing → assert "no data" label appears literally. Plus an audit-done-override fixture: preserved override log with reason matching `audit-done` pattern, assert /cmetrics' Override Health section includes a separate counter line for audit-done overrides. **Structural** (best-effort, AP-003-class — same limitation as INV-006): grep `skills/cmetrics/SKILL.md` for the staleness computation block, assert it references both signals AND the literal `max`/`maximum`/`later of`/equivalent. Target tests: `test_inv005_max_picks_newer_signal`, `test_inv005_no_data_label_when_missing`, `test_inv005_audit_done_override_counter`, `test_inv005_skill_documents_max_of_two`.
- **Risk**: high

### INV-006: audit-record.sh is the sole writer to findings/audit-* paths
- **Type**: must
- **Category**: data-integrity
- **Statement**: Across all `skills/*/SKILL.md` files, no skill body may contain a literal Write/Edit/Bash-redirect to `.correctless/artifacts/findings/audit-{preset}-*-round-*.json` or `.correctless/artifacts/findings/audit-{preset}-history.md` other than via `bash scripts/audit-record.sh ...` invocations. All persistence flows through the script.
- **Boundary**: refs TB-001
- **Violated when**: `skills/caudit/SKILL.md` (or any other skill) instructs a direct `Write` or `Bash` redirect to one of the protected paths instead of invoking `audit-record.sh`; a future skill author bypasses the script and writes the JSON directly
- **Guards against**: drift-back to advisory-prose contract; ensures the script's invariants (path canonicalization, schema validation, history append atomicity) are always exercised
- **Test approach**: structural — grep all `skills/*/SKILL.md` files for write patterns to `findings/audit-*`, assert every match is preceded by `audit-record.sh` on the same or prior line. Target test: `test_inv006_sole_writer_via_script`. **Limitation (AP-003 class)**: this grep matches prose instructions written for an LLM, not code. It catches the obvious case (literal `Write(...)` or `>> findings/audit-...` in a skill body) but produces false negatives on rephrased writes ("persist the round results using the audit-record script") and false positives on reads ("when audit findings exist at findings/audit-..."). This is a best-effort structural check, not a proof. **PRH-001's literal-command-name grep (`audit-record.sh write-round`) is the load-bearing enforcement** — that pattern matches only the actual invocation form and is robust to rephrasing. INV-006's path-based grep is the secondary signal that catches direct-write drift; PRH-001 catches the writer-fanout class.
- **Risk**: medium

### INV-007: audit-record.sh exits 0 on success and non-zero on failure
- **Type**: must
- **Category**: functional
- **Statement**: `audit-record.sh` follows PAT-003 — every subcommand exits 0 on full success (file written + validation passed) and non-zero on any failure (invalid arguments, JSON parse error, write failure, validation failure). Stderr carries an error message identifying which subcommand failed and why. Stdout's success format: a single line containing the absolute path of the written file (no trailing whitespace, no JSON wrapper, no `OK` prefix). This single-line-path format is consumable by callers via `path=$(audit-record.sh write-round ...)`.
- **Violated when**: the script exits 0 despite a write failure (silent fail-open); error messages on stdout instead of stderr; the script swallows jq parse errors with `2>/dev/null` and exits 0; stdout contains JSON, multiple lines, status prefixes, or trailing whitespace on success
- **Test approach**: integration — fixture invokes `write-round` with malformed JSON stdin, asserts exit non-zero AND stderr contains "JSON parse" or similar; runs with valid input, asserts exit 0 AND stdout is exactly the absolute path with a trailing newline (single-line). Target tests: `test_inv007_failure_exits_nonzero`, `test_inv007_success_exits_zero`, `test_inv007_stdout_is_single_line_path`.
- **Risk**: medium

### INV-008: gate respects --override sentinel
- **Type**: must
- **Category**: resource-lifecycle
- **Statement**: `cmd_audit_done`'s artifact-presence check MUST honor the standard workflow-advance override sentinel — if the override flag file is present and within its 10-tool-call window, the gate logs the bypass and proceeds. This is the existing escape hatch that already applies to other phase-transition gates; ABS-029 adds no new exception path. The override is governed by ABS-020 (override scrutiny lifecycle) — supervisor review and Jaccard-similarity retry prevention apply to audit-done overrides identically to any other override.
- **Boundary**: refs TB-001 + the override mechanism already in workflow-advance.sh + ABS-020 (override scrutiny)
- **Violated when**: `cmd_audit_done`'s artifact check fires before the override is consulted; a separate `--force-audit-done` flag is added (would create a parallel escape hatch); the override-bypass log entry omits the audit-specific reason ("Audit findings missing — overridden")
- **Guards against**: gate-bypass proliferation (AP-023 routine-overrides class); ensures auditability of "why was this allowed without findings?"
- **Test approach**: integration — set up override sentinel, run `cmd_audit_done` without artifacts, assert phase advances to `done` AND the override log records the audit-specific bypass reason. Target test: `test_inv008_override_bypasses_with_log_entry`.
- **Risk**: medium

### INV-009: audit-record.sh is sensitive-file-guard protected
- **Type**: must
- **Category**: security
- **Statement**: The writer script `scripts/audit-record.sh` (and its install-mirror `.correctless/scripts/audit-record.sh`) is added to the DEFAULTS block in `hooks/sensitive-file-guard.sh`. Per the 2026-04-26 sole-writer convention recorded in CLAUDE.md ("Structurally-enforced sole-writer for meta files"), every script that is the canonical writer of a sensitive artifact must itself be sensitive-file-guard protected against autonomous Edit/Write — preventing the dead-code-in-security-paths failure mode (AP-022) where the writer is silently replaced by an agent and the contract becomes unenforceable.
- **Boundary**: refs TB-001 + ABS-027 / harness-fingerprint.sh precedent (same convention applied)
- **Violated when**: `scripts/audit-record.sh` or its mirror is missing from DEFAULTS; an agent can autonomously Edit/Write the script; the protection covers only one of the two paths (source or install mirror); a Bash redirect like `cat > scripts/audit-record.sh` succeeds because `_extract_bash_targets` doesn't normalize the path; `tee scripts/audit-record.sh` or `>> scripts/audit-record.sh` (append) succeeds — the protection MUST cover all write surfaces, not just `>` redirect
- **Guards against**: AP-022 (dead-code-in-security-paths); writer-replacement attack on the persistence contract
- **Test approach**: integration — submit each of {Edit, Write, MultiEdit} targeting both `scripts/audit-record.sh` and `.correctless/scripts/audit-record.sh` to sensitive-file-guard; submit each Bash form targeting both paths: `> path`, `>> path`, `tee path`, `cat src | tee path`, `2> path`, `&> path`; assert each is blocked with exit code 2. Target tests: `test_inv009_writer_script_protected_edit`, `test_inv009_writer_script_protected_bash_redirects`, `test_inv009_writer_script_protected_tee`, `test_inv009_install_mirror_protected`.
- **Risk**: high

## Prohibitions

### PRH-001: no skill other than /caudit may invoke audit-record.sh write-round
- **Statement**: `audit-record.sh write-round` is invoked only by `/caudit`. Other skills (/cverify, /cdocs, /cmetrics, etc.) read findings but never write. The structural test enforces this at the skill-prose level — direct invocations of `audit-record.sh write-round` from any `skills/*/SKILL.md` other than `caudit/SKILL.md` are forbidden.
- **Detection**: structural grep — target test `tests/test-audit-findings-persistence.sh` `test_prh001_only_caudit_writes`. Greps `skills/*/SKILL.md` for `audit-record.sh write-round`, asserts every match is in `skills/caudit/SKILL.md`.
- **Consequence**: writer-fanout reintroduces the original AP-026 class through a different path — multiple skills writing to the contract means no single skill owns "the audit ran" signal.

### PRH-002: cmd_audit_done has no environment-variable or flag bypass
- **Statement**: The artifact-presence check in `cmd_audit_done` honors only the standard override mechanism (INV-008). No `CORRECTLESS_SKIP_AUDIT_CHECK=1`, no `--no-verify`, no `audit-done --skip` subcommand. Adding any such bypass would re-open AUTH-R2-001-class confused-deputy: a flag intended for testing becomes the autonomous escape hatch.
- **Detection**: structural test asserts the gate's branching is restricted to the allowed inputs — a positive-shape assertion, not an enumeration of forbidden names. Specifically: extract `cmd_audit_done` body, list every conditional (`if`, `case`, `[[ ]]`), and assert each one's controlling expression references only one of {workflow state fields read via `jq`, override sentinel check, the constructed glob pattern}. Any branch on stdin, environment variable, positional argument beyond `cmd_audit_done`'s formal parameters, or external command exit code (other than `jq`/`find` which are part of the load-bearing read paths) fails the test. Target test: `tests/test-audit-findings-persistence.sh` `test_prh002_gate_branches_restricted_to_allowed_inputs`. The complementary blocklist grep (forbidden flag names like `--skip`, `--no-verify`) is retained as a secondary signal but is NOT the load-bearing check — drift to a new flag name would defeat the blocklist alone.
- **Consequence**: AUTH-R2-001 recurrence in a different surface area.

### PRH-003: audit-record.sh constructs destination paths only from CLI args and lib.sh helpers
- **Statement**: The script constructs its destination paths exclusively from CLI positional arguments (`{preset}`, `{round}`) and a hardcoded base directory `.correctless/artifacts/findings/`. It MUST NOT read any file outside the lib.sh source (workflow state file, config file, env-driven path templates, etc.) to derive the destination path. Reading the workflow state to populate the JSON's `started_at` field is permitted (that's content, not path), but state-derived inputs MUST NOT influence the destination path.
- **Detection**: structural — extract `audit-record.sh` body, identify every variable that contributes to destination-path construction (the file path passed to `cat > $path` or `mv $tmp $path`); assert each such variable's source is one of {CLI positional arg, hardcoded literal, lib.sh helper return value}. Variables sourced from `jq` reads of workflow state, config files, or env vars MUST NOT appear in path construction. Target test: `tests/test-audit-findings-persistence.sh` `test_prh003_path_construction_isolated_from_external_state`.
- **Consequence**: a state-driven or config-driven destination path opens a write-anywhere primitive (TB-001a class).

### PRH-004: history.md append is non-atomic but additive-only
- **Statement**: `audit-record.sh append-history` only appends to `audit-{preset}-history.md` — never rewrites or truncates. A partial-write failure leaves the existing content intact (the new entry may be missing, but old entries are not corrupted). The script does NOT use `locked_update_file` (which is for read-modify-write of structured JSON); it uses simple `>>` append with file-locking via `flock` to serialize concurrent appends.
- **Detection**: structural + behavioral. **Structural**: extract `append-history` body, assert it uses `>>` (or `tee -a`) and never `>` or `tee` without `-a`; assert no truncation primitives appear (`> "$path"`, `: > "$path"`, `truncate`, `cp /dev/null`). **Behavioral (load-bearing)**: fixture creates a history.md with N existing entries; spawn `append-history` and SIGKILL it after the first write syscall; assert the file still contains all N original entries byte-for-byte. The behavioral test catches the failure mode the structural grep can't — e.g., a future implementation that uses an atomic write via `cp original tmp; modify tmp; mv tmp original` (looks fine to grep, but a partial mv leaves the file truncated). Target tests: `tests/test-audit-findings-persistence.sh` `test_prh004_history_append_uses_append_redirect` and `test_prh004_partial_write_preserves_existing_entries`.
- **Consequence**: a partial-write that truncates history would silently destroy historical audit records — the exact data the contract is meant to protect.

### PRH-005: /cmetrics never derives audit recency from a single signal
- **Statement**: After this PR lands, /cmetrics SKILL.md must NOT contain any code path that derives "days since last Olympics" from only `history.md` mtime OR only round-JSON mtime. Both signals are computed and the max wins. A single-signal code path is the original PMB-005 bug.
- **Detection**: structural grep — target test reads `skills/cmetrics/SKILL.md`, finds the staleness computation block, asserts both `history.md` and `round-*.json` (or equivalent glob) are referenced AND the comparison uses `max`/`maximum`/`later of`/equivalent. Target test: `tests/test-audit-findings-persistence.sh` `test_prh005_consumer_uses_both_signals`.
- **Consequence**: PMB-005 recurrence — the exact same bug class with the same observable failure mode.

## Boundary Conditions

### BND-001: Skill orchestrator → cmd_audit_done CLI
- **Boundary**: phase-transition CLI boundary in `hooks/workflow-advance.sh`
- **Input from**: skill orchestrator (`/caudit` or any other skill that calls `bash hooks/workflow-advance.sh audit-done`)
- **Validation required**: read `.audit.type` and `.started_at` from the active state file; reject if either is missing/null/empty; check at least one matching round-JSON contains a `started_at` field equal to state's `started_at`; if check fails AND no override is active, exit non-zero with the explicit remediation message (INV-001a)
- **Failure mode**: fail-closed — phase remains `audit`, exit code is non-zero, stderr names the missing path. Override sentinel can bypass per INV-008.
- **Concurrency**: the workflow state file is per-branch, and only one audit can be active per branch (audit-start refuses if state already exists). Concurrent `cmd_audit_done` invocations against the same branch are not a concern in the design — the gate is read-only against the round-JSON and the state-file write at phase transition uses `locked_update_state` per PAT-004. A second concurrent invocation after the first succeeds simply finds phase already `done` and exits via `require_phase`'s existing check.
- **Test**: integration tests in `tests/test-audit-findings-persistence.sh` — gate-blocks-without-artifact, gate-passes-with-artifact, gate-respects-override

### BND-002: /cmetrics consumer → mtime + history-md filesystem reads
- **Boundary**: read-only consumer boundary; /cmetrics reads filesystem state to compute staleness
- **Input from**: filesystem state of `.correctless/artifacts/findings/`
- **Validation required**: handle missing files gracefully (no exception); compute max of available signals; label "no data" explicitly when both signals absent
- **Failure mode**: fail-open — /cmetrics is advisory; missing data produces a "no data" label, never a hard error
- **Test**: integration test runs /cmetrics with various filesystem states (empty findings dir, history-only, round-only, both)

## STRIDE Analysis

For the implicit trust boundary at `cmd_audit_done` (TB-001 — phase-transition gate decides whether the workflow advances to `done` based on filesystem state):

### Spoofing
- **Threat**: Agent constructs a spoofed round-JSON file with bogus content (e.g., `findings: []` claiming a clean audit when the actual audit produced findings) to satisfy the gate.
- **Mitigation**: ACCEPTED. The gate enforces presence, not authenticity. The threat model for ABS-029 is omission, not tampering — an agent that wants to fake an audit can already do so by editing fix commits, faking specs, or any other workflow artifact. The persistence contract closes the silent-omission class, which is the observed failure mode in PMB-005. Tampering is a separate class; if it becomes a real concern, it warrants its own spec (likely sensitive-file-guard structural enforcement on findings paths).

### Tampering
- **Threat**: Agent modifies an existing round-JSON to alter findings post-hoc (e.g., to make a recurring pattern look like a one-off).
- **Mitigation**: ACCEPTED — same reasoning as Spoofing. Tampering is downstream of the omission class and out of scope per Q2 brainstorm. Future feature can add sensitive-file-guard protection of `findings/` paths if observed.

### Repudiation
- **Threat**: Agent transitions audit to `done` and later denies the audit ran.
- **Mitigation**: INV-001 + INV-001a — the persisted round-JSON IS the audit's evidence. After this PR lands, "audit ran" implies "round-JSON exists" and vice versa.

### Information Disclosure
- N/A. Findings JSONs contain audit content (already visible in the conversation). No secrets traverse the boundary.

### Denial of Service
- **Threat 1**: A too-strict gate blocks legitimate audit-done transitions, forcing routine overrides (AP-023 class).
- **Mitigation 1**: INV-001a (explicit remediation message names the expected file) + the script makes writing the file trivial. Overrides should remain rare. /cmetrics' override-frequency monitor will surface the issue if it manifests.
- **Threat 2**: A flock contention on history.md append blocks indefinitely.
- **Mitigation 2**: PRH-004 — history.md is non-blocking advisory; round-JSON is the gate. flock with a 5-second timeout on history.md (the script's `append-history` subcommand uses `flock -w 5`); on timeout, log a warning to stderr and exit 0 (history append failure does NOT block round-JSON write or gate transition).

### Elevation of Privilege
- **Threat**: A skill other than /caudit gains the ability to mark an audit "complete" by invoking `audit-record.sh write-round` with arbitrary content, then calling `cmd_audit_done`.
- **Mitigation**: PRH-001 — structural test enforces that only /caudit's SKILL.md invokes `write-round`. The script itself doesn't authenticate the caller (impractical in a shell environment), but the structural enforcement at the skill level catches drift.

## Environment Assumptions

### EA-001: workflow state file is the source of truth for audit metadata
- **Assumption**: `cmd_audit_done` reads `.audit.type` and `.started_at` from the state file at `.correctless/artifacts/workflow-state-{branch-slug}.json`. The state file is written only by `workflow-advance.sh` (PAT-004 sole-writer convention); no other tool modifies it during an audit.
- **Refs**: PAT-004 (state file sole writer)
- **Consequence if wrong**: a tampered state file with a stale `started_at` would let the gate accept old round-JSONs as current. PAT-004's sole-writer convention is structurally enforced by sensitive-file-guard (state files are in DEFAULTS).

### EA-001a: state's started_at is frozen at audit-start
- **Assumption**: `cmd_audit_start` writes `.started_at` to the state file at audit initialization, and NO subsequent phase transition (including `cmd_audit_fix` re-entry from a fix round) re-stamps `.started_at`. `.phase_entered_at` shifts on phase changes; `.started_at` is immutable for the lifetime of the audit.
- **Refs**: PAT-004 + cmd_audit_start in workflow-advance.sh (existing behavior — this assumption documents the existing invariant, doesn't add a new one)
- **Consequence if wrong**: if a future change causes `started_at` to update on phase re-entry, round-1's persisted `started_at` no longer matches state's, and the gate rejects round-1 even though it's the legitimate first round of the same audit. Mitigation: the existing `cmd_audit_fix` and other audit-phase transitions only touch `.phase` and `.phase_entered_at`. A regression test asserts state's `started_at` is unchanged after a simulated fix-round transition. Target test in test-audit-findings-persistence.sh: `test_ea001a_started_at_immutable_through_fix_round`.

### EA-002: gate is content-based, immune to filesystem mtime drift
- **Assumption**: The gate's matching key is the round-JSON's `started_at` field (string equality with workflow state's `started_at`), NOT filesystem mtime. ENV-003 explicitly documents that filesystem mtime is unreliable after `git clone`, `git checkout`, or `git rebase` — exactly the operations a developer might run mid-audit. Content-based matching sidesteps that entirely.
- **Refs**: ENV-003 (filesystem mtime unreliable after git ops — already documented in `.correctless/ARCHITECTURE.md`)
- **Consequence if wrong**: this assumption can't be wrong in the way mtime-based matching can — equality on a string field is deterministic regardless of file timestamps. The only failure mode is a tampered state file with a stale `started_at` (covered by EA-001 / PAT-004 sole-writer of state files).

### EA-003: jq is available for state-file reads in cmd_audit_done
- **Assumption**: `jq` is present (ENV-002 — jq 1.7+ project-wide assumption). `cmd_audit_done` uses `jq -r '.audit.type'` and `jq -r '.started_at'` to read state. PAT-001 governs PreToolUse hooks specifically and is not the relevant citation here — `cmd_audit_done` is a hook-side function within `workflow-advance.sh`, not a PreToolUse hook.
- **Refs**: ENV-002 (jq 1.7+ project-wide assumption)
- **Consequence if wrong**: `cmd_audit_done` exits with the existing "jq not found" error (already in workflow-advance.sh's preamble); no new failure mode introduced.

## Open Questions

All resolved during /cspec brainstorm Step 0:

- **OQ-001 [RESOLVED via Q1]**: Zero-finding audits MUST write round-JSON with `findings: []`. Even clean audits leave evidence.
- **OQ-002 [RESOLVED via Q2]**: No retroactive reconstruction of the 2026-04-26 audit record. Gap is self-documenting; fabricated record would be a permanent liability.
- **OQ-003 [RESOLVED via Q3]**: /cmetrics consumer uses two signals (`max(history.md mtime, latest round-JSON mtime)`), not three. PMB reference is sparse and adds defensive bloat for marginal coverage.

## Approved Architecture Updates (deferred to /cdocs)

### Add ABS-029 to `.correctless/ARCHITECTURE.md`

**Trigger**: this spec's INV-001..INV-009 require a single ABS entry to anchor the contract. The entry must land in this PR alongside the gate that enforces it (per AP-026 — writing the contract before the enforcement is the antipattern this spec exists to address).

**Insertion location**: after `### ABS-028: Test-features baseline contract`, before `## Patterns`.

**Draft entry**:

```markdown
### ABS-029: Audit findings persistence contract (.correctless/artifacts/findings/)
- **What**: Per-audit-run findings artifacts at `.correctless/artifacts/findings/audit-{preset}-{date}-round-{N}.json` (one per round, including round-1 with `findings: []` and `rejected: []` for clean audits) and append-only run summary at `.correctless/artifacts/findings/audit-{preset}-history.md`. Round-JSON required schema: `preset`, `date`, `round`, `findings` (array), `rejected` (array), `started_at` (ISO-8601 UTC timestamp `YYYY-MM-DDTHH:MM:SSZ` matching workflow state). Sole writer: `scripts/audit-record.sh` (and its install-mirror `.correctless/scripts/audit-record.sh`) invoked exclusively by `/caudit` (PAT-003 phase-transition script — `write-round` and `append-history` subcommands; verify lives in the gate, not the script). Consumers: `/cmetrics` (last-Olympics staleness via `max(history.md mtime, latest round-JSON mtime)`, run counts, average convergence), `/caudit` itself on subsequent runs (recurring-pattern detection, prior-finding context for Round 1 specialists), `/cdevadv` (recurring-pattern referrals).
- **Invariant**: `scripts/audit-record.sh` is the sole writer and is itself sensitive-file-guard protected (matches the harness-fingerprint.sh sole-writer-convention, AP-022 mitigation). `cmd_audit_done` in `hooks/workflow-advance.sh` refuses the transition to `done` unless at least one round-JSON exists whose `started_at` field equals the workflow state's `started_at` (content-based string equality, not filesystem mtime — robust to ENV-003 post-git-op timestamp drift). Zero-finding audits MUST still write round-1 with `findings: []` and `rejected: []` — absence of the file is NOT evidence of "no findings." `/cmetrics` MUST cross-check both signals when computing staleness; single-signal staleness reading is forbidden. The override sentinel (workflow-advance.sh standard mechanism) is the only bypass; no flag or env-var escape hatch.
- **Enforced at**: `hooks/workflow-advance.sh` (`cmd_audit_done` precondition + content-based match), `scripts/audit-record.sh` (writer), `hooks/sensitive-file-guard.sh` (writer-script protection via DEFAULTS — INV-009), `skills/caudit/SKILL.md` (sole invoker of write-round), `skills/cmetrics/SKILL.md` (multi-signal consumer), `tests/test-audit-findings-persistence.sh`
- **Violated when**: `cmd_audit_done` transitions phase to `done` without a content-matching round-JSON; the gate uses mtime, date suffix, or any non-content key for matching; a consumer derives staleness from a single mtime; any skill other than `/caudit` invokes `audit-record.sh write-round`; `cmd_audit_done` adds an env-var or flag escape hatch; `audit-record.sh` constructs destination paths from config-derived input; the round-JSON path format diverges from `audit-{preset}-{date}-round-{N}.json`; the writer script is missing from sensitive-file-guard DEFAULTS
- **Test**: `tests/test-audit-findings-persistence.sh` (INV-001..009, PRH-001..005, BND-001..002)
- **Guards against**: AP-026, AP-022
```

## Allowed-Tools Cross-Check (AP-008)

- `/caudit` invokes `bash scripts/audit-record.sh write-round ...` and `bash scripts/audit-record.sh append-history ...`. In plugin-distributed installs the resolved path becomes `bash .correctless/scripts/audit-record.sh ...`. Prerequisite: `/caudit`'s `allowed-tools` frontmatter must include BOTH `Bash(bash scripts/audit-record.sh*)` AND `Bash(bash .correctless/scripts/audit-record.sh*)` — a single glob covering one path leaves the other resolution unprotected. Add both during GREEN if not already covered.
- `/cmetrics` reads mtime via filesystem stat — no new tool surface required.
- `cmd_audit_done` uses `find` and `jq` from inside the hook — already on the hook's standard tool surface.
