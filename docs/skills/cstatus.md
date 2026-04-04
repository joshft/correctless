# /cstatus — Workflow Status and Next Steps

> Show the current Correctless workflow state, available commands, and what to do next.

## When to Use

- You are mid-feature and forgot which phase you are in or what comes next.
- You want to check if other branches have active workflows.
- You suspect the workflow is stalled or misconfigured.
- **Not for:** Getting a quick command reference (use `/chelp`), or generating a feature summary (use `/csummary`).

## How It Fits in the Workflow

This skill can be invoked at any point. It reads the current workflow state and tells you exactly where you are in the pipeline and what command to run next. It is purely diagnostic — it never modifies state.

## What It Does

- Verifies Correctless is configured in the project (checks for `workflow-config.json`, hooks, and `ARCHITECTURE.md`).
- Reads the current workflow phase and shows phase-specific guidance (e.g., "RED phase — writing tests. Source files are blocked.").
- Lists all available commands for the current mode (Lite or Full).
- **Detects problems proactively**:
  - **Stale workflows**: If a phase has been active for more than 24 hours, warns and suggests re-running the phase skill or using an override.
  - **Empty docs**: If `ARCHITECTURE.md` or `AGENT_CONTEXT.md` still contains placeholder markers (`{PROJECT_NAME}`), recommends running `/csetup`.
  - **Override abuse**: If 2 or more overrides have been used on the current workflow, suggests the config or file patterns may need adjustment.
- On request, runs a full health check: validates hooks, config JSON, script permissions, and document content.

## Example

```
User: /cstatus

Correctless Lite — active workflow on `feature/rate-limiting`

Phase: tdd-impl (GREEN)
Entered: 3 hours ago
Next: Make the tests pass. When done, advance with `workflow-advance.sh qa`.

Available commands:
  /ctdd           Resume TDD workflow
  /cstatus        This command
  /csummary       What has the workflow caught so far?
  /chelp          Quick command reference
  ...

No problems detected.
```

## What It Reads / Writes

| Reads | Writes |
|-------|--------|
| `.correctless/config/workflow-config.json` | Nothing (read-only) |
| `.claude/hooks/workflow-advance.sh` (status output) | |
| `ARCHITECTURE.md` | |
| `AGENT_CONTEXT.md` | |
| Workflow state file | |

## Lite vs Full

- **Lite mode**: Shows the Lite pipeline and Lite commands.
- **Full mode**: Also shows Full-only commands (`/cmodel`, `/creview-spec`, `/caudit`, `/cupdate-arch`, `/cpostmortem`, `/cdevadv`, `/credteam`) and Full-specific phases.

## Common Issues

- **"Correctless isn't configured"**: Run `/csetup` to initialize the project.
- **Stale workflow detected**: Usually means an agent crashed or the session ended mid-phase. Re-run the skill for the current phase (e.g., `/ctdd` for tdd-impl) to resume.
- **Multiple overrides**: The gate may be misconfigured for your file layout. Run `workflow-advance.sh diagnose "yourfile.ts"` to understand why files are being blocked.
