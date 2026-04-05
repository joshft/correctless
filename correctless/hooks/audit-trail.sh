#!/usr/bin/env bash
# shellcheck disable=SC2254  # Unquoted $pat in case is intentional — we need glob matching
# Correctless — PostToolUse audit trail + adherence feedback
# Records every file modification with workflow phase context.
# Lite mode: phase-violation alerts to stderr
# Full mode: + adherence tracking with coverage progress
# MUST be fast. Audit logging <100ms. Adherence feedback <200ms.

# Fast-path bail: if no .correctless/artifacts/ directory, exit immediately.
[ -d ".correctless/artifacts" ] || exit 0

# Bulk-parse all needed fields from stdin in one jq call (R2-PERF-001)
INPUT="$(cat)"
eval "$(echo "$INPUT" | jq -r '
  @sh "TOOL_NAME=\(.tool_name // "")",
  @sh "TOOL_INPUT_FILE=\(.tool_input.file_path // "")",
  @sh "TOOL_INPUT_COMMAND=\(.tool_input.command // "")",
  @sh "TOOL_INPUT_EDITS=\([.tool_input.edits[]?.file_path // empty] | join("\n"))"
' 2>/dev/null)" || exit 0

# Fast-path bail: no tool name = malformed input
[ -n "$TOOL_NAME" ] || exit 0

# Extract target file(s) from pre-parsed fields
FILES=""
case "$TOOL_NAME" in
  Bash)
    FILES="$(echo "$TOOL_INPUT_COMMAND" | grep -oE '[^ ]+\.(go|ts|tsx|js|jsx|py|rs|java|rb|cpp|c|h|sh|json|md|yaml|yml|toml|cfg|ini|sql|css|html|vue|svelte)' | head -1)" || true
    ;;
  MultiEdit)
    FILES="$TOOL_INPUT_EDITS"
    ;;
  *)
    FILES="$TOOL_INPUT_FILE"
    ;;
esac

# Fast-path bail: no files identified = nothing to audit
[ -n "$FILES" ] || exit 0

# Compute branch slug and find state file (bash builtins instead of sed+cut)
branch="$(git --no-optional-locks branch --show-current 2>/dev/null)" || exit 0
[ -n "$branch" ] || exit 0

slug="${branch//[^a-zA-Z0-9]/-}"
slug="${slug:0:80}"
raw_hash="$(printf '%s' "$branch" | (md5sum 2>/dev/null || md5))"
hash="${raw_hash:0:6}"
STATE_FILE=".correctless/artifacts/workflow-state-${slug}-${hash}.json"

# Fast-path bail: no state file = no active workflow = nothing to audit
[ -f "$STATE_FILE" ] || exit 0

# Read phase and config
PHASE="$(jq -r '.phase // "unknown"' "$STATE_FILE" 2>/dev/null)"
CONFIG_FILE=".correctless/config/workflow-config.json"

# --- Audit trail logging (batch all files in single jq call) ---

TRAIL=".correctless/artifacts/audit-trail-${slug}-${hash}.jsonl"
TS="$(date -u +%FT%TZ 2>/dev/null || date -u +%Y-%m-%dT%H:%M:%SZ)"

# Truncate oldest half if audit trail exceeds 5MB
if [ -f "$TRAIL" ]; then
  trail_size="$(wc -c < "$TRAIL" 2>/dev/null || echo 0)"
  if [ "$trail_size" -gt 5242880 ] 2>/dev/null; then
    total_lines="$(wc -l < "$TRAIL")"
    keep_lines=$(( total_lines / 2 ))
    tail -n "$keep_lines" "$TRAIL" > "$TRAIL.$$" 2>/dev/null && mv "$TRAIL.$$" "$TRAIL" 2>/dev/null \
      || rm -f "$TRAIL.$$" 2>/dev/null
  fi
fi

printf '%s\n' "$FILES" | jq -Rnc \
  --arg ts "$TS" --arg phase "$PHASE" --arg tool "$TOOL_NAME" --arg branch "$branch" \
  '[inputs | select(length > 0)] | .[] | {ts:$ts,phase:$phase,tool:$tool,file:.,branch:$branch}' \
  >> "$TRAIL" 2>/dev/null

# --- Adherence feedback (Lite: violations only, Full: + coverage tracking) ---

# Bulk-read config: patterns + intensity in one jq call (IO-004)
TEST_PATTERN=""
SOURCE_PATTERN=""
IS_FULL="false"
if [ -f "$CONFIG_FILE" ]; then
  eval "$(jq -r '
    @sh "TEST_PATTERN=\(.patterns.test_file // "")",
    @sh "SOURCE_PATTERN=\(.patterns.source_file // "")",
    @sh "IS_FULL=\(if (.workflow.intensity // "") | IN("high","critical") then "true" else "false" end)"
  ' "$CONFIG_FILE" 2>/dev/null)" || true
fi

# Simple file classifier (matches gate logic)
classify() {
  local file="$1" bname
  bname="${file##*/}"
  if [ -n "$TEST_PATTERN" ]; then
    local oldifs="$IFS"; IFS='|'
    for pat in $TEST_PATTERN; do
      IFS="$oldifs"
      case "$pat" in
        */*) case "$file" in $pat) echo "test"; return ;; esac ;;
        *)   case "$bname" in $pat) echo "test"; return ;; esac ;;
      esac
    done
    IFS="$oldifs"
  fi
  if [ -n "$SOURCE_PATTERN" ]; then
    local oldifs="$IFS"; IFS='|'
    for pat in $SOURCE_PATTERN; do
      IFS="$oldifs"
      case "$pat" in
        */*) case "$file" in $pat) echo "source"; return ;; esac ;;
        *)   case "$bname" in $pat) echo "source"; return ;; esac ;;
      esac
    done
    IFS="$oldifs"
  fi
  echo "other"
}

# --- Lite mode: phase-violation alerts ---

while IFS= read -r f; do
  [ -z "$f" ] && continue
  fclass="$(classify "$f")"

  case "$PHASE" in
    tdd-qa|tdd-verify)
      # QA/verify phases should be read-only for source and test files
      if [ "$fclass" = "source" ] && [ "$TOOL_NAME" != "Read" ]; then
        echo "⚠ $PHASE: Source file modified — ${f##*/} (this phase should be read-only)" >&2
      fi
      if [ "$fclass" = "test" ] && [ "$TOOL_NAME" != "Read" ]; then
        echo "⚠ $PHASE: Test file modified — ${f##*/} (this phase should be read-only)" >&2
      fi
      ;;
    tdd-impl)
      # GREEN phase: test edits should be logged
      if [ "$fclass" = "test" ] && [ "$TOOL_NAME" != "Read" ]; then
        echo "📝 GREEN: Test file edited — ${f##*/} (should be logged in test-edit-log)" >&2
      fi
      ;;
    spec|review|review-spec|model)
      # Spec/review phases: no source or test edits
      if [ "$fclass" = "source" ] || [ "$fclass" = "test" ]; then
        echo "⚠ $PHASE: Code file modified — ${f##*/} (spec/review phases are docs-only)" >&2
      fi
      ;;
  esac
done <<< "$FILES"

# --- Full mode: adherence tracking with coverage progress ---
# IS_FULL was set from the bulk config read above

if [ "$IS_FULL" = "true" ]; then
  ADHERENCE=".correctless/artifacts/adherence-state-${slug}-${hash}.json"

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
