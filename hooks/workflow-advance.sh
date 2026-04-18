#!/usr/bin/env bash
# shellcheck disable=SC2254
# Correctless — workflow state machine
# The ONLY way to change the workflow state file.
# Validates transitions with real gates.
# Supports both Lite and Full modes (Full adds: model, review-spec, tdd-verify, audit phases).
# SC2254 disabled: unquoted $pat in case is intentional — we need glob matching

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
CONFIG_FILE="$REPO_ROOT/.correctless/config/workflow-config.json"
ARTIFACTS_DIR="$REPO_ROOT/.correctless/artifacts"
OVERRIDE_LOG="$ARTIFACTS_DIR/override-log.json"

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
_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" 2>/dev/null && pwd || true)"
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
    ".phase = \"$new_phase\" | .phase_entered_at = \"$ts\"" \
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

DRIFT_DEBT_FILE="$REPO_ROOT/.correctless/meta/drift-debt.json"

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

# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------

cmd_init() {
  local task="${1:?Usage: workflow-advance.sh init \"task description\"}"
  local branch
  branch="$(current_branch)"
  local default_branch
  default_branch="$(git remote show origin 2>/dev/null | grep 'HEAD branch' | awk '{print $NF}')" || true
  [ -z "$default_branch" ] && default_branch="main"

  if [ "$branch" = "$default_branch" ] || [ "$branch" = "main" ] || [ "$branch" = "master" ]; then
    die "Cannot init workflow on '$branch'. Create a feature branch first: git checkout -b feature/my-feature
  For small fixes (< 50 LOC), try /cquick instead."
  fi

  local sf
  sf="$(state_file)"
  if [ -f "$sf" ]; then
    die "Workflow already active on this branch. Current phase: $(read_phase). Use 'reset' to start over."
  fi

  local slug
  slug="$(echo "$task" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-//;s/-$//')"
  # Truncate to first 4 hyphen-separated tokens, max 50 chars
  slug="$(echo "$slug" | cut -d'-' -f1-4)"
  slug="${slug:0:50}"
  slug="${slug%-}"

  # Guard: empty slug (all-punctuation or whitespace input)
  [ -n "$slug" ] || die "Could not generate a valid slug from: '$task'. Provide a description containing at least one letter or digit."

  # Check for collision against both spec files on disk AND state files claiming the same spec_file
  spec_slug_in_use() {
    local check_slug="$1"
    [ -f "$REPO_ROOT/.correctless/specs/${check_slug}.md" ] && return 0
    for state_f in "$ARTIFACTS_DIR"/workflow-state-*.json; do
      [ -f "$state_f" ] || continue
      local existing
      existing="$(jq -r '.spec_file // empty' "$state_f" 2>/dev/null)"
      [ "$existing" = ".correctless/specs/${check_slug}.md" ] && return 0
    done
    return 1
  }

  local base_slug="$slug"
  local suffix=2
  while spec_slug_in_use "$slug"; do
    slug="${base_slug}-${suffix}"
    suffix=$((suffix + 1))
  done

  local spec_file=".correctless/specs/${slug}.md"

  mkdir -p "$ARTIFACTS_DIR"
  mkdir -p "$REPO_ROOT/.correctless/specs"
  # QA-R1-014: Write state BEFORE creating spec stub — if write_state fails,
  # no orphaned spec file is left behind. On retry, the same slug is available.
  write_state "$(jq -n \
    --arg phase "spec" \
    --arg task "$task" \
    --arg spec_file "$spec_file" \
    --arg started_at "$(now_iso)" \
    --arg phase_entered_at "$(now_iso)" \
    --arg branch "$branch" \
    '{
      phase: $phase,
      task: $task,
      spec_file: $spec_file,
      started_at: $started_at,
      phase_entered_at: $phase_entered_at,
      branch: $branch,
      qa_rounds: 0
    }')"
  # Create the spec file stub so the path exists for downstream tools
  if [ ! -f "$REPO_ROOT/$spec_file" ]; then
    printf "# Spec: %s\n\n## Rules\n\n_(to be written)_\n" "$task" > "$REPO_ROOT/$spec_file"
  fi

  info "Workflow initialized on branch '$branch'"
  info "Phase: spec"
  info "Spec file: $spec_file"
  info "Next: write the spec, then run 'workflow-advance.sh review'"
}

cmd_review() {
  check_branch_match
  if is_full_mode; then
    die "In Full mode, use 'review-spec' for adversarial spec review, not 'review'."
  fi
  require_phase "spec"
  spec_file_exists
  update_phase "review"
  info "Next: run /creview to get a skeptical review of the spec"
}

cmd_model() {
  check_branch_match
  require_phase "spec"
  spec_file_exists
  if ! is_full_mode; then
    die "The 'model' phase is only available in Full mode (set workflow.intensity in config)"
  fi
  if ! has_formal_model; then
    die "formal_model is not enabled in workflow-config.json. Set formal_model: true, or skip to 'review-spec'."
  fi
  update_phase "model"
  info "Next: run /cmodel to generate and analyze an Alloy formal model"
}

cmd_review_spec() {
  check_branch_match
  # Full mode: comes after model (or spec if formal_model is false)
  if is_full_mode; then
    require_phase_oneof "model" "spec"
  else
    die "The 'review-spec' command is for Full mode. In Lite, use 'review'."
  fi
  spec_file_exists
  update_phase "review-spec"
  info "Next: run /creview-spec for multi-agent adversarial spec review"
}

cmd_tests() {
  check_branch_match
  local current_phase
  current_phase="$(read_phase)"

  # spec phase is only valid after a spec-update (resuming TDD, not skipping review)
  if [ "$current_phase" = "spec" ]; then
    local spec_updates
    spec_updates="$(read_state | jq -r '.spec_updates // 0')"
    if [ "$spec_updates" -eq 0 ]; then
      die "Cannot skip review. Run /creview (Lite) or /creview-spec (Full) first. Review is mandatory — it always finds issues."
    fi
    # spec-update flow: allow transition but warn strongly
    info "WARNING: Advancing to tests after spec-update without re-review."
    info "The changed rules have NOT been reviewed by a fresh agent."
    info "Run /creview or /creview-spec on the changed rules for best results."
  fi

  require_phase_oneof "review" "review-spec" "spec"
  spec_file_exists

  # R-001: Hash the spec file at review->tests transition and store spec_hash
  local _spec_path _spec_hash _spec_lines
  if _read_spec_hash "$(read_state)"; then
    local sf ts
    sf="$(state_file)"
    ts="$(now_iso)"
    locked_update_state "$sf" \
      '.phase = "tdd-tests" | .phase_entered_at = $ts | .spec_hash = $hash | .spec_line_count = ($lines | tonumber)' \
      --arg ts "$ts" --arg hash "$_spec_hash" --arg lines "$_spec_lines" \
      || die "Failed to update state for tdd-tests phase"
    info "Phase: tdd-tests"
  else
    update_phase "tdd-tests"
  fi

  info "Next: write failing tests for the spec rules (RED phase)"
}

cmd_impl() {
  check_branch_match
  require_phase "tdd-tests"
  test_files_exist
  info "Checking that tests fail (RED gate)..."
  tests_fail_not_build_error
  update_phase "tdd-impl"
  info "Next: implement to make the tests pass (GREEN phase)"
}

cmd_qa() {
  check_branch_match
  require_phase "tdd-impl"
  info "Checking that tests pass (GREEN gate)..."
  tests_pass

  # Capture coverage baseline if coverage command exists
  local cov_cmd
  cov_cmd="$(read_config_field '.commands.coverage' 2>/dev/null || echo "")"
  if [ -n "$cov_cmd" ] && [ "$cov_cmd" != "null" ]; then
    info "Capturing coverage baseline..."
    eval "$cov_cmd" > "$ARTIFACTS_DIR/coverage-baseline-$(branch_slug).out" 2>&1 || true
  fi

  # QA-R2-004: Use locked_update_state for atomic read-modify-write
  local sf ts
  sf="$(state_file)"
  ts="$(date -u +%FT%TZ)"
  locked_update_state "$sf" \
    ".qa_rounds += 1 | .phase = \"tdd-qa\" | .phase_entered_at = \"$ts\"" \
    || die "Failed to update state for QA phase"
  info "Phase: tdd-qa"
  info "Next: QA review (edits blocked)"
}

cmd_fix() {
  check_branch_match
  require_phase_oneof "tdd-qa" "tdd-audit"
  update_phase "tdd-impl"
  info "Fix round — address QA findings, then advance to QA again"
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

cmd_verify() {
  # Full mode: tdd-qa → tdd-verify (additional verification phase)
  check_branch_match
  require_phase "tdd-qa"

  if ! is_full_mode; then
    die "The 'verify' transition is for Full mode. In Lite, use 'done' to complete."
  fi

  _require_min_qa_rounds

  info "Checking that tests pass..."
  tests_pass

  update_phase "tdd-verify"
  info "Next: final verification (all edits blocked)"
}

cmd_audit_mini() {
  # Mini-audit phase: tdd-qa or tdd-impl (recheck after fix) → tdd-audit
  check_branch_match
  require_phase_oneof "tdd-qa" "tdd-impl"
  _require_min_qa_rounds

  info "Checking that tests pass..."
  tests_pass

  update_phase "tdd-audit"
  info "Phase: tdd-audit"
  info "Next: mini-audit review (edits blocked)"
}

cmd_done() {
  check_branch_match
  # Accept tdd-qa (Lite, or Full skipping verify-phase), tdd-verify (Full recommended path),
  # or tdd-audit (mini-audit at high+ intensity)
  require_phase_oneof "tdd-qa" "tdd-verify" "tdd-audit"
  _require_min_qa_rounds

  info "Checking that tests still pass..."
  tests_pass

  # R-002/R-004: Check spec integrity before completing
  local state spec_path stored_hash
  state="$(read_state)"
  spec_path="$(echo "$state" | jq -r '.spec_file // ""')"
  stored_hash="$(echo "$state" | jq -r '.spec_hash // ""')"

  if [ -n "$stored_hash" ] && [ "$stored_hash" != "null" ] && [ -n "$spec_path" ] && [ "$spec_path" != "null" ]; then
    if [ ! -f "$REPO_ROOT/$spec_path" ]; then
      # R-004: Spec file deleted between review and done
      info "WARNING: Spec file not found at $spec_path. Cannot verify spec integrity."
    else
      local current_hash
      current_hash="$(sha256_hash_file "$REPO_ROOT/$spec_path" 2>/dev/null || echo "")"
      if [ -n "$current_hash" ] && [ "$current_hash" != "$stored_hash" ]; then
        # R-002: Spec was modified after review approval
        local original_lines current_lines delta
        original_lines="$(echo "$state" | jq -r '.spec_line_count // 0')"
        current_lines="$(wc -l < "$REPO_ROOT/$spec_path" 2>/dev/null || echo "0")"
        delta="$((current_lines - original_lines))"
        [ "$delta" -ge 0 ] && delta="+$delta"
        info "WARNING: Spec file was modified after review approval. ${delta} lines changed. The implementation may not match the reviewed spec. Consider re-running /creview-spec."
      fi
    fi
  fi

  update_phase "done"
  info "TDD complete. Next MANDATORY step: run /cverify"
}

cmd_verified() {
  check_branch_match
  require_phase "done"

  # Check that a verification report was actually written
  local state spec_file slug
  state="$(read_state)"
  spec_file="$(echo "$state" | jq -r '.spec_file')"

  # QA-R1-019: Guard against null spec_file (e.g., on audit branches that transitioned to done)
  if [ -z "$spec_file" ] || [ "$spec_file" = "null" ]; then
    die "No spec file in workflow state — 'verified' is not applicable to audit workflows. Merge the audit branch directly."
  fi

  slug="$(basename "$spec_file" .md)"
  local report="$REPO_ROOT/.correctless/verification/${slug}-verification.md"

  if [ ! -f "$report" ]; then
    die "Verification report not found at $report. Run /cverify first — it must write the report file."
  fi

  update_phase "verified"
  info "Verification complete. Next MANDATORY step: run /cdocs"
}

cmd_documented() {
  check_branch_match
  require_phase "verified"

  # Check that AGENT_CONTEXT.md has been updated (proxy for docs being written)
  local agent_ctx="$REPO_ROOT/.correctless/AGENT_CONTEXT.md"
  if [ -f "$agent_ctx" ]; then
    local last_mod
    last_mod="$(stat -c %Y "$agent_ctx" 2>/dev/null || stat -f %m "$agent_ctx" 2>/dev/null || echo 0)"
    local state_created
    state_created="$(stat -c %Y "$(state_file)" 2>/dev/null || stat -f %m "$(state_file)" 2>/dev/null || echo 0)"
    if [ "$last_mod" -lt "$state_created" ]; then
      info "WARNING: AGENT_CONTEXT.md has not been modified since the workflow started. Run /cdocs to update documentation."
    fi
  fi

  update_phase "documented"
  info "Documentation complete. Branch is ready to merge."
  info "State file persists until cleanup."
}

cmd_audit_start() {
  # Full mode only: start an audit on a dedicated branch
  if ! is_full_mode; then
    die "The 'audit' command is only available in Full mode"
  fi

  local audit_type="${1:-qa}"
  local branch
  branch="$(current_branch)"
  local default_branch
  default_branch="$(git remote show origin 2>/dev/null | grep 'HEAD branch' | awk '{print $NF}')" || true
  [ -z "$default_branch" ] && default_branch="main"

  # Audit can read from main but creates its own branch
  local audit_branch
  audit_branch="audit/${audit_type}-$(date +%Y-%m-%d)"
  if [ "$branch" != "$audit_branch" ]; then
    info "Audit should run on branch '$audit_branch'"
    info "Create it with: git checkout -b $audit_branch"
    die "Not on audit branch"
  fi

  local sf
  sf="$(state_file)"
  if [ -f "$sf" ]; then
    die "Workflow already active on this branch. Use 'reset' to start over."
  fi

  mkdir -p "$ARTIFACTS_DIR"
  write_state "$(jq -n \
    --arg phase "audit" \
    --arg task "audit-$audit_type" \
    --arg started_at "$(now_iso)" \
    --arg phase_entered_at "$(now_iso)" \
    --arg branch "$audit_branch" \
    --arg audit_type "$audit_type" \
    '{
      phase: $phase,
      task: $task,
      spec_file: null,
      started_at: $started_at,
      phase_entered_at: $phase_entered_at,
      branch: $branch,
      qa_rounds: 0,
      audit: {
        type: $audit_type,
        rounds_completed: 0,
        total_findings: 0,
        findings_fixed: 0,
        converged: false
      }
    }')"

  info "Audit initialized: type=$audit_type"
  info "Phase: audit"
  info "Next: run /caudit to start the convergence loop"
}


cmd_audit_done() {
  check_branch_match
  require_phase "audit"
  update_phase "done"
  info "Audit complete. Merge audit branch to main."
  info "Post-merge: update antipatterns, write regression tests."
}

cmd_set_intensity() {
  local level="${1:-}"
  if [ -z "$level" ]; then
    die "Usage: workflow-advance.sh set-intensity <standard|high|critical>"
  fi

  # Validate intensity level
  case "$level" in
    standard|high|critical) ;;
    *) die "Invalid intensity level: '$level'. Must be one of: standard, high, critical" ;;
  esac

  check_branch_match
  # Phase guard: set-intensity only valid during spec-related phases
  require_phase_oneof "spec" "review" "review-spec"

  # QA-R2-004: Use locked_update_state for atomic read-modify-write
  local sf
  sf="$(state_file)"
  [ -f "$sf" ] || die "No state file — run 'init' first"
  locked_update_state "$sf" \
    ".feature_intensity = \"$level\"" \
    || die "Failed to set feature intensity"
  info "Feature intensity set to: $level"
}

cmd_resolve_drift() {
  local drift_id="${1:?Usage: workflow-advance.sh resolve-drift DRIFT-xxx \"reason\"}"
  local reason="${2:?Usage: workflow-advance.sh resolve-drift DRIFT-xxx \"reason\"}"

  if [ ! -f "$DRIFT_DEBT_FILE" ]; then
    die "No drift debt file found at $DRIFT_DEBT_FILE"
  fi

  # Validate JSON
  if ! jq empty "$DRIFT_DEBT_FILE" 2>/dev/null; then
    die "Drift debt file contains invalid JSON: $DRIFT_DEBT_FILE"
  fi

  local found
  found="$(jq --arg id "$drift_id" '.drift_debt[] | select(.id == $id)' "$DRIFT_DEBT_FILE")"
  if [ -z "$found" ]; then
    die "Drift item '$drift_id' not found"
  fi

  # shellcheck disable=SC2064
  trap "$(printf 'rm -f %q' "$DRIFT_DEBT_FILE.$$")" EXIT
  # QA-R2-006: Check return code — don't report success if write failed
  if ! (jq --arg id "$drift_id" --arg reason "$reason" --arg date "$(now_iso)" \
    '(.drift_debt[] | select(.id == $id)) |= . + {status: "resolved", resolved_date: $date, resolution_reason: $reason}' \
    "$DRIFT_DEBT_FILE" > "$DRIFT_DEBT_FILE.$$" && mv "$DRIFT_DEBT_FILE.$$" "$DRIFT_DEBT_FILE"); then
    rm -f "$DRIFT_DEBT_FILE.$$"
    trap - EXIT
    die "Failed to write drift debt file"
  fi
  trap - EXIT

  info "Drift item $drift_id marked as resolved: $reason"
}

cmd_spec_update() {
  local reason="${1:?Usage: workflow-advance.sh spec-update \"reason\"}"
  check_branch_match
  require_phase_oneof "tdd-tests" "tdd-impl" "tdd-qa"

  # Read phase for logging (pre-read is fine — only used for info messages)
  local from_phase
  from_phase="$(read_phase)"

  # R-003: Re-hash spec file and update spec_hash (legitimate spec change path)
  local _spec_path _spec_hash _spec_lines
  local has_hash=false
  _read_spec_hash "$(read_state)" && has_hash=true

  # QA-R2-004: Use locked_update_state for atomic read-modify-write
  local sf ts
  sf="$(state_file)"
  ts="$(now_iso)"
  # QA-R3-001: Use --arg for user-supplied $reason to prevent jq injection
  # Note: avoid `X + 1 as $c` — jq 1.7 parses this as `X + (1 as $c)` (CI regression)
  local jq_filter hash_args=()
  jq_filter='.spec_update_history = (.spec_update_history // []) + [{from_phase: .phase, reason: $reason, timestamp: $ts}]
     | .spec_updates = ((.spec_updates // 0) + 1)
     | .phase = "spec"
     | .phase_entered_at = $ts'
  if [ "$has_hash" = true ]; then
    jq_filter="$jq_filter"'
     | .spec_hash = $hash
     | .spec_line_count = ($lines | tonumber)'
    hash_args=(--arg hash "$_spec_hash" --arg lines "$_spec_lines")
  fi
  locked_update_state "$sf" \
    "$jq_filter" \
    --arg reason "$reason" --arg ts "$ts" "${hash_args[@]}" \
    || die "Failed to update state for spec-update"
  info "Phase: spec"

  # Re-read update_count for the warning check
  local update_count
  update_count="$(read_state | jq -r '.spec_updates // 0')"
  if [ "$update_count" -ge 3 ]; then
    info "WARNING: This spec has been revised $update_count times during implementation."
    info "Consider whether the feature is under-specified or the approach is fundamentally wrong."
    info "It may be better to 'reset' and re-spec from scratch."
  fi

  info "Spec update from $from_phase: $reason"
  info "Edit the spec rules, then run 'workflow-advance.sh tests' to resume TDD."
}

cmd_reset() {
  local sf
  sf="$(state_file)"
  if [ -f "$sf" ]; then
    rm "$sf"
    # Also remove audit trail and checkpoint files for this branch
    local slug_hash
    slug_hash="$(branch_slug)"
    rm -f "$ARTIFACTS_DIR/audit-trail-${slug_hash}.jsonl"
    rm -f "$ARTIFACTS_DIR/adherence-state-${slug_hash}.json"
    rm -f "$ARTIFACTS_DIR/checkpoint-ctdd-"*.json "$ARTIFACTS_DIR/checkpoint-crefactor-"*.json \
          "$ARTIFACTS_DIR/checkpoint-creview-spec-"*.json "$ARTIFACTS_DIR/checkpoint-caudit-"*.json 2>/dev/null
    rm -f "$ARTIFACTS_DIR/.pkg-cache-"*.json 2>/dev/null
    rm -f "$ARTIFACTS_DIR/tdd-test-edits.log" "$ARTIFACTS_DIR/coverage-baseline-${slug_hash}.out" 2>/dev/null
    rm -f "$ARTIFACTS_DIR/token-log-${slug_hash}.jsonl" 2>/dev/null
    rm -f "$ARTIFACTS_DIR/review-decisions-${slug_hash}.json" 2>/dev/null
    rm -f "$ARTIFACTS_DIR/antipattern-findings-${slug_hash}.json" 2>/dev/null
    # Clean lock dirs and temp files from locking operations
    rm -rf "${sf}.lock" "${sf}.lock.breaking."* 2>/dev/null
    rm -f "${sf}."*.tmp "${sf}."[0-9]* 2>/dev/null
    info "Workflow state, audit trail, adherence state, and checkpoints removed for branch '$(current_branch)'"
  else
    info "No workflow state for branch '$(current_branch)'"
  fi
}

cmd_override() {
  local reason="${1:?Usage: workflow-advance.sh override \"reason\"}"
  local sf
  sf="$(state_file)"
  [ -f "$sf" ] || die "No active workflow to override"

  check_branch_match

  local phase
  phase="$(read_phase)"
  local ts
  ts="$(now_iso)"

  # Check override count — max 3 per workflow
  local state
  state="$(read_state)"
  local override_count
  override_count="$(echo "$state" | jq -r '.override_count // 0')"
  if [ "$override_count" -ge 3 ]; then
    die "Override limit reached (3 per workflow). If the gate is consistently blocking legitimate edits, the workflow config or patterns may need adjustment. Use 'reset' as a last resort."
  fi

  # R4-S1: Check for Jaccard retry prevention (PRH-006)
  if command -v jaccard_similarity >/dev/null 2>&1 || {
    local _os_dir
    _os_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)/../scripts"
    [ -f "$_os_dir/override-scrutiny.sh" ] && source "$_os_dir/override-scrutiny.sh" 2>/dev/null
  }; then
    if ! check_override_retry "$reason" "$sf" 2>/dev/null; then
      die "Override rejected: your reason is too similar to a previous override request. Provide a genuinely different justification — explain why this specific edit is needed, not just a rephrasing of the previous reason."
    fi
  fi

  # Block renewal while an override is still active
  local override_active
  override_active="$(echo "$state" | jq -r '.override.active // false')"
  local remaining
  remaining="$(echo "$state" | jq -r '.override.remaining_calls // 0')"
  if [ "$override_active" = "true" ] && [ "$remaining" -gt 0 ]; then
    die "An override is already active ($remaining calls remaining). It must expire before requesting another."
  fi

  # QA-R2-004: Use locked_update_state for atomic read-modify-write
  # QA-R3-001: Use --arg for user-supplied $reason to prevent jq injection
  locked_update_state "$sf" \
    '.override = {active: true, reason: $reason, started_at: $ts, remaining_calls: 10} | .override_count = (.override_count // 0) + 1' \
    --arg reason "$reason" --arg ts "$ts" \
    || die "Failed to write override state"

  # Append to override log
  mkdir -p "$(dirname "$OVERRIDE_LOG")"
  # QA-R2-007: Validate or recreate override log if corrupted
  if [ ! -f "$OVERRIDE_LOG" ] || ! jq empty "$OVERRIDE_LOG" 2>/dev/null; then
    echo '[]' > "$OVERRIDE_LOG"
  fi
  local entry
  entry="$(jq -n \
    --arg phase "$phase" \
    --arg reason "$reason" \
    --arg ts "$ts" \
    --arg branch "$(current_branch)" \
    '{phase: $phase, reason: $reason, timestamp: $ts, branch: $branch}')"
  # shellcheck disable=SC2064
  trap "$(printf 'rm -f %q' "$OVERRIDE_LOG.$$")" EXIT
  jq --argjson entry "$entry" '(. += [$entry]) | .[-100:]' "$OVERRIDE_LOG" > "$OVERRIDE_LOG.$$" \
    && mv "$OVERRIDE_LOG.$$" "$OVERRIDE_LOG"
  trap - EXIT

  info "Override active for next 10 tool calls"
  info "Reason logged: $reason"
  info "The gate will allow all edits until the override expires."
}

cmd_diagnose() {
  local filepath="${1:?Usage: workflow-advance.sh diagnose \"filepath\"}"
  # Normalize case to match gate logic (bash 4+ builtin)
  filepath="${filepath,,}"
  local phase
  phase="$(read_phase)"

  local test_pattern source_pattern
  test_pattern="$(read_config_field '.patterns.test_file' 2>/dev/null || echo "")"
  source_pattern="$(read_config_field '.patterns.source_file' 2>/dev/null || echo "")"

  info "=== Diagnose: $filepath ==="
  info "Current phase: $phase"

  # Classify file (mirrors gate logic: path-based patterns match full path, others match basename)
  local classification="other"
  local bname
  bname="${filepath##*/}"
  if [ -n "$test_pattern" ] && [ "$test_pattern" != "null" ]; then
    local IFS='|'
    for pat in $test_pattern; do
      case "$pat" in
        */*) case "$filepath" in $pat) classification="test"; break ;; esac ;;
        *)   case "$bname" in $pat) classification="test"; break ;; esac ;;
      esac
    done
  fi
  if [ "$classification" = "other" ] && [ -n "$source_pattern" ] && [ "$source_pattern" != "null" ]; then
    local IFS='|'
    for pat in $source_pattern; do
      case "$pat" in
        */*) case "$filepath" in $pat) classification="source"; break ;; esac ;;
        *)   case "$bname" in $pat) classification="source"; break ;; esac ;;
      esac
    done
  fi
  info "File classification: $classification"
  info "Test pattern(s): $test_pattern"
  info "Source pattern(s): $source_pattern"

  # Determine gate decision
  local decision="ALLOW"
  local reason=""
  case "$phase" in
    none)
      reason="No active workflow — all edits allowed"
      ;;
    spec|review|review-spec|model)
      if [ "$classification" = "source" ] || [ "$classification" = "test" ]; then
        decision="BLOCK"
        reason="Phase '$phase' does not allow source or test file edits"
      else
        reason="Non-source/test file — allowed in all phases"
      fi
      ;;
    tdd-tests)
      if [ "$classification" = "source" ]; then
        if [ -f "$REPO_ROOT/$filepath" ] && grep -q 'STUB:TDD' "$REPO_ROOT/$filepath" 2>/dev/null; then
          reason="Source file with STUB:TDD tag — allowed for structural stubs"
        else
          decision="BLOCK"
          reason="Source file without STUB:TDD — blocked during RED phase. Add STUB:TDD to function bodies."
        fi
      else
        reason="Test file or other — allowed during RED phase"
      fi
      ;;
    tdd-impl)
      reason="GREEN phase — all file edits allowed (test edits are logged)"
      ;;
    tdd-qa|tdd-verify|tdd-audit)
      if [ "$classification" = "source" ] || [ "$classification" = "test" ]; then
        decision="BLOCK"
        reason="$phase phase — source and test edits blocked"
      else
        reason="Non-source/test file — allowed"
      fi
      ;;
    audit)
      reason="Audit phase — managed by /caudit skill"
      ;;
    done|verified|documented)
      reason="Post-TDD phase ($phase) — all edits allowed"
      ;;
  esac

  # Check for active override
  local state
  state="$(read_state 2>/dev/null || echo '{}')"
  local override_active
  override_active="$(echo "$state" | jq -r '.override.active // false')"
  if [ "$override_active" = "true" ]; then
    local remaining
    remaining="$(echo "$state" | jq -r '.override.remaining_calls')"
    info "Override active ($remaining calls remaining) — would ALLOW regardless"
    decision="ALLOW (override)"
  fi

  info "Decision: $decision"
  info "Reason: $reason"
}

cmd_status() {
  local state
  state="$(read_state 2>/dev/null)" || {
    info "No active workflow on branch '$(current_branch)'"
    return
  }

  # Bulk-extract all fields in one jq call (IO-007, IO-008)
  local s_phase s_branch s_task s_spec s_started s_qa s_intensity s_updates s_override s_override_rem
  eval "$(echo "$state" | jq -r '
    @sh "s_phase=\(.phase // "none")",
    @sh "s_branch=\(.branch // "")",
    @sh "s_task=\(.task // "")",
    @sh "s_spec=\(.spec_file // "")",
    @sh "s_started=\(.started_at // "")",
    @sh "s_qa=\(.qa_rounds // 0)",
    @sh "s_intensity=\(.feature_intensity // "")",
    @sh "s_updates=\(.spec_updates // 0)",
    @sh "s_override=\(.override.active // false)",
    @sh "s_override_rem=\(.override.remaining_calls // 0)"
  ')"

  if [ "$s_phase" = "none" ]; then
    info "No active workflow on branch '$(current_branch)'"
    return
  fi

  # Verify branch matches
  local cur
  cur="$(current_branch)"
  if [ "$s_branch" != "$cur" ]; then
    die "Workflow state was created on branch '$s_branch', current branch is '$cur'. Run 'reset' to clear stale state."
  fi

  info "=== Workflow Status ==="
  info "Branch:  $s_branch"
  info "Phase:   $s_phase"
  info "Task:    $s_task"
  info "Spec:    $s_spec"
  info "Started: $s_started"
  info "QA rounds: $s_qa"

  if [ -n "$s_intensity" ]; then
    info "Intensity: $s_intensity"
  fi

  if [ "$s_updates" -gt 0 ] 2>/dev/null; then
    info "Spec updates: $s_updates"
    echo "$state" | jq -r '.spec_update_history[]? | "  - \(.from_phase): \(.reason) (\(.timestamp))"'
  fi

  if [ "$s_override" = "true" ]; then
    info "Override: ACTIVE ($s_override_rem calls remaining)"
  fi
}

cmd_status_all() {
  info "=== Active Workflows ==="
  local found=false
  for sf in "$ARTIFACTS_DIR"/workflow-state-*.json; do
    [ -f "$sf" ] || continue
    found=true
    # Bulk-extract all fields in one jq call (IO-009)
    local sa_branch sa_phase sa_task sa_started sa_qa
    eval "$(jq -r '
      @sh "sa_branch=\(.branch // "")",
      @sh "sa_phase=\(.phase // "")",
      @sh "sa_task=\(.task // "")",
      @sh "sa_started=\(.started_at // "" | .[0:10])",
      @sh "sa_qa=\(.qa_rounds // 0)"
    ' "$sf")"
    printf "  %-35s phase: %-10s task: %-20s started: %s  qa_rounds: %s\n" "$sa_branch" "$sa_phase" "$sa_task" "$sa_started" "$sa_qa"
  done
  if [ "$found" = "false" ]; then
    info "  (none)"
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
  done)           cmd_done ;;
  verified)       cmd_verified ;;
  documented)     cmd_documented ;;
  audit-start)    cmd_audit_start "$@" ;;
  audit-done)     cmd_audit_done ;;
  spec-update)    cmd_spec_update "$@" ;;
  set-intensity)  cmd_set_intensity "$@" ;;
  resolve-drift)  cmd_resolve_drift "$@" ;;
  reset)          cmd_reset ;;
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
