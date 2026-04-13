#!/usr/bin/env bash
# Correctless — Decision record management
# Append-only decision record with size-regression detection.

# No set -euo pipefail — this file is sourced by other scripts

# ---------------------------------------------------------------------------
# drx_validate — validate a DR-xxx structured decision request
# ---------------------------------------------------------------------------
# Usage: drx_validate DR_JSON
# Returns: 0 if valid, 1 if malformed (with error on stderr)
# Checks required fields and controlled category vocabulary (INV-003).
drx_validate() {
  local dr_json="$1"

  # Empty or missing input
  if [ -z "$dr_json" ]; then
    echo "ERROR: empty DR-xxx input" >&2
    return 1
  fi

  # Must be valid JSON
  if ! echo "$dr_json" | jq '.' >/dev/null 2>&1; then
    echo "ERROR: DR-xxx is not valid JSON" >&2
    return 1
  fi

  # Check required fields per INV-003 (QA-004: validate all 10 fields, not just 3).
  # Required string fields: decision_id, requesting_agent, phase, category, summary
  # Optional string field: severity (omitted when not applicable)
  # Required array fields: options, relevant_rules, relevant_policies, prior_decisions
  local missing
  missing="$(echo "$dr_json" | jq -r '
    [
      (if .decision_id == null or .decision_id == "" then "decision_id" else empty end),
      (if .requesting_agent == null or .requesting_agent == "" then "requesting_agent" else empty end),
      (if .phase == null or .phase == "" then "phase" else empty end),
      (if .category == null or .category == "" then "category" else empty end),
      (if .summary == null or .summary == "" then "summary" else empty end),
      (if .options == null then "options" elif (.options | type) != "array" then "options(must be array)" else empty end),
      (if .relevant_rules == null then "relevant_rules" elif (.relevant_rules | type) != "array" then "relevant_rules(must be array)" else empty end),
      (if .relevant_policies == null then "relevant_policies" elif (.relevant_policies | type) != "array" then "relevant_policies(must be array)" else empty end),
      (if .prior_decisions == null then "prior_decisions" elif (.prior_decisions | type) != "array" then "prior_decisions(must be array)" else empty end)
    ] | join(", ")
  ' 2>/dev/null)"

  if [ -n "$missing" ]; then
    echo "ERROR: DR-xxx missing required fields: $missing" >&2
    return 1
  fi

  # Validate category against controlled vocabulary
  local category
  category="$(echo "$dr_json" | jq -r '.category' 2>/dev/null)"

  case "$category" in
    security|availability|testability|scope_expansion|performance|architecture|observability|technical_debt|intent|hard_stop_multiplex|dependency|budget|policy|configuration)
      # Valid category
      ;;
    *)
      echo "ERROR: DR-xxx invalid category: $category" >&2
      return 1
      ;;
  esac

  return 0
}

# ---------------------------------------------------------------------------
# dr_append — append a DD-xxx entry to the decision record
# ---------------------------------------------------------------------------
# Usage: dr_append RECORD_FILE DD_ENTRY_JSON
# Formats the DD-xxx entry as markdown and appends to the record file.
# Creates the file if it doesn't exist.
dr_append() {
  local record_file="$1"
  local dd_json="$2"

  # Parse the DD-xxx entry
  local decision_id tier category summary disposition reasoning timestamp
  eval "$(echo "$dd_json" | jq -r '
    @sh "decision_id=\(.decision_id // "")",
    @sh "tier=\(.tier // "")",
    @sh "category=\(.category // "")",
    @sh "summary=\(.summary // "")",
    @sh "disposition=\(.disposition // "")",
    @sh "reasoning=\(.reasoning // "")",
    @sh "timestamp=\(.timestamp // "")"
  ' 2>/dev/null)" || return 1

  # Append as markdown entry
  {
    echo ""
    echo "### $decision_id"
    echo "- **Tier**: $tier"
    echo "- **Category**: $category"
    echo "- **Summary**: $summary"
    echo "- **Disposition**: $disposition"
    echo "- **Reasoning**: $reasoning"
    echo "- **Timestamp**: $timestamp"
  } >> "$record_file"

  return 0
}

# ---------------------------------------------------------------------------
# dr_count_entries — count DD-xxx entries in the decision record
# ---------------------------------------------------------------------------
# Usage: dr_count_entries RECORD_FILE
# Counts lines matching "### DD-" pattern.
dr_count_entries() {
  local record_file="$1"

  if [ ! -f "$record_file" ]; then
    echo "0"
    return 0
  fi

  grep -c '^### DD-' "$record_file" 2>/dev/null || echo "0"
}

# ---------------------------------------------------------------------------
# dr_verify_size — verify file size has not regressed
# ---------------------------------------------------------------------------
# Usage: dr_verify_size RECORD_FILE EXPECTED_MIN_SIZE
# Returns: 0 if size >= expected, 1 if shrunk (INV-016)
dr_verify_size() {
  local record_file="$1"
  local expected_min_size="$2"

  if [ ! -f "$record_file" ]; then
    return 1
  fi

  local actual_size
  actual_size="$(wc -c < "$record_file")"

  if [ "$actual_size" -ge "$expected_min_size" ]; then
    return 0
  else
    echo "ERROR: Decision record size regression: actual=$actual_size < expected=$expected_min_size" >&2
    return 1
  fi
}

# ---------------------------------------------------------------------------
# dr_hedging_scan — scan for hedging language in untagged entries
# ---------------------------------------------------------------------------
# Usage: dr_hedging_scan RECORD_FILE
# Returns: DD-xxx IDs of entries with hedging language but no ASSUMPTION tag.
# Hedging terms: assume, likely, probably, default to, conservative (INV-011)
dr_hedging_scan() {
  local record_file="$1"

  if [ ! -f "$record_file" ]; then
    echo ""
    return 0
  fi

  # Process the file: find DD-xxx entries, check for hedging without ASSUMPTION
  local current_id=""
  local current_block=""
  local results=""

  # Helper: check current block for untagged hedging language
  _check_hedging_block() {
    if [ -n "$current_id" ] && [ -n "$current_block" ]; then
      if echo "$current_block" | grep -qiE 'assume|likely|probably|default to|conservative'; then
        if ! echo "$current_block" | grep -qF 'ASSUMPTION'; then
          results="${results}${current_id}"$'\n'
        fi
      fi
    fi
  }

  while IFS= read -r line; do
    if echo "$line" | grep -q '^### DD-'; then
      _check_hedging_block
      current_id="$(echo "$line" | sed 's/^### //')"
      current_block=""
    else
      current_block="${current_block}${line}"$'\n'
    fi
  done < "$record_file"

  _check_hedging_block
  unset -f _check_hedging_block

  # Output results (trimmed)
  echo "$results" | sed '/^$/d'
}

# ---------------------------------------------------------------------------
# dr_verify_cardinality — verify decision record count matches audit trail
# ---------------------------------------------------------------------------
# Usage: dr_verify_cardinality RECORD_FILE AUDIT_TRAIL_JSONL
# QA-007/QA-008: DD count should equal ALL event types + 1 (DD-000):
#   decision_routed + supervisor_activated + human_decision + system_event + 1
# Returns: 0 if match, 1 if mismatch (INV-002)
dr_verify_cardinality() {
  local record_file="$1"
  local audit_file="$2"

  # Count DD-xxx entries in decision record
  local dd_count
  dd_count="$(dr_count_entries "$record_file")"

  # Count ALL audit trail event types (QA-007: was missing human_decision + system_event)
  local decision_routed_count=0
  local supervisor_activated_count=0
  local human_decision_count=0
  local system_event_count=0

  if [ -f "$audit_file" ]; then
    # grep -c outputs "0" and exits non-zero when no matches. Using || true
    # avoids double-output from || echo 0 (grep already outputs the count).
    decision_routed_count="$(grep -c '"decision_routed"' "$audit_file" 2>/dev/null)" || decision_routed_count=0
    supervisor_activated_count="$(grep -c '"supervisor_activated"' "$audit_file" 2>/dev/null)" || supervisor_activated_count=0
    human_decision_count="$(grep -c '"human_decision"' "$audit_file" 2>/dev/null)" || human_decision_count=0
    system_event_count="$(grep -c '"system_event"' "$audit_file" 2>/dev/null)" || system_event_count=0
  fi

  # Expected: all event types + 1 (DD-000 intent creation)
  local expected_count=$(( decision_routed_count + supervisor_activated_count + human_decision_count + system_event_count + 1 ))

  if [ "$dd_count" -eq "$expected_count" ]; then
    return 0
  else
    echo "ERROR: Cardinality mismatch: DD count=$dd_count, expected=$expected_count (routed=$decision_routed_count + supervisor=$supervisor_activated_count + human=$human_decision_count + system=$system_event_count + 1)" >&2
    return 1
  fi
}
