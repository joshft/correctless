#!/usr/bin/env bash
# Correctless — meta baseline pollution detector (calibration-writer RS-013).
# Spec: .correctless/specs/calibration-writer.md
#
# DETECTION ONLY, ADVISORY (2026-05-15 re-derivation/backstop convention). Flags
# `.correctless/meta/*.json` files carrying a `created_at_commit` that is NOT a
# known commit in this repo (the unambiguous corruption/pollution signal). Repair
# is advisory and out of scope (last-write-wins, gitignored local state); this
# helper only surfaces the anomaly for a human. It ALWAYS exits 0 — it never
# blocks a phase transition (DD-001).
#
# MA-M4: the earlier `created_at_commit != current merge-base` divergence check
# was REMOVED — it false-positived on ~100% of later feature branches (a
# legitimately different feature baseline also diverges), so it could not
# distinguish #226 pollution from the benign later-feature case. A detection-only
# advisory that cannot separate its target from a common benign state is
# signal-erosion by construction. Only the unambiguous unknown/corrupt-commit
# case remains.
#
# Usage: bash scripts/meta-pollution-detect.sh [--meta-dir DIR] [--base-ref REF]
# Output: one advisory line per suspect file on stdout; empty output = clean.

set -o pipefail

META_DIR=".correctless/meta"
BASE_REF=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --meta-dir) META_DIR="${2:-}"; shift 2 ;;
    --base-ref) BASE_REF="${2:-}"; shift 2 ;;
    *) shift ;;
  esac
done

command -v jq >/dev/null 2>&1 || exit 0   # advisory: no jq -> silently no-op
[ -d "$META_DIR" ] || exit 0

# MA-M4: the merge-base divergence compare was removed (chronic false positive).
# --base-ref is still accepted for backward compatibility with existing callers,
# but is no longer consulted for a verdict.
: "${BASE_REF:=}"

for f in "$META_DIR"/*.json; do
  [ -f "$f" ] || continue
  # Only files that actually carry a present, non-null created_at_commit.
  if ! jq -e 'type=="object" and has("created_at_commit") and .created_at_commit != null' "$f" >/dev/null 2>&1; then
    continue
  fi
  sha="$(jq -r '.created_at_commit // ""' "$f" 2>/dev/null)"
  [ -n "$sha" ] || continue

  # Unknown/invalid commit — the ONLY unambiguous pollution/corruption signal
  # (MA-M4). A present, non-null created_at_commit that is not a known commit in
  # this repo cannot be explained by a benign later-feature baseline.
  if command -v git >/dev/null 2>&1 && git rev-parse --git-dir >/dev/null 2>&1; then
    if ! git cat-file -e "${sha}^{commit}" 2>/dev/null; then
      printf 'meta-pollution: %s created_at_commit=%s is not a known commit in this repo (possible corruption or a prior /cdocs blanket-scan — #226)\n' "$f" "$sha"
      continue
    fi
  fi
done

# Always advisory — never a non-zero gate.
exit 0
