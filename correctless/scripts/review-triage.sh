#!/usr/bin/env bash
# Correctless — Review triage functions for Auto Mode Phase 3
# Handles supervisor batch triage of review findings, review decisions
# artifact creation, hash verification, and PRH-003 enforcement.

# No set -euo pipefail — this file is sourced by other scripts

# Source lib.sh for shared utilities.
# Source at top level (not inside functions) to avoid RETURN trap interaction.
_REVIEW_TRIAGE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || true)"
if [ -n "$_REVIEW_TRIAGE_DIR" ] && [ -f "$_REVIEW_TRIAGE_DIR/lib.sh" ]; then
  # shellcheck source=lib.sh
  source "$_REVIEW_TRIAGE_DIR/lib.sh"
fi
unset _REVIEW_TRIAGE_DIR

# ---------------------------------------------------------------------------
# parse_review_findings — parse review skill output into structured findings
# ---------------------------------------------------------------------------
# Usage: parse_review_findings INPUT_TEXT
# Outputs JSON array of findings with schema:
#   [{"finding_id":"F-001","source_agent":"...","category":"...","summary":"...","proposed_action":"..."}]
parse_review_findings() {
  local _input_text="$1"

  # Parse structured review findings from review skill output.
  # Look for numbered findings, section headers, and structured blocks.
  # Output JSON array with the review finding schema.
  if [ -z "$_input_text" ]; then
    echo "[]"
    return 0
  fi

  # Extract findings by looking for patterns like "F-NNN:" or "Finding N:"
  # This is a best-effort parser for structured review output.
  local findings="[]"
  local seq=1
  local current_source="" current_category="" current_summary="" current_action=""

  while IFS= read -r line; do
    # Detect source agent headers
    case "${line,,}" in
      *"red-team"*|*"red team"*) current_source="red-team" ;;
      *"assumptions"*) current_source="assumptions" ;;
      *"testability"*) current_source="testability" ;;
      *"design-contract"*|*"design contract"*) current_source="design-contract" ;;
    esac

    # Detect finding lines (numbered or bulleted)
    if echo "$line" | grep -qE '^[0-9]+\.|^- |^\* |^F-[0-9]+'; then
      current_summary="$(echo "$line" | sed 's/^[0-9]*\.[[:space:]]*//;s/^- //;s/^\* //;s/^F-[0-9]*:[[:space:]]*//')"
      if [ -n "$current_summary" ]; then
        local fid
        fid="$(printf 'F-%03d' "$seq")"
        local src="${current_source:-unknown}"
        local cat="${current_category:-assumption}"
        local act="${current_action:-flag_risk}"

        findings="$(echo "$findings" | jq --arg fid "$fid" --arg src "$src" \
          --arg cat "$cat" --arg sum "$current_summary" --arg act "$act" \
          '. + [{"finding_id":$fid,"source_agent":$src,"category":$cat,"summary":$sum,"proposed_action":$act}]' 2>/dev/null)" || true
        seq=$((seq + 1))
      fi
    fi
  done <<< "$_input_text"

  echo "$findings"
  return 0
}

# ---------------------------------------------------------------------------
# create_review_decisions — write review decisions artifact
# ---------------------------------------------------------------------------
# Usage: create_review_decisions ARTIFACTS_DIR BRANCH_SLUG DECISIONS_JSON
# Creates .correctless/artifacts/review-decisions-{branch_slug}.json
# Returns 0 on success.
create_review_decisions() {
  local _artifacts_dir="$1"
  local _branch_slug="$2"
  local _decisions_json="$3"

  local artifact_file="${_artifacts_dir}/review-decisions-${_branch_slug}.json"

  # Use jq to safely write the JSON (AP-010: no string interpolation)
  echo "$_decisions_json" | jq '.' > "$artifact_file" 2>/dev/null || return 1

  return 0
}

# ---------------------------------------------------------------------------
# hash_review_decisions — compute SHA-256 hash of review decisions artifact
# ---------------------------------------------------------------------------
# Usage: hash_review_decisions ARTIFACT_FILE
# Outputs SHA-256 hash to stdout.
hash_review_decisions() {
  sha256_hash_file "$1"
}

# ---------------------------------------------------------------------------
# verify_review_decisions_hash — check artifact integrity
# ---------------------------------------------------------------------------
# Usage: verify_review_decisions_hash ARTIFACT_FILE STORED_HASH
# Returns 0 if hash matches, 1 if mismatch (tampered).
verify_review_decisions_hash() {
  local _artifact_file="$1"
  local _stored_hash="$2"

  [ -f "$_artifact_file" ] || return 1

  local current_hash
  current_hash="$(hash_review_decisions "$_artifact_file")" || return 1

  if [ "$current_hash" = "$_stored_hash" ]; then
    return 0
  else
    echo "ERROR: Review decisions tampered — hash mismatch" >&2
    return 1
  fi
}

# ---------------------------------------------------------------------------
# enforce_prh003 — enforce source agent category constraints on triage
# ---------------------------------------------------------------------------
# Usage: enforce_prh003 SUPERVISOR_RESPONSE FINDINGS_JSON
# Outputs corrected response JSON. Red Team findings forced to hard_stop
# if supervisor returned reject. Security-keyword findings likewise.
enforce_prh003() {
  local _supervisor_response="$1"
  local _findings_json="$2"

  # Security keywords from PRH-001 (security-scan.sh keyword list)
  local security_keywords="auth credential encrypt token secret permission access control trust boundary identity authorization login verification level privilege"

  # QA-004: Cardinality assertion — fail-closed on array length mismatch.
  # If supervisor returned fewer decisions than findings, security findings
  # beyond the response are silently dropped. Iterate over findings length
  # and treat missing decisions as hard_stop for security-tagged findings.
  local result
  result="$(jq -n --argjson resp "$_supervisor_response" --argjson findings "$_findings_json" \
    --arg keywords "$security_keywords" '
    [range($findings | length)] | map(. as $i |
      ($resp[$i] // null) as $decision |
      $findings[$i] as $finding |
      (
        ($finding.source_agent == "red-team") or
        ($finding.category == "security") or
        (
          ($keywords | split(" ")) as $kws |
          (($finding.summary // "") | ascii_downcase) as $summary_lower |
          (($finding.category // "") | ascii_downcase) as $cat_lower |
          any($kws[]; . as $kw | ($summary_lower | contains($kw)) or ($cat_lower | contains($kw)))
        )
      ) as $is_security |
      if $decision == null then
        # R2-F2: missing decision — hard_stop for security, accept for non-security
        if $is_security then {"decision": "hard_stop", "prh003_missing_decision": true}
        else {"decision": "accept", "prh003_missing_decision": true, "reasoning": "Auto-accepted: supervisor returned fewer decisions than findings"}
        end
      elif $is_security and ($decision.decision == "reject") then
        $decision | .decision = "hard_stop" | .prh003_override = true
      else
        $decision
      end
    )
  ' 2>/dev/null)" || { echo "[]"; return 1; }

  echo "$result"
  return 0
}

# ---------------------------------------------------------------------------
# _default_supervisor_triage — pluggable triage function (test default)
# ---------------------------------------------------------------------------
# In tests, returns accept for all findings. In production, SKILL.md
# orchestrator replaces this with Task(subagent_type="correctless:supervisor")
# invocation using activation_type: review_triage.
# Override by defining CORRECTLESS_TRIAGE_FN before sourcing this file.
_default_supervisor_triage() {
  local _findings="$1"
  # Default: accept all findings (test/stub behavior)
  echo "$_findings" | jq '[.[] | {
    finding_id: .finding_id,
    decision: "accept",
    reasoning: "Accepted by default supervisor triage"
  }]' 2>/dev/null || { echo "[]"; return 1; }
}

# ---------------------------------------------------------------------------
# triage_findings_batch — validate, triage via supervisor, enforce PRH-003
# ---------------------------------------------------------------------------
# Usage: triage_findings_batch FINDINGS_JSON
# Outputs JSON array of triage decisions.
# Contract test: validates I/O shape. Supervisor wiring happens in SKILL.md.
triage_findings_batch() {
  local _findings_json="$1"

  # Step 1: Validate input is valid JSON array
  if ! echo "$_findings_json" | jq -e 'type == "array"' >/dev/null 2>&1; then
    echo "[]"
    return 1
  fi

  # Step 2: BND-001 — empty array produces empty decisions
  local count
  count="$(echo "$_findings_json" | jq 'length' 2>/dev/null)" || count="0"
  if [ "$count" = "0" ]; then
    echo "[]"
    return 0
  fi

  # Step 3: Call pluggable supervisor triage function
  # CORRECTLESS_TRIAGE_FN allows production wiring to replace the default stub
  local supervisor_fn="${CORRECTLESS_TRIAGE_FN:-_default_supervisor_triage}"
  local raw_decisions
  raw_decisions="$($supervisor_fn "$_findings_json" 2>/dev/null)" || { echo "[]"; return 1; }

  # Step 4: Apply enforce_prh003 post-processing on supervisor result
  # QA-001: fail-closed — if enforcement fails and security findings exist,
  # force hard_stop on all security-tagged findings instead of passing through raw decisions
  local result
  if ! result="$(enforce_prh003 "$raw_decisions" "$_findings_json" 2>/dev/null)"; then
    # Check if any finding is security-tagged — if so, fail-closed
    local has_security
    has_security="$(echo "$_findings_json" | jq '[.[] | select(
      .source_agent == "red-team" or .category == "security"
    )] | length' 2>/dev/null)" || has_security="0"
    if [ "$has_security" -gt 0 ] 2>/dev/null; then
      # Fail-closed: force hard_stop on all decisions
      # R2-F5: if jq also fails (malformed raw_decisions), return empty array, not raw data
      result="$(echo "$raw_decisions" | jq '[.[] | .decision = "hard_stop" | .prh003_failclosed = true]' 2>/dev/null)" || { echo "[]"; return 1; }
    else
      result="$raw_decisions"
    fi
  fi

  echo "$result"
  return 0
}
