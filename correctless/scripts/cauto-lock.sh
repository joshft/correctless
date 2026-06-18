#!/usr/bin/env bash
# Correctless — Working-tree / pipeline lockfile management
# Provides mutual exclusion between working-tree-mutating orchestrators
# (/cauto branch-scoped lock AND the shared global worktree.lock — INV-015).

# No set -euo pipefail — this file is sourced by other scripts

# ---------------------------------------------------------------------------
# lock_acquire — acquire a lock at an ARBITRARY lock path
# ---------------------------------------------------------------------------
# Usage: lock_acquire LOCK_FILE [HOLDER]
#   LOCK_FILE  any lock path — a /cauto per-branch path OR the shared global
#              .correctless/artifacts/worktree.lock (INV-015). The primitive is
#              path-agnostic; callers choose the path/scope.
#   HOLDER     optional label naming the acquiring orchestrator (e.g. "/cauto",
#              "/cchores"). Recorded in the lock so a collision message can name
#              the HOLDING orchestrator generically (R3-4) rather than hardcoding
#              the cauto-only "active on this branch" wording.
# Returns: 0 if acquired, 1 if another run holds the lock
# Writes current PID (and holder, if given) to the lock. Recovers stale locks.
lock_acquire() {
  local lock_file="$1"
  local holder="${2:-}"
  local lock_dir="${lock_file}.d"

  # QA-015: use mkdir for atomic lock creation (matches lib.sh pattern)
  if mkdir "$lock_dir" 2>/dev/null; then
    # Acquired — write PID inside the lock directory
    echo "$$" > "$lock_dir/pid" 2>/dev/null || true
    [ -n "$holder" ] && echo "$holder" > "$lock_dir/holder" 2>/dev/null || true
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
        [ -n "$holder" ] && echo "$holder" > "$lock_dir/holder" 2>/dev/null || true
        echo "$$" > "$lock_file" 2>/dev/null || true
        return 0
      fi
      echo "ERROR: $(_lock_busy_message "$lock_dir")" >&2
      return 1
      ;;
    1) echo "ERROR: $(_lock_busy_message "$lock_dir")" >&2; return 1 ;;
    2) echo "ERROR: Lockfile corrupted; delete '$lock_file' and '$lock_dir' manually if no orchestrator is active." >&2; return 1 ;;
  esac
}

# ---------------------------------------------------------------------------
# _lock_busy_message — build a collision message that names the HOLDER
# ---------------------------------------------------------------------------
# Reads the recorded holder (if any) from the lock dir so the message names the
# holding orchestrator generically ("locked by …"), rather than the cauto-only
# "Another /cauto run is active on this branch" wording (R3-4 / INV-015-a).
_lock_busy_message() {
  local lock_dir="$1"
  local recorded_holder=""
  if [ -f "$lock_dir/holder" ]; then
    recorded_holder="$(cat "$lock_dir/holder" 2>/dev/null)" || true
  fi
  if [ -n "$recorded_holder" ]; then
    echo "working tree is locked by ${recorded_holder} (another orchestrator run is holding the lock)."
  else
    echo "working tree is locked by another orchestrator run (holder unknown; the lock is held)."
  fi
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
