#!/usr/bin/env bash
# shellcheck disable=SC1090,SC1091,SC2016,SC2086
# Correctless — Design Contract Checker lens registry sync tests
#
# Enforces the design-contract-lens-sync spec (INV-001..010, BND-001,
# PRH-001..002, EA-001..004, R-E). Binds the lens registry
# (agents/design-contract-lenses.tsv) to the enforcing agent
# (agents/review-spec-design-contract.md) by set-equality, validates
# registry well-formedness with a table-driven negative-fixture suite,
# pins the 8-lens seed as anchored rows, and closes the vacuous-pass traps.
#
# Run from repo root: bash tests/test-design-contract-lens-sync.sh
#
# This is the RED-phase structural test. The registry, the agent's
# `## PMB-derived lenses` section, and the /cpostmortem Step-3 note do not
# exist yet, so the real-file assertions MUST fail (correct RED behavior).
# The test-the-test assertions (which validate the checker logic against
# synthetic fixtures) pass in RED, proving the mechanism is non-vacuous.
#
# POSIX-portable externals only (EA-002/ENV-006): grep, awk, sed, sort,
# diff, od, find. NO `\b`, `\s`, `grep -P`, `grep -o`, `grep -w`. All
# whole-word matching and all tab-field work is done in `awk`.
#   - TSV field work: `awk -F'\t'` (awk interprets the tab separator;
#     `grep -E '\t'` treats it as literal backslash-t — CX-007).
#   - id/pattern matching: ERE via `awk` with explicit `[0-9][0-9][0-9]`
#     (equivalent to `{3}`, avoids interval-support ambiguity), so a
#     2-digit `DCL-01` fails (the 3-digit id-length probe — INV-003 fixture (l)).

source "$(dirname "${BASH_SOURCE[0]}")/test-helpers.sh"
set -eo pipefail   # BND-001: set -euo pipefail (helpers already set -u)

# ============================================================================
# File paths (relative to repo root — helpers cd there at source time)
# ============================================================================

REGISTRY="agents/design-contract-lenses.tsv"
AGENT="agents/review-spec-design-contract.md"
MIRROR="correctless/agents/review-spec-design-contract.md"
CREVIEW_SKILL="skills/creview-spec/SKILL.md"
CPM_SKILL="skills/cpostmortem/SKILL.md"

SELF="${BASH_SOURCE[0]}"
[ -f "$SELF" ] || SELF="tests/test-design-contract-lens-sync.sh"

# The exact 8 seed rows (INV-004). Format: lens_id|keyword|source_pmb
SEED=(
  "DCL-001|cardinality|PMB-013"
  "DCL-002|tool-surface|PMB-014"
  "DCL-003|content-fidelity|PMB-015"
  "DCL-004|extraction-rejection|PMB-016"
  "DCL-005|authoring-affordance|PMB-017"
  "DCL-006|gate-scope|PMB-018"
  "DCL-007|unbounded-input-bounded-medium|PMB-019"
  "DCL-008|mechanism-capability-mismatch|PMB-020"
)

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# ============================================================================
# Shared extractors (INV-008a): TWO scopes, ONE token regex
# ============================================================================
# The token grammar `DCL-[0-9][0-9][0-9]` bounded by `[^[:alnum:]_]` or a
# line edge lives in a single place (emit_dcl_tokens) so the two scopes can
# never diverge. `DCL-0031` / `DCL-003a` are rejected by the boundary check.

emit_dcl_tokens() {
  # stdin -> one bounded DCL-NNN token per occurrence (may repeat)
  awk '{
    line = $0
    while (match(line, /DCL-[0-9][0-9][0-9]/)) {
      tok = substr(line, RSTART, RLENGTH)
      before = (RSTART == 1) ? "" : substr(line, RSTART - 1, 1)
      ap = RSTART + RLENGTH
      after = (ap > length(line)) ? "" : substr(line, ap, 1)
      if ((before == "" || before !~ /[[:alnum:]_]/) && \
          (after  == "" || after  !~ /[[:alnum:]_]/)) print tok
      line = substr(line, ap)
    }
  }'
}

# full-file extractor — every DCL-NNN token anywhere in the file
# (INV-002 orphan detection + INV-005 file-wide "exactly once").
extract_dcl_full() {
  [ -f "$1" ] || return 0
  emit_dcl_tokens < "$1"
}

# section-scoped extractor — DCL-NNN tokens on bullet lines inside the
# `## PMB-derived lenses` section only (INV-001, INV-005 per-lens, INV-010).
# Section boundary (RS-008): from `^## PMB-derived lenses` (exclusive) to the
# next `^## ` or EOF; `### ` sub-headings stay inside.
extract_dcl_section() {
  [ -f "$1" ] || return 0
  awk '
    /^## PMB-derived lenses/ { s = 1; next }
    s && /^## / { s = 0 }
    s && /^[[:space:]]*-[[:space:]]/ { print }
  ' "$1" | emit_dcl_tokens
}

# registry lens_id column (data rows only). Handles a missing final newline
# (awk yields the last record without a trailing LF — a naive `while read`
# would drop it — RS-017).
registry_lens_ids() {
  [ -f "$1" ] || return 0
  awk -F'\t' 'NR > 1 && $1 != "" { print $1 }' "$1"
}

# registry (lens_id, keyword) pairs (data rows only), one TAB-joined pair per
# line. Same awk parse + missing-final-newline handling as registry_lens_ids
# (RS-017). This is the iteration source for the INV-005 per-lens substance
# loop, so the substance guarantee extends to EVERY live registry row (spec
# INV-005: "For each registry lens_id, ALL of the following hold") — not just
# the 8 hard-coded seeds (INV-004 owns the seed-completeness pin separately).
registry_lens_pairs() {
  [ -f "$1" ] || return 0
  awk -F'\t' 'NR > 1 && $1 != "" { print $1 "\t" $2 }' "$1"
}

# count of unique non-empty ids on stdin (empty-safe — INV-008b: `wc -l`
# reports 1 for empty input, hence the floor is >= 8, never >= 1)
count_unique_ids() {
  local n
  n="$(sort -u | grep -cE 'DCL-[0-9][0-9][0-9]' || true)"
  printf '%s' "$n"
}

# ============================================================================
# validate_registry <path> — single callable, non-zero + message on any
# INV-003 violation (BND-001). Always invoke inside `if` (set -e safety).
# ============================================================================

validate_registry() {
  local path="$1" expected_header first3 header awk_out
  [ -f "$path" ] || { echo "registry missing: $path"; return 1; }
  [ -s "$path" ] || { echo "registry zero-byte: $path"; return 1; }

  # Encoding: no UTF-8 BOM (portable first-3-byte check EF BB BF)
  first3="$(head -c 3 "$path" | od -An -tx1 | tr -d ' \n' || true)"
  if [ "$first3" = "efbbbf" ]; then
    echo "registry has UTF-8 BOM: $path"; return 1
  fi

  # Line endings: LF-only, no CR
  if LC_ALL=C grep -q $'\r' "$path"; then
    echo "registry has CR/CRLF line endings: $path"; return 1
  fi

  # Header: exactly lens_id<TAB>keyword<TAB>source_pmb<TAB>summary
  printf -v expected_header 'lens_id\tkeyword\tsource_pmb\tsummary'
  header="$(head -n 1 "$path")"
  if [ "$header" != "$expected_header" ]; then
    echo "registry header mismatch: got [$header] (fix: first line must be lens_id<TAB>keyword<TAB>source_pmb<TAB>summary)"; return 1
  fi

  # Rows: no blank/comment lines; exactly 4 fields; non-empty trimmed fields;
  # unique DCL-[0-9]{3} lens_id; PMB-[0-9]{3} source_pmb; >= 1 data row.
  awk_out="$(awk -F'\t' '
    NR == 1 { next }
    {
      rows++
      if ($0 ~ /^[[:space:]]*$/)        { print "blank-line:" NR; bad = 1; next }
      if ($0 ~ /^#/)                    { print "comment-line:" NR; bad = 1; next }
      if (NF != 4)                      { print "field-count:" NR ":NF=" NF; bad = 1; next }
      for (i = 1; i <= 4; i++) {
        f = $i; gsub(/^[[:space:]]+|[[:space:]]+$/, "", f)
        if (f == "") { print "empty-field:" NR ":col" i; bad = 1 }
      }
      if ($1 !~ /^DCL-[0-9][0-9][0-9]$/) { print "bad-lens_id:" NR ":" $1; bad = 1 }
      if ($3 !~ /^PMB-[0-9][0-9][0-9]$/) { print "bad-source_pmb:" NR ":" $3; bad = 1 }
      if (seen[$1]++)                    { print "dup-lens_id:" NR ":" $1; bad = 1 }
    }
    END { if (rows == 0) { print "no-data-rows"; bad = 1 } if (bad) exit 1 }
  ' "$path" 2>/dev/null)" || { echo "registry violations: ${awk_out}"; return 1; }
  return 0
}

# ============================================================================
# awk-based whole-word / body helpers (EA-002 — no grep -w/-o/\b)
# ============================================================================

# awk_has_word <line> <space-separated set> [exclude-span]
# Returns 0 iff any set member is a whole-word token (case-insensitive) in
# <line>, after removing the optional exclude span (RS-002c directive-vs-
# keyword separation). Tokenizes on [^[:alnum:]_]+ and tests set membership.
awk_has_word() {
  local line="$1" want="$2" excl="${3:-}"
  awk -v line="$line" -v want="$want" -v excl="$excl" '
    BEGIN {
      l = tolower(line)
      if (excl != "") { e = tolower(excl); gsub(/[][(){}.^$*+?|\\]/, ".", e); gsub(e, " ", l) }
      nw = split(want, W, " ")
      nt = split(l, T, /[^[:alnum:]_]+/)
      for (i = 1; i <= nt; i++) P[T[i]] = 1
      for (j = 1; j <= nw; j++) if (W[j] in P) exit 0
      exit 1
    }'
}

# body_floor_len <bullet> <dcl> <keyword>
# Prints the count of non-whitespace chars remaining after stripping the
# leading `- `, the DCL token, the keyword span, and the directive terms.
body_floor_len() {
  local bullet="$1" dcl="$2" kw="$3"
  awk -v b="$bullet" -v d="$dcl" -v k="$kw" '
    BEGIN {
      s = b
      sub(/^[[:space:]]*-[[:space:]]*/, "", s)
      gsub(d, "", s)
      gsub(k, "", s)
      lc = tolower(s)
      gsub(/blocking/, "", lc)
      gsub(/flag/, "", lc)
      gsub(/[[:space:]]/, "", lc)
      print length(lc)
    }'
}

# section_bullet_for <dcl> <file> — first section bullet line containing <dcl>
section_bullet_for() {
  local dcl="$1" file="$2"
  [ -f "$file" ] || return 0
  awk -v d="$dcl" '
    /^## PMB-derived lenses/ { s = 1; next }
    s && /^## / { s = 0 }
    s && /^[[:space:]]*-[[:space:]]/ && index($0, d) > 0 { print; exit }
  ' "$file"
}

# lens_bullet_ok <dcl> <keyword> <file> — INV-005 legs (returns 0/1)
lens_bullet_ok() {
  local dcl="$1" kw="$2" file="$3" full_cnt bullet blen
  full_cnt="$(extract_dcl_full "$file" | grep -Fx "$dcl" | grep -c . || true)"
  [ "$full_cnt" -eq 1 ] || return 1                       # exactly once in whole file
  bullet="$(section_bullet_for "$dcl" "$file")"
  [ -n "$bullet" ] || return 1                            # inside section, on a bullet
  grep -qF "$kw" <<<"$bullet" || return 1                 # keyword verbatim
  awk_has_word "$bullet" "blocking flag" "$kw" || return 1  # directive (excl keyword span)
  awk_has_word "$bullet" "when if" "" || return 1         # condition token
  blen="$(body_floor_len "$bullet" "$dcl" "$kw")"
  [ "$blen" -ge 24 ] || return 1                          # post-strip body floor
  return 0
}

# ============================================================================
# Synthetic fixture builders (for the rejection + test-the-test paths)
# ============================================================================

# make_valid_registry <path> [notrail]
make_valid_registry() {
  local out="$1" notrail="${2:-}"
  {
    printf 'lens_id\tkeyword\tsource_pmb\tsummary\n'
    printf 'DCL-001\tcardinality\tPMB-013\tPin implementation-level cardinality\n'
    printf 'DCL-002\ttool-surface\tPMB-014\tPin tool surface and shared substrate\n'
    printf 'DCL-003\tcontent-fidelity\tPMB-015\tDerived artifact reflects source\n'
    printf 'DCL-004\textraction-rejection\tPMB-016\tExtractor names rejects\n'
    printf 'DCL-005\tauthoring-affordance\tPMB-017\tGuard has a legitimate-edit affordance\n'
    printf 'DCL-006\tgate-scope\tPMB-018\tPre-deliver gate superset of CI gate\n'
    printf 'DCL-007\tunbounded-input-bounded-medium\tPMB-019\tNo unbounded data through argv\n'
    if [ "$notrail" = "notrail" ]; then
      printf 'DCL-008\tmechanism-capability-mismatch\tPMB-020\tThreat model matches enforcement layer'
    else
      printf 'DCL-008\tmechanism-capability-mismatch\tPMB-020\tThreat model matches enforcement layer\n'
    fi
  } > "$out"
}

# make_synth_agent <path> [heading] — a well-formed agent with a valid
# `## PMB-derived lenses` section (8 bullets satisfying every INV-005 leg,
# incl. the DCL-002 dual-marker). Optional first arg overrides the heading
# text for the vacuity (heading-rename) test.
make_synth_agent() {
  local out="$1" heading="${2:-## PMB-derived lenses}"
  {
    printf '# Design Contract Checker — synthetic fixture\n\n'
    printf '%s\n\n' "$heading"
    printf 'Row-format template: `DCL-NNN<TAB>keyword<TAB>PMB-xxx`. Next id: `DCL-<next>`.\n\n'
    printf -- '- DCL-001 cardinality: mark BLOCKING when a spec pins parallel arrays or lockstep sets without a cardinality assertion clause tying their lengths together.\n'
    printf -- '- DCL-002 tool-surface: flag as BLOCKING when concurrent subagents share a mutable substrate without isolation, or a tool surface is prose-pinned only.\n'
    printf -- '- DCL-003 content-fidelity: flag BLOCKING when a gate runs on a derived artifact without an invariant that the copy reflects the source content.\n'
    printf -- '- DCL-004 extraction-rejection: flag BLOCKING when an extraction primitive over a prose document names no adversarial substrings it must reject.\n'
    printf -- '- DCL-005 authoring-affordance: flag BLOCKING when a protection mechanism is added without naming how the protected asset is developed thereafter.\n'
    printf -- '- DCL-006 gate-scope: mark BLOCKING when a pre-deliver gate runs a strict subset of the post-deliver CI gate without a superset invariant.\n'
    printf -- '- DCL-007 unbounded-input-bounded-medium: flag BLOCKING when unbounded filesystem data flows into a bounded medium such as argv without naming the bound.\n'
    printf -- '- DCL-008 mechanism-capability-mismatch: flag BLOCKING when a mechanism is assigned a threat model its enforcement layer cannot structurally deliver.\n'
  } > "$out"
}

# ============================================================================
# BND-001 / preflight: registry + agent exist, fail-closed
# ============================================================================

check_preflight() {
  section "BND-001: preflight (registry + agent exist, fail closed)"

  if [ -f "$REGISTRY" ]; then
    pass "BND-001(registry-exists)" "$REGISTRY exists"
  else
    fail "BND-001(registry-exists)" "$REGISTRY is missing — create the 8-row TSV registry (fail-closed)"
  fi

  if [ -f "$AGENT" ]; then
    pass "BND-001(agent-exists)" "$AGENT exists"
  else
    fail "BND-001(agent-exists)" "$AGENT is missing (fail-closed)"
  fi
}

# ============================================================================
# INV-003 positive: real registry validates
# ============================================================================

check_inv003_positive() {
  section "INV-003: registry well-formedness (real file)"

  local msg
  if msg="$(validate_registry "$REGISTRY" 2>&1)"; then
    pass "INV-003(real)" "$REGISTRY passes validate_registry"
  else
    fail "INV-003(real)" "$REGISTRY failed validate_registry: ${msg}"
  fi
}

# ============================================================================
# INV-003 negative: table-driven malformed fixtures (a)-(o)
# ============================================================================

expect_reject() {
  local id="$1" f="$2" desc="$3"
  if validate_registry "$f" >/dev/null 2>&1; then
    fail "$id" "validate_registry ACCEPTED malformed registry: $desc"
  else
    pass "$id" "validate_registry rejected: $desc"
  fi
}

check_inv003_negative() {
  section "INV-003/BND-001: rejection suite (synthetic malformed fixtures)"

  local base="$TMP/base.tsv"
  make_valid_registry "$base"

  # (a) missing file
  expect_reject "INV-003(a-missing)" "$TMP/does-not-exist.tsv" "(a) missing file"

  # (b) zero-byte file
  : > "$TMP/zero.tsv"
  expect_reject "INV-003(b-zerobyte)" "$TMP/zero.tsv" "(b) zero-byte file"

  # (c) header-only file
  printf 'lens_id\tkeyword\tsource_pmb\tsummary\n' > "$TMP/header-only.tsv"
  expect_reject "INV-003(c-header-only)" "$TMP/header-only.tsv" "(c) header-only (no data rows)"

  # (d) leading BOM
  { printf '\xef\xbb\xbf'; cat "$base"; } > "$TMP/bom.tsv"
  expect_reject "INV-003(d-bom)" "$TMP/bom.tsv" "(d) leading UTF-8 BOM"

  # (e) a CRLF row
  { head -n 8 "$base"; printf 'DCL-008\tmechanism-capability-mismatch\tPMB-020\tsummary\r\n'; } > "$TMP/crlf.tsv"
  expect_reject "INV-003(e-crlf)" "$TMP/crlf.tsv" "(e) CRLF row"

  # (f) embedded tab -> NF==5
  { head -n 1 "$base"; printf 'DCL-001\tcardinality\tPMB-013\tsum\twith-tab\n'; } > "$TMP/embtab.tsv"
  expect_reject "INV-003(f-embedded-tab)" "$TMP/embtab.tsv" "(f) embedded tab (NF==5)"

  # (g) 3-field row
  { head -n 1 "$base"; printf 'DCL-001\tcardinality\tPMB-013\n'; } > "$TMP/threefield.tsv"
  expect_reject "INV-003(g-3field)" "$TMP/threefield.tsv" "(g) 3-field row"

  # (h) whitespace-only field
  { head -n 1 "$base"; printf 'DCL-001\t \tPMB-013\tsummary\n'; } > "$TMP/wsfield.tsv"
  expect_reject "INV-003(h-ws-field)" "$TMP/wsfield.tsv" "(h) whitespace-only field"

  # (i) a #-comment line
  { head -n 1 "$base"; printf '# a comment line\n'; tail -n +2 "$base"; } > "$TMP/comment.tsv"
  expect_reject "INV-003(i-comment)" "$TMP/comment.tsv" "(i) #-comment line"

  # (j) blank interior line
  { head -n 3 "$base"; printf '\n'; tail -n +4 "$base"; } > "$TMP/blankint.tsv"
  expect_reject "INV-003(j-blank-interior)" "$TMP/blankint.tsv" "(j) blank interior line"

  # (k) duplicate DCL-001
  { cat "$base"; printf 'DCL-001\tcardinality\tPMB-013\tdup\n'; } > "$TMP/dup.tsv"
  expect_reject "INV-003(k-dup)" "$TMP/dup.tsv" "(k) duplicate DCL-001"

  # (l) lens_id=DCL-01 (2 digits — the 3-digit id-length probe)
  { head -n 1 "$base"; printf 'DCL-01\tcardinality\tPMB-013\tsummary\n'; } > "$TMP/twodigit.tsv"
  expect_reject "INV-003(l-2digit)" "$TMP/twodigit.tsv" "(l) DCL-01 2-digit id (3-digit id-length probe)"

  # (m) source_pmb=PMB-9
  { head -n 1 "$base"; printf 'DCL-001\tcardinality\tPMB-9\tsummary\n'; } > "$TMP/pmb9.tsv"
  expect_reject "INV-003(m-pmb9)" "$TMP/pmb9.tsv" "(m) PMB-9 short source_pmb"

  # (n) wrong header + valid data rows
  { printf 'id\tkw\tpmb\tdesc\n'; tail -n +2 "$base"; } > "$TMP/wronghdr.tsv"
  expect_reject "INV-003(n-wrong-header)" "$TMP/wronghdr.tsv" "(n) wrong header + valid rows"

  # (o) trailing blank line (distinct from interior blank)
  { cat "$base"; printf '\n'; } > "$TMP/trailblank.tsv"
  expect_reject "INV-003(o-trailing-blank)" "$TMP/trailblank.tsv" "(o) trailing blank line"
}

# ============================================================================
# INV-003 / CX-003 positive parse robustness: 8-row, NO final newline
# ============================================================================

check_inv003_no_newline() {
  section "INV-003/CX-003: 8-row registry with no final newline"

  local f="$TMP/no-newline.tsv"
  make_valid_registry "$f" notrail

  if validate_registry "$f" >/dev/null 2>&1; then
    pass "INV-003(no-nl:valid)" "no-final-newline registry passes validate_registry"
  else
    fail "INV-003(no-nl:valid)" "no-final-newline registry wrongly rejected"
  fi

  local cnt
  cnt="$(registry_lens_ids "$f" | count_unique_ids)"
  if [ "$cnt" -eq 8 ]; then
    pass "INV-003(no-nl:count)" "extractor read all 8 rows despite missing final newline"
  else
    fail "INV-003(no-nl:count)" "extractor read $cnt rows (expected 8 — last row dropped?)"
  fi
}

# ============================================================================
# INV-004: seed completeness — 8 anchored rows via awk field equality
# ============================================================================

check_inv004_seed() {
  section "INV-004: 8 seed rows present (anchored awk field equality)"

  local entry d k p matches
  for entry in "${SEED[@]}"; do
    IFS='|' read -r d k p <<<"$entry"
    if [ ! -f "$REGISTRY" ]; then
      fail "INV-004($d)" "$REGISTRY missing — cannot verify seed row $d/$k/$p"
      continue
    fi
    # awk -F'\t' field equality — grep -E cannot match a literal \t (CX-007)
    matches="$(awk -F'\t' -v d="$d" -v k="$k" -v p="$p" \
      '$1==d && $2==k && $3==p && NF==4' "$REGISTRY" 2>/dev/null | grep -c . || true)"
    if [ "$matches" -eq 1 ]; then
      pass "INV-004($d)" "exactly one row: $d / $k / $p (NF==4)"
    else
      fail "INV-004($d)" "expected exactly 1 row for $d / $k / $p, found $matches (fix: add/repair the seed row)"
    fi
  done
}

# ============================================================================
# INV-001 / INV-002 / INV-008: set-equality with non-vacuity guards
# ============================================================================

check_setequality() {
  section "INV-001/INV-002/INV-008: registry<->agent set-equality (guarded)"

  local reg_cnt full_cnt sec_cnt
  reg_cnt="$(registry_lens_ids "$REGISTRY" | count_unique_ids)"
  full_cnt="$(extract_dcl_full "$AGENT" | count_unique_ids)"
  sec_cnt="$(extract_dcl_section "$AGENT" | count_unique_ids)"

  # INV-008 non-vacuity guards (>= 8) on every extractor BEFORE comparison
  if [ "$reg_cnt" -ge 8 ]; then
    pass "INV-008(registry>=8)" "registry has $reg_cnt lens ids (>= 8)"
  else
    fail "INV-008(registry>=8)" "registry extractor found $reg_cnt ids (< 8) — registry missing/renamed or empty"
  fi
  if [ "$full_cnt" -ge 8 ]; then
    pass "INV-008(agent-full>=8)" "agent full-file scan found $full_cnt ids (>= 8)"
  else
    fail "INV-008(agent-full>=8)" "agent full-file scan found $full_cnt ids (< 8) — section may be renamed or file moved"
  fi
  if [ "$sec_cnt" -ge 8 ]; then
    pass "INV-008(agent-section>=8)" "agent section scan found $sec_cnt ids (>= 8)"
  else
    fail "INV-008(agent-section>=8)" "agent section scan found $sec_cnt ids (< 8) — '## PMB-derived lenses' section missing/empty"
  fi

  # Only run set comparisons when both sides cleared the guard.
  if [ "$reg_cnt" -ge 8 ] && [ "$sec_cnt" -ge 8 ]; then
    local reg_ids sec_ids
    reg_ids="$(registry_lens_ids "$REGISTRY" | sort -u)"
    sec_ids="$(extract_dcl_section "$AGENT" | sort -u)"

    # INV-001: every registry lens_id referenced in the agent section
    if diff <(printf '%s\n' "$reg_ids") <(printf '%s\n' "$sec_ids") >/dev/null 2>&1; then
      pass "INV-001(complete)" "every registry lens_id is referenced in the agent section"
    else
      local missing
      missing="$(comm -23 <(printf '%s\n' "$reg_ids") <(printf '%s\n' "$sec_ids") | tr '\n' ' ' || true)"
      fail "INV-001(complete)" "registry lens ids absent from agent section: ${missing}(fix: add a DCL bullet to '## PMB-derived lenses')"
    fi
  else
    fail "INV-001(complete)" "cannot compare — extractor(s) below the >= 8 non-vacuity floor"
  fi

  # INV-002: every agent DCL token (full-file scope) has a registry row
  if [ "$reg_cnt" -ge 8 ] && [ "$full_cnt" -ge 8 ]; then
    local reg_ids full_ids orphans
    reg_ids="$(registry_lens_ids "$REGISTRY" | sort -u)"
    full_ids="$(extract_dcl_full "$AGENT" | sort -u)"
    orphans="$(comm -13 <(printf '%s\n' "$reg_ids") <(printf '%s\n' "$full_ids") | tr '\n' ' ' || true)"
    if [ -z "${orphans// /}" ]; then
      pass "INV-002(no-orphans)" "no agent DCL token lacks a registry row (full-file scope)"
    else
      fail "INV-002(no-orphans)" "orphan agent DCL tokens with no registry row: ${orphans}"
    fi
  else
    fail "INV-002(no-orphans)" "cannot compare — extractor(s) below the >= 8 non-vacuity floor"
  fi
}

# ============================================================================
# INV-005: agent lenses anchored, keyword-bound, with a condition + body
# ============================================================================

check_inv005() {
  section "INV-005: agent lens bullets are substantive and anchored"

  # Spec INV-005: "For each registry lens_id, ALL of the following hold." The
  # substance legs therefore iterate the LIVE registry rows (parsed from the
  # real TSV), NOT the hard-coded 8-row SEED — so a future DCL-009+ row that
  # satisfies set-equality (INV-001/INV-002) but carries a keywordless or
  # bodyless bullet is still caught here. INV-004 keeps its own anchored seed
  # assertions for seed-completeness; this loop is the per-registry-row leg.
  if [ ! -f "$REGISTRY" ]; then
    fail "INV-005(registry)" "$REGISTRY missing — cannot iterate registry lens ids for the per-lens substance checks (fail-closed)"
    return
  fi

  # Non-vacuity guard (BND-001): the iteration source must yield >= 8 rows,
  # else a silently-empty registry would make this whole loop a no-op pass.
  local pair_cnt
  pair_cnt="$(registry_lens_pairs "$REGISTRY" | awk -F'\t' '$1 != ""' | grep -cE 'DCL-[0-9][0-9][0-9]' || true)"
  if [ "$pair_cnt" -ge 8 ]; then
    pass "INV-005(rows>=8)" "registry_lens_pairs yields $pair_cnt lens rows (>= 8) to substance-check"
  else
    fail "INV-005(rows>=8)" "registry_lens_pairs yielded $pair_cnt rows (< 8) — registry missing/renamed or empty (fail-closed)"
  fi

  local d k
  while IFS=$'\t' read -r d k; do
    [ -n "$d" ] || continue
    if lens_bullet_ok "$d" "$k" "$AGENT"; then
      pass "INV-005($d)" "bullet is unique, in-section, keyword-bound ($k), directive + condition + body floor"
    else
      fail "INV-005($d)" "bullet for $d fails a leg (once/in-section/keyword=$k/directive/when-if/body>=24)"
    fi
  done < <(registry_lens_pairs "$REGISTRY")

  # DCL-002 dual-condition pin (CX-004): tool-surface marker AND a
  # concurrency/shared-substrate marker on the same bullet.
  local bullet002
  bullet002="$(section_bullet_for "DCL-002" "$AGENT")"
  if [ -n "$bullet002" ] && awk_has_word "$bullet002" "concurrent concurrency shared substrate isolation" ""; then
    pass "INV-005(DCL-002-dual)" "DCL-002 bullet carries a concurrency/shared-substrate marker"
  else
    fail "INV-005(DCL-002-dual)" "DCL-002 bullet lacks a concurrency/shared-substrate marker (concurrent|shared|substrate|isolation)"
  fi
}

# ============================================================================
# INV-006: cpostmortem convention wired inside Step 3, <= 10 lines apart
# ============================================================================

check_inv006() {
  section "INV-006: /cpostmortem Step-3 convention note"

  if [ ! -f "$CPM_SKILL" ]; then
    fail "INV-006(exists)" "$CPM_SKILL does not exist"
    return
  fi

  local line_path line_dir
  line_path="$(awk '
    /^### Step 3:/ { s = 1 }
    s && /^### Step [0-9]/ && !/^### Step 3:/ { s = 0 }
    s && /^## / { s = 0 }
    s && index($0, "agents/design-contract-lenses.tsv") > 0 { print NR; exit }
  ' "$CPM_SKILL")"
  line_dir="$(awk '
    /^### Step 3:/ { s = 1 }
    s && /^### Step [0-9]/ && !/^### Step 3:/ { s = 0 }
    s && /^## / { s = 0 }
    s && $0 ~ /Design Contract Checker lens/ { print NR; exit }
  ' "$CPM_SKILL")"

  if [ -n "$line_path" ] && [ -n "$line_dir" ]; then
    local d
    d=$(( line_path > line_dir ? line_path - line_dir : line_dir - line_path ))
    if [ "$d" -le 10 ]; then
      pass "INV-006(proximity)" "both substrings present in Step 3, $d lines apart (<= 10)"
    else
      fail "INV-006(proximity)" "substrings are $d lines apart in Step 3 (> 10)"
    fi
  else
    fail "INV-006(present)" "Step 3 missing registry path (@${line_path:-none}) and/or 'Design Contract Checker lens' (@${line_dir:-none})"
  fi
}

# ============================================================================
# INV-007: no guidance-file coupling (agent + preamble region), fail-closed
# ============================================================================

# preamble_region_ok <file> — 0 iff the anchor line is present AND the
# blockquote file-load region contains no guidance-file reference.
# Fail-closed (return 1) if the anchor is absent (CX-006).
preamble_region_ok() {
  local file="$1" region
  [ -f "$file" ] || return 1
  region="$(awk '
    /^> Before starting your review, read these files in order:/ { a = 1 }
    a == 1 { if ($0 !~ /^>/) exit; print }
  ' "$file")"
  [ -n "$region" ] || return 1                    # fail-closed: anchor absent
  if grep -q 'CLAUDE.md' <<<"$region"; then       # whitelisted needle (PRH-001)
    return 1
  fi
  return 0
}

check_inv007() {
  section "INV-007: no guidance-file coupling (agent + preamble)"

  # (a) agent file references the guidance file zero times
  if [ -f "$AGENT" ]; then
    local agent_ref
    agent_ref="$(grep -c 'CLAUDE.md' agents/review-spec-design-contract.md 2>/dev/null || true)"
    if [ "$agent_ref" -eq 0 ]; then
      pass "INV-007(a)" "agent has zero guidance-file references"
    else
      fail "INV-007(a)" "agent has $agent_ref guidance-file reference(s) — remove them (ABS-010/AP-013)"
    fi
  else
    fail "INV-007(a)" "$AGENT missing"
  fi

  # (b) preamble file-load region excludes the guidance file (fail-closed)
  if preamble_region_ok "$CREVIEW_SKILL"; then
    pass "INV-007(b)" "preamble file-load region is clean (anchor present, no guidance-file ref)"
  else
    fail "INV-007(b)" "preamble region absent (fail-closed) or contains a guidance-file ref in $CREVIEW_SKILL"
  fi

  # (b:test-the-test) inject a guidance-file ref into a fixture copy -> must be caught
  local injval fx_inject
  injval="CLAUDE"".md"                             # constructed token; no contiguous literal in source
  fx_inject="$TMP/preamble-inject.md"
  {
    printf '> Before starting your review, read these files in order:\n'
    printf '> 1. `.correctless/AGENT_CONTEXT.md`\n'
    printf '> 6. `%s` — should be rejected\n' "$injval"
    printf '\nsome following prose\n'
  } > "$fx_inject"
  if preamble_region_ok "$fx_inject"; then
    fail "INV-007(b:inject)" "injected guidance-file ref NOT caught (check is vacuous)"
  else
    pass "INV-007(b:inject)" "injected guidance-file ref correctly caught"
  fi

  # (b:fail-closed) anchor absent -> must fail closed, never vacuously pass
  local fx_noanchor="$TMP/preamble-noanchor.md"
  {
    printf '> some unrelated blockquote line\n'
    printf '> 1. `.correctless/AGENT_CONTEXT.md`\n'
  } > "$fx_noanchor"
  if preamble_region_ok "$fx_noanchor"; then
    fail "INV-007(b:closed)" "missing anchor passed vacuously (should fail closed)"
  else
    pass "INV-007(b:closed)" "missing anchor fails closed"
  fi
}

# ============================================================================
# INV-009: registry is source-only — absent from the distribution mirror
# ============================================================================

check_inv009() {
  section "INV-009: registry absent from correctless/ (property-general)"

  if find correctless/ -name 'design-contract-lenses.tsv' -print -quit 2>/dev/null | grep -q .; then
    fail "INV-009(source-only)" "design-contract-lenses.tsv found under correctless/ — registry must stay source-only (DD-001)"
  else
    pass "INV-009(source-only)" "no design-contract-lenses.tsv anywhere under correctless/"
  fi
}

# ============================================================================
# INV-010: mirror agent stays in DCL-sync with source (own >= 8 guard)
# ============================================================================

check_inv010() {
  section "INV-010: mirror <-> source DCL-set parity (own guard)"

  local src_cnt mir_cnt
  src_cnt="$(extract_dcl_section "$AGENT" | count_unique_ids)"
  mir_cnt="$(extract_dcl_section "$MIRROR" | count_unique_ids)"

  if [ "$src_cnt" -ge 8 ] && [ "$mir_cnt" -ge 8 ]; then
    local src_ids mir_ids
    src_ids="$(extract_dcl_section "$AGENT" | sort -u)"
    mir_ids="$(extract_dcl_section "$MIRROR" | sort -u)"
    if diff <(printf '%s\n' "$src_ids") <(printf '%s\n' "$mir_ids") >/dev/null 2>&1; then
      pass "INV-010(parity)" "mirror and source reference the identical DCL set"
    else
      fail "INV-010(parity)" "mirror DCL set diverges from source — run 'bash sync.sh'"
    fi
  else
    fail "INV-010(guard)" "extractor below >= 8 floor (src=$src_cnt mirror=$mir_cnt) — section missing or mirror unsynced ('bash sync.sh')"
  fi
}

# ============================================================================
# R-E / CX2-4: section intro template uses non-numeric DCL placeholders only
# ============================================================================

check_re_placeholder() {
  section "R-E: section intro uses only non-numeric DCL placeholders"

  if [ ! -f "$AGENT" ]; then
    fail "R-E(exists)" "$AGENT missing — cannot check placeholder template"
    return
  fi

  # Intro = section lines before the first bullet.
  local intro
  intro="$(awk '
    /^## PMB-derived lenses/ { s = 1; next }
    s && /^## / { s = 0 }
    s && /^[[:space:]]*-[[:space:]]/ { exit }
    s { print }
  ' "$AGENT")"

  if grep -qE 'DCL-(NNN|<[a-z]|N)' <<<"$intro"; then
    pass "R-E(placeholder)" "intro template uses a non-numeric DCL placeholder (DCL-NNN / DCL-<next>)"
  else
    fail "R-E(placeholder)" "intro template has no non-numeric DCL placeholder (add 'DCL-NNN' or 'DCL-<next>')"
  fi

  if grep -qE 'DCL-[0-9][0-9][0-9]' <<<"$intro"; then
    fail "R-E(no-numeric)" "intro template contains a numeric DCL-0xx literal — would collide with the exactly-once scan"
  else
    pass "R-E(no-numeric)" "intro template contains no numeric DCL literal"
  fi
}

# ============================================================================
# Test-the-test: non-vacuity of the extractors + INV-005 legs (synthetic)
# ============================================================================

check_ttt_extractors() {
  section "TTT: extractor + validator non-vacuity (synthetic fixtures)"

  local sa="$TMP/synth-agent.md"
  make_synth_agent "$sa"

  # Section extractor finds all 8 synthetic ids
  local sec_cnt full_cnt
  sec_cnt="$(extract_dcl_section "$sa" | count_unique_ids)"
  full_cnt="$(extract_dcl_full "$sa" | count_unique_ids)"
  if [ "$sec_cnt" -eq 8 ]; then
    pass "TTT(section=8)" "section extractor finds 8 ids in the synthetic agent"
  else
    fail "TTT(section=8)" "section extractor found $sec_cnt in synthetic agent (expected 8) — extractor is broken"
  fi
  if [ "$full_cnt" -eq 8 ]; then
    pass "TTT(full=8)" "full-file extractor finds 8 ids in the synthetic agent"
  else
    fail "TTT(full=8)" "full-file extractor found $full_cnt (expected 8)"
  fi

  # INV-005 validator ACCEPTS a well-formed synthetic bullet
  if lens_bullet_ok "DCL-001" "cardinality" "$sa"; then
    pass "TTT(inv005-accept)" "lens_bullet_ok accepts a well-formed synthetic bullet"
  else
    fail "TTT(inv005-accept)" "lens_bullet_ok rejected a valid synthetic bullet — validator too strict"
  fi

  # INV-005 validator REJECTS the bare stub `- DCL-003 content-fidelity: flag`
  local stub="- DCL-003 content-fidelity: flag"
  local blen
  blen="$(body_floor_len "$stub" "DCL-003" "content-fidelity")"
  if [ "$blen" -lt 24 ] && ! awk_has_word "$stub" "when if" ""; then
    pass "TTT(inv005-stub)" "bare stub fails body floor ($blen < 24) and has no when/if condition"
  else
    fail "TTT(inv005-stub)" "bare stub NOT rejected (body=$blen) — INV-005 gameable"
  fi

  # DCL-002 dual-marker present in synthetic bullet
  local b002
  b002="$(section_bullet_for "DCL-002" "$sa")"
  if awk_has_word "$b002" "concurrent concurrency shared substrate isolation" ""; then
    pass "TTT(dcl002-marker)" "synthetic DCL-002 bullet carries the concurrency marker"
  else
    fail "TTT(dcl002-marker)" "synthetic DCL-002 bullet missing concurrency marker — checker broken"
  fi

  # Set-equality logic works on a synthetic matched pair (non-empty, equal)
  local sr="$TMP/synth-reg.tsv"
  make_valid_registry "$sr"
  local rids sids
  rids="$(registry_lens_ids "$sr" | sort -u)"
  sids="$(extract_dcl_section "$sa" | sort -u)"
  if diff <(printf '%s\n' "$rids") <(printf '%s\n' "$sids") >/dev/null 2>&1; then
    pass "TTT(setequal)" "set-equality logic reports equal on a matched synthetic pair"
  else
    fail "TTT(setequal)" "set-equality logic wrong on a matched synthetic pair"
  fi
}

# ============================================================================
# Test-the-test / vacuity (INV-008): heading rename empties the extractor
# ============================================================================

check_ttt_vacuity() {
  section "TTT: vacuity trap — renamed heading empties section extractor"

  local renamed="$TMP/synth-agent-renamed.md"
  make_synth_agent "$renamed" "## Renamed lenses"

  local cnt
  cnt="$(extract_dcl_section "$renamed" | count_unique_ids)"
  if [ "$cnt" -eq 0 ]; then
    pass "TTT(vacuity)" "renamed heading -> section extractor yields 0 (the >= 8 guard would fire)"
  else
    fail "TTT(vacuity)" "renamed heading still yielded $cnt ids — section boundary is wrong (extractor would pass vacuously)"
  fi

  # And a broken registry separator (spaces, not tabs) must be rejected.
  local badreg="$TMP/badsep.tsv"
  { printf 'lens_id keyword source_pmb summary\n'; printf 'DCL-001 cardinality PMB-013 x\n'; } > "$badreg"
  if validate_registry "$badreg" >/dev/null 2>&1; then
    fail "TTT(sep)" "space-separated (non-TSV) registry wrongly accepted — separator not enforced"
  else
    pass "TTT(sep)" "space-separated (non-TSV) registry rejected by validate_registry"
  fi
}

# ============================================================================
# Test-the-test: two-extractor scope divergence (INV-002 / INV-008a / CX-001)
# Proves the full-file scope catches an out-of-section orphan that the
# section scope must NOT see — the whole reason two extractors exist.
# ============================================================================

check_ttt_scopes() {
  section "TTT: two-extractor scope divergence (out-of-section orphan)"

  local sa="$TMP/synth-agent-orphan.md"
  make_synth_agent "$sa"
  # Append an orphan DCL-999 bullet UNDER A DIFFERENT heading (out of section).
  {
    printf '\n## Other section\n\n'
    printf -- '- DCL-999 orphan lens deliberately placed outside the PMB-derived section.\n'
  } >> "$sa"

  # Capture then match via herestring (no `producer | grep -q` — avoids the
  # AP-033 SIGPIPE flake under pipefail).
  local full_out sec_out
  full_out="$(extract_dcl_full "$sa")"
  sec_out="$(extract_dcl_section "$sa")"

  if grep -Fxq "DCL-999" <<<"$full_out"; then
    pass "TTT(orphan-full)" "full-file extractor sees the out-of-section DCL-999"
  else
    fail "TTT(orphan-full)" "full-file extractor missed the out-of-section DCL-999"
  fi

  if grep -Fxq "DCL-999" <<<"$sec_out"; then
    fail "TTT(orphan-section)" "section extractor wrongly saw the out-of-section DCL-999 (scopes do not differ)"
  else
    pass "TTT(orphan-section)" "section extractor correctly ignores the out-of-section DCL-999"
  fi

  # The orphan must surface via the same comm -13 the real INV-002 uses.
  local sr="$TMP/synth-reg-orphan.tsv"
  make_valid_registry "$sr"
  local reg_ids full_ids orphans
  reg_ids="$(registry_lens_ids "$sr" | sort -u)"
  full_ids="$(printf '%s\n' "$full_out" | sort -u)"
  orphans="$(comm -13 <(printf '%s\n' "$reg_ids") <(printf '%s\n' "$full_ids") | tr '\n' ' ' || true)"
  case " $orphans " in
    *" DCL-999 "*) pass "TTT(orphan-comm)" "comm -13 (registry vs full-file) surfaces DCL-999 — INV-002 catches it" ;;
    *)             fail "TTT(orphan-comm)" "comm -13 did not surface DCL-999 (orphans=[${orphans}])" ;;
  esac
}

# ============================================================================
# Test-the-test: end-to-end bare-stub rejection through lens_bullet_ok
# Catches a future refactor that drops the condition/body legs.
# ============================================================================

check_ttt_stub_e2e() {
  section "TTT: end-to-end bare-stub rejection via lens_bullet_ok"

  local sf="$TMP/synth-agent-stub.md"
  {
    printf '# stub fixture\n\n## PMB-derived lenses\n\n'
    printf -- '- DCL-003 content-fidelity: flag\n'
  } > "$sf"

  if lens_bullet_ok "DCL-003" "content-fidelity" "$sf"; then
    fail "TTT(stub-e2e)" "lens_bullet_ok ACCEPTED the bare stub '- DCL-003 content-fidelity: flag'"
  else
    pass "TTT(stub-e2e)" "lens_bullet_ok rejects the bare stub end-to-end (no condition / no body)"
  fi
}

# ============================================================================
# Test-the-test: INV-005 substance checks iterate the LIVE registry, not the
# 8 hard-coded seeds (QA-003). Builds a 9-row registry (8 seeds + a non-seed
# DCL-009) plus an agent whose DCL-009 bullet is MALFORMED, and proves the
# registry-driven substance leg genuinely evaluates the non-seed row. Uses the
# same callable helpers the real check_inv005 loop uses — registry_lens_pairs
# (iteration source) + lens_bullet_ok (the per-lens leg) — no divergent copy.
# ============================================================================

check_ttt_registry_iteration() {
  section "TTT: INV-005 substance loop iterates the live registry past the seeds"

  # 9-row registry: the 8 seeds + a non-seed DCL-009 row (PMB-021).
  local sr="$TMP/synth-reg-9.tsv"
  make_valid_registry "$sr"
  printf 'DCL-009\tsome-keyword\tPMB-021\tsummary\n' >> "$sr"

  # Sanity: the iteration source actually surfaces all 9 rows (incl. DCL-009).
  local pair_ids
  pair_ids="$(registry_lens_pairs "$sr" | awk -F'\t' '{print $1}' | sort -u | grep -cE 'DCL-[0-9][0-9][0-9]' || true)"
  if [ "$pair_ids" -eq 9 ]; then
    pass "TTT(reg-iter:9rows)" "registry_lens_pairs yields all 9 rows (8 seeds + non-seed DCL-009)"
  else
    fail "TTT(reg-iter:9rows)" "registry_lens_pairs yielded $pair_ids ids (expected 9) — iteration source drops rows"
  fi

  # --- negative: a MALFORMED non-seed DCL-009 bullet must FAIL the leg ---
  # 8 well-formed seed bullets, then a keywordless/conditionless/short DCL-009.
  local bad="$TMP/synth-agent-dcl009-bad.md"
  make_synth_agent "$bad"
  printf -- '- DCL-009: flag this\n' >> "$bad"

  # Iterate the LIVE 9-row registry exactly as check_inv005 does; bucket outcomes.
  local d k bad_fail_009=1 bad_seed_fail=0
  while IFS=$'\t' read -r d k; do
    [ -n "$d" ] || continue
    if ! lens_bullet_ok "$d" "$k" "$bad"; then
      if [ "$d" = "DCL-009" ]; then bad_fail_009=0; else bad_seed_fail=1; fi
    fi
  done < <(registry_lens_pairs "$sr")

  if [ "$bad_fail_009" -eq 0 ]; then
    pass "TTT(reg-iter:non-seed-caught)" "registry-driven INV-005 FAILS the malformed non-seed DCL-009 bullet (rows past the seed are genuinely checked)"
  else
    fail "TTT(reg-iter:non-seed-caught)" "malformed DCL-009 bullet NOT caught — INV-005 iterates only the 8 seeds, not the live registry (QA-003 regression)"
  fi
  if [ "$bad_seed_fail" -eq 0 ]; then
    pass "TTT(reg-iter:seeds-ok)" "the 8 well-formed seed bullets still pass while only DCL-009 fails"
  else
    fail "TTT(reg-iter:seeds-ok)" "a seed bullet wrongly failed alongside DCL-009 — synthetic fixture drift"
  fi

  # --- positive: a WELL-FORMED non-seed DCL-009 bullet must PASS the leg ---
  local good="$TMP/synth-agent-dcl009-good.md"
  make_synth_agent "$good"
  printf -- '- DCL-009 some-keyword: flag as BLOCKING when a spec exhibits the some-keyword pattern without a guard clause naming the required invariant.\n' >> "$good"

  if lens_bullet_ok "DCL-009" "some-keyword" "$good"; then
    pass "TTT(reg-iter:wellformed-009)" "a well-formed non-seed DCL-009 bullet passes lens_bullet_ok (same helper the real loop uses)"
  else
    fail "TTT(reg-iter:wellformed-009)" "well-formed DCL-009 bullet rejected — validator too strict for non-seed rows"
  fi

  # And the full registry-driven pass over the well-formed 9-row pair holds.
  local d2 k2 all_ok=0
  while IFS=$'\t' read -r d2 k2; do
    [ -n "$d2" ] || continue
    lens_bullet_ok "$d2" "$k2" "$good" || all_ok=1
  done < <(registry_lens_pairs "$sr")
  if [ "$all_ok" -eq 0 ]; then
    pass "TTT(reg-iter:all9-pass)" "registry-driven INV-005 passes all 9 rows when every bullet (incl. DCL-009) is well-formed"
  else
    fail "TTT(reg-iter:all9-pass)" "registry-driven INV-005 wrongly failed a row on the all-well-formed 9-row fixture"
  fi
}

# ============================================================================
# PRH-001: self-scan — the only guidance-file token in THIS file is the
# whitelisted single-quoted grep needle
# ============================================================================

# prh001_scan_source <path> — 0 iff every case-insensitive guidance-file token
# in <path> is the whitelisted single-quoted grep needle AND that needle's file
# argument is NOT the guidance file. On the first violation it prints a
# diagnostic on stdout and returns non-zero.
#
# CV-001 tightening: the old whitelist accepted any line matching
# `*grep*<sqneedle>*`, which passed the prohibited trailing-file-arg form
# `grep <sqneedle> <bareword-guidance-file>` (reading the guidance file itself —
# the exact coupling PRH-001 forbids). The tightened rule strips EVERY
# occurrence of the single-quoted needle from the line and rejects the line if
# any residual guidance-file token (case-insensitive) remains. The two
# legitimate forms leave no residual once the quoted needle is stripped
# (region here-string grep, agent-file grep); the prohibited trailing file arg
# leaves a bareword residual and is rejected. A bareword occurrence with no
# needle stays a violation (default branch), as before.
#
# The search token and single-quoted needle are built by concatenation so THIS
# function's own source contains no contiguous guidance-file literal (else the
# real self-scan against $SELF would flag these construction lines).
prh001_scan_source() {
  local path="$1"
  local tok sqtok
  tok="CLAUDE"".md"                    # constructed search token (no contiguous source literal)
  sqtok="'""CLAUDE"".md""'"            # constructed single-quoted needle (no contiguous source literal)

  if [ ! -f "$path" ]; then
    printf 'prh001: cannot read source at %s\n' "$path"
    return 2
  fi

  local raw line stripped
  while IFS= read -r raw; do
    line="${raw#*:}"                   # strip grep -n line-number prefix
    case "$line" in
      *grep*"$sqtok"*)
        # Whitelisted SHAPE — now pin the file argument. Strip every occurrence
        # of the single-quoted needle (quoted pattern => literal strip), then
        # reject any residual guidance-file token (case-insensitive, reusing the
        # constructed search token). POSIX-portable grep only (no -P/-o/-w).
        stripped="${line//"$sqtok"/}"
        if printf '%s\n' "$stripped" | grep -iq "$tok"; then
          printf 'prh001: residual guidance-file token after stripping needle (prohibited file argument): %s\n' "$line"
          return 1
        fi
        ;;
      *)
        printf 'prh001: non-whitelisted guidance-file token in source: %s\n' "$line"
        return 1
        ;;
    esac
  done < <(grep -in "$tok" "$path" || true)
  return 0
}

check_prh001_selfscan() {
  section "PRH-001: self-scan for prose-scan re-coupling"

  if [ ! -f "$SELF" ]; then
    fail "PRH-001(self)" "cannot locate this test's own source at $SELF"
    return
  fi

  # (1) REAL self-scan: every guidance-file token in THIS file must be the
  #     whitelisted needle whose file argument is not the guidance file.
  local self_msg
  if self_msg="$(prh001_scan_source "$SELF" 2>&1)"; then
    pass "PRH-001(selfscan)" "all guidance-file token(s) in this file are the whitelisted grep needle"
  else
    fail "PRH-001(selfscan)" "self-scan found a non-whitelisted guidance-file token: ${self_msg}"
  fi

  # (2) test-the-test (CV-001): drive synthetic fixtures through the SAME helper
  #     (no divergent copy). Construct the guidance-file token and single-quoted
  #     needle by concatenation so these fixture-construction lines carry no
  #     contiguous guidance-file literal (the real self-scan above would flag
  #     them otherwise).
  local gtok sqneedle
  gtok="CLAUDE"".md"                   # bareword guidance-file token (constructed)
  sqneedle="'""CLAUDE"".md""'"         # single-quoted needle (constructed)

  # NEGATIVE 1: prohibited trailing file argument — `grep <needle> <guidance>`.
  # This is the exact form CV-001 says the old whitelist wrongly accepted.
  local fx_neg1="$TMP/prh001-neg-trailingarg.sh"
  printf 'grep -n %s %s\n' "$sqneedle" "$gtok" > "$fx_neg1"
  if prh001_scan_source "$fx_neg1" >/dev/null 2>&1; then
    fail "PRH-001(ttt:neg-trailingarg)" "trailing-file-arg grep NOT rejected (whitelist too loose — CV-001)"
  else
    pass "PRH-001(ttt:neg-trailingarg)" "prohibited trailing-file-arg grep correctly rejected"
  fi

  # NEGATIVE 2: reading the guidance file via redirect / cat (no needle at all).
  local fx_neg2="$TMP/prh001-neg-read.sh"
  {
    printf 'region="$(< %s)"\n' "$gtok"
    printf 'cat %s\n' "$gtok"
  } > "$fx_neg2"
  if prh001_scan_source "$fx_neg2" >/dev/null 2>&1; then
    fail "PRH-001(ttt:neg-read)" "redirect/cat read of guidance file NOT rejected"
  else
    pass "PRH-001(ttt:neg-read)" "redirect/cat read of guidance file correctly rejected"
  fi

  # POSITIVE: the two legitimate forms — agent-file grep AND here-string region
  # grep — leave no residual once the quoted needle is stripped.
  local fx_pos="$TMP/prh001-pos.sh"
  {
    printf 'agent_ref="$(grep -c %s agents/review-spec-design-contract.md)"\n' "$sqneedle"
    printf 'if grep -q %s <<<"$region"; then\n' "$sqneedle"
  } > "$fx_pos"
  if prh001_scan_source "$fx_pos" >/dev/null 2>&1; then
    pass "PRH-001(ttt:pos)" "legitimate agent-file + here-string needle forms accepted"
  else
    fail "PRH-001(ttt:pos)" "legitimate needle forms wrongly rejected (whitelist too strict)"
  fi
}

# ============================================================================
# Run all checks
# ============================================================================

check_preflight
check_inv003_positive
check_inv003_negative
check_inv003_no_newline
check_inv004_seed
check_setequality
check_inv005
check_inv006
check_inv007
check_inv009
check_inv010
check_re_placeholder
check_ttt_extractors
check_ttt_vacuity
check_ttt_scopes
check_ttt_stub_e2e
check_ttt_registry_iteration
check_prh001_selfscan

summary "design-contract-lens-sync"
