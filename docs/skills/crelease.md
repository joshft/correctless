# /crelease — Version Bump, Changelog, and Release Tag

> Automate version bumping, changelog generation, and release tagging. Reads specs merged since the last tag to determine the bump level, generates a user-facing changelog, updates the version file, and creates an annotated git tag.

## When to Use

- After merging a feature branch (or set of branches) and you're ready to cut a release
- When you want a changelog entry generated from specs, not commit messages
- When you want sanity checks (tests pass, sync clean, no blocking QA) before tagging
- **Not for:** deploying, pre-release versions, or monorepo per-package versioning

## How It Fits in the Workflow

`/crelease` is the final step after features have gone through /cspec -> /creview -> /ctdd -> /cverify -> /cdocs. It reads the specs that were merged since the last git tag and uses them to determine the version bump and generate the changelog. It does not deploy.

## What It Does

1. **Dirty tree check** — warns if you have uncommitted changes, offers to stash
2. **Tag detection** — finds the last release tag, or asks for initial version if none exist
3. **Change detection** — checks for commits since the last tag, exits if none
4. **Dry-run option** — previews the release without making changes (offered first)
5. **Bump classification** — reads specs to determine major/minor/patch bump
6. **User confirmation** — shows current version, proposed version, and included specs
7. **Changelog generation** — creates entry grouped by Breaking Changes, New Features, Bug Fixes, Internal Improvements
8. **Version file update** — updates package.json, Cargo.toml, pyproject.toml, etc.
9. **Sanity checks** — tests pass, sync clean, no blocking QA, no tag collision
10. **Commit and tag** — commits changes, creates annotated tag
11. **Push offering** — offers to push tag/commit and optionally create GitHub release

## Example

```
Agent: Checking working tree... clean.
       Last tag: v1.2.0. Found 3 commits since then.

       Reading specs...
       - add-user-search (new feature) -> minor bump
       - fix-login-timeout (bug fix) -> patch bump
       Highest bump: minor -> v1.3.0

       Current version: 1.2.0
       Proposed version: 1.3.0
       Included specs: add-user-search, fix-login-timeout

       Confirm? (1) Yes (2) Override bump level

       Generating changelog entry...
       Updating package.json version...
       Running sanity checks... all passed.
       Committed: "Release v1.3.0"
       Created tag: v1.3.0

       Push? (1) Tag + commit (2) Tag only (3) Don't push
```

## Lite vs Full

`/crelease` works the same in both modes. It reads specs from `.correctless/specs/` regardless of mode.

## Common Issues

- **"No changes since last tag"**: There are no commits between the last tag and HEAD. Nothing to release.
- **"No version file configured"**: Run `/csetup` to detect the version file, or provide the path manually.
- **"Tests failed"**: Fix failing tests before releasing. The sanity check is a blocker.
- **"Tag already exists"**: A tag with the proposed version already exists. Choose a different version or delete the old tag.
