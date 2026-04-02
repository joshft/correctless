# Spec: Add /crelease Skill for Versioning and Changelog

## What

Add a `/crelease` skill that automates version bumping, changelog generation, and release tagging. It reads specs merged since the last tag to determine the version bump (major/minor/patch), generates a user-facing changelog from spec titles and rule summaries (not commit messages), updates the version file, and creates an annotated git tag. A pre-tag sanity check gates the release: all tests must pass, sync must be clean, no incomplete workflows on other branches. Both Lite and Full get it.

## Rules

- **R-001** [integration]: `/crelease` determines the version bump by reading all specs in `.correctless/specs/` that correspond to commits between the last git tag and HEAD. New features (specs with new rules) are minor bumps. Bug fixes (specs from `/cdebug` or `/cpostmortem`) are patch bumps. A spec is classified as a breaking change if its rules mention removing or renaming an existing public API, CLI flag, config field, or file path. The skill searches spec text for patterns: "breaking", "removes", "renames", "replaces {old} with {new}", "no longer supports". If any match, present to the user for confirmation: "This looks like a breaking change: {matched text}. Major bump?" Confirmed breaking changes are major bumps. If multiple specs exist, the highest bump wins (major > minor > patch). Commit messages are NOT used for bump classification — only specs. If no specs exist, fall through to R-010 (user classifies manually). After identifying specs, compare the spec count against the commit count since the last tag. If commits exist that don't map to any spec, warn: "{N} commits have no corresponding spec. Review the commit list to ensure the bump level accounts for all changes." Present the unmapped commits alongside the spec-determined bump.

- **R-002** [integration]: `/crelease` presents the determined version bump to the user for confirmation before proceeding. Format: current version, proposed version, bump reason, list of specs included. The user can override the bump level.

- **R-003** [integration]: `/crelease` generates a changelog entry from spec titles and rule summaries, not from commit messages. Entries are grouped by: Breaking Changes, New Features, Bug Fixes, Internal Improvements. Each entry references the spec slug. The generated entry is prepended to `CHANGELOG.md` under a new version heading with today's date.

- **R-004** [integration]: `/crelease` detects the project's version file location during setup. `/csetup` scans for version declarations in: `package.json` (`version` field), `Cargo.toml` (`[package] version`), `pyproject.toml` (`[project] version`), `setup.cfg` (`version`), Go version constants (`const Version =` or `var Version =`), and `CHANGELOG.md` heading (fallback: extract version from the most recent `## [x.y.z]` heading). The detected path and extraction method are stored in `.correctless/config/workflow-config.json` under `release.version_file` and `release.version_pattern`.

- **R-005** [integration]: `/crelease` updates the version in the detected version file. For JSON files (package.json), use `jq`. For TOML files, use `sed` with the stored pattern. For Go constants, use `sed`. For CHANGELOG.md-only projects, the new heading is the version update. After updating, the old version string must not appear in the version file (prevents partial updates). If `release.version_file` is null and the user hasn't provided a version file path, skip version file update and warn: "No version file configured. Run `/csetup` or provide the path. The changelog and tag will still be created."

- **R-006** [integration]: `/crelease` runs a sanity check before tagging. Blockers: (a) the configured test command must pass, (b) `sync.sh --check` must pass (if sync.sh exists), (c) no open BLOCKING QA findings in any `.correctless/artifacts/qa-findings-*.json`, (d) a tag with the proposed version must not already exist. Warnings (non-blocking): (e) if `.correctless/artifacts/workflow-state-*.json` files exist with phase other than `documented` on other branches, warn: "{N} active workflows on other branches. This release only includes main. Continue?" The user can proceed or abort. Each failed blocker produces a specific error identifying the check and how to fix it.

- **R-007** [integration]: `/crelease` creates an annotated git tag `v{version}` with the changelog entry as the tag message. The tag is created on the current commit.

- **R-008** [integration]: `/crelease` commits the changelog and version file changes before tagging. The commit message is `Release v{version}` with the changelog entry in the body.

- **R-009** [integration]: `/crelease` detects version badges in `README.md` (shields.io patterns like `badge/version-x.y.z`). If detected, it offers to update them — not automatic. Presents: "Found {N} version badges in README.md. Update to v{version}? (1) Yes (recommended), (2) No — I'll update manually." Only updates badges the user approves. Does not attempt to parse custom badge formats or non-shields.io services.

- **R-010** [integration]: When no specs exist between the last tag and HEAD, `/crelease` presents the list of commits and asks the user to classify the bump level. No automatic guessing from commit messages — the user decides. If the project uses conventional commits (detected from `workflow-config.json` or commit history), show the conventional-commit classification as a suggestion, but still require user confirmation. This handles commits that went through the workflow but whose specs were cleaned up, or commits that bypassed the workflow entirely.

- **R-011** [integration]: `/crelease` supports a `--dry-run` flag that shows what would happen (version bump, changelog entry, files modified, tag name) without making any changes. Presented as the default first option when the skill runs.

- **R-012** [integration]: The `/crelease` SKILL.md is added to `skills/crelease/SKILL.md`, registered in `sync.sh` for both Lite and Full distributions, documented in `docs/skills/crelease.md`, and added to the README skills table under "Core Workflow" or a new "Release" section.

- **R-013** [integration]: `/csetup` detects the version file during initial setup (Step 1 or Step 3) and stores `release.version_file` and `release.version_pattern` in `workflow-config.json`. If no version file is detected, the fields are set to `null` and `/crelease` asks the user on first run.

- **R-014** [unit]: The changelog entry format preserves the existing `CHANGELOG.md` style. Read the first `## ` heading in the existing CHANGELOG.md and extract the version/date pattern (e.g., `## [x.y.z] - YYYY-MM-DD`). Use the same pattern for the new entry. If the first heading doesn't match any recognized semver pattern, default to `## [x.y.z] - YYYY-MM-DD`. If no changelog exists, create one at the project root with the `## [x.y.z] - YYYY-MM-DD` format and a header: "# Changelog\n\nAll notable changes to this project are documented here. For previous history, see `git log`."

- **R-015** [integration]: After tagging, `/crelease` offers to push the tag and release commit: (a) push tag + commit (recommended), (b) push tag only, (c) don't push — I'll do it manually. If `gh` is available, also offer to create a GitHub release from the tag.

- **R-019** [unit]: If there are no commits between the last tag and HEAD, `/crelease` reports "No changes since v{last}. Nothing to release." and exits.

- **R-018** [integration]: If no git tags exist, `/crelease` asks the user for the initial version: "No prior release tags found. What version is this? (1) 0.1.0, (2) 1.0.0, (3) Enter manually." Then proceeds with changelog generation and tagging as normal.

- **R-017** [integration]: Before making any changes, `/crelease` checks for uncommitted changes (`git status --porcelain`). If the working tree is dirty, present: "You have uncommitted changes. Release commits should only contain version/changelog updates. (1) Stash changes and continue (recommended), (2) Continue anyway, (3) Abort — commit or stash manually first."

- **R-016** [unit]: `/crelease` logs token usage to `.correctless/artifacts/token-log-{slug}.json` with `skill: "crelease"`, `phase: "release"`, `agent_role: "release-agent"`, `total_tokens`, `duration_ms`, and `timestamp`. Appends to existing file or creates it.

## Won't Do

- Deploy anything — this skill versions and tags, it doesn't deploy
- Manage release branches — this is for projects using trunk-based or feature-branch workflows
- Pre-release versions (alpha, beta, rc) — can be added later if needed
- Monorepo per-package versioning — single version for the whole project
- Automatic release on merge — the user explicitly invokes `/crelease`

## Risks

- **Version file detection is fragile** — custom version file locations or formats won't be detected automatically. Mitigation: fallback to asking the user, store in config for future runs.
- **Changelog style mismatch** — generated changelog may not match project's preferred prose style. Mitigation: R-014 matches existing format; user reviews before commit.
- **Incomplete spec-to-commit mapping** — specs may not map cleanly to commits if multiple features were squash-merged. Mitigation: R-001 reads specs from the specs directory rather than trying to map to commits; R-010 handles the no-spec fallback.

## Open Questions

_(none)_
