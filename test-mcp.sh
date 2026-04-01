#!/usr/bin/env bash
# Correctless — MCP integration tests
# Tests spec rules R-001 through R-026 from docs/specs/mcp-integration.md
# Run from repo root: bash test-mcp.sh

set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PASS=0
FAIL=0

# ---------------------------------------------------------------------------
# Helpers (matching test.sh style)
# ---------------------------------------------------------------------------

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (expected '$expected', got '$actual')"
    FAIL=$((FAIL + 1))
  fi
}

assert_contains() {
  local desc="$1" expected="$2" actual="$3"
  if echo "$actual" | grep -q "$expected"; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (expected output to contain '$expected')"
    FAIL=$((FAIL + 1))
  fi
}

# Check if a file contains a pattern (returns 0 if found)
file_contains() {
  grep -q "$2" "$1" 2>/dev/null
}

# Check if a file contains a pattern (case-insensitive, returns 0 if found)
file_contains_i() {
  grep -qi "$2" "$1" 2>/dev/null
}

# ---------------------------------------------------------------------------
# Skill lists from the spec
# ---------------------------------------------------------------------------

# R-022: 14 skills that receive Serena integration
SERENA_SKILLS="cspec creview creview-spec ctdd cverify caudit crefactor credteam cwtf cmaintain ccontribute cdebug cpr-review cdocs"

# R-023: 2 skills that receive Context7 integration
CONTEXT7_SKILLS="cspec cdebug"

# R-024: Skills that do NOT receive MCP integration (except cwtf which is in R-022)
NO_MCP_SKILLS="chelp cstatus csummary cmetrics cpostmortem cdevadv"

# ---------------------------------------------------------------------------
# Test: R-001 — /csetup detection of existing MCP servers
# ---------------------------------------------------------------------------

test_r001() {
  echo ""
  echo "=== R-001: /csetup detects existing MCP config ==="

  local csetup_skill="$REPO_DIR/skills/csetup/SKILL.md"

  # R-001: csetup SKILL.md must describe checking for existing .mcp.json
  file_contains "$csetup_skill" "\.mcp\.json" && local found_mcp="true" || local found_mcp="false"
  assert_eq "R-001: csetup mentions .mcp.json detection" "true" "$found_mcp"

  # R-001: csetup SKILL.md must mention Serena/Context7 already-configured detection
  file_contains_i "$csetup_skill" "serena.*already configured\|context7.*already configured\|already configured.*serena\|already configured.*context7" && local found_already="true" || local found_already="false"
  assert_eq "R-001: csetup mentions Serena/Context7 'already configured' check" "true" "$found_already"

  # R-001: csetup SKILL.md must mention checking for uv and npx binaries
  file_contains "$csetup_skill" "\`uv\`\|command.*uv\|uvx" && local found_uv="true" || local found_uv="false"
  assert_eq "R-001: csetup mentions uv detection" "true" "$found_uv"

  file_contains "$csetup_skill" "npx" && local found_npx="true" || local found_npx="false"
  assert_eq "R-001: csetup mentions npx detection" "true" "$found_npx"
}

# ---------------------------------------------------------------------------
# Test: R-002/R-003 — MCP offer flow in csetup
# ---------------------------------------------------------------------------

test_r002_r003() {
  echo ""
  echo "=== R-002/R-003: MCP offer and tooling prerequisites ==="

  local csetup_skill="$REPO_DIR/skills/csetup/SKILL.md"

  # R-002: csetup must present MCP as a decision with options
  file_contains_i "$csetup_skill" "serena.*context7\|both.*skip\|just serena.*just context7" && local found_offer="true" || local found_offer="false"
  assert_eq "R-002: csetup presents MCP offer with options" "true" "$found_offer"

  # R-003: csetup must mention not auto-installing uv
  file_contains_i "$csetup_skill" "install.*uv\|uv.*install" && local found_uv_install="true" || local found_uv_install="false"
  assert_eq "R-003: csetup mentions uv installation instructions" "true" "$found_uv_install"

  # R-003: csetup must explicitly state NOT to auto-install
  file_contains_i "$csetup_skill" "not.*install.*automatically\|NOT.*attempt.*install\|don.t.*install.*automatically\|user.*responsibility" && local found_no_auto="true" || local found_no_auto="false"
  assert_eq "R-003: csetup prohibits auto-installing uv/npx" "true" "$found_no_auto"
}

# ---------------------------------------------------------------------------
# Test: R-004 — .mcp.json merge behavior in csetup SKILL.md
# ---------------------------------------------------------------------------

test_r004() {
  echo ""
  echo "=== R-004: .mcp.json merge behavior ==="

  local csetup_skill="$REPO_DIR/skills/csetup/SKILL.md"

  # R-004: csetup must describe merging into existing mcpServers
  file_contains_i "$csetup_skill" "mcpServers\|merge.*mcp\|mcp.*merge" && local found_merge="true" || local found_merge="false"
  assert_eq "R-004: csetup describes .mcp.json merge behavior" "true" "$found_merge"

  # R-004: must mention never overwriting existing MCP/mcpServers entries
  file_contains_i "$csetup_skill" "mcpServers.*never.*overwrite\|mcpServers.*not.*overwrite\|existing.*mcpServers\|mcp.*existing.*entries" && local found_preserve="true" || local found_preserve="false"
  assert_eq "R-004: csetup says existing mcpServers entries are never overwritten" "true" "$found_preserve"
}

# ---------------------------------------------------------------------------
# Test: R-005 — .serena.yml creation described in csetup SKILL.md
# ---------------------------------------------------------------------------

test_r005() {
  echo ""
  echo "=== R-005: .serena.yml creation ==="

  local csetup_skill="$REPO_DIR/skills/csetup/SKILL.md"

  # R-005: csetup must describe creating .serena.yml
  file_contains "$csetup_skill" "\.serena\.yml" && local found_yml="true" || local found_yml="false"
  assert_eq "R-005: csetup describes .serena.yml creation" "true" "$found_yml"

  # R-005: must mention project_name, read_only, enable_memories
  file_contains "$csetup_skill" "project_name" && local found_pname="true" || local found_pname="false"
  assert_eq "R-005: csetup mentions project_name in .serena.yml" "true" "$found_pname"

  file_contains "$csetup_skill" "read_only: false" && local found_ro="true" || local found_ro="false"
  assert_eq "R-005: csetup specifies read_only: false in .serena.yml" "true" "$found_ro"

  file_contains "$csetup_skill" "enable_memories: true" && local found_mem="true" || local found_mem="false"
  assert_eq "R-005: csetup specifies enable_memories: true in .serena.yml" "true" "$found_mem"
}

# ---------------------------------------------------------------------------
# Test: R-006 — .gitignore update for .serena/
# ---------------------------------------------------------------------------

test_r006() {
  echo ""
  echo "=== R-006: .gitignore update for .serena/ ==="

  local csetup_skill="$REPO_DIR/skills/csetup/SKILL.md"

  file_contains "$csetup_skill" "\.serena/" && local found_gitignore="true" || local found_gitignore="false"
  assert_eq "R-006: csetup describes adding .serena/ to .gitignore" "true" "$found_gitignore"
}

# ---------------------------------------------------------------------------
# Test: R-007 — workflow-config.json mcp section
# ---------------------------------------------------------------------------

test_r007() {
  echo ""
  echo "=== R-007: workflow-config.json mcp section ==="

  local csetup_skill="$REPO_DIR/skills/csetup/SKILL.md"

  # R-007: csetup must describe writing mcp section to workflow-config.json
  file_contains "$csetup_skill" '"mcp"' && local found_mcp_section="true" || local found_mcp_section="false"
  assert_eq "R-007: csetup describes mcp section in workflow-config.json" "true" "$found_mcp_section"

  file_contains "$csetup_skill" '"serena": true' && local found_serena_true="true" || local found_serena_true="false"
  assert_eq "R-007: csetup describes serena: true flag" "true" "$found_serena_true"

  file_contains "$csetup_skill" '"context7": true' && local found_c7_true="true" || local found_c7_true="false"
  assert_eq "R-007: csetup describes context7: true flag" "true" "$found_c7_true"
}

# ---------------------------------------------------------------------------
# Test: R-008 — Skills check mcp.serena before Serena tool calls
# ---------------------------------------------------------------------------

test_r008() {
  echo ""
  echo "=== R-008: Skills check mcp.serena before Serena calls ==="

  for skill in $SERENA_SKILLS; do
    local skill_file="$REPO_DIR/skills/$skill/SKILL.md"
    if [ -f "$skill_file" ]; then
      file_contains "$skill_file" "mcp\.serena\|mcp.serena" && local found="true" || local found="false"
      assert_eq "R-008: $skill checks mcp.serena" "true" "$found"
    fi
  done
}

# ---------------------------------------------------------------------------
# Test: R-009 — Skills check mcp.context7 before Context7 tool calls
# ---------------------------------------------------------------------------

test_r009() {
  echo ""
  echo "=== R-009: Skills check mcp.context7 before Context7 calls ==="

  for skill in $CONTEXT7_SKILLS; do
    local skill_file="$REPO_DIR/skills/$skill/SKILL.md"
    if [ -f "$skill_file" ]; then
      file_contains "$skill_file" "mcp\.context7\|mcp.context7" && local found="true" || local found="false"
      assert_eq "R-009: $skill checks mcp.context7" "true" "$found"
    fi
  done
}

# ---------------------------------------------------------------------------
# Test: R-010 — Serena fallback table in each skill
# ---------------------------------------------------------------------------

test_r010() {
  echo ""
  echo "=== R-010: Serena fallback table in skills ==="

  for skill in $SERENA_SKILLS; do
    local skill_file="$REPO_DIR/skills/$skill/SKILL.md"
    if [ -f "$skill_file" ]; then
      # Each Serena skill must document the fallback mapping
      file_contains "$skill_file" "find_symbol" && local found_fs="true" || local found_fs="false"
      assert_eq "R-010: $skill has find_symbol fallback" "true" "$found_fs"

      file_contains "$skill_file" "find_referencing_symbols" && local found_frs="true" || local found_frs="false"
      assert_eq "R-010: $skill has find_referencing_symbols fallback" "true" "$found_frs"

      file_contains "$skill_file" "get_symbols_overview" && local found_gso="true" || local found_gso="false"
      assert_eq "R-010: $skill has get_symbols_overview fallback" "true" "$found_gso"

      file_contains "$skill_file" "replace_symbol_body" && local found_rsb="true" || local found_rsb="false"
      assert_eq "R-010: $skill has replace_symbol_body fallback" "true" "$found_rsb"

      file_contains "$skill_file" "search_for_pattern" && local found_sfp="true" || local found_sfp="false"
      assert_eq "R-010: $skill has search_for_pattern fallback" "true" "$found_sfp"
    fi
  done
}

# ---------------------------------------------------------------------------
# Test: R-011 — /cspec uses Context7 for research
# ---------------------------------------------------------------------------

test_r011() {
  echo ""
  echo "=== R-011: /cspec uses Context7 for research ==="

  local skill_file="$REPO_DIR/skills/cspec/SKILL.md"

  file_contains "$skill_file" "resolve-library-id" && local found_resolve="true" || local found_resolve="false"
  assert_eq "R-011: cspec mentions resolve-library-id" "true" "$found_resolve"

  file_contains "$skill_file" "get-library-docs" && local found_getdocs="true" || local found_getdocs="false"
  assert_eq "R-011: cspec mentions get-library-docs" "true" "$found_getdocs"
}

# ---------------------------------------------------------------------------
# Test: R-012 — /cverify uses Serena for traced coverage
# ---------------------------------------------------------------------------

test_r012() {
  echo ""
  echo "=== R-012: /cverify uses Serena for traced coverage ==="

  local skill_file="$REPO_DIR/skills/cverify/SKILL.md"

  file_contains "$skill_file" "find_referencing_symbols" && local found_frs="true" || local found_frs="false"
  assert_eq "R-012: cverify mentions find_referencing_symbols" "true" "$found_frs"

  file_contains_i "$skill_file" "serena.*traced.*coverage\|serena.*coverage.*matrix\|traced coverage.*serena" && local found_matrix="true" || local found_matrix="false"
  assert_eq "R-012: cverify mentions Serena traced coverage matrix" "true" "$found_matrix"
}

# ---------------------------------------------------------------------------
# Test: R-013 — /caudit specialists use Serena
# ---------------------------------------------------------------------------

test_r013() {
  echo ""
  echo "=== R-013: /caudit specialists use Serena ==="

  local skill_file="$REPO_DIR/skills/caudit/SKILL.md"

  # R-013: caudit must describe Serena usage for specialist agents
  file_contains_i "$skill_file" "serena" && local found_serena="true" || local found_serena="false"
  assert_eq "R-013: caudit mentions Serena for specialists" "true" "$found_serena"

  # Scoped to domain-specific symbols
  file_contains_i "$skill_file" "domain.*specific\|scoped.*domain" && local found_scoped="true" || local found_scoped="false"
  assert_eq "R-013: caudit Serena usage is domain-scoped" "true" "$found_scoped"
}

# ---------------------------------------------------------------------------
# Test: R-014 — Silent fallback on Serena failure
# ---------------------------------------------------------------------------

test_r014() {
  echo ""
  echo "=== R-014: Silent fallback on Serena failure ==="

  for skill in $SERENA_SKILLS; do
    local skill_file="$REPO_DIR/skills/$skill/SKILL.md"
    if [ -f "$skill_file" ]; then
      file_contains_i "$skill_file" "serena.*fall.back\|serena.*fallback\|fall.back.*serena\|fallback.*grep\|fall back.*text-based" && local found="true" || local found="false"
      assert_eq "R-014: $skill has Serena fallback instruction" "true" "$found"
    fi
  done
}

# ---------------------------------------------------------------------------
# Test: R-015 — End-of-run Serena failure notification
# ---------------------------------------------------------------------------

test_r015() {
  echo ""
  echo "=== R-015: End-of-run Serena failure notification ==="

  for skill in $SERENA_SKILLS; do
    local skill_file="$REPO_DIR/skills/$skill/SKILL.md"
    if [ -f "$skill_file" ]; then
      file_contains_i "$skill_file" "serena was unavailable\|end.*of.*run.*notif\|notify.*once.*end\|single.*notification.*end" && local found="true" || local found="false"
      assert_eq "R-015: $skill has end-of-run notification" "true" "$found"
    fi
  done
}

# ---------------------------------------------------------------------------
# Test: R-016 — Context7 failures follow same pattern
# ---------------------------------------------------------------------------

test_r016() {
  echo ""
  echo "=== R-016: Context7 failure fallback pattern ==="

  for skill in $CONTEXT7_SKILLS; do
    local skill_file="$REPO_DIR/skills/$skill/SKILL.md"
    if [ -f "$skill_file" ]; then
      # Context7 fallback to web search
      file_contains_i "$skill_file" "context7.*fallback\|context7.*web.*search\|web.*search.*context7\|context7.*unavailable" && local found="true" || local found="false"
      assert_eq "R-016: $skill has Context7 fallback instruction" "true" "$found"
    fi
  done
}

# ---------------------------------------------------------------------------
# Test: R-017 — MCP servers are optimizers, not dependencies
# ---------------------------------------------------------------------------

test_r017() {
  echo ""
  echo "=== R-017: MCP servers are optimizers, not dependencies ==="

  for skill in $SERENA_SKILLS; do
    local skill_file="$REPO_DIR/skills/$skill/SKILL.md"
    if [ -f "$skill_file" ]; then
      file_contains_i "$skill_file" "MCP.*not.*dependenc\|serena.*not.*dependenc\|optimizer.*not.*dependenc\|not.*dependenc.*MCP\|MCP.*optimizer" && local found="true" || local found="false"
      assert_eq "R-017: $skill treats MCP as optimizer not dependency" "true" "$found"
    fi
  done
}

# ---------------------------------------------------------------------------
# Test: R-018 — mcp section uses boolean values only
# ---------------------------------------------------------------------------

test_r018() {
  echo ""
  echo "=== R-018: mcp section uses boolean values only ==="

  local csetup_skill="$REPO_DIR/skills/csetup/SKILL.md"

  # R-018: csetup must describe mcp flags as booleans (feature flags)
  file_contains_i "$csetup_skill" "feature.flag\|boolean" && local found="true" || local found="false"
  assert_eq "R-018: csetup describes mcp flags as boolean feature flags" "true" "$found"
}

# ---------------------------------------------------------------------------
# Test: R-019 — Templates include mcp defaults
# ---------------------------------------------------------------------------

test_r019() {
  echo ""
  echo "=== R-019: Templates include mcp defaults ==="

  local lite_tmpl="$REPO_DIR/templates/workflow-config.json"
  local full_tmpl="$REPO_DIR/templates/workflow-config-full.json"

  # R-019: workflow-config.json template must have "mcp" section
  file_contains "$lite_tmpl" '"mcp"' && local found_lite="true" || local found_lite="false"
  assert_eq "R-019: workflow-config.json template has mcp section" "true" "$found_lite"

  # R-019: workflow-config-full.json template must have "mcp" section
  file_contains "$full_tmpl" '"mcp"' && local found_full="true" || local found_full="false"
  assert_eq "R-019: workflow-config-full.json template has mcp section" "true" "$found_full"

  # R-019: defaults must be serena: false, context7: false
  file_contains "$lite_tmpl" '"serena": false' && local found_s_lite="true" || local found_s_lite="false"
  assert_eq "R-019: lite template has serena: false default" "true" "$found_s_lite"

  file_contains "$lite_tmpl" '"context7": false' && local found_c_lite="true" || local found_c_lite="false"
  assert_eq "R-019: lite template has context7: false default" "true" "$found_c_lite"

  file_contains "$full_tmpl" '"serena": false' && local found_s_full="true" || local found_s_full="false"
  assert_eq "R-019: full template has serena: false default" "true" "$found_s_full"

  file_contains "$full_tmpl" '"context7": false' && local found_c_full="true" || local found_c_full="false"
  assert_eq "R-019: full template has context7: false default" "true" "$found_c_full"
}

# ---------------------------------------------------------------------------
# Test: R-020 — After sync, both distributions have MCP blocks
# ---------------------------------------------------------------------------

test_r020() {
  echo ""
  echo "=== R-020: Sync produces distributions with MCP blocks ==="

  # Check that Lite distribution skills with Serena have the MCP block
  local lite_serena_count=0
  local lite_serena_expected=0
  for skill in $SERENA_SKILLS; do
    local lite_skill="$REPO_DIR/correctless-lite/skills/$skill/SKILL.md"
    # Only count skills that exist in Lite (not all 14 are in Lite)
    if [ -f "$lite_skill" ]; then
      lite_serena_expected=$((lite_serena_expected + 1))
      if file_contains "$lite_skill" "mcp.serena"; then
        lite_serena_count=$((lite_serena_count + 1))
      fi
    fi
  done
  assert_eq "R-020: Lite has Serena blocks in all applicable skills" "$lite_serena_expected" "$lite_serena_count"

  # Check that Full distribution skills with Serena have the MCP block
  local full_serena_count=0
  local full_serena_expected=0
  for skill in $SERENA_SKILLS; do
    local full_skill="$REPO_DIR/correctless-full/skills/$skill/SKILL.md"
    if [ -f "$full_skill" ]; then
      full_serena_expected=$((full_serena_expected + 1))
      if file_contains "$full_skill" "mcp.serena"; then
        full_serena_count=$((full_serena_count + 1))
      fi
    fi
  done
  assert_eq "R-020: Full has Serena blocks in all 14 skills" "$full_serena_expected" "$full_serena_count"

  # Assert absolute skill counts in each distribution
  local lite_total full_total
  lite_total=$(find "$REPO_DIR/correctless-lite/skills" -name "SKILL.md" | wc -l)
  full_total=$(find "$REPO_DIR/correctless-full/skills" -name "SKILL.md" | wc -l)
  assert_eq "R-020: Lite has 16 skills total" "16" "$lite_total"
  assert_eq "R-020: Full has 23 skills total" "23" "$full_total"
}

# ---------------------------------------------------------------------------
# Test: R-021 — MCP is in both Lite and Full (not Full-only)
# ---------------------------------------------------------------------------

test_r021() {
  echo ""
  echo "=== R-021: MCP is in both distributions ==="

  # Check a specific Serena skill that exists in both: ctdd
  local lite_ctdd="$REPO_DIR/correctless-lite/skills/ctdd/SKILL.md"
  local full_ctdd="$REPO_DIR/correctless-full/skills/ctdd/SKILL.md"

  file_contains "$lite_ctdd" "mcp.serena" && local lite_has="true" || local lite_has="false"
  assert_eq "R-021: Lite ctdd has Serena block" "true" "$lite_has"

  file_contains "$full_ctdd" "mcp.serena" && local full_has="true" || local full_has="false"
  assert_eq "R-021: Full ctdd has Serena block" "true" "$full_has"

  # Context7: cspec exists in both
  local lite_cspec="$REPO_DIR/correctless-lite/skills/cspec/SKILL.md"
  local full_cspec="$REPO_DIR/correctless-full/skills/cspec/SKILL.md"

  file_contains "$lite_cspec" "mcp.context7" && local lite_c7="true" || local lite_c7="false"
  assert_eq "R-021: Lite cspec has Context7 block" "true" "$lite_c7"

  file_contains "$full_cspec" "mcp.context7" && local full_c7="true" || local full_c7="false"
  assert_eq "R-021: Full cspec has Context7 block" "true" "$full_c7"
}

# ---------------------------------------------------------------------------
# Test: R-022 — Exactly 14 skills have Serena blocks
# ---------------------------------------------------------------------------

test_r022() {
  echo ""
  echo "=== R-022: Exactly 14 skills have Serena blocks ==="

  local serena_count=0
  for skill in $SERENA_SKILLS; do
    local skill_file="$REPO_DIR/skills/$skill/SKILL.md"
    if [ -f "$skill_file" ] && file_contains "$skill_file" "mcp\.serena\|mcp.serena"; then
      serena_count=$((serena_count + 1))
    fi
  done
  assert_eq "R-022: 14 skills have Serena blocks" "14" "$serena_count"
}

# ---------------------------------------------------------------------------
# Test: R-023 — Exactly 2 skills have Context7 blocks
# ---------------------------------------------------------------------------

test_r023() {
  echo ""
  echo "=== R-023: Exactly 2 skills have Context7 blocks ==="

  local c7_count=0
  for skill in $CONTEXT7_SKILLS; do
    local skill_file="$REPO_DIR/skills/$skill/SKILL.md"
    if [ -f "$skill_file" ] && file_contains_i "$skill_file" "context7"; then
      c7_count=$((c7_count + 1))
    fi
  done
  assert_eq "R-023: 2 skills have Context7 blocks" "2" "$c7_count"

  # Serena-only skills (all SERENA_SKILLS minus cspec and cdebug) must NOT contain mcp.context7
  for skill in $SERENA_SKILLS; do
    # Skip cspec and cdebug — they legitimately have Context7
    if [ "$skill" = "cspec" ] || [ "$skill" = "cdebug" ]; then
      continue
    fi
    local skill_file="$REPO_DIR/skills/$skill/SKILL.md"
    if [ -f "$skill_file" ]; then
      file_contains "$skill_file" "mcp\.context7\|mcp.context7" && local has_c7="true" || local has_c7="false"
      assert_eq "R-023: $skill does NOT have mcp.context7" "false" "$has_c7"
    fi
  done
}

# ---------------------------------------------------------------------------
# Test: R-024 — Excluded skills do NOT have MCP blocks
# ---------------------------------------------------------------------------

test_r024() {
  echo ""
  echo "=== R-024: Excluded skills do NOT have MCP blocks ==="

  for skill in $NO_MCP_SKILLS; do
    local skill_file="$REPO_DIR/skills/$skill/SKILL.md"
    if [ -f "$skill_file" ]; then
      # These skills must NOT contain Serena integration blocks
      # (checking for the mcp.serena config check pattern, not incidental mentions)
      file_contains "$skill_file" "mcp\.serena\|mcp.serena" && local found="true" || local found="false"
      assert_eq "R-024: $skill does NOT have mcp.serena check" "false" "$found"
    fi
  done
}

# ---------------------------------------------------------------------------
# Test: R-025 — Invalid JSON handling in csetup
# ---------------------------------------------------------------------------

test_r025() {
  echo ""
  echo "=== R-025: Invalid .mcp.json handling ==="

  local csetup_skill="$REPO_DIR/skills/csetup/SKILL.md"

  # R-025: csetup must describe handling invalid JSON in .mcp.json
  file_contains_i "$csetup_skill" "valid JSON\|invalid JSON\|isn.*t valid JSON\|not valid JSON" && local found_invalid="true" || local found_invalid="false"
  assert_eq "R-025: csetup describes invalid .mcp.json handling" "true" "$found_invalid"

  # R-025: must say it won't modify/overwrite the corrupt file
  file_contains_i "$csetup_skill" "won.*t modify\|skip.*MCP\|skip.*config.*writ" && local found_skip="true" || local found_skip="false"
  assert_eq "R-025: csetup skips MCP config on invalid JSON" "true" "$found_skip"
}

# ---------------------------------------------------------------------------
# Test: R-026 — Key presence check (not value) for existing config
# ---------------------------------------------------------------------------

test_r026() {
  echo ""
  echo "=== R-026: Key presence check for MCP config ==="

  local csetup_skill="$REPO_DIR/skills/csetup/SKILL.md"

  # R-026: csetup must describe checking key presence, not value
  file_contains_i "$csetup_skill" "key.*presence.*not.*value\|presence.*not.*its.*value\|checks.*presence\|check.*key.*presence" && local found_presence="true" || local found_presence="false"
  assert_eq "R-026: csetup checks key presence, not value" "true" "$found_presence"

  # R-026: must mention not overwriting custom config
  file_contains_i "$csetup_skill" "custom.*config\|custom.*args\|not.*overwrite\|should not.*overwrite" && local found_custom="true" || local found_custom="false"
  assert_eq "R-026: csetup does not overwrite custom MCP config" "true" "$found_custom"
}

# ---------------------------------------------------------------------------
# Run all tests
# ---------------------------------------------------------------------------

echo "Correctless MCP Integration Tests"
echo "=================================="

test_r001
test_r002_r003
test_r004
test_r005
test_r006
test_r007
test_r008
test_r009
test_r010
test_r011
test_r012
test_r013
test_r014
test_r015
test_r016
test_r017
test_r018
test_r019
test_r020
test_r021
test_r022
test_r023
test_r024
test_r025
test_r026

echo ""
echo "=================================="
echo "Results: $PASS passed, $FAIL failed"
echo ""

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
