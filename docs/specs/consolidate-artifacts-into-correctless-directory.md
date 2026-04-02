# Spec: Consolidate Artifacts into .correctless Directory

## What

Move all Correctless-generated files into a single `.correctless/` directory. Currently artifacts are scattered across `.claude/artifacts/`, `.claude/workflow-config.json`, `.claude/antipatterns.md`, `.claude/meta/`, `docs/specs/`, `docs/decisions/`, `docs/verification/`, root-level `ARCHITECTURE.md`, and root-level `AGENT_CONTEXT.md`. The `.claude/` directory belongs to Claude Code; `docs/` belongs to the project. `.correctless/` becomes Correctless's own namespace with a fixed internal structure. The `paths` config section is removed — all paths are derived from the `.correctless/` root. Setup asks about gitignoring (recommends no). Existing installs get a one-time migration.

Target structure:

```
.correctless/
  config/
    workflow-config.json
  hooks/
    workflow-gate.sh
    workflow-advance.sh
    audit-trail.sh
    statusline.sh
  artifacts/
    workflow-state-{slug}.json
    qa-findings-{slug}.json
    tdd-test-edits.log
    token-log-{slug}.json
    audit-trail-{slug}.jsonl
    checkpoint-{skill}-{slug}.json
    research/
  specs/
    {slug}.md
  decisions/
    DECISIONS.md
  verification/
    {slug}-verification.md
  meta/                              (Full mode only)
    drift-debt.json
    workflow-effectiveness.json
    external-review-history.json
  antipatterns.md
  workflow-history.md
  learnings/
  ARCHITECTURE.md
  AGENT_CONTEXT.md
```

## Rules

- **R-001** [integration]: `setup` creates the `.correctless/` directory structure: `config/`, `hooks/`, `artifacts/`, `artifacts/research/`, `specs/`, `decisions/`, `verification/`, `learnings/`. Full mode additionally creates `meta/`.

- **R-002** [integration]: `setup` defaults to NOT adding `.correctless/` to `.gitignore`. The `/csetup` skill asks the user whether to gitignore `.correctless/` using structured decision format (numbered options with recommended default). If the user chooses yes, `/csetup` adds `.correctless/` to `.gitignore`.

- **R-003** [integration]: `workflow-config.json` is generated at `.correctless/config/workflow-config.json`. The `paths` section is removed from the config schema entirely — not generated for any language. This includes the template files `templates/workflow-config.json` and `templates/workflow-config-full.json`.

- **R-004** [integration]: `ARCHITECTURE.md` and `AGENT_CONTEXT.md` are created at `.correctless/ARCHITECTURE.md` and `.correctless/AGENT_CONTEXT.md` instead of project root.

- **R-005** [integration]: `antipatterns.md` is created at `.correctless/antipatterns.md` instead of `.claude/antipatterns.md`.

- **R-006** [integration]: All four hooks (`workflow-advance.sh`, `workflow-gate.sh`, `audit-trail.sh`, `statusline.sh`) read config from `.correctless/config/workflow-config.json` and read/write artifacts in `.correctless/artifacts/`.

- **R-007** [integration]: `workflow-advance.sh` writes spec files to `.correctless/specs/{slug}.md` and verification reports to `.correctless/verification/{slug}-verification.md`.

- **R-008** [integration]: All SKILL.md files reference `.correctless/` paths: specs at `.correctless/specs/`, config at `.correctless/config/workflow-config.json`, artifacts at `.correctless/artifacts/`, antipatterns at `.correctless/antipatterns.md`, architecture at `.correctless/ARCHITECTURE.md`, agent context at `.correctless/AGENT_CONTEXT.md`.

- **R-009** [integration]: `CLAUDE.md` section written by setup says "Read .correctless/AGENT_CONTEXT.md before starting any work" instead of "Read AGENT_CONTEXT.md".

- **R-010** [integration]: When `setup` detects existing artifacts in old locations, it moves them to corresponding `.correctless/` locations. Migration map:
  - `.claude/workflow-config.json` -> `.correctless/config/workflow-config.json`
  - `.claude/artifacts/*` -> `.correctless/artifacts/*`
  - `.claude/antipatterns.md` -> `.correctless/antipatterns.md`
  - `.claude/meta/*` -> `.correctless/meta/*`
  - `docs/specs/*` -> `.correctless/specs/*`
  - `docs/verification/*` -> `.correctless/verification/*`
  - `docs/decisions/*` -> `.correctless/decisions/*`
  - `ARCHITECTURE.md` (root) -> `.correctless/ARCHITECTURE.md` (only if file contains Correctless markers — template placeholders like `{PROJECT_NAME}` or Correctless-generated headers; pre-existing files without markers are left in place and fresh copies are created in `.correctless/`)
  - `AGENT_CONTEXT.md` (root) -> `.correctless/AGENT_CONTEXT.md` (same conditional logic as ARCHITECTURE.md)
  - `.claude/hooks/workflow-gate.sh` -> `.correctless/hooks/workflow-gate.sh`
  - `.claude/hooks/workflow-advance.sh` -> `.correctless/hooks/workflow-advance.sh`
  - `.claude/hooks/audit-trail.sh` -> `.correctless/hooks/audit-trail.sh`
  - `.claude/hooks/statusline.sh` -> `.correctless/hooks/statusline.sh`
  File contents are preserved exactly.

- **R-011** [integration]: Migration is idempotent — running setup when artifacts already exist in `.correctless/` does not duplicate, overwrite, or corrupt files. The `create_if_missing` pattern already used by setup applies.

- **R-012** [integration]: After migration, old directories that are now empty are removed. Directories with non-Correctless content (e.g., `docs/` with other files) are left alone.

- **R-013** [integration]: `.gitignore` entries for old paths (`.claude/artifacts/`) are cleaned up. If user chose to gitignore, `.correctless/` is added. Old `.claude/artifacts/` entries are removed since that directory is no longer used by Correctless.

- **R-014** [integration]: `workflow-config.json` migration strips the `paths` section from existing configs during migration (the field is no longer recognized).

- **R-015** [integration]: `sync.sh` propagates all path changes to both distribution targets. After sync, no file in `correctless-lite/` or `correctless-full/` contains references to `.claude/artifacts`, `.claude/workflow-config`, `.claude/antipatterns`, `docs/specs/`, `docs/verification/`, or `docs/decisions/` as Correctless artifact paths.

- **R-016** [integration]: All existing tests pass with updated path assertions. Tests that create/check `.claude/artifacts/` now create/check `.correctless/artifacts/`.

- **R-017** [integration]: `setup` installs hooks to `.correctless/hooks/` instead of `.claude/hooks/`. The `.claude/settings.json` hook paths reference `.correctless/hooks/workflow-gate.sh`, `.correctless/hooks/audit-trail.sh`, `.correctless/hooks/statusline.sh`. The permissions entry references `.correctless/hooks/workflow-advance.sh`.

- **R-018** [integration]: Migration moves existing hooks from `.claude/hooks/` to `.correctless/hooks/` and updates `.claude/settings.json` to reference the new paths. Old `.claude/hooks/` entries for Correctless hooks (workflow-gate, workflow-advance, audit-trail, statusline) are replaced; non-Correctless hooks in `.claude/hooks/` are left untouched.

- **R-019** [integration]: All SKILL.md files that invoke hooks as commands (e.g., `.claude/hooks/workflow-advance.sh status`) update to `.correctless/hooks/workflow-advance.sh`. After sync, no SKILL.md in source or distributions invokes hooks from `.claude/hooks/`.

- **R-020** [integration]: Project documentation (`correctless.md`, `correctless-lite.md`, `README.md`, `CONTRIBUTING.md`, `templates/AGENT_CONTEXT.md`) updates all path references and directory structure diagrams to use the `.correctless/` layout.

## Won't Do

- Move `.claude/settings.json` — that's Claude Code's own config file
- Change skill behavior — only path references change
- Provide a rollback mechanism — migration is one-way, and setup already shows what it does
- Move `docs/skills/` — those are project documentation for Correctless itself, not generated artifacts

## Risks

- **Breaking existing users** — anyone with Correctless installed has artifacts in old locations. Mitigation: `setup` detects and migrates automatically, one-time.
- **Stale SKILL.md references** — with ~50 SKILL.md copies across source + distributions, a missed path reference breaks a skill. Mitigation: R-015 enforces grep-verification that no old paths remain after sync.
- **Root ARCHITECTURE.md / AGENT_CONTEXT.md confusion** — users may have committed these files and reference them from other tools. Mitigation: migration moves them; CLAUDE.md is updated to point to new location. If a project has a pre-existing ARCHITECTURE.md that predates Correctless, migration should only move it if it contains Correctless markers (template placeholders or Correctless-specific sections).

## Open Questions

_(none — all resolved during brainstorm)_
