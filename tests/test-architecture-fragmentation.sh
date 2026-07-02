#!/usr/bin/env bash
# ============================================================================
# test-architecture-fragmentation.sh
#
# Structural integrity of the ARCHITECTURE.md "index + body-out" fragmentation:
# every `### XXX-NNN:` heading stays in the root index followed by a markdown
# See-link; entry bodies live in per-section fragments under docs/architecture/.
# PAT-001 and PAT-017 are exempt (already `.claude/rules` index entries) and stay
# whole in root. This test guards the bidirectional root<->fragment mapping,
# See-link resolution, index-only root entries, and the deliberate use of the
# markdown See-link form (kept distinct from the drift test's `.claude/rules`
# backtick grammar so INV-003/004/005 in test-architecture-drift stay scoped to
# rule files).
# ============================================================================

source "$(dirname "${BASH_SOURCE[0]}")/test-helpers.sh"

ARCH_ROOT="$REPO_DIR/.correctless/ARCHITECTURE.md"
FRAG_DIR="$REPO_DIR/docs/architecture"

# section-header -> fragment basename -> ID prefix
declare -A FRAG_FOR_PREFIX=(
  [TB]="trust-boundaries.md"
  [ABS]="abstractions.md"
  [PAT]="patterns.md"
  [ENV]="environment.md"
)
EXEMPT_IDS=" PAT-001 PAT-017 "

# heading_ids FILE -> emit `### `-level entry IDs (e.g. TB-001, TB-004d, ABS-010)
heading_ids() {
  grep -oE '^### (TB|ABS|PAT|ENV)-[0-9]+[a-z]?:' "$1" 2>/dev/null \
    | sed -E 's/^### ([A-Z]+-[0-9]+[a-z]?):/\1/'
}

prefix_of() { echo "${1%%-*}"; }

# ============================================================================
section "INV-F1: all four fragment files exist and are non-empty"
# ============================================================================
for frag in trust-boundaries.md abstractions.md patterns.md environment.md; do
  if [ -s "$FRAG_DIR/$frag" ]; then
    pass "INV-F1($frag)" "fragment exists and is non-empty"
  else
    fail "INV-F1($frag)" "fragment missing or empty: docs/architecture/$frag"
  fi
done

# ============================================================================
section "INV-F2: root retains the four top-level section headers"
# ============================================================================
for hdr in "## Trust Boundaries" "## Abstractions" "## Patterns" "## Environment Assumptions"; do
  if grep -qF "$hdr" "$ARCH_ROOT"; then
    pass "INV-F2" "root has section header: $hdr"
  else
    fail "INV-F2" "root missing section header: $hdr"
  fi
done

# ============================================================================
section "INV-F3: each non-exempt root heading is followed by a resolving See-link"
# ============================================================================
# Walk root: for every `### XXX-NNN:` heading, the immediately following
# non-blank line must be the markdown See-link to the fragment matching the ID
# prefix, and that fragment must exist. Exempt entries are checked separately.
f3_fail=0
while IFS= read -r idline; do
  lineno="${idline%%:*}"
  id="$(sed -E 's/^[0-9]+:### ([A-Z]+-[0-9]+[a-z]?):.*/\1/' <<<"$idline")"
  case "$EXEMPT_IDS" in *" $id "*) continue ;; esac
  prefix="$(prefix_of "$id")"
  want_frag="${FRAG_FOR_PREFIX[$prefix]}"
  # next non-blank line after the heading
  nextline="$(awk -v n="$lineno" 'NR>n && $0 !~ /^[[:space:]]*$/ {print; exit}' "$ARCH_ROOT")"
  expected="See [docs/architecture/${want_frag}](docs/architecture/${want_frag})."
  if [ "$nextline" = "$expected" ]; then
    :
  else
    f3_fail=$((f3_fail + 1))
    fail "INV-F3($id)" "expected See-link '$expected', got '$nextline'"
  fi
done < <(grep -nE '^### (TB|ABS|PAT|ENV)-[0-9]+[a-z]?:' "$ARCH_ROOT")
[ "$f3_fail" -eq 0 ] && pass "INV-F3" "every non-exempt root heading has a resolving markdown See-link"

# ============================================================================
section "INV-F4: bidirectional heading mapping (no orphans, no missing bodies)"
# ============================================================================
# (a) Every fragment heading has a matching root heading.
orphan=0
for frag in trust-boundaries.md abstractions.md patterns.md environment.md; do
  while IFS= read -r fid; do
    [ -z "$fid" ] && continue
    if grep -qE "^### ${fid}:" "$ARCH_ROOT"; then :; else
      orphan=$((orphan + 1)); fail "INV-F4a" "fragment $frag entry $fid has no root heading"
    fi
  done < <(heading_ids "$FRAG_DIR/$frag")
done
[ "$orphan" -eq 0 ] && pass "INV-F4a" "no orphan fragment entries (all map back to a root heading)"

# (b) Every non-exempt root heading has a body in its section fragment.
missing=0
while IFS= read -r id; do
  [ -z "$id" ] && continue
  case "$EXEMPT_IDS" in *" $id "*) continue ;; esac
  prefix="$(prefix_of "$id")"
  frag="${FRAG_FOR_PREFIX[$prefix]}"
  if grep -qE "^### ${id}:" "$FRAG_DIR/$frag"; then :; else
    missing=$((missing + 1)); fail "INV-F4b" "root entry $id has no body in docs/architecture/$frag"
  fi
done < <(heading_ids "$ARCH_ROOT")
[ "$missing" -eq 0 ] && pass "INV-F4b" "every non-exempt root heading has a matching fragment body"

# ============================================================================
section "INV-F5: exempt entries stay whole in root, absent from fragments"
# ============================================================================
for eid in PAT-001 PAT-017; do
  if grep -qE "^### ${eid}:" "$ARCH_ROOT" \
     && grep -A2 -E "^### ${eid}:" "$ARCH_ROOT" | grep -qE 'See `\.claude/rules/[^`]+\.md`\.'; then
    pass "INV-F5($eid)" "$eid keeps its .claude/rules See-link in root"
  else
    fail "INV-F5($eid)" "$eid missing or lost its .claude/rules See-link in root"
  fi
  if grep -qE "^### ${eid}:" "$FRAG_DIR/patterns.md"; then
    fail "INV-F5($eid)" "$eid must NOT be duplicated into the patterns fragment"
  else
    pass "INV-F5($eid)" "$eid is not duplicated into the patterns fragment"
  fi
done

# ============================================================================
section "INV-F6: root non-exempt entries are index-only (no body bullets)"
# ============================================================================
# Between a non-exempt `### ` heading and the next `### `/`## `, the only
# non-blank content must be the See-link — no `- **Field**:` body bullets.
stray=0
while IFS= read -r stray_line; do
  stray=$((stray + 1))
  echo "  offending: $stray_line"
done < <(awk '
  /^### (TB|ABS|PAT|ENV)-[0-9]+[a-z]?:/ {
    hdr=$0
    exempt = (hdr ~ /^### PAT-001:/ || hdr ~ /^### PAT-017:/)
    inentry = !exempt
    next
  }
  /^### / || /^## / { inentry=0 }
  inentry && /^- \*\*/ { print }
' "$ARCH_ROOT")
if [ "$stray" -eq 0 ]; then
  pass "INV-F6" "no body bullets under any non-exempt root heading (index-only)"
else
  fail "INV-F6" "$stray body bullet line(s) found under non-exempt root headings — body leaked into root"
fi

# ============================================================================
section "INV-F7: See-links use markdown form, never the .claude/rules backtick grammar"
# ============================================================================
# The drift test recognizes migrated index entries ONLY via `See \`.claude/rules/...\`.`.
# Fragment See-links MUST use the markdown link form so they stay invisible to
# INV-003/004/005 there. Guard against a `See \`docs/architecture/...\`.` regression.
if grep -qE 'See `docs/architecture/[^`]+`' "$ARCH_ROOT"; then
  fail "INV-F7" "root uses .claude/rules-style backtick See-link for a fragment — would collide with drift grammar"
else
  pass "INV-F7" "fragment See-links use the markdown link form (distinct from drift grammar)"
fi

# ============================================================================
section "INV-F8: Patterns reader-note blockquote present before first PAT entry"
# ============================================================================
if awk '
  /^## Patterns/ { in_section = 1; next }
  in_section && /^### PAT-/ { exit }
  in_section && /^>.*ABS-009/ { found = 1 }
  END { exit found ? 0 : 1 }
' "$ARCH_ROOT"; then
  pass "INV-F8" "Patterns reader-note (referencing ABS-009) retained between ## Patterns and first ### PAT-"
else
  fail "INV-F8" "Patterns reader-note blockquote missing from root"
fi

# ============================================================================
section "INV-F9: fragment ID prefixes match their fragment file"
# ============================================================================
declare -A EXPECT_PREFIX=(
  [trust-boundaries.md]="TB"
  [abstractions.md]="ABS"
  [patterns.md]="PAT"
  [environment.md]="ENV"
)
for frag in trust-boundaries.md abstractions.md patterns.md environment.md; do
  bad=0
  while IFS= read -r fid; do
    [ -z "$fid" ] && continue
    [ "$(prefix_of "$fid")" = "${EXPECT_PREFIX[$frag]}" ] || { bad=$((bad+1)); fail "INV-F9($frag)" "$fid does not belong in $frag"; }
  done < <(heading_ids "$FRAG_DIR/$frag")
  [ "$bad" -eq 0 ] && pass "INV-F9($frag)" "all entries carry the ${EXPECT_PREFIX[$frag]} prefix"
done

# ============================================================================
section "INV-F10: root index stays small (fragmentation achieved its goal)"
# ============================================================================
# The /cupdate-arch fragmentation threshold is ~5000 words; the index must stay
# well under it or the split has regressed.
words="$(wc -w < "$ARCH_ROOT")"
if [ "$words" -lt 5000 ]; then
  pass "INV-F10" "root index is $words words (< 5000 threshold)"
else
  fail "INV-F10" "root index grew to $words words (>= 5000) — bodies may have leaked back"
fi

summary "architecture-fragmentation"
