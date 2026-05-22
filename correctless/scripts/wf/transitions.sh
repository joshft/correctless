#!/usr/bin/env bash
# Correctless — workflow-advance transition commands
# Sourced by hooks/workflow-advance.sh — not independently executable.
# Contains phase transition command functions.
#
# All path resolution uses $SCRIPT_DIR (set by the dispatcher before sourcing).
# Do NOT use BASH_SOURCE[0] for path resolution — it resolves to this module
# file, not the dispatcher.

# shellcheck disable=SC2254

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
      '.phase = "tdd-tests" | .phase_entered_at = $ts | .spec_hash = $hash | .spec_line_count = ($lines | tonumber) | .override.active = false | .override.remaining_calls = 0' \
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
  ts="$(now_iso)"
  locked_update_state "$sf" \
    '.qa_rounds += 1 | .phase = "tdd-qa" | .phase_entered_at = $t | .override.active = false | .override.remaining_calls = 0' \
    --arg t "$ts" \
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

  # R-002/R-004: Check spec integrity before completing (single state read)
  local state spec_path stored_hash
  state="$(read_state)"
  local original_lines
  eval "$(echo "$state" | jq -r '@sh "spec_path=\(.spec_file // "") stored_hash=\(.spec_hash // "") original_lines=\(.spec_line_count // 0)"')"

  if [ -n "$stored_hash" ] && [ "$stored_hash" != "null" ] && [ -n "$spec_path" ] && [ "$spec_path" != "null" ]; then
    if [ ! -f "$REPO_ROOT/$spec_path" ]; then
      # R-004: Spec file deleted between review and done
      info "WARNING: Spec file not found at $spec_path. Cannot verify spec integrity."
    else
      local current_hash
      current_hash="$(sha256_hash_file "$REPO_ROOT/$spec_path" 2>/dev/null || echo "")"
      if [ -n "$current_hash" ] && [ "$current_hash" != "$stored_hash" ]; then
        # R-002: Spec was modified after review approval
        local current_lines delta
        current_lines="$(wc -l < "$REPO_ROOT/$spec_path" 2>/dev/null || echo "0")"
        delta="$((current_lines - original_lines))"
        [ "$delta" -ge 0 ] && delta="+$delta"
        info "WARNING: Spec file was modified after review approval. ${delta} lines changed. The implementation may not match the reviewed spec. Consider re-running /creview-spec."
      fi
    fi
  fi

  # INV-006: Non-blocking lens outcome warning
  # If a lens-recommendations artifact exists but has no outcomes field, warn (not gate)
  local branch_slug_val lens_artifact
  branch_slug_val="$(branch_slug)" || true
  lens_artifact="$REPO_ROOT/.correctless/artifacts/lens-recommendations-${branch_slug_val}.json"
  if [ -f "$lens_artifact" ]; then
    if ! jq -e '.outcomes' "$lens_artifact" >/dev/null 2>&1; then
      info "WARNING: Lens recommendation artifact exists but has no outcomes field. Consider recording lens outcomes for auditability."
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
  # QA-R3-004: validate audit_type against the same regex audit-record.sh uses
  # (preset format: 1-32 chars, [a-z][a-z0-9-]*). Prevents log-injection via
  # the unvalidated CLI input that flows into cmd_audit_done's stderr message.
  case "$audit_type" in
    [a-z]*) ;;
    *) die "Invalid audit_type '$audit_type': must start with lowercase letter" ;;
  esac
  case "$audit_type" in
    *[!a-z0-9-]*) die "Invalid audit_type '$audit_type': only [a-z0-9-] allowed" ;;
  esac
  if [ "${#audit_type}" -gt 32 ]; then
    die "Invalid audit_type '$audit_type': must be 32 chars or fewer"
  fi
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

  # ABS-029: refuse the transition unless a current-run round-JSON exists.
  # Match is content-based — string equality on the round-JSON's started_at
  # field with the workflow state's started_at — robust to ENV-003 mtime
  # unreliability after git checkout/clone (INV-001, INV-003).
  local sf preset state_started override_active oa_remaining
  sf="$(state_file)"
  eval "$(jq -r '@sh "preset=\(.audit.type // "") state_started=\(.started_at // "") override_active=\(.override.active // false) oa_remaining=\(.override.remaining_calls // 0)"' "$sf" 2>/dev/null)"
  if [ -z "$preset" ] || [ "$preset" = "null" ]; then
    die "Audit findings missing: state .audit.type is missing or null. Re-run audit-start."
  fi
  # MA-003: validate .audit.type content before using it in glob expansion.
  # State file is sole-writer-trusted (EA-001 / PAT-004) but defense-in-depth
  # prevents a corrupted state with `.audit.type=*` (cross-preset matching)
  # or `.audit.type=../etc` (path-traversal escape from the findings dir).
  case "$preset" in
    [a-z]*) ;;
    *) die "Audit findings missing: state .audit.type '$preset' must start with lowercase letter" ;;
  esac
  case "$preset" in
    *[!a-z0-9-]*) die "Audit findings missing: state .audit.type '$preset' contains invalid characters" ;;
  esac
  if [ "${#preset}" -gt 32 ]; then
    die "Audit findings missing: state .audit.type '$preset' exceeds 32 characters"
  fi
  if [ -z "$state_started" ]; then
    die "Audit findings missing: state .started_at is missing. Re-run audit-start."
  fi

  local override_in_effect=0
  if [ "$override_active" = "true" ] && [ "${oa_remaining:-0}" -gt 0 ]; then
    override_in_effect=1
  fi

  # Run the artifact check first (read-only). H-2: log the audit-done bypass
  # entry ONLY if the gate would have blocked AND the override is what
  # carried it through — otherwise an unrelated still-active override would
  # cause /cmetrics to count phantom audit-done bypasses, polluting the
  # AP-023 monitor signal.
  local findings_dir=".correctless/artifacts/findings"
  local artifact_matched=0
  if [ -d "$findings_dir" ]; then
    local f
    for f in "$findings_dir"/audit-"$preset"-*-round-*.json; do
      [ -f "$f" ] || continue
      local file_started
      file_started=$(jq -r '.started_at // empty' "$f" 2>/dev/null)
      if [ "$file_started" = "$state_started" ]; then
        artifact_matched=1
        break
      fi
    done
  fi

  if [ "$artifact_matched" = 0 ]; then
    if [ "$override_in_effect" = 1 ]; then
      _log_audit_done_override "$state_started"
    else
      echo "BLOCKED: Audit findings missing — no round-JSON for this run found." >&2
      echo "  Expected file pattern: audit-${preset}-*-round-*.json" >&2
      echo "  Required match: started_at = ${state_started}" >&2
      # MA-007: detect which install path actually has the script — emit the
      # one that exists. If neither exists, the user is on an upgrade
      # boundary and needs to run /csetup first.
      if [ -x ".correctless/scripts/audit-record.sh" ]; then
        echo "  Remediation: bash .correctless/scripts/audit-record.sh write-round ${preset} <round> <findings>" >&2
      elif [ -x "scripts/audit-record.sh" ]; then
        echo "  Remediation: bash scripts/audit-record.sh write-round ${preset} <round> <findings>" >&2
      else
        echo "  Remediation: audit-record.sh is not installed — run 'bash setup' to refresh, then write-round." >&2
      fi
      die "cmd_audit_done refused: ABS-029 gate"
    fi
  fi

  update_phase "done"
  info "Audit complete. Merge audit branch to main."
  info "Post-merge: update antipatterns, write regression tests."
}
