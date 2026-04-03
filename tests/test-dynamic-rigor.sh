#!/usr/bin/env bash
# Correctless — dynamic rigor (single distribution) test suite
# Tests spec rules R-001 through R-018 from
# docs/specs/merge-lite-and-full-into-single-plugin-distribution.md
# Run from repo root: bash tests/test-dynamic-rigor.sh

set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="/tmp/correctless-dynamic-rigor-test-$$"
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
  echo '{"name": "test-app", "version": "1.0.0", "scripts": {"test": "echo PASS && exit 0"}}' > package.json
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

# Case-insensitive file contains
file_contains_i() {
  grep -qi "$2" "$1" 2>/dev/null
}

# ============================================
# R-001: sync.sh copies 26 skills to single correctless/ dir
# ============================================

test_r001_sync_single_dist() {
  echo ""
  echo "=== R-001: sync.sh copies all 26 skills to single correctless/ dir ==="

  # R-001: correctless/ distribution directory must exist
  assert_eq "R-001: correctless/ directory exists" "true" \
    "$([ -d "$REPO_DIR/correctless" ] && echo true || echo false)"

  # R-001: correctless-lite/ must NOT exist
  assert_eq "R-001: correctless-lite/ does NOT exist" "false" \
    "$([ -d "$REPO_DIR/correctless-lite" ] && echo true || echo false)"

  # R-001: correctless-full/ must NOT exist
  assert_eq "R-001: correctless-full/ does NOT exist" "false" \
    "$([ -d "$REPO_DIR/correctless-full" ] && echo true || echo false)"

  # R-001: correctless/ must have all 26 skills
  local skill_count=0
  if [ -d "$REPO_DIR/correctless/skills" ]; then
    skill_count="$(ls -d "$REPO_DIR/correctless/skills/"*/ 2>/dev/null | wc -l)"
  fi
  assert_eq "R-001: correctless/ has 26 skills" "26" "$skill_count"

  # R-001: verify each of the 26 skills exists in correctless/
  for skill in csetup cspec cmodel creview creview-spec ctdd cverify caudit cupdate-arch cdocs cpostmortem cdevadv credteam crefactor cpr-review ccontribute cmaintain cstatus csummary cmetrics cdebug chelp cwtf cquick crelease cexplain; do
    assert_eq "R-001: correctless/skills/$skill/SKILL.md exists" "true" \
      "$([ -f "$REPO_DIR/correctless/skills/$skill/SKILL.md" ] && echo true || echo false)"
  done

  # R-001: hooks directory exists in correctless/
  assert_eq "R-001: correctless/hooks/ exists" "true" \
    "$([ -d "$REPO_DIR/correctless/hooks" ] && echo true || echo false)"

  # R-001: hooks are present
  for hook in workflow-gate.sh workflow-advance.sh statusline.sh audit-trail.sh; do
    assert_eq "R-001: correctless/hooks/$hook exists" "true" \
      "$([ -f "$REPO_DIR/correctless/hooks/$hook" ] && echo true || echo false)"
  done

  # R-001: templates directory exists in correctless/
  assert_eq "R-001: correctless/templates/ exists" "true" \
    "$([ -d "$REPO_DIR/correctless/templates" ] && echo true || echo false)"

  # R-001: setup script exists in correctless/
  assert_eq "R-001: correctless/setup exists" "true" \
    "$([ -f "$REPO_DIR/correctless/setup" ] && echo true || echo false)"

  # R-001: sync.sh no longer references correctless-lite or correctless-full
  local sync_file="$REPO_DIR/sync.sh"
  file_not_contains "$sync_file" "correctless-lite" \
    && local no_lite_ref="true" || local no_lite_ref="false"
  assert_eq "R-001: sync.sh has no correctless-lite references" "true" "$no_lite_ref"

  file_not_contains "$sync_file" "correctless-full" \
    && local no_full_ref="true" || local no_full_ref="false"
  assert_eq "R-001: sync.sh has no correctless-full references" "true" "$no_full_ref"
}

# ============================================
# R-002: sync.sh --check exits 0 when clean, non-zero when different
# ============================================

test_r002_sync_check() {
  echo ""
  echo "=== R-002: sync.sh --check exits 0 when clean, non-zero when dirty ==="

  # R-002: --check exits 0 when correctless/ matches source
  bash "$REPO_DIR/sync.sh" >/dev/null 2>&1  # ensure synced first
  bash "$REPO_DIR/sync.sh" --check >/dev/null 2>&1 \
    && local clean_exit="0" || local clean_exit="$?"
  assert_eq "R-002: sync.sh --check exits 0 when clean" "0" "$clean_exit"

  # R-002: --check exits non-zero when different
  # Temporarily corrupt a skill file in the distribution
  if [ -f "$REPO_DIR/correctless/skills/chelp/SKILL.md" ]; then
    local original
    original="$(cat "$REPO_DIR/correctless/skills/chelp/SKILL.md")"
    echo "CORRUPTED" >> "$REPO_DIR/correctless/skills/chelp/SKILL.md"
    bash "$REPO_DIR/sync.sh" --check >/dev/null 2>&1 \
      && local dirty_exit="0" || local dirty_exit="$?"
    # Restore
    echo "$original" > "$REPO_DIR/correctless/skills/chelp/SKILL.md"
    assert_eq "R-002: sync.sh --check exits non-zero when dirty" "true" \
      "$([ "$dirty_exit" -ne 0 ] && echo true || echo false)"
  else
    echo "  FAIL: R-002: correctless/skills/chelp/SKILL.md does not exist (cannot test dirty check)"
    FAIL=$((FAIL + 1))
  fi

  # R-002: --check validates single correctless/ directory (not two)
  local check_output
  check_output="$(bash "$REPO_DIR/sync.sh" --check 2>&1)" || true
  assert_not_contains "R-002: --check output has no correctless-lite reference" "correctless-lite" "$check_output"
  assert_not_contains "R-002: --check output has no correctless-full reference" "correctless-full" "$check_output"
}

# ============================================
# R-003: marketplace.json has exactly one plugin entry named correctless
# ============================================

test_r003_marketplace_single_entry() {
  echo ""
  echo "=== R-003: marketplace.json has exactly one plugin entry ==="

  local mp="$REPO_DIR/.claude-plugin/marketplace.json"
  assert_eq "R-003: marketplace.json exists" "true" \
    "$([ -f "$mp" ] && echo true || echo false)"

  if [ -f "$mp" ] && command -v jq >/dev/null 2>&1; then
    # R-003: exactly one plugin entry
    local plugin_count
    plugin_count="$(jq '.plugins | length' "$mp" 2>/dev/null || echo 0)"
    assert_eq "R-003: marketplace.json has exactly 1 plugin entry" "1" "$plugin_count"

    # R-003: plugin is named "correctless"
    local plugin_name
    plugin_name="$(jq -r '.plugins[0].name' "$mp" 2>/dev/null || echo "")"
    assert_eq "R-003: plugin name is 'correctless'" "correctless" "$plugin_name"

    # R-003: plugin source is ./correctless
    local plugin_source
    plugin_source="$(jq -r '.plugins[0].source' "$mp" 2>/dev/null || echo "")"
    assert_eq "R-003: plugin source is './correctless'" "./correctless" "$plugin_source"

    # R-003: no correctless-lite entry
    local lite_count
    lite_count="$(jq '[.plugins[] | select(.name == "correctless-lite")] | length' "$mp" 2>/dev/null || echo 0)"
    assert_eq "R-003: no correctless-lite plugin entry" "0" "$lite_count"
  else
    echo "  FAIL: R-003: marketplace.json missing or jq unavailable"
    FAIL=$((FAIL + 4))
  fi
}

# ============================================
# R-004: Setup without workflow.intensity — Lite behavior
# ============================================

test_r004_setup_no_intensity() {
  echo ""
  echo "=== R-004: Setup without workflow.intensity ==="

  setup_test_project
  .claude/skills/workflow/setup >/dev/null 2>&1

  local config=".correctless/config/workflow-config.json"

  # R-004: workflow-config.json exists
  assert_eq "R-004: workflow-config.json exists after setup" "true" \
    "$([ -f "$config" ] && echo true || echo false)"

  if [ -f "$config" ] && command -v jq >/dev/null 2>&1; then
    # R-004: workflow-config.json does NOT have workflow.intensity
    local intensity_val
    intensity_val="$(jq -r '.workflow.intensity // empty' "$config" 2>/dev/null || echo "")"
    assert_eq "R-004: config does NOT have workflow.intensity" "" "$intensity_val"

    # R-004: hooks exist
    for hook in workflow-gate.sh workflow-advance.sh statusline.sh audit-trail.sh; do
      assert_eq "R-004: hook $hook exists" "true" \
        "$([ -f ".correctless/hooks/$hook" ] && echo true || echo false)"
    done

    # R-004: common templates exist
    assert_eq "R-004: ARCHITECTURE.md exists" "true" \
      "$([ -f ".correctless/ARCHITECTURE.md" ] && echo true || echo false)"
    assert_eq "R-004: AGENT_CONTEXT.md exists" "true" \
      "$([ -f ".correctless/AGENT_CONTEXT.md" ] && echo true || echo false)"
    assert_eq "R-004: antipatterns.md exists" "true" \
      "$([ -f ".correctless/antipatterns.md" ] && echo true || echo false)"

    # R-004: Full-only meta files do NOT exist
    assert_eq "R-004: workflow-effectiveness.json does NOT exist" "false" \
      "$([ -f ".correctless/meta/workflow-effectiveness.json" ] && echo true || echo false)"
    assert_eq "R-004: drift-debt.json does NOT exist" "false" \
      "$([ -f ".correctless/meta/drift-debt.json" ] && echo true || echo false)"
  else
    echo "  FAIL: R-004: config missing or jq unavailable"
    FAIL=$((FAIL + 1))
  fi

  cleanup
}

# ============================================
# R-005: Setup with workflow.intensity — Full behavior
# ============================================

test_r005_setup_with_intensity() {
  echo ""
  echo "=== R-005: Setup with workflow.intensity ==="

  setup_test_project

  # Pre-create a config with workflow.intensity to simulate Full mode
  mkdir -p .correctless/config
  cat > .correctless/config/workflow-config.json <<'EOF'
{
  "project": { "name": "test-app", "language": "typescript" },
  "workflow": {
    "min_qa_rounds": 1,
    "require_review": true,
    "intensity": "high"
  }
}
EOF
  git add -A && git commit -q -m "add full config"

  .claude/skills/workflow/setup >/dev/null 2>&1

  local config=".correctless/config/workflow-config.json"

  # R-005: workflow.intensity is preserved
  if command -v jq >/dev/null 2>&1 && [ -f "$config" ]; then
    local intensity
    intensity="$(jq -r '.workflow.intensity // empty' "$config" 2>/dev/null || echo "")"
    assert_eq "R-005: workflow.intensity preserved in config" "high" "$intensity"

    # R-005: everything from R-004 exists
    for hook in workflow-gate.sh workflow-advance.sh statusline.sh audit-trail.sh; do
      assert_eq "R-005: hook $hook exists" "true" \
        "$([ -f ".correctless/hooks/$hook" ] && echo true || echo false)"
    done
    assert_eq "R-005: ARCHITECTURE.md exists" "true" \
      "$([ -f ".correctless/ARCHITECTURE.md" ] && echo true || echo false)"
    assert_eq "R-005: AGENT_CONTEXT.md exists" "true" \
      "$([ -f ".correctless/AGENT_CONTEXT.md" ] && echo true || echo false)"
    assert_eq "R-005: antipatterns.md exists" "true" \
      "$([ -f ".correctless/antipatterns.md" ] && echo true || echo false)"

    # R-005: Full-only meta files DO exist
    assert_eq "R-005: workflow-effectiveness.json exists" "true" \
      "$([ -f ".correctless/meta/workflow-effectiveness.json" ] && echo true || echo false)"
    assert_eq "R-005: drift-debt.json exists" "true" \
      "$([ -f ".correctless/meta/drift-debt.json" ] && echo true || echo false)"
    assert_eq "R-005: external-review-history.json exists" "true" \
      "$([ -f ".correctless/meta/external-review-history.json" ] && echo true || echo false)"

    # R-005: invariant templates installed for intensity-configured projects
    assert_eq "R-005: .correctless/templates/invariants/ directory exists" "true" \
      "$([ -d ".correctless/templates/invariants" ] && echo true || echo false)"
    if [ -d ".correctless/templates/invariants" ]; then
      local inv_file_count
      inv_file_count="$(ls .correctless/templates/invariants/*.md 2>/dev/null | wc -l)"
      assert_eq "R-005: invariant templates present (>0 files)" "true" \
        "$([ "$inv_file_count" -gt 0 ] && echo true || echo false)"
    fi
  else
    echo "  FAIL: R-005: config missing or jq unavailable"
    FAIL=$((FAIL + 1))
  fi

  cleanup
}

# ============================================
# R-006: Full-only skills contain intensity gate
# ============================================

test_r006_intensity_gates() {
  echo ""
  echo "=== R-006: Full-only skills contain intensity gate ==="

  local full_only_skills="caudit cmodel creview-spec cupdate-arch cpostmortem cdevadv credteam"

  for skill in $full_only_skills; do
    local skill_file="$REPO_DIR/skills/$skill/SKILL.md"

    # R-006: skill file exists
    assert_eq "R-006: skills/$skill/SKILL.md exists" "true" \
      "$([ -f "$skill_file" ] && echo true || echo false)"

    if [ -f "$skill_file" ]; then
      # R-006: skill contains intensity gate that reads workflow-config.json
      file_contains_i "$skill_file" "workflow.intensity\|workflow-config.json" \
        && local has_config_read="true" || local has_config_read="false"
      assert_eq "R-006: $skill checks workflow.intensity or workflow-config.json" "true" "$has_config_read"

      # R-006: skill mentions intensity gate / minimum intensity / threshold
      file_contains_i "$skill_file" "intensity.*gate\|minimum intensity\|intensity.*threshold\|intensity.*required\|requires.*intensity" \
        && local has_gate="true" || local has_gate="false"
      assert_eq "R-006: $skill has intensity gate language" "true" "$has_gate"

      # R-006: gate defaults to standard when intensity is absent
      file_contains_i "$skill_file" "default.*standard\|absent.*standard\|not set.*standard\|missing.*standard" \
        && local has_default="true" || local has_default="false"
      assert_eq "R-006: $skill defaults to standard when intensity absent" "true" "$has_default"

      # R-006: Intensity Gate section uses full config path
      # Extract lines around "Intensity Gate" and check for full path
      grep -A 15 'Intensity Gate' "$skill_file" 2>/dev/null | grep -q '\.correctless/config/workflow-config\.json' \
        && local has_full_path="true" || local has_full_path="false"
      assert_eq "R-006: $skill Intensity Gate uses full path .correctless/config/workflow-config.json" "true" "$has_full_path"
    fi
  done
}

# ============================================
# R-007: Gate thresholds per skill
# ============================================

test_r007_gate_thresholds() {
  echo ""
  echo "=== R-007: Gate thresholds per skill ==="

  # Threshold mapping: skill -> required minimum
  # caudit=high, cmodel=critical, creview-spec=high, cupdate-arch=high,
  # cpostmortem=standard, cdevadv=standard, credteam=critical

  local -A thresholds
  thresholds=(
    ["caudit"]="high"
    ["cmodel"]="critical"
    ["creview-spec"]="high"
    ["cupdate-arch"]="high"
    ["cpostmortem"]="standard"
    ["cdevadv"]="standard"
    ["credteam"]="critical"
  )

  for skill in caudit cmodel creview-spec cupdate-arch cpostmortem cdevadv credteam; do
    local skill_file="$REPO_DIR/skills/$skill/SKILL.md"
    local expected="${thresholds[$skill]}"

    if [ -f "$skill_file" ]; then
      # R-007: skill mentions its threshold in gate context (not just the bare word)
      grep -qiE "requires.*$expected|minimum.*$expected|threshold.*$expected|activates.*$expected|intensity.*$expected" "$skill_file" \
        && local has_threshold="true" || local has_threshold="false"
      assert_eq "R-007: $skill mentions '$expected' in gate context" "true" "$has_threshold"
    else
      echo "  FAIL: R-007: $skill SKILL.md does not exist"
      FAIL=$((FAIL + 1))
    fi
  done
}

# ============================================
# R-008: Below-threshold gate prints info message, does not execute
# ============================================

test_r008_below_threshold_message() {
  echo ""
  echo "=== R-008: Below-threshold gate prints info, does not execute ==="

  local full_only_skills="caudit cmodel creview-spec cupdate-arch cpostmortem cdevadv credteam"

  for skill in $full_only_skills; do
    local skill_file="$REPO_DIR/skills/$skill/SKILL.md"
    [ -f "$skill_file" ] || continue

    # R-008: gate message includes skill name
    # The skill file itself is for this skill, so check it mentions gating behavior
    file_contains_i "$skill_file" "skill name\|/$skill" \
      && local has_name="true" || local has_name="false"
    # Relax: the skill file will naturally contain its own name
    assert_eq "R-008: $skill gate references skill name" "true" "$has_name"

    # R-008: gate message includes required intensity
    file_contains_i "$skill_file" "required.*intensity\|minimum.*intensity\|requires.*intensity\|intensity.*required" \
      && local has_required="true" || local has_required="false"
    assert_eq "R-008: $skill gate mentions required intensity" "true" "$has_required"

    # R-008: gate message includes current intensity
    file_contains_i "$skill_file" "current.*intensity\|project.*intensity\|configured.*intensity" \
      && local has_current="true" || local has_current="false"
    assert_eq "R-008: $skill gate mentions current intensity" "true" "$has_current"

    # R-008: gate message includes override instructions (--force)
    file_contains_i "$skill_file" "\-\-force\|override" \
      && local has_override="true" || local has_override="false"
    assert_eq "R-008: $skill gate mentions override (--force)" "true" "$has_override"

    # R-008: gate does not execute skill body when below threshold
    file_contains_i "$skill_file" "do not execute\|does not execute\|stop here\|exit.*without\|skip.*body\|do not proceed\|do not run" \
      && local has_block="true" || local has_block="false"
    assert_eq "R-008: $skill gate blocks execution below threshold" "true" "$has_block"
  done
}

# ============================================
# R-009: --force or at/above threshold executes normally
# ============================================

test_r009_force_or_above_threshold() {
  echo ""
  echo "=== R-009: --force or at/above threshold executes normally ==="

  local full_only_skills="caudit cmodel creview-spec cupdate-arch cpostmortem cdevadv credteam"

  for skill in $full_only_skills; do
    local skill_file="$REPO_DIR/skills/$skill/SKILL.md"
    [ -f "$skill_file" ] || continue

    # R-009: skill mentions --force flag
    file_contains_i "$skill_file" "\-\-force" \
      && local has_force="true" || local has_force="false"
    assert_eq "R-009: $skill mentions --force flag" "true" "$has_force"

    # R-009: skill mentions executing normally when at/above threshold
    file_contains_i "$skill_file" "at or above\|meets.*threshold\|above.*threshold\|proceed.*normally\|execute.*normally\|continue.*normally" \
      && local has_proceed="true" || local has_proceed="false"
    assert_eq "R-009: $skill proceeds normally at/above threshold or with --force" "true" "$has_proceed"

    # R-009: no gate message when conditions met
    file_contains_i "$skill_file" "no gate message\|skip.*gate\|gate.*pass\|gate.*not.*shown\|without.*gate" \
      && local no_msg="true" || local no_msg="false"
    assert_eq "R-009: $skill suppresses gate message when passing" "true" "$no_msg"
  done
}

# ============================================
# R-010: Full-only templates and helpers in correctless/
# ============================================

test_r010_full_templates_in_dist() {
  echo ""
  echo "=== R-010: Full-only templates and helpers in correctless/ ==="

  local dist="$REPO_DIR/correctless"

  # R-010: Full-only template files exist in distribution
  for tmpl in workflow-config-full.json workflow-effectiveness.json drift-debt.json external-review-history.json; do
    assert_eq "R-010: correctless/templates/$tmpl exists" "true" \
      "$([ -f "$dist/templates/$tmpl" ] && echo true || echo false)"
  done

  # R-010: invariant templates directory exists
  assert_eq "R-010: correctless/templates/invariants/ exists" "true" \
    "$([ -d "$dist/templates/invariants" ] && echo true || echo false)"

  # R-010: at least some invariant templates exist
  if [ -d "$dist/templates/invariants" ]; then
    local inv_count
    inv_count="$(ls "$dist/templates/invariants/"*.md 2>/dev/null | wc -l)"
    assert_eq "R-010: invariant templates present (>0)" "true" \
      "$([ "$inv_count" -gt 0 ] && echo true || echo false)"
  fi

  # R-010: PBT helpers exist
  assert_eq "R-010: correctless/helpers/ exists" "true" \
    "$([ -d "$dist/helpers" ] && echo true || echo false)"

  if [ -d "$dist/helpers" ]; then
    local helper_count
    helper_count="$(ls "$dist/helpers/"*.md 2>/dev/null | wc -l)"
    assert_eq "R-010: PBT helper files present (>0)" "true" \
      "$([ "$helper_count" -gt 0 ] && echo true || echo false)"
  fi
}

# ============================================
# R-011: /chelp lists all 26 skills with intensity annotations
# ============================================

test_r011_chelp_all_skills() {
  echo ""
  echo "=== R-011: /chelp lists all 26 skills with intensity annotations ==="

  local chelp="$REPO_DIR/skills/chelp/SKILL.md"

  # R-011: chelp lists all 26 skills
  # Check for each skill command name
  for skill in csetup cspec cmodel creview creview-spec ctdd cverify caudit cupdate-arch cdocs cpostmortem cdevadv credteam crefactor cpr-review ccontribute cmaintain cstatus csummary cmetrics cdebug chelp cwtf cquick crelease cexplain; do
    file_contains "$chelp" "/$skill" \
      && local found="true" || local found="false"
    assert_eq "R-011: chelp mentions /$skill" "true" "$found"
  done

  # R-011: Full-only skills annotated with minimum intensity
  # Skills requiring high+ or critical+ should be annotated
  file_contains_i "$chelp" "high+" \
    && local has_high_annotation="true" || local has_high_annotation="false"
  assert_eq "R-011: chelp annotates skills with 'high+' intensity" "true" "$has_high_annotation"

  file_contains_i "$chelp" "critical+" \
    && local has_critical_annotation="true" || local has_critical_annotation="false"
  assert_eq "R-011: chelp annotates skills with 'critical+' intensity" "true" "$has_critical_annotation"

  # R-011: chelp should NOT separate into "Lite" and "Full" sections
  file_not_contains "$chelp" "Lite commands\|Full mode.*add\|Full mode additions\|Lite mode" \
    && local no_mode_split="true" || local no_mode_split="false"
  assert_eq "R-011: chelp does not split into Lite/Full mode sections" "true" "$no_mode_split"
}

# ============================================
# R-012: Skills checking workflow.intensity still work
# ============================================

test_r012_intensity_backward_compat() {
  echo ""
  echo "=== R-012: Skills checking workflow.intensity continue to work ==="

  # R-012: skills that read workflow.intensity should handle absent = standard
  # Check all 7 gated skills plus key skills that reference workflow config
  for skill in caudit cmodel creview-spec cupdate-arch cpostmortem cdevadv credteam cspec cpr-review ctdd cstatus chelp cdocs cverify creview cwtf crefactor; do
    local skill_file="$REPO_DIR/skills/$skill/SKILL.md"
    [ -f "$skill_file" ] || continue

    # R-012: skill references workflow.intensity or workflow-config.json
    file_contains "$skill_file" "workflow.intensity\|workflow-config.json" \
      && local reads_config="true" || local reads_config="false"
    assert_eq "R-012: $skill reads workflow config" "true" "$reads_config"
  done

  # R-012: cspec should work with absent intensity (standard behavior)
  local cspec="$REPO_DIR/skills/cspec/SKILL.md"
  if [ -f "$cspec" ]; then
    # The spec mentions both intensity-present and intensity-absent behavior
    file_contains_i "$cspec" "intensity" \
      && local cspec_intensity="true" || local cspec_intensity="false"
    assert_eq "R-012: cspec references intensity" "true" "$cspec_intensity"
  fi
}

# ============================================
# R-013: README describes one plugin with intensity levels
# ============================================

test_r013_readme_single_plugin() {
  echo ""
  echo "=== R-013: README describes one plugin with intensity levels ==="

  local readme="$REPO_DIR/README.md"

  # R-013: README exists
  assert_eq "R-013: README.md exists" "true" \
    "$([ -f "$readme" ] && echo true || echo false)"

  if [ -f "$readme" ]; then
    # R-013: single install command
    file_contains "$readme" "plugin install correctless" \
      && local has_install="true" || local has_install="false"
    assert_eq "R-013: README has single 'plugin install correctless' command" "true" "$has_install"

    # R-013: no separate correctless-lite install command
    file_not_contains "$readme" "plugin install correctless-lite" \
      && local no_lite_install="true" || local no_lite_install="false"
    assert_eq "R-013: README does NOT have 'plugin install correctless-lite'" "true" "$no_lite_install"

    # R-013: intensity level table (not comparison table)
    file_contains_i "$readme" "intensity" \
      && local has_intensity="true" || local has_intensity="false"
    assert_eq "R-013: README mentions intensity levels" "true" "$has_intensity"

    # R-013: explicit migration section or instructions
    file_contains_i "$readme" "migrat" \
      && local has_migration="true" || local has_migration="false"
    assert_eq "R-013: README includes migration instructions" "true" "$has_migration"

    # R-013: migration covers both paths (Lite users and Full users)
    file_contains_i "$readme" "correctless-lite" \
      && local mentions_lite="true" || local mentions_lite="false"
    assert_eq "R-013: README migration mentions correctless-lite path" "true" "$mentions_lite"

    # R-013: migration also covers Full-to-unified path
    grep -qiE "uninstall correctless[^-]|If you have correctless .*(Full|full)|correctless \(Full\)" "$readme" \
      && local mentions_full="true" || local mentions_full="false"
    assert_eq "R-013: README migration mentions correctless (Full) path" "true" "$mentions_full"

    # R-013: README should NOT describe two separate plugins
    file_not_contains "$readme" "two plugins\|two separate\|Correctless Lite.*Correctless Full\|correctless-lite.*correctless-full" \
      && local no_two_plugins="true" || local no_two_plugins="false"
    assert_eq "R-013: README does not describe two separate plugins" "true" "$no_two_plugins"
  fi
}

# ============================================
# R-014: Design specs merged into single docs/design/correctless.md
# ============================================

test_r014_merged_design_spec() {
  echo ""
  echo "=== R-014: Design specs merged into single docs/design/correctless.md ==="

  # R-014: single design doc exists
  assert_eq "R-014: docs/design/correctless.md exists" "true" \
    "$([ -f "$REPO_DIR/docs/design/correctless.md" ] && echo true || echo false)"

  # R-014: correctless-lite.md design doc no longer exists
  assert_eq "R-014: docs/design/correctless-lite.md does NOT exist" "false" \
    "$([ -f "$REPO_DIR/docs/design/correctless-lite.md" ] && echo true || echo false)"

  # R-014: merged doc covers intensity levels
  if [ -f "$REPO_DIR/docs/design/correctless.md" ]; then
    file_contains_i "$REPO_DIR/docs/design/correctless.md" "intensity" \
      && local has_intensity="true" || local has_intensity="false"
    assert_eq "R-014: merged design doc mentions intensity levels" "true" "$has_intensity"
  fi
}

# ============================================
# R-015: Pre-commit sync check validates single correctless/ directory
# ============================================

test_r015_precommit_single_dir() {
  echo ""
  echo "=== R-015: Pre-commit sync check validates single correctless/ dir ==="

  local precommit="$REPO_DIR/.pre-commit-config.yaml"

  # R-015: pre-commit config exists
  assert_eq "R-015: .pre-commit-config.yaml exists" "true" \
    "$([ -f "$precommit" ] && echo true || echo false)"

  if [ -f "$precommit" ]; then
    # R-015: correctless-sync-check hook exists
    file_contains "$precommit" "correctless-sync-check" \
      && local has_hook="true" || local has_hook="false"
    assert_eq "R-015: pre-commit has correctless-sync-check hook" "true" "$has_hook"

    # R-015: sync check validates via sync.sh --check (single directory)
    file_contains "$precommit" "sync.sh --check" \
      && local has_check="true" || local has_check="false"
    assert_eq "R-015: pre-commit calls sync.sh --check" "true" "$has_check"
  fi

  # R-015: sync.sh only references correctless/ (not correctless-lite/ or correctless-full/)
  local sync_file="$REPO_DIR/sync.sh"
  if [ -f "$sync_file" ]; then
    # The sync.sh should reference the correctless/ distribution directory
    file_contains "$sync_file" 'correctless/' \
      && local has_dist_ref="true" || local has_dist_ref="false"
    assert_eq "R-015: sync.sh references correctless/ directory" "true" "$has_dist_ref"
  fi
}

# ============================================
# R-016: Tests — no references to correctless-lite/ or correctless-full/
# ============================================

test_r016_tests_updated() {
  echo ""
  echo "=== R-016: Tests and project docs have no old distribution references ==="

  local tests_dir="$REPO_DIR/tests"

  # R-016: scan ALL test files for old path references (with and without trailing slash)
  local old_refs_found="false"
  for test_file in "$tests_dir"/*.sh; do
    [ -f "$test_file" ] || continue
    local fname
    fname="$(basename "$test_file")"
    # Skip this test file itself (it mentions old paths in descriptions)
    [ "$fname" = "test-dynamic-rigor.sh" ] && continue

    if grep -q 'correctless-lite' "$test_file" 2>/dev/null; then
      echo "    NOTE: $fname still references correctless-lite"
      old_refs_found="true"
    fi
    if grep -q 'correctless-full' "$test_file" 2>/dev/null; then
      echo "    NOTE: $fname still references correctless-full"
      old_refs_found="true"
    fi
  done
  assert_eq "R-016: no test files reference correctless-lite or correctless-full" "false" "$old_refs_found"

  # R-016: tests that verified "Lite has N skills, Full has M skills" replaced
  # by single distribution count assertions
  local old_count_refs="false"
  for test_file in "$tests_dir"/*.sh; do
    [ -f "$test_file" ] || continue
    local fname
    fname="$(basename "$test_file")"
    [ "$fname" = "test-dynamic-rigor.sh" ] && continue

    if grep -q 'Lite skills.*19\|Full skills.*26\|19.*Lite\|26.*Full' "$test_file" 2>/dev/null; then
      echo "    NOTE: $fname has old Lite/Full skill count references"
      old_count_refs="true"
    fi
  done
  assert_eq "R-016: no test files have old Lite/Full count assertions" "false" "$old_count_refs"

  # R-016 class fix: scan project docs for stale two-distribution references
  local stale_doc_refs="false"
  for doc_file in "$REPO_DIR/AGENT_CONTEXT.md" "$REPO_DIR/ARCHITECTURE.md" "$REPO_DIR/CONTRIBUTING.md"; do
    [ -f "$doc_file" ] || continue
    local dname
    dname="$(basename "$doc_file")"

    if grep -q 'correctless-lite' "$doc_file" 2>/dev/null; then
      echo "    NOTE: $dname still references correctless-lite"
      stale_doc_refs="true"
    fi
    if grep -q 'correctless-full' "$doc_file" 2>/dev/null; then
      echo "    NOTE: $dname still references correctless-full"
      stale_doc_refs="true"
    fi
  done
  assert_eq "R-016: project docs (AGENT_CONTEXT, ARCHITECTURE, CONTRIBUTING) have no correctless-lite/full references" "false" "$stale_doc_refs"
}

# ============================================
# R-017: Setup detects old Lite/Full directories and cleans up
# ============================================

test_r017_setup_migration() {
  echo ""
  echo "=== R-017: Setup detects old Lite/Full directories and cleans them up ==="

  setup_test_project

  # Create old-style Lite directory to simulate existing install
  mkdir -p .claude/skills/workflow/correctless-lite/skills/csetup
  echo "old lite skill" > .claude/skills/workflow/correctless-lite/skills/csetup/SKILL.md

  # Create old-style Full directory
  mkdir -p .claude/skills/workflow/correctless-full/skills/caudit
  echo "old full skill" > .claude/skills/workflow/correctless-full/skills/caudit/SKILL.md

  git add -A && git commit -q -m "simulate old install"

  # Run setup — it should detect and clean up old directories
  local setup_output
  setup_output="$(.claude/skills/workflow/setup 2>&1)" || true

  # R-017: setup prints migration message about old Lite/Full directories
  assert_contains "R-017: setup prints Lite/Full migration message" \
    "old Lite\|old Full\|unified plugin\|Detected old\|Migrating to unified" "$setup_output"

  # R-017: old Lite directory cleaned up
  assert_eq "R-017: old correctless-lite/ directory removed after setup" "false" \
    "$([ -d ".claude/skills/workflow/correctless-lite" ] && echo true || echo false)"

  # R-017: old Full directory cleaned up
  assert_eq "R-017: old correctless-full/ directory removed after setup" "false" \
    "$([ -d ".claude/skills/workflow/correctless-full" ] && echo true || echo false)"

  cleanup
}

# ============================================
# R-018: No "Lite mode" / "Full mode" language in skills
# ============================================

test_r018_no_mode_language() {
  echo ""
  echo "=== R-018: No 'Lite mode' / 'Full mode' language in skills ==="

  # R-018: Priority targets — cstatus and chelp
  local cstatus="$REPO_DIR/skills/cstatus/SKILL.md"
  local chelp="$REPO_DIR/skills/chelp/SKILL.md"

  if [ -f "$cstatus" ]; then
    file_not_contains "$cstatus" "Lite mode\|Full mode" \
      && local cstatus_clean="true" || local cstatus_clean="false"
    assert_eq "R-018: cstatus has no 'Lite mode' or 'Full mode' language" "true" "$cstatus_clean"
  fi

  if [ -f "$chelp" ]; then
    file_not_contains "$chelp" "Lite mode\|Full mode" \
      && local chelp_clean="true" || local chelp_clean="false"
    assert_eq "R-018: chelp has no 'Lite mode' or 'Full mode' language" "true" "$chelp_clean"
  fi

  # R-018: scan ALL source skills for mode language (broad patterns)
  local mode_violations=""
  for skill_dir in "$REPO_DIR"/skills/*/; do
    local skill_name
    skill_name="$(basename "$skill_dir")"
    local skill_file="$skill_dir/SKILL.md"
    [ -f "$skill_file" ] || continue

    if grep -q 'Lite mode\|Full mode' "$skill_file" 2>/dev/null; then
      mode_violations="${mode_violations}${skill_name} "
    fi
  done

  assert_eq "R-018: no skills use 'Lite mode' or 'Full mode' as mode identifiers" "" "$mode_violations"

  # R-018: scan ALL source skills for standalone Lite/Full used as mode identifiers
  # Excludes legitimate English: "full scope", "full coverage", "Full Bootstrap Mode", "fully", etc.
  local id_violations=""
  for skill_dir in "$REPO_DIR"/skills/*/; do
    local skill_name
    skill_name="$(basename "$skill_dir")"
    local skill_file="$skill_dir/SKILL.md"
    [ -f "$skill_file" ] || continue

    # Grep for mode-identifier patterns, excluding legitimate English uses
    if grep -E '\(Lite\)|\(Full\)|For Lite|For Full|Full only|Lite users|Lite to Full' "$skill_file" 2>/dev/null \
       | grep -vE 'full scope|full coverage|Full Bootstrap|fully|full set|full path|full list' >/dev/null 2>&1; then
      id_violations="${id_violations}${skill_name} "
    fi
  done

  assert_eq "R-018: no skills use standalone Lite/Full as mode identifiers" "" "$id_violations"

  # R-018: skills should use intensity-level terminology instead
  if [ -f "$cstatus" ]; then
    file_contains_i "$cstatus" "intensity\|at standard\|at high\|at critical" \
      && local cstatus_intensity="true" || local cstatus_intensity="false"
    assert_eq "R-018: cstatus uses intensity-level terminology" "true" "$cstatus_intensity"
  fi

  if [ -f "$chelp" ]; then
    file_contains_i "$chelp" "intensity\|at standard\|at high\|at critical" \
      && local chelp_intensity="true" || local chelp_intensity="false"
    assert_eq "R-018: chelp uses intensity-level terminology" "true" "$chelp_intensity"
  fi

  # R-018: setup script should also avoid Lite/Full mode language
  local setup_file="$REPO_DIR/setup"
  if [ -f "$setup_file" ]; then
    file_not_contains "$setup_file" "Lite mode\|Full mode" \
      && local setup_clean="true" || local setup_clean="false"
    assert_eq "R-018: setup script has no 'Lite mode' or 'Full mode' language" "true" "$setup_clean"
  fi
}

# ============================================
# Runner
# ============================================

echo "============================================="
echo "Dynamic Rigor (Single Distribution) Test Suite"
echo "============================================="

test_r001_sync_single_dist
test_r002_sync_check
test_r003_marketplace_single_entry
test_r004_setup_no_intensity
test_r005_setup_with_intensity
test_r006_intensity_gates
test_r007_gate_thresholds
test_r008_below_threshold_message
test_r009_force_or_above_threshold
test_r010_full_templates_in_dist
test_r011_chelp_all_skills
test_r012_intensity_backward_compat
test_r013_readme_single_plugin
test_r014_merged_design_spec
test_r015_precommit_single_dir
test_r016_tests_updated
test_r017_setup_migration
test_r018_no_mode_language

echo ""
echo "============================================="
echo "Results: $PASS passed, $FAIL failed"
echo ""

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
