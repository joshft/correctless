# /creview — Skeptical Spec Review

> Read a spec cold and find what the author missed — unstated assumptions, untestable rules, missing edge cases, and security gaps.

## When to Use

- After `/cspec` produces an approved spec — this is the mandatory next step in Lite mode
- In Full mode, for a quick single-pass review on low-risk features (use `/creview-spec` for the full 4-agent adversarial review)
- **Not for:** reviewing code or pull requests (use `/cpr-review`), reviewing implementation after TDD (use `/cverify`)

## How It Fits in the Workflow

`/creview` sits between spec writing and test writing. The pipeline is: /cspec → **/creview** → /ctdd → /cverify → /cdocs → merge. Review is never skipped — the state machine enforces this. Even for small features, review consistently finds unstated assumptions or untestable rules.

## What It Does

1. **Reads the spec with fresh eyes** — this is a separate agent from the spec author, deliberately skeptical. It reads project context, antipatterns, and QA history for additional ammunition.
2. **Checks for unstated assumptions** — does the spec assume the database is available? That the user is authenticated? That input is valid? Each assumption either becomes a rule or an accepted risk.
3. **Checks testability** — flags vague rules ("responds quickly") and proposes concrete rewrites ("responds in under 500ms at the 95th percentile")
4. **Checks edge cases** — empty input, maximum input, concurrent access, network failure, partial success, Unicode. Proposes rules for uncovered boundaries.
5. **Runs the security checklist automatically** — if the spec touches auth, user input, payments, APIs, or data storage, the review checks for missing security rules (CSRF, input validation, RLS, mass assignment, SSRF, etc.) without being asked. Proposes missing rules rather than lecturing.
6. **Checks integration test coverage** — flags rules involving component wiring that are incorrectly tagged as `[unit]` instead of `[integration]`
7. **Produces a self-assessment** — which rules are hardest to test, which assumptions are most likely wrong, and what the overall risk profile looks like

## Example

```
Agent: Assumptions check complete — found 2 unstated assumptions.

       1. UNSTATED: The spec assumes Redis is available for rate limit
          state. What happens if Redis is down?
          Proposed: R-006 [integration]: If the rate limit store is
          unavailable, login attempts proceed without rate limiting
          (fail-open) and an alert is logged.

       2. SECURITY: This feature accepts user input (email) via POST
          but there's no rule for input validation on the server side.
          Proposed: R-007 [unit]: POST /login validates email format
          server-side and returns 400 for malformed input.

       3. EDGE CASE: What happens if the lockout counter overflows?
          With 5 failed attempts every 15 minutes for months, does the
          counter grow unbounded?
          Proposed: R-008 [unit]: Failed attempt records older than
          the lockout window are pruned on each login attempt.

       R-003 ("configurable via environment variable") is weak —
       rewrite to specify the variable name and default value.
```

## What It Reads / Writes

| Reads | Writes |
|-------|--------|
| Spec artifact (`.correctless/specs/{slug}.md`) | Updated spec (new rules appended) |
| `AGENT_CONTEXT.md` | `.correctless/artifacts/reviews/{slug}-review.md` |
| `ARCHITECTURE.md` | `.correctless/artifacts/token-log-{slug}.json` |
| `.correctless/antipatterns.md` | Workflow state (advances to tests phase) |
| `.correctless/meta/workflow-effectiveness.json` (Full) | |
| `.correctless/artifacts/qa-findings-*.json` | |
| Relevant source code | |

## Lite vs Full

In **Lite** mode, `/creview` is the standard review — a single-agent skeptical pass covering assumptions, testability, edge cases, antipatterns, integration test levels, and security. This is what most projects use.

In **Full** mode, `/creview` is available as a quick 3-minute review for low-risk features. For higher-risk features, use `/creview-spec` instead, which runs a 4-agent adversarial review team. Full mode users can choose either based on the feature's risk profile.

## Common Issues

- **Security checklist feels aggressive**: The checklist fires automatically based on what the spec touches. If a recommendation doesn't apply, mark it as an accepted risk in the Risks section — it will still show up in `/cverify` as a tracked decision.
- **Too many findings**: Focus on the proposed rule rewrites. Accept, modify, or reject each one. The review preserves your existing rule numbering and adds new rules at the end.
