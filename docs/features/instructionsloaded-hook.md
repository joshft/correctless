# InstructionsLoaded hook — direct rule-load observability

Feature B (FUTURE-001) of the path-scoped-rules-pat001 line. A fail-open
`InstructionsLoaded` telemetry hook records each time a `.claude/rules/*.md`
rule file is loaded into the agent's editing context, and a `/cwtf` section
presents those rule-load events beside `audit-trail` hook-edit entries so a human
can *see* whether a rule (e.g. `hooks-pretooluse.md`) was in context around a
hook edit — and classify a clause-5 violation themselves.

This **upgrades the PAT-001 measurement signal** from the indirect
git-archaeology proxy (accepted 2026-04-14) to direct runtime observation. It
does **not** re-open that accepted gate.

## What it does

- **`hooks/instructions-loaded.sh`** (registered on the `InstructionsLoaded`
  event, matcher `*`) appends one JSON line per `.claude/rules/*.md` load to
  `.correctless/meta/instructions-loaded.jsonl` (gitignored runtime telemetry).
  It is **fail-open**: missing `jq`/`lib.sh`/`canonicalize_path`, malformed or
  empty stdin, or an unwritable meta dir all → `exit 0` with no log. Exit codes
  are ignored by the harness for this event, so any non-zero exit would be dead
  behavior.
- **`hooks/audit-trail.sh`** gained an additive `session_id` field (from the
  harness stdin field — the same source the new hook reads) so the two logs can
  be shown side-by-side for the same session. This is a **display-alignment
  aid**, not a machine-join key.
- **`/cwtf` → "Rule-Load Observability"** reads both logs and presents raw
  evidence — rule-loads with timestamps + `trigger_file_path`, alongside
  hook-edits grouped per edit-session — with plain-language framing, a
  liveness/denominator line, and **no automated MG-001/MG-002 verdict** (the
  human classifies).

## Why no automated classifier

An earlier draft built a correlator that joined the two logs on
`session_id` + whole-second timestamp ordering + path match to auto-label each
hook edit MG-001 vs MG-002. Multi-agent review found ~8 CRITICAL/HIGH failure
modes concentrated in that one fragile cross-file join, every one biasing the
verdict optimistic (the "flying blind" / silent-telemetry class). Because this is
an advisory, forward-looking signal on an already-accepted gate, the join's risk
did not justify its value. The feature was scoped down to **raw observability the
human interprets** (PRH-005) — matching `/cwtf`'s "context, not judgment" ethos.

## Firing model (verified)

Confirmed empirically against the live harness (Claude Code 2.1.185, 2026-07-01):
opening a `.claude/rules/`-scoped file mid-session emits a **fresh, per-open
`path_glob_match`** event the first time that rule enters context (a rule already
resident at session start does not re-fire). This per-open model is what makes
per-edit observation meaningful. See `ENV-012` and the verification report for
the attestation.

## Data flow

```mermaid
flowchart LR
    A["Agent opens a<br/>.claude/rules/*.md<br/>-scoped file"] -->|InstructionsLoaded event| B["instructions-loaded.sh<br/>(fail-open)"]
    B -->|canonicalize + prefix-check<br/>rule-file scope only| C["jq -n --arg<br/>one JSON line"]
    C -->|O(1) append| D[".correctless/meta/<br/>instructions-loaded.jsonl<br/>(gitignored)"]
    E["Agent edits a<br/>hooks/ file"] -->|PostToolUse| F["audit-trail.sh<br/>(+ session_id)"]
    F --> G[".correctless/artifacts/<br/>audit-trail-{slug}.jsonl"]
    D --> H["/cwtf Rule-Load<br/>Observability"]
    G --> H
    H -->|raw evidence + liveness line<br/>NO verdict| I["Human classifies<br/>MG-001 vs MG-002"]
```

## Configuration & limitations

- **Requires Claude Code ≥ 2.1.69** for the `InstructionsLoaded` event (ENV-012).
  On older harnesses the hook never fires, the log stays empty, and the `/cwtf`
  section is dormant (a non-alarming advisory) — graceful degradation.
- **Activation on upgrade**: the hook is installed by `/csetup` but only
  *registered* in `settings.json` on the next `register_hooks()` run — re-run
  `/csetup` after upgrading, or the log stays dormant.
- **Unbounded local growth**: the log is O(1)-append, gitignored, and local.
  There is currently no `/cprune` reaper for it (accepted; see ABS-046).
- **Forgeable**: the log is agent-writable and deliberately *not*
  SFG-protected (per-session telemetry, not a security asset). Because there is
  no automated verdict, a forged line only misleads a human reading raw evidence
  with the liveness counts in view — an accepted residual for an advisory signal.

## References

- Spec: `.correctless/specs/instructionsloaded-hook.md` (INV-001..016, PRH-001..005)
- Architecture: ABS-004 (amended), ABS-046, TB-010, ENV-012, ENV-005
- Verification / attestation: `.correctless/verification/instructionsloaded-hook-verification.md`
