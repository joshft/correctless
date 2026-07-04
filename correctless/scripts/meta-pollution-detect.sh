#!/usr/bin/env bash
# Correctless — meta baseline pollution detector (calibration-writer RS-013).
# Spec: .correctless/specs/calibration-writer.md
#
# DETECTION ONLY, ADVISORY (2026-05-15 re-derivation/backstop convention). Flags
# `.correctless/meta/*.json` files carrying a non-null `created_at_commit` whose
# value diverges from the current feature's merge-base with the default branch —
# the #226 cross-feature-pollution shape, where an earlier /cdocs blanket-scan
# stamped one feature's merge-base onto another feature's baseline. Repair is
# advisory and out of scope (last-write-wins, gitignored local state); this
# helper only surfaces the divergence for a human. It ALWAYS exits 0 — it never
# blocks a phase transition (DD-001).
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

# Resolve the feature's pre-feature baseline commit (merge-base with the default
# branch). Best-effort: if git or the base ref is unavailable, skip the compare
# but still report unknown/invalid commits.
default_branch="${BASE_REF:-main}"
merge_base=""
if command -v git >/dev/null 2>&1 && git rev-parse --git-dir >/dev/null 2>&1; then
  merge_base="$(git merge-base "$default_branch" HEAD 2>/dev/null || echo "")"
  if [ -z "$merge_base" ] && [ "$default_branch" = "main" ]; then
    merge_base="$(git merge-base master HEAD 2>/dev/null || echo "")"
  fi
fi

for f in "$META_DIR"/*.json; do
  [ -f "$f" ] || continue
  # Only files that actually carry a present, non-null created_at_commit.
  if ! jq -e 'type=="object" and has("created_at_commit") and .created_at_commit != null' "$f" >/dev/null 2>&1; then
    continue
  fi
  sha="$(jq -r '.created_at_commit // ""' "$f" 2>/dev/null)"
  [ -n "$sha" ] || continue

  # Unknown/invalid commit — the strongest pollution/corruption signal.
  if command -v git >/dev/null 2>&1 && git rev-parse --git-dir >/dev/null 2>&1; then
    if ! git cat-file -e "${sha}^{commit}" 2>/dev/null; then
      printf 'meta-pollution: %s created_at_commit=%s is not a known commit in this repo (possible corruption)\n' "$f" "$sha"
      continue
    fi
  fi

  # Divergence from the current feature's merge-base (the #226 shape). Advisory:
  # a legitimately different feature baseline also diverges, so this is a prompt
  # for human inspection, not an assertion of pollution.
  if [ -n "$merge_base" ] && [ "$sha" != "$merge_base" ]; then
    printf 'meta-pollution: %s created_at_commit=%s diverges from this feature merge-base %s (verify it belongs to this feature, not a prior /cdocs blanket-scan — #226)\n' "$f" "$sha" "$merge_base"
  fi
done

# Always advisory — never a non-zero gate.
exit 0
