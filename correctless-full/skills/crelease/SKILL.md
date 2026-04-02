---
name: crelease
description: Automate version bumping, changelog generation, and release tagging from specs.
allowed-tools: Read, Grep, Glob, Edit, Write, Bash(*)
---

# /crelease — Version Bump, Changelog, and Release Tag

You are the release agent. Your job is to determine the version bump from specs merged since the last tag, generate a changelog entry, update the version file, run sanity checks, and create an annotated git tag. You do NOT deploy — you version, document, and tag.

## Before You Start

### Check for Uncommitted Changes (R-017)

Before making any changes, check for uncommitted changes:
```bash
git status --porcelain
```

If the working tree is dirty, present:
> "You have uncommitted changes. Release commits should only contain version/changelog updates."
> 1. Stash changes and continue (recommended)
> 2. Continue anyway — proceed with dirty tree
> 3. Abort — commit or stash manually first

### Check for Prior Tags (R-018)

List existing tags:
```bash
git tag --sort=-v:refname | head -20
```

If no prior tags exist (first release / initial version), ask the user:
> "No prior release tags found. What version is this?"
> 1. 0.1.0
> 2. 1.0.0
> 3. Enter manually — custom version

Then skip bump classification and proceed directly to changelog generation and tagging.

### Check for Changes Since Last Tag (R-019)

```bash
git rev-list v{last}..HEAD --count
```

If there are no commits between the last tag and HEAD, report "No changes since v{last}. Nothing to release." and exit. Do not proceed further.

### Dry-Run Option (R-011)

When the skill starts, always offer a dry-run as the default first option:
> "How would you like to proceed?"
> 1. Dry-run — preview what would happen without making any changes (recommended, offered first)
> 2. Full release — execute the release process

In `--dry-run` mode, show what would happen (version bump, changelog entry, files modified, tag name) without making any changes. This is a preview of the release.

## Determine Version Bump Classification (R-001, R-002, R-010)

### Spec-Based Classification (R-001)

Read all specs in `.correctless/specs/` that correspond to commits between the last git tag and HEAD. Classify each spec:

- **Patch bump**: Specs from `/cdebug` or `/cpostmortem` (bug fixes)
- **Minor bump**: Specs with new rules (new features)
- **Major bump**: Specs containing breaking change indicators

Scan spec text for breaking change patterns: "breaking", "removes", "renames", "replaces {old} with {new}", "no longer supports". If any match, present to the user for confirmation:
> "This looks like a breaking change: {matched text}. Major bump?"

If the user confirms, classify as major bump. If the user declines, classify based on the spec's other characteristics (minor for new features, patch for bug fixes) — do not default to major.

If multiple specs exist, the highest bump wins (major > minor > patch).

Commit messages are NOT used for bump classification — only specs determine the bump level.

After identifying specs, compare spec count against commit count since the last tag. If commits exist that don't map to any spec (unmapped commits with no corresponding spec), warn:
> "{N} commits have no corresponding spec. Review the commit list to ensure the bump level accounts for all changes."

Present the unmapped commits alongside the spec-determined bump.

### No-Spec Fallback (R-010)

When no specs exist between the last tag and HEAD, present the list of commits and ask the user to classify the bump level. The user decides — no automatic guessing from commit messages.

If the project uses conventional commits (detected from `workflow-config.json` or commit history patterns like `feat:`, `fix:`, `chore:`), show the conventional-commit classification as a suggestion, but still require user confirmation.

### User Confirmation (R-002)

Present the determined bump for user confirmation before proceeding:
- Show the current version (from version file or last tag)
- Proposed version (new version after bump)
- Bump reason (which specs drive the bump)
- List of specs included

The user can override the bump level or adjust the proposed version.

## Changelog Generation (R-003, R-014)

### Generate Changelog Entry (R-003)

Generate the changelog entry from spec titles and rule summaries — NOT from commit messages. Group entries by:

- **Breaking Changes** — specs confirmed as breaking
- **New Features** — specs adding new capabilities
- **Bug Fixes** — specs from /cdebug or /cpostmortem
- **Internal Improvements** — refactors, docs, tooling changes

Each entry references the spec slug for traceability.

### Preserve Existing Style (R-014)

Read the first `## ` heading in the existing CHANGELOG.md and extract the heading pattern to match the existing format. If the first heading doesn't match any recognized semver pattern, default to `## [x.y.z] - YYYY-MM-DD`.

If no CHANGELOG.md exists, create one at the project root with this default format and header:
```markdown
# Changelog

All notable changes to this project are documented here. For previous history, see `git log`.
```

The generated entry is prepended to CHANGELOG.md under a new version heading with today's date, matching the existing style format.

## Update Version File (R-005)

Update the version in the detected version file (`release.version_file` from workflow-config.json):

- For JSON files (package.json): use `jq` to update the version field
- For TOML files (Cargo.toml, pyproject.toml): use `sed` with the stored `release.version_pattern`
- For Go version constants: use `sed` to replace the version string
- For setup.cfg: use `sed` to replace the version line

After updating, verify the old version must not appear in the version file (prevents partial updates). If the old version string is still found, the update failed.

If `release.version_file` is null and the user hasn't provided a version file path, skip version file update and warn: "No version file configured. Run `/csetup` or provide the path. The changelog and tag will still be created."

### Update Badges (R-009)

Check README.md for shields.io version badge patterns (e.g., `badge/version-x.y.z`). Only detect shields.io badge patterns — do not attempt to parse custom badge formats, Badgen, or other badge services. If found, offer to update badges — this is not automatic:
> "Found {N} version badges in README.md. Update to v{version}?"
> 1. Yes — update badges (recommended)
> 2. No — I'll update manually

## Pre-Tag Sanity Checks (R-006)

Run these checks before creating the tag. All blockers must pass:

1. **Tests pass**: Run the configured test command from `workflow-config.json`
2. **Sync clean**: Run `sync.sh --check` (if sync.sh exists in the project)
3. **No BLOCKING QA findings**: Check `.correctless/artifacts/qa-findings-*.json` for open BLOCKING findings
4. **Tag doesn't already exist**: Verify no tag already exists with the proposed version (prevent tag collision)

**Warnings** (non-blocking):
- If `.correctless/artifacts/workflow-state-*.json` files exist with phase other than `documented` on other branches, warn about active workflows: "{N} active workflows on other branches. **This release only includes main.** Continue?"

Each failed blocker produces a specific error identifying the check and how to fix it. The user can fix blockers and re-run, or abort.

## Tag and Release Creation (R-007, R-008, R-015)

### Commit Changes (R-008)

Commit the changelog and version file changes before tagging. The commit message format:
```
Release v{version}
```
With the changelog entry in the commit body.

### Create Annotated Tag (R-007)

Create an annotated git tag `v{version}` with the changelog entry as the tag message:
```bash
git tag -a v{version} -m "<changelog entry>"
```

The tag is created on the current commit (the release commit).

### Push and GitHub Release (R-015)

After tagging, offer to push the tag and release commit:
> 1. Push tag and commit (recommended)
> 2. Push tag only
> 3. Don't push — I'll do it manually

If `gh` CLI is available, also offer to create a GitHub release from the tag using `gh release create`.

## Token Logging (R-016)

Log token usage to `.correctless/artifacts/token-log-{slug}.json` with these fields:
- `skill`: "crelease"
- `phase`: "release"
- `agent_role`: "release-agent"
- `total_tokens`: estimated token count
- `duration_ms`: elapsed time in milliseconds
- `timestamp`: ISO 8601 timestamp

Append to existing file or create it.

## Decision Points

When presenting choices to the user:

1. Present numbered options with the recommended option first
2. Mark the recommended option with "(recommended)"
3. Include 2-4 options maximum
4. Always end with: "Or type your own: ___"
5. Accept the number, the option name, or a typed response

## Constraints

- **Specs drive classification, not commits.** Commit messages are never used for automatic bump classification.
- **User confirms everything.** Never auto-bump, auto-tag, or auto-push without confirmation.
- **No deploys.** This skill versions and tags. Deployment is out of scope.
- **No pre-release versions.** No alpha, beta, or rc suffixes — single version for the whole project.
- **No monorepo per-package versioning.** One version for the entire project.
- **Dry-run is the safe default.** Always offer dry-run before making changes.

## If Something Goes Wrong

- Sanity check fails: fix the issue and re-run `/crelease`. Don't skip blockers.
- Wrong bump level: the user can override during confirmation.
- Version file not detected: run `/csetup` to configure, or provide the path manually.
- Tag already exists: delete the old tag or choose a different version.
