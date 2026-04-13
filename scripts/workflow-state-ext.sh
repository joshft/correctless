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

  # QA-009: use locked_update_state for correct EXIT trap handling (AP-015 class fix)
  # QA-012: always store as string — callers needing integers use ws_increment_field
  locked_update_state "$state_file" '.[$f] = $v' --arg f "$field" --arg v "$value"
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

  # QA-009: use locked_update_state for correct EXIT trap handling (AP-015 class fix)
  locked_update_state "$state_file" \
    '((.[$f] // 0) | tonumber) as $cur | .[$f] = (($cur + 1) | tostring)' \
    --arg f "$field"
}

# ---------------------------------------------------------------------------
# Phase 3 extensions
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# ws_set_spec_approval — record spec approval in workflow state
# ---------------------------------------------------------------------------
# Usage: ws_set_spec_approval STATE_FILE APPROVER TIMESTAMP
# Writes spec_approved_by and spec_approved_at fields atomically.
# ABS-003: uses single locked_update_state call to set both fields in one
# lock cycle, avoiding the non-atomic two-field write antipattern.
ws_set_spec_approval() {
  local _state_file="$1"
  local _approver="$2"
  local _timestamp="$3"

  [ -f "$_state_file" ] || return 1

  # Atomic: set both fields in a single locked read-modify-write
  locked_update_state "$_state_file" \
    '.spec_approved_by = $approver | .spec_approved_at = $ts' \
    --arg approver "$_approver" --arg ts "$_timestamp"
}

# ---------------------------------------------------------------------------
# ws_get_spec_approval — read spec approval from workflow state
# ---------------------------------------------------------------------------
# Usage: ws_get_spec_approval STATE_FILE
# Outputs JSON: {"approver":"...","timestamp":"..."}
ws_get_spec_approval() {
  local _state_file="$1"

  [ -f "$_state_file" ] || { echo '{"approver":"","timestamp":""}'; return 1; }

  # Single jq pass to extract both fields
  jq '{approver: (.spec_approved_by // ""), timestamp: (.spec_approved_at // "")}' \
    "$_state_file" 2>/dev/null || echo '{"approver":"","timestamp":""}'
  return 0
}
