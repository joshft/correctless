# Spec: MCP Integration — Serena + Context7

## What

Add Serena (symbol-level code analysis) and Context7 (current library documentation) MCP server integration to all Correctless skills. `/csetup` detects, offers, and installs both servers. Every code-reading skill gains conditional Serena/Context7 usage with silent fallback to grep/read when unavailable. Dual motivation: analysis precision (call graph tracing that grep can't do) and token savings (40-60% reduction on code-heavy skills in larger projects).

## Rules

### Installation & Detection

- **R-001** [integration]: `/csetup` Step 2.5 checks for existing `.mcp.json` in the project root, installed `uv` and `npx` binaries, and whether Serena/Context7 are already configured. Detection checks for key *presence* in the `mcpServers` object, not key *value* — a user with a custom Serena config (different args, different repo) should not have it overwritten. If both are already present, setup skips the MCP offer and reports "Serena ✓ Context7 ✓ (already configured)" in the summary.

- **R-002** [integration]: `/csetup` presents MCP as a single decision with up to four options: "both", "just Serena", "just Context7", "skip". The offer appears between Step 2 (setup script) and Step 3 (config review). The offer only appears when at least one server is not yet configured AND the required tooling (`uv` for Serena, `npx` for Context7) is available. Before offering Serena, `/csetup` performs a usefulness check based on language support AND project size (20+ source files for strong recommendation, caveat for smaller projects or less common languages, skip entirely for `"other"`/non-code projects). When Serena is not useful, only Context7 is offered.

- **R-003** [integration]: If `uv` is not installed and the user wants Serena, `/csetup` prints installation instructions and does NOT attempt to install `uv` automatically. Same for `npx`/Node.js and Context7.

- **R-004** [integration]: When writing `.mcp.json` (in the project root), if the file already exists with other MCP server entries, `/csetup` merges the new entries into the existing `mcpServers` object. Existing entries are never overwritten or removed.

- **R-005** [integration]: `/csetup` creates `.serena.yml` with `project_name` set to the project name detected in Step 1 (from the manifest file, not from `workflow-config.json` which may not be confirmed yet), `read_only: false`, and `enable_memories: true`.

- **R-006** [integration]: `/csetup` adds `.serena/` to `.gitignore` if not already present.

- **R-007** [integration]: After writing configs, `/csetup` updates the existing `mcp` section in `workflow-config.json` (the template already includes `"mcp": {"serena": false, "context7": false}`) — sets the appropriate flags to `true` for installed servers. If the user skipped both, the flags remain `false`.

### Per-Skill Integration

- **R-008** [unit]: Every skill that reads code checks `workflow-config.json` field `mcp.serena` before attempting Serena tool calls. If the field is `false`, absent, or null, the skill uses grep/read immediately without attempting Serena tools.

- **R-009** [unit]: Every skill that does library research checks `workflow-config.json` field `mcp.context7` before attempting Context7 tool calls. If the field is `false`, absent, or null, the skill uses web search immediately.

- **R-010** [unit]: The Serena integration block in each skill specifies which Serena operations replace which text-based operations. Every Serena operation has an explicit fallback documented in the skill prompt. The fallback table is: `find_symbol` → grep for function/type name, `find_referencing_symbols` → grep for symbol name across source files, `get_symbols_overview` → read directory + read index files, `replace_symbol_body` → Edit tool, `search_for_pattern` → Grep tool.

- **R-011** [unit]: `/cspec` research subagent uses Context7's `resolve-library-id` + `get-library-docs` when Context7 is available, falling back to web search when unavailable.

- **R-012** [unit]: `/cverify` uses Serena's `find_referencing_symbols` to trace rule → test → implementation → entry point when available, producing a traced coverage matrix. Without Serena, it uses the existing grep-based approach.

- **R-013** [unit]: `/caudit` specialist agents (concurrency, error handling, resource lifecycle) use Serena to query domain-specific symbols instead of reading the entire codebase. Each specialist's Serena usage is scoped to its domain.

### Graceful Degradation

- **R-014** [unit]: If a Serena tool call fails (timeout, server error, language server crash), the skill falls back to the text-based equivalent silently. The skill does NOT abort, does NOT retry the failed Serena call, and does NOT warn the user mid-operation about the fallback.

- **R-015** [unit]: If Serena fails during a skill run, the skill notifies the user ONCE at the end of the skill's output: "Note: Serena was unavailable during this run — fell back to text-based analysis. If this persists, check that the Serena MCP server is running (`uvx serena-mcp-server`)." The notification does not interrupt the skill's workflow.

- **R-016** [unit]: Context7 failures follow the same pattern as R-014 and R-015: silent fallback to web search, single notification at end if failures occurred.

- **R-017** [unit]: No Correctless skill fails or produces an error because Serena or Context7 is unavailable. MCP servers are optimizers, not dependencies.

### Configuration & State

- **R-018** [unit]: The `mcp` section in `workflow-config.json` uses boolean values only: `{"serena": true, "context7": true}`. Skills read these as feature flags — no version numbers, no server URLs, no connection details.

- **R-019** [unit]: Templates `templates/workflow-config.json` and `templates/workflow-config-full.json` include `"mcp": {"serena": false, "context7": false}` as defaults so new installs have the flags present.

### Sync & Distribution

- **R-020** [integration]: After all skill files are modified, `bash sync.sh` produces 16 Lite skills and 23 Full skills with the MCP integration blocks. `bash test.sh` passes all 57 tests.

- **R-021** [integration]: Serena-specific skill instructions are present in BOTH Lite and Full distributions. Context7 instructions are present in BOTH distributions. MCP integration is not a Full-only feature.

### Skill Coverage

- **R-022** [unit]: The following 14 skills receive Serena integration blocks: `/cspec`, `/creview`, `/creview-spec`, `/ctdd`, `/cverify`, `/caudit`, `/crefactor`, `/credteam`, `/cwtf`, `/cmaintain`, `/ccontribute`, `/cdebug`, `/cpr-review`, `/cdocs`.

- **R-023** [unit]: The following 2 skills receive Context7 integration: `/cspec` (research subagent) and `/cdebug` (when researching library behavior during root cause analysis).

- **R-024** [unit]: Skills that don't read code (`/chelp`, `/cstatus`, `/csummary`, `/cmetrics`, `/cpostmortem`, `/cdevadv`, `/csetup`, `/cwtf`) do NOT receive MCP integration blocks — except `/cwtf` which needs Serena for call-graph-based thoroughness checking (already in R-022).

### Error Handling

- **R-025** [integration]: If `.mcp.json` exists but is not valid JSON, `/csetup` warns the user ("`.mcp.json` exists but isn't valid JSON — I won't modify it. Fix it manually or delete it and re-run `/csetup`.") and skips MCP config writing entirely. It does NOT overwrite or delete the corrupt file.

- **R-026** [unit]: When checking whether Serena/Context7 are "already configured" in `.mcp.json`, `/csetup` checks for the key's *presence* in the `mcpServers` object, not its *value*. A user with custom Serena args (different repo, different transport) should not have their config overwritten by the default.

## Won't Do

- **Token tracking in `/cmetrics`**: The design doc proposes tracking Serena token savings. This requires session-meta data that doesn't exist yet. Deferred to a future spec.
- **Serena verification during `/csetup`**: The design doc proposes running `timeout 30 uvx ...` to verify Serena works. This is fragile (first run downloads language servers, takes minutes). Instead, just write the config and note that first use may take a moment.
- **Automatic `uv`/`npx` installation**: System-level package installation is the user's responsibility.
- **`.serena.yml` `initial_prompt` field**: Serena's initial prompt is project-specific and shouldn't be templated by Correctless. Use defaults.

## Risks

- **`.mcp.json` merge logic** — JSON merge could corrupt existing configs if the file has unexpected structure. Mitigation: read with `jq`, validate it's an object with `mcpServers` key, merge at that level only. If the file isn't valid JSON or doesn't have the expected structure, warn and skip rather than overwrite.
- **Serena offered where not useful** — Serena supports 37 languages but provides little value on small projects or non-code projects (Markdown, config-only). Mitigation: `/csetup` performs a usefulness check (language + source file count) before offering. Projects with `"other"` language or <10 source files skip the Serena offer entirely.
- **Stale `mcp.serena` flag** — user removes Serena from `.mcp.json` but `workflow-config.json` still says `serena: true`. Skills will attempt Serena calls that fail. Mitigation: R-014/R-015 handle this — fallback is silent, notification at end.

## Open Questions

- None — the design doc is comprehensive and the brainstorm resolved scope questions.
