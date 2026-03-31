# /cmaintain — Maintainer Contribution Review

> Evaluate an incoming PR from a maintainer's perspective: scope, conventions, quality, and long-term maintenance burden.

## When to Use

- You are a project maintainer and someone submitted a PR you need to decide on.
- You want to assess whether merging a contribution is worth the long-term cost.
- A first-time contributor opened a PR and you want to give constructive, convention-aware feedback.
- **Not for:** Code-level review (architecture, security, antipatterns) — use `/cpr-review` for that. Not for contributing to someone else's project — use `/ccontribute`.

## How It Fits in the Workflow

This skill is standalone and complements `/cpr-review`. While `/cpr-review` asks "is this code good?", `/cmaintain` asks "should I merge this?" — a question about scope, conventions, and long-term ownership. Run both for a complete picture, or run `/cmaintain` alone when the code quality is not in question but the merge decision is.

## What It Does

- Loads your project's standards: `CONTRIBUTING.md`, PR templates, CODEOWNERS, linter/formatter configs, test patterns, CI config, and architecture docs.
- Fetches PR info and checks the contributor's history (first-time vs. regular contributor) to calibrate review depth.
- **Scope check**: Compares the PR against the linked issue. Flags scope expansion ("Issue asks for X, PR also does Y and Z"), scope reduction, and disproportionate changes (200-line refactor for a 5-line fix).
- **Convention compliance**: Checks code style, test style, commit format, error handling, file placement, import patterns, and PR template completeness.
- **Maintenance burden assessment**: The key differentiator. Evaluates pattern divergence, dependency cost, API surface expansion, complexity budget, and bus factor risk. Rates overall burden as low / medium / high.
- Generates pre-written review comments (ready to copy-paste) tailored to contributor experience: detailed convention explanations for first-timers, shorter notes for regulars.

## Example

```
User: /cmaintain 15

[1/9] Loading project standards...
[2/9] Loading contribution context...
      PR #15 "Add WebSocket support for live updates" by @new-contributor
      First-time contributor. Linked issue: #12.

[3/9] Scope check...
      Issue #12 asks for WebSocket notifications. PR also refactors the event
      emitter (3 files, 140 lines). Fix-to-noise ratio: 0.6.

## Maintainer Review: PR #15 — Add WebSocket support

### Contributor
@new-contributor — first-time contributor

### Scope
Expanded beyond issue. Core feature: 180 lines across 4 files.
Unrelated refactor: 140 lines across 3 files.
Recommendation: ask contributor to split the refactor into a separate PR.

### Maintenance Burden: medium
- Introduces a new event pattern (EventEmitter2) not used elsewhere.
  12 files currently use the built-in EventEmitter.
- ws package adds 0 transitive deps (good), last updated 2 months ago (healthy).
- Adds 3 new public API events — each is a backwards-compatibility commitment.
- Complex change from a first-time contributor. If bugs surface, the
  maintainer team owns the fix.

### Suggested Review Comments
- **General** — Blocking: "Thanks for this! Could you split the EventEmitter
  refactor into a separate PR? Smaller PRs are easier to review and merge."
- **src/events/handler.ts:42** — Suggestion: "We use the built-in EventEmitter
  everywhere else. See src/notifications/service.ts:18 for the pattern."
```

## What It Reads / Writes

| Reads | Writes |
|-------|--------|
| `CONTRIBUTING.md`, PR templates | Nothing (read-only) |
| CODEOWNERS | Optionally posts a PR review comment |
| Linter, formatter, CI configs | |
| `ARCHITECTURE.md`, `AGENT_CONTEXT.md` | |
| PR diff and metadata (via `gh` / `glab`) | |
| Contributor's merged PR history | |
| Linked issue | |

## Lite vs Full

Same in both modes. The maintainer review applies regardless of workflow intensity.

## Common Issues

- **No linked issue**: The skill notes this and skips scope verification. It still checks conventions, quality, and maintenance burden.
- **Neither CLI available**: Ask the user to paste the PR diff and description manually. All checks still run except contributor history lookup and comment posting.
- **Review too harsh or too lenient**: The maintainer reviews and edits the output before posting. The skill never posts without explicit approval.
