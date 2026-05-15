---
title: "/ctriage"
parent: "Observability"
grand_parent: Skills
nav_order: 6
---

# /ctriage — Deferred Findings Triage

> Bulk triage of deferred review findings. Walk through open items one at a time, decide what to fix, keep, or close.

## When to Use

- `/cstatus` warns that deferred findings exceed the threshold (20+).
- You have bandwidth for a cleanup sprint between features.
- Before a release, to review accumulated tech debt from past reviews.
- **Not for:** Triaging QA or audit findings (those have their own workflows), or reviewing active findings during a review phase (use `/creview` or `/creview-spec`).

## How It Fits in the Workflow

This skill sits outside the normal pipeline and can be invoked at any time. It reads and writes `.correctless/meta/deferred-findings.json` — the centralized backlog of non-blocking findings deferred during review. The `/cauto` pipeline also sweeps this backlog before PR creation, but `/ctriage` is for dedicated triage sessions.

## What It Does

- Reads the deferred findings backlog and presents open findings **one at a time** in wizard style (not a report dump).
- Shows a progress counter: "Finding 3 of 12."
- For each finding, displays: ID, source feature, severity, category, description, and the originating review artifact path.
- Offers four disposition options per finding:
  1. **Fix now** — status changes to `in-progress`; you fix it in the current session; status changes to `resolved` when you confirm the fix.
  2. **Keep open** — no change, moves to next finding.
  3. **Won't fix** — prompts for rationale, sets status to `wont-fix` with `resolved_at` timestamp. Item stays in the file permanently (PRH-002).
  4. **Re-prioritize** — change severity (within MEDIUM/LOW/ADVISORY).
- **Incremental saves**: writes the updated backlog after each disposition. If the session is interrupted at finding 8 of 15, the first 7 decisions are preserved.

## Example

```
User: /ctriage

Deferred Findings Backlog: 12 open findings

--- Finding 1 of 12 ---
ID: DF-003
Feature: rate-limiting
Severity: MEDIUM
Category: security
Description: No rate limiting on the retry endpoint after
             authentication failure
Source: .correctless/artifacts/review-spec-findings-rate-limiting.md (RS-004)

Options:
  1. Fix now
  2. Keep open
  3. Won't fix (provide rationale)
  4. Re-prioritize severity

User: 3
Rationale: Rate limiting is handled at the API gateway level,
           not per-endpoint. Documented in ops runbook.

Updated DF-003 to wont-fix.

--- Finding 2 of 12 ---
...
```

## What It Reads / Writes

| Reads | Writes |
|-------|--------|
| `.correctless/meta/deferred-findings.json` | `.correctless/meta/deferred-findings.json` |

## Intensity Levels

Available at all intensity levels. The backlog contains only MEDIUM, LOW, and ADVISORY findings — severity gating is enforced at write time by the review skills and sync script (PRH-003).

## Common Issues

- **"No deferred findings file"**: No findings have been deferred yet, or the backlog hasn't been seeded. Run `bash scripts/sync-deferred-backlog.sh` to import from existing review artifacts.
- **Empty backlog**: All findings are resolved or wont-fix. Nothing to triage.
- **Stale backlog**: If `/cstatus` reports drift between review artifacts and the backlog, run `bash scripts/sync-deferred-backlog.sh` to re-sync before triaging.
