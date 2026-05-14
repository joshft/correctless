---
name: cdashboard
description: Generate a self-contained HTML dashboard with metrics and artifact browser. Opens via file:// protocol.
allowed-tools: Bash(bash*scripts/build-dashboard.sh*), Read, Glob
interaction_mode: autonomous
---

# /cdashboard — Project Dashboard UI

> **Shared constraints apply.** Before executing, read `_shared/constraints.md` from the parent of this skill's base directory. All constraints there apply to this skill.

Generate a self-contained HTML dashboard at `.correctless/dashboard/index.html` with two views:
- **Metrics** — quality trajectory, QA rounds, pipeline phase distribution, fix rate, antipattern health, intensity calibration, override rate, cost by phase, drift debt, dev journal
- **Artifact Browser** — sidebar navigation for browsing specs, verifications, review findings, research briefs, architecture docs, QA findings, and audit history as rendered markdown

## Steps

1. Run `bash scripts/build-dashboard.sh` from the project root (or `bash .correctless/scripts/build-dashboard.sh` on user projects)
2. Report the output path to the user

## Passthrough Fallback

If the script fails (missing config, unresolvable root), it exits 1 and prints available artifacts to stderr. Relay this to the user with the failure reason included.

## Notes

- The dashboard is a static HTML file — no server, no live reload
- Opens correctly via `file://` protocol in any browser
- Markdown rendering uses marked.js + DOMPurify from CDN (SRI-pinned); falls back to raw text if CDN is unreachable
- Read-only v1 — no user input, annotation, or write-back
