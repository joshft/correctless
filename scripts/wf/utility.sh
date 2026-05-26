#!/usr/bin/env bash
# Correctless — workflow-advance utility commands
# Sourced by hooks/workflow-advance.sh — not independently executable.
# Contains operational commands (init, reset, override, status, etc.).
#
# All path resolution uses $SCRIPT_DIR (set by the dispatcher before sourcing).
# Do NOT use BASH_SOURCE[0] for path resolution — it resolves to this module
# file, not the dispatcher.

# shellcheck disable=SC2254

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
    rm -f "$ARTIFACTS_DIR/pipeline-manifest-${slug_hash}.json" 2>/dev/null
    rm -f "$ARTIFACTS_DIR/escalation-${slug_hash}."* 2>/dev/null
    rm -f "$ARTIFACTS_DIR/autonomous-decisions-${slug_hash}.jsonl" 2>/dev/null
    rm -f "$ARTIFACTS_DIR/cost-cache-${slug_hash}.json" 2>/dev/null
    rm -f "$ARTIFACTS_DIR/harness-notified-"*.flag 2>/dev/null
    # Clean lock dirs and temp files from locking operations
    rm -rf "${sf}.lock" "${sf}.lock.breaking."* 2>/dev/null
    rm -f "${sf}."*.tmp "${sf}."[0-9]* 2>/dev/null
    info "Workflow state, audit trail, adherence state, and checkpoints removed for branch '$(current_branch)'"
  else
    info "No workflow state for branch '$(current_branch)'"
  fi
}


cmd_gc() {
  local removed=0
  local kept=0
  for sf in "$ARTIFACTS_DIR"/workflow-state-*.json; do
    [ -f "$sf" ] || continue
    local branch
    branch="$(jq -r '.branch // empty' "$sf" 2>/dev/null)"
    [ -n "$branch" ] || continue
    if ! git show-ref --verify --quiet "refs/heads/$branch" 2>/dev/null; then
      rm -f "$sf"
      removed=$((removed + 1))
    else
      kept=$((kept + 1))
    fi
  done
  info "Garbage collected: $removed orphaned state files removed, $kept active kept"
}
cmd_override() {
  local reason="${1:?Usage: workflow-advance.sh override \"reason\"}"
  local sf
  sf="$(state_file)"
  [ -f "$sf" ] || die "No active workflow to override"

  check_branch_match

  local ts
  ts="$(now_iso)"

  # Single state read — extract phase, override_count, and override status
  local state
  state="$(read_state)"
  local phase override_count override_active remaining
  eval "$(echo "$state" | jq -r '@sh "phase=\(.phase) override_count=\(.override_count // 0) override_active=\(.override.active // false) remaining=\(.override.remaining_calls // 0)"')"

  if [ "$override_count" -ge 3 ]; then
    die "Override limit reached (3 per workflow). If the gate is consistently blocking legitimate edits, the workflow config or patterns may need adjustment. Use 'reset' as a last resort."
  fi

  # R4-S1: Check for Jaccard retry prevention (PRH-006)
  if command -v jaccard_similarity >/dev/null 2>&1 || {
    local _os_dir
    _os_dir="$SCRIPT_DIR/../scripts"
    [ -f "$_os_dir/override-scrutiny.sh" ] && source "$_os_dir/override-scrutiny.sh" 2>/dev/null
  }; then
    if ! check_override_retry "$reason" "$sf" 2>/dev/null; then
      die "Override rejected: your reason is too similar to a previous override request. Provide a genuinely different justification — explain why this specific edit is needed, not just a rephrasing of the previous reason."
    fi
  fi
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
