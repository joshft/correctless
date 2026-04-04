#!/usr/bin/env bash
# Correctless — per-feature intensity detection test suite
# Tests spec rules R-001 through R-013 from
# docs/specs/intensity-detection.md
# Run from repo root: bash tests/test-intensity-detection.sh

set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="/tmp/correctless-intensity-detection-test-$$"
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

# ============================================
# R-001: cspec SKILL.md has "Intensity Detection" section
#        describing 4 signals, NOT gated by intensity level
# ============================================

test_r001_intensity_detection_section() {
  echo ""
  echo "=== R-001: cspec SKILL.md has Intensity Detection section ==="

  local skill_file="$REPO_DIR/skills/cspec/SKILL.md"

  # R-001: section header exists
  file_contains "$skill_file" "Intensity Detection" \
    "R-001: cspec SKILL.md has 'Intensity Detection' section"

  # R-001: describes file path patterns signal
  file_contains_i "$skill_file" "file path\|file.*pattern\|path.*pattern" \
    "R-001: Intensity Detection describes file path patterns signal"

  # R-001: describes keyword matching signal
  file_contains_i "$skill_file" "keyword.*match\|keyword.*signal" \
    "R-001: Intensity Detection describes keyword matching signal"

  # R-001: describes trust boundary signal
  file_contains_i "$skill_file" "trust.*boundar\|TB-xxx" \
    "R-001: Intensity Detection describes trust boundary signal"

  # R-001: describes antipattern/QA history signal
  file_contains_i "$skill_file" "antipattern.*histor\|QA.*histor\|QA.*finding" \
    "R-001: Intensity Detection describes antipattern/QA history signal"

  # R-001: NOT gated by intensity level — should NOT have "(Full Mode)" qualifier
  #        on the Intensity Detection section
  file_not_contains "$skill_file" "Intensity Detection.*(Full Mode)" \
    "R-001: Intensity Detection is NOT gated by '(Full Mode)'"

  # R-001: section should say it runs for all projects
  file_contains_i "$skill_file" "all project\|all intensit\|regardless.*intensity" \
    "R-001: Intensity Detection states it runs for all projects"
}

# ============================================
# R-002: Signal-to-intensity mapping in SKILL.md
# ============================================

test_r002_signal_mapping() {
  echo ""
  echo "=== R-002: Signal-to-intensity mapping ==="

  local skill_file="$REPO_DIR/skills/cspec/SKILL.md"

  # R-002: path patterns — hooks/, security, setup produce high
  file_contains_i "$skill_file" "hooks/" \
    "R-002: mapping mentions hooks/ path pattern"

  # R-002: security keywords produce at least high
  for keyword in auth credential payment encrypt token secret session certificate CSRF injection; do
    file_contains_i "$skill_file" "$keyword" \
      "R-002: mapping includes '$keyword' keyword"
  done

  # R-002: critical keywords
  for keyword in "trust boundary" adversary "threat model" penetration; do
    file_contains_i "$skill_file" "$keyword" \
      "R-002: mapping includes '$keyword' critical keyword"
  done

  # R-002: TB-xxx references produce at least high
  file_contains_i "$skill_file" "TB-xxx\|trust boundar.*high" \
    "R-002: TB-xxx references produce at least high"

  # R-002: dormant signal handling — TB-xxx dormant when no entries
  file_contains_i "$skill_file" "dormant" \
    "R-002: mentions dormant signal concept"

  # R-002: antipattern matches produce at least high (2+ matches)
  file_contains_i "$skill_file" "antipattern.*match\|antipattern.*overlap" \
    "R-002: antipattern matching described"

  # B-2: antipattern threshold specifies the number 2
  file_contains_i "$skill_file" "2.*antipattern\|two.*antipattern" \
    "R-002: antipattern threshold references count of 2"

  # R-002: QA findings threshold (3+ findings)
  file_contains_i "$skill_file" "QA.*finding\|qa.*finding" \
    "R-002: QA findings threshold described"

  # B-2: QA findings threshold specifies the number 3
  file_contains_i "$skill_file" "3.*QA\|three.*QA\|3.*qa.*finding" \
    "R-002: QA findings threshold references count of 3"

  # B-2: keyword-to-level mappings — auth maps to high, adversary maps to critical
  file_contains_i "$skill_file" "auth.*high\|high.*auth" \
    "R-002: 'auth' keyword maps to at least high"
  file_contains_i "$skill_file" "adversary.*critical\|critical.*adversary" \
    "R-002: 'adversary' keyword maps to critical"

  # R-002: dormant when antipatterns.md does not exist
  file_contains_i "$skill_file" "antipatterns.md.*not exist\|antipatterns.md.*dormant\|does not exist.*dormant" \
    "R-002: antipattern signal dormant when file missing"

  # R-002: dormant when no qa-findings files exist
  file_contains_i "$skill_file" "qa-findings.*not exist\|qa-findings.*dormant\|no.*qa-findings.*dormant" \
    "R-002: QA history signal dormant when files missing"
}

# ============================================
# R-003: Humility qualifier for <5 features
# ============================================

test_r003_humility_qualifier() {
  echo ""
  echo "=== R-003: Humility qualifier for <5 completed features ==="

  local skill_file="$REPO_DIR/skills/cspec/SKILL.md"

  # R-003: mentions counting ### headers in workflow-history.md
  file_contains_i "$skill_file" "workflow-history.md" \
    "R-003: references workflow-history.md"

  file_contains_i "$skill_file" "###.*header\|count.*###\|### " \
    "R-003: mentions counting ### headers"

  # B-3: counting mechanism links ### headers to workflow-history.md
  file_contains_i "$skill_file" "###.*workflow-history\|workflow-history.*###\|count.*###.*header" \
    "R-003: counting instruction links ### headers to workflow-history.md"

  # R-003: threshold is 5 features
  file_contains "$skill_file" "fewer than 5\|less than 5\|< *5\|under 5" \
    "R-003: threshold is fewer than 5 completed features"

  # R-003: humility qualifier described
  file_contains_i "$skill_file" "humility\|low confidence\|limited.*histor" \
    "R-003: humility qualifier / low confidence language described"

  # R-003: file does not exist -> count is 0
  file_contains_i "$skill_file" "does not exist.*0\|not exist.*count.*0\|file.*missing.*0" \
    "R-003: if workflow-history.md missing, count is 0"

  # R-003: 5+ features -> no qualifier (tightened: checks the relationship
  # between 5+ completed features and the without-qualifier behavior)
  file_contains_i "$skill_file" "5 or more.*without.*qualifier\|5.*completed.*without\|more.*completed.*confidence without" \
    "R-003: 5+ completed features states confidence without the qualifier"
}

# ============================================
# R-004: Presentation format — numbered options, signals, recommended
# ============================================

test_r004_presentation() {
  echo ""
  echo "=== R-004: Intensity recommendation presentation ==="

  local skill_file="$REPO_DIR/skills/cspec/SKILL.md"

  # R-004: presented in Step 8 (before walking through rules)
  file_contains_i "$skill_file" "Step 8.*intensit\|first item.*Step 8\|intensity.*Step 8" \
    "R-004: intensity recommendation presented in Step 8"

  # R-004: recommended level shown
  file_contains_i "$skill_file" "recommended.*level\|recommend.*level\|recommended.*intensity" \
    "R-004: shows recommended level"

  # R-004: signals that triggered are shown
  file_contains_i "$skill_file" "signals.*trigger\|triggered.*signal\|specific.*file path\|specific.*keyword" \
    "R-004: shows which signals triggered"

  # R-004: options include accept, raise, lower, override
  file_contains_i "$skill_file" "accept" \
    "R-004: accept option"
  file_contains_i "$skill_file" "raise" \
    "R-004: raise option"
  file_contains_i "$skill_file" "lower" \
    "R-004: lower option"
  file_contains_i "$skill_file" "override" \
    "R-004: override option"

  # R-004: recommended option is marked
  file_contains "$skill_file" "(recommended)" \
    "R-004: recommended option is marked with '(recommended)'"
}

# ============================================
# R-005: Spec Metadata section with required fields
# ============================================

test_r005_metadata_section() {
  echo ""
  echo "=== R-005: Spec Metadata section with required fields ==="

  local skill_file="$REPO_DIR/skills/cspec/SKILL.md"

  # R-005: Metadata section documented in SKILL.md
  file_contains "$skill_file" "## Metadata" \
    "R-005: cspec SKILL.md describes Metadata section"

  # R-005: Task field
  file_contains_i "$skill_file" "Task.*feature name\|Task.*field" \
    "R-005: Metadata includes Task field"

  # R-005: Intensity field
  file_contains_i "$skill_file" "Intensity.*approved.*level\|Intensity.*standard.*high.*critical" \
    "R-005: Metadata includes Intensity field (standard/high/critical)"

  # R-005: Intensity reason field
  file_contains_i "$skill_file" "Intensity reason\|Intensity.*reason" \
    "R-005: Metadata includes Intensity reason field"

  # R-005: Override field
  file_contains_i "$skill_file" "Override.*none.*raised.*lowered\|Override.*field" \
    "R-005: Metadata includes Override field (none/raised/lowered)"
}

# ============================================
# R-006: feature_intensity written to state file
#        via workflow-advance.sh set-intensity
# ============================================

test_r006_feature_intensity_state() {
  echo ""
  echo "=== R-006: feature_intensity written via set-intensity ==="

  local skill_file="$REPO_DIR/skills/cspec/SKILL.md"
  local hook_file="$REPO_DIR/hooks/workflow-advance.sh"

  # R-006: cspec SKILL.md instructs writing feature_intensity via set-intensity
  file_contains "$skill_file" "set-intensity" \
    "R-006: cspec references set-intensity subcommand"

  file_contains "$skill_file" "feature_intensity" \
    "R-006: cspec references feature_intensity field"

  # R-006: cspec does NOT instruct writing directly to state file via jq
  #        (PAT-004: workflow-advance.sh is the only state file writer)
  file_not_contains "$skill_file" "jq.*workflow-state\|write.*state.*file.*directly" \
    "R-006: cspec does NOT write directly to state file"

  # B-6: positive assertion that SKILL.md explicitly states workflow-advance.sh
  # is the exclusive state writer (PAT-004)
  file_contains_i "$skill_file" "only.*workflow-advance\|workflow-advance.*only\|PAT-004" \
    "R-006: SKILL.md states workflow-advance.sh is the only state writer (PAT-004)"

  # R-006 [integration]: actually run set-intensity in a test project
  setup_test_project

  # Create feature branch and init workflow
  git checkout -q -b feature/test-intensity
  .claude/skills/workflow/hooks/workflow-advance.sh init "test intensity" 2>/dev/null

  # Run set-intensity
  local _set_result
  _set_result="$(.claude/skills/workflow/hooks/workflow-advance.sh set-intensity "high" 2>&1)" \
    && local set_exit=0 || local set_exit=$?
  assert_eq "R-006: set-intensity exits 0 for valid value" "0" "$set_exit"

  # Check feature_intensity is in state file
  local state_file
  state_file="$(ls .correctless/artifacts/workflow-state-*.json 2>/dev/null | head -1)"
  if [ -n "$state_file" ] && [ -f "$state_file" ]; then
    local fi_val
    fi_val="$(jq -r '.feature_intensity // empty' "$state_file" 2>/dev/null)"
    assert_eq "R-006: feature_intensity is 'high' in state file" "high" "$fi_val"
  else
    echo "  FAIL: R-006: state file not found after init + set-intensity"
    FAIL=$((FAIL + 1))
  fi

  cleanup
}

# ============================================
# R-007: workflow-advance.sh has set-intensity subcommand
# ============================================

test_r007_set_intensity_subcommand() {
  echo ""
  echo "=== R-007: workflow-advance.sh set-intensity subcommand ==="

  local hook_file="$REPO_DIR/hooks/workflow-advance.sh"

  # R-007: set-intensity appears in the case dispatch
  file_contains "$hook_file" "set-intensity" \
    "R-007: workflow-advance.sh has set-intensity in case dispatch"

  # R-007: accepts standard, high, critical
  setup_test_project
  git checkout -q -b feature/test-r007
  .claude/skills/workflow/hooks/workflow-advance.sh init "test r007" 2>/dev/null

  for level in standard high critical; do
    local _result
    _result="$(.claude/skills/workflow/hooks/workflow-advance.sh set-intensity "$level" 2>&1)" \
      && local exit_code=0 || local exit_code=$?
    assert_eq "R-007: set-intensity accepts '$level'" "0" "$exit_code"
  done

  # B-1: After looping through standard/high/critical, verify state file contains
  # the last value written ("critical")
  local state_file_r007
  state_file_r007="$(ls .correctless/artifacts/workflow-state-*.json 2>/dev/null | head -1)"
  if [ -n "$state_file_r007" ] && [ -f "$state_file_r007" ]; then
    local last_intensity
    last_intensity="$(jq -r '.feature_intensity // empty' "$state_file_r007" 2>/dev/null)"
    assert_eq "R-007: state file contains last set-intensity value 'critical'" "critical" "$last_intensity"
  else
    echo "  FAIL: R-007: state file not found after set-intensity loop"
    FAIL=$((FAIL + 1))
  fi

  # R-007: invalid value produces error and exit non-zero
  local _bad_result
  _bad_result="$(.claude/skills/workflow/hooks/workflow-advance.sh set-intensity "invalid-level" 2>&1)" \
    && local bad_exit=0 || local bad_exit=$?
  assert_eq "R-007: set-intensity rejects 'invalid-level' (non-zero exit)" "true" \
    "$([ "$bad_exit" -ne 0 ] && echo true || echo false)"

  # R-007: empty value produces error
  local _empty_result
  _empty_result="$(.claude/skills/workflow/hooks/workflow-advance.sh set-intensity "" 2>&1)" \
    && local empty_exit=0 || local empty_exit=$?
  assert_eq "R-007: set-intensity rejects empty value (non-zero exit)" "true" \
    "$([ "$empty_exit" -ne 0 ] && echo true || echo false)"

  # R-007: init does NOT set feature_intensity
  cleanup
  setup_test_project
  git checkout -q -b feature/test-r007-init
  .claude/skills/workflow/hooks/workflow-advance.sh init "test init no intensity" 2>/dev/null

  local state_file
  state_file="$(ls .correctless/artifacts/workflow-state-*.json 2>/dev/null | head -1)"
  if [ -n "$state_file" ] && [ -f "$state_file" ]; then
    local fi_val
    fi_val="$(jq -r '.feature_intensity // "ABSENT"' "$state_file" 2>/dev/null)"
    assert_eq "R-007: init does NOT set feature_intensity" "ABSENT" "$fi_val"
  else
    echo "  FAIL: R-007: state file not found after init"
    FAIL=$((FAIL + 1))
  fi

  # R-007: status displays feature_intensity when present
  cleanup
  setup_test_project
  git checkout -q -b feature/test-r007-status
  .claude/skills/workflow/hooks/workflow-advance.sh init "test status" 2>/dev/null
  .claude/skills/workflow/hooks/workflow-advance.sh set-intensity "critical" 2>/dev/null || true

  local status_output
  status_output="$(.claude/skills/workflow/hooks/workflow-advance.sh status 2>&1)" || true
  assert_contains "R-007: status displays feature_intensity" "critical" "$status_output"

  cleanup
}

# ============================================
# R-008: allow_intensity_downgrade config behavior
# ============================================

test_r008_downgrade_config() {
  echo ""
  echo "=== R-008: allow_intensity_downgrade config ==="

  local skill_file="$REPO_DIR/skills/cspec/SKILL.md"

  # R-008: SKILL.md mentions allow_intensity_downgrade
  file_contains "$skill_file" "allow_intensity_downgrade" \
    "R-008: cspec mentions allow_intensity_downgrade config field"

  # R-008: when false, user cannot lower below recommended
  file_contains_i "$skill_file" "cannot lower\|cannot.*downgrade\|block.*lower\|prevent.*lower" \
    "R-008: describes blocking lowering when downgrade disabled"

  # R-008: when false, user can still raise
  file_contains_i "$skill_file" "can.*raise\|still raise\|raise.*allowed" \
    "R-008: describes raising still allowed when downgrade disabled"

  # R-008: absent or true means full override in both directions
  file_contains_i "$skill_file" "absent.*true\|true.*both\|both direction\|override.*both" \
    "R-008: absent or true allows override in both directions"
}

# ============================================
# R-009: Detection runs for ALL projects; workflow.intensity is floor
# ============================================

test_r009_detection_all_projects() {
  echo ""
  echo "=== R-009: Detection for all projects, intensity as floor ==="

  local skill_file="$REPO_DIR/skills/cspec/SKILL.md"

  # R-009: runs for ALL projects regardless of workflow.intensity
  file_contains_i "$skill_file" "all project\|regardless.*workflow.intensity\|whether.*workflow.intensity" \
    "R-009: detection runs for all projects"

  # R-009: workflow.intensity acts as a floor
  file_contains_i "$skill_file" "floor\|minimum.*intensity\|cannot.*lower.*configured" \
    "R-009: workflow.intensity acts as a floor"

  # R-009: detection can recommend higher than floor
  file_contains_i "$skill_file" "higher.*floor\|recommend.*higher\|above.*floor" \
    "R-009: detection can recommend higher than floor"

  # R-009: when absent, standard is the baseline
  file_contains_i "$skill_file" "standard.*baseline\|absent.*standard\|default.*standard" \
    "R-009: standard is baseline when workflow.intensity absent"
}

# ============================================
# R-010: Configurable intensity_signals in workflow-config.json
# ============================================

test_r010_configurable_signals() {
  echo ""
  echo "=== R-010: Configurable intensity_signals ==="

  local skill_file="$REPO_DIR/skills/cspec/SKILL.md"

  # R-010: mentions intensity_signals config
  file_contains "$skill_file" "intensity_signals" \
    "R-010: cspec mentions intensity_signals config"

  # R-010: describes path_patterns structure
  file_contains "$skill_file" "path_patterns" \
    "R-010: describes path_patterns in intensity_signals"

  # R-010: describes keywords structure
  file_contains_i "$skill_file" "keywords.*intensity_signals\|intensity_signals.*keywords" \
    "R-010: describes keywords in intensity_signals"

  # R-010: malformed config falls back to built-in defaults
  # NOTE: The actual runtime fallback behavior (parsing malformed JSON, recovering
  # gracefully) is an LLM instruction behavior defined in SKILL.md, not shell logic.
  # We cannot integration-test the fallback in a shell script. Instead, we verify
  # that SKILL.md contains the right instructions: "malformed" near "fallback" or
  # "default", so the LLM knows to fall back.
  file_contains_i "$skill_file" "malformed.*fallback\|malformed.*default\|fallback.*built-in\|fall.*back.*default" \
    "R-010: malformed config falls back to built-in defaults"

  # B-4: malformed config mentions both fallback and default in proximity
  file_contains_i "$skill_file" "malformed.*fallback\|malformed.*default" \
    "R-010: SKILL.md links 'malformed' to 'fallback' or 'default' in proximity"

  # R-010: malformed config logs a warning
  file_contains_i "$skill_file" "warning\|log.*warn" \
    "R-010: malformed config logs a warning"

  # R-010: valid intensity values: standard, high, critical
  file_contains_i "$skill_file" "standard.*high.*critical\|valid.*intensity.*value" \
    "R-010: documents valid intensity values"

  # R-010 [integration]: workflow-config.json schema allows intensity_signals
  # Test that the detection handles optional intensity_signals gracefully
  setup_test_project
  git checkout -q -b feature/test-r010
  mkdir -p .correctless/config

  # Write config WITH intensity_signals
  cat > .correctless/config/workflow-config.json <<'WEOF'
{
  "project": { "name": "test-app", "language": "typescript" },
  "workflow": {
    "min_qa_rounds": 1,
    "intensity_signals": {
      "path_patterns": [{"glob": "hooks/*", "intensity": "high"}],
      "keywords": [{"word": "auth", "intensity": "high"}],
      "keyword_floor": "high",
      "path_floor": "high"
    }
  }
}
WEOF

  # Config should be valid JSON
  if command -v jq >/dev/null 2>&1; then
    local signals
    signals="$(jq -r '.workflow.intensity_signals // empty' .correctless/config/workflow-config.json 2>/dev/null)"
    assert_eq "R-010: intensity_signals is parseable in config" "true" \
      "$([ -n "$signals" ] && echo true || echo false)"
  fi

  cleanup
}

# ============================================
# R-011: Old "Step 7: Recommend Intensity (Full Mode)" replaced
# ============================================

test_r011_old_step7_replaced() {
  echo ""
  echo "=== R-011: Old Step 7 (Full Mode) replaced ==="

  local skill_file="$REPO_DIR/skills/cspec/SKILL.md"

  # R-011: old "(Full Mode)" qualifier on Step 7 is gone
  file_not_contains "$skill_file" "Recommend Intensity (Full Mode)" \
    "R-011: 'Recommend Intensity (Full Mode)' is removed"

  # R-011: old 4-bullet heuristic about trust boundary / security / concurrency / pure is gone
  file_not_contains "$skill_file" "Pure functional change" \
    "R-011: old heuristic 'Pure functional change' is removed"

  # R-011: the new section is not gated by Full Mode
  file_not_contains "$skill_file" "Intensity Detection.*(Full Mode)" \
    "R-011: new section is not gated by (Full Mode)"

  # R-011: Step 7 now references the new Intensity Detection
  file_contains_i "$skill_file" "Step 7.*Intensity Detection\|Intensity Detection.*Step 7\|### Step 7.*Intensity" \
    "R-011: Step 7 now references Intensity Detection"

  # R-011: Step 7 is after Step 6 and before Step 8
  # Check that both Step 6 and Step 8 still exist (ordering)
  file_contains "$skill_file" "Step 6" \
    "R-011: Step 6 still exists (before new Step 7)"
  file_contains "$skill_file" "Step 8" \
    "R-011: Step 8 still exists (after new Step 7)"
}

# ============================================
# R-012: Both templates updated with Metadata section
# ============================================

test_r012_template_metadata() {
  echo ""
  echo "=== R-012: Both templates have Metadata section ==="

  local lite_tpl="$REPO_DIR/templates/spec-lite.md"
  local full_tpl="$REPO_DIR/templates/spec-full.md"

  # R-012: Lite template has Metadata section
  file_contains "$lite_tpl" "## Metadata" \
    "R-012: Lite template has ## Metadata section"

  # R-012: Lite template has Task field
  file_contains_i "$lite_tpl" "Task" \
    "R-012: Lite template has Task field"

  # R-012: Lite template has Intensity field
  file_contains_i "$lite_tpl" "Intensity" \
    "R-012: Lite template has Intensity field"

  # R-012: Lite template has Intensity reason field
  file_contains_i "$lite_tpl" "Intensity reason" \
    "R-012: Lite template has Intensity reason field"

  # R-012: Lite template has Override field
  file_contains_i "$lite_tpl" "Override" \
    "R-012: Lite template has Override field"

  # R-012: Full template retains existing Metadata fields
  file_contains "$full_tpl" "## Metadata" \
    "R-012: Full template has ## Metadata section"

  file_contains_i "$full_tpl" "Created" \
    "R-012: Full template preserves Created field"
  file_contains_i "$full_tpl" "Status" \
    "R-012: Full template preserves Status field"
  file_contains_i "$full_tpl" "Impacts" \
    "R-012: Full template preserves Impacts field"
  file_contains_i "$full_tpl" "Branch" \
    "R-012: Full template preserves Branch field"
  file_contains_i "$full_tpl" "Research" \
    "R-012: Full template preserves Research field"

  # R-012: Full template has NEW Intensity fields (case-sensitive with bold markers
  # to ensure they are formatted as metadata entries, not just prose mentions)
  file_contains "$full_tpl" "\\*\\*Intensity\\*\\*" \
    "R-012: Full template has **Intensity** bold metadata field"
  file_contains "$full_tpl" "\\*\\*Intensity reason\\*\\*" \
    "R-012: Full template has **Intensity reason** bold metadata field"
  file_contains "$full_tpl" "\\*\\*Override\\*\\*" \
    "R-012: Full template has **Override** bold metadata field"
}

# ============================================
# R-013: Highest-wins signal combination logic
# ============================================

test_r013_highest_wins() {
  echo ""
  echo "=== R-013: Highest-wins signal combination ==="

  local skill_file="$REPO_DIR/skills/cspec/SKILL.md"

  # R-013: describes highest-wins logic
  file_contains_i "$skill_file" "highest.*win\|highest.*intensity\|highest.*level.*among\|maximum.*intensity" \
    "R-013: describes highest-wins combination logic"

  # R-013: ordering is standard < high < critical
  file_contains "$skill_file" "standard.*<.*high.*<.*critical\|standard < high < critical" \
    "R-013: documents ordering standard < high < critical"

  # R-013: no signals -> standard (or floor)
  file_contains_i "$skill_file" "no signal.*standard\|no.*trigger.*standard\|default.*standard" \
    "R-013: no signals triggered defaults to standard"

  # R-013: floor from R-009 applies when no signals
  file_contains_i "$skill_file" "floor.*higher\|whichever.*higher\|project.*floor" \
    "R-013: respects project floor when no signals trigger"
}

# ============================================
# QA-002: Phase guard on set-intensity
# ============================================

test_qa002_set_intensity_phase_guard() {
  echo ""
  echo "=== QA-002: set-intensity rejects non-spec phases ==="

  setup_test_project
  git checkout -q -b feature/test-qa002
  .claude/skills/workflow/hooks/workflow-advance.sh init "test qa002" 2>/dev/null

  # Manually set phase to tdd-impl (a non-spec phase) via jq on state file
  local state_file
  state_file="$(ls .correctless/artifacts/workflow-state-*.json 2>/dev/null | head -1)"
  if [ -n "$state_file" ] && [ -f "$state_file" ]; then
    local tmp
    tmp="$(jq '.phase = "tdd-impl"' "$state_file")"
    echo "$tmp" > "$state_file"
  fi

  # Now try set-intensity from tdd-impl — should fail
  local _result
  _result="$(.claude/skills/workflow/hooks/workflow-advance.sh set-intensity "high" 2>&1)" \
    && local exit_code=0 || local exit_code=$?
  assert_eq "QA-002: set-intensity fails from tdd-impl phase (non-zero exit)" "true" \
    "$([ "$exit_code" -ne 0 ] && echo true || echo false)"

  # Also test from "done" phase — should also fail
  cleanup
  setup_test_project
  git checkout -q -b feature/test-qa002-done
  .claude/skills/workflow/hooks/workflow-advance.sh init "test qa002 done" 2>/dev/null

  local state_file_done
  state_file_done="$(ls .correctless/artifacts/workflow-state-*.json 2>/dev/null | head -1)"
  if [ -n "$state_file_done" ] && [ -f "$state_file_done" ]; then
    local tmp_done
    tmp_done="$(jq '.phase = "done"' "$state_file_done")"
    echo "$tmp_done" > "$state_file_done"
  fi

  local _done_result
  _done_result="$(.claude/skills/workflow/hooks/workflow-advance.sh set-intensity "high" 2>&1)" \
    && local done_exit=0 || local done_exit=$?
  assert_eq "QA-002: set-intensity fails from done phase (non-zero exit)" "true" \
    "$([ "$done_exit" -ne 0 ] && echo true || echo false)"

  # Verify set-intensity still works from spec phase
  cleanup
  setup_test_project
  git checkout -q -b feature/test-qa002-ok
  .claude/skills/workflow/hooks/workflow-advance.sh init "test qa002 ok" 2>/dev/null

  local _ok_result
  _ok_result="$(.claude/skills/workflow/hooks/workflow-advance.sh set-intensity "high" 2>&1)" \
    && local ok_exit=0 || local ok_exit=$?
  assert_eq "QA-002: set-intensity succeeds from spec phase (exit 0)" "0" "$ok_exit"

  cleanup
}

# ============================================
# QA-004: Configurable signals override semantics
# ============================================

test_qa004_override_semantics() {
  echo ""
  echo "=== QA-004: SKILL.md instructs override semantics for custom signals ==="

  local skill_file="$REPO_DIR/skills/cspec/SKILL.md"

  # QA-004: SKILL.md should instruct the LLM to override/replace defaults
  # when custom intensity_signals are present
  file_contains_i "$skill_file" "override.*signal\|override.*mapping\|overrides.*signal\|replaces.*default\|override.*default" \
    "QA-004: SKILL.md describes override semantics for custom intensity_signals"
}

# ============================================
# QA-006: Idempotency of set-intensity
# ============================================

test_qa006_set_intensity_idempotent() {
  echo ""
  echo "=== QA-006: set-intensity is idempotent ==="

  setup_test_project
  git checkout -q -b feature/test-qa006
  .claude/skills/workflow/hooks/workflow-advance.sh init "test qa006" 2>/dev/null

  # Call set-intensity "high" twice
  local _result1 _result2
  _result1="$(.claude/skills/workflow/hooks/workflow-advance.sh set-intensity "high" 2>&1)" \
    && local exit1=0 || local exit1=$?
  _result2="$(.claude/skills/workflow/hooks/workflow-advance.sh set-intensity "high" 2>&1)" \
    && local exit2=0 || local exit2=$?

  assert_eq "QA-006: first set-intensity high exits 0" "0" "$exit1"
  assert_eq "QA-006: second set-intensity high exits 0" "0" "$exit2"

  # Verify valid JSON and exactly one feature_intensity field
  local state_file
  state_file="$(ls .correctless/artifacts/workflow-state-*.json 2>/dev/null | head -1)"
  if [ -n "$state_file" ] && [ -f "$state_file" ]; then
    # Valid JSON
    jq empty "$state_file" 2>/dev/null \
      && local json_valid="true" || local json_valid="false"
    assert_eq "QA-006: state file is valid JSON after idempotent calls" "true" "$json_valid"

    # Exactly one feature_intensity field
    local fi_count
    fi_count="$(grep -c '"feature_intensity"' "$state_file")"
    assert_eq "QA-006: exactly one feature_intensity field in state" "1" "$fi_count"

    local fi_val
    fi_val="$(jq -r '.feature_intensity // empty' "$state_file" 2>/dev/null)"
    assert_eq "QA-006: feature_intensity is 'high' after idempotent calls" "high" "$fi_val"
  else
    echo "  FAIL: QA-006: state file not found"
    FAIL=$((FAIL + 1))
  fi

  cleanup
}

# ============================================
# QA-007: Floor logic for unrecognized values like 'low'
# ============================================

test_qa007_low_floor_mapping() {
  echo ""
  echo "=== QA-007: SKILL.md defines floor behavior for unrecognized values ==="

  local skill_file="$REPO_DIR/skills/cspec/SKILL.md"

  # QA-007: SKILL.md should state that values outside the detection vocabulary
  # (like 'low') are treated as 'standard' for floor purposes
  file_contains_i "$skill_file" "not in the detection vocabulary.*standard\|unrecognized.*standard\|low.*treat.*standard" \
    "QA-007: SKILL.md maps unrecognized floor values (like 'low') to standard"
}

# ============================================
# QA-008: Template field ordering
# ============================================

test_qa008_template_field_ordering() {
  echo ""
  echo "=== QA-008: Intensity fields come after Research in spec-full.md ==="

  local full_tpl="$REPO_DIR/templates/spec-full.md"

  # Extract line numbers for Research and Intensity
  local research_line intensity_line
  research_line="$(grep -n 'Research' "$full_tpl" | head -1 | cut -d: -f1)"
  intensity_line="$(grep -n '\\*\\*Intensity\\*\\*' "$full_tpl" | head -1 | cut -d: -f1)"

  if [ -n "$research_line" ] && [ -n "$intensity_line" ]; then
    assert_eq "QA-008: Intensity field (line $intensity_line) comes after Research (line $research_line)" "true" \
      "$([ "$intensity_line" -gt "$research_line" ] && echo true || echo false)"
  else
    echo "  FAIL: QA-008: could not find Research or Intensity line in spec-full.md"
    FAIL=$((FAIL + 1))
  fi
}

# ============================================
# Runner
# ============================================

echo "============================================="
echo "Intensity Detection Test Suite"
echo "============================================="

test_r001_intensity_detection_section
test_r002_signal_mapping
test_r003_humility_qualifier
test_r004_presentation
test_r005_metadata_section
test_r006_feature_intensity_state
test_r007_set_intensity_subcommand
test_r008_downgrade_config
test_r009_detection_all_projects
test_r010_configurable_signals
test_r011_old_step7_replaced
test_r012_template_metadata
test_r013_highest_wins
test_qa002_set_intensity_phase_guard
test_qa004_override_semantics
test_qa006_set_intensity_idempotent
test_qa007_low_floor_mapping
test_qa008_template_field_ordering

echo ""
echo "============================================="
echo "Results: $PASS passed, $FAIL failed"
echo ""

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
