#!/usr/bin/env bash
# shellcheck disable=SC1090,SC1091,SC2016
# Correctless — SFG Edit/Write-only documentation-coherence tests
#
# Enforces the sfg-edit-write-only spec invariants INV-007, INV-008, INV-009
# (documentation coherence sweep). After the GREEN doc sweep, no current-state
# doc may describe SFG as inspecting/blocking Bash commands, redirects, or
# writer commands; the deleted symbols (`_extract_bash_targets`,
# `tests/test-sfg-rescope.sh`) must not be referenced from current-state
# surfaces; the durable downgrade markers and the amended CLAUDE.md conventions
# must be PRESENT; the rule-file extraction-path carve-out must be REMOVED and
# replaced by the narrow DEFAULTS-only-on-config-failure exception.
#
# RED STATE (this feature): the docs are NOT yet swept, so the reject-substring
# and carve-out-absent assertions FAIL, and the required-PRESENT marker
# assertions FAIL. That is the correct RED precondition. GREEN's doc sweep makes
# every assertion pass.
#
# Run from repo root: bash tests/test-sfg-doc-coherence.sh
#
# POSIX-portable external tools only (grep/sed/awk) — no GNU-only extensions.

set -u

# ============================================================================
# Bootstrap — cd to repo root and source the shared harness
# ============================================================================

cd "$(dirname "${BASH_SOURCE[0]}")/.." || { echo "FATAL: cannot cd to repo root" >&2; exit 2; }

source "tests/test-helpers.sh"

ARCH_FILE=".correctless/ARCHITECTURE.md"
# Architecture entry bodies moved to per-section fragments (index+body-out
# fragmentation); root retains only headings + See-links. Body content and the
# current-state doc surface now span these fragment files.
ARCH_ABS_FRAG="docs/architecture/abstractions.md"
ARCH_FRAGMENTS=(
  "docs/architecture/trust-boundaries.md"
  "docs/architecture/abstractions.md"
  "docs/architecture/patterns.md"
  "docs/architecture/environment.md"
)
CLAUDE_MD="CLAUDE.md"
AGENT_CONTEXT=".correctless/AGENT_CONTEXT.md"
README_MD="README.md"
CONTRIBUTING_MD="CONTRIBUTING.md"
RULE_FILE=".claude/rules/hooks-pretooluse.md"
ANTIPATTERNS_MD=".correctless/antipatterns.md"
FEATURES_MD="FEATURES.md"

# ============================================================================
# Normalization helper — collapse runs of whitespace to a single space and
# normalize hyphen variants, so the reject-substring match is robust to
# re-wrapping / hyphenation differences (INV-007 "normalized for space/hyphen").
# Emits the whole file content as a single normalized stream on stdout.
# ============================================================================

normalize_stream() {
  # Replace any unicode-ish hyphen and ASCII hyphen runs are left as-is; we
  # only collapse whitespace (including newlines) to single spaces. This lets a
  # reject literal like "direct redirect/writer-command" match even when the doc
  # wraps "direct redirect/writer-\ncommand" across a line.
  tr '\n\t' '  ' | tr -s ' '
}

# ============================================================================
# CLAUDE.md convention-block extractor.
#
# INV-007/INV-009 scope the CLAUDE.md reject/marker assertions to the two named
# convention blocks and EXCLUDE the append-only `### YYYY-MM-DD — Postmortem`
# PMB-ledger entries (which legitimately quote old SFG behavior). This extracts
# the block beginning at a heading matching HEADER_REGEX through (but not
# including) the next `### ` heading or EOF.
# ============================================================================

claude_convention_block() {
  local header_regex="$1"
  awk -v re="$header_regex" '
    BEGIN { in_sec = 0 }
    $0 ~ re { in_sec = 1; print; next }
    in_sec && /^### / { exit }
    in_sec { print }
  ' "$CLAUDE_MD"
}

# ============================================================================
# CLAUDE.md without Postmortem ledger entries.
#
# For the general CLAUDE.md reject scan, drop every section whose heading
# matches `### YYYY-MM-DD — Postmortem` (append-only history quoting old SFG
# behavior) through the next `### ` heading or EOF. Everything else is emitted.
# ============================================================================

claude_md_minus_postmortems() {
  awk '
    BEGIN { skipping = 0 }
    /^### [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9] .*Postmortem/ { skipping = 1; next }
    /^### / { if (skipping) skipping = 0 }
    { if (!skipping) print }
  ' "$CLAUDE_MD"
}

echo "============================================="
echo "SFG doc-coherence tests (INV-007 / INV-008 / INV-009)"
echo "============================================="

# ============================================================================
# INV-007: reject-substring absence over the doc corpus.
#
# Corpus: ARCHITECTURE.md, CLAUDE.md (scoped, see below), AGENT_CONTEXT.md,
# README.md, every docs/** file EXCEPT docs/dev-journal.md and
# docs/workflow-history.md, and .claude/rules/sfg-deliverable.md.
#
# PINNED reject literals (normalized whitespace/hyphen before matching) — ZERO
# matches required after the sweep:
#   direct redirect/writer-command
#   direct-redirect
#   direct Bash write-destination
#   blocks Edit/Write AND Bash redirects
#   Bash redirects via _has_write_pattern   (core of "blocks ... Bash redirects via _has_write_pattern")
#   write-target extraction path
#   fails open on ambiguity
# ============================================================================

# Reject literals shared across the non-CLAUDE.md corpus files.
#
# MA-R2-CC class fix (2026-06): the corpus is now DERIVED from `git ls-files
# '*.md'` (see build_reject_corpus) so a NEW doc is auto-covered. Round 1 missed
# FEATURES.md and round 2 missed .claude/rules/canonicalize-path.md precisely
# because the corpus was an enumerated allowlist; a git-derived corpus closes
# that class. The `gates every Bash` literal (canonicalize-path.md phrasing) is
# pinned here so the canonicalize-path surface is caught going forward.
REJECT_LITERALS=(
  "direct redirect/writer-command"
  "direct-redirect"
  "direct Bash write-destination"
  "blocks Edit/Write AND Bash redirects"
  "Bash redirects via _has_write_pattern"
  "write-target extraction path"
  "fails open on ambiguity"
  "gates every Bash"
)

# ============================================================================
# Generalized reject-substring corpus (MA-R2-CC class fix).
#
# Corpus = every tracked Markdown file (`git ls-files '*.md'`) MINUS:
#   - docs/dev-journal.md, docs/workflow-history.md (append-only journals)
#   - .correctless/specs/**, .correctless/artifacts/**,
#     .correctless/verification/**  (this very spec + working artifacts +
#     verification reports legitimately quote the old SFG behavior)
#   - *-archived.md, *ARCHITECTURE_DEPRECATED.md  (frozen history)
#   - skills/** and agents/** AND their `correctless/` byte-mirrors
#     (these legitimately discuss SFG/Bash/workflow-gate in non-SFG contexts —
#     they keep the NARROW 4-phrase false-rationale leg below; the full
#     reject-list would false-fail there)
#   - CLAUDE.md  (handled separately via the claude_md_minus_postmortems
#     PMB-ledger projection — its append-only Postmortem entries legitimately
#     quote old SFG behavior)
#
# .claude/rules/**/*.md ARE in the corpus via git ls-files — that is how
# canonicalize-path.md and hooks-pretooluse.md get covered.
# ============================================================================

build_reject_corpus() {
  git ls-files '*.md' 2>/dev/null | while IFS= read -r f; do
    case "$f" in
      docs/dev-journal.md|docs/workflow-history.md) continue ;;
      .correctless/specs/*|.correctless/artifacts/*|.correctless/verification/*) continue ;;
      *-archived.md|*ARCHITECTURE_DEPRECATED.md) continue ;;
      skills/*|agents/*) continue ;;
      correctless/skills/*|correctless/agents/*) continue ;;
      CLAUDE.md) continue ;;
    esac
    printf '%s\n' "$f"
  done
}

# Build the docs/** corpus minus the two excluded journals (still used by the
# dangling-reference checks below, which keep their original docs/** scoping).
build_docs_corpus() {
  # Emit one path per line for every file under docs/ except the two journals.
  find docs -type f 2>/dev/null \
    | grep -v -e '^docs/dev-journal\.md$' -e '^docs/workflow-history\.md$' \
    || true
}

# assert_no_reject_in_file FILE_LABEL FILE_PATH  (whole-file, normalized)
assert_no_reject_in_file() {
  local label="$1" path="$2"
  if [ ! -f "$path" ]; then
    # A missing corpus file is not a reject hit; skip silently (other suites
    # own file-existence). Treat as pass for this assertion's purpose.
    pass "INV-007 reject($label)" "file absent — no reject possible: $path"
    return
  fi
  local normalized lit hit=0
  normalized="$(normalize_stream < "$path")"
  for lit in "${REJECT_LITERALS[@]}"; do
    if printf '%s' "$normalized" | grep -qF -- "$lit"; then
      fail "INV-007 reject($label)" "$path still contains forbidden literal: '$lit'"
      hit=1
    fi
  done
  if [ "$hit" -eq 0 ]; then
    pass "INV-007 reject($label)" "no forbidden Bash-write literals in $path"
  fi
}

# --- Generalized git-derived corpus (non-CLAUDE.md) ---
# Every tracked Markdown file minus the exclusions in build_reject_corpus. This
# auto-covers ARCHITECTURE.md, AGENT_CONTEXT.md, README.md, FEATURES.md,
# sfg-deliverable.md, hooks-pretooluse.md, canonicalize-path.md, docs/** (minus
# journals), templates/**, helpers/**, .correctless/checklists/**, and any NEW
# doc added later — without an enumerated allowlist that can silently miss a
# surface (MA-R2-CC class fix).
reject_corpus="$(build_reject_corpus)"
if [ -z "$reject_corpus" ]; then
  fail "INV-007 reject(corpus)" "git ls-files '*.md' returned no corpus — derivation broken?"
else
  while IFS= read -r cpath; do
    [ -z "$cpath" ] && continue
    assert_no_reject_in_file "${cpath}" "$cpath"
  done <<EOF_CORPUS
$reject_corpus
EOF_CORPUS
fi

# --- CLAUDE.md, scoped to the two named convention blocks ---
# Per INV-007/INV-009: the reject-substring assertion for CLAUDE.md applies to
# the 2026-04-26 "structurally-enforced sole-writer" and 2026-04-30
# "gate-enforced phase-transition" convention blocks, EXCLUDING the dated
# Postmortem ledger entries.
assert_no_reject_in_block() {
  local label="$1" block="$2"
  local normalized lit hit=0
  normalized="$(printf '%s' "$block" | normalize_stream)"
  if [ -z "$normalized" ]; then
    fail "INV-007 reject($label)" "CLAUDE.md convention block not found (extractor returned empty) — heading drift?"
    return
  fi
  for lit in "${REJECT_LITERALS[@]}"; do
    if printf '%s' "$normalized" | grep -qF -- "$lit"; then
      fail "INV-007 reject($label)" "CLAUDE.md $label convention block still contains forbidden literal: '$lit'"
      hit=1
    fi
  done
  if [ "$hit" -eq 0 ]; then
    pass "INV-007 reject($label)" "no forbidden Bash-write literals in CLAUDE.md $label convention block"
  fi
}

claude_2026_04_26_block="$(claude_convention_block '^### 2026-04-26 — Convention confirmed: Structurally-enforced sole-writer')"
claude_2026_04_30_block="$(claude_convention_block '^### 2026-04-30 — Convention introduced: gate-enforced phase-transition')"

assert_no_reject_in_block "2026-04-26" "$claude_2026_04_26_block"
assert_no_reject_in_block "2026-04-30" "$claude_2026_04_30_block"

# Defense-in-depth: the general CLAUDE.md body (minus Postmortem ledger) must
# also be clean of the two highest-signal literals. PMB Postmortem entries are
# excluded because they are append-only history quoting old SFG behavior.
claude_minus_pmb="$(claude_md_minus_postmortems | normalize_stream)"
claude_general_hit=0
for lit in "direct redirect/writer-command" "blocks Edit/Write AND Bash redirects"; do
  if printf '%s' "$claude_minus_pmb" | grep -qF -- "$lit"; then
    fail "INV-007 reject(CLAUDE.md-non-PMB)" "CLAUDE.md (excluding Postmortem ledger) still contains forbidden literal: '$lit'"
    claude_general_hit=1
  fi
done
if [ "$claude_general_hit" -eq 0 ]; then
  pass "INV-007 reject(CLAUDE.md-non-PMB)" "no high-signal Bash-write literals outside the PMB ledger in CLAUDE.md"
fi

# ============================================================================
# INV-007: dangling-reference absence.
#
# Zero occurrences of `test-sfg-rescope` or `_extract_bash_targets` in
# CURRENT-STATE surfaces only:
#   hooks/**, tests/**, ARCHITECTURE.md, CLAUDE.md, AGENT_CONTEXT.md,
#   README.md, CONTRIBUTING.md, docs/** (minus journals), .claude/rules/**
#
# EXCLUDED (would self-fail on this very spec): .correctless/specs/**,
# .correctless/artifacts/**, .correctless/verification/**,
# .correctless/ARCHITECTURE_DEPRECATED.md, .correctless/antipatterns-archived.md.
#
# tests/** legitimately references `_extract_bash_targets` as test-data inside
# the INV-005 structural-grep test and deletion-marker comments
# (test-sensitive-file-guard.sh) and inside this file. Per the spec's scoping
# note: scope the tests/** `_extract_bash_targets` dangling check to EXCLUDE
# test-sensitive-file-guard.sh and test-sfg-doc-coherence.sh; the
# `test-sfg-rescope` check stays repo-wide over the current-state surfaces.
# ============================================================================

# assert_no_token_in_files TOKEN ID  -- args 3..N are file paths
assert_no_token_in_files() {
  local token="$1" id="$2"
  shift 2
  local f hit=0 hitlist=""
  for f in "$@"; do
    [ -f "$f" ] || continue
    if grep -qF -- "$token" "$f"; then
      hit=1
      hitlist="${hitlist}${f} "
    fi
  done
  if [ "$hit" -eq 0 ]; then
    pass "$id" "no dangling '$token' reference in scoped current-state surfaces"
  else
    fail "$id" "dangling '$token' reference still present in: $hitlist"
  fi
}

# Build the docs corpus minus journals (reuse).
docs_corpus_files=()
while IFS= read -r dpath; do
  [ -z "$dpath" ] && continue
  docs_corpus_files+=("$dpath")
done <<EOF_DOCS2
$(build_docs_corpus)
EOF_DOCS2

# Single-file current-state surfaces (non-glob). CLAUDE.md is included raw here;
# the per-token dangling checks below choose, per token, whether to scan the raw
# file or the Postmortem-stripped projection (see CLAUDE_MD_NO_PMB).
SINGLE_SURFACES=(
  "$ARCH_FILE"
  "${ARCH_FRAGMENTS[@]}"
  "$CLAUDE_MD"
  "$AGENT_CONTEXT"
  "$README_MD"
  "$CONTRIBUTING_MD"
  "$FEATURES_MD"
)

# Single-file surfaces with CLAUDE.md replaced by its Postmortem-stripped
# projection. The `_extract_bash_targets` SYMBOL dangling check consumes this so
# that the append-only `### YYYY-MM-DD — Postmortem` PMB-ledger entries (which
# legitimately quote the deleted extractor) are excluded — exactly as the
# amend/reject-substring assertion above excludes them via the SAME shared
# helper (claude_md_minus_postmortems). The two scopings consume one helper so
# they cannot drift (QA-001 class fix). Every OTHER current-state surface
# (hooks/**, ARCHITECTURE.md, README.md, AGENT_CONTEXT.md, docs/**,
# .claude/rules/**) stays strict; only CLAUDE.md gets the PMB-ledger exclusion,
# and only for the symbol. The `test-sfg-rescope` FILENAME check below keeps the
# raw CLAUDE.md (SINGLE_SURFACES) strict — a deleted test FILENAME must never
# appear in current PMB prose.
CLAUDE_MD_NO_PMB="$(mktemp)"
trap 'rm -f "$CLAUDE_MD_NO_PMB"' EXIT
claude_md_minus_postmortems > "$CLAUDE_MD_NO_PMB"

SINGLE_SURFACES_CLAUDE_NO_PMB=(
  "$ARCH_FILE"
  "${ARCH_FRAGMENTS[@]}"
  "$CLAUDE_MD_NO_PMB"
  "$AGENT_CONTEXT"
  "$README_MD"
  "$CONTRIBUTING_MD"
  "$FEATURES_MD"
)

# hooks/** and .claude/rules/** file lists.
hooks_files=()
while IFS= read -r f; do
  [ -z "$f" ] && continue
  hooks_files+=("$f")
done <<EOF_HOOKS
$(find hooks -type f -name '*.sh' 2>/dev/null || true)
EOF_HOOKS

rules_files=()
while IFS= read -r f; do
  [ -z "$f" ] && continue
  rules_files+=("$f")
done <<EOF_RULES
$(find .claude/rules -type f 2>/dev/null || true)
EOF_RULES

# tests/** files EXCLUDING the two that legitimately name _extract_bash_targets
# as test data.
tests_files_scoped=()
while IFS= read -r f; do
  [ -z "$f" ] && continue
  case "$f" in
    tests/test-sensitive-file-guard.sh) continue ;;
    tests/test-sfg-doc-coherence.sh)    continue ;;
  esac
  tests_files_scoped+=("$f")
done <<EOF_TESTS
$(find tests -type f -name '*.sh' 2>/dev/null || true)
EOF_TESTS

# tests/** files for the test-sfg-rescope check. This file itself names the
# deleted `test-sfg-rescope` in its own scoping comments as historical/test
# data, so exclude it (same rationale the spec gives for excluding it from the
# `_extract_bash_targets` tests/** check). The deleted file's own name must not
# appear in any OTHER current-state test.
tests_files_rescope=()
while IFS= read -r f; do
  [ -z "$f" ] && continue
  case "$f" in
    tests/test-sfg-doc-coherence.sh) continue ;;
  esac
  tests_files_rescope+=("$f")
done <<EOF_TESTS_ALL
$(find tests -type f -name '*.sh' 2>/dev/null || true)
EOF_TESTS_ALL

# --- `test-sfg-rescope` dangling check: repo-wide over current-state surfaces
#     (the deleted test file must not be referenced anywhere current-state).
#     `.correctless/antipatterns.md` is included for the FILENAME check ONLY
#     (QA-002 class fix): a deleted test FILENAME must never appear as a
#     current-state reference. It is deliberately NOT added to the
#     `_extract_bash_targets` SYMBOL check nor the reject-substring check, because
#     antipatterns.md legitimately names deleted mechanisms in its historical
#     "What went wrong" prose — a mechanical symbol/substring grep would
#     false-fail there. ---
assert_no_token_in_files "test-sfg-rescope" "INV-007 dangling(test-sfg-rescope)" \
  "${SINGLE_SURFACES[@]}" \
  "$ANTIPATTERNS_MD" \
  "${hooks_files[@]}" \
  "${rules_files[@]}" \
  "${tests_files_rescope[@]}" \
  "${docs_corpus_files[@]}"

# --- `_extract_bash_targets` dangling check: same surfaces, but (a) CLAUDE.md is
#     scanned via its Postmortem-stripped projection (the append-only PMB ledger
#     legitimately quotes the deleted symbol — same exclusion the amend check
#     applies, via the SAME shared helper so they cannot drift), and (b) tests/**
#     is scoped to exclude the two test-data-bearing files. ---
assert_no_token_in_files "_extract_bash_targets" "INV-007 dangling(_extract_bash_targets)" \
  "${SINGLE_SURFACES_CLAUDE_NO_PMB[@]}" \
  "${hooks_files[@]}" \
  "${rules_files[@]}" \
  "${tests_files_scoped[@]}" \
  "${docs_corpus_files[@]}"

# ============================================================================
# INV-009: required-PRESENT durable downgrade markers (positive assertions).
#
# ABS-027 AND ABS-045 in ARCHITECTURE.md each must contain the durable downgrade
# marker core substring:
#   "Bash-redirect structural leg removed 2026-06 by sfg-edit-write-only"
# ============================================================================

DOWNGRADE_MARKER="Bash-redirect structural leg removed 2026-06 by sfg-edit-write-only"

# arch_abs_block ABS_ID -- emit the ABS-xxx section body (heading -> next `### `).
arch_abs_block() {
  local abs_id="$1"
  awk -v id="$abs_id" '
    BEGIN { in_sec = 0 }
    $0 ~ ("^### " id ":") { in_sec = 1; print; next }
    in_sec && /^### / { exit }
    in_sec { print }
  ' "$ARCH_ABS_FRAG"
}

assert_marker_in_abs() {
  local abs_id="$1"
  local block
  block="$(arch_abs_block "$abs_id")"
  if [ -z "$block" ]; then
    fail "INV-009 marker($abs_id)" "could not extract $abs_id section from $ARCH_FILE"
    return
  fi
  if printf '%s' "$block" | grep -qF -- "$DOWNGRADE_MARKER"; then
    pass "INV-009 marker($abs_id)" "$abs_id contains durable downgrade marker"
  else
    fail "INV-009 marker($abs_id)" "$abs_id missing durable downgrade marker: '$DOWNGRADE_MARKER'"
  fi
}

assert_marker_in_abs "ABS-027"
assert_marker_in_abs "ABS-045"

# ============================================================================
# INV-009: CLAUDE.md conventions NAME the cmd_* phase-transition gate as the
# structural leg, tied to the Edit/Write tool-path.
#
# Each of the 2026-04-26 and 2026-04-30 convention blocks must contain BOTH:
#   - the literal `cmd_*`
#   - the phrase `Edit/Write tool-path`
# co-occurring, so the next sole-writer feature reads the corrected contract
# (Edit/Write tool-path guard + content-based cmd_* phase-transition gate).
# ============================================================================

assert_cmd_gate_naming() {
  local label="$1" block="$2"
  if [ -z "$block" ]; then
    fail "INV-009 cmd-gate($label)" "CLAUDE.md $label convention block not found — heading drift?"
    return
  fi
  local has_cmd has_editwrite
  has_cmd=1; has_editwrite=1
  printf '%s' "$block" | grep -qF -- 'cmd_*' || has_cmd=0
  printf '%s' "$block" | grep -qF -- 'Edit/Write tool-path' || has_editwrite=0
  if [ "$has_cmd" -eq 1 ] && [ "$has_editwrite" -eq 1 ]; then
    pass "INV-009 cmd-gate($label)" "$label convention names cmd_* gate + Edit/Write tool-path structural leg"
  else
    fail "INV-009 cmd-gate($label)" "$label convention missing structural-leg naming (cmd_*=$has_cmd Edit/Write-tool-path=$has_editwrite)"
  fi
}

assert_cmd_gate_naming "2026-04-26" "$claude_2026_04_26_block"
assert_cmd_gate_naming "2026-04-30" "$claude_2026_04_30_block"

# ============================================================================
# INV-008: rule-file (.claude/rules/hooks-pretooluse.md) assertions.
#
# (a) The clause-5 EXTRACTION-PATH carve-out subsection is ABSENT. The #205
#     carve-out is titled "Clause-5 carve-out: sensitive-file-guard extraction
#     path fails OPEN" and describes `_extract_bash_targets` failing open on
#     ambiguity. After the sweep none of those carve-out strings may remain.
# (b) The narrow DEFAULTS-only-on-config-failure exception IS documented
#     (custom_patterns unparsable -> DEFAULTS remain enforced; never fully
#     open), so the rule file's claim is honest.
# ============================================================================

if [ ! -f "$RULE_FILE" ]; then
  fail "INV-008 rule-file" "rule file missing: $RULE_FILE"
else
  rule_body="$(cat "$RULE_FILE")"
  rule_norm="$(printf '%s' "$rule_body" | normalize_stream)"

  # (a) Carve-out ABSENT — assert each #205 carve-out marker string is gone.
  carve_hit=0
  # The carve-out subsection heading itself.
  if printf '%s' "$rule_norm" | grep -qF -- "Clause-5 carve-out: sensitive-file-guard extraction path fails OPEN"; then
    fail "INV-008 carve-out-absent(heading)" "rule file still has the #205 extraction-path carve-out heading"
    carve_hit=1
  fi
  # Its defining phrasing — the extraction path failing open on ambiguity.
  if printf '%s' "$rule_norm" | grep -qF -- "extraction path"; then
    fail "INV-008 carve-out-absent(extraction-path)" "rule file still references the deleted 'extraction path' carve-out"
    carve_hit=1
  fi
  if printf '%s' "$rule_norm" | grep -qF -- "fails OPEN on extraction"; then
    fail "INV-008 carve-out-absent(fails-OPEN)" "rule file still claims the extraction path 'fails OPEN on extraction'"
    carve_hit=1
  fi
  if printf '%s' "$rule_norm" | grep -qF -- "_extract_bash_targets"; then
    fail "INV-008 carve-out-absent(symbol)" "rule file still names the deleted symbol '_extract_bash_targets'"
    carve_hit=1
  fi
  if [ "$carve_hit" -eq 0 ]; then
    pass "INV-008 carve-out-absent" "rule file no longer documents the extraction-path fail-open carve-out"
  fi

  # (b) DEFAULTS-only-on-config-failure narrow exception PRESENT.
  #     GREEN will write wording naming custom_patterns unparsable -> DEFAULTS
  #     remain enforced (never fully open). Assert the co-occurring core terms.
  has_degrade=1 has_custom=1 has_defaults=1
  printf '%s' "$rule_norm" | grep -qiF -- "degrades to DEFAULTS-only" || has_degrade=0
  printf '%s' "$rule_norm" | grep -qF -- "custom_patterns" || has_custom=0
  printf '%s' "$rule_norm" | grep -qiF -- "DEFAULTS remain enforced" || has_defaults=0
  if [ "$has_degrade" -eq 1 ] && [ "$has_custom" -eq 1 ] && [ "$has_defaults" -eq 1 ]; then
    pass "INV-008 defaults-exception" "rule file documents the DEFAULTS-only-on-config-failure narrow exception"
  else
    fail "INV-008 defaults-exception" "rule file missing narrow-exception wording (degrades-to-DEFAULTS-only=$has_degrade custom_patterns=$has_custom DEFAULTS-remain-enforced=$has_defaults)"
  fi
fi

# ============================================================================
# INV-007 (MA-002): NARROW skills/** false-rationale reject leg.
#
# Skill prose (skills/**/SKILL.md) previously justified routing writes through a
# sole-writer script by claiming "the SFG permits this because the command
# contains no direct redirect to the protected path" / "direct Edit/redirect is
# blocked". That rationale is now FALSE — SFG guards only the Edit/Write
# tool-path and no longer inspects Bash at all (a direct Bash redirect is an
# accepted residual, AP-040). The routing is a sole-writer (who-writes)
# convention, not a redirect-blocking guarantee.
#
# CRITICAL scoping: assert ZERO occurrences of ONLY these four specific
# false-rationale literals. Do NOT broaden to "Bash redirect" / "blocks Bash" —
# skill prose legitimately discusses SFG, Bash, and workflow-gate in many other
# (true) contexts, and a broad grep would false-fail.
# ============================================================================

SKILLS_FALSE_RATIONALE=(
  "no direct redirect"
  "direct Edit/redirect is blocked"
  "contains no direct redirect"
  "direct redirect to the protected path"
)

skills_files=()
while IFS= read -r f; do
  [ -z "$f" ] && continue
  skills_files+=("$f")
done <<EOF_SKILLS
$(find skills -type f -name '*.md' 2>/dev/null || true)
EOF_SKILLS

skills_rationale_hit=0
if [ "${#skills_files[@]}" -eq 0 ]; then
  pass "INV-007 skills-false-rationale" "no skills/** files to scan"
else
  for f in "${skills_files[@]}"; do
    [ -f "$f" ] || continue
    norm="$(normalize_stream < "$f")"
    for lit in "${SKILLS_FALSE_RATIONALE[@]}"; do
      if printf '%s' "$norm" | grep -qF -- "$lit"; then
        fail "INV-007 skills-false-rationale" "$f still contains false SFG-redirect rationale: '$lit'"
        skills_rationale_hit=1
      fi
    done
  done
  if [ "$skills_rationale_hit" -eq 0 ]; then
    pass "INV-007 skills-false-rationale" "no false 'no direct redirect' SFG rationale in skills/**"
  fi
fi

# ============================================================================
# Summary
# ============================================================================

summary "test-sfg-doc-coherence"
