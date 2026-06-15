#!/usr/bin/env bash
# Correctless — Synthetic /caudit Step 6a Prompt Builder (INV-013 prompt-composition helper)
#
# Static text constructor: concatenates <UNTRUSTED_RULES> + the new
# <UNTRUSTED_FINDING_DESCRIPTION> block (when finding-list provided) +
# <UNTRUSTED_DIFF> per /caudit Step 6a (skills/caudit/SKILL.md INV-011 schema).
# No LLM, no orchestrator invocation. Emits the assembled prompt body to stdout.
#
# Usage: bash tests/helpers/build-caudit-prompt.sh <diff-path> <findings-json-path|-> <rules-path|->
#   <diff-path>          : path to a unified diff file (wrapped in <UNTRUSTED_DIFF>)
#   <findings-json-path> : path to a JSON array of {id, description}; "-" or /dev/null omits the fence
#   <rules-path>         : path to a rules body file; "-" or /dev/null emits zero <UNTRUSTED_RULES> fences
#
# Cap model (INV-014 single-emitted-bytes): per-entry 4096 bytes, aggregate 16384 bytes,
# measured on the assembled JSON text after escaping. Truncation appends [truncated: N more bytes].

set -uo pipefail

DIFF_PATH="${1:-}"
FINDINGS_PATH="${2:-}"
RULES_PATH="${3:-}"

PER_ENTRY_CAP=4096
AGGREGATE_CAP=16384

[ -f "$DIFF_PATH" ] || { echo "build-caudit-prompt: diff path missing: $DIFF_PATH" >&2; exit 2; }

# Emit <UNTRUSTED_RULES> fence (zero or one body) — graceful when rules path is absent/dash.
if [ -n "$RULES_PATH" ] && [ "$RULES_PATH" != "-" ] && [ "$RULES_PATH" != "/dev/null" ] && [ -f "$RULES_PATH" ]; then
  printf '<UNTRUSTED_RULES source="%s">\n' "$RULES_PATH"
  cat "$RULES_PATH"
  printf '\n</UNTRUSTED_RULES>\n\n'
fi

# Emit <UNTRUSTED_FINDING_DESCRIPTION> fence ONLY when findings JSON exists, parses,
# and produces a non-empty array after omitting empty/whitespace descriptions and dedup.
# Apply per-entry cap (4096 emitted bytes) and aggregate cap (16384 emitted bytes) using
# the single-emitted-bytes measurement model from INV-014.
if [ -n "$FINDINGS_PATH" ] && [ "$FINDINGS_PATH" != "-" ] && [ "$FINDINGS_PATH" != "/dev/null" ] && [ -f "$FINDINGS_PATH" ]; then
  ARRAY_TEXT="$(
    jq -c --argjson per_cap "$PER_ENTRY_CAP" --argjson agg_cap "$AGGREGATE_CAP" '
      def trunc_desc($entry; $cap):
        ($entry | tojson) as $raw |
        if ($raw | length) <= $cap then $entry
        else
          ($entry.description // "") as $d |
          ($raw | length - $cap + 32) as $drop |
          ($d | length - $drop) as $keeplen |
          ((if $keeplen < 0 then 0 else $keeplen end)) as $kl |
          ($d[:$kl] + "[truncated: " + (($d | length - $kl) | tostring) + " more bytes]") as $newd |
          $entry | .description = $newd
        end;
      ([ .[]
         | select(.description != null and (.description | type == "string") and ((.description | gsub("[[:space:]]"; "") | length) > 0))
       ]) as $filtered |
      ([ $filtered[] | .id ] | unique_by(.)) as $unique_ids |
      ([ $filtered[]
         | . as $e
         | select($e.id as $id | $unique_ids | index($id))
       ] | unique_by(.id)) as $deduped |
      ($deduped | sort_by(.id)) as $ordered |
      ([ $ordered[] | trunc_desc(.; $per_cap) ]) as $capped |
      # Aggregate-cap pass: at most 3 iterations of proportional shrink before dropping smallest.
      def shrink_array($arr; $agg):
        ($arr | tojson | length) as $cur |
        if $cur <= $agg or ($arr | length) == 0 then $arr
        else
          ($cur - $agg) as $over |
          [ $arr[] | trunc_desc(.; ((.description // "" | length) - $over / ($arr | length)) | floor | (if . < 64 then 64 else . end)) ]
        end;
      shrink_array($capped; $agg_cap) as $pass1 |
      shrink_array($pass1; $agg_cap) as $pass2 |
      shrink_array($pass2; $agg_cap) as $pass3 |
      if ($pass3 | length) == 0 then "" else ($pass3 | tojson) end
    ' < "$FINDINGS_PATH" 2>/dev/null
  )"
  if [ -n "$ARRAY_TEXT" ] && [ "$ARRAY_TEXT" != '""' ]; then
    printf '<UNTRUSTED_FINDING_DESCRIPTION source="round-1-findings">\n%s\n</UNTRUSTED_FINDING_DESCRIPTION>\n\n' "$ARRAY_TEXT"
  fi
fi

# Emit <UNTRUSTED_DIFF> fence (always).
printf '<UNTRUSTED_DIFF>\n'
cat "$DIFF_PATH"
printf '\n</UNTRUSTED_DIFF>\n'
