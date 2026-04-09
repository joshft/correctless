#!/usr/bin/env bash
# Correctless — Token-Aware Intensity Calibration test suite
# Tests spec rules INV-001 through INV-008 and PRH-001/PRH-002 from
# .correctless/specs/token-aware-intensity.md
# Run from repo root: bash tests/test-token-aware-intensity.sh

set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CVERIFY_SKILL="$REPO_DIR/skills/cverify/SKILL.md"
CSPEC_SKILL="$REPO_DIR/skills/cspec/SKILL.md"
CMETRICS_SKILL="$REPO_DIR/skills/cmetrics/SKILL.md"
LITE_CFG="$REPO_DIR/templates/workflow-config.json"
FULL_CFG="$REPO_DIR/templates/workflow-config-full.json"
LIVE_CFG="$REPO_DIR/.correctless/config/workflow-config.json"
PASS=0
FAIL=0

# ============================================
# Helpers (matching project test conventions)
# ============================================

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (expected '$expected', got '$actual')"
    FAIL=$((FAIL + 1))
  fi
}

file_contains() {
  local file="$1" pattern="$2" desc="$3"
  if grep -q "$pattern" "$file" 2>/dev/null; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (pattern '$pattern' not found in $file)"
    FAIL=$((FAIL + 1))
  fi
}

file_not_contains() {
  local file="$1" pattern="$2" desc="$3"
  if grep -q "$pattern" "$file" 2>/dev/null; then
    echo "  FAIL: $desc (pattern '$pattern' should NOT be in $file)"
    FAIL=$((FAIL + 1))
  else
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  fi
}

file_contains_i() {
  local file="$1" pattern="$2" desc="$3"
  if grep -qi "$pattern" "$file" 2>/dev/null; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (pattern '$pattern' not found case-insensitively in $file)"
    FAIL=$((FAIL + 1))
  fi
}

# Section-aware grep: extract a section and check for a pattern within it.
# Sections are delimited by ## or ### headings.
section_contains() {
  local file="$1" section_heading="$2" pattern="$3" desc="$4"
  local section_text
  section_text="$(sed -n "/^###* .*${section_heading}/,/^###* /p" "$file" 2>/dev/null)"
  if echo "$section_text" | grep -qi "$pattern"; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (pattern '$pattern' not found in section '$section_heading' of $file)"
    FAIL=$((FAIL + 1))
  fi
}

section_not_contains() {
  local file="$1" section_heading="$2" pattern="$3" desc="$4"
  local section_text
  section_text="$(sed -n "/^###* .*${section_heading}/,/^###* /p" "$file" 2>/dev/null)"
  if echo "$section_text" | grep -qi "$pattern"; then
    echo "  FAIL: $desc (pattern '$pattern' should NOT be in section '$section_heading' of $file)"
    FAIL=$((FAIL + 1))
  else
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  fi
}

# ============================================
# INV-001: /cverify writes actual_tokens to calibration entries
#   Must sum total_tokens from token-log JSONL using branch_slug,
#   use deterministic jq (not LLM arithmetic), handle malformed
#   lines, and write 0 when token log is missing/empty
# ============================================

test_inv001_cverify_writes_actual_tokens() {
  echo ""
  echo "=== INV-001: /cverify writes actual_tokens to calibration entries ==="

  # INV-001a: cverify SKILL.md references actual_tokens field
  file_contains "$CVERIFY_SKILL" "actual_tokens" \
    "INV-001a: cverify SKILL.md references actual_tokens field"

  # INV-001b: cverify uses branch_slug (not task-slug) to locate token log
  # (AP-003 mitigation: anchor to token-log file location context)
  file_contains_i "$CVERIFY_SKILL" "branch.slug.*token-log\|token-log.*branch.slug\|branch_slug.*token.*log\|token.*log.*branch_slug" \
    "INV-001b: cverify uses branch_slug to locate the token log file"

  # INV-001b-neg: cverify does NOT use task-slug to locate token log
  # (spec explicitly says "Violated when: uses task-slug instead of branch-slug")
  file_not_contains "$CVERIFY_SKILL" "task.slug.*token.log\|task_slug.*token.log\|task-slug.*token-log" \
    "INV-001b-neg: cverify does NOT use task-slug for token log location"

  # INV-001c: cverify references the JSONL file naming convention
  file_contains_i "$CVERIFY_SKILL" "token-log-.*jsonl\|token-log.*\.jsonl" \
    "INV-001c: cverify references token-log-{branch-slug}.jsonl naming convention"

  # INV-001d: cverify uses jq for summation (deterministic, not LLM arithmetic)
  # (AP-003 mitigation: require both jq and token context together)
  file_contains_i "$CVERIFY_SKILL" "jq.*total_tokens\|total_tokens.*jq\|jq.*actual_tokens\|jq.*token.*sum" \
    "INV-001d: cverify uses jq for deterministic token summation"

  # INV-001e: cverify handles malformed JSONL lines
  file_contains_i "$CVERIFY_SKILL" "malformed.*skip\|skip.*malformed\|invalid.*JSON.*skip\|skip.*invalid\|malformed.*line" \
    "INV-001e: cverify skips malformed JSONL lines"

  # INV-001f: actual_tokens is 0 when token log file is missing or empty
  file_contains_i "$CVERIFY_SKILL" "actual_tokens.*0\|0.*actual_tokens.*missing\|missing.*actual_tokens.*0\|does not exist.*actual_tokens.*0\|empty.*actual_tokens.*0" \
    "INV-001f: actual_tokens is 0 when token log missing or empty"

  # INV-001g: sums total_tokens field from the JSONL entries
  file_contains_i "$CVERIFY_SKILL" "sum.*total_tokens\|total_tokens.*sum\|sum of.*total_tokens" \
    "INV-001g: cverify sums total_tokens from JSONL entries"

  # INV-001h: actual_tokens written as integer in calibration entry
  file_contains_i "$CVERIFY_SKILL" "actual_tokens.*integer\|integer.*actual_tokens\|actual_tokens.*calibration" \
    "INV-001h: actual_tokens is integer in calibration entry"
}

# ============================================
# INV-002: /cspec reads actual_tokens from calibration entries
#   Token arithmetic mean computed only across entries where
#   actual_tokens is present AND > 0. Zero/absent excluded from
#   token average only (not from QA/findings arithmetic)
# ============================================

test_inv002_cspec_reads_actual_tokens() {
  echo ""
  echo "=== INV-002: /cspec reads actual_tokens from calibration entries ==="

  # INV-002a: cspec references actual_tokens in calibration arithmetic
  section_contains "$CSPEC_SKILL" "Step 7b" "actual_tokens" \
    "INV-002a: cspec Step 7b references actual_tokens field"

  # INV-002b: cspec computes arithmetic mean of actual_tokens
  file_contains_i "$CSPEC_SKILL" "average.*actual_tokens\|actual_tokens.*average\|mean.*actual_tokens\|actual_tokens.*mean\|arithmetic.*actual_tokens" \
    "INV-002b: cspec computes average of actual_tokens"

  # INV-002c: excludes entries where actual_tokens is zero or absent from token arithmetic
  # (AP-003 mitigation: anchor to exclusion context with both zero and absent)
  file_contains_i "$CSPEC_SKILL" "actual_tokens.*present.*greater.*0\|actual_tokens.*exclude.*zero\|zero.*absent.*actual_tokens\|actual_tokens.*absent.*exclude\|actual_tokens.*0.*exclude" \
    "INV-002c: cspec excludes zero/absent actual_tokens from token arithmetic"

  # INV-002d: QA rounds and findings arithmetic unchanged — includes all overlapping entries
  # (entries without actual_tokens still participate in QA/findings math)
  # (AP-003 mitigation: anchor to actual_tokens context — not generic "unchanged")
  file_contains_i "$CSPEC_SKILL" "actual_tokens.*excluded.*token.*only\|token.*only.*excluded\|actual_tokens.*QA.*unchanged\|actual_tokens.*not.*affect.*QA\|without.*actual_tokens.*QA.*findings.*unchanged" \
    "INV-002d: QA/findings arithmetic includes all overlapping entries (unchanged by actual_tokens)"
}

# ============================================
# INV-003: Token threshold for active mode auto-raise
#   Three conditions OR'd: avg actual_qa_rounds >= 3,
#   avg actual_findings_count >= 8, OR avg actual_tokens >= 200,000
#   All three in same clause with "or" connectors
# ============================================

test_inv003_token_threshold_active_mode() {
  echo ""
  echo "=== INV-003: Token threshold for active mode auto-raise ==="

  # INV-003a: cspec references 200,000 or 200000 token threshold
  file_contains_i "$CSPEC_SKILL" "200,000\|200000" \
    "INV-003a: cspec references 200,000 token threshold"

  # INV-003b: token threshold connected to actual_tokens in active mode
  # (AP-003 mitigation: require both threshold and actual_tokens in proximity)
  file_contains_i "$CSPEC_SKILL" "actual_tokens.*200,000\|200,000.*actual_tokens\|actual_tokens.*200000\|200000.*actual_tokens\|token.*200,000\|200,000.*token" \
    "INV-003b: 200,000 threshold linked to actual_tokens"

  # INV-003c: all three thresholds appear in the same auto-raise clause
  # Check that all three exist in the active mode section together
  local active_section
  active_section="$(sed -n '/^- \*\*Active mode\|^  - \*\*Active\|active.*auto-raise/,/^- \*\*[A-Z]\|^$/p' "$CSPEC_SKILL" 2>/dev/null | head -30)"
  local has_qa=0 has_findings=0 has_tokens=0
  echo "$active_section" | grep -qi "3.*qa\|qa.*3\|qa_rounds.*3\|3.*round" && has_qa=1
  echo "$active_section" | grep -qi "8.*BLOCKING\|BLOCKING.*8\|findings.*8\|8.*finding" && has_findings=1
  echo "$active_section" | grep -qi "200,000\|200000" && has_tokens=1
  if [ "$has_qa" -eq 1 ] && [ "$has_findings" -eq 1 ] && [ "$has_tokens" -eq 1 ]; then
    echo "  PASS: INV-003c: all three thresholds (QA>=3, findings>=8, tokens>=200K) in active mode clause"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: INV-003c: not all three thresholds present in active mode clause (QA=$has_qa, findings=$has_findings, tokens=$has_tokens)"
    FAIL=$((FAIL + 1))
  fi

  # INV-003d: three conditions are disjunctive (OR'd) — "or" connectors
  # Multi-line safe: check that "or" appears in the same section as all three thresholds
  local has_or=0
  echo "$active_section" | grep -qi " or " && has_or=1
  if [ "$has_or" -eq 1 ] && [ "$has_qa" -eq 1 ] && [ "$has_findings" -eq 1 ] && [ "$has_tokens" -eq 1 ]; then
    echo "  PASS: INV-003d: three thresholds connected with 'or' (disjunctive)"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: INV-003d: three thresholds not connected with 'or' in active mode section (or=$has_or, qa=$has_qa, findings=$has_findings, tokens=$has_tokens)"
    FAIL=$((FAIL + 1))
  fi
}

# ============================================
# INV-004: Passive mode shows token calibration arithmetic
#   Display includes sum, count, average of actual_tokens
#   and 200,000 threshold comparison
# ============================================

test_inv004_passive_token_arithmetic() {
  echo ""
  echo "=== INV-004: Passive mode shows token calibration arithmetic ==="

  # INV-004a: passive mode calibration display mentions actual_tokens
  # (AP-006 mitigation: section-anchored to Step 7b / calibration context)
  section_contains "$CSPEC_SKILL" "Step 7b" "actual_tokens.*passive\|passive.*actual_tokens\|actual_tokens.*advisory\|advisory.*actual_tokens\|actual_tokens.*arithmetic\|arithmetic.*actual_tokens" \
    "INV-004a: passive mode calibration display includes actual_tokens"

  # INV-004b: passive mode display shows sum, count, average for token data
  file_contains_i "$CSPEC_SKILL" "sum.*count.*average.*token\|token.*sum.*count.*average\|sum.*actual_tokens\|actual_tokens.*sum.*count" \
    "INV-004b: passive mode shows sum, count, average of actual_tokens"

  # INV-004c: 200,000 threshold comparison shown in passive mode
  # (AP-003 mitigation: require both threshold and passive/calibration context)
  file_contains_i "$CSPEC_SKILL" "200,000.*threshold\|threshold.*200,000\|200000.*threshold\|threshold.*200000\|200,000.*token.*threshold\|token.*threshold.*200,000" \
    "INV-004c: passive mode shows 200,000 threshold comparison"

  # INV-004d: calibration example includes actual_tokens data
  file_contains_i "$CSPEC_SKILL" "actual_tokens.*example\|example.*actual_tokens\|token.*calibration.*example\|example.*token.*calibration" \
    "INV-004d: calibration example includes token data"
}

# ============================================
# INV-005: Graceful handling of missing actual_tokens
#   Entries without actual_tokens participate normally in
#   QA/findings arithmetic. Only excluded from token average.
# ============================================

test_inv005_missing_actual_tokens_graceful() {
  echo ""
  echo "=== INV-005: Graceful handling of missing actual_tokens ==="

  # INV-005a: entries missing actual_tokens are not skipped entirely
  file_contains_i "$CSPEC_SKILL" "missing.*actual_tokens.*not.*skip\|actual_tokens.*missing.*not.*error\|without.*actual_tokens.*participate\|missing.*actual_tokens.*still\|without.*actual_tokens.*not.*skip" \
    "INV-005a: entries missing actual_tokens are not skipped entirely"

  # INV-005b: entries without actual_tokens participate in QA/findings math
  file_contains_i "$CSPEC_SKILL" "missing.*actual_tokens.*QA\|actual_tokens.*missing.*QA.*findings\|participate.*QA.*rounds\|without.*actual_tokens.*QA\|participate.*findings" \
    "INV-005b: entries without actual_tokens participate in QA/findings arithmetic"

  # INV-005c: only excluded from token-specific average
  file_contains_i "$CSPEC_SKILL" "excluded.*token.*average\|token.*average.*excluded\|only.*excluded.*token\|token.*arithmetic.*only\|excluded.*from.*token.*only" \
    "INV-005c: entries without actual_tokens excluded only from token average"

  # INV-005d: no error or warning for legacy entries
  file_contains_i "$CSPEC_SKILL" "no.*error.*actual_tokens\|actual_tokens.*no.*error\|legacy.*entries\|entries.*before.*this.*feature\|entries.*written.*before" \
    "INV-005d: no error/warning for legacy entries without actual_tokens"
}

# ============================================
# INV-006: /cmetrics shows per-feature token cost table
#   Section named "Per-Feature Token Cost", skill-based category
#   mapping (ctdd->TDD, creview/creview-spec->Review,
#   cverify->Verification, caudit->Audit, all others->Other),
#   sorted by total tokens descending
# ============================================

test_inv006_cmetrics_per_feature_table() {
  echo ""
  echo "=== INV-006: /cmetrics shows per-feature token cost table ==="

  # INV-006a: cmetrics has a "Per-Feature Token Cost" section
  file_contains "$CMETRICS_SKILL" "Per-Feature Token Cost" \
    "INV-006a: cmetrics has 'Per-Feature Token Cost' section"

  # INV-006b: Per-Feature Token Cost section has skill-based category mapping
  # (AP-003 mitigation: anchor to "Per-Feature Token Cost" section specifically,
  # not the existing Phase Distribution table which already has categories)
  local per_feature_section
  per_feature_section="$(sed -n '/Per-Feature Token Cost/,/^### /p' "$CMETRICS_SKILL" 2>/dev/null)"

  # INV-006b: ctdd maps to TDD within per-feature section
  if echo "$per_feature_section" | grep -qi "ctdd.*TDD\|TDD.*ctdd"; then
    echo "  PASS: INV-006b: ctdd maps to TDD in Per-Feature Token Cost"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: INV-006b: ctdd->TDD mapping not in Per-Feature Token Cost section"
    FAIL=$((FAIL + 1))
  fi

  # INV-006c: creview/creview-spec maps to Review within per-feature section
  if echo "$per_feature_section" | grep -qi "creview.*Review\|Review.*creview"; then
    echo "  PASS: INV-006c: creview maps to Review in Per-Feature Token Cost"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: INV-006c: creview->Review mapping not in Per-Feature Token Cost section"
    FAIL=$((FAIL + 1))
  fi

  # INV-006d: cverify maps to Verification within per-feature section
  if echo "$per_feature_section" | grep -qi "cverify.*Verification\|Verification.*cverify"; then
    echo "  PASS: INV-006d: cverify maps to Verification in Per-Feature Token Cost"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: INV-006d: cverify->Verification mapping not in Per-Feature Token Cost section"
    FAIL=$((FAIL + 1))
  fi

  # INV-006e: caudit maps to Audit within per-feature section
  if echo "$per_feature_section" | grep -qi "caudit.*Audit\|Audit.*caudit"; then
    echo "  PASS: INV-006e: caudit maps to Audit in Per-Feature Token Cost"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: INV-006e: caudit->Audit mapping not in Per-Feature Token Cost section"
    FAIL=$((FAIL + 1))
  fi

  # INV-006f: other skills map to Other within per-feature section
  if echo "$per_feature_section" | grep -qi "other.*Other\|Other.*other\|all others.*Other\|remaining.*Other\|else.*Other"; then
    echo "  PASS: INV-006f: remaining skills map to Other in Per-Feature Token Cost"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: INV-006f: Other mapping not in Per-Feature Token Cost section"
    FAIL=$((FAIL + 1))
  fi

  # INV-006g: table sorted by total tokens descending
  file_contains_i "$CMETRICS_SKILL" "sorted.*total.*token.*descend\|descend.*total.*token\|sorted.*descend.*token\|total.*tokens.*descend\|sort.*by.*total.*token" \
    "INV-006g: table sorted by total tokens descending"

  # INV-006h: Per-Feature Token Cost section references reading token-log files
  # (AP-003 mitigation: anchor to Per-Feature section to avoid matching existing data sources)
  if echo "$per_feature_section" | grep -qi "token-log.*jsonl\|token-log"; then
    echo "  PASS: INV-006h: Per-Feature Token Cost reads token-log JSONL files"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: INV-006h: Per-Feature Token Cost section does not reference token-log files"
    FAIL=$((FAIL + 1))
  fi

  # INV-006i: uses JSONL skill field for category mapping
  # (AP-003 mitigation: anchor to Per-Feature section)
  if echo "$per_feature_section" | grep -qi "skill.*field.*category\|category.*skill.*field\|skill.*field.*map\|map.*skill.*field\|JSONL.*skill.*field"; then
    echo "  PASS: INV-006i: Per-Feature Token Cost uses JSONL skill field for mapping"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: INV-006i: Per-Feature Token Cost section does not reference JSONL skill field mapping"
    FAIL=$((FAIL + 1))
  fi

  # INV-006j: Per-Feature Token Cost section has skip-with-note for missing data
  if echo "$per_feature_section" | grep -qi "no.*token.*log.*skip\|skip.*no.*token\|no.*token.*note\|missing.*skip"; then
    echo "  PASS: INV-006j: Per-Feature Token Cost skips with note when no token logs"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: INV-006j: Per-Feature Token Cost section missing skip-with-note for no data"
    FAIL=$((FAIL + 1))
  fi

  # INV-006k: Per-Feature Token Cost table includes feature slug column
  if echo "$per_feature_section" | grep -qi "feature.*slug\|feature name\|feature identifier"; then
    echo "  PASS: INV-006k: Per-Feature Token Cost table has feature slug column"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: INV-006k: Per-Feature Token Cost table missing feature slug column"
    FAIL=$((FAIL + 1))
  fi

  # INV-006l: Per-Feature Token Cost table includes QA rounds column
  if echo "$per_feature_section" | grep -qi "QA.*round"; then
    echo "  PASS: INV-006l: Per-Feature Token Cost table has QA rounds column"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: INV-006l: Per-Feature Token Cost table missing QA rounds column"
    FAIL=$((FAIL + 1))
  fi
}

# ============================================
# INV-007: /cmetrics shows token trend across features
#   First-half/second-half split. Odd count: middle goes to
#   first half. 20% threshold. "insufficient data" for <4 features.
#   Replaces existing metric #7's vague approach.
# ============================================

test_inv007_cmetrics_token_trend() {
  echo ""
  echo "=== INV-007: /cmetrics shows token trend across features ==="

  # INV-007a: first-half/second-half split method documented
  file_contains_i "$CMETRICS_SKILL" "first.half.*second.half\|first half.*second half\|split.*two halves\|halves.*chronolog" \
    "INV-007a: cmetrics documents first-half/second-half split method"

  # INV-007b: odd count — middle feature goes to first half
  file_contains_i "$CMETRICS_SKILL" "odd.*middle.*first\|middle.*first half\|odd.*count.*first" \
    "INV-007b: odd count assigns middle feature to first half"

  # INV-007c: 20% threshold documented
  file_contains_i "$CMETRICS_SKILL" "20%\|20 percent\|twenty percent" \
    "INV-007c: 20% threshold for trend classification"

  # INV-007d: "growing" trend when second half exceeds by >20%
  file_contains_i "$CMETRICS_SKILL" "growing.*20\|20.*growing\|exceed.*20.*growing\|growing.*trend" \
    "INV-007d: 'growing' trend when second half exceeds first by >20%"

  # INV-007e: "shrinking" trend when second half is >20% lower
  file_contains_i "$CMETRICS_SKILL" "shrinking.*20\|20.*shrinking\|lower.*20.*shrinking\|shrinking.*trend" \
    "INV-007e: 'shrinking' trend when second half is >20% lower"

  # INV-007f: "stable" trend when within 20% — must appear alongside the first-half/second-half method
  # (AP-003 mitigation: anchor to 20% context to avoid matching existing "{stable/growing/shrinking}")
  file_contains_i "$CMETRICS_SKILL" "stable.*20\|20.*stable\|within.*20.*stable\|stable.*within.*20\|otherwise.*stable.*20\|20.*otherwise.*stable" \
    "INV-007f: 'stable' trend when within 20% threshold"

  # INV-007g: "insufficient data" for fewer than 4 features
  file_contains_i "$CMETRICS_SKILL" "insufficient data.*4\|4.*insufficient data\|fewer than 4.*insufficient\|insufficient.*fewer.*4\|less than 4.*insufficient" \
    "INV-007g: 'insufficient data' for fewer than 4 features"

  # INV-007h: self-contained computation (not "compare with previous metrics")
  file_contains_i "$CMETRICS_SKILL" "first.half.*average\|average.*first.half\|average.*per.*feature.*half\|half.*average.*token" \
    "INV-007h: self-contained computation using half averages"

  # INV-007i: old vague metric #7 text is replaced (not kept alongside new computation)
  file_not_contains "$CMETRICS_SKILL" "Compare with previous metrics" \
    "INV-007i: old 'Compare with previous metrics' phrasing is replaced"
}

# ============================================
# INV-008: Token threshold is a behavioral constant
#   200,000 must NOT appear in workflow-config.json or its templates
#   Follows same pattern as QA rounds (3) and findings (8)
# ============================================

test_inv008_threshold_is_constant() {
  echo ""
  echo "=== INV-008: Token threshold is a behavioral constant ==="

  # INV-008a: lite config template does NOT have token_threshold
  file_not_contains "$LITE_CFG" "token_threshold" \
    "INV-008a: lite config does not contain token_threshold"

  # INV-008b: full config template does NOT have token_threshold
  file_not_contains "$FULL_CFG" "token_threshold" \
    "INV-008b: full config does not contain token_threshold"

  # INV-008c: lite config template does NOT have 200000 or 200,000
  file_not_contains "$LITE_CFG" "200000\|200,000" \
    "INV-008c: lite config does not contain 200000/200,000"

  # INV-008d: full config template does NOT have 200000 or 200,000
  file_not_contains "$FULL_CFG" "200000\|200,000" \
    "INV-008d: full config does not contain 200000/200,000"

  # INV-008e: live project config does NOT have token_threshold
  file_not_contains "$LIVE_CFG" "token_threshold" \
    "INV-008e: live workflow-config.json does not contain token_threshold"

  # INV-008f: live project config does NOT have 200000 or 200,000
  file_not_contains "$LIVE_CFG" "200000\|200,000" \
    "INV-008f: live workflow-config.json does not contain 200000/200,000"

  # INV-008g: lite config template does NOT have calibration_token_threshold
  file_not_contains "$LITE_CFG" "calibration_token" \
    "INV-008g: lite config does not contain calibration_token*"

  # INV-008h: full config template does NOT have calibration_token_threshold
  file_not_contains "$FULL_CFG" "calibration_token" \
    "INV-008h: full config does not contain calibration_token*"

  # INV-008i: threshold IS documented in cspec SKILL.md (positive check)
  file_contains_i "$CSPEC_SKILL" "200,000\|200000" \
    "INV-008i: 200,000 threshold documented in cspec SKILL.md (behavioral constant)"
}

# ============================================
# PRH-001: No changes to token-tracking hook
#   git diff of hooks/token-tracking.sh must be empty
# ============================================

test_prh001_no_hook_changes() {
  echo ""
  echo "=== PRH-001: No changes to token-tracking hook ==="

  # PRH-001a: hooks/token-tracking.sh has no uncommitted changes
  local diff_output
  diff_output="$(cd "$REPO_DIR" && git diff -- hooks/token-tracking.sh 2>/dev/null)"
  if [ -z "$diff_output" ]; then
    echo "  PASS: PRH-001a: hooks/token-tracking.sh has no uncommitted diff"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: PRH-001a: hooks/token-tracking.sh has uncommitted changes"
    FAIL=$((FAIL + 1))
  fi

  # PRH-001b: hooks/token-tracking.sh has no staged changes
  local staged_diff
  staged_diff="$(cd "$REPO_DIR" && git diff --cached -- hooks/token-tracking.sh 2>/dev/null)"
  if [ -z "$staged_diff" ]; then
    echo "  PASS: PRH-001b: hooks/token-tracking.sh has no staged diff"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: PRH-001b: hooks/token-tracking.sh has staged changes"
    FAIL=$((FAIL + 1))
  fi

  # PRH-001c: hooks/token-tracking.sh has no changes relative to main
  local branch_diff
  branch_diff="$(cd "$REPO_DIR" && git diff main -- hooks/token-tracking.sh 2>/dev/null)"
  if [ -z "$branch_diff" ]; then
    echo "  PASS: PRH-001c: hooks/token-tracking.sh unchanged from main"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: PRH-001c: hooks/token-tracking.sh differs from main"
    FAIL=$((FAIL + 1))
  fi
}

# ============================================
# PRH-002: actual_tokens never used as a standalone signal
#   Token/cost references must NOT appear in Step 7 signal
#   evaluation — only in Step 7b (calibration section)
# ============================================

test_prh002_no_standalone_signal() {
  echo ""
  echo "=== PRH-002: actual_tokens never used as a standalone signal ==="

  # PRH-002a: Step 7 (signal evaluation) does NOT mention actual_tokens
  # Extract Step 7 section EXCLUDING Step 7b (calibration is allowed)
  local step7_text
  step7_text="$(sed -n '/^### Step 7: Run Intensity Detection/,/^### Step 7b/p' "$CSPEC_SKILL" 2>/dev/null)"
  if echo "$step7_text" | grep -qi "actual_tokens"; then
    echo "  FAIL: PRH-002a: Step 7 signal evaluation contains 'actual_tokens' (should only be in Step 7b)"
    FAIL=$((FAIL + 1))
  else
    echo "  PASS: PRH-002a: Step 7 signal evaluation does not mention actual_tokens"
    PASS=$((PASS + 1))
  fi

  # PRH-002b: Step 7 (signal evaluation) does NOT mention token_threshold
  if echo "$step7_text" | grep -qi "token_threshold\|token.*threshold"; then
    echo "  FAIL: PRH-002b: Step 7 signal evaluation contains token threshold references"
    FAIL=$((FAIL + 1))
  else
    echo "  PASS: PRH-002b: Step 7 signal evaluation does not mention token thresholds"
    PASS=$((PASS + 1))
  fi

  # PRH-002c: Step 7 (signal evaluation) does NOT mention 200,000 or 200000
  if echo "$step7_text" | grep -qi "200,000\|200000"; then
    echo "  FAIL: PRH-002c: Step 7 signal evaluation contains 200K token threshold"
    FAIL=$((FAIL + 1))
  else
    echo "  PASS: PRH-002c: Step 7 signal evaluation does not contain 200K threshold"
    PASS=$((PASS + 1))
  fi

  # PRH-002d: Step 7b IS the location for actual_tokens (positive confirmation)
  # This will fail until implementation adds actual_tokens to Step 7b
  section_contains "$CSPEC_SKILL" "Step 7b" "actual_tokens" \
    "PRH-002d: actual_tokens appears in Step 7b (calibration), not Step 7 (signals)"

  # PRH-002e: Intensity Detection section does NOT list token as a signal
  # Extract the Intensity Detection section and verify token is not a signal number
  local detection_section
  detection_section="$(sed -n '/^## Intensity Detection/,/^## /p' "$CSPEC_SKILL" 2>/dev/null)"
  if echo "$detection_section" | grep -Ei "signal.*5.*token\|5th.*signal.*token\|token.*5th.*signal\|signal.*token.*cost" | grep -qvi "calibration\|post-signal\|NOT.*5th"; then
    echo "  FAIL: PRH-002e: Intensity Detection section lists token as a signal"
    FAIL=$((FAIL + 1))
  else
    echo "  PASS: PRH-002e: Intensity Detection section does not list token as a signal"
    PASS=$((PASS + 1))
  fi
}

# ============================================
# Runner
# ============================================

echo "============================================="
echo "Token-Aware Intensity Calibration Test Suite"
echo "============================================="

test_inv001_cverify_writes_actual_tokens
test_inv002_cspec_reads_actual_tokens
test_inv003_token_threshold_active_mode
test_inv004_passive_token_arithmetic
test_inv005_missing_actual_tokens_graceful
test_inv006_cmetrics_per_feature_table
test_inv007_cmetrics_token_trend
test_inv008_threshold_is_constant
test_prh001_no_hook_changes
test_prh002_no_standalone_signal

echo ""
echo "============================================="
echo "Results: $PASS passed, $FAIL failed"
echo "============================================="

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
