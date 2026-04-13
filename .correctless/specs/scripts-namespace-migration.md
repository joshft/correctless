# Spec: Scripts Namespace Migration — Move Installed Scripts Under .correctless/

## Metadata
- **Task**: scripts-namespace-migration
- **Recommended-intensity**: standard
- **Intensity**: high
- **Intensity reason**: project floor (workflow.intensity=high); no security signals triggered
- **Override**: none

## What

Move the two scripts Correctless installs into user projects (`lib.sh` and `antipattern-scan.sh`) from `scripts/` to `.correctless/scripts/`. This eliminates the only top-level namespace collision Correctless creates in user projects — hooks are already at `.correctless/hooks/`, and templates/helpers are not installed. The hooks' primary path resolution (`../scripts/` relative to `.correctless/hooks/`) already resolves to `.correctless/scripts/` — only the install target and fallback paths need updating.

## Rules

- **R-001** [unit]: The `setup` script's `install_hooks()` function installs `lib.sh` and `antipattern-scan.sh` to `$REPO_ROOT/.correctless/scripts/` instead of `$REPO_ROOT/scripts/`. The `mkdir -p` target changes from `$REPO_ROOT/scripts` to `$REPO_ROOT/.correctless/scripts`. No other scripts are installed — only these two.
- **R-002** [integration]: On upgrade (existing install with files at `scripts/lib.sh` and/or `scripts/antipattern-scan.sh`), the `setup` script detects the old layout and migrates: moves the two files to `.correctless/scripts/`, then prints a message: "Migrated scripts/lib.sh and scripts/antipattern-scan.sh to .correctless/scripts/. If scripts/ contains only Correctless files, you can safely delete it." The setup script must NOT delete the `scripts/` directory — the user may have their own files there. The migration runs before hook installation so hooks can find `lib.sh` at the new path.
- **R-003** [unit]: All hook fallback paths that reference `$REPO_ROOT/scripts/lib.sh` or bare `scripts/lib.sh` are updated to `$REPO_ROOT/.correctless/scripts/lib.sh` or `.correctless/scripts/lib.sh`. Affected hooks: `workflow-advance.sh`, `workflow-gate.sh`, `sensitive-file-guard.sh`, `audit-trail.sh`, `statusline.sh`, `token-tracking.sh`. The primary resolution path (`$(dirname "${BASH_SOURCE[0]}")/../scripts`) remains unchanged — it already resolves correctly to `.correctless/scripts/` since hooks are installed at `.correctless/hooks/`. The `shellcheck source=` directives remain `../scripts/lib.sh` (relative, unchanged).
- **R-004** [unit]: Skill files that reference `scripts/antipattern-scan.sh` as a command to execute are updated to `.correctless/scripts/antipattern-scan.sh`. Affected skills: `skills/cverify/SKILL.md` (antipattern scan invocation). The `antipattern-scan.sh` script's own usage comment is updated.
- **R-005** [unit]: `sync.sh` continues to sync source `scripts/*.sh` to `correctless/scripts/*.sh` (the distribution directory). No change to the distribution layout — `correctless/scripts/` is the distribution source, `.correctless/scripts/` is the installed target. These are different directories serving different purposes.
- **R-006** [integration]: The test suite passes after migration. Tests that reference `scripts/antipattern-scan.sh` or `scripts/lib.sh` as installed paths (not source paths) are updated to `.correctless/scripts/`. Tests that reference source-tree paths (e.g., `$REPO_DIR/scripts/antipattern-scan.sh` where `REPO_DIR` is the Correctless source tree) remain unchanged — the source tree layout is not modified.
- **R-007** [unit]: Documentation references to installed script paths are updated: README.md, AGENT_CONTEXT.md, CONTRIBUTING.md, and any feature docs that mention `scripts/lib.sh` or `scripts/antipattern-scan.sh` as user-project paths. References to the source-tree `scripts/` directory (in AGENT_CONTEXT.md's component table, ARCHITECTURE.md's pattern descriptions) remain unchanged — they describe the development layout, not the installed layout.

## Won't Do

- **Source tree restructuring** — the development `scripts/`, `hooks/`, `helpers/`, `templates/` directories stay at the repo root. They're development organization, not user-facing namespace. Restructuring is a separate concern with its own cost/benefit.
- **Distribution directory changes** — `correctless/scripts/` stays as-is. It's the marketplace distribution source, not an installed path.
- **Auto-deleting `scripts/` on upgrade** — the user's project may have their own scripts there. Print a message; don't delete.
- **Migration of other directories** — `hooks/` is already at `.correctless/hooks/`. `templates/` and `helpers/` are not installed. Nothing else needs moving.

## Risks

- **Test references to source-tree vs installed paths**: Tests use `$REPO_DIR/scripts/antipattern-scan.sh` where `REPO_DIR` is the Correctless source tree. These are source-tree references and should NOT be updated. The distinction between "source tree `scripts/`" and "installed `.correctless/scripts/`" must be clear during implementation. Misidentifying a source-tree reference as an installed reference breaks tests.
  1. Accept (recommended) — the distinction is mechanical: references using `$REPO_DIR` or paths relative to the test file's location are source-tree. References in setup, hooks, and skills that describe where files live in user projects are installed paths. The test suite is the verification.

- **Existing user installs break if they don't run setup**: If a user pulls the update but doesn't run `setup`, their hooks' fallback paths point to `.correctless/scripts/lib.sh` which doesn't exist yet (setup hasn't moved the files). The primary path (`../scripts/lib.sh`) still resolves to the old `scripts/lib.sh` location. Hooks continue working via the primary path — the fallback never fires. The first `setup` run after the update performs the migration.
  1. Accept (recommended) — hooks work via primary path regardless. Migration happens on next setup run. No silent breakage.

## Open Questions

- ~~**OQ-001**~~: Resolved — hooks are already at `.correctless/hooks/`, templates/helpers are not installed. Only `scripts/` collides.
