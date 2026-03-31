# /cupdate-arch -- Maintain Architecture Documentation

> Scan the codebase for undocumented trust boundaries, abstractions, and patterns, then update ARCHITECTURE.md with human-approved entries.

## When to Use

- After a feature lands via `/cdocs` and the codebase structure has changed
- When new packages, modules, or trust boundaries have been introduced
- When ARCHITECTURE.md feels stale relative to the actual code
- **Not for:** writing architecture from scratch on a new project -- use `/csetup` for initial population

## How It Fits in the Workflow

Runs after features are merged and documented. Keeps the living architecture document accurate so that future `/cspec`, `/creview-spec`, and `/caudit` runs have correct context. Stale architecture docs cause every downstream skill to make wrong assumptions.

**Full mode only.** This skill is not available in Lite mode.

## What It Does

- Reads current ARCHITECTURE.md, recent specs, and verification reports
- Scans the codebase for undocumented trust boundaries (TB-xxx), abstractions (ABS-xxx), patterns (PAT-xxx), and environment assumptions (ENV-xxx)
- Drafts structured entries for each candidate with invariant, violated-when, and detection method
- Presents each entry individually for human approval (no batch auto-writes)
- Checks document size and suggests fragmentation into `docs/architecture/` if it exceeds ~5000 words

## Example

After landing an OAuth2 integration, you run `/cupdate-arch`.

The agent scans the codebase and finds three undocumented items:

1. **TB-004: OAuth2 Token Exchange** -- a new trust boundary where the app exchanges authorization codes with the identity provider. The agent drafts an entry noting the identity assertion method (PKCE + state parameter) and the invariant that authorization codes must be single-use.

2. **ABS-007: HTTP Client Wrapper** -- a wrapper module enforcing timeout and retry policies that 8 call sites use but ARCHITECTURE.md does not mention. The entry notes the invariant "all external HTTP calls go through this wrapper" and the violation condition "direct `http.Get` calls bypassing the wrapper."

3. **PAT-005: Config-Then-Wire** -- a pattern repeated in 6 places where config structs are parsed and then wired to handlers. The entry notes the violation condition "config parsed but wiring call omitted."

You approve TB-004 and ABS-007, reject PAT-005 as too granular. ARCHITECTURE.md is updated with the two new entries.

## What It Reads / Writes

| Reads | Writes |
|-------|--------|
| `ARCHITECTURE.md` | `ARCHITECTURE.md` (updated entries) |
| `docs/specs/*.md` | `docs/architecture/*.md` (fragments, if size threshold exceeded) |
| `docs/verification/*.md` | |
| Source code (scan for patterns) | |

## Entry Types

Each entry follows a structured format with required fields:

| Type | Prefix | Required Fields |
|------|--------|----------------|
| Trust Boundary | TB-xxx | Crosses, identity assertion, data sensitivity change, invariant, violated-when |
| Abstraction | ABS-xxx | What, invariant, enforced-at, violated-when, test |
| Pattern | PAT-xxx | Rule, violated-when, test |
| Environment Assumption | ENV-xxx | Runtime assumption, invariant, violated-when |

## Lite vs Full

This skill is **Full mode only**. In Lite mode, architecture documentation is maintained manually. The structured scanning and entry drafting require the full agent pipeline for context.

## Common Issues

- **Entries require human approval.** The agent never auto-writes. Each entry is presented individually for review.
- **Document growing too large.** When ARCHITECTURE.md exceeds ~5000 words, the agent suggests moving sections into `docs/architecture/` with links from the root file.
- **Sequential numbering.** New entries are numbered sequentially (TB-001, TB-002, etc.) based on existing entries in the document.
- **Partial runs.** If interrupted, re-run `/cupdate-arch`. It scans the codebase fresh each time. Partially written entries can be reviewed and corrected on the next run.
