#!/usr/bin/env bash
# shellcheck disable=SC1090,SC1091,SC2016,SC2086
# Correctless — Integration Test Contracts Structural Tests
#
# Enforces the integration-test-contracts spec rules (R-001..R-010).
# Tests are structural — they verify file content, prompt elements,
# contract format, tiered severity, and documentation updates.
# LLM-behavioral rules are tested only on their mechanical envelope:
# required prompt elements, field names, verification tier tables, etc.
#
# Run from repo root: bash tests/test-integration-test-contracts.sh

source "$(dirname "${BASH_SOURCE[0]}")/test-helpers.sh"
set -f

# ============================================================================
# File paths
# ============================================================================

CSPEC_SKILL="skills/cspec/SKILL.md"
CTDD_SKILL="skills/ctdd/SKILL.md"
# Post-M-1 (2026-04-26): RED-phase test-writer prompt content lives in agents/ctdd-red.md
# (single source of truth per ABS-010). R-008 tests check both files.
CTDD_RED_AGENT="agents/ctdd-red.md"
SPEC_LITE="templates/spec-lite.md"
SPEC_FULL="templates/spec-full.md"
ARCH_FILE=".correctless/ARCHITECTURE.md"
DOCS_CSPEC="docs/skills/cspec.md"
DOCS_CTDD="docs/skills/ctdd.md"
AGENT_CONTEXT=".correctless/AGENT_CONTEXT.md"

# ============================================================================
# R-001 [unit]: cspec SKILL.md has integration contract step
# ============================================================================

section "R-001: cspec SKILL.md has integration contract step"

# R-001a: A contract step exists between Step 3 (rule drafting) and Step 5 (antipatterns)
# The spec says: "adds a new step between rule drafting and antipatterns checking"
# This means a section about integration test contracts should appear in cspec SKILL.md
if grep -qi 'integration.*test.*contract\|integration.*contract\|Entry.*Through.*Exit' "$CSPEC_SKILL"; then
  pass "R-001a" "Integration test contract step exists in cspec SKILL.md"
else
  fail "R-001a" "No integration test contract step found in cspec SKILL.md"
fi

# R-001b: The contract step mentions Entry field
if grep -q 'Entry' "$CSPEC_SKILL" && grep -qi 'entrypoint\|entry.*field\|Entry.*test_via' "$CSPEC_SKILL"; then
  pass "R-001b" "Entry field documented in cspec SKILL.md contract step"
else
  fail "R-001b" "Entry field not documented in cspec SKILL.md"
fi

# R-001c: The contract step mentions Through field
if grep -q 'Through' "$CSPEC_SKILL" && grep -qi 'must not.*mock\|must NOT be mocked\|must be exercised' "$CSPEC_SKILL"; then
  pass "R-001c" "Through field documented in cspec SKILL.md contract step"
else
  fail "R-001c" "Through field not documented in cspec SKILL.md"
fi

# R-001d: The contract step mentions Exit field
if grep -q 'Exit' "$CSPEC_SKILL" && grep -qi 'observable.*behavior\|observable.*assertion' "$CSPEC_SKILL"; then
  pass "R-001d" "Exit field documented in cspec SKILL.md contract step"
else
  fail "R-001d" "Exit field not documented in cspec SKILL.md"
fi

# R-001e: Prerequisite — ABS-023 is referenced in the contract step
if grep -q 'ABS-023' "$CSPEC_SKILL"; then
  pass "R-001e" "ABS-023 referenced in cspec SKILL.md"
else
  fail "R-001e" "ABS-023 not referenced in cspec SKILL.md"
fi

# R-001f: Prerequisite — ABS-024 is referenced in the contract step
if grep -q 'ABS-024' "$CSPEC_SKILL"; then
  pass "R-001f" "ABS-024 referenced in cspec SKILL.md"
else
  fail "R-001f" "ABS-024 not referenced in cspec SKILL.md"
fi

# R-001g: The contract step is positioned after Step 3 (draft) and before Step 5 (antipatterns)
# Step 3 is "Draft the Spec" and Step 5 is "Check Antipatterns"
if grep -n 'Step 3\|Step 4\|Step 5\|integration.*test.*contract\|integration.*contract' "$CSPEC_SKILL" | head -20 > /dev/null 2>&1; then
  step3_line=$(grep -n 'Step 3' "$CSPEC_SKILL" | head -1 | cut -d: -f1)
  step5_line=$(grep -n 'Step 5' "$CSPEC_SKILL" | head -1 | cut -d: -f1)
  contract_line=$(grep -ni 'integration.*contract\|Entry.*Through.*Exit' "$CSPEC_SKILL" | head -1 | cut -d: -f1)
  if [ -n "$step3_line" ] && [ -n "$step5_line" ] && [ -n "$contract_line" ]; then
    if [ "$step3_line" -lt "$contract_line" ] && [ "$contract_line" -lt "$step5_line" ]; then
      pass "R-001g" "Contract step is between Step 3 and Step 5"
    else
      fail "R-001g" "Contract step not properly positioned (step3=$step3_line, contract=$contract_line, step5=$step5_line)"
    fi
  else
    fail "R-001g" "Could not find all section markers (step3=$step3_line, contract=$contract_line, step5=$step5_line)"
  fi
else
  fail "R-001g" "Missing section markers in cspec SKILL.md"
fi

# R-001h: The contract step shows the three-field format with an example
# The spec says Entry/Through/Exit as a block appended to integration rules
if grep -qE 'Entry:.*Through:.*Exit:|Entry:' "$CSPEC_SKILL" 2>/dev/null; then
  pass "R-001h" "Entry/Through/Exit format example present in cspec SKILL.md"
else
  # Check multiline — Entry and Through and Exit as separate lines
  entry_count=$(grep -c 'Entry:' "$CSPEC_SKILL" 2>/dev/null) || entry_count=0
  through_count=$(grep -c 'Through:' "$CSPEC_SKILL" 2>/dev/null) || through_count=0
  exit_count=$(grep -c 'Exit:' "$CSPEC_SKILL" 2>/dev/null) || exit_count=0
  if [ "$entry_count" -gt 0 ] && [ "$through_count" -gt 0 ] && [ "$exit_count" -gt 0 ]; then
    pass "R-001h" "Entry/Through/Exit format example present (multiline) in cspec SKILL.md"
  else
    fail "R-001h" "Entry/Through/Exit format example not found in cspec SKILL.md"
  fi
fi

# ============================================================================
# R-002 [unit]: Entrypoint matching, multi-entrypoint split, sequential IDs
# ============================================================================

section "R-002: Entrypoint matching and multi-entrypoint split"

# R-002a: Instructions to read entrypoints from ARCHITECTURE.md
if grep -qi 'read.*entrypoint\|extract-entrypoints\|entrypoints.*YAML\|ARCHITECTURE.*entrypoint' "$CSPEC_SKILL"; then
  pass "R-002a" "Instructions to read entrypoints present in cspec SKILL.md"
else
  fail "R-002a" "No instructions to read entrypoints in cspec SKILL.md"
fi

# R-002b: Entrypoint matching via scope globs — in the contract step context
# Must appear near integration contract / Entry / entrypoint content, not just anywhere
if grep -qi 'scope.*glob.*overlap\|entrypoint.*scope.*glob\|scope.*overlap.*rule' "$CSPEC_SKILL"; then
  pass "R-002b" "Scope glob matching instructions present in contract context"
else
  fail "R-002b" "Scope glob matching instructions not found in cspec SKILL.md contract context"
fi

# R-002c: test_via field used for Entry derivation
if grep -q 'test_via' "$CSPEC_SKILL"; then
  pass "R-002c" "test_via field referenced in cspec SKILL.md"
else
  fail "R-002c" "test_via field not referenced in cspec SKILL.md"
fi

# R-002d: Multi-entrypoint split instructions — split into separate rules
if grep -qi 'split.*rule\|split.*entrypoint\|one.*rule.*per.*entrypoint\|becomes.*three.*rules\|splitting into' "$CSPEC_SKILL"; then
  pass "R-002d" "Multi-entrypoint split instructions present"
else
  fail "R-002d" "Multi-entrypoint split instructions not found in cspec SKILL.md"
fi

# R-002e: Sequential IDs for split rules (not suffixed)
if grep -qi 'sequential.*ID\|renumber\|standard R-NNN\|no.*suffix\|not.*suffix' "$CSPEC_SKILL"; then
  pass "R-002e" "Sequential ID convention for split rules documented"
else
  fail "R-002e" "Sequential ID convention for split rules not documented"
fi

# R-002f: Lineage comments on split rules
if grep -qi 'lineage\|split from original\|traceable\|original.*R-' "$CSPEC_SKILL"; then
  pass "R-002f" "Lineage comment convention for split rules documented"
else
  fail "R-002f" "Lineage comment convention not documented in cspec SKILL.md"
fi

# R-002g: Affected files derivation from rule description, What section, other rules
# Must be in the context of entrypoint matching, not just general feature scope
if grep -qi 'infer.*affected.*file.*rule.*description\|affected.*file.*feature.*scope.*rule\|rule.*description.*What.*section' "$CSPEC_SKILL"; then
  pass "R-002g" "Affected files derivation documented in entrypoint matching context"
else
  fail "R-002g" "Affected files derivation not documented in cspec SKILL.md entrypoint matching context"
fi

# ============================================================================
# R-003 [unit]: Entrypoint existence check, graceful skip
# ============================================================================

section "R-003: Entrypoint existence check and graceful skip"

# R-003a: Check for ARCHITECTURE.md entrypoints markers
if grep -qi 'correctless:entrypoints:start\|correctless:entrypoints:end\|entrypoint.*marker' "$CSPEC_SKILL"; then
  pass "R-003a" "Entrypoints marker check documented in cspec SKILL.md"
else
  fail "R-003a" "Entrypoints marker check not documented in cspec SKILL.md"
fi

# R-003b: Check that the entrypoints block is non-empty
if grep -qi 'non-empty\|no entrypoint.*exist\|no.*entrypoint.*defined\|entrypoint.*empty' "$CSPEC_SKILL"; then
  pass "R-003b" "Non-empty entrypoints check documented"
else
  fail "R-003b" "Non-empty entrypoints check not documented in cspec SKILL.md"
fi

# R-003c: Skip message when entrypoints missing — mentions /carchitect
if grep -qi 'carchitect\|run.*carchitect\|skip.*integration.*contract' "$CSPEC_SKILL"; then
  pass "R-003c" "Skip message with /carchitect reference present"
else
  fail "R-003c" "Skip message with /carchitect reference not found in cspec SKILL.md"
fi

# R-003d: Spec agent does NOT infer entrypoints from codebase
if grep -qi 'NOT.*infer.*entrypoint\|does not.*infer\|not attempt.*infer' "$CSPEC_SKILL"; then
  pass "R-003d" "No-inference constraint documented"
else
  fail "R-003d" "No-inference constraint not documented in cspec SKILL.md"
fi

# R-003e: User can choose to skip, resulting in [integration] rules without contracts
if grep -qi 'skip.*integration.*contract\|without.*Entry.*Through.*Exit\|without.*contract\|existing behavior' "$CSPEC_SKILL"; then
  pass "R-003e" "Skip option resulting in rules without contracts documented"
else
  fail "R-003e" "Skip option for rules without contracts not documented"
fi

# ============================================================================
# R-004 [unit]: Through field instructions
# ============================================================================

section "R-004: Through field instructions"

# R-004a: "must NOT be mocked" phrase
if grep -q 'must NOT be mocked' "$CSPEC_SKILL" || grep -q 'must not be mocked' "$CSPEC_SKILL"; then
  pass "R-004a" "'must NOT be mocked' phrase present in cspec SKILL.md"
else
  fail "R-004a" "'must NOT be mocked' phrase not found in cspec SKILL.md"
fi

# R-004b: "must be exercised" phrase
if grep -q 'must be exercised' "$CSPEC_SKILL" || grep -q 'must.*exercised' "$CSPEC_SKILL"; then
  pass "R-004b" "'must be exercised' phrase present in cspec SKILL.md"
else
  fail "R-004b" "'must be exercised' phrase not found in cspec SKILL.md"
fi

# R-004c: Through field documents both "components that MUST be exercised" and "must NOT be mocked"
if grep -qi 'Through.*exercised\|Through.*mock\|exercised.*mock' "$CSPEC_SKILL"; then
  pass "R-004c" "Through field covers both exercise and mock constraints"
else
  fail "R-004c" "Through field does not cover both exercise and mock constraints"
fi

# ============================================================================
# R-005 [unit]: Exit field guidance with positive and negative examples
# ============================================================================

section "R-005: Exit field guidance"

# R-005a: Exit field mentions "observable behavior"
if grep -qi 'Exit.*observable\|observable.*behavior' "$CSPEC_SKILL"; then
  pass "R-005a" "Exit field references observable behavior"
else
  fail "R-005a" "Exit field does not reference observable behavior"
fi

# R-005b: Positive example (observable assertion, e.g., "response body contains")
if grep -qi 'response.*body.*contains\|response.*contains\|observable.*assertion\|positive.*example' "$CSPEC_SKILL"; then
  pass "R-005b" "Positive example present for Exit field"
else
  fail "R-005b" "No positive example found for Exit field in cspec SKILL.md"
fi

# R-005c: Negative example (implementation detail assertion, e.g., "Function Y was called")
if grep -qi 'Function.*called\|implementation.*detail\|testing.*implementation\|negative.*example' "$CSPEC_SKILL"; then
  pass "R-005c" "Negative example present for Exit field"
else
  fail "R-005c" "No negative example found for Exit field in cspec SKILL.md"
fi

# R-005d: Exit field must be expressible as test assertion without internal state
if grep -qi 'without.*internal.*state\|test.*assertion\|without.*accessing.*internal' "$CSPEC_SKILL"; then
  pass "R-005d" "Internal state constraint documented for Exit field"
else
  fail "R-005d" "Internal state constraint not documented for Exit field"
fi

# ============================================================================
# R-006 [unit]: Unit rules excluded from contracts
# ============================================================================

section "R-006: Unit rules excluded from contracts"

# R-006a: Explicit statement that [unit] rules do NOT get Entry/Through/Exit
if grep -qi 'unit.*do NOT\|unit.*not.*get.*Entry\|unit.*not.*contract\|contract.*only.*integration\|only.*integration.*rule' "$CSPEC_SKILL"; then
  pass "R-006a" "Unit rules excluded from contracts documented"
else
  fail "R-006a" "Unit rules exclusion from contracts not documented in cspec SKILL.md"
fi

# R-006b: Explicit statement that contracts apply ONLY to [integration] rules
if grep -qi 'only.*\[integration\]\|applies.*only.*integration\|contract.*integration.*rule\|integration.*rule.*contract' "$CSPEC_SKILL"; then
  pass "R-006b" "Contracts apply only to integration rules documented"
else
  fail "R-006b" "Integration-only scope not documented in cspec SKILL.md"
fi

# ============================================================================
# R-007 [integration]: Test audit contract verification in ctdd SKILL.md
# ============================================================================

section "R-007: Test audit contract verification in ctdd SKILL.md"

# R-007a: Contract verification check exists in the test audit section
if grep -qi 'contract.*verif\|verify.*contract\|Entry.*Through.*Exit.*contract\|contract.*satisf' "$CTDD_SKILL"; then
  pass "R-007a" "Contract verification check exists in ctdd SKILL.md"
else
  fail "R-007a" "Contract verification check not found in ctdd SKILL.md"
fi

# R-007b: Entry check — mechanical, BLOCKING — must be in a contract verification context
# This must be in a table or section specifically about contract verification tiers,
# not just any mention of "Entry" and "BLOCKING" in the test audit
if grep -qi 'Entry.*|.*Mechanical.*|.*BLOCKING' "$CTDD_SKILL" || grep -qi 'Entry.*mechanical.*BLOCKING' "$CTDD_SKILL"; then
  pass "R-007b" "Entry check tier (mechanical, BLOCKING) documented in contract verification"
else
  fail "R-007b" "Entry check tier not documented in ctdd SKILL.md contract verification"
fi

# R-007c: Through check — semi-mechanical, BLOCKING or UNCERTAIN
if grep -qi 'Through.*semi-mechanical\|Through.*BLOCKING.*UNCERTAIN\|semi-mechanical.*Through' "$CTDD_SKILL"; then
  pass "R-007c" "Through check tier (semi-mechanical, BLOCKING/UNCERTAIN) documented"
else
  fail "R-007c" "Through check tier not documented in ctdd SKILL.md"
fi

# R-007d: Exit check — semantic, BLOCKING for definite mismatch or ADVISORY
if grep -qi 'Exit.*semantic\|Exit.*BLOCKING.*ADVISORY\|semantic.*Exit' "$CTDD_SKILL"; then
  pass "R-007d" "Exit check tier (semantic, BLOCKING/ADVISORY) documented"
else
  fail "R-007d" "Exit check tier not documented in ctdd SKILL.md"
fi

# R-007e: Tiered severity table exists (Entry/Through/Exit rows)
# Check for a table structure with the three checks
if grep -q 'Entry' "$CTDD_SKILL" && grep -q 'Through' "$CTDD_SKILL" && grep -q 'Exit' "$CTDD_SKILL" && grep -qi 'Mechanical\|Semi-mechanical\|Semantic' "$CTDD_SKILL"; then
  pass "R-007e" "Tiered severity table elements present in ctdd SKILL.md"
else
  fail "R-007e" "Tiered severity table elements not found in ctdd SKILL.md"
fi

# R-007f: UNCERTAIN severity mentioned specifically for Through/contract checks
# Must be in the contract verification context, not just mini-audit UNCERTAIN
if grep -qi 'Through.*UNCERTAIN\|UNCERTAIN.*Through\|BLOCKING.*or.*UNCERTAIN.*Through\|Through.*BLOCKING.*UNCERTAIN' "$CTDD_SKILL"; then
  pass "R-007f" "UNCERTAIN severity mentioned for Through checks in ctdd SKILL.md"
else
  fail "R-007f" "UNCERTAIN severity not mentioned for Through checks in ctdd SKILL.md"
fi

# R-007g: PAT-012 compatibility note
if grep -q 'PAT-012' "$CTDD_SKILL"; then
  pass "R-007g" "PAT-012 compatibility note present in ctdd SKILL.md"
else
  fail "R-007g" "PAT-012 compatibility note not found in ctdd SKILL.md"
fi

# R-007h: "not audited" note for integration rules without contracts
if grep -qi 'not.*audited\|not audited\|test shape not audited' "$CTDD_SKILL"; then
  pass "R-007h" "'not audited' note for rules without contracts present"
else
  fail "R-007h" "'not audited' note for rules without contracts not found in ctdd SKILL.md"
fi

# ============================================================================
# R-008 [unit]: Test agent prompt with contract-as-task framing
# ============================================================================

section "R-008: Test agent prompt with contract-as-task framing"

# R-008a: Contract-as-task framing for test agent
if grep -qi 'self-contained task\|discrete.*bounded.*task\|contract.*task' "$CTDD_SKILL" "$CTDD_RED_AGENT"; then
  pass "R-008a" "Contract-as-task framing present in ctdd SKILL.md"
else
  fail "R-008a" "Contract-as-task framing not found in ctdd SKILL.md"
fi

# R-008b: "Entry tells you where to start" instruction
if grep -qi 'Entry tells you where to start\|Entry.*where.*start' "$CTDD_SKILL" "$CTDD_RED_AGENT"; then
  pass "R-008b" "'Entry tells you where to start' instruction present"
else
  fail "R-008b" "'Entry tells you where to start' instruction not found"
fi

# R-008c: "Through tells you what path to exercise" instruction
if grep -qi 'Through tells you what\|Through.*path.*exercise\|Through.*what.*cannot mock' "$CTDD_SKILL" "$CTDD_RED_AGENT"; then
  pass "R-008c" "'Through tells you what path...' instruction present"
else
  fail "R-008c" "'Through tells you what path...' instruction not found"
fi

# R-008d: "Exit tells you what must be true" instruction
if grep -qi 'Exit tells you what must be true\|Exit.*must be true\|Exit.*what.*true.*end' "$CTDD_SKILL" "$CTDD_RED_AGENT"; then
  pass "R-008d" "'Exit tells you what must be true' instruction present"
else
  fail "R-008d" "'Exit tells you what must be true' instruction not found"
fi

# R-008e: Constraint flagging instruction — flag a contract defect rather than silently comply
# Must be about contract constraint defects specifically, not general mock/test flagging
if grep -qi 'flag.*contract.*defect\|contract.*defect.*finding\|wrong.*constraint.*spec.*issue\|constraint.*seems.*wrong.*flag' "$CTDD_SKILL" "$CTDD_RED_AGENT"; then
  pass "R-008e" "Contract constraint flagging instruction present"
else
  fail "R-008e" "Contract constraint flagging instruction not found in ctdd SKILL.md"
fi

# R-008f: TB-004 reference (escalation to human boundary)
if grep -q 'TB-004' "$CTDD_SKILL" "$CTDD_RED_AGENT"; then
  pass "R-008f" "TB-004 reference present in ctdd SKILL.md"
else
  fail "R-008f" "TB-004 reference not found in ctdd SKILL.md"
fi

# R-008g: TB-005 reference (test agent not overriding auditor)
if grep -q 'TB-005' "$CTDD_SKILL" "$CTDD_RED_AGENT"; then
  pass "R-008g" "TB-005 reference present in ctdd SKILL.md"
else
  fail "R-008g" "TB-005 reference not found in ctdd SKILL.md"
fi

# R-008h: "do not silently downgrade by mocking a prohibited component" instruction
if grep -qi 'silently.*downgrade\|mocking.*prohibited\|testing through a different entry' "$CTDD_SKILL" "$CTDD_RED_AGENT"; then
  pass "R-008h" "Silent downgrade prohibition present"
else
  fail "R-008h" "Silent downgrade prohibition not found in ctdd SKILL.md"
fi

# ============================================================================
# R-009 [unit]: Template files updated with contract format
# ============================================================================

section "R-009: Template files updated with contract format"

# R-009a: spec-lite.md has Entry/Through/Exit format example
if grep -q 'Entry:' "$SPEC_LITE" && grep -q 'Through:' "$SPEC_LITE" && grep -q 'Exit:' "$SPEC_LITE"; then
  pass "R-009a" "spec-lite.md has Entry/Through/Exit format"
else
  fail "R-009a" "spec-lite.md missing Entry/Through/Exit format"
fi

# R-009b: spec-lite.md shows the format within the [integration] test level guide
if grep -qi 'integration.*Entry\|Entry.*Through.*Exit' "$SPEC_LITE"; then
  pass "R-009b" "spec-lite.md shows contract format with integration rule context"
else
  fail "R-009b" "spec-lite.md does not show contract format with integration context"
fi

# R-009c: spec-full.md has Entry/Through/Exit format example
if grep -q 'Entry:' "$SPEC_FULL" && grep -q 'Through:' "$SPEC_FULL" && grep -q 'Exit:' "$SPEC_FULL"; then
  pass "R-009c" "spec-full.md has Entry/Through/Exit format"
else
  fail "R-009c" "spec-full.md missing Entry/Through/Exit format"
fi

# R-009d: spec-full.md uses the format within the invariant structure (high-intensity)
if grep -qi 'Entry:.*Through:\|integration.*contract\|Entry.*Through.*Exit' "$SPEC_FULL"; then
  pass "R-009d" "spec-full.md shows contract format within invariant structure"
else
  fail "R-009d" "spec-full.md does not show contract format within invariant structure"
fi

# ============================================================================
# R-010 [unit]: Documentation updates
# ============================================================================

section "R-010: Documentation updates"

# R-010a: docs/skills/cspec.md documents integration test contract format
if grep -qi 'integration.*test.*contract\|Entry.*Through.*Exit\|contract.*format' "$DOCS_CSPEC" 2>/dev/null; then
  pass "R-010a" "docs/skills/cspec.md documents integration test contracts"
else
  fail "R-010a" "docs/skills/cspec.md does not document integration test contracts"
fi

# R-010b: docs/skills/ctdd.md documents contract verification check
if grep -qi 'contract.*verif\|verify.*contract\|Entry.*Through.*Exit\|contract.*audit' "$DOCS_CTDD" 2>/dev/null; then
  pass "R-010b" "docs/skills/ctdd.md documents contract verification"
else
  fail "R-010b" "docs/skills/ctdd.md does not document contract verification"
fi

# R-010c: AGENT_CONTEXT.md references integration test contracts
if grep -qi 'integration.*test.*contract\|Entry.*Through.*Exit\|contract.*integration' "$AGENT_CONTEXT" 2>/dev/null; then
  pass "R-010c" "AGENT_CONTEXT.md references integration test contracts"
else
  fail "R-010c" "AGENT_CONTEXT.md does not reference integration test contracts"
fi

# R-010d: ABS-023 in ARCHITECTURE.md lists /cspec as a consumer
if grep -q 'ABS-023' "$ARCH_FILE" 2>/dev/null; then
  if grep -A 20 'ABS-023' "$ARCH_FILE" | grep -qi 'cspec.*consumer\|consumer.*cspec\|cspec.*reads\|reads.*entrypoint.*cspec'; then
    pass "R-010d" "ABS-023 lists /cspec as a consumer"
  else
    fail "R-010d" "ABS-023 does not list /cspec as consumer"
  fi
else
  fail "R-010d" "ABS-023 not found in ARCHITECTURE.md"
fi

# R-010e: ABS-023 in ARCHITECTURE.md lists /ctdd as a transitive consumer
if grep -q 'ABS-023' "$ARCH_FILE" 2>/dev/null; then
  if grep -A 20 'ABS-023' "$ARCH_FILE" | grep -qi 'ctdd.*consumer\|transitive.*ctdd\|ctdd.*transitive\|consumer.*ctdd'; then
    pass "R-010e" "ABS-023 lists /ctdd as transitive consumer"
  else
    fail "R-010e" "ABS-023 does not list /ctdd as transitive consumer"
  fi
else
  fail "R-010e" "ABS-023 not found in ARCHITECTURE.md"
fi

# R-010f: ABS-024 exists in ARCHITECTURE.md
if grep -q 'ABS-024' "$ARCH_FILE" 2>/dev/null; then
  pass "R-010f" "ABS-024 exists in ARCHITECTURE.md"
else
  fail "R-010f" "ABS-024 not found in ARCHITECTURE.md"
fi

# R-010g: ABS-024 documents Entry/Through/Exit contract format
if grep -q 'ABS-024' "$ARCH_FILE" 2>/dev/null; then
  if grep -A 15 'ABS-024' "$ARCH_FILE" | grep -qi 'Entry.*Through.*Exit\|contract.*format\|cross-skill.*data.*contract'; then
    pass "R-010g" "ABS-024 documents contract format"
  else
    fail "R-010g" "ABS-024 does not document contract format"
  fi
else
  fail "R-010g" "ABS-024 not found in ARCHITECTURE.md"
fi

# R-010h: ABS-024 specifies writer (/cspec) and consumer (/ctdd)
if grep -q 'ABS-024' "$ARCH_FILE" 2>/dev/null; then
  if grep -A 15 'ABS-024' "$ARCH_FILE" | grep -qi 'cspec' && grep -A 15 'ABS-024' "$ARCH_FILE" | grep -qi 'ctdd'; then
    pass "R-010h" "ABS-024 specifies writer (cspec) and consumer (ctdd)"
  else
    fail "R-010h" "ABS-024 does not specify writer/consumer"
  fi
else
  fail "R-010h" "ABS-024 not found in ARCHITECTURE.md"
fi

# R-010i: ABS-024 documents verification tiers (Entry=mechanical, Through=semi-mechanical, Exit=semantic)
if grep -q 'ABS-024' "$ARCH_FILE" 2>/dev/null; then
  if grep -A 20 'ABS-024' "$ARCH_FILE" | grep -qi 'mechanical\|semi-mechanical\|semantic'; then
    pass "R-010i" "ABS-024 documents verification tiers"
  else
    fail "R-010i" "ABS-024 does not document verification tiers"
  fi
else
  fail "R-010i" "ABS-024 not found in ARCHITECTURE.md"
fi

# R-010j: ABS-023 evolution constraint strengthened — scope field semantics stable
if grep -q 'ABS-023' "$ARCH_FILE" 2>/dev/null; then
  if grep -A 20 'ABS-023' "$ARCH_FILE" | grep -qi 'scope.*field.*stable\|field.*semantic.*stable\|existing.*field.*semantic\|scope.*remains.*list.*glob\|breaking.*change.*new.*field'; then
    pass "R-010j" "ABS-023 evolution constraint strengthened with scope semantics"
  else
    fail "R-010j" "ABS-023 evolution constraint not strengthened with scope field semantics"
  fi
else
  fail "R-010j" "ABS-023 not found in ARCHITECTURE.md"
fi

# R-010k: ABS-023 violated-when includes test_via/scope removal update for cspec contract derivation
# Must mention "contract derivation" or "cspec" in the violated-when context, not just list test_via in schema
if grep -q 'ABS-023' "$ARCH_FILE" 2>/dev/null; then
  if grep -A 20 'ABS-023' "$ARCH_FILE" | grep -qi 'contract.*derivation\|cspec.*contract\|updating.*cspec.*derivation\|removed.*renamed.*without.*updating.*cspec'; then
    pass "R-010k" "ABS-023 violated-when updated for cspec contract derivation"
  else
    fail "R-010k" "ABS-023 violated-when not updated for cspec contract derivation"
  fi
else
  fail "R-010k" "ABS-023 not found in ARCHITECTURE.md"
fi

# ============================================================================
# Summary
# ============================================================================

echo ""
echo "========================================="
echo "  Integration Test Contracts Tests: $PASS passed, $FAIL failed, $SKIPPED skipped"
echo "========================================="
if [ -n "$FAILED_IDS" ]; then
  echo "  Failed: $FAILED_IDS"
fi
echo ""

# Exit with failure if any tests failed
[ "$FAIL" -eq 0 ]
