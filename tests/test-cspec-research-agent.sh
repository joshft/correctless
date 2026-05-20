#!/usr/bin/env bash
# shellcheck disable=SC1090,SC1091,SC2016,SC2086
# Correctless — cspec-research Plugin Agent Migration Tests
#
# Enforces the cspec-agent-migration spec's invariants, prohibitions,
# and boundary condition (INV-001..INV-016, PRH-001..PRH-002, BND-001).
#
# Run from repo root: bash tests/test-cspec-research-agent.sh
#
# This is the RED-phase structural test. It asserts:
#   - agents/cspec-research.md exists with correct frontmatter (INV-001)
#   - Network-capable write-free tool allowlist: WebSearch, WebFetch, Read, Grep (INV-002, PRH-002)
#   - skills/cspec/SKILL.md dispatches via namespaced subagent_type (INV-003)
#   - No inline research agent prompt remains in SKILL.md (INV-004, PRH-001)
#   - Orchestrator-injected dynamic context placeholders (INV-005)
#   - Research-specific content preserved (INV-006)
#   - Skepticism behavioral override (INV-007)
#   - Output format contract with 7 sections (INV-008)
#   - Distribution parity after sync.sh (INV-009)
#   - ABS-010 registry updated with network-read class (INV-010)
#   - Task in SKILL.md allowed-tools (INV-011)
#   - Conditional spawn logic stays in SKILL.md (INV-012, BND-001)
#   - AGENT_CONTEXT.md agents table updated (INV-013)
#   - Harness-prior suppression (INV-014)
#   - Data-treatment directive for untrusted web content (INV-015)
#   - Network unavailability self-diagnostic (INV-016)
#   - No write tools in research agent (PRH-002)
#   - Agent vs orchestrator separation (BND-001)
#
# POSIX-portable externals only: grep, sed, awk, sha256sum, diff.
# Bash 4+ constructs are permitted.

source "$(dirname "${BASH_SOURCE[0]}")/test-helpers.sh"
set -f

# ============================================================================
# File paths
# ============================================================================

AGENT_SRC="agents/cspec-research.md"
AGENT_DIST="correctless/agents/cspec-research.md"
CSPEC_SKILL="skills/cspec/SKILL.md"
SYNC_SH="sync.sh"
ARCH_FILE=".correctless/ARCHITECTURE.md"
AGENT_CONTEXT=".correctless/AGENT_CONTEXT.md"
TEST_RUNNER="tests/test-core.sh"
WORKFLOW_CONFIG=".correctless/config/workflow-config.json"

# ============================================================================
# Precomputed / cached data (avoids redundant file reads across check fns)
# ============================================================================

AGENT_BODY=""
STEP2_BLOCK=""
ABS010_BLOCK=""

_cache_agent_body() {
  [ -f "$AGENT_SRC" ] && AGENT_BODY="$(skill_body "$AGENT_SRC")"
}

_cache_step2_block() {
  [ -f "$CSPEC_SKILL" ] && STEP2_BLOCK="$(_extract_step2_block "$CSPEC_SKILL")"
}

_cache_abs010_block() {
  [ -f "$ARCH_FILE" ] && ABS010_BLOCK="$(_extract_abs010_block "$ARCH_FILE")"
}

# ============================================================================
# Helpers
# ============================================================================

_extract_step2_block() {
  local file="$1"
  [ -f "$file" ] || return 1
  awk '
    BEGIN { in_block = 0 }
    /^### Step 2:/ { in_block = 1; next }
    /^### Step 3:/ { in_block = 0; next }
    in_block { print }
  ' "$file" 2>/dev/null
}

_extract_abs010_block() {
  local file="$1"
  [ -f "$file" ] || return 1
  awk '
    /^### ABS-010:/ { found = 1 }
    found { print }
    found && /^### ABS-0[1-9][1-9]:/ && !/^### ABS-010:/ { exit }
  ' "$file" 2>/dev/null
}

ORCHESTRATOR_DENYLIST=(
  "research signals"
  "Spawn the research subagent when"
  "Inferred signals"
)

# ============================================================================
# INV-001: Agent file exists with correct frontmatter
# ============================================================================

check_inv001() {
  section "INV-001: Agent file exists with correct frontmatter"

  if [ ! -f "$AGENT_SRC" ]; then
    fail "INV-001(a)" "$AGENT_SRC does not exist"
    return
  fi
  pass "INV-001(a)" "$AGENT_SRC exists"

  local fm
  fm="$(extract_frontmatter "$AGENT_SRC" 2>/dev/null)" || {
    fail "INV-001(b)" "$AGENT_SRC has no valid YAML frontmatter (missing --- delimiters)"
    return
  }
  if [ -z "$fm" ]; then
    fail "INV-001(b)" "$AGENT_SRC frontmatter is empty"
    return
  fi
  pass "INV-001(b)" "$AGENT_SRC has a frontmatter block"

  # name: must be "cspec-research"
  local name
  name="$(get_frontmatter_field "$AGENT_SRC" "name" 2>/dev/null)" || name=""
  if [ "$name" = "cspec-research" ]; then
    pass "INV-001(c)" "frontmatter name: is 'cspec-research'"
  else
    fail "INV-001(c)" "frontmatter name: is '$name', expected 'cspec-research'"
  fi

  # description: must exist and be non-empty
  local desc
  desc="$(get_frontmatter_field "$AGENT_SRC" "description" 2>/dev/null)" || desc=""
  if [ -n "$desc" ]; then
    pass "INV-001(d)" "frontmatter description: is non-empty"
  else
    fail "INV-001(d)" "frontmatter description: is missing or empty"
  fi

  # tools: must exist (exact set checked in INV-002)
  local tools
  tools="$(get_frontmatter_field "$AGENT_SRC" "tools" 2>/dev/null)" || tools=""
  if [ -n "$tools" ]; then
    pass "INV-001(e)" "frontmatter tools: is non-empty"
  else
    fail "INV-001(e)" "frontmatter tools: is missing or empty"
  fi
}

# ============================================================================
# INV-002: Network-capable write-free tool allowlist
# ============================================================================

check_inv002() {
  section "INV-002: Network-capable write-free tool allowlist"

  if [ ! -f "$AGENT_SRC" ]; then
    fail "INV-002(a)" "$AGENT_SRC does not exist — cannot check tools"
    return
  fi

  local tools
  tools="$(parse_tools_list "$AGENT_SRC" 2>/dev/null)" || {
    fail "INV-002(a)" "$AGENT_SRC has no tools: field in frontmatter"
    return
  }

  # Expected tools: WebSearch, WebFetch, Read, Grep (exactly)
  local expected="Grep Read WebFetch WebSearch"
  local actual
  actual="$(echo "$tools" | sort | tr '\n' ' ' | sed 's/ $//')"

  if [ "$actual" = "$expected" ]; then
    pass "INV-002(a)" "tools: list matches expected set {WebSearch, WebFetch, Read, Grep}"
  else
    fail "INV-002(a)" "tools: list is '$actual', expected '$expected'"
  fi

  # Tool count must be exactly 4
  local tool_count
  tool_count="$(echo "$tools" | wc -l | tr -d ' ')"
  if [ "$tool_count" -eq 4 ]; then
    pass "INV-002(b)" "tools: list has exactly 4 entries"
  else
    fail "INV-002(b)" "tools: list has $tool_count entries, expected 4"
  fi

  # Must NOT include write-capable tools (Write, Edit, Bash)
  for denied in Write Edit Bash; do
    if echo "$tools" | grep -q "^${denied}$"; then
      fail "INV-002(c:$denied)" "tools: list includes write-capable tool '$denied'"
    else
      pass "INV-002(c:$denied)" "tools: list does not include '$denied'"
    fi
  done

  # Must NOT include escalation tool (Task)
  if echo "$tools" | grep -q "^Task$"; then
    fail "INV-002(d)" "tools: list includes escalation tool 'Task'"
  else
    pass "INV-002(d)" "tools: list does not include 'Task'"
  fi
}

# ============================================================================
# INV-003: Namespaced subagent_type dispatch
# ============================================================================

check_inv003() {
  section "INV-003: SKILL.md uses namespaced subagent_type for research agent"

  if [ -z "$STEP2_BLOCK" ]; then
    fail "INV-003(a)" "$CSPEC_SKILL does not exist or Step 2 block is empty"
    return
  fi

  if echo "$STEP2_BLOCK" | grep -q 'subagent_type="correctless:cspec-research"'; then
    pass "INV-003(a)" "Step 2 contains subagent_type=\"correctless:cspec-research\""
  else
    fail "INV-003(a)" "Step 2 does not contain subagent_type=\"correctless:cspec-research\""
  fi

  if echo "$STEP2_BLOCK" | grep -q 'subagent_type="general-purpose"'; then
    fail "INV-003(b)" "Step 2 still references subagent_type=\"general-purpose\""
  else
    pass "INV-003(b)" "Step 2 does not reference subagent_type=\"general-purpose\""
  fi
}

# ============================================================================
# INV-004: No inline research agent prompt remains
# ============================================================================

check_inv004() {
  section "INV-004: No inline research agent prompt in SKILL.md"

  if [ -z "$STEP2_BLOCK" ]; then
    fail "INV-004(a)" "$CSPEC_SKILL does not exist or Step 2 block is empty"
    return
  fi

  local -a denylist=(
    "You are a research agent supporting the spec phase"
    "Produce a structured brief"
    "Search for:"
  )

  local found_any=false
  for pattern in "${denylist[@]}"; do
    if echo "$STEP2_BLOCK" | grep -qF "$pattern"; then
      fail "INV-004(a:$pattern)" "Step 2 still contains denylist signature: '$pattern'"
      found_any=true
    fi
  done

  if [ "$found_any" = "false" ]; then
    pass "INV-004(a)" "Step 2 has no denylist inline prompt signatures"
  fi

  if echo "$STEP2_BLOCK" | grep -qF "(forked context)"; then
    fail "INV-004(b)" "Step 2 still has stale '(forked context)' annotation"
  else
    pass "INV-004(b)" "Step 2 does not have stale '(forked context)' annotation"
  fi

  local consecutive_blockquotes
  consecutive_blockquotes="$(echo "$STEP2_BLOCK" | awk '
    /^>/ { count++; next }
    { if (count >= 4) found = 1; count = 0 }
    END { if (count >= 4) found = 1; print (found ? "yes" : "no") }
  ')"

  if [ "$consecutive_blockquotes" = "yes" ]; then
    fail "INV-004(c)" "Step 2 has 4+ consecutive blockquoted lines (likely inline prompt)"
  else
    pass "INV-004(c)" "Step 2 has no large blockquoted prompt blocks"
  fi
}

# ============================================================================
# INV-005: Orchestrator-injected dynamic context
# ============================================================================

check_inv005() {
  section "INV-005: Orchestrator-injected dynamic context placeholders"

  if [ -z "$AGENT_BODY" ]; then
    fail "INV-005(a)" "$AGENT_SRC does not exist or body is empty"
    return
  fi

  if echo "$AGENT_BODY" | grep -qF "{topic}"; then
    pass "INV-005(a)" "agent file contains {topic} placeholder"
  else
    fail "INV-005(a)" "agent file does not contain {topic} placeholder"
  fi

  if echo "$AGENT_BODY" | grep -qF "{feature_description}"; then
    pass "INV-005(b)" "agent file contains {feature_description} placeholder"
  else
    fail "INV-005(b)" "agent file does not contain {feature_description} placeholder"
  fi

  if echo "$AGENT_BODY" | grep -qF "AGENT_CONTEXT.md"; then
    pass "INV-005(c)" "agent file references AGENT_CONTEXT.md"
  else
    fail "INV-005(c)" "agent file does not reference AGENT_CONTEXT.md"
  fi
}

# ============================================================================
# INV-006: Research-specific content preserved
# ============================================================================

check_inv006() {
  section "INV-006: Research-specific content preserved"

  if [ -z "$AGENT_BODY" ]; then
    fail "INV-006(a)" "$AGENT_SRC does not exist or body is empty"
    return
  fi

  if echo "$AGENT_BODY" | grep -qF "Current official documentation"; then
    pass "INV-006(a)" "agent file contains 'Current official documentation'"
  else
    fail "INV-006(a)" "agent file does not contain 'Current official documentation'"
  fi

  if echo "$AGENT_BODY" | grep -qF "Dependency Health"; then
    pass "INV-006(b)" "agent file contains 'Dependency Health'"
  else
    fail "INV-006(b)" "agent file does not contain 'Dependency Health'"
  fi
}

# ============================================================================
# INV-007: Skepticism behavioral override
# ============================================================================

check_inv007() {
  section "INV-007: Skepticism behavioral override"

  if [ -z "$AGENT_BODY" ]; then
    fail "INV-007(a)" "$AGENT_SRC does not exist or body is empty"
    return
  fi

  if echo "$AGENT_BODY" | grep -qF "BE SKEPTICAL"; then
    pass "INV-007(a)" "agent file contains 'BE SKEPTICAL' directive"
  else
    fail "INV-007(a)" "agent file does not contain 'BE SKEPTICAL' directive"
  fi
}

# ============================================================================
# INV-008: Output format contract with 7 sections
# ============================================================================

check_inv008() {
  section "INV-008: Output format contract"

  if [ -z "$AGENT_BODY" ]; then
    fail "INV-008(a)" "$AGENT_SRC does not exist or body is empty"
    return
  fi
  local -a required_sections=(
    "Current State"
    "Key Findings"
    "Recommended Patterns"
    "Things to Avoid"
    "Version Pins"
    "Dependency Health"
    "Open Questions"
  )

  local all_found=true
  for section_header in "${required_sections[@]}"; do
    if echo "$AGENT_BODY" | grep -qF "$section_header"; then
      pass "INV-008($section_header)" "agent file contains section header '$section_header'"
    else
      fail "INV-008($section_header)" "agent file does not contain section header '$section_header'"
      all_found=false
    fi
  done

  if [ "$all_found" = "true" ]; then
    pass "INV-008(all)" "all 7 required output format sections present"
  fi
}

# ============================================================================
# INV-009: Distribution parity
# ============================================================================

check_inv009() {
  section "INV-009: Distribution parity (source = dist after sync)"

  if [ ! -f "$AGENT_SRC" ]; then
    fail "INV-009(a)" "$AGENT_SRC does not exist — cannot check parity"
    return
  fi

  if [ ! -f "$AGENT_DIST" ]; then
    fail "INV-009(a)" "$AGENT_DIST does not exist — distribution copy missing"
    return
  fi

  # Byte-equal check
  if diff -q "$AGENT_SRC" "$AGENT_DIST" >/dev/null 2>&1; then
    pass "INV-009(a)" "$AGENT_SRC and $AGENT_DIST are byte-equal"
  else
    fail "INV-009(a)" "$AGENT_SRC and $AGENT_DIST diverge"
  fi
}

# ============================================================================
# INV-010: ABS-010 registry updated with network-read class
# ============================================================================

check_inv010() {
  section "INV-010: ABS-010 registry updated with network-read class"

  if [ -z "$ABS010_BLOCK" ]; then
    fail "INV-010(a)" "$ARCH_FILE does not exist or ABS-010 block is empty"
    return
  fi

  if echo "$ABS010_BLOCK" | grep -q "cspec-research"; then
    pass "INV-010(a)" "ABS-010 entry mentions cspec-research"
  else
    fail "INV-010(a)" "ABS-010 entry does not mention cspec-research"
  fi

  if echo "$ABS010_BLOCK" | grep -q "skills/cspec/SKILL.md"; then
    pass "INV-010(b)" "ABS-010 entry references skills/cspec/SKILL.md as consumer"
  else
    fail "INV-010(b)" "ABS-010 entry does not reference skills/cspec/SKILL.md as consumer"
  fi

  if echo "$ABS010_BLOCK" | grep -qi "network-read\|network.*read\|WebSearch.*WebFetch"; then
    pass "INV-010(c)" "ABS-010 entry distinguishes network-read tool class"
  else
    fail "INV-010(c)" "ABS-010 entry does not distinguish network-read tool class"
  fi

  if echo "$ABS010_BLOCK" | grep -q "test-cspec-research-agent"; then
    pass "INV-010(d)" "ABS-010 Test line references test-cspec-research-agent"
  else
    fail "INV-010(d)" "ABS-010 Test line does not reference test-cspec-research-agent"
  fi
}

# ============================================================================
# INV-011: Task in SKILL.md allowed-tools
# ============================================================================

check_inv011() {
  section "INV-011: Task in SKILL.md allowed-tools"

  if [ ! -f "$CSPEC_SKILL" ]; then
    fail "INV-011(a)" "$CSPEC_SKILL does not exist"
    return
  fi

  local allowed
  allowed="$(get_frontmatter_field "$CSPEC_SKILL" "allowed-tools" 2>/dev/null)" || allowed=""

  if echo "$allowed" | grep -q "Task"; then
    pass "INV-011(a)" "/cspec allowed-tools includes Task"
  else
    fail "INV-011(a)" "/cspec allowed-tools does not include Task"
  fi
}

# ============================================================================
# INV-012: Conditional spawn logic stays in SKILL.md
# ============================================================================

check_inv012() {
  section "INV-012: Conditional spawn logic stays in SKILL.md"

  if [ -z "$STEP2_BLOCK" ]; then
    fail "INV-012(a)" "$CSPEC_SKILL does not exist or Step 2 block is empty"
    return
  fi

  if echo "$STEP2_BLOCK" | grep -qF "research signals" || echo "$STEP2_BLOCK" | grep -qF "Spawn the research subagent when"; then
    pass "INV-012(a)" "SKILL.md Step 2 retains orchestrator spawn logic"
  else
    fail "INV-012(a)" "SKILL.md Step 2 lost orchestrator spawn logic"
  fi

  if [ -z "$AGENT_BODY" ]; then
    fail "INV-012(b)" "$AGENT_SRC does not exist or body is empty"
    return
  fi

  local found_any=false
  for pattern in "${ORCHESTRATOR_DENYLIST[@]}"; do
    if echo "$AGENT_BODY" | grep -qF "$pattern"; then
      fail "INV-012(b:$pattern)" "agent file contains orchestrator logic: '$pattern'"
      found_any=true
    fi
  done

  if [ "$found_any" = "false" ]; then
    pass "INV-012(b)" "agent file does not contain orchestrator logic patterns"
  fi
}

# ============================================================================
# INV-013: AGENT_CONTEXT.md agents table updated
# ============================================================================

check_inv013() {
  section "INV-013: AGENT_CONTEXT.md agents table updated"

  if [ ! -f "$AGENT_CONTEXT" ]; then
    fail "INV-013(a)" "$AGENT_CONTEXT does not exist"
    return
  fi

  if grep -q "cspec-research" "$AGENT_CONTEXT"; then
    pass "INV-013(a)" "AGENT_CONTEXT.md mentions cspec-research"
  else
    fail "INV-013(a)" "AGENT_CONTEXT.md does not mention cspec-research"
  fi
}

# ============================================================================
# INV-014: Harness-prior suppression
# ============================================================================

check_inv014() {
  section "INV-014: Harness-prior suppression"

  if [ -z "$AGENT_BODY" ]; then
    fail "INV-014(a)" "$AGENT_SRC does not exist or body is empty"
    return
  fi

  if echo "$AGENT_BODY" | grep -qi "do not summarize\|exhaustive"; then
    pass "INV-014(a)" "agent file contains harness-prior suppression phrase"
  else
    fail "INV-014(a)" "agent file does not contain 'do not summarize' or 'exhaustive'"
  fi
}

# ============================================================================
# INV-015: Data-treatment directive for untrusted web content
# ============================================================================

check_inv015() {
  section "INV-015: Data-treatment directive for untrusted web content"

  if [ -z "$AGENT_BODY" ]; then
    fail "INV-015(a)" "$AGENT_SRC does not exist or body is empty"
    return
  fi

  if echo "$AGENT_BODY" | grep -qi "advisory"; then
    pass "INV-015(a)" "agent file contains 'advisory'"
  else
    fail "INV-015(a)" "agent file does not contain 'advisory'"
  fi

  if echo "$AGENT_BODY" | grep -qi "untrusted\|not instructions"; then
    pass "INV-015(b)" "agent file contains 'untrusted' or 'not instructions'"
  else
    fail "INV-015(b)" "agent file does not contain 'untrusted' or 'not instructions'"
  fi

  if [ -z "$STEP2_BLOCK" ]; then
    fail "INV-015(c)" "$CSPEC_SKILL does not exist or Step 2 block is empty"
    return
  fi

  if echo "$STEP2_BLOCK" | grep -qi "untrusted\|advisory"; then
    pass "INV-015(c)" "SKILL.md Step 2 contains 'untrusted' or 'advisory' near research brief"
  else
    fail "INV-015(c)" "SKILL.md Step 2 does not contain 'untrusted' or 'advisory'"
  fi
}

# ============================================================================
# INV-016: Network unavailability self-diagnostic
# ============================================================================

check_inv016() {
  section "INV-016: Network unavailability self-diagnostic"

  if [ -z "$AGENT_BODY" ]; then
    fail "INV-016(a)" "$AGENT_SRC does not exist or body is empty"
    return
  fi

  if echo "$AGENT_BODY" | grep -qF "DO NOT substitute training data"; then
    pass "INV-016(a)" "agent file contains 'DO NOT substitute training data' directive"
  else
    fail "INV-016(a)" "agent file does not contain 'DO NOT substitute training data'"
  fi
}

# ============================================================================
# INV-017: UNTRUSTED fence wrapping for research brief in orchestrator
# ============================================================================

check_inv017() {
  section "INV-017: UNTRUSTED fence wrapping for research brief"

  if [ -z "$STEP2_BLOCK" ]; then
    fail "INV-017(a)" "$CSPEC_SKILL does not exist or Step 2 block is empty"
    return
  fi

  if echo "$STEP2_BLOCK" | grep -q 'UNTRUSTED_RESEARCH_BRIEF'; then
    pass "INV-017(a)" "SKILL.md Step 2 contains UNTRUSTED_RESEARCH_BRIEF fence"
  else
    fail "INV-017(a)" "SKILL.md Step 2 does not wrap research brief in UNTRUSTED fence (structural enforcement for TB-007)"
  fi
}

# ============================================================================
# PRH-001: No inline research agent prompt for migrated agent
# ============================================================================

check_prh001() {
  section "PRH-001: No inline research agent prompt (prohibition)"

  if [ -z "$STEP2_BLOCK" ]; then
    fail "PRH-001(a)" "$CSPEC_SKILL does not exist or Step 2 block is empty"
    return
  fi

  if echo "$STEP2_BLOCK" | grep -q "^> You are a research agent supporting the spec phase"; then
    fail "PRH-001(a)" "Step 2 still has inline '> You are a research agent' prompt"
  else
    pass "PRH-001(a)" "Step 2 does not have inline agent identity prompt"
  fi

  if echo "$STEP2_BLOCK" | grep -q "^> .*BE SKEPTICAL"; then
    fail "PRH-001(b)" "Step 2 still has blockquoted 'BE SKEPTICAL' (should be in agent file)"
  else
    pass "PRH-001(b)" "Step 2 does not have blockquoted 'BE SKEPTICAL'"
  fi
}

# ============================================================================
# PRH-002: No write tools in research agent
# ============================================================================

check_prh002() {
  section "PRH-002: No write tools in research agent (prohibition)"

  if [ ! -f "$AGENT_SRC" ]; then
    fail "PRH-002(a)" "$AGENT_SRC does not exist — cannot check write tools"
    return
  fi

  local tools
  tools="$(parse_tools_list "$AGENT_SRC" 2>/dev/null)" || {
    fail "PRH-002(a)" "$AGENT_SRC has no tools: field"
    return
  }

  # Explicitly check each prohibited tool
  for denied in Write Edit Bash Task; do
    if echo "$tools" | grep -q "^${denied}$"; then
      fail "PRH-002($denied)" "research agent has prohibited tool '$denied'"
    else
      pass "PRH-002($denied)" "research agent does not have '$denied'"
    fi
  done
}

# ============================================================================
# BND-001: Agent vs orchestrator separation
# ============================================================================

check_bnd001() {
  section "BND-001: Agent vs orchestrator separation"

  if [ -z "$AGENT_BODY" ]; then
    fail "BND-001(a)" "$AGENT_SRC does not exist or body is empty"
    return
  fi

  local found_any=false
  for pattern in "${ORCHESTRATOR_DENYLIST[@]}"; do
    if echo "$AGENT_BODY" | grep -qF "$pattern"; then
      fail "BND-001(a:$pattern)" "agent file contains orchestrator logic: '$pattern'"
      found_any=true
    fi
  done

  if [ "$found_any" = "false" ]; then
    pass "BND-001(a)" "agent file does not contain orchestrator logic patterns"
  fi

  if [ -z "$STEP2_BLOCK" ]; then
    fail "BND-001(b)" "$CSPEC_SKILL does not exist or Step 2 block is empty"
    return
  fi

  if echo "$STEP2_BLOCK" | grep -qF "research signals" || echo "$STEP2_BLOCK" | grep -qF "Spawn the research subagent when"; then
    pass "BND-001(b)" "SKILL.md Step 2 retains orchestrator spawn logic"
  else
    fail "BND-001(b)" "SKILL.md Step 2 lost orchestrator spawn logic"
  fi
}

# ============================================================================
# VP-001: Agent discoverability — name matches subagent_type basename
# ============================================================================

check_vp001() {
  section "VP-001: Agent discoverability — name matches subagent_type basename"

  if [ ! -f "$AGENT_SRC" ]; then
    fail "VP-001(a)" "$AGENT_SRC does not exist"
    return
  fi

  local name
  name="$(get_frontmatter_field "$AGENT_SRC" "name" 2>/dev/null)" || name=""

  local basename_no_ext
  basename_no_ext="$(basename "$AGENT_SRC" .md)"

  if [ "$name" = "$basename_no_ext" ]; then
    pass "VP-001(a)" "frontmatter name: '$name' matches filename basename '$basename_no_ext'"
  else
    fail "VP-001(a)" "frontmatter name: '$name' does not match filename basename '$basename_no_ext'"
  fi
}

# ============================================================================
# WIRING: Test is registered in test.sh and workflow-config.json
# ============================================================================

check_wiring() {
  section "WIRING: Test registration"

  # DA-002: Test runner now uses glob-based discovery. Accept either direct
  # invocation in test-core.sh or glob pattern in workflow-config.json.
  if [ -f "$TEST_RUNNER" ] && grep -q "test-cspec-research-agent" "$TEST_RUNNER"; then
    pass "WIRING(a)" "test-cspec-research-agent is registered in tests/test-core.sh"
  elif jq -r '.commands.test // ""' ".correctless/config/workflow-config.json" 2>/dev/null | grep -qE 'test-\*\.sh'; then
    pass "WIRING(a)" "test-cspec-research-agent is discoverable by glob in commands.test"
  else
    fail "WIRING(a)" "test-cspec-research-agent is not registered in test runner"
  fi

  if [ -f "$WORKFLOW_CONFIG" ]; then
    if grep -q "test-cspec-research-agent" "$WORKFLOW_CONFIG" || jq -r '.commands.test // ""' "$WORKFLOW_CONFIG" 2>/dev/null | grep -qE 'test-\*\.sh'; then
      pass "WIRING(b)" "test-cspec-research-agent is discoverable by workflow-config.json"
    else
      fail "WIRING(b)" "test-cspec-research-agent is not registered in workflow-config.json"
    fi
  else
    fail "WIRING(b)" "$WORKFLOW_CONFIG does not exist"
  fi
}

# ============================================================================
# SYNC: sync.sh propagates the new agent file
# ============================================================================

check_sync() {
  section "SYNC: sync.sh handles cspec-research.md"

  if [ ! -f "$SYNC_SH" ]; then
    fail "SYNC(a)" "$SYNC_SH does not exist"
    return
  fi

  # sync.sh already uses a glob (agents/*.md), so no explicit listing needed.
  if grep -q 'agents/\*\.md' "$SYNC_SH"; then
    pass "SYNC(a)" "sync.sh uses agents/*.md glob (will pick up cspec-research.md)"
  else
    fail "SYNC(a)" "sync.sh does not glob agents/*.md — cspec-research.md won't be synced"
  fi
}

# ============================================================================
# SKILL-FRONTMATTER: /cspec skill allowed-tools includes Task
# ============================================================================

check_skill_frontmatter() {
  section "SKILL-FRONTMATTER: /cspec allowed-tools includes Task"

  if [ ! -f "$CSPEC_SKILL" ]; then
    fail "SKILL-FM(a)" "$CSPEC_SKILL does not exist"
    return
  fi

  local allowed
  allowed="$(get_frontmatter_field "$CSPEC_SKILL" "allowed-tools" 2>/dev/null)" || allowed=""

  if echo "$allowed" | grep -q "Task"; then
    pass "SKILL-FM(a)" "/cspec allowed-tools includes Task"
  else
    fail "SKILL-FM(a)" "/cspec allowed-tools does not include Task"
  fi
}

# ============================================================================
# Run all checks
# ============================================================================

_cache_agent_body
_cache_step2_block
_cache_abs010_block

check_inv001
check_inv002
check_inv003
check_inv004
check_inv005
check_inv006
check_inv007
check_inv008
check_inv009
check_inv010
check_inv011
check_inv012
check_inv013
check_inv014
check_inv015
check_inv016
check_inv017
check_prh001
check_prh002
check_bnd001
check_vp001
check_wiring
check_sync
check_skill_frontmatter

summary "cspec-research-agent"
