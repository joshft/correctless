#!/usr/bin/env bash
# Correctless — Auto Run Report generation
# Generates the structured report on pipeline completion or pause.

# No set -euo pipefail — this file is sourced by other scripts

# Source decision-record.sh for dr_hedging_scan() (QA-006).
# Source at top level, not inside functions, to avoid RETURN trap interaction.
_AUTO_REPORT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || true)"
if [ -n "$_AUTO_REPORT_DIR" ] && [ -f "$_AUTO_REPORT_DIR/decision-record.sh" ]; then
  # shellcheck source=decision-record.sh
  source "$_AUTO_REPORT_DIR/decision-record.sh"
fi
unset _AUTO_REPORT_DIR

# ---------------------------------------------------------------------------
# report_generate — generate the full Auto Run Report
# ---------------------------------------------------------------------------
# Usage: report_generate ARTIFACTS_DIR SLUG STATUS
# STATUS: COMPLETE | PAUSED | BUDGET_EXCEEDED | TIME_EXCEEDED
# Outputs the report markdown to stdout (INV-009).
report_generate() {
  local artifacts_dir="$1"
  local slug="$2"
  local status="$3"

  local state_file="$artifacts_dir/state.json"
  local record_file="$artifacts_dir/decision-record.md"
  local token_log="$artifacts_dir/token-log.jsonl"

  # Read state for timestamps
  local start_time="unknown"
  local end_time
  end_time="$(date -u +%FT%TZ)"

  if [ -f "$state_file" ]; then
    start_time="$(jq -r '.pipeline_start_time // "unknown"' "$state_file" 2>/dev/null)" || start_time="unknown"
  fi

  # Calculate duration (GNU date -d, then macOS date -jf fallback)
  local duration="unknown"
  if [ "$start_time" != "unknown" ]; then
    local start_epoch
    start_epoch="$(date -d "$start_time" +%s 2>/dev/null)" \
      || start_epoch="$(date -jf "%Y-%m-%dT%H:%M:%SZ" "$start_time" +%s 2>/dev/null)" \
      || start_epoch=0
    if [ "$start_epoch" -gt 0 ]; then
      local diff_seconds=$(( $(date +%s) - start_epoch ))
      local hours=$(( diff_seconds / 3600 ))
      local minutes=$(( (diff_seconds % 3600) / 60 ))
      duration="${hours}h ${minutes}m"
    fi
  fi

  # Token usage
  local token_usage="unknown"
  if [ -f "$token_log" ]; then
    # ABS-006: jq -R + try/catch for JSONL — never jq -s (QA-001).
    token_usage="$(jq -R 'try (fromjson | .total_tokens // 0) catch 0' "$token_log" 2>/dev/null \
      | jq -s 'add // 0' 2>/dev/null)" || token_usage="unknown"
  fi

  # Decision summary
  local decision_summary=""
  if [ -f "$record_file" ]; then
    decision_summary="$(report_section_decisions "$record_file" 2>/dev/null)" || decision_summary="No decisions recorded."
  fi

  # QA-006: Populate "Decisions Requiring Human Review" from hedging scan + ASSUMPTION tags
  local human_review_section=""
  if [ -f "$record_file" ]; then
    # Hedging scan: find entries with hedging language but no ASSUMPTION tag
    local hedging_ids=""
    if command -v dr_hedging_scan >/dev/null 2>&1; then
      hedging_ids="$(dr_hedging_scan "$record_file" 2>/dev/null)" || true
    fi

    # ASSUMPTION-tagged entries
    local assumption_ids=""
    assumption_ids="$(grep -o 'DD-[0-9]*' "$record_file" 2>/dev/null | sort -u | while read -r dd_id; do
      # Check if the block for this DD-xxx contains ASSUMPTION
      if awk "/^### ${dd_id}\$/,/^### DD-/" "$record_file" 2>/dev/null | grep -qF 'ASSUMPTION'; then
        echo "$dd_id"
      fi
    done)" || true

    # Build section content
    if [ -n "$hedging_ids" ] || [ -n "$assumption_ids" ]; then
      if [ -n "$hedging_ids" ]; then
        human_review_section="${human_review_section}### Untagged Hedging Language Detected"$'\n\n'
        while IFS= read -r hid; do
          [ -n "$hid" ] && human_review_section="${human_review_section}- ${hid}"$'\n'
        done <<< "$hedging_ids"
        human_review_section="${human_review_section}"$'\n'
      fi
      if [ -n "$assumption_ids" ]; then
        human_review_section="${human_review_section}### ASSUMPTION-Tagged Entries"$'\n\n'
        while IFS= read -r aid; do
          [ -n "$aid" ] && human_review_section="${human_review_section}- ${aid}"$'\n'
        done <<< "$assumption_ids"
      fi
    else
      human_review_section="No decisions flagged for human review."
    fi
  else
    human_review_section="No decision record available."
  fi

  # QA-006: Populate Spec Summary from state file
  local spec_summary="No spec data available."
  if [ -f "$state_file" ]; then
    local phase rules_count
    phase="$(jq -r '.phase // "unknown"' "$state_file" 2>/dev/null)" || phase="unknown"
    rules_count="$(jq -r '.rules_count // "unknown"' "$state_file" 2>/dev/null)" || rules_count="unknown"
    spec_summary="Current phase: ${phase}. Rules tracked: ${rules_count}."
  fi

  # QA-006: Populate Implementation Summary from state file
  local impl_summary="No implementation data available."
  if [ -f "$state_file" ]; then
    local supervisor_count dr_size
    supervisor_count="$(jq -r '.supervisor_activation_count // 0' "$state_file" 2>/dev/null)" || supervisor_count="0"
    dr_size="$(jq -r '.decision_record_size // 0' "$state_file" 2>/dev/null)" || dr_size="0"
    impl_summary="Supervisor activations: ${supervisor_count}. Decision record size: ${dr_size} bytes."
  fi

  # QA-006: Populate Verification Summary from state file
  local verify_summary="No verification data available."
  if [ -f "$state_file" ]; then
    local verified_phase
    verified_phase="$(jq -r '.phase // "unknown"' "$state_file" 2>/dev/null)" || verified_phase="unknown"
    if [ "$verified_phase" = "documented" ] || [ "$verified_phase" = "done" ] || [ "$verified_phase" = "verified" ]; then
      verify_summary="Verification completed at phase: ${verified_phase}."
    else
      verify_summary="Pipeline at phase: ${verified_phase}. Verification not yet reached."
    fi
  fi

  # Harness warning section (INV-016 of harness-fingerprint spec) — surface any
  # `harness-notified-*.flag` files emitted during the /cauto run so the human
  # reviewer sees the warning in the Auto Run Report's "What to Review First".
  local harness_warning_section=""
  local artifacts_root=".correctless/artifacts"
  if compgen -G "${artifacts_root}/harness-notified-*.flag" >/dev/null 2>&1; then
    harness_warning_section="4. **Harness change detected during run**: harness-fingerprint reported version_bumped at least once. Run \`/cmodelupgrade\` to compare metrics against baseline before merging."
  fi

  # Output the report
  cat << REPORT_EOF
# Auto Run Report

## Feature

${slug}

## Branch

${slug}

## Timestamps

- **Start**: ${start_time}
- **End**: ${end_time}
- **Duration**: ${duration}

## Token Cost

Token usage: ${token_usage}

## Status

${status}

## Decision Summary

${decision_summary}

## Decisions Requiring Human Review

${human_review_section}

## Spec Summary

${spec_summary}

## Implementation Summary

${impl_summary}

## Verification Summary

${verify_summary}

## What to Review First

1. Check all ASSUMPTION-tagged decisions
2. Review supervisor-flagged concerns
3. Verify test coverage for new code
${harness_warning_section}
REPORT_EOF

  return 0
}

# ---------------------------------------------------------------------------
# report_section_decisions — generate decision summary section
# ---------------------------------------------------------------------------
# Usage: report_section_decisions RECORD_FILE
# Summarizes decisions by tier count.
report_section_decisions() {
  local record_file="$1"

  if [ ! -f "$record_file" ]; then
    echo "No decision record found."
    return 0
  fi

  # Count entries by tier — single awk pass instead of 7 separate greps
  local tier0_count=0 tier1_count=0 tier2_count=0 tier3_count=0
  local system_count=0 human_count=0 total_count=0
  eval "$(awk '
    /^### DD-/ { total++ }
    /Tier.*: 0/      { t0++ }
    /Tier.*: 1/      { t1++ }
    /Tier.*: 2/      { t2++ }
    /Tier.*: 3/      { t3++ }
    /Tier.*: system/ { sys++ }
    /Tier.*: human/  { hum++ }
    END {
      printf "tier0_count=%d tier1_count=%d tier2_count=%d tier3_count=%d ", t0+0, t1+0, t2+0, t3+0
      printf "system_count=%d human_count=%d total_count=%d", sys+0, hum+0, total+0
    }
  ' "$record_file" 2>/dev/null)" || true

  cat << SUMMARY_EOF
Total decisions: ${total_count}

- Tier 0 (Policy): ${tier0_count}
- Tier 1 (Worker): ${tier1_count}
- Tier 2 (Decision Agent): ${tier2_count}
- Tier 3 (Supervisor): ${tier3_count}
- System: ${system_count}
- Human: ${human_count}
SUMMARY_EOF
}

# ---------------------------------------------------------------------------
# report_section_implementation — generate implementation summary section
# ---------------------------------------------------------------------------
# Usage: report_section_implementation ARTIFACTS_DIR
report_section_implementation() {
  local artifacts_dir="$1"
  local state_file="$artifacts_dir/state.json"

  if [ ! -f "$state_file" ]; then
    echo "No implementation data available."
    return 0
  fi

  local supervisor_count dr_size
  supervisor_count="$(jq -r '.supervisor_activation_count // 0' "$state_file" 2>/dev/null)" || supervisor_count="0"
  dr_size="$(jq -r '.decision_record_size // 0' "$state_file" 2>/dev/null)" || dr_size="0"
  echo "Supervisor activations: ${supervisor_count}. Decision record size: ${dr_size} bytes."
}

# ---------------------------------------------------------------------------
# Phase 3 extensions
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# report_section_review_triage — generate review triage summary section
# ---------------------------------------------------------------------------
# Usage: report_section_review_triage REVIEW_DECISIONS_FILE
# Outputs markdown section with findings by source agent, accept/reject/hard_stop
# counts, rejected findings with supervisor reasoning.
report_section_review_triage() {
  local _review_decisions_file="$1"

  if [ ! -f "$_review_decisions_file" ]; then
    echo "## Review Triage"
    echo ""
    echo "No review decisions file found."
    return 0
  fi

  # Count decisions by type — single jq pass (PAT-010: explicit parens for as bindings)
  local accept_count=0 reject_count=0 hard_stop_count=0 total_count=0
  eval "$(jq -r '
    (length) as $total |
    ([.[] | select(.supervisor_decision == "accept")] | length) as $accept |
    ([.[] | select(.supervisor_decision == "reject")] | length) as $reject |
    ([.[] | select(.supervisor_decision == "hard_stop")] | length) as $hs |
    @sh "total_count=\($total) accept_count=\($accept) reject_count=\($reject) hard_stop_count=\($hs)"
  ' "$_review_decisions_file" 2>/dev/null)" || true

  echo "## Review Triage"
  echo ""
  echo "Total findings: ${total_count}"
  echo "- accept: ${accept_count}"
  echo "- reject: ${reject_count}"
  echo "- hard_stop: ${hard_stop_count}"
  echo ""

  # List rejected findings with reasoning
  if [ "$reject_count" -gt 0 ] 2>/dev/null; then
    echo "### Rejected Findings"
    echo ""
    jq -r '.[] | select(.supervisor_decision == "reject") | "- **\(.finding_id)**: \(.finding_summary // .summary // "unknown") — Reasoning: \(.supervisor_reasoning // "none")"' \
      "$_review_decisions_file" 2>/dev/null || true
    echo ""
  fi

  # List hard_stop findings
  if [ "$hard_stop_count" -gt 0 ] 2>/dev/null; then
    echo "### Hard-Stopped Findings"
    echo ""
    jq -r '.[] | select(.supervisor_decision == "hard_stop") | "- **\(.finding_id)**: \(.finding_summary // .summary // "unknown")"' \
      "$_review_decisions_file" 2>/dev/null || true
    echo ""
  fi

  return 0
}

# ---------------------------------------------------------------------------
# report_section_override_scrutiny — generate override scrutiny summary section
# ---------------------------------------------------------------------------
# Usage: report_section_override_scrutiny STATE_FILE
# Outputs markdown section with override window activity, dispositions,
# scope drift flags, and override activation counter.
report_section_override_scrutiny() {
  local _state_file="$1"

  if [ ! -f "$_state_file" ]; then
    echo "## Override Scrutiny"
    echo ""
    echo "No state file found."
    return 0
  fi

  local activation_count
  activation_count="$(jq -r '.override_activation_count // 0' "$_state_file" 2>/dev/null)" || activation_count="0"

  echo "## Override Scrutiny"
  echo ""
  echo "Override window activations: ${activation_count}"
  echo ""

  # List override log entries
  local log_length
  log_length="$(jq '.override_log // [] | length' "$_state_file" 2>/dev/null)" || log_length="0"

  if [ "$log_length" -gt 0 ] 2>/dev/null; then
    echo "### Override Log"
    echo ""
    jq -r '.override_log // [] | .[] | "- **\(.override_id // "unknown")** [\(.review_type // "unknown")]: \(.disposition // "unknown") — \(.reasoning // "")"' \
      "$_state_file" 2>/dev/null || true
    echo ""
  fi

  return 0
}
