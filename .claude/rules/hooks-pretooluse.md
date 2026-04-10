---
paths:
  - hooks/workflow-gate.sh
  - hooks/sensitive-file-guard.sh
---

<!-- DOGFOOD: Correctless-internal rule. Do not copy as a user-project template; see FUTURE-003. This rule references Correctless-specific audit finding IDs (QA-R1-004/005) that are meaningless outside this project. -->

# PAT-001: PreToolUse hook conventions

## Rule

Every PreToolUse hook must: (1) `set -euo pipefail` + `set -f`, (2) check `command -v jq` with fail-closed exit 2, (3) bulk-parse stdin with single `eval` + `jq -r @sh`, (4) fast-path `exit 0` for non-relevant tools BEFORE loading config, (5) exit 0 to allow, exit 2 to block — fail-closed means exit 2 on unexpected input, never exit 0 on a parse failure or corrupt config.

## Violated when

- A hook loads config before checking `tool_name` (clause 4 violation).
- A hook uses multiple `jq` calls for stdin parsing instead of a single bulk parse (clause 3 violation).
- A hook exits non-0/non-2 on any code path (clause 5 violation).
- **Clause-5 fail-open**: `|| exit 0` on the stdin `jq` parse path, silent degradation on corrupt `workflow-config.json`, or any path that turns an unexpected input into `exit 0` instead of `exit 2`. A PreToolUse hook that "fails safe" by allowing the operation has inverted its security posture.
- A hook omits `set -euo pipefail` or `set -f` (clause 1 violation).
- A hook treats a missing `jq` binary as advisory (fail-open) instead of blocking — PreToolUse hooks without jq must exit 2, NOT exit 0 (clause 2 violation; contrast with PAT-005 PostToolUse, where fail-open is correct).

## Why clause 5 is strict about fail-closed

PreToolUse hooks enforce TB-001 at runtime. If an unexpected input is allowed through because the hook "didn't know what to do," the gate has been inverted — the model gets free reign precisely in the moments when the hook cannot reason about intent. That is the worst possible failure mode for a gate.

Two concrete historical failures — both caught only by a hostile-lens QA Olympics audit, not by normal review:

- **QA-R1-004**: Corrupted `workflow-config.json` defaulted `fail_closed_when_no_state` to `false`, silently degrading fail-closed posture to fail-open. Clause-5 violation by silent degradation.
- **QA-R1-005**: `workflow-gate.sh` had `|| exit 0` on the stdin `jq` parse failure path. When stdin JSON was malformed, the hook exited 0 instead of 2 — allowing the edit. Exact finding title: *"workflow-gate.sh fails closed on malformed stdin JSON (PAT-001)"*.

QA-R1-005's clause-5 violation persisted across 7+ hook-touching PRs over ~4 days in 2026 before the Olympics audit caught it — the bad pattern was introduced in PR #33 and survived PRs #35, #37, #38, #39, #45, #46 without a single reviewer catching it. That persistence duration is the baseline this rule file stakes its falsifiability on (see MG-002).

The lesson: on unexpected input, exit 2, not 0. No carve-outs, no environment-gated exceptions, no "this edge case is probably safe." If clause 5 has to be loosened, the loosening must be loud and reviewable.

## Tests

- `tests/test-sensitive-file-guard.sh` — sensitive-file-guard.sh shape + fail-closed behavior.
- `tests/test-workflow-gate.sh` — workflow-gate.sh shape + fail-closed behavior.
- `tests/test-dynamic-rigor.sh` — exercises both hooks across intensity levels.

## Related

- **PAT-005** (PostToolUse hook conventions) — the inverted variant: PostToolUse hooks are advisory and fail-open. Contrast with clause 5 here.
- **PAT-006** (Hook self-description via metadata headers) — structural convention every hook in this directory must follow; the `paths:` list for this rule file is discovered by matching `HOOK_TYPE: PreToolUse` headers (INV-017).
