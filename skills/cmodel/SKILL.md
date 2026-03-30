---
name: cmodel
description: Generate an Alloy formal model of security-relevant behavior and run the Alloy Analyzer. Use after /cspec for features with state machines, protocol handling, or trust boundaries.
allowed-tools: Read, Grep, Glob, Bash(java*), Bash(alloy*), Bash(git*), Bash(*workflow-advance.sh*), Write(docs/models/*)
context: fork
---

# /cmodel — Formal Alloy Modeling

You are the modeling agent. Your job is to translate spec invariants into a formal Alloy model and run the Alloy Analyzer to find design-level bugs before any code is written.

## When to Use

Features that involve: state machines, protocol handling, access control, trust boundary transitions, resource ownership. Skip for purely functional transformations (use property-based testing instead).

## Before You Start

Check current phase: `.claude/hooks/workflow-advance.sh status`. You should be in the `model` phase. If not, tell the human to run `/cspec` first to enter the correct phase. Do not advance state from the wrong phase.

1. Read the spec artifact (invariants, prohibitions, trust boundaries, STRIDE analysis).
2. Read `ARCHITECTURE.md` for existing trust boundaries and abstractions.
3. Read `.claude/workflow-config.json` for the Alloy JAR path.

## Behavior

### Step 1: Identify Modelable Scope

Not everything needs modeling. Focus on:
- State machines and lifecycle transitions
- Trust boundary crossings
- Access control logic
- Protocol interactions
- Resource ownership and cleanup

Skip: data transformations, config validation, numeric calculations.

### Step 2: Generate the Alloy Model

Write to `docs/models/{task-slug}.als`. Use Alloy 6 syntax.

- **Signatures** map to system entities
- **Facts** encode system rules (always true)
- **Predicates** model transitions (things that can happen)
- **Assertions** encode spec invariants as checkable properties — reference INV-xxx IDs in comments
- **Attacker model** for security features — model capabilities from STRIDE analysis

Every assertion MUST reference the spec invariant ID it encodes (e.g., `// INV-003`).

### Step 3: Run the Analyzer

```bash
java -jar {alloy_jar} {model_file}
```

For each assertion, run `check assertionName for N` (start with scope 5).

**Auto-retry on syntax errors**: if the analyzer returns a syntax/type error, fix the `.als` file and re-run. Up to 3 retries before surfacing to the human.

### Step 4: Interpret Results (Separate Agent)

**Do NOT interpret counterexamples yourself.** You wrote the model — you have blind spots. Spawn a separate forked subagent (the interpreter) that receives the spec, the model, and the raw analyzer output. It translates counterexamples to domain-specific scenarios.

**Interpreter subagent prompt:**

> You are the Alloy model interpreter. You did NOT write this model. Your job is to translate Alloy Analyzer output into domain-specific scenarios.
>
> You receive:
> - The feature spec (read from docs/specs/{task-slug}.md)
> - The Alloy model (read from docs/models/{task-slug}.als)
> - The raw Alloy Analyzer output
>
> For each counterexample trace:
> 1. Map abstract Alloy states to concrete system behavior
> 2. Translate the trace into a step-by-step scenario in domain terms
> 3. Identify which spec invariant (INV-xxx) is violated
> 4. Present BOTH the raw Alloy trace AND your interpretation — the human verifies the translation
>
> If a counterexample looks like a modeling error (the model allows behavior the real system doesn't), say so explicitly — don't force a domain interpretation of a model bug.
>
> Use Read to examine the spec and model files. Return your interpretation as your final text response.

Always present both the raw Alloy trace AND the interpretation so the human can verify.

**If counterexamples found**: map to INV-xxx/PRH-xxx, propose spec revisions.
**If no counterexamples**: report bounded guarantee ("no counterexample within scope N").

### Step 5: Human Review

Ask: "Does this model accurately represent the feature? Are there behaviors I missed?"

This is load-bearing. A correct analysis of a wrong model creates false confidence.

## Write Results

Write analysis results to `docs/models/{task-slug}-results.md`.

## Advance State

```bash
.claude/hooks/workflow-advance.sh review-spec
```

After advancing, tell the human: "Model complete. Run `/creview-spec` for multi-agent adversarial review of the spec."

## Claude Code Feature Integration

### Task Lists
Structure the modeling process as tasks:
- Identify modelable scope (which parts of spec are amenable to Alloy)
- Generate Alloy model (signatures, facts, predicates, assertions)
- Run Alloy Analyzer (each assertion as a sub-task with result)
- Auto-retry on syntax errors (attempt 1, 2, 3)
- Interpret results (spawn interpreter agent)
- Present to human for model review

### Background Tasks
Run the Alloy Analyzer (`java -jar`) as a background task while preparing the counterexample interpretation context. The JAR can take 30+ seconds for complex state spaces.

## Constraints

- NEVER claim an invariant is "proven" — Alloy provides bounded verification, not proof.
- Keep the model readable with comments.
- Every assertion references a spec invariant ID.
- If the feature has no modelable behavior (pure data transformation, no state machines or trust boundaries), state this explicitly and advance to review-spec. This is the only valid reason to pass through /cmodel without producing a model.

## Limitations (Be Honest)

- Alloy models are abstractions — can't capture OS scheduler or network timing details.
- Claude's reliability with temporal operators (`always`, `after`, `until`) is inconsistent for complex formulas.
- Counterexample translation is an additional error point — always show raw traces.
- Bounded analysis means "no bug found in small scope," not "no bug exists."
