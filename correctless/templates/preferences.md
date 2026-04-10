# Project Preferences

<!--
  This file codifies project-level judgment calls for the semi-auto pipeline (/cauto).
  Edit these preferences to control autonomous agent behavior.
  Protected by the sensitive-file-guard — manual edits only.
-->

## QA Finding Triage

<!-- Which severity levels to auto-fix vs surface to the human -->

- **Auto-fix**: CRITICAL, HIGH (default — the agent fixes these without asking)
- **Surface**: MEDIUM, LOW (default — reported in the PR summary for human review)

<!-- Recommended: keep the default. Override only if your project has specific triage rules. -->

## Documentation Scope

<!-- What documentation to include/exclude when /cdocs runs -->

- **Include**: README updates, AGENT_CONTEXT.md, ARCHITECTURE.md, feature docs, API docs
- **Exclude**: none (default — all standard documentation is updated)

<!-- Recommended: keep the default unless specific docs are maintained externally. -->

## Commit Granularity

<!-- How to structure commits during the implementation pipeline -->

- **Strategy**: one commit per skill phase (default)
  - TDD complete (after /ctdd)
  - Simplification (after /simplify, if accepted)
  - Verification artifacts (after /cverify)
  - Architecture docs (after /cupdate-arch)
  - Documentation (after /cdocs)

<!-- Recommended: keep the default for clean git history and easy bisect. -->

## Escalation Sensitivity

<!-- What constitutes an architectural decision requiring human input -->

- **Threshold**: default (escalate on any architectural decision)
  - New ABS-xxx or TB-xxx entries
  - Gate-blocked ARCHITECTURE.md writes
  - Spec contradictions
  - New dependencies
  - CLAUDE.md modifications

<!-- Recommended: keep the default. Lowering sensitivity risks silent architectural drift. -->

## PR Creation

<!-- How to create the pull request at the end of the pipeline -->

- **Mode**: `gh` (default — creates PR via `gh pr create`)
  - `gh` — create PR using GitHub CLI (requires `gh` installed)
  - `skip` — no PR created, just report completion
  - Custom command — specify a shell command to run (e.g., `my-pr-tool create`)

<!-- Recommended: use `gh` if GitHub CLI is available. Use `skip` for local-only workflows. -->
