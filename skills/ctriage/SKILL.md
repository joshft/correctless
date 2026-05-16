---
name: ctriage
description: Bulk triage deferred findings backlog. Presents findings one at a time with disposition options.
allowed-tools: Read(.correctless/meta/deferred-findings.json), Write(.correctless/meta/deferred-findings.json), Read, Grep, Glob, Bash(jq*)
interaction_mode: interactive
---

# /ctriage — Deferred Findings Backlog Triage

> **Shared constraints apply.** Before executing, read `_shared/constraints.md` from the parent of this skill's base directory. All constraints there apply to this skill.

You are the triage agent. Your job is to walk the user through every open deferred finding, one at a time, wizard-style. Do not dump all findings at once — present each finding individually and wait for the user's response before proceeding.

## Behavior

1. **Read the backlog**: Read `.correctless/meta/deferred-findings.json`. If the file does not exist, tell the user: "No deferred findings backlog found. Run `bash scripts/sync-deferred-backlog.sh` to seed it from review artifacts." and stop.

2. **Filter open findings**: Select all findings where `status` is `open`. If none exist, tell the user: "No open deferred findings. Backlog is clean." and stop.

3. **Present findings one at a time** with a progress counter showing position:

```
Finding 1 of 12: DF-003
Feature: auth-refactor
Severity: MEDIUM
Source: .correctless/artifacts/review-spec-findings-auth-refactor.md (RS-007)
Description: Missing rate limit on password reset endpoint

  1. Fix now — update status to in-progress (you fix it in this session; confirm when done to mark resolved)
  2. Keep open — no change
  3. Won't fix — update status to wont-fix (provide rationale)
  4. Re-prioritize — change severity level

  Or type your own: ___
```

4. **Write incrementally**: After each disposition decision, update `.correctless/meta/deferred-findings.json` immediately — do not batch writes at the end. If the session is interrupted at finding 25 of 30, the first 24 decisions are preserved.

5. **Disposition handling**:
   - **Fix now**: Set `status` to `in-progress`. The user fixes the issue in the current session. When they confirm the fix is applied, update `status` to `resolved` and set `resolved_at` to the current UTC timestamp.
   - **Keep open**: No change to the finding.
   - **Won't fix**: Set `status` to `wont-fix`, `resolved_at` to current UTC timestamp, and `resolution` to the user-provided rationale. Won't-fix items remain in the backlog permanently — they are never deleted or removed.
   - **Re-prioritize**: Update the `severity` field. Only MEDIUM, LOW, and ADVISORY are valid (no HIGH or CRITICAL per PRH-003).

6. **After all findings are triaged**, show a summary: "Triage complete. N fixed, M kept open, P won't-fix, Q re-prioritized."

## Constraints

- Findings with status `wont-fix` must never be deleted from the backlog file. The resolution rationale is the audit trail (PRH-002).
- The backlog only accepts MEDIUM, LOW, and ADVISORY severity findings. Do not allow re-prioritization to HIGH or CRITICAL (PRH-003).
- The `id` field uses zero-padded format: `DF-001`, `DF-002`, ..., `DF-999`.
- All timestamps use UTC (`date -u` convention).
