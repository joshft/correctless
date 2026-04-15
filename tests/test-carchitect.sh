#!/usr/bin/env bash
# shellcheck disable=SC1090,SC1091,SC2016,SC2086
# Correctless — /carchitect Phase 0 Structural Tests
#
# Enforces the carchitect-phase0 spec rules (R-001..R-015).
# Tests are structural — they verify file existence, frontmatter contracts,
# YAML schema, script behavior, and registration. LLM-behavioral rules
# (R-002, R-003, R-006, R-008, R-013) are tested only on their mechanical
# envelope: required prompt elements, tool allowlists, agent file presence.
#
# Run from repo root: bash tests/test-carchitect.sh

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

SKILL_FILE="skills/carchitect/SKILL.md"
SKILL_DIST="correctless/skills/carchitect/SKILL.md"
AGENT_SRC="agents/architecture-reviewer.md"
AGENT_DIST="correctless/agents/architecture-reviewer.md"
EXTRACT_SCRIPT="scripts/extract-entrypoints.sh"
SYNC_SH="sync.sh"
ARCH_FILE=".correctless/ARCHITECTURE.md"
TEST_RUNNER="tests/test.sh"
DOCS_FILE="docs/skills/carchitect.md"
README_MD="README.md"
CONTRIBUTING_MD="CONTRIBUTING.md"
AGENT_CONTEXT=".correctless/AGENT_CONTEXT.md"

# ============================================================================
# Test fixture for R-005 (extract-entrypoints.sh)
# ============================================================================

FIXTURE_DIR="/tmp/correctless-carchitect-test-$$"
cleanup() { rm -rf "$FIXTURE_DIR"; }
trap cleanup EXIT

mkdir -p "$FIXTURE_DIR"

# Valid fixture: ARCHITECTURE.md with entrypoints YAML between marker comments
cat > "$FIXTURE_DIR/ARCHITECTURE-valid.md" << 'FIXTURE_EOF'
# Architecture

## Entrypoints

<!-- correctless:entrypoints:start -->
```yaml
- name: api-server
  type: http
  handler: cmd/server/main.go:main
  test_via: httptest.NewServer(handler)
  scope:
    - pkg/api/**
    - pkg/middleware/**
- name: worker
  type: queue
  handler: cmd/worker/main.go:main
  test_via: direct function call with mock queue
  scope:
    - pkg/worker/**
```
<!-- correctless:entrypoints:end -->

## Key Patterns

Some patterns here.
FIXTURE_EOF

# Missing markers fixture
cat > "$FIXTURE_DIR/ARCHITECTURE-no-markers.md" << 'FIXTURE_EOF'
# Architecture

## Entrypoints

No markers here, just plain text.
FIXTURE_EOF

# Invalid YAML fixture
cat > "$FIXTURE_DIR/ARCHITECTURE-invalid-yaml.md" << 'FIXTURE_EOF'
# Architecture

## Entrypoints

<!-- correctless:entrypoints:start -->
```yaml
- name: broken
  type: http
  handler: [invalid yaml
  this is not: valid: yaml: at: all
```
<!-- correctless:entrypoints:end -->
FIXTURE_EOF

# Empty YAML fixture (markers present but no content)
cat > "$FIXTURE_DIR/ARCHITECTURE-empty.md" << 'FIXTURE_EOF'
# Architecture

## Entrypoints

<!-- correctless:entrypoints:start -->
```yaml
```
<!-- correctless:entrypoints:end -->
FIXTURE_EOF

# ============================================================================
# R-001: Skill file exists with valid frontmatter
# ============================================================================

section "R-001: Skill file existence and frontmatter"

if [ -f "$SKILL_FILE" ]; then
  pass "R-001-a" "Skill file exists at $SKILL_FILE"
else
  fail "R-001-a" "Skill file missing at $SKILL_FILE"
fi

# Check frontmatter fields
if [ -f "$SKILL_FILE" ]; then
  # name field
  if head -20 "$SKILL_FILE" | grep -q '^name: carchitect$'; then
    pass "R-001-b" "Frontmatter has name: carchitect"
  else
    fail "R-001-b" "Frontmatter missing name: carchitect"
  fi

  # description field
  if head -20 "$SKILL_FILE" | grep -q '^description:'; then
    pass "R-001-c" "Frontmatter has description field"
  else
    fail "R-001-c" "Frontmatter missing description field"
  fi

  # allowed-tools field
  if head -20 "$SKILL_FILE" | grep -q '^allowed-tools:'; then
    pass "R-001-d" "Frontmatter has allowed-tools field"
  else
    fail "R-001-d" "Frontmatter missing allowed-tools field"
  fi

  # context: fork
  if head -20 "$SKILL_FILE" | grep -q '^context: fork$'; then
    pass "R-001-e" "Frontmatter has context: fork"
  else
    fail "R-001-e" "Frontmatter missing context: fork"
  fi

  # allowed-tools includes required tools
  _tools_line=$(head -20 "$SKILL_FILE" | grep '^allowed-tools:' || true)
  for tool in "Read" "Grep" "Glob" "Write(.correctless/ARCHITECTURE.md)" "Edit(.correctless/ARCHITECTURE.md)"; do
    if echo "$_tools_line" | grep -qF "$tool"; then
      pass "R-001-f-${tool%%(*}" "allowed-tools includes $tool"
    else
      fail "R-001-f-${tool%%(*}" "allowed-tools missing $tool"
    fi
  done

  # Bash(git*) in allowed-tools
  if echo "$_tools_line" | grep -qE 'Bash\(git'; then
    pass "R-001-g" "allowed-tools includes Bash(git*)"
  else
    fail "R-001-g" "allowed-tools missing Bash(git*)"
  fi

  # Write target is .correctless/ARCHITECTURE.md (not ARCHITECTURE.md bare)
  if echo "$_tools_line" | grep -qF 'Write(.correctless/ARCHITECTURE.md)'; then
    pass "R-001-h" "Write scoped to .correctless/ARCHITECTURE.md"
  else
    fail "R-001-h" "Write not scoped to .correctless/ARCHITECTURE.md"
  fi

  # Edit scoped to .correctless/ARCHITECTURE.md only (no unscoped Edit)
  if echo "$_tools_line" | grep -qF 'Edit(.correctless/ARCHITECTURE.md)'; then
    pass "R-001-i" "Edit scoped to .correctless/ARCHITECTURE.md"
  else
    fail "R-001-i" "Edit not scoped to .correctless/ARCHITECTURE.md"
  fi

  # Edit must NOT be unscoped (bare "Edit" without parens, not preceded by another tool name)
  # Strategy: remove all Edit(...) occurrences, then check if bare "Edit" remains
  _edit_unscoped=false
  _tools_without_scoped_edit=$(echo "$_tools_line" | sed 's/Edit([^)]*)//g')
  if echo "$_tools_without_scoped_edit" | grep -q 'Edit'; then
    _edit_unscoped=true
  fi
  if [ "$_edit_unscoped" = false ]; then
    pass "R-001-j" "No unscoped Edit in allowed-tools"
  else
    fail "R-001-j" "Unscoped Edit found in allowed-tools (should be Edit(.correctless/ARCHITECTURE.md) only)"
  fi
else
  for id in R-001-b R-001-c R-001-d R-001-e R-001-f-Read R-001-f-Grep R-001-f-Glob R-001-f-Write R-001-f-Edit R-001-g R-001-h R-001-i R-001-j; do
    skip "$id" "Skill file missing, cannot check frontmatter"
  done
fi

# R-001 prerequisite: ABS-023 in ARCHITECTURE.md
if [ -f "$ARCH_FILE" ]; then
  if grep -q 'ABS-023' "$ARCH_FILE"; then
    pass "R-001-k" "ARCHITECTURE.md has ABS-023 (entrypoints YAML contract)"
  else
    fail "R-001-k" "ARCHITECTURE.md missing ABS-023 (entrypoints YAML contract)"
  fi
else
  skip "R-001-k" "ARCHITECTURE.md not found"
fi

# R-001 prerequisite: ENV-008 in ARCHITECTURE.md
if [ -f "$ARCH_FILE" ]; then
  if grep -q 'ENV-008' "$ARCH_FILE"; then
    pass "R-001-l" "ARCHITECTURE.md has ENV-008 (python3/yq dependency)"
  else
    fail "R-001-l" "ARCHITECTURE.md missing ENV-008 (python3/yq dependency)"
  fi
else
  skip "R-001-l" "ARCHITECTURE.md not found"
fi

# ============================================================================
# R-002: Reverse-engineer mode (mechanical envelope only)
# ============================================================================

section "R-002: Reverse-engineer mode prompt elements"

if [ -f "$SKILL_FILE" ]; then
  # Must mention reverse-engineer mode
  if grep -qi 'reverse.engineer' "$SKILL_FILE"; then
    pass "R-002-a" "Skill mentions reverse-engineer mode"
  else
    fail "R-002-a" "Skill does not mention reverse-engineer mode"
  fi

  # Must mention coverage report
  if grep -qi 'coverage report' "$SKILL_FILE"; then
    pass "R-002-b" "Skill mentions coverage report"
  else
    fail "R-002-b" "Skill does not mention coverage report"
  fi

  # Must mention user confirmation before writing patterns
  if grep -qi 'confirm' "$SKILL_FILE"; then
    pass "R-002-c" "Skill mentions confirmation requirement"
  else
    fail "R-002-c" "Skill does not mention confirmation requirement"
  fi

  # Must mention inconsistencies presentation
  if grep -qi 'inconsistent' "$SKILL_FILE"; then
    pass "R-002-d" "Skill mentions inconsistency handling"
  else
    fail "R-002-d" "Skill does not mention inconsistency handling"
  fi
else
  for id in R-002-a R-002-b R-002-c R-002-d; do
    skip "$id" "Skill file missing"
  done
fi

# ============================================================================
# R-003: Greenfield mode (mechanical envelope only)
# ============================================================================

section "R-003: Greenfield mode prompt elements"

if [ -f "$SKILL_FILE" ]; then
  # Must mention greenfield mode
  if grep -qi 'greenfield' "$SKILL_FILE"; then
    pass "R-003-a" "Skill mentions greenfield mode"
  else
    fail "R-003-a" "Skill does not mention greenfield mode"
  fi

  # Must mention discovery questions
  if grep -qi 'discovery question' "$SKILL_FILE"; then
    pass "R-003-b" "Skill mentions discovery questions"
  else
    fail "R-003-b" "Skill does not mention discovery questions"
  fi

  # Must mention tiered format (Tier 1/2/3)
  if grep -qi 'tier 1' "$SKILL_FILE" && grep -qi 'tier 2' "$SKILL_FILE" && grep -qi 'tier 3' "$SKILL_FILE"; then
    pass "R-003-c" "Skill mentions all three decision tiers"
  else
    fail "R-003-c" "Skill does not mention all three decision tiers"
  fi

  # Must prohibit scaffolding/code generation
  if grep -qi 'no.*scaffolding\|no.*code.*generation\|document only\|not.*code\|not.*scaffolding' "$SKILL_FILE"; then
    pass "R-003-d" "Skill prohibits scaffolding/code generation"
  else
    fail "R-003-d" "Skill does not prohibit scaffolding/code generation"
  fi
else
  for id in R-003-a R-003-b R-003-c R-003-d; do
    skip "$id" "Skill file missing"
  done
fi

# ============================================================================
# R-004: Entrypoints YAML schema (in skill prompt)
# ============================================================================

section "R-004: Entrypoints YAML schema in skill prompt"

if [ -f "$SKILL_FILE" ]; then
  # Must specify marker comments
  if grep -qF 'correctless:entrypoints:start' "$SKILL_FILE" && grep -qF 'correctless:entrypoints:end' "$SKILL_FILE"; then
    pass "R-004-a" "Skill references entrypoints marker comments"
  else
    fail "R-004-a" "Skill missing entrypoints marker comments"
  fi

  # Must specify all required fields
  for field in name type handler test_via scope; do
    if grep -q "$field" "$SKILL_FILE"; then
      pass "R-004-b-$field" "Skill references field: $field"
    else
      fail "R-004-b-$field" "Skill missing field: $field"
    fi
  done

  # Must specify type enum values
  for enum_val in http cli grpc queue cron library websocket; do
    if grep -q "$enum_val" "$SKILL_FILE"; then
      pass "R-004-c-$enum_val" "Skill references type enum: $enum_val"
    else
      fail "R-004-c-$enum_val" "Skill missing type enum: $enum_val"
    fi
  done

  # Must mention validation at write time
  if grep -qi 'validate.*write\|write.*time.*validate\|before.*writing\|before.*commit' "$SKILL_FILE"; then
    pass "R-004-d" "Skill mentions write-time validation"
  else
    fail "R-004-d" "Skill does not mention write-time validation"
  fi

  # Must mention rejecting invalid entries
  if grep -qi 'reject\|invalid.*error\|error.*invalid' "$SKILL_FILE"; then
    pass "R-004-e" "Skill mentions rejection of invalid entries"
  else
    fail "R-004-e" "Skill does not mention rejection of invalid entries"
  fi
else
  for id in R-004-a R-004-b-name R-004-b-type R-004-b-handler R-004-b-test_via R-004-b-scope R-004-c-http R-004-c-cli R-004-c-grpc R-004-c-queue R-004-c-cron R-004-c-library R-004-c-websocket R-004-d R-004-e; do
    skip "$id" "Skill file missing"
  done
fi

# R-004 prerequisite: TB-005 in ARCHITECTURE.md
if [ -f "$ARCH_FILE" ]; then
  if grep -q 'TB-005' "$ARCH_FILE"; then
    pass "R-004-f" "ARCHITECTURE.md has TB-005 (intra-skill trust boundary)"
  else
    fail "R-004-f" "ARCHITECTURE.md missing TB-005 (intra-skill trust boundary)"
  fi
else
  skip "R-004-f" "ARCHITECTURE.md not found"
fi

# ============================================================================
# R-005: extract-entrypoints.sh
# ============================================================================

section "R-005: extract-entrypoints.sh existence and behavior"

if [ -f "$EXTRACT_SCRIPT" ]; then
  pass "R-005-a" "Extract script exists at $EXTRACT_SCRIPT"
else
  fail "R-005-a" "Extract script missing at $EXTRACT_SCRIPT"
fi

if [ -f "$EXTRACT_SCRIPT" ]; then
  # Script must be executable or runnable via bash
  if [ -x "$EXTRACT_SCRIPT" ] || head -1 "$EXTRACT_SCRIPT" | grep -q 'bash'; then
    pass "R-005-b" "Extract script is runnable"
  else
    fail "R-005-b" "Extract script is not runnable"
  fi

  # Test against valid fixture: should exit 0 and produce valid YAML on stdout
  _extract_out=""
  _extract_exit=0
  _extract_out=$(bash "$EXTRACT_SCRIPT" "$FIXTURE_DIR/ARCHITECTURE-valid.md" 2>/dev/null) || _extract_exit=$?
  if [ "$_extract_exit" -eq 0 ]; then
    pass "R-005-c" "Extract script exits 0 on valid fixture"
  else
    fail "R-005-c" "Extract script exits $_extract_exit on valid fixture (expected 0)"
  fi

  # Output should contain the entrypoint names
  if echo "$_extract_out" | grep -q 'api-server'; then
    pass "R-005-d" "Extract output contains entrypoint name 'api-server'"
  else
    fail "R-005-d" "Extract output missing entrypoint name 'api-server'"
  fi

  if echo "$_extract_out" | grep -q 'worker'; then
    pass "R-005-e" "Extract output contains entrypoint name 'worker'"
  else
    fail "R-005-e" "Extract output missing entrypoint name 'worker'"
  fi

  # Test against missing markers fixture: should exit 1
  _extract_exit_nomarkers=0
  bash "$EXTRACT_SCRIPT" "$FIXTURE_DIR/ARCHITECTURE-no-markers.md" >/dev/null 2>&1 || _extract_exit_nomarkers=$?
  if [ "$_extract_exit_nomarkers" -ne 0 ]; then
    pass "R-005-f" "Extract script exits non-zero when markers missing"
  else
    fail "R-005-f" "Extract script exits 0 when markers missing (should fail)"
  fi

  # Test against invalid YAML fixture: should exit 1
  _extract_exit_invalid=0
  bash "$EXTRACT_SCRIPT" "$FIXTURE_DIR/ARCHITECTURE-invalid-yaml.md" >/dev/null 2>&1 || _extract_exit_invalid=$?
  if [ "$_extract_exit_invalid" -ne 0 ]; then
    pass "R-005-g" "Extract script exits non-zero on invalid YAML"
  else
    fail "R-005-g" "Extract script exits 0 on invalid YAML (should fail)"
  fi

  # Script should mention the fallback chain: yq, python3
  _script_body=$(cat "$EXTRACT_SCRIPT")
  if echo "$_script_body" | grep -q 'yq'; then
    pass "R-005-h" "Extract script references yq"
  else
    fail "R-005-h" "Extract script does not reference yq"
  fi

  if echo "$_script_body" | grep -q 'python3'; then
    pass "R-005-i" "Extract script references python3"
  else
    fail "R-005-i" "Extract script does not reference python3"
  fi

  # Script does NOT validate enum membership (that's R-004's job at write time)
  # Check for actual validation code (case/if statements checking type values),
  # not comments explaining the design decision
  if echo "$_script_body" | grep -v '^\s*#' | grep -qi 'enum.*member\|type.*valid\|valid.*type'; then
    fail "R-005-j" "Extract script validates enum membership (should not — R-004 does this)"
  else
    pass "R-005-j" "Extract script does not validate enum membership (correct)"
  fi
else
  for id in R-005-b R-005-c R-005-d R-005-e R-005-f R-005-g R-005-h R-005-i R-005-j; do
    skip "$id" "Extract script missing"
  done
fi

# ============================================================================
# R-006: Architecture reviewer agent (mechanical envelope)
# ============================================================================

section "R-006: Architecture reviewer agent"

if [ -f "$AGENT_SRC" ]; then
  pass "R-006-a" "Agent source file exists at $AGENT_SRC"
else
  fail "R-006-a" "Agent source file missing at $AGENT_SRC"
fi

if [ -f "$AGENT_SRC" ]; then
  # Check frontmatter: name
  if head -10 "$AGENT_SRC" | grep -q '^name: architecture-reviewer$'; then
    pass "R-006-b" "Agent frontmatter has name: architecture-reviewer"
  else
    fail "R-006-b" "Agent frontmatter missing name: architecture-reviewer"
  fi

  # Check frontmatter: tools must be Read, Grep, Glob (read-only)
  _agent_tools=$(head -10 "$AGENT_SRC" | grep '^tools:' || true)
  if [ -n "$_agent_tools" ]; then
    pass "R-006-c" "Agent frontmatter has tools field"

    # Must include Read, Grep, Glob
    for tool in Read Grep Glob; do
      if echo "$_agent_tools" | grep -qF "$tool"; then
        pass "R-006-d-$tool" "Agent tools include $tool"
      else
        fail "R-006-d-$tool" "Agent tools missing $tool"
      fi
    done

    # Must NOT include Write or Edit (read-only agent)
    for tool in Write Edit; do
      if echo "$_agent_tools" | grep -qF "$tool"; then
        fail "R-006-e-$tool" "Agent tools include $tool (should be read-only)"
      else
        pass "R-006-e-$tool" "Agent tools correctly exclude $tool"
      fi
    done

    # Must NOT include Bash (read-only agent)
    if echo "$_agent_tools" | grep -qF 'Bash'; then
      fail "R-006-e-Bash" "Agent tools include Bash (should be read-only)"
    else
      pass "R-006-e-Bash" "Agent tools correctly exclude Bash"
    fi
  else
    for id in R-006-c R-006-d-Read R-006-d-Grep R-006-d-Glob R-006-e-Write R-006-e-Edit R-006-e-Bash; do
      fail "$id" "Agent frontmatter missing tools field"
    done
  fi

  # Agent must be synced to distribution
  if [ -f "$AGENT_DIST" ]; then
    if diff -q "$AGENT_SRC" "$AGENT_DIST" >/dev/null 2>&1; then
      pass "R-006-f" "Agent synced to distribution"
    else
      fail "R-006-f" "Agent not synced to distribution (source != dist)"
    fi
  else
    fail "R-006-f" "Agent not in distribution directory"
  fi
else
  for id in R-006-b R-006-c R-006-d-Read R-006-d-Grep R-006-d-Glob R-006-e-Write R-006-e-Edit R-006-e-Bash R-006-f; do
    skip "$id" "Agent source file missing"
  done
fi

# Skill file must reference the agent via Task invocation
if [ -f "$SKILL_FILE" ]; then
  if grep -qF 'correctless:architecture-reviewer' "$SKILL_FILE"; then
    pass "R-006-g" "Skill references architecture-reviewer via Task invocation"
  else
    fail "R-006-g" "Skill does not reference correctless:architecture-reviewer Task"
  fi
else
  skip "R-006-g" "Skill file missing"
fi

# ============================================================================
# R-007: Output ARCHITECTURE.md section order
# ============================================================================

section "R-007: Required sections in skill prompt"

if [ -f "$SKILL_FILE" ]; then
  # Must mention all required sections
  for section_name in "System Purpose" "Entrypoints" "Key Patterns" "Layer Conventions" "Anti-Patterns" "Decision Log" "Known Limitations"; do
    if grep -qi "$section_name" "$SKILL_FILE"; then
      pass "R-007-$section_name" "Skill mentions section: $section_name"
    else
      fail "R-007-$section_name" "Skill missing section: $section_name"
    fi
  done

  # Must mention TODO verify markers for uncertain content
  if grep -qF 'TODO: verify' "$SKILL_FILE" || grep -qF 'TODO:verify' "$SKILL_FILE"; then
    pass "R-007-TODO" "Skill mentions TODO: verify markers"
  else
    fail "R-007-TODO" "Skill does not mention TODO: verify markers"
  fi
else
  for section_name in "System Purpose" "Entrypoints" "Key Patterns" "Layer Conventions" "Anti-Patterns" "Decision Log" "Known Limitations" "TODO"; do
    skip "R-007-$section_name" "Skill file missing"
  done
fi

# ============================================================================
# R-008: Decision format (mechanical envelope)
# ============================================================================

section "R-008: Greenfield decision format"

if [ -f "$SKILL_FILE" ]; then
  # Tier 1: full tradeoffs
  if grep -qi 'tier 1.*tradeoff\|tier 1.*advantage\|full tradeoff' "$SKILL_FILE"; then
    pass "R-008-a" "Skill mentions Tier 1 full tradeoffs"
  else
    fail "R-008-a" "Skill does not mention Tier 1 full tradeoffs"
  fi

  # Must mention "Best when" qualifier
  if grep -qi 'best when' "$SKILL_FILE"; then
    pass "R-008-b" "Skill mentions 'Best when' qualifier"
  else
    fail "R-008-b" "Skill does not mention 'Best when' qualifier"
  fi

  # Must mention escape hatch
  if grep -qi 'describe your own\|escape hatch\|your own approach' "$SKILL_FILE"; then
    pass "R-008-c" "Skill mentions escape hatch for decisions"
  else
    fail "R-008-c" "Skill does not mention escape hatch for decisions"
  fi
else
  for id in R-008-a R-008-b R-008-c; do
    skip "$id" "Skill file missing"
  done
fi

# ============================================================================
# R-009: Mode selection prompt
# ============================================================================

section "R-009: Mode selection"

if [ -f "$SKILL_FILE" ]; then
  # Must mention mode selection prompt
  if grep -qi 'reverse.engineer\|greenfield\|which mode' "$SKILL_FILE"; then
    pass "R-009-a" "Skill mentions mode selection"
  else
    fail "R-009-a" "Skill does not mention mode selection"
  fi

  # Must mention --greenfield and --reverse-engineer flags
  if grep -qF -- '--greenfield' "$SKILL_FILE"; then
    pass "R-009-b" "Skill mentions --greenfield flag"
  else
    fail "R-009-b" "Skill does not mention --greenfield flag"
  fi

  if grep -qF -- '--reverse-engineer' "$SKILL_FILE"; then
    pass "R-009-c" "Skill mentions --reverse-engineer flag"
  else
    fail "R-009-c" "Skill does not mention --reverse-engineer flag"
  fi

  # Must mention 20 lines threshold for existing content detection
  if grep -q '20' "$SKILL_FILE"; then
    pass "R-009-d" "Skill mentions 20-line threshold"
  else
    fail "R-009-d" "Skill does not mention 20-line threshold"
  fi

  # Must mention PLACEHOLDER detection
  if grep -qF 'PLACEHOLDER' "$SKILL_FILE" || grep -qF '{PLACEHOLDER}' "$SKILL_FILE"; then
    pass "R-009-e" "Skill mentions PLACEHOLDER detection"
  else
    fail "R-009-e" "Skill does not mention PLACEHOLDER detection"
  fi
else
  for id in R-009-a R-009-b R-009-c R-009-d R-009-e; do
    skip "$id" "Skill file missing"
  done
fi

# ============================================================================
# R-010: Coverage report (mechanical envelope)
# ============================================================================

section "R-010: Coverage report elements"

if [ -f "$SKILL_FILE" ]; then
  # Must mention directories scanned
  if grep -qi 'director.*scan\|scan.*director' "$SKILL_FILE"; then
    pass "R-010-a" "Skill mentions directory scanning"
  else
    fail "R-010-a" "Skill does not mention directory scanning"
  fi

  # Must mention .gitignore
  if grep -qF '.gitignore' "$SKILL_FILE"; then
    pass "R-010-b" "Skill mentions .gitignore"
  else
    fail "R-010-b" "Skill does not mention .gitignore"
  fi

  # Must mention vendor/dependency exclusion directories
  if grep -qF 'node_modules' "$SKILL_FILE"; then
    pass "R-010-c" "Skill mentions node_modules exclusion"
  else
    fail "R-010-c" "Skill does not mention node_modules exclusion"
  fi
else
  for id in R-010-a R-010-b R-010-c; do
    skip "$id" "Skill file missing"
  done
fi

# ============================================================================
# R-011: Registration in sync.sh, docs, and skill counts
# ============================================================================

section "R-011: Registration"

# Check sync.sh includes carchitect
if grep -q 'carchitect' "$SYNC_SH"; then
  pass "R-011-a" "sync.sh includes carchitect"
else
  fail "R-011-a" "sync.sh does not include carchitect"
fi

# Check docs file exists
if [ -f "$DOCS_FILE" ]; then
  pass "R-011-b" "Docs file exists at $DOCS_FILE"
else
  fail "R-011-b" "Docs file missing at $DOCS_FILE"
fi

# Check README skill count updated (should be 28 not 27)
if grep -qE 'skills-28|28 skills' "$README_MD"; then
  pass "R-011-c" "README.md skill count updated to 28"
else
  fail "R-011-c" "README.md skill count not updated to 28"
fi

# Check CONTRIBUTING skill count updated
if grep -qE '\b28\b.*skill|skills.*\b28\b' "$CONTRIBUTING_MD"; then
  pass "R-011-d" "CONTRIBUTING.md skill count updated to 28"
else
  fail "R-011-d" "CONTRIBUTING.md skill count not updated to 28"
fi

# Check sync.sh comment updated
if grep -qE 'All 28 skills|28 skills' "$SYNC_SH"; then
  pass "R-011-e" "sync.sh comment updated to 28 skills"
else
  fail "R-011-e" "sync.sh comment not updated to 28 skills"
fi

# Check AGENT_CONTEXT skill count updated
if grep -qE '\b28\b.*skill|skills.*\b28\b|28 skill' "$AGENT_CONTEXT"; then
  pass "R-011-f" "AGENT_CONTEXT.md skill count updated to 28"
else
  fail "R-011-f" "AGENT_CONTEXT.md skill count not updated to 28"
fi

# Check distribution directory exists
if [ -d "correctless/skills/carchitect" ]; then
  pass "R-011-g" "Distribution directory exists"
else
  fail "R-011-g" "Distribution directory missing"
fi

# Check distribution skill file matches source
if [ -f "$SKILL_FILE" ] && [ -f "$SKILL_DIST" ]; then
  if diff -q "$SKILL_FILE" "$SKILL_DIST" >/dev/null 2>&1; then
    pass "R-011-h" "Distribution skill matches source"
  else
    fail "R-011-h" "Distribution skill does not match source"
  fi
else
  skip "R-011-h" "Skill file or distribution missing"
fi

# ============================================================================
# R-012: No modification of other skills
# ============================================================================

section "R-012: Standalone constraint"

if [ -f "$SKILL_FILE" ]; then
  # Skill file should NOT reference modifying other skills
  # This is a prompt-level constraint — verify the skill mentions it
  if grep -qi 'does not modify\|standalone\|no.*modif.*other.*skill\|phase 0.*standalone' "$SKILL_FILE"; then
    pass "R-012-a" "Skill mentions standalone constraint"
  else
    fail "R-012-a" "Skill does not mention standalone constraint"
  fi

  # Write target must be only .correctless/ARCHITECTURE.md
  _tools_line=$(head -20 "$SKILL_FILE" | grep '^allowed-tools:' || true)
  # Count Write(...) entries — should only be Write(.correctless/ARCHITECTURE.md)
  _write_count=$(echo "$_tools_line" | grep -oF 'Write(' | wc -l)
  if [ "$_write_count" -le 1 ]; then
    pass "R-012-b" "Only one Write scope in allowed-tools"
  else
    fail "R-012-b" "Multiple Write scopes in allowed-tools (should only write ARCHITECTURE.md)"
  fi
else
  for id in R-012-a R-012-b; do
    skip "$id" "Skill file missing"
  done
fi

# ============================================================================
# R-013: Pattern batching (mechanical envelope)
# ============================================================================

section "R-013: Pattern batching elements"

if [ -f "$SKILL_FILE" ]; then
  # Must mention 75% threshold
  if grep -q '75%\|75 percent' "$SKILL_FILE"; then
    pass "R-013-a" "Skill mentions 75% confidence threshold"
  else
    fail "R-013-a" "Skill does not mention 75% confidence threshold"
  fi

  # Must mention 10 pattern cap
  if grep -qi 'at most 10\|cap.*10\|10.*pattern.*cap\|10.*per session' "$SKILL_FILE"; then
    pass "R-013-b" "Skill mentions 10-pattern cap"
  else
    fail "R-013-b" "Skill does not mention 10-pattern cap"
  fi

  # Must mention --continue flag
  if grep -qF -- '--continue' "$SKILL_FILE"; then
    pass "R-013-c" "Skill mentions --continue flag"
  else
    fail "R-013-c" "Skill does not mention --continue flag"
  fi

  # Must mention session-scoped only (not cross-session)
  if grep -qi 'session.*only\|within.*session\|ephemeral\|not.*persist\|not.*cross.session' "$SKILL_FILE"; then
    pass "R-013-d" "Skill mentions session-scoped continuation"
  else
    fail "R-013-d" "Skill does not mention session-scoped continuation"
  fi
else
  for id in R-013-a R-013-b R-013-c R-013-d; do
    skip "$id" "Skill file missing"
  done
fi

# ============================================================================
# R-014: test_via field (mechanical envelope)
# ============================================================================

section "R-014: test_via field"

if [ -f "$SKILL_FILE" ]; then
  # Must mention test_via
  if grep -q 'test_via' "$SKILL_FILE"; then
    pass "R-014-a" "Skill mentions test_via field"
  else
    fail "R-014-a" "Skill does not mention test_via field"
  fi

  # Must mention non-empty constraint
  if grep -qi 'non.empty\|must not be empty\|required.*test_via\|test_via.*required' "$SKILL_FILE"; then
    pass "R-014-b" "Skill mentions test_via non-empty constraint"
  else
    fail "R-014-b" "Skill does not mention test_via non-empty constraint"
  fi
else
  for id in R-014-a R-014-b; do
    skip "$id" "Skill file missing"
  done
fi

# ============================================================================
# R-015: Existing ARCHITECTURE.md detection
# ============================================================================

section "R-015: Existing doc detection"

if [ -f "$SKILL_FILE" ]; then
  # Must mention existing content detection
  if grep -qi 'existing.*content\|already.*exist\|content.*exist' "$SKILL_FILE"; then
    pass "R-015-a" "Skill mentions existing content detection"
  else
    fail "R-015-a" "Skill does not mention existing content detection"
  fi

  # Must mention delete + start fresh option
  if grep -qi 'delete.*fresh\|start fresh\|fresh.*reverse' "$SKILL_FILE"; then
    pass "R-015-b" "Skill mentions delete-and-start-fresh option"
  else
    fail "R-015-b" "Skill does not mention delete-and-start-fresh option"
  fi

  # Must mention cupdate-arch redirect
  if grep -qF '/cupdate-arch' "$SKILL_FILE"; then
    pass "R-015-c" "Skill mentions /cupdate-arch redirect"
  else
    fail "R-015-c" "Skill does not mention /cupdate-arch redirect"
  fi

  # Must mention exit/manual option
  if grep -qi 'exit.*manual\|manual\|handle.*manual' "$SKILL_FILE"; then
    pass "R-015-d" "Skill mentions exit/manual option"
  else
    fail "R-015-d" "Skill does not mention exit/manual option"
  fi

  # Must NOT silently overwrite
  if grep -qi 'not.*silently.*overwrite\|not.*overwrite\|does not.*overwrite\|never.*overwrite' "$SKILL_FILE"; then
    pass "R-015-e" "Skill prohibits silent overwrite"
  else
    fail "R-015-e" "Skill does not prohibit silent overwrite"
  fi
else
  for id in R-015-a R-015-b R-015-c R-015-d R-015-e; do
    skip "$id" "Skill file missing"
  done
fi

# ============================================================================
# Wiring: test runner includes this test
# ============================================================================

section "Wiring: test runner"

if grep -qF 'test-carchitect.sh' "$TEST_RUNNER"; then
  pass "WIRE-a" "test.sh includes test-carchitect.sh"
else
  fail "WIRE-a" "test.sh does not include test-carchitect.sh"
fi

# ============================================================================
# Summary
# ============================================================================

echo ""
echo "============================================="
echo "Results: $PASS passed, $FAIL failed, $SKIPPED skipped"
if [ -n "$FAILED_IDS" ]; then
  echo "Failed: $FAILED_IDS"
fi
echo "============================================="
echo ""

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
