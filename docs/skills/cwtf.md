# /cwtf — Workflow Accountability

> Audit the workflow itself: did agents actually follow their instructions, check every rule, and avoid shortcuts?

## When to Use

- After a feature completes, to verify the workflow was thorough before merging.
- After a bug escapes to production despite the workflow running -- find out which phase missed it.
- When you suspect an agent shortcut (e.g., QA passed suspiciously fast).
- **Not for:** Reviewing code quality (use `/cpr-review`), checking current phase (use `/cstatus`), or getting feature stats (use `/csummary`).

## How It Fits in the Workflow

This skill watches the agents watching the code. It sits outside the normal pipeline and can be invoked at any time after at least one phase has completed. It reads workflow state, spec rules, QA findings, audit trails, verification reports, and Claude Code session data to determine whether each agent did its job. Pair with `/csummary` for a complete post-feature picture: `/csummary` shows what was caught, `/cwtf` shows whether the catching was thorough.

## What It Does

- **Phase execution verification**: Checks that all mandatory phases ran (spec, review, tdd-tests, tdd-impl, tdd-qa, etc.). Uses the audit trail as primary evidence, since the workflow state only records the most recent transition. Flags phases skipped via override.
- **Rule coverage analysis**: For every spec rule (R-xxx, INV-xxx), checks whether a test exists, whether QA examined it, and whether verification covered it. Outputs a coverage table showing gaps.
- **Agent thoroughness -- QA**: Counts how many spec rules QA actually mentioned in findings or the conversation. Checks which implementation files QA read (from the audit trail) vs. which files were modified. Reports token budget indicators from session-meta as a rough signal ("session used 30% of project average -- may have shortcut").
- **Agent thoroughness -- Review**: Checks whether the security checklist fired for applicable categories (auth, input handling, APIs). Checks whether antipatterns were consulted.
- **Deviation detection**: Flags source files modified during QA (should be read-only), test edits during GREEN that were not logged, overrides with timestamps, and spec updates with reasons.
- **Four verdicts**: THOROUGH (all phases ran, all rules covered, no deviations), ADEQUATE (minor gaps that do not affect correctness), INCOMPLETE (significant coverage gaps or skipped checks), SHORTCUT (phase skips, gate bypasses, or far-below-average token usage). A single SHORTCUT criterion dominates -- the verdict cannot be higher than SHORTCUT if any gate bypass occurred.

## Example

```
User: /cwtf

[1/7] Loading workflow state and spec...
      Feature: rate-limiting. 7 spec rules (R-001 through R-007).
[2/7] Phase execution verified — all 8 phases ran. 0 overrides.
[3/7] Rule coverage...
[4/7] QA thoroughness: checked 5 of 7 rules.
[5/7] Review thoroughness: 4/4 applicable security checks ran.
[6/7] Deviation detection: 0 deviations found.
[7/7] Generating verdict...

## Workflow Accountability Report

### Rule Coverage: 5/7 rules covered
| Rule  | Test              | QA Checked | Verify Status |
|-------|-------------------|------------|---------------|
| R-001 | rateLimit.test:12 | Yes        | covered       |
| R-002 | rateLimit.test:34 | Yes        | covered       |
| R-003 | rateLimit.test:56 | Yes        | covered       |
| R-004 | audit.test:18     | NO         | UNCOVERED     |
| R-005 | rateLimit.test:78 | Yes        | covered       |
| R-006 | csrf.test:22      | Yes        | covered       |
| R-007 | deploy.test:9     | NO         | covered       |

### Agent Thoroughness
QA: Checked 5/7 rules. Token usage: 45k (82% of average).
- R-004 (audit logging) was not checked during QA. This may indicate
  the agent prioritized higher-risk rules or hit context limits.
- R-007 (deploy survival) was not checked during QA but was verified
  in the verification phase.

### Deviations (0 found)
No deviations detected.

### Verdict: ADEQUATE
All phases ran and 5 of 7 rules were checked by QA. The 2 unchecked
rules have tests and one was caught by verification. No gate bypasses
or shortcuts detected.
```

## What It Reads / Writes

| Reads | Writes |
|-------|--------|
| `.claude/artifacts/workflow-state-*.json` | Nothing (read-only) |
| Spec file (`docs/specs/{task-slug}.md`) | |
| `.claude/artifacts/qa-findings-{task-slug}.json` | |
| `.claude/artifacts/tdd-test-edits.log` | |
| `.claude/artifacts/audit-trail-*.jsonl` | |
| `.claude/artifacts/override-log.json` | |
| `docs/verification/{task-slug}-verification.md` | |
| `~/.claude/usage-data/session-meta/*.json` | |
| Conversation JSONL (targeted queries only) | |

## Lite vs Full

- **Lite**: Checks the Lite phase sequence (spec, review, tdd-tests, tdd-impl, tdd-qa, done, verified, documented).
- **Full**: Checks the Full phase sequence (adds model, review-spec, tdd-verify) and includes additional checks for those phases.

## Common Issues

- **No audit trail**: The skill still works from QA findings and the verification report, but agent thoroughness analysis (file-level read coverage) will be less detailed. The skill notes this limitation.
- **Conversation JSONL too large**: The skill uses targeted `jq` and `grep` queries on the JSONL file, searching for specific rule IDs and tool names. It never reads the entire file.
- **Verdict feels wrong**: The verdict is a judgment call with explained reasoning. The user decides what matters. SHORTCUT is not punitive -- it is a factual observation that the evidence shows shortcuts were taken.
