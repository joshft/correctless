#!/usr/bin/env bash
# Correctless — wire intensity into /creview test suite
# Tests spec rules R-001 through R-011 from
# .correctless/specs/wire-intensity-creview.md
# Run from repo root: bash tests/test-wire-intensity-creview.sh

set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="/tmp/correctless-wire-intensity-creview-test-$$"
PASS=0
FAIL=0

# ============================================
# Helpers (matching project test conventions)
# ============================================

setup_test_project() {
  rm -rf "$TEST_DIR"
  mkdir -p "$TEST_DIR"
  cd "$TEST_DIR" || exit
  git init -q
  git branch -M main
  echo '{"name": "test-app", "version": "1.0.0"}' > package.json
  echo 'export function hello() {}' > index.ts
  git add -A && git commit -q -m "init"

  # Install correctless (exclude .git to avoid nested repo confusion)
  mkdir -p .claude/skills/workflow
  rsync -a --exclude='.git' --exclude='tests' "$REPO_DIR/" .claude/skills/workflow/
}

cleanup() {
  rm -rf "$TEST_DIR"
}
trap cleanup EXIT

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

# Check that pattern A appears before pattern B in a file (by line number)
file_order() {
  local file="$1" first_pattern="$2" second_pattern="$3" desc="$4"
  local first_line second_line
  first_line="$(grep -n "$first_pattern" "$file" 2>/dev/null | head -1 | cut -d: -f1)"
  second_line="$(grep -n "$second_pattern" "$file" 2>/dev/null | head -1 | cut -d: -f1)"
  if [ -z "$first_line" ]; then
    echo "  FAIL: $desc (first pattern '$first_pattern' not found in $file)"
    FAIL=$((FAIL + 1))
  elif [ -z "$second_line" ]; then
    echo "  FAIL: $desc (second pattern '$second_pattern' not found in $file)"
    FAIL=$((FAIL + 1))
  elif [ "$first_line" -lt "$second_line" ]; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc ('$first_pattern' at line $first_line should be before '$second_pattern' at line $second_line)"
    FAIL=$((FAIL + 1))
  fi
}

# ============================================
# R-001: /creview SKILL.md has "Intensity Configuration" section
#        with markdown table (Standard, High, Critical columns)
# ============================================

test_r001_intensity_configuration_table() {
  echo ""
  echo "=== R-001: /creview SKILL.md has Intensity Configuration section with table ==="

  local skill_file="$REPO_DIR/skills/creview/SKILL.md"

  # R-001: section header exists
  file_contains "$skill_file" "## Intensity Configuration" \
    "R-001: creview SKILL.md has '## Intensity Configuration' section"

  # R-001: table header row has Standard, High, Critical columns
  # Look for markdown table header with all three columns
  file_contains "$skill_file" "| Standard | High | Critical" \
    "R-001: table header has Standard, High, Critical columns"

  # R-001: table row for agents — standard is "1 + security checklist"
  file_contains_i "$skill_file" "1 + security checklist\|1.*security checklist" \
    "R-001: Standard agents row includes '1 + security checklist'"

  # R-001: table row for high agents — "Routes to /creview-spec"
  file_contains_i "$skill_file" "Routes to /creview-spec" \
    "R-001: High agents row includes 'Routes to /creview-spec'"

  # R-001: table row for critical agents — "Routes to /creview-spec + external model"
  file_contains_i "$skill_file" "Routes to /creview-spec.*external model\|external model" \
    "R-001: Critical agents row includes 'external model'"

  # R-001: table row for findings — Standard = "Disposition required"
  file_contains_i "$skill_file" "Disposition required" \
    "R-001: Standard finding threshold is 'Disposition required'"

  # R-001: table row for findings — High = "All addressed"
  file_contains_i "$skill_file" "All addressed" \
    "R-001: High finding threshold is 'All addressed'"

  # R-001: table row for findings — Critical = "Zero unresolved"
  file_contains_i "$skill_file" "Zero unresolved" \
    "R-001: Critical finding threshold is 'Zero unresolved'"

  # R-001: row labels present in table
  file_contains_i "$skill_file" "| Agents" \
    "R-001: table has 'Agents' row label"
  file_contains_i "$skill_file" "| Finding threshold" \
    "R-001: table has 'Finding threshold' row label"

  # R-001: column positioning — "1 + security checklist" on same row as "Agents"
  file_contains_i "$skill_file" "Agents.*1 + security checklist\|Agents.*1.*security checklist" \
    "R-001: 'Agents' row has '1 + security checklist' in correct column"
}

# ============================================
# R-002: /creview SKILL.md has "Effective Intensity" section
#        with max(project_intensity, feature_intensity) computation
# ============================================

test_r002_effective_intensity_section() {
  echo ""
  echo "=== R-002: /creview SKILL.md has Effective Intensity section ==="

  local skill_file="$REPO_DIR/skills/creview/SKILL.md"

  # R-002: section header exists
  file_contains "$skill_file" "## Effective Intensity" \
    "R-002: creview SKILL.md has '## Effective Intensity' section"

  # R-002: max computation documented
  file_contains "$skill_file" "max(project_intensity, feature_intensity)" \
    "R-002: documents max(project_intensity, feature_intensity) computation"

  # R-002: ordering documented
  file_contains "$skill_file" "standard < high < critical" \
    "R-002: documents ordering standard < high < critical"

  # R-002: references workflow.intensity from config
  file_contains "$skill_file" "workflow.intensity" \
    "R-002: references workflow.intensity from config"

  # R-002: references reading project intensity from workflow-config.json
  file_contains_i "$skill_file" "workflow.intensity.*workflow-config.json\|workflow-config.json.*workflow.intensity\|project.*intensity.*config" \
    "R-002: references reading project intensity from workflow-config.json"

  # R-002: references feature_intensity from workflow state
  file_contains "$skill_file" "feature_intensity" \
    "R-002: references feature_intensity"

  # R-002: references workflow-advance.sh status as the interface
  file_contains "$skill_file" "workflow-advance.sh status" \
    "R-002: instructs reading via workflow-advance.sh status"

  # R-002: absent feature_intensity defaults to project intensity alone
  file_contains_i "$skill_file" "feature_intensity.*absent.*project\|absent.*feature_intensity.*project\|feature_intensity is absent" \
    "R-002: absent feature_intensity falls back to project intensity"
}

# ============================================
# R-003: Standard intensity matches current behavior
#        all 8 checks, security checklist, disposition required
# ============================================

test_r003_standard_behavior() {
  echo ""
  echo "=== R-003: Standard intensity matches current behavior ==="

  local skill_file="$REPO_DIR/skills/creview/SKILL.md"

  # R-003: security checklist fires at standard
  file_contains_i "$skill_file" "security checklist\|Security Checklist" \
    "R-003: security checklist present in review body"

  # R-003: disposition required for findings
  file_contains_i "$skill_file" "disposition" \
    "R-003: findings require disposition"

  # R-003: all 8 checks documented (assumptions, testability, edge cases,
  #        antipattern, integration test coverage, security, compliance, self-assessment)
  file_contains_i "$skill_file" "Assumptions" \
    "R-003: Assumptions check present"
  file_contains_i "$skill_file" "Testability" \
    "R-003: Testability check present"
  file_contains_i "$skill_file" "Edge Cases" \
    "R-003: Edge Cases check present"
  file_contains_i "$skill_file" "Antipattern" \
    "R-003: Antipattern check present"
  file_contains_i "$skill_file" "Integration Test Coverage" \
    "R-003: Integration Test Coverage check present"
  file_contains_i "$skill_file" "Security Checklist" \
    "R-003: Security Checklist check present"
  file_contains_i "$skill_file" "compliance" \
    "R-003: standard behavior includes compliance checks"
  file_contains_i "$skill_file" "self-assessment\|self assessment" \
    "R-003: standard behavior includes self-assessment"

  # R-003: no explicit standard-intensity routing section exists
  file_not_contains "$skill_file" "effective intensity is standard" \
    "R-003: no explicit standard-intensity routing section exists"
}

# ============================================
# R-004: High intensity routes to /creview-spec
#        with numbered options and recommendation
# ============================================

test_r004_high_intensity_routing() {
  echo ""
  echo "=== R-004: High intensity routes to /creview-spec ==="

  local skill_file="$REPO_DIR/skills/creview/SKILL.md"

  # R-004: mentions effective intensity is high
  file_contains_i "$skill_file" "effective intensity is high\|effective intensity.*high" \
    "R-004: mentions effective intensity is high"

  # R-004: high intensity routing text tells user to run /creview-spec
  file_contains_i "$skill_file" "Run.*creview-spec.*4-agent adversarial" \
    "R-004: routes to /creview-spec with 4-agent adversarial review at high intensity"

  # R-004: numbered option 1 — switch (recommended)
  file_contains_i "$skill_file" "Switch.*creview-spec\|1.*Switch\|1.*creview-spec" \
    "R-004: numbered option to switch to /creview-spec"

  # R-004: numbered option 2 — proceed with single-pass
  file_contains_i "$skill_file" "Proceed.*single-pass\|2.*Proceed\|2.*single" \
    "R-004: numbered option to proceed with single-pass review"

  # R-004: recommended tag on /creview-spec switch option
  file_contains_i "$skill_file" "Switch.*recommended\|creview-spec.*recommended" \
    "R-004: /creview-spec switch option marked as (recommended)"

  # R-004: routing is a recommendation, not a block —
  # the user can proceed with single-pass even at high intensity
  file_contains_i "$skill_file" "proceed with single-pass\|proceed.*single.*review\|confirm below" \
    "R-004: user can proceed with single-pass review (recommendation, not block)"

  # R-004: high single-pass explicitly states standard behavior
  file_contains_i "$skill_file" "all 8 checks.*security checklist\|standard.*single-pass\|single-pass.*standard\|proceed.*all.*checks" \
    "R-004: high single-pass explicitly states standard behavior"
}

# ============================================
# R-005: Critical intensity routing — zero unresolved threshold
# ============================================

test_r005_critical_intensity_routing() {
  echo ""
  echo "=== R-005: Critical intensity routes to /creview-spec with zero-unresolved ==="

  local skill_file="$REPO_DIR/skills/creview/SKILL.md"

  # R-005: mentions effective intensity is critical
  file_contains_i "$skill_file" "effective intensity is critical\|effective intensity.*critical" \
    "R-005: mentions effective intensity is critical"

  # R-005: routes to /creview-spec with external model
  file_contains_i "$skill_file" "external model" \
    "R-005: mentions external model verification"

  # R-005: zero-unresolved threshold
  file_contains_i "$skill_file" "zero.*unresolved\|zero-unresolved" \
    "R-005: mentions zero-unresolved threshold"

  # R-005: every finding must be addressed
  file_contains_i "$skill_file" "every finding.*addressed\|every finding must" \
    "R-005: states every finding must be addressed"

  # R-005: does not advance workflow until all addressed
  file_contains_i "$skill_file" "does not advance\|not advance.*workflow\|workflow.*not.*advance" \
    "R-005: does not advance workflow state until resolved"

  # R-005: same numbered options as R-004
  file_contains_i "$skill_file" "Switch.*creview-spec\|1.*Switch" \
    "R-005: has numbered option to switch to /creview-spec (same as high)"

  # R-005: option 2 — proceed with single-pass (same options as R-004)
  file_contains_i "$skill_file" "Proceed.*single.*pass\|2.*Proceed\|single-pass.*review" \
    "R-005: has option 2 to proceed with single-pass (same options as R-004)"

  # R-005: zero-unresolved section lists all 4 disposition types
  file_contains "$skill_file" "accept, reject, modify, or defer" \
    "R-005: zero-unresolved section lists all 4 disposition types"

  # R-005: zero-unresolved instruction appears before the output/findings section
  file_order "$skill_file" \
    "zero.*unresolved\|every finding.*addressed\|does not advance" \
    "## Output\|## Advance State" \
    "R-005: zero-unresolved instruction appears before output/advance section"
}

# ============================================
# R-006: workflow-advance.sh status outputs feature_intensity;
#        SKILL.md reads from status output, not state file directly
# ============================================

test_r006_status_outputs_feature_intensity() {
  echo ""
  echo "=== R-006: workflow-advance.sh status outputs feature_intensity ==="

  # R-006 [integration]: set up a test project with feature_intensity in state
  setup_test_project
  git checkout -q -b feature/test-r006
  .claude/skills/workflow/hooks/workflow-advance.sh init "test r006" 2>/dev/null
  .claude/skills/workflow/hooks/workflow-advance.sh set-intensity "high" 2>/dev/null

  local status_output
  status_output="$(.claude/skills/workflow/hooks/workflow-advance.sh status 2>&1)"

  # R-006: status output contains Intensity line
  assert_contains "R-006: status output contains 'Intensity:'" \
    "Intensity:" "$status_output"

  # R-006: status output shows the value we set
  assert_contains "R-006: status output shows 'high'" \
    "high" "$status_output"

  cleanup

  # R-006 [unit]: SKILL.md instructs reading from status output
  local skill_file="$REPO_DIR/skills/creview/SKILL.md"

  file_contains "$skill_file" "workflow-advance.sh status" \
    "R-006: SKILL.md instructs reading feature_intensity from status output"

  # R-006: SKILL.md instructs NOT parsing state file directly
  # (the instruction should reference status, not direct JSON parsing)
  file_not_contains "$skill_file" "workflow-state-.*json" \
    "R-006: SKILL.md does not instruct parsing state file directly"

  # R-006: SKILL.md handles absent Intensity line gracefully
  file_contains_i "$skill_file" "no.*Intensity line\|Intensity.*absent\|absent.*feature_intensity\|Intensity line.*absent" \
    "R-006: SKILL.md handles absent Intensity line in status output"
}

# ============================================
# R-007: "When to use" line updated for effective intensity
# ============================================

test_r007_when_to_use_updated() {
  echo ""
  echo "=== R-007: 'When to use' line references effective intensity ==="

  local skill_file="$REPO_DIR/skills/creview/SKILL.md"

  # R-007: should reference effective intensity
  file_contains_i "$skill_file" "effective intensity\|adapts based on.*intensity" \
    "R-007: 'When to use' area references effective intensity"

  # R-007: specifically check the "When to use" line contains "effective intensity"
  local when_to_use
  when_to_use="$(grep -i "when to use" "$skill_file" | head -1)"
  echo "$when_to_use" | grep -qi "effective intensity" \
    && { echo "  PASS: R-007: 'When to use' line specifically references effective intensity"; PASS=$((PASS + 1)); } \
    || { echo "  FAIL: R-007: 'When to use' line specifically references effective intensity"; FAIL=$((FAIL + 1)); }

  # R-007: should NOT say "standard intensity" as a hardcoded mode
  file_not_contains "$skill_file" "This is the standard review at standard intensity" \
    "R-007: does NOT contain old hardcoded 'standard review at standard intensity' text"

  # R-007: should NOT tell user to manually choose between /creview and /creview-spec
  file_not_contains "$skill_file" "At high+ intensity, use ./creview-spec. instead" \
    "R-007: does NOT tell user to manually choose /creview-spec"
}

# ============================================
# R-008: All 7 gated skills check effective intensity
#        (max of project and feature), not just project
# ============================================

test_r008_gated_skills_effective_intensity() {
  echo ""
  echo "=== R-008: All 7 gated skills use effective intensity ==="

  local gated_skills=(
    "$REPO_DIR/skills/caudit/SKILL.md"
    "$REPO_DIR/skills/cdevadv/SKILL.md"
    "$REPO_DIR/skills/cmodel/SKILL.md"
    "$REPO_DIR/skills/cpostmortem/SKILL.md"
    "$REPO_DIR/skills/credteam/SKILL.md"
    "$REPO_DIR/skills/creview-spec/SKILL.md"
    "$REPO_DIR/skills/cupdate-arch/SKILL.md"
  )

  for skill_file in "${gated_skills[@]}"; do
    local skill_name
    skill_name="$(basename "$(dirname "$skill_file")")"

    # R-008: each gated skill references max(project_intensity, feature_intensity)
    file_contains "$skill_file" "max(project_intensity, feature_intensity)" \
      "R-008: $skill_name references max(project_intensity, feature_intensity)"

    # R-008: each gated skill references both workflow.intensity AND feature_intensity
    file_contains "$skill_file" "workflow.intensity" \
      "R-008: $skill_name references workflow.intensity"
    file_contains "$skill_file" "feature_intensity" \
      "R-008: $skill_name references feature_intensity"
  done
}

# ============================================
# R-009: Consistent max computation across all 8 skills
#        (creview + 7 gated skills)
# ============================================

test_r009_consistent_max_computation() {
  echo ""
  echo "=== R-009: Consistent max(project_intensity, feature_intensity) across all skills ==="

  local all_skills=(
    "$REPO_DIR/skills/creview/SKILL.md"
    "$REPO_DIR/skills/caudit/SKILL.md"
    "$REPO_DIR/skills/cdevadv/SKILL.md"
    "$REPO_DIR/skills/cmodel/SKILL.md"
    "$REPO_DIR/skills/cpostmortem/SKILL.md"
    "$REPO_DIR/skills/credteam/SKILL.md"
    "$REPO_DIR/skills/creview-spec/SKILL.md"
    "$REPO_DIR/skills/cupdate-arch/SKILL.md"
  )

  for skill_file in "${all_skills[@]}"; do
    local skill_name
    skill_name="$(basename "$(dirname "$skill_file")")"

    # R-009: each skill contains the max computation string
    file_contains "$skill_file" "max(project_intensity, feature_intensity)" \
      "R-009: $skill_name contains max(project_intensity, feature_intensity)"

    # R-009: each skill contains the ordering string
    file_contains "$skill_file" "standard < high < critical" \
      "R-009: $skill_name contains ordering standard < high < critical"
  done

  # R-009: max computation is NOT in workflow-advance.sh (LLM instruction only)
  file_not_contains "$REPO_DIR/hooks/workflow-advance.sh" "max(project_intensity" \
    "R-009: max computation is NOT in workflow-advance.sh (LLM instruction only)"
}

# ============================================
# R-010: Positioning — Intensity Configuration before Progress Visibility
# ============================================

test_r010_section_positioning() {
  echo ""
  echo "=== R-010: Intensity Configuration before Progress Visibility ==="

  local skill_file="$REPO_DIR/skills/creview/SKILL.md"

  # R-010: Intensity Configuration appears before Progress Visibility
  file_order "$skill_file" \
    "## Intensity Configuration" \
    "## Progress Visibility" \
    "R-010: '## Intensity Configuration' appears before '## Progress Visibility'"

  # R-010: Effective Intensity also appears before Progress Visibility
  file_order "$skill_file" \
    "## Effective Intensity" \
    "## Progress Visibility" \
    "R-010: '## Effective Intensity' appears before '## Progress Visibility'"

  # R-010: Intensity Configuration appears after the skill title
  file_order "$skill_file" \
    "# /creview" \
    "## Intensity Configuration" \
    "R-010: '## Intensity Configuration' appears after '# /creview' title"
}

# ============================================
# R-011: Fallback chain —
#        feature_intensity -> workflow.intensity -> standard
# ============================================

test_r011_fallback_chain() {
  echo ""
  echo "=== R-011: Fallback chain documented ==="

  local skill_file="$REPO_DIR/skills/creview/SKILL.md"

  # R-011: fallback chain documented
  file_contains_i "$skill_file" "feature_intensity.*workflow.intensity.*standard\|fallback.*chain\|falls back" \
    "R-011: documents fallback chain"

  # R-011: default is standard when both absent
  file_contains_i "$skill_file" "default.*standard\|defaults to.*standard" \
    "R-011: defaults to standard when config absent"

  # R-011: no active workflow handled gracefully — review still runs
  file_contains_i "$skill_file" "no active workflow\|no.*state file\|no.*workflow state" \
    "R-011: handles no active workflow gracefully"

  # R-011: review still runs without active workflow state
  file_contains_i "$skill_file" "review still runs\|still runs\|does not require.*workflow" \
    "R-011: review still runs without active workflow state"

  # R-011 [integration]: test that status with no feature_intensity omits the line
  setup_test_project
  git checkout -q -b feature/test-r011
  .claude/skills/workflow/hooks/workflow-advance.sh init "test r011" 2>/dev/null

  # Do NOT call set-intensity — feature_intensity should be absent
  local status_output
  status_output="$(.claude/skills/workflow/hooks/workflow-advance.sh status 2>&1)"

  # When feature_intensity is absent, status should NOT show an Intensity line
  assert_not_contains "R-011: status omits Intensity line when feature_intensity absent" \
    "Intensity:" "$status_output"

  cleanup
}

# ============================================
# Runner
# ============================================

echo "============================================="
echo "Wire Intensity into /creview Test Suite"
echo "============================================="

test_r001_intensity_configuration_table
test_r002_effective_intensity_section
test_r003_standard_behavior
test_r004_high_intensity_routing
test_r005_critical_intensity_routing
test_r006_status_outputs_feature_intensity
test_r007_when_to_use_updated
test_r008_gated_skills_effective_intensity
test_r009_consistent_max_computation
test_r010_section_positioning
test_r011_fallback_chain

echo ""
echo "============================================="
echo "Results: $PASS passed, $FAIL failed"
echo ""

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
