#!/usr/bin/env bash
# Correctless — Override cross-check functions for Auto Mode Phase 3
# Handles base-commit cross-check for "pre-existing" claims,
# file-touch scope drift detection, and spec completeness parsing.

# No set -euo pipefail — this file is sourced by other scripts

# Source lib.sh for shared utilities.
# Source at top level (not inside functions) to avoid RETURN trap interaction.
_OVERRIDE_CROSSCHECK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || true)"
if [ -n "$_OVERRIDE_CROSSCHECK_DIR" ] && [ -f "$_OVERRIDE_CROSSCHECK_DIR/lib.sh" ]; then
  # shellcheck source=lib.sh
  source "$_OVERRIDE_CROSSCHECK_DIR/lib.sh"
fi
unset _OVERRIDE_CROSSCHECK_DIR

# ---------------------------------------------------------------------------
# detect_pre_existing_claim — check if override reason claims pre-existing error
# ---------------------------------------------------------------------------
# Usage: detect_pre_existing_claim OVERRIDE_REASON
# Returns 0 if claim detected (controlled vocabulary match), 1 if not.
# Outputs matched keywords to stdout.
# Controlled vocabulary: "pre-existing", "not caused by", "already present",
# "existed before", "upstream issue"
detect_pre_existing_claim() {
  local _override_reason="$1"

  local reason_lower="${_override_reason,,}"
  local matched=""
  local phrase

  for phrase in "pre-existing" "not caused by" "already present" "existed before" "upstream issue"; do
    if echo "$reason_lower" | grep -qF "$phrase"; then
      matched="${matched}${phrase} "
    fi
  done

  if [ -n "$matched" ]; then
    echo "$matched"
    return 0
  fi

  return 1
}

# ---------------------------------------------------------------------------
# base_commit_crosscheck — verify "pre-existing" claim against base commit
# ---------------------------------------------------------------------------
# Usage: base_commit_crosscheck CONFIG_FILE
# Outputs cross-check evidence JSON:
#   {"pre_existing_claimed":bool,"base_commit":"...","base_build_success":bool,
#    "base_build_exit_code":N,"base_build_stderr":"...","claim_verified":bool|null,
#    "failure_mode":null|"..."}
base_commit_crosscheck() {
  local _config_file="$1"

  # Read test command from config
  local test_cmd=""
  local test_timeout=120
  if [ -f "$_config_file" ]; then
    test_cmd="$(jq -r '.commands.test // ""' "$_config_file" 2>/dev/null)" || test_cmd=""
    test_timeout="$(jq -r '.commands.test_timeout // 120' "$_config_file" 2>/dev/null)" || test_timeout=120
  fi

  # BND-007 failure mode (c): no test command configured
  if [ -z "$test_cmd" ] || [ "$test_cmd" = "null" ]; then
    jq -n '{
      pre_existing_claimed: false,
      base_commit: null,
      base_build_success: false,
      base_build_exit_code: null,
      base_build_stderr: "",
      claim_verified: null,
      failure_mode: "no_test_command"
    }'
    return 0
  fi

  # Run git commands from the config file's directory context
  # This ensures BND-007 tests (config in /tmp = no git) work correctly
  local config_dir
  config_dir="$(cd "$(dirname "$_config_file")" 2>/dev/null && pwd)" || config_dir="."

  # BND-007 failure mode (a): get base commit via git merge-base
  local base_commit
  base_commit="$(cd "$config_dir" && git merge-base main HEAD 2>/dev/null)" || true

  if [ -z "$base_commit" ]; then
    # Try master if main doesn't exist
    base_commit="$(cd "$config_dir" && git merge-base master HEAD 2>/dev/null)" || true
  fi

  if [ -z "$base_commit" ]; then
    jq -n '{
      pre_existing_claimed: false,
      base_commit: null,
      base_build_success: false,
      base_build_exit_code: null,
      base_build_stderr: "",
      claim_verified: null,
      failure_mode: "merge_base_failed"
    }'
    return 0
  fi

  # BND-007 failure mode (b): create temporary worktree
  local worktree_dir
  worktree_dir="$(mktemp -d)" || {
    jq -n --arg bc "$base_commit" '{
      pre_existing_claimed: false,
      base_commit: $bc,
      base_build_success: false,
      base_build_exit_code: null,
      base_build_stderr: "",
      claim_verified: null,
      failure_mode: "worktree_creation_failed"
    }'
    return 0
  }

  # Clean up worktree on exit
  local worktree_path="${worktree_dir}/crosscheck"

  # QA-005: trap for worktree cleanup on signal/abnormal exit
  # shellcheck disable=SC2064
  trap "$(printf '(cd %q && git worktree remove --force %q 2>/dev/null) || true; rm -rf %q 2>/dev/null' "$config_dir" "$worktree_path" "$worktree_dir")" EXIT SIGTERM SIGINT

  if ! (cd "$config_dir" && git worktree add -q "$worktree_path" "$base_commit" 2>/dev/null); then
    trap - EXIT SIGTERM SIGINT
    rm -rf "$worktree_dir"
    jq -n --arg bc "$base_commit" '{
      pre_existing_claimed: false,
      base_commit: $bc,
      base_build_success: false,
      base_build_exit_code: null,
      base_build_stderr: "",
      claim_verified: null,
      failure_mode: "worktree_add_failed"
    }'
    return 0
  fi

  # Run the test command in the worktree with timeout
  local build_exit_code=0
  local build_stderr=""

  build_stderr="$(cd "$worktree_path" && timeout "$test_timeout" bash -c "$test_cmd" 2>&1)" || build_exit_code=$?

  # BND-007 failure mode (d): timeout check
  local failure_mode_val="null"
  if [ "$build_exit_code" -eq 124 ] 2>/dev/null; then
    failure_mode_val="timeout"
  fi

  local build_success="false"
  [ "$build_exit_code" -eq 0 ] && build_success="true"

  # Clean up worktree (trap handles abnormal exit; explicit cleanup for normal path)
  (cd "$config_dir" && git worktree remove --force "$worktree_path" 2>/dev/null) || true
  rm -rf "$worktree_dir" 2>/dev/null || true
  trap - EXIT SIGTERM SIGINT

  # Determine claim_verified: if build fails on base, the claim might be true
  # If build succeeds on base, the pre-existing claim is false
  # QA-014: timeout is inconclusive (null), not disconfirmed (false)
  local claim_verified="false"
  if [ "$build_success" = "false" ] && [ "$failure_mode_val" = "null" ]; then
    claim_verified="true"
  elif [ "$failure_mode_val" != "null" ]; then
    # Timeout or other non-clean failure — inconclusive
    claim_verified="null"
  fi

  jq -n --arg bc "$base_commit" \
    --argjson success "$build_success" \
    --argjson exit_code "$build_exit_code" \
    --arg stderr "$build_stderr" \
    --arg verified "$claim_verified" \
    --arg fm "$failure_mode_val" \
    '{
      pre_existing_claimed: false,
      base_commit: $bc,
      base_build_success: $success,
      base_build_exit_code: $exit_code,
      base_build_stderr: $stderr,
      claim_verified: (if $verified == "null" then null elif $verified == "true" then true else false end),
      failure_mode: (if $fm == "null" then null else $fm end)
    }'

  return 0
}

# ---------------------------------------------------------------------------
# detect_file_touch_drift — compare touched files against override scope
# ---------------------------------------------------------------------------
# Usage: detect_file_touch_drift TOUCHED_FILES OVERRIDE_REASON SPEC_FILE INTENT_SUMMARY
# TOUCHED_FILES: JSON array of file paths
# Outputs drift evidence JSON:
#   {"touched_files":[...],"in_scope_files":[...],"out_of_scope_files":[...],
#    "scope_drift_detected":bool}
detect_file_touch_drift() {
  local _touched_files="$1"
  local _override_reason="$2"
  local _spec_file="$3"
  local _intent_summary="$4"

  # Build scope sets from override reason, spec, and intent
  local scope_files=""

  # Extract file paths from override reason
  local reason_files
  reason_files="$(echo "$_override_reason" | grep -oE '[a-zA-Z0-9_./-]+\.(go|py|ts|js|md|sh|json|yaml|toml|rs)' 2>/dev/null)" || true
  scope_files="${scope_files} ${reason_files}"

  # Extract file paths from spec
  if [ -f "$_spec_file" ]; then
    local spec_files
    spec_files="$(grep -oE '[a-zA-Z0-9_./-]+\.(go|py|ts|js|md|sh|json|yaml|toml|rs)' "$_spec_file" 2>/dev/null)" || true
    scope_files="${scope_files} ${spec_files}"
  fi

  # Extract file paths from intent summary
  local intent_files
  intent_files="$(echo "$_intent_summary" | grep -oE '[a-zA-Z0-9_./-]+\.(go|py|ts|js|md|sh|json|yaml|toml|rs)' 2>/dev/null)" || true
  scope_files="${scope_files} ${intent_files}"

  # Build drift evidence using jq
  local result
  result="$(echo "$_touched_files" | jq --arg scope "$scope_files" '
    . as $touched |
    ($scope | split(" ") | map(select(length > 0))) as $scope_set |
    {
      touched_files: $touched,
      in_scope_files: [
        $touched[] | select(
          # Exclude transient files: /tmp paths and *.tmp, *.log
          (startswith("/tmp") | not) and
          (endswith(".tmp") | not) and
          (endswith(".log") | not) and
          # Check if file is in scope
          (. as $f | ($scope_set | any(. == $f)) or
           ($scope_set | any(. as $s | $f | contains($s))) or
           ($scope_set | any(. as $s | $s | contains($f))))
        )
      ],
      out_of_scope_files: [
        $touched[] | select(
          # Exclude transient files first
          (startswith("/tmp") | not) and
          (endswith(".tmp") | not) and
          (endswith(".log") | not)
        ) | select(
          # Not in any scope set
          . as $f |
          ($scope_set | any(. == $f) | not) and
          ($scope_set | any(. as $s | $f | contains($s)) | not) and
          ($scope_set | any(. as $s | $s | contains($f)) | not)
        )
      ]
    } | .scope_drift_detected = (.out_of_scope_files | length > 0)
  ' 2>/dev/null)" || {
    echo '{"touched_files":[],"in_scope_files":[],"out_of_scope_files":[],"scope_drift_detected":false}'
    return 0
  }

  echo "$result"
  return 0
}

# ---------------------------------------------------------------------------
# parse_spec_deliverables — extract declared deliverables from spec
# ---------------------------------------------------------------------------
# Usage: parse_spec_deliverables SPEC_FILE
# Outputs JSON array of file paths extracted from spec sections
# (What lands, In scope, Deliverables). Excludes content inside code blocks.
# Handles markdown links by extracting link text.
parse_spec_deliverables() {
  local _spec_file="$1"

  [ -f "$_spec_file" ] || { echo "[]"; return 0; }

  # Parse markdown sections: "What lands", "In scope", "Deliverables" (case-insensitive)
  # Track fenced code blocks to exclude them
  # Extract file paths from bullet lines
  # Handle markdown links: extract text from [text](url) format
  #
  # Step 1: Pre-process the file to handle markdown links and extract section content
  # Step 2: Extract file paths from the pre-processed content
  local result
  result="$(
    # First pass: extract relevant section content, excluding code blocks
    # and converting markdown links to their text content
    awk '
      BEGIN { in_section = 0; in_code_block = 0; section_level = 0 }

      # Track fenced code blocks
      /^```/ {
        in_code_block = !in_code_block
        next
      }

      # Skip code block content
      in_code_block { next }

      # Detect section headings (case-insensitive)
      /^#{1,6} / {
        heading = tolower($0)
        # Count heading level
        level = 0
        for (i = 1; i <= length($0); i++) {
          if (substr($0, i, 1) == "#") level++
          else break
        }

        if (heading ~ /what lands/ || heading ~ /in scope/ || heading ~ /deliverables/) {
          in_section = 1
          section_level = level
        } else if (in_section && level <= section_level) {
          in_section = 0
        }
        next
      }

      # Process bullet lines within deliverable sections
      in_section && /^[[:space:]]*[-*] / {
        line = $0

        # Handle markdown links: replace [text](url) with just text
        # Use a loop with gsub since awk match() third arg is gawk-only
        while (index(line, "](") > 0) {
          # Find the opening [
          before = ""
          rest = line
          pos = index(rest, "[")
          if (pos == 0) break
          before = substr(rest, 1, pos - 1)
          rest = substr(rest, pos + 1)
          # Find the closing ]
          pos2 = index(rest, "](")
          if (pos2 == 0) break
          link_text = substr(rest, 1, pos2 - 1)
          rest = substr(rest, pos2 + 2)
          # Find the closing )
          pos3 = index(rest, ")")
          if (pos3 == 0) break
          rest = substr(rest, pos3 + 1)
          line = before link_text rest
        }

        print line
      }
    ' "$_spec_file" 2>/dev/null \
    | grep -oE '[a-zA-Z0-9_./-]+\.(go|py|ts|js|md|sh|json|yaml|toml|rs)|Dockerfile' 2>/dev/null \
    | sort -u \
    | jq -R -s 'split("\n") | map(select(length > 0))'
  )" || result="[]"

  echo "$result"
  return 0
}

# ---------------------------------------------------------------------------
# check_spec_completeness — compare deliverables against completed files
# ---------------------------------------------------------------------------
# Usage: check_spec_completeness SPEC_FILE COMPLETED_FILES_JSON
# Outputs completeness evidence JSON:
#   {"declared_deliverables":[...],"completed_deliverables":[...],
#    "missing_deliverables":[...],"check_applicable":bool,"complete":bool}
check_spec_completeness() {
  local _spec_file="$1"
  local _completed_files_json="$2"

  # Parse deliverables from spec
  local deliverables
  deliverables="$(parse_spec_deliverables "$_spec_file" 2>/dev/null)" || deliverables="[]"

  local deliverable_count
  deliverable_count="$(echo "$deliverables" | jq 'length' 2>/dev/null)" || deliverable_count="0"

  # If no deliverables found, check is not applicable
  if [ "$deliverable_count" = "0" ]; then
    jq -n '{
      declared_deliverables: [],
      completed_deliverables: [],
      missing_deliverables: [],
      check_applicable: false,
      complete: true
    }'
    return 0
  fi

  # QA-007: Validate completed_files_json before --argjson (fail-closed on malformed input)
  if ! echo "$_completed_files_json" | jq -e 'type == "array"' >/dev/null 2>&1; then
    # Malformed completed_files — fail-closed: report all deliverables as missing
    jq -n --argjson declared "$deliverables" '{
      declared_deliverables: $declared,
      completed_deliverables: [],
      missing_deliverables: $declared,
      check_applicable: true,
      complete: false
    }'
    return 0
  fi

  # Compare against completed files
  local result
  result="$(jq -n --argjson declared "$deliverables" --argjson completed "$_completed_files_json" '
    {
      declared_deliverables: $declared,
      completed_deliverables: [$declared[] | select(. as $d | $completed | any(. == $d))],
      missing_deliverables: [$declared[] | select(. as $d | $completed | any(. == $d) | not)],
      check_applicable: true
    } | .complete = (.missing_deliverables | length == 0)
  ' 2>/dev/null)" || {
    echo '{"declared_deliverables":[],"completed_deliverables":[],"missing_deliverables":[],"check_applicable":false,"complete":true}'
    return 0
  }

  echo "$result"
  return 0
}
