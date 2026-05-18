#!/usr/bin/env bash
# Correctless — intensity calibration loop test suite
# Tests spec rules INV-001 through INV-012 and PRH-001/PRH-002 from
# .correctless/specs/intensity-calibration.md
# Run from repo root: bash tests/test-intensity-calibration.sh

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
  local file="$1" pattern="$2" desc="$3"
  if grep -q "$pattern" "$file" 2>/dev/null; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (pattern '$pattern' not found in $file)"
    FAIL=$((FAIL + 1))
  fi
}

# Check if a file does NOT contain a pattern (returns 0 if not found)
file_not_contains() {
  local file="$1" pattern="$2" desc="$3"
  if grep -q "$pattern" "$file" 2>/dev/null; then
    echo "  FAIL: $desc (pattern '$pattern' should NOT be in $file)"
    FAIL=$((FAIL + 1))
  else
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  fi
}

# Case-insensitive file contains
file_contains_i() {
  local file="$1" pattern="$2" desc="$3"
  if grep -qi "$pattern" "$file" 2>/dev/null; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (pattern '$pattern' not found case-insensitively in $file)"
    FAIL=$((FAIL + 1))
  fi
}

# ============================================
# INV-001: /cverify writes calibration entry
#   cverify SKILL.md must contain instructions to write a calibration
#   entry to .correctless/meta/intensity-calibration.json with all
#   required fields: feature_slug, recommended_intensity (from
#   Recommended-intensity metadata), actual_intensity (from Intensity
#   metadata), actual_qa_rounds, actual_findings_count (BLOCKING only),
#   actual_spec_updates, file_paths_touched, timestamp
# ============================================

test_inv001_cverify_writes_calibration() {
  echo ""
  echo "=== INV-001: /cverify writes calibration entry ==="

  local skill_file="$REPO_DIR/skills/cverify/SKILL.md"

  # INV-001: cverify references the calibration storage file
  file_contains "$skill_file" "intensity-calibration.json" \
    "INV-001: cverify SKILL.md references intensity-calibration.json"

  # INV-001: cverify references the meta directory path for calibration
  file_contains_i "$skill_file" ".correctless/meta.*calibration\|calibration.*\.correctless/meta" \
    "INV-001: cverify SKILL.md references .correctless/meta/ for calibration"

  # INV-001: cverify instructs writing/appending a calibration entry
  file_contains_i "$skill_file" "append.*calibration\|write.*calibration\|add.*calibration.*entry" \
    "INV-001: cverify instructs writing a calibration entry"

  # INV-001: all required fields are specified
  file_contains "$skill_file" "feature_slug" \
    "INV-001: calibration entry includes feature_slug field"

  file_contains "$skill_file" "recommended_intensity" \
    "INV-001: calibration entry includes recommended_intensity field"

  file_contains "$skill_file" "actual_intensity" \
    "INV-001: calibration entry includes actual_intensity field"

  file_contains "$skill_file" "actual_qa_rounds" \
    "INV-001: calibration entry includes actual_qa_rounds field"

  file_contains "$skill_file" "actual_findings_count" \
    "INV-001: calibration entry includes actual_findings_count field"

  file_contains "$skill_file" "actual_spec_updates" \
    "INV-001: calibration entry includes actual_spec_updates field"

  file_contains "$skill_file" "file_paths_touched" \
    "INV-001: calibration entry includes file_paths_touched field"

  file_contains "$skill_file" "timestamp" \
    "INV-001: calibration entry includes timestamp field"

  # INV-001: recommended_intensity sourced from Recommended-intensity metadata
  # (AP-003 mitigation: verify the right SOURCE artifact is referenced, not just
  # the field name — Recommended-intensity is the pre-override system suggestion)
  file_contains_i "$skill_file" "Recommended-intensity.*recommended_intensity\|recommended_intensity.*Recommended-intensity" \
    "INV-001: recommended_intensity sourced from Recommended-intensity metadata field"

  # INV-001: actual_intensity sourced from Intensity metadata (post-override)
  # BLOCKING-2 fix: require "post-override" context to avoid substring match with "Recommended-intensity"
  file_contains_i "$skill_file" "actual_intensity.*post-override\|post-override.*actual_intensity\|actual_intensity.*approved" \
    "INV-001: actual_intensity sourced from post-override Intensity metadata field"

  # INV-001: actual_findings_count is BLOCKING findings only
  file_contains_i "$skill_file" "actual_findings_count.*BLOCKING\|BLOCKING.*actual_findings_count\|BLOCKING.*findings.*calibration\|calibration.*BLOCKING" \
    "INV-001: actual_findings_count counts BLOCKING findings only"

  # INV-001: creates the file and directory if they don't exist
  file_contains_i "$skill_file" "create.*calibration_entries\|does not exist.*create\|mkdir.*meta" \
    "INV-001: instructs creating file/directory if missing"

  # INV-001: calibration entry written before advancing workflow state
  file_contains_i "$skill_file" "before.*advanc\|before.*state" \
    "INV-001: calibration entry written before advancing workflow state"

  # BLOCKING-1 fix: cverify allowed-tools must grant write permission to calibration file
  file_contains_i "$skill_file" "Write(.*meta.*calibration\|Write(.*intensity-calibration" \
    "INV-001: cverify allowed-tools includes write permission for calibration file"
}

# ============================================
# INV-002: Calibration entry schema
#   Schema fields and their sources documented correctly
# ============================================

test_inv002_calibration_schema() {
  echo ""
  echo "=== INV-002: Calibration entry schema ==="

  local skill_file="$REPO_DIR/skills/cverify/SKILL.md"

  # INV-002: schema documents calibration_entries array
  file_contains "$skill_file" "calibration_entries" \
    "INV-002: schema documents calibration_entries array"

  # INV-002: recommended_intensity values are enumerated as part of calibration schema
  file_contains_i "$skill_file" "recommended_intensity.*standard.*high.*critical\|actual_intensity.*standard.*high.*critical" \
    "INV-002: schema enumerates standard|high|critical for calibration intensity fields"

  # INV-002: actual_qa_rounds sourced from workflow state
  file_contains_i "$skill_file" "actual_qa_rounds.*workflow.*state\|workflow.*state.*actual_qa_rounds\|qa_rounds.*from.*state" \
    "INV-002: actual_qa_rounds sourced from workflow state file"

  # INV-002: actual_spec_updates sourced from workflow state
  file_contains_i "$skill_file" "actual_spec_updates.*workflow.*state\|workflow.*state.*actual_spec_updates\|spec_updates.*from.*state" \
    "INV-002: actual_spec_updates sourced from workflow state file"

  # INV-002: actual_findings_count sourced from qa-findings JSON, BLOCKING only
  file_contains_i "$skill_file" "qa-findings.*BLOCKING\|BLOCKING.*qa-findings" \
    "INV-002: actual_findings_count sourced from qa-findings JSON (BLOCKING only)"

  # INV-002: file_paths_touched sourced from git diff
  file_contains_i "$skill_file" "file_paths_touched.*git diff\|git diff.*file_paths_touched\|file_paths.*from.*git" \
    "INV-002: file_paths_touched sourced from git diff"

  # INV-002: timestamp is ISO string
  file_contains_i "$skill_file" "timestamp.*ISO\|ISO.*timestamp" \
    "INV-002: timestamp is ISO string format"
}

# ============================================
# INV-003: /cspec reads calibration data during intensity detection
#   Reads intensity-calibration.json, computes file-path overlap
#   and arithmetic mean, runs as post-signal modifier
# ============================================

test_inv003_cspec_reads_calibration() {
  echo ""
  echo "=== INV-003: /cspec reads calibration data ==="

  local skill_file="$REPO_DIR/skills/cspec/SKILL.md"

  # INV-003: cspec references intensity-calibration.json for reading
  file_contains "$skill_file" "intensity-calibration.json" \
    "INV-003: cspec SKILL.md references intensity-calibration.json"

  # INV-003: cspec references .correctless/meta path for calibration
  file_contains_i "$skill_file" ".correctless/meta.*calibration\|calibration.*\.correctless/meta\|meta/intensity-calibration" \
    "INV-003: cspec SKILL.md references .correctless/meta/ for calibration"

  # INV-003: file path overlap computation described
  file_contains_i "$skill_file" "file.*path.*overlap\|overlap.*file.*path\|path.*in common\|paths.*overlap" \
    "INV-003: cspec describes file path overlap computation"

  # INV-003: arithmetic mean computation described
  file_contains_i "$skill_file" "arithmetic mean\|average.*qa_rounds\|mean.*findings\|compute.*average" \
    "INV-003: cspec describes arithmetic mean computation"

  # INV-003: runs as post-signal modifier (not a 5th signal)
  file_contains_i "$skill_file" "post-signal\|after.*signal.*evaluation\|after.*highest-wins" \
    "INV-003: cspec runs calibration as post-signal modifier"
}

# ============================================
# INV-004: /csetup presents calibration mode selection
#   3 options: passive (default), active, hybrid
#   Writes to workflow.intensity_calibration_mode
# ============================================

# INV-004 (csetup calibration mode) REMOVED — calibration mode selection
# removed from /csetup per simplify-intensity-calibration spec

# ============================================
# INV-005: Calibration mode affects /cspec behavior
#   Passive: advisory text with arithmetic
#   Active: auto-raise when QA>=3 or BLOCKING>=8 at recommended_intensity
#   Hybrid: passive until 5 total entries, then active
#   Override context shown in advisory text
# ============================================

# INV-005 (mode behaviors) REMOVED — active/hybrid mode behaviors
# removed from /cspec per simplify-intensity-calibration spec

# ============================================
# INV-006: Config templates include calibration mode
#   Both workflow-config.json templates (lite and full) include
#   "intensity_calibration_mode": "passive" in the workflow section
# ============================================

test_inv006_config_templates() {
  echo ""
  echo "=== INV-006: Config templates exist ==="

  local lite_cfg="$REPO_DIR/templates/workflow-config.json"
  local full_cfg="$REPO_DIR/templates/workflow-config-full.json"

  # INV-006: lite template exists and is valid JSON
  if [ -f "$lite_cfg" ] && jq empty "$lite_cfg" 2>/dev/null; then
    echo "  PASS: INV-006: lite workflow-config.json exists and is valid JSON"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: INV-006: lite workflow-config.json missing or invalid JSON"
    FAIL=$((FAIL + 1))
  fi

  # INV-006: full template exists and is valid JSON
  if [ -f "$full_cfg" ] && jq empty "$full_cfg" 2>/dev/null; then
    echo "  PASS: INV-006: full workflow-config-full.json exists and is valid JSON"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: INV-006: full workflow-config-full.json missing or invalid JSON"
    FAIL=$((FAIL + 1))
  fi
}

# ============================================
# INV-007: Calibration data is read-only for /cspec
#   /cspec only reads — never writes, modifies, or deletes entries
#   Only /cverify writes calibration entries
# ============================================

test_inv007_cspec_read_only() {
  echo ""
  echo "=== INV-007: /cspec calibration data is read-only ==="

  local skill_file="$REPO_DIR/skills/cspec/SKILL.md"

  # INV-007: cspec must NOT contain write/append/create instructions for calibration
  file_not_contains "$skill_file" "write.*intensity-calibration\|append.*intensity-calibration\|create.*intensity-calibration" \
    "INV-007: cspec does NOT write to intensity-calibration.json"

  file_not_contains "$skill_file" "modify.*calibration.*entry\|delete.*calibration.*entry\|update.*calibration.*entry" \
    "INV-007: cspec does NOT modify/delete calibration entries"

  # INV-007: positive check — cspec states it only reads calibration data
  file_contains_i "$skill_file" "read.*calibration\|reads.*calibration\|read-only.*calibration\|calibration.*read" \
    "INV-007: cspec explicitly states it reads calibration data"
}

# ============================================
# INV-008: Graceful handling when no calibration data
#   When intensity-calibration.json doesn't exist or has zero entries,
#   proceed normally — dormant signal pattern
# ============================================

test_inv008_no_calibration_graceful() {
  echo ""
  echo "=== INV-008: Graceful handling when no calibration data ==="

  local skill_file="$REPO_DIR/skills/cspec/SKILL.md"

  # INV-008: handles missing file gracefully
  file_contains_i "$skill_file" "does not exist.*calibration\|calibration.*not exist\|no.*calibration.*data\|calibration.*missing" \
    "INV-008: cspec handles missing calibration file"

  # INV-008: uses dormant signal pattern (same as antipattern/QA history signals)
  file_contains_i "$skill_file" "dormant.*calibration\|calibration.*dormant\|skip.*calibration\|proceed.*without.*calibration" \
    "INV-008: cspec uses dormant signal pattern for missing calibration"

  # INV-008: no error, no warning, no change to recommendation when absent
  file_contains_i "$skill_file" "no error\|no warning\|proceed.*normally\|no change.*recommend" \
    "INV-008: no error/warning when calibration data absent"
}

# ============================================
# INV-009: Spec Metadata includes Recommended-intensity field
#   Both spec templates include Recommended-intensity placeholder
#   /cspec writes this field during Step 8
# ============================================

test_inv009_recommended_intensity_field() {
  echo ""
  echo "=== INV-009: Recommended-intensity field ==="

  local lite_tpl="$REPO_DIR/templates/spec-lite.md"
  local full_tpl="$REPO_DIR/templates/spec-full.md"
  local skill_file="$REPO_DIR/skills/cspec/SKILL.md"

  # INV-009: lite template has Recommended-intensity field
  file_contains "$lite_tpl" "Recommended-intensity" \
    "INV-009: lite spec template has Recommended-intensity field"

  # INV-009: full template has Recommended-intensity field
  file_contains "$full_tpl" "Recommended-intensity" \
    "INV-009: full spec template has Recommended-intensity field"

  # INV-009: cspec SKILL.md instructs writing Recommended-intensity
  file_contains "$skill_file" "Recommended-intensity" \
    "INV-009: cspec SKILL.md references Recommended-intensity field"

  # INV-009: Recommended-intensity written during Step 8
  # (AP-003 mitigation: check that Recommended-intensity and Step 8 appear
  # in context together, not just anywhere in the file)
  file_contains_i "$skill_file" "Recommended-intensity.*Step 8\|Step 8.*Recommended-intensity" \
    "INV-009: Recommended-intensity written during Step 8"

  # INV-009: Recommended-intensity stores pre-override recommendation
  file_contains_i "$skill_file" "pre-override.*Recommended-intensity\|Recommended-intensity.*pre-override\|system.*recommendation.*Recommended-intensity\|Recommended-intensity.*system.*recommend" \
    "INV-009: Recommended-intensity stores pre-override system recommendation"

  # INV-009: Intensity field continues to store post-override (approved) level
  # — verify the distinction between Recommended-intensity (pre-override) and
  #   Intensity (post-override) is documented in cspec
  file_contains_i "$skill_file" "Intensity.*post-override.*Recommended-intensity\|Recommended-intensity.*pre-override.*Intensity.*post-override\|Intensity.*approved.*Recommended-intensity.*system" \
    "INV-009: distinction between Intensity (post-override) and Recommended-intensity (pre-override)"

  # BLOCKING-5 fix: verify Recommended-intensity appears in the Metadata section of templates
  # (not just anywhere in the file — section-anchored check)
  local lite_metadata full_metadata
  lite_metadata="$(sed -n '/## Metadata/,/^## /p' "$lite_tpl" 2>/dev/null)"
  full_metadata="$(sed -n '/## Metadata/,/^## /p' "$full_tpl" 2>/dev/null)"
  local lite_in_meta="no" full_in_meta="no"
  echo "$lite_metadata" | grep -q "Recommended-intensity" && lite_in_meta="yes"
  echo "$full_metadata" | grep -q "Recommended-intensity" && full_in_meta="yes"
  assert_eq "INV-009: lite template has Recommended-intensity in Metadata section" "yes" "$lite_in_meta"
  assert_eq "INV-009: full template has Recommended-intensity in Metadata section" "yes" "$full_in_meta"
}

# ============================================
# INV-010: Calibration reads use recency window
#   /cspec reads at most 50 most recent entries (by timestamp)
# ============================================

test_inv010_recency_window() {
  echo ""
  echo "=== INV-010: Calibration recency window ==="

  local skill_file="$REPO_DIR/skills/cspec/SKILL.md"

  # INV-010: recency window mentioned
  file_contains_i "$skill_file" "recency.*window\|most recent.*50\|50.*most recent\|recent.*50.*entries\|50.*entries" \
    "INV-010: cspec describes recency window of 50 entries"

  # INV-010: sorted by timestamp, newest first
  file_contains_i "$skill_file" "sorted.*timestamp\|timestamp.*newest\|newest.*first\|most recent" \
    "INV-010: entries sorted by timestamp, newest first"

  # INV-010: entries beyond 50 are ignored
  file_contains_i "$skill_file" "beyond.*50.*ignore\|ignore.*beyond.*50\|older.*entries.*ignore\|cap.*50\|limit.*50" \
    "INV-010: entries beyond 50 are ignored"
}

# ============================================
# INV-011: Calibration is a post-signal modifier
#   NOT a 5th signal in the highest-wins evaluation
#   Runs AFTER the 4-signal evaluation
#   Never lowers the result below what 4 signals produced
# ============================================

test_inv011_post_signal_modifier() {
  echo ""
  echo "=== INV-011: Calibration is a post-signal modifier ==="

  local skill_file="$REPO_DIR/skills/cspec/SKILL.md"

  # INV-011: explicitly NOT a 5th signal
  file_contains_i "$skill_file" "not.*5th.*signal\|not.*fifth.*signal\|not.*additional.*signal" \
    "INV-011: calibration is explicitly not a 5th signal"

  # INV-011: post-signal modifier terminology used
  file_contains_i "$skill_file" "post-signal.*modifier\|post-signal" \
    "INV-011: uses post-signal modifier terminology"

  # INV-011: runs AFTER the 4-signal highest-wins evaluation
  file_contains_i "$skill_file" "after.*4.*signal\|after.*highest-wins\|after.*signal.*evaluation" \
    "INV-011: runs after the 4-signal highest-wins evaluation"

  # INV-011: calibration never lowers the result below what 4 signals produced
  file_contains_i "$skill_file" "calibration.*never.*lower\|never.*lower.*calibration\|calibration.*only.*raise\|post-signal.*never.*lower" \
    "INV-011: calibration never lowers the result"
}

# ============================================
# INV-012: /cspec shows calibration arithmetic
#   List overlapping entries with slugs and values
#   Show sum, count, average, and threshold comparison
# ============================================

test_inv012_show_arithmetic() {
  echo ""
  echo "=== INV-012: /cspec shows calibration arithmetic ==="

  local skill_file="$REPO_DIR/skills/cspec/SKILL.md"

  # INV-012: lists overlapping entries with feature slugs
  file_contains_i "$skill_file" "list.*entries\|list.*overlapping\|overlapping.*entries.*list\|feature.*slug.*list" \
    "INV-012: cspec lists overlapping entries"

  # INV-012: shows average in calibration context
  file_contains_i "$skill_file" "average.*calibration\|calibration.*average\|arithmetic mean.*calibration\|calibration.*arithmetic mean\|Averages:" \
    "INV-012: cspec shows average in calibration arithmetic"

  # INV-012: calibration display is advisory (human reads data and decides)
  file_contains_i "$skill_file" "advisory.*calibration\|calibration.*advisory\|human.*reads.*data\|human.*decides" \
    "INV-012: calibration display is advisory"
}

# ============================================
# PRH-001: No calibration data in workflow state files
#   workflow-advance.sh must NOT contain calibration-related fields
#   Calibration lives in .correctless/meta/, not workflow-state-*.json
# ============================================

test_prh001_no_calibration_in_state() {
  echo ""
  echo "=== PRH-001: No calibration data in workflow state files ==="

  local hook_file="$REPO_DIR/hooks/workflow-advance.sh"

  # PRH-001: workflow-advance.sh must NOT reference calibration fields
  file_not_contains "$hook_file" "calibration" \
    "PRH-001: workflow-advance.sh does not contain 'calibration'"

  file_not_contains "$hook_file" "intensity-calibration" \
    "PRH-001: workflow-advance.sh does not contain 'intensity-calibration'"

  file_not_contains "$hook_file" "recommended_intensity" \
    "PRH-001: workflow-advance.sh does not contain 'recommended_intensity'"

  file_not_contains "$hook_file" "actual_findings_count" \
    "PRH-001: workflow-advance.sh does not contain 'actual_findings_count'"

  file_not_contains "$hook_file" "calibration_entries" \
    "PRH-001: workflow-advance.sh does not contain 'calibration_entries'"
}

# ============================================
# PRH-002: v1 thresholds are behavioral constants
#   Config templates must NOT contain qa_rounds or findings thresholds
#   Users choose MODE, not thresholds
# ============================================

test_prh002_no_thresholds_in_config() {
  echo ""
  echo "=== PRH-002: No threshold values in config templates ==="

  local lite_cfg="$REPO_DIR/templates/workflow-config.json"
  local full_cfg="$REPO_DIR/templates/workflow-config-full.json"

  # PRH-002: lite config does NOT have calibration threshold fields
  file_not_contains "$lite_cfg" "calibration_qa_rounds" \
    "PRH-002: lite config does not contain calibration_qa_rounds threshold"

  file_not_contains "$lite_cfg" "calibration_findings_threshold" \
    "PRH-002: lite config does not contain calibration_findings_threshold"

  file_not_contains "$lite_cfg" "calibration_threshold" \
    "PRH-002: lite config does not contain calibration_threshold"

  # PRH-002: full config does NOT have calibration threshold fields
  file_not_contains "$full_cfg" "calibration_qa_rounds" \
    "PRH-002: full config does not contain calibration_qa_rounds threshold"

  file_not_contains "$full_cfg" "calibration_findings_threshold" \
    "PRH-002: full config does not contain calibration_findings_threshold"

  file_not_contains "$full_cfg" "calibration_threshold" \
    "PRH-002: full config does not contain calibration_threshold"
}

# ============================================
# Runner
# ============================================

echo "============================================="
echo "Intensity Calibration Test Suite"
echo "============================================="

test_inv001_cverify_writes_calibration
test_inv002_calibration_schema
test_inv003_cspec_reads_calibration
test_inv006_config_templates
test_inv007_cspec_read_only
test_inv008_no_calibration_graceful
test_inv009_recommended_intensity_field
test_inv010_recency_window
test_inv011_post_signal_modifier
test_inv012_show_arithmetic
test_prh001_no_calibration_in_state
test_prh002_no_thresholds_in_config

echo ""
echo "============================================="
echo "Results: $PASS passed, $FAIL failed"
echo ""

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
