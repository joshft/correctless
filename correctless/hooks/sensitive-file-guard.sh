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
# Exit codes:
#   0 — allow the operation
#   2 — block the operation (message printed to stderr)
# SC2254 disabled: unquoted $pat in case is intentional — we need glob matching

set -euo pipefail

# Disable glob expansion — patterns like *.pem must not expand to filenames
set -f

# Byte-oriented, locale-independent tokenization / lowercasing / matching
# (INV-019). Extraction runs BEFORE canonicalize_path's internal LC_ALL=C, so
# the hook-scope setting is what makes block decisions reproducible across the
# agent's locale.
LC_ALL=C

# ============================================
# STEP 1: Check jq availability (EA-004)
# ============================================

command -v jq >/dev/null 2>&1 || { echo "BLOCKED [sensitive-file]: jq not found" >&2; exit 2; }

# ============================================
# STEP 2: Parse stdin JSON (single jq bulk call)
# ============================================

INPUT="$(cat)"
TOOL_NAME="" TOOL_INPUT_FILE="" TOOL_INPUT_COMMAND="" TOOL_INPUT_EDITS=""
_PARSED="$(echo "$INPUT" | jq -r '
  @sh "TOOL_NAME=\(.tool_name // "")",
  @sh "TOOL_INPUT_FILE=\(.tool_input.file_path // "")",
  @sh "TOOL_INPUT_COMMAND=\(.tool_input.command // "")",
  @sh "TOOL_INPUT_EDITS=\([.tool_input.edits[]?.file_path // empty] | join("\n"))"
' 2>/dev/null)" || true
# Fail-closed: if jq produced no output (parse failure), block the operation (DA-003)
if [ -z "$_PARSED" ]; then
  echo "BLOCKED [fail-closed]: failed to parse tool input JSON" >&2
  exit 2
fi
eval "$_PARSED"

# ============================================
# STEP 3: Fast-path bail — only write tools (INV-010)
# ============================================

# Exit 0 immediately for Read, Grep, Glob, etc. — BEFORE loading config
case "$TOOL_NAME" in
  Edit|Write|MultiEdit|NotebookEdit|CreateFile) ;;
  Bash)
    if [ -z "$TOOL_INPUT_COMMAND" ]; then exit 0; fi
    ;;
  *)
    exit 0
    ;;
esac

# ============================================
# STEP 4: Source shared library and detect write patterns (INV-002, ABS-001)
# ============================================
# QA-002: lib.sh is required for Bash (fail-closed: write-pattern detection needed).
# For non-Bash tools (Edit/Write/MultiEdit), lib.sh is optional — config_file
# has its own fallback, and these tools don't need write-pattern detection.

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

# For Bash, skip non-write commands (INV-003)
if [ "$TOOL_NAME" = "Bash" ]; then
  COMMAND="$TOOL_INPUT_COMMAND"
  _source_lib_sh || { echo "BLOCKED: lib.sh not found — required for write detection" >&2; exit 2; }
  if ! _has_write_pattern "$COMMAND"; then
    exit 0
  fi
else
  # Non-Bash write tools: source lib.sh for config_file() but don't block if missing
  _source_lib_sh || true
fi

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
    Bash)
      _extract_bash_targets
      ;;
  esac
}

# Strip shell-quote bytes iteratively from both ends of a candidate
# destination token. Destination-driven extraction (INV-007) only ever calls
# this on an already-isolated redirect/writer destination, never on every
# token — so the over-extraction wrapper-peeling rationale of the old version
# no longer applies; this is a light dequote of surrounding quote bytes.
_strip_quotes() {
  local s="$1" prev
  while :; do
    prev="$s"
    s="${s#[\"\']}"
    s="${s%[\"\']}"
    [ "$s" = "$prev" ] && break
  done
  printf '%s' "$s"
}

# Emit a candidate destination unless it is a sink device (INV-006) or an
# unresolvable/dynamic value (INV-007: e.g. `${f}`, `$out`, empty). Anything
# that survives is a genuine write target. Reads/invocations/incidental tokens
# never reach here — only the redirect branch (INV-002) and writer-command
# branch (INV-003) call this.
_emit_dest() {
  local dest
  dest="$(_strip_quotes "$1")"
  [ -n "$dest" ] || return 0
  # Dynamic / unresolvable destination -> fail open (INV-007).
  case "$dest" in
    *'$'*) return 0 ;;
  esac
  # Sink devices are never write targets (INV-006).
  case "$dest" in
    /dev/null|/dev/stdout|/dev/stderr|/dev/fd/*) return 0 ;;
  esac
  printf '%s\n' "$dest"
}

# Excise process-substitution spans `>(…)` / `<(…)` from a command string
# (INV-005 / CX-006), balanced-paren aware, so the `(`/`)` bytes never reach the
# tokenizer to shatter an inner path and the operand stays opaque. Result on
# stdout. Quotes are deliberately PRESERVED here — a quoted redirect/writer
# DESTINATION (`echo > ".env"`, `cp ".env" backup`) must still resolve;
# interpreter eval-operand opacity (INV-005) is applied separately at the
# segment level by _mask_opaque_operands (so `-c "…"` payloads do not leak
# redirects while `> ".env"` destinations do).
_excise_process_subs() {
  local s="$1" out="" n="${#1}" i=0 ch depth
  while [ "$i" -lt "$n" ]; do
    ch="${s:$i:1}"
    if { [ "$ch" = ">" ] || [ "$ch" = "<" ]; } && [ "${s:$((i + 1)):1}" = "(" ]; then
      depth=1
      i=$((i + 2))
      while [ "$i" -lt "$n" ] && [ "$depth" -gt 0 ]; do
        ch="${s:$i:1}"
        if [ "$ch" = "(" ]; then depth=$((depth + 1)); fi
        if [ "$ch" = ")" ]; then depth=$((depth - 1)); fi
        i=$((i + 1))
      done
      out="$out "
      continue
    fi
    out="$out$ch"
    i=$((i + 1))
  done
  printf '%s' "$out"
}

# Mask the OPAQUE operand of an interpreter+eval chain or here-string within a
# single segment string `$1` (INV-005). Returns (on stdout) the segment with:
#   - the word following a here-string `<<<` replaced by a placeholder, and
#   - when the segment's command is an interpreter (bash/sh/python/node/…) and
#     carries an eval flag (-c/-e/-pe/-ne/--eval/-d/…), the eval flag's operand
#     (a full quoted span, or one bare word) replaced by a placeholder.
# Because word-splitting shatters a quoted operand (`"echo x > .env"`) across
# several tokens, the masking is quote-span-aware: it consumes from the start of
# the operand up to its matching closing quote. A redirect/writer OUTSIDE the
# opaque operand survives (e.g. `cat <<< x > .env` keeps the trailing `> .env`).
# `perl -i` is NOT opaque — it is a writer (INV-003) routed to the writer branch.
_mask_opaque_operands() {
  local seg="$1" base out="" mask_next=0 has_interp=0
  local n="${#seg}" i=0 ch tok q
  base="${tokens[0]##*/}"
  case "$base" in
    bash|sh|zsh|dash|perl|python|python3|ruby|php|lua|tclsh|Rscript|nim|node|base64) has_interp=1 ;;
  esac
  while [ "$i" -lt "$n" ]; do
    ch="${seg:$i:1}"
    # Skip leading whitespace verbatim.
    if [ "$ch" = " " ] || [ "$ch" = $'\t' ]; then
      out="$out$ch"; i=$((i + 1)); continue
    fi
    # Read the next whitespace-delimited token, honoring quote spans so a
    # quoted operand is read as ONE unit.
    tok=""
    while [ "$i" -lt "$n" ]; do
      ch="${seg:$i:1}"
      case "$ch" in
        ' '|$'\t') break ;;
        "'"|'"')
          q="$ch"; tok="$tok$ch"; i=$((i + 1))
          while [ "$i" -lt "$n" ] && [ "${seg:$i:1}" != "$q" ]; do
            tok="$tok${seg:$i:1}"; i=$((i + 1))
          done
          if [ "$i" -lt "$n" ]; then tok="$tok${seg:$i:1}"; i=$((i + 1)); fi
          ;;
        *) tok="$tok$ch"; i=$((i + 1)) ;;
      esac
    done
    if [ "$mask_next" -eq 1 ]; then
      out="$out X"; mask_next=0; continue
    fi
    case "$tok" in
      '<<<')
        out="$out$tok"; mask_next=1; continue ;;
      -c|-e|-pe|-ne|-r|-E|--eval|-d|--decode|--execute)
        out="$out$tok"
        [ "$has_interp" -eq 1 ] && mask_next=1
        continue ;;
    esac
    out="$out$tok"
  done
  printf '%s' "$out"
}

# Extract genuine write destinations from a Bash command — destination-driven
# (PRH-001): a token is emitted ONLY by the redirect branch (INV-002) or the
# writer-command branch (INV-003). No unconditional token-emit branch exists.
# Reads, invocations, flags, sources, and interpreter/eval operands resolve to
# the empty set -> allowed (INV-001, INV-005, INV-007). Segmentation (INV-020)
# bounds each writer's positional logic to its own command segment.
_extract_bash_targets() {
  # Excise process-sub spans up front (INV-005/CX-006), then mark segment
  # boundaries. Bare `;`, `&&`, `||`, bare background `&`, and pipe `|`
  # separate segments; an `&` that is part of `&>`/`>&` is NOT a separator
  # (CX-007). We translate every unquoted separator to a newline so each line
  # is one segment, while leaving redirect operators intact.
  local cmd seg op rest dest j masked
  local -a tokens
  cmd="$(_excise_process_subs "$COMMAND")"

  # Insert segment-boundary newlines. Walk char-by-char so redirect operators
  # (`&>`, `&>|`, `>&`, `>|`) are preserved while bare `&`/`&&`/`||`/`|`/`;`
  # become boundaries (CX-007). `cprev` is the previous source byte so we can
  # tell a `|` that belongs to a `>|`/`&>|` redirect from a pipe separator.
  local segmented="" n="${#cmd}" k=0 c c2 cprev
  while [ "$k" -lt "$n" ]; do
    c="${cmd:$k:1}"
    c2="${cmd:$((k + 1)):1}"
    cprev=""
    [ "$k" -gt 0 ] && cprev="${cmd:$((k - 1)):1}"
    case "$c" in
      ';')
        segmented="$segmented"$'\n'; k=$((k + 1)); continue ;;
      '|')
        # `>|` or `&>|` redirect tail -> keep the `|` as part of the operator.
        if [ "$cprev" = ">" ]; then
          segmented="$segmented$c"; k=$((k + 1)); continue
        fi
        if [ "$c2" = "|" ]; then
          segmented="$segmented"$'\n'; k=$((k + 2)); continue
        fi
        segmented="$segmented"$'\n'; k=$((k + 1)); continue ;;
      '&')
        # `&>` / `&>|` redirect, or `>&` (prev was `>`) -> keep as-is.
        if [ "$c2" = ">" ] || [ "$cprev" = ">" ]; then
          segmented="$segmented$c"; k=$((k + 1)); continue
        fi
        # `&&` or bare background `&` -> boundary.
        if [ "$c2" = "&" ]; then
          segmented="$segmented"$'\n'; k=$((k + 2)); continue
        fi
        segmented="$segmented"$'\n'; k=$((k + 1)); continue ;;
      *)
        segmented="$segmented$c"; k=$((k + 1)); continue ;;
    esac
  done

  # shellcheck disable=SC2141
  local IFS=$' \t\n'
  # Process each segment independently (INV-020). Redirect detection is
  # token-local; writer-command positional logic is bounded to the segment.
  local rre='(&>\||&>|>&|>\||>>|[0-9]*>)([^[:space:]<>|&]+)'
  while IFS= read -r seg; do
    [ -n "$seg" ] || continue

    # Tokenize the raw (unmasked) segment for writer-command positional logic
    # (INV-003) — perl -i / sed -i operands must be read from the real tokens.
    # shellcheck disable=SC2206
    tokens=($seg)
    [ "${#tokens[@]}" -gt 0 ] || continue

    # --- Writer-command destinations (INV-003), bounded to this segment ---
    _extract_writer_dests

    # --- Redirect destinations (INV-002) — computed on the OPAQUE-MASKED
    # segment so a redirect inside an interpreter eval operand or here-string
    # operand (INV-005) does not leak, while a redirect OUTSIDE it survives.
    masked="$(_mask_opaque_operands "$seg")"

    # Glued/inline redirects: `cmd>file`, `cmd2>file`, `cmd&>file`, `cmd>|file`.
    rest="$masked"
    while [[ "$rest" =~ $rre ]]; do
      _emit_dest "${BASH_REMATCH[2]}"
      rest="${rest#*"${BASH_REMATCH[0]}"}"
    done

    # Whitespace-separated redirect operators: next token is the destination.
    # shellcheck disable=SC2206
    local -a mtokens=($masked)
    j=0
    while [ "$j" -lt "${#mtokens[@]}" ]; do
      op="${mtokens[$j]}"
      case "$op" in
        '>'|'>>'|'>|'|'1>'|'2>'|'&>'|'&>|'|'>&'|'1>>'|'2>>')
          if [ "$((j + 1))" -lt "${#mtokens[@]}" ]; then
            _emit_dest "${mtokens[$((j + 1))]}"
          fi
          ;;
      esac
      j=$((j + 1))
    done
  done <<< "$segmented"
}

# Detect writer-command destinations within a single already-tokenized segment.
# Uses the segment's token array `tokens` set by the caller. Emits destinations
# via _emit_dest. Interpreter/eval chains (INV-005) and git working-tree
# commands (INV-004) are deliberately NOT writers here.
_extract_writer_dests() {
  local cmd0="${tokens[0]}" base last_nonflag="" t p of_val cmd_idx=0
  base="${cmd0##*/}"

  # `/usr/bin/env [VAR=val…] CMD …` — resolve the real command after env so
  # `env perl -pi … .env` is treated as a perl writer. The argument-index base
  # (cmd_idx) shifts so positional logic starts after the resolved command.
  if [ "$base" = "env" ]; then
    for ((p = 1; p < ${#tokens[@]}; p++)); do
      t="${tokens[$p]}"
      case "$t" in
        -*|*=*) ;;             # env flags / VAR=val assignments — skip
        *) cmd_idx="$p"; base="${t##*/}"; break ;;
      esac
    done
    [ "$cmd_idx" -eq 0 ] && return 0
  fi

  local start=$((cmd_idx + 1))
  case "$base" in
    tee)
      # Every non-`-`-leading arg after `tee` is a destination (INV-003).
      for ((p = start; p < ${#tokens[@]}; p++)); do
        t="${tokens[$p]}"
        case "$t" in
          -*) ;;
          *) _emit_dest "$t" ;;
        esac
      done
      ;;
    cp|mv|install|ln)
      # Final non-flag positional arg within the segment is the destination.
      # No flag-relocation form (-t/--target-directory/-d) — those fail open.
      case " ${tokens[*]} " in
        *' -t '*|*' --target-directory'*|*' -d '*) return 0 ;;
      esac
      for ((p = start; p < ${#tokens[@]}; p++)); do
        t="${tokens[$p]}"
        case "$t" in
          -*) ;;
          *) last_nonflag="$t" ;;
        esac
      done
      [ -n "$last_nonflag" ] && _emit_dest "$last_nonflag"
      ;;
    sed)
      # sed -i / sed -i.bak: the file operand(s) after the script. The frozen
      # prefilter only fires on immediate `-i`, so only that form reaches here.
      # Emit every trailing non-flag arg that is not the script expression.
      _extract_inplace_operand "$start"
      ;;
    perl)
      # perl -i / perl -i -pe / perl -pi: in-place writer (RS-001). Operand is
      # the trailing file arg. perl -e/-pe/-ne WITHOUT -i never reaches here as
      # a writer (opaque, INV-005) because the prefilter requires `-i`.
      _extract_inplace_operand "$start"
      ;;
    dd)
      # dd of=… — position-independent within this segment; if= is a read.
      for ((p = start; p < ${#tokens[@]}; p++)); do
        t="${tokens[$p]}"
        case "$t" in
          of=*) of_val="${t#of=}"; _emit_dest "$of_val" ;;
        esac
      done
      ;;
    truncate)
      # truncate [-s N] FILE — emit every trailing non-flag, non-size operand.
      for ((p = start; p < ${#tokens[@]}; p++)); do
        t="${tokens[$p]}"
        case "$t" in
          -s) p=$((p + 1)) ;;   # skip the size value
          -s*) ;;               # -s0 glued: skip
          --size=*) ;;
          -*) ;;
          *) _emit_dest "$t" ;;
        esac
      done
      ;;
  esac
}

# Shared in-place-edit operand extractor for `sed -i` / `perl -i`. The in-place
# flag is required (prefilter, CX-013). The file operand is the trailing
# non-flag, non-script argument. For sed/perl the script may be a bare arg
# (e.g. `s/a/b/`) — we treat the LAST non-flag arg as the file destination, and
# emit every trailing non-flag run except the first non-flag (the script) when a
# single script+file pair is present. To stay simple and correct for the
# in-scope fixtures, emit every non-flag arg AFTER the first non-flag arg.
_extract_inplace_operand() {
  local start="${1:-1}" p t script_via_flag=0 script_consumed=0
  for ((p = start; p < ${#tokens[@]}; p++)); do
    t="${tokens[$p]}"
    case "$t" in
      -e|-pe|-ne|-pi|--expression|-f)
        # script-bearing flag: its value is the next token (a separate script
        # source, so a bare positional is NOT the script -> it is the file).
        script_via_flag=1
        case "${tokens[$((p + 1))]:-}" in
          -*|'') ;;
          *) p=$((p + 1)) ;;
        esac
        ;;
      -*) ;;   # other flags (e.g. -i, -i.bak, -0777, -w)
      *)
        if [ "$script_via_flag" -eq 0 ] && [ "$script_consumed" -eq 0 ]; then
          # No script flag seen yet: the first bare positional is the script.
          script_consumed=1
        else
          _emit_dest "$t"   # file operand
        fi
        ;;
    esac
  done
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
# STEP 9: Check each file target (INV-001, INV-002, BND-004, INV-005)
# ============================================

while IFS= read -r target; do
  [ -z "$target" ] && continue

  # Canonicalize the target before matching (INV-005, PRH-004).
  canonical_target="$(canonicalize_path "$target")"

  matched_pattern=""
  matched_pattern="$(_check_file_against_patterns "$canonical_target")" || true

  if [ -n "$matched_pattern" ]; then
    echo "BLOCKED [sensitive-file]: this command writes to '$target', which matches protected pattern '$matched_pattern'.
  SFG is a write-target guardrail — it catches accidental/naive writes to protected files. If this is a genuine, intended edit to a deliverable, use the sanctioned lift-and-restore procedure in .claude/rules/sfg-deliverable.md. Otherwise, make the write outside Claude Code." >&2
    exit 2
  fi
done <<< "$FILE_TARGETS"

# ============================================
# STEP 10: No match — allow (INV-006)
# ============================================

exit 0
