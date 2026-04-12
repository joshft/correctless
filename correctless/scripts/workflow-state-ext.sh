#!/usr/bin/env bash
# Correctless — Workflow state extensions for Auto Mode Phase 2
# Provides atomic read/write of Phase 2 fields:
#   supervisor_activation_count, decision_record_size,
#   intent_hash, policy_hash, pipeline_start_time

# No set -euo pipefail — this file is sourced by other scripts.
# Source lib.sh for advisory locking (_acquire_state_lock / _release_state_lock).
# ABS-003 / QA-002: all state file writes must go through locked paths.
# Source at top level (not inside functions) to avoid RETURN trap interaction.
_WS_EXT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || true)"
if [ -n "$_WS_EXT_DIR" ] && [ -f "$_WS_EXT_DIR/lib.sh" ]; then
  # shellcheck source=lib.sh
  source "$_WS_EXT_DIR/lib.sh"
fi
unset _WS_EXT_DIR

# ---------------------------------------------------------------------------
# ws_get_field — read a single field from the workflow state file
# ---------------------------------------------------------------------------
# Usage: ws_get_field STATE_FILE FIELD_NAME
# Outputs the field value to stdout. Returns 0 on success, 1 on failure.
ws_get_field() {
  local state_file="$1"
  local field="$2"

  [ -f "$state_file" ] || return 1
  jq -r --arg f "$field" '.[$f] // empty' "$state_file" 2>/dev/null
}

# ---------------------------------------------------------------------------
# ws_set_field — write a single field to the workflow state file atomically
# ---------------------------------------------------------------------------
# Usage: ws_set_field STATE_FILE FIELD_NAME VALUE
# Uses jq --arg to safely handle user-controlled values (AP-010).
ws_set_field() {
  local state_file="$1"
  local field="$2"
  local value="$3"

  [ -f "$state_file" ] || return 1

  # QA-002 / ABS-003: acquire advisory lock before state file write
  _acquire_state_lock "$state_file" || return 1

  local tmp_file="${state_file}.$$.tmp"
  local rc=0
  # Use if/else to handle numeric vs string values (jq 1.7 compat — no try/catch)
  if jq --arg f "$field" --arg v "$value" \
      'if ($v | test("^-?[0-9]+$")) then .[$f] = ($v | tonumber) else .[$f] = $v end' \
      "$state_file" > "$tmp_file" 2>/dev/null; then
    mv "$tmp_file" "$state_file" || { rm -f "$tmp_file"; rc=1; }
  else
    rm -f "$tmp_file"
    rc=1
  fi

  _release_state_lock "$state_file"
  return "$rc"
}

# ---------------------------------------------------------------------------
# ws_increment_field — atomically increment an integer field
# ---------------------------------------------------------------------------
# Usage: ws_increment_field STATE_FILE FIELD_NAME
# If the field doesn't exist or is null, treats it as 0 before incrementing.
# Uses explicit parenthesization for as $var bindings (PAT-010/AP-011).
ws_increment_field() {
  local state_file="$1"
  local field="$2"

  [ -f "$state_file" ] || return 1

  # QA-002 / ABS-003: acquire advisory lock before state file write
  _acquire_state_lock "$state_file" || return 1

  local tmp_file="${state_file}.$$.tmp"
  local rc=0
  if jq --arg f "$field" \
      '((.[$f] // 0) | tonumber) as $cur | .[$f] = ($cur + 1)' \
      "$state_file" > "$tmp_file" 2>/dev/null; then
    mv "$tmp_file" "$state_file" || { rm -f "$tmp_file"; rc=1; }
  else
    rm -f "$tmp_file"
    rc=1
  fi

  _release_state_lock "$state_file"
  return "$rc"
}
