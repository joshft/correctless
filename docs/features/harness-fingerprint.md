# Harness Fingerprint + Model Upgrade Detection

> Detect when Anthropic ships a new model or updates harness defaults silently — and produce a regression report against a captured baseline. Spec: `.correctless/specs/harness-fingerprint.md`. Architecture: ABS-027, ABS-028.

## What It Does

Correctless's correctness model implicitly depends on a single Anthropic model version's uncontracted behavioral defaults — length caps, parallel-tool-call preferences, anti-defensive code priors, in-context skill inlining. When the model or the harness changes, the workflow can regress silently. The 4.6 → 4.7 audit (`OPUS_4_7_MIGRATION.md`) made this concrete: 3 distinct findings, none surfaced by metrics, none caught by tests.

This feature ships two bundled mechanisms:

1. **Deterministic fingerprint** — `scripts/harness-fingerprint.sh` computes the literal string `"{model_name}|{HARNESS_VERSION}"` (no hashing — debuggable by reading the file directly) where `HARNESS_VERSION` is a manually-bumped integer constant maintained by the human. `/cspec` invokes the script at Step -1, advisory-only. When the fingerprint differs from the stored value, a one-time `version_bumped` notification is shown.
2. **`/cmodelupgrade` skill** — compares the current `{model}+{HARNESS_VERSION}` combination's per-feature pipeline metrics against a stored baseline and emits a regression report. Read-only on the fingerprint store; sole writer of the baseline file.

## How It Works

```
┌─────────────────┐      ┌────────────────────────┐      ┌──────────────────────┐
│ /cspec Step -1  │ ───▶ │ harness-fingerprint.sh │ ───▶ │ harness-fingerprint  │
└─────────────────┘      │ (sole writer)          │      │ .json                │
                         └────────────────────────┘      └──────────────────────┘
                                  │                                 │
                                  ▼                                 ▼
                         ┌────────────────────────┐      ┌──────────────────────┐
                         │ harness-notified-      │      │ /cstatus advisory    │
                         │ {session-id}.flag      │      │ line                 │
                         │ (per-session dedup)    │      └──────────────────────┘
                         └────────────────────────┘                 │
                                                                    ▼
                                                          ┌──────────────────────┐
                                                          │ /cmodelupgrade       │
                                                          │ (sole writer of      │
                                                          │  model-baselines)    │
                                                          └──────────────────────┘
```

## Configuration

No project-level config knobs. The bumped integer constant lives in `scripts/harness-fingerprint.sh`:

```bash
# ============================================================================
# HARNESS_VERSION — INTEGER CONSTANT (PRH-006)
#
# Bumped manually by the maintainer when an Anthropic harness update is
# observed (see OQ-006 in spec for heuristic). Bumping this value triggers a
# version_bumped signal on the next /cspec invocation in any open session.
# DO NOT bump autonomously — sensitive-file-guard protects this script from
# autonomous Edit/Write once committed.
# ============================================================================
HARNESS_VERSION=1
```

When to bump (OQ-006 heuristic):
1. `/cmodelupgrade` regression report shows >20% delta in any metric across consecutive same-model+version runs, OR
2. The maintainer notices a behavioral change manually (spec quality drops, QA round counts climb without explanation, a 4.7-style audit pattern surfaces)

## Files Touched / Added

| Path | Role |
|------|------|
| `scripts/harness-fingerprint.sh` | Fingerprint script (sole writer of fingerprint file) |
| `skills/cmodelupgrade/SKILL.md` | Regression report skill (sole writer of baseline file) |
| `templates/test-features/baseline.md` | Reference feature template scaffolded by `/csetup` Step 2.6 |
| `.correctless/meta/harness-fingerprint.json` | Fingerprint store (`{fingerprint, harness_version, model, timestamp, schema_version}`) |
| `.correctless/meta/model-baselines.json` | Baseline metrics keyed by `{model}+{HARNESS_VERSION}` (`schema_version: 1`) |
| `.correctless/test-features/baseline.md` | User-editable scaffolded reference feature (idempotent — `/csetup` never overwrites) |
| `.correctless/artifacts/harness-notified-{session-id}.flag` | Per-session notification dedup |
| `scripts/lib.sh` | Adds `get_current_session_id()` (cross-platform via `ps -o lstart=` → `/proc/{pid}/stat` → PID fallback) and `locked_update_file()` (generic locked read-modify-write) |

## Integration Points

- `/cspec` Step -1 — runs `harness-fingerprint.sh check` before Socratic brainstorm (marker: `<!-- correctless:harness-fingerprint:invocation -->`)
- `/cstatus` Section 3a — emits the `Harness: model={X} version={Y} fingerprint={hash[:8]} status={ok|new|version-bumped}` advisory line
- `/cverify` — writes `harness_version` field on every new calibration entry (BND-005 prerequisite — without this, the post-fingerprint pool stays empty and the three-tier lookup collapses)
- `/csetup` Step 2.6 — scaffolds `templates/test-features/baseline.md` to `.correctless/test-features/baseline.md` (idempotent guard via `[ ! -f ]`)
- `/cauto` Auto Run Report — surfaces any `harness-notified-*.flag` files in "What to Review First" (INV-016)
- `hooks/sensitive-file-guard.sh` — protects `scripts/harness-fingerprint.sh`, `.correctless/meta/harness-fingerprint.json`, and `.correctless/meta/model-baselines.json` from non-sanctioned writers (Edit/Write AND Bash redirects)

## Examples

### Verify the script is wired (smoke check)

```bash
bash scripts/harness-fingerprint.sh check
# fingerprint=claude-opus-4-7|1
# status=unchanged
# model=claude-opus-4-7
# harness_version=1
# notified=false
```

### Capture an initial baseline

```bash
# Run /cauto on the controlled-baseline reference feature first
# (after /csetup has scaffolded .correctless/test-features/baseline.md)
/cauto

# Then capture the baseline (requires ≥2 qualifying runs, surfaces source slugs)
/cmodelupgrade --capture-baseline
```

### Inspect the fingerprint state

```bash
cat .correctless/meta/harness-fingerprint.json
# {
#   "fingerprint": "claude-opus-4-7|1",
#   "harness_version": 1,
#   "model": "claude-opus-4-7",
#   "timestamp": "2026-04-26T22:17:39Z",
#   "schema_version": 1
# }
```

## Known Limitations

- **`model_name` is not tamper-resistant** (EA-005) — sourced from Claude Code's environment. An autonomous agent with write access to env or session metadata could spoof its own model name. Single-user dev tool threat model accepts this.
- **Mid-session changes are not detected** (EA-003) — sessions started before a HARNESS_VERSION bump continue with the old fingerprint until restart.
- **Per-skill granularity is out of scope** — report is per-feature only. Per-skill requires audit-trail to record per-phase qa_rounds and token-tracking to backfill from cost artifacts (both upstream changes deferred).
- **No automatic detection of behavioral change** (EA-004) — bumping `HARNESS_VERSION` requires human judgment. The mechanism is reactive to its own observations (>20% metric shift within one key surfaces in `/cmodelupgrade`), not predictive.

## Test Coverage

`tests/test-harness-fingerprint.sh` — 110 passed, 0 failed. Covers INV-001..019, PRH-001..006, BND-001..005. Cross-suite coverage in `test-architecture-drift.sh` (ABS-027 presence), `test-sensitive-file-guard.sh` (HF-002 redirect-block + HF-006 Edit-block), `test-allowed-tools-check.sh` (cmodelupgrade frontmatter), `test-scripts-namespace-migration.sh` (HF-PMB003: harness-fingerprint.sh installed), and `test-skill-path-discovery.sh` (R-005(g)-cmodelupgrade).

## See Also

- Spec: `.correctless/specs/harness-fingerprint.md`
- Verification: `.correctless/verification/harness-fingerprint-verification.md`
- Architecture: ABS-027 (fingerprint store contract), ABS-028 (test-features baseline contract) in `.correctless/ARCHITECTURE.md`
- Skill: [`/cmodelupgrade`](../skills/cmodelupgrade.md)
