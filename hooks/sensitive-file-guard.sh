#!/usr/bin/env bash
# shellcheck disable=SC2254
# HOOK_TYPE: PreToolUse
# HOOK_MATCHER: Edit|Write|MultiEdit|NotebookEdit|CreateFile|Bash
# Rule: .claude/rules/hooks-pretooluse.md (PAT-001 — fail-closed posture)
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
  local s="$1" n="${#1}" i=0 ch depth run
  # O(n) accumulation: append chunks to an ARRAY and join ONCE (PMB-019). The old
  # `out="$out$run"` grew a string per iteration — O(n^2) in bash.
  local -a out_arr=()
  # Fast-path (O(n)): a process substitution requires a `(` byte immediately
  # after a `>`/`<`. If the command contains NO `(` at all, there is nothing to
  # excise — return the input unchanged without the per-char loop. This handles
  # the common large case (long args / base64 blobs with no parens) in O(n).
  case "$s" in
    *'('*) ;;            # may contain a process-sub — fall through to slow path
    *) printf '%s' "$s"; return ;;
  esac
  while [ "$i" -lt "$n" ]; do
    # Bulk-copy a maximal run of bytes that are neither `>`, `<`, nor `(`. This
    # is the O(n) construction technique: advance over non-trigger bytes with a
    # single parameter-expansion slice instead of one byte at a time. Only drop
    # to byte granularity at a redirect/process-sub boundary.
    run="${s:$i}"
    run="${run%%[\<\>(]*}"
    if [ -n "$run" ]; then
      out_arr+=("$run")
      i=$((i + ${#run}))
      [ "$i" -lt "$n" ] || break
    fi
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
      out_arr+=(" ")
      continue
    fi
    out_arr+=("$ch")
    i=$((i + 1))
  done
  local IFS=''
  printf '%s' "${out_arr[*]}"
}

# Neutralize shell-operator / separator / comment bytes that are NOT real shell
# syntax because they sit INSIDE a quoted span or after a word-boundary `#`
# comment (QA-001/QA-002, INV-001/INV-007/INV-020). Length is PRESERVED byte for
# byte — only the offending bytes (`> < | & ; #`) are rewritten to a benign
# filler (`_`); quote characters and every other byte are kept verbatim. This is
# deliberately scoped to OPERATOR/SEPARATOR *detection*, not destination reading:
# a quoted redirect/writer DESTINATION (`echo x > ".env"`, `tee ".env"`) keeps
# its bytes (the inner content has no operators), so downstream destination
# extraction still resolves it and `_strip_quotes` removes the surrounding
# quotes at emit time. Only an operator byte that lives *inside* a quoted
# argument (`echo "a > .env"`) or a comment (`ls foo # > .env`) is masked, so it
# can never be mistaken for real shell syntax.
#
# Quote model (byte-oriented, INV-019):
#   - A single-quoted span runs from `'` to the next `'` verbatim (no escapes).
#   - A double-quoted span runs from `"` to the next unescaped `"`; inside it a
#     backslash escapes the following byte (so `\"` does not close the span).
#   - Outside any quote, a `#` that starts a word (preceded by start-of-string or
#     whitespace) begins a comment that runs to end of string. `a#b` is literal.
_mask_quoted_operators() {
  local s="$1" n="${#1}" i=0 ch q prev="" run
  # O(n) accumulation: append every emitted chunk to an ARRAY and join ONCE at
  # the end (PMB-019 / technique 2). The previous `out="$out$chunk"` grew a
  # string in the loop, which is O(n^2) in bash — each append re-copies the whole
  # accumulated buffer — and HUNG on large commands with many small spans
  # (PERF regression). Array append is amortized O(1); the single join is O(n).
  local -a out_arr=()
  # Fast-path (O(n)): this masker only rewrites bytes that live inside a quoted
  # span ('|") or a word-boundary `#` comment, with a backslash (\) able to open
  # an escape. If the command contains NONE of those trigger bytes, there is
  # nothing to mask — return the input UNCHANGED without the per-char loop. A
  # command with no quotes/comments/backslashes has no quoted/commented operator
  # to neutralize, so the masked output is byte-identical to the input. This
  # handles the common large case (long args / base64 blobs) in O(n).
  case "$s" in
    *[\'\"\#\\]*) ;;     # has a trigger byte — fall through to slow path
    *) printf '%s' "$s"; return ;;
  esac
  while [ "$i" -lt "$n" ]; do
    # Bulk-copy a maximal run of bytes that are NOT triggers (`'` `"` `\` `#`).
    # These pass through the default `*)` arm verbatim; copying the run in one
    # parameter-expansion slice (instead of one byte per iteration) makes the
    # slow path O(n) over such runs. `prev` is updated to the run's last byte so
    # the word-boundary `#` logic that follows stays correct.
    run="${s:$i}"
    run="${run%%[\'\"\#\\]*}"
    if [ -n "$run" ]; then
      out_arr+=("$run")
      i=$((i + ${#run}))
      prev="${run: -1}"
      [ "$i" -lt "$n" ] || break
    fi
    ch="${s:$i:1}"
    case "$ch" in
      "'"|'"')
        # Enter a quoted span: copy the opening quote, then mask operator bytes
        # inside it until the matching close quote.
        q="$ch"
        out_arr+=("$ch"); i=$((i + 1))
        while [ "$i" -lt "$n" ]; do
          # Bulk-copy a maximal run of span-interior bytes that need neither
          # masking nor escape handling: not the close quote `q`, not an
          # operator byte (`> < | & ; #`), and — inside double quotes — not a
          # backslash. One parameter-expansion slice per run keeps the inner
          # loop O(n) even for a span made of thousands of such bytes.
          local _span
          if [ "$q" = '"' ]; then
            _span="${s:$i}"
            _span="${_span%%[\"\\\>\<\|\&\;\#]*}"
          else
            _span="${s:$i}"
            _span="${_span%%[\'\>\<\|\&\;\#]*}"
          fi
          if [ -n "$_span" ]; then
            out_arr+=("$_span"); i=$((i + ${#_span}))
            [ "$i" -lt "$n" ] || break
          fi
          ch="${s:$i:1}"
          if [ "$q" = '"' ] && [ "$ch" = '\' ] && [ "$((i + 1))" -lt "$n" ]; then
            # Backslash escape inside double quotes: copy both bytes verbatim,
            # masking the escaped byte if it is an operator.
            out_arr+=("$ch")
            local nb="${s:$((i + 1)):1}"
            case "$nb" in
              '>'|'<'|'|'|'&'|';'|'#') out_arr+=("_") ;;
              *) out_arr+=("$nb") ;;
            esac
            i=$((i + 2)); continue
          fi
          if [ "$ch" = "$q" ]; then
            out_arr+=("$ch"); i=$((i + 1)); break
          fi
          case "$ch" in
            '>'|'<'|'|'|'&'|';'|'#') out_arr+=("_") ;;
            *) out_arr+=("$ch") ;;
          esac
          i=$((i + 1))
        done
        prev="$ch"
        continue
        ;;
      '\')
        # Backslash OUTSIDE any quote: in real bash it escapes the FOLLOWING
        # byte to a literal, so a `\"`/`\'` here does NOT open a quoted span and
        # any redirect/separator that follows is LIVE syntax (QA-003 escape-
        # context parity; AP-022 guard-breakage otherwise). Copy the backslash
        # and the next byte verbatim, masking the next byte only if it is itself
        # an operator (it is a literal, not real syntax). Advance by 2 and set
        # `prev` to the ESCAPED byte so word-boundary `#` logic stays correct.
        if [ "$((i + 1))" -lt "$n" ]; then
          out_arr+=("$ch")
          local eb="${s:$((i + 1)):1}"
          case "$eb" in
            '>'|'<'|'|'|'&'|';'|'#') out_arr+=("_"); prev="_" ;;
            *) out_arr+=("$eb"); prev="$eb" ;;
          esac
          i=$((i + 2)); continue
        fi
        # Trailing lone backslash at end of string: copy verbatim.
        out_arr+=("$ch"); prev="$ch"; i=$((i + 1)); continue
        ;;
      '#')
        # Comment only at a word boundary (start-of-string or after whitespace).
        if [ -z "$prev" ] || [ "$prev" = " " ] || [ "$prev" = $'\t' ] || [ "$prev" = $'\n' ]; then
          # Mask from here to end of string — neutralizes operators/separators in
          # the comment while preserving length. Build the filler run in one slice
          # (length of the remaining tail) rather than byte by byte (O(n)).
          local _tail="${s:$i}" _fill
          printf -v _fill '%*s' "${#_tail}" ''
          out_arr+=("${_fill// /_}")
          i="$n"
          prev="_"
          continue
        fi
        out_arr+=("$ch"); prev="$ch"; i=$((i + 1)); continue
        ;;
      *)
        out_arr+=("$ch"); prev="$ch"; i=$((i + 1)); continue
        ;;
    esac
  done
  local IFS=''
  printf '%s' "${out_arr[*]}"
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
  local seg="$1" base mask_next=0 has_interp=0
  local n="${#seg}" i=0 ch tok q
  # O(n) accumulation: append chunks to an ARRAY, join ONCE at the end. The old
  # `out="$out$tok"` grew a string per token — O(n^2) in bash, which HUNG on a
  # segment with many small tokens. Array append is amortized O(1) (PMB-019).
  local -a out_arr=()
  base="${tokens[0]##*/}"
  case "$base" in
    bash|sh|zsh|dash|perl|python|python3|ruby|php|lua|tclsh|Rscript|nim|node|base64) has_interp=1 ;;
  esac
  local wsrun tailrun qrun
  # Fast-path: nothing to mask unless the command is an interpreter eval chain
  # (has_interp) OR carries a here-string `<<<`. A plain non-interpreter segment
  # with no `<<<` is returned UNCHANGED in O(n) — no token walk needed. This is
  # the common large case (`echo BIGBLOB > dest`).
  if [ "$has_interp" -eq 0 ]; then
    case "$seg" in
      *'<<<'*) ;;        # here-string present — fall through to the masker
      *) printf '%s' "$seg"; return ;;
    esac
  fi
  while [ "$i" -lt "$n" ]; do
    ch="${seg:$i:1}"
    # Skip leading whitespace verbatim. Bulk-copy the maximal whitespace run in
    # one slice (O(n) construction) instead of one byte at a time.
    if [ "$ch" = " " ] || [ "$ch" = $'\t' ]; then
      wsrun="${seg:$i}"
      wsrun="${wsrun%%[! $'\t']*}"
      out_arr+=("$wsrun"); i=$((i + ${#wsrun})); continue
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
          # Bulk-copy the quote-span interior (everything up to the closing
          # quote) in one slice rather than byte by byte.
          qrun="${seg:$i}"
          qrun="${qrun%%"$q"*}"
          # If the closing quote is absent, ${qrun%%…} leaves the rest verbatim,
          # which is the same span the per-char loop would have copied to EOS.
          tok="$tok$qrun"; i=$((i + ${#qrun}))
          if [ "$i" -lt "$n" ]; then tok="$tok${seg:$i:1}"; i=$((i + 1)); fi
          ;;
        *)
          # Bulk-copy a maximal run of bytes that are neither whitespace nor a
          # quote — these terminate the run and are handled by the arms above.
          tailrun="${seg:$i}"
          tailrun="${tailrun%%[ $'\t'\'\"]*}"
          tok="$tok$tailrun"; i=$((i + ${#tailrun}))
          ;;
      esac
    done
    if [ "$mask_next" -eq 1 ]; then
      out_arr+=(" X"); mask_next=0; continue
    fi
    case "$tok" in
      '<<<')
        out_arr+=("$tok"); mask_next=1; continue ;;
      -c|-e|-pe|-ne|-r|-E|--eval|-d|--decode|--execute)
        out_arr+=("$tok")
        [ "$has_interp" -eq 1 ] && mask_next=1
        continue ;;
    esac
    out_arr+=("$tok")
  done
  local IFS=''
  printf '%s' "${out_arr[*]}"
}

# Recognize a LIVE redirect operator that terminates a whitespace-delimited token
# (QA-006 / AP-022). The round-2 masker (`_mask_quoted_operators`) neutralizes
# ESCAPED operator bytes to `_`, so any redirect-operator byte (`>`/`<`/`&`/`|`)
# that survives RAW in a masked token is genuinely live shell syntax — even when a
# literal/masked prefix is glued to it inside one token (`\\>`, `\1>`, `\_>` from
# `\&>`, `\\>>`). We strip a leading run of NON-operator literal/masked bytes (the
# escaped-byte literals the masker emitted) and check whether the trailing suffix
# is EXACTLY a redirect operator (no glued destination — that path is handled by
# the glued `rre` regex). On match, echo the operator suffix; otherwise echo
# nothing. An escaped odd-parity operator (already masked to `_`) leaves no live
# operator byte, so its token yields no suffix and stays allowed (INV-007 parity).
_redirect_op_suffix() {
  local tok="$1" suffix
  # Strip the leading run of bytes that are NOT redirect-operator bytes. Whatever
  # remains begins at the first surviving (live) operator byte. The masker has
  # already rewritten escaped operators to `_` (a non-operator byte), so this
  # leading run is pure literal/masked prefix and never an escaped operator.
  suffix="${tok##*[!\<\>\&\|]}"
  # `${tok##*[!…]}` leaves nothing when the WHOLE token is operator bytes; in that
  # case suffix == tok. When no operator byte exists at all, the greedy strip also
  # leaves the empty string. Disambiguate: re-derive from a literal scan is
  # unnecessary — match the suffix against the exact operator set below.
  # CLASS-FIX (operator-set canonical list): this accept-set and the glued `rre`
  # regex in _extract_bash_targets are the TWO code sites that enumerate the
  # redirect-operator set. They MUST stay in sync — a new operator added to one
  # must be added to the other (drift caused the `&>>` append-both miss found in
  # mini-audit R1: `>>` was handled but `&>>` was not). When editing this set,
  # also edit `rre` (search "GLUED-REDIRECT OPERATOR SET").
  # `<>` is the read-write redirect (O_RDWR|O_CREAT) — it CREATES+WRITES the
  # target in real bash (`echo x 1<> .env`, `exec 3<> .env`). The leading-digit
  # strip above already reduces `1<>`/`3<>` to `<>`, so the accept-set only needs
  # the bare `<>` form. (mini-audit R2 MA-101: same enumeration-drift class as
  # the `&>>` miss in R1.)
  case "$suffix" in
    '>'|'>>'|'>|'|'>&'|'&>'|'&>>'|'&>|'|'<>') printf '%s' "$suffix" ;;
    *) : ;;
  esac
}

# Insert segment-boundary newlines into a (process-sub-excised, quote-masked)
# command string (CX-007). Bare `;`, `&&`, `||`, bare background `&`, and pipe
# `|` separate segments; an `&` that is part of `&>`/`>&` is NOT a separator, and
# a `|` that is part of `>|`/`&>|` is NOT a separator. Result on stdout, one
# segment per line. Lives in its own function so its O(n) array-join IFS shift is
# isolated from _extract_bash_targets' single-IFS-shift body invariant (PRH-005).
_segment_command() {
  local cmd="$1" n="${#1}" k=0 c c2 cprev crun
  # O(n) accumulation: append chunks to an ARRAY, join ONCE (PMB-019). A grown
  # string (`out="$out$c"`) is O(n^2) in bash on commands with many separators.
  local -a seg_arr=()
  # Fast-path (O(n)): segment boundaries are introduced only by `;`, `|`, `&`.
  # If the command contains NONE of these, there is exactly one segment — the
  # whole command — so emit it verbatim (common large case: `echo BIGBLOB > x`).
  case "$cmd" in
    *[\;\|\&]*) ;;       # has a separator/operator byte — fall through
    *) printf '%s' "$cmd"; return ;;
  esac
  while [ "$k" -lt "$n" ]; do
    # Bulk-copy a maximal run of bytes that are not `;`, `|`, or `&` in one
    # parameter-expansion slice (O(n) over the run) — drop to byte granularity
    # only at a separator/operator byte.
    crun="${cmd:$k}"
    crun="${crun%%[\;\|\&]*}"
    if [ -n "$crun" ]; then
      seg_arr+=("$crun")
      k=$((k + ${#crun}))
      [ "$k" -lt "$n" ] || break
    fi
    c="${cmd:$k:1}"
    c2="${cmd:$((k + 1)):1}"
    cprev=""
    [ "$k" -gt 0 ] && cprev="${cmd:$((k - 1)):1}"
    case "$c" in
      ';')
        seg_arr+=($'\n'); k=$((k + 1)); continue ;;
      '|')
        # `>|` or `&>|` redirect tail -> keep the `|` as part of the operator.
        if [ "$cprev" = ">" ]; then
          seg_arr+=("$c"); k=$((k + 1)); continue
        fi
        if [ "$c2" = "|" ]; then
          seg_arr+=($'\n'); k=$((k + 2)); continue
        fi
        seg_arr+=($'\n'); k=$((k + 1)); continue ;;
      '&')
        # `&>` / `&>|` redirect, or `>&` (prev was `>`) -> keep as-is.
        if [ "$c2" = ">" ] || [ "$cprev" = ">" ]; then
          seg_arr+=("$c"); k=$((k + 1)); continue
        fi
        # `&&` or bare background `&` -> boundary.
        if [ "$c2" = "&" ]; then
          seg_arr+=($'\n'); k=$((k + 2)); continue
        fi
        seg_arr+=($'\n'); k=$((k + 1)); continue ;;
      *)
        seg_arr+=("$c"); k=$((k + 1)); continue ;;
    esac
  done
  local IFS=''
  printf '%s' "${seg_arr[*]}"
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

  # RAW-LENGTH cap (INV-007 fail-OPEN, PMB-019 bounded-medium), checked O(1) at
  # the very TOP — before any byte-walk loop or any counting. The quote/comment/
  # segment maskers walk the command with tail-slices (`${s:$i}`, each O(remaining
  # length)); a command whose bulk-run fast-paths are defeated (e.g. an
  # operator-filled quoted span `echo "<60KB of >>>>>" > dest`, or dense quotes/
  # separators) drops to byte granularity and the whole walk is O(n^2) BY
  # CONSTRUCTION — no trigger-count tuning fixes the exponent.
  #
  # The previous TRIGGER-COUNT cap was fundamentally broken on three counts and
  # is REMOVED entirely: (a) its trigger set omitted `>`/`<`, which ARE inner
  # stop-set bytes of the masker, so an operator-filled span counted ~2 triggers
  # and ran ~46s; (b) even a legitimately dense command was O(n^2) regardless of
  # count; (c) it failed OPEN on attacker/author-controlled padding (a large
  # heredoc body or trailing comment inflated the count past the threshold and
  # ALLOWED a real write — the comment/heredoc-bypass class).
  #
  # A single raw-length cap fixes all three at once: anything larger than the cap
  # fails OPEN (INV-007 — a command this large is exotic / non-naive, not a naive
  # accidental clobber; consistent with PMB-020's guardrail-not-perimeter
  # framing). The cap bounds the O(n^2) byte-walk masking cost so the worst-case
  # sub-cap input (a cap-size quoted span of `>`/`<` operators) completes in
  # well under 2s (measured ~0.9s at 12288 on the dev box; the next step up,
  # 16384, measured ~1.4s — 12288 keeps a safe margin for slower CI hardware).
  #
  # TRADE-OFF vs the old trigger cap: a large single-blob redirect
  # (`echo <200KB-of-'a'> > .env`) now ALSO fails OPEN (accepted) rather than
  # blocking. That path was the one carrying the O(n^2) + comment/heredoc-bypass
  # bugs; a >cap-byte command writing a protected file is non-naive (PMB-020), so
  # the accepted gap is consistent with the guardrail framing. The common naive
  # write — and any SUB-cap heredoc/comment-padded write (the comment-aware
  # masker correctly extracts the `> dest` and BLOCKS) — is unaffected.
  local _SFG_LENGTH_CAP=12288
  if [ "${#COMMAND}" -gt "$_SFG_LENGTH_CAP" ]; then
    return 0
  fi

  cmd="$(_excise_process_subs "$COMMAND")"
  # Neutralize operator/separator/comment bytes that sit INSIDE quoted spans or
  # comments so they are never mistaken for real shell syntax (QA-001/QA-002).
  # Length-preserving and quote-preserving — a quoted redirect/writer DESTINATION
  # (`> ".env"`, `tee ".env"`) survives intact and is dequoted at emit time.
  cmd="$(_mask_quoted_operators "$cmd")"

  # Insert segment-boundary newlines (CX-007). The byte-walk + O(n) array join
  # lives in _segment_command so its own internal IFS shift does NOT count
  # against the extractor body's single-IFS-shift invariant (PRH-005). `segmented`
  # is one segment per line.
  local segmented
  segmented="$(_segment_command "$cmd")"

  # shellcheck disable=SC2141
  local IFS=$' \t\n'
  # Process each segment independently (INV-020). Redirect detection is
  # token-local; writer-command positional logic is bounded to the segment.
  # GLUED-REDIRECT OPERATOR SET: this alternation and the accept-set in
  # _redirect_op_suffix are the TWO sites that enumerate redirect operators —
  # keep them in sync (CLASS-FIX). Regex alternation is leftmost, so the LONGER
  # operators must precede their prefixes: `&>|` and `&>>` (append-both) before
  # `&>`, and `>>`/`>|`/`>&` before the bare `[0-9]*>`. `&>>` was the mini-audit
  # R1 miss — the append variant of `&>`. `[0-9]*<>` / `<>` (read-write redirect,
  # O_RDWR|O_CREAT) is the mini-audit R2 miss (MA-101): it CREATES+WRITES the
  # target. `[0-9]*<>` precedes the bare `[0-9]*>` so a glued `1<>file` matches
  # the read-write form, not a spurious `[0-9]*>` (which cannot match `1<` anyway).
  local rre='(&>\||&>>|&>|>&|>\||>>|[0-9]*<>|<>|[0-9]*>)([^[:space:]<>|&]+)'
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
    # A token may carry a LITERAL/masked prefix glued to a LIVE redirect operator
    # within one whitespace-delimited token — e.g. a backslash-escaped non-operator
    # byte followed by a live `>` (`\\>`, `\1>`, `\_>` from `\&>`, `\\>>`). The
    # round-2 masker neutralizes ESCAPED operators to `_`, so any redirect-operator
    # byte (`>`/`<`/`&`/`|`) that SURVIVES raw in the masked token is genuinely live
    # (QA-006 / AP-022: missing this silently ALLOWS a real write). `_redirect_op_suffix`
    # strips a leading run of non-operator literal/masked bytes and recognizes the
    # trailing live operator; the destination is still the next whitespace-separated
    # token. Escaped odd-parity operators (masked to `_`) leave no live suffix and
    # stay allowed.
    # shellcheck disable=SC2206
    local -a mtokens=($masked)
    j=0
    while [ "$j" -lt "${#mtokens[@]}" ]; do
      op="$(_redirect_op_suffix "${mtokens[$j]}")"
      if [ -n "$op" ]; then
        if [ "$((j + 1))" -lt "${#mtokens[@]}" ]; then
          _emit_dest "${mtokens[$((j + 1))]}"
        fi
      fi
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
      # Target-directory relocation (-t / --target-directory) fails open for ALL
      # four commands (the real dest is a directory we don't resolve). The
      # directory-create form `-d` is command-SPECIFIC: only `install -d`
      # means "create directories" (no source/dest pair) — for cp/mv/ln, `-d`
      # is a benign NON-relocating flag (`cp -d` = --no-dereference), so it must
      # NOT short-circuit (mini-audit R1: `cp -d a .env` wrongly ALLOWED). For
      # install, `-d` still fails open. (`ln -d` does not write a file; the
      # positional logic below handles `ln` correctly either way.)
      case " ${tokens[*]} " in
        *' -t '*|*' --target-directory'*) return 0 ;;
      esac
      if [ "$base" = "install" ]; then
        case " ${tokens[*]} " in
          *' -d '*) return 0 ;;
        esac
      fi
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
