#!/usr/bin/env bash
# Correctless — Auto-Promote Recurring Antipatterns test suite
# Tests spec rules INV-001 through INV-008 and PRH-001/PRH-002 from
# .correctless/specs/auto-recurring-patterns.md
# Run from repo root: bash tests/test-auto-recurring-patterns.sh

set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CSPEC_SKILL="$REPO_DIR/skills/cspec/SKILL.md"
CPOSTMORTEM_SKILL="$REPO_DIR/skills/cpostmortem/SKILL.md"
LITE_CFG="$REPO_DIR/templates/workflow-config.json"
FULL_CFG="$REPO_DIR/templates/workflow-config-full.json"
PASS=0
FAIL=0

# ============================================
# Helpers (matching project test conventions)
# ============================================

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

# ============================================
# INV-001 [unit]: /cspec suggests promotion for high-frequency antipatterns (capped at 2)
#   Step 5 must check frequency field, suggest promotion for 3+ features,
#   and cap at 2 promotion suggestions per invocation
# ============================================

test_inv001_cspec_promotion_suggestion() {
  echo ""
  echo "=== INV-001: /cspec suggests promotion for high-frequency antipatterns ==="

  # Tests INV-001 [unit]: cspec Step 5 checks antipattern frequency
  file_contains_i "$CSPEC_SKILL" "frequency\|Frequency" \
    "INV-001a: cspec SKILL.md references antipattern Frequency field"

  # Tests INV-001 [unit]: cspec suggests promotion when threshold met
  file_contains_i "$CSPEC_SKILL" "promot" \
    "INV-001b: cspec SKILL.md contains promotion language"

  # Tests INV-001 [unit]: cspec caps promotion suggestions at 2 per invocation
  # (AP-003 mitigation: anchor to promotion context to avoid matching "Wait 2-3 minutes")
  file_contains_i "$CSPEC_SKILL" "at most 2.*promot\|2.*promot.*per.*invocation\|cap.*2.*promot\|promot.*cap.*2\|maximum of 2.*promot" \
    "INV-001c: cspec SKILL.md caps promotion suggestions at 2 per invocation"

  # Tests INV-001 [unit]: promotion is in the context of antipatterns and architecture
  file_contains_i "$CSPEC_SKILL" "promot.*ARCHITECTURE\|ARCHITECTURE.*promot\|promot.*PAT-\|promot.*ABS-" \
    "INV-001d: cspec promotion references ARCHITECTURE.md entries (PAT-xxx or ABS-xxx)"

  # Tests INV-001 [unit]: remaining qualifying entries deferred to next run
  # (AP-003 mitigation: anchor to promotion context to avoid matching existing Defer option)
  file_contains_i "$CSPEC_SKILL" "defer.*promot.*remaining\|remaining.*promot.*defer\|defer.*remaining.*next\|beyond.*cap.*defer\|promot.*defer.*next" \
    "INV-001e: cspec defers remaining promotion suggestions beyond cap"
}

# ============================================
# INV-002a [unit]: /cpostmortem checks frequency after antipattern creation/update
#   Step 3 checks whether new/updated AP-xxx meets 3-feature threshold
# ============================================

test_inv002a_cpostmortem_frequency_check() {
  echo ""
  echo "=== INV-002a: /cpostmortem checks frequency after antipattern creation/update ==="

  # Tests INV-002a [unit]: cpostmortem references frequency check
  file_contains_i "$CPOSTMORTEM_SKILL" "frequency\|Frequency" \
    "INV-002a-a: cpostmortem SKILL.md references Frequency field"

  # Tests INV-002a [unit]: cpostmortem suggests promotion
  file_contains_i "$CPOSTMORTEM_SKILL" "promot" \
    "INV-002a-b: cpostmortem SKILL.md contains promotion language"

  # Tests INV-002a [unit]: promotion suggestion tied to creation/update of AP-xxx
  # (AP-003 mitigation: anchored fallbacks to AP-xxx context)
  file_contains_i "$CPOSTMORTEM_SKILL" "creat.*AP-\|update.*AP-\|AP-.*creat\|AP-.*update\|after.*creat.*AP-\|after.*update.*AP-" \
    "INV-002a-c: cpostmortem ties promotion to AP-xxx creation/update"
}

# ============================================
# INV-002b [unit]: Prefer threshold crossings over pre-existing entries
#   cpostmortem should prefer entries that just crossed the threshold
# ============================================

test_inv002b_threshold_crossing_preference() {
  echo ""
  echo "=== INV-002b: Prefer threshold crossings over pre-existing entries ==="

  # Tests INV-002b [unit]: cpostmortem contains language about threshold crossing
  file_contains_i "$CPOSTMORTEM_SKILL" "just crossed\|newly meets\|threshold crossing\|cross.*threshold\|just.*reach\|newly.*reach" \
    "INV-002b-a: cpostmortem SKILL.md prefers threshold crossings"
}

# ============================================
# INV-003 [unit]: Promotion drafts a PAT-xxx or ABS-xxx skeleton
#   Both skills must draft entries with Guards against, How to catch it,
#   and What went wrong references
# ============================================

test_inv003_draft_entry_skeleton() {
  echo ""
  echo "=== INV-003: Promotion drafts a PAT-xxx or ABS-xxx skeleton ==="

  # Tests INV-003 [unit]: cspec references "Guards against" in promotion draft context
  # (AP-003 mitigation: require co-occurrence with promotion to avoid matching existing
  # spec template which has "Guards against: {AP-xxx or null}")
  file_contains_i "$CSPEC_SKILL" "promot.*Guards against\|Guards against.*promot\|draft.*Guards against.*AP-\|Guards against.*AP-.*draft" \
    "INV-003a: cspec promotion draft includes Guards against field with AP-xxx"

  # Tests INV-003 [unit]: cspec references "How to catch it" for pre-populating draft
  # (AP-003 mitigation: anchor to promotion/draft context)
  file_contains_i "$CSPEC_SKILL" "promot.*How to catch it\|draft.*How to catch it\|How to catch it.*pre-populate\|How to catch it.*promot" \
    "INV-003b: cspec draft references How to catch it section"

  # Tests INV-003 [unit]: cspec references "What went wrong" for the draft
  # (AP-003 mitigation: anchor to promotion/draft context)
  file_contains_i "$CSPEC_SKILL" "promot.*What went wrong\|draft.*What went wrong\|What went wrong.*promot\|What went wrong.*Violated" \
    "INV-003c: cspec draft references What went wrong section"

  # Tests INV-003 [unit]: cpostmortem references "Guards against" field with AP-xxx
  # (AP-003 mitigation: removed bare "Guards against" fallback — require AP-xxx or promotion context)
  file_contains_i "$CPOSTMORTEM_SKILL" "Guards against.*AP-\|promot.*Guards against\|draft.*Guards against" \
    "INV-003d: cpostmortem draft entry includes Guards against field"

  # Tests INV-003 [unit]: cpostmortem references "How to catch it" for pre-populating draft
  # (AP-003 mitigation: anchor to promotion/draft context)
  file_contains_i "$CPOSTMORTEM_SKILL" "promot.*How to catch it\|draft.*How to catch it\|How to catch it.*pre-populate\|How to catch it.*promot" \
    "INV-003e: cpostmortem draft references How to catch it section"

  # Tests INV-003 [unit]: cpostmortem references "What went wrong" for the draft
  # (AP-003 mitigation: anchor to promotion/draft context)
  file_contains_i "$CPOSTMORTEM_SKILL" "promot.*What went wrong\|draft.*What went wrong\|What went wrong.*promot\|What went wrong.*Violated" \
    "INV-003f: cpostmortem draft references What went wrong section"

  # Tests INV-003 [unit]: draft follows PAT-xxx or ABS-xxx structure in promotion context
  # (AP-003 mitigation: require co-occurrence with promotion/draft to avoid matching
  # existing ABS-xxx references in architecture sections)
  file_contains_i "$CSPEC_SKILL" "promot.*PAT-.*ABS-\|promot.*ABS-.*PAT-\|draft.*PAT-xxx\|draft.*ABS-xxx\|PAT-xxx.*ABS-xxx.*promot" \
    "INV-003g: cspec promotion draft mentions PAT-xxx or ABS-xxx entry structure"

  file_contains_i "$CPOSTMORTEM_SKILL" "promot.*PAT-.*ABS-\|promot.*ABS-.*PAT-\|draft.*PAT-xxx\|draft.*ABS-xxx\|PAT-xxx.*ABS-xxx.*promot" \
    "INV-003h: cpostmortem promotion draft mentions PAT-xxx or ABS-xxx entry structure"
}

# ============================================
# INV-004 [unit]: Deduplication — skip already-promoted antipatterns
#   Both skills must check ARCHITECTURE.md for existing AP-xxx references
# ============================================

test_inv004_deduplication() {
  echo ""
  echo "=== INV-004: Deduplication — skip already-promoted antipatterns ==="

  # Tests INV-004 [unit]: cspec checks ARCHITECTURE.md for existing AP-xxx
  file_contains_i "$CSPEC_SKILL" "ARCHITECTURE.*AP-\|AP-.*ARCHITECTURE\|already.*promot\|dedup\|skip.*already" \
    "INV-004a: cspec checks ARCHITECTURE.md for already-promoted AP-xxx"

  # Tests INV-004 [unit]: cpostmortem checks ARCHITECTURE.md for existing AP-xxx
  # (AP-003 mitigation: anchor to promotion context to avoid matching existing deduplication
  # for PMB entries — "skip (deduplication)" already appears in cpostmortem)
  file_contains_i "$CPOSTMORTEM_SKILL" "ARCHITECTURE.*AP-.*promot\|AP-.*ARCHITECTURE.*promot\|already.*promot.*AP-\|promot.*dedup\|promot.*skip.*already" \
    "INV-004b: cpostmortem checks ARCHITECTURE.md for already-promoted AP-xxx"
}

# ============================================
# INV-005 [unit]: Structured decision format for promotion
#   Both skills present numbered options: Add, Skip, Modify, Defer
# ============================================

test_inv005_structured_decision() {
  echo ""
  echo "=== INV-005: Structured decision format for promotion ==="

  # Tests INV-005 [unit]: cspec has all four promotion decision options together
  # (AP-003 mitigation: require promotion-specific numbering "1. Add" + "2. Skip"
  # to avoid matching existing risk mitigation decisions like "1. Mitigate")
  file_contains_i "$CSPEC_SKILL" "1.*Add.*promot\|Add.*ARCHITECTURE.*recommended\|1.*Add.*architecture" \
    "INV-005a: cspec promotion has Add option"

  file_contains_i "$CSPEC_SKILL" "2.*Skip.*promot\|Skip.*doesn.t warrant\|2.*Skip.*architecture" \
    "INV-005b: cspec promotion has Skip option"

  file_contains_i "$CSPEC_SKILL" "3.*Modify.*draft\|Modify.*before.*add\|3.*Modify.*promot" \
    "INV-005c: cspec promotion has Modify option"

  file_contains_i "$CSPEC_SKILL" "4.*Defer.*promot\|Defer.*revisit.*future\|4.*Defer.*feature" \
    "INV-005d: cspec promotion has Defer option"

  # Tests INV-005 [unit]: cpostmortem has all four promotion decision options
  file_contains_i "$CPOSTMORTEM_SKILL" "1.*Add.*promot\|Add.*ARCHITECTURE.*recommended\|1.*Add.*architecture" \
    "INV-005e: cpostmortem promotion has Add option"

  file_contains_i "$CPOSTMORTEM_SKILL" "2.*Skip.*promot\|Skip.*doesn.t warrant\|2.*Skip.*architecture" \
    "INV-005f: cpostmortem promotion has Skip option"

  file_contains_i "$CPOSTMORTEM_SKILL" "3.*Modify.*draft\|Modify.*before.*add\|3.*Modify.*promot" \
    "INV-005g: cpostmortem promotion has Modify option"

  file_contains_i "$CPOSTMORTEM_SKILL" "4.*Defer.*promot\|Defer.*revisit.*future\|4.*Defer.*feature" \
    "INV-005h: cpostmortem promotion has Defer option"

  # Tests INV-005 [unit]: both have "Or type your own" escape hatch in promotion context
  # (AP-003 mitigation: anchor to promotion context — removed unanchored Add.*Skip.*Modify.*Defer fallback)
  file_contains_i "$CSPEC_SKILL" "promot.*type your own\|promot.*Or type\|type your own.*promot" \
    "INV-005i: cspec promotion decision has 'Or type your own' escape hatch"

  file_contains_i "$CPOSTMORTEM_SKILL" "promot.*type your own\|promot.*Or type\|type your own.*promot" \
    "INV-005j: cpostmortem promotion decision has 'Or type your own' escape hatch"
}

# ============================================
# INV-006 [unit]: Threshold is 3 features
#   Both skills use 3 features as the promotion threshold
#   and handle missing/malformed frequency gracefully
# ============================================

test_inv006_threshold_value() {
  echo ""
  echo "=== INV-006: Threshold is 3 features ==="

  # Tests INV-006 [unit]: cspec references threshold of 3 features in promotion context
  # (AP-003 mitigation: anchor to promotion/frequency context to avoid matching
  # unrelated "3" + "feature" occurrences like "3 features touching these paths")
  file_contains_i "$CSPEC_SKILL" "3.*feature.*promot\|promot.*3.*feature\|threshold.*3.*feature.*frequency\|frequency.*3.*feature" \
    "INV-006a: cspec SKILL.md uses promotion threshold of 3 features"

  # Tests INV-006 [unit]: cpostmortem references threshold of 3 features in promotion context
  file_contains_i "$CPOSTMORTEM_SKILL" "3.*feature.*promot\|promot.*3.*feature\|threshold.*3.*feature.*frequency\|frequency.*3.*feature" \
    "INV-006b: cpostmortem SKILL.md uses promotion threshold of 3 features"

  # Tests INV-006 [unit]: cspec handles missing/malformed frequency gracefully
  file_contains_i "$CSPEC_SKILL" "missing.*frequency\|malformed.*frequency\|unparsable\|absent.*frequency\|skip.*frequency\|cannot.*parse" \
    "INV-006c: cspec handles missing/malformed frequency gracefully"

  # Tests INV-006 [unit]: cpostmortem handles missing/malformed frequency gracefully
  file_contains_i "$CPOSTMORTEM_SKILL" "missing.*frequency\|malformed.*frequency\|unparsable\|absent.*frequency\|skip.*frequency\|cannot.*parse" \
    "INV-006d: cpostmortem handles missing/malformed frequency gracefully"

  # Tests INV-006 [unit]: parses "N findings across M features" format
  file_contains_i "$CSPEC_SKILL" "findings across.*features\|N findings across M features\|across.*features" \
    "INV-006e: cspec parses 'N findings across M features' format"

  file_contains_i "$CPOSTMORTEM_SKILL" "findings across.*features\|N findings across M features\|across.*features" \
    "INV-006f: cpostmortem parses 'N findings across M features' format"
}

# ============================================
# INV-007 [unit]: /cspec promotion runs after relevance check
#   Promotion fires regardless of relevance to current feature
# ============================================

test_inv007_promotion_after_relevance() {
  echo ""
  echo "=== INV-007: /cspec promotion runs after relevance check ==="

  # Tests INV-007 [unit]: promotion is separate from relevance check
  file_contains_i "$CSPEC_SKILL" "regardless of.*relev\|separate.*from.*relev\|independent.*of.*relev\|whether or not.*relev" \
    "INV-007a: cspec promotion fires regardless of relevance to current feature"

  # Tests INV-007 [unit]: promotion check described as a distinct concern from relevance
  file_contains_i "$CSPEC_SKILL" "after.*relevance.*check\|relevance.*then.*promot\|separate concern\|promot.*separate" \
    "INV-007b: cspec promotion is a separate concern from relevance check"
}

# ============================================
# INV-008 [unit]: /cpostmortem has write permission for ARCHITECTURE.md
#   Frontmatter allowed-tools must include Write(.correctless/ARCHITECTURE.md)
# ============================================

test_inv008_cpostmortem_write_permission() {
  echo ""
  echo "=== INV-008: /cpostmortem has write permission for ARCHITECTURE.md ==="

  # Tests INV-008 [unit]: cpostmortem frontmatter includes Write permission for ARCHITECTURE.md
  file_contains "$CPOSTMORTEM_SKILL" 'Write(.correctless/ARCHITECTURE.md)' \
    "INV-008a: cpostmortem allowed-tools includes Write(.correctless/ARCHITECTURE.md)"
}

# ============================================
# PRH-001 [unit]: No auto-writing to ARCHITECTURE.md
#   Both skills must gate ARCHITECTURE.md writes on human approval
# ============================================

test_prh001_no_auto_write() {
  echo ""
  echo "=== PRH-001: No auto-writing to ARCHITECTURE.md ==="

  # Tests PRH-001 [unit]: cspec requires human approval before writing to ARCHITECTURE.md
  file_contains_i "$CSPEC_SKILL" "human.*approv.*ARCHITECTURE\|ARCHITECTURE.*human.*approv\|user.*approv.*ARCHITECTURE\|human.*choose.*Add\|user.*choose.*Add\|approval.*before.*writ.*ARCHITECTURE" \
    "PRH-001a: cspec gates ARCHITECTURE.md writes on human approval"

  # Tests PRH-001 [unit]: cpostmortem requires human approval before writing to ARCHITECTURE.md
  file_contains_i "$CPOSTMORTEM_SKILL" "human.*approv.*ARCHITECTURE\|ARCHITECTURE.*human.*approv\|user.*approv.*ARCHITECTURE\|human.*choose.*Add\|user.*choose.*Add\|approval.*before.*writ.*ARCHITECTURE" \
    "PRH-001b: cpostmortem gates ARCHITECTURE.md writes on human approval"
}

# ============================================
# PRH-002 [unit]: v1 threshold is a behavioral constant
#   Config templates must NOT contain promotion_threshold or similar fields
#   Threshold lives in skill files, not config
# ============================================

test_prh002_no_threshold_in_config() {
  echo ""
  echo "=== PRH-002: v1 threshold is a behavioral constant ==="

  # Tests PRH-002 [unit]: lite config does NOT have promotion_threshold
  file_not_contains "$LITE_CFG" "promotion_threshold" \
    "PRH-002a: lite config does not contain promotion_threshold"

  # Tests PRH-002 [unit]: full config does NOT have promotion_threshold
  file_not_contains "$FULL_CFG" "promotion_threshold" \
    "PRH-002b: full config does not contain promotion_threshold"

  # Tests PRH-002 [unit]: lite config does NOT have antipattern_promotion
  file_not_contains "$LITE_CFG" "antipattern_promotion" \
    "PRH-002c: lite config does not contain antipattern_promotion"

  # Tests PRH-002 [unit]: full config does NOT have antipattern_promotion
  file_not_contains "$FULL_CFG" "antipattern_promotion" \
    "PRH-002d: full config does not contain antipattern_promotion"

  # Tests PRH-002 [unit]: lite config does NOT have promotion_feature_threshold
  file_not_contains "$LITE_CFG" "promotion_feature_threshold" \
    "PRH-002e: lite config does not contain promotion_feature_threshold"

  # Tests PRH-002 [unit]: full config does NOT have promotion_feature_threshold
  file_not_contains "$FULL_CFG" "promotion_feature_threshold" \
    "PRH-002f: full config does not contain promotion_feature_threshold"
}

# ============================================
# Runner
# ============================================

echo "============================================="
echo "Auto-Promote Recurring Antipatterns Test Suite"
echo "============================================="

test_inv001_cspec_promotion_suggestion
test_inv002a_cpostmortem_frequency_check
test_inv002b_threshold_crossing_preference
test_inv003_draft_entry_skeleton
test_inv004_deduplication
test_inv005_structured_decision
test_inv006_threshold_value
test_inv007_promotion_after_relevance
test_inv008_cpostmortem_write_permission
test_prh001_no_auto_write
test_prh002_no_threshold_in_config

echo ""
echo "============================================="
echo "Results: $PASS passed, $FAIL failed"
echo "============================================="

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
