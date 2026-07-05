#!/usr/bin/env bash
# shellcheck disable=SC2254  # Unquoted $pat in case is intentional — we need glob matching
# HOOK_TYPE: PostToolUse
# HOOK_MATCHER: Edit|Write|MultiEdit|NotebookEdit|CreateFile|Bash|Read|Grep
# Correctless — PostToolUse audit trail + adherence feedback
# Records every file modification with workflow phase context.
# Lite mode: phase-violation alerts to stderr
# Full mode: + adherence tracking with coverage progress
# MUST be fast. Audit logging <100ms. Adherence feedback <200ms.
#
# #244 (narrowed): every .correctless/artifacts/ derivation is attributed to the
# EDITED FILE's own git repo F (resolved via the local _resolve_file_repo below),
# NOT the hook's cwd. See .correctless/specs/hook-repo-root-for.md (R-001..R-008).

# ---------------------------------------------------------------------------
# _resolve_file_repo <path> — the edited file's own git repo root (R-001, R-008)
# ---------------------------------------------------------------------------
# Walks up from the path's nearest EXISTING ancestor directory and asks git for
# that directory's repo toplevel. Prints the repo root + returns 0 when the path
# is inside a git repo; prints nothing + returns 1 when it is not (the distinction
# attribution needs, to no-op vs. misattribute). The upward walk is bounded by
# the path's component count. DELIBERATELY no safe.directory / GIT_CEILING /
# -c core.* / timeout hardening — this is fail-open telemetry, kept portable
# (macOS included). Local to this hook (R-008: not lib.sh, avoids the AP-037
# self-guard). The single column-0 `}` below is this function's closing brace —
# a test extracts this body by exact `_resolve_file_repo() {` match up to it, so
# every inner block stays indented (no column-0 `}` inside).
_resolve_file_repo() {
  local p="$1" dir parent root guard max i
  [ -n "$p" ] || return 1
  # Nearest existing ancestor directory to start the git query from.
  if [ -d "$p" ]; then
    dir="$p"
  else
    dir="$(dirname "$p" 2>/dev/null)" || return 1
  fi
  # Bound the walk by the path's component (slash) count, plus slack.
  guard="${p//[^\/]/}"
  max=$(( ${#guard} + 2 ))
  i=0
  while [ "$i" -lt "$max" ]; do
    if [ -d "$dir" ]; then
      # git itself walks up from here to the enclosing repo root (if any).
      root="$(git --no-optional-locks -C "$dir" rev-parse --show-toplevel 2>/dev/null)" || root=""
      if [ -n "$root" ]; then
        printf '%s\n' "$root"
        return 0
      fi
      # dir exists but is not inside any git repo -> no attribution.
      return 1
    fi
    parent="$(dirname "$dir" 2>/dev/null)" || return 1
    if [ "$parent" = "$dir" ]; then
      return 1
    fi
    dir="$parent"
    i=$(( i + 1 ))
  done
  return 1
}

# ---------------------------------------------------------------------------
# _nearest_existing_dir <path> — the path's nearest EXISTING ancestor directory
# ---------------------------------------------------------------------------
# The same starting point _resolve_file_repo walks from. Used as the memo key in
# _resolve_cached (QA-001): every file sharing a nearest-existing dir resolves to
# the SAME repo, because `git -C <dir> rev-parse --show-toplevel` answers per
# directory. Prints the dir + rc 0, or prints nothing + rc 1. Kept SEPARATE from
# _resolve_file_repo so that function stays self-contained (the R-001 test evals
# _resolve_file_repo's body in isolation, so it must not call this helper).
_nearest_existing_dir() {
  local p="$1" dir parent guard max i
  [ -n "$p" ] || return 1
  if [ -d "$p" ]; then
    dir="$p"
  else
    dir="$(dirname "$p" 2>/dev/null)" || return 1
  fi
  guard="${p//[^\/]/}"
  max=$(( ${#guard} + 2 ))
  i=0
  while [ "$i" -lt "$max" ]; do
    if [ -d "$dir" ]; then
      printf '%s\n' "$dir"
      return 0
    fi
    parent="$(dirname "$dir" 2>/dev/null)" || return 1
    [ "$parent" = "$dir" ] && return 1
    dir="$parent"
    i=$(( i + 1 ))
  done
  return 1
}

# ---------------------------------------------------------------------------
# _resolve_cached <path> — memoized wrapper (R-006; QA-001 dir-keyed memo)
# ---------------------------------------------------------------------------
# Sets RESOLVED_REPO and returns 0 when the path is in a repo, else returns 1.
# Memoizes by the file's NEAREST-EXISTING DIRECTORY (QA-001), NOT by prefix-match
# on resolved roots. Prefix matching silently misattributed a file in a NESTED
# git repo/submodule to its PARENT when the parent was resolved first (the R-1
# nested-repo hazard): with /P cached, /P/sub/f matched "$root"/* == /P/* and was
# logged under /P instead of its own repo /P/sub. Per-directory git resolution
# returns the INNERMOST repo, so keying the memo by nearest-existing dir is both
# correct for nested repos AND O(unique nearest-existing dirs) — the R-006 cost
# target. NEVER a "file plausibly in cwd" shortcut — resolution always attributes
# to the file's own repo (R-002).
_resolve_cached() {
  RESOLVED_REPO=""
  local f="$1" d root
  [ -n "$f" ] || return 1
  d="$(_nearest_existing_dir "$f")" || d=""
  # Memo hit: reuse the repo root resolved for this directory (empty value = no
  # repo, a memoized negative that still short-circuits the git fork).
  if [ -n "$d" ] && [ -n "${_REPO_MEMO[$d]+set}" ]; then
    root="${_REPO_MEMO[$d]}"
    [ -n "$root" ] || return 1
    RESOLVED_REPO="$root"
    return 0
  fi
  # Memo miss: authoritative resolve (git returns the INNERMOST repo for the dir).
  root="$(_resolve_file_repo "$f")" || root=""
  [ -n "$d" ] && _REPO_MEMO["$d"]="$root"
  [ -n "$root" ] || return 1
  RESOLVED_REPO="$root"
  return 0
}

# ---------------------------------------------------------------------------
# _process_repo <F> <newline-separated files> — record + adherence for repo F
# ---------------------------------------------------------------------------
# Every .correctless/artifacts/ path here derives from F (R-002), never cwd. A
# repo with no artifacts dir, an empty branch (detached HEAD / non-repo, R-003),
# or no active workflow-state file is a clean no-op for its files.
_process_repo() {
  local F="$1" repo_files="$2"

  # R-002: F must have an artifacts dir, else no-op for these files.
  [ -d "$F/.correctless/artifacts" ] || return 0

  # R-003: branch resolved from F, guarded against the empty->cwd leak.
  # An empty branch (detached HEAD / non-repo) MUST NOT be passed bare into
  # branch_slug — lib.sh:105 would fall back to the CWD branch and re-introduce
  # the cross-repo leak. Empty branch -> no attribution for these files.
  local _branch
  _branch="$(git --no-optional-locks -C "$F" branch --show-current 2>/dev/null || true)"
  [ -n "$_branch" ] || return 0

  local _slug
  _slug="$(branch_slug "$_branch" 2>/dev/null)" || return 0
  [ -n "$_slug" ] || return 0

  local STATE_FILE="$F/.correctless/artifacts/workflow-state-${_slug}.json"
  # No state file = no active workflow for F = nothing to audit (no-op).
  [ -f "$STATE_FILE" ] || return 0

  # Read phase (QA-R1-015: default to "unknown" if jq fails on corrupted state).
  local PHASE
  PHASE="$(jq -r '.phase // "unknown"' "$STATE_FILE" 2>/dev/null)" || true
  [ -n "$PHASE" ] || PHASE="unknown"

  local CONFIG_FILE="$F/.correctless/config/workflow-config.json"
  local TRAIL="$F/.correctless/artifacts/audit-trail-${_slug}.jsonl"

  # --- Audit trail logging (batch all files in single jq call) ---

  # Truncate oldest half if audit trail exceeds 5MB.
  if [ -f "$TRAIL" ]; then
    local trail_size total_lines keep_lines
    trail_size="$(wc -c < "$TRAIL" 2>/dev/null || echo 0)"
    if [ "$trail_size" -gt 5242880 ] 2>/dev/null; then
      total_lines="$(wc -l < "$TRAIL")"
      keep_lines=$(( total_lines / 2 ))
      [ "$keep_lines" -lt 1 ] && keep_lines=1
      trap 'rm -f "$TRAIL.$$"' EXIT
      tail -n "$keep_lines" "$TRAIL" > "$TRAIL.$$" 2>/dev/null && mv "$TRAIL.$$" "$TRAIL" 2>/dev/null \
        || rm -f "$TRAIL.$$" 2>/dev/null
      trap - EXIT
    fi
  fi

  # INV-015: include the harness stdin session_id (same field the InstructionsLoaded
  # hook reads — the harness-provided id, NOT any PID-based session id from lib.sh)
  # as a display-alignment aid for the /cwtf side-by-side view. Additive + backward-
  # compatible. The record's branch is F's branch (R-003), not cwd's.
  printf '%s\n' "$repo_files" | jq -Rnc \
    --arg ts "$TS" --arg phase "$PHASE" --arg tool "$TOOL_NAME" --arg branch "$_branch" --arg session "$SESSION_ID" \
    '[inputs | select(length > 0)] | .[] | {ts:$ts,phase:$phase,tool:$tool,file:.,branch:$branch,session_id:(if $session == "" then null else $session end)}' \
    >> "$TRAIL" 2>/dev/null

  # --- Adherence feedback (Lite: violations only, Full: + coverage tracking) ---

  # Bulk-read config: patterns + intensity in one jq call (IO-004). TEST_PATTERN
  # and SOURCE_PATTERN are consumed by classify_file() via dynamic scope.
  # shellcheck disable=SC2034
  local TEST_PATTERN=""
  # shellcheck disable=SC2034
  local SOURCE_PATTERN=""
  local IS_FULL="false"
  if [ -f "$CONFIG_FILE" ]; then
    eval "$(jq -r '
      @sh "TEST_PATTERN=\(.patterns.test_file // "")",
      @sh "SOURCE_PATTERN=\(.patterns.source_file // "")",
      @sh "IS_FULL=\(if (.workflow.intensity // "" | ascii_downcase) | IN("high","critical") then "true" else "false" end)"
    ' "$CONFIG_FILE" 2>/dev/null)" || true
  fi

  # classify_file() is provided by lib.sh (ABS-001: single definition). Without
  # it we can't classify — skip the advisory sections but never fail the hook.
  command -v classify_file >/dev/null 2>&1 || return 0

  # --- Lite mode: phase-violation alerts ---

  local f fclass
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    fclass="$(classify_file "$f")"

    case "$PHASE" in
      tdd-qa|tdd-verify)
        # QA/verify phases should be read-only for source and test files.
        # QA-R2-001: Exclude read-only tools (Read, Grep) from "modified" warnings.
        if [ "$fclass" = "source" ] && [ "$TOOL_NAME" != "Read" ] && [ "$TOOL_NAME" != "Grep" ]; then
          echo "⚠ $PHASE: Source file modified — ${f##*/} (this phase should be read-only)" >&2
        fi
        if [ "$fclass" = "test" ] && [ "$TOOL_NAME" != "Read" ] && [ "$TOOL_NAME" != "Grep" ]; then
          echo "⚠ $PHASE: Test file modified — ${f##*/} (this phase should be read-only)" >&2
        fi
        ;;
      tdd-impl)
        # GREEN phase: test edits should be logged.
        if [ "$fclass" = "test" ] && [ "$TOOL_NAME" != "Read" ] && [ "$TOOL_NAME" != "Grep" ]; then
          echo "📝 GREEN: Test file edited — ${f##*/} (should be logged in test-edit-log)" >&2
        fi
        ;;
      spec|review|review-spec|model)
        # Spec/review phases: no source or test edits (reads are fine).
        if { [ "$fclass" = "source" ] || [ "$fclass" = "test" ]; } && [ "$TOOL_NAME" != "Read" ] && [ "$TOOL_NAME" != "Grep" ]; then
          echo "⚠ $PHASE: Code file modified — ${f##*/} (spec/review phases are docs-only)" >&2
        fi
        ;;
    esac
  done <<< "$repo_files"

  # --- Full mode: adherence tracking with coverage progress ---

  if [ "$IS_FULL" = "true" ]; then
    local ADHERENCE="$F/.correctless/artifacts/adherence-state-${_slug}.json"

    # Initialize adherence state if missing or empty (REG-R2-002: -s catches 0-byte files).
    if [ ! -s "$ADHERENCE" ]; then
      jq -nc '{phase_files:{},modified_files:[],read_files:[]}' > "$ADHERENCE" 2>/dev/null
    fi

    # Track which files are modified and read per phase — single jq call (IO-005).
    if [ "$TOOL_NAME" = "Read" ] || [ "$TOOL_NAME" = "Grep" ]; then
      # Batch-add all files to read_files with set-like dedup (ALGO-002).
      trap 'rm -f "$ADHERENCE.$$"' EXIT
      printf '%s\n' "$repo_files" | jq -Rn --slurpfile state "$ADHERENCE" \
        '[inputs | select(length > 0)] as $new_files |
         $state[0] | .read_files = ([.read_files[], $new_files[]] | unique)' \
        > "$ADHERENCE.$$" 2>/dev/null && mv "$ADHERENCE.$$" "$ADHERENCE" 2>/dev/null \
        || rm -f "$ADHERENCE.$$" 2>/dev/null
      trap - EXIT
    else
      # Batch-add all files to modified_files + increment phase counter.
      trap 'rm -f "$ADHERENCE.$$"' EXIT
      printf '%s\n' "$repo_files" | jq -Rn --slurpfile state "$ADHERENCE" --arg p "$PHASE" \
        '[inputs | select(length > 0)] as $new_files |
         $state[0] | .modified_files = ([.modified_files[], $new_files[]] | unique)
         | .phase_files[$p] = ((.phase_files[$p] // 0) + ($new_files | length))' \
        > "$ADHERENCE.$$" 2>/dev/null && mv "$ADHERENCE.$$" "$ADHERENCE" 2>/dev/null \
        || rm -f "$ADHERENCE.$$" 2>/dev/null
      trap - EXIT
    fi

    # Show coverage progress during QA phase (single jq call, O(R+M) algorithm).
    if [ "$PHASE" = "tdd-qa" ] && [ "$TOOL_NAME" = "Read" ]; then
      if [ -f "$ADHERENCE" ]; then
        local mod_count read_count _first_file
        eval "$(jq -r '
          (.modified_files | map({key:.,value:1}) | from_entries) as $mod_set |
          @sh "mod_count=\(.modified_files | length)",
          @sh "read_count=\([.read_files[] | select($mod_set[.])] | length)"
        ' "$ADHERENCE" 2>/dev/null)" || true
        # shellcheck disable=SC2154
        if [ "${mod_count:-0}" -gt 0 ] 2>/dev/null; then
          _first_file="${repo_files%%$'\n'*}"
          echo "🔍 QA: Read ${_first_file##*/} ($read_count of $mod_count modified files reviewed)" >&2
        fi
      fi
    fi
  fi
}

# ===========================================================================
# Main flow
# ===========================================================================

# Fail-open: jq required for JSON parsing (PAT-005: PostToolUse exits 0, never blocks)
command -v jq >/dev/null 2>&1 || exit 0

# Bulk-parse all needed fields from stdin in one jq call (R2-PERF-001).
# R-002: the edited-file path is only known after this parse, so parse BEFORE any
# artifacts-dir check — the check now runs against the file's repo, not cwd.
INPUT="$(cat)"
eval "$(echo "$INPUT" | jq -r '
  @sh "TOOL_NAME=\(.tool_name // "")",
  @sh "TOOL_INPUT_FILE=\(.tool_input.file_path // "")",
  @sh "TOOL_INPUT_PATH=\(.tool_input.path // "")",
  @sh "TOOL_INPUT_COMMAND=\(.tool_input.command // "")",
  @sh "TOOL_INPUT_EDITS=\([.tool_input.edits[]?.file_path // empty] | join("\n"))",
  @sh "SESSION_ID=\(.session_id // "")"
' 2>/dev/null)" || exit 0

# Fast-path bail: no tool name = malformed input.
[ -n "$TOOL_NAME" ] || exit 0

# Source shared library for branch_slug() and get_target_file() (ABS-001: single definition).
_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" 2>/dev/null && pwd || true)"
if [ -n "$_LIB_DIR" ] && [ -f "$_LIB_DIR/lib.sh" ]; then
  # shellcheck source=../scripts/lib.sh
  source "$_LIB_DIR/lib.sh"
elif [ -f ".correctless/scripts/lib.sh" ]; then
  source ".correctless/scripts/lib.sh"
fi
unset _LIB_DIR

# Extract target file(s) from pre-parsed fields.
FILES=""
case "$TOOL_NAME" in
  Bash)
    # Use shared get_target_file from lib.sh (INV-004, INV-005). R-007: a Bash
    # write attributes under its target file's repo, same as an Edit.
    if command -v get_target_file >/dev/null 2>&1; then
      FILES="$(get_target_file "$TOOL_INPUT_COMMAND" | head -1)" || true
    fi
    ;;
  MultiEdit)
    # R-248: a real Claude Code MultiEdit carries its single target at top-level
    # .tool_input.file_path (TOOL_INPUT_FILE); edits[] hold only old/new strings.
    # Prefer that, mirroring the default Edit/Write branch. Fall back to the
    # legacy per-edit file_path list (TOOL_INPUT_EDITS) only when it is empty.
    if [ -n "$TOOL_INPUT_FILE" ]; then
      FILES="$TOOL_INPUT_FILE"
    else
      FILES="$TOOL_INPUT_EDITS"
    fi
    ;;
  Grep)
    # QA-R2-002: Grep uses .tool_input.path, not .tool_input.file_path.
    FILES="$TOOL_INPUT_PATH"
    ;;
  *)
    FILES="$TOOL_INPUT_FILE"
    ;;
esac

# Fast-path bail: no files identified = nothing to audit.
[ -n "$FILES" ] || exit 0

# MA-001 (hostile-input): the fan-out below splits FILES on newlines (the in-band
# separator) and later re-splits a TAB-delimited PAIRS buffer. For every tool
# EXCEPT MultiEdit, FILES is a SINGLE path, so an embedded newline or TAB is not a
# real harness path — it is injection that `read` would split into a phantom
# second path, forging a cross-repo audit record into another repo's trail (the
# silent cross-repo misattribution this feature eliminates). DECISION: guard here,
# before the read-split, because after the split each element no longer carries the
# newline (the per-_f newline check in the loop cannot see it). Fail-open no-op
# (R-005): a dropped telemetry record is safe; a forged cross-repo record is the
# bug. MultiEdit legitimately joins distinct paths with newlines, so it is exempt
# from the newline arm; its per-target TAB is still caught by the in-loop guard.
if [ "$TOOL_NAME" != "MultiEdit" ]; then
  case "$FILES" in *$'\n'*|*$'\t'*) exit 0 ;; esac
fi

# branch_slug is required to derive per-repo slugs; without lib.sh, skip (R-005).
command -v branch_slug >/dev/null 2>&1 || exit 0

# QA-R1-006: Disable glob expansion — patterns like *.ts must not expand to
# filenames (workflow-gate.sh and sensitive-file-guard.sh both have this).
set -f

TS="$(date -u +%FT%TZ 2>/dev/null || date -u +%Y-%m-%dT%H:%M:%SZ)"

# --- Resolve each edited file to its OWN repo F and group by repo (R-002/R-006) ---
# Files that resolve to no git repo get no attribution (R-005c no-op); they are
# never logged under cwd.
declare -A _REPO_MEMO=()   # QA-001: memo keyed by nearest-existing dir (per invocation)
PAIRS=""          # lines: <repo><TAB><file>, input order
REPOS_ORDER=""    # lines: <repo>, first-seen order (grouping)
while IFS= read -r _f; do
  [ -z "$_f" ] && continue
  _repo=""
  _resolve_cached "$_f" && _repo="$RESOLVED_REPO"
  [ -n "$_repo" ] || continue
  # MA-001 (hostile-input): a resolved pair whose file path carries a TAB (the
  # PAIRS re-split separator, e.g. a MultiEdit target with an embedded tab) or
  # whose repo root carries a newline/TAB would corrupt the PAIRS/REPOS_ORDER
  # buffers and could forge/misattribute a record. Skip such a pathological pair
  # as a clean fail-open no-op (R-005) — a real harness path never contains these.
  case $_f in *$'\n'*|*$'\t'*) continue ;; esac
  case $_repo in *$'\n'*|*$'\t'*) continue ;; esac
  PAIRS="${PAIRS}${_repo}"$'\t'"${_f}"$'\n'
  case $'\n'"${REPOS_ORDER}" in
    *$'\n'"${_repo}"$'\n'*) : ;;
    *) REPOS_ORDER="${REPOS_ORDER}${_repo}"$'\n' ;;
  esac
done <<< "$FILES"

# No file resolved to a repo -> clean no-op.
[ -n "$REPOS_ORDER" ] || exit 0

# --- Process each repo's records against its own artifacts (grouped, ordered) ---
while IFS= read -r _repo; do
  [ -z "$_repo" ] && continue
  _rf=""
  while IFS=$'\t' read -r _r _ff; do
    [ "$_r" = "$_repo" ] && _rf="${_rf}${_ff}"$'\n'
  done <<< "$PAIRS"
  _process_repo "$_repo" "$_rf"
done <<< "$REPOS_ORDER"

# Never fail.
exit 0
