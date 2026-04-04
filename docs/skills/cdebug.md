# /cdebug — Structured Bug Investigation

> Investigate a bug systematically — reproduce, trace root cause, form hypotheses, fix with TDD discipline, and escalate if the bug resists.

## When to Use

- A bug found in production or reported by users
- During the QA phase of `/ctdd` when a complex bug needs investigation beyond a simple fix round
- After a failed fix round — when the issue needs deeper analysis
- When you are stuck on a bug and guessing hasn't worked
- **Not for:** writing new features (use `/cspec`), planned refactoring (use `/crefactor`), or spec reviews

## How It Fits in the Workflow

`/cdebug` is a standalone workflow — it does not interact with the TDD state machine. It can be invoked during an active TDD workflow (when QA flags a complex bug) or independently for production bugs. Fixes should go through `/ctdd` on a fix branch or be committed directly with manual verification.

## What It Does

1. **Reproduce** — gets a concrete reproduction: a failing test, a curl command, a stack trace. If none exists, writing a test that demonstrates expected behavior is the first step.
2. **Root cause investigation** — traces the code path from entry point to failure. Reads every function in the chain. Checks git blame to find when behavior changed. Reads existing tests to find the gap between "tested" and "failing." Checks antipatterns and QA history for known patterns.
3. **Automated git bisect** (optional) — if the bug has a reliable failing test and is a regression, offers to run `git bisect` to find the exact commit that introduced it. Stashes dirty state, runs bisect, cleans up automatically.
4. **Hypothesis testing** — forms a specific, testable hypothesis: "The bug is caused by [X] because [Y]. I can verify this by [Z]." Designs a test to confirm or deny before touching any code.
5. **TDD fix with agent separation** — writes a failing test that reproduces the bug, then spawns a separate implementation agent to write the fix. The agent that understands the bug writes the test; a different agent writes the code.
6. **Class fix assessment** — determines whether this bug represents a class (same pattern could occur elsewhere) or is a one-off. If a class, adds a structural test that catches all instances and an antipattern entry.
7. **Escalation after 3 failed hypotheses** — if three hypotheses are tested and none explain the bug, stops fixing and spawns a fresh agent for architectural analysis. The bug may be a symptom of a deeper design problem.

## Example

```
User: /cdebug — webhooks from Stripe are returning 401 in production
      but pass in our tests

Agent: Reproduction confirmed — webhook to /api/webhooks/stripe returns
       401 when called with a valid Stripe signature.

       Tracing code path: request hits authMiddleware before reaching
       the webhook handler...

       I have a failing test. Want me to run git bisect to find the
       exact commit? Takes about 1 minute.

User: Yes, go ahead.

Agent: Bisect found commit `a3f2c91`: "refactor: reorganize middleware"
       Changed: src/middleware/index.ts

       Hypothesis 1: The auth middleware was registered before the
       webhook route during the middleware reorganization. Webhook
       endpoints should bypass auth because they use signature
       verification instead. — CONFIRMED.

       The middleware order in index.ts puts authMiddleware() before
       app.use('/api/webhooks'). Before commit a3f2c91, webhooks
       were registered first.

       Writing failing test: "webhook endpoint should not require
       auth header when valid Stripe signature is present"...

       Spawning implementation agent...

       Fix: moved webhook routes above auth middleware registration.
       All tests passing (existing + new).

       Class fix: this is a middleware ordering bug (AP-007 in your
       antipatterns). Added structural test that asserts webhook
       routes are registered before auth middleware in the route
       chain.
```

## What It Reads / Writes

| Reads | Writes |
|-------|--------|
| `AGENT_CONTEXT.md` | `.correctless/artifacts/debug-investigation-{slug}.md` |
| `ARCHITECTURE.md` | `.correctless/artifacts/debug-bisect-test.sh` (temporary, cleaned up) |
| `.correctless/antipatterns.md` | `.correctless/antipatterns.md` (new entry, if class fix) |
| `.correctless/artifacts/qa-findings-*.json` | `.correctless/artifacts/token-log-{slug}.json` |
| `.correctless/meta/drift-debt.json` | Test and source files (fix) |
| Git history and blame | |

## Lite vs Full

Both modes run the same investigation workflow. There is no difference in `/cdebug` behavior between Lite and Full — bug investigation follows the same systematic process regardless of workflow intensity.

## Common Issues

- **Bisect requires a clean worktree**: The skill automatically stashes dirty changes before bisecting and pops the stash afterward. If the stash pop fails (due to conflicts), your changes are still in `git stash list`. Run `git stash pop` manually after resolving conflicts.
- **3 failed hypotheses is not a failure**: Escalation after 3 attempts is the designed recovery path. It means the bug is harder than expected and likely needs architectural analysis, not more guessing.
- **Intermittent bugs**: If the bug only reproduces sometimes, the investigation starts by asking about environment differences, timing, and concurrency. An intermittent bug that only manifests under load suggests a race condition.
