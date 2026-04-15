# /carchitect — Architecture Definition

> Produce a structured `.correctless/ARCHITECTURE.md` for any project. Two modes: reverse-engineer from existing code or greenfield directed discovery. Output includes machine-referenceable entrypoints YAML and human-readable prose sections.

## When to Use

- Starting a new project and need to document its architecture before coding
- Joining an existing project with no architecture doc (or a stub with placeholders)
- Want machine-referenceable entrypoints for downstream tooling (test audits, scope mapping)
- Need a structured starting point that future `/cupdate-arch` invocations can maintain

## How It Fits in the Workflow

`/carchitect` runs independently of the TDD pipeline. It produces `.correctless/ARCHITECTURE.md`, which other skills read but do not write. After the initial architecture doc is created, use `/cupdate-arch` for feature-level updates. Phase 0 is standalone — no other skills are modified.

## What It Does

### Mode Selection

Asks which mode to use, or accepts `--greenfield` / `--reverse-engineer` flags:

1. **Reverse-engineer** — scan existing code, detect patterns, present findings for confirmation
2. **Greenfield** — ask discovery questions, present architectural decisions with tiered tradeoffs

If an ARCHITECTURE.md already exists with real content, offers to delete and start fresh, redirect to `/cupdate-arch`, or exit.

### Reverse-Engineer Mode

1. Scans the codebase (respecting `.gitignore`, excluding vendor directories)
2. Presents a coverage report: directories scanned, files analyzed vs skipped, patterns detected
3. Batches patterns by confidence: high (>= 75%) presented as a group, low presented individually
4. Caps at 10 patterns per session; use `--continue` for more
5. Requires user confirmation before documenting any pattern as canonical
6. Runs an adversarial second pass via the `architecture-reviewer` agent to find missed entrypoints and violated patterns
7. Presents reviewer findings one at a time for user adjudication

### Greenfield Mode

1. Asks concrete discovery questions (purpose, callers, dependencies, deployment, constraints)
2. Presents architectural decisions in tiered format:
   - **Tier 1**: Full tradeoffs with advantages, disadvantages, "Best when" qualifiers, escape hatch
   - **Tier 2**: Brief tradeoffs + recommendation
   - **Tier 3**: Recommendation only
3. Documents decisions without generating code or scaffolding

### Output

Writes `.correctless/ARCHITECTURE.md` with these sections:
1. System Purpose and Boundaries
2. Entrypoints (structured YAML with marker comments)
3. Key Patterns
4. Layer Conventions
5. Anti-Patterns
6. Decision Log
7. Known Limitations

Only Entrypoints is mandatory and structured. Other sections are prose stubs marked with `<!-- TODO: verify -->` where uncertain.

## Example

```
User: /carchitect

Agent: Does this project have meaningful existing code I should analyze,
       or are we designing from scratch?
       1. Reverse-engineer — analyze existing code
       2. Greenfield — design from scratch

User: 1

Agent: Scanning project...

       Coverage Report:
       - src/: 42 files (38 analyzed, 4 skipped: 2 generated, 2 < 5 lines)
       - tests/: 15 files (all skipped: test files)
       - config/: 3 files (all analyzed)

       High-confidence patterns (>= 75%):
       1. Express route handlers follow controller pattern (32/38 files)
       2. All database access goes through repository layer (28/38 files)
       3. Error responses use structured { error, code, message } shape (35/38 files)

       Confirm all, or drill into any? (enter number to drill in)
```

## What It Reads / Writes

| Reads | Writes |
|-------|--------|
| Source code (full project) | `.correctless/ARCHITECTURE.md` |
| `.gitignore` | |
| Existing `.correctless/ARCHITECTURE.md` (existence check) | |

## Options

| Flag | Purpose |
|------|---------|
| `--greenfield` | Skip mode selection, enter greenfield mode |
| `--reverse-engineer` | Skip mode selection, enter reverse-engineer mode |
| `--continue` | Resume pattern review (within current session only) |

## Common Issues

- **"Real content detected"**: An ARCHITECTURE.md already exists. Choose to delete and start fresh, use `/cupdate-arch` for incremental updates, or exit.
- **Too many patterns**: The 10-pattern cap prevents decision fatigue. Use `--continue` to review the next batch.
- **Reviewer found issues**: The adversarial second pass is working as intended. Adjudicate each finding — some may be false positives if the codebase has intentional exceptions.
