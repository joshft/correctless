# Spec: Stale Hook Detection — Detect Installed Hook Drift Before It Causes Silent Failures

## Metadata
- **Task**: stale-hook-detection
- **Recommended-intensity**: high
- **Intensity**: high
- **Intensity reason**: file path signal (hooks/, setup); keyword signal (security — stale gate hooks degrade fail-closed posture); antipattern signal (AP-023 directly motivated by stale hook that required routine overrides)
- **Override**: none

## What

Detect when installed hooks (`.correctless/hooks/`) and scripts (`.correctless/scripts/`) drift from their source. The gate bug in PR #63 (spec edits blocked during review) went undetected because the installed hook was stale — the source was fixed but `setup` hadn't been re-run. This feature makes that class of silent failure loud by writing an install manifest with checksums and checking it at pipeline startup and status display — including source-ahead-of-install detection when the source directory is accessible.

## Rules

- **R-001** [integration]: The `setup` script writes `.correctless/.install-manifest.json` after installing hooks and scripts (at the end of `install_hooks()`, after both hooks and scripts are copied). Setup sources `$SCRIPT_DIR/scripts/lib.sh` (the source-tree copy, not the installed copy) to access `sha256_hash_file`. The manifest contains: `{"installed_at": "{ISO timestamp}", "source_dir": "{abs path to $SCRIPT_DIR}", "files": {"hooks/workflow-gate.sh": {"installed_hash": "{sha256}", "source_hash": "{sha256}"}, "scripts/lib.sh": {"installed_hash": "{sha256}", "source_hash": "{sha256}"}, ...}}`. `source_dir` is the absolute path to `$SCRIPT_DIR` (the common parent of `hooks/` and `scripts/`). Relative paths in the `files` object include the subdirectory prefix (`hooks/` or `scripts/`), resolved relative to `source_dir` for source files and relative to `.correctless/` for installed files. The file set is generated dynamically by scanning `.correctless/hooks/*.sh` and `.correctless/scripts/*.sh` after installation — not a hardcoded list. Only files `setup` copies to `.correctless/hooks/` and `.correctless/scripts/` are tracked; source-tree scripts not installed to user projects (e.g., `scripts/auto-policy.sh`) are excluded. `source_hash` is the hash of the source file at install time; `installed_hash` is the hash of the installed copy — at install time these should be identical. The manifest is written atomically (write to `.install-manifest.json.$$`, then `mv`). If `sha256_hash_file` fails for any file, setup aborts manifest generation with an error message — a partial manifest is never written. If the manifest already exists, it is overwritten. Prerequisite: add ABS-022 to ARCHITECTURE.md documenting the install manifest contract (sole writer: `setup`, readers: `check_install_freshness`, lifecycle: per-install local state, gitignored, overwritten each setup run).
- **R-002** [unit]: A new function `check_install_freshness` in `scripts/lib.sh` reads `.correctless/.install-manifest.json` and performs two checks: (a) **install-vs-manifest**: re-checksums each installed file (at `.correctless/{relative_path}`) and compares against its `installed_hash` in the manifest, and (b) **source-ahead-of-install**: if `source_dir` from the manifest exists and is a valid directory, re-checksums each source file (at `{source_dir}/{relative_path}`) and compares against its `source_hash` in the manifest. Additionally, scans `.correctless/hooks/*.sh` and `.correctless/scripts/*.sh` for files not in the manifest. The function outputs one line per file as `status:relative/path` to stdout: `ok` (both checks pass), `modified` (installed file differs from `installed_hash`), `missing` (file in manifest but not on disk), `source_ahead` (source file differs from `source_hash` — source changed since last setup), `new_file` (file on disk but not in manifest). If the manifest doesn't exist, outputs a single line `no_manifest`. If `source_dir` doesn't exist or isn't a valid directory, the source-ahead check is skipped silently — only install-vs-manifest runs, and `source_dir` MUST NOT produce `source_ahead` statuses in that case.
- **R-003** [integration]: `/cauto` invokes `check_install_freshness` at pipeline startup (after the phase gate, before invoking any skill). Warnings by status, in order of severity: `source_ahead` — "WARNING: {N} source file(s) changed since last setup: {list}. Installed hooks are STALE. Run `setup` to update — you are running outdated hooks that may not include recent fixes." This is the strongest warning (PR #63 failure class). `modified` — "WARNING: {N} installed file(s) differ from their install-time checksums: {list}. Run `setup` to re-install, or ignore if intentionally modified." `missing` — "WARNING: {N} installed file(s) are missing: {list}. Run `setup` to re-install." `new_file` — "WARNING: {N} file(s) in installed directories not in manifest: {list}. These were added after setup." `no_manifest` — "Install manifest not found — run `setup` to enable stale-hook detection." All warnings are advisory, not blocking — the pipeline proceeds. Staleness is logged to the audit trail as `{"type": "install_staleness_detected", "timestamp": "...", "skill": "orchestrator", "affected_files": [...], "statuses": {...}}`. If all files are `ok`, no output.
- **R-004** [unit]: `/cstatus` includes install freshness as a status line. If all files are `ok`: "Install: current". If any have `source_ahead`: "Install: STALE — {N} source files changed since last setup (run setup)". If any have `modified` or `missing` (without `source_ahead`): "Install: STALE ({N} files differ — run setup)". If `no_manifest`: "Install: unknown (no manifest — run setup)". This is a single line in the existing `/cstatus` output, not a separate section.
- **R-005** [unit]: The install manifest `.correctless/.install-manifest.json` is gitignored. It is per-install local state, not shared truth — shared truth lives in the source files. Add `.correctless/.install-manifest.json` to `.gitignore` if not already covered by an existing pattern.

## Won't Do

- **Auto-update installed hooks** — detection only, not remediation. Running `setup` is the fix. Auto-updating hooks without explicit user action could overwrite intentional modifications.
- **Blocking on staleness** — all warnings are advisory. `source_ahead` gets the strongest wording but doesn't block. Blocking would prevent work during active development cycles where hooks are being edited. The warning is prominent enough to be noticed; the user decides whether to act.
- **Checksumming non-installed files** — only files that `setup` installs are tracked. Templates, helpers, skill files, and other distribution content are not installed to user projects and don't need staleness detection.
- **Ignore list for intentional modifications** — a future feature if intentional-modification warnings become common friction.
- **Symlink validation on `source_dir`** — `source_dir` is advisory (used for detection, never for remediation or auto-update). Symlink attacks against `source_dir` could produce false `ok` results, but the blast radius is limited to missing a `source_ahead` warning — install-vs-manifest still detects post-install modification.

## Risks

- **User intentionally modifies an installed hook and gets warned every run**: A user who customizes `.correctless/hooks/workflow-gate.sh` will see the "modified" warning on every `/cauto` run and `/cstatus` check.
  1. Accept (recommended) — advisory, not blocking. If common friction, add an ignore list in a follow-up.

- **`source_dir` path becomes invalid**: Plugin directory moves, `source_dir` points to non-existent path. Source-ahead check silently skips. Install-vs-manifest still works.
  1. Accept (recommended) — graceful degradation. Source-ahead is a bonus when available.

- **Setup overhead**: Checksumming ~9 files adds ~10ms. Negligible.
  1. Accept.

## Open Questions

- ~~**OQ-001**~~: Resolved — manifest-based approach with dynamic file scanning handles all three scenarios.
- ~~**OQ-002**~~: Resolved — `/cauto` (strong warning) + `/cstatus` (advisory line).
- ~~**OQ-003**~~: Resolved — R-002 covers source-ahead-of-install. Closes the PR #63 motivating case.
- ~~**OQ-004**~~: Resolved — gitignore the manifest.
- ~~**OQ-005**~~: Resolved — `source_dir` is `$SCRIPT_DIR`, relative paths include `hooks/`/`scripts/` prefix.
