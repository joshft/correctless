# /cpr-review — Multi-Lens PR Review

> Review an incoming pull request through multiple focused lenses: architecture, security, tests, antipatterns, and conventions.

## When to Use

- Someone opens a PR against your project and you want a thorough review before merging.
- You want to check a PR for security issues, architecture drift, or missing test coverage.
- A dependency bot (Dependabot, Renovate, Snyk) opens a version bump PR.
- **Not for:** Reviewing your own code mid-development (use `/ctdd` QA for that) or deciding whether to merge a contribution (use `/cmaintain`).

## How It Fits in the Workflow

This skill is standalone — it does not require an active Correctless workflow. Use it anytime a PR needs review. It pairs well with `/cmaintain` when you also need a maintainer-perspective assessment on merge readiness.

## What It Does

- Fetches PR info and diff via `gh` (GitHub) or `glab` (GitLab). Falls back to manual diff paste if neither CLI is available.
- **Auto-detects dependency bump PRs** by checking the PR author (Dependabot, Renovate, etc.), changed files, and title patterns. When detected, it switches to a dependency-specific lens: runs the test suite, analyzes project usage of the bumped package, fetches changelog/release notes, checks CVEs, and assesses breaking changes.
- For code PRs, runs focused checks in sequence: architecture compliance, security checklist, test coverage analysis, antipattern scan, convention compliance, and spec alignment (if a spec is linked).
- In Full mode, adds concurrency analysis, trust boundary checks, cross-spec impact, drift detection, performance implications, and dependency risk.
- Groups all findings by severity (CRITICAL / HIGH / MEDIUM / LOW) with file:line references, explanations, and suggested fixes. Always includes a "What Looks Good" section.

## Example

```
User: /cpr-review 42

[1/16] Fetching PR info and diff...
[2/16] Checking for dependency bump...
       PR #42 "Add rate limiting to login endpoint" by @contributor — code change, not a dep bump.
[3/16] Reading project context (ARCHITECTURE.md, antipatterns.md)...
[4/16] Architecture compliance check...
       Architecture compliance complete — 1 finding. Running security checklist...
[5/16] Security checklist (auth code detected)...
       ...

## PR Review: #42 — Add rate limiting to login endpoint

### CRITICAL (1)
- src/middleware/rateLimit.ts:18 — Rate limit counter stored in-memory; resets on deploy.
  Why: Attackers can bypass by waiting for a deploy cycle.
  Fix: Use Redis or the existing cache layer documented in ARCHITECTURE.md (PAT-004).

### What Looks Good
- Correct use of the middleware chain pattern from ARCHITECTURE.md.
- Login endpoint test covers both success and lockout paths.
```

## What It Reads / Writes

| Reads | Writes |
|-------|--------|
| PR diff and metadata (via `gh` / `glab`) | Nothing (read-only) |
| `ARCHITECTURE.md` | Optionally posts a PR comment |
| `AGENT_CONTEXT.md` | |
| `.correctless/antipatterns.md` | |
| `.correctless/config/workflow-config.json` | |
| `.correctless/specs/*.md` (if referenced) | |

## Lite vs Full

- **Lite mode**: Runs architecture, security, test coverage, antipattern, convention, and spec alignment checks.
- **Full mode** (any `workflow.intensity` set): Adds concurrency analysis, trust boundary analysis, cross-spec impact, drift detection, performance implications, and dependency risk assessment.

## Common Issues

- **Neither `gh` nor `glab` installed**: The skill still works if you paste the PR diff manually, but it cannot detect the PR author (for dep bump detection) or post review comments.
- **Rate limit hit**: Wait 2-3 minutes and re-run. The skill is read-only and safe to re-run.
- **Findings overlap with CI**: The skill skips lint errors that CI already catches and focuses on what CI cannot: architecture alignment, security logic, and spec compliance.
