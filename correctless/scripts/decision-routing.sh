#!/usr/bin/env bash
# Correctless — Decision routing engine
# Routes decisions through the tier hierarchy (0-4).

# No set -euo pipefail — this file is sourced by other scripts

# ---------------------------------------------------------------------------
# validate_tier_hierarchy — verify no tier is skipped
# ---------------------------------------------------------------------------
# Usage: validate_tier_hierarchy FROM_TIER TO_TIER
# Returns: 0 if valid transition (adjacent), 1 if tier skipped (INV-005)
validate_tier_hierarchy() {
  local from_tier="$1"
  local to_tier="$2"

  local diff=$(( to_tier - from_tier ))
  if [ "$diff" -eq 1 ]; then
    return 0
  else
    echo "ERROR: Invalid tier transition: Tier $from_tier → Tier $to_tier (must be adjacent)" >&2
    return 1
  fi
}

# ---------------------------------------------------------------------------
# route_decision — route a DR-xxx through the tier hierarchy
# ---------------------------------------------------------------------------
# Usage: route_decision DR_JSON POLICY_FILE PHASE [STORED_HASH]
# Returns: JSON with tier, disposition, reasoning
# Evaluates Tier 0 first; if no match, returns routing info for Tier 1+.
# INV-018: When STORED_HASH is provided, policy_evaluate verifies hash integrity.
route_decision() {
  local dr_json="$1"
  local policy_file="$2"
  local phase="$3"
  local stored_hash="${4:-}"

  # Tier 0: Policy evaluation (deterministic, no LLM)
  # Source auto-policy.sh if policy_evaluate isn't already available
  if ! type -t policy_evaluate >/dev/null 2>&1; then
    local _SCRIPT_DIR
    _SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [ -f "$_SCRIPT_DIR/auto-policy.sh" ]; then
      # shellcheck source=auto-policy.sh
      source "$_SCRIPT_DIR/auto-policy.sh"
    fi
  fi

  local tier0_result=""
  local tier0_rc=0
  if type -t policy_evaluate >/dev/null 2>&1; then
    tier0_result="$(policy_evaluate "$policy_file" "$dr_json" "$phase" "$stored_hash" 2>/dev/null)" || tier0_rc=$?
  fi

  # INV-018: exit code 2 = hash mismatch → Tier 4 hard stop
  if [ "$tier0_rc" -eq 2 ]; then
    jq -n '{tier: 4, disposition: "hard_stop", reasoning: "Policy file hash mismatch — policy modified during run (INV-018)"}'
    return 0
  fi

  if [ -n "$tier0_result" ] && [ "$tier0_result" != "no_match" ]; then
    # Tier 0 matched — return disposition directly (AP-010: use --arg for values)
    jq -n --arg disp "$tier0_result" \
      '{tier: 0, disposition: $disp, reasoning: "Tier 0 policy match"}'
    return 0
  fi

  # Tier 0 no match — route to Tier 1+
  local category
  category="$(echo "$dr_json" | jq -r '.category // "unknown"' 2>/dev/null)" || category="unknown"

  jq -n --arg cat "$category" --arg ph "$phase" \
    '{tier: 1, disposition: "routing", reasoning: ("No Tier 0 policy match for category \u0027" + $cat + "\u0027 in phase \u0027" + $ph + "\u0027 — routing to Tier 1+")}'
  return 0
}

# ---------------------------------------------------------------------------
# tier2_build_context — build minimal context for Tier 2 agent
# ---------------------------------------------------------------------------
# Usage: tier2_build_context DR_JSON POLICY_FILE SPEC_FILE
# Returns: JSON context payload with only allowed fields (INV-006)
# Does NOT include conversation_history, full_spec, or full codebase context.
tier2_build_context() {
  local dr_json="$1"
  local policy_file="$2"
  local spec_file="$3"

  # Extract relevant_rules from DR-xxx to find spec excerpts
  local relevant_rules
  relevant_rules="$(echo "$dr_json" | jq -r '.relevant_rules // [] | .[]' 2>/dev/null)" || true

  # Read spec excerpt (only referenced sections, not full spec)
  local spec_excerpt=""
  if [ -f "$spec_file" ] && [ -n "$relevant_rules" ]; then
    # Extract lines containing any of the referenced rules
    for rule in $relevant_rules; do
      local found
      found="$(grep -A 5 "$rule" "$spec_file" 2>/dev/null)" || true
      if [ -n "$found" ]; then
        spec_excerpt="${spec_excerpt}${found}"$'\n'
      fi
    done
  fi

  # Read matching policy section
  local category
  category="$(echo "$dr_json" | jq -r '.category // ""' 2>/dev/null)" || true

  # Select the correct policy section based on DR-xxx phase (mirrors policy_evaluate logic)
  local dr_phase
  dr_phase="$(echo "$dr_json" | jq -r '.phase // ""' 2>/dev/null)" || dr_phase=""

  local policy_section=""
  if [ -f "$policy_file" ]; then
    local section_key="review_dispositions"
    case "$dr_phase" in
      review|review-spec) section_key="review_dispositions" ;;
      qa|tdd-qa)          section_key="qa_dispositions" ;;
      verify|done|verified|tdd-verify) section_key="drift" ;;
      spec|spec-update)   section_key="spec_update" ;;
    esac
    policy_section="$(jq --arg key "$section_key" --arg cat "$category" \
      '{($key): (.[$key] // {} | if type == "object" then {($cat): .[$cat]} else . end)}' \
      "$policy_file" 2>/dev/null)" || policy_section="{}"
  fi

  # Extract prior_decisions (summary + disposition only)
  local prior_decisions
  prior_decisions="$(echo "$dr_json" | jq '.prior_decisions // []' 2>/dev/null)" || prior_decisions="[]"

  # Build context JSON — only allowed fields
  # Use a temp file approach for complex JSON to avoid shell quoting issues
  local _ctx_tmp
  _ctx_tmp="$(mktemp)"
  # shellcheck disable=SC2064
  trap "$(printf 'rm -f %q' "$_ctx_tmp")" EXIT
  echo "$dr_json" > "$_ctx_tmp"

  local result
  result="$(jq -n \
    --slurpfile dr "$_ctx_tmp" \
    --arg spec_excerpt "$spec_excerpt" \
    --argjson policy_section "${policy_section:-"{}"}" \
    --argjson prior_decisions "${prior_decisions:-"[]"}" \
    '{
      decision_request: $dr[0],
      spec_excerpt: $spec_excerpt,
      policy_section: $policy_section,
      prior_decisions: $prior_decisions
    }' 2>/dev/null)"
  local rc=$?
  rm -f "$_ctx_tmp"
  trap - EXIT
  echo "$result"
  return "$rc"
}

# ---------------------------------------------------------------------------
# supervisor_validate_input — validate supervisor input message schema
# ---------------------------------------------------------------------------
# Usage: supervisor_validate_input INPUT_JSON
# Returns: 0 if valid, 1 if missing required fields (INV-004)
supervisor_validate_input() {
  local input_json="$1"

  # Must be valid JSON
  if ! echo "$input_json" | jq '.' >/dev/null 2>&1; then
    echo "ERROR: supervisor input is not valid JSON" >&2
    return 1
  fi

  # Check required fields: activation_type, intent_summary, phase_summary,
  # decision_record_recent, budget_status
  local missing
  missing="$(echo "$input_json" | jq -r '
    [
      (if .activation_type == null then "activation_type" else empty end),
      (if .intent_summary == null then "intent_summary" else empty end),
      (if .phase_summary == null then "phase_summary" else empty end),
      (if .decision_record_recent == null then "decision_record_recent" else empty end),
      (if .budget_status == null then "budget_status" else empty end)
    ] | join(", ")
  ' 2>/dev/null)"

  if [ -n "$missing" ]; then
    echo "ERROR: supervisor input missing required fields: $missing" >&2
    return 1
  fi

  return 0
}

# ---------------------------------------------------------------------------
# supervisor_validate_response — validate supervisor response schema
# ---------------------------------------------------------------------------
# Usage: supervisor_validate_response RESPONSE_JSON
# Returns: 0 if valid, 1 if missing required fields or invalid decision (BND-004)
supervisor_validate_response() {
  local response_json="$1"

  # Must be valid JSON
  if ! echo "$response_json" | jq '.' >/dev/null 2>&1; then
    echo "ERROR: supervisor response is not valid JSON" >&2
    return 1
  fi

  # Check required fields: decision, reasoning, flags
  local decision reasoning flags_present
  eval "$(echo "$response_json" | jq -r '
    @sh "decision=\(.decision // "")",
    @sh "reasoning=\(.reasoning // "")",
    @sh "flags_present=\(if .flags != null then "yes" else "no" end)"
  ' 2>/dev/null)" || return 1

  if [ -z "$decision" ]; then
    echo "ERROR: supervisor response missing 'decision' field" >&2
    return 1
  fi

  if [ -z "$reasoning" ]; then
    echo "ERROR: supervisor response missing 'reasoning' field" >&2
    return 1
  fi

  if [ "$flags_present" != "yes" ]; then
    echo "ERROR: supervisor response missing 'flags' field" >&2
    return 1
  fi

  # Validate decision value — only approve, reject, hard_stop are valid
  # redirect is explicitly invalid (BND-004: treated as hard_stop by orchestrator)
  case "$decision" in
    approve|reject|hard_stop)
      return 0
      ;;
    redirect)
      echo "ERROR: 'redirect' is not a valid terminal decision (treated as hard_stop)" >&2
      return 1
      ;;
    *)
      echo "ERROR: unrecognized supervisor decision: $decision" >&2
      return 1
      ;;
  esac
}

# ---------------------------------------------------------------------------
# check_supervisor_cap — check if supervisor activation count has reached cap
# ---------------------------------------------------------------------------
# Usage: check_supervisor_cap STATE_FILE
# Returns: "ok" if under cap (<20), "hard_stop" if at/over 20 (INV-007)
check_supervisor_cap() {
  local state_file="$1"

  if [ ! -f "$state_file" ]; then
    echo "ok"
    return 0
  fi

  local count
  count="$(jq -r '.supervisor_activation_count // 0' "$state_file" 2>/dev/null)" || count=0

  if [ "$count" -ge 20 ]; then
    echo "hard_stop"
  else
    echo "ok"
  fi
}
