#!/usr/bin/env bash
# Correctless — Shared Test Harness
#
# Provides common test boilerplate: preamble, color definitions,
# pass/fail/section/skip functions, counter variables, and summary().
#
# Usage: source "$(dirname "${BASH_SOURCE[0]}")/test-helpers.sh"
#
# All functions use a 2-arg signature: func "id" "description"
# The summary() function accepts a test suite name as its first argument.

# shellcheck disable=SC1090,SC1091,SC2034

# ============================================================================
# Preamble
# ============================================================================

set -uo pipefail

cd "$(dirname "${BASH_SOURCE[1]}")/.." || { echo "FATAL: cannot cd to repo root" >&2; exit 2; }
REPO_DIR="$(pwd)"

# ============================================================================
# Colors (only if stdout is a terminal)
# ============================================================================

if [ -t 1 ]; then
  GREEN=$'\033[0;32m'
  RED=$'\033[0;31m'
  YELLOW=$'\033[0;33m'
  RESET=$'\033[0m'
else
  GREEN=""
  RED=""
  YELLOW=""
  RESET=""
fi

# ============================================================================
# Counter variables
# ============================================================================

PASS=0
FAIL=0
SKIPPED=0
FAILED_IDS=""

# ============================================================================
# Result helpers
# ============================================================================

pass() {
  local id="$1" desc="$2"
  echo "  ${GREEN}PASS${RESET}: $id: $desc"
  PASS=$((PASS + 1))
}

fail() {
  local id="$1" desc="$2"
  echo "  ${RED}FAIL${RESET}: $id: $desc"
  FAIL=$((FAIL + 1))
  FAILED_IDS="${FAILED_IDS}${id} "
}

skip() {
  local id="$1" desc="$2"
  echo "  ${YELLOW}SKIP${RESET}: $id: $desc"
  SKIPPED=$((SKIPPED + 1))
}

section() {
  echo ""
  echo "--- Testing: $1 ---"
}

# ============================================================================
# Skill body extractor — strips YAML frontmatter
# Uses awk to skip the first ---/--- block; returns everything after.
# ============================================================================

skill_body() {
  local file="$1"
  awk '
    BEGIN { state = 0 }
    NR == 1 && /^---/ { state = 1; next }
    state == 1 && /^---/ { state = 0; next }
    state == 0 { print }
  ' "$file"
}

# ============================================================================
# Frontmatter helpers — extract/query YAML frontmatter from agents/*.md
# and skills/*/SKILL.md files. Memoized per-file.
# ============================================================================

# Extract frontmatter block (between leading --- lines) from a markdown file.
# Emits nothing and returns non-zero if frontmatter is absent or malformed.
extract_frontmatter() {
  local file="$1"
  [ -f "$file" ] || return 1
  local cache_var
  cache_var="_FM_CACHE_$(printf '%s' "$file" | tr -c 'a-zA-Z0-9' '_')"
  local cached="${!cache_var:-__UNSET__}"
  if [ "$cached" != "__UNSET__" ]; then
    printf '%s' "$cached"
    [ -n "$cached" ] && return 0 || return 1
  fi
  local result
  result="$(awk '
    BEGIN { state = 0 }
    NR == 1 {
      if ($0 == "---") { state = 1; next }
      else { exit 1 }
    }
    state == 1 && $0 == "---" { exit 0 }
    state == 1 { print }
  ' "$file" 2>/dev/null || true)"
  printf -v "$cache_var" '%s' "$result"
  printf '%s' "$result"
  [ -n "$result" ] && return 0 || return 1
}

# Extract a single scalar frontmatter field (key: value) from a markdown file.
get_frontmatter_field() {
  local file="$1" key="$2"
  extract_frontmatter "$file" 2>/dev/null | awk -v k="$key" '
    BEGIN { found = 0 }
    {
      if (match($0, "^[[:space:]]*" k ":[[:space:]]*")) {
        val = substr($0, RSTART + RLENGTH)
        sub(/[[:space:]]+$/, "", val)
        print val
        found = 1
        exit
      }
    }
    END { exit (found ? 0 : 1) }
  '
}

# Parse the `tools:` comma-flow field and emit one tool name per line.
parse_tools_list() {
  local file="$1"
  local raw
  raw="$(get_frontmatter_field "$file" "tools")" || return 1
  [ -n "$raw" ] || return 1
  printf '%s\n' "$raw" | awk '
    {
      n = split($0, a, ",")
      for (i = 1; i <= n; i++) {
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", a[i])
        if (a[i] != "") print a[i]
      }
    }
  '
}

# ============================================================================
# Summary
# ============================================================================

summary() {
  local name="$1"
  local line="${name}: ${PASS} passed, ${FAIL} failed"
  if [ "$SKIPPED" -gt 0 ]; then
    line="${line}, ${SKIPPED} skipped"
  fi
  echo ""
  echo "==========================================="
  echo "$line"
  if [ -n "$FAILED_IDS" ]; then
    echo "Failed: $FAILED_IDS"
  fi
  echo "==========================================="
  if [ "$FAIL" -gt 0 ]; then
    exit 1
  fi
  exit 0
}
