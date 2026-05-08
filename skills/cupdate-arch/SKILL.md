---
name: cupdate-arch
description: Update .correctless/ARCHITECTURE.md after features land. Use after /cdocs or when the codebase structure has changed.
allowed-tools: Read, Grep, Glob, Bash(git*), Edit, Write(.correctless/ARCHITECTURE.md), Write(docs/architecture/*), Write(.claude/rules/*.md)
interaction_mode: hybrid
---

# /cupdate-arch — Maintain Architecture Documentation

> **Shared constraints apply.** Before executing, read `_shared/constraints.md` from the parent of this skill's base directory. All constraints there apply to this skill.

## Intensity Gate

This skill requires effective intensity `high` or above. Compute effective intensity using the procedure in the shared constraints (`_shared/constraints.md`).

**Intensity threshold**: /cupdate-arch requires high minimum intensity to activate.

- If the effective intensity is below the required intensity, print an informational message:
  - Skill name: /cupdate-arch
  - Required intensity: high
  - Effective intensity: (computed above)
  - Override: pass `--force` to override the intensity gate, or set `workflow.intensity` to `high` or above in `.correctless/config/workflow-config.json`
  - Then **do not proceed** with the skill body. Stop here.
- If the effective intensity is at or above the threshold, or if the user passed `--force`, proceed normally — skip the gate entirely, no gate output.

You are the architecture documentation agent. Your job is to keep .correctless/ARCHITECTURE.md current after features land.

## Progress Visibility (MANDATORY)

Architecture updates take 5-10 minutes. The user must see progress throughout.

**Before starting**, create a task list:
1. Read current architecture docs and recent specs
2. Validate existing entries (paths, tests, producers/consumers)
3. Scan codebase for undocumented abstractions
4. Draft new component entries
5. Draft new pattern entries
6. Check size thresholds (fragmentation)
7. Present entries for approval

**Between each step**, print a 1-line status: "Scanned codebase — found {N} undocumented abstractions. Drafting entries..." Mark each task complete as it finishes.

## Before You Start

1. Read current `.correctless/ARCHITECTURE.md`.
2. Read recent specs in `.correctless/specs/`.
3. Read verification reports in `.correctless/verification/`.
4. Scan implementation source code for undocumented patterns.

## Behavior

**Complementarity note:** /cverify detects feature-scoped staleness. /cdocs updates entries for the current feature. This skill validates ALL entries, not just those affected by a single feature.

### 0. Validate Existing Entries

Before scanning for undocumented entries, validate that existing `.correctless/ARCHITECTURE.md` entries are still accurate. For each ABS-xxx, PAT-xxx, TB-xxx, ENV-xxx entry:

1. **Enforced at paths exist on disk**: verify each file path in the `Enforced at` field exists. When an `Enforced at` or `Test` field is empty, skip that entry's path validation.
2. **Test paths exist and reference the entry ID**: verify each file path in the `Test` field exists, and grep it for the entry ID.
3. **Enforced at includes all producers/consumers**: check whether the `Enforced at` paths include all files that actually reference the abstraction as producers or consumers.

Read `.correctless/meta/drift-debt.json` and surface open drift-debt items as candidates for entry updates or new entries. Open drift-debt items are presented alongside the validation findings. Dormant when `drift-debt.json` is absent or empty (PAT-019).

Entries with broken paths or missing test references are presented to the human one at a time with options:

```
  1. Fix (recommended) — update the entry to reflect current paths
  2. Delete — remove the entry (it's no longer relevant)
  3. Skip — investigate later

  Or type your own: ___
```

### 1. Scan for Undocumented Entries

Compare the codebase against .correctless/ARCHITECTURE.md:
- **Trust Boundaries**: scan for network listeners, TLS configs, auth middleware not covered by existing TB-xxx entries.
- **Abstractions**: scan for packages/modules with enforced usage patterns (e.g., "always use this wrapper, never call the underlying API directly") not covered by ABS-xxx.
- **Patterns**: scan for patterns repeated in 5+ places but not documented as PAT-xxx.
- **Environment Assumptions**: scan for runtime assumptions (UIDs, capabilities, file paths) not covered by ENV-xxx.

### 2. Draft Entries

For each candidate, draft the structured entry:

**Trust Boundary**:
```markdown
### TB-xxx: {name}
- **Crosses**: {what boundary}
- **Identity assertion**: {how identity is established}
- **Data sensitivity change**: {from → to}
- **Invariant**: {what must hold}
- **Violated when**: {condition}
```

**Abstraction**:
```markdown
### ABS-xxx: {name}
- **What**: {description}
- **Invariant**: {what must hold}
- **Enforced at**: {file path}
- **Violated when**: {condition}
- **Test**: {how to check}
```

**Pattern**:
```markdown
### PAT-xxx: {name}
- **Pattern**: {name}
- **Rule**: {convention}
- **Violated when**: {condition}
- **Test**: {how to check}
```

### 3. Present for Approval

Present each entry to the human one at a time. Don't batch — each entry deserves individual consideration.

### 4. Check Size

If .correctless/ARCHITECTURE.md exceeds ~5000 words after updates, suggest fragmentation:
- Move sections to `docs/architecture/{section}.md`
- Root .correctless/ARCHITECTURE.md links to fragments

## Autonomous Defaults

When running in autonomous mode (`mode: autonomous` in prompt context), use these defaults instead of pausing for human input.
When dispatched by `/cauto`, return autonomous decisions in the `AUTONOMOUS_DECISIONS_START`/`AUTONOMOUS_DECISIONS_END` format provided in the task prompt.

- **AD-001**: Entry discovery — auto-discover undocumented patterns (default). Rationale: discovery is a codebase scan with objective criteria (5+ occurrences, not already documented).
- **AD-002**: Entry content — generate from code analysis (default). Rationale: entry fields (invariant, violated-when, test) are derived from code structure, not subjective design choices.
- **AD-003**: New entry approval — `escalate: always`. Default if deferred: skip — flag for human review. Rationale: architecture doc changes affect all future features and shape agent behavior across the project.

## If Something Goes Wrong

- **Skill interrupted**: Re-run `/cupdate-arch`. It scans the codebase fresh each time. Partially written entries can be reviewed and corrected.
- **Rate limit hit**: Wait 2-3 minutes and re-run.
- **Wrong entries written**: Edit .correctless/ARCHITECTURE.md directly to fix or remove incorrect entries.

## Constraints

- NEVER auto-write entries without human approval.
- Each entry needs: invariant, violated-when, and test/detection method.
- Number entries sequentially (TB-001, TB-002, etc.).
