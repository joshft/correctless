#!/usr/bin/env bash
# Correctless — consolidation test suite
# Tests spec rules R-001 through R-020 from
# docs/specs/consolidate-artifacts-into-correctless-directory.md
# Run from repo root: bash test-consolidation.sh

set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="/tmp/correctless-consolidation-test-$$"
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
  echo '{"name": "test-app", "scripts": {"test": "echo FAIL && exit 1", "lint": "echo ok", "build": "echo ok"}}' > package.json
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

# ---------------------------------------------------------------------------
# Test: R-001 — setup creates .correctless/ directory structure
# ---------------------------------------------------------------------------

test_r001() {
  echo ""
  echo "=== R-001: setup creates .correctless/ directory structure ==="

  # Tests R-001 [integration]: setup creates .correctless/ directory structure
  setup_test_project
  .claude/skills/workflow/setup >/dev/null 2>&1

  # Core directories
  assert_eq "R-001: .correctless/ exists" "true" \
    "$([ -d .correctless ] && echo true || echo false)"
  assert_eq "R-001: .correctless/config/ exists" "true" \
    "$([ -d .correctless/config ] && echo true || echo false)"
  assert_eq "R-001: .correctless/hooks/ exists" "true" \
    "$([ -d .correctless/hooks ] && echo true || echo false)"
  assert_eq "R-001: .correctless/artifacts/ exists" "true" \
    "$([ -d .correctless/artifacts ] && echo true || echo false)"
  assert_eq "R-001: .correctless/artifacts/research/ exists" "true" \
    "$([ -d .correctless/artifacts/research ] && echo true || echo false)"
  assert_eq "R-001: .correctless/specs/ exists" "true" \
    "$([ -d .correctless/specs ] && echo true || echo false)"
  assert_eq "R-001: .correctless/decisions/ exists" "true" \
    "$([ -d .correctless/decisions ] && echo true || echo false)"
  assert_eq "R-001: .correctless/verification/ exists" "true" \
    "$([ -d .correctless/verification ] && echo true || echo false)"
  assert_eq "R-001: .correctless/learnings/ exists" "true" \
    "$([ -d .correctless/learnings ] && echo true || echo false)"

  # Full mode directories should NOT exist in Lite mode
  assert_eq "R-001: .correctless/meta/ NOT created in Lite mode" "false" \
    "$([ -d .correctless/meta ] && echo true || echo false)"

  # B-01: Full mode should additionally create meta/
  setup_test_project
  # Set up a Full mode config indicator before running setup
  mkdir -p .claude
  cat > .claude/workflow-config.json <<'FULLCFG'
{
  "project": {"name": "test-full", "language": "typescript"},
  "workflow": {"intensity": "standard", "min_qa_rounds": 2}
}
FULLCFG
  .claude/skills/workflow/setup >/dev/null 2>&1

  assert_eq "R-001: .correctless/meta/ created in Full mode" "true" \
    "$([ -d .correctless/meta ] && echo true || echo false)"
}

# ---------------------------------------------------------------------------
# Test: R-002 — setup defaults to NOT gitignoring .correctless/
# ---------------------------------------------------------------------------

test_r002() {
  echo ""
  echo "=== R-002: setup defaults to NOT gitignoring .correctless/ ==="

  # Tests R-002 [integration]: setup defaults to NOT adding .correctless/ to .gitignore
  setup_test_project
  .claude/skills/workflow/setup >/dev/null 2>&1

  # .correctless/ should NOT be in .gitignore
  local gitignore_content=""
  if [ -f .gitignore ]; then
    gitignore_content="$(cat .gitignore)"
  fi
  assert_not_contains "R-002: .correctless/ not in .gitignore by default" \
    "^\.correctless/" "$gitignore_content"

  # The csetup SKILL.md should mention the structured decision about gitignoring
  local csetup_skill="$REPO_DIR/skills/csetup/SKILL.md"
  file_contains "$csetup_skill" "gitignore.*\.correctless\|\.correctless.*gitignore" \
    && local found="true" || local found="false"
  assert_eq "R-002: csetup skill mentions .correctless gitignore decision" "true" "$found"
}

# ---------------------------------------------------------------------------
# Test: R-003 — workflow-config.json at .correctless/config/, no paths section
# ---------------------------------------------------------------------------

test_r003() {
  echo ""
  echo "=== R-003: workflow-config.json at .correctless/config/, no paths section ==="

  # Tests R-003 [integration]: workflow-config.json at .correctless/config/workflow-config.json
  setup_test_project
  .claude/skills/workflow/setup >/dev/null 2>&1

  assert_eq "R-003: config at .correctless/config/workflow-config.json" "true" \
    "$([ -f .correctless/config/workflow-config.json ] && echo true || echo false)"

  # Should NOT be at the old location
  assert_eq "R-003: no config at .claude/workflow-config.json" "false" \
    "$([ -f .claude/workflow-config.json ] && echo true || echo false)"

  # Config should NOT have a paths section
  if [ -f .correctless/config/workflow-config.json ]; then
    local has_paths
    has_paths="$(jq 'has("paths")' .correctless/config/workflow-config.json 2>/dev/null || echo "error")"
    assert_eq "R-003: config has no paths section" "false" "$has_paths"
  else
    # If the new config doesn't exist, check the old one
    if [ -f .claude/workflow-config.json ]; then
      local has_paths
      has_paths="$(jq 'has("paths")' .claude/workflow-config.json 2>/dev/null || echo "error")"
      assert_eq "R-003: config has no paths section (old location)" "false" "$has_paths"
    fi
  fi

  # Template files should also not have paths sections
  local lite_tmpl="$REPO_DIR/templates/workflow-config.json"
  local full_tmpl="$REPO_DIR/templates/workflow-config-full.json"

  local lite_has_paths
  lite_has_paths="$(jq 'has("paths")' "$lite_tmpl" 2>/dev/null || echo "error")"
  assert_eq "R-003: lite template has no paths section" "false" "$lite_has_paths"

  local full_has_paths
  full_has_paths="$(jq 'has("paths")' "$full_tmpl" 2>/dev/null || echo "error")"
  assert_eq "R-003: full template has no paths section" "false" "$full_has_paths"

  # Setup's detect_config output should not have paths section
  # (test by checking the setup script source)
  file_not_contains "$REPO_DIR/setup" '"paths"' \
    && local no_paths_in_setup="true" || local no_paths_in_setup="false"
  assert_eq "R-003: setup script does not generate paths section" "true" "$no_paths_in_setup"
}

# ---------------------------------------------------------------------------
# Test: R-004 — ARCHITECTURE.md and AGENT_CONTEXT.md at .correctless/
# ---------------------------------------------------------------------------

test_r004() {
  echo ""
  echo "=== R-004: ARCHITECTURE.md and AGENT_CONTEXT.md at .correctless/ ==="

  # Tests R-004 [integration]: docs at .correctless/ not project root
  setup_test_project
  .claude/skills/workflow/setup >/dev/null 2>&1

  assert_eq "R-004: ARCHITECTURE.md at .correctless/" "true" \
    "$([ -f .correctless/ARCHITECTURE.md ] && echo true || echo false)"
  assert_eq "R-004: AGENT_CONTEXT.md at .correctless/" "true" \
    "$([ -f .correctless/AGENT_CONTEXT.md ] && echo true || echo false)"

  # Should NOT be created at project root by setup
  # (They may already exist from before, but setup should not create new ones at root)
  # We check fresh install: root copies should not exist
  assert_eq "R-004: no ARCHITECTURE.md at project root (fresh install)" "false" \
    "$([ -f ARCHITECTURE.md ] && echo true || echo false)"
  assert_eq "R-004: no AGENT_CONTEXT.md at project root (fresh install)" "false" \
    "$([ -f AGENT_CONTEXT.md ] && echo true || echo false)"
}

# ---------------------------------------------------------------------------
# Test: R-005 — antipatterns.md at .correctless/
# ---------------------------------------------------------------------------

test_r005() {
  echo ""
  echo "=== R-005: antipatterns.md at .correctless/antipatterns.md ==="

  # Tests R-005 [integration]: antipatterns at .correctless/antipatterns.md
  setup_test_project
  .claude/skills/workflow/setup >/dev/null 2>&1

  assert_eq "R-005: antipatterns.md at .correctless/" "true" \
    "$([ -f .correctless/antipatterns.md ] && echo true || echo false)"

  # Should NOT be at old location
  assert_eq "R-005: no antipatterns.md at .claude/antipatterns.md" "false" \
    "$([ -f .claude/antipatterns.md ] && echo true || echo false)"
}

# ---------------------------------------------------------------------------
# Test: R-006 — All four hooks read from .correctless/ paths
# ---------------------------------------------------------------------------

test_r006() {
  echo ""
  echo "=== R-006: All four hooks read config from .correctless/ paths ==="

  # Tests R-006 [integration]: hooks use .correctless/config/ and .correctless/artifacts/
  local hooks_dir="$REPO_DIR/hooks"

  # workflow-advance.sh should reference .correctless/config/workflow-config.json
  file_contains "$hooks_dir/workflow-advance.sh" '\.correctless/config/workflow-config\.json' \
    && local adv_config="true" || local adv_config="false"
  assert_eq "R-006: workflow-advance reads .correctless/config/workflow-config.json" "true" "$adv_config"

  # workflow-advance.sh should reference .correctless/artifacts/
  file_contains "$hooks_dir/workflow-advance.sh" '\.correctless/artifacts' \
    && local adv_artifacts="true" || local adv_artifacts="false"
  assert_eq "R-006: workflow-advance uses .correctless/artifacts/" "true" "$adv_artifacts"

  # workflow-gate.sh should reference .correctless/ paths
  file_contains "$hooks_dir/workflow-gate.sh" '\.correctless/config/workflow-config\.json' \
    && local gate_config="true" || local gate_config="false"
  assert_eq "R-006: workflow-gate reads .correctless/config/workflow-config.json" "true" "$gate_config"

  file_contains "$hooks_dir/workflow-gate.sh" '\.correctless/artifacts' \
    && local gate_artifacts="true" || local gate_artifacts="false"
  assert_eq "R-006: workflow-gate uses .correctless/artifacts/" "true" "$gate_artifacts"

  # audit-trail.sh should reference .correctless/ paths
  file_contains "$hooks_dir/audit-trail.sh" '\.correctless/artifacts' \
    && local audit_artifacts="true" || local audit_artifacts="false"
  assert_eq "R-006: audit-trail uses .correctless/artifacts/" "true" "$audit_artifacts"

  # statusline.sh should reference .correctless/ paths
  file_contains "$hooks_dir/statusline.sh" '\.correctless/artifacts' \
    && local sl_artifacts="true" || local sl_artifacts="false"
  assert_eq "R-006: statusline uses .correctless/artifacts/" "true" "$sl_artifacts"

  # B-02: audit-trail.sh should reference .correctless/config/workflow-config.json
  file_contains "$hooks_dir/audit-trail.sh" '\.correctless/config/workflow-config\.json' \
    && local audit_config="true" || local audit_config="false"
  assert_eq "R-006: audit-trail reads .correctless/config/workflow-config.json" "true" "$audit_config"

  # Note: statusline.sh does NOT read workflow-config.json — it receives JSON via stdin
  # and reads state files from .correctless/artifacts/. No config file reference needed.

  # None of the hooks should reference old .claude/artifacts or .claude/workflow-config
  for hook in workflow-advance.sh workflow-gate.sh audit-trail.sh statusline.sh; do
    file_not_contains "$hooks_dir/$hook" '\.claude/workflow-config\.json' \
      && local no_old_config="true" || local no_old_config="false"
    assert_eq "R-006: $hook does not reference .claude/workflow-config.json" "true" "$no_old_config"

    file_not_contains "$hooks_dir/$hook" '\.claude/artifacts' \
      && local no_old_artifacts="true" || local no_old_artifacts="false"
    assert_eq "R-006: $hook does not reference .claude/artifacts" "true" "$no_old_artifacts"
  done

  # B-02: Integration test — hook actually reads from .correctless/ paths at runtime
  setup_test_project
  .claude/skills/workflow/setup >/dev/null 2>&1

  # Create a workflow state file at the new path
  mkdir -p .correctless/artifacts
  echo '{"phase": "spec", "slug": "test-int"}' > .correctless/artifacts/workflow-state-test-int.json

  # Invoke workflow-advance.sh status and verify it reads from new path
  local adv_output
  adv_output="$(.correctless/hooks/workflow-advance.sh status 2>&1 || true)"
  # The hook should produce output referencing the state (not error about missing file)
  # If it reads from old path it will not find the state file
  assert_not_contains "R-006: integration — hook does not error about missing .claude/ path" \
    "\.claude/artifacts" "$adv_output"
}

# ---------------------------------------------------------------------------
# Test: R-007 — workflow-advance writes to .correctless/specs/ and
#               .correctless/verification/
# ---------------------------------------------------------------------------

test_r007() {
  echo ""
  echo "=== R-007: workflow-advance writes specs/verification to .correctless/ ==="

  # Tests R-007 [integration]: spec and verification paths in workflow-advance.sh
  local adv="$REPO_DIR/hooks/workflow-advance.sh"

  # Should reference .correctless/specs/
  file_contains "$adv" '\.correctless/specs/' \
    && local has_specs="true" || local has_specs="false"
  assert_eq "R-007: workflow-advance references .correctless/specs/" "true" "$has_specs"

  # Should reference .correctless/verification/
  file_contains "$adv" '\.correctless/verification/' \
    && local has_ver="true" || local has_ver="false"
  assert_eq "R-007: workflow-advance references .correctless/verification/" "true" "$has_ver"

  # Should NOT reference docs/specs/ as an artifact path
  file_not_contains "$adv" 'docs/specs/' \
    && local no_old_specs="true" || local no_old_specs="false"
  assert_eq "R-007: workflow-advance does not reference docs/specs/" "true" "$no_old_specs"

  # Should NOT reference docs/verification/
  file_not_contains "$adv" 'docs/verification/' \
    && local no_old_ver="true" || local no_old_ver="false"
  assert_eq "R-007: workflow-advance does not reference docs/verification/" "true" "$no_old_ver"

  # B-03: Integration test — workflow-advance start creates spec at .correctless/specs/
  setup_test_project
  .claude/skills/workflow/setup >/dev/null 2>&1

  # Create a feature branch so workflow-advance can derive a slug
  git checkout -q -b feature/test-spec-path
  # Start workflow — should create spec file at .correctless/specs/
  .correctless/hooks/workflow-advance.sh start "test-spec-path" >/dev/null 2>&1 || true

  # Assert spec created at new path, not old path
  local spec_at_new
  spec_at_new="$(find .correctless/specs/ -name '*.md' 2>/dev/null | wc -l | tr -d ' ')"
  assert_eq "R-007: integration — spec created under .correctless/specs/" "true" \
    "$([ "$spec_at_new" -ge 1 ] && echo true || echo false)"

  local spec_at_old
  spec_at_old="$(find docs/specs/ -name '*.md' 2>/dev/null | wc -l | tr -d ' ')"
  assert_eq "R-007: integration — no spec created under docs/specs/" "0" "$spec_at_old"

  git checkout -q main
}

# ---------------------------------------------------------------------------
# Test: R-008 — All SKILL.md files reference .correctless/ paths
# ---------------------------------------------------------------------------

test_r008() {
  echo ""
  echo "=== R-008: All SKILL.md files reference .correctless/ paths ==="

  # Tests R-008 [integration]: SKILL.md files use .correctless/ for all artifact paths
  local skills_dir="$REPO_DIR/skills"
  local fail_count_local=0

  # Check that no SKILL.md references old paths for Correctless artifacts
  for skill_dir in "$skills_dir"/*/; do
    local skill_file="$skill_dir/SKILL.md"
    [ -f "$skill_file" ] || continue
    local skill_name
    skill_name="$(basename "$skill_dir")"

    # Should not reference .claude/artifacts/ as Correctless artifact path
    if grep -q '\.claude/artifacts' "$skill_file" 2>/dev/null; then
      echo "  FAIL: R-008: $skill_name/SKILL.md references .claude/artifacts"
      FAIL=$((FAIL + 1))
      fail_count_local=$((fail_count_local + 1))
    fi

    # Should not reference .claude/workflow-config.json
    if grep -q '\.claude/workflow-config\.json' "$skill_file" 2>/dev/null; then
      echo "  FAIL: R-008: $skill_name/SKILL.md references .claude/workflow-config.json"
      FAIL=$((FAIL + 1))
      fail_count_local=$((fail_count_local + 1))
    fi

    # Should not reference .claude/antipatterns.md
    if grep -q '\.claude/antipatterns\.md' "$skill_file" 2>/dev/null; then
      echo "  FAIL: R-008: $skill_name/SKILL.md references .claude/antipatterns.md"
      FAIL=$((FAIL + 1))
      fail_count_local=$((fail_count_local + 1))
    fi

    # B-04: Should not reference docs/specs/ as Correctless artifact path
    # (docs/skills/ is fine — it's project docs, not generated artifacts)
    if grep -q 'docs/specs/' "$skill_file" 2>/dev/null; then
      echo "  FAIL: R-008: $skill_name/SKILL.md references docs/specs/ as artifact path"
      FAIL=$((FAIL + 1))
      fail_count_local=$((fail_count_local + 1))
    fi

    # B-04: Should not reference docs/verification/
    if grep -q 'docs/verification/' "$skill_file" 2>/dev/null; then
      echo "  FAIL: R-008: $skill_name/SKILL.md references docs/verification/"
      FAIL=$((FAIL + 1))
      fail_count_local=$((fail_count_local + 1))
    fi

    # B-04: Should not reference docs/decisions/
    if grep -q 'docs/decisions/' "$skill_file" 2>/dev/null; then
      echo "  FAIL: R-008: $skill_name/SKILL.md references docs/decisions/"
      FAIL=$((FAIL + 1))
      fail_count_local=$((fail_count_local + 1))
    fi

    # B-04: Should not reference bare ARCHITECTURE.md (without .correctless/ prefix)
    # Match "ARCHITECTURE.md" not preceded by ".correctless/" or "/"
    if grep -P '(?<!\.correctless/)(?<!/)ARCHITECTURE\.md' "$skill_file" 2>/dev/null | \
       grep -v '\.correctless/ARCHITECTURE\.md' >/dev/null 2>&1; then
      echo "  FAIL: R-008: $skill_name/SKILL.md references bare ARCHITECTURE.md"
      FAIL=$((FAIL + 1))
      fail_count_local=$((fail_count_local + 1))
    fi

    # B-04: Should not reference bare AGENT_CONTEXT.md (without .correctless/ prefix)
    if grep -P '(?<!\.correctless/)(?<!/)AGENT_CONTEXT\.md' "$skill_file" 2>/dev/null | \
       grep -v '\.correctless/AGENT_CONTEXT\.md' >/dev/null 2>&1; then
      echo "  FAIL: R-008: $skill_name/SKILL.md references bare AGENT_CONTEXT.md"
      FAIL=$((FAIL + 1))
      fail_count_local=$((fail_count_local + 1))
    fi
  done

  if [ "$fail_count_local" -eq 0 ]; then
    echo "  PASS: R-008: no SKILL.md references old .claude/ artifact paths"
    PASS=$((PASS + 1))
  fi

  # Positive check: at least some skill files should reference .correctless/ paths
  local correctless_ref_count=0
  for skill_dir in "$skills_dir"/*/; do
    local skill_file="$skill_dir/SKILL.md"
    [ -f "$skill_file" ] || continue
    if grep -q '\.correctless/' "$skill_file" 2>/dev/null; then
      correctless_ref_count=$((correctless_ref_count + 1))
    fi
  done

  assert_eq "R-008: at least 10 skills reference .correctless/ paths" "true" \
    "$([ "$correctless_ref_count" -ge 10 ] && echo true || echo false)"
}

# ---------------------------------------------------------------------------
# Test: R-009 — CLAUDE.md says "Read .correctless/AGENT_CONTEXT.md"
# ---------------------------------------------------------------------------

test_r009() {
  echo ""
  echo "=== R-009: CLAUDE.md says 'Read .correctless/AGENT_CONTEXT.md' ==="

  # Tests R-009 [integration]: setup writes correct CLAUDE.md reference
  setup_test_project
  .claude/skills/workflow/setup >/dev/null 2>&1

  if [ -f CLAUDE.md ]; then
    file_contains "CLAUDE.md" '\.correctless/AGENT_CONTEXT\.md' \
      && local has_new_ref="true" || local has_new_ref="false"
    assert_eq "R-009: CLAUDE.md references .correctless/AGENT_CONTEXT.md" "true" "$has_new_ref"

    # Should NOT say "Read AGENT_CONTEXT.md" (without .correctless/ prefix)
    # Use a pattern that matches the bare reference but not the .correctless/ one
    local bare_ref
    bare_ref="$(grep -c 'Read AGENT_CONTEXT\.md' CLAUDE.md 2>/dev/null)" || bare_ref=0
    local new_ref
    new_ref="$(grep -c 'Read \.correctless/AGENT_CONTEXT\.md' CLAUDE.md 2>/dev/null)" || new_ref=0
    # bare_ref counts both old and new-style, so subtract new_ref
    local old_only=$(( bare_ref - new_ref ))
    assert_eq "R-009: no bare 'Read AGENT_CONTEXT.md' reference" "0" "$old_only"
  else
    echo "  FAIL: R-009: CLAUDE.md was not created"
    FAIL=$((FAIL + 1))
  fi

  # QA-001: Migration updates stale CLAUDE.md path reference
  setup_test_project
  # Simulate existing install with old-style CLAUDE.md
  cat > CLAUDE.md <<'OLDCMD'
## Correctless Lite

This project uses Correctless Lite for structured development.
Read AGENT_CONTEXT.md before starting any work.
Available commands: /csetup, /cspec, /creview, /ctdd, /cverify
OLDCMD
  # Create old artifact so migration triggers
  mkdir -p .claude/artifacts
  echo '{}' > .claude/artifacts/old-state.json

  .claude/skills/workflow/setup >/dev/null 2>&1

  if [ -f CLAUDE.md ]; then
    file_contains "CLAUDE.md" 'Read \.correctless/AGENT_CONTEXT\.md' \
      && local migrated_ref="true" || local migrated_ref="false"
    assert_eq "R-009: migration updates CLAUDE.md to .correctless/AGENT_CONTEXT.md" "true" "$migrated_ref"

    # Count lines with bare "Read AGENT_CONTEXT.md" (not preceded by .correctless/)
    local old_bare_after
    old_bare_after="$(grep 'Read AGENT_CONTEXT\.md' CLAUDE.md 2>/dev/null | grep -cv '\.correctless/AGENT_CONTEXT\.md')" || old_bare_after=0
    assert_eq "R-009: migration leaves no bare AGENT_CONTEXT.md reference" "0" "$old_bare_after"
  else
    echo "  FAIL: R-009: CLAUDE.md missing after migration"
    FAIL=$((FAIL + 1))
  fi
}

# ---------------------------------------------------------------------------
# Test: R-010 — Migration moves old artifacts to new locations
# ---------------------------------------------------------------------------

test_r010() {
  echo ""
  echo "=== R-010: Migration moves old artifacts to new locations ==="

  # Tests R-010 [integration]: setup detects old locations and migrates
  setup_test_project

  # Create old-style artifacts to migrate
  mkdir -p .claude/artifacts
  echo '{"phase": "spec"}' > .claude/artifacts/workflow-state-test.json
  echo '{}' > .claude/artifacts/qa-findings-test.json

  mkdir -p .claude
  echo '{"project": {"name": "test"}, "paths": {"specs": "docs/specs/"}}' > .claude/workflow-config.json

  echo "# Old antipatterns" > .claude/antipatterns.md

  mkdir -p .claude/meta
  echo '{}' > .claude/meta/drift-debt.json

  mkdir -p docs/specs
  echo "# Old spec" > docs/specs/my-feature.md

  mkdir -p docs/verification
  echo "# Old verification" > docs/verification/my-feature-verification.md

  mkdir -p docs/decisions
  echo "# Old decisions" > docs/decisions/DECISIONS.md

  # Create Correctless-marked root docs (should be moved)
  echo "# Architecture -- {PROJECT_NAME}" > ARCHITECTURE.md
  echo "# Agent Context -- {PROJECT_NAME}" > AGENT_CONTEXT.md

  # Create old-style hooks
  mkdir -p .claude/hooks
  echo "#!/bin/bash" > .claude/hooks/workflow-gate.sh
  echo "#!/bin/bash" > .claude/hooks/workflow-advance.sh
  echo "#!/bin/bash" > .claude/hooks/audit-trail.sh
  echo "#!/bin/bash" > .claude/hooks/statusline.sh

  # Run setup (should migrate)
  .claude/skills/workflow/setup >/dev/null 2>&1

  # Verify migration: workflow-config.json
  assert_eq "R-010: workflow-config migrated to .correctless/config/" "true" \
    "$([ -f .correctless/config/workflow-config.json ] && echo true || echo false)"

  # Verify migration: artifacts
  assert_eq "R-010: artifacts migrated to .correctless/artifacts/" "true" \
    "$([ -f .correctless/artifacts/workflow-state-test.json ] && echo true || echo false)"
  assert_eq "R-010: qa-findings migrated" "true" \
    "$([ -f .correctless/artifacts/qa-findings-test.json ] && echo true || echo false)"

  # Verify migration: antipatterns
  assert_eq "R-010: antipatterns migrated to .correctless/" "true" \
    "$([ -f .correctless/antipatterns.md ] && echo true || echo false)"

  # Verify migration: meta
  assert_eq "R-010: meta migrated to .correctless/meta/" "true" \
    "$([ -f .correctless/meta/drift-debt.json ] && echo true || echo false)"

  # Verify migration: specs
  assert_eq "R-010: specs migrated to .correctless/specs/" "true" \
    "$([ -f .correctless/specs/my-feature.md ] && echo true || echo false)"

  # Verify migration: verification
  assert_eq "R-010: verification migrated to .correctless/verification/" "true" \
    "$([ -f .correctless/verification/my-feature-verification.md ] && echo true || echo false)"

  # Verify migration: decisions
  assert_eq "R-010: decisions migrated to .correctless/decisions/" "true" \
    "$([ -f .correctless/decisions/DECISIONS.md ] && echo true || echo false)"

  # Verify migration: Correctless-marked root docs (has template placeholders)
  assert_eq "R-010: ARCHITECTURE.md (with markers) migrated to .correctless/" "true" \
    "$([ -f .correctless/ARCHITECTURE.md ] && echo true || echo false)"
  assert_eq "R-010: AGENT_CONTEXT.md (with markers) migrated to .correctless/" "true" \
    "$([ -f .correctless/AGENT_CONTEXT.md ] && echo true || echo false)"

  # Verify migration: hooks
  assert_eq "R-010: workflow-gate hook migrated to .correctless/hooks/" "true" \
    "$([ -f .correctless/hooks/workflow-gate.sh ] && echo true || echo false)"
  assert_eq "R-010: workflow-advance hook migrated to .correctless/hooks/" "true" \
    "$([ -f .correctless/hooks/workflow-advance.sh ] && echo true || echo false)"
  assert_eq "R-010: audit-trail hook migrated to .correctless/hooks/" "true" \
    "$([ -f .correctless/hooks/audit-trail.sh ] && echo true || echo false)"
  assert_eq "R-010: statusline hook migrated to .correctless/hooks/" "true" \
    "$([ -f .correctless/hooks/statusline.sh ] && echo true || echo false)"

  # Verify content preserved
  if [ -f .correctless/antipatterns.md ]; then
    file_contains ".correctless/antipatterns.md" "Old antipatterns" \
      && local content_ok="true" || local content_ok="false"
    assert_eq "R-010: migrated antipatterns content preserved" "true" "$content_ok"
  fi

  # B-05: Verify config content preserved (project.name field survives migration)
  if [ -f .correctless/config/workflow-config.json ]; then
    local proj_name
    proj_name="$(jq -r '.project.name' .correctless/config/workflow-config.json 2>/dev/null || echo "")"
    assert_eq "R-010: migrated config preserves project.name" "test" "$proj_name"
  else
    echo "  FAIL: R-010: config not found for content preservation check"
    FAIL=$((FAIL + 1))
  fi

  # B-05: Verify spec file content preserved
  if [ -f .correctless/specs/my-feature.md ]; then
    file_contains ".correctless/specs/my-feature.md" "Old spec" \
      && local spec_ok="true" || local spec_ok="false"
    assert_eq "R-010: migrated spec content preserved" "true" "$spec_ok"
  else
    echo "  FAIL: R-010: spec not found for content preservation check"
    FAIL=$((FAIL + 1))
  fi

  # B-05: Verify artifact content preserved (workflow-state)
  if [ -f .correctless/artifacts/workflow-state-test.json ]; then
    local ws_phase
    ws_phase="$(jq -r '.phase' .correctless/artifacts/workflow-state-test.json 2>/dev/null || echo "")"
    assert_eq "R-010: migrated workflow-state preserves phase field" "spec" "$ws_phase"
  else
    echo "  FAIL: R-010: workflow-state not found for content preservation check"
    FAIL=$((FAIL + 1))
  fi

  # B-05: Verify hook file content preserved
  if [ -f .correctless/hooks/workflow-gate.sh ]; then
    file_contains ".correctless/hooks/workflow-gate.sh" "#!/bin/bash" \
      && local hook_ok="true" || local hook_ok="false"
    assert_eq "R-010: migrated hook content preserved" "true" "$hook_ok"
  else
    echo "  FAIL: R-010: workflow-gate hook not found for content preservation check"
    FAIL=$((FAIL + 1))
  fi

  # Pre-existing ARCHITECTURE.md without Correctless markers should stay
  setup_test_project
  echo "# My Project Architecture" > ARCHITECTURE.md
  echo "This is my own doc." >> ARCHITECTURE.md
  .claude/skills/workflow/setup >/dev/null 2>&1

  assert_eq "R-010: pre-existing ARCHITECTURE.md (no markers) stays at root" "true" \
    "$([ -f ARCHITECTURE.md ] && echo true || echo false)"
  # A fresh copy should still be created in .correctless/
  assert_eq "R-010: fresh ARCHITECTURE.md created in .correctless/ alongside root" "true" \
    "$([ -f .correctless/ARCHITECTURE.md ] && echo true || echo false)"

  # B-06: Negative case — AGENT_CONTEXT.md without Correctless markers should NOT be moved
  setup_test_project
  echo "# Agent Context" > AGENT_CONTEXT.md
  echo "This is a custom agent context I wrote myself." >> AGENT_CONTEXT.md
  local original_content
  original_content="$(cat AGENT_CONTEXT.md)"
  .claude/skills/workflow/setup >/dev/null 2>&1

  assert_eq "R-010: pre-existing AGENT_CONTEXT.md (no markers) stays at root" "true" \
    "$([ -f AGENT_CONTEXT.md ] && echo true || echo false)"

  # B-06: Root file content should be unchanged (not overwritten by template)
  local post_setup_content
  post_setup_content="$(cat AGENT_CONTEXT.md 2>/dev/null || echo "")"
  assert_eq "R-010: root AGENT_CONTEXT.md content unchanged after setup" \
    "$original_content" "$post_setup_content"

  # B-06: Root ARCHITECTURE.md content also unchanged
  setup_test_project
  echo "# My Architecture" > ARCHITECTURE.md
  echo "Custom content not from Correctless." >> ARCHITECTURE.md
  local arch_original
  arch_original="$(cat ARCHITECTURE.md)"
  .claude/skills/workflow/setup >/dev/null 2>&1
  local arch_after
  arch_after="$(cat ARCHITECTURE.md 2>/dev/null || echo "")"
  assert_eq "R-010: root ARCHITECTURE.md content unchanged after setup" \
    "$arch_original" "$arch_after"

  # QA-003: migrate_dir handles pre-existing subdirectories (interrupted setup)
  setup_test_project
  # Create old artifacts with a subdirectory containing a file
  mkdir -p .claude/artifacts/research
  echo "research notes here" > .claude/artifacts/research/somefile.txt
  # Pre-create the destination subdirectory (simulates interrupted first run)
  mkdir -p .correctless/artifacts/research
  # Run setup (migration should recurse into the subdirectory)
  .claude/skills/workflow/setup >/dev/null 2>&1

  assert_eq "R-010: QA-003 subdirectory file migrated despite pre-existing dest dir" "true" \
    "$([ -f .correctless/artifacts/research/somefile.txt ] && echo true || echo false)"
  if [ -f .correctless/artifacts/research/somefile.txt ]; then
    file_contains ".correctless/artifacts/research/somefile.txt" "research notes here" \
      && local subdir_content="true" || local subdir_content="false"
    assert_eq "R-010: QA-003 subdirectory file content preserved" "true" "$subdir_content"
  fi
}

# ---------------------------------------------------------------------------
# Test: R-011 — Migration is idempotent
# ---------------------------------------------------------------------------

test_r011() {
  echo ""
  echo "=== R-011: Migration is idempotent ==="

  # Tests R-011 [integration]: running setup twice does not duplicate or corrupt
  setup_test_project

  # Create old artifacts
  mkdir -p .claude/artifacts
  echo '{"phase": "done"}' > .claude/artifacts/workflow-state-idem.json
  echo '{"project": {"name": "idem"}}' > .claude/workflow-config.json
  echo "# Antipatterns" > .claude/antipatterns.md

  # First run
  .claude/skills/workflow/setup >/dev/null 2>&1

  # Capture state after first run
  local config_after_first=""
  if [ -f .correctless/config/workflow-config.json ]; then
    config_after_first="$(cat .correctless/config/workflow-config.json)"
  fi

  # Second run
  .claude/skills/workflow/setup >/dev/null 2>&1

  # Verify no duplication
  if [ -f .correctless/config/workflow-config.json ]; then
    local config_after_second
    config_after_second="$(cat .correctless/config/workflow-config.json)"
    assert_eq "R-011: config unchanged after second run" "$config_after_first" "$config_after_second"
  else
    echo "  FAIL: R-011: config not found after second run"
    FAIL=$((FAIL + 1))
  fi

  # Verify artifacts not duplicated
  local artifact_count
  artifact_count="$(find .correctless/artifacts/ -name 'workflow-state-idem.json' 2>/dev/null | wc -l | tr -d ' ')"
  assert_eq "R-011: exactly one state file after two runs" "1" "$artifact_count"

  # B-07: antipatterns.md content unchanged across two runs
  local antipatterns_after_first=""
  if [ -f .correctless/antipatterns.md ]; then
    antipatterns_after_first="$(cat .correctless/antipatterns.md)"
  fi
  # Third run to compare against second
  .claude/skills/workflow/setup >/dev/null 2>&1
  local antipatterns_after_third=""
  if [ -f .correctless/antipatterns.md ]; then
    antipatterns_after_third="$(cat .correctless/antipatterns.md)"
  fi
  assert_eq "R-011: antipatterns.md unchanged after re-run" \
    "$antipatterns_after_first" "$antipatterns_after_third"

  # B-07: hook file content unchanged across runs
  local hook_after_second=""
  # Re-read after second run (already ran above)
  if [ -f .correctless/hooks/workflow-gate.sh ]; then
    hook_after_second="$(cat .correctless/hooks/workflow-gate.sh)"
  fi
  .claude/skills/workflow/setup >/dev/null 2>&1
  local hook_after_fourth=""
  if [ -f .correctless/hooks/workflow-gate.sh ]; then
    hook_after_fourth="$(cat .correctless/hooks/workflow-gate.sh)"
  fi
  assert_eq "R-011: workflow-gate.sh unchanged after re-run" \
    "$hook_after_second" "$hook_after_fourth"

  # B-07: file count in .correctless/artifacts/ unchanged between runs
  local count_before
  count_before="$(find .correctless/artifacts/ -type f 2>/dev/null | wc -l | tr -d ' ')"
  .claude/skills/workflow/setup >/dev/null 2>&1
  local count_after
  count_after="$(find .correctless/artifacts/ -type f 2>/dev/null | wc -l | tr -d ' ')"
  assert_eq "R-011: artifact file count unchanged after re-run" "$count_before" "$count_after"
}

# ---------------------------------------------------------------------------
# Test: R-012 — Empty old directories removed after migration
# ---------------------------------------------------------------------------

test_r012() {
  echo ""
  echo "=== R-012: Empty old directories removed after migration ==="

  # Tests R-012 [integration]: old directories cleaned up if empty
  setup_test_project

  # Create old artifacts structure
  mkdir -p .claude/artifacts
  echo '{}' > .claude/artifacts/test-state.json
  echo '{}' > .claude/workflow-config.json
  mkdir -p docs/specs
  echo "# Spec" > docs/specs/test.md
  mkdir -p docs/verification
  echo "# Report" > docs/verification/test-verification.md
  mkdir -p docs/decisions
  echo "# Decisions" > docs/decisions/DECISIONS.md

  # Run setup to trigger migration
  .claude/skills/workflow/setup >/dev/null 2>&1

  # .claude/artifacts/ should be removed if empty after migration
  assert_eq "R-012: .claude/artifacts/ removed after migration" "false" \
    "$([ -d .claude/artifacts ] && echo true || echo false)"

  # docs/specs/ should be removed if empty after migration
  assert_eq "R-012: docs/specs/ removed if empty after migration" "false" \
    "$([ -d docs/specs ] && echo true || echo false)"

  # docs/verification/ should be removed if empty after migration
  assert_eq "R-012: docs/verification/ removed if empty after migration" "false" \
    "$([ -d docs/verification ] && echo true || echo false)"

  # B-08: docs/decisions/ should be removed after migration empties it
  assert_eq "R-012: docs/decisions/ removed if empty after migration" "false" \
    "$([ -d docs/decisions ] && echo true || echo false)"

  # B-08: .claude/hooks/ should be removed after hook migration (if empty)
  # Set up a scenario where .claude/hooks/ only had Correctless hooks
  setup_test_project
  mkdir -p .claude/hooks
  echo '#!/bin/bash' > .claude/hooks/workflow-gate.sh
  echo '#!/bin/bash' > .claude/hooks/workflow-advance.sh
  echo '#!/bin/bash' > .claude/hooks/audit-trail.sh
  echo '#!/bin/bash' > .claude/hooks/statusline.sh
  echo '{}' > .claude/workflow-config.json
  .claude/skills/workflow/setup >/dev/null 2>&1

  assert_eq "R-012: .claude/hooks/ removed after all Correctless hooks migrated" "false" \
    "$([ -d .claude/hooks ] && echo true || echo false)"

  # B-08: .claude/meta/ should be removed after meta migration
  setup_test_project
  mkdir -p .claude/meta
  echo '{}' > .claude/meta/drift-debt.json
  echo '{}' > .claude/meta/workflow-effectiveness.json
  echo '{}' > .claude/workflow-config.json
  .claude/skills/workflow/setup >/dev/null 2>&1

  assert_eq "R-012: .claude/meta/ removed after migration" "false" \
    "$([ -d .claude/meta ] && echo true || echo false)"

  # Test: directory with non-Correctless content should NOT be removed
  setup_test_project
  mkdir -p docs/specs
  echo "# Spec" > docs/specs/test.md
  echo "# My other doc" > docs/my-other-doc.md  # Non-Correctless content in docs/
  mkdir -p docs/decisions
  echo "# Decisions" > docs/decisions/DECISIONS.md
  .claude/skills/workflow/setup >/dev/null 2>&1

  assert_eq "R-012: docs/ kept when it has non-Correctless content" "true" \
    "$([ -d docs ] && echo true || echo false)"
}

# ---------------------------------------------------------------------------
# Test: R-013 — .gitignore entries cleaned up
# ---------------------------------------------------------------------------

test_r013() {
  echo ""
  echo "=== R-013: .gitignore entries cleaned up ==="

  # Tests R-013 [integration]: old .gitignore entries removed
  setup_test_project

  # Create a .gitignore with old entries
  cat > .gitignore <<'EOF'
node_modules/
.claude/artifacts/
dist/
EOF

  .claude/skills/workflow/setup >/dev/null 2>&1

  # Old .claude/artifacts/ entry should be removed
  file_not_contains ".gitignore" '\.claude/artifacts/' \
    && local no_old="true" || local no_old="false"
  assert_eq "R-013: .gitignore no longer has .claude/artifacts/" "true" "$no_old"

  # Non-Correctless entries should remain
  file_contains ".gitignore" 'node_modules/' \
    && local kept="true" || local kept="false"
  assert_eq "R-013: .gitignore keeps non-Correctless entries" "true" "$kept"
}

# ---------------------------------------------------------------------------
# Test: R-014 — paths section stripped from migrated configs
# ---------------------------------------------------------------------------

test_r014() {
  echo ""
  echo "=== R-014: paths section stripped from migrated configs ==="

  # Tests R-014 [integration]: migration removes paths section from config
  setup_test_project

  # Create old config WITH paths section
  mkdir -p .claude
  cat > .claude/workflow-config.json <<'EOF'
{
  "project": {"name": "test", "language": "typescript"},
  "commands": {"test": "npm test"},
  "patterns": {"test_file": "*.test.ts"},
  "is_monorepo": false,
  "workflow": {"min_qa_rounds": 1},
  "paths": {
    "architecture_doc": "ARCHITECTURE.md",
    "specs": "docs/specs/",
    "artifacts": ".claude/artifacts/"
  }
}
EOF

  .claude/skills/workflow/setup >/dev/null 2>&1

  # After migration, config should exist at new location without paths
  if [ -f .correctless/config/workflow-config.json ]; then
    local has_paths
    has_paths="$(jq 'has("paths")' .correctless/config/workflow-config.json 2>/dev/null || echo "error")"
    assert_eq "R-014: migrated config has no paths section" "false" "$has_paths"

    # Verify other fields preserved
    local has_project
    has_project="$(jq 'has("project")' .correctless/config/workflow-config.json 2>/dev/null || echo "error")"
    assert_eq "R-014: migrated config preserves project section" "true" "$has_project"
  else
    echo "  FAIL: R-014: config not migrated to .correctless/config/"
    FAIL=$((FAIL + 1))
  fi
}

# ---------------------------------------------------------------------------
# Test: R-015 — sync.sh propagates changes, no old path references
# ---------------------------------------------------------------------------

test_r015() {
  echo ""
  echo "=== R-015: sync.sh propagates, no old path references in distributions ==="

  # Tests R-015 [integration]: after sync, no old paths in distributions
  # Run sync first
  cd "$REPO_DIR" && bash sync.sh >/dev/null 2>&1

  # Check that no distribution file references old paths
  # B-09: Added .claude/hooks/ to old path patterns
  local old_path_patterns=('.claude/artifacts' '.claude/workflow-config' '.claude/antipatterns' 'docs/specs/' 'docs/verification/' 'docs/decisions/' '.claude/hooks/')

  if [ -d "$REPO_DIR/correctless" ]; then
    for pattern in "${old_path_patterns[@]}"; do
      local found
      found="$(grep -rl "$pattern" "$REPO_DIR/correctless" 2>/dev/null | head -1 || true)"
      if [ -n "$found" ]; then
        echo "  FAIL: R-015: correctless/ contains old path '$pattern' in $(basename "$found")"
        FAIL=$((FAIL + 1))
      fi
    done
  fi

  # Count remaining old path references in the single distribution
  local old_refs=0
  for pattern in "${old_path_patterns[@]}"; do
    old_refs=$((old_refs + $(grep -rl "$pattern" "$REPO_DIR/correctless" 2>/dev/null | wc -l)))
  done

  assert_eq "R-015: correctless/ has zero old path references" "0" "$old_refs"
}

# ---------------------------------------------------------------------------
# Test: R-016 — All existing tests pass with updated assertions
# ---------------------------------------------------------------------------

test_r016() {
  echo ""
  echo "=== R-016: Existing tests use .correctless/ paths ==="

  # Tests R-016 [integration]: existing tests updated to use new paths
  # Check that test.sh references .correctless/ paths instead of .claude/artifacts/ etc.
  local test_file="$REPO_DIR/tests/test.sh"

  # The main test file should NOT reference .claude/artifacts/ for assertions
  # (It may reference .claude/settings.json which is fine — that stays)
  file_not_contains "$test_file" '\.claude/artifacts' \
    && local no_old_artifacts="true" || local no_old_artifacts="false"
  assert_eq "R-016: test.sh does not reference .claude/artifacts" "true" "$no_old_artifacts"

  file_not_contains "$test_file" '\.claude/workflow-config' \
    && local no_old_config="true" || local no_old_config="false"
  assert_eq "R-016: test.sh does not reference .claude/workflow-config" "true" "$no_old_config"

  # test.sh should reference .correctless/ paths for assertions
  file_contains "$test_file" '\.correctless/' \
    && local has_new="true" || local has_new="false"
  assert_eq "R-016: test.sh references .correctless/ paths" "true" "$has_new"
}

# ---------------------------------------------------------------------------
# Test: R-017 — setup installs hooks to .correctless/hooks/
# ---------------------------------------------------------------------------

test_r017() {
  echo ""
  echo "=== R-017: setup installs hooks to .correctless/hooks/ ==="

  # Tests R-017 [integration]: hooks installed to .correctless/hooks/
  setup_test_project
  .claude/skills/workflow/setup >/dev/null 2>&1

  # Hook files should exist in .correctless/hooks/
  for hook in workflow-gate.sh workflow-advance.sh audit-trail.sh statusline.sh; do
    assert_eq "R-017: .correctless/hooks/$hook exists" "true" \
      "$([ -f .correctless/hooks/$hook ] && echo true || echo false)"
  done

  # Hook files should NOT exist in .claude/hooks/ (for fresh install)
  for hook in workflow-gate.sh workflow-advance.sh audit-trail.sh statusline.sh; do
    assert_eq "R-017: .claude/hooks/$hook does NOT exist (fresh)" "false" \
      "$([ -f .claude/hooks/$hook ] && echo true || echo false)"
  done

  # settings.json should reference .correctless/hooks/ paths
  if [ -f .claude/settings.json ]; then
    file_contains ".claude/settings.json" '\.correctless/hooks/workflow-gate\.sh' \
      && local gate_ref="true" || local gate_ref="false"
    assert_eq "R-017: settings.json references .correctless/hooks/workflow-gate.sh" "true" "$gate_ref"

    file_contains ".claude/settings.json" '\.correctless/hooks/audit-trail\.sh' \
      && local audit_ref="true" || local audit_ref="false"
    assert_eq "R-017: settings.json references .correctless/hooks/audit-trail.sh" "true" "$audit_ref"

    file_contains ".claude/settings.json" '\.correctless/hooks/statusline\.sh' \
      && local sl_ref="true" || local sl_ref="false"
    assert_eq "R-017: settings.json references .correctless/hooks/statusline.sh" "true" "$sl_ref"

    file_contains ".claude/settings.json" '\.correctless/hooks/workflow-advance\.sh' \
      && local adv_ref="true" || local adv_ref="false"
    assert_eq "R-017: settings.json permissions reference .correctless/hooks/workflow-advance.sh" "true" "$adv_ref"

    # Should NOT reference .claude/hooks/ in settings
    file_not_contains ".claude/settings.json" '\.claude/hooks/' \
      && local no_old_hooks="true" || local no_old_hooks="false"
    assert_eq "R-017: settings.json does not reference .claude/hooks/" "true" "$no_old_hooks"
  else
    echo "  FAIL: R-017: .claude/settings.json not created"
    FAIL=$((FAIL + 1))
  fi
}

# ---------------------------------------------------------------------------
# Test: R-018 — Migration moves hooks from .claude/hooks/ to .correctless/hooks/
# ---------------------------------------------------------------------------

test_r018() {
  echo ""
  echo "=== R-018: Migration moves hooks, updates settings.json ==="

  # Tests R-018 [integration]: hook migration + settings update
  setup_test_project

  # Create old-style hooks and settings
  mkdir -p .claude/hooks
  echo '#!/bin/bash' > .claude/hooks/workflow-gate.sh
  echo '#!/bin/bash' > .claude/hooks/workflow-advance.sh
  echo '#!/bin/bash' > .claude/hooks/audit-trail.sh
  echo '#!/bin/bash' > .claude/hooks/statusline.sh
  chmod +x .claude/hooks/*.sh

  # Create a non-Correctless hook that should be left alone
  echo '#!/bin/bash' > .claude/hooks/my-custom-hook.sh

  # Create old-style settings.json
  cat > .claude/settings.json <<'EOF'
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [{"type": "command", "command": ".claude/hooks/workflow-gate.sh"}]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [{"type": "command", "command": ".claude/hooks/audit-trail.sh"}]
      }
    ]
  },
  "statusLine": {"command": ".claude/hooks/statusline.sh"},
  "permissions": {"allow": ["Bash(.claude/hooks/workflow-advance.sh *)"]}
}
EOF

  .claude/skills/workflow/setup >/dev/null 2>&1

  # Correctless hooks should be in .correctless/hooks/
  assert_eq "R-018: workflow-gate migrated to .correctless/hooks/" "true" \
    "$([ -f .correctless/hooks/workflow-gate.sh ] && echo true || echo false)"

  # Non-Correctless hook should remain in .claude/hooks/
  assert_eq "R-018: custom hook left in .claude/hooks/" "true" \
    "$([ -f .claude/hooks/my-custom-hook.sh ] && echo true || echo false)"

  # Settings.json should now reference new paths
  if [ -f .claude/settings.json ]; then
    file_contains ".claude/settings.json" '\.correctless/hooks/workflow-gate\.sh' \
      && local new_gate="true" || local new_gate="false"
    assert_eq "R-018: settings.json updated to .correctless/hooks/workflow-gate.sh" "true" "$new_gate"

    file_not_contains ".claude/settings.json" '\.claude/hooks/workflow-gate\.sh' \
      && local no_old="true" || local no_old="false"
    assert_eq "R-018: settings.json no longer references .claude/hooks/workflow-gate.sh" "true" "$no_old"

    file_contains ".claude/settings.json" '\.correctless/hooks/workflow-advance\.sh' \
      && local new_adv="true" || local new_adv="false"
    assert_eq "R-018: settings.json permissions updated to .correctless/hooks/workflow-advance.sh" "true" "$new_adv"
  else
    echo "  FAIL: R-018: settings.json not found"
    FAIL=$((FAIL + 1))
  fi
}

# ---------------------------------------------------------------------------
# B-10: Test: R-017/R-018 convergence — fresh and migration produce same settings
# ---------------------------------------------------------------------------

test_r017_r018_convergence() {
  echo ""
  echo "=== R-017/R-018: Fresh install and migration produce same hook paths ==="

  # B-10: Fresh install — capture settings.json hook paths
  setup_test_project
  .claude/skills/workflow/setup >/dev/null 2>&1

  local fresh_settings=""
  if [ -f .claude/settings.json ]; then
    # Extract just the hook-related paths (normalize for comparison)
    fresh_settings="$(grep -o '\.correctless/hooks/[a-z-]*\.sh' .claude/settings.json 2>/dev/null | sort)"
  fi

  # Migration install — start from old-style paths
  setup_test_project
  mkdir -p .claude/hooks
  echo '#!/bin/bash' > .claude/hooks/workflow-gate.sh
  echo '#!/bin/bash' > .claude/hooks/workflow-advance.sh
  echo '#!/bin/bash' > .claude/hooks/audit-trail.sh
  echo '#!/bin/bash' > .claude/hooks/statusline.sh
  cat > .claude/settings.json <<'OLDSETTINGS'
{
  "hooks": {
    "PreToolUse": [
      {"matcher": "Edit|Write", "hooks": [{"type": "command", "command": ".claude/hooks/workflow-gate.sh"}]}
    ],
    "PostToolUse": [
      {"matcher": "Edit|Write", "hooks": [{"type": "command", "command": ".claude/hooks/audit-trail.sh"}]}
    ]
  },
  "statusLine": {"command": ".claude/hooks/statusline.sh"},
  "permissions": {"allow": ["Bash(.claude/hooks/workflow-advance.sh *)"]}
}
OLDSETTINGS
  .claude/skills/workflow/setup >/dev/null 2>&1

  local migration_settings=""
  if [ -f .claude/settings.json ]; then
    migration_settings="$(grep -o '\.correctless/hooks/[a-z-]*\.sh' .claude/settings.json 2>/dev/null | sort)"
  fi

  # Both should reference the same .correctless/hooks/ paths
  assert_eq "R-017/R-018: fresh and migration settings.json reference same hook paths" \
    "$fresh_settings" "$migration_settings"

  # Neither should contain old .claude/hooks/ references
  if [ -f .claude/settings.json ]; then
    file_not_contains ".claude/settings.json" '\.claude/hooks/' \
      && local no_old="true" || local no_old="false"
    assert_eq "R-017/R-018: migration settings.json has no .claude/hooks/ refs" "true" "$no_old"
  fi

  # QA-002: Matcher convergence — fresh and migration produce same matchers
  # Re-capture fresh install matchers
  setup_test_project
  .claude/skills/workflow/setup >/dev/null 2>&1
  local fresh_pre_matcher="" fresh_post_matcher=""
  if [ -f .claude/settings.json ]; then
    fresh_pre_matcher="$(jq -r '(.hooks.PreToolUse // [] | .[] | select(.hooks[]?.command | test("workflow-gate")) | .matcher) // ""' .claude/settings.json 2>/dev/null || echo "")"
    fresh_post_matcher="$(jq -r '(.hooks.PostToolUse // [] | .[] | select(.hooks[]?.command | test("audit-trail")) | .matcher) // ""' .claude/settings.json 2>/dev/null || echo "")"
  fi

  # Re-capture migration install matchers (start from old narrow matchers)
  setup_test_project
  mkdir -p .claude/hooks
  echo '#!/bin/bash' > .claude/hooks/workflow-gate.sh
  echo '#!/bin/bash' > .claude/hooks/workflow-advance.sh
  echo '#!/bin/bash' > .claude/hooks/audit-trail.sh
  echo '#!/bin/bash' > .claude/hooks/statusline.sh
  cat > .claude/settings.json <<'OLDNARROW'
{
  "hooks": {
    "PreToolUse": [
      {"matcher": "Edit|Write", "hooks": [{"type": "command", "command": ".claude/hooks/workflow-gate.sh"}]}
    ],
    "PostToolUse": [
      {"matcher": "Edit|Write", "hooks": [{"type": "command", "command": ".claude/hooks/audit-trail.sh"}]}
    ]
  },
  "statusLine": {"command": ".claude/hooks/statusline.sh"},
  "permissions": {"allow": ["Bash(.claude/hooks/workflow-advance.sh *)"]}
}
OLDNARROW
  .claude/skills/workflow/setup >/dev/null 2>&1
  local mig_pre_matcher="" mig_post_matcher=""
  if [ -f .claude/settings.json ]; then
    mig_pre_matcher="$(jq -r '(.hooks.PreToolUse // [] | .[] | select(.hooks[]?.command | test("workflow-gate")) | .matcher) // ""' .claude/settings.json 2>/dev/null || echo "")"
    mig_post_matcher="$(jq -r '(.hooks.PostToolUse // [] | .[] | select(.hooks[]?.command | test("audit-trail")) | .matcher) // ""' .claude/settings.json 2>/dev/null || echo "")"
  fi

  assert_eq "R-017/R-018: QA-002 PreToolUse matcher same after migration vs fresh" \
    "$fresh_pre_matcher" "$mig_pre_matcher"
  assert_eq "R-017/R-018: QA-002 PostToolUse matcher same after migration vs fresh" \
    "$fresh_post_matcher" "$mig_post_matcher"

  # QA-009: Pre-audit-trail install — only gate+advance+statusline, no audit-trail
  # Matcher should still be updated to the full version
  setup_test_project
  mkdir -p .claude/hooks
  echo '#!/bin/bash' > .claude/hooks/workflow-gate.sh
  echo '#!/bin/bash' > .claude/hooks/workflow-advance.sh
  echo '#!/bin/bash' > .claude/hooks/statusline.sh
  # No audit-trail.sh — simulates pre-audit-trail install
  cat > .claude/settings.json <<'PREAUDIT'
{
  "hooks": {
    "PreToolUse": [
      {"matcher": "Edit|Write", "hooks": [{"type": "command", "command": ".claude/hooks/workflow-gate.sh"}]}
    ]
  },
  "statusLine": {"command": ".claude/hooks/statusline.sh"},
  "permissions": {"allow": ["Bash(.claude/hooks/workflow-advance.sh *)"]}
}
PREAUDIT
  .claude/skills/workflow/setup >/dev/null 2>&1
  local preaudit_pre_matcher=""
  if [ -f .claude/settings.json ]; then
    preaudit_pre_matcher="$(jq -r '(.hooks.PreToolUse // [] | .[] | select(.hooks[]?.command | test("workflow-gate")) | .matcher) // ""' .claude/settings.json 2>/dev/null || echo "")"
  fi
  assert_eq "R-017/R-018: QA-009 pre-audit-trail install gets full PreToolUse matcher" \
    "$fresh_pre_matcher" "$preaudit_pre_matcher"
}

# ---------------------------------------------------------------------------
# Test: R-019 — All SKILL.md files invoke hooks from .correctless/hooks/
# ---------------------------------------------------------------------------

test_r019() {
  echo ""
  echo "=== R-019: All SKILL.md files invoke hooks from .correctless/hooks/ ==="

  # Tests R-019 [integration]: no SKILL.md invokes hooks from .claude/hooks/
  local skills_dir="$REPO_DIR/skills"
  local old_hook_ref_count=0

  for skill_dir in "$skills_dir"/*/; do
    local skill_file="$skill_dir/SKILL.md"
    [ -f "$skill_file" ] || continue
    local skill_name
    skill_name="$(basename "$skill_dir")"

    if grep -q '\.claude/hooks/' "$skill_file" 2>/dev/null; then
      echo "  FAIL: R-019: $skill_name/SKILL.md invokes hooks from .claude/hooks/"
      FAIL=$((FAIL + 1))
      old_hook_ref_count=$((old_hook_ref_count + 1))
    fi
  done

  if [ "$old_hook_ref_count" -eq 0 ]; then
    echo "  PASS: R-019: no source SKILL.md invokes hooks from .claude/hooks/"
    PASS=$((PASS + 1))
  fi

  # Also check distribution directory after sync
  cd "$REPO_DIR" && bash sync.sh >/dev/null 2>&1

  local dist_dir="$REPO_DIR/correctless/skills"
  if [ -d "$dist_dir" ]; then
    local dist_old_refs
    dist_old_refs="$(grep -rl '\.claude/hooks/' "$dist_dir" 2>/dev/null | wc -l | tr -d ' ')"
    assert_eq "R-019: correctless/ skills have zero .claude/hooks/ references" "0" "$dist_old_refs"
  fi
}

# ---------------------------------------------------------------------------
# Test: R-020 — Project documentation updated with .correctless/ paths
# ---------------------------------------------------------------------------

test_r020() {
  echo ""
  echo "=== R-020: Project docs use .correctless/ paths ==="

  # Tests R-020 [integration]: documentation files reference .correctless/ layout
  # B-11: Check ALL old-path patterns across ALL documentation files

  local doc_files=(
    "$REPO_DIR/docs/design/correctless.md"
    "$REPO_DIR/README.md"
    "$REPO_DIR/CONTRIBUTING.md"
    "$REPO_DIR/templates/AGENT_CONTEXT.md"
    "$REPO_DIR/templates/ARCHITECTURE.md"
  )

  local old_patterns=(
    '.claude/hooks/'
    '.claude/workflow-config'
    '.claude/antipatterns'
    '.claude/artifacts'
    'docs/specs/'
    'docs/verification/'
    'docs/decisions/'
  )

  for doc_file in "${doc_files[@]}"; do
    [ -f "$doc_file" ] || continue
    local doc_name
    doc_name="$(basename "$doc_file")"
    # Use parent dir for templates/ disambiguation
    if [[ "$doc_file" == */templates/* ]]; then
      doc_name="templates/$doc_name"
    fi

    for pattern in "${old_patterns[@]}"; do
      file_not_contains "$doc_file" "$pattern" \
        && local result="true" || local result="false"
      assert_eq "R-020: $doc_name no '$pattern' reference" "true" "$result"
    done
  done
}

# ---------------------------------------------------------------------------
# Run all tests
# ---------------------------------------------------------------------------

trap cleanup EXIT

echo "Correctless Consolidation Test Suite"
echo "====================================="

test_r001
test_r002
test_r003
test_r004
test_r005
test_r006
test_r007
test_r008
test_r009
test_r010
test_r011
test_r012
test_r013
test_r014
test_r015
test_r016
test_r017
test_r018
test_r017_r018_convergence
test_r019
test_r020

echo ""
echo "====================================="
echo "Results: $PASS passed, $FAIL failed"
echo ""

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
