#!/usr/bin/env bash
# Correctless — Synthetic /caudit Step 6a prompt builder (test helper)
#
# Implements the CS-013 prompt-composition + CS-014 truncation algorithm for
# the fix-diff-reviewer-class spec. This is NOT a static concat (RS-025) — it
# performs emitted-byte truncation (per-description <=4096 bytes, aggregate
# <=16384 bytes) measured on the EMITTED (post-JSON-escape) form using a
# byte-counting primitive (jq utf8bytelength / wc -c), NOT char/codepoint.
#
# Usage:
#   build_caudit_prompt <fixture-diff-path> <findings-json-path|/dev/null> <rules-text>
#
# Emits the assembled synthetic Step 6a prompt body to stdout:
#   <UNTRUSTED_RULES> ... </UNTRUSTED_RULES>
#   <UNTRUSTED_FINDING_DESCRIPTION source="round-N-findings"> [JSON array]
#     </UNTRUSTED_FINDING_DESCRIPTION>   (omitted when array would be empty)
#   <UNTRUSTED_DIFF> ... </UNTRUSTED_DIFF>
#
# No LLM, no orchestrator invocation. Mirrors CS-011's schema and CS-014's
# algorithm precisely so the test layer can assert the assembled prompt's shape.
#
# POSIX externals: jq, wc, cat. Bash 4+ permitted.

# shellcheck disable=SC2034

set -uo pipefail

PER_ENTRY_CAP=4096
AGGREGATE_CAP=16384

# Byte length of a string (NOT char/codepoint). RS-022.
_byte_len() {
  printf '%s' "$1" | wc -c | tr -d ' '
}

# Build a single emitted JSON object {"id":..,"description":..}, truncating the
# description (by codepoints, never splitting a multibyte sequence or a JSON
# escape) until the EMITTED object is <= cap bytes. Appends [truncated: N more
# bytes] marker when truncation occurs. Echoes the emitted JSON object text.
_build_entry() {
  local id="$1" desc="$2" cap="${3:-$PER_ENTRY_CAP}"
  local obj
  obj="$(jq -cn --arg id "$id" --arg d "$desc" '{id:$id,description:$d}')"
  local elen
  elen="$(printf '%s' "$obj" | jq -j 'tojson | utf8bytelength' 2>/dev/null || _byte_len "$obj")"
  # jq tojson|utf8bytelength measures the serialized form; fall back to wc -c.
  elen="$(_byte_len "$obj")"
  if [ "$elen" -le "$cap" ]; then
    printf '%s' "$obj"
    return 0
  fi
  # Truncate the description by codepoints from the END until it fits.
  local raw_bytes
  raw_bytes="$(_byte_len "$desc")"
  local trunc="$desc"
  local dropped=0
  while [ "$(_byte_len "$obj")" -gt "$cap" ] && [ -n "$trunc" ]; do
    # Drop ~16 codepoints at a time for speed, then refine by 1.
    local step=16
    [ "${#trunc}" -lt 64 ] && step=1
    trunc="${trunc%"${trunc: -$step}"}"
    local kept_bytes
    kept_bytes="$(_byte_len "$trunc")"
    dropped=$((raw_bytes - kept_bytes))
    obj="$(jq -cn --arg id "$id" --arg d "${trunc}[truncated: ${dropped} more bytes]" '{id:$id,description:$d}')"
  done
  printf '%s' "$obj"
}

build_caudit_prompt() {
  local diff_path="$1" findings_path="$2" rules_text="${3:-no rules}"

  # --- RULES fence ---
  printf '<UNTRUSTED_RULES>\n%s\n</UNTRUSTED_RULES>\n' "$rules_text"

  # --- FINDING_DESCRIPTION fence (CS-011 JSON-array form, CS-014 truncation) ---
  local emit_fence=0 array_text="[]"
  if [ "$findings_path" != "/dev/null" ] && [ -s "$findings_path" ] \
     && jq -e . "$findings_path" >/dev/null 2>&1; then
    # Filter: drop null/empty/whitespace-only descriptions; dedupe id; sort by id.
    local filtered
    filtered="$(jq -c '
      [ .[]
        | select(.description != null)
        | select((.description | gsub("\\s";"") ) != "")
      ]
      | unique_by(.id)
      | sort_by(.id)
    ' "$findings_path" 2>/dev/null || echo '[]')"
    local n
    n="$(printf '%s' "$filtered" | jq 'length' 2>/dev/null || echo 0)"
    if [ "${n:-0}" -gt 0 ]; then
      emit_fence=1
      # Build per-entry-capped entries.
      local i=0 entries=""
      while [ "$i" -lt "$n" ]; do
        local eid edesc entry
        eid="$(printf '%s' "$filtered" | jq -r ".[$i].id")"
        edesc="$(printf '%s' "$filtered" | jq -r ".[$i].description")"
        entry="$(_build_entry "$eid" "$edesc" "$PER_ENTRY_CAP")"
        if [ -z "$entries" ]; then entries="$entry"; else entries="${entries},${entry}"; fi
        i=$((i + 1))
      done
      array_text="[${entries}]"
      # Aggregate cap: proportional re-truncation, marker-per-finding preserved.
      local pass=0
      while [ "$(_byte_len "$array_text")" -gt "$AGGREGATE_CAP" ] && [ "$pass" -lt 3 ]; do
        local share=$(( AGGREGATE_CAP / n ))
        [ "$share" -lt 64 ] && share=64
        i=0; entries=""
        while [ "$i" -lt "$n" ]; do
          local eid edesc entry
          eid="$(printf '%s' "$filtered" | jq -r ".[$i].id")"
          edesc="$(printf '%s' "$filtered" | jq -r ".[$i].description")"
          entry="$(_build_entry "$eid" "$edesc" "$share")"
          if [ -z "$entries" ]; then entries="$entry"; else entries="${entries},${entry}"; fi
          i=$((i + 1))
        done
        array_text="[${entries}]"
        pass=$((pass + 1))
      done
    fi
  fi

  if [ "$emit_fence" -eq 1 ]; then
    printf '<UNTRUSTED_FINDING_DESCRIPTION source="round-N-findings">%s</UNTRUSTED_FINDING_DESCRIPTION>\n' "$array_text"
  else
    # Graceful-degradation advisory (RS-031): observable one-liner.
    printf 'finding-description fence omitted: round artifact absent/unparsable; lens runs on diff signal only\n'
  fi

  # --- DIFF fence ---
  printf '<UNTRUSTED_DIFF>\n'
  cat "$diff_path"
  printf '\n</UNTRUSTED_DIFF>\n'
}

# Allow direct CLI invocation for manual inspection.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  build_caudit_prompt "$@"
fi
