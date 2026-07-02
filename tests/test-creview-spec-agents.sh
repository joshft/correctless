#!/usr/bin/env bash
# shellcheck disable=SC1090,SC1091,SC2016,SC2086
# Correctless — creview-spec Plugin Agent Migration Tests
#
# Enforces the creview-spec-agent-migration spec's invariants, prohibitions,
# boundary conditions (INV-001..INV-012, PRH-001..PRH-002, BND-001..BND-002).
#
# Run from repo root: bash tests/test-creview-spec-agents.sh
#
# This is the RED-phase structural test. It asserts:
#   - 6 agent files exist with correct frontmatter (INV-001)
#   - Read-only tool allowlist: Read, Grep, Glob only (INV-002, PRH-002)
#   - SKILL.md dispatches via namespaced subagent_type (INV-003)
#   - No inline agent prompts remain in SKILL.md (INV-004, PRH-001)
#   - Shared preamble with 4 file references in each agent (INV-005)
#   - Unique adversarial lens preserved with AND-logic keywords (INV-006)
#   - Distribution parity after sync.sh (INV-007)
#   - ABS-010 registry updated in ARCHITECTURE.md (INV-008)
#   - Task in SKILL.md allowed-tools (INV-009)
#   - Intensity-gated selection stays in SKILL.md, not agents (INV-010)
#   - Harness-prior suppression per-agent keywords (INV-011)
#   - Output format contract per agent (INV-012)
#   - Agent vs orchestrator separation — no orchestrator logic in agents (BND-001)
#   - Shared preamble drift guard — byte-equal preambles across agents (BND-002)
#
# POSIX-portable externals only: grep, sed, awk, sha256sum, diff.
# Bash 4+ constructs are permitted.

source "$(dirname "${BASH_SOURCE[0]}")/test-helpers.sh"
set -f

# ============================================================================
# File paths
# ============================================================================

CREVIEW_SPEC_SKILL="skills/creview-spec/SKILL.md"
SYNC_SH="sync.sh"
ARCH_FILE=".correctless/ARCHITECTURE.md"
TEST_RUNNER="tests/test-core.sh"
WORKFLOW_CONFIG=".correctless/config/workflow-config.json"

# The 6 agent files
AGENTS=(
  "review-spec-red-team"
  "review-spec-assumptions"
  "review-spec-testability"
  "review-spec-design-contract"
  "review-spec-upgrade-compat"
  "review-spec-ux"
)

# ============================================================================
# Precomputed / cached data (avoids redundant file reads across check fns)
# ============================================================================

declare -A AGENT_BODIES
_cache_agent_bodies() {
  for agent_name in "${AGENTS[@]}"; do
    local agent_file="agents/${agent_name}.md"
    [ -f "$agent_file" ] && AGENT_BODIES["$agent_name"]="$(skill_body "$agent_file")"
  done
}

STEP1_BLOCK=""
_cache_step1_block() {
  [ -f "$CREVIEW_SPEC_SKILL" ] && STEP1_BLOCK="$(extract_step1_block "$CREVIEW_SPEC_SKILL")"
}

# ============================================================================
# Helpers
# ============================================================================

extract_step1_block() {
  local file="$1"
  [ -f "$file" ] || return 1
  awk '
    BEGIN { in_block = 0 }
    /^## Step 1:/ { in_block = 1; next }
    /^## Step 2:/ { in_block = 0; next }
    in_block { print }
  ' "$file" 2>/dev/null
}

# ============================================================================
# INV-001: Agent files exist with correct frontmatter
# ============================================================================

check_inv001() {
  section "INV-001: Agent files exist with correct frontmatter"

  for agent_name in "${AGENTS[@]}"; do
    local agent_file="agents/${agent_name}.md"

    if [ ! -f "$agent_file" ]; then
      fail "INV-001(${agent_name}:exist)" "$agent_file does not exist"
      continue
    fi
    pass "INV-001(${agent_name}:exist)" "$agent_file exists"

    # Check frontmatter exists
    local fm
    fm="$(extract_frontmatter "$agent_file" 2>/dev/null)" || {
      fail "INV-001(${agent_name}:fm)" "$agent_file has no valid YAML frontmatter"
      continue
    }
    if [ -z "$fm" ]; then
      fail "INV-001(${agent_name}:fm)" "$agent_file frontmatter is empty"
      continue
    fi
    pass "INV-001(${agent_name}:fm)" "$agent_file has a frontmatter block"

    # name: must match basename
    local name
    name="$(get_frontmatter_field "$agent_file" "name" 2>/dev/null)" || name=""
    if [ "$name" = "$agent_name" ]; then
      pass "INV-001(${agent_name}:name)" "frontmatter name: is '$agent_name'"
    else
      fail "INV-001(${agent_name}:name)" "frontmatter name: is '$name', expected '$agent_name'"
    fi

    # description: must exist and be non-empty
    local desc
    desc="$(get_frontmatter_field "$agent_file" "description" 2>/dev/null)" || desc=""
    if [ -n "$desc" ]; then
      pass "INV-001(${agent_name}:desc)" "frontmatter description: is non-empty"
    else
      fail "INV-001(${agent_name}:desc)" "frontmatter description: is missing or empty"
    fi

    # tools: must exist
    local tools
    tools="$(get_frontmatter_field "$agent_file" "tools" 2>/dev/null)" || tools=""
    if [ -n "$tools" ]; then
      pass "INV-001(${agent_name}:tools)" "frontmatter tools: is non-empty"
    else
      fail "INV-001(${agent_name}:tools)" "frontmatter tools: is missing or empty"
    fi
  done
}

# ============================================================================
# INV-002: Read-only tool allowlist (TB-005 security)
# ============================================================================

check_inv002() {
  section "INV-002: Read-only tool allowlist"

  for agent_name in "${AGENTS[@]}"; do
    local agent_file="agents/${agent_name}.md"
    if [ ! -f "$agent_file" ]; then
      fail "INV-002(${agent_name}:tools)" "$agent_file does not exist — cannot check tools"
      continue
    fi

    local tools
    tools="$(parse_tools_list "$agent_file" 2>/dev/null)" || {
      fail "INV-002(${agent_name}:tools)" "$agent_file has no tools: field"
      continue
    }

    # Expected tools: Read, Grep, Glob — exactly these 3, no more
    local actual
    actual="$(echo "$tools" | sort | tr '\n' ' ' | sed 's/ $//')"
    local expected_sorted="Glob Grep Read"

    if [ "$actual" = "$expected_sorted" ]; then
      pass "INV-002(${agent_name}:exact)" "tools: is exactly {Read, Grep, Glob}"
    else
      fail "INV-002(${agent_name}:exact)" "tools: is '$actual', expected '$expected_sorted'"
    fi

    # Tool count must be exactly 3
    local tool_count
    tool_count="$(echo "$tools" | wc -l | tr -d ' ')"
    if [ "$tool_count" -eq 3 ]; then
      pass "INV-002(${agent_name}:count)" "tools: has exactly 3 entries"
    else
      fail "INV-002(${agent_name}:count)" "tools: has $tool_count entries, expected 3"
    fi

    # Must NOT include write-capable tools (PRH-002 overlap)
    local -a denied_tools=("Write" "Edit" "Bash" "Task")
    for denied in "${denied_tools[@]}"; do
      if echo "$tools" | grep -q "^${denied}$"; then
        fail "INV-002(${agent_name}:deny-${denied})" "tools: includes ${denied} (write-capable)"
      else
        pass "INV-002(${agent_name}:deny-${denied})" "tools: does not include ${denied}"
      fi
    done
  done
}

# ============================================================================
# INV-003: Namespaced subagent_type dispatch in SKILL.md
# ============================================================================

check_inv003() {
  section "INV-003: Namespaced subagent_type dispatch in SKILL.md"

  if [ ! -f "$CREVIEW_SPEC_SKILL" ]; then
    fail "INV-003(a)" "$CREVIEW_SPEC_SKILL does not exist"
    return
  fi

  for agent_name in "${AGENTS[@]}"; do
    # Must contain subagent_type="correctless:<agent-name>"
    if grep -q "subagent_type=\"correctless:${agent_name}\"" "$CREVIEW_SPEC_SKILL" 2>/dev/null; then
      pass "INV-003(${agent_name})" "SKILL.md contains subagent_type=\"correctless:${agent_name}\""
    else
      fail "INV-003(${agent_name})" "SKILL.md does not contain subagent_type=\"correctless:${agent_name}\""
    fi
  done

  if echo "$STEP1_BLOCK" | grep -q 'subagent_type="general-purpose"'; then
    fail "INV-003(no-general)" "Step 1 still references subagent_type=\"general-purpose\""
  else
    pass "INV-003(no-general)" "Step 1 does not reference subagent_type=\"general-purpose\""
  fi
}

# ============================================================================
# INV-004: No inline agent prompts remain in SKILL.md
# ============================================================================

check_inv004() {
  section "INV-004: No inline agent prompts remain in SKILL.md"

  if [ ! -f "$CREVIEW_SPEC_SKILL" ]; then
    fail "INV-004(a)" "$CREVIEW_SPEC_SKILL does not exist"
    return
  fi

  local -a denylist=(
    "You are a security-focused adversary"
    "You are an assumptions auditor"
    "You are a test engineering auditor"
    "You are a design contract auditor"
    "You are a UX auditor"
    "upgrade compatibility"
  )

  local found_any=false
  for pattern in "${denylist[@]}"; do
    if echo "$STEP1_BLOCK" | grep -q "^> .*${pattern}"; then
      fail "INV-004(inline:${pattern:0:30})" "Step 1 has blockquoted line containing '${pattern}'"
      found_any=true
    fi
  done

  if [ "$found_any" = "false" ]; then
    pass "INV-004(no-inline)" "Step 1 has no blockquoted agent-identity patterns"
  fi

  # Check for large blockquoted prompt blocks (4+ consecutive > lines)
  # in the Step 1 agent sections. The preamble section (standard preamble
  # for all team members) is expected to remain — check only the numbered
  # agent sections (### 1. through ### 6.)
  for num in 1 2 3 4 5 6; do
    local nxt=$((num + 1))
    local agent_section
    agent_section="$(echo "$STEP1_BLOCK" | awk -v n="$num" -v nxt="$nxt" '
      $0 ~ "^### " n "\\." { in_block = 1; next }
      in_block && $0 ~ "^### " nxt "\\." { in_block = 0; next }
      in_block && /^## / { in_block = 0; next }
      in_block && /^At `/ { in_block = 0; next }
      in_block { print }
    ')"

    local consecutive
    consecutive="$(echo "$agent_section" | awk '
      /^>/ { count++; next }
      { if (count >= 4) found = 1; count = 0 }
      END { if (count >= 4) found = 1; print (found ? "yes" : "no") }
    ')"

    if [ "$consecutive" = "yes" ]; then
      fail "INV-004(block-${num})" "Agent section ${num} has 4+ consecutive blockquoted lines (likely inline prompt)"
    else
      pass "INV-004(block-${num})" "Agent section ${num} has no large blockquoted prompt blocks"
    fi
  done
}

# ============================================================================
# INV-005: Shared preamble with 4 file references
# ============================================================================

check_inv005() {
  section "INV-005: Shared preamble with 4 file references"

  local -a preamble_refs=(
    "AGENT_CONTEXT.md"
    "ARCHITECTURE.md"
    "antipatterns.md"
  )

  # Plus a spec-path placeholder token
  local spec_placeholder_pattern="spec.artifact\|spec_path\|{spec_path}\|spec.*path"

  for agent_name in "${AGENTS[@]}"; do
    local agent_file="agents/${agent_name}.md"
    if [ ! -f "$agent_file" ]; then
      fail "INV-005(${agent_name})" "$agent_file does not exist — cannot check preamble"
      continue
    fi

    local body="${AGENT_BODIES[$agent_name]}"

    for ref in "${preamble_refs[@]}"; do
      if echo "$body" | grep -q "$ref"; then
        pass "INV-005(${agent_name}:${ref})" "contains reference to $ref"
      else
        fail "INV-005(${agent_name}:${ref})" "missing reference to $ref"
      fi
    done

    # Check for spec path placeholder
    if echo "$body" | grep -qi "$spec_placeholder_pattern"; then
      pass "INV-005(${agent_name}:spec-path)" "contains spec path placeholder"
    else
      fail "INV-005(${agent_name}:spec-path)" "missing spec path placeholder"
    fi
  done
}

# ============================================================================
# INV-006: Unique adversarial lens preserved (AND-logic keywords)
# ============================================================================

check_inv006() {
  section "INV-006: Unique adversarial lens preserved"

  # Per-agent AND-logic keyword pairs
  # Format: agent_name|keyword1|keyword2 (keyword2 may be empty for single-keyword agents)
  local -a lens_keywords=(
    "review-spec-red-team|attack paths|bypass vectors"
    "review-spec-assumptions|unstated assumption|"
    "review-spec-testability|test engineering|vague invariants"
    "review-spec-design-contract|design contract|Enforcement:"
    "review-spec-upgrade-compat|upgrade compatibility|backward compatibility"
    "review-spec-ux|sub-lens|new-user"
  )

  for entry in "${lens_keywords[@]}"; do
    local agent_name kw1 kw2
    IFS='|' read -r agent_name kw1 kw2 <<< "$entry"

    local agent_file="agents/${agent_name}.md"
    if [ ! -f "$agent_file" ]; then
      fail "INV-006(${agent_name})" "$agent_file does not exist — cannot check lens keywords"
      continue
    fi

    local body="${AGENT_BODIES[$agent_name]}"

    # Check first keyword
    if echo "$body" | grep -qi "$kw1"; then
      pass "INV-006(${agent_name}:kw1)" "contains '$kw1'"
    else
      fail "INV-006(${agent_name}:kw1)" "missing keyword '$kw1'"
    fi

    # Check second keyword (if present — AND logic)
    if [ -n "$kw2" ]; then
      if echo "$body" | grep -qi "$kw2"; then
        pass "INV-006(${agent_name}:kw2)" "contains '$kw2'"
      else
        fail "INV-006(${agent_name}:kw2)" "missing keyword '$kw2'"
      fi
    fi
  done
}

# ============================================================================
# INV-007: Distribution parity
# ============================================================================

check_inv007() {
  section "INV-007: Distribution parity (source = dist)"

  for agent_name in "${AGENTS[@]}"; do
    local src="agents/${agent_name}.md"
    local dist="correctless/agents/${agent_name}.md"

    if [ ! -f "$src" ]; then
      fail "INV-007(${agent_name}:src)" "$src does not exist"
      continue
    fi

    if [ ! -f "$dist" ]; then
      fail "INV-007(${agent_name}:dist)" "$dist does not exist — distribution copy missing"
      continue
    fi

    if diff -q "$src" "$dist" >/dev/null 2>&1; then
      pass "INV-007(${agent_name})" "$src and $dist are byte-equal"
    else
      fail "INV-007(${agent_name})" "$src and $dist diverge"
    fi
  done
}

# ============================================================================
# INV-008: ABS-010 registry updated in ARCHITECTURE.md
# ============================================================================

check_inv008() {
  section "INV-008: ABS-010 registry updated"

  if [ ! -f "$ARCH_FILE" ]; then
    fail "INV-008(a)" "$ARCH_FILE does not exist"
    return
  fi

  # Extract ABS-010 block. Body moved to the abstractions fragment
  # (index+body-out fragmentation); heading stays in root.
  local abs010_block
  abs010_block="$(awk '
    /^### ABS-010:/ { found = 1 }
    found { print }
    found && /^### ABS-0[1-9]/ && !/^### ABS-010:/ { exit }
  ' "docs/architecture/abstractions.md" 2>/dev/null)"

  for agent_name in "${AGENTS[@]}"; do
    if echo "$abs010_block" | grep -q "$agent_name"; then
      pass "INV-008(${agent_name})" "ABS-010 mentions $agent_name"
    else
      fail "INV-008(${agent_name})" "ABS-010 does not mention $agent_name"
    fi
  done

  # Test file must be referenced in ABS-010
  if echo "$abs010_block" | grep -q "test-creview-spec-agents"; then
    pass "INV-008(test-ref)" "ABS-010 references test-creview-spec-agents"
  else
    fail "INV-008(test-ref)" "ABS-010 does not reference test-creview-spec-agents"
  fi
}

# ============================================================================
# INV-009: Task in SKILL.md allowed-tools
# ============================================================================

check_inv009() {
  section "INV-009: Task in SKILL.md allowed-tools"

  if [ ! -f "$CREVIEW_SPEC_SKILL" ]; then
    fail "INV-009(a)" "$CREVIEW_SPEC_SKILL does not exist"
    return
  fi

  local allowed
  allowed="$(get_frontmatter_field "$CREVIEW_SPEC_SKILL" "allowed-tools" 2>/dev/null)" || allowed=""

  if echo "$allowed" | grep -q "Task"; then
    pass "INV-009(a)" "/creview-spec allowed-tools includes Task"
  else
    fail "INV-009(a)" "/creview-spec allowed-tools does not include Task"
  fi
}

# ============================================================================
# INV-010: Intensity-gated selection stays in SKILL.md
# ============================================================================

check_inv010() {
  section "INV-010: Intensity-gated selection stays in SKILL.md"

  if [ ! -f "$CREVIEW_SPEC_SKILL" ]; then
    fail "INV-010(a)" "$CREVIEW_SPEC_SKILL does not exist"
    return
  fi

  # SKILL.md must still contain intensity-based agent selection
  if grep -q "intensity" "$CREVIEW_SPEC_SKILL" 2>/dev/null; then
    pass "INV-010(skill-intensity)" "SKILL.md contains intensity references"
  else
    fail "INV-010(skill-intensity)" "SKILL.md has no intensity references"
  fi

  # Agent files must NOT contain intensity-gating patterns (denylist)
  for agent_name in "${AGENTS[@]}"; do
    local agent_file="agents/${agent_name}.md"
    if [ ! -f "$agent_file" ]; then
      continue
    fi

    local body="${AGENT_BODIES[$agent_name]}"

    # Denylist pattern 1: "intensity" in conditional context
    if echo "$body" | grep -qiE "if.*intensity|intensity.*standard|intensity.*high|intensity.*low|intensity.*critical"; then
      fail "INV-010(${agent_name}:intensity)" "agent contains intensity in conditional context"
    else
      pass "INV-010(${agent_name}:intensity)" "agent does not contain intensity conditionals"
    fi

    # Denylist pattern 2: "spawn.*agents" or "select.*agents" in conditional context
    if echo "$body" | grep -qiE "spawn.*agents|select.*agents"; then
      fail "INV-010(${agent_name}:spawn)" "agent contains spawn/select agents pattern"
    else
      pass "INV-010(${agent_name}:spawn)" "agent does not contain spawn/select agents pattern"
    fi

    # Denylist pattern 3: agent-count gating (e.g., "low.*2.*standard.*3")
    if echo "$body" | grep -qiE "low.*[0-9].*standard.*[0-9]|standard.*[0-9].*high.*[0-9]"; then
      fail "INV-010(${agent_name}:count-gate)" "agent contains agent-count gating pattern"
    else
      pass "INV-010(${agent_name}:count-gate)" "agent does not contain agent-count gating"
    fi
  done
}

# ============================================================================
# INV-011: Harness-prior suppression per-agent keywords
# ============================================================================

check_inv011() {
  section "INV-011: Harness-prior suppression per-agent keywords"

  # Per-agent exhaustive-output phrases
  local -a exhaustive_phrases=(
    "review-spec-red-team|enumerate ALL attack paths"
    "review-spec-assumptions|List EVERY assumption"
    "review-spec-testability|evaluate ALL invariants"
    "review-spec-design-contract|check EVERY INV-xxx"
    "review-spec-upgrade-compat|check ALL 5 items"
    "review-spec-ux|evaluate through EVERY sub-lens"
  )

  for entry in "${exhaustive_phrases[@]}"; do
    local agent_name phrase
    IFS='|' read -r agent_name phrase <<< "$entry"

    local agent_file="agents/${agent_name}.md"
    if [ ! -f "$agent_file" ]; then
      fail "INV-011(${agent_name})" "$agent_file does not exist — cannot check exhaustive phrase"
      continue
    fi

    local body="${AGENT_BODIES[$agent_name]}"

    if echo "$body" | grep -q "$phrase"; then
      pass "INV-011(${agent_name})" "contains exhaustive phrase '$phrase'"
    else
      fail "INV-011(${agent_name})" "missing exhaustive phrase '$phrase'"
    fi
  done
}

# ============================================================================
# INV-012: Output format contract
# ============================================================================

check_inv012() {
  section "INV-012: Output format contract"

  for agent_name in "${AGENTS[@]}"; do
    local agent_file="agents/${agent_name}.md"
    if [ ! -f "$agent_file" ]; then
      fail "INV-012(${agent_name})" "$agent_file does not exist — cannot check output format"
      continue
    fi

    local body="${AGENT_BODIES[$agent_name]}"

    # Must contain output format instruction with "category" or "finding"
    if echo "$body" | grep -qi "category\|finding"; then
      pass "INV-012(${agent_name}:format)" "contains output format instruction (category/finding)"
    else
      fail "INV-012(${agent_name}:format)" "missing output format instruction"
    fi

    # Must contain markdown list reference (the contract specifies markdown list)
    if echo "$body" | grep -qi "markdown.*list\|list.*findings\|finding.*list\|bulleted\|bullet"; then
      pass "INV-012(${agent_name}:markdown)" "contains markdown list format reference"
    else
      fail "INV-012(${agent_name}:markdown)" "missing markdown list format reference"
    fi
  done
}

# ============================================================================
# PRH-001: No inline agent prompts for migrated agents
# ============================================================================

check_prh001() {
  section "PRH-001: No inline agent prompts for migrated agents"

  if [ ! -f "$CREVIEW_SPEC_SKILL" ]; then
    fail "PRH-001(a)" "$CREVIEW_SPEC_SKILL does not exist"
    return
  fi

  # Each of the original inline prompt signatures must be absent
  local -a inline_signatures=(
    "You are a security-focused adversary"
    "You are an assumptions auditor"
    "You are a test engineering auditor"
    "You are a design contract auditor"
    "existing user has this project"
    "You are a UX auditor"
  )

  for sig in "${inline_signatures[@]}"; do
    if echo "$STEP1_BLOCK" | grep -q "^> .*${sig}"; then
      fail "PRH-001(${sig:0:30})" "Step 1 still has blockquoted inline prompt: '$sig'"
    else
      pass "PRH-001(${sig:0:30})" "Step 1 does not have inline prompt: '${sig:0:30}...'"
    fi
  done
}

# ============================================================================
# PRH-002: No write tools in review agents (overlap with INV-002)
# ============================================================================

check_prh002() {
  section "PRH-002: No write tools in review agents"

  for agent_name in "${AGENTS[@]}"; do
    local agent_file="agents/${agent_name}.md"
    if [ ! -f "$agent_file" ]; then
      fail "PRH-002(${agent_name})" "$agent_file does not exist"
      continue
    fi

    local tools
    tools="$(parse_tools_list "$agent_file" 2>/dev/null)" || {
      fail "PRH-002(${agent_name})" "cannot parse tools field"
      continue
    }

    local has_write=false
    for denied in Write Edit Bash Task; do
      if echo "$tools" | grep -q "^${denied}$"; then
        fail "PRH-002(${agent_name}:${denied})" "agent has ${denied} in tools (write-capable)"
        has_write=true
      fi
    done

    if [ "$has_write" = "false" ]; then
      pass "PRH-002(${agent_name})" "agent has no write-capable tools"
    fi
  done
}

# ============================================================================
# BND-001: Agent vs orchestrator separation
# ============================================================================

check_bnd001() {
  section "BND-001: Agent vs orchestrator separation"

  for agent_name in "${AGENTS[@]}"; do
    local agent_file="agents/${agent_name}.md"
    if [ ! -f "$agent_file" ]; then
      continue
    fi

    local body="${AGENT_BODIES[$agent_name]}"

    # Exclude calibration example lines (PMB-xxx references) which mention
    # orchestrator concepts as examples of bugs to catch.
    local filtered_body
    filtered_body="$(echo "$body" | grep -v "^- PMB-")"

    if echo "$filtered_body" | grep -qi "checkpoint\|workflow-advance\|synthesis.*findings\|spawn.*agent"; then
      fail "BND-001(${agent_name})" "agent contains orchestrator logic (checkpoint/synthesis/spawn/workflow-advance)"
    else
      pass "BND-001(${agent_name})" "agent does not contain orchestrator logic"
    fi
  done
}

# ============================================================================
# BND-002: Shared preamble drift guard (byte-equal preambles)
# ============================================================================

check_bnd002() {
  section "BND-002: Shared preamble drift guard"

  local -a preamble_hashes=()
  local -a preamble_agents=()
  local first_hash=""

  for agent_name in "${AGENTS[@]}"; do
    local agent_file="agents/${agent_name}.md"
    if [ ! -f "$agent_file" ]; then
      fail "BND-002(${agent_name})" "$agent_file does not exist — cannot check preamble"
      continue
    fi

    local body="${AGENT_BODIES[$agent_name]}"

    local preamble
    preamble="$(echo "$body" | awk '
      /^## Preamble/ { in_preamble = 1; next }
      in_preamble && /^## / { exit }
      in_preamble { print }
    ')"

    if [ -z "$preamble" ]; then
      fail "BND-002(${agent_name}:extract)" "could not extract preamble from $agent_file"
      continue
    fi

    local hash
    hash="$(printf '%s' "$preamble" | sha256sum | awk '{print $1}')"
    preamble_hashes+=("$hash")
    preamble_agents+=("$agent_name")

    if [ -z "$first_hash" ]; then
      first_hash="$hash"
    fi
  done

  # All preamble hashes must be identical
  if [ ${#preamble_hashes[@]} -lt 2 ]; then
    fail "BND-002(compare)" "fewer than 2 agents available for preamble comparison"
    return
  fi

  local all_match=true
  for i in "${!preamble_hashes[@]}"; do
    if [ "${preamble_hashes[$i]}" != "$first_hash" ]; then
      fail "BND-002(${preamble_agents[$i]})" "preamble hash differs from ${preamble_agents[0]}"
      all_match=false
    fi
  done

  if [ "$all_match" = "true" ]; then
    pass "BND-002(all)" "all 6 agent preambles are byte-equal"
  fi
}

# ============================================================================
# VP-001: Agent discoverability — name matches subagent_type basename
# ============================================================================

check_vp001() {
  section "VP-001: Agent discoverability"

  for agent_name in "${AGENTS[@]}"; do
    local agent_file="agents/${agent_name}.md"
    if [ ! -f "$agent_file" ]; then
      fail "VP-001(${agent_name})" "$agent_file does not exist"
      continue
    fi

    local name
    name="$(get_frontmatter_field "$agent_file" "name" 2>/dev/null)" || name=""

    local basename_no_ext
    basename_no_ext="$(basename "$agent_file" .md)"

    if [ "$name" = "$basename_no_ext" ]; then
      pass "VP-001(${agent_name})" "name: '$name' matches filename basename"
    else
      fail "VP-001(${agent_name})" "name: '$name' does not match filename basename '$basename_no_ext'"
    fi
  done
}

# ============================================================================
# WIRING: Test is registered in test.sh and workflow-config.json
# ============================================================================

check_wiring() {
  section "WIRING: Test registration"

  # DA-002: Test runner now uses glob-based discovery. Accept either direct
  # invocation in test-core.sh or glob pattern in workflow-config.json.
  if [ -f "$TEST_RUNNER" ] && grep -q "test-creview-spec-agents" "$TEST_RUNNER"; then
    pass "WIRING(a)" "test-creview-spec-agents is registered in tests/test-core.sh"
  elif jq -r '.commands.test // ""' ".correctless/config/workflow-config.json" 2>/dev/null | grep -qE 'test-\*\.sh'; then
    pass "WIRING(a)" "test-creview-spec-agents is discoverable by glob in commands.test"
  else
    fail "WIRING(a)" "test-creview-spec-agents is not registered in test runner"
  fi

  if [ -f "$WORKFLOW_CONFIG" ]; then
    if grep -q "test-creview-spec-agents" "$WORKFLOW_CONFIG" || jq -r '.commands.test // ""' "$WORKFLOW_CONFIG" 2>/dev/null | grep -qE 'test-\*\.sh'; then
      pass "WIRING(b)" "test-creview-spec-agents is discoverable by workflow-config.json"
    else
      fail "WIRING(b)" "test-creview-spec-agents is not registered in workflow-config.json"
    fi
  else
    fail "WIRING(b)" "$WORKFLOW_CONFIG does not exist"
  fi
}

# ============================================================================
# SYNC: sync.sh propagates agent files
# ============================================================================

check_sync() {
  section "SYNC: sync.sh handles agent files"

  if [ ! -f "$SYNC_SH" ]; then
    fail "SYNC(a)" "$SYNC_SH does not exist"
    return
  fi

  if grep -q 'agents/\*\.md' "$SYNC_SH"; then
    pass "SYNC(a)" "sync.sh uses agents/*.md glob (will pick up review-spec agents)"
  else
    fail "SYNC(a)" "sync.sh does not glob agents/*.md"
  fi
}

# ============================================================================
# Run all checks
# ============================================================================

_cache_step1_block
_cache_agent_bodies

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
check_prh001
check_prh002
check_bnd001
check_bnd002
check_vp001
check_wiring
check_sync

summary "creview-spec-agents"
