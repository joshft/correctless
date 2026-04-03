#!/usr/bin/env bash
# Correctless — cexplain test suite
# Tests spec rules R-001 through R-019 from
# docs/specs/add-cexplain-skill-for-guided-codebase-exploration.md
# Run from repo root: bash test-cexplain.sh

set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="/tmp/correctless-cexplain-test-$$"
PASS=0
FAIL=0

# ---------------------------------------------------------------------------
# Helpers (matching test.sh / test-crelease.sh style)
# ---------------------------------------------------------------------------

setup_test_project() {
  rm -rf "$TEST_DIR"
  mkdir -p "$TEST_DIR"
  cd "$TEST_DIR" || exit
  git init -q
  git branch -M main
  echo '{"name": "test-app", "version": "1.0.0", "scripts": {"test": "echo PASS && exit 0"}}' > package.json
  echo 'export function hello() {}' > index.ts
  git add -A && git commit -q -m "init"

  # Install correctless (exclude .git to avoid nested repo confusion)
  mkdir -p .claude/skills/workflow
  rsync -a --exclude='.git' --exclude='tests' "$REPO_DIR/" .claude/skills/workflow/
}

cleanup() {
  rm -rf "$TEST_DIR"
}

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

assert_not_contains() {
  local desc="$1" unexpected="$2" actual="$3"
  if echo "$actual" | grep -q "$unexpected"; then
    echo "  FAIL: $desc (output should NOT contain '$unexpected')"
    FAIL=$((FAIL + 1))
  else
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  fi
}

# Check if a file contains a pattern (returns 0 if found)
file_contains() {
  grep -q "$2" "$1" 2>/dev/null
}

# Check if a file does NOT contain a pattern (returns 0 if not found)
file_not_contains() {
  ! grep -q "$2" "$1" 2>/dev/null
}

# ---------------------------------------------------------------------------
# Test: R-011 — SKILL.md exists and is registered
# ---------------------------------------------------------------------------

test_r011_skill_exists() {
  echo ""
  echo "=== R-011: SKILL.md exists and is registered ==="

  # Tests R-011 [integration]: SKILL.md at skills/cexplain/SKILL.md
  local skill_file="$REPO_DIR/skills/cexplain/SKILL.md"
  assert_eq "R-011: skills/cexplain/SKILL.md exists" "true" \
    "$([ -f "$skill_file" ] && echo true || echo false)"

  # SKILL.md should NOT be a stub — it should have real content
  file_not_contains "$skill_file" "STUB:TDD" \
    && local not_stub="true" || local not_stub="false"
  assert_eq "R-011: SKILL.md is not a stub" "true" "$not_stub"

  # SKILL.md should have correct frontmatter
  file_contains "$skill_file" "^name: cexplain" \
    && local has_name="true" || local has_name="false"
  assert_eq "R-011: SKILL.md has name: cexplain in frontmatter" "true" "$has_name"

  # Tests R-011 [integration]: registered in sync.sh for Lite
  local sync_file="$REPO_DIR/sync.sh"
  file_contains "$sync_file" "cexplain" \
    && local in_sync="true" || local in_sync="false"
  assert_eq "R-011: cexplain registered in sync.sh" "true" "$in_sync"

  # Check Lite skill list specifically
  grep -q 'for skill in.*cexplain' "$sync_file" 2>/dev/null \
    && local in_lite_loop="true" || local in_lite_loop="false"
  assert_eq "R-011: cexplain in sync.sh Lite skill loop" "true" "$in_lite_loop"

  # Check both Lite and Full for-loops contain cexplain
  local cexplain_count
  cexplain_count="$(grep -c 'cexplain' "$sync_file" 2>/dev/null || true)"
  cexplain_count="${cexplain_count:-0}"
  # Should appear at least twice (once per distribution)
  assert_eq "R-011: cexplain in both Lite and Full sync lists (appears 2+ times)" "true" \
    "$([ "$cexplain_count" -ge 2 ] 2>/dev/null && echo true || echo false)"

  # Tests R-011 [integration]: documented in docs/skills/cexplain.md
  local docs_file="$REPO_DIR/docs/skills/cexplain.md"
  assert_eq "R-011: docs/skills/cexplain.md exists" "true" \
    "$([ -f "$docs_file" ] && echo true || echo false)"

  # Docs file should NOT be a stub
  file_not_contains "$docs_file" "STUB:TDD" \
    && local docs_not_stub="true" || local docs_not_stub="false"
  assert_eq "R-011: docs/skills/cexplain.md is not a stub" "true" "$docs_not_stub"

  # Tests R-011 [integration]: in README skills table
  local readme_file="$REPO_DIR/README.md"
  file_contains "$readme_file" "/cexplain" \
    && local in_readme="true" || local in_readme="false"
  assert_eq "R-011: /cexplain in README.md skills table" "true" "$in_readme"

  # README should list cexplain under Observability section
  file_contains "$readme_file" "docs/skills/cexplain.md" \
    && local readme_links="true" || local readme_links="false"
  assert_eq "R-011: README links to docs/skills/cexplain.md" "true" "$readme_links"
}

# ---------------------------------------------------------------------------
# Test: SKILL.md structural integrity (prevents keyword-stuffing)
# ---------------------------------------------------------------------------

test_skill_structure() {
  echo ""
  echo "=== Structural: SKILL.md has organized sections ==="

  local skill="$REPO_DIR/skills/cexplain/SKILL.md"

  # SKILL.md must have substantive content (not a keyword dump)
  local line_count
  line_count="$(wc -l < "$skill" 2>/dev/null || echo 0)"
  assert_eq "Structure: SKILL.md has at least 100 lines" "true" \
    "$([ "$line_count" -ge 100 ] && echo true || echo false)"

  # SKILL.md must have organized sections (at least 8 ## headings)
  local heading_count
  heading_count="$(grep -c '^## ' "$skill" 2>/dev/null | tr -d '[:space:]')"
  heading_count="${heading_count:-0}"
  assert_eq "Structure: SKILL.md has at least 8 ## section headings" "true" \
    "$([ "$heading_count" -ge 8 ] && echo true || echo false)"

  # Key skill phases must have their own sections
  grep -q '^##.*[Oo]verview\|^##.*[Ss]can\|^##.*[Pp]roject.*[Ss]can' "$skill" 2>/dev/null \
    && local has_overview_section="true" || local has_overview_section="false"
  assert_eq "Structure: SKILL.md has overview/scan section" "true" "$has_overview_section"

  grep -q '^##.*[Ee]xploration.*[Mm]enu\|^##.*[Mm]enu\|^##.*[Oo]ption' "$skill" 2>/dev/null \
    && local has_menu_section="true" || local has_menu_section="false"
  assert_eq "Structure: SKILL.md has exploration menu section" "true" "$has_menu_section"

  grep -q '^##.*[Dd]iagram\|^##.*[Mm]ermaid' "$skill" 2>/dev/null \
    && local has_diagram_section="true" || local has_diagram_section="false"
  assert_eq "Structure: SKILL.md has diagrams section" "true" "$has_diagram_section"

  grep -q '^##.*HTML.*[Ee]xport\|^##.*[Ee]xport' "$skill" 2>/dev/null \
    && local has_export_section="true" || local has_export_section="false"
  assert_eq "Structure: SKILL.md has HTML export section" "true" "$has_export_section"

  grep -q '^##.*[Ss]erena\|^##.*MCP' "$skill" 2>/dev/null \
    && local has_serena_section="true" || local has_serena_section="false"
  assert_eq "Structure: SKILL.md has Serena/MCP section" "true" "$has_serena_section"
}

# ---------------------------------------------------------------------------
# Test: R-001 — Project overview scan
# ---------------------------------------------------------------------------

test_r001_overview_scan() {
  echo ""
  echo "=== R-001: Project overview scan ==="

  local skill="$REPO_DIR/skills/cexplain/SKILL.md"

  # Tests R-001 [integration]: scans and presents project overview
  file_contains "$skill" "[Oo]verview" \
    && local has_overview="true" || local has_overview="false"
  assert_eq "R-001: SKILL.md mentions overview" "true" "$has_overview"

  file_contains "$skill" "[Ss]can" \
    && local has_scan="true" || local has_scan="false"
  assert_eq "R-001: SKILL.md mentions scan" "true" "$has_scan"

  # Tests R-001: overview includes project name
  file_contains "$skill" "project name" \
    && local has_name="true" || local has_name="false"
  assert_eq "R-001: SKILL.md mentions project name" "true" "$has_name"

  # Tests R-001: overview includes language(s)
  file_contains "$skill" "language" \
    && local has_lang="true" || local has_lang="false"
  assert_eq "R-001: SKILL.md mentions language" "true" "$has_lang"

  # Tests R-001: overview includes approximate LOC
  file_contains "$skill" "LOC\|lines of code" \
    && local has_loc="true" || local has_loc="false"
  assert_eq "R-001: SKILL.md mentions LOC" "true" "$has_loc"

  # Tests R-001: overview includes major components list
  file_contains "$skill" "component" \
    && local has_components="true" || local has_components="false"
  assert_eq "R-001: SKILL.md mentions components" "true" "$has_components"

  # Tests R-001: reads AGENT_CONTEXT.md
  file_contains "$skill" "AGENT_CONTEXT" \
    && local has_agent_ctx="true" || local has_agent_ctx="false"
  assert_eq "R-001: SKILL.md mentions AGENT_CONTEXT" "true" "$has_agent_ctx"

  # Tests R-001: reads ARCHITECTURE.md
  file_contains "$skill" "ARCHITECTURE" \
    && local has_arch="true" || local has_arch="false"
  assert_eq "R-001: SKILL.md mentions ARCHITECTURE" "true" "$has_arch"

  # A-1 fix: one-sentence purpose and 3-7 component count
  file_contains "$skill" "purpose" \
    && local has_purpose="true" || local has_purpose="false"
  assert_eq "R-001: SKILL.md mentions purpose in overview" "true" "$has_purpose"

  file_contains "$skill" "3-7\|3 to 7\|three to seven" \
    && local has_count="true" || local has_count="false"
  assert_eq "R-001: SKILL.md specifies 3-7 component count" "true" "$has_count"
}

# ---------------------------------------------------------------------------
# Test: R-002 — Exploration menu driven by structural signals
# ---------------------------------------------------------------------------

test_r002_exploration_menu() {
  echo ""
  echo "=== R-002: Exploration menu driven by structural signals ==="

  local skill="$REPO_DIR/skills/cexplain/SKILL.md"

  # Tests R-002 [integration]: structural signal detection
  file_contains "$skill" "structural signal" \
    && local has_signals="true" || local has_signals="false"
  assert_eq "R-002: SKILL.md mentions structural signals" "true" "$has_signals"

  # Tests R-002: HTTP handlers detection
  file_contains "$skill" "HTTP handler\|HTTP.*handler\|router\|middleware" \
    && local has_http="true" || local has_http="false"
  assert_eq "R-002: SKILL.md mentions HTTP handlers" "true" "$has_http"

  # Tests R-002: cmd/ directory / CLI detection
  file_contains "$skill" "cmd/" \
    && local has_cmd="true" || local has_cmd="false"
  assert_eq "R-002: SKILL.md mentions cmd/ directory" "true" "$has_cmd"

  # Tests R-002: cross-imports detection for component dependencies
  file_contains "$skill" "cross-import" \
    && local has_cross="true" || local has_cross="false"
  assert_eq "R-002: SKILL.md mentions cross-imports" "true" "$has_cross"

  # Tests R-002: trust boundaries detection
  file_contains "$skill" "trust boundar" \
    && local has_trust="true" || local has_trust="false"
  assert_eq "R-002: SKILL.md mentions trust boundaries" "true" "$has_trust"

  # Tests R-002: API surface detection
  file_contains "$skill" "API surface" \
    && local has_api="true" || local has_api="false"
  assert_eq "R-002: SKILL.md mentions API surface" "true" "$has_api"

  # Tests R-002: always offers deep dive option
  file_contains "$skill" "[Dd]eep dive" \
    && local has_deep="true" || local has_deep="false"
  assert_eq "R-002: SKILL.md mentions deep dive" "true" "$has_deep"

  # Tests R-002: always offers HTML export option
  file_contains "$skill" "HTML export" \
    && local has_html="true" || local has_html="false"
  assert_eq "R-002: SKILL.md mentions HTML export option" "true" "$has_html"

  # Tests R-002: free text escape hatch
  file_contains "$skill" "free text\|free-text" \
    && local has_freetext="true" || local has_freetext="false"
  assert_eq "R-002: SKILL.md mentions free text escape hatch" "true" "$has_freetext"

  # A-2 fix: actual menu option names
  file_contains "$skill" "request lifecycle" \
    && local has_reqlife="true" || local has_reqlife="false"
  assert_eq "R-002: SKILL.md mentions 'request lifecycle' option" "true" "$has_reqlife"

  file_contains "$skill" "command flow" \
    && local has_cmdflow="true" || local has_cmdflow="false"
  assert_eq "R-002: SKILL.md mentions 'command flow' option" "true" "$has_cmdflow"

  file_contains "$skill" "component dependency" \
    && local has_compdep="true" || local has_compdep="false"
  assert_eq "R-002: SKILL.md mentions 'component dependency' option" "true" "$has_compdep"
}

# ---------------------------------------------------------------------------
# Test: R-003 — Mermaid diagram + prose walkthrough per exploration
# ---------------------------------------------------------------------------

test_r003_diagram_and_prose() {
  echo ""
  echo "=== R-003: Mermaid diagram + prose walkthrough ==="

  local skill="$REPO_DIR/skills/cexplain/SKILL.md"

  # Tests R-003 [integration]: produces mermaid diagrams
  file_contains "$skill" "[Mm]ermaid" \
    && local has_mermaid="true" || local has_mermaid="false"
  assert_eq "R-003: SKILL.md mentions mermaid" "true" "$has_mermaid"

  # Tests R-003: produces prose walkthrough
  file_contains "$skill" "prose.*walkthrough\|prose walkthrough\|walkthrough" \
    && local has_prose="true" || local has_prose="false"
  assert_eq "R-003: SKILL.md mentions prose walkthrough" "true" "$has_prose"

  # Tests R-003: offers follow-up options after each answer
  file_contains "$skill" "follow-up" \
    && local has_followup="true" || local has_followup="false"
  assert_eq "R-003: SKILL.md mentions follow-up options" "true" "$has_followup"

  # Tests R-003: back to overview option
  file_contains "$skill" "[Bb]ack to overview" \
    && local has_back="true" || local has_back="false"
  assert_eq "R-003: SKILL.md mentions back to overview" "true" "$has_back"

  # QA-006 fix: Export to HTML follow-up option
  file_contains "$skill" "[Ee]xport to HTML" \
    && local has_export_followup="true" || local has_export_followup="false"
  assert_eq "R-003: SKILL.md mentions Export to HTML as follow-up option" "true" "$has_export_followup"

  # A-3 fix: numeric constraints for prose and follow-ups
  file_contains "$skill" "2-5 paragraph\|2 to 5 paragraph" \
    && local has_prose_count="true" || local has_prose_count="false"
  assert_eq "R-003: SKILL.md specifies 2-5 paragraphs of prose" "true" "$has_prose_count"

  file_contains "$skill" "2-4 follow-up\|2 to 4 follow-up\|2-4.*follow" \
    && local has_followup_count="true" || local has_followup_count="false"
  assert_eq "R-003: SKILL.md specifies 2-4 follow-up options" "true" "$has_followup_count"
}

# ---------------------------------------------------------------------------
# Test: R-004 — Uncertainty markers and confidence
# ---------------------------------------------------------------------------

test_r004_uncertainty() {
  echo ""
  echo "=== R-004: Uncertainty markers and confidence ==="

  local skill="$REPO_DIR/skills/cexplain/SKILL.md"

  # Tests R-004 [integration]: uncertainty markers
  file_contains "$skill" "[Uu]ncertainty" \
    && local has_uncertainty="true" || local has_uncertainty="false"
  assert_eq "R-004: SKILL.md mentions uncertainty" "true" "$has_uncertainty"

  # Tests R-004: confidence line
  file_contains "$skill" "[Cc]onfidence" \
    && local has_confidence="true" || local has_confidence="false"
  assert_eq "R-004: SKILL.md mentions confidence" "true" "$has_confidence"

  # Tests R-004: traced connections
  file_contains "$skill" "traced" \
    && local has_traced="true" || local has_traced="false"
  assert_eq "R-004: SKILL.md mentions traced connections" "true" "$has_traced"

  # Tests R-004: inferred connections
  file_contains "$skill" "inferred" \
    && local has_inferred="true" || local has_inferred="false"
  assert_eq "R-004: SKILL.md mentions inferred connections" "true" "$has_inferred"

  # Tests R-004: "could not be traced" phrasing
  file_contains "$skill" "could not be traced" \
    && local has_not_traced="true" || local has_not_traced="false"
  assert_eq "R-004: SKILL.md mentions 'could not be traced'" "true" "$has_not_traced"

  # QA-005 class fix: anti-negation check for confidence markers
  file_not_contains "$skill" "[Nn]ever.*[Cc]onfidence\|[Dd]o not.*[Cc]onfidence" \
    && local no_neg_conf="true" || local no_neg_conf="false"
  assert_eq "R-004: SKILL.md does not negate confidence markers" "true" "$no_neg_conf"
}

# ---------------------------------------------------------------------------
# Test: R-005 — HTML export output
# ---------------------------------------------------------------------------

test_r005_html_export() {
  echo ""
  echo "=== R-005: HTML export output ==="

  local skill="$REPO_DIR/skills/cexplain/SKILL.md"

  # Tests R-005 [integration]: HTML output
  file_contains "$skill" "HTML" \
    && local has_html="true" || local has_html="false"
  assert_eq "R-005: SKILL.md mentions HTML" "true" "$has_html"

  # Tests R-005: self-contained HTML
  file_contains "$skill" "self-contained" \
    && local has_selfcontained="true" || local has_selfcontained="false"
  assert_eq "R-005: SKILL.md mentions self-contained" "true" "$has_selfcontained"

  # Tests R-005: disclaimer banner
  file_contains "$skill" "disclaimer" \
    && local has_disclaimer="true" || local has_disclaimer="false"
  assert_eq "R-005: SKILL.md mentions disclaimer" "true" "$has_disclaimer"

  # Tests R-005: best-effort qualifier
  file_contains "$skill" "best-effort\|best effort" \
    && local has_besteffort="true" || local has_besteffort="false"
  assert_eq "R-005: SKILL.md mentions best-effort" "true" "$has_besteffort"

  # Tests R-005: table of contents
  file_contains "$skill" "table of contents" \
    && local has_toc="true" || local has_toc="false"
  assert_eq "R-005: SKILL.md mentions table of contents" "true" "$has_toc"

  # Tests R-005: mermaid.js CDN
  file_contains "$skill" "mermaid.js CDN\|mermaid.*CDN\|CDN.*mermaid" \
    && local has_cdn="true" || local has_cdn="false"
  assert_eq "R-005: SKILL.md mentions mermaid.js CDN" "true" "$has_cdn"

  # Tests R-005: output path .correctless/artifacts/cexplain
  file_contains "$skill" "\.correctless/artifacts/cexplain" \
    && local has_path="true" || local has_path="false"
  assert_eq "R-005: SKILL.md mentions .correctless/artifacts/cexplain output path" "true" "$has_path"

  # B-1 fix: R-005 must describe incremental vs snapshot behavior
  file_contains "$skill" "[Ii]ncremental" \
    && local has_incremental="true" || local has_incremental="false"
  assert_eq "R-005: SKILL.md describes incremental HTML mode behavior" "true" "$has_incremental"

  file_contains "$skill" "[Ss]napshot" \
    && local has_snapshot="true" || local has_snapshot="false"
  assert_eq "R-005: SKILL.md describes snapshot terminal mode behavior" "true" "$has_snapshot"
}

# ---------------------------------------------------------------------------
# Test: R-006 — Serena MCP integration with fallback
# ---------------------------------------------------------------------------

test_r006_serena_mcp() {
  echo ""
  echo "=== R-006: Serena MCP integration with fallback ==="

  local skill="$REPO_DIR/skills/cexplain/SKILL.md"

  # Tests R-006 [integration]: Serena integration
  file_contains "$skill" "[Ss]erena" \
    && local has_serena="true" || local has_serena="false"
  assert_eq "R-006: SKILL.md mentions Serena" "true" "$has_serena"

  # Tests R-006: get_code_map
  file_contains "$skill" "get_code_map" \
    && local has_codemap="true" || local has_codemap="false"
  assert_eq "R-006: SKILL.md mentions get_code_map" "true" "$has_codemap"

  # Tests R-006: find_symbol
  file_contains "$skill" "find_symbol" \
    && local has_findsym="true" || local has_findsym="false"
  assert_eq "R-006: SKILL.md mentions find_symbol" "true" "$has_findsym"

  # Tests R-006: find_referencing_symbols
  file_contains "$skill" "find_referencing_symbols" \
    && local has_refsym="true" || local has_refsym="false"
  assert_eq "R-006: SKILL.md mentions find_referencing_symbols" "true" "$has_refsym"

  # Tests R-006: fallback behavior
  file_contains "$skill" "[Ff]allback" \
    && local has_fallback="true" || local has_fallback="false"
  assert_eq "R-006: SKILL.md mentions fallback" "true" "$has_fallback"

  # Tests R-006: grep fallback
  file_contains "$skill" "grep" \
    && local has_grep="true" || local has_grep="false"
  assert_eq "R-006: SKILL.md mentions grep fallback" "true" "$has_grep"

  # Tests R-006: directory listing fallback
  file_contains "$skill" "directory listing\|directory structure" \
    && local has_dirlist="true" || local has_dirlist="false"
  assert_eq "R-006: SKILL.md mentions directory listing fallback" "true" "$has_dirlist"

  # A-4 fix: search_for_pattern Serena tool
  file_contains "$skill" "search_for_pattern" \
    && local has_searchpat="true" || local has_searchpat="false"
  assert_eq "R-006: SKILL.md mentions search_for_pattern" "true" "$has_searchpat"

  # A-4 fix: silent fallback behavior
  file_contains "$skill" "[Ss]ilent\|[Dd]o not warn\|[Dd]o not abort" \
    && local has_silent="true" || local has_silent="false"
  assert_eq "R-006: SKILL.md specifies silent fallback (no warnings mid-operation)" "true" "$has_silent"

  # QA-003 fix: do not retry instruction
  file_contains "$skill" "do not retry" \
    && local has_no_retry="true" || local has_no_retry="false"
  assert_eq "R-006: SKILL.md specifies do not retry on Serena failure" "true" "$has_no_retry"
}

# ---------------------------------------------------------------------------
# Test: R-007 — Valid mermaid diagram syntax
# ---------------------------------------------------------------------------

test_r007_mermaid_syntax() {
  echo ""
  echo "=== R-007: Valid mermaid diagram syntax ==="

  local skill="$REPO_DIR/skills/cexplain/SKILL.md"

  # Tests R-007 [unit]: valid mermaid syntax instruction
  file_contains "$skill" "valid mermaid\|valid.*mermaid.*syntax" \
    && local has_valid="true" || local has_valid="false"
  assert_eq "R-007: SKILL.md mentions valid mermaid syntax" "true" "$has_valid"

  # Tests R-007: sequenceDiagram type
  file_contains "$skill" "sequenceDiagram" \
    && local has_sequence="true" || local has_sequence="false"
  assert_eq "R-007: SKILL.md mentions sequenceDiagram" "true" "$has_sequence"

  # Tests R-007: graph type
  file_contains "$skill" "graph" \
    && local has_graph="true" || local has_graph="false"
  assert_eq "R-007: SKILL.md mentions graph diagram type" "true" "$has_graph"

  # Tests R-007: classDiagram type
  file_contains "$skill" "classDiagram" \
    && local has_class="true" || local has_class="false"
  assert_eq "R-007: SKILL.md mentions classDiagram" "true" "$has_class"

  # Tests R-007: stateDiagram type
  file_contains "$skill" "stateDiagram" \
    && local has_state="true" || local has_state="false"
  assert_eq "R-007: SKILL.md mentions stateDiagram" "true" "$has_state"

  # Tests R-007: 30 node limit
  file_contains "$skill" "30 node\|30-node" \
    && local has_limit="true" || local has_limit="false"
  assert_eq "R-007: SKILL.md mentions 30 node limit" "true" "$has_limit"

  # A-5 fix: fenced code block instruction
  file_contains "$skill" "fenced code block\|code block.*mermaid\|mermaid.*language tag" \
    && local has_fenced="true" || local has_fenced="false"
  assert_eq "R-007: SKILL.md mentions fenced code block with mermaid tag" "true" "$has_fenced"
}

# ---------------------------------------------------------------------------
# Test: R-008 — Project type detection from signals
# ---------------------------------------------------------------------------

test_r008_project_detection() {
  echo ""
  echo "=== R-008: Project type detection from signals ==="

  local skill="$REPO_DIR/skills/cexplain/SKILL.md"

  # Tests R-008 [integration]: HTTP handler signal
  file_contains "$skill" "HTTP handler\|HTTP.*handler" \
    && local has_http="true" || local has_http="false"
  assert_eq "R-008: SKILL.md mentions HTTP handlers signal" "true" "$has_http"

  # Tests R-008: CLI signal
  file_contains "$skill" "CLI" \
    && local has_cli="true" || local has_cli="false"
  assert_eq "R-008: SKILL.md mentions CLI signal" "true" "$has_cli"

  # Tests R-008: library signal
  file_contains "$skill" "[Ll]ibrary" \
    && local has_lib="true" || local has_lib="false"
  assert_eq "R-008: SKILL.md mentions library signal" "true" "$has_lib"

  # Tests R-008: monorepo signal
  file_contains "$skill" "[Mm]onorepo" \
    && local has_mono="true" || local has_mono="false"
  assert_eq "R-008: SKILL.md mentions monorepo signal" "true" "$has_mono"

  # Tests R-008: not a classifier — uses signals
  file_contains "$skill" "not a classifier\|signal" \
    && local has_notclass="true" || local has_notclass="false"
  assert_eq "R-008: SKILL.md mentions signals-based detection (not a classifier)" "true" "$has_notclass"
}

# ---------------------------------------------------------------------------
# Test: R-009 — Stateless across sessions
# ---------------------------------------------------------------------------

test_r009_stateless() {
  echo ""
  echo "=== R-009: Stateless across sessions ==="

  local skill="$REPO_DIR/skills/cexplain/SKILL.md"

  # Tests R-009 [unit]: stateless across sessions
  file_contains "$skill" "[Ss]tateless" \
    && local has_stateless="true" || local has_stateless="false"
  assert_eq "R-009: SKILL.md mentions stateless" "true" "$has_stateless"

  # Tests R-009: fresh start each invocation
  file_contains "$skill" "[Ff]resh" \
    && local has_fresh="true" || local has_fresh="false"
  assert_eq "R-009: SKILL.md mentions fresh start" "true" "$has_fresh"

  # Tests R-009: no persistence between sessions
  file_contains "$skill" "[Nn]o.*persist\|not.*persist\|no persistence" \
    && local has_nopersist="true" || local has_nopersist="false"
  assert_eq "R-009: SKILL.md mentions no persistence" "true" "$has_nopersist"

  # Tests R-009: maintains context within a session
  file_contains "$skill" "within a session\|within.*session" \
    && local has_session="true" || local has_session="false"
  assert_eq "R-009: SKILL.md mentions within a session context" "true" "$has_session"
}

# ---------------------------------------------------------------------------
# Test: R-010 — Deep dive functionality
# ---------------------------------------------------------------------------

test_r010_deep_dive() {
  echo ""
  echo "=== R-010: Deep dive functionality ==="

  local skill="$REPO_DIR/skills/cexplain/SKILL.md"

  # Tests R-010 [integration]: deep dive into file
  file_contains "$skill" "deep dive.*file\|file.*deep dive\|[Dd]eep dive" \
    && local has_file="true" || local has_file="false"
  assert_eq "R-010: SKILL.md mentions deep dive into file" "true" "$has_file"

  # Tests R-010: deep dive into directory
  file_contains "$skill" "directory" \
    && local has_dir="true" || local has_dir="false"
  assert_eq "R-010: SKILL.md mentions deep dive into directory" "true" "$has_dir"

  # Tests R-010: deep dive into concept
  file_contains "$skill" "concept" \
    && local has_concept="true" || local has_concept="false"
  assert_eq "R-010: SKILL.md mentions deep dive into concept" "true" "$has_concept"

  # Tests R-010: shows imports
  file_contains "$skill" "import" \
    && local has_imports="true" || local has_imports="false"
  assert_eq "R-010: SKILL.md mentions imports" "true" "$has_imports"

  # Tests R-010: call graph
  file_contains "$skill" "call graph" \
    && local has_callgraph="true" || local has_callgraph="false"
  assert_eq "R-010: SKILL.md mentions call graph" "true" "$has_callgraph"

  # Tests R-010: cross-cutting view
  file_contains "$skill" "cross-cutting" \
    && local has_crosscut="true" || local has_crosscut="false"
  assert_eq "R-010: SKILL.md mentions cross-cutting view" "true" "$has_crosscut"
}

# ---------------------------------------------------------------------------
# Test: R-012 — Token usage logging
# ---------------------------------------------------------------------------

test_r012_token_logging() {
  echo ""
  echo "=== R-012: Token usage logging ==="

  local skill="$REPO_DIR/skills/cexplain/SKILL.md"

  # Tests R-012 [unit]: token log path
  file_contains "$skill" "\.correctless/artifacts/token-log" \
    && local has_path="true" || local has_path="false"
  assert_eq "R-012: SKILL.md mentions .correctless/artifacts/token-log path" "true" "$has_path"

  # Tests R-012: skill field set to cexplain
  file_contains "$skill" '"cexplain"\|skill.*cexplain\|cexplain.*skill' \
    && local has_skill="true" || local has_skill="false"
  assert_eq "R-012: SKILL.md specifies skill: cexplain" "true" "$has_skill"

  # Tests R-012: phase field set to exploration
  file_contains "$skill" '"exploration"\|phase.*exploration\|exploration.*phase' \
    && local has_phase="true" || local has_phase="false"
  assert_eq "R-012: SKILL.md specifies phase: exploration" "true" "$has_phase"

  # Tests R-012: agent_role field set to explain-agent
  file_contains "$skill" "explain-agent" \
    && local has_role="true" || local has_role="false"
  assert_eq "R-012: SKILL.md specifies agent_role: explain-agent" "true" "$has_role"

  # Tests R-012: total_tokens field
  file_contains "$skill" "total_tokens" \
    && local has_tokens="true" || local has_tokens="false"
  assert_eq "R-012: SKILL.md specifies total_tokens field" "true" "$has_tokens"

  # Tests R-012: duration_ms field
  file_contains "$skill" "duration_ms" \
    && local has_duration="true" || local has_duration="false"
  assert_eq "R-012: SKILL.md specifies duration_ms field" "true" "$has_duration"

  # Tests R-012: timestamp field
  file_contains "$skill" "timestamp" \
    && local has_timestamp="true" || local has_timestamp="false"
  assert_eq "R-012: SKILL.md specifies timestamp field" "true" "$has_timestamp"
}

# ---------------------------------------------------------------------------
# Test: R-013 — File paths and line numbers
# ---------------------------------------------------------------------------

test_r013_file_paths() {
  echo ""
  echo "=== R-013: File paths and line numbers ==="

  local skill="$REPO_DIR/skills/cexplain/SKILL.md"

  # Tests R-013 [integration]: references file paths
  file_contains "$skill" "file path" \
    && local has_filepath="true" || local has_filepath="false"
  assert_eq "R-013: SKILL.md mentions file paths" "true" "$has_filepath"

  # Tests R-013: references line numbers
  file_contains "$skill" "line number" \
    && local has_linenum="true" || local has_linenum="false"
  assert_eq "R-013: SKILL.md mentions line numbers" "true" "$has_linenum"

  # Tests R-013: specific and verifiable
  file_contains "$skill" "[Ss]pecific\|[Vv]erifiable" \
    && local has_specific="true" || local has_specific="false"
  assert_eq "R-013: SKILL.md mentions specific/verifiable references" "true" "$has_specific"

  # A-6 fix: anti-pattern example (not just generic module names)
  file_contains "$skill" "not.*the.*module handles\|not.*generic.*module\|not just.*module" \
    && local has_antipattern="true" || local has_antipattern="false"
  assert_eq "R-013: SKILL.md warns against generic module-level references" "true" "$has_antipattern"
}

# ---------------------------------------------------------------------------
# Test: R-014 — HTML footer and pinned CDN
# ---------------------------------------------------------------------------

test_r014_html_footer() {
  echo ""
  echo "=== R-014: HTML footer and pinned CDN ==="

  local skill="$REPO_DIR/skills/cexplain/SKILL.md"

  # Tests R-014 [unit]: footer in HTML
  file_contains "$skill" "[Ff]ooter" \
    && local has_footer="true" || local has_footer="false"
  assert_eq "R-014: SKILL.md mentions footer" "true" "$has_footer"

  # Tests R-014: Generated by text
  file_contains "$skill" "Generated by" \
    && local has_genby="true" || local has_genby="false"
  assert_eq "R-014: SKILL.md mentions Generated by" "true" "$has_genby"

  # QA-004 fix: Correctless version in footer
  file_contains "$skill" "[Vv]ersion" \
    && local has_version="true" || local has_version="false"
  assert_eq "R-014: SKILL.md mentions version in Generated by footer" "true" "$has_version"

  # Tests R-014: pinned CDN version (not latest)
  file_contains "$skill" "[Pp]inned" \
    && local has_pinned="true" || local has_pinned="false"
  assert_eq "R-014: SKILL.md mentions pinned CDN version" "true" "$has_pinned"

  # Tests R-014: inline CSS
  file_contains "$skill" "inline CSS" \
    && local has_inlinecss="true" || local has_inlinecss="false"
  assert_eq "R-014: SKILL.md mentions inline CSS" "true" "$has_inlinecss"
}

# ---------------------------------------------------------------------------
# Test: R-015 — Free text input resolution
# ---------------------------------------------------------------------------

test_r015_free_text() {
  echo ""
  echo "=== R-015: Free text input resolution ==="

  local skill="$REPO_DIR/skills/cexplain/SKILL.md"

  # Tests R-015 [integration]: free text input handling
  file_contains "$skill" "free text\|free-text" \
    && local has_freetext="true" || local has_freetext="false"
  assert_eq "R-015: SKILL.md mentions free text input" "true" "$has_freetext"

  # Tests R-015: resolves file path
  file_contains "$skill" "file path" \
    && local has_file="true" || local has_file="false"
  assert_eq "R-015: SKILL.md mentions file path resolution" "true" "$has_file"

  # Tests R-015: resolves directory
  file_contains "$skill" "directory" \
    && local has_dir="true" || local has_dir="false"
  assert_eq "R-015: SKILL.md mentions directory resolution" "true" "$has_dir"

  # Tests R-015: resolves symbol
  file_contains "$skill" "symbol" \
    && local has_symbol="true" || local has_symbol="false"
  assert_eq "R-015: SKILL.md mentions symbol resolution" "true" "$has_symbol"

  # Tests R-015: resolves concept
  file_contains "$skill" "concept" \
    && local has_concept="true" || local has_concept="false"
  assert_eq "R-015: SKILL.md mentions concept resolution" "true" "$has_concept"

  # Tests R-015: handles ambiguous input — clarify with top 3
  file_contains "$skill" "[Aa]mbiguous" \
    && local has_ambiguous="true" || local has_ambiguous="false"
  assert_eq "R-015: SKILL.md mentions ambiguous input handling" "true" "$has_ambiguous"

  file_contains "$skill" "[Cc]larif\|top 3" \
    && local has_clarify="true" || local has_clarify="false"
  assert_eq "R-015: SKILL.md mentions clarify / top 3" "true" "$has_clarify"
}

# ---------------------------------------------------------------------------
# Test: R-016 — 30-node grouping with subgraphs
# ---------------------------------------------------------------------------

test_r016_node_grouping() {
  echo ""
  echo "=== R-016: 30-node grouping with subgraphs ==="

  local skill="$REPO_DIR/skills/cexplain/SKILL.md"

  # Tests R-016 [integration]: 30-node limit enforcement
  file_contains "$skill" "30-node\|30 node" \
    && local has_limit="true" || local has_limit="false"
  assert_eq "R-016: SKILL.md mentions 30-node limit" "true" "$has_limit"

  # Tests R-016: subgraph grouping
  file_contains "$skill" "[Ss]ubgraph" \
    && local has_subgraph="true" || local has_subgraph="false"
  assert_eq "R-016: SKILL.md mentions subgraphs" "true" "$has_subgraph"

  # Tests R-016: collapsed groups
  file_contains "$skill" "[Cc]ollaps" \
    && local has_collapsed="true" || local has_collapsed="false"
  assert_eq "R-016: SKILL.md mentions collapsed groups" "true" "$has_collapsed"

  # Tests R-016: expand group follow-up
  file_contains "$skill" "[Ee]xpand" \
    && local has_expand="true" || local has_expand="false"
  assert_eq "R-016: SKILL.md mentions expand option" "true" "$has_expand"
}

# ---------------------------------------------------------------------------
# Test: R-017 — Works without /csetup
# ---------------------------------------------------------------------------

test_r017_no_setup() {
  echo ""
  echo "=== R-017: Works without /csetup ==="

  local skill="$REPO_DIR/skills/cexplain/SKILL.md"

  # Tests R-017 [integration]: works without /csetup
  file_contains "$skill" "without.*/csetup\|without.*csetup\|csetup.*not.*required\|does not require.*csetup" \
    && local has_nosetup="true" || local has_nosetup="false"
  assert_eq "R-017: SKILL.md mentions working without /csetup" "true" "$has_nosetup"

  # Tests R-017: workflow-config.json does not exist case
  file_contains "$skill" "workflow-config.json.*does not exist\|workflow-config.json.*not.*exist\|no.*workflow-config" \
    && local has_noconfig="true" || local has_noconfig="false"
  assert_eq "R-017: SKILL.md handles missing workflow-config.json" "true" "$has_noconfig"

  # Tests R-017: skips MCP when no config
  file_contains "$skill" "[Ss]kip.*MCP\|MCP.*unavailable\|Serena.*unavailable\|treats.*unavailable" \
    && local has_skipmcp="true" || local has_skipmcp="false"
  assert_eq "R-017: SKILL.md skips MCP when no config" "true" "$has_skipmcp"

  # Tests R-017: low-ceremony approach
  file_contains "$skill" "low-ceremony\|low ceremony" \
    && local has_lowceremony="true" || local has_lowceremony="false"
  assert_eq "R-017: SKILL.md mentions low-ceremony" "true" "$has_lowceremony"
}

# ---------------------------------------------------------------------------
# Test: R-018 — Render mode: terminal vs HTML
# ---------------------------------------------------------------------------

test_r018_render_mode() {
  echo ""
  echo "=== R-018: Render mode: terminal vs HTML ==="

  local skill="$REPO_DIR/skills/cexplain/SKILL.md"

  # Tests R-018 [integration]: terminal render mode
  file_contains "$skill" "[Tt]erminal" \
    && local has_terminal="true" || local has_terminal="false"
  assert_eq "R-018: SKILL.md mentions terminal mode" "true" "$has_terminal"

  # Tests R-018: HTML file render mode
  file_contains "$skill" "HTML file\|HTML mode" \
    && local has_htmlmode="true" || local has_htmlmode="false"
  assert_eq "R-018: SKILL.md mentions HTML file mode" "true" "$has_htmlmode"

  # Tests R-018: render mode choice
  file_contains "$skill" "render mode\|output mode\|preferred.*mode" \
    && local has_mode="true" || local has_mode="false"
  assert_eq "R-018: SKILL.md mentions render mode choice" "true" "$has_mode"

  # Tests R-018: switch modes mid-session
  file_contains "$skill" "[Ss]witch.*mode\|switch to HTML\|switch to terminal" \
    && local has_switch="true" || local has_switch="false"
  assert_eq "R-018: SKILL.md mentions switching modes" "true" "$has_switch"

  # B-2 fix: R-018 must instruct agent to ASK user on first invocation
  file_contains "$skill" "[Aa]sk.*preferred\|[Aa]sk.*output mode\|[Aa]sk.*render\|[Pp]resent.*mode.*choice\|choose.*mode" \
    && local has_ask="true" || local has_ask="false"
  assert_eq "R-018: SKILL.md instructs asking user for mode preference" "true" "$has_ask"

  # B-2 fix: terminal is the default
  file_contains "$skill" "[Tt]erminal.*default\|default.*[Tt]erminal" \
    && local has_default="true" || local has_default="false"
  assert_eq "R-018: SKILL.md specifies terminal as default mode" "true" "$has_default"
}

# ---------------------------------------------------------------------------
# Test: R-019 — Minimal project handling
# ---------------------------------------------------------------------------

test_r019_minimal_project() {
  echo ""
  echo "=== R-019: Minimal project handling ==="

  local skill="$REPO_DIR/skills/cexplain/SKILL.md"

  # Tests R-019 [integration]: fewer than 2 components
  file_contains "$skill" "fewer than 2\|limited structure" \
    && local has_minimal="true" || local has_minimal="false"
  assert_eq "R-019: SKILL.md handles fewer than 2 components" "true" "$has_minimal"

  # Tests R-019: directory tree overview option
  file_contains "$skill" "directory tree" \
    && local has_dirtree="true" || local has_dirtree="false"
  assert_eq "R-019: SKILL.md mentions directory tree option" "true" "$has_dirtree"

  # Tests R-019: always offers a path forward
  file_contains "$skill" "path forward\|always offer\|never.*can't help" \
    && local has_forward="true" || local has_forward="false"
  assert_eq "R-019: SKILL.md always offers a path forward" "true" "$has_forward"

  # A-7 fix: "describe what the project does" fallback option
  file_contains "$skill" "[Dd]escribe what the project does\|[Dd]escribe.*project\|what.*project does" \
    && local has_describe="true" || local has_describe="false"
  assert_eq "R-019: SKILL.md offers 'describe what project does' option" "true" "$has_describe"
}

# ---------------------------------------------------------------------------
# Run all tests
# ---------------------------------------------------------------------------

trap cleanup EXIT

echo "Correctless /cexplain Test Suite"
echo "================================="

test_r011_skill_exists
test_skill_structure
test_r001_overview_scan
test_r002_exploration_menu
test_r003_diagram_and_prose
test_r004_uncertainty
test_r005_html_export
test_r006_serena_mcp
test_r007_mermaid_syntax
test_r008_project_detection
test_r009_stateless
test_r010_deep_dive
test_r012_token_logging
test_r013_file_paths
test_r014_html_footer
test_r015_free_text
test_r016_node_grouping
test_r017_no_setup
test_r018_render_mode
test_r019_minimal_project

echo ""
echo "================================="
echo "Results: $PASS passed, $FAIL failed"
echo ""

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
