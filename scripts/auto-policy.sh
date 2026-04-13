#!/usr/bin/env bash
# Correctless — Auto-policy engine for Tier 0 evaluation
# Deterministic, config-driven policy matching (no LLM reasoning).

# No set -euo pipefail — this file is sourced by other scripts

# Source lib.sh for shared utilities (sha256_hash_file).
# Source at top level (not inside functions) to avoid RETURN trap interaction.
_AUTO_POLICY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || true)"
if [ -n "$_AUTO_POLICY_DIR" ] && [ -f "$_AUTO_POLICY_DIR/lib.sh" ]; then
  # shellcheck source=lib.sh
  source "$_AUTO_POLICY_DIR/lib.sh"
fi
unset _AUTO_POLICY_DIR

# ---------------------------------------------------------------------------
# policy_parse — parse auto-policy.json, return parsed structure or error
# ---------------------------------------------------------------------------
# Usage: policy_parse POLICY_FILE
# Returns the parsed JSON to stdout, or empty string + warning on failure.
policy_parse() {
  local policy_file="$1"

  if [ ! -f "$policy_file" ]; then
    echo "WARNING: auto-policy.json is absent — all decisions will route to Tier 1+." >&2
    echo ""
    return 1
  fi

  local parsed
  parsed="$(jq '.' "$policy_file" 2>/dev/null)" || parsed=""

  if [ -z "$parsed" ]; then
    echo "WARNING: auto-policy.json is empty or malformed — all decisions will route to Tier 1+." >&2
    echo ""
    return 1
  fi

  echo "$parsed"
  return 0
}

# ---------------------------------------------------------------------------
# policy_evaluate — evaluate a DR-xxx against the policy, return disposition
# ---------------------------------------------------------------------------
# Usage: policy_evaluate POLICY_FILE DR_JSON PHASE [STORED_HASH]
# Returns: disposition string or "no_match"
# If STORED_HASH is provided, verifies policy hash first (INV-018).
# Exit code 2 = hash mismatch (tamper detected).
policy_evaluate() {
  local policy_file="$1"
  local dr_json="$2"
  local phase="$3"
  local stored_hash="${4:-}"

  # INV-018: Hash verification if stored hash provided
  if [ -n "$stored_hash" ]; then
    local current_hash
    current_hash="$(policy_hash "$policy_file" 2>/dev/null)" || true
    if [ -n "$current_hash" ] && [ "$current_hash" != "$stored_hash" ]; then
      echo "hash_mismatch" >&2
      return 2
    fi
  fi

  # Parse policy (BND-001: handles malformed/absent/empty)
  local parsed
  if ! parsed="$(policy_parse "$policy_file" 2>/dev/null)" || [ -z "$parsed" ]; then
    echo "no_match"
    return 0
  fi

  # Extract category from DR-xxx (AP-010: use --arg for safety)
  local category
  category="$(echo "$dr_json" | jq -r '.category // empty' 2>/dev/null)" || true

  if [ -z "$category" ]; then
    echo "no_match"
    return 0
  fi

  # First-match-wins: check phase-specific sections in order
  local disposition=""

  case "$phase" in
    review|review-spec)
      disposition="$(echo "$parsed" | jq -r --arg cat "$category" \
        '.review_dispositions[$cat] // .review_dispositions.default // empty' 2>/dev/null)" || true
      ;;
    qa|tdd-qa)
      disposition="$(echo "$parsed" | jq -r --arg cat "$category" \
        '.qa_dispositions[$cat] // empty' 2>/dev/null)" || true
      # Handle complex objects (medium has fix_under_loc/defer_over_loc)
      if echo "$disposition" | jq '.' >/dev/null 2>&1 && [ "$(echo "$disposition" | jq 'type' 2>/dev/null)" = '"object"' ]; then
        disposition="tier2_decide"
      fi
      ;;
    verify|done|verified|tdd-verify)
      disposition="$(echo "$parsed" | jq -r --arg cat "$category" \
        '.drift[$cat] // empty' 2>/dev/null)" || true
      ;;
    spec|spec-update)
      local spec_update
      spec_update="$(echo "$parsed" | jq -r \
        '.spec_update // empty' 2>/dev/null)" || true
      # spec_update is an object, not a direct disposition — route to Tier 2
      if [ -n "$spec_update" ] && [ "$spec_update" != "null" ]; then
        disposition="tier2_decide"
      fi
      ;;
  esac

  if [ -n "$disposition" ] && [ "$disposition" != "null" ]; then
    echo "$disposition"
  else
    echo "no_match"
  fi
  return 0
}

# ---------------------------------------------------------------------------
# policy_validate_tier2 — post-Tier-2 validation pass (INV-012)
# ---------------------------------------------------------------------------
# Usage: policy_validate_tier2 POLICY_FILE DR_JSON TIER2_DISPOSITION [STORED_HASH]
# Returns: "pass", "conflict", or "tamper"
# QA-003 / INV-018: If STORED_HASH is provided, re-verifies policy hash.
policy_validate_tier2() {
  local policy_file="$1"
  local dr_json="$2"
  local tier2_disposition="$3"
  local stored_hash="${4:-}"

  # Extract phase from DR-xxx
  local phase
  phase="$(echo "$dr_json" | jq -r '.phase // "review"' 2>/dev/null)" || phase="review"

  # Run the same deterministic evaluation as pre-routing, forwarding stored_hash
  # so policy_evaluate re-verifies hash (INV-018 TOCTOU prevention).
  local policy_disposition
  if [ -n "$stored_hash" ]; then
    policy_disposition="$(policy_evaluate "$policy_file" "$dr_json" "$phase" "$stored_hash" 2>/dev/null)"
    local eval_rc=$?
    # Exit code 2 from policy_evaluate = hash mismatch (tamper detected)
    if [ "$eval_rc" -eq 2 ]; then
      echo "tamper"
      return 0
    fi
  else
    policy_disposition="$(policy_evaluate "$policy_file" "$dr_json" "$phase" 2>/dev/null)" || true
  fi

  # If policy returns no_match, no contradiction possible — pass
  if [ "$policy_disposition" = "no_match" ] || [ -z "$policy_disposition" ]; then
    echo "pass"
    return 0
  fi

  # Compare Tier 2 disposition against policy disposition
  if [ "$tier2_disposition" = "$policy_disposition" ]; then
    echo "pass"
  else
    echo "conflict"
  fi
  return 0
}

# ---------------------------------------------------------------------------
# policy_hash — compute SHA-256 hash of the policy file
# ---------------------------------------------------------------------------
# Usage: policy_hash POLICY_FILE
# Delegates to sha256_hash_file in lib.sh for the cross-platform fallback chain.
policy_hash() {
  sha256_hash_file "$1"
}
