
## Correctless Lite

This project uses Correctless Lite for structured development.
Read .correctless/AGENT_CONTEXT.md before starting any work.
Available commands: /csetup, /cspec, /creview, /ctdd, /cverify, /cdocs, /crefactor, /cpr-review, /cstatus, /csummary, /cmetrics, /cdebug, /chelp

## GitHub Operations

Use `gh` for GitHub operations (PRs, issues, checks).

## Commit Messages

Imperative mood, capitalized, no conventional commits prefix. Explain *why* when non-obvious.
Examples: "Add mermaid diagrams to README for visual comprehension", "Fix shellcheck directive placement — must be before first statement"

## Correctless Learnings

### 2026-04-02 — Convention confirmed: Serena MCP silent fallback
- Observed in 5+ features — treat as established project convention
- Every skill with Serena integration must: (1) check `mcp.serena` config flag, (2) include the standard 6-tool fallback table, (3) state "optimizer, not a dependency", (4) fall back silently (no abort, no retry, no mid-operation warnings), (5) notify once at session end if unavailable
- Source: /cdocs after add-cexplain-skill-for-guided-codebase-exploration
