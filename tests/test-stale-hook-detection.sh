#!/usr/bin/env bash
# shellcheck disable=SC1090  # Dynamic source path (LIB_SH) always resolves to scripts/lib.sh
# Correctless — Stale Hook Detection Tests
# Tests R-001 through R-005 from the stale-hook-detection spec.
# RED phase: these tests MUST FAIL against current code (no implementation yet).
# Run from repo root: bash tests/test-stale-hook-detection.sh

set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB_SH="$REPO_DIR/scripts/lib.sh"
SETUP_SCRIPT="$REPO_DIR/setup"
PASS=0
FAIL=0

# ============================================================================
# Helpers (same pattern as test-lib.sh)
# ============================================================================

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
    echo "  FAIL: $desc (expected output to contain '$expected', got '$actual')"
    FAIL=$((FAIL + 1))
  fi
}

assert_not_contains() {
  local desc="$1" unexpected="$2" actual="$3"
  if echo "$actual" | grep -qF "$unexpected"; then
    echo "  FAIL: $desc (expected output NOT to contain '$unexpected')"
    FAIL=$((FAIL + 1))
  else
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  fi
}

assert_match() {
  local desc="$1" pattern="$2" actual="$3"
  if printf '%s\n' "$actual" | grep -qE -- "$pattern"; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (expected output to match pattern '$pattern', got '$actual')"
    FAIL=$((FAIL + 1))
  fi
}

assert_file_exists() {
  local desc="$1" path="$2"
  if [ -f "$path" ]; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (file '$path' does not exist)"
    FAIL=$((FAIL + 1))
  fi
}

assert_file_not_exists() {
  local desc="$1" path="$2"
  if [ ! -f "$path" ]; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (file '$path' should not exist but does)"
    FAIL=$((FAIL + 1))
  fi
}

# ============================================================================
# Test environment
# ============================================================================

TEST_DIR="/tmp/correctless-test-stale-hook-$$"

cleanup() {
  rm -rf "$TEST_DIR"
}
trap cleanup EXIT

# Create a minimal test environment simulating an installed project
# with source hooks and scripts available for source-ahead checking.
setup_test_env() {
  rm -rf "$TEST_DIR"
  mkdir -p "$TEST_DIR"

  # Source directory (simulates the correctless distribution, i.e. SCRIPT_DIR)
  local src_dir="$TEST_DIR/source"
  mkdir -p "$src_dir/hooks" "$src_dir/scripts"

  # Create source hooks
  echo '#!/usr/bin/env bash' > "$src_dir/hooks/workflow-gate.sh"
  echo '# gate hook v1' >> "$src_dir/hooks/workflow-gate.sh"
  echo '#!/usr/bin/env bash' > "$src_dir/hooks/audit-trail.sh"
  echo '# audit hook v1' >> "$src_dir/hooks/audit-trail.sh"

  # Create source scripts
  echo '#!/usr/bin/env bash' > "$src_dir/scripts/lib.sh"
  echo '# lib v1' >> "$src_dir/scripts/lib.sh"

  # Installed project directory (simulates user project)
  local proj_dir="$TEST_DIR/project"
  mkdir -p "$proj_dir/.correctless/hooks" "$proj_dir/.correctless/scripts"
  mkdir -p "$proj_dir/.correctless/config"

  # Install copies (identical to source at install time)
  cp "$src_dir/hooks/workflow-gate.sh" "$proj_dir/.correctless/hooks/"
  cp "$src_dir/hooks/audit-trail.sh" "$proj_dir/.correctless/hooks/"
  cp "$src_dir/scripts/lib.sh" "$proj_dir/.correctless/scripts/"

  # Copy the real lib.sh so we can source check_install_freshness
  cp "$LIB_SH" "$proj_dir/.correctless/scripts/lib.sh.real"
}

# Write a test manifest matching the installed files
write_test_manifest() {
  local proj_dir="$TEST_DIR/project"
  local src_dir="$TEST_DIR/source"

  # Compute hashes from installed files
  local gate_hash audit_hash lib_hash
  gate_hash="$(sha256sum "$proj_dir/.correctless/hooks/workflow-gate.sh" | cut -d' ' -f1)"
  audit_hash="$(sha256sum "$proj_dir/.correctless/hooks/audit-trail.sh" | cut -d' ' -f1)"
  lib_hash="$(sha256sum "$proj_dir/.correctless/scripts/lib.sh" | cut -d' ' -f1)"

  cat > "$proj_dir/.correctless/.install-manifest.json" <<EOF
{
  "installed_at": "2026-04-14T10:00:00Z",
  "source_dir": "$src_dir",
  "files": {
    "hooks/workflow-gate.sh": {
      "installed_hash": "$gate_hash",
      "source_hash": "$gate_hash"
    },
    "hooks/audit-trail.sh": {
      "installed_hash": "$audit_hash",
      "source_hash": "$audit_hash"
    },
    "scripts/lib.sh": {
      "installed_hash": "$lib_hash",
      "source_hash": "$lib_hash"
    }
  }
}
EOF
}

echo "Correctless Stale Hook Detection Tests"
echo "======================================="

# ============================================================================
# R-001 [integration]: Setup writes manifest after installing hooks/scripts
# ============================================================================

test_r001_manifest_created_after_setup() {
  echo ""
  echo "=== R-001: Setup writes install manifest ==="

  # Create a minimal project that setup can install into
  local proj_dir="$TEST_DIR/r001-project"
  rm -rf "$proj_dir"
  mkdir -p "$proj_dir"
  cd "$proj_dir" || exit 1

  # Initialize a git repo (setup requires it)
  git init -q
  git branch -M main
  echo "init" > README.md
  git add -A && git commit -q -m "init"

  # Run setup from the repo distribution
  REPO_ROOT="$proj_dir" bash "$SETUP_SCRIPT" 2>/dev/null || true

  # R-001a: Manifest file should exist after setup
  assert_file_exists "R-001a: manifest exists after setup" \
    "$proj_dir/.correctless/.install-manifest.json"

  # R-001b: Manifest should be valid JSON with required schema
  local manifest="$proj_dir/.correctless/.install-manifest.json"
  if [ -f "$manifest" ]; then
    local has_installed_at has_source_dir has_files
    has_installed_at="$(jq -r 'has("installed_at")' "$manifest" 2>/dev/null)"
    has_source_dir="$(jq -r 'has("source_dir")' "$manifest" 2>/dev/null)"
    has_files="$(jq -r 'has("files")' "$manifest" 2>/dev/null)"

    assert_eq "R-001b: manifest has installed_at" "true" "$has_installed_at"
    assert_eq "R-001c: manifest has source_dir" "true" "$has_source_dir"
    assert_eq "R-001d: manifest has files" "true" "$has_files"

    # R-001e: installed_at should be ISO timestamp
    local installed_at
    installed_at="$(jq -r '.installed_at' "$manifest" 2>/dev/null)"
    assert_match "R-001e: installed_at is ISO timestamp" \
      '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}' "$installed_at"

    # R-001f: source_dir should be an absolute path
    local source_dir
    source_dir="$(jq -r '.source_dir' "$manifest" 2>/dev/null)"
    assert_match "R-001f: source_dir is absolute path" '^/' "$source_dir"
  else
    # If manifest doesn't exist, fail these subtests explicitly
    assert_eq "R-001b: manifest has installed_at" "true" "false (no manifest)"
    assert_eq "R-001c: manifest has source_dir" "true" "false (no manifest)"
    assert_eq "R-001d: manifest has files" "true" "false (no manifest)"
    assert_eq "R-001e: installed_at is ISO timestamp" "true" "false (no manifest)"
    assert_eq "R-001f: source_dir is absolute path" "true" "false (no manifest)"
  fi
}

test_r001_dynamic_scanning() {
  echo ""
  echo "=== R-001: Dynamic scanning — all installed hooks/scripts in manifest ==="

  local proj_dir="$TEST_DIR/r001-dynamic"
  rm -rf "$proj_dir"
  mkdir -p "$proj_dir"
  cd "$proj_dir" || exit 1

  git init -q
  git branch -M main
  echo "init" > README.md
  git add -A && git commit -q -m "init"

  REPO_ROOT="$proj_dir" bash "$SETUP_SCRIPT" 2>/dev/null || true

  local manifest="$proj_dir/.correctless/.install-manifest.json"
  if [ -f "$manifest" ]; then
    # Every .sh file in .correctless/hooks/ should be in the manifest
    local missing_hooks=0
    for hook in "$proj_dir"/.correctless/hooks/*.sh; do
      [ -f "$hook" ] || continue
      local basename_hook
      basename_hook="$(basename "$hook")"
      local in_manifest
      in_manifest="$(jq -r --arg key "hooks/$basename_hook" '.files[$key] != null' "$manifest" 2>/dev/null)"
      if [ "$in_manifest" != "true" ]; then
        echo "  FAIL: R-001g: hooks/$basename_hook not in manifest"
        missing_hooks=$((missing_hooks + 1))
      fi
    done

    # Every .sh file in .correctless/scripts/ should be in the manifest
    local missing_scripts=0
    for script in "$proj_dir"/.correctless/scripts/*.sh; do
      [ -f "$script" ] || continue
      local basename_script
      basename_script="$(basename "$script")"
      local in_manifest
      in_manifest="$(jq -r --arg key "scripts/$basename_script" '.files[$key] != null' "$manifest" 2>/dev/null)"
      if [ "$in_manifest" != "true" ]; then
        echo "  FAIL: R-001g: scripts/$basename_script not in manifest"
        missing_scripts=$((missing_scripts + 1))
      fi
    done

    if [ "$missing_hooks" -eq 0 ] && [ "$missing_scripts" -eq 0 ]; then
      echo "  PASS: R-001g: all installed hooks and scripts present in manifest"
      PASS=$((PASS + 1))
    else
      FAIL=$((FAIL + missing_hooks + missing_scripts))
    fi
  else
    echo "  FAIL: R-001g: no manifest file to check"
    FAIL=$((FAIL + 1))
  fi
}

test_r001_hashes_match_at_install() {
  echo ""
  echo "=== R-001: installed_hash == source_hash at install time ==="

  local proj_dir="$TEST_DIR/r001-hashes"
  rm -rf "$proj_dir"
  mkdir -p "$proj_dir"
  cd "$proj_dir" || exit 1

  git init -q
  git branch -M main
  echo "init" > README.md
  git add -A && git commit -q -m "init"

  REPO_ROOT="$proj_dir" bash "$SETUP_SCRIPT" 2>/dev/null || true

  local manifest="$proj_dir/.correctless/.install-manifest.json"
  if [ -f "$manifest" ]; then
    local all_match=true
    while IFS= read -r key; do
      local installed_hash source_hash
      installed_hash="$(jq -r --arg k "$key" '.files[$k].installed_hash' "$manifest")"
      source_hash="$(jq -r --arg k "$key" '.files[$k].source_hash' "$manifest")"
      if [ "$installed_hash" != "$source_hash" ]; then
        echo "  FAIL: R-001h: $key installed_hash != source_hash"
        all_match=false
        FAIL=$((FAIL + 1))
      fi
    done < <(jq -r '.files | keys[]' "$manifest" 2>/dev/null)

    if [ "$all_match" = "true" ]; then
      echo "  PASS: R-001h: all files have installed_hash == source_hash at install time"
      PASS=$((PASS + 1))
    fi
  else
    echo "  FAIL: R-001h: no manifest to check"
    FAIL=$((FAIL + 1))
  fi
}

test_r001_manifest_overwritten_on_rerun() {
  echo ""
  echo "=== R-001: Manifest overwritten on re-run ==="

  local proj_dir="$TEST_DIR/r001-rerun"
  rm -rf "$proj_dir"
  mkdir -p "$proj_dir"
  cd "$proj_dir" || exit 1

  git init -q
  git branch -M main
  echo "init" > README.md
  git add -A && git commit -q -m "init"

  # First setup run
  REPO_ROOT="$proj_dir" bash "$SETUP_SCRIPT" 2>/dev/null || true

  local manifest="$proj_dir/.correctless/.install-manifest.json"
  if [ -f "$manifest" ]; then
    local first_ts
    first_ts="$(jq -r '.installed_at' "$manifest")"

    # Wait a moment so timestamp differs
    sleep 1

    # Second setup run
    REPO_ROOT="$proj_dir" bash "$SETUP_SCRIPT" 2>/dev/null || true

    local second_ts
    second_ts="$(jq -r '.installed_at' "$manifest")"

    # Timestamps should differ — manifest was overwritten
    if [ "$first_ts" != "$second_ts" ]; then
      echo "  PASS: R-001i: manifest overwritten on re-run (different timestamps)"
      PASS=$((PASS + 1))
    else
      echo "  FAIL: R-001i: manifest not overwritten — timestamps identical ($first_ts)"
      FAIL=$((FAIL + 1))
    fi
  else
    echo "  FAIL: R-001i: no manifest to check"
    FAIL=$((FAIL + 1))
  fi
}

test_r001_relative_paths_include_subdirectory() {
  echo ""
  echo "=== R-001: Relative paths include hooks/ and scripts/ prefix ==="

  local proj_dir="$TEST_DIR/r001-paths"
  rm -rf "$proj_dir"
  mkdir -p "$proj_dir"
  cd "$proj_dir" || exit 1

  git init -q
  git branch -M main
  echo "init" > README.md
  git add -A && git commit -q -m "init"

  REPO_ROOT="$proj_dir" bash "$SETUP_SCRIPT" 2>/dev/null || true

  local manifest="$proj_dir/.correctless/.install-manifest.json"
  if [ -f "$manifest" ]; then
    # All keys should start with either hooks/ or scripts/
    local bad_keys=0
    while IFS= read -r key; do
      case "$key" in
        hooks/*|scripts/*) ;; # good
        *) echo "  FAIL: R-001j: key '$key' lacks hooks/ or scripts/ prefix"
           bad_keys=$((bad_keys + 1)) ;;
      esac
    done < <(jq -r '.files | keys[]' "$manifest" 2>/dev/null)

    if [ "$bad_keys" -eq 0 ]; then
      echo "  PASS: R-001j: all manifest keys have hooks/ or scripts/ prefix"
      PASS=$((PASS + 1))
    else
      FAIL=$((FAIL + bad_keys))
    fi
  else
    echo "  FAIL: R-001j: no manifest to check"
    FAIL=$((FAIL + 1))
  fi
}

# ============================================================================
# R-002 [unit]: check_install_freshness function
# ============================================================================

test_r002_ok_status() {
  echo ""
  echo "=== R-002: ok status when file matches manifest hash ==="

  setup_test_env
  local proj_dir="$TEST_DIR/project"
  write_test_manifest

  cd "$proj_dir" || exit 1

  # Source the real lib.sh to get check_install_freshness
  source "$LIB_SH"

  local output
  output="$(check_install_freshness "$proj_dir/.correctless" 2>/dev/null)"

  # All files should be ok
  assert_contains "R-002a: ok status for hooks/workflow-gate.sh" \
    "ok:hooks/workflow-gate.sh" "$output"
  assert_contains "R-002b: ok status for hooks/audit-trail.sh" \
    "ok:hooks/audit-trail.sh" "$output"
  assert_contains "R-002c: ok status for scripts/lib.sh" \
    "ok:scripts/lib.sh" "$output"

  # No non-ok statuses
  assert_not_contains "R-002d: no modified status" "modified:" "$output"
  assert_not_contains "R-002e: no missing status" "missing:" "$output"
  assert_not_contains "R-002f: no source_ahead status" "source_ahead:" "$output"
}

test_r002_modified_status() {
  echo ""
  echo "=== R-002: modified status when installed file changed ==="

  setup_test_env
  local proj_dir="$TEST_DIR/project"
  write_test_manifest

  # Modify an installed file after manifest was written
  echo "# modified locally" >> "$proj_dir/.correctless/hooks/workflow-gate.sh"

  cd "$proj_dir" || exit 1
  source "$LIB_SH"

  local output
  output="$(check_install_freshness "$proj_dir/.correctless" 2>/dev/null)"

  assert_contains "R-002g: modified status for changed file" \
    "modified:hooks/workflow-gate.sh" "$output"

  # Other files still ok
  assert_contains "R-002h: audit-trail.sh still ok" \
    "ok:hooks/audit-trail.sh" "$output"
}

test_r002_missing_status() {
  echo ""
  echo "=== R-002: missing status when file deleted ==="

  setup_test_env
  local proj_dir="$TEST_DIR/project"
  write_test_manifest

  # Delete an installed file
  rm "$proj_dir/.correctless/hooks/audit-trail.sh"

  cd "$proj_dir" || exit 1
  source "$LIB_SH"

  local output
  output="$(check_install_freshness "$proj_dir/.correctless" 2>/dev/null)"

  assert_contains "R-002i: missing status for deleted file" \
    "missing:hooks/audit-trail.sh" "$output"
}

test_r002_source_ahead_status() {
  echo ""
  echo "=== R-002: source_ahead status when source file changed ==="

  setup_test_env
  local proj_dir="$TEST_DIR/project"
  write_test_manifest

  # Modify a source file (simulates a fix in the distribution)
  echo "# bug fix v2" >> "$TEST_DIR/source/hooks/workflow-gate.sh"

  cd "$proj_dir" || exit 1
  source "$LIB_SH"

  local output
  output="$(check_install_freshness "$proj_dir/.correctless" 2>/dev/null)"

  assert_contains "R-002j: source_ahead status for changed source" \
    "source_ahead:hooks/workflow-gate.sh" "$output"

  # Other files still ok (source unchanged)
  assert_contains "R-002k: audit-trail.sh still ok" \
    "ok:hooks/audit-trail.sh" "$output"
}

test_r002_new_file_status() {
  echo ""
  echo "=== R-002: new_file status when file added but not in manifest ==="

  setup_test_env
  local proj_dir="$TEST_DIR/project"
  write_test_manifest

  # Add a new hook file not in the manifest
  echo '#!/usr/bin/env bash' > "$proj_dir/.correctless/hooks/new-hook.sh"
  echo '# brand new hook' >> "$proj_dir/.correctless/hooks/new-hook.sh"

  cd "$proj_dir" || exit 1
  source "$LIB_SH"

  local output
  output="$(check_install_freshness "$proj_dir/.correctless" 2>/dev/null)"

  assert_contains "R-002l: new_file status for unmanifested hook" \
    "new_file:hooks/new-hook.sh" "$output"
}

test_r002_no_manifest() {
  echo ""
  echo "=== R-002: no_manifest when manifest doesn't exist ==="

  setup_test_env
  local proj_dir="$TEST_DIR/project"
  # Don't write a manifest

  cd "$proj_dir" || exit 1
  source "$LIB_SH"

  local output
  output="$(check_install_freshness "$proj_dir/.correctless" 2>/dev/null)"

  assert_eq "R-002m: no_manifest output" "no_manifest" "$output"
}

test_r002_source_ahead_skipped_when_source_dir_missing() {
  echo ""
  echo "=== R-002: source_ahead skipped when source_dir doesn't exist ==="

  setup_test_env
  local proj_dir="$TEST_DIR/project"
  write_test_manifest

  # Modify a source file so it WOULD produce source_ahead
  echo "# changed" >> "$TEST_DIR/source/hooks/workflow-gate.sh"

  # Then delete the entire source dir
  rm -rf "$TEST_DIR/source"

  cd "$proj_dir" || exit 1
  source "$LIB_SH"

  local output
  output="$(check_install_freshness "$proj_dir/.correctless" 2>/dev/null)"

  # Must NOT produce source_ahead since source_dir doesn't exist
  assert_not_contains "R-002n: no source_ahead when source_dir missing" \
    "source_ahead:" "$output"

  # Install-vs-manifest should still work
  assert_contains "R-002o: ok status still works without source_dir" \
    "ok:hooks/workflow-gate.sh" "$output"
}

test_r002_output_format() {
  echo ""
  echo "=== R-002: output format is status:relative/path per line ==="

  setup_test_env
  local proj_dir="$TEST_DIR/project"
  write_test_manifest

  # Create mixed statuses for a rich output
  echo "# modified" >> "$proj_dir/.correctless/hooks/workflow-gate.sh"
  echo "# source fix" >> "$TEST_DIR/source/hooks/audit-trail.sh"

  cd "$proj_dir" || exit 1
  source "$LIB_SH"

  local output
  output="$(check_install_freshness "$proj_dir/.correctless" 2>/dev/null)"

  # Every non-empty line should match the pattern status:path
  local bad_lines=0
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    if ! echo "$line" | grep -qE '^(ok|modified|missing|source_ahead|new_file|no_manifest):'; then
      echo "  FAIL: R-002p: bad output line: '$line'"
      bad_lines=$((bad_lines + 1))
    fi
  done <<< "$output"

  if [ "$bad_lines" -eq 0 ]; then
    echo "  PASS: R-002p: all output lines match status:path format"
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + bad_lines))
  fi
}

# ============================================================================
# R-003 [integration]: /cauto startup warnings
# ============================================================================

# R-003 tests verify the warning message content for each status.
# Since /cauto is a skill (SKILL.md processed by Claude), we test the
# helper function that formats warnings, not the full skill invocation.
# The spec says the warnings are formatted at /cauto startup — we test
# the formatting logic in a shell function that /cauto will call.

test_r003_source_ahead_warning() {
  echo ""
  echo "=== R-003: source_ahead produces strongest warning ==="

  setup_test_env
  local proj_dir="$TEST_DIR/project"
  write_test_manifest

  # Trigger source_ahead
  echo "# bug fix" >> "$TEST_DIR/source/hooks/workflow-gate.sh"

  cd "$proj_dir" || exit 1
  source "$LIB_SH"

  local output
  output="$(check_install_freshness "$proj_dir/.correctless" 2>/dev/null)"

  # Verify source_ahead is detected (prerequisite for R-003 warning test)
  assert_contains "R-003a: source_ahead detected" "source_ahead:" "$output"

  # The warning formatting is tested via the output content — the SKILL.md
  # instructions tell the agent to look for source_ahead and produce the
  # strongest warning. The function provides the data; the skill formats it.
  # We verify the function output enables the skill to detect the condition.
  local source_ahead_count
  source_ahead_count="$(echo "$output" | grep -c '^source_ahead:' || true)"
  if [ "$source_ahead_count" -gt 0 ]; then
    echo "  PASS: R-003b: source_ahead count ($source_ahead_count) enables WARNING formatting"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: R-003b: no source_ahead lines for warning formatting"
    FAIL=$((FAIL + 1))
  fi
}

test_r003_no_output_when_all_ok() {
  echo ""
  echo "=== R-003: no warning output when all files are ok ==="

  setup_test_env
  local proj_dir="$TEST_DIR/project"
  write_test_manifest

  cd "$proj_dir" || exit 1
  source "$LIB_SH"

  local output
  output="$(check_install_freshness "$proj_dir/.correctless" 2>/dev/null)"

  # All lines should be ok: — no warning-triggering statuses
  # Account for any empty trailing lines
  local real_non_ok=0
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    case "$line" in
      ok:*) ;;
      *) real_non_ok=$((real_non_ok + 1)) ;;
    esac
  done <<< "$output"

  assert_eq "R-003c: no non-ok statuses when everything matches" "0" "$real_non_ok"
}

test_r003_new_file_detected() {
  echo ""
  echo "=== R-003: new_file status provides data for warning ==="

  setup_test_env
  local proj_dir="$TEST_DIR/project"
  write_test_manifest

  echo '#!/usr/bin/env bash' > "$proj_dir/.correctless/hooks/extra.sh"

  cd "$proj_dir" || exit 1
  source "$LIB_SH"

  local output
  output="$(check_install_freshness "$proj_dir/.correctless" 2>/dev/null)"

  assert_contains "R-003d: new_file detected for extra hook" "new_file:hooks/extra.sh" "$output"
}

# ============================================================================
# R-004 [unit]: /cstatus install freshness status line
# ============================================================================

# R-004 tests verify that check_install_freshness output can be parsed
# into the correct status line text by the cstatus skill.

test_r004_install_current() {
  echo ""
  echo "=== R-004: Install: current when all ok ==="

  setup_test_env
  local proj_dir="$TEST_DIR/project"
  write_test_manifest

  cd "$proj_dir" || exit 1
  source "$LIB_SH"

  local output
  output="$(check_install_freshness "$proj_dir/.correctless" 2>/dev/null)"

  # Parse: if all lines are ok:, status is "current"
  local has_non_ok=false
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    case "$line" in
      ok:*) ;;
      *) has_non_ok=true ;;
    esac
  done <<< "$output"

  assert_eq "R-004a: all ok means Install: current" "false" "$has_non_ok"
}

test_r004_stale_source_ahead() {
  echo ""
  echo "=== R-004: Install: STALE when source_ahead ==="

  setup_test_env
  local proj_dir="$TEST_DIR/project"
  write_test_manifest

  # Trigger source_ahead
  echo "# fix" >> "$TEST_DIR/source/hooks/workflow-gate.sh"
  echo "# fix" >> "$TEST_DIR/source/scripts/lib.sh"

  cd "$proj_dir" || exit 1
  source "$LIB_SH"

  local output
  output="$(check_install_freshness "$proj_dir/.correctless" 2>/dev/null)"

  local source_ahead_count
  source_ahead_count="$(echo "$output" | grep -c '^source_ahead:' || true)"

  # R-004b: source_ahead should be detected — enables "STALE — N source files" line
  if [ "$source_ahead_count" -ge 1 ]; then
    echo "  PASS: R-004b: source_ahead count ($source_ahead_count) enables STALE status line"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: R-004b: no source_ahead lines for STALE status"
    FAIL=$((FAIL + 1))
  fi
}

test_r004_stale_modified() {
  echo ""
  echo "=== R-004: Install: STALE when modified/missing (no source_ahead) ==="

  setup_test_env
  local proj_dir="$TEST_DIR/project"
  write_test_manifest

  # Modify installed file (no source change)
  echo "# tampered" >> "$proj_dir/.correctless/hooks/workflow-gate.sh"

  cd "$proj_dir" || exit 1
  source "$LIB_SH"

  local output
  output="$(check_install_freshness "$proj_dir/.correctless" 2>/dev/null)"

  local modified_count
  modified_count="$(echo "$output" | grep -c '^modified:' || true)"

  assert_eq "R-004c: modified count enables STALE (N files differ) line" "1" "$modified_count"
  assert_not_contains "R-004d: no source_ahead in this scenario" "source_ahead:" "$output"
}

test_r004_unknown_no_manifest() {
  echo ""
  echo "=== R-004: Install: unknown when no manifest ==="

  setup_test_env
  local proj_dir="$TEST_DIR/project"
  # No manifest written

  cd "$proj_dir" || exit 1
  source "$LIB_SH"

  local output
  output="$(check_install_freshness "$proj_dir/.correctless" 2>/dev/null)"

  assert_eq "R-004e: no_manifest output enables Install: unknown line" "no_manifest" "$output"
}

# ============================================================================
# R-005 [unit]: .correctless/.install-manifest.json is gitignored
# ============================================================================

test_r005_manifest_gitignored() {
  echo ""
  echo "=== R-005: install manifest is gitignored ==="

  # Check that .gitignore contains the manifest path
  local gitignore="$REPO_DIR/.gitignore"
  if [ -f "$gitignore" ]; then
    if grep -qF '.correctless/.install-manifest.json' "$gitignore" || \
       grep -q '\.install-manifest\.json' "$gitignore"; then
      echo "  PASS: R-005a: .install-manifest.json pattern found in .gitignore"
      PASS=$((PASS + 1))
    else
      echo "  FAIL: R-005a: .correctless/.install-manifest.json not in .gitignore"
      FAIL=$((FAIL + 1))
    fi
  else
    echo "  FAIL: R-005a: .gitignore file not found"
    FAIL=$((FAIL + 1))
  fi
}

# ============================================================================
# Run all tests
# ============================================================================

# R-001 tests
test_r001_manifest_created_after_setup
test_r001_dynamic_scanning
test_r001_hashes_match_at_install
test_r001_manifest_overwritten_on_rerun
test_r001_relative_paths_include_subdirectory

# R-002 tests
test_r002_ok_status
test_r002_modified_status
test_r002_missing_status
test_r002_source_ahead_status
test_r002_new_file_status
test_r002_no_manifest
test_r002_source_ahead_skipped_when_source_dir_missing
test_r002_output_format

# R-003 tests
test_r003_source_ahead_warning
test_r003_no_output_when_all_ok
test_r003_new_file_detected

# R-004 tests
test_r004_install_current
test_r004_stale_source_ahead
test_r004_stale_modified
test_r004_unknown_no_manifest

# R-005 tests
test_r005_manifest_gitignored

# ============================================================================
# INV-014: setup detects pre-R2 install of harness-fingerprint.sh and
# force-reinstalls (closes the upgrade-path break Finding #7 surfaced)
# ============================================================================

test_inv014_pre_r2_force_reinstall() {
  echo ""
  echo "=== INV-014: pre-R2 harness-fingerprint.sh force-reinstall ==="

  local target_dir="$TEST_DIR/inv014-target"
  rm -rf "$target_dir"
  mkdir -p "$target_dir/.correctless/scripts" "$target_dir/.correctless/hooks" "$target_dir/.correctless/config"

  # Make $target_dir a git repo so setup's REPO_ROOT detection (git toplevel)
  # picks it up rather than the outer correctless repo.
  ( cd "$target_dir" && git init -q && git commit --allow-empty -q -m init ) >/dev/null 2>&1

  # Stage a fake pre-R2 harness-fingerprint.sh containing the now-removed
  # VERSION_OVERRIDE marker. setup must detect this and force-reinstall.
  cat > "$target_dir/.correctless/scripts/harness-fingerprint.sh" <<'PRE_R2'
#!/usr/bin/env bash
# Pre-R2 stub for INV-014 detection
HARNESS_VERSION=1
VERSION_OVERRIDE=""
PRE_R2

  # Setup uses REPO_ROOT from the current working directory's git toplevel
  # (or pwd fallback). cd into target_dir so REPO_ROOT resolves correctly,
  # while invoking the setup script from the source repo via $SETUP_SCRIPT.
  local stderr_out
  stderr_out="$(cd "$target_dir" && bash "$SETUP_SCRIPT" 2>&1 >/dev/null)" || true

  # (a)+(b): notice present in stderr
  local got_notice="no"
  if echo "$stderr_out" | grep -qE 'pre-R2|VERSION_OVERRIDE|INV-014|INV-009'; then
    got_notice="yes"
  fi
  assert_eq "INV-014: setup emits pre-R2 detection notice" "yes" "$got_notice"

  # (c): post-install file does NOT contain VERSION_OVERRIDE
  local installed="$target_dir/.correctless/scripts/harness-fingerprint.sh"
  local has_override="yes"
  if [ -f "$installed" ] && ! grep -q 'VERSION_OVERRIDE' "$installed"; then
    has_override="no"
  fi
  assert_eq "INV-014: post-install file has no VERSION_OVERRIDE" "no" "$has_override"

  # (d): manifest hash entry exists for harness-fingerprint.sh
  local manifest="$target_dir/.correctless/.install-manifest.json"
  local manifest_ok="no"
  if [ -f "$manifest" ] && jq -e '.files["scripts/harness-fingerprint.sh"]' "$manifest" >/dev/null 2>&1; then
    manifest_ok="yes"
  fi
  assert_eq "INV-014-manifest: install manifest contains entry" "yes" "$manifest_ok"
}

test_inv014_pre_r2_force_reinstall

# ============================================================================
# Summary
# ============================================================================

echo ""
echo "=============================="
echo "  PASS: $PASS"
echo "  FAIL: $FAIL"
echo "=============================="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
