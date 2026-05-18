#!/usr/bin/env bash
# Correctless — Simplify Intensity Calibration test suite
# Tests spec rules INV-001 through INV-009 and PRH-001/PRH-002 from
# .correctless/specs/simplify-intensity-calibration.md
#
# This is a SIMPLIFICATION spec — tests verify ABSENCE of removed patterns
# and PRESENCE of the simplified advisory-only display.
# Run from repo root: bash tests/test-simplify-intensity-calibration.sh

set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CSPEC_SKILL="$REPO_DIR/skills/cspec/SKILL.md"
CSPEC_DIST="$REPO_DIR/correctless/skills/cspec/SKILL.md"
CSETUP_SKILL="$REPO_DIR/skills/csetup/SKILL.md"
CSETUP_DIST="$REPO_DIR/correctless/skills/csetup/SKILL.md"
LITE_CFG="$REPO_DIR/templates/workflow-config.json"
FULL_CFG="$REPO_DIR/templates/workflow-config-full.json"
LITE_CFG_DIST="$REPO_DIR/correctless/templates/workflow-config.json"
FULL_CFG_DIST="$REPO_DIR/correctless/templates/workflow-config-full.json"
AGENT_CONTEXT="$REPO_DIR/.correctless/AGENT_CONTEXT.md"
FEATURES_FILE="$REPO_DIR/FEATURES.md"
PASS=0
FAIL=0

# ============================================
# Helpers
# ============================================

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

file_not_contains_i() {
  local file="$1" pattern="$2" desc="$3"
  if grep -qi "$pattern" "$file" 2>/dev/null; then
    echo "  FAIL: $desc (pattern '$pattern' should NOT be in $file, case-insensitive)"
    FAIL=$((FAIL + 1))
  else
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  fi
}

# Section-aware grep: extract a section and check for a pattern within it.
section_contains() {
  local file="$1" section_heading="$2" pattern="$3" desc="$4"
  local section_text
  section_text="$(sed -n "/^###* .*${section_heading}/,/^###* /p" "$file" 2>/dev/null)"
  if echo "$section_text" | grep -qi "$pattern"; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (pattern '$pattern' not found in section '$section_heading' of $file)"
    FAIL=$((FAIL + 1))
  fi
}

section_not_contains() {
  local file="$1" section_heading="$2" pattern="$3" desc="$4"
  local section_text
  section_text="$(sed -n "/^###* .*${section_heading}/,/^###* /p" "$file" 2>/dev/null)"
  if echo "$section_text" | grep -qi "$pattern"; then
    echo "  FAIL: $desc (pattern '$pattern' should NOT be in section '$section_heading' of $file)"
    FAIL=$((FAIL + 1))
  else
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  fi
}

# ============================================
# INV-001: No auto-raise in /cspec
#   /cspec SKILL.md MUST NOT contain auto-raise logic.
#   No "auto-raise" phrasing, no "active mode" auto-adjustment,
#   no "hybrid mode" conditional switching.
# ============================================

test_inv001_no_auto_raise() {
  echo ""
  echo "=== INV-001: No auto-raise in /cspec ==="

  # INV-001a: no "auto-raise" or "auto-raised" phrasing
  file_not_contains_i "$CSPEC_SKILL" "auto-raise\|auto-raised\|auto raise" \
    "INV-001a: cspec SKILL.md does not contain auto-raise phrasing"

  # INV-001b: no "active mode" auto-adjustment behavior
  file_not_contains_i "$CSPEC_SKILL" "active mode" \
    "INV-001b: cspec SKILL.md does not contain 'active mode'"

  # INV-001c: no "hybrid mode" conditional switching
  file_not_contains_i "$CSPEC_SKILL" "hybrid mode\|hybrid.*passive" \
    "INV-001c: cspec SKILL.md does not contain 'hybrid mode'"

  # INV-001d: no automatic intensity level adjustment language
  file_not_contains_i "$CSPEC_SKILL" "automatically.*raise\|automatically.*adjust\|auto.*adjust.*intensity" \
    "INV-001d: cspec does not contain automatic adjustment language"

  # INV-001e: calibration section must be advisory-only
  section_not_contains "$CSPEC_SKILL" "Step 7b" "auto-raise\|auto-raised\|automatically.*raise" \
    "INV-001e: Step 7b calibration section is advisory-only (no auto-raise)"

  # INV-001f: same checks on distribution copy
  file_not_contains_i "$CSPEC_DIST" "auto-raise\|auto-raised\|auto raise" \
    "INV-001f: dist cspec SKILL.md does not contain auto-raise phrasing"

  file_not_contains_i "$CSPEC_DIST" "active mode" \
    "INV-001g: dist cspec SKILL.md does not contain 'active mode'"
}

# ============================================
# INV-002: No calibration mode config key
#   /cspec SKILL.md MUST NOT reference intensity_calibration_mode
#   as a config key. Calibration is always passive.
# ============================================

test_inv002_no_calibration_mode_key() {
  echo ""
  echo "=== INV-002: No calibration mode config key ==="

  # INV-002a: cspec does not reference intensity_calibration_mode
  file_not_contains "$CSPEC_SKILL" "intensity_calibration_mode" \
    "INV-002a: cspec SKILL.md does not reference intensity_calibration_mode"

  # INV-002b: cspec does not instruct reading a mode from config
  file_not_contains_i "$CSPEC_SKILL" "read.*calibration.*mode\|calibration.*mode.*from.*config" \
    "INV-002b: cspec does not instruct reading calibration mode from config"

  # INV-002c: no "default to passive" language (implies mode selector exists)
  section_not_contains "$CSPEC_SKILL" "Step 7b" "default.*passive\|absent.*passive" \
    "INV-002c: Step 7b does not contain 'default to passive' (no mode selector)"

  # INV-002d: distribution copy also clean
  file_not_contains "$CSPEC_DIST" "intensity_calibration_mode" \
    "INV-002d: dist cspec SKILL.md does not reference intensity_calibration_mode"
}

# ============================================
# INV-003: No 200K token threshold
#   /cspec SKILL.md MUST NOT contain "200,000" or "200000"
#   in the calibration section (Step 7b). Total absence.
# ============================================

test_inv003_no_200k_threshold() {
  echo ""
  echo "=== INV-003: No 200K token threshold ==="

  # INV-003a: no "200,000" anywhere in cspec
  file_not_contains "$CSPEC_SKILL" "200,000" \
    "INV-003a: cspec SKILL.md does not contain '200,000'"

  # INV-003b: no "200000" anywhere in cspec
  file_not_contains "$CSPEC_SKILL" "200000" \
    "INV-003b: cspec SKILL.md does not contain '200000'"

  # INV-003c: specifically in Step 7b section
  section_not_contains "$CSPEC_SKILL" "Step 7b" "200,000\|200000" \
    "INV-003c: Step 7b does not contain 200K threshold"

  # INV-003d: distribution copy also clean
  file_not_contains "$CSPEC_DIST" "200,000\|200000" \
    "INV-003d: dist cspec does not contain 200K threshold"
}

# ============================================
# INV-004: Passive advisory display retained
#   /cspec MUST still display calibration data as advisory text
#   during Step 8 presentation. Shows overlapping entry slugs,
#   QA rounds average, BLOCKING findings average, override history,
#   actual_tokens average (when non-zero). MUST NOT include
#   threshold comparisons or raise recommendations.
# ============================================

test_inv004_passive_advisory_display() {
  echo ""
  echo "=== INV-004: Passive advisory display retained ==="

  # INV-004a: calibration advisory text still exists in Step 7b
  section_contains "$CSPEC_SKILL" "Step 7b" "advisory\|calibration" \
    "INV-004a: Step 7b still contains calibration advisory"

  # INV-004b: display shows QA rounds average
  file_contains_i "$CSPEC_SKILL" "QA rounds" \
    "INV-004b: cspec shows QA rounds in calibration display"

  # INV-004c: display shows BLOCKING findings average
  file_contains_i "$CSPEC_SKILL" "BLOCKING.*findings\|findings.*BLOCKING" \
    "INV-004c: cspec shows BLOCKING findings in calibration display"

  # INV-004d: display shows override history
  file_contains_i "$CSPEC_SKILL" "override.*history\|overrode.*recommendation\|override.*count" \
    "INV-004d: cspec shows override history in calibration display"

  # INV-004e: display shows actual_tokens average (when non-zero entries exist)
  file_contains_i "$CSPEC_SKILL" "actual_tokens.*average\|actual_tokens.*non-zero\|token.*usage.*average\|Token usage average" \
    "INV-004e: cspec shows actual_tokens average when non-zero entries exist"

  # INV-004f: display format matches spec example —
  # "Calibration context (advisory — {N} prior features overlapped with these paths):"
  file_contains_i "$CSPEC_SKILL" "Calibration context.*advisory\|advisory.*prior features.*overlapped" \
    "INV-004f: display uses 'Calibration context (advisory...)' format"

  # INV-004g: display shows per-entry detail with feature slugs
  file_contains_i "$CSPEC_SKILL" "feature.*QA rounds.*BLOCKING\|QA rounds.*BLOCKING findings" \
    "INV-004g: display shows per-entry QA rounds and BLOCKING findings"

  # INV-004h: display shows averages line
  file_contains_i "$CSPEC_SKILL" "Averages:.*QA rounds\|Averages.*BLOCKING" \
    "INV-004h: display shows 'Averages:' line"

  # INV-004i: NO threshold comparisons in the display
  section_not_contains "$CSPEC_SKILL" "Step 7b" "threshold.*comparison\|compare.*threshold\|exceeds threshold\|threshold.*3\|threshold.*8" \
    "INV-004i: Step 7b does NOT contain threshold comparisons"

  # INV-004j: NO raise recommendations
  section_not_contains "$CSPEC_SKILL" "Step 7b" "Consider.*intensity\|consider.*higher\|consider.*raising" \
    "INV-004j: Step 7b does NOT contain 'Consider higher intensity' recommendations"

  # INV-004k: distribution copy retains advisory
  file_contains_i "$CSPEC_DIST" "Calibration context.*advisory\|advisory.*prior features.*overlapped" \
    "INV-004k: dist cspec retains advisory display format"
}

# ============================================
# INV-005: /cverify writer unchanged
#   /cverify SKILL.md calibration writer MUST remain unchanged.
#   Continues to write entries with all existing fields.
# ============================================

test_inv005_cverify_writer_unchanged() {
  echo ""
  echo "=== INV-005: /cverify writer unchanged ==="

  local cverify_skill="$REPO_DIR/skills/cverify/SKILL.md"

  # INV-005a: cverify still references calibration storage file
  file_contains "$cverify_skill" "intensity-calibration.json" \
    "INV-005a: cverify SKILL.md still references intensity-calibration.json"

  # INV-005b: cverify still writes feature_slug
  file_contains "$cverify_skill" "feature_slug" \
    "INV-005b: cverify still writes feature_slug field"

  # INV-005c: cverify still writes recommended_intensity
  file_contains "$cverify_skill" "recommended_intensity" \
    "INV-005c: cverify still writes recommended_intensity field"

  # INV-005d: cverify still writes actual_intensity
  file_contains "$cverify_skill" "actual_intensity" \
    "INV-005d: cverify still writes actual_intensity field"

  # INV-005e: cverify still writes actual_qa_rounds
  file_contains "$cverify_skill" "actual_qa_rounds" \
    "INV-005e: cverify still writes actual_qa_rounds field"

  # INV-005f: cverify still writes actual_findings_count
  file_contains "$cverify_skill" "actual_findings_count" \
    "INV-005f: cverify still writes actual_findings_count field"

  # INV-005g: cverify still writes actual_tokens
  file_contains "$cverify_skill" "actual_tokens" \
    "INV-005g: cverify still writes actual_tokens field"

  # INV-005h: cverify still writes file_paths_touched
  file_contains "$cverify_skill" "file_paths_touched" \
    "INV-005h: cverify still writes file_paths_touched field"

  # INV-005i: cverify still writes timestamp
  file_contains "$cverify_skill" "timestamp" \
    "INV-005i: cverify still writes timestamp field"
}

# ============================================
# INV-006: Graceful absence unchanged
#   When calibration file doesn't exist or has zero entries,
#   /cspec proceeds without calibration input. No error, no warning.
# ============================================

test_inv006_graceful_absence() {
  echo ""
  echo "=== INV-006: Graceful absence unchanged ==="

  # INV-006a: cspec still handles missing calibration file gracefully
  file_contains_i "$CSPEC_SKILL" "does not exist\|file.*missing\|no.*calibration.*file\|absent" \
    "INV-006a: cspec handles missing calibration file"

  # INV-006b: no error or warning when file absent
  file_contains_i "$CSPEC_SKILL" "proceed.*without\|skip.*calibration\|no.*error\|dormant" \
    "INV-006b: cspec proceeds without calibration (dormant signal)"
}

# ============================================
# INV-007: Recency window unchanged
#   50-entry recency window MUST remain. /cspec reads at most
#   the 50 most recent entries.
# ============================================

test_inv007_recency_window() {
  echo ""
  echo "=== INV-007: Recency window unchanged ==="

  # INV-007a: cspec references 50-entry limit
  file_contains "$CSPEC_SKILL" "50" \
    "INV-007a: cspec references 50-entry recency window"

  # INV-007b: recency window language present
  file_contains_i "$CSPEC_SKILL" "recent.*entries\|recency.*window\|most recent.*50\|50.*most recent\|50.*entries" \
    "INV-007b: cspec contains recency window language"
}

# ============================================
# INV-008: No calibration mode in /csetup or templates
#   /csetup MUST NOT present calibration mode selection.
#   Config templates MUST NOT contain intensity_calibration_mode key.
# ============================================

test_inv008_no_mode_in_csetup_or_templates() {
  echo ""
  echo "=== INV-008: No calibration mode in /csetup or templates ==="

  # INV-008a: csetup does not present calibration mode selection
  file_not_contains "$CSETUP_SKILL" "intensity_calibration_mode" \
    "INV-008a: csetup SKILL.md does not reference intensity_calibration_mode"

  # INV-008b: csetup does not present passive/active/hybrid mode decision
  file_not_contains_i "$CSETUP_SKILL" "active.*auto.*raise\|hybrid.*passive.*5\|calibration.*mode.*selection" \
    "INV-008b: csetup does not present mode selection decision"

  # INV-008c: lite config template does NOT have intensity_calibration_mode
  file_not_contains "$LITE_CFG" "intensity_calibration_mode" \
    "INV-008c: templates/workflow-config.json does not contain intensity_calibration_mode"

  # INV-008d: full config template does NOT have intensity_calibration_mode
  file_not_contains "$FULL_CFG" "intensity_calibration_mode" \
    "INV-008d: templates/workflow-config-full.json does not contain intensity_calibration_mode"

  # INV-008e: distribution lite config template also clean
  file_not_contains "$LITE_CFG_DIST" "intensity_calibration_mode" \
    "INV-008e: dist templates/workflow-config.json does not contain intensity_calibration_mode"

  # INV-008f: distribution full config template also clean
  file_not_contains "$FULL_CFG_DIST" "intensity_calibration_mode" \
    "INV-008f: dist templates/workflow-config-full.json does not contain intensity_calibration_mode"

  # INV-008g: csetup dist also clean
  file_not_contains "$CSETUP_DIST" "intensity_calibration_mode" \
    "INV-008g: dist csetup SKILL.md does not reference intensity_calibration_mode"
}

# ============================================
# INV-009: Documentation reflects removal
#   AGENT_CONTEXT.md and FEATURES.md MUST NOT describe active mode,
#   hybrid mode, or 200K token auto-raise as current functionality.
# ============================================

test_inv009_docs_reflect_removal() {
  echo ""
  echo "=== INV-009: Documentation reflects removal ==="

  # INV-009a: AGENT_CONTEXT.md does not describe active mode auto-raise
  file_not_contains_i "$AGENT_CONTEXT" "active.*auto-raise\|auto-raise.*active" \
    "INV-009a: AGENT_CONTEXT.md does not describe active mode auto-raise"

  # INV-009b: AGENT_CONTEXT.md does not describe hybrid mode
  file_not_contains_i "$AGENT_CONTEXT" "hybrid.*passive.*active\|passive.*active after 5" \
    "INV-009b: AGENT_CONTEXT.md does not describe hybrid mode"

  # INV-009c: AGENT_CONTEXT.md does not describe 200K token trigger
  file_not_contains_i "$AGENT_CONTEXT" "200K.*trigger\|200K.*auto-raise\|exceeding 200K.*trigger" \
    "INV-009c: AGENT_CONTEXT.md does not describe 200K token trigger"

  # INV-009d: AGENT_CONTEXT.md does not list configurable modes
  file_not_contains_i "$AGENT_CONTEXT" "Configurable modes:.*passive.*active.*hybrid\|modes:.*passive.*active.*hybrid" \
    "INV-009d: AGENT_CONTEXT.md does not list configurable calibration modes"

  # INV-009e: FEATURES.md does not describe active mode auto-raise
  file_not_contains_i "$FEATURES_FILE" "active.*auto-raise\|auto-raise.*active" \
    "INV-009e: FEATURES.md does not describe active mode auto-raise"

  # INV-009f: FEATURES.md does not describe hybrid mode
  file_not_contains_i "$FEATURES_FILE" "hybrid.*passive.*active\|passive.*active after 5" \
    "INV-009f: FEATURES.md does not describe hybrid mode"

  # INV-009g: FEATURES.md does not describe 200K token trigger
  file_not_contains_i "$FEATURES_FILE" "200K.*trigger\|200K.*auto-raise\|exceeding 200K.*trigger" \
    "INV-009g: FEATURES.md does not describe 200K token trigger"
}

# ============================================
# PRH-001: No automated intensity decisions
#   Calibration MUST NEVER automatically change the recommendation.
#   Advisory context only.
# ============================================

test_prh001_no_automated_decisions() {
  echo ""
  echo "=== PRH-001: No automated intensity decisions ==="

  # PRH-001a: no auto-raise in calibration section
  section_not_contains "$CSPEC_SKILL" "Step 7b" "auto-raise\|auto-adjust\|automatically" \
    "PRH-001a: Step 7b has no auto-raise/auto-adjust/automatically"

  # PRH-001b: no "raise" or "lower" commands in calibration
  section_not_contains "$CSPEC_SKILL" "Step 7b" "raise.*level\|lower.*level\|adjust.*level" \
    "PRH-001b: Step 7b has no raise/lower/adjust level language"

  # PRH-001c: calibration explicitly described as advisory/read-only
  file_contains_i "$CSPEC_SKILL" "advisory\|read-only.*calibration\|calibration.*advisory" \
    "PRH-001c: calibration described as advisory"
}

# ============================================
# PRH-002: No removal of data collection
#   /cverify calibration entry writer MUST still exist.
#   Calibration file must NOT be deleted.
# ============================================

test_prh002_data_collection_intact() {
  echo ""
  echo "=== PRH-002: No removal of data collection ==="

  local cverify_skill="$REPO_DIR/skills/cverify/SKILL.md"

  # PRH-002a: cverify still has calibration write instructions
  file_contains_i "$cverify_skill" "write.*calibration\|append.*calibration\|add.*calibration.*entry" \
    "PRH-002a: cverify still has calibration write instructions"

  # PRH-002b: cverify still references the calibration file path
  file_contains "$cverify_skill" "intensity-calibration.json" \
    "PRH-002b: cverify still references intensity-calibration.json"

  # PRH-002c: calibration file is not deleted (meta directory reference preserved)
  file_contains_i "$cverify_skill" ".correctless/meta" \
    "PRH-002c: cverify still references .correctless/meta/ directory"
}

# ============================================
# Cross-check: Existing preserved tests still pass
#   Verify the test functions that should NOT be removed
#   still exist in the original test files.
# ============================================

test_preserved_tests_exist() {
  echo ""
  echo "=== Cross-check: Preserved test functions still exist ==="

  local cal_test="$REPO_DIR/tests/test-intensity-calibration.sh"
  local tok_test="$REPO_DIR/tests/test-token-aware-intensity.sh"

  # Preserved in test-intensity-calibration.sh
  file_contains "$cal_test" "test_inv001_cverify_writes_calibration" \
    "preserved: test_inv001_cverify_writes_calibration exists"

  file_contains "$cal_test" "test_inv002_calibration_schema" \
    "preserved: test_inv002_calibration_schema exists"

  file_contains "$cal_test" "test_inv003_cspec_reads_calibration" \
    "preserved: test_inv003_cspec_reads_calibration exists"

  file_contains "$cal_test" "test_inv007_cspec_read_only" \
    "preserved: test_inv007_cspec_read_only exists"

  file_contains "$cal_test" "test_inv008_no_calibration_graceful" \
    "preserved: test_inv008_no_calibration_graceful exists"

  file_contains "$cal_test" "test_inv009_recommended_intensity_field" \
    "preserved: test_inv009_recommended_intensity_field exists"

  file_contains "$cal_test" "test_inv010_recency_window" \
    "preserved: test_inv010_recency_window exists"

  file_contains "$cal_test" "test_inv011_post_signal_modifier" \
    "preserved: test_inv011_post_signal_modifier exists"

  file_contains "$cal_test" "test_prh001_no_calibration_in_state" \
    "preserved: test_prh001_no_calibration_in_state exists"

  file_contains "$cal_test" "test_prh002_no_thresholds_in_config" \
    "preserved: test_prh002_no_thresholds_in_config exists"

  # Preserved in test-token-aware-intensity.sh
  file_contains "$tok_test" "test_inv001_cverify_writes_actual_tokens" \
    "preserved: test_inv001_cverify_writes_actual_tokens exists"

  file_contains "$tok_test" "test_inv002_cspec_reads_actual_tokens" \
    "preserved: test_inv002_cspec_reads_actual_tokens exists"
}

# ============================================
# Cross-check: Removed test functions are gone
#   Verify the test functions that SHOULD be removed
#   are no longer present.
# ============================================

test_removed_tests_gone() {
  echo ""
  echo "=== Cross-check: Removed test functions are gone ==="

  local cal_test="$REPO_DIR/tests/test-intensity-calibration.sh"
  local tok_test="$REPO_DIR/tests/test-token-aware-intensity.sh"

  # Removed from test-intensity-calibration.sh
  file_not_contains "$cal_test" "test_inv004_csetup_calibration_mode" \
    "removed: test_inv004_csetup_calibration_mode is gone"

  file_not_contains "$cal_test" "test_inv005_mode_behaviors" \
    "removed: test_inv005_mode_behaviors is gone"

  # Removed from test-token-aware-intensity.sh
  file_not_contains "$tok_test" "test_inv003_token_threshold_active_mode" \
    "removed: test_inv003_token_threshold_active_mode is gone"
}

# ============================================
# Cross-check: Updated tests have correct assertions
#   INV-006 (config templates) — remove intensity_calibration_mode
#   assertion, keep template existence check.
#   INV-012 (show arithmetic) — remove threshold comparison and
#   "Consider.*intensity" assertions.
#   INV-004c (passive token arithmetic) — remove 200K threshold.
#   INV-008i (behavioral constant check) — remove 200K presence check.
# ============================================

test_updated_tests_correct() {
  echo ""
  echo "=== Cross-check: Updated test assertions ==="

  local cal_test="$REPO_DIR/tests/test-intensity-calibration.sh"
  local tok_test="$REPO_DIR/tests/test-token-aware-intensity.sh"

  # test_inv006_config_templates — should NOT assert intensity_calibration_mode presence
  # (the test function itself may still exist to check templates exist, but the
  # specific assertion about intensity_calibration_mode must be gone)
  local inv006_body
  inv006_body="$(sed -n '/^test_inv006_config_templates/,/^}/p' "$cal_test" 2>/dev/null)"
  if echo "$inv006_body" | grep -q "intensity_calibration_mode"; then
    echo "  FAIL: updated: test_inv006 still asserts intensity_calibration_mode presence"
    FAIL=$((FAIL + 1))
  else
    echo "  PASS: updated: test_inv006 no longer asserts intensity_calibration_mode presence"
    PASS=$((PASS + 1))
  fi

  # test_inv012_show_arithmetic — should NOT assert threshold comparison
  local inv012_body
  inv012_body="$(sed -n '/^test_inv012_show_arithmetic/,/^}/p' "$cal_test" 2>/dev/null)"
  if echo "$inv012_body" | grep -qi "threshold.*comparison\|Compare.*threshold"; then
    echo "  FAIL: updated: test_inv012 still asserts threshold comparison"
    FAIL=$((FAIL + 1))
  else
    echo "  PASS: updated: test_inv012 no longer asserts threshold comparison"
    PASS=$((PASS + 1))
  fi

  # test_inv012_show_arithmetic — should NOT assert "Consider.*intensity"
  if echo "$inv012_body" | grep -qi "Consider.*intensity\|consider.*higher"; then
    echo "  FAIL: updated: test_inv012 still asserts 'Consider higher intensity'"
    FAIL=$((FAIL + 1))
  else
    echo "  PASS: updated: test_inv012 no longer asserts 'Consider higher intensity'"
    PASS=$((PASS + 1))
  fi

  # test_inv004_passive_token_arithmetic in token-aware — should NOT assert 200K threshold
  local inv004c_body
  inv004c_body="$(sed -n '/^test_inv004_passive_token_arithmetic/,/^}/p' "$tok_test" 2>/dev/null)"
  if echo "$inv004c_body" | grep -qi "200,000.*threshold\|threshold.*200,000\|200000.*threshold"; then
    echo "  FAIL: updated: test_inv004c (token-aware) still asserts 200K threshold"
    FAIL=$((FAIL + 1))
  else
    echo "  PASS: updated: test_inv004c (token-aware) no longer asserts 200K threshold"
    PASS=$((PASS + 1))
  fi

  # INV-008i check — should NOT assert 200K presence in cspec as a positive check
  local inv008_body
  inv008_body="$(sed -n '/^test_inv008_threshold_is_constant/,/^}/p' "$tok_test" 2>/dev/null)"
  if echo "$inv008_body" | grep -qi "INV-008i.*200,000\|200,000.*behavioral constant"; then
    echo "  FAIL: updated: test_inv008i still asserts 200K is present as behavioral constant"
    FAIL=$((FAIL + 1))
  else
    echo "  PASS: updated: test_inv008i no longer asserts 200K presence"
    PASS=$((PASS + 1))
  fi
}

# ============================================
# Runner
# ============================================

echo "============================================="
echo "Simplify Intensity Calibration Test Suite"
echo "============================================="

test_inv001_no_auto_raise
test_inv002_no_calibration_mode_key
test_inv003_no_200k_threshold
test_inv004_passive_advisory_display
test_inv005_cverify_writer_unchanged
test_inv006_graceful_absence
test_inv007_recency_window
test_inv008_no_mode_in_csetup_or_templates
test_inv009_docs_reflect_removal
test_prh001_no_automated_decisions
test_prh002_data_collection_intact
test_preserved_tests_exist
test_removed_tests_gone
test_updated_tests_correct

echo ""
echo "============================================="
echo "Results: $PASS passed, $FAIL failed"
echo "============================================="

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
