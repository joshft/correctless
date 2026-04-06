#!/usr/bin/env bash
# Correctless — Shared library functions
# Sourced by hooks and scripts that need common utilities.

# ---------------------------------------------------------------------------
# branch_slug — filesystem-safe slug from current branch name
# ---------------------------------------------------------------------------
# Non-alphanumeric characters replaced by hyphens, truncated to 80 chars,
# appended with 6-char hash to avoid collisions.
# (feature/foo-bar and feature/foo_bar produce different hashes)

branch_slug() {
  local branch
  branch="$(git branch --show-current 2>/dev/null)" || { echo "error: not in a git repository" >&2; return 1; }
  [ -n "$branch" ] || { echo "error: detached HEAD" >&2; return 1; }
  local slug raw_hash
  slug="${branch//[^a-zA-Z0-9]/-}"
  slug="${slug:0:80}"
  raw_hash="$(printf '%s' "$branch" | (md5sum 2>/dev/null || md5))"
  echo "${slug}-${raw_hash:0:6}"
}

# ---------------------------------------------------------------------------
# repo_root — absolute path to the git repository root (cached)
# ---------------------------------------------------------------------------

repo_root() {
  if [ -z "${_CORRECTLESS_REPO_ROOT:-}" ]; then
    _CORRECTLESS_REPO_ROOT="$(git --no-optional-locks rev-parse --show-toplevel 2>/dev/null || pwd)"
  fi
  echo "$_CORRECTLESS_REPO_ROOT"
}

# ---------------------------------------------------------------------------
# config_file — absolute path to workflow-config.json (cached)
# ---------------------------------------------------------------------------

config_file() {
  if [ -z "${_CORRECTLESS_CONFIG_FILE:-}" ]; then
    _CORRECTLESS_CONFIG_FILE="$(repo_root)/.correctless/config/workflow-config.json"
  fi
  echo "$_CORRECTLESS_CONFIG_FILE"
}

# ---------------------------------------------------------------------------
# artifacts_dir — absolute path to artifacts directory (cached)
# ---------------------------------------------------------------------------

artifacts_dir() {
  if [ -z "${_CORRECTLESS_ARTIFACTS_DIR:-}" ]; then
    _CORRECTLESS_ARTIFACTS_DIR="$(repo_root)/.correctless/artifacts"
  fi
  echo "$_CORRECTLESS_ARTIFACTS_DIR"
}

# ---------------------------------------------------------------------------
# classify_file — classify a relative path as test, source, or other
# ---------------------------------------------------------------------------
# Used by: workflow-gate.sh, audit-trail.sh
# Requires TEST_PATTERN and SOURCE_PATTERN globals to be set by the caller.
# Patterns are pipe-delimited globs (e.g., "*.test.ts|*.spec.ts|tests/*.rs").
# Patterns with "/" match against the full relative path; without "/" match basename only.

# shellcheck disable=SC2254  # Unquoted $pat in case is intentional — we need glob matching
classify_file() {
  local file="$1" bname
  # Normalize case — patterns are lowercase, filenames may not be (bash 4+ builtin)
  file="${file,,}"
  bname="${file##*/}"

  if [ -n "$TEST_PATTERN" ]; then
    local oldifs="$IFS"; IFS='|'
    for pat in $TEST_PATTERN; do
      IFS="$oldifs"
      case "$pat" in
        */*) case "$file" in $pat) echo "test"; return ;; esac ;;
        *)   case "$bname" in $pat) echo "test"; return ;; esac ;;
      esac
    done
    IFS="$oldifs"
  fi

  if [ -n "$SOURCE_PATTERN" ]; then
    local oldifs="$IFS"; IFS='|'
    for pat in $SOURCE_PATTERN; do
      IFS="$oldifs"
      case "$pat" in
        */*) case "$file" in $pat) echo "source"; return ;; esac ;;
        *)   case "$bname" in $pat) echo "source"; return ;; esac ;;
      esac
    done
    IFS="$oldifs"
  fi

  echo "other"
}

# ---------------------------------------------------------------------------
# read_patterns — set TEST_PATTERN and SOURCE_PATTERN from config
# ---------------------------------------------------------------------------
# Pre-positioned for Phase 2 hook decomposition. Not yet called by hooks
# (they use bulk jq calls for performance); available for future sub-handlers.
# Reads .patterns.test_file and .patterns.source_file from workflow-config.json.
# Sets them as globals for use with classify_file().

read_patterns() {
  local cf="${1:-$(config_file 2>/dev/null)}"
  [ -f "$cf" ] || return 1
  eval "$(jq -r '
    @sh "TEST_PATTERN=\(.patterns.test_file // "")",
    @sh "SOURCE_PATTERN=\(.patterns.source_file // "")"
  ' "$cf" 2>/dev/null)" || return 1
}

# ---------------------------------------------------------------------------
# read_intensity — output the project workflow intensity
# ---------------------------------------------------------------------------
# Pre-positioned for Phase 2 hook decomposition (see read_patterns note).
# Returns "standard", "high", or "critical". Defaults to "standard".

read_intensity() {
  local cf="${1:-$(config_file 2>/dev/null)}"
  [ -f "$cf" ] || { echo "standard"; return; }
  local val
  val="$(jq -r '.workflow.intensity // "standard"' "$cf" 2>/dev/null)" || val="standard"
  echo "$val"
}
