#!/usr/bin/env bash
# Correctless — PostToolUse audit trail + adherence feedback
# Records every file modification with workflow phase context.
# Lite mode: phase-violation alerts to stderr
# Full mode: + adherence tracking with coverage progress
# MUST be fast. Audit logging <100ms. Adherence feedback <200ms.

# Fast-path bail: if no .claude/artifacts/ directory, exit immediately.
[ -d ".claude/artifacts" ] || exit 0

# Read input
INPUT="$(cat)"
TOOL_NAME="$(echo "$INPUT" | jq -r '.tool_name // empty')"

# Fast-path bail: no tool name = malformed input
[ -n "$TOOL_NAME" ] || exit 0

# Extract target file(s) — MultiEdit may have multiple
FILES=""
case "$TOOL_NAME" in
  Bash)
    FILES="$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null | grep -oE '[^ ]+\.(go|ts|tsx|js|jsx|py|rs|java|rb|cpp|c|h)' | head -1)" || true
    ;;
  MultiEdit)
    FILES="$(echo "$INPUT" | jq -r '.tool_input.edits[]?.file_path // empty' 2>/dev/null)"
    ;;
  *)
    FILES="$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)"
    ;;
esac

# Compute branch slug and find state file
branch="$(git --no-optional-locks branch --show-current 2>/dev/null)" || exit 0
[ -n "$branch" ] || exit 0

slug="$(echo "$branch" | sed 's/[^a-zA-Z0-9]/-/g' | cut -c1-80)"
hash="$(printf '%s' "$branch" | (md5sum 2>/dev/null || md5) | cut -c1-6)"
STATE_FILE=".claude/artifacts/workflow-state-${slug}-${hash}.json"

# Fast-path bail: no state file = no active workflow = nothing to audit
[ -f "$STATE_FILE" ] || exit 0

# Read phase and config
PHASE="$(jq -r '.phase // "unknown"' "$STATE_FILE" 2>/dev/null)"
CONFIG_FILE=".claude/workflow-config.json"

# --- Audit trail logging (always, both modes) ---

TRAIL=".claude/artifacts/audit-trail-${slug}-${hash}.jsonl"
TS="$(date -u +%FT%TZ 2>/dev/null || date -u +%Y-%m-%dT%H:%M:%SZ)"

echo "$FILES" | while IFS= read -r f; do
  [ -z "$f" ] && continue
  jq -nc --arg ts "$TS" --arg phase "$PHASE" --arg tool "$TOOL_NAME" --arg file "$f" --arg branch "$branch" \
    '{ts:$ts,phase:$phase,tool:$tool,file:$file,branch:$branch}' >> "$TRAIL" 2>/dev/null
done

# --- Adherence feedback (Lite: violations only, Full: + coverage tracking) ---

# Read test/source patterns for file classification
TEST_PATTERN=""
SOURCE_PATTERN=""
if [ -f "$CONFIG_FILE" ]; then
  TEST_PATTERN="$(jq -r '.patterns.test_file // empty' "$CONFIG_FILE" 2>/dev/null)"
  SOURCE_PATTERN="$(jq -r '.patterns.source_file // empty' "$CONFIG_FILE" 2>/dev/null)"
fi

# Simple file classifier (matches gate logic)
classify() {
  local file="$1" bname
  bname="$(basename "$file")"
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

echo "$FILES" | while IFS= read -r f; do
  [ -z "$f" ] && continue
  fclass="$(classify "$f")"

  case "$PHASE" in
    tdd-qa|tdd-verify)
      # QA/verify phases should be read-only for source and test files
      if [ "$fclass" = "source" ] && [ "$TOOL_NAME" != "Read" ]; then
        echo "⚠ $PHASE: Source file modified — $(basename "$f") (this phase should be read-only)" >&2
      fi
      if [ "$fclass" = "test" ] && [ "$TOOL_NAME" != "Read" ]; then
        echo "⚠ $PHASE: Test file modified — $(basename "$f") (this phase should be read-only)" >&2
      fi
      ;;
    tdd-impl)
      # GREEN phase: test edits should be logged
      if [ "$fclass" = "test" ] && [ "$TOOL_NAME" != "Read" ]; then
        echo "📝 GREEN: Test file edited — $(basename "$f") (should be logged in test-edit-log)" >&2
      fi
      ;;
    spec|review|review-spec|model)
      # Spec/review phases: no source or test edits
      if [ "$fclass" = "source" ] || [ "$fclass" = "test" ]; then
        echo "⚠ $PHASE: Code file modified — $(basename "$f") (spec/review phases are docs-only)" >&2
      fi
      ;;
  esac
done

# --- Full mode: adherence tracking with coverage progress ---

IS_FULL="false"
if [ -f "$CONFIG_FILE" ]; then
  intensity="$(jq -r '.workflow.intensity // empty' "$CONFIG_FILE" 2>/dev/null)"
  [ -n "$intensity" ] && [ "$intensity" != "null" ] && IS_FULL="true"
fi

if [ "$IS_FULL" = "true" ]; then
  ADHERENCE=".claude/artifacts/adherence-state-${slug}-${hash}.json"

  # Initialize adherence state if missing
  if [ ! -f "$ADHERENCE" ]; then
    jq -nc '{phase_files:{},modified_files:[],read_files:[]}' > "$ADHERENCE" 2>/dev/null
  fi

  # Track which files are modified and read per phase
  echo "$FILES" | while IFS= read -r f; do
    [ -z "$f" ] && continue

    if [ "$TOOL_NAME" = "Read" ] || [ "$TOOL_NAME" = "Grep" ]; then
      # Track reads (for QA coverage analysis)
      jq --arg f "$f" --arg p "$PHASE" \
        '.read_files += [$f] | .read_files |= unique' \
        "$ADHERENCE" > "$ADHERENCE.$$" 2>/dev/null && mv "$ADHERENCE.$$" "$ADHERENCE" 2>/dev/null
    else
      # Track writes
      jq --arg f "$f" --arg p "$PHASE" \
        '.modified_files += [$f] | .modified_files |= unique | .phase_files[$p] = ((.phase_files[$p] // 0) + 1)' \
        "$ADHERENCE" > "$ADHERENCE.$$" 2>/dev/null && mv "$ADHERENCE.$$" "$ADHERENCE" 2>/dev/null
    fi
  done

  # Show coverage progress during QA phase
  if [ "$PHASE" = "tdd-qa" ] && [ "$TOOL_NAME" = "Read" ]; then
    # Count how many modified files QA has read
    if [ -f "$ADHERENCE" ]; then
      mod_count="$(jq '.modified_files | length' "$ADHERENCE" 2>/dev/null || echo 0)"
      read_count="$(jq '[.read_files[] as $r | .modified_files[] | select(. == $r)] | unique | length' "$ADHERENCE" 2>/dev/null || echo 0)"
      if [ "$mod_count" -gt 0 ] 2>/dev/null; then
        echo "🔍 QA: Read $(basename "$(echo "$FILES" | head -1)") ($read_count of $mod_count modified files reviewed)" >&2
      fi
    fi
  fi
fi

# Never fail
exit 0
