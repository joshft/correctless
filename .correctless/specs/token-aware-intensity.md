# Spec: Token-Aware Intensity Calibration

## Metadata
- **Created**: 2026-04-09T03:30:00Z
- **Status**: approved
- **Impacts**: intensity-calibration, cverify, cspec, cmetrics
- **Branch**: feature/token-aware-intensity
- **Research**: null
- **Recommended-intensity**: high
- **Intensity**: high
- **Intensity reason**: file path signal (skills/), impacts calibration data flow (ABS-005)
- **Override**: none

## Context

The calibration loop (ABS-005) records QA rounds and BLOCKING findings per feature but ignores token cost. A feature that burned 300K tokens across 8 subagents gets the same intensity recommendation as one that used 30K tokens. Adding token data to calibration entries lets /cspec raise intensity for code areas that historically consume disproportionate tokens — expensive features are often complex features that benefit from higher intensity. Separately, /cmetrics already shows aggregate token ROI but lacks a per-feature cost table showing which features were expensive and why.

## Scope

**Covers:**
- Add `actual_tokens` field to /cverify's calibration entry schema (summed from token-log JSONL via deterministic jq)
- Add token-based threshold to /cspec's calibration reader (post-signal modifier, same pattern as QA rounds)
- Add per-feature token cost table to /cmetrics output (tokens per feature, per skill category, trend line)
- Update /cspec's passive and active mode calibration arithmetic display to include token data
- Document token-log JSONL schema as ABS-006 during /cupdate-arch

**Does NOT cover:**
- Active budget warnings during implementation (deferred — needs mid-phase hooks)
- Token cost as a standalone detection signal (remains post-signal modifier only)
- Configurable token thresholds (v1 hardcodes; configurable thresholds deferred)
- Changes to the token-tracking PostToolUse hook (data collection is unchanged)
- Cost estimation in dollars (token-to-dollar conversion is model-dependent and stale quickly)

## Complexity Budget
- **Estimated LOC**: ~120 net change
- **Files touched**: ~5 (cverify SKILL.md, cspec SKILL.md, cmetrics SKILL.md, test file, CI/config wiring)
- **New abstractions**: 1 (ABS-006: token-log JSONL contract — documented during /cupdate-arch)
- **Trust boundaries touched**: 0
- **Risk surface delta**: low (LLM skill instructions only, no hooks or scripts modified)

## Invariants

### INV-001: /cverify writes actual_tokens to calibration entries
- **Type**: must
- **Category**: data-integrity
- **Statement**: When writing a calibration entry to `.correctless/meta/intensity-calibration.json`, /cverify sums `total_tokens` from all entries in the token log JSONL file for the current branch. The file is located using branch_slug (from the workflow state's `.branch` field via `branch_slug()` in scripts/lib.sh), matching the naming convention used by the token-tracking hook: `.correctless/artifacts/token-log-{branch-slug}.jsonl`. The summation must use a deterministic `jq` command (not LLM arithmetic). The result is written as `actual_tokens` (integer) in the calibration entry. If the token log file does not exist or is empty, `actual_tokens` is 0. Malformed JSONL lines (truncated, invalid JSON) must be skipped — sum only lines where `total_tokens` is a valid number.
- **Violated when**: /cverify writes a calibration entry without `actual_tokens`, uses task-slug instead of branch-slug to locate the file, uses LLM arithmetic instead of jq, or a malformed line causes the entire summation to fail
- **Test approach**: unit — grep cverify SKILL.md for actual_tokens field, branch_slug/branch-slug file location, jq summation command, and malformed line handling

### INV-002: /cspec reads actual_tokens from calibration entries (token-aware entries only)
- **Type**: must
- **Category**: functional
- **Statement**: During Step 7b (Intensity Calibration), /cspec reads `actual_tokens` from overlapping calibration entries alongside `actual_qa_rounds` and `actual_findings_count`. The arithmetic mean of `actual_tokens` is computed only across entries where `actual_tokens` is present and greater than 0 — entries without `actual_tokens` (or with `actual_tokens: 0`) are excluded from the token-specific arithmetic. This prevents legacy entries from diluting the signal. The QA rounds and BLOCKING findings arithmetic continues to include all overlapping entries (no change to existing behavior).
- **Violated when**: /cspec's calibration reader ignores the actual_tokens field, or includes zero/absent actual_tokens entries in the token arithmetic
- **Test approach**: unit — grep cspec SKILL.md for actual_tokens in calibration arithmetic, and for exclusion of zero/absent entries from token average

### INV-003: Token threshold for active mode auto-raise
- **Type**: must
- **Category**: functional
- **Statement**: In active mode, /cspec auto-raises the intensity recommendation by one level if any of these conditions hold for overlapping calibration entries: average `actual_qa_rounds` >= 3, average `actual_findings_count` >= 8, or average `actual_tokens` >= 200,000. These three conditions are disjunctive (OR'd). The auto-raise clause in the SKILL.md must list all three thresholds with "or" connectors in the same clause.
- **Violated when**: /cspec does not check actual_tokens against a threshold in active mode, the threshold is not 200K, or the three thresholds are not listed disjunctively
- **Test approach**: unit — grep cspec SKILL.md for "200,000" or "200000" near "actual_tokens", and verify all three thresholds appear in the same auto-raise clause with "or" connectors

### INV-004: Passive mode shows token calibration arithmetic
- **Type**: must
- **Category**: functional
- **Statement**: In passive mode, /cspec's calibration arithmetic display includes actual_tokens alongside QA rounds and BLOCKING findings. The display shows sum, count, and average of actual_tokens (computed only across entries with token data per INV-002), and states the threshold comparison (200,000 tokens).
- **Violated when**: Passive mode calibration display omits token data
- **Test approach**: unit — grep cspec SKILL.md for actual_tokens in calibration arithmetic display and 200,000 threshold comparison

### INV-005: Graceful handling of missing actual_tokens in non-token contexts
- **Type**: must
- **Category**: data-integrity
- **Statement**: If a calibration entry is missing the `actual_tokens` field (entries written before this feature), /cspec does not error, warn, or skip the entry for QA rounds / BLOCKING findings arithmetic. The entry participates normally in all non-token calculations. It is only excluded from the token-specific average (per INV-002).
- **Violated when**: A calibration entry without actual_tokens causes an error, is skipped entirely, or is excluded from QA/findings arithmetic
- **Test approach**: unit — grep cspec SKILL.md for graceful handling of entries missing actual_tokens

### INV-006: /cmetrics shows per-feature token cost table
- **Type**: must
- **Category**: functional
- **Statement**: /cmetrics reads all `token-log-*.jsonl` files and produces a per-feature token cost table as a new section ("Per-Feature Token Cost") alongside the existing Phase Distribution table. Each row is one feature. Columns: feature slug, total tokens, tokens by skill category (matching existing cmetrics categories: TDD, Review, Verification, Audit, Other), and QA rounds. The phase-to-category mapping uses the JSONL `skill` field: ctdd→TDD, creview/creview-spec→Review, cverify→Verification, caudit→Audit, all others→Other. The table is sorted by total tokens descending. If no token logs exist, the section is skipped with a note.
- **Violated when**: /cmetrics does not produce a per-feature breakdown table, the table uses a different category taxonomy than the existing Phase Distribution, or the phase mapping is absent
- **Test approach**: unit — grep cmetrics SKILL.md for per-feature token table with skill-based category mapping

### INV-007: /cmetrics shows token trend across features
- **Type**: must
- **Category**: functional
- **Statement**: /cmetrics computes a token trend by splitting completed features chronologically into two halves (first N/2 vs last N/2; for odd counts, the middle feature goes to the first half). It computes the average tokens per feature for each half. If the second half average exceeds the first half average by more than 20%, the trend is "growing". If it is more than 20% lower, the trend is "shrinking". Otherwise, the trend is "stable". If fewer than 4 features have token data, the trend is "insufficient data". This replaces existing metric #7's vague "compare with previous metrics" approach with a self-contained computation.
- **Violated when**: /cmetrics does not compute a token trend, uses a different method than first-half/second-half, or omits the 20% threshold
- **Test approach**: unit — grep cmetrics SKILL.md for first-half/second-half comparison, 20% threshold, and "insufficient data" for fewer than 4 features

### INV-008: Token threshold is a behavioral constant
- **Type**: must
- **Category**: functional
- **Statement**: The 200,000 token threshold is documented in the cspec SKILL.md, not stored in workflow-config.json. This follows the same pattern as the 3 QA rounds and 8 BLOCKING findings thresholds (PRH-002 from intensity-calibration spec).
- **Violated when**: The token threshold appears in workflow-config.json or its templates
- **Test approach**: unit — grep workflow-config templates for token_threshold or similar (must find none)

## Prohibitions

### PRH-001: No changes to token-tracking hook
- **Statement**: The token-tracking PostToolUse hook (`hooks/token-tracking.sh`) must not be modified by this feature. Data collection is unchanged — only data consumption changes.
- **Detection**: git diff hooks/token-tracking.sh must be empty
- **Consequence**: Breaking the hook affects all future data collection

### PRH-002: actual_tokens never used as a standalone signal
- **Statement**: Token data must remain a post-signal modifier within the calibration system (ABS-005). It must not become a 5th detection signal in Step 7's signal evaluation. The intensity detection architecture remains 4 signals + post-signal modifiers.
- **Detection**: grep cspec SKILL.md Step 7 section for token/cost references (must find none outside Step 7b)
- **Consequence**: Adding a 5th signal changes the detection architecture, which has been stable across 4 features

## Risks

- **Threshold tuning**: 200K tokens is a guess based on current feature sizes (~30K-100K typical, high-intensity features 150K-300K). If every feature exceeds 200K after model improvements increase token output, the threshold becomes useless. Accepted for v1 — the threshold is easy to adjust and the calibration system already handles threshold drift via the recency window.
- **Token undercounting**: The token-tracking hook only captures Agent tool subagent tokens, not orchestrator-session tokens. `actual_tokens` systematically undercounts true feature cost. Accepted — the threshold applies to tracked subagent tokens only, and the signal is relative (comparing features against each other), not absolute.

## Open Questions

None.

## Review Notes

- F1: INV-001 now specifies branch_slug (not task-slug) for token log file location, matching the hook's naming convention
- F2: INV-001 now requires deterministic jq summation and line-by-line malformed line skipping
- F3: INV-006 aligned to existing cmetrics categories (TDD/Review/Verification/Audit/Other) with explicit skill-based mapping
- F4: INV-002 and INV-005 updated — token arithmetic excludes zero/absent entries; QA/findings arithmetic unchanged
- F5: INV-007 now specifies 20% threshold, odd-count rounding, replaces existing metric #7
- F6: INV-001 requires jq command, not LLM arithmetic
- F7: Scope updated to include ABS-006 documentation during /cupdate-arch; complexity budget updated
- F8: INV-006 clarified as additive "Per-Feature Token Cost" section alongside existing Phase Distribution
