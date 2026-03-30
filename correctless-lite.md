# Correctless Lite: Structured Development Workflow

> **Note:** This is the original design specification. The implementation has evolved — 8 skills were added (/csetup, /cstatus, /csummary, /cmetrics, /cdebug, /cpr-review, /crefactor, /chelp), the security checklist was added to /creview, and the research agent was added to /cspec. Lite now has 13 skills; Full has 20. See the [README](README.md) and the actual [skill files](skills/) for the current implementation.



## Overview

A lightweight set of Claude Code skills that bring structure and discipline to everyday development without the ceremony required for high-assurance software. Designed for web applications, CLI tools, APIs, media projects, and anything where you want fewer bugs and better architecture — but don't need formal verification or convergence-based auditing.

The workflow: **Spec → Review → Implement (TDD) → Verify → Document**

Same paradigm as Correctless, stripped to the essentials. Thirteen skills. Lightweight version of the full twenty-skill suite. One reviewer instead of an agent team. No Alloy, no STRIDE, no convergence loops, no external model integration.

### Core Design Principle: The Lens Determines What the Agent Finds

LLMs are prone to confirmation bias. An agent told to *build* sees code as a thing to complete. An agent told to *verify* sees it as a thing to check. An agent told to *break* sees it as a thing to attack. Same model, same code — different outputs because the framing determines what the agent looks for.

This is why the workflow uses separate agents for each TDD phase: the test-writing agent (RED) has a "what should be true?" lens and writes thorough tests without knowing the implementation plan. The implementation agent (GREEN) has a "make this work" lens and didn't write the tests, so it can't game them. The QA agent has a "find what's wrong" lens and is independent of both. The verification agent has a "does this match the spec?" lens and never saw the implementation happen.

**Never let an agent grade its own work. Always give review agents an explicitly skeptical framing.**

### Quick Start

```bash
# 1. Add to your project
# Replace joshft/correctless with the actual repo URL
git clone https://github.com/joshft/correctless.git .claude/skills/workflow
cd .claude/skills/workflow && ./setup

# 2. Review the generated config (auto-detected from your project)

# 3. Start building
git checkout -b feature/my-feature
/cspec
```

### What You Get

- **Specs before code**: every feature starts with a short spec that defines what "correct" means — before tests or implementation. Prevents the "I built the wrong thing" failure mode.
- **Enforced TDD**: hooks block source code edits until tests exist. Tests block advancing until they fail first (RED) and then pass (GREEN). Claude can't skip phases.
- **Lightweight review**: a single review pass challenges your spec for unstated assumptions and untestable claims. Not a multi-agent debate — a focused second look.
- **Verification**: after implementation, check that what you built matches what you specced. Coverage gaps, dead invariants, undocumented dependencies.
- **Living documentation**: AGENT_CONTEXT.md keeps fresh agents oriented. Antipatterns grow from real bugs. Architecture docs stay current.

### What This Doesn't Do

If you're building security-critical infrastructure, network proxies, financial systems, or anything where a bug is a vulnerability — use the [Correctless](./correctless.md) instead. This lite version doesn't include: formal modeling (Alloy), STRIDE threat analysis, multi-agent adversarial review, convergence-based auditing, external model cross-checking, mutation testing with deterministic tools, or drift debt tracking.

---

## Project Configuration

### `.claude/workflow-config.json`

```json
{
  "project": {
    "name": "string — project name",
    "language": "go | python | typescript | rust | java | other",
    "description": "one-line description"
  },
  "commands": {
    "test": "npm test",
    "test_verbose": "npm test -- --verbose",
    "coverage": "npm test -- --coverage",
    "lint": "npm run lint",
    "build": "npm run build"
  },
  "patterns": {
    "test_file": "*.test.ts|*.test.tsx|*.spec.ts|*.spec.tsx",
    "source_file": "*.ts|*.tsx",
    "test_fail_pattern": "FAIL|failing",
    "build_error_pattern": "error TS|Cannot find|SyntaxError"
  },
  "workflow": {
    "min_qa_rounds": 1,
    "require_review": true,
    "auto_update_antipatterns": true
  },
  "paths": {
    "architecture_doc": "ARCHITECTURE.md",
    "agent_context": "AGENT_CONTEXT.md",
    "antipatterns": ".claude/antipatterns.md",
    "docs": "docs/",
    "specs": "docs/specs/",
    "artifacts": ".claude/artifacts/",
    "state": ".claude/artifacts/workflow-state-{branch-slug}.json"
  }
}
```

The `setup` script auto-detects your language, test runner, and build commands. Review the generated config and adjust.

---

### `ARCHITECTURE.md`

Lighter than Correctless. No formal trust boundary IDs or invariant enforcement references. Just document the important stuff so Claude (and future you) understands the project.

```markdown
# Architecture

## Key Components

| Component | Location | Purpose |
|-----------|----------|---------|
| API routes | src/routes/ | HTTP endpoints |
| Database | src/db/ | Postgres via Prisma |
| Auth | src/auth/ | JWT-based, middleware pattern |

## Design Patterns

- **Error handling**: all route handlers use try/catch with a central error middleware. Never throw unhandled.
- **Validation**: Zod schemas at API boundaries. Validate input at the edge, trust it internally.
- **State management**: React Query for server state, Zustand for client state. No mixing.

## Conventions

- Config lives in environment variables, loaded via src/config.ts. Never import process.env directly.
- All database queries go through the repository pattern in src/db/repos/. No raw SQL in route handlers.
- Tests use MSW for API mocking. No mocking internal functions — test behavior, not implementation.

## Known Limitations

- No rate limiting on public endpoints (TODO)
- File uploads stored locally, not S3 (fine for MVP)
```

**Cold start**: start with whatever you know. Even 5 bullet points about your project's patterns is better than nothing. ARCHITECTURE.md grows naturally as you build features — the `/cdocs` skill suggests new entries after each feature.

---

### `.claude/antipatterns.md`

Starts empty. Grows when bugs are found post-merge.

```markdown
# Antipatterns — [Project Name]

Every item is a bug class that escaped testing at least once.
The /cspec and /creview skills check new features against this list.

## How to maintain this file

When a bug is found after merge, add an entry here. Ask yourself:
1. What broke?
2. How should a spec rule or test have caught it?
3. Write the check that would prevent recurrence.

This is the feedback loop that makes Correctless Lite improve over time.
No special skill required — just edit this file. If you upgrade to
Correctless (full), the /cpostmortem skill automates this process.

## Entries

### AP-001: {short name}
- **What went wrong**: {description}
- **How to catch it**: {the check or test that would prevent recurrence}

(grows organically)
```

---

## Artifact Formats

### Spec Artifact (`docs/specs/{task-slug}.md`)

Deliberately simple. Five sections, not twelve.

```markdown
# Spec: {Task Title}

## What

What this feature does, who it's for, and why it matters.
One paragraph. If you can't explain it in one paragraph, the scope is too big.

## Rules

The things that must be true when this feature is done. Each rule is a testable assertion.

- **R-001**: {testable statement} — e.g., "submitting the form with an empty email field shows a validation error"
- **R-002**: {testable statement} — e.g., "uploading a file >10MB returns a 413 response"
- **R-003**: {testable statement}

Keep it concrete. "The UX should be good" is not a rule. "The loading state appears within 200ms of form submission" is.

## Won't Do

What this feature explicitly does NOT cover. Prevents scope creep.

- {thing that's out of scope}
- {another thing}

## Risks

What could go wrong. Not a threat model — just the things you're worried about.

- {risk} — {mitigation or "accepted"}
- {risk} — {mitigation}

## Open Questions

Things to resolve before or during implementation. If any remain when /ctdd starts, they become decisions the implementing agent makes — which may be wrong.

- {question}
```

### Workflow State (`.claude/artifacts/workflow-state-{branch-slug}.json`)

```json
{
  "phase": "spec | review | tdd-tests | tdd-impl | tdd-qa | done",
  "task": "human-readable task description",
  "spec_file": "docs/specs/task-slug.md",
  "started_at": "ISO timestamp",
  "phase_entered_at": "ISO timestamp",
  "branch": "feature/branch-name",
  "qa_rounds": 0
}
```

---

## Skills

### Skill 1: `/cspec`

**Purpose**: Turn a feature idea into a short spec with testable rules before any code is written.

**Frontmatter**:
```yaml
---
name: spec
description: Create a short specification with testable rules for a new feature. Use before starting any feature work.
allowed-tools: Read, Grep, Glob, Bash(git log*), Bash(git diff*)
model: claude-opus-4-6
---
```

**Reads**:
- `ARCHITECTURE.md`
- `AGENT_CONTEXT.md`
- `.claude/antipatterns.md`
- Relevant source code (grep/glob based on feature description)

**Produces**:
- `docs/specs/{task-slug}.md`
- Updates workflow state to phase: `spec`

**Behavior**:

1. **Understand the context**. Read ARCHITECTURE.md and AGENT_CONTEXT.md. Scan relevant code areas.

2. **Ask what they're building**. Get enough detail to write the spec. Batch related questions — don't force unnecessary round trips. For a developer who clearly knows what they want, one or two exchanges is enough.

3. **Draft the spec**. Write all five sections. For each rule, make sure it's actually testable — if you can't describe a test for it, rewrite it until you can.

4. **Check antipatterns**. For each AP-xxx entry, ask: does this feature risk repeating this bug class? If yes, add a rule that prevents it.

5. **Present to human**. Walk through the rules. Human approves, adjusts, or rejects.

**Constraints**:
- NEVER write code. This skill produces a spec, nothing else.
- Every rule MUST be testable. No vague aspirations.
- If on main branch, tell the user to create a feature branch first.

**Phase transition**: Human approves → state moves to `review`.

---

### Skill 2: `/creview`

**Purpose**: A skeptical second look at the spec by a fresh agent that didn't write it. Not a multi-agent debate — a structured review that assumes the spec is incomplete and looks for what's missing.

**Frontmatter**:
```yaml
---
name: review
description: Skeptically review a spec for unstated assumptions, untestable rules, and missing edge cases. Run after /cspec.
allowed-tools: Read, Grep, Glob
model: claude-opus-4-6
context: fork
---
```

**Agent separation**: the review agent MUST be a fresh forked context — it did NOT write the spec. The spec author's lens is "here's my complete design." The reviewer's lens is "what did the author miss?" These lenses are incompatible in the same agent.

**Reads**:
- The spec artifact
- `ARCHITECTURE.md`
- `.claude/antipatterns.md`
- Relevant source code

**Produces**:
- Revised spec (updated in place)
- Updates workflow state

**Behavior**:

The reviewer checks four things:

1. **Assumptions**: what does this spec assume that isn't stated? Does it assume the database is available? That the user is authenticated? That the input is valid? Each unstated assumption either gets added as a rule or noted as accepted.

2. **Testability**: for each rule, can you actually write a test for this? If a rule says "the API responds quickly" — that's not testable. "The API responds in under 500ms for the 95th percentile" is. Flag and rewrite vague rules.

3. **Edge cases**: what happens at the boundaries? Empty input, maximum input, concurrent access, network failure, partial success. The reviewer picks the 3-5 most likely edge cases and asks whether the spec covers them.

4. **Antipattern check**: does this feature match any pattern in the antipatterns list? If the project has historically had issues with, say, forgetting to handle the loading state — check whether this spec has a rule for loading states.

Present findings to the human. Incorporate approved changes into the spec.

**Phase transition**: Human approves revised spec → state moves to `tdd-tests`.

---

### Skill 3: `/ctdd`

**Purpose**: Enforced test-driven development. Tests first, then implementation.

**Frontmatter**:
```yaml
---
name: tdd
description: Enforced TDD workflow. Write failing tests from spec rules, then implement. Use after /creview approves a spec.
model: claude-sonnet-4-6
agent: general-purpose
---
```

Note: the `/ctdd` skill itself runs on Sonnet as the orchestrator. It spawns the test agent on Opus (careful test design) and the implementation agent on Sonnet (mechanical implementation). The QA agent runs on Sonnet.

**Reads**:
- Approved spec artifact
- `.claude/workflow-config.json`
- `ARCHITECTURE.md`

**Produces**:
- Test files (each test references the spec rule it tests, e.g., `// Tests R-001`)
- Implementation files
- Workflow state updates

**Agent separation**: the RED phase (test writing) and GREEN phase (implementation) MUST be executed by different subagents. If the same agent writes both the tests and the implementation, it will write tests that are easy to satisfy, or implement code that games the specific test cases rather than satisfying the rules broadly. The `/ctdd` orchestrator spawns a test agent for RED and a separate implementation agent for GREEN. The test agent sees the spec rules but no implementation plan. The implementation agent sees the failing tests and the spec but didn't write the tests. The QA phase is a third agent, independent of both.

#### Phase: `tdd-tests` (RED)

**Executed by**: test agent (forked subagent, uses Opus for careful test design).

Write tests for the spec's rules. Each test references the rule ID it covers.

**Allowed file operations** (enforced by hook):
- Create/edit test files
- Create/edit source files ONLY for structural stubs containing `STUB:TDD`
- BLOCKED: source file edits with implementation logic

**Gate to next phase**: at least one test file exists AND tests fail (not build error).

#### Phase: `tdd-impl` (GREEN)

**Executed by**: implementation agent (separate forked subagent, uses Sonnet — did NOT write the tests).

Implement to make tests pass.

**Allowed file operations**:
- Create/edit any file
- Test file edits are logged (reason required — acceptable: test had a bug, needed updated fixture. Unacceptable: weakening an assertion to make it pass, deleting a "too strict" test.)

**Behavior**:
- Implement specifically to make the failing tests pass
- Each implementation decision should trace back to a spec rule
- Before advancing: run tests, confirm all pass
- Suggest running `/simplify` before QA: "Tests pass. Consider running `/simplify` to clean up before QA."

**Gate to next phase**: tests pass.

#### Phase: `tdd-qa` (QA)

**Executed by**: QA agent (third forked subagent — did NOT write the tests or the implementation).

Skeptical review of the implementation. The QA agent's lens: "This code is suspect. The tests might be too easy. The implementation might satisfy the test cases without actually satisfying the rules. Find what's wrong."

**Allowed file operations**:
- BLOCKED: all source and test file edits

**Behavior**:
- For each rule R-xxx in the spec: is there a test that covers it? Does the implementation *actually* satisfy the rule, or does it just pass the specific test cases? Probe the gap.
- Review the test-edit log: did the implementation agent weaken any tests? Flag any assertion that became less strict.
- Check for obvious issues: unclosed resources, missing error handling, hardcoded values that should be config
- Check antipatterns list — does the implementation exhibit any known bad patterns?
- If issues found: transition back to `tdd-impl` for fixes, then re-run QA
- If clean after `min_qa_rounds`: transition to `done`

**Gate to done**: zero blocking issues AND `qa_rounds >= min_qa_rounds`.

#### Enforcement: `workflow-gate.sh` (PreToolUse hook)

Same concept as Correctless but simpler. Reads the branch-scoped state file, blocks file operations that violate the current phase.

**Implementation note**: a Go or Python binary is recommended over bash for reliability. The spec describes behavior, not implementation language.

- Blocks direct edits to state files
- Classifies files as test/source/other based on `patterns.*` from config
- RED phase: blocks source edits unless file contains `STUB:TDD`
- QA phase: blocks all source and test edits
- No state file: everything allowed (backward compat)
- Catches common bash write bypasses (`>`, `>>`, `sed -i` targeting source files) — this is an accidental-violation catcher, not a security boundary

#### Enforcement: `workflow-advance.sh`

State transitions with validation:

- `init "task description"` — creates state file. Refuses if on main branch.
- `tests` — spec → tdd-tests (requires spec exists)
- `impl` — tdd-tests → tdd-impl (requires tests exist and fail)
- `qa` — tdd-impl → tdd-qa (requires tests pass)
- `fix` — tdd-qa → tdd-impl (issues found)
- `done` — tdd-qa → done (zero issues, min rounds met, state persists until merge)
- `spec-update "reason"` — tdd-tests|tdd-impl|tdd-qa → spec (when a rule turns out to be wrong mid-implementation. Logs the reason, preserves all TDD state. Edit the spec's rules, then `workflow-advance.sh tests` to resume. In Lite, no re-review is required — just update the rules and continue. If you're doing this more than twice per feature, the spec was under-baked.)
- `reset` — any → none (escape hatch)
- `override "reason"` — disables gate for next 10 tool calls, logged
- `diagnose "filepath"` — shows why a file would be blocked
- `status` — prints current state

---

### Skill 4: `/cverify`

**Purpose**: Quick post-implementation check that what you built matches what you specced.

**Agent separation**: run `/cverify` as a fresh session or forked subagent, NOT in the same session that did the implementation. The implementing agent knows where it cut corners — a fresh agent checks the spec against the code without that insider knowledge.

**Frontmatter**:
```yaml
---
name: verify
description: Verify implementation matches spec. Check rule coverage, undocumented dependencies, and basic code quality. Run after /ctdd completes.
allowed-tools: Read, Grep, Glob, Bash(commands.test*)
model: claude-sonnet-4-6
---
```

**Reads**:
- Spec artifact
- Implementation (changed files on branch)
- Test files
- `ARCHITECTURE.md`

**Produces**:
- Verification summary (printed, not a file — keep it lightweight)
- Proposed ARCHITECTURE.md updates if new patterns emerged

**Behavior**:

The verify agent's lens: "The tests pass and QA approved — but does the implementation *actually* satisfy the spec, or does it just satisfy the test cases?"

1. **Rule coverage**: for each R-xxx in the spec, is there a test that references it? For covered rules: does the test actually probe the rule, or is it a trivial assertion that would pass even if the rule were violated? Result: table of R-xxx → test → covered/uncovered/weak.

2. **Dependency check**: diff package manifest (package.json, go.mod, etc.) against base branch. Flag new dependencies with what they're used for.

3. **Architecture compliance**: does the implementation follow the patterns in ARCHITECTURE.md? If it introduces a new pattern, suggest adding it.

4. **Basic smell check**: obvious issues that QA might have missed — TODO comments that should be addressed, console.log/print statements left in, commented-out code blocks, overly broad error catches.

5. **Report**: print a summary. Pass/fail with details. If new patterns were introduced, suggest running `/cdocs` to update ARCHITECTURE.md.

---

### Skill 5: `/cdocs`

**Purpose**: Keep README, AGENT_CONTEXT.md, and feature docs current after features land.

**Frontmatter**:
```yaml
---
name: docs
description: Update project documentation after a feature lands. Updates README, AGENT_CONTEXT.md, and feature docs. Run before merging.
allowed-tools: Read, Grep, Glob, Write(docs/*), Write(README.md), Write(ARCHITECTURE.md), Write(AGENT_CONTEXT.md)
model: claude-sonnet-4-6
---
```

**Reads**:
- Recent git history
- Changed files on branch
- Existing docs
- `ARCHITECTURE.md`
- `AGENT_CONTEXT.md`

**Produces**:
- Updated README.md (if features changed)
- Updated AGENT_CONTEXT.md
- New/updated feature docs in `docs/`
- Proposed ARCHITECTURE.md additions

**Behavior**:

1. **What changed?** Diff against main. Identify new features, changed behavior, new config options.

2. **README**: is the feature list current? Are setup instructions still accurate? Update if needed.

3. **AGENT_CONTEXT.md**: update the components table, design patterns, common pitfalls, current state, and quick reference. This is the file that fresh agents read first — keep it current.

4. **Feature docs**: for significant features, create or update a doc in `docs/`. Structure: what it does, how to use it, configuration, examples.

5. **ARCHITECTURE.md**: if the feature introduced new patterns or conventions, suggest additions. Present each to the human for approval.

6. **Fact-check** (via separate subagent). After writing doc updates, a separate subagent reads the new documentation and spot-checks claims against actual code. Does the API accept those parameters? Does the config default to what the doc says? Catches plausible-but-wrong documentation written from spec understanding rather than actual implementation.

Present all changes for human approval before committing.

---

## Agent Context File: `AGENT_CONTEXT.md`

Same concept as Correctless, shorter. Target: under 1500 words.

```markdown
# Agent Context — {Project Name}

> Last updated: {date}

## What This Project Does
{2-3 sentences}

## Key Components
| Component | Location | Purpose |
|-----------|----------|---------|
| ... | ... | ... |

## Design Patterns
- **Pattern**: {what} — {convention} — example: {file path}
- ...

## Common Pitfalls
- **Pitfall**: {what goes wrong} — **Instead**: {correct approach}
- ...

## Quick Reference
| Need to... | Do this |
|------------|---------|
| Run tests | `{command}` |
| Build | `{command}` |
| Lint | `{command}` |
| Find a spec | `docs/specs/{feature}.md` |
```

---

## File Hierarchy

```
project-root/
├── README.md
├── ARCHITECTURE.md
├── AGENT_CONTEXT.md
├── CLAUDE.md
│
├── docs/
│   ├── specs/                    # committed — spec artifacts
│   │   └── user-registration.md
│   └── features/                 # committed — feature docs
│       └── auth-flow.md
│
├── .claude/
│   ├── workflow-config.json      # committed
│   ├── antipatterns.md           # committed
│   │
│   ├── skills/workflow/          # committed — Correctless Lite
│   │   ├── setup
│   │   ├── SKILL.md              # (or individual skill dirs)
│   │   └── hooks/
│   │       ├── workflow-gate.sh
│   │       └── workflow-advance.sh
│   │
│   └── artifacts/                # GITIGNORED
│       └── workflow-state-*.json
```

`.gitignore` addition:
```
.claude/artifacts/
```

---

## Workflow Lifecycle

### Full feature flow:

```
git checkout -b feature/my-feature
  │
  ├── /cspec
  │   ├── Conversation about what you're building
  │   ├── Produces: docs/specs/my-feature.md
  │   └── Human approves spec
  │
  ├── /creview
  │   ├── Single-pass review: assumptions, testability, edge cases, antipatterns
  │   ├── Spec revised with findings
  │   └── Human approves
  │
  ├── /ctdd
  │   ├── RED: write failing tests (source edits blocked)
  │   ├── GREEN: implement to make tests pass
  │   ├── QA: quick check against spec (edits blocked)
  │   ├── SPEC-UPDATE (if a rule is wrong): edit spec, resume from RED
  │   └── Done
  │
  ├── /cverify
  │   ├── Rule coverage check
  │   ├── Dependency check
  │   ├── Architecture compliance
  │   └── Smell check
  │
  ├── /cdocs (update docs before merge)
  │
  └── Merge to main
```

### Lighter workflows:

Not everything needs the full pipeline:

- **Bug fix**: `/ctdd` only (skip spec/review if the fix is obvious)
- **Config/docs change**: no workflow needed
- **Refactor**: `/ctdd` (existing tests should keep passing) + `/cverify`
- **New feature**: full pipeline

The workflow only activates when you create a state file via `/cspec` or `/ctdd init`. If you don't invoke these, there's no gating — you edit files normally.

**If you get stuck**: if the gate is blocking a legitimate edit (pattern matching bug, edge case), run `workflow-advance.sh override "reason"` to temporarily bypass it for 10 tool calls. Use `workflow-advance.sh diagnose "filepath"` to understand why something is blocked. Use `reset` only as a last resort — it removes all workflow state for the current branch.

---

## Installation & Setup

```bash
git clone https://github.com/joshft/correctless.git .claude/skills/workflow
cd .claude/skills/workflow && ./setup
```

The `setup` script:
1. Detects language and test runner
2. Generates `.claude/workflow-config.json` with detected values
3. Registers the PreToolUse hook in `.claude/settings.json`
4. Registers slash commands
5. Creates ARCHITECTURE.md template (if missing)
6. Creates AGENT_CONTEXT.md template (if missing)
7. Creates `.claude/antipatterns.md` template (if missing)
8. Creates directory structure (`docs/specs/`, `.claude/artifacts/`)
9. Updates `.gitignore`
10. Appends Correctless Lite section to `CLAUDE.md`

**Idempotent** — re-running never overwrites user-edited files.

**For teammates**: if Correctless Lite is committed to the repo, teammates run `./setup` to register hooks locally.

**Updating**: `cd .claude/skills/workflow && git pull && ./setup`

---

## Differences from Full Suite

| Feature | Lite | Full |
|---------|------|------|
| Spec format | 5 sections, simple rules | 12+ sections, typed invariants with IDs |
| Review | Single-pass, one agent | Agent team (4 agents), adversarial |
| Formal modeling (Alloy) | No | Optional |
| STRIDE threat analysis | No | At high/critical intensity |
| TDD enforcement | Yes (hooks + agent separation) | Yes (hooks + frontmatter allowed-tools + agent separation) |
| Mutation testing | No | Deterministic tools + LLM fallback |
| Convergence audit | No | Multi-round with fresh agents |
| External model review | No | Configurable (Codex, Gemini) |
| Drift debt tracking | No | Yes |
| Meta-verification | No | Yes (workflow-effectiveness.json) |
| Antipatterns | Yes (simple) | Yes (structured AP-xxx with categories) |
| Property-based testing | No | Language-specific helpers |
| Complexity budget | No | Yes |
| Polyglot scoping | No | Yes |
| Fail-closed mode | No | At high/critical intensity |
| Intensity levels | No (one size) | 4 levels (low/standard/high/critical) |
| Agent context file | Yes | Yes |
| Documentation skill | Yes | Yes |
| Postmortem skill | No | Yes |
| Cost | ~5 min overhead per feature | ~15-30 min overhead per feature |

### Upgrading to Correctless

When your project grows into something that needs higher assurance — handling user data, processing payments, security-sensitive logic — you can upgrade:

1. Install Correctless alongside or replacing the lite version
2. Run `/csetup` — it detects your existing ARCHITECTURE.md, antipatterns, and specs
3. Existing specs can be enhanced with the full invariant format incrementally
4. Existing antipatterns carry over directly (add category and phase fields)
5. The transition is gradual — you don't need to re-spec every feature at once

---

## Files to Create

| File | Purpose |
|------|---------|
| `setup` | Install script (auto-detection + scaffolding) |
| `.claude/skills/workflow/spec/SKILL.md` | `/cspec` skill |
| `.claude/skills/workflow/review/SKILL.md` | `/creview` skill |
| `.claude/skills/workflow/tdd/SKILL.md` | `/ctdd` skill |
| `.claude/skills/workflow/verify/SKILL.md` | `/cverify` skill |
| `.claude/skills/workflow/docs/SKILL.md` | `/cdocs` skill |
| `.claude/skills/workflow/hooks/workflow-gate.sh` | PreToolUse hook |
| `.claude/skills/workflow/hooks/workflow-advance.sh` | State transition script |
| `ARCHITECTURE.md` | Template |
| `AGENT_CONTEXT.md` | Template |
| `.claude/workflow-config.json` | Template |
| `.claude/antipatterns.md` | Empty template |

## Implementation Order

1. `setup` script — detection, scaffolding, hook registration
2. `workflow-gate.sh` — phase-based edit gating
3. `workflow-advance.sh` — state machine with all transitions
4. `/cspec` skill
5. `/creview` skill
6. `/ctdd` skill
7. `/cverify` skill
8. `/cdocs` skill
9. Templates (ARCHITECTURE.md, AGENT_CONTEXT.md, antipatterns.md)
10. End-to-end test on a real feature
