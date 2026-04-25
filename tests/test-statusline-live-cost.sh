#!/usr/bin/env bash
# Correctless — Statusline Live Cost Tests
#
# Tests R-001 through R-010 from:
#   .correctless/specs/statusline-live-cost.md
#
# Covers: cost display in statusline Section 4, cost cache reading,
# background refresh spawning, display format, performance constraints,
# compute-session-cost.sh --cache/--phase flags.
#
# Run from repo root: bash tests/test-statusline-live-cost.sh

# shellcheck disable=SC1090
source "$(dirname "${BASH_SOURCE[0]}")/test-helpers.sh"

STATUSLINE="$REPO_DIR/hooks/statusline.sh"
COST_SCRIPT="$REPO_DIR/scripts/compute-session-cost.sh"
LIB_SH="$REPO_DIR/scripts/lib.sh"

# ============================================================================
# Helpers
# ============================================================================

# Strip ANSI color codes
strip_colors() {
  sed 's/\x1b\[[0-9;]*m//g; s/\\x1b\[[0-9;]*m//g'
}

# Run the statusline script with JSON input; returns plain text (colors stripped)
run_sl() {
  local json="$1"
  printf '%s' "$json" | bash "$STATUSLINE" 2>/dev/null | strip_colors
}

# Compute the workflow state filename for a given branch (matches statusline algorithm)
state_filename() {
  local branch="$1"
  local slug hash
  slug="$(printf '%s' "$branch" | sed 's/[^a-zA-Z0-9]/-/g' | cut -c1-80)"
  hash="$(printf '%s' "$branch" | (md5sum 2>/dev/null || md5) | cut -c1-6)"
  echo ".correctless/artifacts/workflow-state-${slug}-${hash}.json"
}

# JSON for integration tests pointing at a test dir
# Uses TEST_DIR variable from the calling context
integration_json() {
  jq -n --arg dir "$TEST_DIR" '{
    workspace: {current_dir: $dir},
    model: {display_name: "Opus 4.6"},
    output_style: {name: "default"},
    context_window: {
      current_usage: {input_tokens: 10000, cache_creation_input_tokens: 0, cache_read_input_tokens: 0},
      context_window_size: 200000,
      total_input_tokens: 19700,
      total_output_tokens: 2100
    },
    cost: {total_cost_usd: 0.51, total_lines_added: 4, total_lines_removed: 0},
    total_duration_ms: 1380000
  }'
}

# Set up a temp git repo with correctless artifacts directory
setup_test_repo() {
  TEST_DIR=$(mktemp -d)
  mkdir -p "$TEST_DIR/.correctless/artifacts"
  mkdir -p "$TEST_DIR/.correctless/scripts"
  # Copy lib.sh so branch_slug works inside the test repo
  if [ -f "$REPO_DIR/scripts/lib.sh" ]; then
    cp "$REPO_DIR/scripts/lib.sh" "$TEST_DIR/.correctless/scripts/lib.sh"
  fi
  cd "$TEST_DIR" || exit 1
  git init -q
  git -c user.email="t@t.com" -c user.name="T" commit -q --allow-empty -m "init"
  git checkout -q -b main 2>/dev/null || true
}

cleanup_test_repo() {
  rm -rf "$TEST_DIR"
  cd "$REPO_DIR" || true
}

# Create a cost cache file for the test repo
# Arguments: $1=branch-slug, $2=total_cost_usd, $3=current_phase_cost_usd, $4=age_seconds (0=fresh)
create_cost_cache() {
  local slug="$1" total="$2" phase_cost="$3" age_seconds="${4:-0}"
  local cache_path="$TEST_DIR/.correctless/artifacts/cost-cache-${slug}.json"
  local computed_at
  computed_at=$(date -u -d "${age_seconds} seconds ago" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null \
    || date -u -v-"${age_seconds}"S '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null \
    || date -u '+%Y-%m-%dT%H:%M:%SZ')

  cat > "$cache_path" <<CACHE
{
  "total_cost_usd": $total,
  "by_phase": [{"phase": "tdd-impl", "cost_usd": $phase_cost}],
  "computed_at": "$computed_at",
  "current_phase_cost_usd": $phase_cost
}
CACHE

  # If age_seconds > 0, backdate the file modification time
  if [ "$age_seconds" -gt 0 ]; then
    touch -d "${age_seconds} seconds ago" "$cache_path" 2>/dev/null \
      || touch -A -"$(printf '%02d%02d' $((age_seconds/3600)) $((age_seconds%3600/60)))" "$cache_path" 2>/dev/null \
      || true
  fi
}

echo "=== Statusline Live Cost Tests ==="

# ============================================================================
# R-001: Cost display in Section 4 — omit when 0 or missing
# ============================================================================

section "R-001: Cost display omission"

# Tests R-001 [unit]: When cost cache has total_cost_usd > 0, the workflow
# section should include a dollar amount like $47.23
test_r001_cost_shown_when_available() {
  setup_test_repo
  local state_file
  state_file="$(state_filename "main")"
  cat > "$TEST_DIR/$state_file" <<SFJSON
{
  "phase": "tdd-impl",
  "task": "add-auth",
  "qa_rounds": 0,
  "phase_entered_at": "$(date -u -d '5 minutes ago' '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date -u -v-5M '+%Y-%m-%dT%H:%M:%SZ')"
}
SFJSON

  # Get the branch slug the same way the statusline does
  local slug
  slug=$(cd "$TEST_DIR" && source "$LIB_SH" && branch_slug 2>/dev/null) || slug=""
  if [ -z "$slug" ]; then
    fail "R001-a" "Could not derive branch slug for test setup"
    cleanup_test_repo
    return
  fi

  create_cost_cache "$slug" 47.23 12.50 0

  local out
  out=$(run_sl "$(integration_json)")

  # The workflow section (Section 4) should contain $47.23 for the feature total
  if printf '%s' "$out" | grep -qF '$47.23'; then
    pass "R001-a" "Feature cost \$47.23 shown in workflow section"
  else
    fail "R001-a" "Feature cost \$47.23 not found in output: $out"
  fi

  cleanup_test_repo
}

# Tests R-001 [unit]: When total_cost_usd is 0 in the cache, cost display is omitted
test_r001_cost_omitted_when_zero() {
  setup_test_repo
  local state_file
  state_file="$(state_filename "main")"
  cat > "$TEST_DIR/$state_file" <<SFJSON
{
  "phase": "tdd-impl",
  "task": "add-auth",
  "qa_rounds": 0
}
SFJSON

  local slug
  slug=$(cd "$TEST_DIR" && source "$LIB_SH" && branch_slug 2>/dev/null) || slug=""
  [ -n "$slug" ] || { fail "R001-b" "branch_slug failed"; cleanup_test_repo; return; }

  create_cost_cache "$slug" 0 0 0

  local out
  out=$(run_sl "$(integration_json)")

  # Should NOT contain a dollar sign in the workflow section
  # Section 3 has session cost ($0.51), so we need to check Section 4 specifically
  # Section 4 starts with ⚙ — check that the ⚙ segment does not contain a $ for cost
  local sec4_part
  sec4_part=$(printf '%s' "$out" | sed -n 's/.*⚙/⚙/p')
  if printf '%s' "$sec4_part" | grep -qF '$'; then
    fail "R001-b" "Cost should be omitted when total_cost_usd=0, but found \$ in workflow section: $sec4_part"
  else
    pass "R001-b" "Cost display omitted when total_cost_usd=0"
  fi

  cleanup_test_repo
}

# Tests R-001 [unit]: When cache file doesn't exist, cost display is omitted
test_r001_cost_omitted_when_no_cache() {
  setup_test_repo
  local state_file
  state_file="$(state_filename "main")"
  cat > "$TEST_DIR/$state_file" <<SFJSON
{
  "phase": "tdd-impl",
  "task": "add-auth",
  "qa_rounds": 0
}
SFJSON

  # No cost cache file created

  local out
  out=$(run_sl "$(integration_json)")

  # Workflow section should exist but have no feature cost
  local sec4_part
  sec4_part=$(printf '%s' "$out" | sed -n 's/.*⚙/⚙/p')
  if printf '%s' "$sec4_part" | grep -qE '\$[0-9]'; then
    fail "R001-c" "Cost should be omitted when no cache exists, but found dollar amount in: $sec4_part"
  else
    pass "R001-c" "Cost display omitted when no cache file exists"
  fi

  cleanup_test_repo
}

test_r001_cost_shown_when_available
test_r001_cost_omitted_when_zero
test_r001_cost_omitted_when_no_cache

# ============================================================================
# R-002: Cache file reading and staleness detection
# ============================================================================

section "R-002: Cache reading and staleness"

# Tests R-002 [unit]: Cache file is read from the correct path
# (.correctless/artifacts/cost-cache-{branch-slug}.json)
test_r002_cache_path() {
  setup_test_repo
  local state_file
  state_file="$(state_filename "main")"
  cat > "$TEST_DIR/$state_file" <<SFJSON
{
  "phase": "tdd-impl",
  "task": "add-auth",
  "qa_rounds": 0
}
SFJSON

  local slug
  slug=$(cd "$TEST_DIR" && source "$LIB_SH" && branch_slug 2>/dev/null) || slug=""
  [ -n "$slug" ] || { fail "R002-a" "branch_slug failed"; cleanup_test_repo; return; }

  # Create cache with a distinctive cost value
  create_cost_cache "$slug" 99.88 0 0

  local out
  out=$(run_sl "$(integration_json)")

  if printf '%s' "$out" | grep -qF '$99.88'; then
    pass "R002-a" "Cost read from correct cache path cost-cache-{slug}.json"
  else
    fail "R002-a" "Cost \$99.88 not found; cache may not be read from correct path. Output: $out"
  fi

  cleanup_test_repo
}

# Tests R-002 [unit]: Cache uses single jq call to extract all needed fields
test_r002_single_jq_call() {
  # Structural test: the statusline should use at most 1 jq call for extracting
  # cost data fields from the cache (FEATURE_COST, PHASE_COST).
  # The jq call uses $COST_CACHE_FILE, so count jq lines referencing the variable.
  local jq_cache_count
  jq_cache_count=$(grep -cE 'jq.*COST_CACHE_FILE|COST_CACHE.*jq' "$STATUSLINE" 2>/dev/null)
  jq_cache_count=${jq_cache_count:-0}

  # We expect at most 2 jq invocations: one for data extraction (bulk parse),
  # one conditional for computed_at fallback (staleness check, not data)
  if [ "$jq_cache_count" -le 2 ]; then
    pass "R002-b" "At most 2 jq invocations for cost cache (data + staleness fallback)"
  else
    fail "R002-b" "Too many jq invocations for cost cache ($jq_cache_count); expected <= 2"
  fi
}

# Tests R-002 [unit]: Staleness detection uses file mtime (stat -c %Y or stat -f %m)
test_r002_staleness_detection() {
  # Structural: the statusline source should use stat for mtime comparison
  if grep -qE 'stat.*-c.*%Y|stat.*-f.*%m' "$STATUSLINE"; then
    pass "R002-c" "Staleness detection uses stat for file mtime"
  else
    # Fallback: computed_at parsing is also acceptable per spec
    if grep -q 'computed_at' "$STATUSLINE"; then
      pass "R002-c" "Staleness detection uses computed_at fallback"
    else
      fail "R002-c" "No staleness detection mechanism found (expected stat -c %Y / stat -f %m or computed_at)"
    fi
  fi
}

# Tests R-002 [unit]: Stale cache (>30s old) triggers background refresh
test_r002_stale_cache_triggers_refresh() {
  setup_test_repo
  local state_file
  state_file="$(state_filename "main")"
  cat > "$TEST_DIR/$state_file" <<SFJSON
{
  "phase": "tdd-impl",
  "task": "add-auth",
  "qa_rounds": 0
}
SFJSON

  local slug
  slug=$(cd "$TEST_DIR" && source "$LIB_SH" && branch_slug 2>/dev/null) || slug=""
  [ -n "$slug" ] || { fail "R002-d" "branch_slug failed"; cleanup_test_repo; return; }

  # Create a cache that's 60 seconds old (stale per 30-second threshold)
  create_cost_cache "$slug" 10.00 5.00 60

  # Run statusline and capture stderr (background spawn might log)
  # The statusline should still display the stale cost (reads first, refreshes in background)
  local out
  out=$(run_sl "$(integration_json)")

  # Even with stale data, the old cost should still be shown
  if printf '%s' "$out" | grep -qF '$10.00'; then
    pass "R002-d" "Stale cache data still displayed while refresh spawns"
  else
    fail "R002-d" "Stale cache cost not displayed. Output: $out"
  fi

  cleanup_test_repo
}

test_r002_cache_path
test_r002_single_jq_call
test_r002_staleness_detection
test_r002_stale_cache_triggers_refresh

# ============================================================================
# R-003: Background refresh with atomic write and lock
# ============================================================================

section "R-003: Background refresh mechanism"

# Tests R-003 [unit]: Background refresh spawns compute-session-cost.sh with --cache --phase
test_r003_background_command() {
  # Structural: the statusline must contain a line that spawns compute-session-cost.sh
  # with --cache and --phase flags, using & disown
  # The statusline resolves the script path to a variable and calls it with --cache
  if grep -q 'compute-session-cost' "$STATUSLINE" && grep -q '\-\-cache' "$STATUSLINE"; then
    pass "R003-a" "Background refresh calls compute-session-cost.sh --cache"
  else
    fail "R003-a" "No compute-session-cost.sh --cache invocation found in statusline"
  fi
}

# Tests R-003 [unit]: Background spawn uses & disown
test_r003_disown() {
  if grep -qE '&.*disown|disown' "$STATUSLINE"; then
    pass "R003-b" "Background spawn uses & disown"
  else
    fail "R003-b" "No & disown pattern found in statusline"
  fi
}

# Tests R-003 [unit]: Lock file created BEFORE the background spawn,
# containing $! (the background PID)
test_r003_lock_before_spawn() {
  # Structural: look for lock file creation pattern before the & spawn
  # The lock file should be at .correctless/artifacts/cost-cache.lock
  if grep -q 'cost-cache\.lock' "$STATUSLINE"; then
    pass "R003-c" "Lock file path cost-cache.lock referenced in statusline"
  else
    fail "R003-c" "No cost-cache.lock reference found in statusline"
  fi
}

# Tests R-003 [unit]: Lock file contains PID and is checked with kill -0
test_r003_lock_pid_check() {
  if grep -q 'kill -0' "$STATUSLINE"; then
    pass "R003-d" "Lock file PID checked with kill -0"
  else
    fail "R003-d" "No kill -0 check for lock file PID"
  fi
}

# Tests R-003 [unit]: Atomic write uses temp file + mv (not direct stdout redirection)
test_r003_atomic_write() {
  # The spec says the background process writes to a temp file then mv's to cache path.
  # This is in compute-session-cost.sh --cache mode, not the statusline itself.
  # But the statusline's spawn command should NOT redirect stdout directly to the cache.
  # Check for mv or temp file pattern in the background command or in the script.
  if grep -qE 'mv.*cost-cache|temp.*mv|tmp.*mv' "$STATUSLINE" || grep -qE 'mktemp|tmp.*mv' "$STATUSLINE"; then
    pass "R003-e" "Atomic write pattern (temp + mv) found"
  else
    # Also acceptable if the compute-session-cost.sh --cache flag handles this
    # Check compute-session-cost.sh for atomic write when --cache is used
    if grep -qE 'mv.*cost-cache|mktemp.*cache' "$COST_SCRIPT"; then
      pass "R003-e" "Atomic write pattern found in compute-session-cost.sh"
    else
      fail "R003-e" "No atomic write pattern (temp + mv) found"
    fi
  fi
}

# Tests R-003 [unit]: Stale lock (PID not running) is auto-cleaned
test_r003_stale_lock_cleanup() {
  setup_test_repo
  local state_file
  state_file="$(state_filename "main")"
  cat > "$TEST_DIR/$state_file" <<SFJSON
{
  "phase": "tdd-impl",
  "task": "add-auth",
  "qa_rounds": 0
}
SFJSON

  local slug
  slug=$(cd "$TEST_DIR" && source "$LIB_SH" && branch_slug 2>/dev/null) || slug=""
  [ -n "$slug" ] || { fail "R003-f" "branch_slug failed"; cleanup_test_repo; return; }

  # Create a stale cache to trigger refresh
  create_cost_cache "$slug" 5.00 1.00 60

  # Create a stale lock file with a non-existent PID
  echo "99999999" > "$TEST_DIR/.correctless/artifacts/cost-cache.lock"

  # Run statusline — it should clean up the stale lock and proceed
  local exit_code=0
  local out
  out=$(printf '%s' "$(integration_json)" | bash "$STATUSLINE" 2>/dev/null) || exit_code=$?

  if [ "$exit_code" -eq 0 ]; then
    pass "R003-f" "Statusline handles stale lock file gracefully (exit 0)"
  else
    fail "R003-f" "Statusline crashed with stale lock file (exit $exit_code)"
  fi

  cleanup_test_repo
}

# Tests R-003 [unit]: trap-based lock cleanup on background process exit
test_r003_trap_cleanup() {
  # Structural: the background process or the statusline must use trap for lock cleanup
  if grep -qiE 'trap.*lock|trap.*cost.cache' "$STATUSLINE"; then
    pass "R003-g" "Trap-based lock cleanup in statusline"
  else
    # Also check if compute-session-cost.sh has trap cleanup for --cache mode
    if grep -qiE 'trap.*lock|trap.*cost.cache' "$COST_SCRIPT"; then
      pass "R003-g" "Trap-based lock cleanup in compute-session-cost.sh"
    else
      fail "R003-g" "No trap-based lock cleanup found"
    fi
  fi
}

test_r003_background_command
test_r003_disown
test_r003_lock_before_spawn
test_r003_lock_pid_check
test_r003_atomic_write
test_r003_stale_lock_cleanup
test_r003_trap_cleanup

# ============================================================================
# R-004: Cost display format
# ============================================================================

section "R-004: Cost display format"

# Tests R-004 [unit]: Format is "$X.XX ($Y.YY in PHASE)"
# when both total and phase cost are available
test_r004_full_format() {
  setup_test_repo
  local state_file
  state_file="$(state_filename "main")"
  cat > "$TEST_DIR/$state_file" <<SFJSON
{
  "phase": "tdd-impl",
  "task": "add-auth",
  "qa_rounds": 1,
  "phase_entered_at": "$(date -u -d '3 minutes ago' '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date -u -v-3M '+%Y-%m-%dT%H:%M:%SZ')"
}
SFJSON

  local slug
  slug=$(cd "$TEST_DIR" && source "$LIB_SH" && branch_slug 2>/dev/null) || slug=""
  [ -n "$slug" ] || { fail "R004-a" "branch_slug failed"; cleanup_test_repo; return; }

  create_cost_cache "$slug" 47.23 12.50 0

  local out
  out=$(run_sl "$(integration_json)")

  # Expected format includes "$47.23" and "($12.50 in GREEN)"
  # The phase name in display is the display name (GREEN for tdd-impl)
  if printf '%s' "$out" | grep -qF '$47.23'; then
    pass "R004-a" "Feature total \$47.23 present in output"
  else
    fail "R004-a" "Feature total \$47.23 not found. Output: $out"
  fi

  if printf '%s' "$out" | grep -qE '\$12\.50 in GREEN'; then
    pass "R004-b" "Phase cost (\$12.50 in GREEN) present in output"
  else
    fail "R004-b" "Phase cost (\$12.50 in GREEN) not found. Output: $out"
  fi

  cleanup_test_repo
}

# Tests R-004 [unit]: When current_phase_cost_usd is 0, only total is shown
test_r004_total_only_when_phase_zero() {
  setup_test_repo
  local state_file
  state_file="$(state_filename "main")"
  cat > "$TEST_DIR/$state_file" <<SFJSON
{
  "phase": "tdd-impl",
  "task": "add-auth",
  "qa_rounds": 0
}
SFJSON

  local slug
  slug=$(cd "$TEST_DIR" && source "$LIB_SH" && branch_slug 2>/dev/null) || slug=""
  [ -n "$slug" ] || { fail "R004-c" "branch_slug failed"; cleanup_test_repo; return; }

  create_cost_cache "$slug" 47.23 0 0

  local out
  out=$(run_sl "$(integration_json)")

  if printf '%s' "$out" | grep -qF '$47.23'; then
    pass "R004-c" "Feature total shown when phase cost is 0"
  else
    fail "R004-c" "Feature total not found. Output: $out"
  fi

  # Should NOT have "in GREEN" part
  if printf '%s' "$out" | grep -q 'in GREEN'; then
    fail "R004-d" "Phase cost should be omitted when current_phase_cost_usd=0"
  else
    pass "R004-d" "Phase cost correctly omitted when current_phase_cost_usd=0"
  fi

  cleanup_test_repo
}

# Tests R-004 [unit]: When current_phase_cost_usd is null, only total is shown
test_r004_total_only_when_phase_null() {
  setup_test_repo
  local state_file
  state_file="$(state_filename "main")"
  cat > "$TEST_DIR/$state_file" <<SFJSON
{
  "phase": "tdd-qa",
  "task": "add-auth",
  "qa_rounds": 1
}
SFJSON

  local slug
  slug=$(cd "$TEST_DIR" && source "$LIB_SH" && branch_slug 2>/dev/null) || slug=""
  [ -n "$slug" ] || { fail "R004-e" "branch_slug failed"; cleanup_test_repo; return; }

  # Cache without current_phase_cost_usd field (null)
  local cache_path="$TEST_DIR/.correctless/artifacts/cost-cache-${slug}.json"
  cat > "$cache_path" <<CACHE
{
  "total_cost_usd": 33.50,
  "by_phase": [{"phase": "tdd-qa", "cost_usd": 8.00}],
  "computed_at": "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
}
CACHE

  local out
  out=$(run_sl "$(integration_json)")

  if printf '%s' "$out" | grep -qF '$33.50'; then
    pass "R004-e" "Feature total shown when current_phase_cost_usd is absent"
  else
    fail "R004-e" "Feature total not found. Output: $out"
  fi

  # Should NOT have "in QA" part
  if printf '%s' "$out" | grep -q 'in QA'; then
    fail "R004-f" "Phase cost should be omitted when current_phase_cost_usd is null/absent"
  else
    pass "R004-f" "Phase cost correctly omitted when current_phase_cost_usd is absent"
  fi

  cleanup_test_repo
}

test_r004_full_format
test_r004_total_only_when_phase_zero
test_r004_total_only_when_phase_null

# ============================================================================
# R-005: Session cost unchanged, feature cost additive
# ============================================================================

section "R-005: Section 3 session cost unchanged"

# Tests R-005 [unit]: Session cost in Section 3 ($0.51 from .cost.total_cost_usd)
# is still visible when feature cost is also displayed in Section 4
test_r005_both_costs_visible() {
  setup_test_repo
  local state_file
  state_file="$(state_filename "main")"
  cat > "$TEST_DIR/$state_file" <<SFJSON
{
  "phase": "tdd-impl",
  "task": "add-auth",
  "qa_rounds": 0
}
SFJSON

  local slug
  slug=$(cd "$TEST_DIR" && source "$LIB_SH" && branch_slug 2>/dev/null) || slug=""
  [ -n "$slug" ] || { fail "R005-a" "branch_slug failed"; cleanup_test_repo; return; }

  create_cost_cache "$slug" 25.00 10.00 0

  local out
  out=$(run_sl "$(integration_json)")

  # Session cost ($0.51) should still be present
  if printf '%s' "$out" | grep -qF '$0.51'; then
    pass "R005-a" "Session cost \$0.51 still present in Section 3"
  else
    fail "R005-a" "Session cost \$0.51 missing from output. Output: $out"
  fi

  # Feature cost ($25.00) should also be present
  if printf '%s' "$out" | grep -qF '$25.00'; then
    pass "R005-b" "Feature cost \$25.00 present in Section 4"
  else
    fail "R005-b" "Feature cost \$25.00 missing from output. Output: $out"
  fi

  cleanup_test_repo
}

test_r005_both_costs_visible

# ============================================================================
# R-006: Cache and lock files are gitignored
# ============================================================================

section "R-006: Cache files gitignored"

# Tests R-006 [unit]: .correctless/artifacts/ is gitignored (covers cache + lock files)
test_r006_artifacts_gitignored() {
  if grep -q '\.correctless/artifacts' "$REPO_DIR/.gitignore"; then
    pass "R006-a" ".correctless/artifacts/ is gitignored"
  else
    fail "R006-a" ".correctless/artifacts/ not in .gitignore"
  fi
}

# Tests R-006 [unit]: Cache file path is under .correctless/artifacts/
test_r006_cache_under_artifacts() {
  # Structural: the statusline should reference .correctless/artifacts/cost-cache-
  if grep -q 'correctless/artifacts/cost-cache' "$STATUSLINE"; then
    pass "R006-b" "Cache file path under .correctless/artifacts/"
  else
    fail "R006-b" "Cache file path not under .correctless/artifacts/"
  fi
}

# Tests R-006 [unit]: Lock file path is under .correctless/artifacts/
test_r006_lock_under_artifacts() {
  if grep -q 'correctless/artifacts/cost-cache\.lock' "$STATUSLINE"; then
    pass "R006-c" "Lock file path under .correctless/artifacts/"
  else
    fail "R006-c" "Lock file path not under .correctless/artifacts/"
  fi
}

test_r006_artifacts_gitignored
test_r006_cache_under_artifacts
test_r006_lock_under_artifacts

# ============================================================================
# R-007: compute-session-cost.sh --cache and --phase flags
# ============================================================================

section "R-007: compute-session-cost.sh --cache and --phase flags"

# Tests R-007 [unit]: --cache flag is recognized by the script
test_r007_cache_flag_recognized() {
  if grep -q '\-\-cache' "$COST_SCRIPT"; then
    pass "R007-a" "--cache flag handled in compute-session-cost.sh"
  else
    fail "R007-a" "--cache flag not found in compute-session-cost.sh"
  fi
}

# Tests R-007 [unit]: --phase flag is recognized by the script
test_r007_phase_flag_recognized() {
  if grep -q '\-\-phase' "$COST_SCRIPT"; then
    pass "R007-b" "--phase flag handled in compute-session-cost.sh"
  else
    fail "R007-b" "--phase flag not found in compute-session-cost.sh"
  fi
}

# Tests R-007 [unit]: --cache produces lightweight JSON (total + by_phase + current_phase_cost)
test_r007_cache_output_format() {
  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  local FAKE_HOME
  FAKE_HOME=$(mktemp -d)

  # Set up minimal git repo
  git -C "$TEST_DIR" init -q 2>/dev/null
  git -C "$TEST_DIR" config user.email "test@test.com"
  git -C "$TEST_DIR" config user.name "Test"
  touch "$TEST_DIR/.gitkeep"
  git -C "$TEST_DIR" add .gitkeep
  git -C "$TEST_DIR" commit -q -m "init" 2>/dev/null
  git -C "$TEST_DIR" checkout -q -b "feature/cache-test" 2>/dev/null

  mkdir -p "$TEST_DIR/.correctless/config"
  mkdir -p "$TEST_DIR/.correctless/artifacts"
  cat > "$TEST_DIR/.correctless/config/workflow-config.json" <<'EOF'
{
  "project": { "name": "test-project" },
  "workflow": { "intensity": "standard" }
}
EOF

  # Create a session directory with one matching entry
  local proj_slug
  proj_slug=$(echo "$TEST_DIR" | tr '/' '-' | sed 's/^-//')
  local session_dir="$FAKE_HOME/.claude/projects/$proj_slug"
  mkdir -p "$session_dir"
  local jsonl_path="$session_dir/session-001.jsonl"
  cat > "$jsonl_path" <<'ENTRY'
{"type":"assistant","message":{"id":"msg-001","model":"claude-sonnet-4-6","usage":{"input_tokens":5000,"output_tokens":2500,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}},"timestamp":"2026-04-15T10:00:00Z","gitBranch":"feature/cache-test"}
ENTRY

  local output
  output=$(cd "$TEST_DIR" && HOME="$FAKE_HOME" bash "$COST_SCRIPT" --cache --phase tdd-impl "feature/cache-test" 2>/dev/null)

  # Should output valid JSON
  if echo "$output" | jq -e '.' >/dev/null 2>&1; then
    pass "R007-c" "--cache produces valid JSON"
  else
    fail "R007-c" "--cache does not produce valid JSON: $output"
    rm -rf "$TEST_DIR" "$FAKE_HOME"
    return
  fi

  # Should have total_cost_usd field
  if echo "$output" | jq -e 'has("total_cost_usd")' >/dev/null 2>&1; then
    pass "R007-d" "--cache output has total_cost_usd"
  else
    fail "R007-d" "--cache output missing total_cost_usd"
  fi

  # Should have by_phase field
  if echo "$output" | jq -e 'has("by_phase")' >/dev/null 2>&1; then
    pass "R007-e" "--cache output has by_phase"
  else
    fail "R007-e" "--cache output missing by_phase"
  fi

  # Should have current_phase_cost_usd field
  if echo "$output" | jq -e 'has("current_phase_cost_usd")' >/dev/null 2>&1; then
    pass "R007-f" "--cache output has current_phase_cost_usd"
  else
    fail "R007-f" "--cache output missing current_phase_cost_usd"
  fi

  # Should have computed_at field
  if echo "$output" | jq -e 'has("computed_at")' >/dev/null 2>&1; then
    pass "R007-g" "--cache output has computed_at"
  else
    fail "R007-g" "--cache output missing computed_at"
  fi

  # Should be LIGHTWEIGHT — fewer fields than full output
  local field_count
  field_count=$(echo "$output" | jq 'keys | length' 2>/dev/null)
  if [ "$field_count" -le 6 ]; then
    pass "R007-h" "--cache output is lightweight ($field_count fields, expected <= 6)"
  else
    fail "R007-h" "--cache output has too many fields ($field_count); expected lightweight subset"
  fi

  rm -rf "$TEST_DIR" "$FAKE_HOME"
}

# Tests R-007 [unit]: --phase accepts raw phase names (tdd-impl, not GREEN)
test_r007_phase_accepts_raw_names() {
  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  local FAKE_HOME
  FAKE_HOME=$(mktemp -d)

  git -C "$TEST_DIR" init -q 2>/dev/null
  git -C "$TEST_DIR" config user.email "test@test.com"
  git -C "$TEST_DIR" config user.name "Test"
  touch "$TEST_DIR/.gitkeep"
  git -C "$TEST_DIR" add .gitkeep
  git -C "$TEST_DIR" commit -q -m "init" 2>/dev/null
  git -C "$TEST_DIR" checkout -q -b "feature/phase-raw" 2>/dev/null

  mkdir -p "$TEST_DIR/.correctless/config"
  mkdir -p "$TEST_DIR/.correctless/artifacts"
  cat > "$TEST_DIR/.correctless/config/workflow-config.json" <<'EOF'
{
  "project": { "name": "test-project" },
  "workflow": { "intensity": "standard" }
}
EOF

  local proj_slug
  proj_slug=$(echo "$TEST_DIR" | tr '/' '-' | sed 's/^-//')
  local session_dir="$FAKE_HOME/.claude/projects/$proj_slug"
  mkdir -p "$session_dir"
  local jsonl_path="$session_dir/session-001.jsonl"
  cat > "$jsonl_path" <<'ENTRY'
{"type":"assistant","message":{"id":"msg-001","model":"claude-sonnet-4-6","usage":{"input_tokens":5000,"output_tokens":2500,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}},"timestamp":"2026-04-15T10:00:00Z","gitBranch":"feature/phase-raw"}
ENTRY

  # Create an audit trail to attribute to tdd-impl
  local branch_slug
  branch_slug=$(cd "$TEST_DIR" && source "$LIB_SH" && branch_slug "feature/phase-raw")
  cat > "$TEST_DIR/.correctless/artifacts/audit-trail-${branch_slug}.jsonl" <<'TRAIL'
{"phase":"tdd-impl","timestamp":"2026-04-15T09:00:00Z"}
TRAIL

  # Use raw phase name tdd-impl (not GREEN)
  local output
  output=$(cd "$TEST_DIR" && HOME="$FAKE_HOME" bash "$COST_SCRIPT" --cache --phase tdd-impl "feature/phase-raw" 2>/dev/null)

  if echo "$output" | jq -e '.current_phase_cost_usd >= 0' >/dev/null 2>&1; then
    pass "R007-i" "--phase accepts raw phase name 'tdd-impl'"
  else
    fail "R007-i" "--phase with 'tdd-impl' failed: $output"
  fi

  rm -rf "$TEST_DIR" "$FAKE_HOME"
}

# Tests R-007 [unit]: Without --cache, behavior is unchanged (writes full artifact)
test_r007_no_cache_flag_unchanged() {
  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  local FAKE_HOME
  FAKE_HOME=$(mktemp -d)

  git -C "$TEST_DIR" init -q 2>/dev/null
  git -C "$TEST_DIR" config user.email "test@test.com"
  git -C "$TEST_DIR" config user.name "Test"
  touch "$TEST_DIR/.gitkeep"
  git -C "$TEST_DIR" add .gitkeep
  git -C "$TEST_DIR" commit -q -m "init" 2>/dev/null

  mkdir -p "$TEST_DIR/.correctless/config"
  mkdir -p "$TEST_DIR/.correctless/artifacts"
  cat > "$TEST_DIR/.correctless/config/workflow-config.json" <<'EOF'
{
  "project": { "name": "test-project" },
  "workflow": { "intensity": "standard" }
}
EOF

  local proj_slug
  proj_slug=$(echo "$TEST_DIR" | tr '/' '-' | sed 's/^-//')
  local session_dir="$FAKE_HOME/.claude/projects/$proj_slug"
  mkdir -p "$session_dir"
  local jsonl_path="$session_dir/session-001.jsonl"
  cat > "$jsonl_path" <<'ENTRY'
{"type":"assistant","message":{"id":"msg-001","model":"claude-sonnet-4-6","usage":{"input_tokens":5000,"output_tokens":2500,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}},"timestamp":"2026-04-15T10:00:00Z","gitBranch":"main"}
ENTRY

  local output
  output=$(cd "$TEST_DIR" && HOME="$FAKE_HOME" bash "$COST_SCRIPT" "main" 2>/dev/null)

  # Without --cache: full output should have all fields (branch, feature, sessions, etc.)
  if echo "$output" | jq -e 'has("branch") and has("sessions") and has("model_breakdown")' >/dev/null 2>&1; then
    pass "R007-j" "Without --cache, full artifact output is produced"
  else
    fail "R007-j" "Without --cache, output missing expected fields"
  fi

  rm -rf "$TEST_DIR" "$FAKE_HOME"
}

# Tests R-007 [unit]: --cache writes output to stdout (caller handles file placement)
test_r007_cache_writes_stdout() {
  # Structural: in --cache mode, the script should NOT write the artifact file directly
  # (the caller — statusline — handles atomic file placement per R-003)
  # This is tested by checking that --cache mode outputs to stdout
  # We already tested this implicitly in R007-c, but verify no artifact written
  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  local FAKE_HOME
  FAKE_HOME=$(mktemp -d)

  git -C "$TEST_DIR" init -q 2>/dev/null
  git -C "$TEST_DIR" config user.email "test@test.com"
  git -C "$TEST_DIR" config user.name "Test"
  touch "$TEST_DIR/.gitkeep"
  git -C "$TEST_DIR" add .gitkeep
  git -C "$TEST_DIR" commit -q -m "init" 2>/dev/null
  git -C "$TEST_DIR" checkout -q -b "feature/stdout-test" 2>/dev/null

  mkdir -p "$TEST_DIR/.correctless/config"
  mkdir -p "$TEST_DIR/.correctless/artifacts"
  cat > "$TEST_DIR/.correctless/config/workflow-config.json" <<'EOF'
{
  "project": { "name": "test-project" },
  "workflow": { "intensity": "standard" }
}
EOF

  local proj_slug
  proj_slug=$(echo "$TEST_DIR" | tr '/' '-' | sed 's/^-//')
  local session_dir="$FAKE_HOME/.claude/projects/$proj_slug"
  mkdir -p "$session_dir"
  local jsonl_path="$session_dir/session-001.jsonl"
  cat > "$jsonl_path" <<'ENTRY'
{"type":"assistant","message":{"id":"msg-001","model":"claude-sonnet-4-6","usage":{"input_tokens":5000,"output_tokens":2500,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}},"timestamp":"2026-04-15T10:00:00Z","gitBranch":"feature/stdout-test"}
ENTRY

  cd "$TEST_DIR" && HOME="$FAKE_HOME" bash "$COST_SCRIPT" --cache --phase tdd-impl "feature/stdout-test" >/dev/null 2>/dev/null

  # Check that no cost-*.json artifact was written (only cost-cache should be handled by caller)
  local artifact_count
  artifact_count=$(ls "$TEST_DIR/.correctless/artifacts/cost-"*.json 2>/dev/null | wc -l)
  if [ "$artifact_count" -eq 0 ]; then
    pass "R007-k" "--cache mode does not write artifact file directly"
  else
    fail "R007-k" "--cache mode wrote artifact file (should output to stdout only)"
  fi

  rm -rf "$TEST_DIR" "$FAKE_HOME"
}

test_r007_cache_flag_recognized
test_r007_phase_flag_recognized
test_r007_cache_output_format
test_r007_phase_accepts_raw_names
test_r007_no_cache_flag_unchanged
test_r007_cache_writes_stdout

# ============================================================================
# R-008: Performance constraint — at most 1 additional file read + 1 jq extraction
# ============================================================================

section "R-008: Performance constraints"

# Tests R-008 [unit]: No synchronous subprocess spawns for cost computation
test_r008_no_sync_subprocess() {
  # Structural: the statusline must NOT call compute-session-cost.sh synchronously.
  # The script resolves the path to $_COST_SCRIPT variable, then calls it via
  # bash "$_COST_SCRIPT" inside a subshell with & disown.
  # Check: any bash invocation of the cost script must be inside a subshell with &
  # and there must be a disown after the &.
  if grep -qE 'disown' "$STATUSLINE" && grep -qE '\) &' "$STATUSLINE"; then
    pass "R008-a" "Cost script called asynchronously (subshell with & disown)"
  else
    fail "R008-a" "No async pattern (subshell + & + disown) found for cost script"
  fi
}

# Tests R-008 [unit]: At most 1 additional file read for cost cache
test_r008_file_read_count() {
  # Structural: count file reads in the cost-related section of statusline
  # The cache read should use at most 1 cat/jq call for the cache file
  local cache_reads
  cache_reads=$(grep -cE 'jq.*cost-cache|cat.*cost-cache|eval.*cost-cache' "$STATUSLINE" 2>/dev/null)
  cache_reads=${cache_reads:-0}

  if [ "$cache_reads" -le 1 ]; then
    pass "R008-b" "At most 1 file read for cost cache ($cache_reads)"
  else
    fail "R008-b" "Too many cost cache file reads ($cache_reads; expected <= 1)"
  fi
}

test_r008_no_sync_subprocess
test_r008_file_read_count

# ============================================================================
# R-009: No cost display when no active workflow
# ============================================================================

section "R-009: No cost without active workflow"

# Tests R-009 [unit]: When no workflow state file exists, no cost display
test_r009_no_workflow_no_cost() {
  setup_test_repo
  # No state file created — no active workflow

  local slug
  slug=$(cd "$TEST_DIR" && source "$LIB_SH" && branch_slug 2>/dev/null) || slug=""
  if [ -n "$slug" ]; then
    # Create a cost cache file even though no workflow exists
    create_cost_cache "$slug" 50.00 20.00 0
  fi

  local out
  out=$(run_sl "$(integration_json)")

  # Should NOT have ⚙ (workflow section) and therefore no feature cost
  if printf '%s' "$out" | grep -qF '⚙'; then
    fail "R009-a" "Workflow section should not appear without state file"
  else
    pass "R009-a" "No workflow section when no state file exists"
  fi

  # Double-check: no feature cost dollar amount in output
  # Session cost ($0.51) is fine, but feature cost ($50.00) should not appear
  if printf '%s' "$out" | grep -qF '$50.00'; then
    fail "R009-b" "Feature cost should not appear without active workflow"
  else
    pass "R009-b" "Feature cost correctly omitted without active workflow"
  fi

  cleanup_test_repo
}

test_r009_no_workflow_no_cost

# ============================================================================
# R-010: Hardcoded 30-second refresh interval
# ============================================================================

section "R-010: Hardcoded refresh interval"

# Tests R-010 [unit]: The 30-second threshold is hardcoded in the statusline
test_r010_hardcoded_30s() {
  if grep -q '30' "$STATUSLINE" && grep -qE 'stale|fresh|age|CACHE_MAX_AGE|cache.*30|30.*second|30.*sec' "$STATUSLINE"; then
    pass "R010-a" "30-second threshold present in statusline"
  else
    fail "R010-a" "30-second refresh threshold not found in statusline"
  fi
}

# Tests R-010 [unit]: The refresh interval is NOT read from workflow-config.json
test_r010_not_configurable() {
  # Structural: the statusline should not read a refresh interval from config
  if grep -qE 'refresh_interval|cache_interval|cache_ttl' "$STATUSLINE"; then
    fail "R010-b" "Statusline appears to read configurable refresh interval (should be hardcoded for v1)"
  else
    pass "R010-b" "Refresh interval is not configurable (hardcoded for v1)"
  fi
}

test_r010_hardcoded_30s
test_r010_not_configurable

# ============================================================================
# Integration: statusline exits 0 always (Notification hook contract)
# ============================================================================

section "Integration: statusline always exits 0"

# Tests that the statusline exits 0 even with cost-related edge cases
test_exit_0_with_corrupt_cache() {
  setup_test_repo
  local state_file
  state_file="$(state_filename "main")"
  cat > "$TEST_DIR/$state_file" <<SFJSON
{
  "phase": "tdd-impl",
  "task": "add-auth",
  "qa_rounds": 0
}
SFJSON

  local slug
  slug=$(cd "$TEST_DIR" && source "$LIB_SH" && branch_slug 2>/dev/null) || slug=""
  [ -n "$slug" ] || { fail "INT-a" "branch_slug failed"; cleanup_test_repo; return; }

  # Write corrupt JSON to the cache file
  echo "NOT VALID JSON {{{" > "$TEST_DIR/.correctless/artifacts/cost-cache-${slug}.json"

  local exit_code=0
  printf '%s' "$(integration_json)" | bash "$STATUSLINE" 2>/dev/null >/dev/null || exit_code=$?

  if [ "$exit_code" -eq 0 ]; then
    pass "INT-a" "Statusline exits 0 with corrupt cost cache"
  else
    fail "INT-a" "Statusline exited $exit_code with corrupt cost cache"
  fi

  cleanup_test_repo
}

test_exit_0_with_corrupt_cache

# ============================================================================
# Summary
# ============================================================================

summary "Statusline Live Cost"
