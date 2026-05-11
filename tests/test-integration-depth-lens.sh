#!/usr/bin/env bash
# shellcheck disable=SC1090,SC1091,SC2016,SC2086
# Correctless — Integration Depth Mini-Audit Lens Structural Tests
#
# Enforces the integration-depth-mini-audit-lens spec rules (INV-001..INV-008).
# Tests are structural — they verify keyword presence and structural
# properties of the ctdd skill file. All tests are [unit] — keyword/structural
# checks on the skill file itself.
#
# Run from repo root: bash tests/test-integration-depth-lens.sh

source "$(dirname "${BASH_SOURCE[0]}")/test-helpers.sh"
set -f

# ============================================================================
# File paths
# ============================================================================

CTDD_SKILL="skills/ctdd/SKILL.md"

# ============================================================================
# INV-001: Agent prompt exists with contract references and correlation guidance
# ============================================================================

section "INV-001: Agent prompt with contract references and correlation"

# INV-001a: Agent prompt references Entry/Through/Exit contracts near integration depth
if grep -B 5 -A 50 'integration.depth\|Integration depth' "$CTDD_SKILL" | grep -qi 'Entry/Through/Exit\|Through.*component\|Through.*contract'; then
  pass "INV-001a" "integration depth agent references Entry/Through/Exit contracts"
else
  fail "INV-001a" "integration depth agent does not reference Entry/Through/Exit contracts"
fi

# INV-001b: Correlation mechanism explicitly stated (R-xxx in test names)
if grep -B 5 -A 50 'integration.depth\|Integration depth' "$CTDD_SKILL" | grep -qi 'R-xxx\|rule.*ID\|correlat\|test.*function.*name'; then
  pass "INV-001b" "correlation mechanism present in integration depth agent prompt"
else
  fail "INV-001b" "no correlation mechanism guidance in integration depth agent prompt"
fi

# INV-001c: Agent prompt instructs verification of execution evidence
if grep -B 5 -A 50 'integration.depth\|Integration depth' "$CTDD_SKILL" | grep -qi 'execution.*evidence\|assert.*fail\|would.*fail.*if.*removed\|would.*fail.*if.*stubbed'; then
  pass "INV-001c" "agent prompt instructs execution evidence verification"
else
  fail "INV-001c" "no execution evidence instruction in integration depth agent prompt"
fi

# ============================================================================
# INV-002: Execution evidence requirement
# ============================================================================

section "INV-002: Execution evidence requirement"

# INV-002a: Prompt mentions assertion-based evidence (not just imports/wiring)
if grep -B 5 -A 50 'integration.depth\|Integration depth' "$CTDD_SKILL" | grep -qi 'side.effect\|error.*path.*assert\|state.*change\|401\|log.*entry\|config.*value.*response'; then
  pass "INV-002a" "prompt includes concrete execution evidence examples"
else
  fail "INV-002a" "no concrete execution evidence examples in agent prompt"
fi

# INV-002b: Prompt distinguishes execution evidence from mere import/wiring
if grep -B 5 -A 50 'integration.depth\|Integration depth' "$CTDD_SKILL" | grep -qi 'not.*just.*import\|not.*just.*wir\|beyond.*import\|more.*than.*import\|actually.*ran\|actually.*fired\|actually.*execute'; then
  pass "INV-002b" "prompt distinguishes execution evidence from import/wiring"
else
  fail "INV-002b" "prompt does not distinguish execution evidence from mere import/wiring"
fi

# ============================================================================
# INV-003: Contracts-only scope with advisory fallback
# ============================================================================

section "INV-003: Contracts-only scope with advisory fallback"

# INV-003a: Advisory text for uncontracted [integration] tests
if grep -B 5 -A 50 'integration.depth\|Integration depth' "$CTDD_SKILL" | grep -qi 'without.*Entry/Through/Exit\|without.*contract\|no.*contract\|not.*auditable'; then
  pass "INV-003a" "advisory fallback for uncontracted tests present"
else
  fail "INV-003a" "no advisory fallback for uncontracted [integration] tests"
fi

# INV-003b: Scoping instruction limits agent to contracted tests only
if grep -B 5 -A 50 'integration.depth\|Integration depth' "$CTDD_SKILL" | grep -qi 'operate ONLY.*contract\|ONLY on.*integration.*contract\|only.*contract'; then
  pass "INV-003b" "scoping instruction limits agent to contracted tests"
else
  fail "INV-003b" "no explicit scoping of agent to contracted tests only"
fi

# ============================================================================
# INV-004: Through-component checklist approach (per-component)
# ============================================================================

section "INV-004: Through-component checklist (per-component)"

# INV-004a: Per-component evaluation language
if grep -B 5 -A 50 'integration.depth\|Integration depth' "$CTDD_SKILL" | grep -qi 'each.*Through.*component\|per.*component\|for.*each.*component\|individually\|one.*by.*one'; then
  pass "INV-004a" "per-component evaluation language present"
else
  fail "INV-004a" "no per-component evaluation language in agent prompt"
fi

# INV-004b: Reports which components have/lack evidence
if grep -B 5 -A 50 'integration.depth\|Integration depth' "$CTDD_SKILL" | grep -qi 'report.*which\|which.*have.*evidence\|which.*lack\|component.*status\|evidence.*found\|evidence.*missing'; then
  pass "INV-004b" "agent reports per-component evidence status"
else
  fail "INV-004b" "no per-component reporting instruction in agent prompt"
fi

# ============================================================================
# INV-005: LENS enum value is integration-depth
# ============================================================================

section "INV-005: LENS enum includes integration-depth"

# INV-005a: integration-depth in the LENS enum line
if grep -q 'LENS:.*integration-depth' "$CTDD_SKILL"; then
  pass "INV-005a" "integration-depth in LENS enum"
else
  fail "INV-005a" "integration-depth not found in LENS enum line"
fi

# INV-005b: Agent prompt uses LENS: integration-depth
if grep -B 5 -A 50 'integration.depth\|Integration depth' "$CTDD_SKILL" | grep -qi 'LENS.*integration-depth\|integration-depth.*LENS'; then
  pass "INV-005b" "agent prompt specifies LENS: integration-depth"
else
  fail "INV-005b" "agent prompt does not specify LENS: integration-depth"
fi

# ============================================================================
# INV-006: Agent count cascading updates (5 → 6)
# ============================================================================

section "INV-006: Agent count updates (5 → 6)"

# INV-006a: No "five specialist agents" remaining
if grep -qi 'five specialist agents' "$CTDD_SKILL"; then
  fail "INV-006a" "stale 'five specialist agents' text still present"
else
  pass "INV-006a" "no stale 'five specialist agents' text"
fi

# INV-006b: No "spawning 5 specialist" remaining
if grep -qi 'spawning 5 specialist' "$CTDD_SKILL"; then
  fail "INV-006b" "stale 'spawning 5 specialist' text still present"
else
  pass "INV-006b" "no stale 'spawning 5 specialist' text"
fi

# INV-006c: "six specialist agents" or "6 specialist agents" present
if grep -qi 'six specialist agents\|6 specialist agents' "$CTDD_SKILL"; then
  pass "INV-006c" "'six specialist agents' present in ctdd"
else
  fail "INV-006c" "neither 'six specialist agents' nor '6 specialist agents' found"
fi

# INV-006d: "all six agents" or "all 6 agents" in zero-findings section
if grep -qi 'all six agents\|all 6 agents' "$CTDD_SKILL"; then
  pass "INV-006d" "'all six agents' present (zero-findings section)"
else
  fail "INV-006d" "neither 'all six agents' nor 'all 6 agents' found"
fi

# INV-006e: integration-depth in token tracking agent_role list
if grep -qE 'agent_role.*integration-depth' "$CTDD_SKILL"; then
  pass "INV-006e" "integration-depth in agent_role token tracking"
else
  fail "INV-006e" "integration-depth not in token tracking agent_role list"
fi

# ============================================================================
# INV-007: Severity calibration included
# ============================================================================

section "INV-007: Severity calibration examples"

# INV-007a: CRITICAL/HIGH calibration example present (stubs/mocks Through component)
if grep -B 5 -A 50 'integration.depth\|Integration depth' "$CTDD_SKILL" | grep -qi 'stub.*Through\|mock.*Through\|Through.*mock\|Through.*stub\|CRITICAL.*stub\|CRITICAL.*mock'; then
  pass "INV-007a" "calibration example references Through component stubbing"
else
  fail "INV-007a" "no calibration example for Through component stubbing"
fi

# INV-007b: LOW/MEDIUM calibration example present (acceptable mock not in Through)
if grep -B 5 -A 50 'integration.depth\|Integration depth' "$CTDD_SKILL" | grep -qi 'acceptable\|not.*in.*Through\|external.*API\|LOW.*mock\|outside.*Through'; then
  pass "INV-007b" "calibration example for acceptable mocking present"
else
  fail "INV-007b" "no calibration example for acceptable mocking"
fi

# ============================================================================
# INV-008: Fail-open on no contracts
# ============================================================================

section "INV-008: Fail-open when no contracts exist"

# INV-008a: Graceful exit language when no contracts found
if grep -B 5 -A 50 'integration.depth\|Integration depth' "$CTDD_SKILL" | grep -qi 'no.*contract.*found\|nothing.*to.*audit\|zero.*finding\|no.*integration.*contract'; then
  pass "INV-008a" "graceful exit language for no-contracts case"
else
  fail "INV-008a" "no graceful exit language when no contracts exist"
fi

# ============================================================================
# BND-002: Empty Through field handling
# ============================================================================

section "BND-002: Empty Through field"

# BND-002a: Agent handles empty Through gracefully
if grep -B 5 -A 50 'integration.depth\|Integration depth' "$CTDD_SKILL" | grep -qi 'empty.*Through\|no mock restrictions\|no.*component'; then
  pass "BND-002a" "empty Through field handling present"
else
  fail "BND-002a" "no handling for empty Through field"
fi

# ============================================================================
# PRH-001: Must not duplicate mechanical checks
# ============================================================================

section "PRH-001: No duplication of mechanical checks"

# PRH-001a: Agent prompt mentions complementarity with test audit
# Extract integration depth agent section to avoid context bleed from other sections
if sed -n '/^6\. \*\*Integration depth agent/,/^[0-9]\. \*\*\|^###/p' "$CTDD_SKILL" | grep -qi 'not.*re-check\|not.*duplicate\|complement\|semantic.*not.*structural\|above.*mechanical\|beyond.*check'; then
  pass "PRH-001a" "agent prompt distinguishes from mechanical test audit checks"
else
  fail "PRH-001a" "no language distinguishing from mechanical checks"
fi

# ============================================================================
# PRH-002: Must not require test execution
# ============================================================================

section "PRH-002: No test execution required"

# PRH-002a: Agent operates on source code, not test output
if grep -B 5 -A 50 'integration.depth\|Integration depth' "$CTDD_SKILL" | grep -qi 'source.*code\|test.*code\|assertion.*pattern\|infer.*from.*assertion\|read.*test.*file'; then
  pass "PRH-002a" "agent operates on test source code (not runtime output)"
else
  fail "PRH-002a" "unclear whether agent operates on source code vs runtime output"
fi

# ============================================================================
# BND-004: Non-decomposable Through field
# ============================================================================

section "BND-004: Non-decomposable Through field handling"

# BND-004a: Advisory for non-decomposable Through
if grep -B 5 -A 50 'integration.depth\|Integration depth' "$CTDD_SKILL" | grep -qi 'non-decomposable\|cannot.*decompose\|collective.*description\|full.*middleware.*chain.*ADVISORY\|decompos'; then
  pass "BND-004a" "non-decomposable Through field handling present"
else
  fail "BND-004a" "no handling for non-decomposable Through fields"
fi

# ============================================================================
# Summary
# ============================================================================

summary "integration-depth-lens"
