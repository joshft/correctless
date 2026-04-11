# Simulation Annex: Fix-Diff Reviewer Replay (NON-NORMATIVE)

**IMPORTANT**: This file is NOT the VP-002 functional-equivalence replay
required by INV-007. It is a simulation run from a session where the
`correctless:fix-diff-reviewer` plugin agent was not yet discoverable.
The real VP-002 (and VP-001) must still be executed in a fresh Claude Code
session after plugin reinstall — see
`.correctless/verification/RESUME-VP-001-AND-VP-002.md`.

This annex records the simulation outputs so the implementer has a
reference point when running the real VP-002 — if the real finding sets
disagree sharply with these, that is a signal to investigate before
accepting PASS.

- **Generated**: 2026-04-11 (orchestrator-side simulation)
- **Method**: Three parallel `Task(subagent_type="general-purpose")` calls,
  each invoked with the full fix-diff-reviewer system prompt (copied verbatim
  from `agents/fix-diff-reviewer.md` to `/tmp/fdr-system-prompt.txt`) and
  instructed to review one of the three historical fixture diffs. The
  fixtures were referenced by filepath rather than being pasted into a
  `<UNTRUSTED_DIFF>` fence — the subagent used its own Read tool to
  retrieve them. This is a material deviation from how the real /caudit
  orchestrator would invoke the plugin agent: (a) the data-treatment
  clause was never actually exercised because the diff wasn't fenced, and
  (b) the subagent had access to the full Claude Code tool set, not just
  Read/Grep/Glob.
- **Fixtures**:
  - `tests/fixtures/fix-diff-reviewer-historical-r1.diff` (SHA-256
    `2b0a181c...` — MATCH, 30 KB)
  - `tests/fixtures/fix-diff-reviewer-historical-r2.diff` (SHA-256
    `f33569ff...` — MATCH, 17 KB)
  - `tests/fixtures/fix-diff-reviewer-historical-r3.diff` (SHA-256
    `37975aac...` — MATCH, 5 KB)

## Output contract compliance

| Fixture | JSON validity | Notes |
|---------|---------------|-------|
| r1 | **VIOLATED** | Response began with ~2 KB of prose analysis ("Key observations:") before the JSON array. A real /caudit invocation would hit `jq -e .` parse failure and trigger PRH-003 fail-closed — aborting the round. This is a useful observation: a general-purpose subagent given the fix-diff-reviewer system prompt **cannot reliably produce pure JSON** even when the prompt explicitly says "Return ONLY the JSON array." The real plugin agent may or may not do better — VP-002 will tell us. |
| r2 | Clean | Pure JSON array returned, parses with `jq -e .`. |
| r3 | Clean | Pure JSON array returned, parses with `jq -e .`. |

This is **exactly** the failure mode INV-017 (`jq -e .` identity parse
gate) exists to catch. The simulation accidentally validated the design
of the invariant: without the gate, the orchestrator would have
silently consumed r1's prose-wrapped response, the regex extractor
would have needed to scrape the embedded array, and any parse error
would be hidden. With the gate, the round aborts with a clear error.

## Finding counts

`findings_returned_per_replay: [8, 9, 4]`

Total: 21 findings across 3 replays. Not `[0, 0, 0]`.

## Finding summary by fixture

### r1 (8 findings — R1 fixes introduced regressions)

| ID | Severity | Title | Location |
|----|----------|-------|----------|
| FD-001 | critical | `update_phase` jq filter built via string interpolation enables injection and breaks on special chars | `hooks/workflow-advance.sh` 75-86 |
| FD-002 | critical | `audit-trail` HOOK_MATCHER now fires on Read and Grep, polluting audit log | `hooks/audit-trail.sh` 8-12 |
| FD-003 | high | `locked_update_state` EXIT trap clobbers caller's pre-existing EXIT trap | `scripts/lib.sh` 196-212 |
| FD-004 | high | `_acquire_state_lock` stale-lock break races with an in-progress lock holder | `scripts/lib.sh` 160-172 |
| FD-005 | high | `workflow-gate` comment-stripping bypass breaks legitimate commands with '#' | `hooks/workflow-gate.sh` 73-78 |
| FD-006 | high | `setup install_hooks` now unconditionally overwrites user-modified hooks | `setup` 252-255 |
| FD-007 | medium | `workflow-gate` fail-closed recovery path has dead branch and incorrect FAIL_CLOSED detection | `hooks/workflow-gate.sh` 102-120 |
| FD-008 | medium | `cmd_init` reorder leaves workflow state pointing at a spec file that may never be created | `hooks/workflow-advance.sh` 414-437 |

### r2 (9 findings — R2 fixes introduced regressions)

| ID | Severity | Title | Location |
|----|----------|-------|----------|
| FD-001 | high | Unquoted interpolation of user-supplied reason into `cmd_spec_update` jq filter allows injection | `hooks/workflow-advance.sh` 777-802 |
| FD-002 | high | `cmd_override` filter interpolates reason and ts into jq program body, losing --arg safety | `hooks/workflow-advance.sh` 860-880 |
| FD-003 | high | `cmd_qa` locked_update_state filter inlines `$ts` instead of using --arg | `hooks/workflow-advance.sh` 530-545 |
| FD-004 | high | `cmd_set_intensity` filter inlines `$level` without --arg | `hooks/workflow-advance.sh` 728-742 |
| FD-005 | high | `cmd_spec_update` drops atomicity by re-reading state after locked update for warning count | `hooks/workflow-advance.sh` 790-812 |
| FD-006 | medium | `cmd_spec_update` filter reads `.phase` after it has been overwritten in the same pipeline | `hooks/workflow-advance.sh` 777-802 |
| FD-007 | medium | `audit-trail.sh` Grep branch ignores Glob and other read tools, narrowing fix to one tool | `hooks/audit-trail.sh` 49-60 |
| FD-008 | medium | `setup` unconditional script copy clobbers user-modified `lib.sh` and `antipattern-scan.sh` | `setup` 263-275 |
| FD-009 | medium | Duplicate diff hunks for plugin and top-level paths risk drift | `hooks/workflow-advance.sh` |

### r3 (4 findings — R3 fix + CI surface)

| ID | Severity | Title | Location |
|----|----------|-------|----------|
| FD-001 | high | jq 1.7 operator precedence regression on `as $count` binding | `hooks/workflow-advance.sh` 785-795 |
| FD-002 | high | `cmd_override` references `sf` after its declaration was deleted | `hooks/workflow-advance.sh` 863-870 |
| FD-003 | medium | Duplicate fix applied to two divergent copies of the same file without a shared source | `correctless/hooks/workflow-advance.sh` 785-870 |
| FD-004 | low | `locked_update_state` silently swallows jq errors via `2>/dev/null` | `scripts/lib.sh` 206-212 |

## Regression-layer coverage

PMB-002 post-mortem identifies three regression layers. Simulation
findings cover each:

| Layer | Simulation coverage |
|-------|---------------------|
| **R1 fixes → R2 regressions** (3 regressions in token-tracking and workflow-advance state handling) | r1 FD-001 (update_phase jq injection), r1 FD-002 (audit-trail matcher expansion), r1 FD-003 (locked_update_state EXIT trap clobber), r1 FD-004 (lock break race), r1 FD-005 (workflow-gate comment strip bypass) — five simulation findings identify the classes of regression that R2 had to fix. |
| **R2 fixes → R3 regressions** (1 regression: `locked_update_state` `--arg` passthrough lost quoting safety check) | r2 FD-001 through FD-004 directly identify the `--arg` regression across four cmd_* call sites. r2 FD-005 identifies the atomicity drop. r3 FD-002 identifies the `sf` dangling reference class. |
| **R3 fix → CI failure** (PMB-001-adjacent: jq 1.7 vs 1.8 `as $var` binding precedence) | r3 FD-001 directly identifies the PAT-010 / AP-011 tooling-version drift. |

**All three layers have at least one corresponding simulation finding
with a non-placeholder ID.**

## Caveats — why this is NOT VP-002

1. **Wrong subagent binding**: VP-001 exists specifically to catch the
   case where the orchestrator thinks it's invoking `correctless:fix-diff-reviewer`
   but a different agent actually responds. This simulation used the
   `general-purpose` subagent type — by definition, it proves nothing
   about plugin-loader binding correctness.

2. **Data-treatment clause unexercised**: The fixture diffs were not
   fenced inside `<UNTRUSTED_DIFF>...</UNTRUSTED_DIFF>`; the subagent
   Read-tool'd them directly from the filesystem. Prompt-injection
   defenses (INV-015) were therefore not tested.

3. **Tool allowlist unenforced**: The simulation subagent had the full
   Claude Code toolset (Bash, Edit, Write, Task, …), not the pinned
   `{Read, Grep, Glob}` set. PRH-002's read-only guarantee was not
   tested.

4. **R1 output contract violation**: As noted above, the r1 simulation
   returned prose + JSON, not pure JSON. A real /caudit invocation
   would hit PRH-003 fail-closed. VP-002 must confirm the real plugin
   agent produces pure JSON across all three fixtures.

5. **Not transcribed into the real replay report**: the structural
   test at `tests/test-fix-diff-reviewer-agent.sh:97` expects
   `.correctless/verification/fix-diff-reviewer-migration-replay.md` —
   this annex is a separate file. The 3 skipped assertions in the
   structural test will remain SKIP until the real replay report is
   written.

## What this simulation *does* tell us

- The fix-diff-reviewer system prompt, when followed, produces
  specific, locatable, non-placeholder findings that map cleanly to
  the three PMB-002 regression layers.
- The simulation's r1 prose leak is strong evidence that INV-017's
  `jq -e .` identity parse is a load-bearing invariant — without it,
  a well-intentioned reviewer that produces "JSON + analysis prose"
  would silently pass through the orchestrator's extractor and the
  round would advance on partial data.
- The simulation did NOT produce `[0, 0, 0]` — the historical
  fixtures contain enough signal for an attentive reviewer to
  generate 4-9 findings per fixture. This is a lower bound: if the
  real VP-002 returns fewer than ~3 findings per fixture or returns
  `[0, 0, 0]`, investigate whether the real plugin agent is being
  suppressed or whether its system prompt has drifted.

## Resume instructions

See `.correctless/verification/RESUME-VP-001-AND-VP-002.md` for the
one-paste message that a fresh Claude Code session (post plugin
reinstall and Claude Code restart) can use to finish VP-001 + VP-002 +
write the real replay report.
