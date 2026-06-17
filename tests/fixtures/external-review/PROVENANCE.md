# Source provenance (PAT-020) — real codex 0.139.0 captures

Captured: 2026-06-16T22:28:04Z
Tool: codex-cli 0.139.0 (`codex exec`)
Command shape:
    codex exec --sandbox read-only \
      --output-schema <findings-schema.json> \
      --output-last-message <out.json> \
      --json --ephemeral --cd <repo-root> -

These are **real** codex outputs (not hand-authored), captured during the
INV-021 RED gate for feature/cross-model-spec-review. They resolve:

- **OQ-005**: `--json` and `--output-last-message` compose in a single `codex exec` call.
- **EA-004**: the usage event path is pinned to the `turn.completed` JSONL event,
  top-level `.type == "turn.completed"`, with usage at `.usage`:
  `{input_tokens, cached_input_tokens, output_tokens, reasoning_output_tokens}`
  (NOT nested under `.msg`).
- **EA-003 / OQ-007**: `--output-last-message` writes under `--sandbox read-only`,
  and read-only codex with `--cd` repo-root can read a schema file placed under
  `.correctless/artifacts/`.

Files:
- `codex-output-last-message.json` — schema-conforming findings JSON (the deliverable).
- `codex-json-stream.jsonl` — the 4-event `--json` stream (thread.started,
  turn.started, item.completed, turn.completed). Cost is read from turn.completed.

The producer's jq usage-path string is pinned to this fixture by the INV-021 drift test.
