#!/usr/bin/env bash
# Correctless — crelease test suite
# Tests spec rules R-001 through R-019 from
# docs/specs/add-crelease-skill-for-versioning-and-changelog.md
# Run from repo root: bash test-crelease.sh

set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="/tmp/correctless-crelease-test-$$"
PASS=0
FAIL=0

# ---------------------------------------------------------------------------
# Helpers (matching test.sh style)
# ---------------------------------------------------------------------------

setup_test_project() {
  rm -rf "$TEST_DIR"
  mkdir -p "$TEST_DIR"
  cd "$TEST_DIR" || exit
  git init -q
  git branch -M main
  echo '{"name": "test-app", "version": "1.2.3", "scripts": {"test": "echo PASS && exit 0", "lint": "echo ok", "build": "echo ok"}}' > package.json
  echo 'export function hello() {}' > index.ts
  git add -A && git commit -q -m "init"

  # Install correctless (exclude .git to avoid nested repo confusion)
  mkdir -p .claude/skills/workflow
  rsync -a --exclude='.git' --exclude='tests' "$REPO_DIR/" .claude/skills/workflow/
}

cleanup() {
  rm -rf "$TEST_DIR"
}

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (expected '$expected', got '$actual')"
    FAIL=$((FAIL + 1))
  fi
}

assert_contains() {
  local desc="$1" expected="$2" actual="$3"
  if echo "$actual" | grep -q "$expected"; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (expected output to contain '$expected')"
    FAIL=$((FAIL + 1))
  fi
}

assert_not_contains() {
  local desc="$1" unexpected="$2" actual="$3"
  if echo "$actual" | grep -q "$unexpected"; then
    echo "  FAIL: $desc (output should NOT contain '$unexpected')"
    FAIL=$((FAIL + 1))
  else
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  fi
}

# Check if a file contains a pattern (returns 0 if found)
file_contains() {
  grep -q "$2" "$1" 2>/dev/null
}

# Check if a file does NOT contain a pattern (returns 0 if not found)
file_not_contains() {
  ! grep -q "$2" "$1" 2>/dev/null
}

ADV() { cd "$TEST_DIR" && .correctless/hooks/workflow-advance.sh "$@"; }

# ---------------------------------------------------------------------------
# Test: R-012 — SKILL.md exists and is registered
# ---------------------------------------------------------------------------

test_r012_skill_exists() {
  echo ""
  echo "=== R-012: SKILL.md exists and is registered ==="

  # Tests R-012 [integration]: SKILL.md at skills/crelease/SKILL.md
  local skill_file="$REPO_DIR/skills/crelease/SKILL.md"
  assert_eq "R-012: skills/crelease/SKILL.md exists" "true" \
    "$([ -f "$skill_file" ] && echo true || echo false)"

  # SKILL.md should NOT be a stub — it should have real content
  file_not_contains "$skill_file" "STUB:TDD" \
    && local not_stub="true" || local not_stub="false"
  assert_eq "R-012: SKILL.md is not a stub" "true" "$not_stub"

  # SKILL.md should have correct frontmatter
  file_contains "$skill_file" "^name: crelease" \
    && local has_name="true" || local has_name="false"
  assert_eq "R-012: SKILL.md has name: crelease in frontmatter" "true" "$has_name"

  # Tests R-012 [integration]: registered in sync.sh for Lite
  local sync_file="$REPO_DIR/sync.sh"
  file_contains "$sync_file" "crelease" \
    && local in_sync="true" || local in_sync="false"
  assert_eq "R-012: crelease registered in sync.sh" "true" "$in_sync"

  # Check skill list contains crelease
  grep -q 'for skill in.*crelease' "$sync_file" 2>/dev/null \
    && local in_skill_loop="true" || local in_skill_loop="false"
  assert_eq "R-012: crelease in sync.sh skill loop" "true" "$in_skill_loop"

  # Check crelease appears in sync.sh
  local crelease_count
  crelease_count="$(grep -c 'crelease' "$sync_file" 2>/dev/null || true)"
  crelease_count="${crelease_count:-0}"
  # Should appear at least once in the skill loop
  assert_eq "R-012: crelease in sync.sh skill list (appears 1+ times)" "true" \
    "$([ "$crelease_count" -ge 1 ] 2>/dev/null && echo true || echo false)"

  # Tests R-012 [integration]: documented in docs/skills/crelease.md
  local docs_file="$REPO_DIR/docs/skills/crelease.md"
  assert_eq "R-012: docs/skills/crelease.md exists" "true" \
    "$([ -f "$docs_file" ] && echo true || echo false)"

  # Docs file should NOT be a stub
  file_not_contains "$docs_file" "STUB:TDD" \
    && local docs_not_stub="true" || local docs_not_stub="false"
  assert_eq "R-012: docs/skills/crelease.md is not a stub" "true" "$docs_not_stub"

  # Tests R-012 [integration]: in README skills table
  local readme_file="$REPO_DIR/README.md"
  file_contains "$readme_file" "/crelease" \
    && local in_readme="true" || local in_readme="false"
  assert_eq "R-012: /crelease in README.md skills table" "true" "$in_readme"

  # README should link to the docs file
  file_contains "$readme_file" "docs/skills/crelease.md" \
    && local readme_links="true" || local readme_links="false"
  assert_eq "R-012: README links to docs/skills/crelease.md" "true" "$readme_links"
}

# ---------------------------------------------------------------------------
# Test: R-004, R-013 — Setup detects version files
# ---------------------------------------------------------------------------

test_r004_r013_version_detection() {
  echo ""
  echo "=== R-004, R-013: Setup detects version file ==="

  # Tests R-004 [integration]: /csetup detects package.json version
  setup_test_project
  .claude/skills/workflow/setup >/dev/null 2>&1

  local config_file=".correctless/config/workflow-config.json"
  assert_eq "R-004: workflow-config.json exists after setup" "true" \
    "$([ -f "$config_file" ] && echo true || echo false)"

  # Tests R-013 [integration]: release.version_file stored in config
  local version_file
  version_file="$(jq -r '.release.version_file // empty' "$config_file" 2>/dev/null || echo "")"
  assert_eq "R-013: release.version_file set for package.json project" "package.json" "$version_file"

  local version_pattern
  version_pattern="$(jq -r '.release.version_pattern // empty' "$config_file" 2>/dev/null || echo "")"
  assert_eq "R-013: release.version_pattern is set" "true" \
    "$([ -n "$version_pattern" ] && echo true || echo false)"

  # Tests R-004 [integration]: /csetup detects Cargo.toml version
  setup_test_project
  rm -f package.json
  cat > Cargo.toml <<'TOML'
[package]
name = "test-app"
version = "0.5.1"
edition = "2021"
TOML
  git add -A && git commit -q -m "switch to rust"
  .claude/skills/workflow/setup >/dev/null 2>&1

  version_file="$(jq -r '.release.version_file // empty' "$config_file" 2>/dev/null || echo "")"
  assert_eq "R-004: release.version_file set for Cargo.toml project" "Cargo.toml" "$version_file"

  # Tests R-004 [integration]: /csetup detects pyproject.toml version
  setup_test_project
  rm -f package.json
  cat > pyproject.toml <<'TOML'
[project]
name = "test-app"
version = "2.0.0"
TOML
  git add -A && git commit -q -m "switch to python"
  .claude/skills/workflow/setup >/dev/null 2>&1

  version_file="$(jq -r '.release.version_file // empty' "$config_file" 2>/dev/null || echo "")"
  assert_eq "R-004: release.version_file set for pyproject.toml project" "pyproject.toml" "$version_file"

  # Tests R-013 [integration]: no version file → fields are null
  setup_test_project
  rm -f package.json
  echo "just a plain text project" > README.md
  git add -A && git commit -q -m "no version file"
  .claude/skills/workflow/setup >/dev/null 2>&1

  # The release section must explicitly exist as an object with null fields
  local has_release_key
  has_release_key="$(jq 'has("release")' "$config_file" 2>/dev/null || echo "false")"
  assert_eq "R-013: config has explicit release section" "true" "$has_release_key"

  version_file="$(jq -r '.release.version_file' "$config_file" 2>/dev/null || echo "missing")"
  assert_eq "R-013: release.version_file is null when no version file" "null" "$version_file"

  version_pattern="$(jq -r '.release.version_pattern' "$config_file" 2>/dev/null || echo "missing")"
  assert_eq "R-013: release.version_pattern is null when no version file" "null" "$version_pattern"
}

# ---------------------------------------------------------------------------
# Test: R-001 — SKILL.md contains spec-based bump classification instructions
# ---------------------------------------------------------------------------

test_r001_skill_content() {
  echo ""
  echo "=== R-001: SKILL.md contains spec-based bump classification ==="

  local skill="$REPO_DIR/skills/crelease/SKILL.md"

  # Tests R-001 [integration]: reads specs from .correctless/specs/
  file_contains "$skill" "\.correctless/specs" \
    && local has_specs_dir="true" || local has_specs_dir="false"
  assert_eq "R-001: SKILL.md references .correctless/specs/" "true" "$has_specs_dir"

  # Tests R-001: classifies new features as minor bumps
  file_contains "$skill" "minor" \
    && local has_minor="true" || local has_minor="false"
  assert_eq "R-001: SKILL.md mentions minor bump" "true" "$has_minor"

  # Tests R-001: classifies bug fixes as patch bumps
  file_contains "$skill" "patch" \
    && local has_patch="true" || local has_patch="false"
  assert_eq "R-001: SKILL.md mentions patch bump" "true" "$has_patch"

  # Tests R-001: classifies breaking changes as major bumps
  file_contains "$skill" "major" \
    && local has_major="true" || local has_major="false"
  assert_eq "R-001: SKILL.md mentions major bump" "true" "$has_major"

  # Tests R-001: breaking change detection patterns (spec requires: "breaking", "removes", "renames", "no longer supports")
  file_contains "$skill" "breaking" \
    && local has_breaking="true" || local has_breaking="false"
  assert_eq "R-001: SKILL.md mentions breaking changes" "true" "$has_breaking"

  file_contains "$skill" "removes\|renames" \
    && local has_remove_rename="true" || local has_remove_rename="false"
  assert_eq "R-001: SKILL.md mentions removes/renames detection patterns" "true" "$has_remove_rename"

  file_contains "$skill" "no longer supports" \
    && local has_no_longer="true" || local has_no_longer="false"
  assert_eq "R-001: SKILL.md mentions 'no longer supports' detection pattern" "true" "$has_no_longer"

  # Tests R-001: commit messages NOT used for bump classification
  file_contains "$skill" "[Cc]ommit messages.*[Nn][Oo][Tt]\|[Nn]ot.*commit messages\|specs.*not commit" \
    && local has_no_commits="true" || local has_no_commits="false"
  assert_eq "R-001: SKILL.md states commit messages not used for classification" "true" "$has_no_commits"

  # Tests R-001: warns about unmapped commits
  file_contains "$skill" "unmapped\|unmap\|no corresponding spec" \
    && local has_unmapped="true" || local has_unmapped="false"
  assert_eq "R-001: SKILL.md warns about unmapped commits" "true" "$has_unmapped"

  # Tests R-001: highest bump wins when multiple specs
  file_contains "$skill" "highest.*wins\|major.*>.*minor\|highest bump" \
    && local has_highest="true" || local has_highest="false"
  assert_eq "R-001: SKILL.md states highest bump wins" "true" "$has_highest"

  # Tests R-001: falls through to R-010 when no specs
  file_contains "$skill" "[Nn]o specs\|fallback\|fall.*through\|no.*specs.*exist" \
    && local has_fallthrough="true" || local has_fallthrough="false"
  assert_eq "R-001: SKILL.md mentions no-spec fallthrough" "true" "$has_fallthrough"
}

# ---------------------------------------------------------------------------
# Test: R-002 — SKILL.md contains version bump confirmation instructions
# ---------------------------------------------------------------------------

test_r002_skill_content() {
  echo ""
  echo "=== R-002: SKILL.md contains version bump confirmation ==="

  local skill="$REPO_DIR/skills/crelease/SKILL.md"

  # Tests R-002 [integration]: presents determined bump for confirmation
  file_contains "$skill" "confirm\|approval\|present.*bump\|user.*confirm" \
    && local has_confirm="true" || local has_confirm="false"
  assert_eq "R-002: SKILL.md mentions user confirmation" "true" "$has_confirm"

  # Tests R-002: shows current version
  file_contains "$skill" "current version\|current.*version" \
    && local has_current="true" || local has_current="false"
  assert_eq "R-002: SKILL.md mentions showing current version" "true" "$has_current"

  # Tests R-002: shows proposed version
  file_contains "$skill" "proposed version\|proposed.*version\|new version" \
    && local has_proposed="true" || local has_proposed="false"
  assert_eq "R-002: SKILL.md mentions showing proposed version" "true" "$has_proposed"

  # Tests R-002: user can override bump level
  file_contains "$skill" "override\|change.*bump\|adjust" \
    && local has_override="true" || local has_override="false"
  assert_eq "R-002: SKILL.md mentions user can override bump" "true" "$has_override"
}

# ---------------------------------------------------------------------------
# Test: R-003 — SKILL.md contains changelog generation instructions
# ---------------------------------------------------------------------------

test_r003_skill_content() {
  echo ""
  echo "=== R-003: SKILL.md contains changelog generation ==="

  local skill="$REPO_DIR/skills/crelease/SKILL.md"

  # Tests R-003 [integration]: generates changelog from spec titles
  file_contains "$skill" "changelog\|CHANGELOG" \
    && local has_changelog="true" || local has_changelog="false"
  assert_eq "R-003: SKILL.md mentions changelog" "true" "$has_changelog"

  # Tests R-003: groups by Breaking Changes
  file_contains "$skill" "Breaking Changes\|breaking.*changes" \
    && local has_breaking="true" || local has_breaking="false"
  assert_eq "R-003: SKILL.md mentions Breaking Changes group" "true" "$has_breaking"

  # Tests R-003: groups by New Features
  file_contains "$skill" "New Features\|new.*features" \
    && local has_features="true" || local has_features="false"
  assert_eq "R-003: SKILL.md mentions New Features group" "true" "$has_features"

  # Tests R-003: groups by Bug Fixes
  file_contains "$skill" "Bug Fixes\|bug.*fixes" \
    && local has_bugfixes="true" || local has_bugfixes="false"
  assert_eq "R-003: SKILL.md mentions Bug Fixes group" "true" "$has_bugfixes"

  # Tests R-003: groups by Internal Improvements
  file_contains "$skill" "Internal Improvements\|internal.*improvements" \
    && local has_internal="true" || local has_internal="false"
  assert_eq "R-003: SKILL.md mentions Internal Improvements group" "true" "$has_internal"

  # Tests R-003: references spec slug in entries
  file_contains "$skill" "spec.*slug\|slug" \
    && local has_slug="true" || local has_slug="false"
  assert_eq "R-003: SKILL.md mentions spec slug in entries" "true" "$has_slug"

  # Tests R-003: prepended to CHANGELOG.md
  file_contains "$skill" "prepend\|CHANGELOG.md" \
    && local has_prepend="true" || local has_prepend="false"
  assert_eq "R-003: SKILL.md mentions prepending to CHANGELOG.md" "true" "$has_prepend"
}

# ---------------------------------------------------------------------------
# Test: R-005 — SKILL.md contains version file update instructions
# ---------------------------------------------------------------------------

test_r005_skill_content() {
  echo ""
  echo "=== R-005: SKILL.md contains version file update instructions ==="

  local skill="$REPO_DIR/skills/crelease/SKILL.md"

  # Tests R-005 [integration]: updates version in detected file
  file_contains "$skill" "version.*file\|update.*version\|version_file" \
    && local has_update="true" || local has_update="false"
  assert_eq "R-005: SKILL.md mentions version file update" "true" "$has_update"

  # Tests R-005: uses jq for JSON
  file_contains "$skill" "jq" \
    && local has_jq="true" || local has_jq="false"
  assert_eq "R-005: SKILL.md mentions jq for JSON updates" "true" "$has_jq"

  # Tests R-005: uses sed for TOML/Go
  file_contains "$skill" "sed" \
    && local has_sed="true" || local has_sed="false"
  assert_eq "R-005: SKILL.md mentions sed for TOML/Go updates" "true" "$has_sed"

  # Tests R-005: old version must not remain
  file_contains "$skill" "old version.*must not\|must not.*appear\|old.*version.*not.*appear\|verify.*old" \
    && local has_verify="true" || local has_verify="false"
  assert_eq "R-005: SKILL.md states old version must not remain" "true" "$has_verify"

  # Tests R-005: skip with warning when no version file
  file_contains "$skill" "[Nn]o version file\|version_file.*null\|skip.*version\|warn.*version" \
    && local has_skip="true" || local has_skip="false"
  assert_eq "R-005: SKILL.md handles missing version file" "true" "$has_skip"
}

# ---------------------------------------------------------------------------
# Test: R-006 — SKILL.md contains sanity check instructions
# ---------------------------------------------------------------------------

test_r006_skill_content() {
  echo ""
  echo "=== R-006: SKILL.md contains sanity check instructions ==="

  local skill="$REPO_DIR/skills/crelease/SKILL.md"

  # Tests R-006 [integration]: test command must pass
  file_contains "$skill" "test.*pass\|tests.*pass\|test command" \
    && local has_tests="true" || local has_tests="false"
  assert_eq "R-006: SKILL.md mentions tests must pass" "true" "$has_tests"

  # Tests R-006: sync.sh --check must pass
  file_contains "$skill" "sync\|sync.sh" \
    && local has_sync="true" || local has_sync="false"
  assert_eq "R-006: SKILL.md mentions sync check" "true" "$has_sync"

  # Tests R-006: no BLOCKING QA findings
  file_contains "$skill" "[Bb][Ll][Oo][Cc][Kk].*[Qq][Aa]\|qa.*findings\|QA.*findings\|BLOCKING" \
    && local has_qa="true" || local has_qa="false"
  assert_eq "R-006: SKILL.md mentions blocking QA findings" "true" "$has_qa"

  # Tests R-006: tag must not already exist
  file_contains "$skill" "tag.*exist\|tag.*already\|already.*exist.*tag\|tag.*collision" \
    && local has_tag_check="true" || local has_tag_check="false"
  assert_eq "R-006: SKILL.md checks tag doesn't already exist" "true" "$has_tag_check"

  # Tests R-006: warns about active workflows on other branches
  file_contains "$skill" "active workflow\|other branch" \
    && local has_workflow_warn="true" || local has_workflow_warn="false"
  assert_eq "R-006: SKILL.md warns about active workflows" "true" "$has_workflow_warn"
}

# ---------------------------------------------------------------------------
# Test: R-007 — SKILL.md contains annotated tag instructions
# ---------------------------------------------------------------------------

test_r007_skill_content() {
  echo ""
  echo "=== R-007: SKILL.md contains annotated tag creation ==="

  local skill="$REPO_DIR/skills/crelease/SKILL.md"

  # Tests R-007 [integration]: creates annotated git tag v{version}
  file_contains "$skill" "annotated.*tag\|git tag -a\|annotated" \
    && local has_annotated="true" || local has_annotated="false"
  assert_eq "R-007: SKILL.md mentions annotated tag" "true" "$has_annotated"

  # Tests R-007: tag format is v{version}
  file_contains "$skill" "v{version}\|v{.*version" \
    && local has_format="true" || local has_format="false"
  assert_eq "R-007: SKILL.md specifies v{version} tag format" "true" "$has_format"

  # Tests R-007: changelog as tag message
  file_contains "$skill" "changelog.*tag.*message\|tag.*message.*changelog\|changelog.*message" \
    && local has_msg="true" || local has_msg="false"
  assert_eq "R-007: SKILL.md uses changelog as tag message" "true" "$has_msg"
}

# ---------------------------------------------------------------------------
# Test: R-008 — SKILL.md contains commit-before-tag instructions
# ---------------------------------------------------------------------------

test_r008_skill_content() {
  echo ""
  echo "=== R-008: SKILL.md contains commit-before-tag instructions ==="

  local skill="$REPO_DIR/skills/crelease/SKILL.md"

  # Tests R-008 [integration]: commits changelog + version before tagging
  file_contains "$skill" "commit.*before.*tag\|commit.*changelog.*version\|commit.*version.*changelog" \
    && local has_commit="true" || local has_commit="false"
  assert_eq "R-008: SKILL.md mentions commit before tag" "true" "$has_commit"

  # Tests R-008: commit message is "Release v{version}"
  file_contains "$skill" 'Release v{version}\|Release v.*{version}' \
    && local has_msg="true" || local has_msg="false"
  assert_eq "R-008: SKILL.md specifies 'Release v{version}' commit message" "true" "$has_msg"
}

# ---------------------------------------------------------------------------
# Test: R-009 — SKILL.md contains badge detection instructions
# ---------------------------------------------------------------------------

test_r009_skill_content() {
  echo ""
  echo "=== R-009: SKILL.md contains badge detection ==="

  local skill="$REPO_DIR/skills/crelease/SKILL.md"

  # Tests R-009 [integration]: detects shields.io version badges
  file_contains "$skill" "badge\|shields.io" \
    && local has_badge="true" || local has_badge="false"
  assert_eq "R-009: SKILL.md mentions badge detection" "true" "$has_badge"

  # Tests R-009: offers to update, not automatic — specific to badges context
  file_contains "$skill" "offer.*update.*badge\|badge.*not automatic\|badge.*offer\|badge.*ask\|update.*badge" \
    && local has_offer="true" || local has_offer="false"
  assert_eq "R-009: SKILL.md offers badge update (not automatic)" "true" "$has_offer"
}

# ---------------------------------------------------------------------------
# Test: R-010 — SKILL.md contains no-spec fallback instructions
# ---------------------------------------------------------------------------

test_r010_skill_content() {
  echo ""
  echo "=== R-010: SKILL.md contains no-spec fallback ==="

  local skill="$REPO_DIR/skills/crelease/SKILL.md"

  # Tests R-010 [integration]: presents commits when no specs
  file_contains "$skill" "no specs\|no.*spec.*exist\|list.*commits\|commit.*list" \
    && local has_no_specs="true" || local has_no_specs="false"
  assert_eq "R-010: SKILL.md handles no-specs scenario" "true" "$has_no_specs"

  # Tests R-010: user classifies bump manually
  file_contains "$skill" "user.*classif\|classif.*bump\|manual.*bump\|user.*decide\|user decides" \
    && local has_manual="true" || local has_manual="false"
  assert_eq "R-010: SKILL.md mentions user classifies bump" "true" "$has_manual"

  # Tests R-010: conventional commits shown as suggestion
  file_contains "$skill" "conventional commit\|conventional-commit" \
    && local has_conventional="true" || local has_conventional="false"
  assert_eq "R-010: SKILL.md mentions conventional commits as suggestion" "true" "$has_conventional"
}

# ---------------------------------------------------------------------------
# Test: R-011 — SKILL.md contains dry-run instructions
# ---------------------------------------------------------------------------

test_r011_skill_content() {
  echo ""
  echo "=== R-011: SKILL.md contains dry-run instructions ==="

  local skill="$REPO_DIR/skills/crelease/SKILL.md"

  # Tests R-011 [integration]: supports --dry-run flag
  file_contains "$skill" "dry.run\|dry_run\|--dry-run" \
    && local has_dry_run="true" || local has_dry_run="false"
  assert_eq "R-011: SKILL.md mentions dry-run" "true" "$has_dry_run"

  # Tests R-011: shows what would happen without changes
  file_contains "$skill" "without.*change\|no.*change\|preview\|what would happen" \
    && local has_preview="true" || local has_preview="false"
  assert_eq "R-011: SKILL.md describes dry-run as preview" "true" "$has_preview"

  # Tests R-011: dry-run is the default first option
  file_contains "$skill" "default.*first\|first.*option\|default.*option\|offered first" \
    && local has_default="true" || local has_default="false"
  assert_eq "R-011: SKILL.md presents dry-run as default first option" "true" "$has_default"
}

# ---------------------------------------------------------------------------
# Test: R-014 — SKILL.md contains changelog style preservation instructions
# ---------------------------------------------------------------------------

test_r014_skill_content() {
  echo ""
  echo "=== R-014: SKILL.md contains changelog style preservation ==="

  local skill="$REPO_DIR/skills/crelease/SKILL.md"

  # Tests R-014 [unit]: preserves existing CHANGELOG.md style
  file_contains "$skill" "existing.*style\|preserve.*style\|match.*format\|existing.*format" \
    && local has_style="true" || local has_style="false"
  assert_eq "R-014: SKILL.md mentions preserving changelog style" "true" "$has_style"

  # Tests R-014: reads first ## heading pattern
  file_contains "$skill" "first.*heading\|## .*heading\|heading.*pattern\|extract.*pattern" \
    && local has_heading="true" || local has_heading="false"
  assert_eq "R-014: SKILL.md mentions reading heading pattern" "true" "$has_heading"

  # Tests R-014: creates changelog if none exists
  file_contains "$skill" "create.*changelog\|no changelog\|no.*CHANGELOG\|create.*CHANGELOG" \
    && local has_create="true" || local has_create="false"
  assert_eq "R-014: SKILL.md handles creating new changelog" "true" "$has_create"

  # Tests R-014: default format with date
  file_contains "$skill" "YYYY-MM-DD\|x\.y\.z\|\[.*\].*-.*date" \
    && local has_format="true" || local has_format="false"
  assert_eq "R-014: SKILL.md specifies default date format" "true" "$has_format"
}

# ---------------------------------------------------------------------------
# Test: R-015 — SKILL.md contains push/release instructions
# ---------------------------------------------------------------------------

test_r015_skill_content() {
  echo ""
  echo "=== R-015: SKILL.md contains push/release offering ==="

  local skill="$REPO_DIR/skills/crelease/SKILL.md"

  # Tests R-015 [integration]: offers to push tag + commit
  file_contains "$skill" "push.*tag\|push.*commit\|push.*release" \
    && local has_push="true" || local has_push="false"
  assert_eq "R-015: SKILL.md mentions pushing tag" "true" "$has_push"

  # Tests R-015: push tag + commit option
  file_contains "$skill" "tag.*commit\|push.*tag.*commit\|tag and commit" \
    && local has_both="true" || local has_both="false"
  assert_eq "R-015: SKILL.md offers push tag + commit option" "true" "$has_both"

  # Tests R-015: push tag only option
  file_contains "$skill" "tag only\|tag.*only\|push.*tag.*only" \
    && local has_tag_only="true" || local has_tag_only="false"
  assert_eq "R-015: SKILL.md offers push tag only option" "true" "$has_tag_only"

  # Tests R-015: don't push option
  file_contains "$skill" "don.*push\|manual\|don't push\|skip.*push" \
    && local has_no_push="true" || local has_no_push="false"
  assert_eq "R-015: SKILL.md offers don't push option" "true" "$has_no_push"

  # Tests R-015: GitHub release via gh
  file_contains "$skill" "gh.*release\|GitHub release\|github release" \
    && local has_gh="true" || local has_gh="false"
  assert_eq "R-015: SKILL.md mentions GitHub release via gh" "true" "$has_gh"
}

# ---------------------------------------------------------------------------
# Test: R-016 — SKILL.md contains token logging instructions
# ---------------------------------------------------------------------------

test_r016_skill_content() {
  echo ""
  echo "=== R-016: SKILL.md contains token logging ==="

  local skill="$REPO_DIR/skills/crelease/SKILL.md"

  # Tests R-016 [unit]: logs token usage to token-log-{slug}.json
  file_contains "$skill" "token.*log\|token-log" \
    && local has_token_log="true" || local has_token_log="false"
  assert_eq "R-016: SKILL.md mentions token logging" "true" "$has_token_log"

  # Tests R-016: correct artifact path
  file_contains "$skill" "\.correctless/artifacts/token-log" \
    && local has_path="true" || local has_path="false"
  assert_eq "R-016: SKILL.md specifies .correctless/artifacts/ token log path" "true" "$has_path"

  # Tests R-016: skill field is crelease
  file_contains "$skill" '"crelease"\|skill.*crelease\|crelease.*skill' \
    && local has_skill_field="true" || local has_skill_field="false"
  assert_eq "R-016: SKILL.md specifies crelease skill field" "true" "$has_skill_field"

  # Tests R-016: required fields: phase, agent_role, total_tokens, duration_ms, timestamp
  file_contains "$skill" "phase.*release\|release.*phase" \
    && local has_phase="true" || local has_phase="false"
  assert_eq "R-016: SKILL.md specifies release phase field" "true" "$has_phase"

  file_contains "$skill" "agent_role\|release.agent" \
    && local has_role="true" || local has_role="false"
  assert_eq "R-016: SKILL.md specifies agent_role field" "true" "$has_role"

  file_contains "$skill" "total_tokens" \
    && local has_tokens="true" || local has_tokens="false"
  assert_eq "R-016: SKILL.md specifies total_tokens field" "true" "$has_tokens"

  file_contains "$skill" "duration_ms" \
    && local has_duration="true" || local has_duration="false"
  assert_eq "R-016: SKILL.md specifies duration_ms field" "true" "$has_duration"

  file_contains "$skill" "timestamp" \
    && local has_timestamp="true" || local has_timestamp="false"
  assert_eq "R-016: SKILL.md specifies timestamp field" "true" "$has_timestamp"
}

# ---------------------------------------------------------------------------
# Test: R-017 — SKILL.md contains dirty working tree check
# ---------------------------------------------------------------------------

test_r017_skill_content() {
  echo ""
  echo "=== R-017: SKILL.md contains dirty working tree check ==="

  local skill="$REPO_DIR/skills/crelease/SKILL.md"

  # Tests R-017 [integration]: checks for uncommitted changes
  file_contains "$skill" "uncommitted\|dirty\|git status.*porcelain\|working tree\|working.*dirty" \
    && local has_dirty="true" || local has_dirty="false"
  assert_eq "R-017: SKILL.md checks for uncommitted changes" "true" "$has_dirty"

  # Tests R-017: stash option
  file_contains "$skill" "[Ss]tash" \
    && local has_stash="true" || local has_stash="false"
  assert_eq "R-017: SKILL.md offers stash option" "true" "$has_stash"

  # Tests R-017: abort option
  file_contains "$skill" "[Aa]bort" \
    && local has_abort="true" || local has_abort="false"
  assert_eq "R-017: SKILL.md offers abort option" "true" "$has_abort"

  # Tests R-017: continue anyway option
  file_contains "$skill" "[Cc]ontinue anyway\|continue.*anyway\|proceed" \
    && local has_continue="true" || local has_continue="false"
  assert_eq "R-017: SKILL.md offers continue anyway option" "true" "$has_continue"
}

# ---------------------------------------------------------------------------
# Test: R-018 — SKILL.md contains first release instructions
# ---------------------------------------------------------------------------

test_r018_skill_content() {
  echo ""
  echo "=== R-018: SKILL.md contains first release (no prior tags) ==="

  local skill="$REPO_DIR/skills/crelease/SKILL.md"

  # Tests R-018 [integration]: detects no git tags
  file_contains "$skill" "[Nn]o.*tag\|no prior.*tag\|first.*release\|initial.*version" \
    && local has_no_tags="true" || local has_no_tags="false"
  assert_eq "R-018: SKILL.md handles no prior tags" "true" "$has_no_tags"

  # Tests R-018: offers 0.1.0 as option
  file_contains "$skill" "0\.1\.0" \
    && local has_010="true" || local has_010="false"
  assert_eq "R-018: SKILL.md offers 0.1.0 as initial version" "true" "$has_010"

  # Tests R-018: offers 1.0.0 as option
  file_contains "$skill" "1\.0\.0" \
    && local has_100="true" || local has_100="false"
  assert_eq "R-018: SKILL.md offers 1.0.0 as initial version" "true" "$has_100"

  # Tests R-018: offers manual entry
  file_contains "$skill" "[Mm]anual\|[Ee]nter manually\|custom" \
    && local has_manual="true" || local has_manual="false"
  assert_eq "R-018: SKILL.md offers manual version entry" "true" "$has_manual"
}

# ---------------------------------------------------------------------------
# Test: R-019 — SKILL.md contains nothing-to-release exit
# ---------------------------------------------------------------------------

test_r019_skill_content() {
  echo ""
  echo "=== R-019: SKILL.md contains nothing-to-release exit ==="

  local skill="$REPO_DIR/skills/crelease/SKILL.md"

  # Tests R-019 [unit]: no commits between last tag and HEAD
  file_contains "$skill" "[Nn]o changes\|[Nn]othing to release\|no commits" \
    && local has_nothing="true" || local has_nothing="false"
  assert_eq "R-019: SKILL.md handles nothing to release" "true" "$has_nothing"

  # Tests R-019: exits cleanly — specific to the no-changes scenario
  file_contains "$skill" "[Nn]othing to release.*exit\|[Nn]o changes since.*exit\|report.*nothing\|exits.*no.*change\|no commits.*exit" \
    && local has_exit="true" || local has_exit="false"
  assert_eq "R-019: SKILL.md exits when nothing to release" "true" "$has_exit"
}

# ---------------------------------------------------------------------------
# Test: R-004 — Setup detects Go version constants
# ---------------------------------------------------------------------------

test_r004_go_detection() {
  echo ""
  echo "=== R-004: Setup detects Go version constants ==="

  # Tests R-004 [integration]: detects Go version constant
  setup_test_project
  rm -f package.json
  mkdir -p cmd
  cat > go.mod <<'GOMOD'
module example.com/test
go 1.21
GOMOD
  cat > cmd/version.go <<'GOVER'
package cmd
const Version = "3.1.0"
GOVER
  git add -A && git commit -q -m "go project"
  .claude/skills/workflow/setup >/dev/null 2>&1

  local config_file=".correctless/config/workflow-config.json"
  local version_file
  version_file="$(jq -r '.release.version_file // empty' "$config_file" 2>/dev/null || echo "")"
  assert_eq "R-004: release.version_file set for Go project" "cmd/version.go" "$version_file"
}

# ---------------------------------------------------------------------------
# Test: R-004 — Setup detects setup.cfg version
# ---------------------------------------------------------------------------

test_r004_setupcfg_detection() {
  echo ""
  echo "=== R-004: Setup detects setup.cfg version ==="

  # Tests R-004 [integration]: detects setup.cfg version
  setup_test_project
  rm -f package.json
  cat > setup.cfg <<'CFG'
[metadata]
name = test-app
version = 0.9.0
CFG
  git add -A && git commit -q -m "setup.cfg project"
  .claude/skills/workflow/setup >/dev/null 2>&1

  local config_file=".correctless/config/workflow-config.json"
  local version_file
  version_file="$(jq -r '.release.version_file // empty' "$config_file" 2>/dev/null || echo "")"
  assert_eq "R-004: release.version_file set for setup.cfg project" "setup.cfg" "$version_file"
}

# ---------------------------------------------------------------------------
# Test: R-004 — CHANGELOG.md heading fallback
# ---------------------------------------------------------------------------

test_r004_changelog_fallback() {
  echo ""
  echo "=== R-004: CHANGELOG.md heading fallback ==="

  # Tests R-004 [integration]: detects version from CHANGELOG.md heading
  setup_test_project
  rm -f package.json
  cat > CHANGELOG.md <<'CL'
# Changelog

## [1.5.0] - 2025-12-01

### Added
- Initial feature
CL
  git add -A && git commit -q -m "changelog-only version"
  .claude/skills/workflow/setup >/dev/null 2>&1

  local config_file=".correctless/config/workflow-config.json"
  local version_file
  version_file="$(jq -r '.release.version_file // empty' "$config_file" 2>/dev/null || echo "")"
  assert_eq "R-004: release.version_file set for CHANGELOG.md fallback" "CHANGELOG.md" "$version_file"
}

# ---------------------------------------------------------------------------
# Test: SKILL.md structural integrity (B-1: prevents keyword-stuffing)
# ---------------------------------------------------------------------------

test_skill_structure() {
  echo ""
  echo "=== Structural: SKILL.md has organized sections ==="

  local skill="$REPO_DIR/skills/crelease/SKILL.md"

  # B-1 fix: SKILL.md must have substantive content (not a keyword dump)
  local line_count
  line_count="$(wc -l < "$skill" 2>/dev/null || echo 0)"
  assert_eq "Structure: SKILL.md has at least 80 lines" "true" \
    "$([ "$line_count" -ge 80 ] && echo true || echo false)"

  # B-1 fix: SKILL.md must have organized sections (at least 6 ## headings)
  local heading_count
  heading_count="$(grep -c '^## ' "$skill" 2>/dev/null | tr -d '[:space:]')"
  heading_count="${heading_count:-0}"
  assert_eq "Structure: SKILL.md has at least 6 ## section headings" "true" \
    "$([ "$heading_count" -ge 6 ] && echo true || echo false)"

  # B-1 fix: Key workflow phases must have their own sections
  grep -q '^##.*[Vv]ersion.*[Bb]ump\|^##.*[Bb]ump.*[Cc]lassif\|^##.*[Dd]etermine' "$skill" 2>/dev/null \
    && local has_bump_section="true" || local has_bump_section="false"
  assert_eq "Structure: SKILL.md has bump classification section" "true" "$has_bump_section"

  grep -q '^##.*[Cc]hangelog\|^##.*[Gg]enerat' "$skill" 2>/dev/null \
    && local has_changelog_section="true" || local has_changelog_section="false"
  assert_eq "Structure: SKILL.md has changelog generation section" "true" "$has_changelog_section"

  grep -q '^##.*[Ss]anity\|^##.*[Pp]re.*[Tt]ag\|^##.*[Cc]heck' "$skill" 2>/dev/null \
    && local has_sanity_section="true" || local has_sanity_section="false"
  assert_eq "Structure: SKILL.md has sanity check section" "true" "$has_sanity_section"

  grep -q '^##.*[Tt]ag\|^##.*[Rr]elease.*[Cc]reat' "$skill" 2>/dev/null \
    && local has_tag_section="true" || local has_tag_section="false"
  assert_eq "Structure: SKILL.md has tagging section" "true" "$has_tag_section"
}

# ---------------------------------------------------------------------------
# Run all tests
# ---------------------------------------------------------------------------

trap cleanup EXIT

echo "Correctless /crelease Test Suite"
echo "================================="

test_r012_skill_exists
test_r004_r013_version_detection
test_r001_skill_content
test_r002_skill_content
test_r003_skill_content
test_r005_skill_content
test_r006_skill_content
test_r007_skill_content
test_r008_skill_content
test_r009_skill_content
test_r010_skill_content
test_r011_skill_content
test_r014_skill_content
test_r015_skill_content
test_r016_skill_content
test_r017_skill_content
test_r018_skill_content
test_r019_skill_content
test_r004_go_detection
test_r004_setupcfg_detection
test_r004_changelog_fallback
test_skill_structure

echo ""
echo "================================="
echo "Results: $PASS passed, $FAIL failed"
echo ""

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
