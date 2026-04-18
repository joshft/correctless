# /cspec — Write a Feature Specification

> Turn a feature idea into a structured specification with testable rules before any code is written.

## When to Use

- Starting a new feature — before writing any code or tests
- After creating a feature branch and before the TDD cycle
- When you need to clarify requirements and surface edge cases early
- **Not for:** bug fixes (use `/cdebug`), refactoring (use `/crefactor`), or changes that already have an approved spec

## How It Fits in the Workflow

`/cspec` is the first skill you run after `/csetup`. It produces the spec document that drives everything downstream. After the spec is approved, you run `/creview` to challenge it with fresh eyes. The full pipeline is: **/cspec** → /creview → /ctdd → /cverify → /cdocs → merge.

## What It Does

1. **Socratic brainstorm** — challenges your assumptions with targeted questions: "What problem does this solve? Not the feature — the problem." Scales depth to your confidence level.
2. **Reads project context** — ARCHITECTURE.md, antipatterns, drift debt, QA history, and recent git log to ground the spec in your codebase's reality
3. **Researches current best practices** (when needed) — spawns a research subagent for topics where training data may be stale (new library versions, security protocols, rapidly-evolving APIs). Saves findings to an artifact.
4. **Drafts the spec** — at standard intensity, produces Rules (R-001, R-002...) with test levels. At high/critical intensity, produces Invariants, Prohibitions, Boundary Conditions, and optionally STRIDE analysis.
5. **Walks you through the spec** — presents rules in small groups for approval, resolves open questions, checks against known antipatterns, and advances the workflow state when approved

## Example

```
User: /cspec — add rate limiting to the login endpoint

Agent: Before writing the spec, let me understand the problem.
       What's driving this? Brute force attacks, or general API abuse?

User: Brute force. We've had credential stuffing attempts.

Agent: What's the simplest version that would be useful? Per-IP limiting,
       per-account limiting, or both?

User: Per-account first. IP limiting can come later.

Agent: Based on our discussion, here's what I understand: rate limiting on
       the login endpoint to prevent credential stuffing, scoped to
       per-account lockout. IP-based limiting is out of scope for now.

       [reads ARCHITECTURE.md, antipatterns, recent git log]

       # Spec: Login Rate Limiting

       ## Rules
       - **R-001** [unit]: After 5 failed login attempts for the same email
         within 15 minutes, subsequent attempts return 429 with a
         Retry-After header
       - **R-002** [integration]: The lockout counter resets after a
         successful login
       - **R-003** [unit]: The lockout duration is configurable via
         environment variable (default: 15 minutes)
       - **R-004** [integration]: Rate limit state persists across server
         restarts (stored in Redis/database, not in-memory)
       - **R-005** [unit]: The 429 response does not reveal whether the
         email exists in the system

       Does this look right? Anything to add or change?
```

## What It Reads / Writes

| Reads | Writes |
|-------|--------|
| `AGENT_CONTEXT.md` | `.correctless/specs/{task-slug}.md` |
| `ARCHITECTURE.md` | `.correctless/artifacts/research/{slug}-research.md` (if research triggered) |
| `.correctless/antipatterns.md` | `.correctless/artifacts/token-log-{slug}.json` |
| `.correctless/meta/drift-debt.json` (high+ intensity) | Workflow state (advances to review phase) |
| `.correctless/artifacts/qa-findings-*.json` | |
| Git log (recent 20 commits) | |

## Integration Test Contracts

For `[integration]` rules, `/cspec` defines Entry/Through/Exit contract constraints derived from `.correctless/ARCHITECTURE.md` entrypoints (ABS-023). The contract format (ABS-024) tells the TDD agent exactly what the integration test must exercise:

- **Entry**: which entrypoint the test must use (from the entrypoint's `test_via` field)
- **Through**: which components must be exercised and which must NOT be mocked
- **Exit**: what observable behavior must hold (expressible as a test assertion without internal state)

If no entrypoints are defined in ARCHITECTURE.md, the skill prompts you to run `/carchitect` first or skip contracts for this spec. Rules tagged `[unit]` are not affected — contracts apply only to `[integration]` rules.

## Intensity Levels

**Standard intensity** produces 5 sections: What, Rules (R-xxx with test levels), Won't Do, Risks, Open Questions. Simple and fast.

**High/critical intensity** scales artifact weight by intensity level. High adds Boundary Conditions and Complexity Budget. Critical adds STRIDE analysis, Environment Assumptions, and Design Decisions. At high/critical intensity, the skill also checks drift debt and recommends an intensity level based on trust boundaries touched.

## Common Issues

- **On the main branch**: The skill will tell you to create a feature branch first. The workflow state machine requires a feature branch.
- **Research takes a while**: If the skill spawns a research subagent (for new libraries, security topics, or rapidly-evolving APIs), expect 1-3 extra minutes. It announces when research starts and finishes.
- **Spec feels over-specified**: Start with fewer rules. You can always add more during `/creview`. The review skill exists specifically to catch what you missed.
