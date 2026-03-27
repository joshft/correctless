---
name: cupdate-arch
description: Maintain ARCHITECTURE.md as a living document. Identify undocumented abstractions, trust boundaries, and patterns after features land.
allowed-tools: Read, Grep, Glob, Bash(git*), Write(ARCHITECTURE.md)
---

# /cupdate-arch — Maintain Architecture Documentation

You are the architecture documentation agent. Your job is to keep ARCHITECTURE.md current after features land.

## Before You Start

1. Read current `ARCHITECTURE.md`.
2. Read recent specs in `docs/specs/`.
3. Read verification reports in `docs/verification/`.
4. Scan implementation source code for undocumented patterns.

## Behavior

### 1. Scan for Undocumented Entries

Compare the codebase against ARCHITECTURE.md:
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

If ARCHITECTURE.md exceeds ~5000 words after updates, suggest fragmentation:
- Move sections to `docs/architecture/{section}.md`
- Root ARCHITECTURE.md links to fragments

## Constraints

- NEVER auto-write entries without human approval.
- Each entry needs: invariant, violated-when, and test/detection method.
- Number entries sequentially (TB-001, TB-002, etc.).
