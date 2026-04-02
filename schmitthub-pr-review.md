# PR #12 Review: Add /crelease skill for versioning and changelog

**4 agents reviewed**: code quality, test coverage, error handling, documentation accuracy.

---

## Critical Issues (3)

### 1. SKILL.md uses bare `workflow-config.json` path
**`skills/crelease/SKILL.md:86,126,148`**

Every other skill uses `.correctless/config/workflow-config.json`. An AI agent executing `/crelease` will look at the repo root instead of `.correctless/config/`. The spec has the same bare reference, but SKILL.md is what agents actually execute.

### 2. Silent skip when `jq` unavailable
**`setup:570`**

`detect_version_file()` does `command -v jq || return 0` — returns success with no warning. User sees setup complete normally, then `/crelease` says "No version file configured. Run /csetup." Re-running setup produces the same result — infinite loop with no diagnostic.

```bash
# suggested fix
if ! command -v jq >/dev/null 2>&1; then
  warn "jq not found — skipping version file detection (install jq for /crelease support)"
  return 0
fi
```

### 3. TOML grep fails on indented files
**`setup:580,584`**

The pattern `^version\s*=` requires `version` at column 0. TOML allows leading whitespace (`  version = "1.0.0"`), which some auto-formatters produce. Detection silently falls through to the wrong file (e.g., CHANGELOG.md as fallback). Same issue on line 584 for pyproject.toml.

Fix: use `^\s*version\s*=` instead of `^version\s*=` in both grep patterns.

---

## Important Issues (4)

### 4. Stale skill counts in AGENT_CONTEXT.md and ARCHITECTURE.md

- `AGENT_CONTEXT.md:7` — still says "Lite (16 skills" and "Full (23 skills" → should be 18/25
- `AGENT_CONTEXT.md:17,18` — distribution target rows still say 16-skill and 23-skill
- `ARCHITECTURE.md:11,12,24` — still say 16/23 → should be 18/25

The Skills row in both files was updated to 25 but these 6 references were missed, creating internal contradictions.

### 5. `jq` write failure leaves no diagnostic
**`setup:609-614`**

If `jq` fails writing release config, `set -e` kills the entire setup script with no context. The `$config.$$` temp file may be orphaned. Re-running setup may skip the config step because it already exists.

Fix: wrap in `if ... then ok ... else rm -f "$config.$$"; warn ... fi`.

### 6. No negative tests for section-aware TOML parsing
**`test-crelease.sh`**

`detect_version_file` deliberately parses `[package]`/`[project]` sections, but no test verifies this works:

- Cargo.toml with `version` only under `[workspace]` (no `[package]`) → should result in `version_file: null`
- pyproject.toml with `version` only under `[tool.poetry]` (no `[project]`) → should result in `version_file: null`

### 7. No version file priority test
**`test-crelease.sh`**

The elif chain has implicit priority (package.json > Cargo.toml > pyproject.toml > setup.cfg > Go > CHANGELOG.md). Reordering the chain silently changes behavior. Add a test with multiple version files present.

---

## Suggestions (5)

### 8. ~78% of test assertions are keyword-greps on SKILL.md
**`test-crelease.sh`**

Most test functions grep SKILL.md for words like "minor", "patch", "changelog". These pass even if instructions are wrong — the word just needs to appear. The R-004/R-013 behavioral tests are excellent by comparison. Consider tightening patterns to check specific phrases in context, or acknowledge these are content-contract tests.

### 9. Workflow history says "Findings fixed: 7" but should be 8
**`docs/workflow-history.md:5`**

Verification report lists QA-001 through QA-008, all fixed. PR body also says "8 QA findings."

### 10. SKILL.md R-006 warning omits spec wording
**`skills/crelease/SKILL.md:154`**

Spec says: "{N} active workflows on other branches. **This release only includes main.** Continue?" — the bolded phrase is omitted. It provides context about why other-branch workflows are flagged.

### 11. AGENT_CONTEXT.md test command missing `test-decisions.sh`
**`AGENT_CONTEXT.md:41`**

Lists 7 test suites but there are 8. Pre-existing but this line was modified to add `test-crelease.sh`.

### 12. Files outside PR scope with stale counts

`docs/index.md`, `.claude-plugin/marketplace.json`, `correctless-lite.md`, `correctless.md` all still say 16/23. Worth fixing while counts are being updated.

---

## Strengths

- Three-way file consistency is perfect (SKILL.md and setup copies are byte-identical)
- `detect_version_file()` is well-designed with section-aware TOML parsing, `jq -e` null checks, and JSON validation guard
- R-004/R-013 version detection tests are excellent — real project structures with actual setup execution
- Rust `build_error_pattern` JSON escape fix is correct
- SKILL.md has clear execution order with explicit decision points and error recovery
- Overall error handling is above average for shell scripts
