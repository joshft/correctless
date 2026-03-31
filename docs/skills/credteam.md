# /credteam — Red Team Assessment

> Live adversarial penetration testing against a running system with source code access and a specific objective to accomplish.

## When to Use

- After Hacker Olympics findings are fixed and you want to verify exploitability against the live system
- When you need to test runtime-only issues that static analysis misses (middleware ordering, deployment config, service interaction)
- For goal-directed security validation: "can an attacker actually achieve X?"
- **Not for:** code-level vulnerability scanning — that is `/caudit hacker`. Red teaming is live exploitation toward a specific objective, not a checklist.

## How It Fits in the Workflow

Runs after Hacker Olympics fixes are applied. The recommended sequence is: Hacker Olympics (static, finds code-level flaws) then Red Team (live, proves exploitability) then Devil's Advocate (periodic, challenges the security approach itself). The red team finds integration gaps, runtime behavior, and defense chain failures that no amount of code reading can surface.

**Full mode only.** This skill is not available in Lite mode.

## What It Does

- Verifies the target environment is isolated (private IP, localhost, or mesh network — refuses public internet targets)
- Reads source code to map trust boundaries: where identity, privilege, and data sensitivity change
- Identifies seams between boundaries where validation gaps, transform-after-validate patterns, or implicit trust exist
- Executes live attacks against the running target, chaining techniques toward the objective
- Produces an attack narrative (not a findings list) documenting every attempt, response, and pivot
- Writes mandatory regression tests for any achieved objective

## Example

Your objective is: "Starting from an unauthenticated session, access internal service metrics."

The agent reads the source and maps trust boundaries. It finds that the public API gateway validates auth tokens, but an internal service discovery endpoint (`/internal/services`) was added for health monitoring and sits outside the auth middleware chain.

The agent crafts a request to `/internal/services` and receives a list of internal service URLs. One service exposes a `/metrics` endpoint that returns system metrics including database connection strings. The agent chains: unauthenticated request to service discovery, then direct request to the metrics endpoint using the internal service URL.

**Objective achieved via SSRF through internal service discovery.** The report includes:
1. The exact request sequence (boundary map, attack chain, proof)
2. Recommended fixes: move `/internal/services` behind auth middleware, restrict metrics endpoints to loopback
3. A regression test that reproduces the attack path for CI

## What It Reads / Writes

| Reads | Writes |
|-------|--------|
| Source code (full access) | Report (`.claude/artifacts/redteam/report-{date}.md`) |
| `ARCHITECTURE.md` | Regression tests |
| Running target (live requests) | Updated antipatterns (`.claude/antipatterns.md`) |
| | Token log (`.claude/artifacts/token-log-{slug}.json`) |

## Options

**Agent structure:**

| Mode | When to Use | Agents |
|------|-------------|--------|
| Solo (default) | Most assessments | 1 agent, all angles |
| Team | Complex targets with multiple attack surfaces | 2-3 agents: Primary Interface Attacker, Control Plane Attacker, Resilience Attacker |

**Overnight runs:** For infrastructure targets, the red team can run unattended on an isolated VPS with `--dangerously-skip-permissions` and `--max-turns 200`. Read the report in the morning.

## Common Issues

- **Agent may refuse attack actions.** The agent is instructed to think like an attacker and execute real payloads. If it hesitates, this is expected behavior from safety training. Emphasize that the environment is isolated, the target is on a private network, and the assessment has explicit authorization. The isolation check at the start is mandatory precisely so the agent can operate freely.
- **Target must be isolated.** The agent programmatically verifies the target resolves to a private IP (RFC1918, loopback, or mesh network). If it resolves to a public IP, the agent refuses to proceed. This is non-negotiable.
- **No isolated environment available.** The agent can help you dockerize your application with a `docker-compose.yml` that stands up the full stack (app, database, supporting services, mock third-party APIs) on an isolated Docker network.
- **Long runtime.** Red team assessments can run for hours. The task list serves as the attack narrative — check it periodically for progress.
- **Production credentials.** Never use production credentials or real user data. All keys must be test/sandbox keys. Plant synthetic artifacts for the objective.
