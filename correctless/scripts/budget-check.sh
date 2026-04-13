#!/usr/bin/env bash
# Correctless — Budget enforcement for Auto Mode
# Token + time budget tracking with warn/hard-stop thresholds.

# No set -euo pipefail — this file is sourced by other scripts

# ---------------------------------------------------------------------------
# budget_get_token_usage — read total token usage from token log
# ---------------------------------------------------------------------------
# Usage: budget_get_token_usage TOKEN_LOG
# Returns: integer (total tokens) or "unknown" if file missing (BND-002)
budget_get_token_usage() {
  local token_log="$1"

  if [ ! -f "$token_log" ]; then
    echo "unknown"
    return 0
  fi

  # Sum total_tokens from JSONL, skipping malformed lines (ABS-006)
  # Must use jq -R + try/catch, never jq -s — a single malformed line must not
  # disable all token-based budget enforcement (QA-001 / ABS-006).
  local total
  total="$(jq -R 'try (fromjson | .total_tokens // 0) catch 0' "$token_log" 2>/dev/null \
    | jq -s 'add // 0' 2>/dev/null)" || total="unknown"

  if [ -z "$total" ] || [ "$total" = "null" ]; then
    echo "unknown"
  else
    echo "$total"
  fi
}

# ---------------------------------------------------------------------------
# budget_get_elapsed — compute elapsed time since pipeline start
# ---------------------------------------------------------------------------
# Usage: budget_get_elapsed STATE_FILE
# Returns: decimal hours
budget_get_elapsed() {
  local state_file="$1"

  if [ ! -f "$state_file" ]; then
    echo "0"
    return 0
  fi

  local start_time
  start_time="$(jq -r '.pipeline_start_time // empty' "$state_file" 2>/dev/null)" || true

  if [ -z "$start_time" ]; then
    echo "0"
    return 0
  fi

  # Convert ISO 8601 to epoch seconds (GNU date -d, then macOS date -jf fallback)
  local start_epoch now_epoch
  start_epoch="$(date -d "$start_time" +%s 2>/dev/null)" \
    || start_epoch="$(date -jf "%Y-%m-%dT%H:%M:%SZ" "$start_time" +%s 2>/dev/null)" \
    || start_epoch=0
  now_epoch="$(date +%s)"

  if [ "$start_epoch" -eq 0 ]; then
    echo "0"
    return 0
  fi

  # Convert elapsed seconds to decimal hours
  awk -v secs=$(( now_epoch - start_epoch )) 'BEGIN { printf "%.2f", secs / 3600.0 }'
}

# ---------------------------------------------------------------------------
# budget_check — check budget status against policy thresholds
# ---------------------------------------------------------------------------
# Usage: budget_check TOKEN_LOG POLICY_FILE STATE_FILE
# Returns status string: "ok", "warn", or "hard_stop"
budget_check() {
  local token_log="$1"
  local policy_file="$2"
  local state_file="$3"

  # Read policy thresholds
  local max_tokens=2000000 warn_pct=75 stop_pct=100
  local max_hours=8 warn_hours=6

  if [ -f "$policy_file" ]; then
    eval "$(jq -r '
      @sh "max_tokens=\(.budget.max_tokens // 2000000)",
      @sh "warn_pct=\(.budget.warn_at_percent // 75)",
      @sh "stop_pct=\(.budget.hard_stop_at_percent // 100)",
      @sh "max_hours=\(.time.max_duration_hours // 8)",
      @sh "warn_hours=\(.time.warn_at_hours // 6)"
    ' "$policy_file" 2>/dev/null)" || true
  fi

  # Check time budget
  local elapsed
  elapsed="$(budget_get_elapsed "$state_file")"

  local time_exceeded="no" time_warn="no"
  if [ -n "$elapsed" ] && [ "$elapsed" != "0" ]; then
    eval "$(awk -v elapsed="$elapsed" -v max_hours="$max_hours" -v warn_hours="$warn_hours" 'BEGIN {
      if (elapsed >= max_hours) print "time_exceeded=yes"
      else if (elapsed >= warn_hours) print "time_warn=yes"
    }')"
  fi

  if [ "$time_exceeded" = "yes" ]; then
    echo "hard_stop"
    return 0
  fi

  # Check token budget
  local token_usage
  token_usage="$(budget_get_token_usage "$token_log")"

  if [ "$token_usage" = "unknown" ]; then
    # BND-002: missing token log — token budget disabled, time budget still active
    if [ "$time_warn" = "yes" ]; then
      echo "warn"
    else
      echo "ok"
    fi
    return 0
  fi

  # R2-F4: guard against division by zero if policy sets max_tokens to 0
  if [ "$max_tokens" -le 0 ] 2>/dev/null; then
    max_tokens=2000000
  fi

  # Calculate token percentage
  local token_pct=$(( (token_usage * 100) / max_tokens ))

  if [ "$token_pct" -ge "$stop_pct" ]; then
    echo "hard_stop"
    return 0
  fi

  if [ "$token_pct" -ge "$warn_pct" ] || [ "$time_warn" = "yes" ]; then
    echo "warn"
    return 0
  fi

  echo "ok"
}

# ---------------------------------------------------------------------------
# escalation_write — write structured escalation file on hard stop
# ---------------------------------------------------------------------------
# Usage: escalation_write OUTPUT_FILE PHASE REASON OPTIONS_JSON PRIORITY_CONDITIONS
# PRIORITY_CONDITIONS is comma-separated: "integrity,security,budget"
# Returns: 0 if written, 1 on failure (INV-010)
escalation_write() {
  local output_file="$1"
  local phase="$2"
  local reason="$3"
  local options_json="$4"
  local priority_conditions="$5"

  # Build conditions list sorted by priority (comma-separated input)
  local priority_order="integrity security budget supervisor_cap other"
  local conditions_text=""

  for p in $priority_order; do
    if echo "$priority_conditions" | grep -qi "$p"; then
      conditions_text="${conditions_text}"$'- **'"${p}"$'**: Active\n'
    fi
  done

  # Parse options from JSON
  local options_text=""
  if [ -n "$options_json" ] && [ "$options_json" != "null" ]; then
    options_text="$(echo "$options_json" | jq -r '.[] | "\(.id). \(.description)"' 2>/dev/null)" || true
  fi

  # Write the escalation file
  {
    printf '%s\n' "---"
    printf '%s\n' "failed_at_phase: $phase"
    printf '%s\n' "reason: $reason"
    printf '%s\n' "---"
    printf '\n%s\n\n' "## Hard Stop: $reason"
    printf '%s\n\n' "### Active Conditions (Priority Order)"
    printf '%b\n' "$conditions_text"
    printf '%s\n\n' "### Options"
    printf '%s\n\n' "$options_text"
    printf '%s\n\n' "### Resume"
    printf '%s\n\n' 'To resume the pipeline, run: `/cauto resume "decision"`'
    printf '%s\n' 'Where "decision" is the option number (e.g., "1") or a text description of your decision.'
  } > "$output_file"

  return 0
}

# ---------------------------------------------------------------------------
# resume_parse_decision — parse human's resume decision from /cauto resume
# ---------------------------------------------------------------------------
# Usage: resume_parse_decision DECISION_STRING
# Returns: JSON with parsed decision details (INV-015)
# Tries numeric option first, falls back to text.
resume_parse_decision() {
  local decision_string="$1"

  # Try numeric option first
  if [[ "$decision_string" =~ ^[0-9]+$ ]]; then
    # Numeric option selected
    jq -n --arg opt "$decision_string" --arg tier "human" \
      '{option: ($opt | tonumber), text: ("Selected option " + $opt), tier: $tier}'
    return 0
  fi

  # Fall back to text interpretation
  jq -n --arg text "$decision_string" --arg tier "human" \
    '{option: null, text: $text, tier: $tier}'
  return 0
}
