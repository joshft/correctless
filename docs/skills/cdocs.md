# /cdocs — Update Project Documentation

> Keep project documentation current after a feature lands — README, AGENT_CONTEXT.md, feature docs, and ARCHITECTURE.md suggestions.

## When to Use

- After `/cverify` passes — this is the final step before merging
- When the workflow state is `verified` and the verification report exists
- **Not for:** writing specs (use `/cspec`), writing code documentation inline, or documenting features that haven't been verified yet

## How It Fits in the Workflow

`/cdocs` is the last skill in the pipeline before merge. The full flow is: /cspec → /creview → /ctdd → /cverify → **/cdocs** → merge. It requires the verification report from `/cverify` to exist — if it does not, the skill stops and tells you to run `/cverify` first.

## What It Does

1. **Analyzes what changed** — diffs against main to identify new features, changed behavior, new config options, API endpoints, environment variables, and removed functionality
2. **Updates README.md** — checks feature list, setup instructions, usage examples, and project description against the current state of the project
3. **Updates AGENT_CONTEXT.md** — the briefing document every fresh agent reads. Adds new components, design patterns, common pitfalls, and verifies the quick reference commands are accurate. Keeps it under 1500 words.
4. **Creates feature documentation** — for significant features, creates or updates docs in `docs/features/` with usage, configuration, examples, and known limitations
5. **Suggests ARCHITECTURE.md additions** — if the feature introduced new patterns or conventions, proposes entries one at a time for your approval
6. **Fact-checks against code** — verifies that documented API parameters, config defaults, and described flows actually match the implementation
7. **Flags stale docs** — checks existing documentation for references to code, config, or features that no longer exist

## Example

```
Agent: Diff analysis complete — 1 new feature (login rate limiting),
       2 new config options. Checking README...

       README changes proposed:
       - Add "Rate Limiting" to the Features section
       - Add RATE_LIMIT_WINDOW_MINUTES to the Configuration table

       AGENT_CONTEXT.md updates:
       - Add Redis dependency to Key Components
       - Add rate limiting pattern to Design Patterns

       Feature doc: created docs/features/rate-limiting.md
       - What it does, config options, Redis requirement

       ARCHITECTURE.md: no new patterns needed — rate limiting
       follows existing middleware pattern (PAT-003).

       Staleness check: docs/features/old-auth.md references
       `src/middleware/basicAuth.ts` which was removed in this branch.

       Approve these changes?
```

## What It Reads / Writes

| Reads | Writes |
|-------|--------|
| `docs/verification/{slug}-verification.md` | `README.md` (updated) |
| `.correctless/specs/{slug}.md` | `AGENT_CONTEXT.md` (updated) |
| `README.md`, `ARCHITECTURE.md`, `AGENT_CONTEXT.md` | `docs/features/{slug}.md` (new or updated) |
| `.correctless/config/workflow-config.json` | `ARCHITECTURE.md` (additions, if approved) |
| Git diff against main | `CLAUDE.md` (convention learning, if 3+ features share a pattern) |
| | Workflow state (advances to documented) |

## Lite vs Full

Both modes run the same documentation checks. Full mode includes convention learning — if the same architectural pattern has appeared in 3+ features, it appends a "Convention confirmed" entry to `CLAUDE.md` so future agents treat it as an established project convention.

## Common Issues

- **"Run /cverify first"**: The skill requires the verification report at `docs/verification/{slug}-verification.md`. If you see this message, run `/cverify` before `/cdocs`.
- **AGENT_CONTEXT.md too long**: The skill enforces a 1500-word limit. If your project context is growing, it will trim and prioritize. Reference ARCHITECTURE.md for details rather than duplicating content.
