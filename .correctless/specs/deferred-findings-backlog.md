# Spec: Deferred Findings Backlog

## Metadata
- **Created**: 2026-05-15T12:00:00Z
- **Status**: draft
- **Impacts**: creview-spec, creview, cauto, cstatus, cmetrics
- **Branch**: feature/deferred-findings-backlog
- **Research**: null
- **Recommended-intensity**: high
- **Intensity**: high
- **Intensity reason**: project floor (workflow.intensity=high); no security signals
- **Override**: none

## Context

Review skills (`/creview-spec`, `/creview`) identify non-blocking findings and present them to the user with disposition options. When the user selects "defer" or "accept risk," the finding is marked in the review artifact but nothing ever resurfaces it. Over 22 features, 47 non-blocking findings accumulated with status "pending" — invisible to `/cstatus`, `/cmetrics`, and the pipeline. This feature introduces a centralized backlog file, integrates it with review skills (writers), `/cauto` (sweep), `/cstatus` and `/cmetrics` (visibility), and a new `/ctriage` skill (bulk triage).

**Design decision: local-only.** The backlog file lives under `.correctless/meta/` which is gitignored — it is local-only and does not transfer across clones or machines. This is intentional: the backlog is advisory data derived from review artifacts (which ARE committed). The sync script (`scripts/sync-deferred-backlog.sh`) can reconstruct the backlog on any machine from committed artifacts. Team-shared backlog state is a v2 concern.

## Scope

**In scope:**
- Centralized deferred findings backlog file at `.correctless/meta/deferred-findings.json`
- Review skill integration: `/creview-spec` and `/creview` write deferred findings to the backlog after disposition
- `/cauto` backlog sweep step: before PR creation, surface in-scope deferred findings
- `/cstatus` integration: show backlog count + severity breakdown
- `/cmetrics` integration: show backlog trend, oldest item, severity distribution
- New `/ctriage` skill for bulk triage sprints
- Backlog seeding: script to import existing pending findings from review artifacts into the backlog

**Out of scope:**
- Automated fixing of deferred findings (human decides what to fix)
- QA findings or audit findings — only review-skill findings enter the backlog
- Changes to finding severity levels or review disposition options
- Gate enforcement — the backlog is visibility, not a blocker

## Complexity Budget
- **Estimated LOC**: ~400
- **Files touched**: ~16 (2 review skills + allowed-tools updates, cauto skill, cstatus skill, cmetrics skill, new ctriage skill, backlog sync script, tests, sync.sh + skill count update, AGENT_CONTEXT.md, CLAUDE.md, README.md, CONTRIBUTING.md, chelp/SKILL.md, setup, workflow-advance.sh help, docs)
- **New abstractions**: 1 (ABS-033: deferred findings backlog contract — multi-writer, advisory)
- **Trust boundaries touched**: 1 (TB-003: LLM-generated findings → agent context via /cauto sweep)
- **Risk surface delta**: low

## Invariants

### INV-001: Backlog file schema
- **Type**: must
- **Category**: data-integrity
- **Statement**: `.correctless/meta/deferred-findings.json` is a JSON file with schema `{"findings": [...], "schema_version": 1}`. Each finding entry has required fields: `id` (string, unique, zero-padded format `DF-001`, `DF-002`, ..., `DF-999`), `source_file` (string — path to originating review artifact), `finding_id` (string — original finding ID from review artifact, e.g. RS-004), `feature` (string — spec slug), `severity` (enum: MEDIUM, LOW, ADVISORY), `description` (string), `category` (string), `status` (enum: open, in-progress, resolved, wont-fix), `deferred_at` (ISO-8601 UTC timestamp), `resolved_at` (ISO-8601 UTC timestamp or null), `resolution` (string or null — rationale for wont-fix or description of fix). All timestamps use UTC (`date -u` convention per project standard).
- **Violated when**: A finding entry is missing a required field, uses an invalid severity or status value, or has a duplicate `id`
- **Enforcement**: CI test assertion (structural test validates schema on a fixture file + validates real file if present)
- **Guards against**: null
- **Test approach**: unit
- **Risk**: low

### INV-002a: Review skills reference backlog write path (structural)
- **Type**: must
- **Category**: functional
- **Boundary**: TB-003
- **Statement**: The `/creview-spec` SKILL.md and `/creview` SKILL.md each contain: (a) the literal path `.correctless/meta/deferred-findings.json`, (b) a `Write(.correctless/meta/deferred-findings.json)` entry in their `allowed-tools` frontmatter, and (c) the literal string `DF-` or equivalent ID-assignment instruction within 20 lines of the backlog path reference.
- **Violated when**: Either skill file is missing the backlog path reference, the Write() permission, or the ID-assignment instruction
- **Enforcement**: CI test assertion (structural grep for path, allowed-tools entry, and ID pattern)
- **Guards against**: AP-008 (spec specifies file writes without verifying allowed-tools)
- **Test approach**: unit
- **Risk**: low

### INV-002b: Review skills write deferred findings on defer (prompt-level)
- **Type**: must
- **Category**: functional
- **Boundary**: TB-003
- **Statement**: When a user selects "defer" disposition for a non-blocking finding in `/creview-spec` or `/creview`, the review skill appends the finding to `.correctless/meta/deferred-findings.json` with status `open` and the current UTC timestamp. The `id` field is auto-assigned as the next zero-padded `DF-{NNN}` by incrementing the highest existing ID. This invariant is prompt-level — the structural backstop is the sync script (INV-009) which can re-derive the backlog from review artifacts at any time.
- **Violated when**: A user defers a finding and it is not written to the backlog file
- **Enforcement**: prompt-level (review skill instructions — no structural enforcement available for LLM disposition handling). Mitigated by `scripts/sync-deferred-backlog.sh` as ongoing re-derivation backstop (see INV-009).
- **Test approach**: manual verification during dogfood runs
- **Risk**: medium

### INV-003: Backlog file creation on first write
- **Type**: must
- **Category**: functional
- **Statement**: If `.correctless/meta/deferred-findings.json` does not exist when a writer (review skill, `/ctriage`, or sync script) attempts to write a deferred finding, the writer creates the `.correctless/meta/` directory if needed (`mkdir -p`) and then creates the file with the initial schema (`{"findings": [], "schema_version": 1}`) before appending.
- **Violated when**: A write attempt fails because the file or directory doesn't exist, or the file is created without the schema wrapper
- **Enforcement**: CI test assertion (for sync script and ctriage); prompt-level for review skills
- **Test approach**: unit (test sync script against a directory with no existing backlog file or meta directory)
- **Risk**: low

### INV-004: /cauto backlog sweep
- **Type**: must
- **Category**: functional
- **Boundary**: TB-003
- **Statement**: `/cauto` includes a backlog sweep as an internal orchestration action (not a canonical pipeline step — excluded from the ABS-031 step enum) between `/cdocs` and consolidation. The sweep reads `.correctless/meta/deferred-findings.json` and presents ALL findings with status `open` to the user (in autonomous mode: log as advisory in pipeline summary, do not block). No relevance filtering — all open findings are shown; the user skips irrelevant ones. If the backlog file does not exist, the sweep is a no-op. Sweep failure is non-blocking — if it fails, consolidation proceeds.
- **Violated when**: The sweep step is missing from the pipeline, or open findings exist but are not surfaced
- **Enforcement**: CI test assertion (structural test that cauto SKILL.md references backlog sweep between cdocs and consolidation)
- **Test approach**: unit
- **Risk**: low

### INV-005: /cstatus backlog visibility
- **Type**: must
- **Category**: functional
- **Boundary**: TB-003
- **Statement**: `/cstatus` reads `.correctless/meta/deferred-findings.json` (if it exists) and displays: total open findings count, severity breakdown (MEDIUM/LOW/ADVISORY counts), and a threshold warning when open findings exceed 20. When the file does not exist or has zero open findings, `/cstatus` omits the backlog section entirely (dormant per PAT-019 — no "0 findings" noise). Additionally, if review artifacts contain "pending" findings not present in the backlog, `/cstatus` suggests running `scripts/sync-deferred-backlog.sh` to re-sync (drift detection for INV-002b).
- **Violated when**: The backlog section appears with zero findings, or the threshold warning is missing when open findings exceed 20
- **Enforcement**: CI test assertion (structural test that cstatus SKILL.md references deferred-findings.json, the threshold, and the sync suggestion)
- **Test approach**: unit
- **Risk**: low

### INV-006: /cstatus threshold suggestion
- **Type**: must
- **Category**: functional
- **Statement**: When `/cstatus` detects more than 20 open deferred findings, it appends: "Consider running `/ctriage` to review the deferred findings backlog." The threshold value (20) is a constant in the `/cstatus` SKILL.md, not configurable. Calibration rationale: the threshold is intentionally aggressive to drive early triage adoption. With 47 existing findings, the warning fires immediately after seeding — this is expected and desired. The alternative (higher threshold that delays the warning) risks normalizing backlog growth before the triage habit forms.
- **Violated when**: The suggestion is missing when open findings exceed 20, or appears when findings are <= 20
- **Enforcement**: CI test assertion
- **Test approach**: unit
- **Risk**: low

### INV-007: /cmetrics backlog trend
- **Type**: must
- **Category**: functional
- **Statement**: `/cmetrics` reads `.correctless/meta/deferred-findings.json` and displays: total open count, severity breakdown, oldest open finding (date and feature), count resolved in the last 30 days, and count added in the last 30 days. All date comparisons use UTC timestamps (ISO-8601). When the file does not exist, `/cmetrics` shows "No deferred findings data." The 30-day trend computation is prompt-level (performed by the LLM agent reading the JSON), not a script — acceptable for advisory data. If portability becomes a concern (jq date arithmetic across GNU/BSD), extract to `scripts/backlog-metrics.sh` in a future iteration.
- **Violated when**: Metrics are displayed without the backlog file, or the trend data (added/resolved in 30 days) is missing
- **Enforcement**: CI test assertion
- **Test approach**: unit
- **Risk**: low

### INV-008: /ctriage skill structure
- **Type**: must
- **Category**: functional
- **Statement**: A new skill `/ctriage` exists at `skills/ctriage/SKILL.md` with frontmatter including `allowed-tools` (must include `Read(.correctless/meta/deferred-findings.json)` and `Write(.correctless/meta/deferred-findings.json)`). The skill reads `.correctless/meta/deferred-findings.json`, presents open findings one at a time with a progress counter ("Finding N of M"), wizard-style per user preference (not report dump), and for each finding offers disposition options: (1) Fix now — skill updates status to `in-progress` (user fixes it in the current session; status changes to `resolved` only when user confirms the fix is applied), (2) Keep open — no change, (3) Won't fix — skill updates status to `wont-fix` with user-provided rationale, (4) Re-prioritize — change severity. The skill writes the updated backlog file incrementally after each disposition (not batch at end — if the session is interrupted at finding 25 of 30, the first 24 decisions are preserved). The skill must NOT use `context: fork` (AP-027 — wizard-style is inherently multi-turn).
- **Violated when**: The skill does not exist, does not present findings one at a time, does not show progress counter, does not offer all four disposition options, uses `context: fork`, or writes only at end (batch)
- **Enforcement**: CI test assertion (structural test for skill existence, wizard-style keywords, progress counter, disposition options, no context:fork, incremental write instruction)
- **Test approach**: unit
- **Risk**: low

### INV-009: Backlog sync script
- **Type**: must
- **Category**: functional
- **Statement**: A script at `scripts/sync-deferred-backlog.sh` reads all existing `review-spec-findings-*.md` and `review-findings-*.md` files from `.correctless/artifacts/` (and `review-findings-*.md` from `.correctless/artifacts/reviews/`), extracts findings with status "pending" (case-insensitive grep), and writes them to `.correctless/meta/deferred-findings.json` with auto-assigned `DF-{NNN}` IDs. The script serves dual purpose: initial seed (import existing backlog) and ongoing re-sync (structural backstop for INV-002b prompt-level write drift per AP-026/PMB-005 precedent). The script is idempotent — running it twice does not create duplicate entries (dedup by `source_file` + `finding_id` pair). The script outputs the count of findings imported/synced. Severity mapping: BLOCKING→skip (must be fixed in review), HIGH→skip, NON-BLOCKING→MEDIUM, MEDIUM→MEDIUM, LOW→LOW, INFORMATIONAL→ADVISORY, unknown→MEDIUM (with warning to stderr). Finding ID extraction: first `{LETTERS}-{NNN}` pattern match in the finding heading, else `Finding-N` ordinal based on position in the artifact.
- **Violated when**: The script creates duplicate entries on re-run, misses findings from either artifact pattern, fails to assign unique IDs, or maps HIGH/BLOCKING severity to the backlog (violates PRH-003)
- **Enforcement**: CI test assertion
- **Test approach**: unit
- **Risk**: low

### INV-010: Won't-fix items persist with rationale
- **Type**: must
- **Category**: data-integrity
- **Statement**: When a finding's status is changed to `wont-fix`, the `resolution` field must be non-empty (contains the human's rationale) and `resolved_at` must be set to the current timestamp. Won't-fix items remain in the backlog file permanently — they are never deleted.
- **Violated when**: A wont-fix finding has an empty resolution field, or wont-fix items are removed from the file
- **Enforcement**: CI test assertion (schema validation test)
- **Test approach**: unit
- **Risk**: low

### INV-012: Backlog file in allowed-tools for all writers
- **Type**: must
- **Category**: functional
- **Boundary**: TB-003
- **Statement**: The `allowed-tools` frontmatter of `/creview-spec` SKILL.md, `/creview` SKILL.md, and `/ctriage` SKILL.md must each include `Write(.correctless/meta/deferred-findings.json)`. `/ctriage` must additionally include `Read(.correctless/meta/deferred-findings.json)`. Without these entries, the skills cannot write to the backlog file — the feature is dead on arrival (RS-001/AP-008).
- **Violated when**: Any of the three skill files is missing the required Write() entry, or `/ctriage` is missing the Read() entry
- **Enforcement**: CI test assertion (structural grep of allowed-tools frontmatter in each SKILL.md)
- **Guards against**: AP-008 (spec specifies file writes without verifying allowed-tools)
- **Test approach**: unit
- **Risk**: low

### INV-011: Distribution sync
- **Type**: must
- **Category**: parity
- **Statement**: The new `/ctriage` skill at `skills/ctriage/SKILL.md` and the sync script at `scripts/sync-deferred-backlog.sh` are synced to `correctless/skills/ctriage/SKILL.md` and `correctless/scripts/sync-deferred-backlog.sh` via `sync.sh`. The `sync.sh` script includes the new skill directory and script file in its propagation list.
- **Violated when**: Source and distribution copies diverge, or sync.sh does not include the new paths
- **Enforcement**: CI test assertion (sync.sh --check)
- **Test approach**: unit
- **Risk**: low

## Prohibitions

### PRH-001: No gate enforcement
- **Statement**: The deferred findings backlog must never block any pipeline phase transition. No `workflow-advance.sh` command may check the backlog as a precondition. The backlog is purely advisory — visibility, not enforcement.
- **Detection**: grep workflow-advance.sh for "deferred-findings" (must find none)
- **Consequence**: Pipeline would stall on accumulated low-severity items, creating the same "override as routine" problem (AP-023)

### PRH-002: No deletion of won't-fix items
- **Statement**: Won't-fix findings must never be removed from the backlog file. The resolution rationale is the audit trail.
- **Detection**: Schema validation test asserts wont-fix items have non-empty resolution and are retained across seed/triage runs
- **Consequence**: Loss of decision history — the same finding gets re-raised in future reviews without context on why it was rejected

### PRH-003: No HIGH/CRITICAL findings in backlog
- **Statement**: The backlog only accepts MEDIUM, LOW, and ADVISORY severity findings. HIGH and CRITICAL findings must be fixed during the review that identified them — they cannot be deferred.
- **Detection**: Schema validation test rejects entries with severity HIGH or CRITICAL
- **Consequence**: Dangerous findings silently accumulate in a low-priority backlog instead of being fixed immediately

## Boundary Conditions

### BND-001: Empty backlog file
- **Input from**: Review skill attempting first deferred write
- **Validation required**: File doesn't exist — create with schema wrapper before appending
- **Failure mode**: Fail-closed — if file creation fails, the finding is still in the review artifact (AP-029 persist-before-present ensures this)

### BND-002: Malformed backlog file
- **Input from**: Any consumer reading the backlog
- **Validation required**: `jq -e '.findings | type == "array"' deferred-findings.json` — if parse fails or `.findings` is not an array, treat as empty. Writers additionally validate that existing entries conform to INV-001 schema (required fields present, severity in MEDIUM/LOW/ADVISORY per PRH-003) before appending — a malformed file with HIGH/CRITICAL entries is treated as corrupt.
- **Failure mode**: Fail-open for consumers (cstatus, cmetrics, cauto sweep) — degrade to "no backlog data". Fail-closed for writers (review skills, ctriage) — refuse to write to a corrupt file, warn user

### BND-003: Concurrent backlog writes
- **Input from**: Two review skills or ctriage running simultaneously (unlikely but possible)
- **Validation required**: None — advisory data, not safety-critical. Last-write-wins is acceptable for severity level.
- **Failure mode**: Fail-open — concurrent writes may lose one entry, but the finding still exists in the review artifact as the source of truth

## Open Questions

- ~~**OQ-001**: Should the backlog file be under sensitive-file-guard protection?~~ **Resolved**: No — the backlog is advisory data, not security-critical. Multiple skills write to it (review skills, ctriage). SFG protection would require adding exceptions for each writer, adding complexity for no security benefit. The review artifacts remain the source of truth.

## Won't Do

- **Automated fixing of backlog items** — the backlog is visibility infrastructure, not an auto-fix pipeline
- **Blocking pipeline on backlog size** — PRH-001 explicitly prohibits this
- **QA/audit findings in the backlog** — scope is review-skill findings only; QA and audit have their own persistence contracts (ABS-029)
- **Configurable threshold** — the 20-item threshold in `/cstatus` is a constant, not user-configurable; over-configuration for advisory features is waste
- **Backlog item linking to PRs** — tracking which PR fixed a finding adds schema complexity for minimal value in v1
- **Dashboard integration** — `/cdashboard` does not display backlog data in v1; `/cstatus` and `/cmetrics` provide the visibility; dashboard integration deferred to v2 when the dashboard's data-source architecture is more stable
- **Schema version migration** — `schema_version: 1` has no migration path; accepted as future concern per project convention (same as all other `.correctless/meta/` JSON files)

## Risks

- **Backlog write drift** — review skills are prompt-instructed to write deferred findings; if the instruction fades under context pressure, findings won't reach the backlog. Mitigation: the review artifact (AP-029) is the source of truth; the seed script can always re-derive the backlog from review artifacts.
- **Backlog file growth** — with 47 existing items and ~2-5 added per feature, the file stays small for years. No cap needed in v1.
- **Stale resolved items** — won't-fix and resolved items accumulate forever. Mitigation: consumers filter by status=open; closed items are inert JSON weight. If the file exceeds 500 entries, a future feature can add archival.
