#!/usr/bin/env bash
# Correctless — Token Tracking Skill Field Tests
# Tests R-001 through R-008 from the token-tracking-skill-field spec.
# Run from repo root: bash tests/test-token-tracking-skill-field.sh

set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$REPO_DIR/hooks/token-tracking.sh"
LIB_SH="$REPO_DIR/scripts/lib.sh"
ADVANCE_SH="$REPO_DIR/hooks/workflow-advance.sh"
PASS=0
FAIL=0

# ============================================================================
# Helpers
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

assert_not_match() {
  local desc="$1" pattern="$2" actual="$3"
  if printf '%s\n' "$actual" | grep -qE -- "$pattern"; then
    echo "  FAIL: $desc (expected output NOT to match '$pattern', got '$actual')"
    FAIL=$((FAIL + 1))
  else
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  fi
}

# ============================================================================
# Test environment setup
# ============================================================================

TEST_DIR="/tmp/correctless-test-skill-field-$$"
BRANCH_NAME="feature/test-skill-field"

setup_test_env() {
  rm -rf "$TEST_DIR"
  mkdir -p "$TEST_DIR"
  cd "$TEST_DIR" || exit 1

  # Initialize a git repo with a feature branch
  git init -q
  git branch -M main
  echo "init" > README.md
  git add -A && git commit -q -m "init"
  git checkout -q -b "$BRANCH_NAME"

  # Copy lib.sh so the hook can source it
  mkdir -p .correctless/scripts
  cp "$LIB_SH" .correctless/scripts/lib.sh

  # Copy the hook under test
  mkdir -p hooks
  cp "$HOOK" hooks/token-tracking.sh
  chmod +x hooks/token-tracking.sh

  # Create artifacts directory
  mkdir -p .correctless/artifacts

  # Compute the branch slug using lib.sh
  source .correctless/scripts/lib.sh
  SLUG="$(branch_slug)"
  TOKEN_LOG=".correctless/artifacts/token-log-${SLUG}.jsonl"
  STATE_FILE=".correctless/artifacts/workflow-state-${SLUG}.json"
}

cleanup() {
  rm -rf "$TEST_DIR"
}
trap cleanup EXIT

# Helper: build Agent tool stdin JSON
build_agent_stdin() {
  local input_tokens="${1:-100}"
  local output_tokens="${2:-50}"
  local total_cost="${3:-0.005}"
  local duration="${4:-1200}"
  local description="${5:-run tests}"
  local subagent_type="${6:-qa-expert}"

  cat <<EOF
{
  "tool_name": "Agent",
  "tool_input": {
    "description": "$description",
    "subagent_type": "$subagent_type"
  },
  "tool_response": {
    "usage": {
      "input_tokens": $input_tokens,
      "output_tokens": $output_tokens
    },
    "total_cost_usd": $total_cost,
    "duration_ms": $duration,
    "result": "subagent output"
  }
}
EOF
}

# Helper: run the hook with stdin, capture exit code
run_hook() {
  local stdin_data="$1"
  local exit_code
  echo "$stdin_data" | bash hooks/token-tracking.sh >/dev/null 2>/dev/null && exit_code=0 || exit_code=$?
  echo "$exit_code"
}

# Helper: run the hook and return the first JSONL entry's skill field
get_skill_for_phase() {
  local phase="$1"
  rm -f "$TEST_DIR/$TOKEN_LOG"

  if [ "$phase" = "__ABSENT__" ]; then
    # No state file at all
    rm -f "$TEST_DIR/$STATE_FILE"
  elif [ "$phase" = "__EMPTY__" ]; then
    # State file with empty phase
    echo '{"task": "test-feature"}' > "$TEST_DIR/$STATE_FILE"
  else
    cat > "$TEST_DIR/$STATE_FILE" <<STEOF
{"phase": "$phase", "task": "test-feature"}
STEOF
  fi

  local agent_stdin
  agent_stdin="$(build_agent_stdin)"
  run_hook "$agent_stdin" >/dev/null

  if [ -f "$TEST_DIR/$TOKEN_LOG" ]; then
    head -1 "$TEST_DIR/$TOKEN_LOG" | jq -r '.skill // "__MISSING__"' 2>/dev/null || echo "__MISSING__"
  else
    echo "__NO_LOG__"
  fi
}

echo "Correctless Token Tracking Skill Field Tests"
echo "============================================="

# ============================================================================
# R-001 [unit]: skill field derived from phase via case statement
# ============================================================================

test_r001_skill_mapping() {
  echo ""
  echo "=== R-001: skill field derived from phase via case statement ==="

  setup_test_env

  # -----------------------------------------------
  # R-001a: spec -> cspec
  # -----------------------------------------------
  local skill
  skill="$(get_skill_for_phase "spec")"
  assert_eq "R-001a: phase=spec -> skill=cspec" "cspec" "$skill"

  # -----------------------------------------------
  # R-001b: model -> cmodel
  # -----------------------------------------------
  skill="$(get_skill_for_phase "model")"
  assert_eq "R-001b: phase=model -> skill=cmodel" "cmodel" "$skill"

  # -----------------------------------------------
  # R-001c: review -> creview
  # -----------------------------------------------
  skill="$(get_skill_for_phase "review")"
  assert_eq "R-001c: phase=review -> skill=creview" "creview" "$skill"

  # -----------------------------------------------
  # R-001d: review-spec -> creview
  # -----------------------------------------------
  skill="$(get_skill_for_phase "review-spec")"
  assert_eq "R-001d: phase=review-spec -> skill=creview" "creview" "$skill"

  # -----------------------------------------------
  # R-001e: tdd-tests -> ctdd
  # -----------------------------------------------
  skill="$(get_skill_for_phase "tdd-tests")"
  assert_eq "R-001e: phase=tdd-tests -> skill=ctdd" "ctdd" "$skill"

  # -----------------------------------------------
  # R-001f: tdd-impl -> ctdd
  # -----------------------------------------------
  skill="$(get_skill_for_phase "tdd-impl")"
  assert_eq "R-001f: phase=tdd-impl -> skill=ctdd" "ctdd" "$skill"

  # -----------------------------------------------
  # R-001g: tdd-qa -> ctdd
  # -----------------------------------------------
  skill="$(get_skill_for_phase "tdd-qa")"
  assert_eq "R-001g: phase=tdd-qa -> skill=ctdd" "ctdd" "$skill"

  # -----------------------------------------------
  # R-001h: tdd-verify -> ctdd
  # -----------------------------------------------
  skill="$(get_skill_for_phase "tdd-verify")"
  assert_eq "R-001h: phase=tdd-verify -> skill=ctdd" "ctdd" "$skill"

  # -----------------------------------------------
  # R-001i: done -> cverify
  # -----------------------------------------------
  skill="$(get_skill_for_phase "done")"
  assert_eq "R-001i: phase=done -> skill=cverify" "cverify" "$skill"

  # -----------------------------------------------
  # R-001j: verified -> cverify
  # -----------------------------------------------
  skill="$(get_skill_for_phase "verified")"
  assert_eq "R-001j: phase=verified -> skill=cverify" "cverify" "$skill"

  # -----------------------------------------------
  # R-001k: documented -> cdocs
  # -----------------------------------------------
  skill="$(get_skill_for_phase "documented")"
  assert_eq "R-001k: phase=documented -> skill=cdocs" "cdocs" "$skill"

  # -----------------------------------------------
  # R-001l: audit -> caudit
  # -----------------------------------------------
  skill="$(get_skill_for_phase "audit")"
  assert_eq "R-001l: phase=audit -> skill=caudit" "caudit" "$skill"

  # -----------------------------------------------
  # R-001m: static check — mapping is a bash case statement, not jq
  # -----------------------------------------------
  local hook_src
  hook_src="$(cat "$HOOK")"

  # Must contain a case statement (non-comment lines)
  local has_case="no"
  if grep -vE '^[[:space:]]*#' <<<"$hook_src" | grep -qE '^[[:space:]]*case\b'; then
    has_case="yes"
  fi
  assert_eq "R-001m: mapping uses bash case statement" "yes" "$has_case"

  # The case statement body must reference at least spec, review, tdd
  local case_body
  case_body="$(grep -vE '^[[:space:]]*#' <<<"$hook_src" || true)"
  local has_spec_in_case="no"
  if grep -qF 'spec)' <<<"$case_body" || grep -qF 'spec|' <<<"$case_body" || grep -qF '"spec"' <<<"$case_body"; then
    has_spec_in_case="yes"
  fi
  assert_eq "R-001n: case statement maps spec" "yes" "$has_spec_in_case"
}

# ============================================================================
# R-002 [unit]: skill passed to jq via --arg, not interpolated
# ============================================================================

test_r002_skill_via_arg() {
  echo ""
  echo "=== R-002: skill passed to jq via --arg, not interpolated ==="

  local hook_src
  hook_src="$(cat "$HOOK")"
  local non_comment
  non_comment="$(grep -vE '^[[:space:]]*#' <<<"$hook_src")"

  # -----------------------------------------------
  # R-002a: --arg for skill must appear in the jq command
  # -----------------------------------------------
  local has_arg_skill="no"
  if grep -qE -- '--arg[[:space:]]+skill' <<<"$non_comment"; then
    has_arg_skill="yes"
  fi
  assert_eq "R-002a: jq uses --arg for skill" "yes" "$has_arg_skill"

  # -----------------------------------------------
  # R-002b: skill field must use jq variable reference ($skill), not shell interpolation
  # The jq template should reference $skill (inside the jq string), not a shell variable
  # -----------------------------------------------
  # Look for the jq JSON template block — it should have skill: $skill (jq var)
  # and NOT have skill: "' ... $SKILL ... '" (shell interpolation)
  local has_jq_var_ref="no"
  if grep -qF '$skill' <<<"$non_comment"; then
    has_jq_var_ref="yes"
  fi
  assert_eq "R-002b: jq template references \$skill (jq variable)" "yes" "$has_jq_var_ref"

  # -----------------------------------------------
  # R-002c: no direct shell variable interpolation of skill into jq template
  # If there is a SKILL variable, it must not appear inside the jq single-quoted block
  # We check that no line has both a jq JSON key "skill" and a shell $SKILL expansion
  # -----------------------------------------------
  # Check there is no "skill": "$SKILL" pattern (shell interpolation into JSON)
  local has_interpolated="no"
  if grep -qE '"skill"[[:space:]]*:[[:space:]]*"\$' <<<"$non_comment"; then
    has_interpolated="yes"
  fi
  assert_eq "R-002c: no shell interpolation of skill into JSON template" "no" "$has_interpolated"
}

# ============================================================================
# R-003 [unit]: mapping defined in hook file, not in lib.sh
# ============================================================================

test_r003_mapping_in_hook() {
  echo ""
  echo "=== R-003: phase-to-skill mapping defined in hook, not lib.sh ==="

  # -----------------------------------------------
  # R-003a: lib.sh must NOT contain a phase-to-skill mapping function
  # -----------------------------------------------
  local lib_src
  lib_src="$(cat "$LIB_SH")"

  local lib_has_skill_map="no"
  # Check for function names like phase_to_skill, map_phase_to_skill, get_skill, etc.
  if grep -qE '(phase_to_skill|map_phase|_phase_skill|get_skill_from_phase)' <<<"$lib_src"; then
    lib_has_skill_map="yes"
  fi
  assert_eq "R-003a: lib.sh has no phase-to-skill mapping function" "no" "$lib_has_skill_map"

  # -----------------------------------------------
  # R-003b: the hook itself must contain the mapping
  # Check for a case statement that maps phases to skills
  # -----------------------------------------------
  local hook_src
  hook_src="$(cat "$HOOK")"
  local non_comment
  non_comment="$(grep -vE '^[[:space:]]*#' <<<"$hook_src")"

  local hook_has_mapping="no"
  # The hook must have a case statement and reference skill-related terms
  if grep -qE '^[[:space:]]*case\b' <<<"$non_comment"; then
    # And within that code, we should see skill assignments (cspec, ctdd, creview, etc.)
    if grep -qF 'cspec' <<<"$non_comment" || grep -qF 'ctdd' <<<"$non_comment" || grep -qF 'creview' <<<"$non_comment"; then
      hook_has_mapping="yes"
    fi
  fi
  assert_eq "R-003b: hook contains phase-to-skill case mapping" "yes" "$hook_has_mapping"

  # -----------------------------------------------
  # R-003c: no external file is sourced specifically for the mapping
  # The hook should not source any file beyond lib.sh
  # -----------------------------------------------
  local extra_sources
  # Match 'source FILE' or '. FILE' (dot-space for POSIX sourcing), exclude lib.sh
  extra_sources="$(grep -vE '^[[:space:]]*#' <<<"$hook_src" | grep -E '(^|[[:space:]])(source[[:space:]]|\.[[:space:]])' | grep -vE 'lib\.sh' || true)"
  local has_extra_source="no"
  if [ -n "$extra_sources" ]; then
    has_extra_source="yes"
  fi
  assert_eq "R-003c: hook sources no external file beyond lib.sh" "no" "$has_extra_source"
}

# ============================================================================
# R-004 [unit]: empty/absent/none/unrecognized phase -> skill is "unknown"
# ============================================================================

test_r004_fallback_to_unknown() {
  echo ""
  echo "=== R-004: empty/absent/none/unrecognized phase -> skill=unknown ==="

  setup_test_env

  # -----------------------------------------------
  # R-004a: phase = "none" -> skill = "unknown"
  # -----------------------------------------------
  local skill
  skill="$(get_skill_for_phase "none")"
  assert_eq "R-004a: phase=none -> skill=unknown" "unknown" "$skill"

  # -----------------------------------------------
  # R-004b: absent state file -> skill = "unknown"
  # -----------------------------------------------
  skill="$(get_skill_for_phase "__ABSENT__")"
  assert_eq "R-004b: absent state file -> skill=unknown" "unknown" "$skill"

  # -----------------------------------------------
  # R-004c: state file with no phase field -> skill = "unknown"
  # -----------------------------------------------
  skill="$(get_skill_for_phase "__EMPTY__")"
  assert_eq "R-004c: missing phase field -> skill=unknown" "unknown" "$skill"

  # -----------------------------------------------
  # R-004d: unrecognized phase value -> skill = "unknown"
  # -----------------------------------------------
  skill="$(get_skill_for_phase "banana")"
  assert_eq "R-004d: phase=banana -> skill=unknown" "unknown" "$skill"

  # -----------------------------------------------
  # R-004e: all fallback cases still produce a log entry (not skipped)
  # -----------------------------------------------
  # Test that "none" produces a log entry
  rm -f "$TEST_DIR/$TOKEN_LOG"
  cat > "$TEST_DIR/$STATE_FILE" <<'EOF'
{"phase": "none", "task": "test"}
EOF
  local agent_stdin
  agent_stdin="$(build_agent_stdin)"
  run_hook "$agent_stdin" >/dev/null

  local log_exists="no"
  if [ -f "$TEST_DIR/$TOKEN_LOG" ]; then
    local line_count
    line_count="$(wc -l < "$TEST_DIR/$TOKEN_LOG" | tr -d ' ')"
    if [ "$line_count" -ge 1 ]; then
      log_exists="yes"
    fi
  fi
  assert_eq "R-004e: phase=none still produces a log entry" "yes" "$log_exists"

  # -----------------------------------------------
  # R-004f: unrecognized phase still produces a log entry
  # -----------------------------------------------
  rm -f "$TEST_DIR/$TOKEN_LOG"
  cat > "$TEST_DIR/$STATE_FILE" <<'EOF'
{"phase": "totally-invented", "task": "test"}
EOF
  run_hook "$agent_stdin" >/dev/null

  log_exists="no"
  if [ -f "$TEST_DIR/$TOKEN_LOG" ]; then
    local line_count2
    line_count2="$(wc -l < "$TEST_DIR/$TOKEN_LOG" | tr -d ' ')"
    if [ "$line_count2" -ge 1 ]; then
      log_exists="yes"
    fi
  fi
  assert_eq "R-004f: unrecognized phase still produces a log entry" "yes" "$log_exists"
}

# ============================================================================
# R-005 [unit]: existing 11 fields unchanged
# ============================================================================

test_r005_existing_fields_preserved() {
  echo ""
  echo "=== R-005: existing 11 fields unchanged, skill added alongside ==="

  setup_test_env

  # Create state file with known values
  cat > "$TEST_DIR/$STATE_FILE" <<'EOF'
{"phase": "tdd-impl", "task": "my-feature"}
EOF

  local agent_stdin
  agent_stdin="$(build_agent_stdin 300 150 0.009 2500 "write tests" "test-writer")"
  run_hook "$agent_stdin" >/dev/null

  if [ ! -f "$TEST_DIR/$TOKEN_LOG" ]; then
    echo "  FAIL: R-005: no log file created (cannot verify fields)"
    FAIL=$((FAIL + 12))
    return
  fi

  local log_entry
  log_entry="$(head -1 "$TEST_DIR/$TOKEN_LOG")"

  # -----------------------------------------------
  # R-005a-k: all 11 original fields present
  # -----------------------------------------------
  local required_fields=(
    "timestamp"
    "branch"
    "phase"
    "feature"
    "agent_description"
    "agent_type"
    "input_tokens"
    "output_tokens"
    "total_tokens"
    "total_cost_usd"
    "duration_ms"
  )

  for field in "${required_fields[@]}"; do
    local val
    val="$(echo "$log_entry" | jq -r ".$field // \"__MISSING__\"" 2>/dev/null || echo "__MISSING__")"
    if [ "$val" != "__MISSING__" ] && [ "$val" != "null" ] && [ -n "$val" ]; then
      echo "  PASS: R-005: field '$field' present"
      PASS=$((PASS + 1))
    else
      echo "  FAIL: R-005: field '$field' missing from log entry"
      FAIL=$((FAIL + 1))
    fi
  done

  # -----------------------------------------------
  # R-005l: the new skill field is also present (12th field)
  # -----------------------------------------------
  local skill_val
  skill_val="$(echo "$log_entry" | jq -r '.skill // "__MISSING__"' 2>/dev/null || echo "__MISSING__")"
  if [ "$skill_val" != "__MISSING__" ] && [ "$skill_val" != "null" ] && [ -n "$skill_val" ]; then
    echo "  PASS: R-005l: skill field present alongside original 11"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: R-005l: skill field missing (should be added alongside original 11)"
    FAIL=$((FAIL + 1))
  fi
}

# ============================================================================
# R-006 [unit]: phase preserved alongside skill (both coexist)
# ============================================================================

test_r006_phase_and_skill_coexist() {
  echo ""
  echo "=== R-006: phase preserved alongside skill (both coexist) ==="

  setup_test_env

  cat > "$TEST_DIR/$STATE_FILE" <<'EOF'
{"phase": "tdd-impl", "task": "test-feature"}
EOF

  local agent_stdin
  agent_stdin="$(build_agent_stdin)"
  run_hook "$agent_stdin" >/dev/null

  if [ ! -f "$TEST_DIR/$TOKEN_LOG" ]; then
    echo "  FAIL: R-006: no log file created"
    FAIL=$((FAIL + 3))
    return
  fi

  local log_entry
  log_entry="$(head -1 "$TEST_DIR/$TOKEN_LOG")"

  # -----------------------------------------------
  # R-006a: phase field exists
  # -----------------------------------------------
  local phase_val
  phase_val="$(echo "$log_entry" | jq -r '.phase // "__MISSING__"' 2>/dev/null || echo "__MISSING__")"
  assert_eq "R-006a: phase field present" "tdd-impl" "$phase_val"

  # -----------------------------------------------
  # R-006b: skill field exists
  # -----------------------------------------------
  local skill_val
  skill_val="$(echo "$log_entry" | jq -r '.skill // "__MISSING__"' 2>/dev/null || echo "__MISSING__")"
  # For tdd-impl, skill should be ctdd
  assert_eq "R-006b: skill field present with correct value" "ctdd" "$skill_val"

  # -----------------------------------------------
  # R-006c: phase derivation unchanged (.phase // "none" from state file)
  # Verify phase comes from state file, not from the skill mapping
  # -----------------------------------------------
  # Test with a phase that maps to a different skill name
  rm -f "$TEST_DIR/$TOKEN_LOG"
  cat > "$TEST_DIR/$STATE_FILE" <<'EOF'
{"phase": "review-spec", "task": "test-feature"}
EOF
  run_hook "$agent_stdin" >/dev/null

  log_entry="$(head -1 "$TEST_DIR/$TOKEN_LOG" 2>/dev/null || echo "")"
  phase_val="$(echo "$log_entry" | jq -r '.phase // "__MISSING__"' 2>/dev/null || echo "__MISSING__")"
  skill_val="$(echo "$log_entry" | jq -r '.skill // "__MISSING__"' 2>/dev/null || echo "__MISSING__")"

  # Phase should be "review-spec" (raw from state), skill should be "creview" (mapped)
  assert_eq "R-006c: phase is raw value from state file" "review-spec" "$phase_val"
  assert_eq "R-006d: skill is mapped value (different from phase)" "creview" "$skill_val"
}

# ============================================================================
# R-007 [static]: PAT-005 conventions maintained
# ============================================================================

test_r007_pat005_conventions() {
  echo ""
  echo "=== R-007: PAT-005 PostToolUse conventions maintained ==="

  local hook_src
  hook_src="$(cat "$HOOK")"

  # -----------------------------------------------
  # R-007a: no set -e (or set -euo pipefail)
  # -----------------------------------------------
  local has_set_e="no"
  if grep -vE '^[[:space:]]*#' <<<"$hook_src" | grep -qE 'set[[:space:]]+-[a-z]*e'; then
    has_set_e="yes"
  fi
  assert_eq "R-007a: no set -e in hook" "no" "$has_set_e"

  # -----------------------------------------------
  # R-007b: has || exit 0 guards (fail-open)
  # -----------------------------------------------
  local has_exit_0_guard="no"
  if grep -vE '^[[:space:]]*#' <<<"$hook_src" | grep -qE '\|\|[[:space:]]*exit[[:space:]]+0'; then
    has_exit_0_guard="yes"
  fi
  assert_eq "R-007b: hook has || exit 0 guards" "yes" "$has_exit_0_guard"

  # -----------------------------------------------
  # R-007c: always exits 0 (last meaningful line)
  # -----------------------------------------------
  local last_line
  last_line="$(grep -vE '^[[:space:]]*$|^[[:space:]]*#' <<<"$hook_src" | tail -1)"
  local ends_exit_0="no"
  if grep -qF 'exit 0' <<<"$last_line"; then
    ends_exit_0="yes"
  fi
  assert_eq "R-007c: hook ends with exit 0" "yes" "$ends_exit_0"

  # -----------------------------------------------
  # R-007d: no exit [1-9] anywhere (non-comment lines)
  # -----------------------------------------------
  local has_nonzero_exit="no"
  if grep -vE '^[[:space:]]*#' <<<"$hook_src" | grep -qE 'exit[[:space:]]+[1-9]'; then
    has_nonzero_exit="yes"
  fi
  assert_eq "R-007d: no non-zero exit codes" "no" "$has_nonzero_exit"

  # -----------------------------------------------
  # R-007e: command -v jq exits 0 if missing (not exit 2)
  # -----------------------------------------------
  local jq_check_line
  jq_check_line="$(grep -A1 'command.*-v.*jq' <<<"$hook_src" || true)"
  local jq_exits_2="no"
  if grep -qE 'exit[[:space:]]+2' <<<"$jq_check_line"; then
    jq_exits_2="yes"
  fi
  assert_eq "R-007e: jq check uses exit 0 not exit 2" "no" "$jq_exits_2"

  # -----------------------------------------------
  # R-007f: hook still functions after skill field addition (runtime fail-open)
  # -----------------------------------------------
  setup_test_env
  local agent_stdin
  agent_stdin="$(build_agent_stdin)"
  local exit_code
  exit_code="$(echo "$agent_stdin" | bash hooks/token-tracking.sh >/dev/null 2>/dev/null && echo 0 || echo $?)"
  assert_eq "R-007f: hook exits 0 at runtime" "0" "$exit_code"
}

# ============================================================================
# R-008 [sync]: every update_phase target in workflow-advance.sh appears
#               in the hook's case statement
# ============================================================================

test_r008_phase_sync() {
  echo ""
  echo "=== R-008: sync test — all phases from workflow-advance.sh mapped in hook ==="

  # -----------------------------------------------
  # Extract all phase targets from workflow-advance.sh
  # Sources:
  #   1. update_phase "PHASE" calls
  #   2. .phase = "PHASE" in jq expressions
  #   3. --arg phase "PHASE" in jq calls
  # -----------------------------------------------
  local advance_src
  advance_src="$(cat "$ADVANCE_SH")"

  # Extract update_phase targets: update_phase "value"
  local update_phase_targets
  update_phase_targets="$(grep -oE 'update_phase[[:space:]]+"[^"]+"' <<<"$advance_src" \
    | sed -E 's/update_phase[[:space:]]+"([^"]+)"/\1/' \
    | sort -u || true)"

  # Extract direct .phase = "value" assignments in jq
  # Filter out jq variable references like $p, $phase (not literal phase names)
  local jq_phase_targets
  jq_phase_targets="$(grep -oE '\.phase[[:space:]]*=[[:space:]]*"[^"]+"' <<<"$advance_src" \
    | sed -E 's/\.phase[[:space:]]*=[[:space:]]*"([^"]+)"/\1/' \
    | grep -vE '^\$' \
    | sort -u || true)"

  # Extract --arg phase "value" targets
  # Filter out shell variable references like $phase (not literal phase names)
  local arg_phase_targets
  arg_phase_targets="$(grep -oE -- '--arg[[:space:]]+phase[[:space:]]+"[^"]+"' <<<"$advance_src" \
    | sed -E 's/--arg[[:space:]]+phase[[:space:]]+"([^"]+)"/\1/' \
    | grep -vE '^\$' \
    | sort -u || true)"

  # Combine and deduplicate all phase targets
  local all_phases
  all_phases="$(printf '%s\n%s\n%s' "$update_phase_targets" "$jq_phase_targets" "$arg_phase_targets" \
    | sort -u | grep -v '^$' || true)"

  # -----------------------------------------------
  # R-008a: verify we found a reasonable number of phases
  # -----------------------------------------------
  local phase_count
  phase_count="$(echo "$all_phases" | wc -l | tr -d ' ')"
  local found_enough="no"
  if [ "$phase_count" -ge 8 ]; then
    found_enough="yes"
  fi
  assert_eq "R-008a: found at least 8 phases in workflow-advance.sh (found $phase_count)" "yes" "$found_enough"

  # -----------------------------------------------
  # R-008b-N: each phase appears in the hook's case statement
  # -----------------------------------------------
  local hook_src
  hook_src="$(cat "$HOOK")"
  local non_comment
  non_comment="$(grep -vE '^[[:space:]]*#' <<<"$hook_src")"

  local missing_count=0
  local missing_phases=""

  while IFS= read -r phase; do
    [ -z "$phase" ] && continue
    # Check if the phase appears as a case pattern in the hook source
    # Must match: phase) or phase|other) or other|phase) — not substring of another word
    # Use word-boundary-safe pattern: phase followed by ) or | (case delimiters)
    local found="no"
    if grep -qE "(^|[[:space:]|])${phase}[)|]" <<<"$non_comment"; then
      found="yes"
    fi
    if [ "$found" = "yes" ]; then
      echo "  PASS: R-008: phase '$phase' mapped in hook"
      PASS=$((PASS + 1))
    else
      echo "  FAIL: R-008: phase '$phase' NOT mapped in hook case statement"
      FAIL=$((FAIL + 1))
      missing_count=$((missing_count + 1))
      missing_phases="$missing_phases $phase"
    fi
  done <<< "$all_phases"

  if [ "$missing_count" -gt 0 ]; then
    echo "  INFO: missing phases:$missing_phases"
  fi
}

# ============================================================================
# Run all tests
# ============================================================================

test_r001_skill_mapping
test_r002_skill_via_arg
test_r003_mapping_in_hook
test_r004_fallback_to_unknown
test_r005_existing_fields_preserved
test_r006_phase_and_skill_coexist
test_r007_pat005_conventions
test_r008_phase_sync

# ============================================================================
# Summary
# ============================================================================

echo ""
echo "=============================="
echo "  PASS: $PASS"
echo "  FAIL: $FAIL"
echo "=============================="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
