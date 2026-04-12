#!/usr/bin/env bash
# Correctless — Security constraint detection (PRH-001)
# Three-layer detection: category gate, keyword scan, structural guard.

# No set -euo pipefail — this file is sourced by other scripts

# ---------------------------------------------------------------------------
# security_category_gate — check if category is "security"
# ---------------------------------------------------------------------------
# Usage: security_category_gate DR_JSON
# Returns: 0 if security category (must route to Tier 4), 1 if not
# This is PRH-001 layer 1 — hardcoded, applies even with malformed policy.
security_category_gate() {
  local dr_json="$1"

  local category
  category="$(echo "$dr_json" | jq -r '.category // ""' 2>/dev/null)" || true

  if [ "$category" = "security" ]; then
    return 0
  fi
  return 1
}

# ---------------------------------------------------------------------------
# security_keyword_scan — scan summary/reasoning for security terms
# ---------------------------------------------------------------------------
# Usage: security_keyword_scan DR_JSON
# Returns: 0 if security keywords found in non-security category (mismatch), 1 if clean
# Outputs "mismatch" on stdout if mismatch detected (PRH-001 layer 2).
security_keyword_scan() {
  local dr_json="$1"

  local category summary reasoning
  eval "$(echo "$dr_json" | jq -r '
    @sh "category=\(.category // "")",
    @sh "summary=\(.summary // "")",
    @sh "reasoning=\(.reasoning // "")"
  ' 2>/dev/null)" || return 1

  # If category IS security, no mismatch possible
  if [ "$category" = "security" ]; then
    return 1
  fi

  # Combine summary + reasoning for keyword scanning
  local text="${summary} ${reasoning}"
  local text_lower="${text,,}"

  # Security keywords from PRH-001 spec
  # Single words checked individually; multi-word phrases ("access control", etc.)
  # are covered because their component words appear in this list.
  local keywords="auth credential encrypt token secret permission access control trust boundary identity authorization login verification level privilege"

  for keyword in $keywords; do
    if echo "$text_lower" | grep -qF "$keyword"; then
      echo "mismatch: security keyword '$keyword' found in $category category"
      return 0
    fi
  done

  # No security keywords found — clean
  return 1
}

# ---------------------------------------------------------------------------
# security_structural_guard — check if options remove/downgrade checks
# ---------------------------------------------------------------------------
# Usage: security_structural_guard DR_JSON
# Returns: 0 if structural concern found (must escalate), 1 if clean
# PRH-001 layer 3 — category-independent.
security_structural_guard() {
  local dr_json="$1"

  # Extract all option descriptions
  local options_text
  options_text="$(echo "$dr_json" | jq -r '.options[]?.description // empty' 2>/dev/null)" || true

  if [ -z "$options_text" ]; then
    return 1
  fi

  local options_lower="${options_text,,}"

  # Check for remove/downgrade/disable/skip of checks, constraints, validations, tests
  if echo "$options_lower" | grep -qiE '(remove|downgrade|disable|skip).*(check|constraint|validation|test|guard|access|logging|security)'; then
    return 0
  fi

  return 1
}

# ---------------------------------------------------------------------------
# check_test_deletion — check if a diff deletes test files or test functions
# ---------------------------------------------------------------------------
# Usage: check_test_deletion DIFF_TEXT
# Returns: 0 if no test deletion, 1 if test deletion detected (PRH-003)
check_test_deletion() {
  local diff_text="$1"

  # Check for deleted test files (deleted file mode)
  if echo "$diff_text" | grep -q 'deleted file mode'; then
    # Check if deleted file is in tests/ or has test in the name
    if echo "$diff_text" | grep -E '^\-\-\- a/tests/|^\-\-\- a/.*test' | grep -q '.'; then
      return 1
    fi
  fi

  # Check for removed test functions (lines starting with - that contain test_)
  if echo "$diff_text" | grep -qE '^-[[:space:]]*(test_|def test_|it\(|describe\()'; then
    return 1
  fi

  return 0
}

# ---------------------------------------------------------------------------
# check_override_usage — check if content uses workflow-advance.sh override
# ---------------------------------------------------------------------------
# Usage: check_override_usage CONTENT
# Returns: 0 if no override usage, 1 if override detected (PRH-004)
check_override_usage() {
  local content="$1"

  if echo "$content" | grep -qF "workflow-advance.sh override"; then
    return 1
  fi

  return 0
}
