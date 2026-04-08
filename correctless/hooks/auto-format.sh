#!/usr/bin/env bash
# HOOK_TYPE: PostToolUse
# HOOK_MATCHER: Edit|Write|MultiEdit
# Correctless — PostToolUse auto-format hook
# Runs the project's configured formatter after Edit/Write/MultiEdit.
# MUST exit 0 always. Formatting is advisory, never gating.

# ============================================
# STEP 1: Parse stdin JSON (single jq bulk call)
# ============================================

# Fail-open: jq required for JSON parsing (PAT-005: PostToolUse exits 0, never blocks)
command -v jq >/dev/null 2>&1 || exit 0

INPUT="$(cat)"
eval "$(echo "$INPUT" | jq -r '
  @sh "TOOL_NAME=\(.tool_name // "")",
  @sh "TOOL_INPUT_FILE=\(.tool_input.file_path // "")",
  @sh "TOOL_INPUT_EDITS=\([.tool_input.edits[]?.file_path // empty] | join("\n"))"
' 2>/dev/null)" || exit 0

# ============================================
# STEP 2: Fast-path bail — only Edit, Write, MultiEdit
# ============================================

case "$TOOL_NAME" in
  Edit|Write|MultiEdit) ;;
  *) exit 0 ;;
esac

# ============================================
# STEP 3: Read config (single jq bulk call)
# ============================================

CONFIG_FILE=".correctless/config/workflow-config.json"
[ -f "$CONFIG_FILE" ] || exit 0

eval "$(jq -r '
  @sh "AF_ENABLED=\(.auto_format.enabled // false)",
  @sh "AF_FORMATTERS=\(.auto_format.formatters // {} | to_entries | map("\(.key)=\(.value)") | join("\n"))"
' "$CONFIG_FILE" 2>/dev/null)" || exit 0

# Bail if auto_format is not explicitly enabled
[ "$AF_ENABLED" = "true" ] || exit 0

# ============================================
# STEP 4: Collect file paths to format
# ============================================

FILES=""
case "$TOOL_NAME" in
  MultiEdit)
    FILES="$TOOL_INPUT_EDITS"
    ;;
  *)
    FILES="$TOOL_INPUT_FILE"
    ;;
esac

[ -n "$FILES" ] || exit 0

# ============================================
# STEP 5: Format each file
# ============================================

# validate_command — exact-match allowlist + metacharacter defense-in-depth (QA-NEW-001, QA-NEW-002)
validate_command() {
  local cmd="$1"
  # Exact match against allowed formatter commands
  case "$cmd" in
    prettier|"npx prettier"|eslint|"npx eslint"|black|ruff|gofmt|rustfmt)
      ;;
    *)
      return 1
      ;;
  esac
  # Defense-in-depth: reject shell metacharacters (QA-003)
  # None of the 8 allowed strings contain these, but guards against future allowlist edits
  case "$cmd" in
    *'|'*|*';'*|*'$('*|*'`'*|*'&'*) return 1 ;;
  esac
  return 0
}

# find_formatter — match file extension against config formatters map
# Sets FOUND_FORMATTER global instead of echoing (avoids subshell fork in loop)
find_formatter() {
  FOUND_FORMATTER=""
  local filepath="$1"
  local filename="${filepath##*/}"
  local ext=""

  case "$filename" in
    *.*) ext=".${filename##*.}" ;;
    *) return 1 ;;
  esac

  ext="${ext,,}"

  while IFS= read -r entry; do
    [ -z "$entry" ] && continue
    local pattern="${entry%%=*}"
    local cmd="${entry#*=}"

    local pat_ext=""
    case "$pattern" in
      '*'*) pat_ext="${pattern#\*}" ;;
    esac

    if [ "$ext" = "$pat_ext" ]; then
      FOUND_FORMATTER="$cmd"
      return 0
    fi
  done <<< "$AF_FORMATTERS"

  return 1
}

while IFS= read -r filepath; do
  [ -z "$filepath" ] && continue

  # Find formatter for this file's extension (sets FOUND_FORMATTER, no subshell)
  find_formatter "$filepath" || continue
  formatter_cmd="$FOUND_FORMATTER"
  [ -n "$formatter_cmd" ] || continue

  # Validate command against allowlist
  validate_command "$formatter_cmd" || continue

  # Split command into array for multi-word support (QA-002)
  read -ra cmd_parts <<< "$formatter_cmd"

  # Check formatter binary is installed and resolve path (single command -v)
  resolved="$(command -v "${cmd_parts[0]}")" || continue
  cmd_parts[0]="$resolved"

  # Check file exists before formatting (BND-002)
  [ -f "$filepath" ] || continue

  # Add in-place flags for formatters that write to stdout by default (H-1)
  base_bin="${cmd_parts[0]##*/}"
  case "$base_bin" in
    prettier) cmd_parts+=("--write") ;;
    gofmt)    cmd_parts+=("-w") ;;
  esac

  # Run formatter with timeout, array-based execution (PRH-004, QA-002)
  if timeout 5 "${cmd_parts[@]}" "$filepath" >/dev/null 2>&1; then
    echo "Formatted ${filepath} with ${formatter_cmd}" >&2
  fi
done <<< "$FILES"

# Never fail (INV-003)
exit 0
