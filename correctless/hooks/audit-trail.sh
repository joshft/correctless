#!/usr/bin/env bash
# shellcheck disable=SC2254  # Unquoted $pat in case is intentional — we need glob matching
# HOOK_TYPE: PostToolUse
# HOOK_MATCHER: Edit|Write|MultiEdit|NotebookEdit|CreateFile|Bash|Read|Grep
# Correctless — PostToolUse audit trail + adherence feedback
# Records every file modification with workflow phase context.
# Lite mode: phase-violation alerts to stderr
# Full mode: + adherence tracking with coverage progress
# MUST be fast. Audit logging <100ms. Adherence feedback <200ms.

# Fast-path bail: if no .correctless/artifacts/ directory, exit immediately.
[ -d ".correctless/artifacts" ] || exit 0

# Fail-open: jq required for JSON parsing (PAT-005: PostToolUse exits 0, never blocks)
command -v jq >/dev/null 2>&1 || exit 0

# Bulk-parse all needed fields from stdin in one jq call (R2-PERF-001)
INPUT="$(cat)"
eval "$(echo "$INPUT" | jq -r '
  @sh "TOOL_NAME=\(.tool_name // "")",
  @sh "TOOL_INPUT_FILE=\(.tool_input.file_path // "")",
  @sh "TOOL_INPUT_PATH=\(.tool_input.path // "")",
  @sh "TOOL_INPUT_COMMAND=\(.tool_input.command // "")",
  @sh "TOOL_INPUT_EDITS=\([.tool_input.edits[]?.file_path // empty] | join("\n"))"
' 2>/dev/null)" || exit 0

# Fast-path bail: no tool name = malformed input
[ -n "$TOOL_NAME" ] || exit 0

# Source shared library for branch_slug() and get_target_file() (ABS-001: single definition)
_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" 2>/dev/null && pwd || true)"
if [ -n "$_LIB_DIR" ] && [ -f "$_LIB_DIR/lib.sh" ]; then
  # shellcheck source=../scripts/lib.sh
  source "$_LIB_DIR/lib.sh"
elif [ -f ".correctless/scripts/lib.sh" ]; then
  source ".correctless/scripts/lib.sh"
fi
unset _LIB_DIR

# Extract target file(s) from pre-parsed fields
FILES=""
case "$TOOL_NAME" in
  Bash)
    # Use shared get_target_file from lib.sh (INV-004, INV-005)
    if command -v get_target_file >/dev/null 2>&1; then
      FILES="$(get_target_file "$TOOL_INPUT_COMMAND" | head -1)" || true
    fi
    ;;
  MultiEdit)
    FILES="$TOOL_INPUT_EDITS"
    ;;
  Grep)
    # QA-R2-002: Grep uses .tool_input.path, not .tool_input.file_path
    FILES="$TOOL_INPUT_PATH"
    ;;
  *)
    FILES="$TOOL_INPUT_FILE"
    ;;
esac

# Fast-path bail: no files identified = nothing to audit
[ -n "$FILES" ] || exit 0

# Compute state file path using shared branch_slug (ABS-001: single definition in lib.sh)
if command -v branch_slug >/dev/null 2>&1; then
  _slug="$(branch_slug 2>/dev/null)" || exit 0
  [ -n "$_slug" ] || exit 0
else
  # lib.sh not available — can't determine state, skip audit
  exit 0
fi
STATE_FILE=".correctless/artifacts/workflow-state-${_slug}.json"

# Fast-path bail: no state file = no active workflow = nothing to audit
[ -f "$STATE_FILE" ] || exit 0

# Read phase and config
# QA-R1-015: Default to "unknown" if jq fails on corrupted state file
PHASE="$(jq -r '.phase // "unknown"' "$STATE_FILE" 2>/dev/null)" || true
[ -n "$PHASE" ] || PHASE="unknown"
CONFIG_FILE="$(config_file 2>/dev/null)" || CONFIG_FILE=".correctless/config/workflow-config.json"

# --- Audit trail logging (batch all files in single jq call) ---

TRAIL=".correctless/artifacts/audit-trail-${_slug}.jsonl"
TS="$(date -u +%FT%TZ 2>/dev/null || date -u +%Y-%m-%dT%H:%M:%SZ)"

# Truncate oldest half if audit trail exceeds 5MB
if [ -f "$TRAIL" ]; then
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

# Get branch name for audit trail (branch_slug doesn't expose it as a variable)
_audit_branch="$(git --no-optional-locks branch --show-current 2>/dev/null || true)"
printf '%s\n' "$FILES" | jq -Rnc \
  --arg ts "$TS" --arg phase "$PHASE" --arg tool "$TOOL_NAME" --arg branch "$_audit_branch" \
  '[inputs | select(length > 0)] | .[] | {ts:$ts,phase:$phase,tool:$tool,file:.,branch:$branch}' \
  >> "$TRAIL" 2>/dev/null

# --- Adherence feedback (Lite: violations only, Full: + coverage tracking) ---

# Bulk-read config: patterns + intensity in one jq call (IO-004)
# shellcheck disable=SC2034  # Used by classify_file() in lib.sh
TEST_PATTERN=""
# shellcheck disable=SC2034
SOURCE_PATTERN=""
IS_FULL="false"
if [ -f "$CONFIG_FILE" ]; then
  eval "$(jq -r '
    @sh "TEST_PATTERN=\(.patterns.test_file // "")",
    @sh "SOURCE_PATTERN=\(.patterns.source_file // "")",
    @sh "IS_FULL=\(if (.workflow.intensity // "" | ascii_downcase) | IN("high","critical") then "true" else "false" end)"
  ' "$CONFIG_FILE" 2>/dev/null)" || true
fi

# classify_file() is provided by lib.sh (ABS-001: single definition)
# Requires TEST_PATTERN and SOURCE_PATTERN globals set above.
command -v classify_file >/dev/null 2>&1 || exit 0

# QA-R1-006: Disable glob expansion — patterns like *.ts must not expand to filenames
# (workflow-gate.sh and sensitive-file-guard.sh both have this; audit-trail was missing it)
set -f

# --- Lite mode: phase-violation alerts ---

while IFS= read -r f; do
  [ -z "$f" ] && continue
  fclass="$(classify_file "$f")"

  case "$PHASE" in
    tdd-qa|tdd-verify)
      # QA/verify phases should be read-only for source and test files
      # QA-R2-001: Exclude read-only tools (Read, Grep) from "modified" warnings
      if [ "$fclass" = "source" ] && [ "$TOOL_NAME" != "Read" ] && [ "$TOOL_NAME" != "Grep" ]; then
        echo "⚠ $PHASE: Source file modified — ${f##*/} (this phase should be read-only)" >&2
      fi
      if [ "$fclass" = "test" ] && [ "$TOOL_NAME" != "Read" ] && [ "$TOOL_NAME" != "Grep" ]; then
        echo "⚠ $PHASE: Test file modified — ${f##*/} (this phase should be read-only)" >&2
      fi
      ;;
    tdd-impl)
      # GREEN phase: test edits should be logged
      if [ "$fclass" = "test" ] && [ "$TOOL_NAME" != "Read" ] && [ "$TOOL_NAME" != "Grep" ]; then
        echo "📝 GREEN: Test file edited — ${f##*/} (should be logged in test-edit-log)" >&2
      fi
      ;;
    spec|review|review-spec|model)
      # Spec/review phases: no source or test edits (reads are fine)
      if { [ "$fclass" = "source" ] || [ "$fclass" = "test" ]; } && [ "$TOOL_NAME" != "Read" ] && [ "$TOOL_NAME" != "Grep" ]; then
        echo "⚠ $PHASE: Code file modified — ${f##*/} (spec/review phases are docs-only)" >&2
      fi
      ;;
  esac
done <<< "$FILES"

# --- Full mode: adherence tracking with coverage progress ---
# IS_FULL was set from the bulk config read above

if [ "$IS_FULL" = "true" ]; then
  ADHERENCE=".correctless/artifacts/adherence-state-${_slug}.json"

  # Initialize adherence state if missing or empty (REG-R2-002: -s catches 0-byte files)
  if [ ! -s "$ADHERENCE" ]; then
    jq -nc '{phase_files:{},modified_files:[],read_files:[]}' > "$ADHERENCE" 2>/dev/null
  fi

  # Track which files are modified and read per phase — single jq call for all files (IO-005)
  if [ "$TOOL_NAME" = "Read" ] || [ "$TOOL_NAME" = "Grep" ]; then
    # Batch-add all files to read_files with set-like dedup (ALGO-002)
    trap 'rm -f "$ADHERENCE.$$"' EXIT
    printf '%s\n' "$FILES" | jq -Rn --slurpfile state "$ADHERENCE" \
      '[inputs | select(length > 0)] as $new_files |
       $state[0] | .read_files = ([.read_files[], $new_files[]] | unique)' \
      > "$ADHERENCE.$$" 2>/dev/null && mv "$ADHERENCE.$$" "$ADHERENCE" 2>/dev/null \
      || rm -f "$ADHERENCE.$$" 2>/dev/null
    trap - EXIT
  else
    # Batch-add all files to modified_files + increment phase counter
    trap 'rm -f "$ADHERENCE.$$"' EXIT
    printf '%s\n' "$FILES" | jq -Rn --slurpfile state "$ADHERENCE" --arg p "$PHASE" \
      '[inputs | select(length > 0)] as $new_files |
       $state[0] | .modified_files = ([.modified_files[], $new_files[]] | unique)
       | .phase_files[$p] = ((.phase_files[$p] // 0) + ($new_files | length))' \
      > "$ADHERENCE.$$" 2>/dev/null && mv "$ADHERENCE.$$" "$ADHERENCE" 2>/dev/null \
      || rm -f "$ADHERENCE.$$" 2>/dev/null
    trap - EXIT
  fi

  # Show coverage progress during QA phase (single jq call for both counters, O(R+M) algorithm)
  if [ "$PHASE" = "tdd-qa" ] && [ "$TOOL_NAME" = "Read" ]; then
    if [ -f "$ADHERENCE" ]; then
      eval "$(jq -r '
        (.modified_files | map({key:.,value:1}) | from_entries) as $mod_set |
        @sh "mod_count=\(.modified_files | length)",
        @sh "read_count=\([.read_files[] | select($mod_set[.])] | length)"
      ' "$ADHERENCE" 2>/dev/null)" || true
      # shellcheck disable=SC2154  # mod_count, read_count assigned via eval
      if [ "${mod_count:-0}" -gt 0 ] 2>/dev/null; then
        _first_file="${FILES%%$'\n'*}"
        echo "🔍 QA: Read ${_first_file##*/} ($read_count of $mod_count modified files reviewed)" >&2
      fi
    fi
  fi
fi

# Never fail
exit 0
