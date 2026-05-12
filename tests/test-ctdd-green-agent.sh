#!/usr/bin/env bash
# shellcheck disable=SC1090,SC1091,SC2016,SC2086
# Correctless — ctdd-green Plugin Agent Migration Tests
#
# Enforces the ctdd-green-agent-migration spec's invariants, prohibitions,
# boundary conditions, and breaking change (INV-001..INV-009, PRH-001..PRH-002,
# BND-002, BC-001).
#
# Run from repo root: bash tests/test-ctdd-green-agent.sh
#
# This is the RED-phase structural test. It asserts:
#   - agents/ctdd-green.md exists with correct frontmatter (INV-001, INV-002)
#   - skills/ctdd/SKILL.md GREEN phase uses namespaced Task invocation (INV-003)
#   - SKILL.md GREEN phase has no inline blockquoted agent prompt (INV-004, PRH-001)
#   - Agent prompt has defensive code override (INV-005)
#   - Agent prompt prohibits test file edits (INV-006)
#   - Agent prompt references commands.test from workflow-config.json (INV-007)
#   - Distribution parity after sync.sh (INV-008)
#   - .correctless/ARCHITECTURE.md ABS-010 lists ctdd-green consumer (INV-009)
#   - Agent prompt does not enumerate test runners (PRH-002)
#   - Agent prompt has structured TEST_BUG escalation format (BND-002)
#   - QA agent tdd-test-edits.log review is conditional on file existing (BC-001)
#   - SKILL.md constraint line reflects prohibition policy (BC-001)
#
# POSIX-portable externals only: grep, sed, awk, sha256sum, find. Bash 4+
# constructs are permitted.

source "$(dirname "${BASH_SOURCE[0]}")/test-helpers.sh"
set -f

# ============================================================================
# File paths
# ============================================================================

AGENT_SRC="agents/ctdd-green.md"
AGENT_DIST="correctless/agents/ctdd-green.md"
CTDD_SKILL="skills/ctdd/SKILL.md"
SYNC_SH="sync.sh"
ARCH_FILE=".correctless/ARCHITECTURE.md"
TEST_RUNNER="tests/test.sh"
WORKFLOW_CONFIG=".correctless/config/workflow-config.json"

# ============================================================================
# Helpers
# ============================================================================

# Extract frontmatter block (between leading --- lines) from a markdown file.
# Emits nothing and returns non-zero if frontmatter is absent or malformed.
#
# Result is memoized per-file.
extract_frontmatter() {
  local file="$1"
  [ -f "$file" ] || return 1
  local cache_var
  cache_var="_FM_CACHE_$(printf '%s' "$file" | tr -c 'a-zA-Z0-9' '_')"
  local cached="${!cache_var:-__UNSET__}"
  if [ "$cached" != "__UNSET__" ]; then
    printf '%s' "$cached"
    [ -n "$cached" ] && return 0 || return 1
  fi
  local result
  result="$(awk '
    BEGIN { state = 0 }
    NR == 1 {
      if ($0 == "---") { state = 1; next }
      else { exit 1 }
    }
    state == 1 && $0 == "---" { exit 0 }
    state == 1 { print }
  ' "$file" 2>/dev/null || true)"
  printf -v "$cache_var" '%s' "$result"
  printf '%s' "$result"
  [ -n "$result" ] && return 0 || return 1
}

# Extract a single scalar frontmatter field (key: value) from the agent file.
get_frontmatter_field() {
  local file="$1" key="$2"
  extract_frontmatter "$file" 2>/dev/null | awk -v k="$key" '
    BEGIN { found = 0 }
    {
      if (match($0, "^[[:space:]]*" k ":[[:space:]]*")) {
        val = substr($0, RSTART + RLENGTH)
        sub(/[[:space:]]+$/, "", val)
        print val
        found = 1
        exit
      }
    }
    END { exit (found ? 0 : 1) }
  '
}

# Parse the `tools:` comma-flow field and emit one tool name per line.
parse_tools_list() {
  local file="$1"
  local raw
  raw="$(get_frontmatter_field "$file" "tools")" || return 1
  [ -n "$raw" ] || return 1
  printf '%s\n' "$raw" | awk '
    {
      n = split($0, a, ",")
      for (i = 1; i <= n; i++) {
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", a[i])
        if (a[i] != "") print a[i]
      }
    }
  '
}

# Extract the GREEN phase section from SKILL.md — from "## Phase: GREEN"
# to the next "### GREEN Phase Calm Reset Prompt" heading.
# This is the block where the inline agent prompt lived pre-migration.
extract_green_phase_block() {
  local file="$1"
  [ -f "$file" ] || return 1
  awk '
    BEGIN { in_block = 0 }
    /^## Phase: GREEN/ { in_block = 1; next }
    /^### GREEN Phase Calm Reset Prompt/ { in_block = 0; next }
    in_block { print }
  ' "$file" 2>/dev/null
}

# Extract the QA phase section from SKILL.md — from "## Phase: QA"
# to the next "## " heading of same level.
extract_qa_phase_block() {
  local file="$1"
  [ -f "$file" ] || return 1
  awk '
    BEGIN { in_block = 0 }
    /^## Phase: QA/ { in_block = 1; next }
    in_block && /^## [^#]/ { in_block = 0; next }
    in_block { print }
  ' "$file" 2>/dev/null
}

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

  # name: must be "ctdd-green"
  local name
  name="$(get_frontmatter_field "$AGENT_SRC" "name" 2>/dev/null)" || name=""
  if [ "$name" = "ctdd-green" ]; then
    pass "INV-001(c)" "frontmatter name: is 'ctdd-green'"
  else
    fail "INV-001(c)" "frontmatter name: is '$name', expected 'ctdd-green'"
  fi

  # model: must be "inherit"
  local model
  model="$(get_frontmatter_field "$AGENT_SRC" "model" 2>/dev/null)" || model=""
  if [ "$model" = "inherit" ]; then
    pass "INV-001(d)" "frontmatter model: is 'inherit'"
  else
    fail "INV-001(d)" "frontmatter model: is '$model', expected 'inherit'"
  fi
}

# ============================================================================
# INV-002: Tool allowlist pinned
# ============================================================================

check_inv002() {
  section "INV-002: Tool allowlist pinned"

  if [ ! -f "$AGENT_SRC" ]; then
    fail "INV-002(a)" "$AGENT_SRC does not exist — cannot check tools"
    return
  fi

  local tools
  tools="$(parse_tools_list "$AGENT_SRC" 2>/dev/null)" || {
    fail "INV-002(a)" "$AGENT_SRC has no tools: field in frontmatter"
    return
  }

  # Expected tools: Read, Grep, Glob, Write, Edit, Bash (same as ctdd-red)
  local expected="Read Grep Glob Write Edit Bash"
  local actual
  actual="$(echo "$tools" | sort | tr '\n' ' ' | sed 's/ $//')"
  local expected_sorted
  expected_sorted="$(echo "$expected" | tr ' ' '\n' | sort | tr '\n' ' ' | sed 's/ $//')"

  if [ "$actual" = "$expected_sorted" ]; then
    pass "INV-002(a)" "tools: list matches expected set {$expected}"
  else
    fail "INV-002(a)" "tools: list is '$actual', expected '$expected_sorted'"
  fi

  # Tool count must be exactly 6
  local tool_count
  tool_count="$(echo "$tools" | wc -l | tr -d ' ')"
  if [ "$tool_count" -eq 6 ]; then
    pass "INV-002(b)" "tools: list has exactly 6 entries"
  else
    fail "INV-002(b)" "tools: list has $tool_count entries, expected 6"
  fi

  # Must NOT include Task or Agent (escalation tools)
  if echo "$tools" | grep -q "^Task$"; then
    fail "INV-002(c)" "tools: list includes Task (escalation tool)"
  else
    pass "INV-002(c)" "tools: list does not include Task"
  fi

  if echo "$tools" | grep -q "^Agent$"; then
    fail "INV-002(d)" "tools: list includes Agent (escalation tool)"
  else
    pass "INV-002(d)" "tools: list does not include Agent"
  fi
}

# ============================================================================
# INV-003: SKILL.md uses namespaced subagent_type
# ============================================================================

check_inv003() {
  section "INV-003: SKILL.md uses namespaced subagent_type for GREEN phase"

  if [ ! -f "$CTDD_SKILL" ]; then
    fail "INV-003(a)" "$CTDD_SKILL does not exist"
    return
  fi

  local green_block
  green_block="$(extract_green_phase_block "$CTDD_SKILL")"

  # Must contain the namespaced subagent_type
  if echo "$green_block" | grep -q 'subagent_type="correctless:ctdd-green"'; then
    pass "INV-003(a)" "GREEN phase contains subagent_type=\"correctless:ctdd-green\""
  else
    fail "INV-003(a)" "GREEN phase does not contain subagent_type=\"correctless:ctdd-green\""
  fi

  # Must NOT contain general-purpose subagent_type
  if echo "$green_block" | grep -q 'subagent_type="general-purpose"'; then
    fail "INV-003(b)" "GREEN phase still references subagent_type=\"general-purpose\""
  else
    pass "INV-003(b)" "GREEN phase does not reference subagent_type=\"general-purpose\""
  fi
}

# ============================================================================
# INV-004: No inline prompt in SKILL.md GREEN phase
# ============================================================================

check_inv004() {
  section "INV-004: No inline blockquoted agent prompt in GREEN phase"

  if [ ! -f "$CTDD_SKILL" ]; then
    fail "INV-004(a)" "$CTDD_SKILL does not exist"
    return
  fi

  local green_block
  green_block="$(extract_green_phase_block "$CTDD_SKILL")"

  # Denylist: blockquoted lines containing agent identity/behavioral patterns
  # These patterns were the inline prompt content pre-migration.
  local -a denylist=(
    "You are the implementation agent"
    "your job is to"
    "allowed-tools"
    "Log all test edits"
    "Write: source files"
    "Read: .correctless/AGENT_CONTEXT.md"
  )

  local found_any=false
  for pattern in "${denylist[@]}"; do
    # Check for blockquoted lines containing these patterns
    if echo "$green_block" | grep -q "^> .*${pattern}"; then
      fail "INV-004(a)" "GREEN phase has blockquoted line containing '$pattern'"
      found_any=true
    fi
  done

  if [ "$found_any" = "false" ]; then
    pass "INV-004(a)" "GREEN phase has no blockquoted agent-identity patterns"
  fi

  # Verify there is no multi-line blockquoted prompt (more than 3 consecutive blockquote
  # lines that look like agent instructions). A blockquote line starts with '>' optionally
  # followed by a space — blank blockquote continuations (just '>') count too.
  local consecutive_blockquotes
  consecutive_blockquotes="$(echo "$green_block" | awk '
    /^>/ { count++; next }
    { if (count >= 4) found = 1; count = 0 }
    END { if (count >= 4) found = 1; print (found ? "yes" : "no") }
  ')"

  if [ "$consecutive_blockquotes" = "yes" ]; then
    fail "INV-004(b)" "GREEN phase has 4+ consecutive blockquoted lines (likely inline prompt)"
  else
    pass "INV-004(b)" "GREEN phase has no large blockquoted prompt blocks"
  fi
}

# ============================================================================
# INV-005: Defensive code override in agent prompt
# ============================================================================

check_inv005() {
  section "INV-005: Defensive code override in agent prompt"

  if [ ! -f "$AGENT_SRC" ]; then
    fail "INV-005(a)" "$AGENT_SRC does not exist — cannot check defensive override"
    return
  fi

  local body
  body="$(skill_body "$AGENT_SRC")"

  # Must contain explicit override of defensive-code suppression
  # Looking for keywords that indicate the agent is told to write guards/validation
  # despite harness defaults that might suppress them
  if echo "$body" | grep -qi "defensive\|guard\|validation.*required\|error handling"; then
    pass "INV-005(a)" "agent prompt contains defensive code instruction"
  else
    fail "INV-005(a)" "agent prompt has no defensive code override instruction"
  fi

  # Must NOT defer to harness "don't add validation for impossible scenarios"
  # The agent prompt MAY mention the harness prior in order to override it
  # (e.g., "the inverse applies") — that's an override, not a deferral.
  # It may also list "skip validation" in a "do NOT do" section — that's a prohibition.
  # A deferral would be an affirmative instruction to follow the harness default.
  # Check for affirmative deferral patterns only:
  if echo "$body" | grep -qi "follow.*harness.*default\|defer.*to.*harness\|don.t add.*unnecessary.*validation"; then
    fail "INV-005(b)" "agent prompt defers to harness defensive-code suppression"
  else
    pass "INV-005(b)" "agent prompt does not defer to harness defensive-code suppression"
  fi
}

# ============================================================================
# INV-006: Test file edit prohibition
# ============================================================================

check_inv006() {
  section "INV-006: Test file edit prohibition in agent prompt"

  if [ ! -f "$AGENT_SRC" ]; then
    fail "INV-006(a)" "$AGENT_SRC does not exist — cannot check test-edit prohibition"
    return
  fi

  local body
  body="$(skill_body "$AGENT_SRC")"

  # Must contain explicit prohibition against editing test files
  if echo "$body" | grep -qi "must not.*edit.*test\|prohibit.*test.*edit\|do not.*edit.*test\|never.*edit.*test\|not.*Write.*Edit.*test"; then
    pass "INV-006(a)" "agent prompt contains test-edit prohibition"
  else
    fail "INV-006(a)" "agent prompt has no explicit test-edit prohibition"
  fi

  # Must instruct agent to stop and report rather than fix tests
  if echo "$body" | grep -qi "stop.*report\|report.*orchestrator\|escalat"; then
    pass "INV-006(b)" "agent prompt instructs stop-and-report on test bugs"
  else
    fail "INV-006(b)" "agent prompt does not instruct stop-and-report behavior"
  fi
}

# ============================================================================
# INV-007: Config-derived test command
# ============================================================================

check_inv007() {
  section "INV-007: Config-derived test command in agent prompt"

  if [ ! -f "$AGENT_SRC" ]; then
    fail "INV-007(a)" "$AGENT_SRC does not exist — cannot check test command derivation"
    return
  fi

  local body
  body="$(skill_body "$AGENT_SRC")"

  # Must reference commands.test from workflow-config.json
  if echo "$body" | grep -q "commands\.test"; then
    pass "INV-007(a)" "agent prompt references commands.test"
  else
    fail "INV-007(a)" "agent prompt does not reference commands.test"
  fi

  # Must reference workflow-config.json
  if echo "$body" | grep -q "workflow-config\.json"; then
    pass "INV-007(b)" "agent prompt references workflow-config.json"
  else
    fail "INV-007(b)" "agent prompt does not reference workflow-config.json"
  fi
}

# ============================================================================
# INV-008: Distribution parity
# ============================================================================

check_inv008() {
  section "INV-008: Distribution parity (source = dist after sync)"

  if [ ! -f "$AGENT_SRC" ]; then
    fail "INV-008(a)" "$AGENT_SRC does not exist — cannot check parity"
    return
  fi

  if [ ! -f "$AGENT_DIST" ]; then
    fail "INV-008(a)" "$AGENT_DIST does not exist — distribution copy missing"
    return
  fi

  # Byte-equal check
  if diff -q "$AGENT_SRC" "$AGENT_DIST" >/dev/null 2>&1; then
    pass "INV-008(a)" "$AGENT_SRC and $AGENT_DIST are byte-equal"
  else
    fail "INV-008(a)" "$AGENT_SRC and $AGENT_DIST diverge"
  fi
}

# ============================================================================
# INV-009: ABS-010 consumer list and write-permission updated
# ============================================================================

check_inv009() {
  section "INV-009: ABS-010 consumer list includes ctdd-green"

  if [ ! -f "$ARCH_FILE" ]; then
    fail "INV-009(a)" "$ARCH_FILE does not exist"
    return
  fi

  # ABS-010 consumer list must mention ctdd-green
  local abs010_block
  abs010_block="$(awk '
    /^### ABS-010:/ { found = 1 }
    found { print }
    found && /^### ABS-0[1-9][1-9]:/ && !/^### ABS-010:/ { exit }
  ' "$ARCH_FILE" 2>/dev/null)"

  if echo "$abs010_block" | grep -q "ctdd-green"; then
    pass "INV-009(a)" "ABS-010 entry mentions ctdd-green"
  else
    fail "INV-009(a)" "ABS-010 entry does not mention ctdd-green"
  fi

  # Write-permission parenthetical must also name ctdd-green
  if echo "$abs010_block" | grep -qi "ctdd-green.*write\|write.*ctdd-green"; then
    pass "INV-009(b)" "ABS-010 write-permission mentions ctdd-green"
  else
    fail "INV-009(b)" "ABS-010 write-permission does not mention ctdd-green"
  fi

  # Test file must be listed in ABS-010's Test line
  if echo "$abs010_block" | grep -q "test-ctdd-green-agent"; then
    pass "INV-009(c)" "ABS-010 Test line references test-ctdd-green-agent"
  else
    fail "INV-009(c)" "ABS-010 Test line does not reference test-ctdd-green-agent"
  fi
}

# ============================================================================
# PRH-001: No inline agent prompt in SKILL.md GREEN phase
# (Overlaps with INV-004 but tests the prohibition specifically)
# ============================================================================

check_prh001() {
  section "PRH-001: No inline agent prompt (prohibition)"

  if [ ! -f "$CTDD_SKILL" ]; then
    fail "PRH-001(a)" "$CTDD_SKILL does not exist"
    return
  fi

  local green_block
  green_block="$(extract_green_phase_block "$CTDD_SKILL")"

  # The GREEN phase section must not contain a blockquoted system prompt
  # defining the implementation agent's identity
  if echo "$green_block" | grep -q "^> You are the implementation agent"; then
    fail "PRH-001(a)" "GREEN phase still has inline '> You are the implementation agent' prompt"
  else
    pass "PRH-001(a)" "GREEN phase does not have inline agent identity prompt"
  fi

  # Must not contain the old allowed-tools restriction as blockquote
  if echo "$green_block" | grep -q "^> .*allowed-tools.*restricted to"; then
    fail "PRH-001(b)" "GREEN phase still has inline allowed-tools restriction"
  else
    pass "PRH-001(b)" "GREEN phase does not have inline allowed-tools restriction"
  fi
}

# ============================================================================
# PRH-002: No test runner enumeration in agent prompt
# ============================================================================

check_prh002() {
  section "PRH-002: No test runner enumeration in agent prompt"

  if [ ! -f "$AGENT_SRC" ]; then
    fail "PRH-002(a)" "$AGENT_SRC does not exist — cannot check for test runner enumeration"
    return
  fi

  local body
  body="$(skill_body "$AGENT_SRC")"

  # Must not enumerate specific test runners
  local -a runners=(
    "npm test"
    "go test"
    "pytest"
    "cargo test"
    "jest"
    "vitest"
    "mocha"
  )

  local found_runner=false
  for runner in "${runners[@]}"; do
    # Use word-boundary-ish matching — avoid false positives from prose about test commands
    if echo "$body" | grep -q "$runner"; then
      fail "PRH-002(a)" "agent prompt enumerates test runner '$runner'"
      found_runner=true
    fi
  done

  if [ "$found_runner" = "false" ]; then
    pass "PRH-002(a)" "agent prompt does not enumerate specific test runners"
  fi
}

# ============================================================================
# BND-002: Test edit bug escalation — structured TEST_BUG format
# ============================================================================

check_bnd002() {
  section "BND-002: Structured TEST_BUG escalation format"

  if [ ! -f "$AGENT_SRC" ]; then
    fail "BND-002(a)" "$AGENT_SRC does not exist — cannot check TEST_BUG format"
    return
  fi

  local body
  body="$(skill_body "$AGENT_SRC")"

  # Must contain TEST_BUG sentinel/format instruction
  if echo "$body" | grep -q "TEST_BUG"; then
    pass "BND-002(a)" "agent prompt contains TEST_BUG sentinel"
  else
    fail "BND-002(a)" "agent prompt does not contain TEST_BUG sentinel"
  fi

  # Must describe the structured format (test_file:line — description)
  if echo "$body" | grep -q "test_file\|{test_file}"; then
    pass "BND-002(b)" "agent prompt describes TEST_BUG format with file reference"
  else
    fail "BND-002(b)" "agent prompt does not describe TEST_BUG format with file reference"
  fi
}

# ============================================================================
# BC-001: Breaking change — test-edit policy + QA log conditional
# ============================================================================

check_bc001() {
  section "BC-001: Breaking change — test-edit policy update"

  if [ ! -f "$CTDD_SKILL" ]; then
    fail "BC-001(a)" "$CTDD_SKILL does not exist"
    return
  fi

  # QA agent section: tdd-test-edits.log review must be conditional on file existing
  local qa_block
  qa_block="$(extract_qa_phase_block "$CTDD_SKILL")"

  # The QA block must have conditional language around tdd-test-edits.log
  # e.g., "if it exists", "if present", "when present"
  if echo "$qa_block" | grep -q "tdd-test-edits.log"; then
    # It mentions the log — now check it's conditional
    if echo "$qa_block" | grep -qi "tdd-test-edits.log.*if.*exist\|if.*exist.*tdd-test-edits.log\|if present.*tdd-test-edits.log\|tdd-test-edits.log.*if present\|tdd-test-edits.log.*when.*present\|when.*present.*tdd-test-edits.log"; then
      pass "BC-001(a)" "QA agent tdd-test-edits.log review is conditional on existence"
    else
      fail "BC-001(a)" "QA agent mentions tdd-test-edits.log but not conditionally"
    fi
  else
    # If it doesn't mention the log at all, that could be OK (removed entirely)
    # but per spec it should be conditional, not removed
    fail "BC-001(a)" "QA agent section does not mention tdd-test-edits.log at all"
  fi

  # SKILL.md constraints section: line about test edits must reflect prohibition
  # Old: "Test edits during GREEN are logged, not blocked."
  # New: should reference prohibition/blocked/not allowed
  local constraints_line
  constraints_line="$(grep -n "Test edits during GREEN" "$CTDD_SKILL" 2>/dev/null || true)"

  if [ -n "$constraints_line" ]; then
    # The old line says "logged, not blocked" — the new line must say something about
    # prohibition/not permitted. We specifically reject the old phrasing.
    if echo "$constraints_line" | grep -q "logged, not blocked"; then
      fail "BC-001(b)" "SKILL.md constraint line still says 'logged, not blocked' — needs update to reflect prohibition"
    elif echo "$constraints_line" | grep -qi "prohibit\|not permitted\|not allowed"; then
      pass "BC-001(b)" "SKILL.md constraint line reflects test-edit prohibition policy"
    else
      fail "BC-001(b)" "SKILL.md constraint line does not clearly reflect prohibition policy"
    fi
  else
    fail "BC-001(b)" "SKILL.md has no constraint line about test edits during GREEN"
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

  # The filename basename (without .md) must equal the name: field
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

  # Test must be listed in tests/test.sh
  if [ -f "$TEST_RUNNER" ]; then
    if grep -q "test-ctdd-green-agent" "$TEST_RUNNER"; then
      pass "WIRING(a)" "test-ctdd-green-agent is registered in tests/test.sh"
    else
      fail "WIRING(a)" "test-ctdd-green-agent is not registered in tests/test.sh"
    fi
  else
    fail "WIRING(a)" "$TEST_RUNNER does not exist"
  fi

  # Test must be in workflow-config.json commands.test
  if [ -f "$WORKFLOW_CONFIG" ]; then
    if grep -q "test-ctdd-green-agent" "$WORKFLOW_CONFIG"; then
      pass "WIRING(b)" "test-ctdd-green-agent is registered in workflow-config.json"
    else
      fail "WIRING(b)" "test-ctdd-green-agent is not registered in workflow-config.json"
    fi
  else
    fail "WIRING(b)" "$WORKFLOW_CONFIG does not exist"
  fi
}

# ============================================================================
# SKILL-FRONTMATTER: /ctdd skill allowed-tools includes Task
# ============================================================================

check_skill_frontmatter() {
  section "SKILL-FRONTMATTER: /ctdd allowed-tools includes Task"

  if [ ! -f "$CTDD_SKILL" ]; then
    fail "SKILL-FM(a)" "$CTDD_SKILL does not exist"
    return
  fi

  local allowed
  allowed="$(get_frontmatter_field "$CTDD_SKILL" "allowed-tools" 2>/dev/null)" || allowed=""

  # The orchestrator needs Task to spawn ctdd-red and ctdd-green subagents
  if echo "$allowed" | grep -q "Task"; then
    pass "SKILL-FM(a)" "/ctdd allowed-tools includes Task"
  else
    fail "SKILL-FM(a)" "/ctdd allowed-tools does not include Task"
  fi
}

# ============================================================================
# SYNC: sync.sh propagates the new agent file
# ============================================================================

check_sync() {
  section "SYNC: sync.sh handles ctdd-green.md"

  if [ ! -f "$SYNC_SH" ]; then
    fail "SYNC(a)" "$SYNC_SH does not exist"
    return
  fi

  # sync.sh already uses a glob (agents/*.md), so no explicit listing needed.
  # Verify the glob pattern is still there.
  if grep -q 'agents/\*\.md' "$SYNC_SH"; then
    pass "SYNC(a)" "sync.sh uses agents/*.md glob (will pick up ctdd-green.md)"
  else
    fail "SYNC(a)" "sync.sh does not glob agents/*.md — ctdd-green.md won't be synced"
  fi
}

# ============================================================================
# Run all checks
# ============================================================================

check_inv001
check_inv002
check_inv003
check_inv004
check_inv005
check_inv006
check_inv007
check_inv008
check_inv009
check_prh001
check_prh002
check_bnd002
check_bc001
check_vp001
check_wiring
check_skill_frontmatter
check_sync

summary "ctdd-green-agent"
