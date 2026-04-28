# Spec: Harness Fingerprint + Model Upgrade Detection

## Metadata

- **Created**: 2026-04-25
- **Revised**: 2026-04-26 (post-/creview-spec — major restructure per CR-1..CR-4)
- **Status**: revised
- **Impacts**: skills/cspec, skills/cstatus, skills/csetup, skills/cauto, scripts/lib.sh, hooks/sensitive-file-guard.sh, .correctless/meta/ contract (ABS-005 neighborhood)
- **Branch**: feature/opus-4-7-compat
- **Research**: null
- **Recommended-intensity**: high
- **Intensity**: high
- **Intensity reason**: project floor (`workflow.intensity: high` in workflow-config.json) + file path signal (touches hooks/sensitive-file-guard.sh and adds a new skill)
- **Override**: none

## Context

The Correctless workflow's correctness model implicitly depends on a single Anthropic model version's uncontracted behavioral defaults — length caps, parallel-tool-call preferences, anti-defensive code priors, in-context skill inlining, etc. When Anthropic ships a new model OR updates the harness defaults within an existing model version, the workflow regresses silently. The Opus 4.6→4.7 audit (2026-04-24, see `OPUS_4_7_MIGRATION.md`) demonstrated this concretely: 3 distinct findings, none surfaced by metrics, none caught by tests.

This feature ships two bundled mechanisms — (a) a **deterministic harness fingerprint** computed from `{model_name}+{HARNESS_VERSION}` where `HARNESS_VERSION` is a manually-maintained integer constant in `scripts/harness-fingerprint.sh` that the maintainer increments when a behavioral change is observed, and (b) a `/cmodelupgrade` skill that compares the current model+version combination's per-feature pipeline metrics against stored baselines and produces a regression report. C-2 and C-5 from the migration doc are bundled because the detection signal (fingerprint) without the response mechanism (regression comparison) is incomplete.

**"Harness" defined**: for the purposes of this feature, "harness" means the runtime behavior shaped by Anthropic's system prompt + system-reminder injections + default tool surface as observed by the orchestrator. Length caps, "trust but verify" instructions, parallel-tool-call preferences, default subagent dispatch behavior all qualify. MCP server availability and project CLAUDE.md content do NOT qualify (those are project-controlled).

**Why no LLM probe** (CR-2 from /creview-spec, 2026-04-26): the original spec proposed using an LLM probe to introspect distinctive harness substrings. That approach had compounding problems — undefined channel between agent and script, stability uncertainty, a new trust boundary, susceptibility to negation-spoofing, and required a fallback gate (INV-013 in the v1 spec) because the probe might not work. If the fallback is the thing you trust, make it the primary. A deterministic version constant is testable, has no trust boundary, and aligns with how harness changes actually get noticed in practice (a human observes "things feel wrong" within one session — exactly how this audit started). Less automated, more reliable.

## Scope

**In scope:**

- New script `scripts/harness-fingerprint.sh` that:
  - Reads `HARNESS_VERSION` integer constant defined at the top of the script (commit-controlled — bumped by maintainer when behavioral change is observed)
  - Reads current model name from environment (Claude Code provides this — exact mechanism resolved during /ctdd)
  - Computes `sha256("{model_name}|{HARNESS_VERSION}")` as the fingerprint
  - Compares against stored value in `.correctless/meta/harness-fingerprint.json`
  - Returns status code (`first_seen`, `unchanged`, `version_bumped`, `corrupted_recovered`)
  - Accepts `--session-id <id>` and `--meta-dir <path>` flags for testability (defaults to live values)
- A `harness_fingerprint_check` invocation block added to `/cspec` at Step 0 (before Socratic brainstorm), with structural marker `<!-- correctless:harness-fingerprint:invocation -->` for grep-test stability
- Per-session notification dedup using flag file at `.correctless/artifacts/harness-notified-{session-id}.flag`. Session-id derived from `get_current_session_id()` in `scripts/lib.sh` (extract as shared helper) using **process PID + boot time** (read from `/proc/{pid}/stat` or fall back to process start timestamp on non-Linux)
- New skill `skills/cmodelupgrade/SKILL.md` that:
  1. Reads current model identifier and HARNESS_VERSION (via the script)
  2. Reads `.correctless/meta/model-baselines.json` for matching baseline (key: `{model_id}+{HARNESS_VERSION}`)
  3. **Bootstrap mode (first run after install for existing users)**: aggregate per-feature metrics from runs that don't have a HARNESS_VERSION tag (these predate this feature) — present as "pre-fingerprint baseline" with explicit labeling that fingerprint comparison applies only from the current version forward
  4. **Bootstrap mode (>=M qualifying runs available)**: aggregate per-feature metrics from `.correctless/meta/intensity-calibration.json` (QA rounds, total_tokens) + `.correctless/artifacts/cost-{slug}.json` (USD cost per ABS-026) + `.correctless/artifacts/workflow-state-{slug}.json` (phase counts) for the most recent N feature runs at the current model+version. Default M=2. Surface source feature slugs and durations to the human for validation before saving as authoritative baseline.
  5. **No-baseline mode**: if zero qualifying runs exist anywhere, display "No baseline available — capture one with /cmodelupgrade --capture-baseline (runs /cauto on .correctless/test-features/baseline.md)" and exit 0. Never compare against zero or null.
  6. **Subsequent invocations**: when both bootstrap data and a controlled baseline exist, compare against controlled baseline by default; offer bootstrap as alternate view.
- Baseline storage at `.correctless/meta/model-baselines.json` with `schema_version: 1` from creation
- `lib.sh`: extract `get_current_session_id()` as shared helper (single source of truth — HP-4)
- Template at `templates/test-features/baseline.md` (small reference feature exercising the standard /cauto pipeline)
- `/csetup` step that scaffolds `.correctless/test-features/baseline.md` from the template (idempotent — never overwrites)
- `/cstatus` advisory line: `Harness: model={X} version={Y} fingerprint={hash[:8]} status={ok|new|version-bumped}` between workflow state and intensity calibration sections
- `/cauto` Auto Run Report (ABS-013) "What to Review First" section surfaces any harness warning emitted during the run

**Out of scope:**

- LLM probe-based detection (rejected — see Context above and /creview-spec CR-2)
- Auto-recommendation of which agents to migrate (the migration arc itself handles this)
- **Per-skill granularity in regression reports** — deferred per CR-1. The data sources to support per-skill (audit-trail recording per-phase qa_rounds, token-tracking backfilled from cost artifacts) don't exist yet. Report is per-feature for now. Add a `Future` note pointing at the upstream producer changes that would unlock per-skill.
- Auto-applying `/cmodelupgrade` recommendations (always advisory)
- Cross-project fingerprint comparison
- Detection of harness changes mid-session (a session that started before a HARNESS_VERSION bump continues with the old fingerprint until next session)
- Automatic detection of behavioral change without human bumping HARNESS_VERSION (deliberate — see EA-004)

## Complexity Budget

- **Estimated LOC**: ~350 (script ~100, new skill ~250, /cspec patch ~30, /csetup patch ~20, lib.sh helper ~30, template ~50; tests ~400 separately) — substantially smaller than v1 estimate of 600 because the probe orchestration is gone
- **Files touched**: 9 (new script, new skill, /cspec patch, /csetup patch, /cstatus patch, /cauto patch, sensitive-file-guard patch, lib.sh extension, sync.sh entry, new template; tests separate)
- **New abstractions**: 1 (ABS-027: Harness fingerprint store contract)
- **Trust boundaries touched**: 0 (advisory mechanism — the LLM probe TB from v1 is gone with the probe)
- **Risk surface delta**: low (deterministic computation, advisory output, fail-open posture, no LLM-in-the-loop for detection)

## Invariants

### INV-001: Fingerprint is the literal string `"{model_name}|{HARNESS_VERSION}"`
- **Type**: must
- **Category**: functional
- **Statement**: The fingerprint stored in `.correctless/meta/harness-fingerprint.json` and used as a key everywhere is the literal string `"{model_name}|{HARNESS_VERSION}"` (no hashing) where `model_name` is the current model identifier and `HARNESS_VERSION` is the integer constant defined at the top of `scripts/harness-fingerprint.sh`. Hashing was dropped per /creview-spec round 2 (HI-1) — neither input is secret, and a literal key is debuggable (you can read the stored value and immediately know what it represents).
- **Boundary**: ABS-027
- **Violated when**: Additional inputs are mixed in, the separator changes, model_name capitalization is normalized differently across producers and consumers, or any consumer attempts to hash the fingerprint
- **Test approach**: unit — given fixed `model_name` and `HARNESS_VERSION`, assert the output is exactly `"{model_name}|{HARNESS_VERSION}"`
- **Risk**: low

### INV-002: Fingerprint changes when HARNESS_VERSION is bumped
- **Type**: must
- **Category**: functional
- **Statement**: Incrementing the `HARNESS_VERSION` constant in `scripts/harness-fingerprint.sh` causes the next invocation to produce a different fingerprint than the previously stored value. The status code returned is `version_bumped`.
- **Boundary**: ABS-027
- **Violated when**: Hash collision (vanishingly unlikely), or status code mapping fails to distinguish bump from corruption
- **Test approach**: unit — script run twice with bumped constant; assert hashes differ + status `version_bumped`
- **Risk**: low

### INV-003: Notification fires at most once per session
- **Type**: must
- **Category**: functional
- **Statement**: For a given fingerprint mismatch detected at session S (where session-id is derived from `get_current_session_id()` returning process PID + boot time), exactly one notification is emitted across all `/cspec` invocations within S. Subsequent invocations within S see the existing flag file at `.correctless/artifacts/harness-notified-{session-id}.flag` and skip the notification.
- **Boundary**: ABS-027
- **Violated when**: Flag file is not written, session-id returns different values across same-session invocations, or the flag file check is skipped
- **Guards against**: notification fatigue
- **Test approach**: integration — invoke script twice in same session with mismatched fingerprint, assert exactly one notification observed (use explicit `--session-id` flag for determinism)
- **Risk**: medium

### INV-004: Script I/O completes within performance budget
- **Type**: must
- **Category**: functional
- **Statement**: The script (no LLM call involved — pure I/O, hashing, comparison) completes in under 200ms wall time on a typical developer machine. No degradation as session count grows.
- **Boundary**: ABS-027
- **Test approach**: integration — script wrapped in `time`, asserts wall time < 200ms across 10 invocations on CI-equivalent hardware (LO-1 noted: relax if CI is consistently slow)
- **Risk**: low

### INV-005: First-run handling is silent
- **Type**: must
- **Category**: functional
- **Statement**: When `.correctless/meta/harness-fingerprint.json` does not exist (first run on a project), the script writes the current fingerprint with status `first_seen`, returns success, and `/cspec` emits no warning to the user.
- **Boundary**: ABS-027
- **Test approach**: integration — delete fingerprint file, invoke script, assert no warning + assert file exists post-invocation
- **Risk**: low

### INV-006: Corruption fails open
- **Type**: must
- **Category**: functional
- **Statement**: When `.correctless/meta/harness-fingerprint.json` exists but is malformed, the script logs a one-line warning to stderr, returns exit 0, overwrites with a fresh fingerprint, and returns status `corrupted_recovered`.
- **Boundary**: ABS-027
- **Test approach**: integration — write malformed JSON, invoke script, assert exit 0 + warning + file recovered
- **Risk**: medium

### INV-007: cmodelupgrade does not write the fingerprint store
- **Type**: must-not
- **Category**: data-integrity
- **Statement**: `/cmodelupgrade` reads `.correctless/meta/harness-fingerprint.json` to identify the current harness, but never writes, modifies, or deletes it. Sole writer is `scripts/harness-fingerprint.sh`. Mirrors ABS-005 cspec/cverify separation.
- **Test approach (HI-5 round-2 disposition)**: integration test is the gate — invoke `/cmodelupgrade` end-to-end, snapshot the fingerprint file before+after via SHA-256, assert byte-equal. Belt-and-suspenders: also grep `skills/cmodelupgrade/SKILL.md` for any write reference to the fingerprint file (first-pass keyword check) AND assert allowed-tools does not include the fingerprint write permission. The integration test is the actual proof of the invariant; the grep is a fast smoke check.
- **Risk**: low

### INV-008: Baseline file keyed by the same literal as the fingerprint, exact-match only
- **Type**: must
- **Category**: data-integrity
- **Statement**: `.correctless/meta/model-baselines.json` stores baseline metrics keyed by the same literal string defined in INV-001 (`"{model_name}|{HARNESS_VERSION}"`, e.g., `claude-opus-4-7|1`). Same model under two different versions stores two distinct baselines. Lookup by full literal only — partial-key matches forbidden. The fingerprint and the baseline key are the same string by construction (HI-1 unification — single source of truth, no derivation drift).
- **Test approach**: unit — synthetic baseline file with multiple keys, assert /cmodelupgrade lookup returns only exact-match; structural test asserts INV-001's fingerprint is the same string used as the baseline key
- **Risk**: medium

### INV-009: Per-feature regression report [integration]
- **Type**: must
- **Category**: functional
- **Statement**: When a baseline exists for the current model+version, `/cmodelupgrade` produces a report with one row per feature (NOT per skill) and at least these metrics per row, drawn from real producers: `total_qa_rounds` from `.correctless/meta/intensity-calibration.json`, `total_tokens` from `.correctless/meta/intensity-calibration.json`, `total_cost_usd` from `.correctless/artifacts/cost-*.json` (per ABS-026 — read across all branches via glob, NOT a hardcoded slug list per ME-14/AP-024), `phase_count` from `.correctless/artifacts/workflow-state-{slug}.json`. The default sample window is **N=5 most recent feature runs at the current model+version** (ME-11 round-2 disposition — enough for variance estimation, recent enough to reflect current state). For each metric: baseline value, current value, absolute delta, percent change.
- **Cost artifact field path (HI-2 round-2)**: the exact field for `total_cost_usd` within `cost-{slug}.json` is pinned during /ctdd RED by reading `compute-session-cost.sh`'s output schema; a structural test asserts producer and consumer agree on the field path (same pattern as ABS-023 entrypoints contract).
- **Exit codes (HI-3 round-2)**: `/cmodelupgrade` exit-code contract:
  - `0` — completed successfully (includes no-baseline message per INV-009b)
  - `1` — unexpected error (read failure on producer files, jq error, etc.)
  - `2` — unrecoverable (baseline file corrupt and migration unavailable)
- **Future**: per-skill granularity requires audit-trail to record per-phase qa_rounds and token-tracking to backfill from cost artifacts — both out-of-scope here.
- **Boundary**: ABS-027
- **Violated when**: Report uses sources other than the four named, computes metrics not enumerated, reports per-skill (current implementation must be per-feature), or hardcodes a slug list instead of globbing
- **Test approach**: integration
- **Integration contract**:
  - **Entry**: invocation of `/cmodelupgrade` skill via Skill tool from a session with populated `.correctless/meta/intensity-calibration.json`, `.correctless/artifacts/cost-*.json`, and `.correctless/artifacts/workflow-state-*.json` from at least 2 prior `/cauto` runs at the current model+version
  - **Through**: the skill must read all three sources via Read or Bash glob (not via mocks); must compute aggregations from real file contents using jq; must lookup baseline from real `.correctless/meta/model-baselines.json` (not mocked); ABS-026's prohibition against deriving USD from token-log is respected (cost comes from cost artifacts only); cost glob pattern is `cost-*.json` (not a hardcoded slug list)
  - **Exit**: stdout or markdown report contains a table with one row per feature (up to N=5), 4 metric columns; report references actual numeric deltas computed from input files; no mock of any data-source-parsing logic
- **Risk**: high (this is the core regression-detection deliverable)

### INV-009b: No baseline → explicit message, never compare against zero
- **Type**: must
- **Category**: functional
- **Statement**: When the baseline is missing, empty, or has zero qualifying entries for the current model+version, the report MUST display a clear `"No baseline available — capture one with /cmodelupgrade --capture-baseline"` message and exit 0. Reports that render against zero or null baselines are forbidden — they're the DA-004 self-referential-metrics class.
- **Boundary**: ABS-027
- **Violated when**: Any code path produces a report whose baseline column shows 0 or null without explicitly indicating no-baseline state
- **Guards against**: DA-004 (self-referential metrics) and HP-5
- **Test approach**: integration — invoke /cmodelupgrade with empty baseline file, assert the no-baseline message + exit 0; invoke with missing key, assert same
- **Risk**: high

### INV-010: Fingerprint check fires before /cspec Step 0
- **Type**: must
- **Category**: functional
- **Statement**: `skills/cspec/SKILL.md` invokes `bash scripts/harness-fingerprint.sh check` before any other Step 0 instructions execute. The invocation is marked with the structural HTML comment `<!-- correctless:harness-fingerprint:invocation -->` immediately preceding it (used by the structural test instead of line-position grep — ME-11).
- **Boundary**: ABS-027
- **Test approach**: structural — grep `skills/cspec/SKILL.md` for the marker; assert it appears before the "Step 0" section header AND before any reference to "Socratic brainstorm"
- **Risk**: low

### INV-011: HARNESS_VERSION value stored in fingerprint file alongside hash
- **Type**: must
- **Category**: data-integrity
- **Statement**: The fingerprint file JSON includes `harness_version` (integer) and `model` (string) fields alongside `fingerprint` (sha256 hash) and `timestamp`. Allows debugging without recomputing.
- **Boundary**: ABS-027
- **Test approach**: unit — assert file schema includes all four fields after first write
- **Risk**: low

### INV-012: /cmodelupgrade SKILL.md uses explicit path discovery for every artifact
- **Type**: must
- **Category**: functional
- **Statement**: Every artifact read by `/cmodelupgrade` (intensity-calibration.json, cost-{slug}.json, workflow-state-{slug}.json, model-baselines.json, harness-fingerprint.json) has an explicit path-discovery step in the SKILL.md — either via `bash .correctless/hooks/workflow-advance.sh status` or via direct workflow-state read. The skill never assumes the orchestrator already knows artifact paths from conversation context. Direct mitigation of AP-025 / PMB-004.
- **Boundary**: ABS-027
- **Test approach**: structural — grep `skills/cmodelupgrade/SKILL.md` for path discovery patterns matching the PMB-004 fix template; assert each artifact read is preceded by a discovery instruction
- **Risk**: medium

### INV-013: ABS-027 entry exists in ARCHITECTURE.md
- **Type**: must
- **Category**: data-integrity
- **Statement**: `.correctless/ARCHITECTURE.md` contains an `### ABS-027:` entry whose body matches the §New Architectural Entry text in this spec.
- **Boundary**: n/a (architectural)
- **Test approach**: structural — `tests/test-architecture-drift.sh` extends to assert ABS-027 presence
- **Risk**: low

### INV-014: Bootstrap baseline requires ≥M=2 qualifying runs + human validation
- **Type**: must
- **Category**: data-integrity
- **Statement**: First `/cmodelupgrade --capture-baseline` invocation requires at least 2 qualifying runs at the current model+version. The skill surfaces source feature slugs + durations + sample size to the human for explicit confirmation before writing the baseline file. If the human declines, the baseline is not saved (status: `bootstrap_declined`). **Quality filter (LO-2 round-2)**: source runs marked `incomplete` in their workflow state (pipeline aborted mid-run) are excluded from the qualifying pool — degenerate runs cannot poison the baseline.
- **Testability flag (HI-4 round-2)**: the skill accepts a `--auto-confirm` flag (testing-only, documented as such in SKILL.md). Tests assert both flows: interactive flow asserts the prompt is present; automated flow asserts the flag bypasses the prompt AND writes an audit-trail entry of type `bootstrap_auto_confirmed` so the bypass is traceable.
- **Boundary**: ABS-027
- **Guards against**: bootstrap baseline poisoning (HI-4 / RT-005) — a degenerate first run becoming the comparison reference forever
- **Test approach**: integration — invoke with 1 qualifying run, assert "need at least 2" message; invoke with 2 runs, assert human-confirmation prompt is presented; assert decline → no write; invoke with `--auto-confirm`, assert prompt bypassed AND audit entry written; invoke with 1 incomplete + 2 complete runs, assert incomplete is excluded
- **Risk**: medium

### INV-015: /cstatus shows fingerprint state in advisory line format
- **Type**: must
- **Category**: functional
- **Statement**: `/cstatus` output includes a one-line entry of the form `Harness: model={X} version={Y} fingerprint={hash[:8]} status={ok|new|version-bumped}` placed between the workflow state and intensity calibration sections.
- **Boundary**: ABS-027
- **Test approach**: structural — invoke /cstatus, assert output contains a line matching the regex `Harness: model=\S+ version=\d+ fingerprint=[0-9a-f]{8} status=(ok|new|version-bumped)`
- **Risk**: low

### INV-016: /cauto Auto Run Report surfaces harness warnings in "What to Review First"
- **Type**: must
- **Category**: functional
- **Statement**: When a fingerprint warning was emitted during a `/cauto` run, the resulting Auto Run Report (ABS-013) at `.correctless/artifacts/auto-report-{slug}.md` includes the warning text in its "What to Review First" section.
- **Boundary**: ABS-013, ABS-027
- **Test approach**: integration — synthesize a /cauto run with a known fingerprint warning emission, assert the auto-report.md file's "What to Review First" section contains the warning
- **Risk**: low

### INV-017: harness-fingerprint.sh conforms to PAT-003 phase-transition script convention
- **Type**: must
- **Category**: functional
- **Statement**: `scripts/harness-fingerprint.sh` sources `lib.sh`, exits 0 on every code path (advisory — never blocks), produces structured stdout consumable by skills.
- **Boundary**: PAT-003
- **Test approach**: structural + integration — grep for `source.*lib\.sh`; trace all exit codes (assert all exit 0); assert stdout is parseable JSON or k=v lines
- **Risk**: low

### INV-018: Script CLI accepts explicit input flags for testability
- **Type**: must
- **Category**: functional
- **Statement**: `scripts/harness-fingerprint.sh` accepts `--session-id <id>` and `--meta-dir <path>` flags. When flags absent, defaults to live values (real session-id derivation via `get_current_session_id()`, real `.correctless/meta/`). Tests use the explicit flags to drive deterministic input. Designed standalone (ME-2 round-2 — the v1 reference to "workflow-advance.sh's testability flags" was a false precedent and is removed).
- **Sentinel value scheme (ME-8 round-2)**: tests pass `--session-id` values prefixed with `__test_session_` (e.g., `__test_session_001__`) so the script can verify the flag was actually honored vs. silently falling through to the live default. The script asserts that any value with the `__test_session_` prefix MUST come from the explicit flag (never from `get_current_session_id()`); a mismatch indicates flag-handling broke. Production session-ids never use this prefix.
- **Boundary**: ABS-027
- **Test approach**: unit — invoke with explicit flags using sentinel values, assert behavior reflects the sentinel; invoke without flags, assert live defaults applied; verify the sentinel-prefix assertion catches flag-handling regressions
- **Risk**: medium

### INV-019: Baseline file includes schema_version from creation
- **Type**: must
- **Category**: data-integrity
- **Statement**: First write of `.correctless/meta/model-baselines.json` includes a top-level `"schema_version": 1` field. BND-004's evolution mechanism reads this field on every load. Subsequent writes preserve the field.
- **Boundary**: ABS-027
- **Test approach (ME-7 round-2)**: explicit two-step test — (1) delete any existing baseline file, invoke `--capture-baseline`, assert schema_version=1 is present; (2) invoke `--capture-baseline` again on the now-existing file, assert schema_version is preserved (still 1, not removed or modified).
- **Risk**: low

## Prohibitions

### PRH-001: Must not block /cspec on fingerprint check failure
- **Statement**: No code path in the harness fingerprint mechanism may cause `/cspec` to halt, error out, or refuse to proceed. The mechanism is strictly advisory.
- **Detection**: Grep `scripts/harness-fingerprint.sh` for any `exit 1`, `exit 2`, or non-zero exit on a non-syntax-error code path. Grep `skills/cspec/SKILL.md` Step 0 for any conditional that aborts based on fingerprint check return value.
- **Consequence**: A bug in the fingerprint mechanism could brick the entire workflow's spec phase. Fail-open posture is mandatory.

### PRH-002: Must not write fingerprint or baseline files outside sanctioned writers — STRUCTURAL enforcement
- **Statement**: `.correctless/meta/harness-fingerprint.json` is written exclusively by `scripts/harness-fingerprint.sh`. `.correctless/meta/model-baselines.json` is written exclusively by `/cmodelupgrade`. Enforcement is **structural**, not advisory: `hooks/sensitive-file-guard.sh` blocks Edit/Write **AND** Bash redirects (using `lib.sh`'s `_has_write_pattern` detection) for both meta files. Direct mitigation of HI-2 / AP-022 (dead-code-in-security-paths) — the protection must be structurally present, not just textually claimed.
- **Detection (ME-6 round-2)**: structural test in `tests/test-sensitive-file-guard.sh` covering Bash-redirect blocking for both meta paths. Test design: feed `sensitive-file-guard.sh` a synthetic PreToolUse JSON for `Bash` tool with `command = "echo X > .correctless/meta/harness-fingerprint.json"` and assert exit 2 (blocked); repeat for several redirect forms (`>>`, `tee`, `cat <<EOF >`); reuse the test patterns already present in `tests/test-sensitive-file-guard.sh` for existing protected paths. Cross-check `allowed-tools` in all SKILL.md files for `Write(.correctless/meta/model-baselines.json)` (must appear only in `/cmodelupgrade`); ditto for fingerprint file (must appear nowhere).
- **Sensitive-file-guard fail-mode confirmation (ME-13 round-2)**: sensitive-file-guard is PreToolUse and fail-closed per PAT-001 — if jq is missing or stdin is malformed, it exits 2 (blocks). This is the safe direction for this protection — a broken guard fails toward "no writes allowed" rather than "all writes allowed."
- **Consequence**: Unenforced sole-writer claim is exactly the AP-022 antipattern.

### PRH-003: Must not auto-apply /cmodelupgrade recommendations
- **Statement**: `/cmodelupgrade` produces a regression report. The report does NOT auto-trigger any migration, agent file change, or skill modification. All actions following the report require explicit human invocation of follow-up skills.
- **Detection**: Grep `skills/cmodelupgrade/SKILL.md` for invocations of Edit, Write (outside the baseline file), or Task spawning — must find none beyond report generation. Grep for "auto-apply", "automatically", "trigger" in action contexts — manual review.
- **Consequence**: Auto-application would violate TB-004 (LLM orchestrator autonomy boundary).

### PRH-004: No verbatim system-prompt content in either meta file
- **Statement**: Neither meta file may contain raw system-prompt text. Only hashes, integers, model identifiers, and aggregate metrics. Simplified from v1 (no probe response to potentially leak), but still relevant — the baseline file must contain only numeric and structural fields.
- **Detection**: Inspect schemas — fingerprint file fields are `{fingerprint, harness_version, model, timestamp}`; baseline file fields are `{schema_version, baselines: {key: {metrics: {feature_slug: {qa_rounds, total_tokens, total_cost_usd, phase_count}}, sample_size, captured_at}}}`. No prose fields anywhere.
- **Consequence**: Data minimization; small information-leak surface if files are ever shared.

### PRH-005: Must not spam notifications
- **Statement**: At most one notification per session for a given fingerprint mismatch. The session-flag file mechanism (INV-003) is the gate; bypassing it is prohibited.
- **Detection**: Grep `scripts/harness-fingerprint.sh` for emission paths — must check flag-file existence first. Grep `skills/cspec/SKILL.md` Step 0 for direct notification emission outside the script call.
- **Consequence**: Per-invocation notifications would train users to ignore the warning.

### PRH-006: HARNESS_VERSION constant cannot be bumped autonomously by an agent
- **Statement**: The `HARNESS_VERSION` integer in `scripts/harness-fingerprint.sh` is bumped only via human commit. `hooks/sensitive-file-guard.sh` protects `scripts/harness-fingerprint.sh` from autonomous Edit/Write **once the file exists in git** (i.e., after the initial implementation commit lands). During `/ctdd` GREEN on this very feature, the file does NOT yet exist in git — the implementation agent must be able to create it. Protection activates after first commit. This is the same lifecycle as any other shipped script: write it once during the feature's TDD cycle, then it's protected. CR-1 round-2 disposition: scoping fix to avoid bricking implementation.
- **Detection**: structural test asserting `scripts/harness-fingerprint.sh` is in `sensitive-file-guard.sh`'s protected paths; **enforcement uses CODEOWNERS** (per LO-4 round-2 disposition — no new CI label infrastructure needed) so that PRs touching the script require maintainer review; the "block autonomous edits to existing tracked files" check is what sensitive-file-guard provides at runtime
- **Consequence**: Without this, an agent that wanted to suppress harness-change detection could just bump the constant and pretend it had been bumped legitimately. Lifecycle scoping prevents the over-protection that would block the implementation agent from creating the script in the first place.

## Boundary Conditions

### BND-001: HARNESS_VERSION mismatch (current vs. stored)
- **Boundary**: ABS-027
- **Input from**: existing `.correctless/meta/harness-fingerprint.json` written under an older HARNESS_VERSION
- **Validation required**: compare stored `harness_version` field against current script constant; if mismatch, status = `version_bumped`
- **Failure mode**: emit notification (this is the intended detection signal)
- **Why this matters**: this IS the detection mechanism; the prior spec's `harness_changed` vs. `substring_list_changed` distinction collapses into one path now

### BND-002: Concurrent /cspec invocations on same project (covers TOCTOU on flag file too)
- **Boundary**: ABS-027 + ABS-003 (state file locking)
- **Input from**: two simultaneous /cspec runs (rare — same project, two terminals)
- **Validation required**: writes to `.correctless/meta/harness-fingerprint.json` use `lib.sh`'s locking mechanism. **ME-4 round-2**: verify during /ctdd whether existing `locked_update_state` works for arbitrary file paths or whether a generic `locked_update_file` helper needs to be added to `lib.sh`. Reads are not locked (point-in-time snapshots are acceptable).
- **TOCTOU on session flag file (LO-3 round-2)**: the per-session notification flag file (`harness-notified-{session-id}.flag`) is also subject to a race between two same-session /cspec invocations both checking flag-file existence before either writes. Mitigation: use the same locking mechanism for the flag write, OR (cheaper) accept the race — both invocations would emit one notification each (over-notification), which is the safe failure direction per BND-003's principle.
- **Failure mode**: fail-closed write on the fingerprint file (lock-acquire timeout → skip write, log warning); fail-open accept on the flag file (race → at most 2 notifications instead of 1, acceptable)
- **Why this matters**: concurrent writes without locking would corrupt the fingerprint store

### BND-003: Session-id derivation falls back when /proc unavailable
- **Boundary**: ABS-027
- **Input from**: `get_current_session_id()` in `lib.sh` reading `/proc/{pid}/stat` for boot time
- **Validation required (ME-3 round-2)**: cross-platform implementation uses `ps -o lstart= -p $$` as the canonical mechanism (works on Linux, macOS, BSD). The `/proc/{pid}/stat` Linux-specific path is one valid implementation; tests must verify the function works on macOS too. If `ps` is unavailable, fall back to a process-start timestamp captured at first invocation in this process (stored in `.correctless/artifacts/process-start-{pid}.flag` with PID-mtime check); if that fails, fall back to PID alone with a one-line warning.
- **Failure mode**: fail-open emit — when in doubt, notify (over-warning is annoying; under-warning is the real risk)
- **Why this matters**: a broken session-id mechanism that fails-silent would suppress all warnings indefinitely

### BND-004: Baseline file schema evolution
- **Boundary**: ABS-027
- **Input from**: `.correctless/meta/model-baselines.json` written by older Correctless version
- **Validation required**: every read validates `schema_version` field; mismatch triggers a one-line warning + treats baseline as missing (user is prompted to capture a new baseline)
- **Failure mode**: fail-open + prompt re-capture
- **Why this matters**: schema evolution is inevitable

### BND-005: Three-tier bootstrap lookup (exact-match pool / pre-fingerprint pool / no-baseline)
- **Boundary**: ABS-027
- **Input from**: existing `intensity-calibration.json` entries (mix of pre-fingerprint and post-fingerprint) + cost artifacts
- **Validation required (CR-2 round-2 disposition)**: bootstrap aggregation uses an explicit three-tier lookup:
  1. **Exact-match pool**: calibration entries where `harness_version` field is present AND equals the current `HARNESS_VERSION` constant
  2. **Pre-fingerprint pool**: calibration entries where `harness_version` field is absent (entries written before `/cverify` was extended to record the field)
  3. **No-baseline mode**: neither pool has any entries
- **Resolution priority**: when both pools exist, prefer the exact-match pool (more accurate). When only the pre-fingerprint pool exists, use it with the explicit `"pre-fingerprint baseline"` label in the report (CR-3 from round 1). When neither pool exists, emit the no-baseline message per INV-009b. Do NOT mix pools — that would produce misleading averages.
- **Implication for /cverify**: this BND requires that `/cverify` be extended to write the `harness_version` field on every calibration entry it creates going forward. Without that extension, the post-fingerprint pool stays empty forever and the spec's bootstrap-vs-controlled distinction collapses. **Add to Prerequisites**: `/cverify` SKILL.md must be extended to read `HARNESS_VERSION` from the script and include it in every new calibration entry. Existing entries are NOT backfilled (LO-5 round-2 — they stay tagless permanently in the pre-fingerprint pool, which is acceptable).
- **Failure mode**: fail-open present
- **Why this matters**: without the three-tier distinction, the "pre-fingerprint" and "current-version" entries would be indistinguishable, and BND-005 would silently average across pools that shouldn't be combined

## Environment Assumptions

### EA-001: jq is available
- **Assumption**: `jq` is installed on the developer's machine
- **Refs**: ENV-001 (existing — Correctless requires jq throughout)
- **Consequence if wrong**: script falls back to a coarse "fingerprint not computable" status — does not block, logs warning

### EA-002: ~/.claude/projects/ readable (only for cost artifacts and model_name)
- **Assumption**: `~/.claude/projects/<encoded-name>/` is readable by the user
- **Refs**: ENV-007 (existing — token-tracking and `compute-session-cost.sh` depend on this)
- **Scope clarification (ME-1 round-2)**: this assumption is load-bearing only for (a) reading session JSONLs in `compute-session-cost.sh` to produce cost artifacts, and (b) reading model name from session metadata if that's the chosen `model_name` source per CR-3 / pinned during /ctdd. The fingerprint mechanism itself (INV-001..006, INV-018) does NOT depend on session-dir readability — it uses `/proc` or `ps -o lstart=` for session-id (BND-003), and reads model_name from whatever environment source /ctdd pins.
- **Consequence if wrong**: cost artifact reads produce no data → report shows zero cost rows; if model_name comes from session metadata, fingerprint becomes "unknown|{HARNESS_VERSION}" with a stderr warning

### EA-003: Harness changes propagate at session start
- **Assumption**: when Anthropic ships a harness update, all sessions started after the update see the new harness; sessions started before continue with the old harness until restart
- **Consequence if wrong**: mid-session harness change would not be detected. Documented as accepted limitation (Scope out-of-scope item).

### EA-005: model_name is sourced from the environment and is not tamper-resistant
- **Assumption**: `model_name` (the input to INV-001's literal fingerprint) is sourced from Claude Code's environment (env var, session JSONL metadata, or whatever Claude Code provides — pinned during /ctdd RED). The mechanism is not tamper-resistant — an autonomous agent with write access to the env or the session metadata could spoof its own model name.
- **Accepted limitation (CR-3 round-2 disposition)**: this is an advisory mechanism in a single-user dev tool. The threat model — an agent deliberately spoofing its own model name to suppress harness-change detection — requires a compromised agent that is both sophisticated enough to understand the fingerprint mechanism and motivated to evade it. At that point, fingerprint accuracy is the least of the user's concerns. The mitigation cost (finding a tamper-resistant model name source, which may not exist in Claude Code's current API) outweighs the risk for a single-user advisory feature.
- **Consequence if wrong**: a compromised agent could pretend it's still on the prior model+version and suppress the change detection. Detected via INV-014 human-validation step (the human reviews source feature slugs before saving baseline) and EA-004's >20% delta heuristic (a spoofed agent's behavior would still shift metrics within the spoofed key, eventually triggering a bump).
- **Revisit if**: the threat model changes — multi-user shared-config scenarios, marketplace plugin distribution, or any context where "compromised agent" becomes a realistic adversary class.

### EA-004: Maintainer responds to metric shifts by bumping HARNESS_VERSION
- **Assumption**: a human (the project maintainer or a contributor) responds to the signal `/cmodelupgrade` produces and increments the constant in a commit. The mechanism presumes this response is reliable and timely.
- **The circularity and how it breaks**: at first glance there's a chicken-and-egg problem — `/cmodelupgrade` compares against a baseline keyed by `{model}+{version}`, so if HARNESS_VERSION hasn't been bumped, the current runs match the existing baseline key and the report shows deltas against the same harness. That looks like the human needs to independently discover harness changes before the regression mechanism becomes useful. **It does not.** The escape route is OQ-006(a): `/cmodelupgrade` detects metric shifts WITHIN a single model+version key (consecutive runs at the same key showing >20% delta in any metric is itself the signal). The human's job is to respond to that signal — not to independently discover harness changes via gut feeling. The cycle is: metrics shift inside key K → /cmodelupgrade surfaces the shift → human bumps HARNESS_VERSION (new key K') → new baseline captured under K' → future comparisons within K' are clean until the next shift. The mechanism is reactive to its own observations, not dependent on external observation.
- **Why this still presumes human judgment**: the threshold (>20%) is a heuristic; the maintainer must judge whether a shift is harness-related vs. project-related (e.g., codebase growth, new test categories, intensity calibration noise). The spec doesn't replace human judgment — it concentrates it on a single, mechanically-surfaced decision point.
- **Consequence if wrong**: if the maintainer ignores the signal or routinely dismisses metric shifts as noise, harness regressions accumulate undetected. The 4.6→4.7 audit was triggered by exactly this kind of metric-shift-noticing pattern (3 distinct findings surfaced in one audit session), so the assumption is empirically grounded for at least the first known case. Worth revisiting after 6 months of production data — if maintainers routinely override the signal, the threshold needs tightening or the heuristic needs replacement.

## Open Questions

- **OQ-001**: ~~probe stability~~ → **REMOVED** (no probe in this revision)
- **OQ-002**: ~~probe substrings~~ → **REMOVED** (no probe in this revision)
- **OQ-003**: ~~standard test feature vs. recent runs~~ → **resolved** (bootstrap-first per /creview-spec CR-3)
- **OQ-004**: ~~/cmodelupgrade writes calibration?~~ → **resolved** (no — separation of concerns)
- **OQ-005**: ~~per-session vs. until-cmodelupgrade-runs notification scope~~ → **resolved** (per-session for simplicity)
- **OQ-006** (NEW): What heuristic triggers a HARNESS_VERSION bump? Initial guidance for the maintainer: bump when (a) `/cmodelupgrade` regression report shows >20% delta in any metric across consecutive same-model+version runs, OR (b) the maintainer notices a behavioral change manually (e.g., spec quality drops, QA round counts climb without explanation, a 4.7-style audit pattern surfaces). Refine the threshold during /ctdd based on the variance observed in the first few weeks of production data.
- **OQ-007** (NEW): What goes in `templates/test-features/baseline.md`? Should be a small reference feature that exercises the standard /cauto pipeline end-to-end — needs at least one TDD-able rule, one integration rule, one prohibition. Specific content TBD during /ctdd. Should be small enough to /cauto in <20 minutes.

## Prerequisites (allowed-tools cross-check per AP-008)

The following `allowed-tools` updates are required by this spec:

- **`skills/cspec/SKILL.md`**: add `Bash(*harness-fingerprint*)` to allowed-tools (script invocation in Step 0)
- **`skills/cmodelupgrade/SKILL.md`** (new file): allowed-tools must include `Read, Grep, Glob, Bash(jq*), Bash(*workflow-advance.sh*), Bash(*harness-fingerprint*), Write(.correctless/meta/model-baselines.json), Write(.correctless/artifacts/cmodelupgrade-*)`. Must NOT include `Write(.correctless/meta/harness-fingerprint.json)` per INV-007 or `Edit(scripts/harness-fingerprint.sh)` per PRH-006. The skill must include explicit path discovery via `workflow-advance.sh status` for every artifact it reads (INV-012). **The skill spawns NO subagents (ME-12 round-2)** — all work happens in the orchestrator's context. SKILL.md must include the explicit statement "This skill spawns no subagents — all aggregation, comparison, and report rendering happens inline." for clarity vs ABS-010 / AP-013.
- **`skills/cverify/SKILL.md`**: extend to read `HARNESS_VERSION` from `scripts/harness-fingerprint.sh` and include it in every new calibration entry written to `.correctless/meta/intensity-calibration.json` (CR-2 round-2 prerequisite — without this, BND-005's three-tier lookup collapses).
- **`skills/csetup/SKILL.md`**: add scaffolding step for `templates/test-features/baseline.md` → `.correctless/test-features/baseline.md` (idempotent)
- **`skills/cstatus/SKILL.md`**: no allowed-tools change needed; verify the `Harness:` line addition fits in the existing output structure
- **`skills/cauto/SKILL.md`**: ABS-013 Auto Run Report generation reads `.correctless/artifacts/harness-notified-*.flag` — Read access already present; no allowed-tools change
- **`hooks/sensitive-file-guard.sh`**: add `scripts/harness-fingerprint.sh`, `.correctless/meta/harness-fingerprint.json`, `.correctless/meta/model-baselines.json` to protected-paths list. The Bash-redirect detection (`_has_write_pattern` from lib.sh) must cover both meta files (PRH-002 / HI-2).
- **`scripts/lib.sh`**: extract `get_current_session_id()` as shared helper (HP-4)
- **`sync.sh`**: add `cmodelupgrade` to skill list; add `harness-fingerprint` to script list
- **`tests/test-allowed-tools-check.sh`**: verify covers `cmodelupgrade` SKILL.md (HP-3)
- **`tests/test-scripts-namespace-migration.sh`**: verify install-completeness covers `harness-fingerprint.sh` (HP-1 / AP-024)
- **`CONTRIBUTING.md`**: update "Adding a New Script" section if it has a checklist (HP-1)
- **New file**: `templates/test-features/baseline.md` (small reference feature for controlled-baseline mode)

## New Architectural Entry — ABS-027

This spec proposes adding **ABS-027: Harness fingerprint store contract** to `.correctless/ARCHITECTURE.md`:

> **What**: JSON file at `.correctless/meta/harness-fingerprint.json` recording the SHA-256 hash of `"{model_name}|{HARNESS_VERSION}"` plus `harness_version`, `model`, and `timestamp` fields. Companion file at `.correctless/meta/model-baselines.json` (with `schema_version: 1`) stores per-model+version baseline metrics for `/cmodelupgrade` regression comparison. Per-feature granularity (per-skill deferred until upstream producers exist). Session-id used in flag-file paths is produced by `get_current_session_id()` in `scripts/lib.sh` (single source of truth — no per-skill derivation drift permitted).
>
> **Invariant**: Sole writer of `harness-fingerprint.json` is `scripts/harness-fingerprint.sh`. Sole writer of `model-baselines.json` is `/cmodelupgrade`. Sole writer of `HARNESS_VERSION` constant is human commit (`scripts/harness-fingerprint.sh` is sensitive-file-guard protected). All consumers fail-open on missing/malformed files. The fingerprint check is advisory — never blocks any skill. Sole-writer enforcement is structural (sensitive-file-guard blocks Edit/Write AND Bash redirects), not advisory.
>
> **Enforced at**: `scripts/harness-fingerprint.sh`, `skills/cmodelupgrade/SKILL.md`, `skills/cspec/SKILL.md` (Step 0 invocation), `hooks/sensitive-file-guard.sh` (writer enforcement), `scripts/lib.sh` (session-id helper), `tests/test-harness-fingerprint.sh`
>
> **Violated when**: any skill or script other than the sanctioned writers writes to either meta file or to the script; an agent autonomously bumps HARNESS_VERSION; the check blocks /cspec; raw probe responses or system-prompt content stored verbatim; per-skill granularity is added without the upstream producer changes; session-id derivation duplicated outside `lib.sh`
>
> **Test**: `tests/test-harness-fingerprint.sh` covering INV-001..019, PRH-001..006, BND-001..005

---

## Restructure Summary

### Round 2 (post-/creview-spec round 2, 2026-04-26)

| Finding | Disposition | Spec impact |
|---|---|---|
| CR-1 (PRH-006 over-protection) | accept | PRH-006 lifecycle scoping — protection activates after first commit |
| CR-2 (BND-005 backfill gap) | accept | BND-005 rewritten as three-tier lookup; `/cverify` extension added to Prerequisites |
| CR-3 (model_name spoofing) | accept-the-risk | EA-005 added documenting the accepted limitation |
| HI-1 (drop hashing) | accept | INV-001/INV-008 use literal `"{model_name}|{HARNESS_VERSION}"` everywhere; no SHA-256 |
| HI-2 (cost field path) | accept | INV-009 pins glob pattern + structural test, /ctdd RED pins exact field path |
| HI-3 (exit codes) | accept | INV-009 documents 0/1/2 exit code contract |
| HI-4 (--auto-confirm flag) | accept | INV-014 specifies test-only flag with audit-trail entry |
| HI-5 (INV-007 grep test) | accept | INV-007 promoted to integration snapshot test, grep is belt-and-suspenders |
| HI-6 (baseline.md missing) | accept | /cmodelupgrade fail-open path falls back to bootstrap |
| HI-7 (schema migration) | defer | BND-004 unchanged; address when v2 schema is proposed |
| ME-1..ME-14 | mostly accept | scattered fixes throughout; ME-9 deferred (per HI-7) |
| LO-1..LO-5 | accept | LO-4 specifically: PRH-006 uses CODEOWNERS, not new CI label |

### Round 1 (post-/creview-spec round 1, 2026-04-26)

For traceability, the changes from v1:

**Removed (CR-2 cascade — drop LLM probe):**
- v1 INV-001 (probe stability across sessions)
- v1 INV-002 (probe captures substring changes)
- v1 INV-012 (probe failure fail-open)
- v1 INV-013 (probe instability fallback gate — critical-rated invariant in v1)
- v1 OQ-001 (probe stability empirical question)
- v1 OQ-002 (which substrings to probe)
- v1 ME-7 (Correctless-relevance vs. Anthropic-behavior gap)
- v1 ME-9 (negation spoofing on probe)
- v1 BND-001's `substring_list_changed` status (collapsed into single `version_bumped`)
- The proposed new TB (probe-response → script-input boundary)
- ~250 LOC of probe orchestration

**Added (CR fixes + HIGHs + HPs):**
- INV-009 rewritten per-feature using actual data sources (CR-1)
- INV-009b — no baseline → explicit message (HP-5 / DA-004 prevention)
- INV-012 — explicit path discovery in /cmodelupgrade (HI-7 / AP-025 / PMB-004)
- INV-013 — ABS-027 ARCHITECTURE.md drift test (ME-2)
- INV-014 — bootstrap requires ≥M=2 + human validation (HI-4 / RT-005)
- INV-015 — /cstatus advisory line (ME-4)
- INV-016 — /cauto Auto Run Report integration (ME-5)
- INV-017 — PAT-003 conformance (ME-6)
- INV-018 — explicit CLI flags for testability (HI-6)
- INV-019 — schema_version from creation (ME-3)
- BND-005 — bootstrap from pre-fingerprint runs (CR-3)
- PRH-002 — structural sole-writer enforcement, not just advisory (HI-2 / AP-022)
- PRH-006 — HARNESS_VERSION protected from autonomous bump
- EA-004 — explicit assumption that maintainer reliably bumps the constant
- OQ-006 — when to bump HARNESS_VERSION (heuristic)
- OQ-007 — what goes in `templates/test-features/baseline.md`
- HI-1 split: variance-as-test removed entirely (no probe), variance-as-empirical-gate also removed

**Deferred:**
- HI-3 (notification flag pre-touch attack) — low practical risk in single-user dev tool
- v1 INV-013's per-skill granularity — needs upstream audit-trail/token-tracking changes (CR-1)

Net: spec is shorter, lower-risk, fully unit-testable for the detection mechanism, and removes a trust boundary.
