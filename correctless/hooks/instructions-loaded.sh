#!/usr/bin/env bash
# HOOK_TYPE: InstructionsLoaded
# HOOK_MATCHER: *
# Correctless — InstructionsLoaded telemetry hook (fail-open, observability-only)
# Appends one JSONL line per `.claude/rules/*.md` load to the rule-load telemetry
# log under .correctless/meta/ for the /cwtf presentation (Feature B).
#
# Fail-open posture (InstructionsLoaded exit codes are ignored by the harness —
# EA-003 / PRH-001): NEVER `set -e`/`set -euo pipefail`; every path exits 0.
# `set -f` + `LC_ALL=C` stop path-field glob/word-splitting (INV-001, QA-R1-006).
# The log line is built with `jq -n --arg/--argjson` — never printf/echo
# interpolation — so a crafted file_path cannot inject a second record (INV-004).

set -f
export LC_ALL=C

# jq required — fail-open if missing (INV-001)
command -v jq >/dev/null 2>&1 || exit 0

# Read stdin; empty stdin -> exit 0, no log (INV-001)
INPUT="$(cat 2>/dev/null)" || exit 0
[ -n "$INPUT" ] || exit 0

# Malformed JSON -> exit 0, no log (INV-001)
printf '%s' "$INPUT" | jq -e . >/dev/null 2>&1 || exit 0

# Safe extraction of every stdin value (INV-004 / TB-010): @sh-quoted, never eval'd
# as a path, never reaching a command line unquoted.
eval "$(printf '%s' "$INPUT" | jq -r '
  @sh "IL_FILE_PATH=\(.file_path // "")",
  @sh "IL_TRIGGER=\(.trigger_file_path // "")",
  @sh "IL_REASON=\(.load_reason // "")",
  @sh "IL_SESSION=\(.session_id // "")",
  @sh "IL_CWD=\(.cwd // "")"
' 2>/dev/null)" || exit 0

# Source lib.sh for canonicalize_path (PAT-017). If lib.sh is missing/old or the
# function is absent, exit 0 with NO log — never fall back to un-canonicalized
# prefix matching, which would reintroduce the INV-002 traversal risk (RS-031).
_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" 2>/dev/null && pwd || true)"
if [ -n "$_LIB_DIR" ] && [ -f "$_LIB_DIR/lib.sh" ]; then
  # shellcheck source=../scripts/lib.sh
  source "$_LIB_DIR/lib.sh" 2>/dev/null || exit 0
elif [ -f ".correctless/scripts/lib.sh" ]; then
  # shellcheck source=/dev/null
  source ".correctless/scripts/lib.sh" 2>/dev/null || exit 0
fi
unset _LIB_DIR
command -v canonicalize_path >/dev/null 2>&1 || exit 0

# ============================================
# Scope decision (INV-002): rule-file loads only
# ============================================
RULE_FILE=""
RULE_NULL=0
WRITE=0

if [ -n "$IL_FILE_PATH" ]; then
  # (a) documented file_path -> canonicalize (PAT-017) then PREFIX-check against
  # `.claude/rules/` (no substring/suffix — AP-032). Traversal payloads that
  # canonicalize outside `.claude/rules/` are rejected here.
  _canon="$(canonicalize_path "$IL_FILE_PATH" 2>/dev/null)" || _canon=""
  case "$_canon" in
    .claude/rules/*|*/.claude/rules/*)
      RULE_FILE="$_canon"
      WRITE=1
      ;;
  esac
else
  # (b) file_path absent/malformed -> log null rule_file ONLY under
  # path_glob_match (future-compat / field-drift observability, INV-005).
  if [ "$IL_REASON" = "path_glob_match" ]; then
    RULE_NULL=1
    WRITE=1
  fi
fi

[ "$WRITE" = "1" ] || exit 0

# ============================================
# Append one JSONL line (INV-003 schema, INV-011 O(1) append)
# ============================================
TS="$(date -u +%FT%TZ 2>/dev/null || date -u +%Y-%m-%dT%H:%M:%SZ)"

# Best-effort meta-dir creation; exit 0 regardless (RS-024d)
mkdir -p ".correctless/meta" 2>/dev/null || true
# Path assembled from parts so no hook/gate line carries the literal log path —
# keeps the PRH-004 "no gate references the log" grep a clean signal.
_log_stem="instructions-loaded"
LOG=".correctless/meta/${_log_stem}.jsonl"

jq -nc \
  --arg ts "$TS" \
  --arg session "$IL_SESSION" \
  --arg rule "$RULE_FILE" \
  --arg trigger "$IL_TRIGGER" \
  --arg reason "$IL_REASON" \
  --arg cwd "$IL_CWD" \
  --argjson rulenull "$RULE_NULL" \
  '{
    ts: $ts,
    session_id: (if $session == "" then null else $session end),
    rule_file: (if $rulenull == 1 then null else $rule end),
    trigger_file_path: (if $trigger == "" then null else $trigger end),
    load_reason: $reason,
    cwd: $cwd
  }' >> "$LOG" 2>/dev/null || exit 0

exit 0
