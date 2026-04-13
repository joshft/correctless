#!/usr/bin/env bash
# Correctless — Pipeline lockfile management
# Prevents concurrent /cauto invocations on the same branch.

# No set -euo pipefail — this file is sourced by other scripts

# ---------------------------------------------------------------------------
# lock_acquire — acquire pipeline lock for this branch
# ---------------------------------------------------------------------------
# Usage: lock_acquire LOCK_FILE
# Returns: 0 if acquired, 1 if another run is active
# Writes current PID to lockfile. Checks for stale locks (BND-006).
lock_acquire() {
  local lock_file="$1"
  local lock_dir="${lock_file}.d"

  # QA-015: use mkdir for atomic lock creation (matches lib.sh pattern)
  if mkdir "$lock_dir" 2>/dev/null; then
    # Acquired — write PID inside the lock directory
    echo "$$" > "$lock_dir/pid" 2>/dev/null || true
    # Also write to the legacy lock_file location for lock_check_stale compat
    echo "$$" > "$lock_file" 2>/dev/null || true
    return 0
  fi

  # Lock dir exists — check if stale
  lock_check_stale "$lock_file"
  case $? in
    0)
      # Stale lock was cleaned — retry acquire
      if mkdir "$lock_dir" 2>/dev/null; then
        echo "$$" > "$lock_dir/pid" 2>/dev/null || true
        echo "$$" > "$lock_file" 2>/dev/null || true
        return 0
      fi
      echo "ERROR: Another /cauto run is active on this branch." >&2
      return 1
      ;;
    1) echo "ERROR: Another /cauto run is active on this branch." >&2; return 1 ;;
    2) echo "ERROR: Lockfile corrupted; delete '$lock_file' and '$lock_dir' manually if no /cauto run is active." >&2; return 1 ;;
  esac
}

# ---------------------------------------------------------------------------
# lock_release — release pipeline lock
# ---------------------------------------------------------------------------
# Usage: lock_release LOCK_FILE
lock_release() {
  local lock_file="$1"
  rm -rf "${lock_file}.d" 2>/dev/null
  rm -f "$lock_file"
  return 0
}

# ---------------------------------------------------------------------------
# lock_check_stale — check if lockfile is stale (PID no longer running)
# ---------------------------------------------------------------------------
# Usage: lock_check_stale LOCK_FILE
# Returns: 0 if stale (auto-cleaned), 1 if active, 2 if corrupted
lock_check_stale() {
  local lock_file="$1"

  if [ ! -f "$lock_file" ]; then
    return 0
  fi

  local pid_content
  pid_content="$(cat "$lock_file" 2>/dev/null)" || true

  # Check if content is a valid PID (numeric)
  if ! [[ "$pid_content" =~ ^[0-9]+$ ]]; then
    # Not a parseable PID — corrupted lockfile (BND-006)
    return 2
  fi

  # Check if the PID is still running
  if kill -0 "$pid_content" 2>/dev/null; then
    # PID is alive — lock is active
    return 1
  else
    # PID is dead — stale lock, auto-clean (including .d directory from atomic locking)
    rm -rf "${lock_file}.d" 2>/dev/null
    rm -f "$lock_file"
    return 0
  fi
}
