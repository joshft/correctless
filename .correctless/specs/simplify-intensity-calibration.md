# Spec: Simplify Intensity Calibration (DA-004)

## Metadata
- **Created**: 2026-05-16T07:00:00Z
- **Status**: reviewed
- **Impacts**: intensity-calibration (strips active/hybrid modes), token-aware-intensity (removes 200K threshold)
- **Branch**: feature/simplify-intensity-calibration
- **Research**: null
- **Recommended-intensity**: high
- **Intensity**: high
- **Intensity reason**: project floor = high; modifies skills/cspec/SKILL.md (core pipeline skill)
- **Override**: none

## Context

The intensity calibration system was designed to auto-adjust intensity recommendations based on historical data (QA rounds, BLOCKING findings, token usage). In practice: 21 of 22 calibration entries have `actual_tokens: 0`, the auto-raise threshold (200K tokens) has never fired, `intensity_calibration_mode` was never set in config (defaulting to passive — meaning active/hybrid modes never ran), and model-baselines.json doesn't exist. The auto-raise system is elaborate infrastructure that has never produced a single automated decision. This feature strips the non-functional automation while retaining the useful parts: historical data collection (/cverify still writes entries) and passive advisory display (/cspec still shows calibration context to the human).

## Scope

**In scope:**
- Remove active mode (auto-raise logic) from /cspec SKILL.md Step 7b
- Remove hybrid mode (passive-until-5-entries-then-active) from /cspec SKILL.md Step 7b
- Remove `intensity_calibration_mode` config key recognition — calibration is always passive
- Remove the `intensity_calibration_mode` key from config templates (workflow-config.json, workflow-config-full.json)
- Remove the calibration mode selection decision from /csetup SKILL.md
- Remove the 200K token threshold comparison from the calibration display
- Simplify the passive display: show QA rounds and findings averages as advisory, without threshold-based "consider raising" recommendations
- Update documentation: remove mode descriptions from AGENT_CONTEXT.md and FEATURES.md
- Remove specific broken test functions (see Tests Requiring Update below)

**Tests requiring update (enumerated):**
- `test-intensity-calibration.sh` INV-004 (`test_inv004_csetup_calibration_mode`) — REMOVE (tests mode selection in /csetup)
- `test-intensity-calibration.sh` INV-005 (`test_inv005_mode_behaviors`) — REMOVE (tests active/hybrid mode logic)
- `test-intensity-calibration.sh` INV-006 (`test_inv006_config_templates`) — UPDATE (remove `intensity_calibration_mode` assertion, keep template existence check)
- `test-intensity-calibration.sh` INV-012 (`test_inv012_show_arithmetic`) — UPDATE (remove threshold comparison and "Consider.*intensity" assertions)
- `test-token-aware-intensity.sh` INV-003 (`test_inv003_token_threshold_active_mode`) — REMOVE
- `test-token-aware-intensity.sh` INV-004c (passive token arithmetic with 200K reference) — UPDATE (remove 200K threshold assertion)
- `test-token-aware-intensity.sh` INV-008i (behavioral constant presence check for 200K) — REMOVE

**Tests preserved unchanged:**
- `test-intensity-calibration.sh` INV-001, INV-002, INV-003, INV-007, INV-008, INV-009, INV-010, INV-011, PRH-001, PRH-002
- `test-token-aware-intensity.sh` INV-001, INV-002

**Not in scope:**
- Removing /cverify's calibration writer (it still writes entries — data collection continues)
- Removing the calibration file (`.correctless/meta/intensity-calibration.json` stays)
- Removing the `actual_tokens` field from calibration entries (data is still collected; it's just not used for auto-raise)
- Changing intensity detection signals (Step 7) — only the post-signal calibration modifier (Step 7b) is affected
- Removing `Recommended-intensity` / override tracking in spec metadata — these still serve the calibration loop's data collection purpose

## Complexity Budget
- **Estimated LOC**: ~200 (mostly deletions — net negative LOC; includes ~150 lines of test function removal)
- **Files touched**: ~12 (skills/cspec/SKILL.md, correctless/skills/cspec/SKILL.md, skills/csetup/SKILL.md, correctless/skills/csetup/SKILL.md, tests/test-intensity-calibration.sh, tests/test-token-aware-intensity.sh, templates/workflow-config.json, templates/workflow-config-full.json, correctless/templates/workflow-config.json, correctless/templates/workflow-config-full.json, .correctless/AGENT_CONTEXT.md, FEATURES.md)
- **New abstractions**: 0
- **Trust boundaries touched**: 0
- **Risk surface delta**: negative (removing complexity)

## Invariants

### INV-001: No auto-raise in /cspec
- **Type**: must-not
- **Category**: functional
- **Statement**: The /cspec SKILL.md MUST NOT contain auto-raise logic. Specifically: no "auto-raise" or "auto-raised" phrasing, no "active mode" auto-adjustment behavior, no "hybrid mode" conditional switching. The calibration section must be advisory-only.
- **Boundary**: null
- **Violated when**: /cspec contains language instructing automatic intensity level adjustment based on calibration data
- **Enforcement**: CI test assertion (grep for absence of auto-raise patterns)
- **Guards against**: null
- **Test approach**: unit
- **Risk**: low

### INV-002: No calibration mode config key
- **Type**: must-not
- **Category**: functional
- **Statement**: The /cspec SKILL.md MUST NOT reference `intensity_calibration_mode` as a config key to read. Calibration behavior is always passive — there is no mode selector.
- **Boundary**: null
- **Violated when**: /cspec reads or references `intensity_calibration_mode` from workflow-config.json
- **Enforcement**: CI test assertion (grep for absence)
- **Guards against**: null
- **Test approach**: unit
- **Risk**: low

### INV-003: No 200K token threshold
- **Type**: must-not
- **Category**: functional
- **Statement**: The /cspec SKILL.md MUST NOT contain the literal strings "200,000" or "200000" anywhere in the calibration section (Step 7b). Total absence is the expected outcome — no threshold constant for tokens is permitted.
- **Boundary**: null
- **Violated when**: /cspec contains "200,000" or "200000" in the calibration section
- **Enforcement**: CI test assertion (grep for absence of 200,000/200000)
- **Guards against**: null
- **Test approach**: unit
- **Risk**: low

### INV-004: Passive advisory display retained
- **Type**: must
- **Category**: functional
- **Statement**: The /cspec SKILL.md MUST still display calibration data as advisory text during Step 8 presentation when overlapping calibration entries exist. The display shows: overlapping entry feature slugs, QA rounds average, BLOCKING findings average, override history, and actual_tokens average (when non-zero entries exist). The display MUST NOT include threshold comparisons or raise recommendations.
- **Boundary**: ABS-005
- **Violated when**: Calibration data is not displayed when available, or the display includes threshold-based recommendations
- **Enforcement**: CI test assertion (grep for advisory display elements + grep for absence of threshold/recommendation patterns)
- **Guards against**: null
- **Test approach**: unit
- **Risk**: low
- **Display format example**:
  ```
  Calibration context (advisory — {N} prior features overlapped with these paths):
  - feature-a: 4 QA rounds, 2 BLOCKING findings
  - feature-b: 3 QA rounds, 5 BLOCKING findings
  - Averages: 3.5 QA rounds, 3.5 BLOCKING findings
  - Override history: 1 of 2 features overrode the recommendation
  ```
  When `actual_tokens` entries are non-zero, add: `- Token usage average: {N}`

### INV-005: /cverify writer unchanged
- **Type**: must
- **Category**: functional
- **Statement**: The /cverify SKILL.md calibration writer MUST remain unchanged. /cverify continues to write entries with all existing fields (feature_slug, recommended_intensity, actual_intensity, actual_qa_rounds, actual_findings_count, actual_tokens, file_paths_touched, timestamp).
- **Boundary**: ABS-005
- **Violated when**: /cverify stops writing calibration entries or drops fields from the entry schema
- **Enforcement**: CI test assertion (existing test-intensity-calibration.sh INV-001 tests remain unchanged)
- **Guards against**: null
- **Test approach**: unit
- **Risk**: low

### INV-006: Graceful absence unchanged
- **Type**: must
- **Category**: functional
- **Statement**: When the calibration file doesn't exist or has zero entries, /cspec MUST proceed without calibration input (dormant signal behavior). No error, no warning, no change to the recommendation. This behavior is unchanged from the current implementation.
- **Boundary**: null
- **Violated when**: /cspec errors or warns when calibration file is absent
- **Enforcement**: CI test assertion (existing test-intensity-calibration.sh INV-008 tests remain unchanged)
- **Guards against**: null
- **Test approach**: unit
- **Risk**: low

### INV-007: Recency window unchanged
- **Type**: must
- **Category**: functional
- **Statement**: The 50-entry recency window MUST remain. /cspec reads at most the 50 most recent entries. This caps file read size regardless of how much historical data accumulates.
- **Boundary**: null
- **Violated when**: /cspec reads unlimited entries or removes the 50-entry cap
- **Enforcement**: CI test assertion (existing test-intensity-calibration.sh INV-010 tests remain unchanged)
- **Guards against**: null
- **Test approach**: unit
- **Risk**: low

### INV-008: No calibration mode in /csetup or templates
- **Type**: must-not
- **Category**: functional
- **Statement**: The /csetup SKILL.md MUST NOT present a calibration mode selection decision. The config templates (workflow-config.json, workflow-config-full.json) MUST NOT contain the `intensity_calibration_mode` key. There is no mode to choose — calibration is always passive.
- **Boundary**: null
- **Violated when**: /csetup presents a mode selection question, or templates scaffold the dead config key
- **Enforcement**: CI test assertion (grep for absence of `intensity_calibration_mode` in /csetup and templates)
- **Guards against**: AP-005
- **Test approach**: unit
- **Risk**: low

### INV-009: Documentation reflects removal
- **Type**: must
- **Category**: functional
- **Statement**: `.correctless/AGENT_CONTEXT.md` and `FEATURES.md` MUST NOT describe active mode, hybrid mode, or the 200K token auto-raise threshold as current functionality. Historical references in `docs/workflow-history.md` are exempt (they describe what existed at a point in time).
- **Boundary**: null
- **Violated when**: AGENT_CONTEXT.md or FEATURES.md describes calibration modes that no longer exist
- **Enforcement**: CI test assertion (grep AGENT_CONTEXT.md and FEATURES.md for "active.*auto-raise|hybrid.*passive|200K.*trigger" patterns — must be absent)
- **Guards against**: AP-005
- **Test approach**: unit
- **Risk**: low

## Prohibitions

### PRH-001: No automated intensity decisions
- **Statement**: Calibration data MUST NEVER automatically change the intensity recommendation. The human always decides. Calibration is read-only advisory context, not a decision-maker.
- **Detection**: grep /cspec SKILL.md for auto-raise/auto-adjust/automatically patterns in calibration section
- **Consequence**: The system silently raises intensity without human awareness — defeats the purpose of human-controlled workflow

### PRH-002: No removal of data collection
- **Statement**: This feature MUST NOT remove /cverify's calibration entry writer or delete the calibration file. Data collection continues — only the automated consumption is removed.
- **Detection**: grep /cverify SKILL.md for calibration write instructions (must still exist)
- **Consequence**: Historical data stops accumulating, preventing future analysis or manual use of the data

## Design Decisions

- **DD-001**: Keep data collection, remove automation. Rationale: the QA rounds and findings count data IS useful advisory context. The auto-raise was the broken part, not the data.
- **DD-002**: Remove `intensity_calibration_mode` entirely rather than hardcoding "passive". Rationale: a config key with only one valid value is dead weight. The behavior is just "how calibration works" — no mode selection needed.
- **DD-003**: Remove threshold comparisons from the advisory display. Rationale: "average rounds (3.7) exceeds threshold (3)" implies a recommendation even without auto-raise. The advisory should show data, not evaluate it against thresholds. The human reads the numbers and decides.
- **DD-004**: Keep `actual_tokens` in the advisory display (when non-zero). Rationale: if token data ever becomes available (via Overcorrect or future fix), showing it in the advisory is free. No harm in displaying it; harm comes only from using it for automated decisions.

## Won't Do

- Remove /cverify writer
- Remove calibration file
- Remove `actual_tokens` from entry schema
- Change intensity detection signals (Step 7)
- Remove Recommended-intensity metadata tracking

## Open Questions

None.
