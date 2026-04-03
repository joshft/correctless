# /cexplain — Guided Codebase Exploration

> Interactive codebase exploration using mermaid diagrams and prose walkthroughs. Scans the project, presents an overview, and lets you drill into what you care about. Export explored sections to a self-contained HTML document at any point.

## When to Use

- Onboarding onto an unfamiliar codebase and need a guided tour
- Want to understand how a request flows through the system
- Need a visual component dependency map for a design discussion
- Want to share an architecture overview with a teammate (HTML export)
- Quick exploration without running `/csetup` first — works out of the box

## How It Fits in the Workflow

`/cexplain` is an observability skill — it reads the codebase but never modifies it. It works at any point in the workflow and does not require `/csetup`. It benefits from Serena MCP when available (better symbol tracing), but falls back to grep-based analysis automatically.

## What It Does

1. **Mode selection** — asks terminal (default) or HTML output preference
2. **Project scan** — reads .correctless/AGENT_CONTEXT.md, .correctless/ARCHITECTURE.md, directory structure, and manifests
3. **30-second overview** — project name, language, LOC, purpose, 3-7 major components
4. **Exploration menu** — options driven by structural signals (HTTP routes, CLI entry points, cross-imports, etc.)
5. **Interactive drill-down** — mermaid diagrams + prose walkthroughs with follow-up options
6. **Confidence markers** — every answer distinguishes traced vs inferred connections
7. **HTML export** — self-contained HTML with rendered mermaid diagrams, table of contents, and disclaimer

## Example

```
Agent: How would you like to view exploration results?
       1. Terminal (default) — inline mermaid + prose
       2. HTML file — rendered diagrams in a shareable file

User: 1

Agent: Scanning project...

       ## Project Overview
       **Name:** my-api
       **Language:** TypeScript
       **LOC:** ~12,400
       **Purpose:** REST API for user management with JWT auth

       **Components:**
       1. `src/routes/` — Express route handlers (8 files)
       2. `src/middleware/` — Auth, validation, error handling (4 files)
       3. `src/models/` — Sequelize data models (6 files)
       4. `src/services/` — Business logic layer (5 files)
       5. `src/utils/` — Shared helpers (3 files)

       What would you like to explore?
       1. Request lifecycle — trace a request from entry to response
       2. Component dependency diagram
       3. Trust boundary map
       4. Deep dive into a specific component
       5. Export to HTML
       Or name a file, directory, or concept: ___

User: 1

Agent: [sequenceDiagram showing request flow]
       [2-5 paragraphs explaining the flow with file:line references]
       Confidence: Traced 5/6 connections. Middleware → Service connection inferred from naming.

       Follow-ups:
       1. Drill into the auth middleware?
       2. See the data model for User?
       3. Back to overview
       4. Export to HTML
```

## Lite vs Full

`/cexplain` works the same in both Lite and Full. When Serena MCP is available (Full mode with MCP configured), symbol tracing is more precise. Without Serena, the skill uses grep-based analysis.

## Common Issues

- **"Limited structure detected"**: The project has fewer than 2 identifiable components. Name a specific file or directory to explore, or describe what the project does.
- **Diagrams too complex**: The 30-node limit with subgraph grouping keeps diagrams readable. Ask to expand a specific group for details.
- **Serena unavailable**: The skill falls back silently to grep. A note appears at the end of the session. Results may be less precise.
