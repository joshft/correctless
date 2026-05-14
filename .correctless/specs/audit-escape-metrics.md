# Spec: Audit Findings as Escape Metrics

## Metadata
- **Created**: 2026-05-08T16:00:00Z
- **Status**: approved
- **Impacts**: ABS-029 (additive schema — optional `escape_type` field in findings entries)
- **Branch**: feature/audit-escape-metrics
- **Research**: null
- **Task**: audit-escape-metrics
- **Recommended-intensity**: standard
- **Intensity**: high
- **Intensity reason**: no detection signals triggered (standard); raised to high by project floor (`workflow.intensity: "high"`)
- **Override**: none

## What

Reframe `/caudit` findings as pipeline escapes rather than "post-merge bugs reported by users." The current bug escape rate (0% from `workflow-effectiveness.json`) conflates "no one reported a bug" with "no bugs exist." `/caudit` findings are defects that passed per-feature review, QA, and verification — the textbook definition of an escape. This feature adds an escape gate taxonomy (per-feature / audit / production), root-cause classification (implementation escape vs spec escape), severity-weighted scoring, and per-cycle tracking to `/cmetrics`. The metrics are informational — consumed by humans deciding where to focus scrutiny, not fed into auto-adjustment.

## Rules

- **R-001** [unit]: `audit-record.sh write-round` accepts findings JSON where each `findings[]` entry MAY include an `escape_type` field with values `implementation`, `spec`, or `non-escape`. The writer validates each entry's `escape_type` during the merge step (vocabulary check per INV-002) — iterating through `findings[]` entries and rejecting the entire payload if any entry has an invalid value. When `escape_type` is absent or `null`, it defaults to unclassified. Existing round-JSON files without `escape_type` remain valid — consumers treat missing field as unclassified.

- **R-002** [unit]: `/cmetrics` computes escape counts per audit cycle by reading round-JSON files from `.correctless/artifacts/findings/`. An "audit cycle" is a set of round-JSON files sharing the same `preset` and `date`. Escape count = number of findings with a non-null `severity` field not equal to `"info"` (info findings are not counted as escapes). Findings without a `severity` field are excluded from escape counts and weighted scoring.

- **R-003** [unit]: `/cmetrics` computes a severity-weighted escape score per audit cycle using weights: critical=5, high=3, medium=2, low=1, info=0. Severity matching is case-insensitive — consumers normalize to lowercase before applying the weight mapping. The score is the sum of `weight(severity)` across all findings with a valid severity field that is not `"info"`. The info severity is included for forward compatibility — current audit presets use critical/high/medium/low.

- **R-004** [unit]: `/cmetrics` reports escape breakdown by root cause: implementation escapes (code violates spec), spec escapes (spec was too permissive), and unclassified (no `escape_type` field). The breakdown uses the `escape_type` field from round-JSON findings. Missing or null `escape_type` is counted as "unclassified."

- **R-005** [unit]: `/cmetrics` escape rate section replaces the current single "Bug escape rate" line with a three-gate breakdown:
  - Per-feature escapes: issues caught by a later per-feature gate (derived from qa-findings files — count of BLOCKING findings across all qa-findings-*.json; NON-BLOCKING and UNCERTAIN findings are excluded since they represent advisory observations, not escaped defects). Note: QA findings use BLOCKING/NON-BLOCKING/UNCERTAIN severity vocabulary, distinct from audit findings' critical/high/medium/low/info vocabulary.
  - Audit escapes: issues caught by `/caudit` (from round-JSON findings, excluding info severity, case-insensitive per R-003)
  - Production escapes: from `workflow-effectiveness.json` `post_merge_bugs` (unchanged source)

- **R-006** [unit]: `/cmetrics` tracks escape trends across audit cycles. For each preset, compare the current cycle's weighted escape score to the previous cycle's score. Report trend as improving (score decreased), stable (score change <= 20%), or regressing (score change > 20%). When fewer than 2 cycles exist for a preset, report "insufficient data for trend" — this covers both single-finding cycles and first-ever cycles.

- **R-007** [unit]: `/cmetrics` reports severity distribution per audit cycle as a table: count of CRITICAL, HIGH, MEDIUM, LOW findings. Distribution shift from previous cycle noted when available.

- **R-008** [unit]: When no round-JSON files exist (no audit has been run), the entire escape metrics section is dormant — no error, no warning, just omitted from output. Follows PAT-019.

- **R-009** [unit]: The `build-dashboard.sh` Escape Metrics section reads the latest `/cmetrics` artifact (`.correctless/artifacts/metrics-*.md`). When no metrics artifact exists, the dashboard section is dormant.

- **R-010** [unit]: Each `/caudit` specialist agent includes `escape_type` (`implementation`, `spec`, or `non-escape`) in its finding submission alongside severity. The triage agent validates the classification during finding triage — rejecting invalid values and defaulting to `implementation` when ambiguous. `/caudit` passes the validated classification to `audit-record.sh write-round` during persistence. Classification is distributed across the audit (one decision per finding at submission time), not batched after convergence.

## Won't Do

- **Auto-adjustment of intensity based on escape data.** Escape metrics are informational. If this changes, it's a separate feature that extends ABS-005 (calibration).
- **Implied outstanding issues calculation.** The `audit_escapes / catch_rate` estimate requires multiple audit cycles to calibrate. Dropped per brainstorm.
- **Per-feature escape tracking within the per-feature pipeline.** "Per-feature escapes" uses existing qa-findings data. No new tracking within `/ctdd`.
- **Retroactive classification of historical findings.** Existing round-JSON files remain unclassified (`escape_type: null`). Classification applies to future audit runs only.
- **Changes to the phase-transition gate (cmd_audit_done).** The ABS-029 contract is unchanged. Classification is additive metadata, not a gate precondition.

## Risks

- **Classification accuracy** — LLM judgment on "implementation vs spec escape" may be inconsistent across audit runs. Mitigation: the `unclassified` category is always available; classification is advisory, not gated. Trend data across cycles will show whether classification is stable enough to be useful.
  - Accept (recommended) — classification is advisory; inconsistency produces noise but no incorrect gating decisions.

- **Round-JSON schema evolution** — adding `escape_type` to findings changes the schema. Mitigation: the field is optional with null default; existing consumers (`cmd_audit_done`, `/cmetrics` staleness, fix-diff-reviewer) ignore unknown fields. No breaking change.
  - Mitigate — R-001 specifies the field as optional with null default. Existing consumers are unaffected.

- **Metrics artifact size growth** — escape breakdown adds ~20 lines to the metrics output. Mitigation: trivial relative to existing metrics artifact size.
  - Accept — negligible impact.

## Complexity Budget
- **Estimated LOC**: ~80 (audit-record.sh flag parsing + cmetrics SKILL.md sections + build-dashboard.sh section)
- **Files touched**: ~4 (scripts/audit-record.sh, skills/cmetrics/SKILL.md, skills/caudit/SKILL.md, scripts/build-dashboard.sh)
- **New abstractions**: 0
- **Trust boundaries touched**: 0
- **Risk surface delta**: low

## Invariants

### INV-001: escape_type field is additive and optional
- **Type**: must
- **Category**: data-integrity
- **Statement**: The `escape_type` field in round-JSON `findings[]` entries is optional. Consumers must treat absent or null `escape_type` as "unclassified" and never fail on its absence.
- **Boundary**: ABS-029 (round-JSON schema)
- **Violated when**: A consumer errors, crashes, or produces incorrect output when `escape_type` is missing from a findings entry
- **Guards against**: null
- **Test approach**: unit
- **Risk**: medium
- **Enforcement**: unit test with round-JSON fixtures containing findings both with and without `escape_type`

### INV-002: escape_type vocabulary is closed
- **Type**: must
- **Category**: data-integrity
- **Statement**: Valid `escape_type` values are exactly: `implementation`, `spec`, `non-escape`, `null`. `audit-record.sh write-round` rejects any other value with exit 1 and a clear error message.
- **Boundary**: ABS-029 (sole writer contract)
- **Violated when**: A round-JSON file contains an `escape_type` value outside the vocabulary
- **Guards against**: null
- **Test approach**: unit
- **Risk**: low
- **Enforcement**: validation in audit-record.sh write-round — the merge step iterates through each `findings[]` entry and rejects the entire payload with exit 1 if any entry has an `escape_type` value outside the vocabulary

### INV-003: severity weight mapping is deterministic
- **Type**: must
- **Category**: functional
- **Statement**: The severity-to-weight mapping (critical=5, high=3, medium=2, low=1, info=0) is case-insensitive and produces identical weighted escape scores for identical input across invocations.
- **Boundary**: null
- **Violated when**: The same set of findings produces different weighted scores on different runs
- **Guards against**: null
- **Test approach**: unit
- **Risk**: low
- **Enforcement**: unit test with fixed input fixtures

### INV-004: dormant escape metrics follow PAT-019
- **Type**: must
- **Category**: functional
- **Statement**: When no round-JSON files exist, the escape metrics section is omitted entirely from `/cmetrics` output and the dashboard. No error, no warning, no placeholder text.
- **Boundary**: null
- **Violated when**: `/cmetrics` outputs an error, warning, or empty escape section when no audit data exists
- **Guards against**: null
- **Test approach**: unit
- **Risk**: low
- **Enforcement**: unit test running cmetrics escape computation against empty findings directory

## Prohibitions

### PRH-001: escape_type must not gate phase transitions
- **Statement**: The `escape_type` field must never be added as a precondition to `cmd_audit_done` or any other phase-transition command in `workflow-advance.sh`. Classification is informational metadata, not a workflow gate.
- **Detection**: grep workflow-advance.sh for `escape_type` — must find zero matches
- **Consequence**: Adding escape_type to the gate would block audit completion when classification is missing, breaking backward compatibility with existing round-JSON files and all projects that haven't upgraded

### PRH-002: escape metrics must not feed into intensity auto-adjustment
- **Statement**: Escape data must not be written to `intensity-calibration.json` or used by `/cspec` intensity detection signals. Escape metrics are consumed by humans only.
- **Detection**: grep cspec SKILL.md and intensity-calibration references for `escape` — must find zero matches in signal evaluation context
- **Consequence**: Auto-raising intensity based on audit escapes would create a ratchet effect — audits find things (by design), which raises intensity, which increases audit thoroughness, which finds more things

## Boundary Conditions

### BND-001: mixed-vintage round-JSON files
- **Boundary**: ABS-029
- **Input from**: filesystem (historical round-JSON files pre-dating this feature)
- **Validation required**: `escape_type` may be absent from any or all findings entries. Consumers must not assume the field exists.
- **Failure mode**: fail-open (treat as unclassified, include in raw count, exclude from root-cause breakdown)

### BND-002: first or single-finding audit cycle
- **Boundary**: null
- **Input from**: first-ever audit for a preset, or audit with only 1 finding
- **Validation required**: trend calculation (R-006) must handle first-ever cycles (no previous cycle to compare), cycles with 0 findings, and cycles with 1 finding — all without division-by-zero or percentage errors
- **Failure mode**: report "insufficient data for trend" when fewer than 2 cycles exist for a preset

## Open Questions

- ~~**OQ-001**: Should `/caudit` classification be per-finding or per-round?~~ Resolved: per-finding at specialist submission time (R-010).
