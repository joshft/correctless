# Spec: Intensity Calibration Loop

## Metadata
- **Created**: 2026-04-08T22:00:00Z
- **Status**: approved
- **Impacts**: intensity-detection, wire-intensity-creview, wire-intensity-pipeline
- **Branch**: feature/intensity-calibration-loop
- **Research**: null
- **Intensity**: high
- **Intensity reason**: file path signal (skills/, hooks/workflow-advance.sh), impacts intensity detection system
- **Override**: none

## Context

The intensity detection system recommends standard/high/critical per feature based on 4 signals (file paths, keywords, trust boundaries, QA history). But it never learns from outcomes. A feature recommended "standard" that needed 4 QA rounds and 11 findings was a bad recommendation — nothing records that or adjusts future recommendations. This feature closes the feedback loop: /cverify writes calibration entries after each feature, and /cspec reads them to improve future intensity recommendations. The user chooses the calibration mode (passive/active/hybrid) via /csetup, defaulting to passive.

## Scope

**Covers:**
- Calibration entry schema and storage file (`.correctless/meta/intensity-calibration.json`)
- /cverify writes a calibration entry at the end of verification (before advancing state)
- /cspec reads calibration data during intensity detection to inform recommendations
- /csetup presents calibration mode selection (passive/active/hybrid, default passive)
- New config field `workflow.intensity_calibration_mode` in workflow-config.json
- New `Recommended-intensity` field in spec Metadata section (stores pre-override system recommendation)
- Add write permission for `intensity-calibration.json` to cverify's scope
- Recency window: calibration reads consider only the most recent 50 entries

**Does NOT cover:**
- Changing the 4 existing intensity detection signals — those remain as-is
- Auto-adjusting intensity without user involvement in active mode (active mode raises the floor, user still sees and can override)
- Token-aware intensity (separate feature)
- Auto-promoting recurring patterns (separate feature)
- File path overlap after refactoring — known limitation; refactorings invalidate calibration data (documented, not addressed)

## Complexity Budget
- **Estimated LOC**: ~80 net change
- **Files touched**: ~7 (cverify SKILL.md, cspec SKILL.md, csetup SKILL.md, workflow-config.json templates ×2, spec templates ×2, test file)
- **New abstractions**: 0 (extends existing intensity detection, no new runtime code)
- **Trust boundaries touched**: 0
- **Risk surface delta**: low (LLM skill instructions only, no hooks or scripts modified)

## Invariants

### INV-001: /cverify writes calibration entry
- **Type**: must
- **Category**: functional
- **Statement**: After completing verification and before advancing the workflow state, /cverify appends a calibration entry to `.correctless/meta/intensity-calibration.json`. The entry contains: `feature_slug`, `recommended_intensity` (from the spec's `Recommended-intensity` metadata field — the system's pre-override suggestion), `actual_intensity` (from the spec's `Intensity` metadata field — the approved post-override level), `actual_qa_rounds` (from workflow state), `actual_findings_count` (count of BLOCKING findings only from qa-findings JSON), `actual_spec_updates` (from workflow state), `file_paths_touched` (from git diff), and `timestamp`. If the file doesn't exist, create it with a `calibration_entries` array. If `.correctless/meta/` does not exist, create it.
- **Violated when**: /cverify completes without writing a calibration entry, or the entry is missing any required field
- **Test approach**: unit — grep cverify SKILL.md for calibration entry writing instructions, verify all fields are specified and source artifacts are correct (Recommended-intensity for recommended, Intensity for actual)

### INV-002: Calibration entry schema
- **Type**: must
- **Category**: data-integrity
- **Statement**: Each calibration entry follows this schema: `{ feature_slug: string, recommended_intensity: "standard"|"high"|"critical", actual_intensity: "standard"|"high"|"critical", actual_qa_rounds: number, actual_findings_count: number, actual_spec_updates: number, file_paths_touched: string[], timestamp: ISO string }`. The `recommended_intensity` is read from the spec's `Recommended-intensity` metadata field (the system's pre-override suggestion, written by /cspec during Step 8). The `actual_intensity` is read from the spec's `Intensity` metadata field (the approved post-override level). The `actual_qa_rounds` and `actual_spec_updates` are read from the workflow state file. The `actual_findings_count` is the count of BLOCKING findings only from `qa-findings-{slug}.json` (not MEDIUM/LOW — those indicate thorough QA, not insufficient intensity).
- **Violated when**: A calibration entry has wrong types, missing fields, or values sourced from the wrong artifact
- **Test approach**: unit — verify schema documentation in cverify SKILL.md matches this spec

### INV-003: /cspec reads calibration data during intensity detection
- **Type**: must
- **Category**: functional
- **Statement**: During the intensity detection step (Step 7), /cspec reads `.correctless/meta/intensity-calibration.json` if it exists. It reads at most the 50 most recent entries (INV-010). For each file path in the current feature's scope, it finds calibration entries whose `file_paths_touched` have any overlap (at least one file path in common). It computes the arithmetic mean of `actual_qa_rounds` and `actual_findings_count` for overlapping entries. This data is used according to the calibration mode (INV-005). Calibration runs AFTER the 4-signal highest-wins evaluation as a post-signal modifier (INV-011).
- **Violated when**: /cspec's intensity detection section does not reference intensity-calibration.json, does not compute overlap-based averages, or runs calibration as a signal rather than a post-signal modifier
- **Test approach**: unit — grep cspec SKILL.md for calibration data reading instructions

### INV-004: /csetup presents calibration mode selection
- **Type**: must
- **Category**: functional
- **Statement**: /csetup presents the intensity calibration mode as a structured decision during source control configuration (Step 8). Options: (1) Passive (default, recommended) — show advisory text during /cspec, (2) Active — automatically raise the intensity floor for file paths that historically underperformed, (3) Hybrid — passive for first 5 calibration entries, then active. The selected mode is written to `workflow.intensity_calibration_mode` in workflow-config.json. If the user doesn't choose, default to `passive`.
- **Violated when**: /csetup does not present the calibration mode decision, or the default is not passive
- **Test approach**: unit — grep csetup SKILL.md for calibration mode options, verify 3 options present with passive as default

### INV-005: Calibration mode affects /cspec behavior
- **Type**: must
- **Category**: functional
- **Statement**: /cspec's intensity detection reads `workflow.intensity_calibration_mode` from config (default: `passive`). When absent from config, default to `passive`. Behavior per mode: **Passive**: during Step 8 presentation, show advisory text with full arithmetic (INV-012): "{N} prior features touching these paths averaged {avg} QA rounds and {M} BLOCKING findings at {recommended_intensity}. [list: feature-a: 4 rounds, feature-b: 3 rounds, ...]. Threshold: 3 rounds or 8 findings. Consider {higher} intensity." Include override context: "In {K} of {N} cases, the user overrode the recommendation." No automatic floor adjustment. **Active**: if overlapping calibration entries show average QA rounds >= 3 or average BLOCKING findings >= 8 at the `recommended_intensity` (not `actual_intensity` — learn from what the system suggested, not what was used after override), automatically raise the recommendation by one level (standard→high, high→critical). Show the same arithmetic as passive mode but note "auto-raised from {old} to {new} based on calibration data." **Hybrid**: behave as passive until 5+ total calibration entries exist (global count, not per-path), then switch to active behavior.
- **Violated when**: /cspec ignores the calibration mode, or active mode doesn't auto-raise when thresholds are met
- **Test approach**: unit — verify all 3 mode behaviors are documented in cspec SKILL.md with thresholds matching this spec

### INV-006: Config templates include calibration mode
- **Type**: must
- **Category**: functional
- **Statement**: Both `workflow-config.json` templates (lite and full) include `"intensity_calibration_mode": "passive"` in the `workflow` section. The field appears in the same position as other workflow fields.
- **Violated when**: A template is missing the field, or the default value is not "passive"
- **Test approach**: unit — grep both templates for intensity_calibration_mode with default passive

### INV-007: Calibration data is read-only for /cspec
- **Type**: must
- **Category**: data-integrity
- **Statement**: /cspec only reads calibration data — it never writes, modifies, or deletes calibration entries. Only /cverify writes calibration entries.
- **Violated when**: /cspec's SKILL.md contains instructions to write to intensity-calibration.json
- **Test approach**: unit — grep cspec SKILL.md for write/append/create instructions referencing calibration

### INV-008: Graceful handling when no calibration data exists
- **Type**: must
- **Category**: functional
- **Statement**: When `.correctless/meta/intensity-calibration.json` does not exist or has zero entries, /cspec's intensity detection proceeds normally without calibration input. No error, no warning, no change to the recommendation. The calibration signal is dormant (same pattern as antipattern/QA history signals in the existing detection).
- **Violated when**: /cspec errors or changes behavior when calibration data is absent
- **Test approach**: unit — verify cspec SKILL.md handles missing file gracefully (dormant signal pattern)

### INV-009: Spec Metadata includes Recommended-intensity field
- **Type**: must
- **Category**: data-integrity
- **Statement**: /cspec's spec Metadata section includes a `Recommended-intensity` field that stores the system's pre-override intensity recommendation. This field is written during Step 8 after intensity detection runs (Step 7), before the user sees the override options. The `Intensity` field continues to store the approved (post-override) level. Both spec templates (lite and full) must include the `Recommended-intensity` field placeholder.
- **Violated when**: A spec is produced without a `Recommended-intensity` field, or the field stores the post-override value instead of the pre-override recommendation
- **Test approach**: unit — grep both spec templates for `Recommended-intensity` field; grep cspec SKILL.md for instructions to write this field during Step 8

### INV-010: Calibration reads use recency window
- **Type**: must
- **Category**: functional
- **Statement**: When /cspec reads calibration data (INV-003), it considers only the most recent 50 entries (sorted by timestamp, newest first). Entries beyond 50 are ignored. This caps file read size and naturally de-escalates as recent features at elevated intensity run clean.
- **Violated when**: /cspec reads all calibration entries without a recency limit
- **Test approach**: unit — grep cspec SKILL.md for recency window / most recent 50

### INV-011: Calibration is a post-signal modifier
- **Type**: must
- **Category**: functional
- **Statement**: Calibration data is NOT a 5th signal in the intensity detection signal hierarchy. It runs AFTER the 4-signal highest-wins evaluation as a post-signal modifier. In passive mode, it adds advisory text to the presentation. In active mode, it may raise the result by one level. It never lowers the result below what the 4 signals produced.
- **Violated when**: Calibration is integrated as a signal in the highest-wins evaluation rather than as a post-evaluation modifier
- **Test approach**: unit — verify cspec SKILL.md places calibration logic after the signal evaluation, not inside it

### INV-012: /cspec shows calibration arithmetic
- **Type**: must
- **Category**: functional
- **Statement**: When calibration data produces advisory text (passive mode) or an auto-raise (active mode), /cspec must show the intermediate calculation: list the overlapping entries with their feature slugs and values, show the sum, count, and average, and state the threshold comparison. The user must see the math, not just the conclusion.
- **Violated when**: /cspec shows only "Recommending high based on calibration data" without the underlying entries and arithmetic
- **Test approach**: unit — grep cspec SKILL.md for instructions to list entries, show arithmetic, and display threshold comparison

## Prohibitions

### PRH-001: No calibration data in workflow state files
- **Statement**: Calibration data lives in `.correctless/meta/intensity-calibration.json`, not in workflow state files (`workflow-state-*.json`). The state file is per-branch and ephemeral; calibration data is cross-branch and persistent.
- **Detection**: grep workflow-advance.sh for calibration-related fields
- **Consequence**: Calibration data lost when workflow state is reset or branch is deleted

### PRH-002: v1 thresholds are behavioral constants
- **Statement**: The active mode thresholds (QA rounds >= 3, BLOCKING findings >= 8) are documented in skill files in v1, not stored in workflow-config.json. Users choose the MODE (passive/active/hybrid), not the thresholds. If demand exists from enterprise teams wanting custom thresholds (e.g., security-focused teams triggering at 2 QA rounds, noisy-QA teams raising findings threshold to 12), expose as optional config in a future iteration.
- **Detection**: grep workflow-config.json templates for qa_rounds or findings thresholds (v1 only — may be relaxed later)
- **Consequence**: Premature config exposure creates values users don't understand. Defer until real demand exists.

## Open Questions

None.
