# Correctless: Correctness-Oriented Development Workflow

> **Note:** This is the original design specification. The implementation has evolved — 3 skills were added (/cdevadv, /credteam, /cstatus), the bounty/penalty economics were refined, and several feedback loops were closed. See the [README](README.md) and the actual [skill files](skills/) for the current implementation.



## Overview

A set of composable Claude Code skills that enforce a rigorous development workflow optimized for correctness over speed. Designed for projects where bugs are not technical debt but security vulnerabilities, data corruption, or silent failures.

The workflow: **Spec → Model → Review → Implement (TDD) → Verify → Document → Audit**

Each skill produces structured artifacts that downstream skills consume. The artifact format at each phase boundary is a contract — changing it requires updating all consumers.

### Core Design Principle: The Lens Determines What the Agent Finds

LLMs are prone to confirmation bias. An agent told to *build* something sees code as a thing to complete — it confirms its own implementation decisions. An agent told to *verify* something sees it as a thing to check — it's more critical, but still inclined toward the happy path. An agent told to *break* something sees it as a thing to attack — it finds failure modes that the builder and verifier never considered. Same model, same weights, same code — radically different outputs because the framing determines what the agent looks for, and confirmation bias means it finds what it's looking for.

This principle drives every design decision about agent separation in this workflow:

- **Spec and review are separate agents** — the spec author is biased toward the quality of their own invariants. A fresh reviewer with a "find the gaps" lens catches what the author missed.
- **RED and GREEN are separate agents** — the test writer doesn't know the implementation plan, so it writes tests from the *spec's* perspective, not the *implementer's* convenience. The implementer didn't write the tests, so it can't exploit knowledge of what's covered and what isn't.
- **QA is a third agent** — it didn't write the tests or the implementation, so it has no ownership bias toward either. Its "find problems" lens treats both the tests and the code as suspect.
- **Verify is a fresh agent** — it didn't participate in implementation, so it doesn't unconsciously skip the areas where it knows coverage is thin.
- **Audit agents have narrow, hostile lenses** — a concurrency specialist finds race conditions because it sees every shared variable as suspicious. A cleanup specialist finds resource leaks because it traces every allocation to its release. Each lens biases the agent toward finding a specific category of bug, and that bias is a feature.

The implication: **never let an agent grade its own work, and always give review agents an explicitly adversarial or skeptical framing.** A "review this code" prompt produces weaker results than "find the ways this code fails under concurrent access." The lens is the mechanism.

### Quick Start

```bash
# 1. Add to your project (30 seconds)
# Replace joshft/correctless with the actual repo URL
git clone https://github.com/joshft/correctless.git .claude/skills/workflow
cd .claude/skills/workflow && ./setup

# 2. Review the generated config
# setup auto-detects your language, test runner, and available tools

# 3. Fill in your architecture (start small — one trust boundary, one core abstraction)
/csetup  # in Claude Code — interactive config + ARCHITECTURE.md bootstrapping

# 4. Start building
git checkout -b feature/my-feature
/cspec
```

See [Installation & Setup](#installation--setup) for full details.

### What to Expect

The workflow reduces bugs — it doesn't eliminate them. The first 3-5 features are a calibration period: antipatterns are empty, invariant templates are generic, and the meta-verification loop has no history to learn from. During this period, the immediate value comes from `/creview-spec` agents finding unstated assumptions, the testability auditor flagging untestable invariants, and the mutation testing revealing test coverage gaps. These produce value on the first use.

After the first month (roughly 5-10 features through the pipeline), the compounding effects kick in: antipatterns accumulate from real bugs, templates get refined from postmortems, and the workflow-effectiveness tracking shows which phases are catching what. The system gets meaningfully better the more you use it.

For teams where only one developer uses the full workflow: the artifacts (specs as design docs, antipatterns as review checklists, ARCHITECTURE.md as onboarding material) are useful to teammates reading PRs even if they never install the suite themselves.

---

## Project Configuration

### `.claude/workflow-config.json`

Every project declares its language-specific commands and workflow preferences. Skills read this file and refuse to run if it's missing or incomplete.

```json
{
  "project": {
    "name": "string — project name",
    "language": "go | python | typescript | rust | java | other",
    "description": "one-line description of what this project does"
  },
  "commands": {
    "test": "go test ./...",
    "test_json": "go test -json ./...",
    "test_race": "go test -race -short ./...",
    "test_verbose": "go test -v ./...",
    "coverage": "go test -coverprofile=coverage.out ./...",
    "lint": "go vet ./...",
    "build": "go build ./...",
    "format": "gofmt -w .",
    "mutation_tool": "go-mutesting --no-exec-command"
  },
  "patterns": {
    "test_file": "*_test.go",
    "source_file": "*.go",
    "test_fail_pattern": "FAIL",
    "build_error_pattern": "cannot|undefined|syntax error"
  },
  "workflow": {
    "intensity": "standard",
    "min_qa_rounds": 2,
    "max_audit_rounds": 5,
    "require_external_review": false,
    "external_models": {
      "codex": {"command": "codex exec \"{prompt}\" --sandbox read-only", "stdin_file": true, "timeout_seconds": 300},
      "gemini": {"command": "gemini \"{prompt}\"", "stdin_file": true, "timeout_seconds": 300}
    },
    "external_review_threshold": "high",
    "mutation_count": 10,
    "require_stride": true,
    "formal_model": false,
    "alloy_jar": null,
    "auto_update_antipatterns": true,
    "fail_closed_when_no_state": false,
    "merge_strategy": "squash"
  },
  "paths": {
    "architecture_doc": "ARCHITECTURE.md",
    "agent_context": "AGENT_CONTEXT.md",
    "antipatterns": ".claude/antipatterns.md",
    "docs": "docs/",
    "diagrams": "docs/diagrams/",
    "specs": "docs/specs/",
    "models": "docs/models/",
    "meta": ".claude/meta/",
    "artifacts": ".claude/artifacts/",
    "state": ".claude/artifacts/workflow-state-{branch-slug}.json"
  }
}
```

Note: the state file is branch-scoped. The `{branch-slug}` is derived from the current branch name (e.g., `feature/localhost-inspection` → `workflow-state-feature-localhost-inspection.json`). This allows parallel feature development in git worktrees — each branch has its own state file. The `workflow-advance.sh` script computes the slug from `git branch --show-current` on every invocation.

### File Hierarchy

```
project-root/
│
├── README.md                          # committed — human-facing project overview
├── ARCHITECTURE.md                    # committed — structured trust boundaries, abstractions, patterns
├── AGENT_CONTEXT.md                   # committed — agent onboarding brief
├── CLAUDE.md                          # committed — behavioral instructions for Claude
│
├── docs/                              # committed — all permanent documentation
│   ├── specs/                         # committed — spec artifacts (document of intent)
│   │   ├── localhost-inspection.md
│   │   └── sens052-rule.md
│   ├── models/                        # committed — Alloy models (formal analysis record)
│   │   ├── localhost-inspection.als
│   │   └── localhost-inspection-results.md
│   ├── diagrams/                      # committed — Mermaid architecture diagrams
│   │   ├── system-overview.mermaid
│   │   ├── data-flow.mermaid
│   │   └── trust-boundaries.mermaid
│   ├── features/                      # committed — feature documentation
│   │   ├── traffic-inspection.md
│   │   └── detection-rules.md
│   ├── verification/                  # committed — verification reports
│   │   └── localhost-inspection-verification.md
│   └── decisions/                     # committed — design decision records (optional)
│       └── 001-packet-marks-over-uid.md
│
├── .claude/
│   ├── workflow-config.json           # committed — project workflow configuration
│   ├── antipatterns.md                # committed — living bug class checklist (AP-xxx)
│   │
│   ├── skills/workflow/               # committed — Correctless skill suite (cloned repo)
│   │   ├── setup                      # install script
│   │   ├── spec/SKILL.md
│   │   ├── model/SKILL.md
│   │   ├── review-spec/SKILL.md
│   │   ├── tdd/SKILL.md
│   │   ├── verify/SKILL.md
│   │   ├── audit/SKILL.md
│   │   ├── update-arch/SKILL.md
│   │   ├── docs/SKILL.md
│   │   ├── setup-skill/SKILL.md
│   │   ├── postmortem/SKILL.md
│   │   └── hooks/
│   │       ├── workflow-gate.sh
│   │       └── workflow-advance.sh
│   │
│   ├── templates/                     # committed — invariant templates
│   │   └── invariants/
│   │       ├── concurrency.md
│   │       ├── resource-lifecycle.md
│   │       ├── config-lifecycle.md
│   │       ├── network-protocol.md
│   │       ├── security-detection.md
│   │       └── data-integrity.md
│   │
│   ├── helpers/                       # committed — PBT language helpers
│   │   ├── pbt-go.md
│   │   ├── pbt-python.md
│   │   ├── pbt-typescript.md
│   │   └── pbt-rust.md
│   │
│   ├── meta/                          # committed — workflow learning data
│   │   ├── workflow-effectiveness.json
│   │   ├── drift-debt.json
│   │   └── external-review-history.json
│   │
│   └── artifacts/                     # GITIGNORED — transient working state
│       ├── workflow-state-*.json       # branch-scoped phase state (one per active branch)
│       ├── tdd-test-edits.log         # test file edit log during impl phase
│       ├── coverage-baseline.out      # coverage snapshot at impl→qa transition
│       ├── findings/                  # per-round audit/QA findings
│       │   ├── localhost-inspection-round-1.json
│       │   ├── localhost-inspection-round-2.json
│       │   └── localhost-inspection-fixes-round-1.json
│       └── reviews/                   # spec review records
│           ├── localhost-inspection-review.json
│           └── localhost-inspection-external.json
```

### `.gitignore` additions

```gitignore
# Workflow artifacts (transient working state)
.claude/artifacts/
```

### Why specs and models are committed

Specs and Alloy models are **not** transient artifacts — they're documentation of intent and formal analysis. A future developer (or agent) looking at a feature should be able to read the spec that drove its implementation and the model that verified its design. They live in `docs/` alongside feature documentation and diagrams because they serve the same purpose: explaining why the code is the way it is.

Findings, review records, and workflow state are transient — they're working data from the process of building a feature. Once the feature merges, the findings have been resolved and the state file is deleted. They don't need to be in git history.

### `ARCHITECTURE.md`

Structured document that every spec-phase skill reads. Not prose — structured sections the skills parse.

**Size guidance**: target under 5000 words. When it grows beyond this, fragment it: move each section into its own file under `docs/architecture/` (e.g., `docs/architecture/trust-boundaries.md`, `docs/architecture/abstractions.md`) and have the root ARCHITECTURE.md link to them. Skills load only the sections relevant to the current spec's referenced TB-xxx, ABS-xxx, PAT-xxx, and ENV-xxx entries — not the entire file. This prevents context window pressure on large projects.

**Cold start**: you do NOT need to fill this in completely before using the workflow. Start with your single most critical trust boundary and one core abstraction. The `/cupdate-arch` skill adds new entries after each feature, and the `/csetup` bootstrap can suggest initial entries by scanning your codebase. ARCHITECTURE.md grows organically through use — a half-empty file that covers the boundaries you're actively working on is far more useful than a comprehensive document you never wrote.

```markdown
# Architecture

## Trust Boundaries

Each entry defines where privilege, identity, or data sensitivity changes.

### TB-001: External Client → Proxy Ingress
- **Crosses**: network boundary, TLS termination
- **Identity assertion**: client certificate or SNI
- **Data sensitivity change**: untrusted → inspected
- **Invariant**: plaintext from inspection MUST NOT be accessible outside the inspection goroutine
- **Violated when**: inspection buffer is shared, logged, or passed by reference to non-inspection code

### TB-002: ...

## Core Abstractions

Each entry defines an abstraction, its invariant, and where the invariant is enforced.

### ABS-001: Outbound Dialer
- **What**: all outbound connections go through the dialer, never net.Dial directly
- **Invariant**: every outbound connection has SO_MARK set
- **Enforced at**: pkg/dialer/dial.go
- **Violated when**: any code path calls net.Dial, net.DialContext, or tls.Dial directly
- **Test**: grep for direct dial calls outside pkg/dialer/ should return zero results

### ABS-002: ...

## Design Patterns

Patterns in use and their constraints. New features must compose with these.

### PAT-001: Config Lifecycle
- **Pattern**: normalize-at-parse
- **Rule**: every config field must appear in: raw struct, parse, save, defaults, validation, SIGHUP reload
- **Violated when**: a new config field is added to fewer than all six locations
- **Test**: config struct field count == parse function field count == save function field count (etc.)

### PAT-002: ...

## Environment Assumptions

What the project assumes about its runtime environment. Each assumption documents what happens when it's violated.

### ENV-001: Dedicated UID
- **Assumes**: process runs as a dedicated UID for iptables exclusion
- **Violated when**: process runs as root alongside other root processes
- **Consequence**: iptables UID match hits all root traffic, causing loops
- **Mitigation**: use packet marks (SO_MARK) instead of UID matching
- **Status**: mitigated in v2.1, ENV assumption kept for documentation

### ENV-002: ...
```

### `.claude/antipatterns.md`

Living checklist. Starts empty for new projects. Grows with every bug found post-verification.

```markdown
# Antipatterns — [Project Name]

Every item here is a bug class that escaped verification at least once.
All QA, spec, and review skills reference this file.
Invariants can reference antipattern IDs directly (e.g., "guards against AP-003").

## How to add entries
- After any bug found post-verification, add an entry with the next AP-xxx ID
- Include: what went wrong, which phase should have caught it, the check that would have caught it
- Reference the spec/finding ID where the bug was first identified
- The /caudit skill and /cspec skill both read this file — new entries are automatically checked in future work

## Entries

### AP-001: {short descriptive name}
- **Category**: concurrency | resource-leak | parity | security | config | data-integrity
- **Description**: {what went wrong}
- **First seen**: {date} — {spec ID or finding ID}
- **Phase that missed it**: {spec | review-spec | tdd-qa | verify | audit}
- **Why missed**: {explanation}
- **Detection**: {the check that catches this — grep pattern, test pattern, invariant template item}
- **Frequency**: {how many times this pattern has been seen — updated when recurrences found}

(grows organically — start empty)
```

---

## Artifact Formats

### Spec Artifact (`docs/specs/{task-slug}.md`)

Produced by `/cspec`. Consumed by `/creview-spec`, `/ctdd`, `/cverify`, `/caudit`.

**Artifact weight scales with intensity.** At `low` intensity, only Metadata, Context, Scope, Invariants, and Prohibitions are required — skip Complexity Budget, STRIDE Analysis, Boundary Conditions, Environment Assumptions, and Self-Assessment. At `standard`, add Boundary Conditions. At `high`/`critical`, all sections are required. This prevents a low-risk config change from generating a 12-section spec document that nobody reads.

```markdown
# Spec: {Task Title}

## Metadata
- **Created**: ISO timestamp
- **Author**: human + claude
- **Status**: draft | reviewed | approved | superseded
- **Supersedes**: (spec ID if this replaces a previous spec)
- **Impacts**: (list of other spec slugs whose invariants may be affected by this feature — e.g., if modifying traffic inspection could break assumptions in detection rules, list `detection-rules` here. `/cverify` checks impacted specs for drift when this feature merges.)
- **Branch**: feature branch name
- **Config**: path to workflow-config.json used

## Context
Brief prose description of what this feature does and why.
What problem does it solve? What's the user-facing or system-facing behavior change?

## Scope
What this spec covers and — critically — what it does NOT cover.
Explicit out-of-scope list prevents the implementing agent from gold-plating.

## Complexity Budget
Rough scale estimate. Gives review and audit agents a sense of proportionality.

- **Estimated new/changed LOC**: ~X
- **Files touched**: ~Y (list key files if known)
- **New abstractions introduced**: N (list them)
- **Trust boundaries touched**: N (list refs: TB-xxx)
- **Risk surface delta**: low | medium | high (does this expand the attack surface?)

## Design Decisions
Key decisions made during spec authoring, with rationale.
Each decision references the relevant ARCHITECTURE.md entry if applicable.

- **DD-001**: [decision] — because [rationale] — refs ABS-001
- **DD-002**: ...

## Invariants

Machine-parseable. Each invariant is a testable assertion.

### INV-001: {short name}
- **Type**: must | must-not
- **Category**: functional | security | concurrency | data-integrity | resource-lifecycle | parity
- **Statement**: {precise testable statement}
- **Boundary**: {which trust boundary or abstraction this relates to — ref TB-xxx or ABS-xxx}
- **Violated when**: {specific condition that breaks this invariant}
- **Guards against**: {ref AP-xxx if this invariant exists because of a known antipattern, null otherwise}
- **Test approach**: {how to verify — unit test, property-based test, integration test, manual}
- **Risk**: low | medium | high | critical
- **Needs external review**: true | false (auto-flagged by /cspec based on risk + category)
- **Implemented in**: {filled during GREEN phase — list of file paths where this invariant is enforced, e.g., `[pkg/dialer/dial.go:SetMark, pkg/proxy/connect.go:handleOutbound]`. Left blank during /cspec, auto-populated by /ctdd during implementation. Used by /cverify for targeted mutation, /caudit for scoping, and drift detection for orphan checking.}

### INV-002: ...

## Prohibitions

Things that must NEVER happen. Distinct from invariants because they're about absence, not presence.

### PRH-001: {short name}
- **Statement**: {what must never happen}
- **Detection**: {how to detect a violation — test, linter, grep, runtime check}
- **Consequence**: {what goes wrong if violated}

### PRH-002: ...

## Boundary Conditions

Where the feature interacts with trust boundaries, external systems, or environmental assumptions.

### BND-001: {short name}
- **Boundary**: {ref TB-xxx}
- **Input from**: {untrusted source}
- **Output to**: {trusted/untrusted destination}
- **Validation required**: {what must be checked}
- **Failure mode**: {what happens if validation fails — fail-open? fail-closed? passthrough?}

### BND-002: ...

## STRIDE Analysis

One entry per trust boundary this feature touches. Skip if workflow-config.json has require_stride: false.

### STRIDE for TB-001: {boundary name}
- **Spoofing**: {can an attacker impersonate a legitimate entity at this boundary? how?}
- **Tampering**: {can data be modified in transit or at rest? what's the integrity check?}
- **Repudiation**: {can an action be denied? is there an audit trail?}
- **Information Disclosure**: {can sensitive data leak across this boundary? what data?}
- **Denial of Service**: {can this boundary be overwhelmed? what's the rate limit / backpressure?}
- **Elevation of Privilege**: {can an unprivileged actor gain privilege through this boundary?}

### STRIDE for TB-002: ...

## Environment Assumptions

What this feature assumes about the runtime environment. Each assumption references ENV-xxx from ARCHITECTURE.md or introduces a new one.

- **EA-001**: {assumption} — refs ENV-001 — {what happens if wrong}
- **EA-002**: ...

## Open Questions

Things the spec author is uncertain about. These MUST be resolved before the spec moves to "approved" status. `/creview-spec` specifically targets these.

- **OQ-001**: {question} — {why it matters} — {candidate answers}
- **OQ-002**: ...

## Self-Assessment

Produced by the `/cspec` skill. Identifies which parts of this spec are least confident and why.

- **Highest risk invariants**: [INV-xxx, INV-xxx] — because {reason}
- **Assumptions most likely to be wrong**: [EA-xxx] — because {reason}
- **Areas where ARCHITECTURE.md has gaps**: {description}
- **Recommended for external review**: [INV-xxx, PRH-xxx] — because {reason}
```

### Findings Artifact (`.claude/artifacts/findings/{task-slug}-round-{N}.json`)

Produced by `/caudit` QA agents. Consumed by `/caudit` orchestrator, `/cverify`.

```json
{
  "task": "spec slug",
  "round": 1,
  "agent": "agent role identifier",
  "timestamp": "ISO timestamp",
  "findings": [
    {
      "id": "QA-{AGENT}-{NNN}",
      "severity": "critical | high | medium | low",
      "category": "concurrency | resource-leak | parity | security | logic | test-gap",
      "file": "path/to/file.go",
      "line_range": [100, 115],
      "description": "precise description of the issue",
      "reproduction": "steps or commands to reproduce",
      "proposed_fix": "suggested fix approach",
      "evidence": "command output, test result, or code reference",
      "invariant_ref": "INV-xxx if this maps to a spec invariant, null otherwise",
      "status": "open | fixed | disputed | dismissed",
      "reintroduced_from": "finding ID from a previous round if this is a regression of an earlier fix, null otherwise",
      "resolution": null
    }
  ]
}
```

### Resolution Artifact (`.claude/artifacts/findings/{task-slug}-fixes-round-{N}.json`)

Produced by fix agent during `/caudit` fix rounds.

```json
{
  "task": "spec slug",
  "round": 1,
  "fixes": [
    {
      "finding_id": "QA-CONC-001",
      "resolution": "fixed | wont-fix | not-a-bug",
      "description": "what was changed and why",
      "files_changed": ["path/to/file.go"],
      "test_added": "path/to/test_file.go:TestName or null"
    }
  ]
}
```

### Workflow State (`.claude/artifacts/workflow-state-{branch-slug}.json`)

Managed exclusively by the state transition script. No skill writes to this directly.

```json
{
  "phase": "spec | model | review-spec | tdd-tests | tdd-impl | tdd-qa | tdd-verify | audit | done",
  "task": "human-readable task description",
  "spec_file": "docs/specs/task-slug.md",
  "started_at": "ISO timestamp",
  "phase_entered_at": "ISO timestamp",
  "branch": "feature/branch-name",
  "default_branch": "main",
  "tdd": {
    "qa_rounds": 0,
    "is_fix_round": false,
    "coverage_baseline": null,
    "test_edit_count": 0
  },
  "audit": {
    "type": "qa | security | custom",
    "rounds_completed": 0,
    "total_findings": 0,
    "findings_fixed": 0,
    "converged": false
  },
  "review": {
    "internal_complete": false,
    "external_complete": false,
    "consensus_reached": false,
    "disputed_invariants": []
  },
  "spec_updates": {
    "count": 0,
    "history": [
      {
        "from_phase": "tdd-impl",
        "reason": "INV-003 is impossible to implement — SO_MARK requires CAP_NET_ADMIN which we don't have in container mode",
        "timestamp": "ISO timestamp",
        "invariants_changed": ["INV-003", "EA-002"]
      }
    ]
  }
}
```

---

## Skills

### Skill 1: `/cspec`

**Purpose**: Transform a feature idea into a structured specification with testable invariants, explicit prohibitions, boundary conditions, STRIDE analysis, and environment assumptions.

**Trigger**: Human describes a feature they want to build.

**Frontmatter** (SKILL.md):
```yaml
---
name: spec
description: Create a structured specification with testable invariants for a new feature. Use when planning any new feature, especially security-critical changes.
allowed-tools: Read, Grep, Glob, Bash(git log*), Bash(git diff*), Bash(git branch*)
model: claude-opus-4-6
context: fork
---
```

Note: all skills use frontmatter for `allowed-tools`, `model`, and `context` settings. See [Claude Code Native Feature Integration](#claude-code-native-feature-integration) for the full matrix. Only `/cspec` shows the example frontmatter here to avoid repetition — the implementation agent should apply the same pattern to all skills.

**Reads**:
- `ARCHITECTURE.md` — existing trust boundaries, abstractions, patterns, env assumptions
- `CLAUDE.md` — project conventions
- `AGENT_CONTEXT.md` — project overview for context
- `.claude/antipatterns.md` — known bug classes to spec against (AP-xxx entries)
- `.claude/meta/drift-debt.json` — outstanding drift debt (flag if new feature touches drifted code)
- `.claude/workflow-config.json` — project settings
- Relevant source code (via grep/glob based on feature description)
- Recent git history for the area being changed

**Produces**:
- `docs/specs/{task-slug}.md` — the spec artifact
- Updates `.claude/artifacts/workflow-state-{branch-slug}.json` to phase: `spec`

**Behavior**:

1. **Understand the project context**. Read ARCHITECTURE.md, CLAUDE.md, antipatterns. Run `git log --oneline -30` and `git diff --stat` to understand recent context. Grep/glob to map the codebase areas relevant to the feature.

2. **Ask the human what they're building**. Not a form — a conversation. But a directed one. The skill asks:
   - What is the feature? (functional description)
   - What is the adversary model? Who is trying to break this, and what capabilities do they have? (skip for non-security projects if require_stride is false)
   - What existing abstractions does this touch? (reference ARCHITECTURE.md entries)
   - What happens when this fails? (failure mode — fail-open, fail-closed, passthrough, crash)
   - What does "correct" mean for this feature? (the answer becomes invariants)
   - What must this feature NEVER do? (the answer becomes prohibitions)

3. **Draft the spec**. Write the full spec artifact with all sections. For each invariant, assess risk and flag whether it needs external review. Cross-reference every invariant against ARCHITECTURE.md — does it compose with existing abstractions or introduce a new one?

4. **Check against antipatterns**. For every AP-xxx entry in `.claude/antipatterns.md`, ask: does this feature introduce a new instance of this bug class? If yes, add a specific invariant or prohibition that prevents it, with `guards_against: AP-xxx` referencing the antipattern ID.

5. **Check drift debt**. Read `.claude/meta/drift-debt.json`. If any open drift debt items involve files or abstractions this feature touches, surface them: "This feature touches code with outstanding drift debt: DRIFT-001 — {description}. Consider resolving the drift as part of this feature, or add an invariant that accounts for the drifted state."

6. **No self-assessment**. The spec author does NOT assess the quality of their own spec. Self-assessment is biased — the agent that wrote an invariant won't flag it as weak. Instead, the self-assessment is produced by the first step of `/creview-spec`, where a fresh agent reads the spec cold and identifies weak points. This separation prevents the spec author from marking everything as low-risk and "doesn't need external review."

7. **Present to human for initial review**. Walk through the spec section by section. Don't dump it — present invariants one at a time or in small groups, ask for confirmation or correction. Open questions must be resolved before moving forward.

**Constraints**:
- NEVER write code. Not even test stubs. This skill produces a spec document, nothing else.
- NEVER skip the STRIDE analysis for features touching trust boundaries (unless require_stride is false).
- Every invariant MUST be testable. If you can't describe how to test it, it's not an invariant — it's a wish. Rewrite it until it's testable or remove it.
- Questions to the human should be **batched by theme** when the human clearly understands the domain (functional + failure modes together, adversary model + prohibitions together — typically 2-3 questions per batch). Reserve strict one-at-a-time for genuinely ambiguous answers that need follow-up before the next question makes sense. Read the human's expertise from AGENT_CONTEXT.md and the conversation tone — a product security engineer describing a network proxy doesn't need six sequential round trips before spec authoring begins.

**Phase transition**: Human approves the spec → state moves to `model` (if `workflow.formal_model` is true) or `review-spec` (if false).

---

### Skill 2: `/cmodel`

**Purpose**: Generate a formal Alloy model of the feature's security-relevant behavior and run the Alloy Analyzer to check spec invariants against the model. Finds design-level bugs before any code or tests are written by exhaustively exploring the state space.

**Trigger**: Spec approved by human, `workflow.formal_model` is true, state is `model`.

**When to use**: Features that involve state machines, protocol handling, access control, trust boundary transitions, or any behavior where you need to know "can the system ever reach a bad state." Not useful for purely functional transformations (data formatting, config parsing) where property-based testing covers the same ground with less effort.

**Reads**:
- The spec artifact from `/cspec` (invariants, prohibitions, trust boundaries, STRIDE analysis)
- `ARCHITECTURE.md` (trust boundaries, abstractions — for modeling existing system context)
- `AGENT_CONTEXT.md` (for understanding system structure)
- `.claude/workflow-config.json`

**Produces**:
- `docs/models/{task-slug}.als` — the Alloy model source file
- `docs/models/{task-slug}-results.md` — analysis results (counterexamples or clean run)
- Updated spec artifact if counterexamples found (new invariants, revised invariants, or design changes)

**Requires**:
- Alloy Analyzer installed (Java JAR — `java -jar org.alloytools.alloy.dist.jar`)
- Or: Alloy CLI (`alloy solve`) if available
- If Alloy is not installed, the skill generates the model file and reports: "Alloy model generated but analyzer not available. Install Alloy to run verification, or review the model manually."

**Behavior**:

1. **Identify modelable scope**. Not everything in the spec needs a formal model. The skill identifies which parts of the spec are amenable to Alloy modeling:
   - State machines and lifecycle transitions (connection states, request processing phases)
   - Trust boundary crossings (where does identity, privilege, or data sensitivity change?)
   - Access control and authorization logic (who can do what, under what conditions?)
   - Protocol interactions (message sequences, handshake flows, negotiation)
   - Resource ownership and cleanup (who holds a resource, when is it released, can it leak?)

   Skip: pure data transformations, config validation, numeric calculations (use PBT/SMT for those).

2. **Generate the Alloy model**. Translate the modelable scope into Alloy 6 syntax:

   **Signatures** map to entities in the system:
   ```alloy
   sig Connection {
     var state: one ConnectionState,
     var mark: lone PacketMark,
     origin: one Endpoint,
     destination: one Endpoint
   }

   sig Endpoint {}

   abstract sig ConnectionState {}
   one sig Incoming, Inspecting, Dialing, Established, Closed extends ConnectionState {}

   sig PacketMark {}
   one sig SO_MARK extends PacketMark {}
   ```

   **Facts** encode system rules (things that are always true):
   ```alloy
   // All outbound connections must go through the dialer
   fact dialerAbstraction {
     always all c: Connection |
       c.state = Dialing implies some c.mark
   }
   ```

   **Predicates** model transitions (things that can happen):
   ```alloy
   pred inspect[c: Connection] {
     c.state = Incoming
     c.state' = Inspecting
     c.mark' = c.mark  // mark unchanged
   }

   pred dial[c: Connection] {
     c.state = Inspecting
     c.state' = Dialing
     c.mark' = SO_MARK  // mark set on dial
   }
   ```

   **Assertions** encode spec invariants as checkable properties:
   ```alloy
   // INV-003: SO_MARK set on all outbound connections
   assert allOutboundMarked {
     always all c: Connection |
       c.state = Established implies c.mark = SO_MARK
   }
   check allOutboundMarked for 5

   // PRH-001: Plaintext never accessible outside inspection
   assert plaintextContained {
     always all c: Connection |
       c.state != Inspecting implies no plaintextAccessible[c]
   }
   check plaintextContained for 5
   ```

   **Attacker model** (for security features):
   ```alloy
   sig Attacker extends Endpoint {
     var spoofedSNI: lone SNIValue,
     var capabilities: set AttackCapability
   }

   abstract sig AttackCapability {}
   one sig CanSendArbitrarySNI, CanSendMalformedTLS, CanTriggerECH extends AttackCapability {}

   // Attacker can do anything within their capabilities
   pred attackerAction[a: Attacker] {
     CanSendArbitrarySNI in a.capabilities implies
       a.spoofedSNI' in SNIValue
   }
   ```

3. **Run the Alloy Analyzer**. For each assertion in the model:
   - Run `check assertionName for N` where N is the scope (start with 5, increase if no counterexample found)
   - **Auto-retry on syntax/type errors**: if the Alloy Analyzer returns a syntax error, type error, or other compilation failure, the skill feeds the exact error message back to the agent to fix the `.als` file and re-run. Up to 3 retry attempts before surfacing the error to the human. This is expected — Claude will occasionally get Alloy cardinality constraints (`some`/`all`/`lone`), signature hierarchies, or temporal operators wrong. The retry loop handles this without human involvement.
   - If a counterexample is found: the analyzer produces a concrete scenario where the invariant is violated
   - If no counterexample within scope: the invariant likely holds (bounded guarantee, not absolute proof)

4. **Interpret results** (via a separate interpretation agent).

   **Agent separation**: the agent that wrote the Alloy model should NOT interpret the counterexamples. The model author has the same blind spot that caused any modeling error — it'll interpret ambiguous traces through the lens of "my model is correct." A separate forked subagent (the **interpreter**) receives: the spec, the Alloy model (for reference), and the raw analyzer output. It translates counterexamples to domain-specific attack scenarios without having authored the model.

   **If counterexamples are found**:
   - Alloy's counterexample output is its own textual instance trace format, NOT structured JSON. The interpreter agent parses these traces and translates them back to domain terms. This translation is non-trivial and error-prone — the agent should present both the raw Alloy trace and its interpretation so the human can verify the translation.
   - For each counterexample, translate it back to a concrete scenario in the spec's terms: "An attacker with capability CanSendArbitrarySNI can create a Connection that reaches state Established without mark SO_MARK by: [step 1] → [step 2] → [step 3]"
   - Map the counterexample to the specific INV-xxx or PRH-xxx that was violated
   - Present to the human: "The Alloy model found a design flaw. INV-003 can be violated in this scenario: [description]. This means the spec needs revision before implementation."
   - Propose spec revisions: new invariants, tighter constraints, or design changes that close the gap
   - Human approves revisions → spec is updated

   **If no counterexamples found**:
   - Report: "Alloy checked {N} assertions across {scope} atoms with no counterexamples. The invariants are consistent with the model within this scope."
   - Note: this is a bounded guarantee. Alloy checks all instances up to the specified scope. Bugs may exist in larger configurations, though in practice most design flaws manifest in small scopes (the "small scope hypothesis").

5. **Model review**. Before treating results as definitive, the human should review the model itself:
   - Does the model faithfully represent the system? (Are there behaviors the model allows that the real system doesn't, or vice versa?)
   - Is the attacker model realistic? (Does it include all relevant capabilities?)
   - Are the assertions complete? (Do they cover all spec invariants, or were some too hard to model?)

   The skill explicitly asks the human: "Does this model accurately represent the feature? Are there behaviors I missed?" This is critical — a correct analysis of a wrong model is worse than no analysis.

**Constraints**:
- The model MUST be reviewable by the human. No opaque Alloy — keep it readable with comments explaining what each signature, fact, and assertion represents.
- Every assertion MUST reference the spec invariant ID it encodes (e.g., `// INV-003`).
- The skill MUST NOT claim an invariant is "proven" — Alloy provides bounded verification, not proof. Use language like "no counterexample found within scope N."
- If the feature doesn't have modelable security behavior (pure functional change, no state transitions, no trust boundaries), the skill should say so and recommend skipping to `/creview-spec`.

**Limitations to be honest about**:
- Alloy models are abstractions. They can't capture every detail of the Go runtime, the OS scheduler, or network timing. Concurrency bugs that depend on specific interleavings may not be expressible.
- The translation from spec invariants to Alloy assertions is done by Claude. The model could be wrong. **Step 5 (model review) is load-bearing, not optional.** A clean Alloy run on a wrong model is worse than no model at all — it creates false confidence. The human must review the model.
- Claude's reliability with Alloy 6 temporal operators (`always`, `after`, `until`, `eventually`) is inconsistent. Simple `always` properties work well. Complex nested temporal formulas or liveness properties are more likely to be subtly wrong. For complex temporal properties, 3 auto-retries may not be sufficient — if the model still fails after retries, present it to the human for manual correction rather than silently giving up.
- Alloy's counterexample traces are in Alloy's own textual format, not structured data. The agent's translation of traces to domain-specific attack scenarios is an additional point where errors can be introduced. Always present the raw trace alongside the interpretation.
- Alloy's bounded analysis means "no bug found in small scope," not "no bug exists." For most design-level flaws, the small scope hypothesis holds, but it's not a guarantee.

**Phase transition**: Model analysis complete (counterexamples resolved or none found) → state moves to `review-spec`.

---

### Skill 3: `/creview-spec`

**Purpose**: Multi-agent adversarial review of the spec. Surface unstated assumptions, challenge invariants, identify gaps in STRIDE analysis, verify testability of every invariant.

**Trigger**: Spec approved by human, state is `review-spec`.

**Reads**:
- The spec artifact from `/cspec`
- `ARCHITECTURE.md`
- `AGENT_CONTEXT.md` (provided to each review agent for project context)
- `.claude/antipatterns.md`
- `.claude/workflow-config.json`
- Relevant source code

**Produces**:
- Revised spec artifact (updated in place with review findings incorporated)
- `.claude/artifacts/reviews/{task-slug}-review.json` — structured review record
- Updates workflow state

**Behavior — Internal Review (Claude agent team)**:

**Step 0: Independent self-assessment (before agent team)**. A fresh subagent (forked context, did NOT author the spec) reads the spec cold and produces the self-assessment that the spec author was not allowed to write:
- Which invariants are hardest to test and why?
- Which assumptions are most likely wrong?
- Where does ARCHITECTURE.md have gaps relative to this spec?
- Which invariants should be flagged for external review?
- What's the overall risk profile?

This assessment is passed to the agent team members as input — it tells them where to focus their adversarial effort. The self-assessment subagent is incentivized differently from the spec author: it has no ownership of the invariants and no reason to rate them favorably.

**Step 1: Agent team review**. Spawn an agent team with the following teammates:

1. **Red Team Agent**
   - Prompt: "You are a security-focused adversary. Your job is to find attack paths, bypass vectors, and failure modes that the spec doesn't cover. For every trust boundary in the spec, describe how you would attack it. For every invariant, describe a scenario where it holds in tests but fails in production. Reference ARCHITECTURE.md for the project's existing security posture. IMPORTANT: evaluate the threat model specific to THIS system — if it's a network proxy, think about protocol-level attacks, not SQL injection. If it's a CLI tool, think about argument injection, not XSS. Your attack paths must be credible for the system described in the spec and AGENT_CONTEXT.md."
   - Receives: spec, ARCHITECTURE.md, AGENT_CONTEXT.md, relevant source
   - Produces: structured list of attack paths and gaps, each referencing specific INV/PRH/BND entries

2. **Assumptions Auditor**
   - Prompt: "You are an assumptions auditor. Your job is to find every unstated assumption in this spec. An unstated assumption is anything the spec relies on but doesn't explicitly declare. Check: does the spec assume a specific OS? A specific UID? Network connectivity? DNS resolution? File system permissions? Clock synchronization? For each unstated assumption, determine whether it's documented in ARCHITECTURE.md. If not, flag it."
   - Receives: spec, ARCHITECTURE.md, environment assumptions
   - Produces: list of unstated assumptions, each with severity and proposed EA-xxx entry

3. **Testability Auditor**
   - Prompt: "You are a test engineering auditor. For every invariant and prohibition in this spec, evaluate whether it's actually testable as written. 'Testable' means: you can write a concrete test that passes when the invariant holds and fails when it doesn't. If an invariant is vague, ambiguous, or requires conditions that can't be reproduced in a test environment, flag it. Propose a rewrite that makes it testable."
   - Receives: spec, workflow-config.json (for test framework details)
   - Produces: per-invariant testability assessment (pass/fail/rewrite-needed)

4. **Design Contract Checker**
   - Prompt: "You are a design contract auditor. Your job is to check whether this spec composes correctly with the project's existing abstractions and patterns. For every invariant, check: does it conflict with an existing ABS-xxx or PAT-xxx entry in ARCHITECTURE.md? Does the feature introduce a new abstraction that should be documented? Does it violate an existing design pattern's constraints?"
   - Receives: spec, ARCHITECTURE.md
   - Produces: conflict list and proposed ARCHITECTURE.md updates

The lead agent collects all teammate findings, deduplicates, and presents to the human:
- Findings that all agents agree on → auto-incorporate into spec
- Findings where agents disagree → present the disagreement to human for resolution
- New unstated assumptions → propose additions to ARCHITECTURE.md

**Behavior — External Review (optional, based on config)**:

If `require_external_review` is true, OR if any invariant is flagged `needs_external_review`:

1. Extract the flagged invariants + their surrounding context (trust boundary, abstraction, env assumptions) + the project's `.claude/antipatterns.md` (so the external model knows what the project has historically gotten wrong). Write this to a temporary review brief file.
2. Invoke external model CLIs using the generic interface from `workflow-config.json`:

   **Generic interface**: each entry in `external_models` defines a `command` template (with `{prompt}` placeholder), `stdin_file` (whether to pipe the review brief via stdin), and `timeout_seconds`. This keeps specific CLI invocation patterns in config, not baked into the skill prompt — when CLIs change their syntax, update the config, not the skill.

   - Write the review brief to a temp file (spec invariants + ARCHITECTURE.md context + antipatterns)
   - For each configured external model: substitute `{prompt}` in the command template, pipe the review brief via stdin if `stdin_file` is true, run with the configured timeout
   - Each CLI is expected to be pre-authenticated (API keys in the user's environment, NOT in project config)
   - If a configured CLI is not found at runtime, skip it and log a warning

3. Collect external responses. Where external models disagree with Claude's team, present the disagreement to the human.
   - **Error handling**: if an external model CLI times out (>5 minutes), exits with a non-zero code, returns unparseable output, or returns an empty response, log the failure and continue without that model's input. Do not block the workflow on external model availability. Do not retry — external model failures are transient and retrying burns credits.
   - **Credibility weighting**: external findings are not automatically higher-credibility than Claude's team findings. External models lack project context — they haven't read the full codebase or conversation history. Treat external findings as "worth investigating" not "definitely correct." Over time, the `external-review-history.json` builds a track record: if Gemini has historically been right about networking invariants but wrong about concurrency, weight its future feedback accordingly. The `/cspec` skill reads this history to decide which invariant categories benefit most from external review.
4. Track disagreements in `.claude/meta/external-review-history.json` for future reference — which categories of invariants have needed external correction, and which external model was right vs wrong?
5. **Report external model cost**: after external review completes, report the approximate token usage per model (based on input/output size). This makes external model costs visible — a user on `critical` intensity with `require_external_review: true` sending specs and source to Codex and Gemini on every feature should know what that costs outside their Claude subscription. The `/csetup` skill should mention this cost implication when configuring external models.

**Phase transition**: Human approves revised spec → state moves to `tdd-tests`.

---

### Skill 4: `/ctdd`

**Purpose**: Enforced test-driven development. Write failing tests from spec invariants, implement to make them pass, verify via QA loop.

**Trigger**: Reviewed spec approved, state is `tdd-tests`.

**Reads**:
- Approved spec artifact
- `.claude/workflow-config.json`
- `ARCHITECTURE.md`
- `AGENT_CONTEXT.md` (for subagents and agent team members)
- `.claude/antipatterns.md`

**Produces**:
- Test files (mapping to spec invariant IDs)
- Implementation files
- `.claude/artifacts/workflow-state-{branch-slug}.json` updates
- `.claude/artifacts/tdd-test-edits.log` (if tests modified during impl phase)

**Sub-skills / Phases**:

This skill manages a state machine with hook-based enforcement.

**Agent separation principle**: the RED phase (test writing) and GREEN phase (implementation) MUST be executed by different agents. If the same agent writes both the tests and the implementation, it will — consciously or not — write tests that are easy to satisfy, or implement code that games the specific test cases rather than broadly satisfying the invariant. The `/ctdd` orchestrator spawns a **test agent** (subagent with `context: fork`) for the RED phase and a separate **implementation agent** (subagent with `context: fork`) for the GREEN phase. The test agent receives the spec rules and ARCHITECTURE.md but never sees an implementation plan. The implementation agent receives the failing tests and the spec but did not write the tests — so it can't exploit knowledge of which edge cases are covered and which aren't. Both agents are restricted to their phase's allowed-tools via frontmatter. The QA phase runs as a third agent — also isolated from both the test author and the implementer.

#### Phase: `tdd-tests` (RED)

**Executed by**: test agent (forked subagent — does NOT carry over to GREEN phase).

Write tests that encode the spec's invariants. Each test function's doc comment references the invariant ID it tests (e.g., `// Tests INV-003: SO_MARK set on all outbound connections`).

**Allowed file operations**:
- Create/edit test files (per `patterns.test_file`)
- Create/edit test helpers, mocks, fakes, fixtures, testdata
- Create/edit non-source files (yaml, json, md, etc.)
- Create/edit source files ONLY for structural stubs: function signatures, interface definitions, type/struct definitions, and constants. Every stub function body MUST contain the comment tag `STUB:TDD` (e.g., `// STUB:TDD` in Go, `# STUB:TDD` in Python, `// STUB:TDD` in TypeScript/Rust). Stub bodies must contain only the tag, zero-value returns, `panic("not implemented")`, or equivalent. NO implementation logic.
- BLOCKED: source file edits where new function bodies do not contain the `STUB:TDD` tag

**Stub recognition**: the gate does NOT use heuristics to detect stub bodies. It uses a deterministic check: every new or modified function body in a source file during the RED phase must contain the literal string `STUB:TDD`. If it doesn't, the edit is blocked. This is language-agnostic and unfakeable by accident — the agent must explicitly mark its stubs. When the GREEN phase begins, the agent replaces the stub bodies with real implementation (and the `STUB:TDD` tags disappear naturally).

**Why stubs are allowed**: In typed languages (Go, Rust, TypeScript), tests for new functions won't compile without at least a function signature in the source. Blocking all source edits would deadlock the state machine — the test produces a build error instead of a test failure. Stubs resolve this while preserving the TDD invariant: no real implementation exists before tests.

**Gate to next phase**: at least one test file modified AND test runner indicates failure. Detection method (in order of preference):
1. **Structured output** (if `commands.test_json` is defined): parse the JSON/XML test output for failure entries. Most reliable across languages.
2. **Exit code + pattern**: test command returns exit code != 0 AND stdout/stderr matches `patterns.test_fail_pattern` AND does NOT exclusively match `patterns.build_error_pattern`. Catches the "tests fail" vs "code doesn't compile" distinction.
3. **Exit code only** (fallback): test command returns exit code != 0. Least precise — can't distinguish build errors from test failures. Use only if no structured output or fail pattern is configured.

#### Phase: `tdd-impl` (GREEN)

**Executed by**: implementation agent (separate forked subagent — did NOT write the tests).

Write implementation to make tests pass.

**Allowed file operations**:
- Create/edit any source file
- Edit test files: ALLOWED but LOGGED to `.claude/artifacts/tdd-test-edits.log` with timestamp, file path, and justification. **Acceptable reasons to edit tests during GREEN**: the test had a bug (wrong assertion target, incorrect setup), the test was testing an implementation detail that changed during design (not the invariant itself), or the test needs an updated fixture/mock. **Unacceptable and flagged during QA review**: weakening an assertion to make it pass (changing expected value to match actual output), deleting a test because it's "too strict," removing an error case test because the implementation doesn't handle it. The QA phase reviews this log and flags any edit where the test became less strict as a finding (severity: high).
- Create/edit non-source files

**Behavior**:
- Reference the RED phase test failures and implement specifically to make them pass
- Run `commands.test_race` (if defined) before advancing
- Each implementation decision should trace back to a spec invariant
- **Auto-populate `implemented_in`**: as each invariant is implemented, update the spec artifact's INV-xxx entry with the file paths and function names where the invariant is enforced. This creates the invariant-to-code trace that `/cverify`, `/caudit`, and drift detection rely on.

**Gate to next phase**: `commands.test` passes (exit code 0). If `commands.test_race` is defined, it must also pass. Before advancing to QA, the skill suggests: "Tests pass. Consider running `/simplify` to clean up code quality issues before QA review." This is a recommendation, not a gate — the human can skip it.

#### Phase: `tdd-qa` (QA)

**Executed by**: QA agent (separate forked subagent — did NOT write the tests or the implementation).

Adversarial review of the implementation. The QA agent's lens is explicitly hostile: "This code is guilty until proven innocent. Find the ways it fails, the invariants it doesn't actually enforce, the edge cases the tests don't cover, and the assumptions the implementation makes that the spec didn't authorize."

**Allowed file operations**:
- BLOCKED: all source and test file edits
- Allowed: findings JSON, notes, markdown

**Behavior**:
- For each INV-xxx in the spec: does the implementation actually enforce this invariant, or does it just happen to pass the specific test cases? Probe the gap between "tests pass" and "invariant holds."
- Review the test-edit log from GREEN phase: did the implementation agent weaken any tests? Flag any assertion that became less strict.
- Run QA agents with domain-specific hostile lenses (see `/caudit` for agent roles, but scoped to just the changed files)
- Produce findings in structured JSON format
- Run mutation testing via deterministic tools (see Mutation Testing Strategy below). The LLM identifies which files/functions to target based on spec invariants, configures the mutation tool, runs it, and analyzes the survivor report. Surviving mutants are findings (severity: high).

**Gate to next phase**:
- If critical/high findings remain → transition to `tdd-impl` (fix round), set `is_fix_round: true`
- If zero critical/high AND `qa_rounds >= min_qa_rounds` → transition to `tdd-verify`

#### Phase: `tdd-verify`

Final verification before done.

**Allowed file operations**:
- BLOCKED: all source and test file edits

**Behavior**:
- Run full test suite with race detection
- Check coverage delta: for **existing** packages touched by this feature, coverage must not decrease vs baseline captured at impl→qa transition. For **new** packages (no baseline exists), a minimum coverage threshold applies: all new packages must have at least 60% line coverage (configurable via `workflow.min_new_package_coverage` — defaults to 60%). This prevents the trivially-satisfied case where new code has 0% baseline and any test at all "doesn't decrease."
- Verify all findings from QA rounds are resolved (diff findings JSON against resolution JSON)
- Review `.claude/artifacts/tdd-test-edits.log` — were any tests weakened during impl? (assertion removed, expected value changed to match actual, test deleted)
- Verify spec invariant coverage: for each INV-xxx in the spec, confirm at least one test references it

**Gate to done**: all checks pass → state moves to `done`, state file removed.

#### Enforcement: `workflow-gate.sh` (PreToolUse hook)

**Implementation note**: this spec describes the gate's *behavior*, not its implementation language. The gate performs JSON parsing, file pattern classification, stub tag enforcement, bash write-pattern detection, package manager blocking, and polyglot scope resolution — all within a 5-second timeout. A small Go or Python binary is recommended over raw bash for testability and maintainability. The spec uses `.sh` naming for consistency with Claude Code hook conventions, but the hook can invoke any executable.

Reads the branch-scoped `.claude/artifacts/workflow-state-{branch-slug}.json`. Blocks file operations that violate the current phase.

- Blocks direct edits to any `.claude/artifacts/workflow-state-*.json` file (only the advance script can modify them)
- Classifies files based on `patterns.test_file` and `patterns.source_file` from workflow-config.json
- Returns exit code 2 to block, exit code 0 to allow
- Logs test-file edits during impl phase to `.claude/artifacts/tdd-test-edits.log`
- **Bash write detection** (accidental violation catcher, NOT a security boundary): the hook matcher includes `Bash` in addition to `Edit|Write|MultiEdit|CreateFile`. When the tool is `Bash`, the gate inspects the command for common shell write patterns (`>`, `>>`, `tee`, `sed -i`) targeting files that match source file patterns. This catches the common case where Claude reflexively uses shell commands instead of the Edit tool to modify source files. It is NOT bulletproof — the agent could bypass this via `python -c "open(...).write(...)"`, `cp` from a temp file, `git checkout` of a stash, or countless other indirection methods. The hook prevents accidental violations by a well-intentioned agent, not adversarial evasion. If Claude is compliant with the workflow (which it is — the skill prompts instruct compliance), the hook is a safety net. If it were truly adversarial, no PreToolUse hook would save you.
- **Package manager blocking during TDD**: during `tdd-tests` and `tdd-impl` phases, the gate blocks bash commands that install unmanifested dependencies: `apt-get install`, `brew install`, `curl | bash`, `curl | sh`, `wget ... | bash`, `pip install` (outside of requirements.txt), `go get` (outside of go.mod), `npm install <package>` (as opposed to `npm install` with no args which installs from package.json). This prevents the agent from silently pulling in dependencies to make tests pass without going through the dependency manifest. Legitimate dependency additions must be done via the manifest file (go.mod, package.json, etc.) which gets caught by the ghost dependency check in `/cverify`.
- **Stub tag enforcement**: during the `tdd-tests` phase, source file edits are allowed only if the file contains the literal string `STUB:TDD` AND does not contain implementation indicators. The gate checks: (1) `STUB:TDD` is present somewhere in the file — this is the language-agnostic part. (2) The file does not contain a blocklist of implementation patterns — this is the imperfect part. The blocklist is configurable per language scope and typically includes: `if ` followed by non-trivial conditions, `for `/`range `/`while `, function calls to external packages, channel operations, mutex operations, etc. This is a heuristic, not a parser — it will occasionally false-positive on complex type definitions or false-negative on clever inline implementations. It catches the 90% case of "agent wrote real logic during RED phase." The 10% that slips through gets caught by the QA phase's test-edit review. Do NOT rely on this as the sole enforcement of TDD discipline — the skill prompt's instructions are the primary control, the gate is the safety net.
- **Fail-open vs fail-closed**: when no state file exists, behavior depends on `workflow.fail_closed_when_no_state`:
  - `false` (default, `low`/`standard` intensity): everything editable (backward compat)
  - `true` (`high`/`critical` intensity): all source file edits BLOCKED. The agent must run `workflow-advance.sh init` to create a state file before editing any source. This prevents accidental unconstrained editing in high-assurance projects where the state file was deleted, corrupted, or never created.

#### Enforcement: `workflow-advance.sh` (Bash script)

The ONLY way to change the workflow state file. Validates transitions with real gates.

Commands:
- `init "task description"` — creates branch-scoped state file (`workflow-state-{branch-slug}.json`), sets phase to spec. If on main/default branch, refuses and tells user to create a feature branch first.
- `tests` — spec → tdd-tests (requires spec file exists and is approved)
- `impl` — tdd-tests → tdd-impl (requires test failure, not build error. Detection uses `commands.test_json` for structured output parsing if available, falls back to exit code + `patterns.test_fail_pattern` / `patterns.build_error_pattern`)
- `qa` — tdd-impl → tdd-qa (requires tests pass, captures coverage baseline)
- `fix` — tdd-qa → tdd-impl (requires unresolved findings exist)
- `verify` — tdd-qa → tdd-verify (requires zero critical/high, min rounds met)
- `done` — tdd-verify → done (requires all checks pass. Sets phase to `done` but does NOT remove the state file yet — state persists until the branch is merged. If the merge fails or needs rework, the state file allows the workflow to resume from `done` or transition back via `fix`. State file is cleaned up by `reset` or by the `/cdocs` skill as part of post-merge documentation.)
- `spec-update "reason"` — tdd-tests|tdd-impl|tdd-qa → spec (logs reason, preserves TDD state, increments update count)
- `reset` — any → none (user escape hatch, removes all state files for current branch)
- `override "reason"` — temporarily disables the gate hook for the next 10 tool calls or 5 minutes (whichever comes first). The reason is logged to `.claude/artifacts/override-log.json` with timestamp, phase, and reason. This is the targeted escape valve for when the gate is blocking a legitimate edit due to a pattern matching bug or edge case — use it instead of `reset` when you don't want to lose all workflow state. The log is reviewed during `/cverify` — frequent overrides indicate a gate configuration problem.
- `diagnose "filepath"` — shows why a specific file would be allowed or blocked in the current phase, without actually blocking anything. Prints: current phase, file classification (test/source/other), which patterns matched, whether STUB:TDD would be required, and the gate's decision. Useful for debugging gate behavior.
- `status` — prints current state, findings summary, spec update history
- `status-all` — scans all `.claude/artifacts/workflow-state-*.json` and prints a summary of all active branches

Branch awareness: state file is branch-scoped (derived from `git branch --show-current`). On every invocation, the script computes the current branch slug and reads the corresponding state file. If no state file exists for the current branch, the script behaves according to `fail_closed_when_no_state`. This supports parallel feature development — each branch has independent workflow state.

---

### Skill 5: `/cverify`

**Purpose**: Post-implementation verification that the implementation matches the spec. Catches drift between what was specified and what was built.

**Agent separation**: `/cverify` MUST run as a fresh agent (forked context) that did NOT participate in the `/ctdd` implementation. If the verification agent is the same session that wrote the code, it has memory of what it implemented and what it skipped — it'll unconsciously avoid probing the areas where it knows coverage is thin. A fresh agent reads the spec and the code independently and checks correspondence without insider knowledge of the implementation decisions.

**Trigger**: After TDD completes, or on-demand against any branch.

**Reads**:
- Spec artifact
- Implementation (source files changed on branch)
- Test files
- `ARCHITECTURE.md`
- Coverage data

**Produces**:
- `docs/verification/{task-slug}-verification.md` — verification report
- Proposed updates to `ARCHITECTURE.md` if the feature introduced new abstractions
- Proposed updates to `.claude/antipatterns.md` if the verification found patterns that should be watched

**Behavior**:

1. **Invariant coverage matrix**. For each INV-xxx in the spec:
   - Is there a test that references this invariant ID? (grep test files for the ID)
   - Does that test pass?
   - Does the test actually exercise the invariant, or is it a trivial assertion? (heuristic: does the test call the relevant code path?)
   - Result: table of INV-xxx → test name → status (covered | uncovered | weak)

2. **Mutation testing**. For each covered invariant:
   - Read the invariant's `implemented_in` field to identify the exact source files and functions to target (if populated during GREEN phase). Fall back to grep-based file discovery if `implemented_in` is empty.
   - Configure the project's mutation tool (`commands.mutation_tool` from workflow-config.json) to target those specific files/functions
   - Run the mutation tool — it generates mutants deterministically (faster and more thorough than LLM-generated mutations)
   - Analyze the survivor report: for each mutant that was NOT killed by the test suite, map it to the relevant invariant and report as a coverage gap
   - If no mutation tool is configured, fall back to LLM-directed mutations: the LLM reads the code, picks high-value mutation targets based on spec invariants, applies them one at a time, runs tests, and checks results. This is slower but works for any language.
   - Perform up to `workflow.mutation_count` targeted mutations per verification run, prioritizing highest-risk invariants

3. **Prohibition verification**. For each PRH-xxx in the spec:
   - Run the detection method specified in the prohibition (grep, linter, static analysis)
   - If the prohibition is violated, report it

4. **Ghost dependency check**. Detect newly introduced external dependencies:
   - Diff the dependency manifest (go.mod, package.json, Cargo.toml, requirements.txt) against the base branch
   - For each new dependency: flag it in the report with the package name, what it's used for, and which source file introduced it
   - Check: is the dependency specified in the spec or ARCHITECTURE.md? If not, flag as an undocumented dependency (severity: medium)
   - Check: does the dependency introduce a new trust boundary? (e.g., a new HTTP client, a new crypto library, a new DNS resolver) If so, flag for STRIDE review (severity: high)
   - Where tooling supports it, also check for transitive dependency changes (`go mod graph`, `npm ls --all`, `cargo tree`). A new transitive dependency pulled in by an existing package can introduce vulnerabilities without any direct manifest change. Flag new transitive dependencies that touch security-sensitive domains (crypto, network, auth).

5. **Complexity budget check**. Compare the spec's complexity budget against actual implementation:
   - Actual changed LOC vs estimated LOC: flag if actual > 2× estimate
   - Actual files touched vs estimated: flag if actual > estimate + 50%
   - New abstractions introduced vs estimated: flag any unplanned abstractions
   - This catches scope creep — if the implementation grew far beyond the spec's expectations, either the spec was under-specified or the implementation diverged from intent. Both are worth investigating before merge.

6. **Spec drift detection**. Compare the spec's invariants against the actual code:
   - Does the code reference the abstractions the spec says it should? (e.g., if the spec says "use the dialer abstraction," does the code import and use the dialer?)
   - Has the code introduced patterns not covered by the spec? (new trust boundaries, new external dependencies, new goroutines without shutdown paths)
   - **Invariant orphan detection**: for each INV-xxx with a populated `implemented_in` field, check whether those files and functions still exist. If an invariant references `pkg/dialer/dial.go:SetMark` but `SetMark` was renamed or removed, mark the invariant as `status: stale — requires spec pruning`. Also check for invariants whose `implemented_in` is empty post-implementation — these may have been forgotten during the GREEN phase.
   - **Cross-spec impact check**: read the current spec's `impacts` field. For each listed spec slug, load that spec and check whether any of its invariants reference files or abstractions modified by this feature. If so, flag: "This feature modifies code referenced by invariant INV-xxx in spec {other-slug}. Verify that the impacted invariant still holds." This prevents a change to traffic inspection from silently breaking a detection rules invariant that depends on the same code path.

7. **Design contract compliance**. Check the implementation against ARCHITECTURE.md:
   - Does the feature introduce a new abstraction? If so, propose an ARCHITECTURE.md update
   - Does the feature violate any existing PAT-xxx constraint? (e.g., new config field missing from one of the six config lifecycle locations)
   - Does the feature touch a trust boundary? If so, verify the STRIDE analysis from the spec is actually addressed in the implementation

8. **Report**. Produce a verification report with:
   - Overall pass/fail
   - Invariant coverage table (with `implemented_in` trace for each)
   - Mutation results
   - Prohibition check results
   - Ghost dependency findings
   - Complexity budget comparison (estimated vs actual LOC, files, abstractions)
   - Drift findings (including orphaned invariants with `status: stale` and cross-spec impact warnings)
   - Spec update history (if any spec-updates occurred during TDD)
   - Workflow health summary (from meta-verification tracking)
   - Proposed doc updates

   For any drift findings the human accepts without fixing (e.g., "this drift is intentional" or "will fix later"), log them as structured drift debt in `.claude/meta/drift-debt.json`:

   ```json
   {
     "drift_debt": [
       {
         "id": "DRIFT-001",
         "spec_id": "localhost-inspection",
         "invariant_id": "INV-007",
         "description": "implementation uses direct net.Dial in fallback path instead of dialer abstraction",
         "detected": "2026-03-26",
         "accepted_by": "human",
         "reason": "fallback path is emergency-only, dialer refactor planned for next sprint",
         "status": "open | resolved",
         "resolved_date": null,
         "related_ap": null
       }
     ]
   }
   ```

   The `/cspec` skill reads drift debt and flags when a new feature touches code with outstanding drift. The `/caudit` skill checks whether drift debt items have been resolved or have aged beyond a configurable threshold (default: 90 days — set via `workflow.drift_debt_age_threshold_days`). This makes architectural erosion visible and trackable rather than silently accumulating.

   **Drift debt resolution**: drift items transition to `status: resolved` in three ways:
   - **During a feature**: if a `/cspec` flags outstanding drift and the human chooses to resolve it as part of the current feature, the `/cverify` phase checks that the drift is actually fixed and marks the item resolved with `resolved_date` and a reference to the fixing spec.
   - **During an audit**: if the `/caudit` convergence loop produces a finding that matches an open drift item, fixing that finding also resolves the drift. The lead agent cross-references findings against drift debt.
   - **Manually**: the human can mark drift items resolved via `workflow-advance.sh resolve-drift DRIFT-001 "resolved in commit abc123"`. This is for cases where drift was fixed outside the workflow (e.g., a manual refactor).

---

### Skill 6: `/caudit`

**Purpose**: Multi-round convergence audit. Runs multiple QA agents in parallel, fixes findings, repeats until a round produces no new critical/high findings and no new medium/low findings that weren't present in the previous round.

**Trigger**: On-demand after a major feature lands, before a release, or on a schedule.

**Reads**:
- All source code (or scoped to specific packages/directories)
- Spec artifacts for relevant features
- `ARCHITECTURE.md`
- `.claude/antipatterns.md`
- Previous findings docs (for regression hunting)
- `AGENT_CONTEXT.md` (provided to each agent team member)
- `.claude/workflow-config.json`

**Produces**:
- `.claude/artifacts/findings/caudit-{type}-{date}-round-{N}.json` per round
- Updated `.claude/antipatterns.md`
- Regression tests for security-critical findings
- Audit summary report

**Parameters**:
- `type`: `qa` | `security` | `custom`
- `scope`: `all` | `changed` | `path/to/cspecific/package`
- `focus_areas`: list of focus area overrides (default: derived from type)

**Presets**:

`qa` preset (your QA Olympics):
- Focus areas: concurrency/data races, error handling/silent failures, input validation/edge cases, resource leaks/cleanup, API contract mismatches, test coverage gaps

`security` preset (your Hacker Olympics):
- Focus areas: encoding/normalization bypass, protocol abuse, config manipulation, exception system abuse, header spoofing, content-type routing bypass, detection rule gaps

`custom` preset:
- Focus areas provided by human at invocation

**Behavior — Per Round**:

1. **Spawn agent team** with one teammate per focus area (4-6 agents), plus one Regression Hunter.

   Each focus area agent receives:
   - Its focus area description
   - The relevant source files (scoped by `scope` parameter)
   - The antipatterns checklist
   - The ARCHITECTURE.md trust boundaries and abstractions
   - Instruction to produce structured JSON findings (not prose)
   - Instruction to execute verification (run tests, run tools) — not just read code

   The Regression Hunter receives:
   - The full previous findings doc (`.claude/artifacts/findings/` for this audit type)
   - The antipatterns checklist
   - Instruction: check whether any previously fixed issues have regressed or reappeared
   - Must reference specific finding IDs from previous rounds

   **Agent team communication model**: teammates coordinate via Claude Code's TeammateTool — a disk-mediated system using a shared task list and direct messaging between sessions. Each teammate runs in its own context window and does NOT inherit the lead's conversation history or other teammates' context. Communication works like this: (1) the lead spawns teammates with role-specific initial prompts containing the spec, ARCHITECTURE.md, AGENT_CONTEXT.md, and antipatterns; (2) teammates work independently in parallel; (3) when a teammate produces findings, it writes them to the shared task list or sends them via SendMessage to the lead; (4) the lead can forward one teammate's findings to another via SendMessage for cross-checking. This is NOT a shared room — it's structured message-passing. Skill prompts must be explicit about what each agent receives in its initial prompt (full context for its role) versus what arrives mid-run via messages (specific findings from other teammates to react to).

2. **Collect and triage findings**. Lead agent:
   - Deduplicates across agents. Finding identity is based on `invariant_ref` + a content hash of the relevant code region (not line numbers, which shift when fixes move code). When `invariant_ref` is null, fall back to file path + function name + description similarity. This identity is stable across rounds — if round 2 rediscovers the same issue that round 1 found and fixed, the `reintroduced_from` field catches it even if line numbers changed.
   - Verifies each finding is real (not a false positive) — run the reproduction step if provided
   - Classifies by severity
   - Maps findings to spec invariants where applicable (set `invariant_ref`)

3. **Present findings to human**. Summarize: N findings (X critical, Y high, Z medium, W low). For critical/high, show details. Ask human to confirm before proceeding to fix.

4. **Fix round**. For each finding:
   - Non-trivial fixes: follow TDD workflow (write test first that reproduces the issue, then fix)
   - Trivial fixes (one-liner guards, missing nil checks): apply directly
   - Update findings JSON with resolution

5. **Update antipatterns**. For any new validated finding, add an entry to `.claude/antipatterns.md` with: what went wrong, which phase should have caught it, the check that would catch it in future.

6. **Commit fixes**. Commit to the audit branch with structured message: `fix(audit-{type}-r{round}): {finding-id} — {one-line description}`. NEVER commit directly to main.

7. **Next round**. Spawn a fresh agent team (new context, no memory of previous round). The new team receives the updated codebase and the antipatterns checklist (which now includes entries from this audit). They do NOT receive the previous round's findings — they start fresh.

8. **Convergence check**: the audit has converged when a round produces zero critical/high findings AND no *new* medium/low findings (i.e., any medium/low findings in this round were also present in the previous round — they're persistent noise, not new discoveries). Absolute zero across all severities is unrealistic — agent teams at high/critical intensity will always find something marginal. The goal is convergence of *meaningful* findings, not silence.

   **Oscillation detection**: if a round finds an issue in the same file and line range as a previously fixed finding, set `reintroduced_from` on the finding to reference the original. If the same finding is reintroduced twice, the lead agent escalates to the human: "Fix for {finding-id} has been undone twice — the fixes may be conflicting. Human review required." The audit pauses until the human resolves the conflict.

   **Divergence detection**: if a round finds MORE issues than the previous one, the lead agent checks whether the new findings are in files modified by the previous round's fixes. If yes, the fixes introduced regressions — flag this explicitly and consider reverting the problematic fix before continuing.

   **Max rounds ceiling**: if the audit reaches `workflow.max_audit_rounds` without converging, it pauses and dumps all remaining open findings to the human for manual triage. The lead agent reports: "Audit has not converged after {N} rounds. {M} findings remain open. This may indicate an eager reviewer problem (agents generating low-value findings to fulfill their role) or genuinely deep issues. Human review required." The human can then dismiss false positives, approve remaining fixes, or reset and re-run with adjusted focus areas.

**Post-convergence**:
- For `security` type audits: write regression tests for every finding involving detection bypass, protocol abuse, encoding tricks, or config manipulation. Each test must reproduce the exact attack path.
- For `qa` type audits: write regression tests for critical/high findings.
- Run verification against spec invariants for any spec that was in scope.

**External model pass (optional)**:
After Claude convergence, send the final implementation to an external model for a single "fresh eyes" pass. The external model receives: the changed source files, the spec invariants, the ARCHITECTURE.md trust boundaries, and `.claude/antipatterns.md` (so it knows what this project has historically missed). This catches systematic blind spots that Claude-on-Claude convergence can't find. External findings go into antipatterns and the external review history for future reference.

---

### Skill 7: `/cupdate-arch`

**Purpose**: Maintain ARCHITECTURE.md as a living document. After any feature, verify that new abstractions, trust boundaries, patterns, or environment assumptions are documented.

**Trigger**: After `/cverify` or `/caudit` identifies undocumented abstractions or design patterns. Also on-demand.

**Reads**:
- Current `ARCHITECTURE.md`
- Recent specs and their invariants
- Implementation source code
- Verification reports

**Produces**:
- Updated `ARCHITECTURE.md` with new entries
- Git commit with the update

**Behavior**:
1. Scan recent specs for abstractions, trust boundaries, patterns, and environment assumptions that aren't in ARCHITECTURE.md
2. Scan the codebase for patterns that repeat but aren't documented (e.g., a specific error-handling pattern used in 5+ places)
3. For each candidate entry, draft the structured ARCHITECTURE.md entry (with invariant, enforced-at, violated-when, test)
4. Present to human for approval — one entry at a time
5. Commit approved updates

---

### Skill 8: `/cdocs`

**Purpose**: Keep project documentation current. Update README, feature docs, architecture diagrams, and the agent context file after features land.

**Trigger**: After a feature branch is squash-merged to main, or on-demand. The `/ctdd` skill suggests running `/cdocs` after `done`. The `/caudit` skill suggests it after convergence if source files changed significantly.

**Reads**:
- Recent git history (`git log --oneline` since last `/cdocs` run)
- Changed files (`git diff` against last documented state)
- Existing documentation (README.md, docs/, ARCHITECTURE.md)
- Existing agent context file (`AGENT_CONTEXT.md`)
- Spec artifacts for recently completed features
- `.claude/workflow-config.json`

**Produces**:
- Updated `README.md` — project description, setup instructions, feature list
- Updated or new feature documentation in `docs/` — one doc per major feature or subsystem
- Updated or new architecture diagrams (Mermaid) in `docs/diagrams/`
- Updated `AGENT_CONTEXT.md` — agent onboarding brief
- Git commit with all doc changes

**Behavior**:

1. **Diff analysis**. Determine what changed since docs were last updated. Use git history, spec artifacts, and ARCHITECTURE.md changes to build a list of documentation impacts:
   - New features that need docs
   - Existing features whose behavior changed
   - New or changed trust boundaries, abstractions, or patterns
   - Removed or deprecated functionality
   - New CLI flags, config options, API endpoints, or environment variables

2. **README update**. Check the README against the current state of the project:
   - Is the feature list current?
   - Are setup/install instructions still accurate? (check against actual build commands in workflow-config.json)
   - Are usage examples current?
   - Does the project description still accurately describe what the project does?
   - Present proposed changes to human for approval before writing

3. **Feature documentation**. For each new or significantly changed feature:
   - Create or update a doc in `docs/{feature-slug}.md`
   - Structure: what it does, why it exists, how it works, configuration options, examples, known limitations
   - Include Mermaid diagrams for data flow, state machines, or decision trees where they add clarity
   - Reference the spec artifact for detailed invariants (don't duplicate — link)
   - Keep language accessible to someone who knows the problem domain but hasn't read the source

4. **Architecture diagrams**. Maintain Mermaid diagrams in `docs/diagrams/`:
   - `system-overview.mermaid` — high-level component diagram showing major subsystems and their relationships
   - `data-flow.mermaid` — how data moves through the system, including trust boundary crossings
   - `trust-boundaries.mermaid` — visual representation of ARCHITECTURE.md trust boundaries
   - Feature-specific diagrams as needed (state machines, sequence diagrams, decision flows)
   - Diagrams reference ARCHITECTURE.md entries (TB-xxx, ABS-xxx) in their labels
   - Update diagrams when ARCHITECTURE.md changes — the `/cupdate-arch` skill should trigger a `/cdocs` run for diagram updates

5. **Agent context file update**. Update `AGENT_CONTEXT.md` (see below for format). This is the most important output for workflow quality — every subagent and fresh session reads it.

6. **Staleness check**. For existing docs NOT touched by this run, check whether they reference code, config, or features that no longer exist. Flag stale docs for human review rather than auto-deleting.

7. **Fact-check** (via separate subagent). After the doc-writing agent produces its updates, a separate forked subagent reads the new/updated documentation and spot-checks claims against the actual code. Does the API actually accept the parameters the doc says? Does the config option actually default to what the doc claims? Does the described flow match the actual code path? The fact-checker has read-only access to source code and the docs — it can't fix anything, only flag inaccuracies. This catches the common failure mode where a doc-writing agent that didn't implement the feature writes plausible-but-wrong documentation from its understanding of the spec rather than the actual code.

**Constraints**:
- Don't duplicate information that lives in ARCHITECTURE.md or spec artifacts. Reference them.
- Don't write documentation for internal implementation details — document behavior, interfaces, and configuration.
- Mermaid diagrams should be readable without the surrounding docs (labeled arrows, clear node names).
- Present changes to the human for approval before committing. Documentation is the project's external face — the human should sign off.

---

### Agent Context File: `AGENT_CONTEXT.md`

**Purpose**: A single file optimized for fresh AI agents seeing the project for the first time. Every Claude Code session, subagent, and agent team member should read this file before doing any work. It provides the minimum context needed to make correct decisions without reading the entire codebase or conversation history.

**This is NOT documentation.** It's a structured briefing. It should be concise (target: under 3000 words), opinionated (tell the agent what matters, not everything), and current (stale context is worse than no context).

**Location**: Project root, next to README.md and CLAUDE.md.

**Relationship to CLAUDE.md**: CLAUDE.md contains instructions for how Claude should behave in this project (coding conventions, tool preferences, permissions). AGENT_CONTEXT.md contains information about what the project IS and how it works. They're complementary — CLAUDE.md is behavioral, AGENT_CONTEXT.md is contextual.

**Format**:

```markdown
# Agent Context — {Project Name}

> Last updated: {date} by /cdocs skill after {feature/change that triggered update}

## What This Project Does

{2-3 sentences. What problem does it solve? Who uses it? What's the deployment model?}

## Architecture Summary

{Brief prose overview of the system architecture. How do the major components fit together?
Reference the detailed ARCHITECTURE.md for formal trust boundaries and abstractions.}

### Key Components

| Component | Location | Purpose | Key Interfaces |
|-----------|----------|---------|----------------|
| {name} | {path} | {what it does} | {main exported functions/types} |
| ... | ... | ... | ... |

### Data Flow

{How data moves through the system. Where does input come from? What transformations happen?
Where does output go? Where do trust boundaries get crossed?}

Reference: `docs/diagrams/data-flow.mermaid`

## Design Paradigms

{The patterns and principles this project follows. Not coding conventions (those are in CLAUDE.md)
— architectural and design decisions that affect how new code should be structured.}

### Pattern: {pattern name}
- **What**: {brief description}
- **Why**: {rationale — what problem does it solve?}
- **Convention**: {the rule to follow}
- **Example**: {one concrete example of this pattern in the codebase, with file path}
- **Anti-example**: {what violating this pattern looks like — the mistake to avoid}

### Pattern: {another pattern}
...

## Critical Invariants

{The 5-10 most important invariants that a new agent MUST know about. Not all invariants — just
the ones where a violation would cause a security issue, data loss, or system failure.
Reference ARCHITECTURE.md entries by ID.}

- **{INV-ID}**: {one-line statement} — refs {ABS-xxx or TB-xxx}
- ...

## Common Pitfalls

{Things agents frequently get wrong in this codebase. Sourced from the antipatterns checklist
and post-merge bug history. Top 5-10 items only — the full list is in .claude/antipatterns.md.}

- **Pitfall**: {description} — **Instead**: {correct approach} — refs {AP-xxx}
- ...

## Current State

{What's in progress, what's recently changed, what's upcoming. This section updates frequently.}

- **Recent changes**: {last 2-3 features merged, with brief descriptions}
- **In progress**: {feature branches currently active, if any}
- **Known issues**: {top 3-5 known bugs or limitations}
- **Upcoming**: {next planned features, if known}

## Testing

{How to run tests, what the test structure looks like, any test-specific conventions.}

- **Run all tests**: `{command from workflow-config.json}`
- **Run with race detector**: `{command}`
- **Test file naming**: `{pattern}`
- **Test structure**: {brief description of how tests are organized — by package, by feature, etc.}

## Quick Reference

| Need to... | Do this |
|------------|---------|
| Build the project | `{build command}` |
| Run tests | `{test command}` |
| Lint | `{lint command}` |
| Find the spec for a feature | `docs/specs/{feature-slug}.md` |
| Find architecture docs | `ARCHITECTURE.md` |
| Find known bug patterns | `.claude/antipatterns.md` |
| Find workflow state | `.claude/artifacts/workflow-state-{branch}.json` |
```

**How it's maintained**:

The `/cdocs` skill updates AGENT_CONTEXT.md as part of every documentation run. Specifically:
- **Key Components table**: regenerated from the codebase (scan for packages/modules, their main exports)
- **Design Paradigms**: updated when ARCHITECTURE.md patterns (PAT-xxx) change
- **Critical Invariants**: updated when new high/critical invariants are added to specs
- **Common Pitfalls**: updated from `.claude/antipatterns.md` (top items by frequency)
- **Current State**: updated from git history and active branches
- **Quick Reference**: updated from `workflow-config.json` commands

**Who reads it**:
- Every `/ctdd` invocation reads it at the start to understand the project context
- Every `/caudit` agent team member receives it as part of their context
- Every `/creview-spec` agent receives it alongside the spec and ARCHITECTURE.md
- Every subagent spawned by any skill receives it
- Fresh Claude Code sessions should be told to read it first (add to CLAUDE.md: "Read AGENT_CONTEXT.md before starting any work")

---

### Skill 9: `/csetup`

**Purpose**: Interactive project configuration. Detects project structure, bootstraps ARCHITECTURE.md and AGENT_CONTEXT.md, configures workflow intensity and audit presets, validates existing setup.

**Trigger**: Run manually after initial install (`./setup` handles the mechanical parts, `/csetup` handles the interactive parts). Also run on-demand to reconfigure or validate.

**Reads**:
- Project root (scans for manifest files, source directories, existing config)
- `.claude/workflow-config.json` (if exists — to show current config)
- `ARCHITECTURE.md` (if exists — to check if still template)
- `AGENT_CONTEXT.md` (if exists — to check if still template)
- Codebase structure (packages, modules, imports, test files)

**Produces**:
- Updated `.claude/workflow-config.json`
- Bootstrapped `ARCHITECTURE.md` (if template or missing)
- Bootstrapped `AGENT_CONTEXT.md` (if template or missing)
- Validation report (if run on existing setup)

**Behavior — First Run (bootstrapping)**:

1. **Intensity selection**. Ask the human:
   - "What kind of project is this?" — present options: security/infrastructure tooling → recommend `critical`, backend services → recommend `high`, general application → recommend `standard`, prototype/exploration → recommend `low`
   - Explain what intensity controls (QA rounds, mutation count, STRIDE, fail-closed, formal modeling)
   - Human picks intensity → config updated

2. **Audit preset configuration**. Ask the human:
   - "What should QA audits focus on?" — present common categories (concurrency, resource leaks, data integrity, API contracts) and let the human select which apply
   - "Do you need security audits?" — if yes, ask about specific attack surfaces relevant to the project
   - Generate `audit_presets` section of config

3. **External model configuration**. Check which CLIs are available (`codex --version`, `gemini --version`):
   - Report findings: "Found codex CLI. Gemini CLI not found."
   - Ask: "Use codex for external review? Which intensity level triggers it?"
   - Update `external_models` and `external_review_threshold` in config

4. **Alloy configuration**. Check for Alloy JAR:
   - If found: "Alloy Analyzer found at {path}. Enable formal modeling?"
   - If not found: "Alloy not installed. Formal modeling will be disabled. Install from https://alloytools.org/ to enable it."

5. **ARCHITECTURE.md bootstrap**. If the file is still the template:
   - Scan for network listeners, TLS configurations → suggest trust boundary entries
   - Scan for package/module structure → suggest core abstraction entries
   - Scan for config structs and their usage → suggest config lifecycle pattern entries
   - Scan for goroutine spawns and channel usage → suggest concurrency-relevant entries
   - Scan for file/connection/resource allocations → suggest resource lifecycle entries
   - Present each suggestion to human for approval/edit/skip — one at a time
   - Write approved entries to ARCHITECTURE.md

6. **AGENT_CONTEXT.md bootstrap**. If the file is still the template:
   - Read the codebase, ARCHITECTURE.md, CLAUDE.md, and recent git history
   - Draft the full agent context document
   - Present to human for review and approval
   - Write approved version

**Behavior — Subsequent Runs (reconfigure/validate)**:

1. **Validate setup**. Check that all required files exist and are valid:
   - Hooks registered in `.claude/settings.json`?
   - Commands accessible?
   - Config valid (all required fields present)?
   - ARCHITECTURE.md populated (not just template)?
   - AGENT_CONTEXT.md populated?
   - Report any issues

2. **Re-detect tools**. Check for newly installed tools (mutation testing, Alloy, external CLIs). Offer to enable newly detected tools.

3. **Review config**. Show current configuration and offer to change any setting. Present as a summary, not a form.

**Constraints**:
- `/csetup` NEVER auto-writes ARCHITECTURE.md entries without human approval. The bootstrap suggests entries — the human decides.
- `/csetup` is idempotent. Running it multiple times never overwrites user-edited content.
- `/csetup` respects the existing config. If the human has already configured intensity, don't re-ask unless they request reconfiguration.

---

### Skill 10: `/cpostmortem`

**Purpose**: Structured post-merge bug analysis. When a bug is found after the workflow approved the code, walk through what happened, which phase should have caught it, why it didn't, and what corrective action to take. Maintains the meta-verification feedback loop that makes the workflow improve over time.

**Trigger**: A bug is found in merged code — via user report, monitoring, manual testing, or a subsequent `/caudit` run. The human invokes `/cpostmortem` to analyze it.

**Reads**:
- `.claude/meta/workflow-effectiveness.json` (existing post-merge bug history)
- `.claude/antipatterns.md` (to check if this bug class is already tracked)
- The spec artifact for the feature where the bug was introduced (if one exists)
- The verification report for that feature (if one exists)
- Relevant source code and test files

**Produces**:
- New entry in `.claude/meta/workflow-effectiveness.json`
- Optionally: new AP-xxx entry in `.claude/antipatterns.md`
- Optionally: update to an invariant template in `.claude/templates/invariants/`
- Optionally: new DRIFT-xxx entry in `.claude/meta/drift-debt.json`

**Behavior**:

1. **Gather the facts**. Ask the human (batched where appropriate):
   - What broke? (description of the bug, how it was discovered)
   - What's the severity? (critical / high / medium / low)
   - Which feature introduced it? (spec slug, if known)
   - Was the workflow run for that feature? Which phases were executed?

2. **Analyze the miss**. Read the spec and verification report for the feature (if they exist):
   - Did a spec invariant cover this bug class? If yes, why didn't the test catch it?
   - If no invariant covered it, should one have existed? Which category (concurrency, resource lifecycle, security, etc.)?
   - Which workflow phase should have caught this? (spec, review-spec, tdd-qa, verify, audit)
   - Was that phase skipped? If so, would running it have caught the bug?
   - If that phase ran and still missed it, why? (mutation testing didn't target this path, QA agents didn't check this pattern, invariant was too vague, etc.)

3. **Determine corrective action**. For each miss, propose one or more of:
   - **New antipattern**: draft an AP-xxx entry describing this bug class, which phase missed it, and the detection check. Present to human for approval.
   - **Invariant template update**: if this bug class should be caught by a template (e.g., concurrency template should check for this goroutine pattern), draft the addition. Present to human.
   - **Spec update**: if the original spec exists and should have had an invariant for this, draft the invariant for the spec. (This doesn't retroactively fix the spec — it serves as a reference for future specs.)
   - **Drift debt**: if the bug reveals architectural drift that wasn't tracked, create a DRIFT-xxx entry.

4. **Write the PMB entry**. Create a structured entry in `workflow-effectiveness.json`:
   ```json
   {
     "id": "PMB-{NNN}",
     "date": "ISO date",
     "description": "what broke",
     "severity": "high",
     "found_by": "how it was discovered",
     "root_cause": "technical root cause",
     "spec_existed": true,
     "spec_id": "feature-slug",
     "invariant_existed": false,
     "invariant_id": null,
     "phase_that_should_have_caught": "tdd-qa",
     "phase_was_skipped": false,
     "why_missed": "explanation",
     "corrective_action": {
       "antipattern_added": true,
       "antipattern_id": "AP-xxx",
       "invariant_template_updated": false,
       "template": null,
       "addition": null,
       "drift_debt_created": false
     }
   }
   ```

5. **Update phase effectiveness summary**. Increment the counters in `phase_effectiveness` for the relevant phase. If a pattern emerges (e.g., `tdd-qa` has missed 5 bugs that all involve goroutine lifecycle), note it in that phase's `notes` field.

**Constraints**:
- `/cpostmortem` does NOT fix the bug. It analyzes why the workflow missed it and strengthens the workflow for next time. Fixing the bug is a separate `/ctdd` cycle.
- Every `/cpostmortem` MUST produce at least one corrective action (antipattern, template update, or drift debt entry). If the analysis concludes "this was unpreventable," the human must explicitly confirm that — the skill should push back and ask whether a more specific invariant or a different test approach would have caught it.

---

### `workflow-advance.sh` additional commands

Beyond the phase transition commands defined in Skill 4, the advance script supports:

- `status-all` — scans `.claude/artifacts/workflow-state-*.json` and prints a summary of all active branches:
  ```
  Active workflows:
    feature/localhost-inspection  phase: tdd-impl   started: 2026-03-24  qa_rounds: 0
    feature/sens052-rule          phase: review-spec started: 2026-03-25  qa_rounds: 0
    audit/security-2026-03-26     phase: audit       started: 2026-03-26  rounds: 2/7  findings: 3 open
  ```
  Essential for parallel development — see where everything is at a glance.

- `resolve-drift DRIFT-xxx "reason"` — marks a drift debt item as resolved in `.claude/meta/drift-debt.json`. Sets `status: resolved`, `resolved_date`, and logs the reason.

---

## Claude Code Native Feature Integration

The workflow leverages several built-in Claude Code features for enforcement, performance, and context management. These are configured in each skill's YAML frontmatter and in the workflow orchestration logic.

### Skill Frontmatter: `allowed-tools`

Every skill restricts its tool access via frontmatter. This is a **second enforcement layer** on top of `workflow-gate.sh` — the hook catches accidental violations, but `allowed-tools` prevents the tools from even being available. Both layers must agree.

| Skill | `allowed-tools` | Rationale |
|-------|-----------------|-----------|
| `/cspec` | `Read, Grep, Glob, Bash(git log*), Bash(git diff*), Bash(git branch*)` | Read-only. Spec authoring must never touch source code. |
| `/cmodel` | `Read, Grep, Bash(java -jar*), Write(docs/models/*)` | Can only write Alloy model files. Can run the Alloy Analyzer JAR. |
| `/creview-spec` | `Read, Grep, Glob, Bash(git*), Write(.claude/artifacts/reviews/*), Write(docs/specs/*)` | Can read everything, write review artifacts and update the spec. Cannot touch source code. |
| `/ctdd` | (varies by phase — orchestrator manages tool restrictions for spawned agents) | RED phase agents: `Read, Grep, Write(files matching patterns.test_file), Bash(commands.test*)`. GREEN phase agents: full tool access. QA phase agents: `Read, Grep, Glob, Bash(commands.test*), Write(.claude/artifacts/findings/*)`. |
| `/cverify` | `Read, Grep, Glob, Bash(go test*), Bash(npm test*), Write(docs/verification/*)` | Can read and run tests. Can only write verification reports. Cannot modify source. |
| `/caudit` | (orchestrator manages per-agent — QA agents get read + test execution, fix agents get full access) | Agent-specific restrictions set when spawning teammates. |
| `/cdocs` | `Read, Grep, Glob, Write(docs/*), Write(README.md), Write(ARCHITECTURE.md), Write(AGENT_CONTEXT.md)` | Can write documentation files only. Cannot touch source code. |
| `/cpostmortem` | `Read, Grep, Glob, Write(.claude/meta/*), Write(.claude/antipatterns.md)` | Can read everything, write meta-verification data and antipatterns. Cannot touch source. |
| `/csetup` | `Read, Grep, Glob, Bash(*), Write(.claude/workflow-config.json), Write(ARCHITECTURE.md), Write(AGENT_CONTEXT.md), Write(.claude/antipatterns.md), Write(.claude/meta/*), Write(.claude/templates/*), Write(.claude/skills/workflow/hooks/*), Write(.claude/settings.json)` | Needs broad write access to scaffold project files and register hooks. Cannot write source code or test files. |

### Skill Frontmatter: `model`

Skills specify which model to use for cost efficiency:

| Skill / Phase | Model | Rationale |
|---------------|-------|-----------|
| `/cspec` | `claude-opus-4-6` | Spec authoring requires deep reasoning and domain understanding. |
| `/cmodel` | `claude-opus-4-6` | Formal modeling requires precise Alloy syntax generation. |
| `/creview-spec` lead | `claude-opus-4-6` | Synthesis of multi-agent findings requires judgment. |
| `/creview-spec` teammates | `claude-sonnet-4-6` | Individual review passes are focused and don't need Opus. |
| `/ctdd` RED phase (test agent) | `claude-opus-4-6` | Test design from invariants requires careful reasoning. Separate agent from implementation. |
| `/ctdd` GREEN phase (impl agent) | `claude-sonnet-4-6` | Implementation is more mechanical. Separate agent — never sees the test-writing context. |
| `/ctdd` QA agents | `claude-sonnet-4-6` | Focused QA checks. Third agent — independent from both test and impl agents. |
| `/cverify` | `claude-sonnet-4-6` | Verification is structured and checklist-driven. |
| `/caudit` agents | `claude-sonnet-4-6` | Focused audit checks. Lead uses Opus for synthesis. |
| `/cdocs` | `claude-sonnet-4-6` | Documentation writing is well-structured. |
| `/simplify` (bundled) | (default) | Uses its own built-in model selection. |
| `/cpostmortem` | `claude-opus-4-6` | Root cause analysis requires deep reasoning. |

These are defaults. The human can override with `/cmodel` at any time. On a Max subscription, the cost difference is negligible — this is about matching capability to task complexity.

### Skill Frontmatter: `context: fork`

Skills that spawn agent teams or perform review should fork the context to prevent polluting the main conversation:

- `/creview-spec`: `context: fork` — the multi-agent review conversation stays isolated
- `/caudit`: `context: fork` — each audit round's agent team conversation stays isolated
- `/cpostmortem`: `context: fork` — analysis conversation stays isolated

This means the main session doesn't accumulate the back-and-forth from review debates or audit rounds. The skill produces its artifacts (findings JSON, review records) and the main session sees only the summary.

### Built-in `/simplify` Integration

Claude Code's bundled `/simplify` skill spawns three parallel review agents (code reuse, code quality, efficiency) and applies fixes. This is complementary to our QA phase — `/simplify` catches code smell and cleanup opportunities, while QA checks invariant correctness.

**Recommended integration point**: after GREEN phase passes tests, before advancing to QA. The `/ctdd` skill should suggest: "Tests pass. Run `/simplify` to clean up before QA review?" This is a recommendation, not a gate — the human can skip it. But running it reduces the noise in QA findings by fixing obvious quality issues first.

### Context Management: `context: fork` and `/compact`

**`context: fork`** in skill frontmatter is the primary context isolation mechanism. Forked skills start with a clean context that doesn't inherit the parent session's full conversation history — the skill receives only its explicit inputs (spec, ARCHITECTURE.md, etc.). This solves most context bloat problems for agent teams: each teammate in `/creview-spec` and `/caudit` starts fresh.

**`/compact`** is a user-invocable command, not something a skill prompt can call programmatically. It's relevant in one specific scenario: the **lead orchestrator** in multi-round `/caudit` loops, where the lead accumulates findings across rounds within a single session. For this case:
- The `/caudit` skill prompt should recommend: "Between audit rounds, run `/compact` retaining only the current findings summary and convergence status."
- Alternatively, the lead can spawn each round as a separate forked subagent, avoiding accumulation entirely.

For `/creview-spec`, `context: fork` makes `/compact` unnecessary — the review agents already start clean.

### `/effort` Per Phase

The `/effort` command controls reasoning depth. **Note**: `/effort` is not settable via skill frontmatter — it's a user-invocable command. Skill prompts should include a recommendation: "For best results, set `/effort high` before running this skill." The implementation agent should explore whether effort can be set programmatically via the Agent SDK's options.

| Phase | Recommended Effort | Rationale |
|-------|--------|-----------|
| Spec authoring | high | Deep reasoning about invariants and threat models |
| Alloy modeling | high | Precise formal syntax generation |
| Review-spec | high | Adversarial reasoning requires depth |
| TDD RED (test agent) | high | Test design from invariants requires care. Separate agent. |
| TDD GREEN (impl agent) | medium | Implementation is more mechanical. Separate agent — never sees test-writing context. |
| TDD QA (QA agent) | high | Bug finding requires depth. Third agent — independent of test and impl. |
| Verify | medium | Structured checklist-driven verification |
| Audit agents | high | Adversarial bug hunting |
| Documentation | medium | Structured writing |
| Postmortem | high | Root cause analysis |

### `--worktree` for Branch Isolation

Claude Code's `--worktree` flag creates an isolated git worktree for a session. The workflow can use this instead of requiring manual branch creation:

- `/ctdd init` could use `--worktree feature/{task-slug}` to create an isolated workspace automatically
- `/caudit` could use `--worktree audit/{type}-{date}` for audit fix rounds
- This prevents workflow sessions from interfering with each other when running parallel features

The `/csetup` skill should detect whether the user prefers manual branch creation or automatic worktrees and configure accordingly.

---

## Hook Configuration

### `.claude/settings.json`

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Edit|Write|MultiEdit|CreateFile|Bash",
        "command": ".claude/skills/workflow/hooks/workflow-gate.sh",
        "timeout_ms": 5000
      }
    ]
  },
  "permissions": {
    "allow": [
      "Bash(.claude/skills/workflow/hooks/workflow-advance.sh *)"
    ]
  }
}
```

---

## Workflow Lifecycle

### Full feature lifecycle:

```
Human: "I want to add localhost traffic inspection"
  │
  ├── Create feature branch (or confirm not on main)
  │
  ├── /cspec
  │   ├── Conversation: what, why, adversary model, failure modes
  │   ├── Reads: ARCHITECTURE.md, antipatterns, drift debt, relevant source
  │   ├── Produces: docs/specs/localhost-inspection.md
  │   └── Human approves spec
  │
  ├── /cmodel (if formal_model enabled)
  │   ├── Translate spec invariants + trust boundaries into Alloy model
  │   ├── Model attacker capabilities from STRIDE analysis
  │   ├── Run Alloy Analyzer on all assertions
  │   ├── If counterexample found: translate to concrete attack scenario
  │   │   ├── Present to human, propose spec revision
  │   │   └── Loop until all counterexamples resolved
  │   ├── Human reviews model for faithfulness to system
  │   └── Produces: docs/models/{slug}.als + results
  │
  ├── /creview-spec
  │   ├── Agent team: red team, assumptions auditor, testability auditor, design contract checker
  │   ├── Teammates work independently in parallel, lead synthesizes findings
  │   ├── Lead synthesizes, presents disagreements to human
  │   ├── Optional: external model review on flagged invariants (spec-only, no source)
  │   ├── Spec revised with findings incorporated
  │   └── Human approves revised spec
  │
  ├── /ctdd
  │   ├── RED: write tests for each invariant (source edits blocked)
  │   │   └── Gate: tests exist and FAIL
  │   ├── GREEN: implement (test edits logged)
  │   │   └── Gate: tests pass, race detector clean
  │   ├── QA: agent review + mutation testing (all edits blocked)
  │   │   └── Gate: zero critical/high, min rounds met
  │   ├── VERIFY: final checks (all edits blocked)
  │   │   └── Gate: tests pass, coverage non-negative, findings resolved, no test weakening
  │   ├── SPEC-UPDATE (escape hatch): if spec is wrong mid-TDD
  │   │   ├── Log reason and phase, preserve all TDD state
  │   │   ├── Edit only the wrong invariants
  │   │   ├── /creview-spec scoped to changed invariants only
  │   │   ├── Resume TDD from RED phase
  │   │   └── Warning if >3 spec updates (consider full re-spec)
  │   └── DONE: phase set to done, state file persists until merge
  │
  ├── /cverify
  │   ├── Invariant coverage matrix
  │   ├── Mutation testing on high-risk invariants
  │   ├── Prohibition checks
  │   ├── Spec drift detection
  │   ├── Design contract compliance
  │   ├── Spec update history included in report
  │   └── Produces: verification report + proposed ARCHITECTURE.md updates
  │
  ├── /cupdate-arch (if verification found undocumented abstractions)
  │   └── Updates ARCHITECTURE.md with new entries
  │
  ├── /cdocs (update documentation before merge)
  │   ├── Update README if features changed
  │   ├── Create/update feature docs in docs/
  │   ├── Update Mermaid architecture diagrams
  │   ├── Update AGENT_CONTEXT.md with new components, patterns, pitfalls
  │   └── Human approves doc changes
  │
  ├── Merge feature branch to main (strategy per config: squash or merge-commit)
  │
  └── /caudit (periodic or pre-release, on audit/* branch)
      ├── Creates audit/{type}-{date} branch from main
      ├── Multi-round convergence loop (auto-commit per fix round)
      ├── Fresh agent team each round
      ├── Fix → re-audit until convergence (zero critical/high + no new medium/low)
      ├── Post-convergence regression tests
      ├── Optional: external model fresh-eyes pass (source included)
      ├── Merge audit branch to main (strategy per config)
      └── Update antipatterns
```

### Lighter workflows:

Not every change needs the full pipeline. The skills are composable:

- **Small bug fix**: `/ctdd` only on a `fix/{slug}` branch (skip spec/review if the fix is obvious and doesn't change any invariant)
- **Config change**: no workflow needed (non-source files aren't gated)
- **Documentation update**: no workflow needed
- **Refactor without behavior change**: `/ctdd` on a `refactor/{slug}` branch (tests should already exist and keep passing) + `/cverify` (check for spec drift)
- **New feature, low risk**: `/cspec` → `/ctdd` → `/cverify` → `/cdocs` on a `feature/{slug}` branch (skip review-spec and audit)
- **New feature, high risk**: full pipeline on a `feature/{slug}` branch
- **Pre-release audit**: `/caudit` with full scope on an `audit/{type}-{date}` branch

The human decides which skills to invoke. The enforcement only kicks in once a skill creates a state file — if you don't run `/ctdd`, there's no gating. This preserves backward compatibility for non-workflow changes. All workflow-initiated work happens on branches; squash merge to main when complete.

---

## Project-Specific Customization

### Go security proxy example: `.claude/workflow-config.json`

```json
{
  "project": {
    "name": "my-proxy",
    "language": "go",
    "description": "transparent security proxy for network traffic inspection and threat detection"
  },
  "commands": {
    "test": "go test ./...",
    "test_json": "go test -json ./...",
    "test_race": "go test -race -short ./...",
    "coverage": "go test -coverprofile=coverage.out ./...",
    "lint": "go vet ./...",
    "build": "go build ./cmd/proxy/",
    "mutation_tool": "go-mutesting --no-exec-command"
  },
  "patterns": {
    "test_file": "*_test.go",
    "source_file": "*.go",
    "test_fail_pattern": "FAIL",
    "build_error_pattern": "cannot|undefined|syntax error"
  },
  "workflow": {
    "intensity": "critical",
    "min_qa_rounds": 2,
    "max_audit_rounds": 7,
    "require_external_review": true,
    "external_models": {
      "codex": {"command": "codex exec \"{prompt}\" --sandbox read-only", "stdin_file": true, "timeout_seconds": 300},
      "gemini": {"command": "gemini \"{prompt}\"", "stdin_file": true, "timeout_seconds": 300}
    },
    "external_review_threshold": "high",
    "mutation_count": 10,
    "require_stride": true,
    "formal_model": true,
    "alloy_jar": "/opt/alloy/org.alloytools.alloy.dist.jar",
    "auto_update_antipatterns": true,
    "fail_closed_when_no_state": true,
    "merge_strategy": "merge"
  },
  "audit_presets": {
    "qa": {
      "focus_areas": [
        "concurrency: race conditions, deadlocks, goroutine leaks, missing mutex coverage",
        "parity: Go/Python feature drift, stub files missing methods, config lifecycle",
        "cleanup: unclosed connections, leaked goroutines, iptables rules not cleaned on crash",
        "detection: rule gaps, FP-prone regex, missing FP test cases, scan limit edge cases"
      ]
    },
    "security": {
      "focus_areas": [
        "encoding bypass: normalization tricks, double encoding, null bytes in hostnames",
        "protocol abuse: HTTP smuggling, TLS renegotiation, WebSocket upgrade hijacking",
        "config manipulation: SIGHUP race conditions, config desync between fields",
        "detection bypass: regex anchoring failures, content-type routing bypass, scan limit abuse",
        "network: UID-based exclusion bypass, SO_MARK gaps, ECH/SNI confusion"
      ]
    }
  }
}
```

### TypeScript web app example: `.claude/workflow-config.json`

```json
{
  "project": {
    "name": "my-web-app",
    "language": "typescript",
    "description": "SaaS dashboard for analytics"
  },
  "commands": {
    "test": "npm test",
    "test_json": "npm test -- --json",
    "test_verbose": "npm test -- --verbose",
    "coverage": "npm test -- --coverage",
    "lint": "npm run lint",
    "build": "npm run build",
    "format": "npm run format"
  },
  "patterns": {
    "test_file": "*.test.ts|*.test.tsx|*.spec.ts|*.spec.tsx",
    "source_file": "*.ts|*.tsx",
    "test_fail_pattern": "FAIL|failing",
    "build_error_pattern": "error TS|Cannot find|SyntaxError"
  },
  "workflow": {
    "intensity": "low",
    "min_qa_rounds": 1,
    "require_external_review": false,
    "mutation_count": 5,
    "require_stride": false,
    "auto_update_antipatterns": true
  }
}
```

### Polyglot projects

For projects with multiple languages (e.g., Go backend + TypeScript frontend + Python ML pipeline), the flat `commands` and `patterns` objects break down. Use directory-scoped overrides:

```json
{
  "project": {
    "name": "my-platform",
    "language": "polyglot",
    "description": "platform with Go backend, TypeScript frontend, Python data pipeline"
  },
  "commands": {
    "test": "make test-all",
    "lint": "make lint-all",
    "build": "make build-all"
  },
  "patterns": {
    "test_file": "*_test.go|*.test.ts|*.test.tsx|test_*.py|*_test.py",
    "source_file": "*.go|*.ts|*.tsx|*.py"
  },
  "scopes": {
    "backend/": {
      "language": "go",
      "commands": {
        "test": "cd backend && go test ./...",
        "test_race": "cd backend && go test -race -short ./...",
        "coverage": "cd backend && go test -coverprofile=coverage.out ./...",
        "lint": "cd backend && go vet ./...",
        "mutation_tool": "cd backend && go-mutesting --no-exec-command"
      },
      "patterns": {
        "test_file": "*_test.go",
        "source_file": "*.go",
        "test_fail_pattern": "FAIL",
        "build_error_pattern": "cannot|undefined|syntax error"
      }
    },
    "frontend/": {
      "language": "typescript",
      "commands": {
        "test": "cd frontend && npm test",
        "coverage": "cd frontend && npm test -- --coverage",
        "lint": "cd frontend && npm run lint",
        "mutation_tool": "cd frontend && npx stryker run --reporters json"
      },
      "patterns": {
        "test_file": "*.test.ts|*.test.tsx",
        "source_file": "*.ts|*.tsx",
        "test_fail_pattern": "FAIL|failing",
        "build_error_pattern": "error TS|Cannot find"
      }
    },
    "pipeline/": {
      "language": "python",
      "commands": {
        "test": "cd pipeline && pytest",
        "coverage": "cd pipeline && pytest --cov",
        "lint": "cd pipeline && ruff check .",
        "mutation_tool": "cd pipeline && mutmut run"
      },
      "patterns": {
        "test_file": "test_*.py|*_test.py",
        "source_file": "*.py",
        "test_fail_pattern": "FAILED|ERROR",
        "build_error_pattern": "SyntaxError|ImportError"
      }
    }
  },
  "workflow": {
    "intensity": "high"
  }
}
```

**How scopes work**: when the workflow gate or advance script operates on a file, it resolves the scope by checking which `scopes` prefix matches the file path. If multiple prefixes match (e.g., `backend/` and `backend/shared/`), the **longest matching prefix wins**. The matching scope's commands and patterns override the top-level defaults. If no scope matches, the top-level config applies. This means the `/ctdd` skill runs the correct test command for the language of the file being edited, and the gate applies the correct file patterns.

The `/cspec` skill should note which scopes a feature touches. A feature that spans `backend/` and `frontend/` may need tests in both scopes, and the `/ctdd` gate needs to know that source file patterns differ between them.

---

## Workflow Intensity Levels

The `workflow.intensity` field in `workflow-config.json` controls how much ceremony each skill requires. This can be set project-wide and overridden per-invocation.

### Level definitions

| Setting | `min_qa_rounds` | `mutation_count` | `require_stride` | `formal_model` | `require_external_review` | Review-spec agents | Audit convergence | `max_audit_rounds` | `fail_closed_when_no_state` |
|---------|----------------|-----------------|-------------------|---------------|--------------------------|-------------------|-------------------|-------------------|----------------------------|
| `low` | 1 | 3 | false | false | false | 2 (assumptions + testability) | 1 clean round | 3 | false |
| `standard` | 2 | 5 | false | false | false | 3 (+ red team) | 1 clean round | 5 | false |
| `high` | 2 | 10 | true | optional | on flagged invariants | 4 (full team) | 2 clean rounds | 5 | **true** |
| `critical` | 3 | 15 | true | **true** | on all security invariants | 4 (full team) + external | 2 clean rounds + external pass | 7 | **true** |

### How intensity is applied

Skills read `workflow.intensity` and use it to set defaults for any field the user hasn't explicitly overridden. Explicit config values always win — intensity is a preset, not a constraint.

Example: a project sets `"intensity": "high"` but overrides `"mutation_count": 20`. The project gets high-intensity defaults everywhere except mutation count, which uses 20.

### Per-invocation override

The human can override intensity for a single feature:
```
/cspec --intensity critical
```
This sets the intensity for the current workflow state file without changing the project config. Useful for: "this feature touches a trust boundary, crank it up."

### Choosing intensity

The `/cspec` skill, after drafting the spec, recommends an intensity level based on the spec content:
- Touches a trust boundary → recommend `high` or `critical`
- Security-categorized invariants present → recommend `high` or `critical`
- Concurrency-categorized invariants present → recommend at least `standard`
- Pure functional change, no boundaries → `low` is fine

The recommendation is advisory — the human decides. The skill does NOT auto-escalate without asking.

---

## Invariant Templates

The `/cspec` skill loads category-specific invariant templates to prevent under-specification of tricky domains. Templates live at `.claude/templates/invariants/` and provide structured prompts for each category.

### Shipped templates

#### Concurrency (`concurrency.md`)
When a feature involves goroutines, channels, mutexes, or shared state, the `/cspec` skill loads this template and ensures the spec addresses:

- Every goroutine has an explicit shutdown path via `ctx.Done()` or equivalent
- Every mutex has bounded hold time — no lock held across I/O or network calls
- Every channel has a documented producer, consumer, and backpressure strategy
- Every shared data structure has a documented synchronization strategy
- Race detector passes under load (not just unit tests)

For each applicable item, the template generates a starter invariant the spec author refines.

#### Resource Lifecycle (`resource-lifecycle.md`)
When a feature allocates resources (connections, file handles, iptables rules, goroutines, map entries):

- Every resource allocation has a corresponding release
- Every `defer` cleanup is ordered correctly (LIFO relative to acquisition)
- Error paths release resources (not just happy path)
- Crash paths have failsafe cleanup (or document why they don't)
- Long-lived map/cache entries have an eviction or cleanup path

#### Config Lifecycle (`config-lifecycle.md`)
When a feature adds or modifies configuration fields:

- New field appears in: raw struct, parse function, save function, defaults function, validation function, SIGHUP reload handler
- Field is validated at parse time (normalize-at-parse convention)
- Field has a documented default value and the default is safe
- Fields that must agree (e.g., redirect port vs proxy listen port) are validated together
- SIGHUP reload of this field doesn't cause a race with in-flight requests

#### Network & Protocol (`network-protocol.md`)
When a feature involves network communication, TLS, or protocol handling:

- All outbound connections use the project's dialer abstraction (if one exists)
- TLS certificate validation is explicit (not default-trusted)
- SNI/hostname handling distinguishes between outer (untrusted) and inner (verified) values
- Connection timeouts are set on all paths (dial, TLS handshake, request, idle)
- Proxy/forwarding preserves or explicitly strips security-relevant headers

#### Security & Detection (`security-detection.md`)
When a feature involves detection rules, pattern matching, or security decisions:

- Every new detection rule has both true-positive and false-positive test cases
- Regex patterns are anchored appropriately (no unanchored `.*` matching benign substrings)
- Scan/inspection limits emit a truncation event when hit
- Block actions document exactly what they prevent (and what they don't)
- Bypass vectors are enumerated: encoding tricks, chunked transfer, case normalization

#### Data Integrity (`data-integrity.md`)
When a feature transforms, stores, or transmits data:

- Byte length vs character count is explicit for any Unicode operation
- Serialization roundtrips preserve data: `deserialize(serialize(x)) == x`
- Partial writes are atomic or recoverable
- Data validation happens at ingress, not at use-site
- Error messages don't leak sensitive data

### Custom templates

Projects can add custom templates at `.claude/templates/invariants/{name}.md`. The `/cspec` skill discovers them automatically. Templates follow the same format: a category description, a checklist of concerns, and starter invariant structures.

### How templates are used

The `/cspec` skill doesn't blindly apply every template. During the conversation with the human, when the feature's scope becomes clear, the skill identifies which categories apply and loads those templates. It then walks through each template item and asks whether it's relevant. Relevant items become draft invariants in the spec. Irrelevant items are skipped — not silently, but with a noted reason ("not applicable: feature doesn't allocate goroutines").

---

## Meta-Verification: Workflow Effectiveness Tracking

Track whether the workflow is actually catching bugs, and which phases are doing the catching. This creates a feedback loop on the workflow itself.

### Tracking file: `.claude/meta/workflow-effectiveness.json`

```json
{
  "post_merge_bugs": [
    {
      "id": "PMB-001",
      "date": "2026-03-26",
      "description": "goroutine leak in DNS handler when context cancelled during active query",
      "severity": "high",
      "found_by": "manual testing | user report | monitoring | audit",
      "root_cause": "missing select on ctx.Done() in goroutine",
      "spec_existed": true,
      "spec_id": "localhost-inspection",
      "invariant_existed": true,
      "invariant_id": "INV-003",
      "phase_that_should_have_caught": "tdd-qa",
      "phase_was_skipped": false,
      "why_missed": "mutation testing didn't target this goroutine — mutation budget spent on dialer paths",
      "corrective_action": {
        "antipattern_added": true,
        "antipattern_id": "AP-012",
        "invariant_template_updated": true,
        "template": "concurrency.md",
        "addition": "added: mutation budget must cover all goroutine spawn sites, not just highest-risk",
        "drift_debt_created": false
      }
    }
  ],
  "phase_effectiveness": {
    "spec": {
      "bugs_that_should_have_been_caught_here": 2,
      "bugs_actually_caught_here": 0,
      "notes": "spec phase tends to miss concurrency issues — consider adding concurrency template auto-load when goroutines detected"
    },
    "review-spec": {
      "bugs_that_should_have_been_caught_here": 1,
      "bugs_actually_caught_here": 1,
      "notes": null
    },
    "tdd-qa": {
      "bugs_that_should_have_been_caught_here": 5,
      "bugs_actually_caught_here": 3,
      "notes": "mutation testing budget too low for large features — consider scaling with file count"
    },
    "verify": {
      "bugs_that_should_have_been_caught_here": 1,
      "bugs_actually_caught_here": 1,
      "notes": null
    },
    "audit": {
      "bugs_that_should_have_been_caught_here": 3,
      "bugs_actually_caught_here": 3,
      "notes": null
    }
  },
  "workflow_skips": [
    {
      "date": "2026-03-20",
      "feature": "config-reload-fix",
      "phases_skipped": ["spec", "review-spec"],
      "reason": "small bug fix, obvious invariant",
      "bug_escaped": true,
      "bug_id": "PMB-001"
    }
  ]
}
```

### How it's maintained

This file is updated via the `/cpostmortem` skill (Skill 10) when a bug is found after merge. The key fields are:

- `phase_that_should_have_caught`: which phase in the workflow was responsible for catching this class of bug
- `phase_was_skipped`: whether that phase was actually run
- `why_missed`: if the phase ran but missed it, what went wrong

### How it's consumed

The `/cspec` skill reads `phase_effectiveness` and uses it to inform recommendations:
- If a phase has a pattern of missing a specific category, the skill recommends higher intensity or additional invariants in that category
- If `workflow_skips` shows a pattern of bugs escaping from skipped phases, the skill mentions it: "last 3 bugs that escaped came from features where `/creview-spec` was skipped"

The `/caudit` skill reads `post_merge_bugs` as an additional input alongside the antipatterns checklist — these are bugs that the whole workflow missed, so the audit should specifically look for similar patterns.

### Periodic review

The `/cverify` skill includes a section in its report: "Workflow health: {N} post-merge bugs in the last 30 days, {M} from skipped phases, top missed phase: {phase}." This surfaces workflow effectiveness without requiring a separate skill invocation.

---

## Files to Create

| File | Purpose |
|------|---------|
| `.claude/skills/workflow/hooks/workflow-gate.sh` | PreToolUse hook — phase-based edit gating |
| `.claude/skills/workflow/hooks/workflow-advance.sh` | State transition script with real gates |
| `.claude/skills/workflow/spec/SKILL.md` | `/cspec` skill prompt |
| `.claude/skills/workflow/model/SKILL.md` | `/cmodel` skill prompt |
| `.claude/skills/workflow/review-spec/SKILL.md` | `/creview-spec` skill prompt |
| `.claude/skills/workflow/tdd/SKILL.md` | `/ctdd` skill prompt |
| `.claude/skills/workflow/verify/SKILL.md` | `/cverify` skill prompt |
| `.claude/skills/workflow/audit/SKILL.md` | `/caudit` skill prompt |
| `.claude/skills/workflow/update-arch/SKILL.md` | `/cupdate-arch` skill prompt |
| `.claude/skills/workflow/docs/SKILL.md` | `/cdocs` skill prompt |
| `.claude/skills/workflow/setup/SKILL.md` | `/csetup` skill prompt |
| `.claude/skills/workflow/postmortem/SKILL.md` | `/cpostmortem` skill prompt |
| `setup` | Install script (executable, runs detection + scaffolding) |
| `ARCHITECTURE.md` | Template — project fills in (or `/csetup` bootstraps) |
| `AGENT_CONTEXT.md` | Template — agent onboarding brief |
| `.claude/workflow-config.json` | Template — project fills in |
| `.claude/antipatterns.md` | Empty template |
| `.claude/meta/workflow-effectiveness.json` | Meta-verification tracking (starts empty) |
| `.claude/meta/drift-debt.json` | Drift debt tracking (starts empty) |
| `.claude/templates/invariants/concurrency.md` | Invariant template: goroutines, mutexes, channels |
| `.claude/templates/invariants/resource-lifecycle.md` | Invariant template: allocation, cleanup, crash paths |
| `.claude/templates/invariants/config-lifecycle.md` | Invariant template: config field completeness |
| `.claude/templates/invariants/network-protocol.md` | Invariant template: connections, TLS, headers |
| `.claude/templates/invariants/security-detection.md` | Invariant template: rules, regex, bypass vectors |
| `.claude/templates/invariants/data-integrity.md` | Invariant template: encoding, serialization, validation |
| `.claude/helpers/pbt-go.md` | PBT helper: rapid for Go |
| `.claude/helpers/pbt-python.md` | PBT helper: hypothesis for Python |
| `.claude/helpers/pbt-typescript.md` | PBT helper: fast-check for TypeScript |
| `.claude/helpers/pbt-rust.md` | PBT helper: proptest for Rust |

---

## Installation & Setup

### Install (30 seconds)

Correctless is a git repo that gets cloned into the project's `.claude/skills/` directory. Everything is self-contained.

```bash
# Add to your project (replace joshft/correctless with actual repo URL)
git clone https://github.com/joshft/correctless.git .claude/skills/workflow
cd .claude/skills/workflow && ./setup
```

The `setup` script does the following automatically:

1. **Detects project language** — scans the repo for `go.mod`, `package.json`, `Cargo.toml`, `requirements.txt`, `pyproject.toml`, or mixed (polyglot). Sets `project.language` accordingly.

2. **Detects existing tools** — checks for installed mutation testing tools (`go-mutesting`, `stryker`, `cargo-mutants`, `mutmut`), Alloy JAR, and external model CLIs (`codex`, `gemini`). Configures what's available, leaves the rest null.

3. **Detects test runner** — identifies the test command, coverage command, and whether structured JSON output is available. Pre-fills `commands.*` fields.

4. **Registers hooks** — merges the `PreToolUse` hook into the project's `.claude/settings.json`. If settings.json doesn't exist, creates it. If it exists, appends the hook without clobbering existing hooks.

5. **Registers skills** — the skill files live within the cloned repo at `.claude/skills/workflow/{name}/SKILL.md`. Claude Code discovers them automatically from the `.claude/skills/` directory — no symlinks or copies needed.

6. **Scaffolds project files** — creates the directory structure and empty templates:
   - `ARCHITECTURE.md` — template with section headers, instructions, and one example entry per section
   - `AGENT_CONTEXT.md` — template with section headers and placeholder text
   - `.claude/workflow-config.json` — pre-filled with detected values, ready for human review
   - `.claude/antipatterns.md` — empty template with format instructions
   - `.claude/meta/workflow-effectiveness.json` — empty `{}`
   - `.claude/meta/drift-debt.json` — empty `{}`
   - `.claude/meta/external-review-history.json` — empty `{}`
   - `.claude/artifacts/` — created with `.gitignore` inside it
   - `docs/specs/`, `docs/models/`, `docs/diagrams/`, `docs/features/`, `docs/verification/` — created empty

7. **Updates `.gitignore`** — adds `.claude/artifacts/` if not already present.

8. **Updates `CLAUDE.md`** — appends a section pointing to Correctless:
   ```markdown
   ## Correctless
   This project uses Correctless for correctness-oriented development.
   Read AGENT_CONTEXT.md before starting any work.
   Available commands: /cspec, /cmodel, /creview-spec, /ctdd, /cverify, /caudit, /cupdate-arch, /cdocs, /csetup
   ```
   If CLAUDE.md doesn't exist, creates it with this content plus basic project info.

9. **Prints summary** — shows what was detected, what was configured, and what the human should review:
   ```
   ✓ Detected: Go project (go.mod found)
   ✓ Test command: go test ./...
   ✓ Structured output: go test -json ./...
   ✓ Race detector: go test -race -short ./...
   ✓ Mutation tool: go-mutesting (found in PATH)
   ✓ Alloy: not found (formal modeling disabled)
   ✓ External models: codex (found), gemini (not found)
   ✓ Hooks registered in .claude/settings.json
   ✓ Commands registered: /cspec /cmodel /creview-spec /ctdd /cverify /caudit /cupdate-arch /cdocs /csetup
   
   Created:
     .claude/workflow-config.json  ← review and adjust
     ARCHITECTURE.md               ← fill in your project's architecture
     AGENT_CONTEXT.md              ← fill in or run /cdocs to auto-generate
   
   Next steps:
     1. Review .claude/workflow-config.json — adjust intensity, enable formal_model if desired
     2. Fill in ARCHITECTURE.md — at minimum, document your trust boundaries and core abstractions
     3. Try it: create a feature branch and run /cspec
   ```

### `/csetup` skill (post-install configuration)

After initial install, the `/csetup` command can be re-run to:

- **Re-detect tools** — if you install `go-mutesting` or Alloy after initial setup, `/csetup` picks them up
- **Adjust intensity** — interactive: "What intensity level? This is a security proxy → recommending `critical`"
- **Configure audit presets** — interactive: "What should QA Olympics focus on? What should Hacker Olympics focus on?" Generates the `audit_presets` section of workflow-config.json
- **Configure external models** — interactive: "Do you have Codex CLI? Gemini CLI? Which should be used for external review?"
- **Bootstrap ARCHITECTURE.md** — if the file is still the template, `/csetup` can scan the codebase and draft initial entries:
  - Scan for package structure → suggest key components
  - Scan for network listeners / TLS configs → suggest trust boundaries
  - Scan for config structs → suggest config lifecycle patterns
  - Scan for goroutine spawns → suggest concurrency abstractions
  - Present each suggestion for human approval
- **Bootstrap AGENT_CONTEXT.md** — if the file is still the template, `/csetup` reads the codebase, ARCHITECTURE.md, CLAUDE.md, and recent git history to draft the agent context. Presents to human for approval.
- **Validate existing setup** — checks that hooks are registered, commands are accessible, config is valid, required files exist. Reports any issues.

### Updating

```bash
cd .claude/skills/workflow && git pull && ./setup
```

The setup script is idempotent — re-running it detects what's already configured and only updates what's changed. It never overwrites user-edited files (ARCHITECTURE.md, workflow-config.json, antipatterns.md) — it only creates them if they don't exist.

### Uninstalling

```bash
# Remove skills and hooks
rm -rf .claude/skills/workflow
# The setup script adds a comment tag to hooks it registered — grep and remove:
# Look for "# correctless" in .claude/settings.json and remove those entries
```

### For teammates

If Correctless is committed to the repo (`.claude/skills/workflow/`), teammates get it automatically on `git clone`. They just need to run:

```bash
cd .claude/skills/workflow && ./setup
```

This registers hooks and commands in their local `.claude/settings.json` without touching committed project files.

---

## Implementation Order

### Phase 0: Setup & Install
1. `setup` script — language detection, tool detection, hook registration, scaffolding
2. `/csetup` skill prompt — interactive configuration, ARCHITECTURE.md bootstrap, validation
3. Test: run setup on a fresh Go project, a fresh TypeScript project, and a polyglot project

### Phase 1: Foundation
1. `workflow-config.json` schema and validation (including intensity levels)
2. `ARCHITECTURE.md` template
3. `antipatterns.md` template
4. `workflow-gate.sh` — hook with phase gating
5. `workflow-advance.sh` — state machine with all gates (including `spec-update`)
6. `workflow-effectiveness.json` — empty meta-verification tracking file
7. Manual test: verify all transitions and blocks work, including branch enforcement

### Phase 2: Invariant templates
8. `concurrency.md` template
9. `resource-lifecycle.md` template
10. `config-lifecycle.md` template
11. `network-protocol.md` template
12. `security-detection.md` template
13. `data-integrity.md` template

### Phase 3: Spec skills
14. `/cspec` skill prompt (with template loading and intensity recommendation)
15. `/cmodel` skill prompt (Alloy model generation and analysis)
16. `/creview-spec` skill prompt (agent team version)
17. Spec artifact format validation
18. Test: run `/cspec` → `/cmodel` → `/creview-spec` on a small real feature

### Phase 4: TDD skill
19. `/ctdd` skill prompt (orchestrates the state machine)
20. Mutation testing integration
21. PBT helpers: `pbt-go.md`, `pbt-python.md`, `pbt-typescript.md`, `pbt-rust.md`
22. Test: run full RED-GREEN-QA-VERIFY cycle on a real feature, including PBT

### Phase 5: Verification
23. `/cverify` skill prompt (including workflow health reporting from meta-verification)
24. Invariant coverage matrix generation
25. Spec drift detection
26. Test: run on a feature with known gaps, verify it catches them

### Phase 6: Audit
27. `/caudit` skill prompt with presets and intensity-aware defaults
28. Agent team configuration for audit rounds
29. Convergence loop with regression testing
30. Test: run on a real codebase, verify convergence

### Phase 7: Integration & Feedback Loop
31. `/cupdate-arch` skill prompt
32. `/cdocs` skill prompt (including AGENT_CONTEXT.md generation)
33. `/cpostmortem` skill prompt
34. `AGENT_CONTEXT.md` template
35. `status-all` and `resolve-drift` commands in workflow-advance.sh
36. External model integration testing (generic CLI interface)
37. End-to-end test: full pipeline on a real feature (including Alloy modeling)
38. End-to-end test: `/cpostmortem` on a simulated post-merge bug
39. Documentation

---

## Resolved Design Decisions

1. **`/cspec` and `/creview-spec` are separate skills.** Cleaner state transitions, clearer responsibility boundaries. Human invokes each explicitly.

2. **Auto-commit to branches, configurable merge strategy.** All workflow-initiated work happens on feature branches. The `/ctdd` skill creates a branch at init if not already on one (refuses to run on main). The `/caudit` skill creates an `audit/{type}-{date}` branch for its fix rounds. Auto-commit between audit rounds for `git bisect` capability. Merge strategy is configurable: `"squash"` (default, clean history) or `"merge"` (preserves individual commits — recommended for security software where audit trail matters). See Branching Strategy below.

3. **Property-based tests via language-specific helpers.** The spec format supports `property-based` as a test approach value. The `/ctdd` skill delegates property-based test generation to a language-specific helper file that knows the PBT library for the project's language. See Property-Based Testing Helpers below.

4. **Spec-only for `/creview-spec`, source-included for post-convergence `/caudit` external pass.** External models during spec review see only the spec invariants + ARCHITECTURE.md context — no source code. External models during the post-convergence audit pass see the implementation source for the changed files. This balances token cost against review depth.

5. **`spec-update` transition exists but is logged and requires re-review.** If the implementing agent discovers the spec is wrong mid-TDD, it can invoke `workflow-advance.sh spec-update "reason"`. This pauses TDD, sets phase back to `spec` with `is_spec_update: true` and logs the reason and the current TDD phase. Only the changed invariants need re-review (the `/creview-spec` skill checks which invariants were modified and scopes review to those). The full audit trail of spec updates is preserved in the state file history. This prevents "reset and lose all context" while keeping the escape hatch from becoming a bypass.

---

## Branching Strategy

### Rules

- **Never commit workflow-initiated changes directly to main.** Skills refuse to operate if the current branch is `main` (or the project's default branch). Exception: `/caudit` can *read* main but creates its own branch for fixes.
- **`/ctdd` creates a feature branch** at init if the user isn't already on one. Branch name: `feature/{task-slug}` or user-provided.
- **`/caudit` creates an audit branch** at start: `audit/{type}-{date}` (e.g., `audit/security-2026-03-26`). Fixes are committed here. After convergence, the human merges.
- **Auto-commit during audit rounds.** Each fix round gets a commit with a structured message: `fix(audit-{type}-r{round}): {finding-id} — {one-line description}`. This enables `git bisect` if a fix introduces a regression.
- **Merge strategy is configurable.** `workflow.merge_strategy` in config: `"squash"` (default — clean history, single commit per feature) or `"merge"` (preserves individual commits — better for `git bisect` and audit trails). For security software where the full commit history of a fix matters (which finding ID drove which change), `"merge"` is recommended. The structured commit messages (`fix(audit-security-r2): QA-SEC-007 — ...`) are valuable precisely because they're individually `git bisect`-able. For typical projects, `"squash"` keeps history clean.

### State file and branch awareness

The workflow state file records the branch at init. On every `workflow-advance.sh` invocation, the script checks the current branch. If the branch has changed since state was created:
- Emit a warning: "Workflow state was created on branch `feature/X`, current branch is `main`. Run `workflow-advance.sh reset` to clear stale state."
- Do NOT auto-reset — the user may be on a detached HEAD during rebase.
- Do NOT allow phase transitions on a mismatched branch.

---

## Property-Based Testing Helpers

The spec format allows any invariant to specify `test_approach: property-based`. When the `/ctdd` skill encounters such an invariant during the RED phase, it delegates to a language-specific helper that knows how to write PBT tests.

### Helper interface

Each helper is a reference file at `.claude/helpers/pbt-{language}.md` that the `/ctdd` skill reads before generating property-based tests. It contains:

- Which PBT library to use (e.g., `rapid` for Go, `hypothesis` for Python, `fast-check` for TypeScript)
- Import patterns and test structure
- How to define generators for project-specific types
- How to express invariants as properties
- How to integrate with the project's existing test runner

### Shipped helpers

Correctless ships with helpers for:

| Language | Library | Helper file |
|----------|---------|-------------|
| Go | `pgregory.net/rapid` | `pbt-go.md` |
| Python | `hypothesis` | `pbt-python.md` |
| TypeScript | `fast-check` | `pbt-typescript.md` |
| Rust | `proptest` | `pbt-rust.md` |

### When to use PBT vs example-based tests

The `/cspec` skill should recommend `property-based` as the test approach when:
- The invariant is about a relationship between inputs and outputs (e.g., "for all valid configs, parse(save(config)) == config")
- The invariant involves numeric boundaries or ranges
- The invariant is about preservation of a property across transformation (e.g., "encoding then decoding yields the original")
- The invariant involves ordering, uniqueness, or set membership

Example-based tests remain appropriate when:
- The invariant is about a specific code path (e.g., "calling X with nil returns ErrNilInput")
- The invariant is about integration with an external system
- The test requires specific fixtures or test data

---

## Mutation Testing Strategy

Mutation testing verifies that tests actually catch the bugs they claim to prevent. The workflow uses **deterministic mutation tools** for speed and coverage, with LLM analysis for interpreting results.

### Principle: tools mutate, LLMs analyze

The LLM's job is to:
1. Read the spec invariants and identify which source files/functions implement them
2. Configure the mutation tool to target those files
3. Run the tool
4. Read the survivor report and map surviving mutants to spec invariants
5. Report surviving mutants as findings with invariant references

The LLM does NOT manually edit files to create mutants. That's slow, error-prone, and limited in coverage compared to purpose-built tools.

### Tool configuration

Add `commands.mutation_tool` to `workflow-config.json`. The tool must output a machine-readable report (JSON or structured text) that the LLM can parse.

| Language | Tool | Config key |
|----------|------|-----------|
| Go | `go-mutesting` | `"mutation_tool": "go-mutesting --no-exec-command"` |
| TypeScript | `Stryker` | `"mutation_tool": "npx stryker run --reporters json"` |
| Rust | `cargo-mutants` | `"mutation_tool": "cargo mutants --json"` |
| Python | `mutmut` | `"mutation_tool": "mutmut run --runner 'pytest'"` |

### Fallback: LLM-directed mutations

If no mutation tool is configured (or for languages without good tooling), the LLM falls back to manual mutations:
1. Read the source file implementing a spec invariant
2. Identify a high-value mutation target (error check, boundary condition, cleanup path, lock acquisition)
3. Apply the mutation (e.g., comment out an error check)
4. Run the test suite
5. Check if the relevant test fails
6. Restore the original code
7. Report result

This is slower (one mutation per cycle vs. hundreds in a tool run) and should be considered a degraded mode. The `workflow.mutation_count` setting caps how many LLM-directed mutations are attempted per run.

### Mutation budget scaling

The static `mutation_count` from workflow config is a baseline. The actual number of mutations should scale with the feature's risk profile:

- **Per-invariant floor**: every invariant at medium risk or above gets at least 1 mutation, regardless of priority ordering or total budget. This prevents the scenario where the entire budget is spent on critical invariants and a medium-risk concurrency invariant with a subtle bug gets zero mutations. The floor is checked first — allocate 1 per qualifying invariant, then distribute the remaining budget by priority.
- **Minimum total**: `mutation_count` from config (always run at least this many)
- **Scale up for**: high/critical-risk invariants — add 2 mutations per high-risk invariant, 4 per critical, on top of the floor
- **Scale down for**: features with few invariants — if a feature has only 3 invariants, 15 mutations is wasteful
- **Priority order for surplus budget**: after the per-invariant floor is met, distribute remaining budget targeting critical invariants first, then high, then medium.

This prevents the mutation budget from being either wasteful (15 mutations on a 20-line config change) or insufficient (5 mutations on a feature with 12 security invariants touching 3 trust boundaries).

### What surviving mutants mean

A surviving mutant (one that doesn't cause a test failure) means one of:
- The test suite doesn't cover this code path → **test gap** (severity: high)
- The test covers the path but the assertion is too weak → **weak test** (severity: medium)
- The mutation is semantically equivalent (e.g., `>=` vs `>` where the boundary value is never hit) → **not a real gap** (dismiss)

The LLM's analysis step distinguishes these cases by checking whether the mutated code path is reachable from any test and whether the assertions would detect the change.

---

## Spec Update Protocol

When the implementing agent discovers during TDD that a spec invariant is wrong, insufficient, or impossible to implement as written:

### Transition: `workflow-advance.sh spec-update "reason"`

**Valid from**: `tdd-tests`, `tdd-impl`, `tdd-qa`

**Behavior**:
1. Records in the state file:
   - `spec_update_reason`: the reason text
   - `spec_update_from_phase`: which TDD phase triggered the update
   - `spec_update_timestamp`: when the update was requested
   - `spec_update_count`: incremented (tracks how many times the spec has been revised)
2. Sets phase to `spec` with `is_spec_update: true`
3. Preserves all existing TDD state (test files, implementation, findings) — nothing is deleted

**What happens next**:
1. The human (or `/cspec` skill) edits the spec. Changes MUST be limited to the invariants that are actually wrong — not a wholesale rewrite. Each changed invariant gets a `revised: true` flag and a `revision_reason` field.
2. `/creview-spec` runs again, scoped to the revised invariants PLUS any invariants that share a boundary, abstraction, or environment assumption with the changed ones. Changing INV-003 can silently invalidate INV-007 if both depend on the same trust boundary — the review must check for cascading invalidation within the spec, not just the literal text of the changed invariant. The review team receives the revision reasons and evaluates whether the changes are justified and whether dependent invariants are still valid.
3. After review, `workflow-advance.sh tests` resumes TDD from the `tdd-tests` phase. If tests for the revised invariants already exist, they may need updating. If tests for unchanged invariants already pass, they don't need to be rewritten.

**Guardrails**:
- If `spec_update_count` exceeds 3 for a single task, the skill surfaces a warning: "This spec has been revised {N} times during implementation. Consider whether the feature is under-specified or whether the approach is fundamentally wrong. It may be better to `reset` and re-spec from scratch."
- All spec updates are visible in the final verification report — the `/cverify` skill shows the full revision history.
