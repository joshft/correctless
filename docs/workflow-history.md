# Workflow History

### 2026-04-02 — Consolidate artifacts into .correctless directory
Branch: feature/correctless-directory. Rules: 20. QA rounds: 3. Findings fixed: 5. Moved all Correctless-generated files from scattered locations (.claude/artifacts/, docs/specs/, root ARCHITECTURE.md) into a unified .correctless/ directory with auto-migration for existing installs.

### 2026-04-02 — Add /crelease skill for versioning and changelog
Branch: feature/crelease-skill. Rules: 19. QA rounds: 2. Findings fixed: 7. Added /crelease skill that automates version bumping from specs (not commits), changelog generation grouped by type, sanity gate, annotated git tagging, and optional push/GitHub release. Setup now detects version files (package.json, Cargo.toml, pyproject.toml, setup.cfg, Go constants, CHANGELOG.md) with section-aware TOML parsing. Also fixed pre-existing Rust JSON escape bug and incorrect consolidation test assertion.
