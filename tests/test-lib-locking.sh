#!/usr/bin/env bash
# Correctless — Locking Mechanism Tests
# Tests R-015 through R-019, R-021 from the infrastructure hardening spec.
# Run from repo root: bash tests/test-lib-locking.sh

set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB_SH="$REPO_DIR/scripts/lib.sh"
ADV_HOOK="$REPO_DIR/hooks/workflow-advance.sh"
GATE_HOOK="$REPO_DIR/hooks/workflow-gate.sh"
PASS=0
FAIL=0

# ============================================================================
# Helpers
# ============================================================================

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (expected '$expected', got '$actual')"
    FAIL=$((FAIL + 1))
  fi
}

assert_contains() {
  local desc="$1" expected="$2" actual="$3"
  if echo "$actual" | grep -qF "$expected"; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (expected output to contain '$expected')"
    FAIL=$((FAIL + 1))
  fi
}

assert_not_exists() {
  local desc="$1" path="$2"
  if [ ! -e "$path" ]; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (path '$path' should not exist but does)"
    FAIL=$((FAIL + 1))
  fi
}

assert_exists() {
  local desc="$1" path="$2"
  if [ -e "$path" ]; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (path '$path' should exist but does not)"
    FAIL=$((FAIL + 1))
  fi
}

# ============================================================================
# Test environment
# ============================================================================

TEST_DIR="/tmp/correctless-test-locking-$$"
STATE_FILE=""
LOCK_DIR=""

setup_test_env() {
  rm -rf "$TEST_DIR"
  mkdir -p "$TEST_DIR"
  cd "$TEST_DIR" || exit 1

  # Initialize git repo
  git init -q
  git branch -M main
  echo "init" > README.md
  git add -A && git commit -q -m "init"
  git checkout -q -b feature/test-locking

  # Copy lib.sh
  mkdir -p .correctless/scripts
  cp "$LIB_SH" .correctless/scripts/lib.sh

  # Create config and artifacts dirs
  mkdir -p .correctless/config .correctless/artifacts
  cat > .correctless/config/workflow-config.json <<'WCEOF'
{
  "patterns": {
    "test_file": "*.test.ts|*.spec.ts",
    "source_file": "*.ts|*.js"
  },
  "workflow": {
    "fail_closed_when_no_state": false
  }
}
WCEOF

  # Source lib.sh to get functions
  source .correctless/scripts/lib.sh

  # Set up state file path
  STATE_FILE="$TEST_DIR/.correctless/artifacts/test-state.json"
  LOCK_DIR="${STATE_FILE}.lock"

  # Create a valid initial state
  cat > "$STATE_FILE" <<'EOF'
{
  "phase": "tdd-impl",
  "override": {
    "active": false,
    "remaining_calls": 0
  },
  "qa_rounds": 0
}
EOF
}

cleanup() {
  rm -rf "$TEST_DIR"
}
trap cleanup EXIT

echo "Correctless Locking Mechanism Tests"
echo "====================================="

# ============================================================================
# R-015 [integration]: write_state creates lockfile during write, removes after
# ============================================================================

test_write_state_lockfile() {
  echo ""
  echo "=== R-015: write_state creates and removes lockfile ==="

  setup_test_env

  # Source lib.sh again after setup to get the latest functions
  source .correctless/scripts/lib.sh

  # We need to verify that the lockfile (a directory via mkdir) exists DURING
  # the write and does NOT exist AFTER the write completes.

  # Strategy: write_state should use _acquire_state_lock / _release_state_lock.
  # We observe by checking the lock directory before and after.

  # Clean any existing lock
  rm -rf "$LOCK_DIR"

  # Write new state using the function
  local new_state='{"phase": "tdd-qa", "override": {"active": false, "remaining_calls": 0}}'

  # Observe the lock deterministically: acquire, check it exists, then release.
  # No background polling needed — we hold the lock and inspect.
  local lock_seen="no"

  _acquire_state_lock "$STATE_FILE" 2>/dev/null && {
    # Lock is held — verify the lock directory exists NOW
    if [ -d "$LOCK_DIR" ]; then
      lock_seen="yes"
    fi
    echo "$new_state" | jq '.' > "${STATE_FILE}.$$" && mv "${STATE_FILE}.$$" "$STATE_FILE"
    _release_state_lock "$STATE_FILE"
  }

  assert_eq "R-015a: lockfile existed during write" "yes" "$lock_seen"

  # After write completes, the lock must not exist
  assert_not_exists "R-015b: lockfile removed after write" "$LOCK_DIR"

  # Verify the state was actually written
  local written_phase
  written_phase="$(jq -r '.phase' "$STATE_FILE" 2>/dev/null)"
  assert_eq "R-015c: state file updated correctly" "tdd-qa" "$written_phase"

  # QA-001 fix: verify write_state() in workflow-advance.sh actually calls
  # _acquire_state_lock within its function body (wiring check)
  local ws_body
  ws_body="$(sed -n '/^write_state()/,/^}/p' "$ADV_HOOK")"
  local ws_has_acquire="no"
  if echo "$ws_body" | grep -q '_acquire_state_lock'; then
    ws_has_acquire="yes"
  fi
  assert_eq "R-015d: write_state() calls _acquire_state_lock" "yes" "$ws_has_acquire"

  local ws_has_release="no"
  if echo "$ws_body" | grep -q '_release_state_lock'; then
    ws_has_release="yes"
  fi
  assert_eq "R-015e: write_state() calls _release_state_lock" "yes" "$ws_has_release"
}

# ============================================================================
# R-016 [integration]: locked_update_state creates lock, modifies state,
#   rolls back on jq failure, and always removes lock
# ============================================================================

test_locked_update_state() {
  echo ""
  echo "=== R-016: locked_update_state lock lifecycle and rollback ==="

  setup_test_env
  source .correctless/scripts/lib.sh

  # (1) Successful transformation — state updated, lock released after
  locked_update_state "$STATE_FILE" '.phase = "tdd-qa"' 2>/dev/null

  # Verify state was modified
  local new_phase
  new_phase="$(jq -r '.phase' "$STATE_FILE" 2>/dev/null)"
  assert_eq "R-016a: state reflects modification after success" "tdd-qa" "$new_phase"

  # Verify lock is released
  assert_not_exists "R-016b: lockfile removed after successful update" "$LOCK_DIR"

  # (2) Failed jq transformation — state unchanged, lock released
  # Reset state
  cat > "$STATE_FILE" <<'EOF'
{
  "phase": "tdd-impl",
  "override": {
    "active": false,
    "remaining_calls": 0
  }
}
EOF

  # Use an invalid jq filter that will fail
  locked_update_state "$STATE_FILE" '.INVALID_SYNTAX[[[' 2>/dev/null || true

  # State should be unchanged
  local unchanged_phase
  unchanged_phase="$(jq -r '.phase' "$STATE_FILE" 2>/dev/null)"
  assert_eq "R-016c: state unchanged after failed jq" "tdd-impl" "$unchanged_phase"

  # Lock must be released even after failure
  assert_not_exists "R-016d: lockfile removed after failed update" "$LOCK_DIR"
}

# ============================================================================
# R-017 [unit]: Stale lock detection via dead PID
# ============================================================================

test_stale_lock_detection() {
  echo ""
  echo "=== R-017: Stale lock broken when holder PID is dead ==="

  setup_test_env
  source .correctless/scripts/lib.sh

  # Create a stale lock with a dead PID
  # Fork a subshell, capture PID, let it exit
  local dead_pid
  (exit 0) &
  dead_pid=$!
  wait "$dead_pid" 2>/dev/null || true

  # Verify the PID is truly dead
  if kill -0 "$dead_pid" 2>/dev/null; then
    echo "  SKIP: R-017: could not create dead PID for test"
    FAIL=$((FAIL + 1))
    return
  fi

  # Manually create a lock directory with the dead PID
  mkdir -p "$LOCK_DIR"
  echo "$dead_pid" > "$LOCK_DIR/pid"

  # _acquire_state_lock should detect the stale lock and break it
  local acquire_exit
  _acquire_state_lock "$STATE_FILE" 2>/dev/null && acquire_exit=0 || acquire_exit=$?

  assert_eq "R-017a: acquire succeeds after breaking stale lock" "0" "$acquire_exit"

  # The lock should now exist with OUR PID
  if [ -d "$LOCK_DIR" ] && [ -f "$LOCK_DIR/pid" ]; then
    local lock_pid
    lock_pid="$(cat "$LOCK_DIR/pid")"
    assert_eq "R-017b: lock now contains our PID" "$$" "$lock_pid"
  else
    echo "  FAIL: R-017b: lock directory or pid file missing after acquisition"
    FAIL=$((FAIL + 1))
  fi

  # Cleanup
  _release_state_lock "$STATE_FILE" 2>/dev/null || true
}

# ============================================================================
# R-018 [unit]: Lock acquisition times out with clear error message
# ============================================================================

test_lock_timeout() {
  echo ""
  echo "=== R-018: Lock acquisition timeout ==="

  setup_test_env
  source .correctless/scripts/lib.sh

  # Create a lock held by a LIVE process (ourselves, effectively)
  mkdir -p "$LOCK_DIR"
  echo "$$" > "$LOCK_DIR/pid"

  # Set a very short timeout
  export CORRECTLESS_LOCK_TIMEOUT=1

  # Try to acquire — should fail because the lock is held by a live PID ($$)
  local acquire_exit stderr_output
  stderr_output="$(_acquire_state_lock "$STATE_FILE" 2>&1)" && acquire_exit=0 || acquire_exit=$?

  # Should fail with non-zero exit
  if [ "$acquire_exit" -ne 0 ]; then
    echo "  PASS: R-018a: acquire fails when lock held by live PID"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: R-018a: acquire should fail when lock held by live PID (got exit 0)"
    FAIL=$((FAIL + 1))
  fi

  # Error message should contain "timeout"
  assert_contains "R-018b: error message contains timeout" "timeout" "$stderr_output"

  # Cleanup
  rm -rf "$LOCK_DIR"
  unset CORRECTLESS_LOCK_TIMEOUT
}

# ============================================================================
# R-019 [unit]: Lock released after both success and failure paths
# ============================================================================

test_lock_cleanup_on_all_paths() {
  echo ""
  echo "=== R-019: Lock released on success and failure paths ==="

  setup_test_env
  source .correctless/scripts/lib.sh

  # (1) Success path: valid JSON write
  rm -rf "$LOCK_DIR"
  local new_state='{"phase": "done", "override": {"active": false, "remaining_calls": 0}}'

  _acquire_state_lock "$STATE_FILE" 2>/dev/null || true
  echo "$new_state" | jq '.' > "${STATE_FILE}.$$" 2>/dev/null && mv "${STATE_FILE}.$$" "$STATE_FILE" 2>/dev/null
  _release_state_lock "$STATE_FILE" 2>/dev/null || true

  assert_not_exists "R-019a: no stale lock after successful write" "$LOCK_DIR"

  # (2) Failure path: invalid jq input — use locked_update_state with bad filter
  cat > "$STATE_FILE" <<'EOF'
{
  "phase": "tdd-impl",
  "override": {"active": false, "remaining_calls": 0}
}
EOF

  rm -rf "$LOCK_DIR"
  locked_update_state "$STATE_FILE" '.INVALID[[[' 2>/dev/null || true

  assert_not_exists "R-019b: no stale lock after failed write" "$LOCK_DIR"

  # (3) Verify state was not corrupted by the failed path
  local phase_after
  phase_after="$(jq -r '.phase' "$STATE_FILE" 2>/dev/null)"
  assert_eq "R-019c: state intact after failed write" "tdd-impl" "$phase_after"
}

# ============================================================================
# R-021 [unit]: Locking does not depend on flock or lockfile commands
# ============================================================================

test_no_flock_dependency() {
  echo ""
  echo "=== R-021: Locking uses mkdir, not flock/lockfile ==="

  # Static analysis: grep lib.sh for flock or lockfile as command invocations
  # (exclude comments — lines starting with #)
  local flock_found="no"
  if grep -vE '^[[:space:]]*#' "$LIB_SH" 2>/dev/null | grep -qE '\bflock\b'; then
    flock_found="yes"
  fi
  assert_eq "R-021a: lib.sh does not invoke flock" "no" "$flock_found"

  local lockfile_found="no"
  if grep -vE '^[[:space:]]*#' "$LIB_SH" 2>/dev/null | grep -qE '\blockfile\b'; then
    lockfile_found="yes"
  fi
  assert_eq "R-021b: lib.sh does not invoke lockfile command" "no" "$lockfile_found"

  # Verify mkdir IS used in non-comment code (positive check)
  local mkdir_found="no"
  if grep -vE '^[[:space:]]*#' "$LIB_SH" 2>/dev/null | grep -qE 'mkdir.*lock'; then
    mkdir_found="yes"
  fi
  assert_eq "R-021c: lib.sh uses mkdir for locking" "yes" "$mkdir_found"

  # Also check workflow-advance.sh and workflow-gate.sh for flock invocations
  local adv_flock="no"
  if grep -vE '^[[:space:]]*#' "$ADV_HOOK" 2>/dev/null | grep -qE '\bflock\b'; then
    adv_flock="yes"
  fi
  assert_eq "R-021d: workflow-advance.sh does not invoke flock" "no" "$adv_flock"

  local gate_flock="no"
  if grep -vE '^[[:space:]]*#' "$GATE_HOOK" 2>/dev/null | grep -qE '\bflock\b'; then
    gate_flock="yes"
  fi
  assert_eq "R-021e: workflow-gate.sh does not invoke flock" "no" "$gate_flock"
}

# ============================================================================
# AP-015: Every script writing workflow-state-*.json must use advisory locking
# ============================================================================

test_all_state_writers_use_locking() {
  echo ""
  echo "=== AP-015: All workflow state writers use advisory locking ==="

  # Find all scripts that write to workflow-state files
  local scripts_with_state_writes=()

  for script in "$REPO_DIR"/scripts/*.sh; do
    [ -f "$script" ] || continue
    local bname
    bname="$(basename "$script")"

    # Check if the script modifies state files specifically:
    # Must reference state file AND write to it (mv ... state_file pattern)
    # Exclude scripts that only READ state or write to OTHER files
    if grep -qE 'mv.*state_file|mv.*STATE_FILE|mv.*workflow-state' "$script" 2>/dev/null; then
      scripts_with_state_writes+=("$bname")
    elif grep -qE '>[[:space:]]*"\$.*state_file|>[[:space:]]*"\$.*STATE_FILE' "$script" 2>/dev/null; then
      scripts_with_state_writes+=("$bname")
    fi
  done

  # Each state-writing script must reference locking functions
  for script_name in "${scripts_with_state_writes[@]}"; do
    local script_path="$REPO_DIR/scripts/$script_name"
    local has_lock="no"
    if grep -q '_acquire_state_lock' "$script_path" 2>/dev/null; then
      has_lock="yes"
    fi
    assert_eq "AP-015: $script_name uses _acquire_state_lock" "yes" "$has_lock"

    local has_release="no"
    if grep -q '_release_state_lock' "$script_path" 2>/dev/null; then
      has_release="yes"
    fi
    assert_eq "AP-015: $script_name uses _release_state_lock" "yes" "$has_release"
  done

  # Verify workflow-advance.sh uses locking (transitively via write_state/locked_update_state)
  local adv_has_lock="no"
  if grep -qE '_acquire_state_lock|write_state|locked_update_state' "$ADV_HOOK" 2>/dev/null; then
    adv_has_lock="yes"
  fi
  assert_eq "AP-015: workflow-advance.sh uses locking (direct or transitive)" "yes" "$adv_has_lock"
}

# ============================================================================
# QA-002: Direct N-way concurrency test for the mkdir->O_EXCL lock primitive
# ============================================================================
# Regression guard for the O_EXCL pid-file exclusion gate (and the QA-001
# double-hold hardening). Spawns ~25 genuinely-separate processes (bash -c, each
# with its own PID — a subshell would share $$), each acquiring the SAME lock,
# doing a read-modify-write on a shared counter with a widened window, then
# releasing. Asserts (a) NO lost updates — the final counter equals the number
# of successful acquisitions, and (b) at no instant were two holders inside the
# critical section (a single-line "holders" marker that must never exceed 1).
# WOULD fail if mutual exclusion regressed: both detectors trip (lost counter
# updates AND a >1 holder marker). Deterministic under the O_EXCL exactly-one-
# winner regime with a generous 30s timeout, so all N acquire.

test_concurrent_nway_no_lost_update() {
  echo ""
  echo "=== QA-002: N-way concurrent _acquire_state_lock — no lost update, single-holder ==="

  setup_test_env
  source .correctless/scripts/lib.sh

  local shared="$TEST_DIR/.correctless/artifacts/counter-target"
  local counter_file="$TEST_DIR/counter.val"
  local holders_file="$TEST_DIR/holders.log"
  local success_dir="$TEST_DIR/success"
  local violation_file="$TEST_DIR/violation.log"
  local lib_path="$TEST_DIR/.correctless/scripts/lib.sh"

  rm -rf "${shared}.lock" "$counter_file" "$holders_file" "$success_dir" "$violation_file"
  mkdir -p "$success_dir"
  printf '0' > "$counter_file"
  : > "$holders_file"

  local N=25 i
  for i in $(seq 1 "$N"); do
    bash -c '
      set -uo pipefail
      lib="$1"; shared="$2"; counter="$3"; holders="$4"; succ="$5"; viol="$6"; id="$7"
      source "$lib"
      export CORRECTLESS_LOCK_TIMEOUT=30
      if _acquire_state_lock "$shared" 2>/dev/null; then
        # --- critical section ---
        # single-holder marker: record entry, then assert exactly one holder.
        printf "%s\n" "$id" >> "$holders"
        n_holders="$(wc -l < "$holders" | tr -d "[:space:]")"
        if [ "$n_holders" != "1" ]; then
          printf "%s\n" "$id" >> "$viol"
        fi
        # read-modify-write with a WIDENED window (the classic lost-update shape).
        cur="$(cat "$counter")"
        sleep 0.02
        printf "%s" "$((cur + 1))" > "$counter"
        # leave the critical section: clear our holder marker before releasing.
        : > "$holders"
        # --- end critical section ---
        _release_state_lock "$shared"
        printf "ok" > "$succ/$id"
      fi
    ' _ "$lib_path" "$shared" "$counter_file" "$holders_file" "$success_dir" "$violation_file" "$i" &
  done
  wait

  local successes final violations
  successes="$(find "$success_dir" -type f 2>/dev/null | wc -l | tr -d '[:space:]')"
  final="$(cat "$counter_file" 2>/dev/null)"
  if [ -f "$violation_file" ]; then
    violations="$(wc -l < "$violation_file" | tr -d '[:space:]')"
  else
    violations=0
  fi

  # (a) NO lost updates: final counter == number of successful acquisitions.
  assert_eq "QA-002a: counter == successful acquisitions (no lost update)" "$successes" "$final"

  # (b) Exactly-one-winner regime: with a 30s timeout all N processes acquire.
  assert_eq "QA-002b: all $N processes acquired the lock" "$N" "$successes"

  # (c) At no point were two holders simultaneously inside the critical section.
  assert_eq "QA-002c: never >1 concurrent holder in the critical section" "0" "$violations"

  # (d) No stale lock left behind after all releases.
  assert_not_exists "QA-002d: no stale lock dir after all releases" "${shared}.lock"
}

# ============================================================================
# Run all tests
# ============================================================================

test_write_state_lockfile
test_locked_update_state
test_stale_lock_detection
test_lock_timeout
test_lock_cleanup_on_all_paths
test_no_flock_dependency
test_all_state_writers_use_locking
test_concurrent_nway_no_lost_update

# ============================================================================
# Summary
# ============================================================================

echo ""
echo "=============================="
echo "  PASS: $PASS"
echo "  FAIL: $FAIL"
echo "=============================="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
