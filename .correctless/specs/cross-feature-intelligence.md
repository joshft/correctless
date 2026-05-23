# Spec: Cross-Feature Intelligence Layer

## Metadata
- **Created**: 2026-05-22T16:30:00Z
- **Status**: approved
- **Impacts**: cspec-agent-migration, deferred-findings-backlog, review-driven-mini-audit-lenses
- **Branch**: feature/cross-feature-intelligence
- **Research**: null
- **Recommended-intensity**: high
- **Intensity**: high
- **Intensity reason**: touches skills/cspec/SKILL.md (core workflow skill), new script in scripts/, new cross-skill artifact contract
- **Override**: none

## Context

The Correctless pipeline generates rich data about what went wrong, what was deferred, what needed overrides, and what recurring concerns surface — but each `/cspec` run starts from a near-blank slate. `/cspec` reads antipatterns, drift debt, qa-findings, and calibration data, but ignores 6 other data sources that accumulate across features: deferred review findings, Devil's Advocate recurring themes, override patterns, recurring lens recommendations, debug root-cause clusters, and phase effectiveness history. This feature adds an aggregation script that synthesizes these sources into a single cross-feature intelligence brief, filtered by file-scope overlap with the current feature and recency-weighted. `/cspec` reads this brief during Step 0 (Socratic brainstorm) to inform — not constrain — its questioning.

## Scope

**In scope:**
- Aggregation script (`scripts/cross-feature-intel.sh`) that reads 6 data sources and produces a JSON brief
- `/cspec` Step 0 modification to read and present the brief during brainstorm
- File-scope filtering: only surface intelligence relevant to the current feature's affected files
- Recency weighting: newer data ranks higher, stale data (>90 days) excluded
- Cap on brief size to prevent context flooding
- `/cstatus` visibility: show intelligence brief age and data source health

**Out of scope:**
- Modifying the 6 source data formats — consume them as-is
- Adding new data sources beyond the 6 identified
- Machine learning or statistical analysis — this is deterministic aggregation
- Changing `/creview`, `/creview-spec`, `/ctdd`, or `/caudit` to write differently
- Feeding intelligence into skills other than `/cspec` (v2 concern — DEFER-001)

## Complexity Budget
- **Estimated LOC**: ~450 (script ~200, cspec prompt ~50, tests ~400, docs ~30)
- **Files touched**: ~9 (scripts/cross-feature-intel.sh, skills/cspec/SKILL.md, skills/cstatus/SKILL.md, tests/test-cross-feature-intel.sh, sync.sh, setup, .correctless/ARCHITECTURE.md, .correctless/AGENT_CONTEXT.md, CONTRIBUTING.md)
- **New abstractions**: 1 (ABS-037: cross-feature intelligence brief)
- **Trust boundaries touched**: 1 (TB-003 — LLM-generated historical findings → spec agent context)
- **Risk surface delta**: low

## Abstractions

### ABS-037: Cross-feature intelligence brief (.correctless/meta/)
- **What**: JSON artifact at `.correctless/meta/cross-feature-intel.json` produced by `scripts/cross-feature-intel.sh`. Aggregates 6 data sources into a single brief filtered by file scope and recency. The script is the sole writer. Consumers: `/cspec` (reads during brainstorm, advisory only), `/cstatus` (reads brief metadata for health reporting). The artifact is project-level (not branch-scoped) and gitignored under `.correctless/meta/`. The script is idempotent — re-running produces the same output given the same inputs.
- **Invariant**: `scripts/cross-feature-intel.sh` is the sole writer. `/cspec` is read-only — it never writes, modifies, or deletes the brief. The brief is advisory — never gates any phase transition or blocks any skill. Consumers handle missing/malformed briefs via dormant degradation (PAT-019). SFG protection omitted: the brief is advisory and non-gating — corruption or tampering has no lasting effect because the brief can be regenerated from source artifacts at any time. The script itself is protected by the existing `scripts/*.sh` glob in SFG.
- **Enforced at**: `scripts/cross-feature-intel.sh` (writer), `skills/cspec/SKILL.md` (consumer), `skills/cstatus/SKILL.md` (consumer)
- **Violated when**: a skill other than the script writes to the brief; `/cspec` treats brief content as constraints rather than context; the brief gates a phase transition; a consumer errors when the brief is absent
- **Test**: `tests/test-cross-feature-intel.sh`
- **Guards against**: cross-feature amnesia — pipeline forgetting what prior runs discovered

## Invariants

### INV-001: Aggregation script reads 6 data sources
- **Type**: must
- **Category**: functional
- **Statement**: `scripts/cross-feature-intel.sh` must read and aggregate from exactly these 6 sources: (1) `.correctless/meta/deferred-findings.json` — open deferred review findings, (2) `.correctless/artifacts/devadv/report-*.md` — Devil's Advocate reports, (3) `.correctless/meta/overrides/*.json` — override history, (4) `.correctless/artifacts/lens-recommendations-*.json` — lens recommendation artifacts, (5) `.correctless/artifacts/debug-investigation-*.md` — debug investigations, (6) `.correctless/meta/workflow-effectiveness.json` — phase effectiveness history (which phases miss which bug categories). Each source is optional — missing sources produce an empty section in the output, not an error.
- **Violated when**: the script reads fewer than 6 source types, errors on a missing source, or reads from an undocumented source
- **Enforcement**: CI test assertion (grep script for all 6 source paths)
- **Test approach**: unit
- **Risk**: low

### INV-002: File-scope filtering
- **Type**: must
- **Category**: functional
- **Statement**: The script accepts a `--scope` argument with a comma-separated list of file paths (the current feature's affected files). File-scope filtering applies when source data includes file references — currently only debug investigations (INV-012) have file-scoped data. Other sources (deferred findings, devadv themes, overrides, lens recommendations, phase effectiveness) have empty `file_refs` and are included unconditionally as project-wide concerns. Entries without file references are included unconditionally. When `--scope` is omitted, all entries from all sources are included (unfiltered mode for `/cstatus`). The 30-entry cap (INV-004) is the primary bound on brief size. Overlap is defined as exact string equality between a `file_refs` entry and a scope entry after normalization (no glob matching, no directory containment).
- **Violated when**: an entry with file references that don't overlap with the scope appears in the filtered output, or an entry without file references is excluded
- **Enforcement**: CI test assertion + behavioral test (fixture with known scope, verify filtering)
- **Test approach**: unit
- **Risk**: medium

### INV-003: Recency weighting and staleness exclusion
- **Type**: must
- **Category**: data-integrity
- **Statement**: Entries older than 90 days (based on the entry's date field) are excluded from the brief. Remaining entries are sorted by recency within each section (newest first). The 90-day threshold is a constant in the script, not configurable. Date fields used: `deferred_at` for deferred findings, file modification date for devadv reports, `completed_at` for overrides, artifact mtime for lens recommendations, file mtime for debug investigations.
- **Violated when**: an entry older than 90 days appears in the brief, or entries are not sorted newest-first within sections
- **Enforcement**: CI test assertion (fixture with old dates, verify exclusion)
- **Test approach**: unit
- **Risk**: low

### INV-004: Brief size cap with per-section minimum
- **Type**: must
- **Category**: resource-lifecycle
- **Statement**: The output brief is capped at 30 entries total across all 6 sections. Selection: first, each non-empty section retains at least 1 entry (its most recent). Remaining cap slots are filled by global recency sort across all sections. This prevents the highest-signal source (phase effectiveness, INV-016) from being crowded out by a flood of entries from a single section. The count of excluded entries is reported as `truncated_count` in the output metadata. When `truncated_count > 0`, the `/cspec` presentation includes a one-line note: "Showing N of M entries (K older entries excluded by recency cap)."
- **Violated when**: the brief contains more than 30 entries, the truncation count is wrong, or a non-empty section has zero entries when the total exceeds the cap
- **Enforcement**: CI test assertion (fixture with >30 entries, verify cap and per-section minimum)
- **Test approach**: unit
- **Risk**: low

### INV-005: Output schema
- **Type**: must
- **Category**: data-integrity
- **Statement**: The script outputs JSON with this schema: `{"schema_version": 1, "generated_at": "YYYY-MM-DDTHH:MM:SSZ", "scope": [...], "truncated_count": N, "warnings": [...], "sections": {"deferred_findings": [...], "devadv_themes": [...], "override_patterns": [...], "lens_recommendations": [...], "debug_clusters": [...], "phase_effectiveness": [...]}}`. Each section entry has: `source` (filename), `date` (ISO), `summary` (string, max 200 chars), `file_refs` (array of file paths or empty), `severity` (string or null), `id` (string — DF-NNN, DA-NNN, override reason hash, lens name, debug slug, or phase name). Collapsed entries (overrides, lens recommendations, phase effectiveness) additionally have `count` (integer). Lens recommendations with `count >= 3` additionally have `"promotion_candidate": true`. Section arrays may be empty (`[]`). The `warnings` array contains strings for each malformed source file skipped (e.g., "skipped corrupted deferred-findings.json: invalid JSON"). The output is valid JSON — parse errors are a contract violation.
- **Violated when**: output is not valid JSON, a required field is missing, an entry summary exceeds 200 chars, or the schema_version is not 1
- **Enforcement**: CI test assertion (jq schema validation on fixture output)
- **Test approach**: unit
- **Risk**: low

### INV-006: /cspec reads brief after first brainstorm exchange
- **Type**: must
- **Category**: functional
- **Statement**: `/cspec` Step 0 (Socratic brainstorm) must invoke the aggregation script via `Bash()` after the first brainstorm exchange — once the user has described their feature and the scope is known. The script is invoked with the feature's likely file scope via `--scope` (derived from the user's feature description, git diff against base branch, or omitted for unfiltered mode if scope is unclear). The `Bash()` invocation must NOT use `2>/dev/null` — stderr warnings from malformed sources should be captured. If the script produces non-empty sections, present a "Cross-Feature Intelligence" summary showing: the number of entries per section, the 3-5 most recent entries (sorted by date descending), any warnings from malformed sources, and a one-line framing: "Prior workflow runs surfaced these concerns for files in this feature's scope. These inform the brainstorm — they are context, not constraints." If `truncated_count > 0`, add: "Showing N of M entries (K older entries excluded by recency cap)." If the script fails, is absent, or produces empty sections, skip silently (PAT-019 dormant). **Prerequisite**: `/cspec` allowed-tools must include `Bash(*cross-feature-intel*)` — without this pattern, the invocation is tool-blocked (AP-008).
- **Violated when**: `/cspec` errors on a script failure, treats brief content as rules rather than context, presents the brief before the user has described their feature, or the allowed-tools pattern is missing
- **Enforcement**: prompt-level (cspec is LLM-orchestrated). Structural backstop: grep cspec SKILL.md for `cross-feature-intel.sh` invocation and `--scope` argument (must find both). Grep cspec allowed-tools for `cross-feature-intel` pattern (must find one).
- **Test approach**: unit
- **Risk**: medium

### INV-007: Anti-anchoring directive with calibration
- **Type**: must
- **Category**: functional
- **Statement**: The `/cspec` brainstorm section must include an explicit directive: "The intelligence brief is advisory context from prior workflow runs. It may surface relevant concerns but must not anchor your analysis. Challenge its relevance to the current feature — a concern that recurred on 3 prior features may be irrelevant to this one. Fresh thinking about the current feature's unique risks takes priority over historical patterns. Weight intelligence highly when: the current feature touches the same files as a prior finding, the same concern appeared 3+ times, or the concern is security-related. Dismiss when: the current feature is in a different module, the concern is near the 90-day staleness boundary, or the concern is about a pattern the current feature doesn't use." This directive must appear before the brainstorm questions, not after. The calibration examples prevent agents from defaulting to blanket dismissal (same lesson as PMB-007/AP-028 — uncalibrated directives cause agents to default to lowest-friction interpretation).
- **Violated when**: the cspec SKILL.md does not contain the anti-anchoring directive or the calibration examples, or the directive is placed after the brainstorm questions
- **Enforcement**: CI test assertion (grep for directive text and calibration examples in cspec SKILL.md)
- **Test approach**: unit
- **Risk**: medium

### INV-008: Deferred findings extraction
- **Type**: must
- **Category**: functional
- **Statement**: For the deferred findings section, the script reads `.correctless/meta/deferred-findings.json` and extracts entries with `status: "open"`. Each entry maps to: `id` = the finding's `id` (DF-NNN), `date` = `deferred_at`, `summary` = `description` truncated to 200 chars, `file_refs` = empty (deferred findings lack file-scope data — `source_file` is the review artifact path, not the feature's source files; included unconditionally per INV-002, same as devadv and overrides), `severity` = the finding's `severity`. Entries with `status` other than `"open"` are excluded.
- **Violated when**: a resolved/wont-fix finding appears in the brief, or an open finding is excluded
- **Enforcement**: CI test assertion (fixture with mixed statuses)
- **Test approach**: unit
- **Risk**: low

### INV-009: Devil's Advocate theme extraction
- **Type**: must
- **Category**: functional
- **Statement**: For the devadv section, the script reads `.correctless/artifacts/devadv/report-*.md` and extracts headings matching `## DA-NNN:` (regex `^## DA-[0-9]+:`) as themes. Each entry maps to: `id` = DA-NNN, `date` = parsed from filename via regex `/report-(\d{4}-\d{2}-\d{2})\.md$/` (if no match, fall back to file mtime), `summary` = the heading text after the DA-NNN prefix truncated to 200 chars, `file_refs` = empty (devadv reports are project-wide — included unconditionally per INV-002), `severity` = parsed from EITHER `### Severity` subsection (bare word on next line) OR inline `**Severity:** value` format — handle both patterns, as existing reports use both formats (2026-04-05 uses inline bold, 2026-05-16 uses subsection). If neither pattern found, severity = null.
- **Violated when**: a DA-NNN heading is missed, or a non-DA heading is included
- **Enforcement**: CI test assertion (fixture with known DA entries)
- **Test approach**: unit
- **Risk**: low

### INV-010: Override pattern extraction
- **Type**: must
- **Category**: functional
- **Statement**: For the overrides section, the script reads `.correctless/meta/overrides/*.json` and extracts override entries. Each entry maps to: `id` = hash of the override `reason` (first 8 chars of sha256), `date` = `completed_at` from the metadata wrapper, `summary` = override `reason` truncated to 200 chars, `file_refs` = empty (overrides are workflow-level — included unconditionally per INV-002), `severity` = null. When multiple overrides across different runs share the same reason hash, they are collapsed into one entry with a `count` field showing recurrence.
- **Violated when**: duplicate reason hashes produce duplicate entries instead of collapsing, or `count` is wrong
- **Enforcement**: CI test assertion (fixture with repeated reasons)
- **Test approach**: unit
- **Risk**: low

### INV-011: Lens recommendation extraction
- **Type**: must
- **Category**: functional
- **Statement**: For the lens recommendations section, the script reads `.correctless/artifacts/lens-recommendations-*.json` and extracts entries from the `recommended_lenses` array. Each entry maps to: `id` = `lens_name`, `date` = artifact mtime, `summary` = `rationale` truncated to 200 chars, `file_refs` = empty (included unconditionally per INV-002), `severity` = null. When the same `lens_name` appears across multiple artifacts, they are collapsed into one entry with a `count` field. Lens names with `count >= 3` are flagged with `"promotion_candidate": true`.
- **Violated when**: duplicate lens names produce duplicate entries, or the count is wrong, or a lens with count >= 3 is not flagged
- **Enforcement**: CI test assertion (fixture with repeated lens names)
- **Test approach**: unit
- **Risk**: low

### INV-012: Debug investigation extraction
- **Type**: must
- **Category**: functional
- **Statement**: For the debug clusters section, the script reads `.correctless/artifacts/debug-investigation-*.md` and extracts: `id` = filename slug (e.g., `statusline` from `debug-investigation-statusline.md`), `date` = file mtime, `summary` = the text after `## Root Cause` heading truncated to 200 chars (or the first `## ` heading's content if no Root Cause section exists), `file_refs` = file paths extracted from lines under the `## Fix` or `## Class Fix` headings via regex `(scripts/[^ )]+|hooks/[^ )]+|skills/[^ )]+|tests/[^ )]+|\.correctless/[^ )]+)` — intentionally narrow to project-conventional path prefixes to avoid false positives from prose. Paths not matching this pattern are ignored. `severity` = null.
- **Violated when**: a debug investigation file is missed, or the root cause text is not extracted
- **Enforcement**: CI test assertion (fixture with known debug investigations)
- **Test approach**: unit
- **Risk**: low

### INV-016: Phase effectiveness extraction
- **Type**: must
- **Category**: functional
- **Statement**: For the phase effectiveness section, the script reads `.correctless/meta/workflow-effectiveness.json` and extracts entries from `post_merge_bugs`. Each entry maps to: `id` = `phase_that_should_have_caught` (the phase name — e.g., "spec", "audit"), `date` = the bug's `date` field, `summary` = `"{severity} bug missed by {phase_that_should_have_caught} phase: {description first 150 chars}"` truncated to 200 chars (fields `severity`, `description` from the real schema), `file_refs` = empty (effectiveness data is project-wide — included unconditionally per INV-002), `severity` = the bug's `severity` field. When multiple bugs share the same `phase_that_should_have_caught`, they are collapsed into one entry with a `count` field (e.g., "spec phase missed 3 bugs") and the `summary` lists the severity levels. This is the highest-signal source — it answers "what keeps going wrong in the same way" rather than "what went wrong." At least one test fixture must use a verbatim subset of the real `.correctless/meta/workflow-effectiveness.json` to guard against AP-031 field-name drift.
- **Violated when**: a post-merge bug entry is missed, or entries are not collapsed by phase
- **Enforcement**: CI test assertion (fixture with known effectiveness data)
- **Test approach**: unit
- **Risk**: low

### INV-013: Script is PAT-003 compliant
- **Type**: must
- **Category**: functional
- **Statement**: The script follows PAT-003 (phase-transition script conventions): lives in `scripts/`, accepts CLI arguments (not stdin JSON), outputs structured JSON to stdout, exits 0 always (informational), and sources `scripts/lib.sh` for shared utilities.
- **Violated when**: the script is placed in hooks/, reads stdin JSON, exits non-zero, or does not source lib.sh
- **Enforcement**: CI test assertion (file location, shebang, exit code, lib.sh sourcing)
- **Test approach**: unit
- **Risk**: low

### INV-014: /cstatus intelligence health
- **Type**: must
- **Category**: functional
- **Statement**: `/cstatus` must include a "Cross-Feature Intelligence" line with three states: (1) **No data**: when the brief doesn't exist AND no data sources have content, display "No cross-feature intelligence available yet — data accumulates as features complete review, audit, or debug phases." (2) **Stale**: when the brief exists but is older than 7 days, display brief age, entry count per section, and remediation: "will refresh on next /cspec run, or run: bash .correctless/scripts/cross-feature-intel.sh" (3) **Current**: when the brief exists and is <7 days old, display brief age and entry count per section. Dormant when the script itself doesn't exist (pre-upgrade projects).
- **Violated when**: `/cstatus` errors on a missing brief, shows a staleness warning on a fresh project with no pipeline history, or omits remediation on a stale brief
- **Enforcement**: prompt-level. Structural backstop: grep cstatus SKILL.md for `cross-feature-intel` reference and staleness threshold (must find both).
- **Test approach**: unit
- **Risk**: low

### INV-015: Setup installs the script
- **Type**: must
- **Category**: functional
- **Statement**: The `setup` script must install `scripts/cross-feature-intel.sh` to `.correctless/scripts/cross-feature-intel.sh` alongside other scripts. The glob-based installation (PAT-016) handles this automatically. The script must appear in the install manifest (ABS-022).
- **Violated when**: the script is not installed by setup, or is missing from the install manifest
- **Enforcement**: CI test assertion (existing glob-count test catches this automatically)
- **Test approach**: unit
- **Risk**: low

## Prohibitions

### PRH-001: Intelligence brief must not gate any phase transition
- **Statement**: The brief is advisory data. No `workflow-advance.sh` command, no hook, and no skill may check for the brief's existence or content as a precondition for any operation.
- **Detection**: grep `workflow-advance.sh` and `scripts/wf/*.sh` for `cross-feature-intel` references (must find none)
- **Consequence**: gating on the brief would break projects that haven't run the script or upgraded

### PRH-002: /cspec must not write to the brief
- **Statement**: `/cspec` is read-only for the intelligence brief. The script is the sole writer. If `/cspec` discovers something during brainstorm that should feed back, the mechanism is the existing pipeline (review artifacts, deferred findings, antipatterns).
- **Detection**: grep `/cspec` SKILL.md for write/append/create referencing cross-feature-intel (must find none)
- **Consequence**: /cspec writing to the brief would create a self-reinforcing feedback loop

### PRH-003: Brief content must not be interpolated into spec rules
- **Statement**: Intelligence entries are context for the brainstorm conversation, not text to copy into INV-xxx statements. The spec agent uses the brief to inform questioning, not to template invariants from historical data.
- **Detection**: prompt-level (anti-anchoring directive in INV-007)
- **Consequence**: pasting brief content into rules anchors the spec on historical patterns instead of the current feature's actual requirements

## Boundary Conditions

### BND-001: Zero data sources have content
- **Boundary**: PAT-019
- **Input from**: fresh project with no deferred findings, no devadv reports, no overrides, no lens recommendations, no debug investigations, no workflow effectiveness data
- **Validation required**: script outputs valid JSON with all 6 sections as empty arrays and `warnings` as empty array
- **Failure mode**: dormant — /cspec skips the intelligence presentation silently

### BND-002: All entries filtered out by scope
- **Boundary**: INV-002
- **Input from**: feature touching files that no prior data source references
- **Validation required**: script outputs valid JSON with all 6 sections as empty arrays (after filtering)
- **Failure mode**: dormant — same as BND-001

### BND-003: Malformed source files
- **Boundary**: data-integrity
- **Input from**: corrupted JSON, unparsable markdown
- **Validation required**: script skips malformed files, adds a warning string to the output `warnings` array (e.g., "skipped corrupted deferred-findings.json: invalid JSON"), and continues processing remaining sources. Warnings are included in the JSON output — not only stderr — so consumers can surface them.
- **Failure mode**: fail-open — skip the malformed source, include others

## STRIDE Analysis

### STRIDE for TB-003: LLM-generated historical findings → spec agent context

- **Spoofing**: A tampered brief could introduce false concerns. Mitigated by: the script derives from local artifacts; tampering requires filesystem access. However, the artifacts themselves contain LLM-generated text (deferred findings from review agents, lens recommendations from review agents, debug investigation summaries from debug agents) that was reviewed by a human and persisted — but could have been subtly wrong when originally written. The brief amplifies this by recycling it into future specs. PRH-003 (brief content must not be interpolated into spec rules) is the primary mitigation — the brief informs the brainstorm conversation but does not template spec invariants from historical agent output.
- **Tampering**: Brief could be modified between generation and /cspec read. Mitigated by: brief is advisory (PRH-001), anti-anchoring directive (INV-007), `generated_at` timestamp for freshness assessment.
- **Repudiation**: No concern — informational, not a decision record.
- **Information Disclosure**: Brief aggregates findings and override reasons. Mitigated by: gitignored under `.correctless/meta/`.
- **Denial of Service**: Large artifact volumes could slow the script. Mitigated by: 30-entry cap (INV-004) and 90-day exclusion (INV-003).
- **Elevation of Privilege**: Brief could contain prompt-injection from prior LLM findings. Mitigated by: anti-anchoring directive frames brief as "context, not instructions" (DD-004) — same TB-003 treatment as shift-left review.

## Environment Assumptions

- **EA-001**: `jq` is available — the script uses jq for JSON parsing. If jq is missing, the script outputs `{"error": "jq not found"}` and exits 0 (informational, not crash). `/cspec` treats this as dormant.
- **EA-002**: File mtimes are usable for recency — refs ENV-003 (filesystem mtime unreliability after git operations). For devadv reports and debug investigations that use mtime as date source, recency sort is approximate. Acceptable for advisory data.
- **EA-003**: Date arithmetic portability — the script requires converting ISO-8601 dates to epoch seconds for 90-day comparison. GNU `date -d` and BSD `date -jf` diverge. The script must use the existing GNU-first-BSD-fallback pattern from `scripts/auto-report.sh` and `scripts/budget-check.sh`. `stat` for mtime retrieval must also use the GNU/BSD fallback (`stat -c '%Y'` / `stat -f '%m'`). The project has no `lib.sh` date-parsing utility — the script handles the fallback internally.

## Design Decisions

### DD-001: Script over LLM aggregation
A deterministic bash script aggregates the data rather than having `/cspec` read raw sources. Rationale: scripts are testable, reproducible, and auditable.

### DD-002: Single brief file over per-source reads
One JSON file rather than 6 separate reads in `/cspec`. Rationale: one file read is one context injection. Six separate reads would be fragile (AP-025) and consume more prompt space.

### DD-003: 90-day staleness exclusion
Entries older than 90 days are excluded. Rationale: stale deferred findings are either irrelevant or accepted risks. The 30-entry cap provides a secondary bound.

### DD-004: Anti-anchoring directive over UNTRUSTED fence
The brief is framed with an anti-anchoring directive rather than an UNTRUSTED fence. The data originates from the project's own workflow, but much of it is LLM-generated (deferred findings from review agents, lens recommendations from review agents, debug summaries from debug agents) — it was reviewed by a human and persisted, but could have been subtly wrong when originally written. The risk is cognitive anchoring (the spec agent over-weighting historical patterns instead of thinking fresh), not prompt injection (the data doesn't instruct, it informs). The anti-anchoring directive addresses the actual risk; PRH-003 (brief content must not be interpolated into spec rules) prevents the amplification vector where a subtly wrong historical finding gets recycled into a new spec invariant.

**Asymmetry with TB-007 research brief**: Within the same `/cspec` SKILL.md, the TB-007 research brief uses `<UNTRUSTED_RESEARCH_BRIEF>` fences. The intelligence brief uses a prose directive instead. This is a conscious asymmetry: the research brief contains external untrusted content (web pages, package registries) with no prior human review. The intelligence brief contains internal project data that was human-reviewed at creation time (deferred findings were triaged by the user, devadv reports were read, overrides were supervisor-reviewed). The trust level is different: external-untrusted (fence) vs. internal-advisory (directive). This asymmetry should be documented in ARCHITECTURE.md TB-003 as a variant mitigation pattern.

### DD-005: /cspec invokes the script, not a hook
The script is invoked by `/cspec` at brainstorm start, not by a hook. Rationale: hooks run on every tool call; this should run once per `/cspec` invocation.

## Open Questions

- **OQ-001**: Should the script support `--regenerate` to force re-aggregation? Currently it always regenerates. Caching could help but adds complexity. Deferred — always-regenerate is simpler and should be fast (<1s).

## Deferred

- **DEFER-001**: Feed the intelligence brief into `/creview` and `/creview-spec` synthesis phases. The same data that informs spec writing could inform spec review. Extends the consumer set without changing the script. **Feedback loop risk**: if implemented, review agents read the brief (which contains deferred review findings) → generate new findings → some deferred → appear in next brief → review agents read again. The loop is slow (one cycle per feature) and bounded (30-entry cap, 90-day staleness), but a frequency dampener may be needed (e.g., an entry must appear in 3+ briefs before surfacing in review context).
- **DEFER-002**: ~~Add a 6th data source: `workflow-effectiveness.json`.~~ Promoted to v1 as INV-016. Phase effectiveness is the highest-signal, lowest-effort source — structured JSON, no markdown extraction, and it answers "what keeps going wrong" rather than "what went wrong once."
