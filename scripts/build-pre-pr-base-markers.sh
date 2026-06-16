#!/usr/bin/env bash
# Correctless — pre-PR-base SIBLING-DEFERRED marker producer (MA-M1, CS-016c)
#
# CODED producer for the orchestrator-supplied pre-PR-base marker list consumed
# by build-caudit-prompt.sh as its `pre_pr_base_markers_path` argument. Symmetric
# with the RS-014 finding-description producer: the suppress-vs-downgrade contract
# (CS-016) needs a coded data source for which SIBLING-DEFERRED markers were
# ALREADY PRESENT at the PR base / merge-base. Without this, the marker variable
# defaults to /dev/null and the SUPPRESS path is dead — every legitimately
# pre-deferred sibling re-fires at MEDIUM each round (AP-026 prose-only contract).
#
# It computes the merge-base of the feature branch against the base branch
# (default origin/main) and extracts every line containing a `SIBLING-DEFERRED:`
# marker from the tree AT that merge-base. Those are the markers present before
# the current PR — the reviewer fully suppresses findings for siblings these
# cover (current-PR-only markers only downgrade to MEDIUM).
#
# Usage:
#   build-pre-pr-base-markers.sh [base-ref] [output-path]
#     base-ref     defaults to origin/main (falls back to main)
#     output-path  defaults to a temp file; the path is printed to stdout
#
# Output: writes the marker lines (one per line) to <output-path> and prints the
# path on stdout so the caller can pass it to build-caudit-prompt.sh. When git is
# unavailable or no merge-base resolves, writes an EMPTY file and still prints its
# path (the consumer treats an empty file as "no pre-PR-base markers" and emits
# the degradation advisory inside the fence — observable, never silent).
#
# POSIX externals: git, grep. Bash 4+ permitted.

set -uo pipefail

base_ref="${1:-}"
out_path="${2:-}"

[ -n "$out_path" ] || out_path="$(mktemp 2>/dev/null)" || out_path="/tmp/pre-pr-base-markers.$$"
: > "$out_path" 2>/dev/null || true

# Resolve the base ref: prefer the explicit arg, then origin/main, then main.
if [ -z "$base_ref" ]; then
  if git rev-parse --verify origin/main >/dev/null 2>&1; then
    base_ref="origin/main"
  else
    base_ref="main"
  fi
fi

if command -v git >/dev/null 2>&1; then
  merge_base="$(git merge-base "$base_ref" HEAD 2>/dev/null || echo "")"
  if [ -n "$merge_base" ]; then
    # Enumerate the tree at the merge-base and grep each tracked text file for
    # SIBLING-DEFERRED markers. `git grep` against the merge-base commit scans the
    # tree as it existed at the PR base — exactly the pre-PR-base provenance the
    # CS-016 suppress path requires.
    git grep -h -E 'SIBLING-DEFERRED:[[:space:]]+\S+(:[0-9]+)?[[:space:]]+[—-]' \
      "$merge_base" -- 2>/dev/null >> "$out_path" || true
  fi
fi

printf '%s\n' "$out_path"
