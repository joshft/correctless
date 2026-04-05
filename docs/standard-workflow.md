# Standard Workflow Guide

The standard Correctless workflow enforces a linear pipeline: **spec, review, TDD, verify, docs, merge**. Each step is a separate skill invocation. The human decides when to advance — skills never auto-invoke the next skill.

[Back to documentation index](index.md)

---

## 1. Pipeline Overview

```mermaid
graph LR
    subgraph "Standard Intensity"
        S["/cspec<br>Write spec"] --> R["/creview<br>Skeptical review"]
        R --> T["/ctdd<br>Enforced TDD"]
        T --> V["/cverify<br>Verification"]
        V --> D["/cdocs<br>Documentation"]
        D --> M["Merge"]
    end

    subgraph "High+ Intensity adds"
        S2["/cspec"] --> RS["/creview-spec<br>4-agent adversarial"]
        RS --> T2["/ctdd"]
        T2 --> V2["/cverify"]
        V2 --> A["/cupdate-arch"]
        A --> D2["/cdocs"]
        D2 --> AU["/caudit<br>Olympics"]
        AU --> M2["Merge"]
    end

    style S fill:#4caf50,color:#fff
    style T fill:#ff9800,color:#fff
    style M fill:#2196f3,color:#fff
    style S2 fill:#4caf50,color:#fff
    style T2 fill:#ff9800,color:#fff
    style AU fill:#e91e63,color:#fff
    style M2 fill:#2196f3,color:#fff
```

At **high+ intensity**, the pipeline expands: `/creview` becomes `/creview-spec` (4-agent adversarial review), `/cupdate-arch` runs after verification, and `/caudit` (Olympics convergence audit) runs before merge.

The state machine in `hooks/workflow-advance.sh` enforces the ordering — you cannot skip phases or go backwards. Each transition has a gate that validates preconditions (e.g., tests must fail before advancing from RED to GREEN, verification report must exist before advancing to documented).

---

## 2. State Machine Transitions

```mermaid
stateDiagram-v2
    [*] --> spec: init
    spec --> review: review (standard)
    spec --> review_spec: review-spec (high+)
    spec --> model: model (critical+)
    model --> review_spec: review-spec

    review --> tdd_tests: tests
    review_spec --> tdd_tests: tests

    tdd_tests --> tdd_impl: impl (tests exist + fail)
    tdd_impl --> tdd_qa: qa (tests pass)
    tdd_qa --> tdd_impl: fix (findings exist)
    tdd_qa --> done: done (no findings, standard)
    tdd_qa --> tdd_verify: verify-phase (high+)
    tdd_verify --> done: done

    done --> verified: verified (report exists)
    verified --> documented: documented
    documented --> [*]: merge

    note right of tdd_tests: RED phase\nOnly test files allowed
    note right of tdd_impl: GREEN phase\nSource + test files allowed
    note right of tdd_qa: QA phase\nAll edits blocked
```

Each phase transition is a named command in `hooks/workflow-advance.sh`. Key gates:

| Transition | Gate |
|---|---|
| **init → spec** | Must be on a feature branch, not main |
| **spec → review/review-spec** | Spec file must exist |
| **review → tdd-tests** | Spec reviewed |
| **tdd-tests → tdd-impl (RED → GREEN)** | `commands.test_new` must fail — tests exist and are red |
| **tdd-impl → tdd-qa (GREEN → QA)** | `commands.test_new` must pass — implementation is green |
| **tdd-qa → done** | Full test suite (`commands.test`) must pass |
| **done → verified** | Verification report file must exist |
| **verified → documented** | Documentation updated |

State is stored in `.correctless/artifacts/workflow-state-{branch-slug}.json`. Only `workflow-advance.sh` writes to this file.

---

## 3. Hook Architecture

```mermaid
sequenceDiagram
    participant CC as Claude Code
    participant SFG as sensitive-file-guard.sh
    participant WG as workflow-gate.sh
    participant Tool as Edit/Write/Bash
    participant AT as audit-trail.sh
    participant AF as auto-format.sh
    participant SL as statusline.sh

    CC->>SFG: PreToolUse JSON (stdin)
    alt Sensitive file detected
        SFG-->>CC: exit 2 BLOCKED
    else Allowed
        SFG-->>CC: exit 0
    end

    CC->>WG: PreToolUse JSON (stdin)
    alt Phase violation
        WG-->>CC: exit 2 BLOCKED
    else Allowed
        WG-->>CC: exit 0
    end

    CC->>Tool: Execute tool
    Tool-->>CC: Result

    par PostToolUse hooks
        CC->>AT: audit-trail.sh (log + adherence)
        CC->>AF: auto-format.sh (format edited file)
    end

    Note over SL: Statusline renders continuously
```

Five hooks run on every tool call:

| Hook | Type | Purpose |
|---|---|---|
| **sensitive-file-guard.sh** | PreToolUse | Blocks writes to `.env`, credentials, keys. Fail-closed, no overrides. |
| **workflow-gate.sh** | PreToolUse | Enforces phase-specific file restrictions (RED blocks source, QA blocks everything). |
| **audit-trail.sh** | PostToolUse | Logs every file modification with phase context to JSONL. Tracks adherence metrics. |
| **auto-format.sh** | PostToolUse | Runs the project's formatter on edited files. Allowlist-validated, array-based execution. |
| **statusline.sh** | Statusline | Shows branch, phase, QA round, cost, context %, lines delta. |

All hooks follow [PAT-001](https://github.com/joshft/correctless/blob/main/.correctless/ARCHITECTURE.md): `set -euo pipefail` + `set -f`, jq check, bulk `eval`+`jq @sh` stdin parse, fast-path exit 0 before loading config.

---

## 4. TDD Cycle (RED → GREEN → QA)

```mermaid
graph TD
    START["Read spec + config"] --> RED
    RED["RED: Spawn test agent<br>(writes failing tests)"]
    RED --> AUDIT["Test Audit: Spawn auditor<br>(checks test quality)"]
    AUDIT -->|BLOCKING findings| FIXTEST["Fix tests"]
    FIXTEST --> AUDIT
    AUDIT -->|Clean| GREEN["GREEN: Spawn impl agent<br>(makes tests pass)"]
    GREEN --> SIMPLIFY["/simplify<br>(code cleanup)"]
    SIMPLIFY --> QA["QA: Spawn QA agent<br>(adversarial review)"]
    QA -->|BLOCKING findings| FIX["Fix round"]
    FIX --> QA
    QA -->|Clean| DONE["done"]

    style RED fill:#f44336,color:#fff
    style GREEN fill:#4caf50,color:#fff
    style QA fill:#ff9800,color:#fff
    style DONE fill:#2196f3,color:#fff
```

The `/ctdd` skill is an **orchestrator** — it spawns separate agents for each phase and never writes code itself. This enforces agent separation:

- **Test agent (RED)** sees the spec rules but no implementation plan
- **Implementation agent (GREEN)** sees the failing tests but didn't write them
- **QA agent** is independent of both — reviews with a hostile lens

**RED phase:** Tests are written encoding every spec rule (INV-xxx, PRH-xxx, BND-xxx). The workflow gate blocks source edits unless they contain `STUB:TDD` markers. A **test audit** agent checks test quality before implementation begins.

**GREEN phase:** The implementation agent makes tests pass. A calm reset prompt fires after 3 consecutive failures to redirect away from dead-end approaches.

**QA phase:** All edits are blocked. Every BLOCKING finding must include both an **instance fix** (fix this bug) and a **class fix** (prevent this category). The fix → re-QA loop runs up to 3 rounds at high intensity.

---

## 5. Phase Gating Decision Tree

```mermaid
graph TD
    INPUT["Tool call arrives"] --> SFG{"sensitive-file-guard<br>Sensitive file?"}
    SFG -->|Yes| BLOCK1["BLOCKED<br>(no overrides)"]
    SFG -->|No| WG{"workflow-gate<br>Parse stdin"}
    WG --> FAST{"Non-write tool?"}
    FAST -->|Yes| ALLOW1["ALLOW"]
    FAST -->|No| STATE{"Read state file"}
    STATE -->|No state| FC{"Fail-closed?"}
    FC -->|Yes + source| BLOCK2["BLOCKED"]
    FC -->|No| ALLOW2["ALLOW"]
    STATE -->|Has state| PHASE{"Check phase"}
    PHASE -->|done/verified/documented| ALLOW3["ALLOW"]
    PHASE --> OVERRIDE{"Override active?"}
    OVERRIDE -->|Yes| ALLOW4["ALLOW + decrement"]
    OVERRIDE -->|No| CLASSIFY{"Classify file"}
    CLASSIFY -->|other| ALLOW5["ALLOW"]
    CLASSIFY -->|test or source| GATE{"Phase rules"}
    GATE -->|Allowed| ALLOW6["ALLOW"]
    GATE -->|Blocked| BLOCK3["BLOCKED"]

    style BLOCK1 fill:#f44336,color:#fff
    style BLOCK2 fill:#f44336,color:#fff
    style BLOCK3 fill:#f44336,color:#fff
    style ALLOW1 fill:#4caf50,color:#fff
    style ALLOW3 fill:#4caf50,color:#fff
```

The most common path (non-write tools like Read/Grep) exits at the fast-path check before loading any config or state.

**Phase-specific rules:**

| Phase | Source files | Test files |
|---|---|---|
| spec / review / model | Blocked | Blocked |
| tdd-tests (RED) | Blocked (unless STUB:TDD) | Allowed |
| tdd-impl (GREEN) | Allowed | Allowed (logged) |
| tdd-qa / tdd-verify | Blocked | Blocked |
| done / verified / documented | Allowed | Allowed |
| audit | Allowed | Allowed |

The override mechanism (`workflow-advance.sh override "reason"`) grants 10 tool calls that bypass gating.

---

## 6. Data Flow

```mermaid
graph LR
    subgraph "Artifacts"
        WS["workflow-state-*.json<br>Phase, task, QA rounds"]
        QF["qa-findings-*.json<br>Findings + class fixes"]
        AT["audit-trail-*.jsonl<br>Every modification"]
        TL["token-log-*.json<br>Per-skill token usage"]
    end

    subgraph "Specs & Verification"
        SPEC["specs/*.md<br>Testable rules"]
        VR["verification/*-verification.md<br>Rule coverage matrix"]
    end

    subgraph "Config"
        CFG["workflow-config.json<br>Commands, patterns, intensity"]
    end

    SPEC -->|referenced by| WS
    WS -->|controls| GATE["workflow-gate.sh"]
    CFG -->|configures| GATE
    QF -->|verified by| VR
```

All workflow artifacts are branch-scoped — the branch slug is embedded in filenames. This allows concurrent workflows on different branches. `workflow-advance.sh reset` cleans up all branch-scoped artifacts.

| Artifact | Purpose | Created by |
|---|---|---|
| `workflow-state-{slug}.json` | Current phase, task, branch, QA rounds | `workflow-advance.sh` |
| `qa-findings-{slug}.json` | QA findings with instance + class fixes | `/ctdd` orchestrator |
| `audit-trail-{slug}.jsonl` | Every file modification with phase context | `audit-trail.sh` |
| `token-log-{slug}.json` | Per-skill token usage for `/cmetrics` | Each skill |
| `specs/{name}.md` | Testable rules (INV/PRH/BND) | `/cspec` |
| `verification/{name}-verification.md` | Rule coverage matrix | `/cverify` |
