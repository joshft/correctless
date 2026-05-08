---
name: cmodelupgrade
description: Compare current model+HARNESS_VERSION pipeline metrics against stored baselines and produce a per-feature regression report. Use after Anthropic ships a model upgrade or when /cspec/cstatus surfaces a harness version_bumped advisory. Read-only on the fingerprint store; writes only the baseline file.
allowed-tools: Read, Grep, Glob, Bash(jq*), Bash(*workflow-advance.sh*), Bash(*harness-fingerprint*), Bash(git*), Write(.correctless/meta/model-baselines.json), Write(.correctless/artifacts/cmodelupgrade-*)
interaction_mode: hybrid
---

# /cmodelupgrade — Harness Regression Report

> **Shared constraints apply.** Before executing, read `_shared/constraints.md` from the parent of this skill's base directory. All constraints there apply to this skill.

You are the model upgrade agent. Your job: compare the current `{model}+{HARNESS_VERSION}` combination's per-feature pipeline metrics against stored baselines and produce a regression report. The report is **advisory only** (PRH-003 — never auto-apply, never auto-trigger migrations). All actions following the report require explicit human follow-up.

**This skill spawns no subagents — all aggregation, comparison, and report rendering happens inline (ME-12 of harness-fingerprint spec, distinct from ABS-010 / AP-013).**

## Source attribution

This skill implements harness-fingerprint spec INV-007, INV-008, INV-009, INV-009b, INV-012, INV-014, INV-019, BND-004, BND-005, and PRH-003. AP-025 / PMB-004 (skill must use explicit path discovery, never assume the orchestrator knows artifact paths from prior conversation context) governs every artifact read below.

## Step 0: Path discovery (AP-025 / PMB-004 mitigation)

Every artifact path used by this skill is discovered via `workflow-advance.sh status` or constructed via documented globs — never assumed from conversation context. Run:

```bash
.correctless/hooks/workflow-advance.sh status
```

Read the output to extract `Branch:`. Then derive `branch_slug` via:

```bash
source .correctless/scripts/lib.sh
SLUG="$(branch_slug)"
```

Use `$SLUG` to construct the per-branch artifact paths listed in Step 2. Never assume `$SLUG` from conversation history — derive it explicitly here. This is the direct mitigation of **AP-025 / PMB-004**: "Skill says 'Read the spec artifact' without path discovery".

## Step 1: Read the current harness fingerprint

Run the fingerprint script and extract the current `model` and `harness_version`:

```bash
bash .correctless/scripts/harness-fingerprint.sh check
```

Parse the `model=...` and `harness_version=...` lines from stdout. Construct the lookup key:

```
KEY="${model}|${harness_version}"
```

This **literal string** (no hashing — INV-001 dropped hashing in round 2) is the same string that appears in `.correctless/meta/harness-fingerprint.json`'s `fingerprint` field and is also used as the **exact-match** key in `.correctless/meta/model-baselines.json`'s `baselines` map (INV-008). Lookup is exact-match only — partial-key matches forbidden. The fingerprint and the baseline key are the same literal model_name|HARNESS_VERSION string by construction (HI-1 unification).

## Step 2: Read the four data sources (per-feature granularity)

Per INV-009 (per-feature regression report — NOT per-skill, which is explicitly out-of-scope until upstream producers exist):

1. `.correctless/meta/intensity-calibration.json` — `total_qa_rounds` and `total_tokens` per calibration entry (cverify writes `harness_version` per BND-005 round-2 disposition)
2. `.correctless/artifacts/cost-*.json` — `total_cost_usd` per ABS-026 (cost artifact contract). **Read across all branches via Bash glob, NOT a hardcoded slug list per ME-14 / AP-024**:

   ```bash
   ls .correctless/artifacts/cost-*.json 2>/dev/null
   ```

3. `.correctless/artifacts/workflow-state-*.json` — `phase_count` (count of distinct phases recorded)
4. `.correctless/meta/model-baselines.json` — the stored baseline metrics for the current `KEY`

**Cost artifact field path**: the canonical field is `total_cost_usd` at the top level of `cost-{slug}.json` (ABS-026, validated against `compute-session-cost.sh` schema during /ctdd RED via a structural test that asserts producer and consumer agree on the field path — same pattern as ABS-023 entrypoints contract, HI-2 round-2).

**Glob never lists**: every `cost-*.json` read must use a glob (`compgen`, `ls`, or jq's array iteration), never a hardcoded slug list. PMB-003 / AP-024 root cause: hardcoded lists go stale silently.

## Step 3: Three-tier bootstrap lookup (BND-005)

Aggregate per-feature metrics from `intensity-calibration.json` using an **explicit three-tier lookup**:

1. **Exact-match pool**: calibration entries where `harness_version` field is present AND equals the current `HARNESS_VERSION` constant
2. **Pre-fingerprint pool**: calibration entries where `harness_version` field is absent (entries written before /cverify was extended to record the field)
3. **No-baseline mode**: neither pool has any entries

**Resolution priority**: when both pools exist, prefer the **exact-match pool** (more accurate). When only the **pre-fingerprint pool** exists, use it with the explicit `"pre-fingerprint baseline"` label in the report. When neither pool exists, emit the no-baseline message per INV-009b. **Do not mix pools** — that would produce misleading averages. The "exact-match" / "pre-fingerprint" / "no-baseline" terminology is fixed; do not paraphrase.

## Step 4: Bootstrap mode — capture-baseline flow (INV-014)

When invoked with `--capture-baseline`, this skill:

1. Aggregates per-feature metrics from the most recent N=5 feature runs at the current model+version (default sample window — ME-11 round-2 disposition: enough for variance estimation, recent enough to reflect current state).
2. Requires **at least 2 qualifying runs (M=2)** — if fewer, surface "need at least 2 qualifying runs at current model+version to capture a baseline".
3. **Quality filter (LO-2 round-2)**: source runs marked `incomplete` in their workflow state (pipeline aborted mid-run) are **excluded** from the qualifying pool. Degenerate runs cannot poison the baseline (RT-005 mitigation).
4. Surfaces source feature slugs + durations + sample size to the **human for explicit confirmation** before writing the baseline file. Mandatory human confirmation prompt, no shortcuts.
5. If the human declines, the baseline is not saved (status: `bootstrap_declined`).
6. If `--auto-confirm` is also passed (testing-only flag, documented as such), bypasses the prompt AND writes an `audit-trail` entry of type `bootstrap_auto_confirmed` so the bypass is traceable. Production callers should never use `--auto-confirm`.

Example: `/cmodelupgrade --capture-baseline --auto-confirm` (testing only — bypasses human confirmation prompt and emits `bootstrap_auto_confirmed` audit entry).

## Step 5: Write the baseline file (INV-019 — schema_version from creation)

When persisting a captured baseline, the JSON file at `.correctless/meta/model-baselines.json` MUST include `"schema_version": 1` at the top level on the **first write**. On subsequent writes, **preserve** the field — never remove or modify `schema_version` once present. BND-004's evolution mechanism reads this field on every load.

Schema:

```json
{
  "schema_version": 1,
  "baselines": {
    "claude-opus-4-7|1": {
      "metrics": {
        "feature-slug-1": {"qa_rounds": 2, "total_tokens": 250000, "total_cost_usd": 1.42, "phase_count": 6},
        "feature-slug-2": {...}
      },
      "sample_size": 2,
      "captured_at": "2026-04-26T14:00:00Z"
    }
  }
}
```

**PRH-004**: no prose fields anywhere. Only schema_version, baselines map, metrics map, sample_size, captured_at. Never raw probe responses or system-prompt content.

## Step 6: Render the regression report

For the current `KEY`, produce one row per feature (NOT per skill — per-skill granularity deferred until audit-trail records per-phase qa_rounds and token-tracking can backfill from cost artifacts; both out-of-scope here per CR-1 round-2). Up to N=5 features. Columns:

| Feature | Baseline qa_rounds | Current | Δ | % | Baseline tokens | Current | Δ | % | Baseline cost | Current | Δ | % | Baseline phases | Current | Δ | % |

Each row references actual numeric deltas computed from input files — no mock of any data-source-parsing logic.

## Step 6a: No-baseline mode (INV-009b — never compare against zero)

When the baseline is missing, empty, or has zero qualifying entries for the current model+version, the report MUST display:

```
No baseline available — capture one with /cmodelupgrade --capture-baseline (runs /cauto on .correctless/test-features/baseline.md)
```

and exit 0. **Reports that render against zero or null baselines are forbidden** — they're the DA-004 self-referential-metrics class. Never compare current values against zero or null baselines without explicitly rendering the no-baseline state. This guards against DA-004 (self-referential metrics) and HP-5.

## Step 7: BND-004 — schema_version mismatch handling

On every load of `.correctless/meta/model-baselines.json`, validate the `schema_version` field. On mismatch (e.g., the file was written by an older Correctless version that used a different schema):

1. Emit a one-line warning to stderr noting the mismatch (e.g., `warning: model-baselines.json schema_version=2 found, expected 1 — treating baseline as missing`)
2. Treat the baseline as missing
3. Prompt the user to re-capture (via `/cmodelupgrade --capture-baseline`)
4. **Fail-open + prompt re-capture** — never error, never block

## Exit codes (HI-3 round-2)

The exit-code contract for `/cmodelupgrade` is:

- **exit 0** — completed successfully (includes no-baseline message per INV-009b — exit 0 is the right answer when there's nothing to compare against)
- **exit 1** — unexpected error (read failure on producer files, jq error, etc.)
- **exit 2** — unrecoverable (baseline file corrupt and migration unavailable)

The exit codes 0/1/2 are the gate for `/cauto` integration. Always document any new failure mode against this contract.

## Autonomous Defaults

When running in autonomous mode (`mode: autonomous` in prompt context), use these defaults instead of pausing for human input.
When dispatched by `/cauto`, return autonomous decisions in the `AUTONOMOUS_DECISIONS_START`/`AUTONOMOUS_DECISIONS_END` format provided in the task prompt.

- **AD-001**: Upgrade scope — apply all compatible upgrades (default). Rationale: compatible upgrades have passed the regression report checks and are safe to apply.
- **AD-002**: Breaking model changes — `escalate: always`. Default if deferred: skip breaking changes. Rationale: breaking model changes can invalidate baselines and need human assessment of downstream impact.

## Constraints

- **Never write to `.correctless/meta/harness-fingerprint.json`** (INV-007). The sole writer is `scripts/harness-fingerprint.sh`. This skill reads it via the `harness-fingerprint check` invocation in Step 1 — never via a Write or Edit. The `allowed-tools` frontmatter does not include the fingerprint write permission, so the harness-side guarantee is structural.
- **Never spawn subagents.** All work happens inline. The `Task` tool is excluded from `allowed-tools` (PRH-003 enforcement).
- **Never auto-apply recommendations** (PRH-003). The report is purely advisory. Migration follow-up requires explicit human invocation of additional skills.
- **Never block on the report.** If anything goes wrong during aggregation, log the issue and continue with the rest of the report — partial output is more useful than no output.

## Antipattern integration

Direct mitigation of:
- **AP-022** (dead-code-in-security-paths) — the `Write(.correctless/meta/model-baselines.json)` permission is in the allowed-tools frontmatter and exercised by Step 5; sensitive-file-guard structurally blocks all other writers (PRH-002).
- **AP-024** (hardcoded file list instead of glob) — Step 2's cost artifact read MUST glob `cost-*.json`, never hardcode a slug list. PMB-003 root cause.
- **AP-025 / PMB-004** (skill references workflow artifact by concept without path discovery) — Step 0 derives every artifact path via explicit `workflow-advance.sh status` + `branch_slug` resolution. No conversation-context assumptions.
- **DA-004** (self-referential metrics) — Step 6a forbids rendering against zero/null baselines.

## After report runs

The report is presented to the human. They decide what to do — possible follow-up skills include `/caudit` (codebase sweep), `/cdebug` (investigate a specific regression), or manual inspection of `agents/*.md` if regressions appear consistently in a particular agent type. **Never auto-trigger any of these.**
