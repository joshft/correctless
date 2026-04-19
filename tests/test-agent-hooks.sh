#!/usr/bin/env bash
# shellcheck disable=SC1090,SC1091,SC2016
# Correctless — Agent Hook Tests (import-guard)
#
# Enforces the agent-hooks spec rules (R-001..R-012).
# Tests are structural — they verify the JSON config structure,
# prompt content, setup registration, sync propagation, and docs.
#
# Run from repo root: bash tests/test-agent-hooks.sh

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

HOOK_FILE="hooks/import-guard.json"
HOOK_DIST="correctless/hooks/import-guard.json"
SYNC_FILE="sync.sh"
AGENT_CONTEXT=".correctless/AGENT_CONTEXT.md"
CONTRIBUTING_MD="CONTRIBUTING.md"

echo "Correctless Agent Hook Tests (import-guard)"
echo "============================================="

# ============================================================================
# R-001 [unit]: Hook config file exists with correct structure
# ============================================================================

section "R-001: Hook config file exists with correct structure"

# R-001a: Hook config file exists at hooks/import-guard.json
if [ -f "$HOOK_FILE" ]; then
  pass "R-001a" "Hook config file exists at $HOOK_FILE"
else
  fail "R-001a" "Hook config file does not exist at $HOOK_FILE"
fi

# R-001b: Hook config is valid JSON
if [ -f "$HOOK_FILE" ] && jq empty "$HOOK_FILE" 2>/dev/null; then
  pass "R-001b" "Hook config is valid JSON"
else
  fail "R-001b" "Hook config is not valid JSON"
fi

# R-001c: Hook config has type: "agent"
if [ -f "$HOOK_FILE" ] && jq -e '.type == "agent"' "$HOOK_FILE" >/dev/null 2>&1; then
  pass "R-001c" "Hook config has type 'agent'"
else
  fail "R-001c" "Hook config does not have type 'agent'"
fi

# R-001d: Hook config has a matcher field for Write|Edit
if [ -f "$HOOK_FILE" ]; then
  matcher=$(jq -r '.matcher // ""' "$HOOK_FILE" 2>/dev/null)
  if echo "$matcher" | grep -q 'Write' && echo "$matcher" | grep -q 'Edit'; then
    pass "R-001d" "Hook config matcher includes Write and Edit"
  else
    fail "R-001d" "Hook config matcher does not include both Write and Edit (got: '$matcher')"
  fi
else
  fail "R-001d" "Hook config file missing — cannot check matcher"
fi

# R-001e: Hook config has a prompt field (non-empty string)
if [ -f "$HOOK_FILE" ] && jq -e '.prompt | type == "string" and length > 0' "$HOOK_FILE" >/dev/null 2>&1; then
  pass "R-001e" "Hook config has a non-empty prompt field"
else
  fail "R-001e" "Hook config does not have a non-empty prompt field"
fi

# R-001f: Hook config has hook_type: "PreToolUse" (for setup registration)
if [ -f "$HOOK_FILE" ] && jq -e '.hook_type == "PreToolUse"' "$HOOK_FILE" >/dev/null 2>&1; then
  pass "R-001f" "Hook config has hook_type 'PreToolUse'"
else
  fail "R-001f" "Hook config does not have hook_type 'PreToolUse'"
fi

# ============================================================================
# R-002 [unit]: Prompt includes the sequential check steps
# ============================================================================

section "R-002: Prompt includes sequential check steps"

if [ -f "$HOOK_FILE" ]; then
  prompt=$(jq -r '.prompt // ""' "$HOOK_FILE" 2>/dev/null)
else
  prompt=""
fi

# R-002a: Prompt mentions checking if file is a test file
if echo "$prompt" | grep -qi 'test file'; then
  pass "R-002a" "Prompt mentions checking for test files"
else
  fail "R-002a" "Prompt does not mention checking for test files"
fi

# R-002b: Prompt mentions returning ok:true for non-test files
if echo "$prompt" | grep -qi 'not a test.*allow\|non-test.*allow\|not.*test file.*allow'; then
  pass "R-002b" "Prompt mentions allowing non-test files"
else
  fail "R-002b" "Prompt does not mention allowing non-test files"
fi

# R-002c: Prompt mentions checking ARCHITECTURE.md for entrypoints
if echo "$prompt" | grep -qi 'ARCHITECTURE.md.*entrypoint\|entrypoint.*ARCHITECTURE.md'; then
  pass "R-002c" "Prompt mentions checking ARCHITECTURE.md for entrypoints"
else
  fail "R-002c" "Prompt does not mention checking ARCHITECTURE.md for entrypoints"
fi

# R-002d: Prompt mentions the entrypoints markers
if echo "$prompt" | grep -q 'correctless:entrypoints:start'; then
  pass "R-002d" "Prompt mentions entrypoints markers"
else
  fail "R-002d" "Prompt does not mention entrypoints markers"
fi

# R-002e: Prompt mentions reading test_helpers allow-list
if echo "$prompt" | grep -qi 'test_helpers'; then
  pass "R-002e" "Prompt mentions test_helpers allow-list"
else
  fail "R-002e" "Prompt does not mention test_helpers allow-list"
fi

# R-002f: Prompt mentions checking imports against entrypoint scope
if echo "$prompt" | grep -qi 'import.*scope\|scope.*import\|imports.*within.*scope'; then
  pass "R-002f" "Prompt mentions checking imports against entrypoint scope"
else
  fail "R-002f" "Prompt does not mention checking imports against entrypoint scope"
fi

# R-002g: Prompt mentions deny with reason for internal imports
if echo "$prompt" | grep -qi 'deny\|block.*reason\|reason.*block'; then
  pass "R-002g" "Prompt mentions denying with reason for internal imports"
else
  fail "R-002g" "Prompt does not mention denying with reason"
fi

# ============================================================================
# R-003 [unit]: Language-aware import patterns
# ============================================================================

section "R-003: Language-aware import patterns"

# R-003a: Prompt mentions Go import pattern
if echo "$prompt" | grep -q 'import ".*\|Go.*import'; then
  pass "R-003a" "Prompt mentions Go import pattern"
else
  fail "R-003a" "Prompt does not mention Go import pattern"
fi

# R-003b: Prompt mentions TypeScript/JavaScript import pattern
if echo "$prompt" | grep -qi 'import.*from\|require('; then
  pass "R-003b" "Prompt mentions TypeScript/JavaScript import pattern"
else
  fail "R-003b" "Prompt does not mention TypeScript/JavaScript import pattern"
fi

# R-003c: Prompt mentions Python import pattern
if echo "$prompt" | grep -qi 'from.*import\|import.*python\|Python.*import'; then
  pass "R-003c" "Prompt mentions Python import pattern"
else
  fail "R-003c" "Prompt does not mention Python import pattern"
fi

# R-003d: Prompt mentions Rust import pattern
if echo "$prompt" | grep -qi 'use crate\|Rust.*use\|mod.*rust\|Rust.*mod'; then
  pass "R-003d" "Prompt mentions Rust import pattern"
else
  fail "R-003d" "Prompt does not mention Rust import pattern"
fi

# R-003e: Prompt mentions allowing unsupported languages
if echo "$prompt" | grep -qi 'unsupported.*language.*allow\|language.*not.*list.*allow\|not in this list.*allow'; then
  pass "R-003e" "Prompt mentions allowing unsupported languages"
else
  fail "R-003e" "Prompt does not mention allowing unsupported languages"
fi

# ============================================================================
# R-004 [unit]: Entrypoint self-import exclusion
# ============================================================================

section "R-004: Entrypoint self-import exclusion"

# R-004a: Prompt mentions excluding the entrypoint handler itself
if echo "$prompt" | grep -qi 'entrypoint.*handler.*itself\|entrypoint itself\|exclude.*entrypoint.*handler\|self-import\|not.*flag.*entrypoint.*handler'; then
  pass "R-004a" "Prompt mentions excluding entrypoint handler imports"
else
  fail "R-004a" "Prompt does not mention excluding entrypoint handler imports"
fi

# R-004b: Prompt distinguishes internal packages from the entrypoint
if echo "$prompt" | grep -qi 'within.*scope.*through.*entrypoint\|packages.*within.*entrypoint.*scope\|internal.*package.*not.*entrypoint'; then
  pass "R-004b" "Prompt distinguishes internal packages from entrypoint"
else
  fail "R-004b" "Prompt does not distinguish internal packages from entrypoint"
fi

# ============================================================================
# R-005 [unit]: Timeout configuration
# ============================================================================

section "R-005: Timeout configuration"

# R-005a: Hook config has timeout field set to 30
if [ -f "$HOOK_FILE" ] && jq -e '.timeout == 30' "$HOOK_FILE" >/dev/null 2>&1; then
  pass "R-005a" "Hook config has timeout set to 30 seconds"
else
  fail "R-005a" "Hook config does not have timeout set to 30 seconds"
fi

# R-005b: Hook config does NOT specify a model field (defaults to Haiku)
if [ -f "$HOOK_FILE" ]; then
  has_model=$(jq 'has("model")' "$HOOK_FILE" 2>/dev/null)
  if [ "$has_model" = "false" ]; then
    pass "R-005b" "Hook config omits model field (defaults to Haiku)"
  else
    fail "R-005b" "Hook config specifies a model field (should default to Haiku)"
  fi
else
  fail "R-005b" "Hook config file missing — cannot check model field"
fi

# ============================================================================
# R-006 [integration]: Setup script registers the agent hook
# ============================================================================

section "R-006: Setup script registers agent hook"

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="/tmp/correctless-test-agent-hooks-$$"

cleanup() {
  rm -rf "$TEST_DIR"
}
trap cleanup EXIT

setup_test_project() {
  rm -rf "$TEST_DIR"
  mkdir -p "$TEST_DIR"
  cd "$TEST_DIR" || exit 1
  git init -q
  git branch -M main
  echo "init" > README.md
  git add -A && git commit -q -m "init"

  # Install correctless (exclude .git to avoid nested repo confusion)
  mkdir -p .claude/skills/workflow
  rsync -a --exclude='.git' --exclude='tests' "$REPO_DIR/" .claude/skills/workflow/
}

# R-006a: Setup script registers agent hook from import-guard.json
setup_test_project
SETUP=".claude/skills/workflow/setup"
if [ -f "$SETUP" ]; then
  bash "$SETUP" > /dev/null 2>&1
  settings="$TEST_DIR/.claude/settings.json"
  if [ -f "$settings" ] && jq -e '.hooks.PreToolUse[] | .hooks[] | select(.type == "agent")' "$settings" >/dev/null 2>&1; then
    pass "R-006a" "Setup registers agent hook in settings.json"
  else
    fail "R-006a" "Setup does not register agent hook in settings.json"
  fi
else
  fail "R-006a" "Setup script not found"
fi
cd "$REPO_DIR" || exit 1

# R-006b: Setup registers agent hook with correct prompt from JSON config
setup_test_project
SETUP=".claude/skills/workflow/setup"
if [ -f "$SETUP" ]; then
  bash "$SETUP" > /dev/null 2>&1
  settings="$TEST_DIR/.claude/settings.json"
  if [ -f "$settings" ]; then
    agent_prompt=$(jq -r '.hooks.PreToolUse[] | .hooks[] | select(.type == "agent") | .prompt // ""' "$settings" 2>/dev/null | head -1)
    if [ -n "$agent_prompt" ] && [ ${#agent_prompt} -gt 50 ]; then
      pass "R-006b" "Setup registers agent hook with non-trivial prompt"
    else
      fail "R-006b" "Setup does not register agent hook with proper prompt"
    fi
  else
    fail "R-006b" "settings.json not found after setup"
  fi
else
  fail "R-006b" "Setup script not found"
fi
cd "$REPO_DIR" || exit 1

# R-006c: Setup is idempotent — re-running does not duplicate agent hooks
setup_test_project
SETUP=".claude/skills/workflow/setup"
if [ -f "$SETUP" ]; then
  bash "$SETUP" > /dev/null 2>&1
  bash "$SETUP" > /dev/null 2>&1  # Run twice
  settings="$TEST_DIR/.claude/settings.json"
  if [ -f "$settings" ]; then
    agent_count=$(jq '[.hooks.PreToolUse[]?.hooks[]? | select(.type == "agent")] | length' "$settings" 2>/dev/null)
    if [ "$agent_count" = "1" ]; then
      pass "R-006c" "Setup is idempotent — one agent hook after two runs"
    else
      fail "R-006c" "Setup is not idempotent — $agent_count agent hooks after two runs"
    fi
  else
    fail "R-006c" "settings.json not found after setup"
  fi
else
  fail "R-006c" "Setup script not found"
fi
cd "$REPO_DIR" || exit 1

# ============================================================================
# R-007 [unit]: Graceful degradation without entrypoints
# ============================================================================

section "R-007: Graceful degradation without entrypoints"

# R-007a: Prompt mentions graceful degradation when no entrypoints exist
if echo "$prompt" | grep -qi 'no entrypoint.*allow\|no.*entrypoints.*allow\|graceful.*degradation\|return.*allow.*no.*entrypoint'; then
  pass "R-007a" "Prompt mentions graceful degradation without entrypoints"
else
  fail "R-007a" "Prompt does not mention graceful degradation without entrypoints"
fi

# R-007b: Prompt mentions checking for entrypoints markers before parsing
if echo "$prompt" | grep -q 'correctless:entrypoints:start'; then
  pass "R-007b" "Prompt checks for entrypoints markers (already verified in R-002d)"
else
  fail "R-007b" "Prompt does not check for entrypoints markers"
fi

# ============================================================================
# R-008 [unit]: Documentation in hook file
# ============================================================================

section "R-008: Documentation in hook file"

# R-008a: Hook config has a _description field explaining what it does
if [ -f "$HOOK_FILE" ] && jq -e '._description | type == "string" and length > 20' "$HOOK_FILE" >/dev/null 2>&1; then
  pass "R-008a" "Hook config has a _description field"
else
  fail "R-008a" "Hook config does not have a _description field (JSON has no comments — use _description)"
fi

# R-008b: Description references the entrypoint documentation
if [ -f "$HOOK_FILE" ]; then
  desc=$(jq -r '._description // ""' "$HOOK_FILE" 2>/dev/null)
  if echo "$desc" | grep -qi 'entrypoint\|ARCHITECTURE.md\|test audit'; then
    pass "R-008b" "Description references entrypoint documentation"
  else
    fail "R-008b" "Description does not reference entrypoint documentation"
  fi
else
  fail "R-008b" "Hook config file missing"
fi

# ============================================================================
# R-009 [unit]: Documentation updates
# ============================================================================

section "R-009: Documentation updates"

# R-009a: AGENT_CONTEXT.md references agent hooks or import-guard
if grep -qi 'import-guard\|agent hook' "$AGENT_CONTEXT" 2>/dev/null; then
  pass "R-009a" "AGENT_CONTEXT.md references agent hooks"
else
  fail "R-009a" "AGENT_CONTEXT.md does not reference agent hooks"
fi

# R-009b: AGENT_CONTEXT.md Hooks section lists import-guard
if grep -q 'import-guard' "$AGENT_CONTEXT" 2>/dev/null; then
  pass "R-009b" "AGENT_CONTEXT.md lists import-guard hook"
else
  fail "R-009b" "AGENT_CONTEXT.md does not list import-guard hook"
fi

# R-009c: CONTRIBUTING.md test count is updated (checks for test count > 57)
if [ -f "$CONTRIBUTING_MD" ]; then
  test_count=$(grep -oE '[0-9]+ test files' "$CONTRIBUTING_MD" 2>/dev/null | grep -oE '[0-9]+' | head -1)
  if [ -n "$test_count" ] && [ "$test_count" -ge 58 ]; then
    pass "R-009c" "CONTRIBUTING.md test count updated (${test_count})"
  else
    fail "R-009c" "CONTRIBUTING.md test count not updated (current: ${test_count:-unknown}, need >= 58)"
  fi
else
  fail "R-009c" "CONTRIBUTING.md not found"
fi

# ============================================================================
# R-010 [unit]: Actionable deny reason with entrypoint name and test_via
# ============================================================================

section "R-010: Actionable deny reason with entrypoint name and test_via"

# R-010a: Prompt includes an example deny reason with entrypoint name
if echo "$prompt" | grep -qi 'entrypoint.*name\|specific.*entrypoint'; then
  pass "R-010a" "Prompt includes entrypoint name in deny reason"
else
  fail "R-010a" "Prompt does not include entrypoint name in deny reason"
fi

# R-010b: Prompt includes test_via pattern in deny reason
if echo "$prompt" | grep -qi 'test_via'; then
  pass "R-010b" "Prompt includes test_via in deny reason"
else
  fail "R-010b" "Prompt does not include test_via in deny reason"
fi

# R-010c: Prompt includes escape hatch instruction (add to test_helpers)
if echo "$prompt" | grep -qi 'test_helpers.*workflow-config\|workflow-config.*test_helpers\|add.*test_helpers'; then
  pass "R-010c" "Prompt includes test_helpers escape hatch instruction"
else
  fail "R-010c" "Prompt does not include test_helpers escape hatch instruction"
fi

# R-010d: Prompt mentions the specific internal package that was detected
if echo "$prompt" | grep -qi 'internal package\|which.*package\|specific.*package'; then
  pass "R-010d" "Prompt mentions specific internal package in deny"
else
  fail "R-010d" "Prompt does not mention specific internal package in deny"
fi

# ============================================================================
# R-011 [unit]: test_helpers allow-list in workflow-config.json
# ============================================================================

section "R-011: test_helpers allow-list"

# R-011a: Prompt references workflow.test_helpers from workflow-config.json
if echo "$prompt" | grep -qi 'workflow.test_helpers\|test_helpers.*workflow-config\|workflow-config.*test_helpers'; then
  pass "R-011a" "Prompt references workflow.test_helpers from workflow-config.json"
else
  fail "R-011a" "Prompt does not reference workflow.test_helpers"
fi

# R-011b: Prompt mentions glob patterns for test_helpers
if echo "$prompt" | grep -qi 'glob.*pattern\|testutil\|fixtures'; then
  pass "R-011b" "Prompt mentions glob patterns or common test helper paths"
else
  fail "R-011b" "Prompt does not mention glob patterns for test helpers"
fi

# R-011c: Prompt mentions test_helpers is optional (empty if absent)
if echo "$prompt" | grep -qi 'absent.*empty\|missing.*empty\|optional\|not.*present.*empty\|field is absent.*treat as empty'; then
  pass "R-011c" "Prompt mentions test_helpers field is optional"
else
  fail "R-011c" "Prompt does not mention test_helpers is optional"
fi

# ============================================================================
# R-012 [unit]: Retry-loop breaker guidance
# ============================================================================

section "R-012: Retry-loop breaker guidance"

# R-012a: Prompt includes escalation guidance in deny reason
# (Review finding: agent hooks are stateless — cannot count retries.
#  Escalation guidance is unconditional in every deny reason.)
if echo "$prompt" | grep -qi 'ask the user\|escalat.*user\|user.*guidance'; then
  pass "R-012a" "Prompt includes user escalation guidance in deny reason"
else
  fail "R-012a" "Prompt does not include user escalation guidance"
fi

# R-012b: Escalation guidance is part of the deny reason template (not conditional)
if echo "$prompt" | grep -qi 'ask the user for guidance'; then
  pass "R-012b" "Prompt includes 'ask the user for guidance' in deny template"
else
  fail "R-012b" "Prompt does not include 'ask the user for guidance'"
fi

# ============================================================================
# Sync: Hook config propagates to distribution
# ============================================================================

section "Sync: Hook config in distribution"

# SYNC-001: Distribution copy exists
if [ -f "$HOOK_DIST" ]; then
  pass "SYNC-001" "Distribution copy exists at $HOOK_DIST"
else
  fail "SYNC-001" "Distribution copy missing at $HOOK_DIST"
fi

# SYNC-002: Distribution copy matches source
if [ -f "$HOOK_FILE" ] && [ -f "$HOOK_DIST" ]; then
  if diff -q "$HOOK_FILE" "$HOOK_DIST" >/dev/null 2>&1; then
    pass "SYNC-002" "Distribution copy matches source"
  else
    fail "SYNC-002" "Distribution copy does not match source"
  fi
else
  fail "SYNC-002" "Cannot compare — one or both files missing"
fi

# SYNC-003: sync.sh copies JSON hook files from hooks/ to correctless/hooks/
if grep -q 'import-guard\.json\|hooks/\*\.json' "$SYNC_FILE" 2>/dev/null; then
  pass "SYNC-003" "sync.sh copies JSON hook files"
else
  fail "SYNC-003" "sync.sh does not copy JSON hook files from hooks/"
fi

# SYNC-004: sync.sh --check detects stale JSON hooks in distribution
if grep -q 'import-guard\|\.json.*hooks' "$SYNC_FILE" 2>/dev/null; then
  pass "SYNC-004" "sync.sh handles JSON hooks in check mode"
else
  fail "SYNC-004" "sync.sh does not handle JSON hooks in check mode"
fi

# ============================================================================
# Registration: test-agent-hooks.sh is registered in CI and test runner
# ============================================================================

section "Registration: Test file registration"

CI_YML=".github/workflows/ci.yml"
WF_CONFIG=".correctless/config/workflow-config.json"

# REG-001: test-agent-hooks.sh appears in ci.yml
if grep -q 'test-agent-hooks' "$CI_YML" 2>/dev/null; then
  pass "REG-001" "test-agent-hooks.sh registered in ci.yml"
else
  fail "REG-001" "test-agent-hooks.sh NOT registered in ci.yml"
fi

# REG-002: test-agent-hooks.sh appears in workflow-config.json commands.test
if grep -q 'test-agent-hooks' "$WF_CONFIG" 2>/dev/null; then
  pass "REG-002" "test-agent-hooks.sh registered in workflow-config.json"
else
  fail "REG-002" "test-agent-hooks.sh NOT registered in workflow-config.json"
fi

# ============================================================================
# Summary
# ============================================================================

echo ""
echo "==========================================="
echo "Results: $PASS passed, $FAIL failed, $SKIPPED skipped"
if [ -n "$FAILED_IDS" ]; then
  echo "Failed: $FAILED_IDS"
fi
echo "==========================================="

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
exit 0
