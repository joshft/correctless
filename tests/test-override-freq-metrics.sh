#!/usr/bin/env bash
# Correctless — Override Frequency Metrics test suite
# Tests R-001 through R-006 from the override-freq-metrics spec.
# RED phase: these tests MUST FAIL — implementation does not exist yet.
# Run from repo root: bash tests/test-override-freq-metrics.sh

set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0
FAIL=0

# ============================================
# Helpers (matching project test conventions)
# ============================================

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
  if ! echo "$actual" | grep -qF "$unexpected"; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (expected output NOT to contain '$unexpected')"
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
    echo "  FAIL: $desc (file '$path' should not exist)"
    FAIL=$((FAIL + 1))
  fi
}

file_contains() {
  local file="$1" pattern="$2" desc="$3"
  if grep -q "$pattern" "$file" 2>/dev/null; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (pattern '$pattern' not found in $file)"
    FAIL=$((FAIL + 1))
  fi
}

# ============================================
# Source scripts at top level to avoid RETURN trap + source interaction
source "$REPO_DIR/scripts/override-scrutiny.sh"

# ============================================
# R-001 [unit]: Preserve override logs on /cauto completion
# ============================================

test_r001_preserved_file_created() {
  echo ""
  echo "=== R-001: Preserved file created at correct path with metadata wrapper ==="

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN

  # Set up override log with entries from the current branch
  mkdir -p "$TEST_DIR/.correctless/artifacts"
  mkdir -p "$TEST_DIR/.correctless/meta/overrides"
  cat > "$TEST_DIR/.correctless/artifacts/override-log.json" << 'EOF'
[
  {"phase": "tdd-impl", "reason": "Build fails due to missing stub", "timestamp": "2026-04-10T10:00:00Z", "branch": "feature/my-feature"},
  {"phase": "tdd-qa", "reason": "Test framework issue", "timestamp": "2026-04-10T11:00:00Z", "branch": "feature/my-feature"}
]
EOF

  # Call the preserve function
  local result
  result="$(preserve_override_log "$TEST_DIR" "my-feature" "feature/my-feature" 2>/dev/null)"
  local rc=$?

  assert_eq "R-001: preserve_override_log exits 0" "0" "$rc"

  # Check a preserved file was created
  local preserved_count
  preserved_count="$(find "$TEST_DIR/.correctless/meta/overrides" -name 'my-feature-*.json' 2>/dev/null | wc -l | tr -d ' ')"
  assert_eq "R-001: preserved file exists" "1" "$preserved_count"

  # Check metadata wrapper structure
  local preserved_file
  preserved_file="$(find "$TEST_DIR/.correctless/meta/overrides" -name 'my-feature-*.json' 2>/dev/null | head -1)"
  if [ -n "$preserved_file" ]; then
    local task_slug
    task_slug="$(jq -r '.task_slug' "$preserved_file" 2>/dev/null)" || task_slug=""
    assert_eq "R-001: metadata wrapper has task_slug" "my-feature" "$task_slug"

    local branch
    branch="$(jq -r '.branch' "$preserved_file" 2>/dev/null)" || branch=""
    assert_eq "R-001: metadata wrapper has branch" "feature/my-feature" "$branch"

    local completed_at
    completed_at="$(jq -r '.completed_at' "$preserved_file" 2>/dev/null)" || completed_at=""
    local has_timestamp="no"
    [ -n "$completed_at" ] && [ "$completed_at" != "null" ] && has_timestamp="yes"
    assert_eq "R-001: metadata wrapper has completed_at" "yes" "$has_timestamp"

    local override_count
    override_count="$(jq -r '.override_count' "$preserved_file" 2>/dev/null)" || override_count=""
    assert_eq "R-001: metadata wrapper has override_count=2" "2" "$override_count"

    local overrides_len
    overrides_len="$(jq -r '.overrides | length' "$preserved_file" 2>/dev/null)" || overrides_len=""
    assert_eq "R-001: overrides array has 2 entries" "2" "$overrides_len"
  fi
}

test_r001_branch_filtering() {
  echo ""
  echo "=== R-001: Branch filtering — only current branch's entries preserved ==="

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN

  mkdir -p "$TEST_DIR/.correctless/artifacts"
  mkdir -p "$TEST_DIR/.correctless/meta/overrides"

  # Override log with entries from TWO branches
  cat > "$TEST_DIR/.correctless/artifacts/override-log.json" << 'EOF'
[
  {"phase": "tdd-impl", "reason": "Reason A", "timestamp": "2026-04-10T10:00:00Z", "branch": "feature/my-feature"},
  {"phase": "tdd-qa", "reason": "Reason B", "timestamp": "2026-04-10T11:00:00Z", "branch": "feature/other-feature"},
  {"phase": "tdd-impl", "reason": "Reason C", "timestamp": "2026-04-10T12:00:00Z", "branch": "feature/my-feature"}
]
EOF

  preserve_override_log "$TEST_DIR" "my-feature" "feature/my-feature" 2>/dev/null
  local rc=$?
  assert_eq "R-001: branch filtering exits 0" "0" "$rc"

  local preserved_file
  preserved_file="$(find "$TEST_DIR/.correctless/meta/overrides" -name 'my-feature-*.json' 2>/dev/null | head -1)"
  if [ -n "$preserved_file" ]; then
    local override_count
    override_count="$(jq -r '.override_count' "$preserved_file" 2>/dev/null)" || override_count=""
    assert_eq "R-001: only matching branch entries preserved (count=2)" "2" "$override_count"

    # Verify no entries from feature/other-feature
    local other_entries
    other_entries="$(jq '[.overrides[] | select(.branch == "feature/other-feature")] | length' "$preserved_file" 2>/dev/null)" || other_entries="?"
    assert_eq "R-001: no entries from other branch" "0" "$other_entries"
  else
    assert_eq "R-001: preserved file should exist for branch filtering check" "exists" "missing"
  fi
}

test_r001_zero_override_case() {
  echo ""
  echo "=== R-001: Zero-override case — preserved file has override_count: 0 ==="

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN

  mkdir -p "$TEST_DIR/.correctless/artifacts"
  mkdir -p "$TEST_DIR/.correctless/meta/overrides"

  # Override log with entries from OTHER branches only
  cat > "$TEST_DIR/.correctless/artifacts/override-log.json" << 'EOF'
[
  {"phase": "tdd-impl", "reason": "Reason A", "timestamp": "2026-04-10T10:00:00Z", "branch": "feature/other-feature"}
]
EOF

  preserve_override_log "$TEST_DIR" "my-feature" "feature/my-feature" 2>/dev/null
  local rc=$?
  assert_eq "R-001: zero-override exits 0" "0" "$rc"

  local preserved_file
  preserved_file="$(find "$TEST_DIR/.correctless/meta/overrides" -name 'my-feature-*.json' 2>/dev/null | head -1)"
  if [ -n "$preserved_file" ]; then
    local override_count
    override_count="$(jq -r '.override_count' "$preserved_file" 2>/dev/null)" || override_count=""
    assert_eq "R-001: zero overrides yields override_count=0" "0" "$override_count"

    local overrides_len
    overrides_len="$(jq -r '.overrides | length' "$preserved_file" 2>/dev/null)" || overrides_len=""
    assert_eq "R-001: zero overrides yields empty overrides array" "0" "$overrides_len"
  else
    assert_eq "R-001: preserved file should exist even with zero overrides" "exists" "missing"
  fi
}

test_r001_date_suffix_prevents_collision() {
  echo ""
  echo "=== R-001: Date suffix in filename prevents collision ==="

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN

  mkdir -p "$TEST_DIR/.correctless/artifacts"
  mkdir -p "$TEST_DIR/.correctless/meta/overrides"
  echo '[]' > "$TEST_DIR/.correctless/artifacts/override-log.json"

  preserve_override_log "$TEST_DIR" "my-feature" "feature/my-feature" 2>/dev/null

  local preserved_file
  preserved_file="$(find "$TEST_DIR/.correctless/meta/overrides" -name 'my-feature-*.json' 2>/dev/null | head -1)"
  if [ -n "$preserved_file" ]; then
    local filename
    filename="$(basename "$preserved_file")"
    # Verify filename matches pattern: {task-slug}-{YYYYMMDD}.json
    local has_date_suffix="no"
    if echo "$filename" | grep -qE '^my-feature-[0-9]{8}\.json$'; then
      has_date_suffix="yes"
    fi
    assert_eq "R-001: filename has YYYYMMDD date suffix" "yes" "$has_date_suffix"
  else
    assert_eq "R-001: preserved file should exist for date suffix check" "exists" "missing"
  fi
}

test_r001_missing_override_log() {
  echo ""
  echo "=== R-001: Missing override log — preserved file still created with count 0 ==="

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN

  mkdir -p "$TEST_DIR/.correctless/artifacts"
  mkdir -p "$TEST_DIR/.correctless/meta/overrides"
  # Intentionally no override-log.json

  preserve_override_log "$TEST_DIR" "my-feature" "feature/my-feature" 2>/dev/null
  local rc=$?
  assert_eq "R-001: missing override log exits 0" "0" "$rc"

  local preserved_count
  preserved_count="$(find "$TEST_DIR/.correctless/meta/overrides" -name 'my-feature-*.json' 2>/dev/null | wc -l | tr -d ' ')"
  assert_eq "R-001: preserved file created even without override log" "1" "$preserved_count"

  local preserved_file
  preserved_file="$(find "$TEST_DIR/.correctless/meta/overrides" -name 'my-feature-*.json' 2>/dev/null | head -1)"
  if [ -n "$preserved_file" ]; then
    local override_count
    override_count="$(jq -r '.override_count' "$preserved_file" 2>/dev/null)" || override_count=""
    assert_eq "R-001: missing log yields override_count=0" "0" "$override_count"
  fi
}

# ============================================
# R-002 [unit]: /cdocs includes override count in workflow-history.md
# ============================================

test_r002_override_count_in_history() {
  echo ""
  echo "=== R-002: Override count > 0 appears in workflow-history.md format ==="

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN

  mkdir -p "$TEST_DIR/.correctless/meta/overrides"
  # Create a preserved file with override_count > 0
  cat > "$TEST_DIR/.correctless/meta/overrides/my-feature-20260410.json" << 'EOF'
{"task_slug": "my-feature", "branch": "feature/my-feature", "completed_at": "2026-04-10T12:00:00Z", "override_count": 3, "overrides": [{"reason":"a"},{"reason":"b"},{"reason":"c"}]}
EOF

  # The cdocs SKILL.md says the format is:
  # "Branch: {branch}. Rules: {count}. QA rounds: {N}. Findings fixed: {N}. Overrides: {N}. {description}."
  # Test that the skill file contains the Overrides field instruction
  local cdocs_skill="$REPO_DIR/skills/cdocs/SKILL.md"
  local has_overrides_format="no"
  if grep -q 'Overrides:' "$cdocs_skill" 2>/dev/null; then
    has_overrides_format="yes"
  fi
  assert_eq "R-002: cdocs SKILL.md mentions 'Overrides:' format" "yes" "$has_overrides_format"
}

test_r002_zero_count_omitted() {
  echo ""
  echo "=== R-002: Override count = 0 is omitted from workflow-history.md ==="

  # The spec says: "If the override count is 0, omit the field"
  # Verify the SKILL.md instructs to omit when 0
  local cdocs_skill="$REPO_DIR/skills/cdocs/SKILL.md"
  local has_omit_zero="no"
  if grep -qi 'override count is 0.*omit\|omit.*override.*0\|if.*override.*0.*omit\|greater than 0' "$cdocs_skill" 2>/dev/null; then
    has_omit_zero="yes"
  fi
  assert_eq "R-002: cdocs SKILL.md instructs omitting override count when 0" "yes" "$has_omit_zero"
}

test_r002_fallback_chain() {
  echo ""
  echo "=== R-002: Fallback chain — preserved file then ephemeral log then 0 ==="

  # Verify the skill instructs reading from preserved file first, falling back to ephemeral
  local cdocs_skill="$REPO_DIR/skills/cdocs/SKILL.md"
  local has_fallback="no"
  if grep -qi 'meta/overrides\|preserved.*file.*fall.*back\|override.*log.*json.*fall' "$cdocs_skill" 2>/dev/null; then
    has_fallback="yes"
  fi
  assert_eq "R-002: cdocs SKILL.md describes fallback chain for override count" "yes" "$has_fallback"
}

# ============================================
# R-003 [unit]: /cmetrics adds Override Health section
# ============================================

test_r003_override_health_section() {
  echo ""
  echo "=== R-003: Override Health section appears in /cmetrics output format ==="

  local cmetrics_skill="$REPO_DIR/skills/cmetrics/SKILL.md"
  local has_section="no"
  if grep -q 'Override Health' "$cmetrics_skill" 2>/dev/null; then
    has_section="yes"
  fi
  assert_eq "R-003: cmetrics SKILL.md has Override Health section" "yes" "$has_section"
}

test_r003_mean_calculation() {
  echo ""
  echo "=== R-003: Mean calculation description in cmetrics ==="

  local cmetrics_skill="$REPO_DIR/skills/cmetrics/SKILL.md"
  # Verify the skill describes mean overrides per run
  local has_mean="no"
  if grep -qi 'mean.*overrides.*per.*run\|overrides.*per.*run.*mean\|total.*overrides.*count.*preserved' "$cmetrics_skill" 2>/dev/null; then
    has_mean="yes"
  fi
  assert_eq "R-003: cmetrics describes mean overrides per run" "yes" "$has_mean"
}

test_r003_warning_threshold() {
  echo ""
  echo "=== R-003: Warning emitted when mean > 0.5 ==="

  local cmetrics_skill="$REPO_DIR/skills/cmetrics/SKILL.md"
  local has_warning="no"
  if grep -q '0\.5' "$cmetrics_skill" 2>/dev/null && grep -qi 'elevated\|warning\|gate misclassification' "$cmetrics_skill" 2>/dev/null; then
    has_warning="yes"
  fi
  assert_eq "R-003: cmetrics warns when mean override rate > 0.5" "yes" "$has_warning"
}

test_r003_empty_directory_message() {
  echo ""
  echo "=== R-003: Empty directory shows 'No override data yet' message ==="

  local cmetrics_skill="$REPO_DIR/skills/cmetrics/SKILL.md"
  local has_empty_msg="no"
  if grep -qi 'No override data yet\|override.*tracking.*starts.*automatically' "$cmetrics_skill" 2>/dev/null; then
    has_empty_msg="yes"
  fi
  assert_eq "R-003: cmetrics has empty-directory message" "yes" "$has_empty_msg"
}

test_r003_cluster_tie_breaking() {
  echo ""
  echo "=== R-003: Cluster tie-breaking — alphabetical by shortest reason ==="

  local cmetrics_skill="$REPO_DIR/skills/cmetrics/SKILL.md"
  local has_tiebreak="no"
  if grep -qi 'alphabetical.*shortest\|shortest.*reason\|ties.*broken.*alphabetical' "$cmetrics_skill" 2>/dev/null; then
    has_tiebreak="yes"
  fi
  assert_eq "R-003: cmetrics describes cluster tie-breaking rule" "yes" "$has_tiebreak"
}

# ============================================
# R-004 [integration]: Cross-run check in review_override_issuance
# ============================================

test_r004_cross_run_escalation() {
  echo ""
  echo "=== R-004: Cross-run check — 2+ matching reasons escalates to human ==="

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN

  mkdir -p "$TEST_DIR/.correctless/meta/overrides"
  mkdir -p "$TEST_DIR/.correctless/artifacts"

  # Create 2 preserved files with matching override reasons
  cat > "$TEST_DIR/.correctless/meta/overrides/feature-a-20260408.json" << 'EOF'
{"task_slug": "feature-a", "branch": "feature/a", "completed_at": "2026-04-08T12:00:00Z", "override_count": 1, "overrides": [{"phase": "tdd-impl", "reason": "Build fails due to missing stub function", "timestamp": "2026-04-08T10:00:00Z", "branch": "feature/a"}]}
EOF
  cat > "$TEST_DIR/.correctless/meta/overrides/feature-b-20260409.json" << 'EOF'
{"task_slug": "feature-b", "branch": "feature/b", "completed_at": "2026-04-09T12:00:00Z", "override_count": 1, "overrides": [{"phase": "tdd-qa", "reason": "Build fails because stub function is missing", "timestamp": "2026-04-09T10:00:00Z", "branch": "feature/b"}]}
EOF

  # Set up state file for the function
  echo '{"phase":"tdd-impl"}' > "$TEST_DIR/state.json"
  echo "## Decision Record" > "$TEST_DIR/decision-record.md"
  local crosscheck_evidence='{"pre_existing_claimed":false,"claim_verified":true}'

  # Call review_override_issuance with a similar override reason
  local result
  result="$(OVERRIDES_DIR="$TEST_DIR/.correctless/meta/overrides" \
    review_override_issuance "$TEST_DIR/state.json" \
    "Build fails due to missing stub function" \
    "tdd-impl" "Build a policy engine" \
    "$TEST_DIR/decision-record.md" "$crosscheck_evidence" 2>/dev/null)"

  # With 2+ matching reasons across runs, should escalate
  assert_eq "R-004: 2+ cross-run matches → escalate_to_human" "escalate_to_human" "$result"
}

test_r004_cross_run_single_no_escalation() {
  echo ""
  echo "=== R-004: Cross-run check — 1 matching reason does NOT escalate ==="

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN

  mkdir -p "$TEST_DIR/.correctless/meta/overrides"
  mkdir -p "$TEST_DIR/.correctless/artifacts"

  # Only 1 preserved file with a matching reason
  cat > "$TEST_DIR/.correctless/meta/overrides/feature-a-20260408.json" << 'EOF'
{"task_slug": "feature-a", "branch": "feature/a", "completed_at": "2026-04-08T12:00:00Z", "override_count": 1, "overrides": [{"phase": "tdd-impl", "reason": "Build fails due to missing stub function", "timestamp": "2026-04-08T10:00:00Z", "branch": "feature/a"}]}
EOF

  echo '{"phase":"tdd-impl"}' > "$TEST_DIR/state.json"
  echo "## Decision Record" > "$TEST_DIR/decision-record.md"
  local crosscheck_evidence='{"pre_existing_claimed":false,"claim_verified":true}'

  local result
  result="$(OVERRIDES_DIR="$TEST_DIR/.correctless/meta/overrides" \
    review_override_issuance "$TEST_DIR/state.json" \
    "Build fails due to missing stub function" \
    "tdd-impl" "Build a policy engine" \
    "$TEST_DIR/decision-record.md" "$crosscheck_evidence" 2>/dev/null)"

  # 1 match is not enough for escalation
  assert_not_contains "R-004: 1 cross-run match should NOT escalate" "escalate_to_human" "$result"
}

test_r004_cross_run_zero_preserved() {
  echo ""
  echo "=== R-004: Cross-run check — 0 preserved files, no escalation ==="

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN

  mkdir -p "$TEST_DIR/.correctless/meta/overrides"
  mkdir -p "$TEST_DIR/.correctless/artifacts"

  # No preserved files at all

  echo '{"phase":"tdd-impl"}' > "$TEST_DIR/state.json"
  echo "## Decision Record" > "$TEST_DIR/decision-record.md"
  local crosscheck_evidence='{"pre_existing_claimed":false,"claim_verified":true}'

  local result
  result="$(OVERRIDES_DIR="$TEST_DIR/.correctless/meta/overrides" \
    review_override_issuance "$TEST_DIR/state.json" \
    "Build fails due to missing stub function" \
    "tdd-impl" "Build a policy engine" \
    "$TEST_DIR/decision-record.md" "$crosscheck_evidence" 2>/dev/null)"

  # No preserved files — proceed normally
  assert_not_contains "R-004: 0 preserved files should NOT escalate" "escalate_to_human" "$result"
}

test_r004_escalation_message_includes_context() {
  echo ""
  echo "=== R-004: Escalation message includes task slugs and dates ==="

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN

  mkdir -p "$TEST_DIR/.correctless/meta/overrides"
  mkdir -p "$TEST_DIR/.correctless/artifacts"

  # Create 2 preserved files with matching reasons
  cat > "$TEST_DIR/.correctless/meta/overrides/feature-x-20260408.json" << 'EOF'
{"task_slug": "feature-x", "branch": "feature/x", "completed_at": "2026-04-08T12:00:00Z", "override_count": 1, "overrides": [{"phase": "tdd-impl", "reason": "Gate bug blocks legitimate edit", "timestamp": "2026-04-08T10:00:00Z", "branch": "feature/x"}]}
EOF
  cat > "$TEST_DIR/.correctless/meta/overrides/feature-y-20260409.json" << 'EOF'
{"task_slug": "feature-y", "branch": "feature/y", "completed_at": "2026-04-09T12:00:00Z", "override_count": 1, "overrides": [{"phase": "tdd-qa", "reason": "Gate bug blocks legitimate edit", "timestamp": "2026-04-09T10:00:00Z", "branch": "feature/y"}]}
EOF

  echo '{"phase":"tdd-impl"}' > "$TEST_DIR/state.json"
  echo "## Decision Record" > "$TEST_DIR/decision-record.md"
  local crosscheck_evidence='{"pre_existing_claimed":false,"claim_verified":true}'

  # Capture stderr (where the cross-run message should appear)
  local output
  output="$(OVERRIDES_DIR="$TEST_DIR/.correctless/meta/overrides" \
    review_override_issuance "$TEST_DIR/state.json" \
    "Gate bug blocks legitimate edit" \
    "tdd-impl" "Build a policy engine" \
    "$TEST_DIR/decision-record.md" "$crosscheck_evidence" 2>&1)"

  # The structured message should include task slugs and the cross-run pattern phrase
  assert_contains "R-004: message mentions CROSS-RUN" "CROSS-RUN" "$output"
  assert_contains "R-004: message mentions task slug feature-x" "feature-x" "$output"
  assert_contains "R-004: message mentions task slug feature-y" "feature-y" "$output"
}

test_r004_recent_window() {
  echo ""
  echo "=== R-004: Recent window — only last 10 files considered ==="

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN

  mkdir -p "$TEST_DIR/.correctless/meta/overrides"
  mkdir -p "$TEST_DIR/.correctless/artifacts"

  # Create 11 preserved files — the 2 matching ones are the oldest (outside window)
  for i in $(seq 1 9); do
    cat > "$TEST_DIR/.correctless/meta/overrides/recent-$i-2026041${i}.json" << EOF
{"task_slug": "recent-$i", "branch": "feature/r$i", "completed_at": "2026-04-1${i}T12:00:00Z", "override_count": 1, "overrides": [{"phase": "tdd-impl", "reason": "Unrelated reason $i", "timestamp": "2026-04-1${i}T10:00:00Z", "branch": "feature/r$i"}]}
EOF
  done

  # These 2 matching files are the OLDEST — should be outside the recent-10 window
  cat > "$TEST_DIR/.correctless/meta/overrides/old-a-20260401.json" << 'EOF'
{"task_slug": "old-a", "branch": "feature/old-a", "completed_at": "2026-04-01T12:00:00Z", "override_count": 1, "overrides": [{"phase": "tdd-impl", "reason": "Build fails due to missing stub function", "timestamp": "2026-04-01T10:00:00Z", "branch": "feature/old-a"}]}
EOF
  cat > "$TEST_DIR/.correctless/meta/overrides/old-b-20260402.json" << 'EOF'
{"task_slug": "old-b", "branch": "feature/old-b", "completed_at": "2026-04-02T12:00:00Z", "override_count": 1, "overrides": [{"phase": "tdd-impl", "reason": "Build fails because stub function is missing", "timestamp": "2026-04-02T10:00:00Z", "branch": "feature/old-b"}]}
EOF

  echo '{"phase":"tdd-impl"}' > "$TEST_DIR/state.json"
  echo "## Decision Record" > "$TEST_DIR/decision-record.md"
  local crosscheck_evidence='{"pre_existing_claimed":false,"claim_verified":true}'

  # The 2 matching files are outside the recent-10 window, so no escalation
  local result
  result="$(OVERRIDES_DIR="$TEST_DIR/.correctless/meta/overrides" \
    review_override_issuance "$TEST_DIR/state.json" \
    "Build fails due to missing stub function" \
    "tdd-impl" "Build a policy engine" \
    "$TEST_DIR/decision-record.md" "$crosscheck_evidence" 2>/dev/null)"

  assert_not_contains "R-004: matches outside recent-10 window should NOT escalate" "escalate_to_human" "$result"
}

# ============================================
# R-005 [unit]: .correctless/meta/ is gitignored and project-level
# ============================================

test_r005_meta_gitignored() {
  echo ""
  echo "=== R-005: .correctless/meta/ is in .gitignore ==="

  local gitignore="$REPO_DIR/.gitignore"
  local has_meta_ignore="no"
  if grep -q '\.correctless/meta/' "$gitignore" 2>/dev/null; then
    has_meta_ignore="yes"
  fi
  assert_eq "R-005: .gitignore contains .correctless/meta/" "yes" "$has_meta_ignore"
}

test_r005_path_not_branch_scoped() {
  echo ""
  echo "=== R-005: Directory is project-level (not branch-scoped) ==="

  # The spec says: "The data persists across branches because .correctless/meta/
  # is a project-level directory (not branch-scoped)"
  # Verify the preserved file path in cauto SKILL.md does NOT contain branch slug
  local cauto_skill="$REPO_DIR/skills/cauto/SKILL.md"
  local has_branch_in_path="yes"
  if grep -qi 'meta/overrides/{task-slug}' "$cauto_skill" 2>/dev/null; then
    # Path uses task-slug, not branch-slug — correct
    has_branch_in_path="no"
  fi
  # Additionally check the spec itself says meta/overrides/
  local spec_file="$REPO_DIR/.correctless/specs/override-freq-metrics.md"
  if grep -q 'meta/overrides/{task-slug}' "$spec_file" 2>/dev/null; then
    has_branch_in_path="no"
  fi
  assert_eq "R-005: override path uses task-slug, not branch-slug (project-level)" "no" "$has_branch_in_path"
}

# ============================================
# R-006 [unit]: 50-file cap on preserved override files
# ============================================

test_r006_cap_triggers_deletion() {
  echo ""
  echo "=== R-006: 50-file cap — 51st file triggers deletion of oldest ==="

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN

  mkdir -p "$TEST_DIR/.correctless/artifacts"
  mkdir -p "$TEST_DIR/.correctless/meta/overrides"

  # Create 50 existing preserved files with ascending timestamps
  for i in $(seq 1 50); do
    local day
    day=$(printf "%02d" $((i % 28 + 1)))
    local month
    month=$(printf "%02d" $(((i / 28) + 1)))
    cat > "$TEST_DIR/.correctless/meta/overrides/feat-$i-2026${month}${day}.json" << EOF
{"task_slug": "feat-$i", "branch": "feature/f$i", "completed_at": "2026-${month}-${day}T12:00:00Z", "override_count": 0, "overrides": []}
EOF
  done

  # Verify we have 50 files
  local pre_count
  pre_count="$(find "$TEST_DIR/.correctless/meta/overrides" -name '*.json' | wc -l | tr -d ' ')"
  assert_eq "R-006: pre-condition 50 files exist" "50" "$pre_count"

  # Now add the 51st via preserve_override_log
  echo '[]' > "$TEST_DIR/.correctless/artifacts/override-log.json"
  preserve_override_log "$TEST_DIR" "new-feature" "feature/new-feature" 2>/dev/null

  # Should still have at most 50 files
  local post_count
  post_count="$(find "$TEST_DIR/.correctless/meta/overrides" -name '*.json' | wc -l | tr -d ' ')"
  local within_cap="no"
  [ "$post_count" -le 50 ] && within_cap="yes"
  assert_eq "R-006: after adding 51st, total <= 50" "yes" "$within_cap"

  # Verify the new file exists
  local new_exists
  new_exists="$(find "$TEST_DIR/.correctless/meta/overrides" -name 'new-feature-*.json' 2>/dev/null | wc -l | tr -d ' ')"
  assert_eq "R-006: new file was created" "1" "$new_exists"
}

test_r006_malformed_evicted_first() {
  echo ""
  echo "=== R-006: Malformed file (missing completed_at) evicted first ==="

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN

  mkdir -p "$TEST_DIR/.correctless/artifacts"
  mkdir -p "$TEST_DIR/.correctless/meta/overrides"

  # Create 49 valid files + 1 malformed (no completed_at)
  for i in $(seq 1 49); do
    cat > "$TEST_DIR/.correctless/meta/overrides/valid-$i-20260410.json" << EOF
{"task_slug": "valid-$i", "branch": "feature/v$i", "completed_at": "2026-04-10T${i}:00:00Z", "override_count": 0, "overrides": []}
EOF
  done
  # Malformed file — missing completed_at entirely
  cat > "$TEST_DIR/.correctless/meta/overrides/malformed-20260401.json" << 'EOF'
{"task_slug": "malformed", "branch": "feature/m", "override_count": 0, "overrides": []}
EOF

  # Now we have 50. Add 51st to trigger eviction.
  echo '[]' > "$TEST_DIR/.correctless/artifacts/override-log.json"
  preserve_override_log "$TEST_DIR" "trigger" "feature/trigger" 2>/dev/null

  # The malformed file should be evicted first
  local malformed_exists
  malformed_exists="$(find "$TEST_DIR/.correctless/meta/overrides" -name 'malformed-*.json' 2>/dev/null | wc -l | tr -d ' ')"
  assert_eq "R-006: malformed file evicted first" "0" "$malformed_exists"
}

test_r006_timestamps_sorted_correctly() {
  echo ""
  echo "=== R-006: Files with valid timestamps sorted correctly ==="

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN

  mkdir -p "$TEST_DIR/.correctless/artifacts"
  mkdir -p "$TEST_DIR/.correctless/meta/overrides"

  # Create 50 files with known timestamps — oldest is feat-oldest
  cat > "$TEST_DIR/.correctless/meta/overrides/feat-oldest-20260101.json" << 'EOF'
{"task_slug": "feat-oldest", "branch": "feature/oldest", "completed_at": "2026-01-01T00:00:00Z", "override_count": 0, "overrides": []}
EOF

  for i in $(seq 2 50); do
    cat > "$TEST_DIR/.correctless/meta/overrides/feat-$i-20260410.json" << EOF
{"task_slug": "feat-$i", "branch": "feature/f$i", "completed_at": "2026-04-10T$(printf '%02d' $i):00:00Z", "override_count": 0, "overrides": []}
EOF
  done

  # Add 51st — should evict feat-oldest
  echo '[]' > "$TEST_DIR/.correctless/artifacts/override-log.json"
  preserve_override_log "$TEST_DIR" "new-one" "feature/new-one" 2>/dev/null

  # feat-oldest should be gone
  local oldest_exists
  oldest_exists="$(find "$TEST_DIR/.correctless/meta/overrides" -name 'feat-oldest-*.json' 2>/dev/null | wc -l | tr -d ' ')"
  assert_eq "R-006: oldest by timestamp is evicted" "0" "$oldest_exists"

  # New file should exist
  local new_exists
  new_exists="$(find "$TEST_DIR/.correctless/meta/overrides" -name 'new-one-*.json' 2>/dev/null | wc -l | tr -d ' ')"
  assert_eq "R-006: new file was created after eviction" "1" "$new_exists"
}

# ============================================
# Runner
# ============================================

echo "============================================="
echo "Override Frequency Metrics"
echo "============================================="

# R-001: Preserve override logs
test_r001_preserved_file_created
test_r001_branch_filtering
test_r001_zero_override_case
test_r001_date_suffix_prevents_collision
test_r001_missing_override_log

# R-002: Override count in workflow-history.md
test_r002_override_count_in_history
test_r002_zero_count_omitted
test_r002_fallback_chain

# R-003: Override Health section in /cmetrics
test_r003_override_health_section
test_r003_mean_calculation
test_r003_warning_threshold
test_r003_empty_directory_message
test_r003_cluster_tie_breaking

# R-004: Cross-run pattern check in override-scrutiny.sh
test_r004_cross_run_escalation
test_r004_cross_run_single_no_escalation
test_r004_cross_run_zero_preserved
test_r004_escalation_message_includes_context
test_r004_recent_window

# R-005: .correctless/meta/ gitignored and project-level
test_r005_meta_gitignored
test_r005_path_not_branch_scoped

# R-006: 50-file cap on preserved files
test_r006_cap_triggers_deletion
test_r006_malformed_evicted_first
test_r006_timestamps_sorted_correctly

echo ""
echo "============================================="
echo "Results: $PASS passed, $FAIL failed"
echo ""

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
