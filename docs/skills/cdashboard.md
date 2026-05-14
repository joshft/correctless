---
title: "/cdashboard"
parent: "Observability"
grand_parent: Skills
nav_order: 7
---

# /cdashboard — Project Dashboard

> Generate a self-contained HTML dashboard with project metrics and an artifact browser.

## When to Use

- After several features have gone through the workflow, to visualize quality trends.
- When you want to browse specs, verifications, review findings, and audit history in one place.
- Before a project review or retrospective, to see the full picture.
- **Not for:** Checking current workflow state (use `/cstatus`), or getting aggregate metrics data (use `/cmetrics`).

## How It Fits in the Workflow

This skill is standalone. It reads accumulated data from `.correctless/` artifacts and generates a snapshot dashboard. Run it anytime — it does not modify workflow state or artifacts.

## What It Does

Invokes `scripts/build-dashboard.sh` to generate a single self-contained HTML file at `.correctless/dashboard/index.html`. The dashboard has two views:

### Metrics View (default)

All existing project health sections:
- Project summary and quality trajectory
- QA rounds trend per feature
- Pipeline phase distribution
- Fix rate
- Escape metrics
- Antipattern health with dormancy detection
- Intensity calibration accuracy
- Override rate
- Cost by phase (from session transcript data)
- Drift debt
- Dev journal

### Artifact Browser

Sidebar navigation for browsing project artifacts as rendered markdown:
- **Specs** — `.correctless/specs/*.md`
- **Verifications** — `.correctless/verification/*.md`
- **Review Findings** — `.correctless/artifacts/review-spec-findings-*.md`, `.correctless/artifacts/review-findings-*.md`
- **Research Briefs** — `.correctless/artifacts/research/*.md`
- **Architecture** — `.correctless/ARCHITECTURE.md`, `.correctless/AGENT_CONTEXT.md`, `.correctless/antipatterns.md`
- **QA Findings** — `.correctless/artifacts/qa-findings-*.json` (rendered as formatted tables)
- **Audit History** — `.correctless/artifacts/findings/audit-*-history.md`

Missing categories are omitted from the sidebar automatically.

## Example

```
User: /cdashboard

Dashboard generated: .correctless/dashboard/index.html — open in a browser to view
```

Open the file in any browser via `file://` protocol.

## What It Reads / Writes

| Reads | Writes |
|-------|--------|
| `.correctless/specs/*.md` | `.correctless/dashboard/index.html` |
| `.correctless/verification/*.md` | |
| `.correctless/artifacts/*` | |
| `.correctless/ARCHITECTURE.md` | |
| `.correctless/AGENT_CONTEXT.md` | |
| `.correctless/antipatterns.md` | |
| `.correctless/config/workflow-config.json` | |
| `docs/workflow-history.md` | |
| `docs/dev-journal.md` | |
| `CONTRIBUTING.md` | |

## Dependencies

- **bash 4+**, **jq 1.7+**, and POSIX tools (no exotic dependencies)
- **marked.js v14.0.0** + **DOMPurify v3.2.4** loaded from CDN with SRI hashes (browser-side only)
- If CDN is unreachable, markdown displays as raw text with a visible notice

## Dark Mode

Respects `prefers-color-scheme: dark` media query automatically.

## Common Issues

- **Empty dashboard**: Normal on fresh projects with no artifacts. The dashboard shows "No data yet" placeholders.
- **Markdown not rendering**: CDN may be unreachable. Raw markdown text is still readable. Check your network connection.
- **Script fails**: Ensure jq is installed (`jq --version`). The script requires jq 1.7+.
