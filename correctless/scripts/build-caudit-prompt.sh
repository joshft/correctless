#!/usr/bin/env bash
# Correctless — /caudit Step 6a prompt builder (PRODUCTION producer)
#
# This is the production prompt producer invoked by /caudit Step 6a (CS-011,
# RS-014). It is NOT test-only — it is installed to .correctless/scripts/ by
# setup and propagated to correctless/scripts/ by sync.sh, and Step 6a invokes
# the INSTALLED copy at `.correctless/scripts/build-caudit-prompt.sh` to emit the
# `<UNTRUSTED_FINDING_DESCRIPTION>` fence text it embeds (verbatim) into the
# reviewer Task prompt between `<UNTRUSTED_RULES>` and `<UNTRUSTED_DIFF>`.
#
# Implements the CS-013 prompt-composition + CS-014 truncation algorithm. This is
# NOT a static concat (RS-025) — it performs emitted-byte truncation
# (per-description <=4096 bytes, aggregate <= carve) measured on the EMITTED
# (post-JSON-escape) form using a byte-counting primitive (jq utf8bytelength /
# wc -c), NOT char/codepoint.
#
# Aggregate cap is a CARVE (CS-014, QA-003), not a static 16384:
#     aggregate_cap = min(16384, 102400 - measured(DIFF) - measured(RULES) - overhead)
# so the fence never pushes the assembled prompt over /caudit's 100 KB ceiling.
# When the measured DIFF+RULES bytes are not supplied, the cap falls back to the
# static 16384 (the small-prompt common case).
#
# Usage:
#   build_caudit_prompt <fixture-diff-path> <findings-json-path|/dev/null> \
#       [rules-text] [diff_bytes] [rules_bytes] [pre_pr_base_markers_path|/dev/null]
#
# Emits the assembled Step 6a prompt body to stdout:
#   <UNTRUSTED_RULES> ... </UNTRUSTED_RULES>
#   <UNTRUSTED_FINDING_DESCRIPTION source="round-N-findings"> [JSON array]
#     </UNTRUSTED_FINDING_DESCRIPTION>   (omitted when array would be empty)
#   <PRE_PR_BASE_MARKERS> ... </PRE_PR_BASE_MARKERS>   (CS-016c, QA-005 — emitted
#     whenever the diff carries a SIBLING-DEFERRED marker; enumerates the markers
#     the orchestrator computed as present at the PR base / merge-base)
#   <UNTRUSTED_DIFF> ... </UNTRUSTED_DIFF>
#
# No LLM. Mirrors CS-011's schema and CS-014's algorithm precisely.
#
# POSIX externals: jq, wc, cat, grep. Bash 4+ permitted.

# shellcheck disable=SC2034

set -uo pipefail

PER_ENTRY_CAP=4096
# Static upper bound on the aggregate fence; the live cap is carved from the
# 100 KB prompt ceiling per CS-014 (see _carve_aggregate_cap).
AGGREGATE_CAP_MAX=16384
PROMPT_CEILING=102400
# Fixed overhead reserved for fence wrappers, output contract, framing, and the
# pre-PR-base-marker fence so the carve does not push the prompt over ceiling.
CARVE_OVERHEAD=8192

# Compute the live aggregate cap (CS-014, QA-003):
#   min(AGGREGATE_CAP_MAX, PROMPT_CEILING - diff_bytes - rules_bytes - overhead)
# Falls back to AGGREGATE_CAP_MAX when measured byte counts are absent/zero.
# Never returns below a 256-byte floor so at least a per-finding truncation
# marker survives.
_carve_aggregate_cap() {
  local diff_bytes="${1:-0}" rules_bytes="${2:-0}"
  [[ "$diff_bytes" =~ ^[0-9]+$ ]] || diff_bytes=0
  [[ "$rules_bytes" =~ ^[0-9]+$ ]] || rules_bytes=0
  if [ "$diff_bytes" -eq 0 ] && [ "$rules_bytes" -eq 0 ]; then
    printf '%s' "$AGGREGATE_CAP_MAX"
    return 0
  fi
  local carve=$(( PROMPT_CEILING - diff_bytes - rules_bytes - CARVE_OVERHEAD ))
  if [ "$carve" -lt 256 ]; then carve=256; fi
  if [ "$carve" -gt "$AGGREGATE_CAP_MAX" ]; then carve="$AGGREGATE_CAP_MAX"; fi
  printf '%s' "$carve"
}

# Byte length of a string (NOT char/codepoint). RS-022.
_byte_len() {
  printf '%s' "$1" | wc -c | tr -d ' '
}

# Serialize {"id":..,"description":..} with the description truncated to the
# first `keep` codepoints, appending the truncation marker when keep < full.
# Never splits a multibyte sequence or a JSON escape (substring is codepoint-
# indexed; jq re-escapes the result so the emitted form is always valid JSON).
_emit_obj() {
  local id="$1" full="$2" keep="$3" raw_bytes="$4"
  if [ "$keep" -ge "${#full}" ]; then
    jq -cn --arg id "$id" --arg d "$full" '{id:$id,description:$d}'
    return 0
  fi
  local trunc="${full:0:$keep}"
  local kept_bytes dropped
  kept_bytes="$(_byte_len "$trunc")"
  dropped=$((raw_bytes - kept_bytes))
  jq -cn --arg id "$id" --arg d "${trunc}[truncated: ${dropped} more bytes]" '{id:$id,description:$d}'
}

# Build a single emitted JSON object {"id":..,"description":..}, truncating the
# description (by codepoints, never splitting a multibyte sequence or a JSON
# escape) until the EMITTED object is <= cap bytes. Appends [truncated: N more
# bytes] marker when truncation occurs. Echoes the emitted JSON object text.
#
# QA2-004: the keep-length is found by BINARY SEARCH on codepoint count
# (O(log n) jq invocations) rather than a linear codepoint-drop loop (O(n)).
# The emitted-byte length is monotonic non-decreasing in keep, so binary search
# over [0, len] for the largest keep whose emitted object is <= cap is correct.
_build_entry() {
  local id="$1" desc="$2" cap="${3:-$PER_ENTRY_CAP}"
  local obj
  obj="$(jq -cn --arg id "$id" --arg d "$desc" '{id:$id,description:$d}')"
  # Fast path: untruncated object already fits.
  if [ "$(_byte_len "$obj")" -le "$cap" ]; then
    printf '%s' "$obj"
    return 0
  fi
  local raw_bytes len
  raw_bytes="$(_byte_len "$desc")"
  len="${#desc}"
  # Binary search for the largest keep in [0, len) whose EMITTED (post-escape,
  # marker-appended) object is <= cap. lo is the best known-good keep so far.
  local lo=0 hi="$len" best=0
  while [ "$lo" -le "$hi" ]; do
    local mid=$(( (lo + hi) / 2 ))
    local cand
    cand="$(_emit_obj "$id" "$desc" "$mid" "$raw_bytes")"
    if [ "$(_byte_len "$cand")" -le "$cap" ]; then
      best="$mid"
      lo=$((mid + 1))
    else
      hi=$((mid - 1))
    fi
  done
  _emit_obj "$id" "$desc" "$best" "$raw_bytes"
}

build_caudit_prompt() {
  local diff_path="$1" findings_path="$2" rules_text="${3:-no rules}"
  # CS-014/QA-003: measured DIFF+RULES byte counts feed the aggregate carve.
  # When omitted (0), the producer self-measures from the diff file and rules
  # text (so the caller need not duplicate the byte-count in the skill text);
  # if both are still zero the carve falls back to the static AGGREGATE_CAP_MAX.
  local diff_bytes="${4:-0}" rules_bytes="${5:-0}"
  # QA-005/CS-016c: optional path to the orchestrator-computed pre-PR-base
  # SIBLING-DEFERRED marker list (one marker per line). /dev/null or empty when
  # none were computed.
  local pre_pr_base_path="${6:-/dev/null}"

  # Self-measure when not supplied (keeps the byte-counting out of the skill
  # prose so it does not collide with the PROMPT_BYTES 100 KB gate's own counter).
  [ "$diff_bytes" -eq 0 ] && [ -f "$diff_path" ] && diff_bytes="$(_byte_len "$(cat "$diff_path")")"
  [ "$rules_bytes" -eq 0 ] && rules_bytes="$(_byte_len "$rules_text")"

  # Live aggregate cap carved from the 100 KB ceiling (CS-014).
  local aggregate_cap
  aggregate_cap="$(_carve_aggregate_cap "$diff_bytes" "$rules_bytes")"

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
      # The cap is the carve (min(16384, 100KB - DIFF - RULES - overhead)), not
      # a static 16384 (CS-014, QA-003).
      local pass=0
      while [ "$(_byte_len "$array_text")" -gt "$aggregate_cap" ] && [ "$pass" -lt 3 ]; do
        local share=$(( aggregate_cap / n ))
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

      # QA2-003: HARD carve enforcement. After proportional re-truncation, the
      # array may STILL exceed the carve when there are many entries (the JSON
      # wrappers + per-entry minimums sum above the cap, or `share` hit its 64-
      # byte floor). The invariant "emitted <= aggregate_cap" must hold BY
      # CONSTRUCTION, not best-effort. Rebuild the array entry-by-entry, dropping
      # WHOLE entries from the tail once the next entry would breach the cap.
      # Each dropped entry is NOT silent — it is replaced by a minimal per-finding
      # truncation marker object {"id":..,"description":"[truncated: dropped]"} so
      # no finding vanishes without a trace, while still respecting the cap.
      if [ "$(_byte_len "$array_text")" -gt "$aggregate_cap" ]; then
        local rebuilt="" j=0
        while [ "$j" -lt "$n" ]; do
          local eid edesc entry marker candidate
          eid="$(printf '%s' "$filtered" | jq -r ".[$j].id")"
          edesc="$(printf '%s' "$filtered" | jq -r ".[$j].description")"
          entry="$(_build_entry "$eid" "$edesc" "$PER_ENTRY_CAP")"
          # Marker object stands in for a dropped finding (forensic, not silent).
          marker="$(jq -cn --arg id "$eid" '{id:$id,description:"[truncated: finding dropped to honor aggregate cap]"}')"
          # Would adding the FULL entry keep us within cap? If yes, add it; else
          # try the marker; if even the marker breaches, stop (tail dropped).
          if [ -z "$rebuilt" ]; then candidate="[${entry}]"; else candidate="[${rebuilt},${entry}]"; fi
          if [ "$(_byte_len "$candidate")" -le "$aggregate_cap" ]; then
            if [ -z "$rebuilt" ]; then rebuilt="$entry"; else rebuilt="${rebuilt},${entry}"; fi
            j=$((j + 1)); continue
          fi
          if [ -z "$rebuilt" ]; then candidate="[${marker}]"; else candidate="[${rebuilt},${marker}]"; fi
          if [ "$(_byte_len "$candidate")" -le "$aggregate_cap" ]; then
            if [ -z "$rebuilt" ]; then rebuilt="$marker"; else rebuilt="${rebuilt},${marker}"; fi
            j=$((j + 1)); continue
          fi
          # Even the marker would breach — the remaining tail cannot be carried.
          break
        done
        # Guarantee a non-empty, in-cap array. If even the first marker did not
        # fit (cap smaller than a single minimal object — only at the 256 floor
        # with a long id), emit a single global truncation marker.
        if [ -z "$rebuilt" ]; then
          rebuilt="$(jq -cn '{id:"AGG",description:"[truncated: all findings dropped to honor aggregate cap]"}')"
        fi
        array_text="[${rebuilt}]"
      fi
    fi
  fi

  if [ "$emit_fence" -eq 1 ]; then
    printf '<UNTRUSTED_FINDING_DESCRIPTION source="round-N-findings">%s</UNTRUSTED_FINDING_DESCRIPTION>\n' "$array_text"
  else
    # Graceful-degradation advisory (RS-031): observable one-liner.
    printf 'finding-description fence omitted: round artifact absent/unparsable; lens runs on diff signal only\n'
  fi

  # --- PRE_PR_BASE_MARKERS fence (CS-016c, QA-005) ---
  # The suppress-vs-downgrade contract (CS-016) needs a CODED data source for
  # which SIBLING-DEFERRED markers were already present at the PR base. The
  # reviewer cannot run git, so the orchestrator computes them and the builder
  # emits them in a fence. When the diff carries ANY SIBLING-DEFERRED marker we
  # MUST emit this fence so the reviewer can distinguish suppress (pre-PR-base)
  # from downgrade-to-MEDIUM (current-PR-only). If no pre-PR-base marker list was
  # supplied, emit an observable degradation advisory inside the fence (forensic
  # check: a SIBLING-DEFERRED marker in the diff with no pre-PR-base fence is a
  # wiring bug, never silent).
  if grep -qE 'SIBLING-DEFERRED:' "$diff_path" 2>/dev/null; then
    printf '<PRE_PR_BASE_MARKERS source="merge-base">\n'
    if [ "$pre_pr_base_path" != "/dev/null" ] && [ -s "$pre_pr_base_path" ]; then
      cat "$pre_pr_base_path"
    else
      printf 'pre-PR-base marker list unavailable: no markers computed at merge-base; treat all SIBLING-DEFERRED markers in the diff as current-PR (downgrade to MEDIUM, do not suppress)\n'
    fi
    printf '</PRE_PR_BASE_MARKERS>\n'
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
