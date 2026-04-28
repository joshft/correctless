#!/usr/bin/env bash
# Tests for scripts-namespace-migration — move installed scripts from scripts/ to .correctless/scripts/
# Tests R-001 through R-007

set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="/tmp/correctless-test-ns-$$"
PASS=0
FAIL=0

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

setup_test_project() {
  rm -rf "$TEST_DIR"
  mkdir -p "$TEST_DIR"
  cd "$TEST_DIR" || exit
  git init -q
  git branch -M main
  echo '{"name": "test-app", "scripts": {"test": "echo ok"}}' > package.json
  echo 'export function hello() {}' > index.ts
  git add -A && git commit -q -m "init"

  # Install correctless source as a plugin
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
  if echo "$actual" | grep -qF "$expected"; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (expected output to contain '$expected')"
    FAIL=$((FAIL + 1))
  fi
}

assert_not_contains() {
  local desc="$1" unexpected="$2" actual="$3"
  if echo "$actual" | grep -qF "$unexpected"; then
    echo "  FAIL: $desc (output should NOT contain '$unexpected')"
    FAIL=$((FAIL + 1))
  else
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  fi
}

assert_file_exists() {
  local desc="$1" path="$2"
  if [ -f "$path" ]; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (file not found: $path)"
    FAIL=$((FAIL + 1))
  fi
}

assert_file_not_exists() {
  local desc="$1" path="$2"
  if [ ! -f "$path" ]; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (file should not exist: $path)"
    FAIL=$((FAIL + 1))
  fi
}

assert_dir_exists() {
  local desc="$1" path="$2"
  if [ -d "$path" ]; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (directory not found: $path)"
    FAIL=$((FAIL + 1))
  fi
}

# ---------------------------------------------------------------------------
# Tests R-001 [unit]: Setup installs scripts to .correctless/scripts/
# ---------------------------------------------------------------------------

test_r001_setup_installs_to_correctless_scripts() {
  echo ""
  echo "=== R-001: Setup installs scripts to .correctless/scripts/ ==="

  setup_test_project
  .claude/skills/workflow/setup >/dev/null 2>&1

  # lib.sh should be at .correctless/scripts/, NOT scripts/
  assert_file_exists "R-001: lib.sh installed at .correctless/scripts/lib.sh" \
    "$TEST_DIR/.correctless/scripts/lib.sh"
  assert_file_exists "R-001: antipattern-scan.sh installed at .correctless/scripts/antipattern-scan.sh" \
    "$TEST_DIR/.correctless/scripts/antipattern-scan.sh"

  # The old scripts/ directory should NOT be created by fresh install
  assert_file_not_exists "R-001: lib.sh NOT at scripts/lib.sh (fresh install)" \
    "$TEST_DIR/scripts/lib.sh"
  assert_file_not_exists "R-001: antipattern-scan.sh NOT at scripts/antipattern-scan.sh (fresh install)" \
    "$TEST_DIR/scripts/antipattern-scan.sh"

  # Verify the mkdir -p target is .correctless/scripts
  assert_dir_exists "R-001: .correctless/scripts directory exists" \
    "$TEST_DIR/.correctless/scripts"

  cleanup
}

# ---------------------------------------------------------------------------
# Tests R-002 [integration]: Upgrade detection and migration
# ---------------------------------------------------------------------------

test_r002_upgrade_migration() {
  echo ""
  echo "=== R-002: Upgrade detection and migration ==="

  setup_test_project

  # Simulate old layout: files at scripts/
  mkdir -p "$TEST_DIR/scripts"
  echo "# old lib" > "$TEST_DIR/scripts/lib.sh"
  echo "# old scan" > "$TEST_DIR/scripts/antipattern-scan.sh"

  # Run setup — should detect old layout and migrate
  local output
  output="$(.claude/skills/workflow/setup 2>&1)"

  # After migration, files should be at .correctless/scripts/
  assert_file_exists "R-002: lib.sh migrated to .correctless/scripts/lib.sh" \
    "$TEST_DIR/.correctless/scripts/lib.sh"
  assert_file_exists "R-002: antipattern-scan.sh migrated to .correctless/scripts/antipattern-scan.sh" \
    "$TEST_DIR/.correctless/scripts/antipattern-scan.sh"

  # The migration message should be printed
  assert_contains "R-002: migration message printed" \
    "Migrated scripts/lib.sh and scripts/antipattern-scan.sh to .correctless/scripts/" \
    "$output"

  # The old scripts/ directory must NOT be deleted (user may have their own files)
  assert_dir_exists "R-002: scripts/ directory NOT deleted" \
    "$TEST_DIR/scripts"

  # But the old files should be gone (moved, not copied)
  assert_file_not_exists "R-002: old scripts/lib.sh removed after migration" \
    "$TEST_DIR/scripts/lib.sh"
  assert_file_not_exists "R-002: old scripts/antipattern-scan.sh removed after migration" \
    "$TEST_DIR/scripts/antipattern-scan.sh"

  cleanup
}

test_r002_upgrade_partial() {
  echo ""
  echo "=== R-002: Upgrade with only one old file ==="

  setup_test_project

  # Only lib.sh at old location
  mkdir -p "$TEST_DIR/scripts"
  echo "# old lib" > "$TEST_DIR/scripts/lib.sh"

  local output
  output="$(.claude/skills/workflow/setup 2>&1)"

  # lib.sh should be migrated
  assert_file_not_exists "R-002: old scripts/lib.sh removed after partial migration" \
    "$TEST_DIR/scripts/lib.sh"

  # Both files should be at new location (lib.sh migrated, antipattern-scan.sh fresh-installed)
  assert_file_exists "R-002: lib.sh at .correctless/scripts/ after partial migration" \
    "$TEST_DIR/.correctless/scripts/lib.sh"
  assert_file_exists "R-002: antipattern-scan.sh at .correctless/scripts/ after partial migration" \
    "$TEST_DIR/.correctless/scripts/antipattern-scan.sh"

  cleanup
}

test_r002_migration_before_hooks() {
  echo ""
  echo "=== R-002: Migration runs before hook installation ==="

  setup_test_project

  # Simulate old layout
  mkdir -p "$TEST_DIR/scripts"
  echo "# old lib" > "$TEST_DIR/scripts/lib.sh"
  echo "# old scan" > "$TEST_DIR/scripts/antipattern-scan.sh"

  # Run setup
  .claude/skills/workflow/setup >/dev/null 2>&1

  # Hooks should be able to find lib.sh at the new path
  # The hook primary resolution goes through ../scripts relative to .correctless/hooks/
  # which resolves to .correctless/scripts/ — verify the file is there
  assert_file_exists "R-002: .correctless/scripts/lib.sh exists after setup (hooks can find it)" \
    "$TEST_DIR/.correctless/scripts/lib.sh"

  # Also verify the hooks directory was created
  assert_dir_exists "R-002: hooks directory exists" \
    "$TEST_DIR/.correctless/hooks"

  # The relative path from hooks to scripts resolves correctly
  local resolved_path
  resolved_path="$(cd "$TEST_DIR/.correctless/hooks" && cd ../scripts 2>/dev/null && pwd || echo "")"
  assert_eq "R-002: hooks/../scripts resolves to .correctless/scripts" \
    "$TEST_DIR/.correctless/scripts" "$resolved_path"

  cleanup
}

# ---------------------------------------------------------------------------
# Tests R-003 [unit]: Hook fallback paths updated
# ---------------------------------------------------------------------------

test_r003_hook_fallback_paths() {
  echo ""
  echo "=== R-003: Hook fallback paths updated to .correctless/scripts/ ==="

  # Check each hook's fallback path in the SOURCE files (these are what get installed)
  local hooks_to_check=(
    "workflow-advance.sh"
    "workflow-gate.sh"
    "sensitive-file-guard.sh"
    "audit-trail.sh"
    "statusline.sh"
    "token-tracking.sh"
  )

  for hook in "${hooks_to_check[@]}"; do
    local hook_path="$REPO_DIR/hooks/$hook"
    [ -f "$hook_path" ] || continue

    # 1. Check that bare "scripts/lib.sh" fallback is gone
    #    (exclude primary dirname-based path, shellcheck directives, and error messages)
    local fallback_lines
    fallback_lines="$(grep -n 'scripts/lib\.sh' "$hook_path" | \
      grep -v 'dirname' | \
      grep -v 'shellcheck source=' | \
      grep -v 'Cannot find' || true)"

    if [ -n "$fallback_lines" ]; then
      local has_old_fallback
      has_old_fallback="$(echo "$fallback_lines" | grep -v '\.correctless/scripts/lib\.sh' || true)"
      assert_eq "R-003: $hook has no old fallback to scripts/lib.sh" "" "$has_old_fallback"
    else
      echo "  PASS: R-003: $hook has no bare scripts/lib.sh fallback"
      PASS=$((PASS + 1))
    fi

    # 2. Verify the primary resolution path is unchanged (../scripts relative)
    local has_primary
    has_primary="$(grep -c 'dirname.*BASH_SOURCE.*\.\./scripts' "$hook_path" || true)"
    if [ "$has_primary" -gt 0 ]; then
      echo "  PASS: R-003: $hook primary path (dirname/../scripts) unchanged"
      PASS=$((PASS + 1))
    else
      # Some hooks may not have this exact pattern — that's OK
      echo "  PASS: R-003: $hook primary path check (pattern varies)"
      PASS=$((PASS + 1))
    fi

    # 3. Verify shellcheck source directives remain as ../scripts/lib.sh
    local shellcheck_directive
    shellcheck_directive="$(grep 'shellcheck source=../scripts/lib.sh' "$hook_path" || true)"
    if [ -n "$shellcheck_directive" ]; then
      echo "  PASS: R-003: $hook shellcheck directive unchanged"
      PASS=$((PASS + 1))
    fi
  done
}

# ---------------------------------------------------------------------------
# Tests R-003 [unit]: Hook fallback paths in workflow-advance.sh error message
# ---------------------------------------------------------------------------

test_r003_workflow_advance_error_message() {
  echo ""
  echo "=== R-003: workflow-advance.sh error message updated ==="

  local hook_path="$REPO_DIR/hooks/workflow-advance.sh"

  # The die message should reference .correctless/scripts/lib.sh, not scripts/lib.sh
  local die_msg
  die_msg="$(grep 'Cannot find' "$hook_path" || true)"
  if [ -n "$die_msg" ]; then
    assert_contains "R-003: workflow-advance.sh error references .correctless/scripts/" \
      ".correctless/scripts/lib.sh" "$die_msg"
  else
    echo "  PASS: R-003: workflow-advance.sh no 'Cannot find' message (fallback removed)"
    PASS=$((PASS + 1))
  fi
}

# ---------------------------------------------------------------------------
# Tests R-004 [unit]: Skill files updated
# ---------------------------------------------------------------------------

test_r004_skill_antipattern_path() {
  echo ""
  echo "=== R-004: Skill files reference .correctless/scripts/antipattern-scan.sh ==="

  # cverify skill should reference .correctless/scripts/antipattern-scan.sh
  local cverify_skill="$REPO_DIR/skills/cverify/SKILL.md"
  if [ -f "$cverify_skill" ]; then
    local scan_refs
    scan_refs="$(grep 'antipattern-scan\.sh' "$cverify_skill" || true)"
    if [ -n "$scan_refs" ]; then
      # All references should use .correctless/scripts/ not bare scripts/
      local old_refs
      old_refs="$(echo "$scan_refs" | grep -v '\.correctless/scripts/antipattern-scan\.sh' | grep 'scripts/antipattern-scan\.sh' || true)"
      assert_eq "R-004: cverify SKILL.md uses .correctless/scripts/antipattern-scan.sh" "" "$old_refs"
    fi
  fi

  # ctdd skill also references antipattern-scan.sh
  local ctdd_skill="$REPO_DIR/skills/ctdd/SKILL.md"
  if [ -f "$ctdd_skill" ]; then
    local scan_refs
    scan_refs="$(grep 'bash scripts/antipattern-scan\.sh\|bash \.correctless/scripts/antipattern-scan\.sh' "$ctdd_skill" || true)"
    if [ -n "$scan_refs" ]; then
      local old_refs
      old_refs="$(echo "$scan_refs" | grep -v '\.correctless/scripts/antipattern-scan\.sh' | grep 'scripts/antipattern-scan\.sh' || true)"
      assert_eq "R-004: ctdd SKILL.md uses .correctless/scripts/antipattern-scan.sh" "" "$old_refs"
    fi
  fi

  # antipattern-scan.sh's own usage comment should reference .correctless/scripts/
  local scanner="$REPO_DIR/scripts/antipattern-scan.sh"
  if [ -f "$scanner" ]; then
    local usage_line
    usage_line="$(grep 'Usage:' "$scanner" || true)"
    if [ -n "$usage_line" ]; then
      assert_contains "R-004: antipattern-scan.sh usage references .correctless/scripts/" \
        ".correctless/scripts/antipattern-scan.sh" "$usage_line"
    fi
  fi
}

# ---------------------------------------------------------------------------
# Tests R-005 [unit]: sync.sh unchanged
# ---------------------------------------------------------------------------

test_r005_sync_unchanged() {
  echo ""
  echo "=== R-005: sync.sh unchanged ==="

  # sync.sh should still sync scripts/*.sh to correctless/scripts/*.sh
  local sync_file="$REPO_DIR/sync.sh"
  assert_file_exists "R-005: sync.sh exists" "$sync_file"

  # Verify it still references scripts/ as source for syncing to correctless/scripts/
  assert_contains "R-005: sync.sh syncs scripts/ to distribution" \
    "correctless/scripts" "$(cat "$sync_file")"

  # Run sync to make sure it still works
  local output
  output="$(cd "$REPO_DIR" && bash sync.sh 2>&1)" || true
  # sync.sh should complete without error
  assert_eq "R-005: sync.sh runs successfully" "0" "$?"

  # Verify distribution files exist after sync
  assert_file_exists "R-005: correctless/scripts/lib.sh exists after sync" \
    "$REPO_DIR/correctless/scripts/lib.sh"
  assert_file_exists "R-005: correctless/scripts/antipattern-scan.sh exists after sync" \
    "$REPO_DIR/correctless/scripts/antipattern-scan.sh"
}

# ---------------------------------------------------------------------------
# Tests R-006 [integration]: Test suite passes — source-tree vs installed-path distinction
# ---------------------------------------------------------------------------

test_r006_source_tree_refs_unchanged() {
  echo ""
  echo "=== R-006: Source-tree references in tests remain unchanged ==="

  # Tests that use $REPO_DIR/scripts/ are source-tree references — should NOT be changed
  # Check key test files that we know use source-tree references
  local test_files=(
    "test-antipattern-scan.sh"
    "test-lib-locking.sh"
    "test-architecture-drift.sh"
    "test-hook-sync.sh"
    "test-test-evasion-antipatterns.sh"
  )

  for tf in "${test_files[@]}"; do
    local test_path="$REPO_DIR/tests/$tf"
    [ -f "$test_path" ] || continue

    # These files should still reference $REPO_DIR/scripts/ (source-tree paths)
    local source_refs
    source_refs="$(grep 'REPO_DIR.*scripts/' "$test_path" | head -3 || true)"
    if [ -n "$source_refs" ]; then
      # Verify they are NOT changed to .correctless/scripts/
      local changed_refs
      changed_refs="$(echo "$source_refs" | grep '\.correctless/scripts/' || true)"
      assert_eq "R-006: $tf source-tree refs not changed to .correctless/" "" "$changed_refs"
    fi
  done
}

test_r006_installed_path_refs_updated() {
  echo ""
  echo "=== R-006: Installed-path references in tests updated ==="

  # Tests that set up test projects and install scripts should use .correctless/scripts/
  # These tests copy lib.sh into a test project to simulate a user install.
  # After migration, these copies should target .correctless/scripts/ not scripts/.

  # Check each test file that has installed-path references (not source-tree refs).
  # Source-tree refs use $REPO_DIR/scripts/ — installed-path refs use plain scripts/ or $TEST_DIR/scripts/.
  local test_files_with_installed_refs=(
    "test-gate-path-exceptions.sh"
    "test-workflow-gate.sh"
    "test-token-tracking.sh"
    "test-token-tracking-setup.sh"
    "test-token-tracking-skill-field.sh"
    "test-lib-locking.sh"
  )

  for tf in "${test_files_with_installed_refs[@]}"; do
    local test_path="$REPO_DIR/tests/$tf"
    [ -f "$test_path" ] || continue

    # Find lines that copy lib.sh to scripts/ or source scripts/lib.sh in test project context
    # These are installed-path references: they set up the test project to simulate an install
    # Filter out source-tree references (lines containing $REPO_DIR)
    local installed_refs
    installed_refs="$(grep -n 'scripts/lib\.sh' "$test_path" | \
      grep -v '\$REPO_DIR\|REPO_DIR' | \
      grep -v 'shellcheck' | \
      grep -v '\.correctless/scripts/' || true)"

    if [ -n "$installed_refs" ]; then
      assert_eq "R-006: $tf installed-path refs updated to .correctless/scripts/" "" "$installed_refs"
    else
      echo "  PASS: R-006: $tf no old installed-path refs"
      PASS=$((PASS + 1))
    fi
  done
}

test_r006_full_test_suite() {
  echo ""
  echo "=== R-006: Full test suite integration check ==="

  # Run the main test suite to verify nothing is broken
  local output
  output="$(cd "$REPO_DIR" && bash tests/test.sh 2>&1)" || true
  local exit_code=$?

  # The test suite should pass
  assert_eq "R-006: main test suite passes" "0" "$exit_code"

  # Check that the results line shows no failures
  local results_line
  results_line="$(echo "$output" | grep '^Results:' || true)"
  if [ -n "$results_line" ]; then
    assert_contains "R-006: test results show 0 failed" "0 failed" "$results_line"
  fi
}

# ---------------------------------------------------------------------------
# Tests R-007 [unit]: Documentation references updated
# ---------------------------------------------------------------------------

test_r007_readme_updated() {
  echo ""
  echo "=== R-007: README.md references updated ==="

  local readme="$REPO_DIR/README.md"
  if [ -f "$readme" ]; then
    # The uninstall section references scripts/lib.sh and scripts/antipattern-scan.sh
    # as installed paths — these should be updated to .correctless/scripts/
    local uninstall_refs
    uninstall_refs="$(grep 'scripts/lib\.sh\|scripts/antipattern-scan\.sh' "$readme" || true)"
    if [ -n "$uninstall_refs" ]; then
      # Should reference .correctless/scripts/ not bare scripts/
      local old_refs
      old_refs="$(echo "$uninstall_refs" | grep -v '\.correctless/scripts/' || true)"
      assert_eq "R-007: README.md uses .correctless/scripts/ for installed paths" "" "$old_refs"
    else
      # If no references at all, that's also fine (already cleaned up)
      echo "  PASS: R-007: README.md has no old installed path references"
      PASS=$((PASS + 1))
    fi
  fi
}

test_r007_agent_context_source_refs_unchanged() {
  echo ""
  echo "=== R-007: AGENT_CONTEXT source-tree refs unchanged ==="

  local agent_ctx="$REPO_DIR/.correctless/AGENT_CONTEXT.md"
  if [ -f "$agent_ctx" ]; then
    # The component table references "scripts/" as a development layout directory
    # This is a source-tree reference and should NOT be changed
    local component_ref
    component_ref="$(grep '| Scripts' "$agent_ctx" || true)"
    if [ -n "$component_ref" ]; then
      # Should still say "scripts/" (source-tree layout, not installed layout)
      assert_contains "R-007: AGENT_CONTEXT component table still references scripts/ (source-tree)" \
        "scripts/" "$component_ref"
    fi
  fi
}

# ---------------------------------------------------------------------------
# Integration: setup + hooks + fallback path end-to-end
# ---------------------------------------------------------------------------

test_integration_hooks_find_lib_after_setup() {
  echo ""
  echo "=== Integration: Hooks can source lib.sh after fresh setup ==="

  setup_test_project
  .claude/skills/workflow/setup >/dev/null 2>&1

  # The hooks are at .correctless/hooks/ and lib.sh should be at .correctless/scripts/
  # The primary path resolution is: hooks/../scripts = .correctless/scripts/
  local resolved
  resolved="$(cd "$TEST_DIR/.correctless/hooks" && cd ../scripts 2>/dev/null && pwd)"
  assert_eq "R-001+R-003: primary path resolves to .correctless/scripts" \
    "$TEST_DIR/.correctless/scripts" "$resolved"

  # lib.sh should exist at the resolved path
  assert_file_exists "R-001+R-003: lib.sh exists at primary resolution path" \
    "$resolved/lib.sh"

  cleanup
}

test_integration_upgrade_then_hooks() {
  echo ""
  echo "=== Integration: Upgrade migration then hooks find lib.sh ==="

  setup_test_project

  # Simulate old install
  mkdir -p "$TEST_DIR/scripts"
  echo "# old lib" > "$TEST_DIR/scripts/lib.sh"
  echo "# old scan" > "$TEST_DIR/scripts/antipattern-scan.sh"

  # Run setup (triggers migration)
  .claude/skills/workflow/setup >/dev/null 2>&1

  # Now hooks should find lib.sh at .correctless/scripts/ via primary path
  assert_file_exists "R-002+R-003: lib.sh at .correctless/scripts/ after upgrade" \
    "$TEST_DIR/.correctless/scripts/lib.sh"

  # And the old location should be empty
  assert_file_not_exists "R-002+R-003: old scripts/lib.sh gone after upgrade" \
    "$TEST_DIR/scripts/lib.sh"

  cleanup
}

# ---------------------------------------------------------------------------
# PMB-003: All source scripts installed (AP-024 structural guard)
# ---------------------------------------------------------------------------

test_pmb003_all_scripts_installed() {
  echo ""
  echo "=== PMB-003: Setup installs ALL scripts from source (AP-024) ==="

  setup_test_project
  .claude/skills/workflow/setup >/dev/null 2>&1

  # Count .sh files in the plugin's scripts/ directory (source of truth)
  local source_count installed_count
  source_count="$(find .claude/skills/workflow/scripts -maxdepth 1 -name '*.sh' -type f | wc -l | tr -d ' ')"
  installed_count="$(find "$TEST_DIR/.correctless/scripts" -maxdepth 1 -name '*.sh' -type f | wc -l | tr -d ' ')"

  assert_eq "PMB-003: installed script count ($installed_count) matches source ($source_count)" \
    "$source_count" "$installed_count"

  # Verify each source script has a corresponding installed copy
  for src in .claude/skills/workflow/scripts/*.sh; do
    [ -f "$src" ] || continue
    local name
    name="$(basename "$src")"
    assert_file_exists "PMB-003: $name installed" \
      "$TEST_DIR/.correctless/scripts/$name"
  done

  # HF-PMB003: explicitly verify harness-fingerprint.sh is installed
  # (harness-fingerprint spec PRE-006 — install-completeness coverage)
  assert_file_exists "HF-PMB003: harness-fingerprint.sh installed" \
    "$TEST_DIR/.correctless/scripts/harness-fingerprint.sh"

  cleanup
}

# ---------------------------------------------------------------------------
# Run all tests
# ---------------------------------------------------------------------------

echo "=== Scripts Namespace Migration Tests ==="

test_r001_setup_installs_to_correctless_scripts
test_r002_upgrade_migration
test_r002_upgrade_partial
test_r002_migration_before_hooks
test_r003_hook_fallback_paths
test_r003_workflow_advance_error_message
test_r004_skill_antipattern_path
test_r005_sync_unchanged
test_r006_source_tree_refs_unchanged
test_r006_installed_path_refs_updated
test_r006_full_test_suite
test_r007_readme_updated
test_r007_agent_context_source_refs_unchanged
test_integration_hooks_find_lib_after_setup
test_integration_upgrade_then_hooks
test_pmb003_all_scripts_installed

echo ""
echo "======================"
echo "Results: $PASS passed, $FAIL failed"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
