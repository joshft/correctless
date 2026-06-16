#!/usr/bin/env bash
# shellcheck disable=SC2254
# Correctless — workflow state machine
# The ONLY way to change the workflow state file.
# Validates transitions with real gates.
# Supports both Lite and Full modes (Full adds: model, review-spec, tdd-verify, audit phases).
# SC2254 disabled: unquoted $pat in case is intentional — we need glob matching
#
# Command functions live in sourced modules under scripts/wf/:
#   transitions.sh — phase transition commands
#   utility.sh     — operational commands (init, reset, override, status, etc.)
#   metadata.sh    — state modification commands (set-intensity, resolve-drift, spec-update)

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
CONFIG_FILE="$REPO_ROOT/.correctless/config/workflow-config.json"
ARTIFACTS_DIR="$REPO_ROOT/.correctless/artifacts"
OVERRIDE_LOG="$ARTIFACTS_DIR/override-log.json"

# ---------------------------------------------------------------------------
# SCRIPT_DIR — set before sourcing any modules (DD-006 / INV-011)
# Modules use $SCRIPT_DIR for relative path resolution instead of
# BASH_SOURCE[0], which would resolve to the module file after decomposition.
# ---------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

die() { printf "ERROR: %b\n" "$*" >&2; exit 1; }
info() { echo "$*"; }

require_jq() {
  command -v jq >/dev/null 2>&1 || die "jq is required but not installed"
}

# Source shared library (provides branch_slug and other utilities).
# Try: relative to hook dir, then REPO_ROOT/scripts (installed by setup).
_LIB_DIR="$SCRIPT_DIR/../scripts"
if [ -n "$_LIB_DIR" ] && [ -f "$_LIB_DIR/lib.sh" ]; then
  # shellcheck source=../scripts/lib.sh
  source "$_LIB_DIR/lib.sh"
elif [ -f "$REPO_ROOT/.correctless/scripts/lib.sh" ]; then
  source "$REPO_ROOT/.correctless/scripts/lib.sh"
else
  die "Cannot find .correctless/scripts/lib.sh — run setup or check installation"
fi
unset _LIB_DIR

state_file() {
  local slug
  slug="$(branch_slug)" || die "Cannot determine branch slug"
  echo "$ARTIFACTS_DIR/workflow-state-${slug}.json"
}

read_state() {
  local sf
  sf="$(state_file)"
  [ -f "$sf" ] || return 1
  cat "$sf"
}

read_phase() {
  local state
  state="$(read_state)" || { echo "none"; return; }
  echo "$state" | jq -r '.phase'
}

write_state() {
  local sf
  sf="$(state_file)"
  mkdir -p "$(dirname "$sf")"
  _acquire_state_lock "$sf" || die "Failed to acquire state lock"
  # shellcheck disable=SC2064  # Intentional: capture $sf at definition time, not at trap execution
  trap "$(printf '_release_state_lock %q; rm -f %q' "$sf" "$sf.$$")" EXIT
  if ! (echo "$1" | jq '.' > "$sf.$$" && mv "$sf.$$" "$sf"); then
    rm -f "$sf.$$"
    _release_state_lock "$sf"
    trap - EXIT
    die "Failed to write state file: $sf"
  fi
  _release_state_lock "$sf"
  trap - EXIT
}

update_phase() {
  local new_phase="$1"
  # QA-R1-012: Use locked_update_state for atomic read-modify-write
  # (prevents TOCTOU race if two workflow-advance.sh invocations overlap)
  local sf
  sf="$(state_file)"
  [ -f "$sf" ] || die "No state file — run 'init' first"
  local ts
  ts="$(date -u +%FT%TZ)"
  locked_update_state "$sf" \
    '.phase = $p | .phase_entered_at = $t | .override.active = false | .override.remaining_calls = 0' \
    --arg p "$new_phase" --arg t "$ts" \
    || die "Failed to update phase"
  info "Phase: $new_phase"
}

now_iso() {
  date -u +%FT%TZ
}

# _read_spec_hash — resolve spec file path from state and compute its SHA-256 hash
# Sets caller variables: _spec_path, _spec_hash, _spec_lines
# Returns 1 if the spec path is unset/null or the file is missing/unhashable.
_read_spec_hash() {
  local state="$1"
  _spec_path="$(echo "$state" | jq -r '.spec_file // ""')"
  _spec_hash=""
  _spec_lines="0"

  [ -n "$_spec_path" ] && [ "$_spec_path" != "null" ] || return 1
  [ -f "$REPO_ROOT/$_spec_path" ] || return 1

  _spec_hash="$(sha256_hash_file "$REPO_ROOT/$_spec_path" 2>/dev/null || echo "")"
  _spec_lines="$(wc -l < "$REPO_ROOT/$_spec_path" 2>/dev/null || echo "0")"
  [ -n "$_spec_hash" ] || return 1
}

current_branch() {
  local b
  b="$(git branch --show-current 2>/dev/null)" || die "Not in a git repository"
  [ -n "$b" ] || die "Detached HEAD — checkout a branch first"
  echo "$b"
}

check_branch_match() {
  local state
  state="$(read_state)" || return 0
  local state_branch
  state_branch="$(echo "$state" | jq -r '.branch')"
  local cur
  cur="$(current_branch)"
  if [ "$state_branch" != "$cur" ]; then
    die "Workflow state was created on branch '$state_branch', current branch is '$cur'. Run 'reset' to clear stale state."
  fi
}

require_phase() {
  local expected="$1"
  local current
  current="$(read_phase)"
  [ "$current" = "$expected" ] || die "Expected phase '$expected', but current phase is '$current'.
  Run /cstatus to see available transitions, or use 'workflow-advance.sh status' for details."
}

require_phase_oneof() {
  local current
  current="$(read_phase)"
  for p in "$@"; do
    [ "$current" = "$p" ] && return 0
  done
  die "Current phase '$current' is not one of: $*.
  Run /cstatus to see available transitions, or use 'workflow-advance.sh status' for details."
}

read_config_field() {
  local field="$1"
  [ -f "$CONFIG_FILE" ] || die "Config file not found: $CONFIG_FILE"
  jq -r "$field" "$CONFIG_FILE"
}

# Full mode detection — checks effective intensity (max of project config and feature_intensity)
is_full_mode() {
  [ -f "$CONFIG_FILE" ] || return 1
  local intensity
  intensity="$(jq -r '.workflow.intensity // empty' "$CONFIG_FILE" 2>/dev/null)" || true
  # Normalize case — handle user-edited configs with "High" or "CRITICAL"
  intensity="${intensity,,}"

  # Also check feature_intensity from the state file (PAT-005: effective intensity)
  local STATE_FILE
  STATE_FILE="$(state_file 2>/dev/null)" || true
  if [ -n "$STATE_FILE" ] && [ -f "$STATE_FILE" ]; then
    local feature_intensity
    feature_intensity="$(jq -r '.feature_intensity // empty' "$STATE_FILE" 2>/dev/null)" || true
    # Normalize case
    feature_intensity="${feature_intensity,,}"
    # Compute effective intensity as max(project, feature) using ordering standard < high < critical
    if [ -n "$feature_intensity" ]; then
      case "$feature_intensity" in
        critical) intensity="critical" ;;
        high)
          case "$intensity" in
            critical) ;; # project is already higher
            *) intensity="high" ;;
          esac
          ;;
      esac
    fi
  fi

  case "$intensity" in
    high|critical) return 0 ;;
    *) return 1 ;;
  esac
}

# Monorepo package resolution (longest-prefix match)
is_monorepo() {
  [ -f "$CONFIG_FILE" ] || return 1
  jq -e '.is_monorepo' "$CONFIG_FILE" >/dev/null 2>&1
}

# Read a config field with package scope fallback
# Usage: read_package_config '.commands.test' 'api'
read_package_config() {
  local field="$1" scope="${2:-.}"
  # Validate field is a safe jq dotpath (letters, digits, underscores, dots only)
  if [[ "$field" =~ [^a-zA-Z0-9_.] ]]; then
    die "read_package_config: unsafe field path: '$field'"
  fi
  if [ "$scope" != "." ] && is_monorepo; then
    local val
    val="$(jq -r --arg s "$scope" "(.packages[\$s]$field) // ($field) // empty" "$CONFIG_FILE" 2>/dev/null)"
    if [ -n "$val" ] && [ "$val" != "null" ]; then echo "$val"; return; fi
  fi
  read_config_field "$field" 2>/dev/null || echo ""
}

# Detect which packages are affected by current branch changes
detect_affected_packages() {
  is_monorepo || { echo "."; return; }
  local changed_files
  # shellcheck disable=SC1083  # Braces in HEAD@{upstream} are git refspec syntax, not shell
  changed_files="$(git diff --name-only "$(git merge-base HEAD "$(git rev-parse --abbrev-ref HEAD@{upstream} 2>/dev/null || echo HEAD~1)" 2>/dev/null)" HEAD 2>/dev/null || git diff --name-only HEAD~1 2>/dev/null || echo "")"
  [ -n "$changed_files" ] || { echo "."; return; }

  local packages=""
  while IFS= read -r key; do
    local pkg_path
    pkg_path="$(jq -r --arg k "$key" '.packages[$k].path' "$CONFIG_FILE")"
    if echo "$changed_files" | awk -v p="${pkg_path}/" 'index($0, p) == 1 { found=1; exit } END { exit !found }'; then
      packages="${packages:+$packages }$key"
    fi
  done < <(jq -r '.packages | keys[]' "$CONFIG_FILE" 2>/dev/null)

  echo "${packages:-.}"
}

is_fail_closed() {
  local val
  val="$(read_config_field '.workflow.fail_closed_when_no_state' 2>/dev/null || echo "false")"
  [ "$val" = "true" ]
}

has_formal_model() {
  local val
  val="$(read_config_field '.workflow.formal_model' 2>/dev/null || echo "false")"
  [ "$val" = "true" ]
}

# ---------------------------------------------------------------------------
# Test execution helpers
# ---------------------------------------------------------------------------

tests_fail_not_build_error() {
  local test_cmd fail_pattern build_pattern
  # Use first affected package's config, or global fallback
  local pkg="."
  if is_monorepo; then
    pkg="$(detect_affected_packages | awk '{print $1}')"
    [ "$pkg" = "." ] || true
  fi
  # Prefer commands.test_new if present (allows separate new-test file for RED gate)
  test_cmd="$(read_package_config '.commands.test_new' "$pkg")"
  if [ -z "$test_cmd" ] || [ "$test_cmd" = "null" ]; then
    test_cmd="$(read_package_config '.commands.test' "$pkg")"
  fi
  fail_pattern="$(read_package_config '.patterns.test_fail_pattern' "$pkg")"
  build_pattern="$(read_package_config '.patterns.build_error_pattern' "$pkg")"

  [ -n "$test_cmd" ] && [ "$test_cmd" != "null" ] || die "No test command configured"

  local output exit_code
  output="$(eval "$test_cmd" 2>&1)" && exit_code=0 || exit_code=$?

  if [ "$exit_code" -eq 0 ]; then
    die "Tests pass — they need to fail first (RED phase). Write tests that exercise the spec rules, then advance."
  fi

  # Check for build errors vs test failures
  if [ -n "$build_pattern" ] && [ "$build_pattern" != "null" ]; then
    if echo "$output" | grep -qE "$build_pattern"; then
      # Could be build error — check if there are also test failures
      if [ -n "$fail_pattern" ] && [ "$fail_pattern" != "null" ]; then
        if echo "$output" | grep -qE "$fail_pattern"; then
          return 0  # Has both build-like and fail-like output — treat as test failure
        fi
      fi
      die "Tests don't compile (build error), not a test failure. Fix compilation errors before advancing.\n\nOutput:\n$output"
    fi
  fi

  # Exit code non-zero and no build error detected — it's a test failure
  return 0
}

tests_pass() {
  # In monorepo mode, ALL affected packages must pass
  if is_monorepo; then
    local packages any_run=false
    packages="$(detect_affected_packages)"
    for pkg in $packages; do
      [ "$pkg" = "." ] && continue
      local cmd output exit_code
      cmd="$(read_package_config '.commands.test' "$pkg")"
      [ -n "$cmd" ] && [ "$cmd" != "null" ] || continue
      any_run=true
      output="$(eval "$cmd" 2>&1)" && exit_code=0 || exit_code=$?
      if [ "$exit_code" -ne 0 ]; then
        die "Tests do not pass in package '$pkg'. Fix failures before advancing.\n\nOutput (last 30 lines):\n$(echo "$output" | tail -30)"
      fi
    done
    # If no package tests ran, fall back to global test command
    if [ "$any_run" = "false" ]; then
      local test_cmd output exit_code
      test_cmd="$(read_config_field '.commands.test')"
      [ -n "$test_cmd" ] && [ "$test_cmd" != "null" ] || die "No test command configured"
      output="$(eval "$test_cmd" 2>&1)" && exit_code=0 || exit_code=$?
      if [ "$exit_code" -ne 0 ]; then
        die "Tests do not pass. Fix failures before advancing.\n\nOutput (last 30 lines):\n$(echo "$output" | tail -30)"
      fi
    fi
    return 0
  fi

  local test_cmd output exit_code
  test_cmd="$(read_config_field '.commands.test')"
  [ -n "$test_cmd" ] && [ "$test_cmd" != "null" ] || die "No test command configured"

  output="$(eval "$test_cmd" 2>&1)" && exit_code=0 || exit_code=$?

  if [ "$exit_code" -ne 0 ]; then
    die "Tests do not pass. Fix failures before advancing.\n\nOutput (last 30 lines):\n$(echo "$output" | tail -30)"
  fi
  return 0
}

test_files_exist() {
  local test_pattern
  test_pattern="$(read_config_field '.patterns.test_file')"
  [ -n "$test_pattern" ] && [ "$test_pattern" != "null" ] || die "No test_file pattern configured"

  # Split pipe-delimited patterns and check each
  local IFS='|'
  for pattern in $test_pattern; do
    # Convert glob pattern to regex: escape dots, convert * to .*
    local regex
    regex="$(printf '%s' "$pattern" | sed 's/\./\\./g; s/\*/.*/g')"
    local count
    # shellcheck disable=SC1083  # Braces in HEAD@{upstream} are git refspec syntax, not shell
    count="$(git diff --name-only "$(git merge-base HEAD "$(git rev-parse --abbrev-ref HEAD@{upstream} 2>/dev/null || echo HEAD~1)" 2>/dev/null)" HEAD 2>/dev/null | grep -cE "$regex" || true)"
    if [ "$count" -gt 0 ]; then
      return 0
    fi
    # Also check unstaged/staged new files
    count="$(git status --porcelain | grep -cE "$regex" || true)"
    if [ "$count" -gt 0 ]; then
      return 0
    fi
  done

  # Fallback: check if any test files exist matching the pattern in the repo
  for pattern in $test_pattern; do
    if compgen -G "$REPO_ROOT/**/$pattern" >/dev/null 2>&1 || \
       compgen -G "$REPO_ROOT/$pattern" >/dev/null 2>&1; then
      return 0
    fi
    # Use find as fallback
    if find "$REPO_ROOT" -name "$pattern" -not -path '*/.git/*' -not -path '*/node_modules/*' 2>/dev/null | grep -q .; then
      return 0
    fi
  done

  die "No test files found matching pattern(s): $test_pattern"
}

spec_file_exists() {
  local state spec_file
  state="$(read_state)" || die "No state file"
  spec_file="$(echo "$state" | jq -r '.spec_file')"
  [ -n "$spec_file" ] && [ "$spec_file" != "null" ] && [ -f "$REPO_ROOT/$spec_file" ] || \
    die "Spec file not found: $spec_file"
}

_require_min_qa_rounds() {
  local min_rounds
  min_rounds="$(read_config_field '.workflow.min_qa_rounds' 2>/dev/null || echo "1")"
  [ "$min_rounds" = "null" ] && min_rounds=1
  [[ "$min_rounds" =~ ^[0-9]+$ ]] || die "workflow.min_qa_rounds must be a non-negative integer, got: '$min_rounds'"
  local qa_rounds
  qa_rounds="$(read_state | jq -r '.qa_rounds // 0')"

  if [ "$qa_rounds" -lt "$min_rounds" ]; then
    die "Only $qa_rounds QA round(s) completed, minimum is $min_rounds. Run another QA round."
  fi
}

_log_audit_done_override() {
  # Append an audit-done-specific bypass entry to OVERRIDE_LOG so /cmetrics'
  # audit-done-override counter (AP-023 monitor for the ABS-029 gate) can
  # distinguish gate bypasses from other audit-phase overrides.
  #
  # H-3: explicit error reporting on jq/mv failure — silently swallowing
  # parse errors is exactly the silent-telemetry-failure shape this PR
  # exists to close.
  # MA-010: initialize OVERRIDE_LOG with [] if missing (PMB-005-class fix).
  local state_started="$1"
  if [ ! -f "$OVERRIDE_LOG" ]; then
    mkdir -p "$(dirname "$OVERRIDE_LOG")" 2>/dev/null || true
    printf '[]\n' > "$OVERRIDE_LOG" 2>/dev/null || {
      echo "WARN: cannot initialize $OVERRIDE_LOG — audit-done bypass not logged" >&2
      return 0
    }
  fi

  local _ts tmp
  _ts="$(now_iso)"
  tmp="$OVERRIDE_LOG.tmp"

  # NB: --arg name "gate" intentionally avoids "phase" — the
  # test-token-tracking-skill-field R-008 extractor treats `--arg phase
  # "..."` as a real phase declaration. This entry is metadata.
  if ! jq --arg ts "$_ts" --arg gate "audit-done" \
        --arg reason "Audit findings missing — overridden (ABS-029 gate)" \
        --arg started_at "$state_started" \
        '. + [{timestamp: $ts, gate: $gate, reason: $reason, bypass_target: "cmd_audit_done", state_started_at: $started_at}]' \
        "$OVERRIDE_LOG" > "$tmp" 2>/dev/null; then
    echo "WARN: jq failed appending audit-done bypass to $OVERRIDE_LOG (corrupt JSON?) — entry dropped" >&2
    rm -f "$tmp"
    return 0
  fi
  if ! mv "$tmp" "$OVERRIDE_LOG"; then
    echo "WARN: cannot atomically commit audit-done bypass to $OVERRIDE_LOG — entry dropped" >&2
    rm -f "$tmp"
    return 0
  fi
  return 0
}

# ---------------------------------------------------------------------------
# Source command modules (INV-002 / ABS-035)
# ---------------------------------------------------------------------------

_WF_MODULE_DIR="$SCRIPT_DIR/../scripts/wf"
# Installed location fallback (user projects)
if [ ! -d "$_WF_MODULE_DIR" ] && [ -d "$REPO_ROOT/.correctless/scripts/wf" ]; then
  _WF_MODULE_DIR="$REPO_ROOT/.correctless/scripts/wf"
fi

for _module in transitions.sh utility.sh metadata.sh; do
  # shellcheck disable=SC1090
  source "$_WF_MODULE_DIR/$_module" || die "Module not found: $_WF_MODULE_DIR/$_module — run setup to install"
done
unset _module _WF_MODULE_DIR

# ---------------------------------------------------------------------------
# CS-018(d) / CS-019: done-transition gate (ABS-041 + ABS-029 pattern)
# ---------------------------------------------------------------------------
# This gate runs BEFORE the transitions.sh cmd_done() body executes. It refuses
# the `done` transition under two conditions:
#   (d) A SFG lift sentinel `.correctless/.sfg-lift-active` is still in the tree
#       (AP-037 lift-and-restore not yet restored).
#   (CS-019) The full test suite has not produced a fixed-name test-success
#       sentinel whose recorded SHA content-matches the current HEAD SHA
#       (ABS-029 content-based gate, robust to ENV-003 mtime drift).
_done_phase_gate() {
  local sentinel=".correctless/.sfg-lift-active"
  if [ -f "$REPO_ROOT/$sentinel" ]; then
    echo "REFUSED: cannot transition to 'done' while $sentinel exists." >&2
    echo "  An SFG lift commit is in the tree without its restore commit (AP-037 lift-and-restore)." >&2
    echo "  Restore agents/fix-diff-reviewer.md to hooks/sensitive-file-guard.sh DEFAULTS, then:" >&2
    echo "    git rm -f $sentinel && bash sync.sh" >&2
    echo "  See .claude/rules/sfg-deliverable.md." >&2
    exit 1
  fi

  # CS-019 / QA2-001: require a fixed-name full-suite test-success sentinel whose
  # CONTENT (the recorded SHA) matches the live HEAD SHA. The sentinel is the
  # FIXED file .correctless/artifacts/test-success.sha — NOT keyed on HEAD in the
  # filename. Its content is the HEAD SHA at which the full tests/test-*.sh suite
  # last passed. The gate reads that recorded SHA and compares against live HEAD:
  #   - present, content == HEAD  -> allow (suite is green at this exact tree)
  #   - present, content != HEAD  -> REFUSE (HEAD advanced past the last green
  #                                  suite; the sentinel is stale)
  #   - absent                    -> allow, SILENTLY (the process gate is the
  #                                  backstop; the sentinel is written by the
  #                                  full-suite / CI gate per CS-019, not on
  #                                  every run). Do NOT fail-closed on absent —
  #                                  that breaks test-spec-mutation-alerts, whose
  #                                  temp project's qa passes with a stubbed test
  #                                  command and writes no sentinel.
  local head_sha test_success_sentinel recorded_sha
  head_sha="$(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null || echo "")"
  test_success_sentinel="$REPO_ROOT/.correctless/artifacts/test-success.sha"
  if [ -n "$head_sha" ] && [ -f "$test_success_sentinel" ]; then
    recorded_sha="$(head -n1 "$test_success_sentinel" 2>/dev/null | tr -d '[:space:]')"
    if [ -n "$recorded_sha" ] && [ "$recorded_sha" != "$head_sha" ]; then
      echo "REFUSED: 'done' requires a test-success sentinel matching HEAD ($head_sha)." >&2
      echo "  Recorded test-success SHA ($recorded_sha) does not match HEAD — the full suite" >&2
      echo "  last passed at an earlier commit. Re-run the full suite at HEAD before completing." >&2
      exit 1
    fi
  fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

require_jq

cmd="${1:-}"
shift || true

case "$cmd" in
  init|start)     cmd_init "$@" ;;
  review)         cmd_review ;;
  model)          cmd_model ;;
  review-spec)    cmd_review_spec ;;
  tests)          cmd_tests ;;
  impl)           cmd_impl ;;
  qa)             cmd_qa ;;
  verify-phase)   cmd_verify ;;
  fix)            cmd_fix ;;
  audit-mini)     cmd_audit_mini ;;
  done)           _done_phase_gate; cmd_done ;;
  verified)       cmd_verified ;;
  documented)     cmd_documented ;;
  audit-start)    cmd_audit_start "$@" ;;
  audit-done)     cmd_audit_done ;;
  spec-update)    cmd_spec_update "$@" ;;
  set-intensity)  cmd_set_intensity "$@" ;;
  resolve-drift)  cmd_resolve_drift "$@" ;;
  reset)          cmd_reset ;;
  gc)             cmd_gc ;;
  override)       cmd_override "$@" ;;
  diagnose)       cmd_diagnose "$@" ;;
  status)         cmd_status ;;
  status-all)     cmd_status_all ;;
  *)
    echo "Usage: workflow-advance.sh <command> [args]"
    echo ""
    echo "Phase transitions:"
    echo "  init \"task\"       Create workflow state (must be on a feature branch)"
    echo "  review             spec → review (requires spec file exists)"
    echo "  tests              review|review-spec|spec(update) → tdd-tests"
    echo "  impl               tdd-tests → tdd-impl (requires tests fail, not build error)"
    echo "  qa                 tdd-impl → tdd-qa (requires tests pass)"
    echo "  fix                tdd-qa|tdd-audit → tdd-impl (issues found, fix round)"
    echo "  audit-mini         tdd-qa|tdd-impl → tdd-audit (mini-audit at high+ intensity)"
    echo "  done               tdd-qa|tdd-verify|tdd-audit → done (zero issues, min rounds met)"
    echo "  verified           done → verified (requires /cverify report file exists)"
    echo "  documented         verified → documented (ready to merge)"
    echo "  spec-update \"why\" tdd-* → spec (spec was wrong, preserves TDD state)"
    echo ""
    echo "Phase transitions (Full mode only):"
    echo "  model              spec → model (requires formal_model: true)"
    echo "  review-spec        model|spec → review-spec (multi-agent adversarial review)"
    echo "  verify-phase       tdd-qa → tdd-verify (final verification before done)"
    echo "  audit-start [type] Start audit on audit/* branch (type: qa|hacker|perf|custom)"
    echo "  audit-done         audit → done (convergence reached, ready to merge)"
    echo "  resolve-drift ID \"reason\"  Mark drift debt item as resolved"
    echo ""
    echo "Utilities:"
    echo "  set-intensity lvl  Set feature intensity (standard|high|critical)"
    echo "  reset              Remove all workflow state for current branch"
    echo "  gc                 Remove state files for deleted branches"
    echo "  override \"reason\" Temporarily bypass gate for 10 tool calls"
    echo "  diagnose \"file\"   Show why a file would be blocked/allowed"
    echo "  status             Print current workflow state"
    echo "  status-all         Print all active workflows across branches"
    echo ""
    echo "Skills: /csetup /cspec /creview /ctdd /cverify /cdocs /crefactor /cpr-review /ccontribute /cmaintain /cstatus /csummary /cmetrics /cdebug /chelp /cwtf /cquick /crelease /cexplain /cauto"
    echo "High+:  /cmodel /creview-spec /caudit /cupdate-arch /cpostmortem /cdevadv /credteam"
    exit 1
    ;;
esac
