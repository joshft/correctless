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

# ---------------------------------------------------------------------------
# State file locking — atomic mkdir + PID-based stale detection
# ---------------------------------------------------------------------------
# Uses mkdir for portability (no flock dependency — works on macOS).
# Lock directory: ${state_file}.lock with a pid file inside.

# _acquire_state_lock — acquire a lock for the given state file
_acquire_state_lock() {
  local state_file="$1"
  [ -n "$state_file" ] || { echo "ERROR: _acquire_state_lock called with empty path" >&2; return 1; }
  local lock_dir="${state_file}.lock"
  local timeout="${CORRECTLESS_LOCK_TIMEOUT:-5}"
  [[ "$timeout" =~ ^[0-9]+$ ]] || timeout=5
  local deadline=$((SECONDS + timeout))

  while true; do
    if mkdir "$lock_dir" 2>/dev/null; then
      echo "$$" > "$lock_dir/pid" || { rm -rf "$lock_dir"; return 1; }
      return 0
    fi

    # Lock exists — check if holder is alive
    if [ -f "$lock_dir/pid" ]; then
      local holder_pid
      holder_pid="$(cat "$lock_dir/pid" 2>/dev/null)" || holder_pid=""
      if [ -n "$holder_pid" ] && ! kill -0 "$holder_pid" 2>/dev/null; then
        # Holder is dead — atomically claim stale lock via mv.
        # Only one process's mv succeeds; losers retry from the top.
        local break_dir="${lock_dir}.breaking.$$"
        if mv "$lock_dir" "$break_dir" 2>/dev/null; then
          rm -rf "$break_dir"
        fi
        continue
      fi
    elif [ -d "$lock_dir" ]; then
      # QA-R1-018: No pid file — lock was interrupted between mkdir and pid write.
      # Treat as stale and break it to prevent 5s timeout deadlock.
      local break_dir="${lock_dir}.breaking.$$"
      if mv "$lock_dir" "$break_dir" 2>/dev/null; then
        rm -rf "$break_dir"
      fi
      continue
    fi

    # Holder is alive or PID unknown — wait and retry
    if [ "$SECONDS" -ge "$deadline" ]; then
      echo "ERROR: Lock acquisition timeout after ${timeout}s for $state_file" >&2
      return 1
    fi
    sleep 0.1
  done
}

# _release_state_lock — release the lock for the given state file
_release_state_lock() {
  local state_file="$1"
  local lock_dir="${state_file}.lock"
  # Only release if we are the holder — prevents EXIT trap from deleting another process's lock
  if [ -f "$lock_dir/pid" ] && [ "$(cat "$lock_dir/pid" 2>/dev/null)" = "$$" ]; then
    rm -rf "$lock_dir"
  fi
}

# locked_update_state — read-modify-write a state file under lock
# Usage: locked_update_state STATE_FILE JQ_FILTER [--arg key val ...]
# QA-R3-001: Extra arguments after the filter are passed through to jq,
# enabling safe parameterization via --arg instead of string interpolation.
locked_update_state() {
  local state_file="$1"
  local jq_filter="$2"
  shift 2
  local rc=0

  _acquire_state_lock "$state_file" || return 1
  # QA-R1-013: EXIT trap ensures lock is released on abnormal termination
  # (e.g., hook runner kills the process at timeout between acquire and release)
  # shellcheck disable=SC2064
  trap "$(printf '_release_state_lock %q; rm -f %q' "$state_file" "${state_file}.$$.tmp")" EXIT

  local tmp_file="${state_file}.$$.tmp"
  # Extra args (e.g., --arg key val) must come BEFORE the filter for older jq (1.6)
  if jq "$@" "$jq_filter" "$state_file" > "$tmp_file" 2>/dev/null; then
    mv "$tmp_file" "$state_file" || { rm -f "$tmp_file"; rc=1; }
  else
    rm -f "$tmp_file"
    rc=1
  fi

  _release_state_lock "$state_file"
  trap - EXIT
  return "$rc"
}

# ---------------------------------------------------------------------------
# _has_write_pattern — detect write/destructive shell command patterns
# ---------------------------------------------------------------------------
# Returns 0 if the command contains a write pattern, 1 otherwise.
# Union of all write-command tokens from workflow-gate.sh and
# sensitive-file-guard.sh: redirect regex, token list, sed -i, perl -i.

_has_write_pattern() {
  local cmd="$1"
  # Check redirect operators (single combined grep).
  # Known limitation: matches '>' inside quoted strings (e.g., echo "x > y").
  # False positives are fail-safe — read-only commands get phase-gated, not bypassed.
  echo "$cmd" | grep -qE '>>|[0-9]*>[^&]' && return 0
  # Tokenize on shell metacharacters and check each token
  # shellcheck disable=SC2141
  local IFS=$' \t\n;|&()`'
  for tok in $cmd; do
    case "$tok" in
      cp|mv|tee|install|rm|rmdir|unlink|dd|curl|wget|rsync|patch|truncate|shred|ln|python|python3|node|ruby) return 0 ;;
      tar|unzip|7z|cpio|ar|touch|chmod|chown|chgrp|scp|sftp|mkdir) return 0 ;;
      git) [[ "$cmd" =~ git[[:space:]]+(checkout|restore|reset|stash|clean|apply|am|merge|rebase|cherry-pick) ]] && return 0 ;;
      sed) [[ "$cmd" =~ sed[[:space:]]+-i ]] && return 0 ;;
      perl) [[ "$cmd" =~ perl[[:space:]]+-i ]] && return 0 ;;
    esac
  done
  return 1
}

# ---------------------------------------------------------------------------
# get_target_file — extract file paths with known extensions from a command
# ---------------------------------------------------------------------------
# Wraps the grep -oE call with the 25-extension regex pattern.
# Usage: FILES="$(get_target_file "$COMMAND")"

get_target_file() {
  local cmd="$1"
  echo "$cmd" | sed "s/['\"]//g" | tr ' \t' '\n\n' | grep -E '\.(go|ts|tsx|js|jsx|py|rs|java|rb|cpp|c|h|sh|json|md|yaml|yml|toml|cfg|ini|sql|css|html|vue|svelte)$'
}

# ---------------------------------------------------------------------------
# sha256_hash_file — compute SHA-256 hash of a file (cross-platform)
# ---------------------------------------------------------------------------
# Tries sha256sum, shasum -a 256, openssl dgst -sha256 in order.
# Usage: sha256_hash_file FILE_PATH
# Outputs the hex hash to stdout. Returns 1 if no tool available.

sha256_hash_file() {
  local file="$1"

  [ -f "$file" ] || return 1

  local hash=""

  if command -v sha256sum >/dev/null 2>&1; then
    hash="$(sha256sum "$file" 2>/dev/null | cut -d' ' -f1)"
  elif command -v shasum >/dev/null 2>&1; then
    hash="$(shasum -a 256 "$file" 2>/dev/null | cut -d' ' -f1)"
  elif command -v openssl >/dev/null 2>&1; then
    hash="$(openssl dgst -sha256 "$file" 2>/dev/null | sed 's/^.*= //')"
  fi

  if [ -n "$hash" ]; then
    echo "$hash"
    return 0
  fi

  return 1
}
