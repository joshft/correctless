#!/usr/bin/env bash
# shellcheck disable=SC1090,SC1091,SC2016,SC2086
# Correctless — TDD Mini-Audit Phase Structural Tests
#
# Enforces the tdd-mini-audit spec rules (R-001..R-020).
# Tests are structural — they verify file content, phase transitions,
# gating behavior, prompt elements, and token tracking mappings.
# LLM-behavioral rules are tested only on their mechanical envelope:
# required prompt elements, tool allowlists, finding format, etc.
#
# Run from repo root: bash tests/test-tdd-mini-audit.sh

set -uo pipefail
set -f

cd "$(dirname "${BASH_SOURCE[0]}")/.." || { echo "FATAL: cannot cd to repo root" >&2; exit 2; }

# ============================================================================
# Colors (only if stdout is a terminal)
# ============================================================================

if [ -t 1 ]; then
  GREEN=$'\033[0;32m'
  RED=$'\033[0;31m'
  YELLOW=$'\033[0;33m'
  RESET=$'\033[0m'
else
  GREEN=""
  RED=""
  YELLOW=""
  RESET=""
fi

PASS=0
FAIL=0
SKIPPED=0
FAILED_IDS=""

# ============================================================================
# Result helpers
# ============================================================================

pass() {
  local id="$1" desc="$2"
  echo "  ${GREEN}PASS${RESET}: $id: $desc"
  PASS=$((PASS + 1))
}

fail() {
  local id="$1" desc="$2"
  echo "  ${RED}FAIL${RESET}: $id: $desc"
  FAIL=$((FAIL + 1))
  FAILED_IDS="${FAILED_IDS}${id} "
}

skip() {
  local id="$1" desc="$2"
  echo "  ${YELLOW}SKIP${RESET}: $id: $desc"
  SKIPPED=$((SKIPPED + 1))
}

section() {
  echo ""
  echo "--- Testing: $1 ---"
}

# ============================================================================
# File paths
# ============================================================================

WORKFLOW_ADVANCE="hooks/workflow-advance.sh"
WORKFLOW_GATE="hooks/workflow-gate.sh"
TOKEN_TRACKING="hooks/token-tracking.sh"
SKILL_FILE="skills/ctdd/SKILL.md"
CAUTO_SKILL="skills/cauto/SKILL.md"
DOCS_FILE="docs/skills/ctdd.md"
AGENT_CONTEXT=".correctless/AGENT_CONTEXT.md"

# ============================================================================
# R-001 [unit]: tdd-audit phase in workflow-advance.sh
# ============================================================================

section "R-001: tdd-audit phase exists in workflow-advance.sh"

# R-001a: cmd_audit_mini function exists
if grep -q 'cmd_audit_mini' "$WORKFLOW_ADVANCE"; then
  pass "R-001a" "cmd_audit_mini function exists in workflow-advance.sh"
else
  fail "R-001a" "cmd_audit_mini function not found in workflow-advance.sh"
fi

# R-001b: audit-mini command is registered in the main case dispatch
if grep -q 'audit-mini' "$WORKFLOW_ADVANCE"; then
  pass "R-001b" "audit-mini command registered in workflow-advance.sh dispatch"
else
  fail "R-001b" "audit-mini command not registered in workflow-advance.sh dispatch"
fi

# R-001c: audit-mini accepts tdd-qa as a source phase
if grep -qE 'require_phase_oneof.*tdd-qa' "$WORKFLOW_ADVANCE" && grep -qE 'cmd_audit_mini' "$WORKFLOW_ADVANCE"; then
  # More specific: the cmd_audit_mini function should accept tdd-qa
  if awk '/cmd_audit_mini/,/^cmd_/' "$WORKFLOW_ADVANCE" | grep -q 'tdd-qa'; then
    pass "R-001c" "audit-mini accepts tdd-qa as source phase"
  else
    fail "R-001c" "audit-mini does not accept tdd-qa as source phase"
  fi
else
  fail "R-001c" "audit-mini does not accept tdd-qa as source phase"
fi

# R-001d: audit-mini accepts tdd-impl as a source phase (recheck after fix flow)
if grep -q 'cmd_audit_mini' "$WORKFLOW_ADVANCE"; then
  if awk '/cmd_audit_mini/,/^cmd_/' "$WORKFLOW_ADVANCE" | grep -q 'tdd-impl'; then
    pass "R-001d" "audit-mini accepts tdd-impl as source phase"
  else
    fail "R-001d" "audit-mini does not accept tdd-impl as source phase"
  fi
else
  fail "R-001d" "audit-mini does not accept tdd-impl as source phase"
fi

# R-001e: audit-mini transitions to tdd-audit phase
if grep -q 'cmd_audit_mini' "$WORKFLOW_ADVANCE"; then
  if awk '/cmd_audit_mini/,/^cmd_/' "$WORKFLOW_ADVANCE" | grep -q 'tdd-audit'; then
    pass "R-001e" "audit-mini transitions to tdd-audit phase"
  else
    fail "R-001e" "audit-mini does not transition to tdd-audit phase"
  fi
else
  fail "R-001e" "audit-mini does not transition to tdd-audit phase"
fi

# R-001f: cmd_done accepts tdd-audit as a valid source phase
if grep -q 'cmd_done' "$WORKFLOW_ADVANCE"; then
  if awk '/^cmd_done\(\)/,/^}$/' "$WORKFLOW_ADVANCE" | grep -q 'tdd-audit'; then
    pass "R-001f" "cmd_done accepts tdd-audit as source phase"
  else
    fail "R-001f" "cmd_done does not accept tdd-audit as source phase"
  fi
else
  fail "R-001f" "cmd_done does not accept tdd-audit in workflow-advance.sh"
fi

# R-001g: cmd_fix accepts tdd-audit as a valid source phase (fix from mini-audit)
if grep -q 'cmd_fix' "$WORKFLOW_ADVANCE"; then
  if awk '/^cmd_fix\(\)/,/^}$/' "$WORKFLOW_ADVANCE" | grep -q 'tdd-audit'; then
    pass "R-001g" "cmd_fix accepts tdd-audit as source phase"
  else
    fail "R-001g" "cmd_fix does not accept tdd-audit as source phase"
  fi
else
  fail "R-001g" "cmd_fix does not accept tdd-audit in workflow-advance.sh"
fi

# R-001h: audit-mini requires tests passing (same gate as done)
if grep -q 'cmd_audit_mini' "$WORKFLOW_ADVANCE"; then
  if awk '/^cmd_audit_mini\(\)/,/^}$/' "$WORKFLOW_ADVANCE" | grep -q 'tests_pass'; then
    pass "R-001h" "audit-mini checks that tests pass"
  else
    fail "R-001h" "audit-mini does not check that tests pass"
  fi
else
  fail "R-001h" "audit-mini function not found"
fi

# R-001i: audit-mini checks min QA rounds (same gate as done)
if grep -q 'cmd_audit_mini' "$WORKFLOW_ADVANCE"; then
  if awk '/^cmd_audit_mini\(\)/,/^}$/' "$WORKFLOW_ADVANCE" | grep -q 'min_qa_rounds\|min_rounds\|qa_rounds'; then
    pass "R-001i" "audit-mini checks QA rounds requirement"
  else
    fail "R-001i" "audit-mini does not check QA rounds"
  fi
else
  fail "R-001i" "audit-mini function not found"
fi

# R-001j: tdd-audit is in workflow-gate.sh known-phase allowlist
if grep -q 'tdd-audit' "$WORKFLOW_GATE"; then
  pass "R-001j" "tdd-audit appears in workflow-gate.sh"
else
  fail "R-001j" "tdd-audit not found in workflow-gate.sh"
fi

# R-001k: tdd-audit is in the known-phase validation case in workflow-gate.sh
# The pattern is: spec|review|review-spec|model|tdd-tests|tdd-impl|tdd-qa|tdd-verify|...
if grep -qE 'tdd-audit.*\)' "$WORKFLOW_GATE" || grep -qE '\|tdd-audit' "$WORKFLOW_GATE"; then
  pass "R-001k" "tdd-audit in workflow-gate.sh known-phase case"
else
  fail "R-001k" "tdd-audit not in workflow-gate.sh known-phase case"
fi

# R-001l: tdd-audit receives code-frozen blocking in workflow-gate.sh (alongside tdd-qa|tdd-verify)
if grep -qE 'tdd-qa\|tdd-verify\|tdd-audit|tdd-qa\|tdd-audit\|tdd-verify|tdd-audit\|tdd-qa\|tdd-verify' "$WORKFLOW_GATE"; then
  pass "R-001l" "tdd-audit in code-frozen gating alongside tdd-qa/tdd-verify"
else
  fail "R-001l" "tdd-audit not in code-frozen gating case in workflow-gate.sh"
fi

# R-001m: audit-mini listed in usage/help text of workflow-advance.sh
if grep -q 'audit-mini' "$WORKFLOW_ADVANCE" && grep -qE 'audit.mini|tdd-audit' "$WORKFLOW_ADVANCE"; then
  pass "R-001m" "audit-mini documented in workflow-advance.sh"
else
  fail "R-001m" "audit-mini not documented in workflow-advance.sh help text"
fi

# R-001n: tdd-audit in diagnose command's phase-specific case statement
if awk '/cmd_diagnose/,/^cmd_/' "$WORKFLOW_ADVANCE" | grep -q 'tdd-audit'; then
  pass "R-001n" "tdd-audit handled in diagnose command"
else
  fail "R-001n" "tdd-audit not handled in diagnose command"
fi

# ============================================================================
# R-002 [unit]: /ctdd SKILL.md has mini-audit section
# ============================================================================

section "R-002: /ctdd SKILL.md has Mini-Audit section"

# R-002a: A "Mini-Audit" or "tdd-audit" section exists in SKILL.md
if grep -qi 'mini.audit\|tdd-audit' "$SKILL_FILE"; then
  pass "R-002a" "Mini-audit section exists in ctdd SKILL.md"
else
  fail "R-002a" "No mini-audit section found in ctdd SKILL.md"
fi

# R-002b: The section is between QA and "After TDD Completes"
# Check that "Mini-Audit" appears after "QA" and before "After TDD Completes"
if grep -n 'Phase.*QA\|Phase.*Mini.Audit\|After TDD Completes' "$SKILL_FILE" | head -10 > /dev/null 2>&1; then
  qa_line=$(grep -n 'Phase.*QA' "$SKILL_FILE" | head -1 | cut -d: -f1)
  mini_line=$(grep -n -i 'Phase.*Mini.Audit\|Mini.Audit.*tdd-audit' "$SKILL_FILE" | head -1 | cut -d: -f1)
  after_line=$(grep -n 'After TDD Completes' "$SKILL_FILE" | head -1 | cut -d: -f1)
  if [ -n "$qa_line" ] && [ -n "$mini_line" ] && [ -n "$after_line" ]; then
    if [ "$qa_line" -lt "$mini_line" ] && [ "$mini_line" -lt "$after_line" ]; then
      pass "R-002b" "Mini-audit section is between QA and 'After TDD Completes'"
    else
      fail "R-002b" "Mini-audit section is not properly positioned (qa=$qa_line, mini=$mini_line, after=$after_line)"
    fi
  else
    fail "R-002b" "Could not find all section markers (qa=$qa_line, mini=$mini_line, after=$after_line)"
  fi
else
  fail "R-002b" "Missing section markers in SKILL.md"
fi

# R-002c: The section mentions workflow-advance.sh audit-mini
if grep -q 'workflow-advance.sh audit-mini\|workflow-advance\.sh.*audit-mini' "$SKILL_FILE"; then
  pass "R-002c" "SKILL.md references workflow-advance.sh audit-mini"
else
  fail "R-002c" "SKILL.md does not reference workflow-advance.sh audit-mini"
fi

# R-002d: Intensity-scaled rounds are documented (standard=1, high=2, critical=3)
if grep -qE 'standard.*1|1.*round' "$SKILL_FILE" && grep -qE 'high.*2|2.*round' "$SKILL_FILE" && grep -qE 'critical.*3|3.*round' "$SKILL_FILE"; then
  pass "R-002d" "Intensity-scaled round counts documented"
else
  fail "R-002d" "Intensity-scaled round counts not documented in SKILL.md"
fi

# ============================================================================
# R-003 [unit]: Three specialist agents with specific prompts
# ============================================================================

section "R-003: Three specialist agent prompts"

# R-003a: Cross-component interaction agent prompt
if grep -qi 'cross.component' "$SKILL_FILE"; then
  pass "R-003a" "Cross-component interaction agent referenced in SKILL.md"
else
  fail "R-003a" "Cross-component interaction agent not found in SKILL.md"
fi

# R-003b: Hostile input agent prompt
if grep -qi 'hostile.input\|attacker' "$SKILL_FILE"; then
  pass "R-003b" "Hostile input agent referenced in SKILL.md"
else
  fail "R-003b" "Hostile input agent not found in SKILL.md"
fi

# R-003c: Resource bounds agent prompt
if grep -qi 'resource.bound' "$SKILL_FILE"; then
  pass "R-003c" "Resource bounds agent referenced in SKILL.md"
else
  fail "R-003c" "Resource bounds agent not found in SKILL.md"
fi

# R-003d: Cross-component agent mentions entrypoints and trust boundaries
if grep -qi 'entrypoint' "$SKILL_FILE" && grep -qi 'trust.boundar' "$SKILL_FILE"; then
  pass "R-003d" "Cross-component agent references entrypoints and trust boundaries"
else
  fail "R-003d" "Cross-component agent missing entrypoints or trust boundaries reference"
fi

# R-003e: Hostile input agent mentions incorrect behavior / security bypass / silent data corruption
if grep -qi 'incorrect.behavior\|security.bypass\|silent.data.corruption\|wrong.result' "$SKILL_FILE"; then
  pass "R-003e" "Hostile input agent mentions specific failure modes"
else
  fail "R-003e" "Hostile input agent missing specific failure mode descriptions"
fi

# R-003f: Resource bounds agent mentions exhaustion/leak/contention
if grep -qi 'exhaust\|leak\|contend' "$SKILL_FILE"; then
  pass "R-003f" "Resource bounds agent mentions resource failure modes"
else
  fail "R-003f" "Resource bounds agent missing resource failure mode descriptions"
fi

# R-003g: Agents are described as running in parallel (forked subagents)
if grep -qi 'parallel\|fork' "$SKILL_FILE"; then
  pass "R-003g" "Agents described as parallel/forked"
else
  fail "R-003g" "No mention of parallel/forked agent execution"
fi

# ============================================================================
# R-004 [unit]: Agent context and tool restrictions
# ============================================================================

section "R-004: Agent context and tool restrictions"

# R-004a: Agents receive spec as context
if grep -qi 'spec.*context\|read.*spec\|receive.*spec' "$SKILL_FILE"; then
  pass "R-004a" "Agents receive spec as context"
else
  fail "R-004a" "No mention of spec as agent context"
fi

# R-004b: Agents receive ARCHITECTURE.md
if grep -q 'ARCHITECTURE.md' "$SKILL_FILE"; then
  pass "R-004b" "Agents receive ARCHITECTURE.md"
else
  fail "R-004b" "No ARCHITECTURE.md in agent context"
fi

# R-004c: Agents have read-only tools (Read, Grep, Glob)
if grep -qi 'Read.*Grep.*Glob\|read-only' "$SKILL_FILE"; then
  pass "R-004c" "Read-only tool restrictions mentioned"
else
  fail "R-004c" "Read-only tool restrictions not mentioned in SKILL.md"
fi

# R-004d: No Write/Edit tools for mini-audit agents
if grep -qi 'no.*Write\|no.*Edit\|read-only' "$SKILL_FILE"; then
  pass "R-004d" "Write/Edit exclusion mentioned"
else
  fail "R-004d" "Write/Edit exclusion not explicitly mentioned for mini-audit agents"
fi

# ============================================================================
# R-005 [unit]: MA- prefix finding format
# ============================================================================

section "R-005: MA- prefix finding format"

# R-005a: MA- prefix is documented
if grep -q 'MA-' "$SKILL_FILE"; then
  pass "R-005a" "MA- prefix finding format documented in SKILL.md"
else
  fail "R-005a" "MA- prefix not found in SKILL.md"
fi

# R-005b: Finding format includes SEVERITY field
if grep -qi 'SEVERITY.*CRITICAL\|SEVERITY.*HIGH\|SEVERITY:' "$SKILL_FILE"; then
  pass "R-005b" "SEVERITY field in finding format"
else
  fail "R-005b" "SEVERITY field not found in finding format"
fi

# R-005c: Finding format includes LENS field
if grep -q 'LENS' "$SKILL_FILE"; then
  pass "R-005c" "LENS field in finding format"
else
  fail "R-005c" "LENS field not found in finding format"
fi

# R-005d: Finding format includes INSTANCE_FIX and CLASS_FIX
if grep -q 'INSTANCE_FIX' "$SKILL_FILE" && grep -q 'CLASS_FIX' "$SKILL_FILE"; then
  pass "R-005d" "INSTANCE_FIX and CLASS_FIX in finding format"
else
  fail "R-005d" "INSTANCE_FIX and/or CLASS_FIX missing from finding format"
fi

# R-005e: Findings persisted to qa-findings JSON
if grep -qi 'qa-findings.*json\|qa.findings' "$SKILL_FILE"; then
  pass "R-005e" "Findings persisted to qa-findings JSON"
else
  fail "R-005e" "No reference to qa-findings JSON persistence"
fi

# ============================================================================
# R-006 [unit]: Disposition options for CRITICAL/HIGH findings
# ============================================================================

section "R-006: Disposition options"

# R-006a: "Fix now" disposition option
if grep -qi 'Fix now' "$SKILL_FILE"; then
  pass "R-006a" "'Fix now' disposition option present"
else
  fail "R-006a" "'Fix now' disposition option not found"
fi

# R-006b: "Accept risk" disposition option
if grep -qi 'Accept risk' "$SKILL_FILE"; then
  pass "R-006b" "'Accept risk' disposition option present"
else
  fail "R-006b" "'Accept risk' disposition option not found"
fi

# R-006c: "Dispute" disposition option
if grep -qi 'Dispute' "$SKILL_FILE"; then
  pass "R-006c" "'Dispute' disposition option present"
else
  fail "R-006c" "'Dispute' disposition option not found"
fi

# R-006d: MEDIUM/LOW findings are advisory (non-blocking)
if grep -qi 'advisory\|non-blocking\|MEDIUM.*LOW.*advisory\|MEDIUM.*advisory' "$SKILL_FILE"; then
  pass "R-006d" "MEDIUM/LOW as advisory documented"
else
  fail "R-006d" "MEDIUM/LOW advisory status not documented"
fi

# ============================================================================
# R-007 [unit]: Fix loop with regression test requirement
# ============================================================================

section "R-007: Fix loop with regression test"

# R-007a: Fix transitions back to tdd-impl
if grep -qi 'tdd-impl.*fix\|fix.*tdd-impl\|workflow-advance.sh fix' "$SKILL_FILE"; then
  pass "R-007a" "Fix transitions back to tdd-impl documented"
else
  fail "R-007a" "Fix transition to tdd-impl not documented in SKILL.md"
fi

# R-007b: Regression test requirement for fixes
if grep -qi 'regression.test\|regression.*fix' "$SKILL_FILE"; then
  pass "R-007b" "Regression test requirement documented"
else
  fail "R-007b" "Regression test requirement not documented in SKILL.md"
fi

# R-007c: Re-runs only the mini-audit round that produced the finding
if grep -qi 're-run.*round\|recheck.*round\|only.*round\|single round' "$SKILL_FILE"; then
  pass "R-007c" "Re-run of specific round documented"
else
  fail "R-007c" "Specific round re-run not documented"
fi

# R-007d: Fix uses workflow-advance.sh audit-mini to return to tdd-audit
if grep -qi 'audit-mini.*tdd-impl\|tdd-impl.*audit-mini' "$SKILL_FILE"; then
  pass "R-007d" "Fix flow uses audit-mini from tdd-impl"
else
  fail "R-007d" "Fix flow via audit-mini from tdd-impl not documented"
fi

# ============================================================================
# R-008 [unit]: Raise-the-bar prompt and no-anchoring
# ============================================================================

section "R-008: Raise-the-bar prompt and no-anchoring"

# R-008a: No-anchoring constraint — round 2+ agents don't see previous findings
if grep -qi 'anchor\|fresh.*context\|start fresh\|no.*previous.*finding' "$SKILL_FILE"; then
  pass "R-008a" "No-anchoring constraint documented"
else
  fail "R-008a" "No-anchoring constraint not found in SKILL.md"
fi

# R-008b: Raise-the-bar prompt text
if grep -qi 'raise.the.bar\|sloppy.*missed\|overconfident.*under-thorough\|Do better' "$SKILL_FILE"; then
  pass "R-008b" "Raise-the-bar prompt present"
else
  fail "R-008b" "Raise-the-bar prompt not found in SKILL.md"
fi

# R-008c: Deduplication happens at orchestrator level
if grep -qi 'deduplicat.*orchestrator\|orchestrator.*deduplicat' "$SKILL_FILE"; then
  pass "R-008c" "Orchestrator-level deduplication documented"
else
  fail "R-008c" "Orchestrator-level deduplication not documented"
fi

# ============================================================================
# R-009 [integration]: /cauto phase mapping
# ============================================================================

section "R-009: /cauto phase mapping"

# R-009a: tdd-audit appears in cauto SKILL.md
if grep -q 'tdd-audit' "$CAUTO_SKILL"; then
  pass "R-009a" "tdd-audit referenced in cauto SKILL.md"
else
  fail "R-009a" "tdd-audit not found in cauto SKILL.md"
fi

# R-009b: tdd-audit row in phase-to-step mapping table
if grep -q 'tdd-audit' "$CAUTO_SKILL" && grep -q 'tdd-audit.*Resume\|tdd-audit.*ctdd' "$CAUTO_SKILL"; then
  pass "R-009b" "tdd-audit row in cauto phase mapping table"
else
  fail "R-009b" "tdd-audit row not found in cauto phase mapping table"
fi

# ============================================================================
# R-010 [unit]: Progress announcements
# ============================================================================

section "R-010: Progress announcements"

# R-010a: Round start announcement format
if grep -qi 'Starting mini-audit round\|mini.audit round.*spawning' "$SKILL_FILE"; then
  pass "R-010a" "Round start announcement documented"
else
  fail "R-010a" "Round start announcement not found in SKILL.md"
fi

# R-010b: Agent completion announcement
if grep -qi 'complete.*found\|complete.*finding\|agent.*still running' "$SKILL_FILE"; then
  pass "R-010b" "Agent completion announcement documented"
else
  fail "R-010b" "Agent completion announcement not found in SKILL.md"
fi

# R-010c: Round completion summary
if grep -qi 'Round.*complete.*total.*finding\|round.*complete.*blocking.*advisory' "$SKILL_FILE"; then
  pass "R-010c" "Round completion summary documented"
else
  fail "R-010c" "Round completion summary not found in SKILL.md"
fi

# ============================================================================
# R-011 [unit]: Pipeline diagram
# ============================================================================

section "R-011: Pipeline diagram"

# R-011a: Pipeline diagram includes mini-audit
if grep -qi 'mini-audit\|mini.audit' "$SKILL_FILE"; then
  # Check the pipeline diagram line contains mini-audit between QA and done
  if grep -qE 'QA.*mini.audit.*done' "$SKILL_FILE"; then
    pass "R-011a" "Pipeline diagram includes mini-audit between QA and done"
  else
    fail "R-011a" "Pipeline diagram does not show mini-audit between QA and done"
  fi
else
  fail "R-011a" "mini-audit not found in SKILL.md pipeline"
fi

# R-011b: Full pipeline description updated
if grep -qE 'RED.*GREEN.*QA.*mini.audit|RED.*audit.*GREEN.*QA.*mini.audit' "$SKILL_FILE"; then
  pass "R-011b" "Full pipeline description includes mini-audit"
else
  fail "R-011b" "Full pipeline description does not include mini-audit"
fi

# R-011c: Constraints section pipeline updated
if grep -qi 'mini-audit' "$SKILL_FILE" && grep -qi 'Constraint' "$SKILL_FILE"; then
  pass "R-011c" "Constraints section references mini-audit"
else
  fail "R-011c" "Constraints section does not reference mini-audit"
fi

# ============================================================================
# R-012 [unit]: Architecture-aware instructions
# ============================================================================

section "R-012: Architecture-aware instructions"

# R-012a: Cross-component agent references entrypoints YAML markers
if grep -qi 'entrypoints:start\|entrypoints:end\|entrypoint' "$SKILL_FILE"; then
  pass "R-012a" "Entrypoints markers referenced"
else
  fail "R-012a" "Entrypoints markers not referenced in SKILL.md"
fi

# R-012b: Fallback for missing entrypoints (git diff-scoped analysis)
if grep -qi 'git diff.*fallback\|fallback.*git diff\|no entrypoint' "$SKILL_FILE"; then
  pass "R-012b" "Fallback for missing entrypoints documented"
else
  fail "R-012b" "Fallback for missing entrypoints not documented"
fi

# R-012c: Hostile input agent reads trust boundaries (TB-xxx)
if grep -qE 'TB-|trust.boundar' "$SKILL_FILE"; then
  pass "R-012c" "Trust boundaries referenced for hostile input agent"
else
  fail "R-012c" "Trust boundaries not referenced for hostile input agent"
fi

# R-012d: Resource bounds agent reads environment assumptions (ENV-xxx)
if grep -qE 'ENV-|environment.assumption' "$SKILL_FILE"; then
  pass "R-012d" "Environment assumptions referenced for resource bounds agent"
else
  fail "R-012d" "Environment assumptions not referenced for resource bounds agent"
fi

# ============================================================================
# R-013 [unit]: Fixed rounds, no convergence
# ============================================================================

section "R-013: Fixed rounds, no convergence"

# R-013a: Explicitly states no convergence loop
if grep -qi 'no.*convergence\|not.*convergence\|fixed.*round\|fixed.cost' "$SKILL_FILE"; then
  pass "R-013a" "No-convergence constraint documented"
else
  fail "R-013a" "No-convergence constraint not found in SKILL.md"
fi

# R-013b: Fixed round counts: 1/2/3
if grep -qE '1.*2.*3|standard.*1.*high.*2.*critical.*3' "$SKILL_FILE"; then
  pass "R-013b" "Fixed round counts 1/2/3 documented"
else
  fail "R-013b" "Fixed round counts not documented"
fi

# ============================================================================
# R-014 [unit]: UNCERTAIN severity
# ============================================================================

section "R-014: UNCERTAIN severity"

# R-014a: UNCERTAIN severity level defined
if grep -q 'UNCERTAIN' "$SKILL_FILE"; then
  pass "R-014a" "UNCERTAIN severity defined in SKILL.md"
else
  fail "R-014a" "UNCERTAIN severity not found in SKILL.md"
fi

# R-014b: UNCERTAIN is non-blocking/advisory
if grep -qi 'UNCERTAIN.*advisory\|UNCERTAIN.*non.blocking\|advisory.*UNCERTAIN' "$SKILL_FILE"; then
  pass "R-014b" "UNCERTAIN as advisory documented"
else
  fail "R-014b" "UNCERTAIN advisory status not documented"
fi

# R-014c: >50% UNCERTAIN triggers low-confidence flag
if grep -qi '50.*UNCERTAIN\|UNCERTAIN.*50\|low.confidence' "$SKILL_FILE"; then
  pass "R-014c" ">50% UNCERTAIN low-confidence flag documented"
else
  fail "R-014c" ">50% UNCERTAIN low-confidence flag not documented"
fi

# ============================================================================
# R-015 [unit]: Token tracking mapping
# ============================================================================

section "R-015: Token tracking mapping"

# R-015a: tdd-audit -> ctdd mapping in token-tracking.sh
if grep -qE 'tdd-audit.*ctdd|tdd-audit\).*SKILL_VAL.*ctdd' "$TOKEN_TRACKING"; then
  pass "R-015a" "tdd-audit -> ctdd mapping in token-tracking.sh"
else
  fail "R-015a" "tdd-audit -> ctdd mapping not found in token-tracking.sh"
fi

# R-015b: tdd-audit is in the phase-to-skill case statement
if grep -q 'tdd-audit' "$TOKEN_TRACKING"; then
  pass "R-015b" "tdd-audit appears in token-tracking.sh"
else
  fail "R-015b" "tdd-audit not found in token-tracking.sh"
fi

# R-015c: mini-audit-round-N phase format mentioned in SKILL.md
if grep -qi 'mini-audit-round\|mini.audit.*round' "$SKILL_FILE"; then
  pass "R-015c" "mini-audit-round phase format in SKILL.md"
else
  fail "R-015c" "mini-audit-round phase format not found in SKILL.md"
fi

# ============================================================================
# R-016 [unit]: Intensity table
# ============================================================================

section "R-016: Intensity table"

# R-016a: Intensity table includes mini-audit rounds row
# Extract the table area between "Intensity Configuration" header and the next section
if sed -n '/^## Intensity Configuration/,/^## [^I]/p' "$SKILL_FILE" | grep -qi 'Mini.audit.*round\|Mini.audit'; then
  pass "R-016a" "Mini-audit rounds row in intensity table"
else
  fail "R-016a" "Mini-audit rounds not in intensity configuration table"
fi

# R-016b: Intensity table shows standard=1, high=2, critical=3 for mini-audit
if sed -n '/^## Intensity Configuration/,/^## [^I]/p' "$SKILL_FILE" | grep -qi 'Mini.audit' && \
   sed -n '/^## Intensity Configuration/,/^## [^I]/p' "$SKILL_FILE" | grep -qE '1.*2.*3'; then
  pass "R-016b" "Intensity table round counts 1/2/3 present"
else
  fail "R-016b" "Intensity table does not show round counts 1/2/3"
fi

# ============================================================================
# R-017 [unit]: Documentation updates
# ============================================================================

section "R-017: Documentation updates"

# R-017a: docs/skills/ctdd.md mentions mini-audit
if grep -qi 'mini.audit\|tdd-audit' "$DOCS_FILE" 2>/dev/null; then
  pass "R-017a" "docs/skills/ctdd.md mentions mini-audit"
else
  fail "R-017a" "docs/skills/ctdd.md does not mention mini-audit"
fi

# R-017b: AGENT_CONTEXT.md pipeline description includes mini-audit
if grep -qi 'mini.audit\|tdd-audit' "$AGENT_CONTEXT" 2>/dev/null; then
  pass "R-017b" "AGENT_CONTEXT.md references mini-audit"
else
  fail "R-017b" "AGENT_CONTEXT.md does not reference mini-audit"
fi

# ============================================================================
# R-018 [unit]: Deduplication
# ============================================================================

section "R-018: Deduplication"

# R-018a: Deduplication by file + issue category documented
if grep -qi 'deduplicat.*file.*category\|file.*issue.*category.*deduplicat\|deduplicat' "$SKILL_FILE"; then
  pass "R-018a" "Deduplication by file + issue category documented"
else
  fail "R-018a" "Deduplication mechanism not documented in SKILL.md"
fi

# R-018b: duplicate_of field mentioned
if grep -q 'duplicate_of' "$SKILL_FILE"; then
  pass "R-018b" "duplicate_of field documented"
else
  fail "R-018b" "duplicate_of field not found in SKILL.md"
fi

# R-018c: Higher severity finding kept
if grep -qi 'higher.severity\|keep.*higher\|keeps.*higher' "$SKILL_FILE"; then
  pass "R-018c" "Higher severity retention documented"
else
  fail "R-018c" "Higher severity retention not documented"
fi

# ============================================================================
# R-019 [unit]: Agent failure handling
# ============================================================================

section "R-019: Agent failure handling"

# R-019a: Agent failure handling documented (context limit, tool error, etc.)
if grep -qi 'agent.*fail\|fail.*agent\|context.limit\|tool.error\|malformed.output\|timeout' "$SKILL_FILE"; then
  pass "R-019a" "Agent failure scenarios documented"
else
  fail "R-019a" "Agent failure scenarios not documented in SKILL.md"
fi

# R-019b: No automatic retry
if grep -qi 'no.*retry\|no.*automatic.*retry\|not.*retry' "$SKILL_FILE"; then
  pass "R-019b" "No automatic retry documented"
else
  fail "R-019b" "No-retry policy not documented"
fi

# R-019c: Warning message about missing lens
if grep -qi 'Warning.*agent.*failed\|missing.*lens\|lens.*not.*evaluated' "$SKILL_FILE"; then
  pass "R-019c" "Missing lens warning documented"
else
  fail "R-019c" "Missing lens warning not documented in SKILL.md"
fi

# ============================================================================
# R-020 [unit]: Zero findings + clean round
# ============================================================================

section "R-020: Zero findings + clean round"

# R-020a: Clean round announcement
if grep -qi 'clean.*no.*finding\|no.*finding.*all.*three.*lens\|round.*clean' "$SKILL_FILE"; then
  pass "R-020a" "Clean round announcement documented"
else
  fail "R-020a" "Clean round announcement not documented in SKILL.md"
fi

# R-020b: Incomplete vs clean distinction (failed agent makes round "incomplete" not "clean")
if grep -qi 'incomplete.*rather.*clean\|incomplete.*not.*clean\|not.*clean.*failed' "$SKILL_FILE"; then
  pass "R-020b" "Incomplete vs clean distinction documented"
else
  fail "R-020b" "Incomplete vs clean distinction not documented"
fi

# R-020c: Does not auto-transition to done
if grep -qi 'no.*auto.*transition\|not.*auto.*done\|does not auto\|wait.*user\|waits.*user' "$SKILL_FILE"; then
  pass "R-020c" "No auto-transition to done documented"
else
  fail "R-020c" "No auto-transition to done not documented"
fi

# R-020d: Subsequent rounds still run even if earlier rounds clean (multi-round)
if grep -qi 'subsequent.*round.*still.*run\|later.*round.*still\|fresh.context\|still run.*even.*clean' "$SKILL_FILE"; then
  pass "R-020d" "Subsequent rounds run even if earlier clean documented"
else
  fail "R-020d" "Subsequent rounds behavior not documented"
fi

# ============================================================================
# Summary
# ============================================================================

echo ""
echo "========================================="
echo "  TDD Mini-Audit Tests: $PASS passed, $FAIL failed, $SKIPPED skipped"
echo "========================================="
if [ -n "$FAILED_IDS" ]; then
  echo "  Failed: $FAILED_IDS"
fi
echo ""

# Exit with failure if any tests failed
[ "$FAIL" -eq 0 ]
