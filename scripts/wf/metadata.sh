#!/usr/bin/env bash
# Correctless — workflow-advance metadata/state modification commands
# Sourced by hooks/workflow-advance.sh — not independently executable.
# Contains state modification commands (set-intensity, resolve-drift, spec-update).
#
# All path resolution uses $SCRIPT_DIR (set by the dispatcher before sourcing).
# Do NOT use BASH_SOURCE[0] for path resolution — it resolves to this module
# file, not the dispatcher.

cmd_set_intensity() {
  local level="${1:-}"
  if [ -z "$level" ]; then
    die "Usage: workflow-advance.sh set-intensity <standard|high|critical>"
  fi

  # Validate intensity level
  case "$level" in
    standard|high|critical) ;;
    *) die "Invalid intensity level: '$level'. Must be one of: standard, high, critical" ;;
  esac

  check_branch_match
  # Phase guard: set-intensity only valid during spec-related phases
  require_phase_oneof "spec" "review" "review-spec"

  # QA-R2-004: Use locked_update_state for atomic read-modify-write
  local sf
  sf="$(state_file)"
  [ -f "$sf" ] || die "No state file — run 'init' first"
  locked_update_state "$sf" \
    '.feature_intensity = $lv' \
    --arg lv "$level" \
    || die "Failed to set feature intensity"
  info "Feature intensity set to: $level"
}

cmd_resolve_drift() {
  local drift_id="${1:?Usage: workflow-advance.sh resolve-drift DRIFT-xxx \"reason\"}"
  local reason="${2:?Usage: workflow-advance.sh resolve-drift DRIFT-xxx \"reason\"}"

  if [ ! -f "$DRIFT_DEBT_FILE" ]; then
    die "No drift debt file found at $DRIFT_DEBT_FILE"
  fi

  # Validate JSON
  if ! jq empty "$DRIFT_DEBT_FILE" 2>/dev/null; then
    die "Drift debt file contains invalid JSON: $DRIFT_DEBT_FILE"
  fi

  local found
  found="$(jq --arg id "$drift_id" '.drift_debt[] | select(.id == $id)' "$DRIFT_DEBT_FILE")"
  if [ -z "$found" ]; then
    die "Drift item '$drift_id' not found"
  fi

  # shellcheck disable=SC2064
  trap "$(printf 'rm -f %q' "$DRIFT_DEBT_FILE.$$")" EXIT
  # QA-R2-006: Check return code — don't report success if write failed
  if ! (jq --arg id "$drift_id" --arg reason "$reason" --arg date "$(now_iso)" \
    '(.drift_debt[] | select(.id == $id)) |= . + {status: "resolved", resolved_date: $date, resolution_reason: $reason}' \
    "$DRIFT_DEBT_FILE" > "$DRIFT_DEBT_FILE.$$" && mv "$DRIFT_DEBT_FILE.$$" "$DRIFT_DEBT_FILE"); then
    rm -f "$DRIFT_DEBT_FILE.$$"
    trap - EXIT
    die "Failed to write drift debt file"
  fi
  trap - EXIT

  info "Drift item $drift_id marked as resolved: $reason"
}

cmd_spec_update() {
  local reason="${1:?Usage: workflow-advance.sh spec-update \"reason\"}"
  check_branch_match
  require_phase_oneof "tdd-tests" "tdd-impl" "tdd-qa"

  # Read phase for logging (pre-read is fine — only used for info messages)
  local from_phase
  from_phase="$(read_phase)"

  # R-003: Re-hash spec file and update spec_hash (legitimate spec change path)
  local _spec_path _spec_hash _spec_lines
  local has_hash=false
  _read_spec_hash "$(read_state)" && has_hash=true

  # QA-R2-004: Use locked_update_state for atomic read-modify-write
  local sf ts
  sf="$(state_file)"
  ts="$(now_iso)"
  # QA-R3-001: Use --arg for user-supplied $reason to prevent jq injection
  # Note: avoid `X + 1 as $c` — jq 1.7 parses this as `X + (1 as $c)` (CI regression)
  local jq_filter hash_args=()
  jq_filter='.spec_update_history = (.spec_update_history // []) + [{from_phase: .phase, reason: $reason, timestamp: $ts}]
     | .spec_updates = ((.spec_updates // 0) + 1)
     | .phase = "spec"
     | .phase_entered_at = $ts
     | .override.active = false
     | .override.remaining_calls = 0'
  if [ "$has_hash" = true ]; then
    jq_filter="$jq_filter"'
     | .spec_hash = $hash
     | .spec_line_count = ($lines | tonumber)'
    hash_args=(--arg hash "$_spec_hash" --arg lines "$_spec_lines")
  fi
  locked_update_state "$sf" \
    "$jq_filter" \
    --arg reason "$reason" --arg ts "$ts" "${hash_args[@]}" \
    || die "Failed to update state for spec-update"
  info "Phase: spec"

  # Re-read update_count for the warning check
  local update_count
  update_count="$(read_state | jq -r '.spec_updates // 0')"
  if [ "$update_count" -ge 3 ]; then
    info "WARNING: This spec has been revised $update_count times during implementation."
    info "Consider whether the feature is under-specified or the approach is fundamentally wrong."
    info "It may be better to 'reset' and re-spec from scratch."
  fi

  info "Spec update from $from_phase: $reason"
  info "Edit the spec rules, then run 'workflow-advance.sh tests' to resume TDD."
}
