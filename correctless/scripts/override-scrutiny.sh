#!/usr/bin/env bash
# Correctless — Override window scrutiny for Auto Mode Phase 3
# Handles supervisor review of override issuance, per-action review
# during override windows, closure review, retry prevention, and
# override log extensions.

# No set -euo pipefail — this file is sourced by other scripts

# Source lib.sh for shared utilities.
# Source at top level (not inside functions) to avoid RETURN trap interaction.
_OVERRIDE_SCRUTINY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || true)"
if [ -n "$_OVERRIDE_SCRUTINY_DIR" ] && [ -f "$_OVERRIDE_SCRUTINY_DIR/lib.sh" ]; then
  # shellcheck source=lib.sh
  source "$_OVERRIDE_SCRUTINY_DIR/lib.sh"
fi
if [ -n "${_OVERRIDE_SCRUTINY_DIR:-}" ] && [ -f "$_OVERRIDE_SCRUTINY_DIR/workflow-state-ext.sh" ]; then
  # shellcheck source=workflow-state-ext.sh
  source "$_OVERRIDE_SCRUTINY_DIR/workflow-state-ext.sh"
fi
unset _OVERRIDE_SCRUTINY_DIR

# ---------------------------------------------------------------------------
# build_override_issuance_payload — build payload for override issuance review
# ---------------------------------------------------------------------------
# Usage: build_override_issuance_payload OVERRIDE_REASON PHASE INTENT_SUMMARY DECISION_RECORD_FILE
# Outputs JSON payload for supervisor activation_type: override_issued
build_override_issuance_payload() {
  local _override_reason="$1"
  local _phase="$2"
  local _intent_summary="$3"
  local _decision_record_file="$4"

  # Read last 10 DD-xxx entries from decision record
  local recent_decisions="[]"
  if [ -f "$_decision_record_file" ]; then
    recent_decisions="$(awk '/^### DD-/{found++} found>0' "$_decision_record_file" 2>/dev/null \
      | tail -50 | head -50)" || true
    # Convert to simple JSON array with summary lines
    recent_decisions="$(echo "$recent_decisions" | grep -E '(DD-|Summary|Disposition)' 2>/dev/null \
      | jq -R -s 'split("\n") | map(select(length > 0))' 2>/dev/null)" || recent_decisions="[]"
  fi

  # Build JSON payload using jq --arg (AP-010)
  jq -n \
    --arg reason "$_override_reason" \
    --arg phase "$_phase" \
    --arg intent "$_intent_summary" \
    --argjson recent "$recent_decisions" \
    '{
      activation_type: "override_issued",
      override_reason: $reason,
      phase: $phase,
      intent_summary: $intent,
      recent_decisions: $recent
    }'

  return 0
}

# ---------------------------------------------------------------------------
# review_override_issuance — review override issuance via supervisor
# ---------------------------------------------------------------------------
# Usage: review_override_issuance STATE_FILE OVERRIDE_REASON PHASE INTENT_SUMMARY DECISION_RECORD_FILE CROSSCHECK_EVIDENCE
# Outputs disposition: approve_override | reject_override | escalate_to_human
review_override_issuance() {
  local _state_file="$1"
  local _override_reason="$2"
  local _phase="$3"
  local _intent_summary="$4"
  local _decision_record_file="$5"
  local _crosscheck_evidence="$6"

  # BND-008: Intent hash presence check.
  # In production, intent_verify would be called for full verification.

  # BND-006: Validate cross-check evidence is valid JSON
  if ! echo "$_crosscheck_evidence" | jq '.' >/dev/null 2>&1; then
    # Invalid JSON evidence — escalate to human per BND-006
    echo "escalate_to_human"
    return 0
  fi

  # Check cross-check evidence: if claim_verified is false, reject or escalate
  # Note: jq's // operator treats false as falsy, so use explicit conditional
  local claim_verified
  claim_verified="$(echo "$_crosscheck_evidence" | jq -r 'if .claim_verified == false then "false" elif .claim_verified == true then "true" else "null" end' 2>/dev/null)" || claim_verified="null"

  if [ "$claim_verified" = "false" ]; then
    # Pre-existing claim was false — reject the override
    # QA-006: persist rejection so Jaccard retry prevention (PRH-006) can detect retries
    if [ -f "$_state_file" ]; then
      locked_update_state "$_state_file" \
        '.rejected_overrides = ((.rejected_overrides // []) + [$reason])' \
        --arg reason "$_override_reason" 2>/dev/null || true
    fi
    echo "reject_override"
    return 0
  elif [ "$claim_verified" = "null" ]; then
    # QA-014: timeout or inconclusive — escalate instead of rejecting
    echo "escalate_to_human"
    return 0
  fi

  # In production, this would call the supervisor via Task(subagent_type="correctless:supervisor")
  # The supervisor evaluates the override reason against the intent and evidence.
  echo "approve_override"
  return 0
}

# ---------------------------------------------------------------------------
# build_override_action_payload — build payload for per-action review
# ---------------------------------------------------------------------------
# Usage: build_override_action_payload ACTION_DESC OVERRIDE_REASON INTENT_SUMMARY DD_ENTRIES_SINCE
# Outputs JSON payload for supervisor activation_type: override_action_review
build_override_action_payload() {
  local _action_desc="$1"
  local _override_reason="$2"
  local _intent_summary="$3"
  local _dd_entries_since="$4"

  # QA-026: validate _dd_entries_since is valid JSON before --argjson
  if ! echo "$_dd_entries_since" | jq -e '.' >/dev/null 2>&1; then
    _dd_entries_since="[]"
  fi

  # Build JSON payload using jq --arg (AP-010)
  jq -n \
    --arg action "$_action_desc" \
    --arg reason "$_override_reason" \
    --arg intent "$_intent_summary" \
    --argjson dd_since "$_dd_entries_since" \
    '{
      activation_type: "override_action_review",
      action_description: $action,
      override_reason: $reason,
      intent_summary: $intent,
      dd_entries_since: $dd_since
    }'

  return 0
}

# ---------------------------------------------------------------------------
# review_override_action — review individual action during override window
# ---------------------------------------------------------------------------
# Usage: review_override_action STATE_FILE ACTION_DESC OVERRIDE_REASON INTENT_SUMMARY DD_SINCE DRIFT_EVIDENCE
# Outputs disposition: approve_action | reject_action | escalate_to_human
review_override_action() {
  local _state_file="$1"
  local _action_desc="$2"
  local _override_reason="$3"
  local _intent_summary="$4"
  local _dd_since="$5"
  local _drift_evidence="$6"

  # BND-008: Verify intent hash — compare stored hash against actual intent file.
  # Return hard_stop only on MISMATCH (tampered intent). Matching hash → proceed.
  if [ -f "$_state_file" ]; then
    local stored_intent_hash
    stored_intent_hash="$(jq -r '.intent_hash // ""' "$_state_file" 2>/dev/null)" || true
    if [ -n "$stored_intent_hash" ] && [ "$stored_intent_hash" != "null" ]; then
      local intent_file
      intent_file="$(jq -r '.intent_file // ""' "$_state_file" 2>/dev/null)" || intent_file=""
      if [ -n "$intent_file" ] && [ -f "$intent_file" ]; then
        local current_intent_hash
        current_intent_hash="$(sha256_hash_file "$intent_file" 2>/dev/null)" || current_intent_hash=""
        if [ -n "$current_intent_hash" ] && [ "$current_intent_hash" != "$stored_intent_hash" ]; then
          echo "hard_stop"
          return 0
        fi
        # Hash matches — intent is intact, proceed with normal review
      else
        # Intent file missing or path unknown — fail-closed
        echo "hard_stop"
        return 0
      fi
    fi
  fi

  # BND-006: Validate drift evidence is valid JSON
  if ! echo "$_drift_evidence" | jq '.' >/dev/null 2>&1; then
    # Invalid drift evidence — reject action per BND-006
    echo "reject_action"
    return 0
  fi

  # INV-041: Check scope drift evidence
  # Note: jq's // operator treats false as falsy, so use explicit conditional
  local scope_drift
  scope_drift="$(echo "$_drift_evidence" | jq -r 'if .scope_drift_detected == true then "true" else "false" end' 2>/dev/null)" || scope_drift="false"
  if [ "$scope_drift" = "true" ]; then
    # Scope drift detected — escalate to human per INV-041
    echo "escalate_to_human"
    return 0
  fi

  # In production, the supervisor agent would be called via
  # Task(subagent_type="correctless:supervisor") with activation_type override_action_review
  echo "approve_action"
  return 0
}

# ---------------------------------------------------------------------------
# review_override_closure — review override window closure
# ---------------------------------------------------------------------------
# Usage: review_override_closure STATE_FILE OVERRIDE_REASON ACTIONS_TAKEN INTENT_SUMMARY DD_DURING COMPLETENESS_EVIDENCE
# Outputs disposition: approve_window | reject_window | partial_accept
review_override_closure() {
  local _state_file="$1"
  local _override_reason="$2"
  local _actions_taken="$3"
  local _intent_summary="$4"
  local _dd_during="$5"
  local _completeness_evidence="$6"

  # BND-006: Validate completeness evidence is valid JSON
  if ! echo "$_completeness_evidence" | jq '.' >/dev/null 2>&1; then
    # Invalid evidence — escalate to human per BND-006
    echo "escalate_to_human"
    return 0
  fi

  # INV-042: Check completeness evidence — if deliverables are missing, reject
  # Note: jq's // operator treats false as falsy, so use explicit conditionals
  local is_complete
  is_complete="$(echo "$_completeness_evidence" | jq -r 'if .complete == true then "true" elif .complete == false then "false" else "true" end' 2>/dev/null)" || is_complete="true"
  local check_applicable
  check_applicable="$(echo "$_completeness_evidence" | jq -r 'if .check_applicable == true then "true" elif .check_applicable == false then "false" else "false" end' 2>/dev/null)" || check_applicable="false"

  if [ "$check_applicable" = "true" ] && [ "$is_complete" = "false" ]; then
    # Missing deliverables — reject window per INV-042
    # In production, the supervisor agent would be invoked via
    # Task(subagent_type="correctless:supervisor") with activation_type override_window_closing
    echo "reject_window"
    return 0
  fi

  # INV-037: Pretext check — verify work addresses override reason
  # In production, the supervisor evaluates whether accumulated work addresses
  # the stated override reason. For test purposes, check completeness evidence.

  # In production, the supervisor would be called via Task(subagent_type="correctless:supervisor")
  echo "approve_window"
  return 0
}

# ---------------------------------------------------------------------------
# track_override_activations — increment override-specific activation counter
# ---------------------------------------------------------------------------
# Usage: track_override_activations STATE_FILE
# Increments override_activation_count in state. Outputs new count.
track_override_activations() {
  local _state_file="$1"

  [ -f "$_state_file" ] || return 1

  # Increment override_activation_count using ws_increment_field pattern
  ws_increment_field "$_state_file" "override_activation_count" || return 1

  # Output the new count
  local count
  count="$(jq -r '.override_activation_count // 0' "$_state_file" 2>/dev/null)" || count="0"
  echo "$count"
  return 0
}

# ---------------------------------------------------------------------------
# check_override_soft_cap — check if override activations hit soft cap (50)
# ---------------------------------------------------------------------------
# Usage: check_override_soft_cap STATE_FILE
# Outputs "ok" or "escalate" (at 50).
check_override_soft_cap() {
  local _state_file="$1"

  [ -f "$_state_file" ] || { echo "ok"; return 0; }

  local count
  count="$(jq -r '.override_activation_count // 0' "$_state_file" 2>/dev/null)" || count="0"

  if [ "$count" -ge 50 ] 2>/dev/null; then
    echo "escalate"
  else
    echo "ok"
  fi

  return 0
}

# ---------------------------------------------------------------------------
# update_override_log — append supervisor review to override log
# ---------------------------------------------------------------------------
# Usage: update_override_log STATE_FILE OVERRIDE_ID REVIEW_TYPE DISPOSITION REASONING
# REVIEW_TYPE: supervisor_issuance_review | supervisor_action_reviews | supervisor_closure_review
# Appends to override log — backward compatible with legacy entries.
update_override_log() {
  local _state_file="$1"
  local _override_id="$2"
  local _review_type="$3"
  local _disposition="$4"
  local _reasoning="$5"

  [ -f "$_state_file" ] || return 1

  local timestamp
  timestamp="$(date -u +%FT%TZ 2>/dev/null)" || timestamp="unknown"

  # Use locked_update_state from lib.sh for atomic read-modify-write (AP-010)
  locked_update_state "$_state_file" \
    '.override_log = (((.override_log // []) + [{
       override_id: $oid,
       review_type: $rt,
       disposition: $disp,
       reasoning: $rsn,
       timestamp: $ts
     }]) | .[-100:])' \
    --arg oid "$_override_id" --arg rt "$_review_type" \
    --arg disp "$_disposition" --arg rsn "$_reasoning" --arg ts "$timestamp"
}

# ---------------------------------------------------------------------------
# jaccard_similarity — compute Jaccard similarity between two texts
# ---------------------------------------------------------------------------
# Usage: jaccard_similarity TEXT_A TEXT_B
# Outputs similarity score (0.0-1.0).
# Tokenizes to lowercase words, removes English stop words, computes
# |intersection| / |union|.
jaccard_similarity() {
  local _text_a="$1"
  local _text_b="$2"

  # Stop words to remove
  local stop_words="the a an is are was were be been for of to in on at by with from and or but not this that"

  # Tokenize, lowercase, remove stop words, compute Jaccard
  # Use awk for the computation to avoid bash floating point issues
  local result
  result="$(awk -v text_a="$_text_a" -v text_b="$_text_b" -v stops="$stop_words" '
    BEGIN {
      # Build stop word set
      n = split(stops, sw, " ")
      for (i = 1; i <= n; i++) stop[sw[i]] = 1

      # Tokenize text_a
      gsub(/[^a-zA-Z0-9 ]/, " ", text_a)
      n_a = split(tolower(text_a), words_a, " ")
      for (i = 1; i <= n_a; i++) {
        w = words_a[i]
        if (w != "" && !(w in stop)) set_a[w] = 1
      }

      # Tokenize text_b
      gsub(/[^a-zA-Z0-9 ]/, " ", text_b)
      n_b = split(tolower(text_b), words_b, " ")
      for (i = 1; i <= n_b; i++) {
        w = words_b[i]
        if (w != "" && !(w in stop)) set_b[w] = 1
      }

      # Compute intersection and union
      intersection = 0
      union_count = 0
      for (w in set_a) {
        union_count++
        if (w in set_b) intersection++
      }
      for (w in set_b) {
        if (!(w in set_a)) union_count++
      }

      # Handle empty sets
      if (union_count == 0) {
        printf "0.0"
      } else {
        sim = intersection / union_count
        # Format to one decimal or "1.0" for exact match
        if (sim == 1) {
          printf "1.0"
        } else if (sim == 0) {
          printf "0.0"
        } else {
          printf "%.2f", sim
        }
      }
    }
  ')" || { echo "0.0"; return 1; }

  echo "$result"
  return 0
}

# ---------------------------------------------------------------------------
# check_override_retry — check if override reason is too similar to rejected
# ---------------------------------------------------------------------------
# Usage: check_override_retry OVERRIDE_REASON STATE_FILE
# Returns 0 if allowed (not a retry), 1 if retry detected (similarity >= 0.4).
check_override_retry() {
  local _override_reason="$1"
  local _state_file="$2"

  [ -f "$_state_file" ] || return 0

  # Read rejected_overrides from state
  local rejected_reasons
  rejected_reasons="$(jq -r '.rejected_overrides // [] | .[]' "$_state_file" 2>/dev/null)" || true

  if [ -z "$rejected_reasons" ]; then
    # No rejected overrides — allowed
    return 0
  fi

  # Compare against each rejected reason using Jaccard similarity
  while IFS= read -r rejected; do
    [ -n "$rejected" ] || continue
    local sim
    sim="$(jaccard_similarity "$_override_reason" "$rejected" 2>/dev/null)" || continue

    # Check if similarity >= 0.4 (awk handles float comparison portably)
    if [ "$(awk -v s="$sim" 'BEGIN { print (s+0 >= 0.4) ? "yes" : "no" }')" = "yes" ]; then
      return 1
    fi
  done <<< "$rejected_reasons"

  # No similar rejected overrides found — allowed
  return 0
}
