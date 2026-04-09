# Spec: Add skill field to token-tracking hook JSONL

## Metadata
- **Task**: token-tracking-skill-field
- **Recommended-intensity**: high
- **Intensity**: high
- **Intensity reason**: file path signal (hooks/), keyword signal (token)
- **Override**: none

## What

Add a `skill` field to the token-tracking PostToolUse hook's JSONL output. Currently the hook writes `phase` (a workflow concept like `tdd-impl`) but consumers (cmetrics, cverify) need `skill` (a tool concept like `ctdd`) for accurate category mapping. The hook derives `skill` from `phase` using a hardcoded mapping in the hook itself, keeping the state machine unchanged.

## Rules

- **R-001** [unit]: The hook's JSONL output includes a `skill` field derived from the `phase` field using this mapping: `spec` → `cspec`, `model` → `cmodel`, `review`/`review-spec` → `creview` (intentional grouping — both are review-category activities), `tdd-tests`/`tdd-impl`/`tdd-qa`/`tdd-verify` → `ctdd`, `done`/`verified` → `cverify`, `documented` → `cdocs`, `audit` → `caudit`, all others (including `none`) → `unknown`. The mapping is a bash `case` statement in the hook — not jq, not a config value, not sourced from the state file. Note: implementing this requires extracting `phase` from the state file into a bash variable before the jq call (the current hook extracts phase inside the jq pipeline at `.phase // "none"`).
- **R-002** [unit]: The `skill` field appears in the jq JSON construction block (the `'{...}'` template) as a string field alongside existing fields (`phase`, `feature`, `agent_description`, etc.). It must be passed to jq via `--arg` — never interpolated into the JSON template string.
- **R-003** [unit]: The phase-to-skill mapping function is defined in the hook file itself, not in `scripts/lib.sh` or any external file. This mapping is hook-private because no other bash script needs it. If a second bash consumer emerges, the mapping must move to lib.sh per ABS-001.
- **R-004** [unit]: When the `phase` field from the state file is empty, absent, or `none`, the `skill` field is `unknown`. When the `phase` field is an unrecognized value (not in the mapping), the `skill` field is `unknown`. In all these cases, the hook still produces a JSONL log entry (does not skip or abort).
- **R-005** [unit]: The existing 11 fields in the JSONL output (`timestamp`, `branch`, `phase`, `feature`, `agent_description`, `agent_type`, `input_tokens`, `output_tokens`, `total_tokens`, `total_cost_usd`, `duration_ms`) are all present in every log entry with unchanged names and semantics. No field is removed or renamed. The `skill` field is added alongside them.
- **R-006** [unit]: The `phase` field is preserved in every JSONL entry alongside the new `skill` field. Both fields coexist. The `phase` field's name and derivation logic (`.phase // "none"` from the state file) are unchanged.
- **R-007** [unit]: The hook continues to follow PAT-005 PostToolUse conventions: no `set -e`, fail-open on all errors, every operation guarded with `|| exit 0`, always exits 0.
- **R-008** [unit]: A sync test extracts all `update_phase` target values from `hooks/workflow-advance.sh` and verifies each appears in the hook's phase-to-skill case statement. Unmapped phases (falling through to `unknown`) are test failures. This prevents silent mapping drift when new phases are added.

## Won't Do

- Adding `skill` to the workflow state file — the state machine is unchanged
- Making the mapping configurable — hardcoded is simpler and matches how phase names are hardcoded
- Changing cmetrics SKILL.md to use `skill` as primary — already done in token-aware-intensity feature
- Modifying skill-level Token Tracking sections in SKILL.md files — those already include `skill`

## Risks

- **Mapping staleness**: If new phases are added to workflow-advance.sh, the mapping in the hook needs updating. Mitigated: R-008 sync test catches this at CI time. The `unknown` fallback provides graceful degradation until the mapping is updated.

## Post-Implementation

- Update ABS-006 in `.correctless/ARCHITECTURE.md` during /cupdate-arch: the `skill` field changes from "optional, added by skills" to "always present in hook-produced entries, derived from phase."

## Review Notes

- F1: Added `model` → `cmodel` to R-001 (was missing — workflow-advance.sh line 436)
- F2: Added R-008 mandatory sync test (was a suggestion in Risks, now a rule)
- F3: R-001 now acknowledges pipeline restructure (phase must be extracted to bash variable before jq)
- F4: R-003 now cites ABS-001 single-consumer exception instead of PAT-002
- F5: R-005 dropped "reordered" (unverifiable in JSON)
- F6: R-004 clarified "still produces a JSONL log entry" for all fallback cases
- F7: Added Post-Implementation section for ABS-006 update
- F8: R-001 clarifies `review`/`review-spec` → `creview` is intentional grouping

## Open Questions

None.
