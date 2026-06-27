#!/usr/bin/env bash
# shellcheck disable=SC2254
# HOOK_TYPE: PreToolUse
# HOOK_MATCHER: Edit|Write|MultiEdit|NotebookEdit|CreateFile|Bash
# Correctless — PreToolUse sensitive file protection hook
# Blocks the agent from modifying sensitive files (.env, credentials, keys, etc.)
# Independent of workflow state — no overrides, no phase exceptions.
#
# Called by Claude Code as a PreToolUse hook. Receives tool info on stdin as JSON:
#   { "tool_name": "Edit", "tool_input": { "file_path": "...", ... } }
#
# Scope (sfg-edit-write-only, 2026-06): this hook guards the Edit/Write
# tool-path ONLY. It matches tool_input.file_path for
# Edit/Write/MultiEdit/NotebookEdit/CreateFile against the protected-pattern
# list. Bash commands are NEVER inspected and NEVER blocked — Bash-mediated
# writes (redirects, writer commands, interpreters, git) are ALL accepted
# non-goals (the prior Bash write-target extraction path was removed). See
# ABS-045 + AP-040 + PMB-020.
#
# Exit codes:
#   0 — allow the operation
#   2 — block the operation (message printed to stderr)
# SC2254 disabled: unquoted $pat in case is intentional — we need glob matching

set -euo pipefail

# Disable glob expansion — patterns like *.pem must not expand to filenames.
set -f

# Byte-oriented, locale-independent lowercasing / matching on the Edit/Write
# path. canonicalize_path (PAT-017) and the `${var,,}` lowercasing of file
# targets and patterns must produce locale-independent, reproducible block
# decisions across the agent's locale, so the hook pins LC_ALL=C at hook scope.
LC_ALL=C

# ============================================
# STEP 1: Check jq availability (EA-004)
# ============================================

command -v jq >/dev/null 2>&1 || { echo "BLOCKED [sensitive-file]: jq not found" >&2; exit 2; }

# ============================================
# STEP 2: Parse stdin JSON (single jq bulk call)
# ============================================

INPUT="$(cat)"
TOOL_NAME="" TOOL_INPUT_FILE="" TOOL_INPUT_EDITS=""
# tool_name MUST be a scalar string. A non-string (array/object/number/bool/null
# or absent) tool_name is unexpected input → jq errors → empty $_PARSED → the
# STEP-2 guard below exits 2 (fail-closed, INV-006 / PAT-001 clause 5). This also
# prevents @sh from rendering a multi-element array as multiple shell tokens,
# which would make `eval "$_PARSED"` run an arbitrary command (exit 127, not a
# fail-closed exit 2). file_path/edits are coerced to scalar strings for the same
# token-safety reason; a non-string target simply yields no protected match.
_PARSED="$(echo "$INPUT" | jq -r '
  if (.tool_name | type) != "string" then error("non-string tool_name")
  else
    @sh "TOOL_NAME=\(.tool_name)",
    @sh "TOOL_INPUT_FILE=\(.tool_input.file_path | if type == "string" then . else "" end)",
    @sh "TOOL_INPUT_EDITS=\([.tool_input.edits[]?.file_path | select(type == "string")] | join("\n"))"
  end
' 2>/dev/null)" || true
# Fail-closed: if jq produced no output (parse failure), block the operation (DA-003)
if [ -z "$_PARSED" ]; then
  echo "BLOCKED [fail-closed]: failed to parse tool input JSON" >&2
  exit 2
fi
eval "$_PARSED"

# ============================================
# STEP 3: Fast-path bail (INV-001, INV-010)
# ============================================

# Bash is never inspected — exit 0 immediately, BEFORE sourcing lib.sh or
# reading config (INV-001). Read/Grep/Glob and every other non-write tool also
# exit 0 here. Only the Edit/Write family proceeds to pattern matching.
case "$TOOL_NAME" in
  Edit|Write|MultiEdit|NotebookEdit|CreateFile) ;;
  Bash)
    exit 0
    ;;
  *)
    exit 0
    ;;
esac

# ============================================
# STEP 4: Source shared library (for canonicalize_path + config_file)
# ============================================
# The Edit/Write path needs canonicalize_path (PAT-017) for canonical-form
# matching and config_file (transitively repo_root, EA-001) for the config
# path. lib.sh is optional here — config_file has its own fallback — but the
# canonicalize_path v1 sentinel probe (STEP 4a) fails closed if the function is
# missing or version-mismatched.

_source_lib_sh() {
  local _LIB_DIR
  _LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" 2>/dev/null && pwd || true)"
  if [ -n "$_LIB_DIR" ] && [ -f "$_LIB_DIR/lib.sh" ]; then
    # shellcheck source=../scripts/lib.sh
    source "$_LIB_DIR/lib.sh"
  elif [ -f ".correctless/scripts/lib.sh" ]; then
    source ".correctless/scripts/lib.sh"
  else
    return 1
  fi
}

_source_lib_sh || true

# STEP 4a: canonicalize_path v1 sentinel probe (INV-005a) — catches partial
# upgrades where the new guard is paired with an old lib.sh missing the
# function or shipping a divergent implementation.

if ! declare -f canonicalize_path >/dev/null 2>&1 \
   || [ "$(canonicalize_path '__canonicalize_path_v1_probe__/foo' 2>/dev/null || true)" != "__canonicalize_path_v1_probe__/foo" ]; then
  echo "BLOCKED [sensitive-file]: canonicalize_path missing or version mismatch — re-run 'bash setup' to refresh installed scripts" >&2
  exit 2
fi

# ============================================
# STEP 5: Collect file targets to check
# ============================================

collect_targets() {
  case "$TOOL_NAME" in
    Edit|Write|CreateFile|NotebookEdit)
      if [ -n "$TOOL_INPUT_FILE" ]; then
        echo "$TOOL_INPUT_FILE"
      fi
      ;;
    MultiEdit)
      # Iterate all file paths from edits array
      if [ -n "$TOOL_INPUT_EDITS" ]; then
        echo "$TOOL_INPUT_EDITS"
      fi
      if [ -n "$TOOL_INPUT_FILE" ]; then
        echo "$TOOL_INPUT_FILE"
      fi
      ;;
  esac
}

FILE_TARGETS="$(collect_targets)"

# No targets -> nothing to check -> allow (BND-002)
if [ -z "$FILE_TARGETS" ]; then
  exit 0
fi

# ============================================
# STEP 6: Hardcoded default patterns (INV-004)
# ============================================

DEFAULTS=".env
.env.*
*.pem
*.key
*.p12
*.pfx
credentials.json
credentials.yml
service-account*.json
*.secret
*.secrets
secrets.yml
secrets.yaml
secrets.json
.secrets
id_rsa
id_rsa.*
id_ed25519
id_ed25519.*
*.keystore
*.jks
.correctless/preferences.md
.correctless/config/auto-policy.json
.correctless/artifacts/intent-*.md
.correctless/artifacts/workflow-state-*.json
.correctless/artifacts/decision-record-*.md
.correctless/artifacts/autonomous-decisions-*.jsonl
.correctless/meta/harness-fingerprint.json
.correctless/meta/model-baselines.json
.correctless/meta/prune-pattern-baseline.json
scripts/harness-fingerprint.sh
.correctless/scripts/harness-fingerprint.sh
harness-fingerprint.sh
scripts/audit-record.sh
.correctless/scripts/audit-record.sh
audit-record.sh
scripts/autonomous-decision-writer.sh
.correctless/scripts/autonomous-decision-writer.sh
autonomous-decision-writer.sh
scripts/prune-scan.sh
.correctless/scripts/prune-scan.sh
prune-scan.sh
scripts/external-review-run.sh
.correctless/scripts/external-review-run.sh
external-review-run.sh
scripts/config-update.sh
.correctless/scripts/config-update.sh
config-update.sh
.correctless/ARCHITECTURE_DEPRECATED.md
.correctless/antipatterns-archived.md
.correctless/CLAUDE_LEARNINGS_ARCHIVED.md
scripts/wf/transitions.sh
scripts/wf/utility.sh
scripts/wf/metadata.sh
.correctless/scripts/wf/transitions.sh
.correctless/scripts/wf/utility.sh
.correctless/scripts/wf/metadata.sh
scripts/lib.sh
.correctless/scripts/lib.sh
.correctless/config/workflow-config.json
scripts/override-scrutiny.sh
.correctless/scripts/override-scrutiny.sh
scripts/review-triage.sh
.correctless/scripts/review-triage.sh
scripts/supervisor-mandate.sh
.correctless/scripts/supervisor-mandate.sh
scripts/intent-hash.sh
.correctless/scripts/intent-hash.sh
.correctless/meta/intensity-calibration.json
.correctless/meta/pat001-measurement-due.json
.correctless/.sfg-lift-active
agents/fix-diff-reviewer.md
agents/supervisor.md
agents/decision-agent.md
agents/ctdd-red.md
agents/ctdd-green.md"

# ============================================
# STEP 7: Read custom patterns from config (INV-005)
# ============================================

CUSTOM_PATTERNS=""

# Resolve config file path via lib.sh (falls back to relative if unavailable)
CONFIG_FILE="$(config_file 2>/dev/null)" || CONFIG_FILE=".correctless/config/workflow-config.json"

if [ -f "$CONFIG_FILE" ]; then
  # Read custom_patterns as newline-separated list; on failure, CUSTOM_PATTERNS stays empty
  CUSTOM_PATTERNS="$(jq -r '.protected_files.custom_patterns // [] | if type == "array" then .[] else empty end' "$CONFIG_FILE" 2>/dev/null)" || CUSTOM_PATTERNS=""
fi

# Combine defaults + custom into a single newline-separated list, pre-lowercased
ALL_PATTERNS="$DEFAULTS"
if [ -n "$CUSTOM_PATTERNS" ]; then
  ALL_PATTERNS="$ALL_PATTERNS
$CUSTOM_PATTERNS"
fi
# Pre-lowercase all patterns once (avoids per-file lowercasing in the match loop)
ALL_PATTERNS="${ALL_PATTERNS,,}"

# Canonicalize every pattern once (INV-005, INV-008, PRH-004 — canonical forms
# on both sides). Glob bytes (`*.pem`, `secrets.*`) survive per INV-004.
_canonical_arr=()
while IFS= read -r pat; do
  [ -n "$pat" ] && { canonicalize_path "$pat"; _canonical_arr+=( "$_CANONICAL_RESULT" ); }
done <<< "$ALL_PATTERNS"
_IFS_save="${IFS-}"; IFS=$'\n'
CANONICAL_PATTERNS="${_canonical_arr[*]}"
IFS="$_IFS_save"

# ============================================
# STEP 8: Match each file target against patterns (INV-007, INV-008)
# ============================================

_check_file_against_patterns() {
  # Pre-condition: argument is already a canonical-form path (output of
  # canonicalize_path). Matched against CANONICAL_PATTERNS only. PRH-004.
  local filepath="$1"

  # Case-insensitive: lowercase the filepath (EA-002)
  local filepath_lower="${filepath,,}"
  local basename_lower="${filepath_lower##*/}"

  # Empty basename means no file to check
  if [ -z "$basename_lower" ]; then
    return 1
  fi

  while IFS= read -r pat; do
    [ -z "$pat" ] && continue
    case "$pat" in
      */*)
        # Full-path pattern: match against the full filepath
        # Require path separator boundary to avoid partial dir matches (QA-002)
        case "$filepath_lower" in
          $pat|*/$pat) echo "$pat"; return 0 ;;
        esac
        ;;
      *)
        # Basename pattern: match against basename only
        case "$basename_lower" in
          $pat) echo "$pat"; return 0 ;;
        esac
        ;;
    esac
  done <<< "$CANONICAL_PATTERNS"

  return 1
}

# ============================================
# STEP 9: Check each file target (INV-002, BND-004)
# ============================================

while IFS= read -r target; do
  [ -z "$target" ] && continue

  # Canonicalize the target before matching (INV-003, PRH-004).
  canonical_target="$(canonicalize_path "$target")"

  matched_pattern=""
  matched_pattern="$(_check_file_against_patterns "$canonical_target")" || true

  if [ -n "$matched_pattern" ]; then
    echo "BLOCKED [sensitive-file]: this Edit/Write tool target '$target' matches protected pattern '$matched_pattern'.
  SFG is a write-target guardrail — it catches accidental/naive Edit/Write writes to protected files. If this is a genuine, intended edit to a deliverable, use the sanctioned lift-and-restore procedure in .claude/rules/sfg-deliverable.md. Otherwise, make the write outside Claude Code." >&2
    exit 2
  fi
done <<< "$FILE_TARGETS"

# ============================================
# STEP 10: No match — allow (INV-006)
# ============================================

exit 0
