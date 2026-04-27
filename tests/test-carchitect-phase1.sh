#!/usr/bin/env bash
# shellcheck disable=SC1090,SC1091,SC2016,SC2086
# Correctless — /carchitect Phase 1 Structural Tests
#
# Enforces the carchitect-phase1 spec rules (R-001..R-009).
# Tests are structural — they verify prompt text in skills/ctdd/SKILL.md,
# test audit check content, and documentation updates.
# LLM-behavioral rules are tested only on their mechanical envelope:
# required prompt phrases, check descriptions, and doc references.
#
# Run from repo root: bash tests/test-carchitect-phase1.sh

source "$(dirname "${BASH_SOURCE[0]}")/test-helpers.sh"
set -f

# ============================================================================
# File paths
# ============================================================================

CTDD_SKILL="skills/ctdd/SKILL.md"
CTDD_DIST="correctless/skills/ctdd/SKILL.md"
# Post-M-1 (2026-04-26): RED-phase prompt content lives in agents/ctdd-red.md
# (single source of truth per ABS-010). Tests checking RED-phase guidance must
# search both files — content may legitimately live in either.
CTDD_RED_AGENT="agents/ctdd-red.md"
DOCS_CTDD="docs/skills/ctdd.md"
AGENT_CONTEXT=".correctless/AGENT_CONTEXT.md"
CONTRIBUTING_MD="CONTRIBUTING.md"

# ============================================================================
# R-001 [unit]: RED phase prompt references entrypoints for integration tests
# ============================================================================

section "R-001: RED phase prompt references entrypoints for integration tests"

# R-001a: RED phase prompt instructs agent to read entrypoints from ARCHITECTURE.md
if grep -q 'entrypoints.*ARCHITECTURE.md\|ARCHITECTURE.md.*entrypoints' "$CTDD_SKILL"; then
  pass "R-001a" "RED phase prompt references entrypoints from ARCHITECTURE.md"
else
  fail "R-001a" "RED phase prompt does not reference entrypoints from ARCHITECTURE.md"
fi

# R-001b: RED phase prompt instructs writing integration tests through entrypoints
if grep -qi 'test_via\|through.*entrypoint\|through that entrypoint' "$CTDD_SKILL"; then
  pass "R-001b" "RED phase prompt references test_via/entrypoint pattern"
else
  fail "R-001b" "RED phase prompt does not reference test_via or entrypoint pattern"
fi

# R-001c: Instruction mentions matching rule scope to entrypoint scope
if grep -qi 'scope.*glob\|entrypoint.*scope\|scope.*entrypoint' "$CTDD_SKILL"; then
  pass "R-001c" "RED phase prompt references entrypoint scope matching"
else
  fail "R-001c" "RED phase prompt does not reference entrypoint scope matching"
fi

# R-001d: Instruction explicitly says not to import internal packages directly
# Post-M-1: search the agent file (canonical) AND SKILL.md (orchestrator-side audit checks may reference it).
if grep -qi 'not.*import.*internal.*direct\|not by importing internal' "$CTDD_SKILL" "$CTDD_RED_AGENT"; then
  pass "R-001d" "RED phase prompt warns against direct internal imports"
else
  fail "R-001d" "RED phase prompt does not warn against direct internal imports"
fi

# ============================================================================
# R-002 [unit]: RED phase prompt references Key Patterns, Layer Conventions,
#               Trust Boundaries
# ============================================================================

section "R-002: RED phase prompt references architecture patterns"

# R-002a: Prompt mentions Key Patterns
if grep -q 'Key Patterns' "$CTDD_SKILL"; then
  pass "R-002a" "RED phase prompt references Key Patterns"
else
  fail "R-002a" "RED phase prompt does not reference Key Patterns"
fi

# R-002b: Prompt mentions Layer Conventions
if grep -q 'Layer Conventions' "$CTDD_SKILL" "$CTDD_RED_AGENT"; then
  pass "R-002b" "RED phase prompt references Layer Conventions"
else
  fail "R-002b" "RED phase prompt does not reference Layer Conventions"
fi

# R-002c: Prompt mentions Trust Boundaries
if grep -q 'Trust Boundaries' "$CTDD_SKILL" "$CTDD_RED_AGENT"; then
  pass "R-002c" "RED phase prompt references Trust Boundaries"
else
  fail "R-002c" "RED phase prompt does not reference Trust Boundaries"
fi

# R-002d: Instruction mentions layer access constraints for tests
if grep -qi 'layer.*should not.*access\|should not be accessed directly' "$CTDD_SKILL" "$CTDD_RED_AGENT"; then
  pass "R-002d" "RED phase prompt includes layer access constraints"
else
  fail "R-002d" "RED phase prompt does not include layer access constraints"
fi

# ============================================================================
# R-003 [unit]: RED phase Read context list emphasizes entrypoints
# ============================================================================

section "R-003: RED phase Read context list emphasizes entrypoints"

# R-003a: The Read line mentions "especially the Entrypoints section"
if grep -qi 'especially.*Entrypoints\|Entrypoints section' "$CTDD_SKILL"; then
  pass "R-003a" "Read context list emphasizes Entrypoints section"
else
  fail "R-003a" "Read context list does not emphasize Entrypoints section"
fi

# R-003b: The Read line mentions Key Patterns alongside Entrypoints
if grep -qi 'Entrypoints.*Key Patterns\|Key Patterns.*Entrypoints' "$CTDD_SKILL"; then
  pass "R-003b" "Read context list mentions both Entrypoints and Key Patterns"
else
  fail "R-003b" "Read context list does not mention both Entrypoints and Key Patterns"
fi

# ============================================================================
# R-004 [unit]: Graceful fallback when no entrypoints exist
# ============================================================================

section "R-004: Graceful fallback when no entrypoints exist"

# R-004a: RED phase prompt includes fallback instruction for missing entrypoints
if grep -qi 'no.*entrypoints.*section\|no.*correctless:entrypoints:start' "$CTDD_SKILL"; then
  pass "R-004a" "RED phase prompt includes missing entrypoints fallback"
else
  fail "R-004a" "RED phase prompt does not include missing entrypoints fallback"
fi

# R-004b: Fallback mentions a comment marker for the gap
if grep -qi 'No documented entrypoint' "$CTDD_SKILL"; then
  pass "R-004b" "Fallback includes 'No documented entrypoint' comment marker"
else
  fail "R-004b" "Fallback does not include 'No documented entrypoint' comment marker"
fi

# R-004c: Fallback mentions using best available entry point
if grep -qi 'best available entry point\|inferred entry point' "$CTDD_SKILL" "$CTDD_RED_AGENT"; then
  pass "R-004c" "Fallback mentions using best available/inferred entry point"
else
  fail "R-004c" "Fallback does not mention using best available/inferred entry point"
fi

# ============================================================================
# R-005 [unit]: Test audit check 10 — internal import bypass detection
# ============================================================================

section "R-005: Test audit check 10 — internal import bypass detection"

# R-005a: Test audit section contains a check numbered 10
if grep -qE '10\.\s|check 10|10\. \*\*' "$CTDD_SKILL"; then
  pass "R-005a" "Test audit contains check 10"
else
  fail "R-005a" "Test audit does not contain check 10"
fi

# R-005b: Check 10 mentions "internal import bypass" or "import bypass"
if grep -qi 'internal import bypass\|import.*bypass.*detection\|Internal import bypass' "$CTDD_SKILL"; then
  pass "R-005b" "Check 10 mentions internal import bypass detection"
else
  fail "R-005b" "Check 10 does not mention internal import bypass detection"
fi

# R-005c: Check 10 is marked as BLOCKING
if grep -qi 'import.*bypass.*BLOCKING\|BLOCKING.*import.*bypass\|BLOCKING.*internal.*import' "$CTDD_SKILL"; then
  pass "R-005c" "Check 10 internal import bypass is BLOCKING severity"
else
  # Also check if BLOCKING appears near the check 10 section
  check10_line=$(grep -n 'internal import bypass\|Internal import bypass' "$CTDD_SKILL" 2>/dev/null | head -1 | cut -d: -f1)
  if [ -n "$check10_line" ]; then
    # Look within 15 lines for BLOCKING
    nearby_blocking=$(sed -n "$((check10_line)),$((check10_line + 15))p" "$CTDD_SKILL" | grep -c 'BLOCKING') || nearby_blocking=0
    if [ "$nearby_blocking" -gt 0 ]; then
      pass "R-005c" "Check 10 internal import bypass has BLOCKING severity (nearby)"
    else
      fail "R-005c" "Check 10 internal import bypass does not have BLOCKING severity"
    fi
  else
    fail "R-005c" "Check 10 internal import bypass section not found"
  fi
fi

# R-005d: Check 10 mentions consolidation with check 9 when both fire
if grep -qi 'consolidat.*finding\|one.*finding.*rather than two\|consolidated' "$CTDD_SKILL"; then
  pass "R-005d" "Check 10 mentions consolidation with check 9"
else
  fail "R-005d" "Check 10 does not mention consolidation with check 9"
fi

# R-005e: Check 10 mentions entrypoint test_via pattern in the bypass finding message
if grep -qi 'test_via\|use.*entrypoint.*instead' "$CTDD_SKILL"; then
  pass "R-005e" "Check 10 references test_via in bypass finding"
else
  fail "R-005e" "Check 10 does not reference test_via in bypass finding"
fi

# ============================================================================
# R-006 [unit]: Language-aware import detection patterns
# ============================================================================

section "R-006: Language-aware import detection"

# R-006a: Check 10 mentions Go import pattern
if grep -qE 'Go.*import|import.*pkg/' "$CTDD_SKILL"; then
  pass "R-006a" "Check 10 includes Go import detection pattern"
else
  fail "R-006a" "Check 10 does not include Go import detection pattern"
fi

# R-006b: Check 10 mentions TypeScript/JavaScript import pattern
if grep -qE 'TypeScript|JavaScript|import.*from|require\(' "$CTDD_SKILL"; then
  pass "R-006b" "Check 10 includes TypeScript/JavaScript import detection pattern"
else
  fail "R-006b" "Check 10 does not include TypeScript/JavaScript import detection pattern"
fi

# R-006c: Check 10 mentions Python import pattern
if grep -qE 'Python.*import|from.*import|import.*pkg' "$CTDD_SKILL"; then
  pass "R-006c" "Check 10 includes Python import detection pattern"
else
  fail "R-006c" "Check 10 does not include Python import detection pattern"
fi

# R-006d: Check 10 mentions Rust import pattern
if grep -qE 'Rust|use crate|mod ' "$CTDD_SKILL"; then
  pass "R-006d" "Check 10 includes Rust import detection pattern"
else
  fail "R-006d" "Check 10 does not include Rust import detection pattern"
fi

# R-006e: Check 10 mentions ADVISORY skip for unsupported languages
if grep -qi 'ADVISORY.*language\|language.*ADVISORY\|Cannot detect.*internal.*import\|manual review recommended' "$CTDD_SKILL"; then
  pass "R-006e" "Check 10 includes ADVISORY skip for unsupported languages"
else
  fail "R-006e" "Check 10 does not include ADVISORY skip for unsupported languages"
fi

# R-006f: Check 10 reads entrypoints from ARCHITECTURE.md
if grep -qi 'entrypoints.*ARCHITECTURE\|ARCHITECTURE.*entrypoints\|extract-entrypoints' "$CTDD_SKILL"; then
  pass "R-006f" "Check 10 references entrypoints from ARCHITECTURE.md"
else
  fail "R-006f" "Check 10 does not reference entrypoints from ARCHITECTURE.md"
fi

# ============================================================================
# R-007 [unit]: Entrypoint self-import exclusion
# ============================================================================

section "R-007: Entrypoint self-import exclusion"

# R-007a: Check 10 explicitly excludes imports of the entrypoint itself
if grep -qi 'NOT flag.*import.*entrypoint itself\|does NOT flag import.*of the entrypoint\|not flag.*entrypoint.*import\|import.*entrypoint.*itself' "$CTDD_SKILL"; then
  pass "R-007a" "Check 10 excludes self-imports of entrypoints"
else
  fail "R-007a" "Check 10 does not exclude self-imports of entrypoints"
fi

# R-007b: Exclusion distinguishes scope (behind entrypoint) from entrypoint itself
if grep -qi 'within.*scope\|behind.*entrypoint\|through.*entrypoint\|packages.*within.*scope' "$CTDD_SKILL"; then
  pass "R-007b" "Check 10 distinguishes scope packages from entrypoint itself"
else
  fail "R-007b" "Check 10 does not distinguish scope packages from entrypoint itself"
fi

# ============================================================================
# R-008 [unit]: Graceful skip when no entrypoints
# ============================================================================

section "R-008: Test audit graceful skip when no entrypoints"

# R-008a: Test audit mentions skip message for missing entrypoints
if grep -qi 'No documented entrypoints.*internal import bypass.*skipped\|entrypoints.*skipped\|bypass check.*skipped' "$CTDD_SKILL"; then
  pass "R-008a" "Test audit includes skip message for missing entrypoints"
else
  fail "R-008a" "Test audit does not include skip message for missing entrypoints"
fi

# R-008b: Skip is consistent with R-004 fallback approach
# Both R-004 (RED agent) and R-008 (test audit) should handle missing entrypoints gracefully
# The test audit skip message should reference missing markers or no entrypoints
if grep -qi 'ARCHITECTURE.md.*missing\|no entrypoints.*marker\|no.*correctless:entrypoints' "$CTDD_SKILL"; then
  pass "R-008b" "Test audit skip references ARCHITECTURE.md or marker absence"
else
  # Accept a softer match — just "no documented entrypoints" is consistent
  if grep -qi 'No documented entrypoints' "$CTDD_SKILL"; then
    pass "R-008b" "Test audit skip references 'No documented entrypoints' (consistent with R-004)"
  else
    fail "R-008b" "Test audit skip does not reference entrypoint absence condition"
  fi
fi

# ============================================================================
# R-009 [unit]: Documentation updates
# ============================================================================

section "R-009: Documentation updates"

# R-009a: docs/skills/ctdd.md mentions entrypoint-aware test writing
if grep -qi 'entrypoint.*aware\|entrypoint.*test\|internal import bypass' "$DOCS_CTDD"; then
  pass "R-009a" "docs/skills/ctdd.md documents entrypoint-aware test writing"
else
  fail "R-009a" "docs/skills/ctdd.md does not document entrypoint-aware test writing"
fi

# R-009b: docs/skills/ctdd.md mentions internal import bypass check
if grep -qi 'internal import\|import bypass\|check 10' "$DOCS_CTDD"; then
  pass "R-009b" "docs/skills/ctdd.md documents internal import bypass check"
else
  fail "R-009b" "docs/skills/ctdd.md does not document internal import bypass check"
fi

# R-009c: .correctless/AGENT_CONTEXT.md references Phase 1
if grep -qi 'Phase 1\|entrypoint-aware\|carchitect.*phase.*1\|entrypoint.*aware.*TDD' "$AGENT_CONTEXT"; then
  pass "R-009c" "AGENT_CONTEXT.md references Phase 1 / entrypoint-aware TDD"
else
  fail "R-009c" "AGENT_CONTEXT.md does not reference Phase 1 / entrypoint-aware TDD"
fi

# R-009d: CONTRIBUTING.md test file count includes carchitect-phase1 or is current
# Check that test count is at least 55 (was 54+1 from integration-test-contracts)
test_count_line=$(grep -o '[0-9]* test.*files\|[0-9]* test.*suites' "$CONTRIBUTING_MD" 2>/dev/null | head -1) || test_count_line=""
if [ -n "$test_count_line" ]; then
  count=$(echo "$test_count_line" | grep -o '^[0-9]*')
  if [ "$count" -ge 55 ]; then
    pass "R-009d" "CONTRIBUTING.md test count ($count) includes new test file"
  else
    fail "R-009d" "CONTRIBUTING.md test count ($count) needs update (expected >= 55)"
  fi
else
  skip "R-009d" "Could not find test count in CONTRIBUTING.md"
fi

# R-009e: Source and distribution are in sync for ctdd SKILL.md
if [ -f "$CTDD_DIST" ]; then
  if diff -q "$CTDD_SKILL" "$CTDD_DIST" > /dev/null 2>&1; then
    pass "R-009e" "ctdd SKILL.md source and distribution are in sync"
  else
    fail "R-009e" "ctdd SKILL.md source and distribution are out of sync (run sync.sh)"
  fi
else
  fail "R-009e" "Distribution file $CTDD_DIST does not exist"
fi

# ============================================================================
# Summary
# ============================================================================

echo ""
echo "============================================"
echo "carchitect-phase1 tests: $PASS passed, $FAIL failed, $SKIPPED skipped"
echo "============================================"

if [ "$FAIL" -gt 0 ]; then
  echo "Failed: $FAILED_IDS"
  exit 1
fi

exit 0
