#!/usr/bin/env bash
# Correctless — PreToolUse gate hook (supports both Lite and Full modes)
# Blocks file operations that violate the current workflow phase.
#
# Called by Claude Code as a PreToolUse hook. Receives tool info on stdin as JSON:
#   { "tool_name": "Edit", "tool_input": { "file_path": "...", ... } }
#
# Exit codes:
#   0 — allow the operation
#   2 — block the operation (message printed to stderr)

set -euo pipefail

# Disable glob expansion — patterns like *.ts must not expand to filenames
set -f
command -v jq >/dev/null 2>&1 || { echo "BLOCKED: jq not found — required for workflow gate" >&2; exit 2; }

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
CONFIG_FILE="$REPO_ROOT/.claude/workflow-config.json"
ARTIFACTS_DIR="$REPO_ROOT/.claude/artifacts"
TEST_EDIT_LOG="$ARTIFACTS_DIR/tdd-test-edits.log"

# ---------------------------------------------------------------------------
# Read hook input
# ---------------------------------------------------------------------------

INPUT="$(cat)"
TOOL_NAME="$(echo "$INPUT" | jq -r '.tool_name // empty')"
TOOL_INPUT="$(echo "$INPUT" | jq -r '.tool_input // empty')"

# Only gate write operations
case "$TOOL_NAME" in
  Edit|Write|MultiEdit|NotebookEdit|CreateFile) ;;
  Bash)
    # Guard: empty/null tool_input is not valid JSON for jq
    if [ -z "$TOOL_INPUT" ]; then exit 0; fi
    # Check for shell write patterns targeting source files
    COMMAND="$(echo "$TOOL_INPUT" | jq -r '.command // empty')"
    if [ -z "$COMMAND" ]; then
      exit 0
    fi
    # Only inspect commands that contain write-like patterns
    # Use space-padded matching instead of \b for BSD grep portability
    if ! echo " $COMMAND " | grep -qE '(>>?|tee |sed -i| cp | mv | install )'; then
      exit 0
    fi
    # Fall through to phase checking with the command as context
    ;;
  *)
    exit 0
    ;;
esac

# ---------------------------------------------------------------------------
# Read state
# ---------------------------------------------------------------------------

branch_slug() {
  local branch
  branch="$(git branch --show-current 2>/dev/null)"
  local slug hash
  slug="$(echo "$branch" | sed 's/[^a-zA-Z0-9]/-/g' | cut -c1-80)"
  hash="$(printf '%s' "$branch" | (md5sum 2>/dev/null || md5) | cut -c1-6)"
  echo "${slug}-${hash}"
}

STATE_FILE="$ARTIFACTS_DIR/workflow-state-$(branch_slug).json"

# No state file → check fail-closed config
if [ ! -f "$STATE_FILE" ]; then
  FAIL_CLOSED="false"
  if [ -f "$CONFIG_FILE" ]; then
    FAIL_CLOSED="$(jq -r '.workflow.fail_closed_when_no_state // false' "$CONFIG_FILE")"
  fi
  if [ "$FAIL_CLOSED" = "true" ]; then
    # Full mode fail-closed: block source edits when no state file exists
    TARGET_FILE_CHECK="$(echo "$TOOL_INPUT" | jq -r '.file_path // empty')"
    if [ -n "$TARGET_FILE_CHECK" ]; then
      SOURCE_PAT="$(jq -r '.patterns.source_file // empty' "$CONFIG_FILE")"
      if [ -n "$SOURCE_PAT" ]; then
        BASENAME_CHECK="$(basename "$TARGET_FILE_CHECK")"
        IFS='|'
        for p in $SOURCE_PAT; do
          case "$BASENAME_CHECK" in
            $p)
              echo "BLOCKED [fail-closed]: This project requires an active workflow before editing source files.
  Start a workflow: .claude/hooks/workflow-advance.sh init \"task description\"
  (You must be on a feature branch, not main.)
  Or run /cstatus to see what's going on." >&2
              exit 2
              ;;
          esac
        done
        unset IFS
      fi
    fi
  fi
  exit 0
fi

PHASE="$(jq -r '.phase' "$STATE_FILE")"

# Validate phase is a known value
case "$PHASE" in
  spec|review|review-spec|model|tdd-tests|tdd-impl|tdd-qa|tdd-verify|done|verified|documented|audit) ;;
  *)
    echo "BLOCKED: Invalid or corrupted workflow phase: $PHASE. Run workflow-advance.sh status to check." >&2
    exit 2
    ;;
esac

# Post-TDD phases → allow everything (verification, docs, and documented are read/write as needed)
case "$PHASE" in
  done|verified|documented) exit 0 ;;
esac

# ---------------------------------------------------------------------------
# Check for active override
# ---------------------------------------------------------------------------

OVERRIDE_ACTIVE="$(jq -r '.override.active // false' "$STATE_FILE")"
if [ "$OVERRIDE_ACTIVE" = "true" ]; then
  REMAINING="$(jq -r '.override.remaining_calls // 0' "$STATE_FILE")"
  if [ "$REMAINING" -gt 0 ]; then
    # Atomic read-modify-write: decrement and deactivate in a single jq call
    jq 'if .override.remaining_calls > 0 then
          .override.remaining_calls -= 1
          | if .override.remaining_calls <= 0 then .override.active = false else . end
        else . end' "$STATE_FILE" > "$STATE_FILE.$$" \
      && mv "$STATE_FILE.$$" "$STATE_FILE"
    exit 0
  fi
fi

# ---------------------------------------------------------------------------
# Block direct edits to state files
# ---------------------------------------------------------------------------

get_target_file() {
  if [ "$TOOL_NAME" = "Bash" ]; then
    # Try to extract file target from shell command — best-effort
    echo "$COMMAND" | grep -oE '[^ ]+\.(go|ts|tsx|js|jsx|py|rs|java|rb|cpp|c|h)' | head -1 || true
    return
  fi
  # Handle MultiEdit which uses .edits[].file_path instead of .file_path
  local fp
  fp="$(echo "$TOOL_INPUT" | jq -r '.file_path // empty')"
  if [ -z "$fp" ]; then
    fp="$(echo "$TOOL_INPUT" | jq -r '.edits[0].file_path // empty' 2>/dev/null)"
  fi
  echo "$fp"
}

TARGET_FILE="$(get_target_file)"

# Block edits to state files
if echo "$TARGET_FILE" | grep -q 'workflow-state-.*\.json'; then
  echo "BLOCKED: Direct edits to workflow state files are not allowed. Use workflow-advance.sh to change state." >&2
  exit 2
fi

# Block edits to workflow config during TDD phases (prevents test command injection)
if echo "$TARGET_FILE" | grep -q 'workflow-config\.json'; then
  case "$PHASE" in
    tdd-tests|tdd-impl|tdd-qa|tdd-verify)
      echo "BLOCKED [$PHASE]: workflow-config.json is protected during TDD phases to prevent test command manipulation." >&2
      exit 2
      ;;
  esac
fi

# No target file identified → allow
if [ -z "$TARGET_FILE" ]; then
  exit 0
fi

# Make path relative to repo root for pattern matching
REL_FILE="${TARGET_FILE#$REPO_ROOT/}"

# ---------------------------------------------------------------------------
# Classify file
# ---------------------------------------------------------------------------

if [ ! -f "$CONFIG_FILE" ]; then
  exit 0  # No config → can't classify → allow
fi

TEST_PATTERN="$(jq -r '.patterns.test_file // empty' "$CONFIG_FILE")"
SOURCE_PATTERN="$(jq -r '.patterns.source_file // empty' "$CONFIG_FILE")"

classify_file() {
  local file="$1"
  local bname
  bname="$(basename "$file")"

  # Check test patterns (pipe-delimited globs like "*.test.ts|*.spec.ts|tests/*.rs")
  if [ -n "$TEST_PATTERN" ]; then
    local oldifs="$IFS"
    IFS='|'
    for pat in $TEST_PATTERN; do
      IFS="$oldifs"
      # Patterns containing "/" need to match against the full relative path
      case "$pat" in
        */*)
          case "$file" in
            $pat) echo "test"; return ;;
          esac
          ;;
        *)
          case "$bname" in
            $pat) echo "test"; return ;;
          esac
          ;;
      esac
    done
    IFS="$oldifs"
  fi

  # Check source patterns
  if [ -n "$SOURCE_PATTERN" ]; then
    local oldifs="$IFS"
    IFS='|'
    for pat in $SOURCE_PATTERN; do
      IFS="$oldifs"
      case "$pat" in
        */*)
          case "$file" in
            $pat) echo "source"; return ;;
          esac
          ;;
        *)
          case "$bname" in
            $pat) echo "source"; return ;;
          esac
          ;;
      esac
    done
    IFS="$oldifs"
  fi

  echo "other"
}

FILE_CLASS="$(classify_file "$REL_FILE")"

# Non-source, non-test files are always allowed
if [ "$FILE_CLASS" = "other" ]; then
  exit 0
fi

# ---------------------------------------------------------------------------
# Phase-specific gating
# ---------------------------------------------------------------------------

block() {
  echo "BLOCKED [$PHASE]: $*" >&2
  exit 2
}

case "$PHASE" in
  spec|review|review-spec|model)
    # Spec, review, model phases: no source or test edits
    if [ "$FILE_CLASS" = "source" ] || [ "$FILE_CLASS" = "test" ]; then
      block "You're in the $PHASE phase — source and test files are locked until the spec is reviewed and approved.
  What to do: finish the spec conversation, then advance the workflow.
  Run: .claude/hooks/workflow-advance.sh status  (to see current state)
  Bypass: .claude/hooks/workflow-advance.sh override \"reason\"  (emergency only)"
    fi
    ;;

  tdd-tests)
    # RED phase: test files allowed, source files only with STUB:TDD
    if [ "$FILE_CLASS" = "source" ]; then
      # Check if the file exists and contains STUB:TDD
      if [ -f "$REPO_ROOT/$REL_FILE" ]; then
        if ! grep -q 'STUB:TDD' "$REPO_ROOT/$REL_FILE" 2>/dev/null; then
          # File exists but no STUB:TDD — check if the edit adds it
          if [ "$TOOL_NAME" != "Bash" ]; then
            NEW_CONTENT="$(echo "$TOOL_INPUT" | jq -r '.new_string // .content // empty')"
            if echo "$NEW_CONTENT" | grep -q 'STUB:TDD'; then
              exit 0  # Edit is adding STUB:TDD — allow
            fi
          fi
          block "RED phase — write tests first, not implementation.
  Source files are blocked unless they contain structural stubs marked with STUB:TDD.
  What to do: write your test files first. For type signatures that tests need to compile,
  create stub functions with '// STUB:TDD' in the body and zero-value returns.
  When tests exist and fail: .claude/hooks/workflow-advance.sh impl  (unlocks source files)"
        fi
      else
        # New file — check if content contains STUB:TDD
        if [ "$TOOL_NAME" != "Bash" ]; then
          NEW_CONTENT="$(echo "$TOOL_INPUT" | jq -r '.content // .new_string // empty')"
          if [ -n "$NEW_CONTENT" ] && ! echo "$NEW_CONTENT" | grep -q 'STUB:TDD'; then
            block "RED phase — new source files must contain STUB:TDD tag.
  Add '// STUB:TDD' (or '# STUB:TDD' in Python) to function bodies.
  Stub bodies should contain only the tag, zero-value returns, or panic(\"not implemented\")."
          fi
        fi
      fi
    fi
    # Test files are allowed
    ;;

  tdd-impl)
    # GREEN phase: all edits allowed, but test edits are logged
    if [ "$FILE_CLASS" = "test" ]; then
      mkdir -p "$(dirname "$TEST_EDIT_LOG")"
      echo "[$(date -u +%FT%TZ)] $REL_FILE — edited during GREEN phase" >> "$TEST_EDIT_LOG"
    fi
    # Everything allowed
    ;;

  tdd-qa|tdd-verify)
    # QA and verify phases: no source or test edits
    if [ "$FILE_CLASS" = "source" ] || [ "$FILE_CLASS" = "test" ]; then
      if [ "$PHASE" = "tdd-qa" ]; then
        block "QA phase — code is frozen while the QA agent reviews.
  Source and test files are locked. Report findings as text, don't edit code.
  If issues found: .claude/hooks/workflow-advance.sh fix  (returns to implementation)
  If clean: .claude/hooks/workflow-advance.sh done  (completes the workflow)"
      else
        block "Verification phase — code is frozen for final checks.
  If all checks pass: .claude/hooks/workflow-advance.sh done
  Bypass: .claude/hooks/workflow-advance.sh override \"reason\"  (emergency only)"
      fi
    fi
    ;;

  audit)
    # Audit phase: managed by the audit skill — source edits allowed during fix rounds
    # The audit orchestrator handles sub-phase gating via agent tool restrictions
    ;;
esac

# Default: allow
exit 0
