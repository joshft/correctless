# Workflow History

### 2026-04-02 — Consolidate artifacts into .correctless directory
Branch: feature/correctless-directory. Rules: 20. QA rounds: 3. Findings fixed: 5. Moved all Correctless-generated files from scattered locations (.claude/artifacts/, docs/specs/, root ARCHITECTURE.md) into a unified .correctless/ directory with auto-migration for existing installs.

### 2026-04-03 — Add calm reset prompts to orchestrators
Branch: feature/calm-resets. Rules: 11. QA rounds: 2. Findings fixed: 7. Added desperation-vector management to /ctdd and /caudit — conditional reset prompts fire at known spiral trigger points (3+ consecutive failures in GREEN/fix rounds, recurring BLOCKINGs across QA rounds, diverging finding counts in audit). Each reset redirects the agent to re-read source material and offers human escalation. One reset per trigger per phase, then mandatory escalation with /cdebug suggestion.

### 2026-04-02 — Add /crelease skill for versioning and changelog
Branch: feature/crelease-skill. Rules: 19. QA rounds: 2. Findings fixed: 7. Added /crelease skill that automates version bumping from specs (not commits), changelog generation grouped by type, sanity gate, annotated git tagging, and optional push/GitHub release. Setup now detects version files (package.json, Cargo.toml, pyproject.toml, setup.cfg, Go constants, CHANGELOG.md) with section-aware TOML parsing. Also fixed pre-existing Rust JSON escape bug and incorrect consolidation test assertion.

### 2026-04-02 — Add /cexplain skill for guided codebase exploration
Branch: feature/cexplain-skill. Rules: 19. QA rounds: 2. Findings fixed: 6. Added /cexplain skill for interactive codebase exploration using mermaid diagrams and prose walkthroughs. Signal-based exploration menus, uncertainty markers, HTML export (incremental/snapshot modes), Serena MCP integration with silent fallback, output mode selection (terminal/HTML), 30-node grouping, and no-setup operation. QA caught missing Serena integration registration and missing spec-verbatim instructions.
