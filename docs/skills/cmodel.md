# /cmodel -- Formal Alloy Modeling

> Translate spec invariants into a formal Alloy model and run the Alloy Analyzer to find design-level bugs before code is written.

## When to Use

- Features with state machines or lifecycle transitions (e.g., token creation, refresh, revocation)
- Protocol handling or trust boundary crossings
- Access control logic or resource ownership
- **Not for:** pure data transformations, config validation, or numeric calculations -- use property-based testing instead

## How It Fits in the Workflow

Runs after `/cspec` (spec phase) and before `/creview-spec`. The modeling phase sits between "what should the system do" and "is the spec actually correct." Finds design bugs while they are still cheap to fix.

**Full mode only.** This skill is not available in Lite mode.

## What It Does

- Reads the spec artifact (invariants, prohibitions, trust boundaries, STRIDE analysis) and ARCHITECTURE.md
- Generates an Alloy 6 model (`docs/models/{task-slug}.als`) with signatures, facts, predicates, and assertions mapped to INV-xxx IDs
- Runs the Alloy Analyzer (`java -jar`) to check each assertion within a bounded scope
- Spawns a separate interpreter subagent to translate counterexamples into domain-specific scenarios (avoids blind spots from the model author)
- Presents both raw Alloy traces and interpreted scenarios for human review

## Example

You are building an auth token lifecycle feature. After writing the spec with `/cspec`, you run `/cmodel`.

The agent identifies two state machines (token lifecycle and session lifecycle) and one trust boundary (client-to-auth-server). It generates an Alloy model encoding rules like "a revoked token cannot transition back to active" (INV-007) and "a refresh token is invalidated after single use" (INV-012).

The Analyzer finds a counterexample for INV-012: a trace where two concurrent refresh requests both read the token as valid before either marks it consumed. The interpreter subagent translates this into a concrete scenario: "Client A and Client B both present the same refresh token within 5ms. Both receive new access tokens because the revocation check and token issuance are not atomic."

You revise the spec to require atomic check-and-consume, then advance to `/creview-spec`.

## What It Reads / Writes

| Reads | Writes |
|-------|--------|
| Spec artifact (`docs/specs/{slug}.md`) | Alloy model (`docs/models/{slug}.als`) |
| `ARCHITECTURE.md` | Analysis results (`docs/models/{slug}-results.md`) |
| `.claude/workflow-config.json` | Token log (`.claude/artifacts/token-log-{slug}.json`) |

## Common Issues

- **"No counterexample" does not mean "proven."** Alloy provides bounded verification within a scope (typically 5 entities). It means no bug was found in that scope, not that none exists.
- **Syntax errors on first run.** The agent auto-retries up to 3 times before surfacing to you.
- **Temporal operators.** Claude's reliability with `always`, `after`, and `until` in Alloy is inconsistent for complex formulas. Review temporal assertions carefully.
- **Wrong model, correct analysis.** A correct analysis of a wrong model creates false confidence. The human review step is load-bearing -- always verify the model represents the real system.

## Lite vs Full

This skill is **Full mode only**. In Lite mode, formal modeling is skipped entirely. Features go directly from `/cspec` to `/creview` (the single-pass review). If your feature involves state machines or trust boundaries and you are in Lite mode, consider upgrading to Full for this feature.

## Limitations

- Alloy models are abstractions. They cannot capture OS scheduler behavior or precise network timing.
- Counterexample translation is an additional error point. Raw traces are always shown alongside interpretations.
- If the feature has no modelable behavior (no state machines or trust boundaries), the agent states this explicitly and advances to review-spec. This is the only valid reason to pass through `/cmodel` without producing a model.
- The Analyzer runs as a background task (30+ seconds for complex state spaces). The agent prepares interpretation context while waiting.
