---
title: "/cmodelupgrade"
parent: "High+ Intensity"
grand_parent: Skills
nav_order: 8
---

# /cmodelupgrade — Harness Regression Report

> Compare the current `{model}+HARNESS_VERSION` combination's pipeline metrics against a stored baseline and produce a per-feature regression report. Strictly advisory — never auto-applies anything.

## When to Use

- After Anthropic ships a new model (e.g., 4.6 → 4.7) and you want to know whether the workflow's behavior has shifted on your project
- When `/cspec` or `/cstatus` surfaces a `version_bumped` advisory (the maintainer has bumped `HARNESS_VERSION` in `scripts/harness-fingerprint.sh` because a behavioral change was observed)
- To capture an initial baseline for the current model+version with `--capture-baseline` (requires at least 2 qualifying runs at the current key, plus human confirmation)
- **Not for:** auto-migrating agents, modifying skill files, or making any change to the workflow. The report is informational; follow-up is human-driven.

## How It Fits in the Workflow

This skill sits outside the standard feature pipeline. It's invoked manually after a model upgrade or when the harness fingerprint mechanism flags a change. The fingerprint is computed at every `/cspec` Step -1 by `scripts/harness-fingerprint.sh` — when the literal `{model_name}|{HARNESS_VERSION}` string differs from the stored value, `/cspec` and `/cstatus` surface a one-time advisory pointing here.

## What It Does

1. **Reads the current fingerprint** via `bash .correctless/scripts/harness-fingerprint.sh check` — extracts `model` and `harness_version`, constructs the lookup key `{model}|{HARNESS_VERSION}`
2. **Reads four data sources per feature**: `intensity-calibration.json` (qa_rounds, total_tokens), `cost-*.json` glob (total_cost_usd from ABS-026 cost artifacts — never hardcoded list), `workflow-state-*.json` (phase_count), `model-baselines.json` (the stored baseline for the current key)
3. **Three-tier bootstrap lookup**: exact-match pool (entries tagged with current `harness_version`) → pre-fingerprint pool (entries from before /cverify recorded `harness_version`, used with explicit `"pre-fingerprint baseline"` label) → no-baseline mode (clear message, exit 0 — never compares against zero)
4. **Renders a per-feature regression table**: up to N=5 features, columns for baseline/current/delta/percent across qa_rounds, total_tokens, total_cost_usd, phase_count
5. **`--capture-baseline` mode**: aggregates per-feature metrics from the most recent N=5 qualifying runs, requires ≥2 runs (incomplete runs excluded), surfaces source slugs to the human for explicit confirmation before writing `model-baselines.json`. The `--auto-confirm` flag is testing-only and emits a `bootstrap_auto_confirmed` audit-trail entry when used

## Example

You ran `/cspec` for a new feature and saw:

```
Harness has changed (model=claude-opus-4-7 version=2). Run /cmodelupgrade to compare metrics against baseline.
```

You finish the feature and then run `/cmodelupgrade`:

```
Lookup key: claude-opus-4-7|2
Pool: exact-match (3 qualifying runs)
Baseline: claude-opus-4-7|1 (5 features, captured 2026-04-15)

| Feature              | qa_rounds Δ | tokens Δ      | cost Δ    | phases Δ |
| feature/auth-redirect | +1 (+50%)  | +180k (+22%) | +$1.10    |  0       |
| feature/email-queue   |  0          | +95k (+12%)  | +$0.40    |  0       |
| feature/rate-limit    |  0          | +210k (+28%) | +$1.55    |  0       |

Token cost delta is consistent at +20-28% across all 3 features. Possible
harness change: increased verbosity in spec/review phases. Consider running
/caudit to look for systemic patterns, or inspect agents/*.md if regressions
appear in a specific agent type.
```

You decide whether the deltas warrant a deeper investigation. The skill never spawns subagents and never auto-applies any fix.

## What It Reads / Writes

| Reads | Writes |
|-------|--------|
| `.correctless/meta/harness-fingerprint.json` (read-only — sole writer is the script) | `.correctless/meta/model-baselines.json` (with `--capture-baseline` only, schema_version: 1 from creation) |
| `.correctless/meta/intensity-calibration.json` (qa_rounds, total_tokens, harness_version) | `.correctless/artifacts/cmodelupgrade-{slug}.md` (the rendered report) |
| `.correctless/artifacts/cost-*.json` (total_cost_usd glob) | (no other writes — TB-004 / PRH-003 forbid auto-application) |
| `.correctless/artifacts/workflow-state-*.json` (phase_count) | |
| `.correctless/test-features/baseline.md` (controlled-baseline reference feature) | |

## Common Issues

- **"No baseline available"**: Either no qualifying runs have been recorded for the current `{model}+{HARNESS_VERSION}` key, or the baseline file is missing. Run `/cmodelupgrade --capture-baseline` after running `/cauto` on `.correctless/test-features/baseline.md` (scaffolded by `/csetup`).
- **"need at least 2 qualifying runs"**: `--capture-baseline` requires ≥2 complete runs at the current key. Pipeline-aborted runs marked `incomplete` in their workflow state are excluded — degenerate runs cannot poison the baseline.
- **`pre-fingerprint baseline` label**: When only entries from before the fingerprint mechanism was added qualify, the report uses them with this explicit label. The exact-match pool (entries tagged with `harness_version`) is preferred whenever it exists. Pools are never mixed.
- **`schema_version` mismatch on `model-baselines.json`**: BND-004's fail-open path emits a one-line stderr warning, treats the baseline as missing, and prompts re-capture. Never errors, never blocks.

## Constraints

- **Strictly advisory** (PRH-001/PRH-003). The exit-code contract is `0` (success including no-baseline message), `1` (unexpected error), `2` (unrecoverable corruption with no migration). The report never auto-triggers any migration, agent file change, or skill modification.
- **Per-feature granularity only**. Per-skill granularity is deferred until audit-trail records per-phase qa_rounds and token-tracking can backfill from cost artifacts (both upstream changes are out-of-scope here).
- **Sole writer of `model-baselines.json`**. The fingerprint file itself (`harness-fingerprint.json`) is read-only here — sole writer is `scripts/harness-fingerprint.sh`. Both files have a write-target guardrail via `hooks/sensitive-file-guard.sh`, which blocks Edit/Write AND direct Bash redirect/writer-command destinations (`>`, `tee`, `cp`, `sed -i`, …). This is a guardrail for accidental/naive writes; interpreter-mediated and git-mediated out-of-band writes are accepted non-goals (AP-040); see ABS-045.
- **No subagents** (ME-12 of harness-fingerprint spec). All aggregation, comparison, and report rendering happens inline. The `Task` tool is excluded from `allowed-tools`.
- **Path discovery via `workflow-advance.sh status`** for every artifact (AP-025 / PMB-004). Never assumes the orchestrator already knows artifact paths from conversation context.
