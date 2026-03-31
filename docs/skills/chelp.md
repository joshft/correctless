# /chelp — Quick Help

> Show the workflow pipeline, all available commands, and a quick-reference cheat sheet.

## When to Use

- You are new to Correctless and want to see what commands are available.
- You need a quick reminder of the pipeline order or a specific command name.
- **Not for:** Diagnosing workflow state or problems (use `/cstatus`).

## How It Fits in the Workflow

This skill can be invoked at any time. It is a read-only reference card that detects whether you are in Lite or Full mode and shows the relevant commands.

## What It Does

- Detects the current mode (not set up / Lite / Full) from `.claude/workflow-config.json`.
- Prints the pipeline diagram for your mode.
- Lists all available commands grouped by category (feature workflow, standalone tools, Full-mode additions).
- Shows a quick-reference table mapping common tasks to commands.

## Example

```
User: /chelp

Correctless Lite — Workflow Pipeline:
  /cspec -> /creview -> /ctdd [RED -> test audit -> GREEN -> /simplify -> QA] -> /cverify -> /cdocs -> merge

Feature workflow:
  /cspec        Write a feature spec with testable rules
  /creview      Skeptical review + security checklist (~3 min)
  /ctdd         Enforced TDD: tests -> implement -> QA
  /cverify      Verify implementation matches spec
  /cdocs        Update documentation

Other:
  /crefactor    Structured refactoring (tests must pass before + after)
  /cpr-review   Review someone else's PR
  /ccontribute  Contribute to someone else's project
  /cmaintain    Review contributions as a maintainer
  /cdebug       Structured bug investigation
  /cstatus      Where am I? What's next?
  /csummary     What did the workflow catch this feature?
  /cmetrics     Project-wide health dashboard
  /cwtf         Audit the workflow — did agents follow instructions?

No active workflow. Start one: git checkout -b feature/my-feature then /cspec
```

## What It Reads / Writes

| Reads | Writes |
|-------|--------|
| `.claude/workflow-config.json` | Nothing (read-only) |
| `.claude/hooks/workflow-advance.sh` (status output) | |

## Lite vs Full

- **Lite mode**: Shows the Lite pipeline and Lite commands only.
- **Full mode**: Adds the Full pipeline diagram and Full-only commands (`/cmodel`, `/creview-spec`, `/caudit`, `/cupdate-arch`, `/cpostmortem`, `/cdevadv`, `/credteam`).
