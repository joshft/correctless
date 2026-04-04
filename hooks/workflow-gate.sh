#!/usr/bin/env bash
# shellcheck disable=SC2254
# Correctless — PreToolUse gate hook (supports both Lite and Full modes)
# Blocks file operations that violate the current workflow phase.
#
# Called by Claude Code as a PreToolUse hook. Receives tool info on stdin as JSON:
#   { "tool_name": "Edit", "tool_input": { "file_path": "...", ... } }
#
# Exit codes:
#   0 — allow the operation
#   2 — block the operation (message printed to stderr)
# SC2254 disabled: unquoted $pat in case is intentional — we need glob matching

set -euo pipefail

# Disable glob expansion — patterns like *.ts must not expand to filenames
set -f
command -v jq >/dev/null 2>&1 || { echo "BLOCKED: jq not found — required for workflow gate" >&2; exit 2; }

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
CONFIG_FILE="$REPO_ROOT/.correctless/config/workflow-config.json"
ARTIFACTS_DIR="$REPO_ROOT/.correctless/artifacts"
TEST_EDIT_LOG="$ARTIFACTS_DIR/tdd-test-edits.log"

# ---------------------------------------------------------------------------
# Read hook input (single jq parse for all fields)
# ---------------------------------------------------------------------------

INPUT="$(cat)"
eval "$(echo "$INPUT" | jq -r '
  @sh "TOOL_NAME=\(.tool_name // "")",
  @sh "TOOL_INPUT_FILE=\(.tool_input.file_path // "")",
  @sh "TOOL_INPUT_COMMAND=\(.tool_input.command // "")",
  @sh "TOOL_INPUT_NEW=\(.tool_input.new_string // .tool_input.content // "")",
  @sh "TOOL_INPUT_EDITS=\([.tool_input.edits[]?.file_path // empty] | join("\n"))",
  @sh "TOOL_INPUT_EDITS_NEW=\([.tool_input.edits[]?.new_string // empty] | join("\n"))"
' 2>/dev/null)" || exit 0

# Only gate write operations
case "$TOOL_NAME" in
  Edit|Write|MultiEdit|NotebookEdit|CreateFile) ;;
  Bash)
    if [ -z "$TOOL_INPUT_COMMAND" ]; then exit 0; fi
    COMMAND="$TOOL_INPUT_COMMAND"
    # Detect write/destructive patterns — tokenize to catch chained commands
    _has_write_pattern() {
      local cmd="$1"
      # Check redirect operators (single combined grep)
      echo "$cmd" | grep -qE '>>|[^-0-9]>' && return 0
      # Tokenize on shell metacharacters and check each token
      # shellcheck disable=SC2141
      local IFS=$' \t\n;|&()`'
      for tok in $cmd; do
        case "$tok" in
          cp|mv|tee|install|rm|rmdir|unlink|dd|curl|wget|rsync|patch|truncate|shred|ln) return 0 ;;
          sed) [[ "$cmd" =~ sed[[:space:]]+-i ]] && return 0 ;;
          perl) [[ "$cmd" =~ perl[[:space:]]+-i ]] && return 0 ;;
          python|python3|node|ruby) return 0 ;;
        esac
      done
      return 1
    }
    if ! _has_write_pattern "$COMMAND"; then
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
  branch="$(git --no-optional-locks branch --show-current 2>/dev/null)"
  [ -n "$branch" ] || { exit 0; }  # detached HEAD: no workflow, allow all
  local slug raw_hash
  slug="${branch//[^a-zA-Z0-9]/-}"
  slug="${slug:0:80}"
  raw_hash="$(printf '%s' "$branch" | (md5sum 2>/dev/null || md5))"
  echo "${slug}-${raw_hash:0:6}"
}

STATE_FILE="$ARTIFACTS_DIR/workflow-state-$(branch_slug).json"

# No state file → check fail-closed config
if [ ! -f "$STATE_FILE" ]; then
  FAIL_CLOSED="false"
  FC_SOURCE_PAT=""
  if [ -f "$CONFIG_FILE" ]; then
    eval "$(jq -r '
      @sh "FAIL_CLOSED=\(.workflow.fail_closed_when_no_state // false)",
      @sh "FC_SOURCE_PAT=\(.patterns.source_file // "")"
    ' "$CONFIG_FILE" 2>/dev/null)" || true
  fi
  if [ "$FAIL_CLOSED" = "true" ]; then
    # Full mode fail-closed: block source edits when no state file exists
    TARGET_FILE_CHECK="$TOOL_INPUT_FILE"
    if [ -z "$TARGET_FILE_CHECK" ] && [ -n "$TOOL_INPUT_EDITS" ]; then
      TARGET_FILE_CHECK="${TOOL_INPUT_EDITS%%$'\n'*}"
    fi
    if [ -n "$TARGET_FILE_CHECK" ]; then
      SOURCE_PAT="$FC_SOURCE_PAT"
      if [ -n "$SOURCE_PAT" ]; then
        BASENAME_CHECK="${TARGET_FILE_CHECK##*/}"
        _FC_OLDIFS="$IFS"
        IFS='|'
        for p in $SOURCE_PAT; do
          IFS="$_FC_OLDIFS"
          case "$BASENAME_CHECK" in
            $p)
              echo "BLOCKED [fail-closed]: This project requires an active workflow before editing source files.
  Start a workflow: .correctless/hooks/workflow-advance.sh init \"task description\"
  (You must be on a feature branch, not main.)
  Or run /cstatus to see what's going on." >&2
              exit 2
              ;;
          esac
        done
        IFS="$_FC_OLDIFS"
      fi
    fi
  fi
  exit 0
fi

# Bulk-read state file: phase + override fields in one jq call
eval "$(jq -r '
  @sh "PHASE=\(.phase // "")",
  @sh "OVERRIDE_ACTIVE=\(.override.active // false)",
  @sh "OVERRIDE_REMAINING=\(.override.remaining_calls // 0)"
' "$STATE_FILE" 2>/dev/null)" || {
  echo "BLOCKED: State file is corrupt or unreadable. Run workflow-advance.sh status to check." >&2
  exit 2
}

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

if [ "$OVERRIDE_ACTIVE" = "true" ]; then
  REMAINING="$OVERRIDE_REMAINING"
  if [ "$REMAINING" -gt 0 ]; then
    # Atomic read-modify-write: decrement and deactivate in a single jq call
    jq 'if .override.remaining_calls > 0 then
          .override.remaining_calls -= 1
          | if .override.remaining_calls <= 0 then .override.active = false else . end
        else . end' "$STATE_FILE" > "$STATE_FILE.$$" \
      && mv "$STATE_FILE.$$" "$STATE_FILE" \
      || { rm -f "$STATE_FILE.$$"; exit 2; }
    exit 0
  fi
fi

# ---------------------------------------------------------------------------
# Block direct edits to state files
# ---------------------------------------------------------------------------

get_target_file() {
  if [ "$TOOL_NAME" = "Bash" ]; then
    # Extract file targets from shell command — includes all common extensions
    echo "$COMMAND" | grep -oE '[^ ]+\.(go|ts|tsx|js|jsx|py|rs|java|rb|cpp|c|h|sh|json|md|yaml|yml|toml|cfg|ini|sql|css|html|vue|svelte)' | head -5 || true
    return
  fi
  # Use pre-parsed fields from bulk jq at top
  if [ -n "$TOOL_INPUT_FILE" ]; then
    echo "$TOOL_INPUT_FILE"
  elif [ -n "$TOOL_INPUT_EDITS" ]; then
    # MultiEdit: output ALL file paths (one per line) so each gets checked
    echo "$TOOL_INPUT_EDITS"
  fi
}

TARGET_FILES="$(get_target_file)"

# Check each target file for protected files (state files, config during TDD)
check_protected_file() {
  local tf="$1"
  case "$tf" in
    *workflow-state-*.json)
      echo "BLOCKED: Direct edits to workflow state files are not allowed. Use workflow-advance.sh to change state." >&2
      exit 2
      ;;
    *workflow-config.json)
      echo "BLOCKED [$PHASE]: workflow-config.json is protected during active workflows to prevent test command manipulation. Use 'reset' to reconfigure." >&2
      exit 2
      ;;
  esac
}

# For MultiEdit, TARGET_FILES may contain multiple lines — check all
while IFS= read -r _tf; do
  [ -z "$_tf" ] && continue
  check_protected_file "$_tf"
done <<< "$TARGET_FILES"

# No target files identified → allow
if [ -z "$TARGET_FILES" ]; then
  exit 0
fi

# For phase gating below, use the first file for single-file tools.
# For MultiEdit, check ALL files — block if ANY is in a blocked class.
TARGET_FILE="${TARGET_FILES%%$'\n'*}"
REL_FILE="${TARGET_FILE#$REPO_ROOT/}"
# Normalize: strip leading ./ to prevent classification bypass
REL_FILE="${REL_FILE#./}"

# ---------------------------------------------------------------------------
# Classify file
# ---------------------------------------------------------------------------

if [ ! -f "$CONFIG_FILE" ]; then
  exit 0  # No config → can't classify → allow
fi

# Bulk-read config: patterns + monorepo flag in one jq call
eval "$(jq -r '
  @sh "CFG_IS_MONOREPO=\(.is_monorepo // false)",
  @sh "CFG_TEST_PATTERN=\(.patterns.test_file // "")",
  @sh "CFG_SOURCE_PATTERN=\(.patterns.source_file // "")"
' "$CONFIG_FILE" 2>/dev/null)" || true

# ---------------------------------------------------------------------------
# Package resolution for monorepos (longest-prefix match with caching)
# ---------------------------------------------------------------------------

resolve_package() {
  local file="$1"
  # Fast bail: not a monorepo (uses pre-loaded flag)
  [ "$CFG_IS_MONOREPO" = "true" ] || { echo "."; return; }

  # Check cache (invalidated by config mtime)
  local mtime cache_file=""
  mtime="$(stat -c %Y "$CONFIG_FILE" 2>/dev/null || stat -f %m "$CONFIG_FILE" 2>/dev/null)"
  if [ -n "$mtime" ] && [ -d "$ARTIFACTS_DIR" ]; then
    cache_file="$ARTIFACTS_DIR/.pkg-cache-${mtime}.json"
    if [ -f "$cache_file" ]; then
      local cached
      cached="$(jq -r --arg f "$file" '.[$f] // empty' "$cache_file" 2>/dev/null)"
      if [ -n "$cached" ]; then echo "$cached"; return; fi
    fi
  fi

  # Longest-prefix match
  local best="." best_len=0
  while IFS= read -r key; do
    local pkg_path
    pkg_path="$(jq -r --arg k "$key" '.packages[$k].path' "$CONFIG_FILE")"
    case "$file" in
      "$pkg_path"/*)
        if [ ${#pkg_path} -gt $best_len ]; then
          best="$key"; best_len=${#pkg_path}
        fi ;;
    esac
  done < <(jq -r '.packages | keys[]' "$CONFIG_FILE" 2>/dev/null)

  # Write to cache (only if mtime was available)
  if [ -n "$cache_file" ]; then
    # Prune stale cache files — shell glob instead of find subprocess (REG-006)
    for _old_cache in "$ARTIFACTS_DIR"/.pkg-cache-*.json; do
      [ -f "$_old_cache" ] && [ "$_old_cache" != "$cache_file" ] && rm -f "$_old_cache" 2>/dev/null
    done
    if [ -f "$cache_file" ]; then
      jq --arg f "$file" --arg p "$best" '. + {($f): $p}' "$cache_file" > "$cache_file.$$" 2>/dev/null && mv "$cache_file.$$" "$cache_file" 2>/dev/null || true
    else
      jq -nc --arg f "$file" --arg p "$best" '{($f): $p}' > "$cache_file" 2>/dev/null || true
    fi
  fi

  echo "$best"
}

# Resolve package for the current file and read appropriate patterns
PACKAGE_SCOPE="$(resolve_package "$REL_FILE")"
if [ "$PACKAGE_SCOPE" != "." ]; then
  # Monorepo: read package-scoped patterns in single jq call (IO-R2-002)
  eval "$(jq -r --arg s "$PACKAGE_SCOPE" '
    @sh "TEST_PATTERN=\((.packages[$s].patterns.test_file) // .patterns.test_file // "")",
    @sh "SOURCE_PATTERN=\((.packages[$s].patterns.source_file) // .patterns.source_file // "")"
  ' "$CONFIG_FILE" 2>/dev/null)" || true
else
  # Single-package: use pre-loaded patterns
  TEST_PATTERN="$CFG_TEST_PATTERN"
  SOURCE_PATTERN="$CFG_SOURCE_PATTERN"
fi

# Fail closed if patterns are empty — prevents classification bypass via config tampering
if [ -z "$SOURCE_PATTERN" ] && [ -z "$TEST_PATTERN" ]; then
  echo "BLOCKED: File classification patterns are empty — workflow config may be corrupt or tampered." >&2
  exit 2
fi

classify_file() {
  local file="$1"
  # Normalize case — patterns are lowercase, filenames may not be (bash 4+ builtin)
  file="${file,,}"
  local bname
  bname="${file##*/}"

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

# For MultiEdit, find the most restrictive classification across all files.
# Collect ALL source files (needed for per-file STUB:TDD checks in RED phase).
MOST_RESTRICTIVE="other"
ALL_SOURCE_FILES=""
while IFS= read -r _check_file; do
  [ -z "$_check_file" ] && continue
  _rel="${_check_file#$REPO_ROOT/}"
  _cls="$(classify_file "$_rel")"
  if [ "$_cls" = "source" ]; then
    MOST_RESTRICTIVE="source"
    REL_FILE="$_rel"
    ALL_SOURCE_FILES="${ALL_SOURCE_FILES:+$ALL_SOURCE_FILES
}$_rel"
  elif [ "$_cls" = "test" ] && [ "$MOST_RESTRICTIVE" != "source" ]; then
    MOST_RESTRICTIVE="test"
    REL_FILE="$_rel"
  fi
done <<< "$TARGET_FILES"

FILE_CLASS="$MOST_RESTRICTIVE"

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
  Run: .correctless/hooks/workflow-advance.sh status  (to see current state)
  Bypass: .correctless/hooks/workflow-advance.sh override \"reason\"  (emergency only)"
    fi
    ;;

  tdd-tests)
    # RED phase: test files allowed, source files only with STUB:TDD
    # For MultiEdit, check EVERY source file (not just the first)
    if [ "$FILE_CLASS" = "source" ]; then
      while IFS= read -r _src_rel; do
        [ -z "$_src_rel" ] && continue
        if [ -f "$REPO_ROOT/$_src_rel" ]; then
          if ! grep -q 'STUB:TDD' "$REPO_ROOT/$_src_rel" 2>/dev/null; then
            # File exists but no STUB:TDD — check if the edit adds it
            if [ "$TOOL_NAME" != "Bash" ]; then
              if [[ "$TOOL_INPUT_NEW" == *"STUB:TDD"* ]] || [[ "$TOOL_INPUT_EDITS_NEW" == *"STUB:TDD"* ]]; then
                continue  # Edit is adding STUB:TDD to this file — allow
              fi
            fi
            block "RED phase — write tests first, not implementation.
  Source file '$_src_rel' is blocked — no STUB:TDD marker found.
  What to do: write your test files first. For type signatures that tests need to compile,
  create stub functions with '// STUB:TDD' in the body and zero-value returns.
  When tests exist and fail: .correctless/hooks/workflow-advance.sh impl  (unlocks source files)"
          fi
        else
          # New file — check if content contains STUB:TDD
          if [ "$TOOL_NAME" != "Bash" ]; then
            # Check both single-edit and multi-edit content fields
            _has_stub=false
            [[ "$TOOL_INPUT_NEW" == *"STUB:TDD"* ]] && _has_stub=true
            [[ "$TOOL_INPUT_EDITS_NEW" == *"STUB:TDD"* ]] && _has_stub=true
            if { [ -n "$TOOL_INPUT_NEW" ] || [ -n "$TOOL_INPUT_EDITS_NEW" ]; } && [ "$_has_stub" = "false" ]; then
              block "RED phase — new source file '$_src_rel' must contain STUB:TDD tag.
  Add '// STUB:TDD' (or '# STUB:TDD' in Python) to function bodies.
  Stub bodies should contain only the tag, zero-value returns, or panic(\"not implemented\")."
            fi
          fi
        fi
      done <<< "$ALL_SOURCE_FILES"
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
  If issues found: .correctless/hooks/workflow-advance.sh fix  (returns to implementation)
  If clean: .correctless/hooks/workflow-advance.sh done  (completes the workflow)"
      else
        block "Verification phase — code is frozen for final checks.
  If all checks pass: .correctless/hooks/workflow-advance.sh done
  Bypass: .correctless/hooks/workflow-advance.sh override \"reason\"  (emergency only)"
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
