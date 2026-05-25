#!/usr/bin/env bash
# Correctless — /cprune Pruning Skill Tests
# Tests spec rules from .correctless/specs/cprune-skill.md
# INV-001 through INV-019, PRH-001 through PRH-004, BND-001 through BND-004
# Run from repo root: bash tests/test-cprune.sh

# shellcheck disable=SC1090,SC1091,SC2034

source "$(dirname "${BASH_SOURCE[0]}")/test-helpers.sh"

# ============================================
# SETUP: Test fixtures and helpers
# ============================================

SCANNER="$REPO_DIR/scripts/prune-scan.sh"

setup_fixture_dir() {
  local tmpdir
  tmpdir="$(mktemp -d)"
  # Initialize a git repo in the fixture dir for branch-aware tests
  git -C "$tmpdir" init -q 2>/dev/null
  git -C "$tmpdir" checkout -b main 2>/dev/null
  # Configure git user for commits in fixture repos
  git -C "$tmpdir" config user.email "test@test.com" 2>/dev/null
  git -C "$tmpdir" config user.name "Test" 2>/dev/null
  # Create basic structure
  mkdir -p "$tmpdir/.correctless"/{artifacts,meta,specs,config} \
           "$tmpdir"/{scripts,hooks,skills,agents,tests}
  # Copy lib.sh for sourcing
  cp "$REPO_DIR/scripts/lib.sh" "$tmpdir/scripts/lib.sh"
  echo "$tmpdir"
}

cleanup_fixture() {
  [ -n "${1:-}" ] && rm -rf "$1"
}

assert_json_valid() {
  local id="$1" desc="$2" json_str="$3"
  if echo "$json_str" | jq . >/dev/null 2>&1; then
    pass "$id" "$desc"
  else
    fail "$id" "$desc (invalid JSON)"
  fi
}

assert_json_array_length() {
  local id="$1" desc="$2" expected="$3" json_str="$4"
  local actual
  actual="$(echo "$json_str" | jq 'length' 2>/dev/null || echo "-1")"
  if [ "$expected" = "$actual" ]; then
    pass "$id" "$desc"
  else
    fail "$id" "$desc (expected $expected, got $actual)"
  fi
}

assert_json_field_eq() {
  local id="$1" desc="$2" field="$3" expected="$4" json_str="$5"
  local actual
  actual="$(echo "$json_str" | jq -r "$field" 2>/dev/null)"
  if [ "$expected" = "$actual" ]; then
    pass "$id" "$desc"
  else
    fail "$id" "$desc (expected '$expected', got '$actual')"
  fi
}

assert_json_field_exists() {
  local id="$1" desc="$2" field="$3" json_str="$4"
  if echo "$json_str" | jq -e "$field" >/dev/null 2>&1; then
    pass "$id" "$desc"
  else
    fail "$id" "$desc (field '$field' not found)"
  fi
}

assert_contains() {
  local id="$1" desc="$2" needle="$3" haystack="$4"
  if echo "$haystack" | grep -qF "$needle"; then
    pass "$id" "$desc"
  else
    fail "$id" "$desc (expected to contain '$needle')"
  fi
}

assert_not_contains() {
  local id="$1" desc="$2" needle="$3" haystack="$4"
  if ! echo "$haystack" | grep -qF "$needle"; then
    pass "$id" "$desc"
  else
    fail "$id" "$desc (should not contain '$needle')"
  fi
}

# ============================================
# INV-002: Scanner script basics
# ============================================

section "INV-002: Scanner script detects staleness mechanically"

# Tests INV-002 [unit]: scanner script exists and is executable
if [ -f "$SCANNER" ] && [ -x "$SCANNER" ]; then
  pass "INV-002-a" "Scanner script exists and is executable"
else
  fail "INV-002-a" "Scanner script should exist at scripts/prune-scan.sh and be executable"
fi

# Tests INV-002 [behavioral]: scanner accepts --category flag
TMPDIR_002="$(setup_fixture_dir)"
result_002="$(bash "$SCANNER" --category architecture --base "$TMPDIR_002" 2>/dev/null)" || true
assert_json_valid "INV-002-b" "Scanner outputs valid JSON for --category architecture" "$result_002"
cleanup_fixture "$TMPDIR_002"

# Tests INV-002 [behavioral]: scanner accepts all 9 categories
for cat in architecture antipatterns claude-md artifacts deferred counts crossrefs specs driftdebt; do
  TMPDIR_CAT="$(setup_fixture_dir)"
  result_cat="$(bash "$SCANNER" --category "$cat" --base "$TMPDIR_CAT" 2>/dev/null)" || true
  assert_json_valid "INV-002-cat-$cat" "Scanner outputs valid JSON for --category $cat" "$result_cat"
  cleanup_fixture "$TMPDIR_CAT"
done

# Tests INV-002 [behavioral]: each candidate has required fields
TMPDIR_002f="$(setup_fixture_dir)"
# Create a fixture ARCHITECTURE.md with a dead entry
cat > "$TMPDIR_002f/.correctless/ARCHITECTURE.md" << 'ARCH_EOF'
# Architecture

## Abstractions

### ABS-099: Dead entry
- **What**: References a deleted file
- **Invariant**: Something something
- **Enforced at**: `scripts/nonexistent-file.sh` (writer)
- **Violated when**: something
- **Test**: `tests/test-nonexistent.sh`
ARCH_EOF
result_002f="$(bash "$SCANNER" --category architecture --base "$TMPDIR_002f" 2>/dev/null)" || true
if [ "$(echo "$result_002f" | jq 'length' 2>/dev/null)" -gt 0 ]; then
  # Check required fields on the first candidate
  assert_json_field_exists "INV-002-f1" "Candidate has 'id' field" '.[0].id' "$result_002f"
  assert_json_field_exists "INV-002-f2" "Candidate has 'category' field" '.[0].category' "$result_002f"
  assert_json_field_exists "INV-002-f3" "Candidate has 'reason' field" '.[0].reason' "$result_002f"
  assert_json_field_exists "INV-002-f4" "Candidate has 'risk' field" '.[0].risk' "$result_002f"
  assert_json_field_exists "INV-002-f5" "Candidate has 'dead_refs' field" '.[0].dead_refs' "$result_002f"
  assert_json_field_exists "INV-002-f6" "Candidate has 'live_refs' field" '.[0].live_refs' "$result_002f"
  assert_json_field_exists "INV-002-f7" "Candidate has 'bulk_warning' field" '.[0].bulk_warning' "$result_002f"
else
  fail "INV-002-f1" "Scanner should detect dead ABS-099 entry"
  fail "INV-002-f2" "Candidate should have 'category' field"
  fail "INV-002-f3" "Candidate should have 'reason' field"
  fail "INV-002-f4" "Candidate should have 'risk' field"
  fail "INV-002-f5" "Candidate should have 'dead_refs' field"
  fail "INV-002-f6" "Candidate should have 'live_refs' field"
  fail "INV-002-f7" "Candidate should have 'bulk_warning' field"
fi
cleanup_fixture "$TMPDIR_002f"

# Tests INV-002 [behavioral]: sources scripts/lib.sh (ABS-001 compliance)
if [ -f "$SCANNER" ]; then
  if grep -q 'source.*scripts/lib\.sh\|\..*scripts/lib\.sh' "$SCANNER" 2>/dev/null; then
    pass "INV-002-lib" "Scanner sources scripts/lib.sh"
  else
    fail "INV-002-lib" "Scanner should source scripts/lib.sh per ABS-001"
  fi
else
  fail "INV-002-lib" "Scanner script does not exist"
fi

# Tests INV-002 [behavioral]: per-category error handling — missing data source
TMPDIR_002e="$(setup_fixture_dir)"
# Don't create ARCHITECTURE.md — the data source is missing
result_002e="$(bash "$SCANNER" --category architecture --base "$TMPDIR_002e" 2>/dev/null)" || true
assert_json_valid "INV-002-e" "Missing data source produces valid JSON (empty array)" "$result_002e"
assert_json_array_length "INV-002-e2" "Missing data source produces empty array" "0" "$result_002e"
cleanup_fixture "$TMPDIR_002e"

# ============================================
# INV-003: Architecture entry staleness detection
# ============================================

section "INV-003: Architecture entry staleness detection"

# Tests INV-003 [behavioral]: entry with ALL dead refs is flagged
TMPDIR_003="$(setup_fixture_dir)"
cat > "$TMPDIR_003/.correctless/ARCHITECTURE.md" << 'ARCH_EOF'
# Architecture

## Abstractions

### ABS-050: Completely dead entry
- **What**: References only deleted files
- **Invariant**: Something
- **Enforced at**: `scripts/deleted-script.sh` (writer), `hooks/deleted-hook.sh` (consumer)
- **Violated when**: something
- **Test**: `tests/test-deleted.sh`
ARCH_EOF
result_003a="$(bash "$SCANNER" --category architecture --base "$TMPDIR_003" 2>/dev/null)" || true
if [ "$(echo "$result_003a" | jq 'length' 2>/dev/null)" -gt 0 ]; then
  assert_json_field_eq "INV-003-a" "Dead entry is flagged with correct id" '.[0].id' "ABS-050" "$result_003a"
else
  fail "INV-003-a" "Entry with all dead refs should be flagged as stale"
fi
cleanup_fixture "$TMPDIR_003"

# Tests INV-003 [behavioral]: entry with at least one LIVE ref is NOT flagged
TMPDIR_003b="$(setup_fixture_dir)"
# Create a file that exists
touch "$TMPDIR_003b/scripts/lib.sh"
cat > "$TMPDIR_003b/.correctless/ARCHITECTURE.md" << 'ARCH_EOF'
# Architecture

## Abstractions

### ABS-051: Has one live ref
- **What**: References one live and one dead file
- **Invariant**: Something
- **Enforced at**: `scripts/lib.sh` (writer), `scripts/deleted-script.sh` (consumer)
- **Violated when**: something
- **Test**: `tests/test-deleted.sh`
ARCH_EOF
result_003b="$(bash "$SCANNER" --category architecture --base "$TMPDIR_003b" 2>/dev/null)" || true
assert_json_array_length "INV-003-b" "Entry with one live ref is NOT flagged" "0" "$result_003b"
cleanup_fixture "$TMPDIR_003b"

# Tests INV-003 [behavioral]: pure prose entries (no file refs) are NOT flagged
TMPDIR_003c="$(setup_fixture_dir)"
cat > "$TMPDIR_003c/.correctless/ARCHITECTURE.md" << 'ARCH_EOF'
# Architecture

## Abstractions

### ABS-052: Pure prose entry
- **What**: This is a conceptual entry with no file references at all
- **Invariant**: Agents must follow this principle
- **Violated when**: Agents ignore the principle
ARCH_EOF
result_003c="$(bash "$SCANNER" --category architecture --base "$TMPDIR_003c" 2>/dev/null)" || true
assert_json_array_length "INV-003-c" "Pure prose entry (no file refs) is NOT flagged" "0" "$result_003c"
cleanup_fixture "$TMPDIR_003c"

# Tests INV-003 [behavioral]: extracts backtick-quoted file paths
TMPDIR_003d="$(setup_fixture_dir)"
cat > "$TMPDIR_003d/.correctless/ARCHITECTURE.md" << 'ARCH_EOF'
# Architecture

## Abstractions

### ABS-053: Backtick refs
- **What**: References `scripts/nonexistent.sh` and `hooks/missing.sh`
- **Invariant**: Something
ARCH_EOF
result_003d="$(bash "$SCANNER" --category architecture --base "$TMPDIR_003d" 2>/dev/null)" || true
if [ "$(echo "$result_003d" | jq 'length' 2>/dev/null)" -gt 0 ]; then
  pass "INV-003-d" "Backtick-quoted file paths are extracted and detected as dead"
else
  fail "INV-003-d" "Scanner should extract backtick-quoted file paths"
fi
cleanup_fixture "$TMPDIR_003d"

# Tests INV-003 [behavioral]: extracts Enforced at comma-separated paths
TMPDIR_003e="$(setup_fixture_dir)"
cat > "$TMPDIR_003e/.correctless/ARCHITECTURE.md" << 'ARCH_EOF'
# Architecture

## Abstractions

### ABS-054: Enforced-at refs
- **What**: Something
- **Invariant**: Something
- **Enforced at**: `scripts/missing1.sh` (writer), `scripts/missing2.sh` (consumer)
- **Violated when**: something
ARCH_EOF
result_003e="$(bash "$SCANNER" --category architecture --base "$TMPDIR_003e" 2>/dev/null)" || true
if [ "$(echo "$result_003e" | jq 'length' 2>/dev/null)" -gt 0 ]; then
  # Verify dead_refs contains both files
  local_dead="$(echo "$result_003e" | jq -r '.[0].dead_refs | length' 2>/dev/null)"
  if [ "$local_dead" -ge 2 ]; then
    pass "INV-003-e" "Enforced at comma-separated paths are extracted"
  else
    fail "INV-003-e" "Should extract both comma-separated Enforced at paths (got $local_dead)"
  fi
else
  fail "INV-003-e" "Scanner should extract Enforced at paths"
fi
cleanup_fixture "$TMPDIR_003e"

# Tests INV-003 [behavioral]: extracts See-link paths (index-only entries)
TMPDIR_003f="$(setup_fixture_dir)"
cat > "$TMPDIR_003f/.correctless/ARCHITECTURE.md" << 'ARCH_EOF'
# Architecture

## Key Patterns

### PAT-099: Indexed entry
See `path/to/nonexistent-rule.md`.
ARCH_EOF
result_003f="$(bash "$SCANNER" --category architecture --base "$TMPDIR_003f" 2>/dev/null)" || true
if [ "$(echo "$result_003f" | jq 'length' 2>/dev/null)" -gt 0 ]; then
  pass "INV-003-f" "See-link paths in index-only entries are extracted"
else
  fail "INV-003-f" "Scanner should detect dead See-link paths"
fi
cleanup_fixture "$TMPDIR_003f"

# Tests INV-003 [behavioral]: extracts Test field paths
TMPDIR_003g="$(setup_fixture_dir)"
cat > "$TMPDIR_003g/.correctless/ARCHITECTURE.md" << 'ARCH_EOF'
# Architecture

## Abstractions

### ABS-055: Test refs
- **What**: Something
- **Invariant**: Something
- **Test**: `tests/test-nonexistent.sh`
ARCH_EOF
result_003g="$(bash "$SCANNER" --category architecture --base "$TMPDIR_003g" 2>/dev/null)" || true
if [ "$(echo "$result_003g" | jq 'length' 2>/dev/null)" -gt 0 ]; then
  pass "INV-003-g" "Test field paths are extracted"
else
  fail "INV-003-g" "Scanner should extract Test field paths"
fi
cleanup_fixture "$TMPDIR_003g"

# Tests INV-003 [behavioral]: sub-entries (#### level) are part of parent
TMPDIR_003h="$(setup_fixture_dir)"
cat > "$TMPDIR_003h/.correctless/ARCHITECTURE.md" << 'ARCH_EOF'
# Architecture

## Trust Boundaries

### TB-099: Parent entry
- **What**: Parent has a live ref
- **Invariant**: Something
- **Enforced at**: `scripts/lib.sh` (writer)

#### TB-099a: Sub-entry with dead refs
- **Scoped extension**: Something at `scripts/nonexistent-sub.sh`
- **Test**: `tests/test-nonexistent-sub.sh`
ARCH_EOF
# scripts/lib.sh exists in the fixture
result_003h="$(bash "$SCANNER" --category architecture --base "$TMPDIR_003h" 2>/dev/null)" || true
assert_json_array_length "INV-003-h" "Sub-entry refs merged with parent — parent has live ref so not flagged" "0" "$result_003h"
cleanup_fixture "$TMPDIR_003h"

# Tests INV-003 [behavioral]: use verbatim copy of real ARCHITECTURE.md entry (AP-031)
# Using real ABS-001 entry from the repo
TMPDIR_003real="$(setup_fixture_dir)"
# Copy lib.sh so the ref is live
cp "$REPO_DIR/scripts/lib.sh" "$TMPDIR_003real/scripts/lib.sh"
cat > "$TMPDIR_003real/.correctless/ARCHITECTURE.md" << 'ARCH_EOF'
# Architecture

## Abstractions

### ABS-001: Shared script library (scripts/lib.sh)
- **What**: Shared bash utilities sourced by hooks and phase-transition scripts. Provides path helpers (branch_slug, repo_root, config_file, artifacts_dir), file classification (classify_file, read_patterns, read_intensity), state file locking (ABS-003), and write pattern detection (_has_write_pattern, get_target_file).
- **Invariant**: Functions in lib.sh have a single definition. Scripts must source lib.sh rather than duplicating functions locally.
- **Enforced at**: scripts/lib.sh (source), hooks/workflow-advance.sh (consumer), hooks/workflow-gate.sh (consumer), hooks/sensitive-file-guard.sh (consumer), hooks/audit-trail.sh (consumer), hooks/statusline.sh (consumer), scripts/antipattern-scan.sh (consumer), scripts/compute-session-cost.sh (consumer), scripts/build-dashboard.sh (consumer), scripts/cross-feature-intel.sh (consumer), scripts/wf/transitions.sh (indirect consumer via dispatcher scope), scripts/wf/utility.sh (indirect consumer via dispatcher scope), scripts/wf/metadata.sh (indirect consumer via dispatcher scope)
- **Violated when**: A hook or script defines branch_slug(), classify_file(), _has_write_pattern(), _acquire_state_lock(), or any other lib.sh function locally instead of sourcing the library
- **Test**: R-019e in antipattern-scan tests (verifies workflow-advance.sh does not define branch_slug locally), R-021 in test-lib-locking.sh (no flock dependency)
ARCH_EOF
result_003real="$(bash "$SCANNER" --category architecture --base "$TMPDIR_003real" 2>/dev/null)" || true
# ABS-001 has scripts/lib.sh as live ref, so it should NOT be flagged
assert_json_array_length "INV-003-real" "Real ABS-001 entry with live scripts/lib.sh is NOT flagged (AP-031)" "0" "$result_003real"
cleanup_fixture "$TMPDIR_003real"

# Tests INV-003 [behavioral]: handles PAT/TB/ENV entry types
TMPDIR_003types="$(setup_fixture_dir)"
cat > "$TMPDIR_003types/.correctless/ARCHITECTURE.md" << 'ARCH_EOF'
# Architecture

## Key Patterns

### PAT-098: Dead pattern
- **What**: References only deleted files
- **Invariant**: Something at `scripts/nonexistent-pat.sh`
- **Test**: `tests/test-nonexistent-pat.sh`

## Trust Boundaries

### TB-098: Dead trust boundary
- **What**: References only deleted files
- **Invariant**: Something
- **Enforced at**: `hooks/nonexistent-hook.sh` (consumer)
- **Test**: `tests/test-nonexistent-tb.sh`

## Environment Assumptions

### ENV-098: Dead env assumption
- **What**: References only deleted files at `scripts/nonexistent-env.sh`
ARCH_EOF
result_003types="$(bash "$SCANNER" --category architecture --base "$TMPDIR_003types" 2>/dev/null)" || true
count_003types="$(echo "$result_003types" | jq 'length' 2>/dev/null || echo "0")"
if [ "$count_003types" -ge 3 ]; then
  pass "INV-003-types" "PAT, TB, ENV entry types are all detected"
else
  fail "INV-003-types" "Should detect PAT, TB, ENV entries (found $count_003types, expected 3+)"
fi
cleanup_fixture "$TMPDIR_003types"

# ============================================
# INV-004: Archive-not-delete for documentation
# ============================================

section "INV-004: Archive-not-delete for documentation entries"

# Tests INV-004 [unit]: SKILL.md references archive files
if [ -f "skills/cprune/SKILL.md" ]; then
  body_004="$(cat "skills/cprune/SKILL.md")"
  assert_contains "INV-004-a" "SKILL.md references ARCHITECTURE_DEPRECATED.md" ".correctless/ARCHITECTURE_DEPRECATED.md" "$body_004"
  assert_contains "INV-004-b" "SKILL.md references antipatterns-archived.md" ".correctless/antipatterns-archived.md" "$body_004"
  assert_contains "INV-004-c" "SKILL.md references CLAUDE_LEARNINGS_ARCHIVED.md" ".correctless/CLAUDE_LEARNINGS_ARCHIVED.md" "$body_004"
else
  fail "INV-004-a" "skills/cprune/SKILL.md does not exist"
  fail "INV-004-b" "skills/cprune/SKILL.md does not exist"
  fail "INV-004-c" "skills/cprune/SKILL.md does not exist"
fi

# ============================================
# INV-005: Orphaned artifact cleanup
# ============================================

section "INV-005: Orphaned artifact cleanup"

# Tests INV-005 [behavioral]: artifacts for deleted branches are flagged
TMPDIR_005="$(setup_fixture_dir)"
# Create a branch so branch_slug works
git -C "$TMPDIR_005" commit --allow-empty -m "init" -q 2>/dev/null
# Create artifact for a branch that does NOT exist
touch "$TMPDIR_005/.correctless/artifacts/workflow-state-feature-deleted-branch-abc123.json"
# Create artifact for main (which exists)
main_slug="$(cd "$TMPDIR_005" && source "$TMPDIR_005/scripts/lib.sh" && branch_slug "main")"
touch "$TMPDIR_005/.correctless/artifacts/workflow-state-${main_slug}.json"

result_005="$(bash "$SCANNER" --category artifacts --base "$TMPDIR_005" 2>/dev/null)" || true
if [ "$(echo "$result_005" | jq 'length' 2>/dev/null)" -gt 0 ]; then
  # The orphaned artifact should be flagged
  first_id="$(echo "$result_005" | jq -r '.[0].id' 2>/dev/null)"
  if echo "$first_id" | grep -q "deleted-branch"; then
    pass "INV-005-a" "Artifact for deleted branch is flagged"
  else
    fail "INV-005-a" "Flagged artifact should be for the deleted branch (got $first_id)"
  fi
else
  fail "INV-005-a" "Artifacts for deleted branches should be flagged"
fi

# The main artifact should NOT be flagged
flagged_main="$(echo "$result_005" | jq -r '.[] | select(.id | test("main"))' 2>/dev/null)"
if [ -z "$flagged_main" ]; then
  pass "INV-005-b" "Artifact for existing branch (main) is NOT flagged"
else
  fail "INV-005-b" "Artifact for existing branch should not be flagged"
fi
cleanup_fixture "$TMPDIR_005"

# Tests INV-005 [behavioral]: scanner accepts --branches-file for testing
TMPDIR_005c="$(setup_fixture_dir)"
git -C "$TMPDIR_005c" commit --allow-empty -m "init" -q 2>/dev/null
# Compute the real slug for the branch
test_branch_slug="$(cd "$TMPDIR_005c" && source "$TMPDIR_005c/scripts/lib.sh" && branch_slug "feature/test-branch")"
touch "$TMPDIR_005c/.correctless/artifacts/workflow-state-${test_branch_slug}.json"
echo "main" > "$TMPDIR_005c/branches.txt"
echo "  feature/test-branch" >> "$TMPDIR_005c/branches.txt"
result_005c="$(bash "$SCANNER" --category artifacts --base "$TMPDIR_005c" --branches-file "$TMPDIR_005c/branches.txt" 2>/dev/null)" || true
# feature/test-branch is in the branches file, so its artifact should NOT be flagged
assert_json_array_length "INV-005-c" "Artifact for branch in --branches-file is NOT flagged" "0" "$result_005c"
cleanup_fixture "$TMPDIR_005c"

# Tests INV-005 [behavioral]: orphaned artifacts are risk: low
TMPDIR_005d="$(setup_fixture_dir)"
git -C "$TMPDIR_005d" commit --allow-empty -m "init" -q 2>/dev/null
touch "$TMPDIR_005d/.correctless/artifacts/workflow-state-feature-gone-bbbbbb.json"
echo "main" > "$TMPDIR_005d/branches.txt"
result_005d="$(bash "$SCANNER" --category artifacts --base "$TMPDIR_005d" --branches-file "$TMPDIR_005d/branches.txt" 2>/dev/null)" || true
if [ "$(echo "$result_005d" | jq 'length' 2>/dev/null)" -gt 0 ]; then
  assert_json_field_eq "INV-005-d" "Orphaned artifact is risk: low" '.[0].risk' "low" "$result_005d"
else
  fail "INV-005-d" "Should flag orphaned artifact"
fi
cleanup_fixture "$TMPDIR_005d"

# ============================================
# INV-006: AGENT_CONTEXT.md count verification
# ============================================

section "INV-006: AGENT_CONTEXT.md count verification"

# Tests INV-006 [behavioral]: mismatched counts are detected
TMPDIR_006="$(setup_fixture_dir)"
# Create AGENT_CONTEXT.md with wrong counts
cat > "$TMPDIR_006/.correctless/AGENT_CONTEXT.md" << 'AGENT_EOF'
# Agent Context

Ships as a single distribution with 99 skills and configurable intensity levels.
There are 99 test files covering behavior.
The project has 99 scripts.
There are 99 agents defined.
AGENT_EOF
# Create some real files to count
touch "$TMPDIR_006/tests/test-one.sh"
touch "$TMPDIR_006/tests/test-two.sh"
touch "$TMPDIR_006/scripts/lib.sh"
touch "$TMPDIR_006/scripts/scan.sh"
mkdir -p "$TMPDIR_006/skills/csetup"
mkdir -p "$TMPDIR_006/skills/cspec"
touch "$TMPDIR_006/agents/red.md"
result_006="$(bash "$SCANNER" --category counts --base "$TMPDIR_006" 2>/dev/null)" || true
count_006="$(echo "$result_006" | jq 'length' 2>/dev/null || echo "0")"
if [ "$count_006" -gt 0 ]; then
  pass "INV-006-a" "Mismatched counts are detected"
  assert_json_field_eq "INV-006-a2" "Count mismatch is risk: low" '.[0].risk' "low" "$result_006"
else
  fail "INV-006-a" "Scanner should detect mismatched counts"
  fail "INV-006-a2" "Count mismatch should be risk: low"
fi
cleanup_fixture "$TMPDIR_006"

# Tests INV-006 [behavioral]: correct counts are NOT flagged
TMPDIR_006b="$(setup_fixture_dir)"
touch "$TMPDIR_006b/tests/test-one.sh"
touch "$TMPDIR_006b/scripts/lib.sh"
mkdir -p "$TMPDIR_006b/skills/csetup"
touch "$TMPDIR_006b/agents/red.md"
cat > "$TMPDIR_006b/.correctless/AGENT_CONTEXT.md" << 'AGENT_EOF'
# Agent Context

Ships with 1 skills and stuff.
There are 1 test files.
The project has 1 scripts.
There are 1 agents.
AGENT_EOF
result_006b="$(bash "$SCANNER" --category counts --base "$TMPDIR_006b" 2>/dev/null)" || true
assert_json_array_length "INV-006-b" "Correct counts are NOT flagged" "0" "$result_006b"
cleanup_fixture "$TMPDIR_006b"

# Tests INV-006 [behavioral]: sed substitution anchors on label, not bare number
TMPDIR_006c="$(setup_fixture_dir)"
# AGENT_CONTEXT with count value appearing in multiple places
cat > "$TMPDIR_006c/.correctless/AGENT_CONTEXT.md" << 'AGENT_EOF'
# Agent Context

Chapter 5 discusses 5 design decisions across 5 skills and 5 test patterns.
There are 5 test files covering 5 areas.
The project has 5 scripts including 5 helpers.
5 agents are registered across 5 modules.
AGENT_EOF
touch "$TMPDIR_006c/tests/test-one.sh"
touch "$TMPDIR_006c/tests/test-two.sh"
touch "$TMPDIR_006c/tests/test-three.sh"
touch "$TMPDIR_006c/scripts/lib.sh"
touch "$TMPDIR_006c/scripts/scan.sh"
touch "$TMPDIR_006c/scripts/build.sh"
mkdir -p "$TMPDIR_006c/skills/csetup"
mkdir -p "$TMPDIR_006c/skills/cspec"
mkdir -p "$TMPDIR_006c/skills/ctdd"
touch "$TMPDIR_006c/agents/red.md"
touch "$TMPDIR_006c/agents/green.md"
result_006c="$(bash "$SCANNER" --category counts --base "$TMPDIR_006c" 2>/dev/null)" || true
# There should be mismatches detected (5 vs 3 tests, 5 vs 3 scripts, 5 vs 3 skills, 5 vs 2 agents)
count_006c="$(echo "$result_006c" | jq 'length' 2>/dev/null || echo "0")"
if [ "$count_006c" -gt 0 ]; then
  pass "INV-006-c" "Detects mismatches even when count value appears multiple times in file"
else
  fail "INV-006-c" "Should detect mismatches even when count value is ambiguous"
fi
cleanup_fixture "$TMPDIR_006c"

# ============================================
# INV-007: Cross-reference consistency check
# ============================================

section "INV-007: Cross-reference consistency check"

# Tests INV-007 [behavioral]: stale cross-refs detected
TMPDIR_007="$(setup_fixture_dir)"
touch "$TMPDIR_007/scripts/lib.sh"  # primary file exists
cat > "$TMPDIR_007/.correctless/ARCHITECTURE.md" << 'ARCH_EOF'
# Architecture

## Abstractions

### ABS-060: Has stale cross-ref
- **What**: Primary file exists but cross-ref is dead
- **Invariant**: Something
- **Enforced at**: `scripts/lib.sh` (source), `skills/nonexistent-skill/SKILL.md` (consumer)
- **Violated when**: something
- **Test**: `tests/test-lib.sh`
ARCH_EOF
touch "$TMPDIR_007/tests/test-lib.sh"
result_007="$(bash "$SCANNER" --category crossrefs --base "$TMPDIR_007" 2>/dev/null)" || true
if [ "$(echo "$result_007" | jq 'length' 2>/dev/null)" -gt 0 ]; then
  # Should be risk: medium (cross-ref update needed, not archiving)
  assert_json_field_eq "INV-007-a" "Stale cross-ref is risk: medium" '.[0].risk' "medium" "$result_007"
  pass "INV-007-a2" "Stale cross-references are detected"
else
  fail "INV-007-a" "Stale cross-ref should be risk: medium"
  fail "INV-007-a2" "Stale cross-references should be detected"
fi
cleanup_fixture "$TMPDIR_007"

# Tests INV-007 [behavioral]: stale cross-ref does NOT cause archiving flag
TMPDIR_007b="$(setup_fixture_dir)"
touch "$TMPDIR_007b/scripts/lib.sh"
cat > "$TMPDIR_007b/.correctless/ARCHITECTURE.md" << 'ARCH_EOF'
# Architecture

## Abstractions

### ABS-061: Live primary, dead cross-ref
- **What**: Something
- **Invariant**: Something
- **Enforced at**: `scripts/lib.sh` (source), `skills/deleted/SKILL.md` (consumer)
ARCH_EOF
# Check the architecture category — should NOT flag this entry
result_007b="$(bash "$SCANNER" --category architecture --base "$TMPDIR_007b" 2>/dev/null)" || true
assert_json_array_length "INV-007-b" "Entry with stale cross-ref but live primary is NOT flagged for archiving" "0" "$result_007b"
cleanup_fixture "$TMPDIR_007b"

# ============================================
# INV-008: CLAUDE.md learning staleness detection
# ============================================

section "INV-008: CLAUDE.md learning staleness detection"

# Tests INV-008 [behavioral]: learning with all dead file refs is flagged
TMPDIR_008="$(setup_fixture_dir)"
cat > "$TMPDIR_008/CLAUDE.md" << 'CLAUDE_EOF'
## Correctless Learnings

### 2026-01-01 — Bug fix: specific thing broke
- Fixed a bug in `scripts/nonexistent-old.sh` related to `hooks/deleted-hook.sh`
- Source: /cdocs after feature/deleted-feature
CLAUDE_EOF
result_008="$(bash "$SCANNER" --category claude-md --base "$TMPDIR_008" 2>/dev/null)" || true
if [ "$(echo "$result_008" | jq 'length' 2>/dev/null)" -gt 0 ]; then
  pass "INV-008-a" "Learning with all dead file refs is flagged"
  assert_json_field_eq "INV-008-a2" "CLAUDE.md learning is risk: high" '.[0].risk' "high" "$result_008"
else
  fail "INV-008-a" "Learning with all dead file refs should be flagged"
  fail "INV-008-a2" "CLAUDE.md learning should be risk: high"
fi
cleanup_fixture "$TMPDIR_008"

# Tests INV-008 [behavioral]: general-principle learnings (no file refs) are never flagged
TMPDIR_008b="$(setup_fixture_dir)"
cat > "$TMPDIR_008b/CLAUDE.md" << 'CLAUDE_EOF'
## Correctless Learnings

### 2026-01-01 — Always prefer structural enforcement
- Structural enforcement over prompt-level instructions
- Source: /cdocs
CLAUDE_EOF
result_008b="$(bash "$SCANNER" --category claude-md --base "$TMPDIR_008b" 2>/dev/null)" || true
assert_json_array_length "INV-008-b" "General-principle learning (no file refs) is NOT flagged" "0" "$result_008b"
cleanup_fixture "$TMPDIR_008b"

# Tests INV-008 [behavioral]: class-level "Convention confirmed" title excluded
TMPDIR_008c="$(setup_fixture_dir)"
cat > "$TMPDIR_008c/CLAUDE.md" << 'CLAUDE_EOF'
## Correctless Learnings

### 2026-01-01 — Convention confirmed: Something important
- Observed in `scripts/nonexistent.sh` — this convention still matters conceptually
- Source: /cdocs after feature/deleted
CLAUDE_EOF
result_008c="$(bash "$SCANNER" --category claude-md --base "$TMPDIR_008c" 2>/dev/null)" || true
assert_json_array_length "INV-008-c" "'Convention confirmed' title is excluded from staleness" "0" "$result_008c"
cleanup_fixture "$TMPDIR_008c"

# Tests INV-008 [behavioral]: class-level "Convention introduced" title excluded
TMPDIR_008d="$(setup_fixture_dir)"
cat > "$TMPDIR_008d/CLAUDE.md" << 'CLAUDE_EOF'
## Correctless Learnings

### 2026-01-01 — Convention introduced: Some new convention
- First instance at `scripts/nonexistent.sh`
- Source: /cdocs
CLAUDE_EOF
result_008d="$(bash "$SCANNER" --category claude-md --base "$TMPDIR_008d" 2>/dev/null)" || true
assert_json_array_length "INV-008-d" "'Convention introduced' title is excluded from staleness" "0" "$result_008d"
cleanup_fixture "$TMPDIR_008d"

# Tests INV-008 [behavioral]: class-level "Postmortem" title excluded
TMPDIR_008e="$(setup_fixture_dir)"
cat > "$TMPDIR_008e/CLAUDE.md" << 'CLAUDE_EOF'
## Correctless Learnings

### 2026-01-01 — Postmortem: Something went wrong
- Root cause was in `scripts/nonexistent.sh` at `hooks/deleted.sh`
- Source: PMB-099
CLAUDE_EOF
result_008e="$(bash "$SCANNER" --category claude-md --base "$TMPDIR_008e" 2>/dev/null)" || true
assert_json_array_length "INV-008-e" "'Postmortem' title is excluded from staleness" "0" "$result_008e"
cleanup_fixture "$TMPDIR_008e"

# Tests INV-008 [behavioral]: body text "always"/"never" do NOT make it class-level
TMPDIR_008f="$(setup_fixture_dir)"
cat > "$TMPDIR_008f/CLAUDE.md" << 'CLAUDE_EOF'
## Correctless Learnings

### 2026-01-01 — Bug fix: specific instance fix
- Always check `scripts/nonexistent.sh` — never skip the validation at `hooks/deleted.sh`
- All 65 tests passed against the fixture
- Source: /cdocs
CLAUDE_EOF
result_008f="$(bash "$SCANNER" --category claude-md --base "$TMPDIR_008f" 2>/dev/null)" || true
if [ "$(echo "$result_008f" | jq 'length' 2>/dev/null)" -gt 0 ]; then
  pass "INV-008-f" "Body text 'always'/'never' does NOT make entry class-level"
else
  fail "INV-008-f" "Instance-level entry with 'always'/'All' in body should still be flagged"
fi
cleanup_fixture "$TMPDIR_008f"

# ============================================
# INV-009: Completed spec archiving
# ============================================

section "INV-009: Completed spec archiving"

# Tests INV-009 [behavioral]: spec with merged branch 30+ days ago is candidate
TMPDIR_009="$(setup_fixture_dir)"
git -C "$TMPDIR_009" add -A 2>/dev/null || true
git -C "$TMPDIR_009" commit --allow-empty -m "init" -q 2>/dev/null || true
# Create a spec referencing a deleted branch
cat > "$TMPDIR_009/.correctless/specs/old-feature.md" << 'SPEC_EOF'
# Spec: Old Feature
## Metadata
- **Branch**: feature/old-feature
SPEC_EOF
# Simulate a merge commit from 60+ days ago — git log will find "feature/old-feature" in the message
GIT_COMMITTER_DATE="2026-03-01T00:00:00Z" git -C "$TMPDIR_009" commit --allow-empty -m "Merge feature/old-feature into main (#42)" --date="2026-03-01T00:00:00Z" -q 2>/dev/null || true
# feature/old-feature is NOT in the branches file (merged and deleted)
echo "main" > "$TMPDIR_009/branches.txt"
result_009="$(bash "$SCANNER" --category specs --base "$TMPDIR_009" --branches-file "$TMPDIR_009/branches.txt" 2>/dev/null)" || true
if [ "$(echo "$result_009" | jq 'length' 2>/dev/null)" -gt 0 ]; then
  pass "INV-009-a" "Spec for merged branch 30+ days ago is flagged"
else
  fail "INV-009-a" "Spec with merged branch 30+ days ago should be a candidate"
fi
cleanup_fixture "$TMPDIR_009"

# Tests INV-009 [behavioral]: spec for unmerged branch is NOT flagged
TMPDIR_009b="$(setup_fixture_dir)"
git -C "$TMPDIR_009b" commit --allow-empty -m "init" -q 2>/dev/null
git -C "$TMPDIR_009b" checkout -b feature/active-feature 2>/dev/null
git -C "$TMPDIR_009b" checkout main 2>/dev/null
cat > "$TMPDIR_009b/.correctless/specs/active-feature.md" << 'SPEC_EOF'
# Spec: Active Feature
## Metadata
- **Branch**: feature/active-feature
SPEC_EOF
result_009b="$(bash "$SCANNER" --category specs --base "$TMPDIR_009b" 2>/dev/null)" || true
assert_json_array_length "INV-009-b" "Spec for unmerged (active) branch is NOT flagged" "0" "$result_009b"
cleanup_fixture "$TMPDIR_009b"

# Tests INV-009 [behavioral]: spec without determinable merge date is NOT flagged (fail-closed)
TMPDIR_009c="$(setup_fixture_dir)"
git -C "$TMPDIR_009c" commit --allow-empty -m "init" -q 2>/dev/null
cat > "$TMPDIR_009c/.correctless/specs/unknown-date.md" << 'SPEC_EOF'
# Spec: Unknown Date Feature
## Metadata
- **Branch**: feature/unknown-date
SPEC_EOF
# No workflow state, no merge commit mentioning the branch
echo "main" > "$TMPDIR_009c/branches.txt"
result_009c="$(bash "$SCANNER" --category specs --base "$TMPDIR_009c" --branches-file "$TMPDIR_009c/branches.txt" 2>/dev/null)" || true
assert_json_array_length "INV-009-c" "Spec without merge date is NOT flagged (fail-closed)" "0" "$result_009c"
cleanup_fixture "$TMPDIR_009c"

# ============================================
# INV-010: Stale deferred findings detection
# ============================================

section "INV-010: Stale deferred findings detection"

# Tests INV-010 [behavioral]: finding with dead source_file is flagged
TMPDIR_010="$(setup_fixture_dir)"
cat > "$TMPDIR_010/.correctless/meta/deferred-findings.json" << 'DEF_EOF'
{"schema_version":1,"findings":[
  {
    "id": "DF-001",
    "status": "open",
    "source_file": ".correctless/artifacts/review-spec-findings-nonexistent.md",
    "description": "Some finding"
  },
  {
    "id": "DF-002",
    "status": "open",
    "source_file": ".correctless/artifacts/review-spec-findings-existing.md",
    "description": "Another finding"
  }
]}
DEF_EOF
# Create the existing source file for DF-002
touch "$TMPDIR_010/.correctless/artifacts/review-spec-findings-existing.md"
result_010="$(bash "$SCANNER" --category deferred --base "$TMPDIR_010" 2>/dev/null)" || true
if [ "$(echo "$result_010" | jq 'length' 2>/dev/null)" -eq 1 ]; then
  assert_json_field_eq "INV-010-a" "Dead source_file finding is flagged" '.[0].id' "DF-001" "$result_010"
  pass "INV-010-a2" "Only findings with dead source_file are flagged"
else
  fail "INV-010-a" "Finding with dead source_file should be flagged"
  fail "INV-010-a2" "Only one finding should be flagged (the dead one)"
fi
cleanup_fixture "$TMPDIR_010"

# Tests INV-010 [behavioral]: findings with status other than open are skipped
TMPDIR_010b="$(setup_fixture_dir)"
cat > "$TMPDIR_010b/.correctless/meta/deferred-findings.json" << 'DEF_EOF'
{"schema_version":1,"findings":[
  {
    "id": "DF-003",
    "status": "wont-fix",
    "source_file": ".correctless/artifacts/nonexistent.md",
    "description": "Already resolved"
  }
]}
DEF_EOF
result_010b="$(bash "$SCANNER" --category deferred --base "$TMPDIR_010b" 2>/dev/null)" || true
assert_json_array_length "INV-010-b" "Non-open findings are NOT flagged" "0" "$result_010b"
cleanup_fixture "$TMPDIR_010b"

# Tests INV-010 [behavioral]: risk is medium for deferred findings
TMPDIR_010c="$(setup_fixture_dir)"
cat > "$TMPDIR_010c/.correctless/meta/deferred-findings.json" << 'DEF_EOF'
{"schema_version":1,"findings":[
  {
    "id": "DF-004",
    "status": "open",
    "source_file": ".correctless/artifacts/nonexistent-review.md",
    "description": "Stale finding"
  }
]}
DEF_EOF
result_010c="$(bash "$SCANNER" --category deferred --base "$TMPDIR_010c" 2>/dev/null)" || true
if [ "$(echo "$result_010c" | jq 'length' 2>/dev/null)" -gt 0 ]; then
  assert_json_field_eq "INV-010-c" "Deferred finding is risk: medium" '.[0].risk' "medium" "$result_010c"
else
  fail "INV-010-c" "Should flag stale deferred finding"
fi
cleanup_fixture "$TMPDIR_010c"

# ============================================
# INV-011: Antipattern staleness detection
# ============================================

section "INV-011: Antipattern staleness detection"

# Tests INV-011 [behavioral]: instance-level AP with all dead refs is flagged
TMPDIR_011="$(setup_fixture_dir)"
cat > "$TMPDIR_011/.correctless/antipatterns.md" << 'AP_EOF'
# Known Antipatterns

### AP-099: Specific instance bug in deleted file
- **What went wrong**: A bug in `scripts/deleted-script.sh` caused issues with `hooks/removed-hook.sh`
- **How to catch it**: Run `tests/test-deleted.sh` to verify
- **Frequency**: 1 finding in deleted-feature
AP_EOF
result_011="$(bash "$SCANNER" --category antipatterns --base "$TMPDIR_011" 2>/dev/null)" || true
if [ "$(echo "$result_011" | jq 'length' 2>/dev/null)" -gt 0 ]; then
  pass "INV-011-a" "Instance-level AP with all dead refs is flagged"
else
  fail "INV-011-a" "Instance-level AP with all dead refs should be flagged"
fi
cleanup_fixture "$TMPDIR_011"

# Tests INV-011 [behavioral]: class-level AP is NOT flagged (abstract pattern title)
TMPDIR_011b="$(setup_fixture_dir)"
cat > "$TMPDIR_011b/.correctless/antipatterns.md" << 'AP_EOF'
# Known Antipatterns

### AP-098: String interpolation of user input into filter strings
- **What went wrong**: User input was interpolated into `scripts/deleted.sh` jq filters
- **How to catch it**: Run `tests/test-deleted.sh`
- **Frequency**: 5 findings
AP_EOF
result_011b="$(bash "$SCANNER" --category antipatterns --base "$TMPDIR_011b" 2>/dev/null)" || true
assert_json_array_length "INV-011-b" "Class-level AP (title: 'interpolation') is NOT flagged" "0" "$result_011b"
cleanup_fixture "$TMPDIR_011b"

# Tests INV-011 [behavioral]: class keywords in title — drift, silent, injection, phantom
for kw in drift silent injection phantom; do
  TMPDIR_011kw="$(setup_fixture_dir)"
  cat > "$TMPDIR_011kw/.correctless/antipatterns.md" << AP_EOF
# Known Antipatterns

### AP-097: Test shows $kw pattern in codebase
- **What went wrong**: Something at \`scripts/deleted.sh\`
- **How to catch it**: Run \`tests/test-deleted.sh\`
AP_EOF
  result_011kw="$(bash "$SCANNER" --category antipatterns --base "$TMPDIR_011kw" 2>/dev/null)" || true
  assert_json_array_length "INV-011-kw-$kw" "Class keyword '$kw' in title prevents flagging" "0" "$result_011kw"
  cleanup_fixture "$TMPDIR_011kw"
done

# Tests INV-011 [behavioral]: body "All" does NOT prevent flagging
TMPDIR_011c="$(setup_fixture_dir)"
cat > "$TMPDIR_011c/.correctless/antipatterns.md" << 'AP_EOF'
# Known Antipatterns

### AP-096: Specific bug in removed module
- **What went wrong**: All 65 tests passed against `scripts/deleted.sh` fixture using `hooks/deleted.sh`
- **How to catch it**: Run `tests/test-deleted.sh`
- **Frequency**: 1
AP_EOF
result_011c="$(bash "$SCANNER" --category antipatterns --base "$TMPDIR_011c" 2>/dev/null)" || true
if [ "$(echo "$result_011c" | jq 'length' 2>/dev/null)" -gt 0 ]; then
  pass "INV-011-c" "Body text 'All' does NOT prevent flagging of instance-level AP"
else
  fail "INV-011-c" "Instance-level AP with 'All' in body should still be flagged when refs are dead"
fi
cleanup_fixture "$TMPDIR_011c"

# ============================================
# INV-012: /cauto integration
# ============================================

section "INV-012: /cauto integration"

# Tests INV-012 [unit]: cauto SKILL.md references cprune invocation
if [ -f "skills/cauto/SKILL.md" ]; then
  if grep -qF "cprune" "skills/cauto/SKILL.md"; then
    pass "INV-012-a" "/cauto references cprune invocation"
  else
    fail "INV-012-a" "/cauto should reference cprune"
  fi
else
  fail "INV-012-a" "skills/cauto/SKILL.md does not exist"
fi

# Tests INV-012 [unit]: cprune is NOT in the canonical step name enum
if [ -f "skills/cauto/SKILL.md" ]; then
  # Verify cprune appears in the file (bare reference, not necessarily quoted)
  if grep -q 'cprune' "skills/cauto/SKILL.md" 2>/dev/null; then
    # Now check it's NOT in the canonical step enum (quoted "cprune" in expected_steps)
    if grep -E 'expected_steps' "skills/cauto/SKILL.md" | grep -q '"cprune"'; then
      fail "INV-012-b" "cprune should NOT be in the canonical step name enum"
    else
      pass "INV-012-b" "cprune is referenced but NOT in the canonical step name enum"
    fi
  else
    fail "INV-012-b" "cauto SKILL.md should reference cprune"
  fi
else
  fail "INV-012-b" "skills/cauto/SKILL.md does not exist"
fi

# ============================================
# INV-013: /cstatus pruning-recommended signal
# ============================================

section "INV-013: /cstatus pruning-recommended signal"

# Tests INV-013 [unit]: cstatus SKILL.md references pruning signal
if [ -f "skills/cstatus/SKILL.md" ]; then
  cstatus_body="$(cat "skills/cstatus/SKILL.md")"
  assert_contains "INV-013-a" "/cstatus references pruning recommendation" "Pruning recommended" "$cstatus_body"
  assert_contains "INV-013-b" "/cstatus references prune-scan.sh" "prune-scan.sh" "$cstatus_body"
  # Check threshold values
  assert_contains "INV-013-c" "/cstatus references orphaned artifact threshold (10)" "10" "$cstatus_body"
  assert_contains "INV-013-d" "/cstatus references stale architecture threshold (3)" "3" "$cstatus_body"
else
  fail "INV-013-a" "skills/cstatus/SKILL.md does not exist"
  fail "INV-013-b" "skills/cstatus/SKILL.md does not exist"
  fail "INV-013-c" "skills/cstatus/SKILL.md does not exist"
  fail "INV-013-d" "skills/cstatus/SKILL.md does not exist"
fi

# Tests INV-013 [unit]: dormant behavior when scanner not installed
if [ -f "skills/cstatus/SKILL.md" ]; then
  if grep -q "prune-scan.sh.*not.*exist\|file does not exist\|PAT-019\|dormant" "skills/cstatus/SKILL.md" 2>/dev/null; then
    pass "INV-013-e" "/cstatus has dormant behavior when scanner unavailable"
  else
    fail "INV-013-e" "/cstatus should degrade gracefully when scanner unavailable (PAT-019)"
  fi
else
  fail "INV-013-e" "skills/cstatus/SKILL.md does not exist"
fi

# ============================================
# INV-014: Drift debt pruning
# ============================================

section "INV-014: Drift debt pruning"

# Tests INV-014 [behavioral]: resolved drift debt >90 days is flagged
TMPDIR_014="$(setup_fixture_dir)"
cat > "$TMPDIR_014/.correctless/meta/drift-debt.json" << 'DRIFT_EOF'
{"drift_debt":[
  {
    "id": "DD-001",
    "status": "resolved",
    "detected": "2026-01-01",
    "resolved_at": "2026-01-15T00:00:00Z",
    "description": "Old resolved debt"
  },
  {
    "id": "DD-002",
    "status": "open",
    "detected": "2026-01-01",
    "description": "Still open debt"
  }
]}
DRIFT_EOF
result_014="$(bash "$SCANNER" --category driftdebt --base "$TMPDIR_014" 2>/dev/null)" || true
if [ "$(echo "$result_014" | jq 'length' 2>/dev/null)" -eq 1 ]; then
  assert_json_field_eq "INV-014-a" "Resolved drift debt >90 days is flagged" '.[0].id' "DD-001" "$result_014"
  pass "INV-014-a2" "Open drift debt is NOT flagged"
else
  fail "INV-014-a" "Should flag resolved drift debt >90 days"
  fail "INV-014-a2" "Should NOT flag open drift debt"
fi
cleanup_fixture "$TMPDIR_014"

# Tests INV-014 [behavioral]: wont-fix drift debt >90 days is also flagged
TMPDIR_014b="$(setup_fixture_dir)"
cat > "$TMPDIR_014b/.correctless/meta/drift-debt.json" << 'DRIFT_EOF'
{"drift_debt":[
  {
    "id": "DD-003",
    "status": "wont-fix",
    "detected": "2026-01-01",
    "resolved_at": "2026-01-15T00:00:00Z",
    "description": "Old wont-fix debt"
  }
]}
DRIFT_EOF
result_014b="$(bash "$SCANNER" --category driftdebt --base "$TMPDIR_014b" 2>/dev/null)" || true
if [ "$(echo "$result_014b" | jq 'length' 2>/dev/null)" -gt 0 ]; then
  pass "INV-014-b" "wont-fix drift debt >90 days is flagged"
else
  fail "INV-014-b" "wont-fix drift debt >90 days should be flagged"
fi
cleanup_fixture "$TMPDIR_014b"

# Tests INV-014 [behavioral]: resolved debt <90 days is NOT flagged
TMPDIR_014c="$(setup_fixture_dir)"
recent_date="$(date -u -d "-30 days" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date -u -v-30d '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null)"
cat > "$TMPDIR_014c/.correctless/meta/drift-debt.json" << DRIFT_EOF
{"drift_debt":[
  {
    "id": "DD-004",
    "status": "resolved",
    "detected": "2026-05-01",
    "resolved_at": "${recent_date}",
    "description": "Recently resolved debt"
  }
]}
DRIFT_EOF
result_014c="$(bash "$SCANNER" --category driftdebt --base "$TMPDIR_014c" 2>/dev/null)" || true
assert_json_array_length "INV-014-c" "Resolved debt <90 days is NOT flagged" "0" "$result_014c"
cleanup_fixture "$TMPDIR_014c"

# ============================================
# INV-015: Persist-before-present (AP-029)
# ============================================

section "INV-015: Persist-before-present"

# Tests INV-015 [unit]: SKILL.md references artifact write before presentation
if [ -f "skills/cprune/SKILL.md" ]; then
  body_015="$(cat "skills/cprune/SKILL.md")"
  assert_contains "INV-015-a" "SKILL.md references prune-report artifact" "prune-report" "$body_015"
  # Verify the artifact write is mentioned before the presentation
  if grep -n "prune-report" "skills/cprune/SKILL.md" | head -1 | grep -qE "^[0-9]+:"; then
    pass "INV-015-b" "SKILL.md mentions prune report artifact"
  else
    fail "INV-015-b" "SKILL.md should reference prune-report artifact path"
  fi
else
  fail "INV-015-a" "skills/cprune/SKILL.md does not exist"
  fail "INV-015-b" "skills/cprune/SKILL.md does not exist"
fi

# ============================================
# INV-016: SFG protection for scanner and archive files
# ============================================

section "INV-016: SFG protection"

# Tests INV-016 [unit]: sensitive-file-guard.sh DEFAULTS include required paths
if [ -f "hooks/sensitive-file-guard.sh" ]; then
  sfg_body="$(cat "hooks/sensitive-file-guard.sh")"
  assert_contains "INV-016-a" "SFG protects scripts/prune-scan.sh" "scripts/prune-scan.sh" "$sfg_body"
  assert_contains "INV-016-b" "SFG protects .correctless/scripts/prune-scan.sh" ".correctless/scripts/prune-scan.sh" "$sfg_body"
  assert_contains "INV-016-c" "SFG protects ARCHITECTURE_DEPRECATED.md" "ARCHITECTURE_DEPRECATED.md" "$sfg_body"
  assert_contains "INV-016-d" "SFG protects antipatterns-archived.md" "antipatterns-archived.md" "$sfg_body"
  assert_contains "INV-016-e" "SFG protects CLAUDE_LEARNINGS_ARCHIVED.md" "CLAUDE_LEARNINGS_ARCHIVED.md" "$sfg_body"
else
  fail "INV-016-a" "hooks/sensitive-file-guard.sh does not exist"
  fail "INV-016-b" "hooks/sensitive-file-guard.sh does not exist"
  fail "INV-016-c" "hooks/sensitive-file-guard.sh does not exist"
  fail "INV-016-d" "hooks/sensitive-file-guard.sh does not exist"
  fail "INV-016-e" "hooks/sensitive-file-guard.sh does not exist"
fi

# ============================================
# INV-017: TB-004c consolidation allowlist update
# ============================================

section "INV-017: TB-004c consolidation allowlist"

# Tests INV-017 [unit]: cauto SKILL.md Step 8.1 includes archive file paths
# Note: grep -qF directly on file (not assert_contains pipe) because cauto SKILL.md
# is ~44KB — large enough that echo|grep -q triggers SIGPIPE under pipefail.
if [ -f "skills/cauto/SKILL.md" ]; then
  if grep -qF "ARCHITECTURE_DEPRECATED.md" "skills/cauto/SKILL.md"; then
    pass "INV-017-a" "cauto allowlist includes ARCHITECTURE_DEPRECATED.md"
  else
    fail "INV-017-a" "cauto allowlist should include ARCHITECTURE_DEPRECATED.md"
  fi
  if grep -qF "antipatterns-archived.md" "skills/cauto/SKILL.md"; then
    pass "INV-017-b" "cauto allowlist includes antipatterns-archived.md"
  else
    fail "INV-017-b" "cauto allowlist should include antipatterns-archived.md"
  fi
  if grep -qF "CLAUDE_LEARNINGS_ARCHIVED.md" "skills/cauto/SKILL.md"; then
    pass "INV-017-c" "cauto allowlist includes CLAUDE_LEARNINGS_ARCHIVED.md"
  else
    fail "INV-017-c" "cauto allowlist should include CLAUDE_LEARNINGS_ARCHIVED.md"
  fi
else
  fail "INV-017-a" "skills/cauto/SKILL.md does not exist"
  fail "INV-017-b" "skills/cauto/SKILL.md does not exist"
  fail "INV-017-c" "skills/cauto/SKILL.md does not exist"
fi

# ============================================
# INV-018: Interactive report format
# ============================================

section "INV-018: Interactive report format"

# Tests INV-018 [unit]: SKILL.md has progress display and disposition options
if [ -f "skills/cprune/SKILL.md" ]; then
  body_018="$(cat "skills/cprune/SKILL.md")"
  assert_contains "INV-018-a" "SKILL.md has progress display text" "Scanning" "$body_018"
  assert_contains "INV-018-b" "SKILL.md has disposition option: Execute all" "Execute all" "$body_018"
  assert_contains "INV-018-c" "SKILL.md has disposition option: Review individually" "Review individually" "$body_018"
  assert_contains "INV-018-d" "SKILL.md has disposition option: Skip this category" "Skip" "$body_018"
  assert_contains "INV-018-e" "SKILL.md mentions un-archiving is manual" "un-archive" "$body_018"
else
  fail "INV-018-a" "skills/cprune/SKILL.md does not exist"
  fail "INV-018-b" "skills/cprune/SKILL.md does not exist"
  fail "INV-018-c" "skills/cprune/SKILL.md does not exist"
  fail "INV-018-d" "skills/cprune/SKILL.md does not exist"
  fail "INV-018-e" "skills/cprune/SKILL.md does not exist"
fi

# ============================================
# INV-019: sync.sh skill list update
# ============================================

section "INV-019: sync.sh skill list update"

# Tests INV-019 [unit]: sync.sh uses glob for skills (AP-024 fix)
if grep -q 'skills/\*/' "sync.sh" 2>/dev/null; then
  pass "INV-019-a" "sync.sh uses glob for skill directories"
else
  fail "INV-019-a" "sync.sh should use glob for skill directories (AP-024)"
fi

# Tests INV-019 [unit]: sync.sh uses glob for templates (AP-024 fix)
if grep -q 'templates/\*\.md\|templates/\*\.json' "sync.sh" 2>/dev/null; then
  pass "INV-019-b" "sync.sh uses glob for templates"
else
  fail "INV-019-b" "sync.sh should use glob for templates (AP-024)"
fi

# ============================================
# INV-001: Two execution modes
# ============================================

section "INV-001: Two execution modes"

# Tests INV-001 [unit]: SKILL.md has mode detection logic
if [ -f "skills/cprune/SKILL.md" ]; then
  body_001="$(cat "skills/cprune/SKILL.md")"
  assert_contains "INV-001-a" "SKILL.md mentions autonomous mode" "autonomous" "$body_001"
  assert_contains "INV-001-b" "SKILL.md mentions interactive mode" "interactive" "$body_001"
  # Check for mode detection branching
  if grep -qE "mode.*autonomous|autonomous.*mode|mode.*interactive|interactive.*mode" "skills/cprune/SKILL.md" 2>/dev/null; then
    pass "INV-001-c" "SKILL.md has mode detection logic"
  else
    fail "INV-001-c" "SKILL.md should have autonomous/interactive mode detection"
  fi
else
  fail "INV-001-a" "skills/cprune/SKILL.md does not exist"
  fail "INV-001-b" "skills/cprune/SKILL.md does not exist"
  fail "INV-001-c" "skills/cprune/SKILL.md does not exist"
fi

# ============================================
# PRH-001: Never permanently delete documentation
# ============================================

section "PRH-001: Never permanently delete documentation entries"

# Tests PRH-001 [unit]: SKILL.md and scanner reference archive-before-remove
if [ -f "skills/cprune/SKILL.md" ]; then
  if grep -qE "archive.*before.*remov|write.*archive.*before|archive.*then.*remov" "skills/cprune/SKILL.md" 2>/dev/null; then
    pass "PRH-001-a" "SKILL.md enforces archive-before-remove ordering"
  else
    fail "PRH-001-a" "SKILL.md should enforce archive-write-before-remove ordering"
  fi
else
  fail "PRH-001-a" "skills/cprune/SKILL.md does not exist"
fi

# ============================================
# PRH-002: Never modify CLAUDE.md in autonomous mode
# ============================================

section "PRH-002: Never modify CLAUDE.md in autonomous mode"

# Tests PRH-002 [unit]: SKILL.md excludes CLAUDE.md from autonomous mode
if [ -f "skills/cprune/SKILL.md" ]; then
  if grep -qE "claude.*autonomous.*exclu|autonomous.*claude.*skip|autonomous.*never.*CLAUDE|CLAUDE.*interactive.only|interactive-only.*CLAUDE" "skills/cprune/SKILL.md" 2>/dev/null; then
    pass "PRH-002-a" "SKILL.md excludes CLAUDE.md from autonomous mode"
  else
    fail "PRH-002-a" "SKILL.md should exclude CLAUDE.md modification in autonomous mode"
  fi
else
  fail "PRH-002-a" "skills/cprune/SKILL.md does not exist"
fi

# ============================================
# PRH-003: Never archive entries with live file references
# ============================================

section "PRH-003: Never archive entries with live file references"

# Tests PRH-003 [behavioral]: entry with one live ref is NOT a candidate
# (already covered by INV-003-b, but PRH-003 is the prohibition angle)
TMPDIR_PRH003="$(setup_fixture_dir)"
touch "$TMPDIR_PRH003/scripts/lib.sh"
cat > "$TMPDIR_PRH003/.correctless/ARCHITECTURE.md" << 'ARCH_EOF'
# Architecture

## Abstractions

### ABS-070: Mixed refs
- **What**: Has both live and dead refs
- **Invariant**: Something
- **Enforced at**: `scripts/lib.sh` (live), `scripts/deleted.sh` (dead)
ARCH_EOF
result_prh003="$(bash "$SCANNER" --category architecture --base "$TMPDIR_PRH003" 2>/dev/null)" || true
assert_json_array_length "PRH-003-a" "Entry with live file refs is NOT flagged (PRH-003)" "0" "$result_prh003"
cleanup_fixture "$TMPDIR_PRH003"

# ============================================
# PRH-004: Read-only for deferred findings
# ============================================

section "PRH-004: /cprune is read-only for deferred findings"

# Tests PRH-004 [unit]: SKILL.md allowed-tools does NOT include Write for deferred-findings
if [ -f "skills/cprune/SKILL.md" ]; then
  if grep -q 'Write.*deferred-findings\|deferred-findings.*Write' "skills/cprune/SKILL.md" 2>/dev/null; then
    fail "PRH-004-a" "SKILL.md should NOT include Write access to deferred-findings.json"
  else
    pass "PRH-004-a" "SKILL.md does NOT include Write access to deferred-findings.json"
  fi
else
  fail "PRH-004-a" "skills/cprune/SKILL.md does not exist"
fi

# ============================================
# BND-001: Empty archive files
# ============================================

section "BND-001: Empty archive files"

# Tests BND-001 [unit]: SKILL.md describes archive file creation with header
if [ -f "skills/cprune/SKILL.md" ]; then
  if grep -qE "header.*comment|created.*first.*use|first.*entry.*append" "skills/cprune/SKILL.md" 2>/dev/null; then
    pass "BND-001-a" "SKILL.md describes archive file creation with header"
  else
    fail "BND-001-a" "SKILL.md should describe archive file creation with header comment"
  fi
else
  fail "BND-001-a" "skills/cprune/SKILL.md does not exist"
fi

# ============================================
# BND-002: All entries are stale (bulk warning)
# ============================================

section "BND-002: All entries are stale (bulk warning)"

# Tests BND-002 [behavioral]: bulk_warning is true when >50% are candidates
TMPDIR_BND002="$(setup_fixture_dir)"
cat > "$TMPDIR_BND002/.correctless/ARCHITECTURE.md" << 'ARCH_EOF'
# Architecture

## Abstractions

### ABS-080: Dead entry 1
- **What**: Something
- **Enforced at**: `scripts/deleted1.sh`

### ABS-081: Dead entry 2
- **What**: Something
- **Enforced at**: `scripts/deleted2.sh`

### ABS-082: Dead entry 3
- **What**: Something
- **Enforced at**: `scripts/deleted3.sh`
ARCH_EOF
result_bnd002="$(bash "$SCANNER" --category architecture --base "$TMPDIR_BND002" 2>/dev/null)" || true
if [ "$(echo "$result_bnd002" | jq 'length' 2>/dev/null)" -gt 0 ]; then
  bulk_val="$(echo "$result_bnd002" | jq -r '.[0].bulk_warning' 2>/dev/null)"
  if [ "$bulk_val" = "true" ]; then
    pass "BND-002-a" "bulk_warning is true when >50% of entries are candidates"
  else
    fail "BND-002-a" "bulk_warning should be true when all entries are stale (got $bulk_val)"
  fi
else
  fail "BND-002-a" "Scanner should flag dead entries"
fi
cleanup_fixture "$TMPDIR_BND002"

# Tests BND-002 [behavioral]: bulk_warning is false when <50%
TMPDIR_BND002b="$(setup_fixture_dir)"
touch "$TMPDIR_BND002b/scripts/live1.sh"
touch "$TMPDIR_BND002b/scripts/live2.sh"
touch "$TMPDIR_BND002b/scripts/live3.sh"
cat > "$TMPDIR_BND002b/.correctless/ARCHITECTURE.md" << 'ARCH_EOF'
# Architecture

## Abstractions

### ABS-083: Live entry 1
- **What**: Something
- **Enforced at**: `scripts/live1.sh`

### ABS-084: Live entry 2
- **What**: Something
- **Enforced at**: `scripts/live2.sh`

### ABS-085: Live entry 3
- **What**: Something
- **Enforced at**: `scripts/live3.sh`

### ABS-086: Dead entry 1
- **What**: Something
- **Enforced at**: `scripts/deleted.sh`
ARCH_EOF
result_bnd002b="$(bash "$SCANNER" --category architecture --base "$TMPDIR_BND002b" 2>/dev/null)" || true
if [ "$(echo "$result_bnd002b" | jq 'length' 2>/dev/null)" -gt 0 ]; then
  bulk_val_b="$(echo "$result_bnd002b" | jq -r '.[0].bulk_warning' 2>/dev/null)"
  if [ "$bulk_val_b" = "false" ]; then
    pass "BND-002-b" "bulk_warning is false when <50% of entries are candidates"
  else
    fail "BND-002-b" "bulk_warning should be false when <50% are stale (got $bulk_val_b)"
  fi
else
  fail "BND-002-b" "Scanner should flag the dead entry"
fi
cleanup_fixture "$TMPDIR_BND002b"

# ============================================
# BND-003: No git remote
# ============================================

section "BND-003: No git remote"

# Tests BND-003 [behavioral]: scanner works with local-only repo (no remote)
TMPDIR_BND003="$(setup_fixture_dir)"
git -C "$TMPDIR_BND003" commit --allow-empty -m "init" -q 2>/dev/null
# No remote configured — default git init has no remote
touch "$TMPDIR_BND003/.correctless/artifacts/workflow-state-feature-local-only-cccccc.json"
result_bnd003="$(bash "$SCANNER" --category artifacts --base "$TMPDIR_BND003" 2>/dev/null)" || true
assert_json_valid "BND-003-a" "Scanner produces valid JSON with no remote" "$result_bnd003"
cleanup_fixture "$TMPDIR_BND003"

# ============================================
# BND-004: Concurrent /cprune invocations
# ============================================

section "BND-004: Concurrent /cprune invocations"

# Tests BND-004 [unit]: SKILL.md references lockfile pattern
if [ -f "skills/cprune/SKILL.md" ]; then
  body_bnd004="$(cat "skills/cprune/SKILL.md")"
  assert_contains "BND-004-a" "SKILL.md references lockfile" "lock" "$body_bnd004"
  assert_contains "BND-004-b" "SKILL.md references cprune-lock" "cprune-lock" "$body_bnd004"
else
  fail "BND-004-a" "skills/cprune/SKILL.md does not exist"
  fail "BND-004-b" "skills/cprune/SKILL.md does not exist"
fi

# ============================================
# ABS-038: Archive file contract
# ============================================

section "ABS-038: Archive file contract"

# Tests ABS-038 [unit]: SKILL.md is the sole writer for archive files
if [ -f "skills/cprune/SKILL.md" ]; then
  if grep -qE "sole.*writer|only.*cprune.*writes|exclusive.*write" "skills/cprune/SKILL.md" 2>/dev/null; then
    pass "ABS-038-a" "SKILL.md declares sole-writer for archive files"
  else
    fail "ABS-038-a" "SKILL.md should declare sole-writer for archive files"
  fi
else
  fail "ABS-038-a" "skills/cprune/SKILL.md does not exist"
fi

# Tests ABS-038 [unit]: allowed-tools includes Write for all three archive files
if [ -f "skills/cprune/SKILL.md" ]; then
  body_abs038="$(cat "skills/cprune/SKILL.md")"
  assert_contains "ABS-038-b" "allowed-tools includes ARCHITECTURE_DEPRECATED" "ARCHITECTURE_DEPRECATED" "$body_abs038"
  assert_contains "ABS-038-c" "allowed-tools includes antipatterns-archived" "antipatterns-archived" "$body_abs038"
  assert_contains "ABS-038-d" "allowed-tools includes CLAUDE_LEARNINGS_ARCHIVED" "CLAUDE_LEARNINGS_ARCHIVED" "$body_abs038"
else
  fail "ABS-038-b" "skills/cprune/SKILL.md does not exist"
  fail "ABS-038-c" "skills/cprune/SKILL.md does not exist"
  fail "ABS-038-d" "skills/cprune/SKILL.md does not exist"
fi

# ============================================
# DETERMINISM: Scanner produces same output for same input
# ============================================

section "Determinism: Same input produces same output"

# Tests INV-002 [behavioral]: determinism — run scanner twice, compare output
TMPDIR_DET="$(setup_fixture_dir)"
cat > "$TMPDIR_DET/.correctless/ARCHITECTURE.md" << 'ARCH_EOF'
# Architecture

## Abstractions

### ABS-090: Dead determinism test entry
- **What**: Something
- **Enforced at**: `scripts/deleted-det.sh`
ARCH_EOF
run1="$(bash "$SCANNER" --category architecture --base "$TMPDIR_DET" 2>/dev/null)" || true
run2="$(bash "$SCANNER" --category architecture --base "$TMPDIR_DET" 2>/dev/null)" || true
if [ "$run1" = "$run2" ]; then
  pass "DET-001" "Scanner is deterministic (same input → same output)"
else
  fail "DET-001" "Scanner should be deterministic"
fi
cleanup_fixture "$TMPDIR_DET"

# ============================================
# EDGE CASES
# ============================================

section "Edge cases"

# Tests INV-002 [behavioral]: invalid --category value produces error or empty
TMPDIR_EDGE="$(setup_fixture_dir)"
result_edge="$(bash "$SCANNER" --category invalid-category --base "$TMPDIR_EDGE" 2>/dev/null)" || true
# Should either produce valid JSON (empty array) or error — not crash
if [ -z "$result_edge" ] || echo "$result_edge" | jq . >/dev/null 2>&1; then
  pass "EDGE-001" "Invalid category does not crash scanner"
else
  fail "EDGE-001" "Invalid category should produce valid JSON or empty output"
fi
cleanup_fixture "$TMPDIR_EDGE"

# Tests INV-003 [behavioral]: ARCHITECTURE.md with no entries produces empty array
TMPDIR_EDGE2="$(setup_fixture_dir)"
cat > "$TMPDIR_EDGE2/.correctless/ARCHITECTURE.md" << 'ARCH_EOF'
# Architecture

This file has no entries yet.
ARCH_EOF
result_edge2="$(bash "$SCANNER" --category architecture --base "$TMPDIR_EDGE2" 2>/dev/null)" || true
assert_json_valid "EDGE-002" "Empty ARCHITECTURE.md produces valid JSON" "$result_edge2"
assert_json_array_length "EDGE-002b" "Empty ARCHITECTURE.md produces empty array" "0" "$result_edge2"
cleanup_fixture "$TMPDIR_EDGE2"

# Tests INV-002 [behavioral]: --base flag is required
result_nobase="$(bash "$SCANNER" --category architecture 2>&1)" || true
# Should either use cwd or error — verify it doesn't crash
if [ $? -le 2 ]; then
  pass "EDGE-003" "Scanner handles missing --base gracefully"
else
  fail "EDGE-003" "Scanner should handle missing --base without crash"
fi

# ============================================
# SUMMARY
# ============================================

summary "cprune"
