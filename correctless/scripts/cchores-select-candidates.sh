#!/usr/bin/env bash
# Correctless — /cchores deterministic candidate-filter (B-3, INV-002/INV-004).
#
# The MECHANICAL part of /cchores issue selection is pinned here as a coded,
# behaviorally-testable helper so the exclusion logic is not prose-only in the
# SKILL.md (AP-013 / structural-enforcement-over-prompt). The LLM severity
# ranking among the SUITABLE survivors remains a documented prompt-level
# residual; this script only computes the ELIGIBLE candidate SET.
#
# Contract:
#   Input  : `gh issue list` JSON on STDIN, or via --issues-file <path>.
#            An array of {number, title, body, labels, createdAt}.
#   Flags  : --attempted-store <path>  cchores-attempted.json
#                                       {schema_version, attempts:[{issue,outcome,...}]}
#            --open-prs-file   <path>  `gh pr list` JSON
#                                       [{number, headRefName, body}]
#            --issues-file     <path>  read issues from a file instead of stdin
#   Output : a JSON array of candidate issue NUMBERS on stdout =
#            open issues
#              MINUS any issue with an open PR carrying an exact `Closes #N` /
#                    `Fixes #N` in its .body OR a .headRefName matching the EXACT
#                    ref `chore/issue-{N}-*` (NOT a raw {N} substring — RS-027 /
#                    INV-004: `chore/issue-3-x` must NOT match issue #33),
#              MINUS any issue with an `aborted` attempt in the store (INV-019),
#            preserving input order.
#
#   Pagination completeness (RS-028 / INV-002j): if the input contains EXACTLY
#   100 issues (the `--limit 100` page), the set is NOT assumed complete — a
#   `--truncated` warning is emitted to stderr. The candidate set is still
#   printed (the warning is advisory; the caller must paginate).
#
# All JSON parsing is via jq. Exact-ref matching anchors on the literal
# `chore/issue-{N}-` prefix so issue #3 cannot match a #33 branch.
set -euo pipefail

# ---------------------------------------------------------------------------
# jq is the only hard dependency. Fail loudly if it is missing.
# ---------------------------------------------------------------------------
if ! command -v jq >/dev/null 2>&1; then
  echo "cchores-select-candidates: jq is required but not found on PATH" >&2
  exit 2
fi

ISSUES_FILE=""
ATTEMPTED_STORE=""
OPEN_PRS_FILE=""

# ---------------------------------------------------------------------------
# Argument parsing. Each flag takes a path argument.
# ---------------------------------------------------------------------------
while [ "$#" -gt 0 ]; do
  case "$1" in
    --issues-file)
      ISSUES_FILE="${2:-}"; shift 2 || { echo "cchores-select-candidates: --issues-file needs a path" >&2; exit 2; }
      ;;
    --attempted-store)
      ATTEMPTED_STORE="${2:-}"; shift 2 || { echo "cchores-select-candidates: --attempted-store needs a path" >&2; exit 2; }
      ;;
    --open-prs-file)
      OPEN_PRS_FILE="${2:-}"; shift 2 || { echo "cchores-select-candidates: --open-prs-file needs a path" >&2; exit 2; }
      ;;
    *)
      echo "cchores-select-candidates: unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

# ---------------------------------------------------------------------------
# Load the issues array (from --issues-file if given, else stdin).
# ---------------------------------------------------------------------------
if [ -n "$ISSUES_FILE" ]; then
  if [ ! -f "$ISSUES_FILE" ]; then
    echo "cchores-select-candidates: --issues-file not found: $ISSUES_FILE" >&2
    exit 2
  fi
  ISSUES_JSON="$(cat "$ISSUES_FILE")"
else
  ISSUES_JSON="$(cat)"
fi

# Validate the issues input is a JSON array. Fail closed on malformed input.
if ! printf '%s' "$ISSUES_JSON" | jq -e 'type == "array"' >/dev/null 2>&1; then
  echo "cchores-select-candidates: issues input is not a JSON array" >&2
  exit 2
fi

# ---------------------------------------------------------------------------
# Load the open-PRs array (default to []) — validate and fail closed.
# ---------------------------------------------------------------------------
OPEN_PRS_JSON="[]"
if [ -n "$OPEN_PRS_FILE" ]; then
  if [ ! -f "$OPEN_PRS_FILE" ]; then
    echo "cchores-select-candidates: --open-prs-file not found: $OPEN_PRS_FILE" >&2
    exit 2
  fi
  OPEN_PRS_JSON="$(cat "$OPEN_PRS_FILE")"
  if ! printf '%s' "$OPEN_PRS_JSON" | jq -e 'type == "array"' >/dev/null 2>&1; then
    echo "cchores-select-candidates: --open-prs-file is not a JSON array: $OPEN_PRS_FILE" >&2
    exit 2
  fi
fi

# ---------------------------------------------------------------------------
# Load the attempted-store (default to an empty attempts set) — validate.
# ---------------------------------------------------------------------------
ATTEMPTED_JSON='{"schema_version":1,"attempts":[]}'
if [ -n "$ATTEMPTED_STORE" ]; then
  if [ ! -f "$ATTEMPTED_STORE" ]; then
    echo "cchores-select-candidates: --attempted-store not found: $ATTEMPTED_STORE" >&2
    exit 2
  fi
  ATTEMPTED_JSON="$(cat "$ATTEMPTED_STORE")"
  if ! printf '%s' "$ATTEMPTED_JSON" | jq -e 'type == "object" and (.attempts | type == "array")' >/dev/null 2>&1; then
    echo "cchores-select-candidates: --attempted-store has no .attempts array: $ATTEMPTED_STORE" >&2
    exit 2
  fi
fi

# ---------------------------------------------------------------------------
# Pagination-completeness signal (RS-028 / INV-002j): exactly 100 input issues
# means the `--limit 100` page could be truncated — surface a warning. Never
# treat a full page as authoritatively complete.
# ---------------------------------------------------------------------------
ISSUE_COUNT="$(printf '%s' "$ISSUES_JSON" | jq 'length')"
if [ "$ISSUE_COUNT" -eq 100 ]; then
  echo "cchores-select-candidates: --truncated: exactly 100 issues returned; the candidate set may be incomplete (RS-028 — paginate beyond --limit 100, not assumed complete)" >&2
fi

# ---------------------------------------------------------------------------
# Core filter (single jq pass).
#   in_progress[]  : the set of issue numbers in progress, derived from open PRs.
#       - .body containing an exact `Closes #N` / `Fixes #N` (case-insensitive
#         keyword, word-bounded number — `Closes #2` must not match `#202`).
#       - .headRefName matching the EXACT ref `chore/issue-{N}-` prefix
#         (anchored — `chore/issue-3-` must NOT match `chore/issue-33-foo`).
#   aborted[]      : issue numbers with an `aborted` attempt in the store.
#   The output is the input issue numbers minus (in_progress + aborted),
#   in input order.
#
# Exact-ref derivation strategy: rather than test "does PR X reference issue N"
# for every (issue, PR) pair (which invites substring bugs), we EXTRACT the set
# of referenced issue numbers directly from each PR:
#   - from .body: capture the digits after `Closes #` / `Fixes #` via regex with
#     a trailing non-digit / end boundary, so `#2` never absorbs into `#202`.
#   - from .headRefName: capture the digits in `chore/issue-{N}-` anchored at the
#     start of the ref and terminated by the literal `-`, so `3` != `33`.
# Both yield NUMERIC issue ids; membership is then exact numeric equality.
#
# AP-039 / PMB-019: the issues blob is UNBOUNDED (every issue body) and MUST NOT
# transit argv. Passing it via `--argjson issues "$ISSUES_JSON"` puts the whole
# serialized array on jq's command line, which dies with `Argument list too
# long` (exit 126) once the single argument exceeds the per-arg ARG_MAX (~128KB
# on Linux). Instead we feed each blob through a file descriptor via `--rawfile`
# from process substitution (no persisted temp file) and parse it inside jq with
# `fromjson`. prs/store get the same treatment for robustness against the class.
# ---------------------------------------------------------------------------
RESULT="$(
  jq -n \
    --rawfile issues_raw <(printf '%s' "$ISSUES_JSON") \
    --rawfile prs_raw <(printf '%s' "$OPEN_PRS_JSON") \
    --rawfile store_raw <(printf '%s' "$ATTEMPTED_JSON") '
    ($issues_raw | fromjson) as $issues |
    ($prs_raw    | fromjson) as $prs    |
    ($store_raw  | fromjson) as $store  |
    # --- issue numbers referenced by open PRs (exact-ref, RS-027) ---------
    (
      [ $prs[]
        | (
            # Closes/Fixes #N from the body — bounded so #2 != #202.
            ( (.body // "")
              | [ scan("(?i)(?:closes|fixes)\\s+#([0-9]+)") ]
              | map(.[0] | tonumber)
            )
            +
            # chore/issue-{N}- from the head ref — anchored at start, the
            # number terminated by `-` so chore/issue-3- != chore/issue-33-.
            ( (.headRefName // "")
              | [ scan("^chore/issue-([0-9]+)-") ]
              | map(.[0] | tonumber)
            )
          )
        | .[]
      ]
      | unique
    ) as $in_progress
    |
    # --- issue numbers with an `aborted` attempt in the store (INV-019) ----
    (
      [ ($store.attempts // [])[]
        | select((.outcome // "") == "aborted")
        | .issue
      ]
      | unique
    ) as $aborted
    |
    # --- keep open issues minus (in_progress + aborted), input order ------
    [ $issues[]
      | .number
      | select( (. as $n | $in_progress | index($n)) == null )
      | select( (. as $n | $aborted    | index($n)) == null )
    ]
  '
)"

printf '%s\n' "$RESULT"
