# Spec: Review Intelligence Consumer

## Metadata
- **Created**: 2026-05-23T06:15:00Z
- **Status**: draft
- **Impacts**: cross-feature-intelligence, review-driven-mini-audit-lenses
- **Branch**: feature/review-intelligence-consumer
- **Research**: null
- **Recommended-intensity**: high
- **Intensity**: high
- **Intensity reason**: touches skills/creview-spec/SKILL.md and skills/creview/SKILL.md (core review workflow skills), extends TB-003 consumption pattern, feedback loop risk
- **Override**: none

## Context

The cross-feature intelligence brief (ABS-037) aggregates 6 data sources -- deferred findings, devadv themes, override patterns, lens recommendations, debug investigations, and phase effectiveness -- into a single JSON brief consumed by `/cspec` during brainstorm. Review skills (`/creview-spec`, `/creview`) already read 3 of these sources independently (qa-findings, audit-history, devadv reports) and classify them into ephemeral pattern classes during Historical Pattern Integration. This feature extends the review orchestrators to also read the intelligence brief during synthesis, giving them the aggregated view (including deferred findings, overrides, lens recommendations, and phase effectiveness that they currently don't see) while preserving the existing agent separation: adversarial agents still review the spec cold, only the orchestrator sees historical data. A 3-occurrence threshold dampener prevents the feedback loop where review-deferred findings re-enter the brief and amplify across runs.

## Scope

**In scope:**
- `/creview-spec` orchestrator reads the intelligence brief file during Historical Pattern Integration
- `/creview` orchestrator reads the intelligence brief file during Historical Pattern Findings
- 3-occurrence threshold: review orchestrators filter brief entries client-side, selecting only entries with `occurrences >= 3`
- Review skills read `.correctless/meta/cross-feature-intel.json` directly via `jq` — they do NOT invoke `scripts/cross-feature-intel.sh` (the script is invoked only by `/cspec`, which is the sole trigger for regeneration and occurrence tracking)
- `Bash(*cross-feature-intel*)` added to both review skills' allowed-tools (for jq-based file reading)
- `scripts/cross-feature-intel.sh` gains occurrence tracking and a `--min-occurrences N` stdout filter flag
- `scripts/cross-feature-intel.sh` uses `locked_update_file()` for the read-modify-write cycle on the brief file
- ABS-037 consumer list and TB-003 consumer list updated in ARCHITECTURE.md
- Tests verifying orchestrator integration and threshold behavior

**Out of scope:**
- Changing the 6 adversarial review agents -- they stay clean (no brief access)
- Changing the brief's data sources or output schema (ABS-037 v1 is stable)
- Feeding the brief into `/ctdd` QA or mini-audit agents
- Modifying the `/cspec` anti-anchoring directive (review skills get review-adapted calibration examples)

## Complexity Budget
- **Estimated LOC**: ~300 (script occurrence tracking + locking + dormant-counts ~120, skill prompt changes ~60, tests ~200, docs ~10)
- **Files touched**: ~7 (scripts/cross-feature-intel.sh, skills/creview-spec/SKILL.md, skills/creview/SKILL.md, tests/test-review-intel-consumer.sh, .correctless/ARCHITECTURE.md, .correctless/AGENT_CONTEXT.md, CONTRIBUTING.md)
- **New abstractions**: 0
- **Trust boundaries touched**: 1 (TB-003 -- extends existing consumption pattern)
- **Risk surface delta**: low

## Invariants

### INV-001: Review orchestrators read the intelligence brief file
- **Type**: must
- **Category**: functional
- **Statement**: Both `/creview-spec` and `/creview` orchestrators must read the brief file at `.correctless/meta/cross-feature-intel.json` via `jq` during their Historical Pattern Integration / Historical Pattern Findings section, after agent findings are collected and before presenting historical patterns to the user. The orchestrator filters entries client-side, selecting only entries with `occurrences >= 3`. Review skills must NOT invoke `scripts/cross-feature-intel.sh` — the script is invoked only by `/cspec`, which is the sole trigger for regeneration and occurrence tracking. This separation prevents review invocations from incrementing occurrence counts, which would allow a single feature's pipeline to cross the 3-occurrence threshold.
- **Violated when**: a review orchestrator invokes the script instead of reading the file, or reads the brief before agent findings are collected, or does not apply the `occurrences >= 3` filter, or errors on a missing/malformed file
- **Enforcement**: CI test assertion (grep both SKILL.md files for `cross-feature-intel.json` jq read pattern; grep both SKILL.md files for `cross-feature-intel.sh` invocation — must find none)
- **Guards against**: null
- **Test approach**: unit
- **Risk**: low

### INV-002: 3-occurrence threshold dampener
- **Type**: must
- **Category**: data-integrity
- **Statement**: The threshold operates at two levels: (1) **Script-side**: `scripts/cross-feature-intel.sh` must accept a `--min-occurrences N` flag that filters stdout output only — entries with `occurrences < N` are excluded from stdout but their occurrence count is always tracked in the on-disk brief file. The file always contains all entries regardless of the flag. When `--min-occurrences` is omitted (default), all entries pass through stdout (backward compatible). (2) **Consumer-side**: Review orchestrators read the brief file directly and apply client-side `occurrences >= 3` filtering via `jq`. Entries without an `occurrences` field (produced by pre-occurrence-tracking versions of the script, or from an old installed script that ignores `--min-occurrences`) are treated as `occurrences = 0` and excluded — this ensures the dampener defaults to conservative behavior when the installed script lacks occurrence tracking.
- **Violated when**: an entry with fewer than N occurrences appears in filtered output, or the occurrence count is not incremented on regeneration, or the flag breaks existing callers that omit it, or entries missing the `occurrences` field are treated as passing the threshold
- **Enforcement**: CI test assertion (behavioral test with fixture having entries at various occurrence counts, including entries with missing `occurrences` field)
- **Test approach**: behavioral
- **Risk**: medium

### INV-003: Agents never see the brief
- **Type**: must-not
- **Category**: security
- **Statement**: The 6 adversarial agents spawned by `/creview-spec` (red-team, assumptions, testability, design-contract, upgrade-compatibility, ux) and the single-pass agent in `/creview` must never receive intelligence brief data in their prompts. Only the orchestrator reads the brief during synthesis. This preserves the unanchored adversarial analysis that is the review's primary value. **Accepted risk**: review agents have the Read tool and could technically read `.correctless/meta/cross-feature-intel.json` at runtime. Mitigation: the brief file path is not in the agent preamble, and agents have no instruction to seek it. The grep test catches any future addition of the path to agent prompts or Task() arguments.
- **Boundary**: TB-003, TB-005
- **Violated when**: any review agent's prompt includes brief data, the standard preamble for agents includes the brief, or a Task() invocation argument references brief data
- **Enforcement**: CI test assertion (grep agent definition files and SKILL.md Task() invocation sections for `cross-feature-intel` references — must find none in agent context, only in orchestrator synthesis sections)
- **Test approach**: unit
- **Risk**: medium

### INV-004: Brief data supplements, not replaces, existing historical data
- **Type**: must
- **Category**: functional
- **Statement**: The intelligence brief is an additional data source for the Historical Pattern Integration section, alongside the existing 3 sources (qa-findings, audit-history, devadv reports). The orchestrator reads the brief after reading the existing 3 sources. Brief entries are classified into pattern classes using the same classification rules (strip instance details, preserve pattern description, merge over split). The brief provides data the existing 3 sources don't cover: deferred findings, override patterns, lens recommendations, and phase effectiveness.
- **Violated when**: the brief replaces the existing 3 data sources instead of supplementing them, or brief data is classified using different rules than existing data
- **Enforcement**: CI test assertion (verify both `qa-findings` and `cross-feature-intel` references co-exist in the Historical Pattern section)
- **Test approach**: unit
- **Risk**: low

### INV-005: Anti-anchoring directive in review synthesis
- **Type**: must
- **Category**: functional
- **Statement**: Both `/creview-spec` and `/creview` must include an anti-anchoring directive adapted for the review context when presenting brief data during synthesis. The directive text must appear before the brief data is presented, not after. The directive must include review-specific calibration examples, distinct from `/cspec`'s brainstorm-context examples. Review calibration: "Weight when a historical pattern contradicts an agent's conclusion (the brief adds independent signal); Dismiss when agents independently found the same issue (the brief is redundant, not additive) or when the brief entry is about a pattern in a different module from the current spec."
- **Violated when**: the review skill presents brief data without the anti-anchoring directive, or the directive appears after the data, or the calibration examples are copied from `/cspec` without review-context adaptation
- **Enforcement**: CI test assertion (grep for anti-anchoring directive text in both SKILL.md files, verify ordering via line-number comparison)
- **Test approach**: unit
- **Risk**: low

### INV-006: Dormant degradation when brief is absent
- **Type**: must
- **Category**: functional
- **Statement**: When the brief file at `.correctless/meta/cross-feature-intel.json` is absent, malformed, or contains only entries below the occurrence threshold, the review orchestrator proceeds without brief data — no error, no behavioral change. The existing Historical Pattern Integration section continues to function with its 3 data sources. This follows PAT-019 (dormant-signal graceful degradation). When the brief is present but all entries are below threshold, the orchestrator emits a one-time informational note: "Intelligence brief has N entries accumulating (need 3+ feature cycles to surface in reviews)." This provides visibility into the cold-start accumulation process without blocking.
- **Violated when**: a review skill errors when the brief file is missing or malformed, or skips the entire Historical Pattern section when only the brief is unavailable, or fails to emit the informational note when entries exist but are all below threshold
- **Enforcement**: CI test assertion (verify Historical Pattern section references both brief dormant behavior, the informational note text, and existing data sources)
- **Test approach**: unit
- **Risk**: low

### INV-007: Occurrence tracking persists across regenerations
- **Type**: must
- **Category**: data-integrity
- **Statement**: The script maintains occurrence counts in the brief file at `.correctless/meta/cross-feature-intel.json`. On each regeneration: (1) read the existing brief if it exists via `locked_update_file()` from `scripts/lib.sh` (ABS-003 pattern — protects the read-modify-write cycle against concurrent invocations), (2) extract current entries with their occurrence counts, (3) regenerate from source data, (4) for entries that appear in both old and new (matched by `id`): increment `occurrences` by 1, (5) for entries new in this generation: set `occurrences` to 1, (6) entries that were in the old brief but not in the new (filtered by staleness or scope) retain their count in a `_dormant_counts` metadata section (top-level JSON object, keyed by entry `id`) for future re-appearance. `_dormant_counts` entries older than 90 days (matching the parent spec's staleness filter) are evicted. The `_dormant_counts` section is capped at 100 entries, with oldest entries evicted first when the cap is exceeded. (7) Entries without an `occurrences` field in the existing brief (from pre-occurrence-tracking versions) are treated as `occurrences = 0`, so the first run seeds them at `occurrences = 1`. The `occurrences` field is added to the entry schema alongside the existing fields (`id`, `date`, `summary`, `file_refs`, `severity`, `source`). This makes the script stateful — each run mutates occurrence counts. Only `/cspec` invokes the script (INV-001 prohibits review skills from invoking it), so the regeneration + increment cycle is bound to one invocation per feature. ABS-037's idempotency claim must be updated to: "the script is stateful (occurrence counts accumulate) while remaining sole-writer and deterministic (same inputs + same prior state = same output)."
- **Violated when**: occurrence counts reset to 1 on every regeneration, or counts are lost when entries temporarily leave the brief (scope filtering), or the field is missing from entries after the first run, or `_dormant_counts` grows unboundedly, or the read-modify-write cycle does not use `locked_update_file()`
- **Enforcement**: CI test assertion (behavioral test: generate brief twice with same data, verify count increments; verify `_dormant_counts` eviction at cap; verify `locked_update_file` usage via grep)
- **Test approach**: behavioral
- **Risk**: medium

### INV-008: Allowed-tools updated for both review skills
- **Type**: must
- **Category**: functional
- **Statement**: Both `skills/creview-spec/SKILL.md` and `skills/creview/SKILL.md` must include `Bash(*cross-feature-intel*)` in their `allowed-tools` frontmatter. This enables the orchestrator's `jq`-based read of `.correctless/meta/cross-feature-intel.json` via `Bash()`. The pattern matches jq commands reading the file; review skills must NOT use this pattern to invoke `scripts/cross-feature-intel.sh` (see INV-001).
- **Violated when**: either review skill's allowed-tools lacks the pattern
- **Enforcement**: CI test assertion (grep frontmatter for the pattern)
- **Guards against**: AP-008
- **Test approach**: unit
- **Risk**: low

### INV-009: ABS-037 consumer list and ABS-037 statefulness update
- **Type**: must
- **Category**: functional
- **Statement**: `.correctless/ARCHITECTURE.md` ABS-037 entry must: (1) list `/creview-spec` and `/creview` as consumers alongside `/cspec` and `/cstatus`, with a note: "Review skills read the brief file directly (jq-based, no script invocation) — they are pure consumers, not regeneration triggers." The `Enforced at` field must include `skills/creview-spec/SKILL.md (consumer)` and `skills/creview/SKILL.md (consumer)`. (2) Replace the word "Idempotent" with "stateful (occurrence counts accumulate)" in the ABS-037 invariant text. (3) TB-003's mitigation variant text must list `/creview-spec` and `/creview` as consumers of the anti-anchoring directive pattern alongside `/cspec`.
- **Violated when**: the ABS-037 entry does not list both review skills as consumers, or the ABS-037 entry still contains the word "idempotent", or the TB-003 entry does not list both review skills
- **Enforcement**: CI test assertion (grep ARCHITECTURE.md ABS-037 section for both skill references, grep ABS-037 for absence of "idempotent" and presence of "stateful", grep TB-003 for both review skill references)
- **Guards against**: AP-005
- **Test approach**: unit
- **Risk**: low

### INV-010: /cstatus reports threshold proximity
- **Type**: must
- **Category**: functional
- **Statement**: `/cstatus` section 6c (intelligence health) must report threshold proximity for brief entries: number of entries at each occurrence count below the threshold (e.g., "5 entries at 2/3 occurrences, 2 entries above threshold"). This provides diagnostic visibility for users investigating why intelligence is not surfacing in reviews.
- **Violated when**: `/cstatus` reports brief entry counts but not occurrence-level breakdown
- **Enforcement**: CI test assertion (grep `/cstatus` SKILL.md for occurrence/threshold proximity text)
- **Test approach**: unit
- **Risk**: low

### INV-011: Review findings artifact records intelligence consumption
- **Type**: must
- **Category**: functional
- **Statement**: The review findings artifact (`.correctless/artifacts/review-spec-findings-{slug}.md` for `/creview-spec`, `.correctless/artifacts/review-findings-{slug}.md` for `/creview`) must include a metadata line recording intelligence brief consumption status: "Intelligence brief: consumed (N entries above threshold)" or "Intelligence brief: dormant (file absent/malformed/all below threshold)". This provides a persistent record distinguishing "intelligence was unavailable" from "intelligence found nothing relevant."
- **Violated when**: the review findings artifact contains no intelligence consumption metadata
- **Enforcement**: CI test assertion (grep both review SKILL.md files for the metadata line template in the artifact-write section)
- **Test approach**: unit
- **Risk**: low

## Prohibitions

### PRH-001: Brief data must not enter agent prompts
- **Statement**: Intelligence brief content must never be interpolated into the standard preamble or individual prompts of any review agent (red-team, assumptions, testability, design-contract, upgrade-compatibility, ux, single-pass). The orchestrator is the sole consumer within the review skill.
- **Detection**: grep all agent definition files (`agents/review-spec-*.md`) and SKILL.md agent spawn sections for `cross-feature-intel` references in agent context -- must find zero
- **Consequence**: agents receiving historical data lose their unanchored adversarial perspective -- the review's primary value proposition

### PRH-002: Review skills must not invoke the intelligence script
- **Statement**: Review skills (`/creview-spec`, `/creview`) must never invoke `scripts/cross-feature-intel.sh`. They read the brief file at `.correctless/meta/cross-feature-intel.json` directly via `jq` with client-side `occurrences >= 3` filtering. Only `/cspec` invokes the script (sole regeneration trigger). This separation prevents review invocations from incrementing occurrence counts, which would allow a single feature's pipeline to cross the 3-occurrence threshold and defeat the feedback loop dampener.
- **Detection**: grep review SKILL.md files for `cross-feature-intel.sh` invocations — must find zero. Grep for `cross-feature-intel.json` jq reads — must find one per skill.
- **Consequence**: if review skills invoke the script, a single feature's pipeline (`/cspec` → `/creview-spec` → `/creview`) triggers 3 regenerations, crossing the threshold within one cycle and defeating the dampener entirely

## Boundary Conditions

### BND-001: All entries below threshold
- **Boundary**: INV-002
- **Input from**: project with brief entries that have all appeared only 1-2 times
- **Validation required**: review orchestrator's jq filter returns empty when all entries have `occurrences < 3`. Script's `--min-occurrences 3` stdout output produces valid JSON with all sections empty.
- **Failure mode**: dormant — review orchestrator emits informational note ("N entries accumulating, need 3+ cycles") and proceeds without brief-sourced patterns, existing 3 data sources still function
- **Test approach**: behavioral

### BND-002: First-ever brief generation and pre-occurrence-tracking migration
- **Boundary**: INV-007
- **Input from**: project running the script for the first time (no existing brief file), OR project with an existing brief file from pre-occurrence-tracking era (entries without `occurrences` field)
- **Validation required**: (a) No existing brief: all entries start with `occurrences: 1`, no error from missing prior brief. (b) Existing brief without `occurrences` field: entries are treated as `occurrences = 0`, seeded to `occurrences = 1` on first run. The `_dormant_counts` section is absent — created empty on first run.
- **Failure mode**: all entries below threshold on first run — review gets no brief data until 3+ regenerations, which is correct (the dampener working as designed)
- **Test approach**: behavioral

### BND-003: Entry leaves and re-enters the brief
- **Boundary**: INV-007
- **Input from**: an entry filtered out by scope on one run, then matching scope on a later run
- **Validation required**: the entry's occurrence count is preserved via `_dormant_counts` and resumed when it re-enters — not reset to 1
- **Failure mode**: fail-open — if `_dormant_counts` is lost or corrupted (missing key, null value, wrong type), the entry restarts at 1 (conservative, delays re-surfacing but doesn't break anything)
- **Test approach**: behavioral (must include corruption cases: `_dormant_counts` key missing, null, string-instead-of-integer)

## STRIDE Analysis

### STRIDE for TB-003: LLM-generated historical findings -> review agent context
- **Spoofing**: Same as cross-feature-intelligence spec -- brief data is LLM-generated from project artifacts. The 3-occurrence threshold adds a natural dampener: a spoofed entry must survive 3 regeneration cycles before surfacing in review context.
- **Tampering**: Brief file could be modified between script generation and review read. The `occurrences` field is functionally a gate (controls what enters review context), but the file is local-only, gitignored, and an attacker with filesystem access already implies full compromise. **Accepted risk**: SFG protection is not added for the brief file — the advisory classification is preserved. Mitigated by: anti-anchoring directive, orchestrator classifies patterns (doesn't echo raw text per TB-003 invariant), and the threshold is a dampener not a security boundary.
- **Repudiation**: No concern -- informational.
- **Information Disclosure**: Brief aggregates findings. Mitigated by: gitignored under `.correctless/meta/`.
- **Denial of Service**: Brief could be large. Mitigated by: 30-entry cap from parent spec (INV-004), plus threshold filtering further reduces entries.
- **Elevation of Privilege**: Brief could contain injection text. Mitigated by: anti-anchoring directive (INV-005), agents never see it (INV-003/PRH-001), orchestrator re-classifies patterns instead of echoing text.

## Environment Assumptions

- **EA-001**: `scripts/cross-feature-intel.sh` exists and is executable -- if not, review skills degrade dormant per INV-006. Refs parent spec EA-001 (jq availability).

## Design Decisions

### DD-001: Orchestrator-only consumption, not agent-level
The brief feeds into the orchestrator's synthesis phase, not into individual review agents. This preserves the agent separation that is the review's primary value: agents give unanchored fresh analysis, the orchestrator cross-references. This matches the existing pattern -- the shift-left review's Historical Pattern Integration section already works this way for qa-findings, audit-history, and devadv reports.

### DD-002: 3-occurrence threshold over source-type filtering
Instead of excluding deferred findings from the review brief (which would lose genuine high-signal entries), the threshold requires any entry to have appeared in 3+ brief generations before surfacing in review context. This bounds the feedback loop temporally (3+ features must have run) while preserving all data source types. The threshold is a constant in the review orchestrator's jq filter, not configurable — simplicity over flexibility for v1. The feedback loop is primarily through deferred findings (review defers → deferred finding → brief → review) but can cross source types (e.g., a review finding about an override pattern gets deferred, enters the deferred findings source, then resurfaces in the brief's deferred section). The threshold dampens all sources uniformly — this is conservative by design. Source-specific thresholds are deferred to v2 if the uniform approach proves too blunt.

### DD-003: Occurrence count stored in the brief file, not a separate counter
The brief file already exists as the sole-writer artifact (ABS-037). Adding `occurrences` per entry and `_dormant_counts` in metadata is simpler than maintaining a separate counter file. The trade-off is that the brief file grows slightly (~1 field per entry) but stays self-contained. The sole-writer contract is unchanged -- only `scripts/cross-feature-intel.sh` writes.

## Open Questions

- **OQ-001**: Should the threshold be configurable per project? Currently hardcoded at 3. A project with very frequent feature cycles might want 5; a slower project might want 2. Deferred -- hardcoded is simpler and 3 is a reasonable default.
