#!/usr/bin/env bash
# Correctless — wire intensity into remaining pipeline skills test suite
# Tests spec rules R-001 through R-022 from
# .correctless/specs/wire-intensity-pipeline.md
# Run from repo root: bash tests/test-wire-intensity-pipeline.sh

set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0
FAIL=0

# ============================================
# Helpers (matching project test conventions)
# ============================================

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

file_contains() {
  local file="$1" pattern="$2" desc="$3"
  if grep -q "$pattern" "$file" 2>/dev/null; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (pattern '$pattern' not found in $file)"
    FAIL=$((FAIL + 1))
  fi
}

file_not_contains() {
  local file="$1" pattern="$2" desc="$3"
  if grep -q "$pattern" "$file" 2>/dev/null; then
    echo "  FAIL: $desc (pattern '$pattern' should NOT be in $file)"
    FAIL=$((FAIL + 1))
  else
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  fi
}

file_contains_i() {
  local file="$1" pattern="$2" desc="$3"
  if grep -qi "$pattern" "$file" 2>/dev/null; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (pattern '$pattern' not found case-insensitively in $file)"
    FAIL=$((FAIL + 1))
  fi
}

file_order() {
  local file="$1" first_pattern="$2" second_pattern="$3" desc="$4"
  local first_line second_line
  first_line="$(grep -n "$first_pattern" "$file" 2>/dev/null | head -1 | cut -d: -f1)"
  second_line="$(grep -n "$second_pattern" "$file" 2>/dev/null | head -1 | cut -d: -f1)"
  if [ -z "$first_line" ]; then
    echo "  FAIL: $desc (first pattern '$first_pattern' not found in $file)"
    FAIL=$((FAIL + 1))
  elif [ -z "$second_line" ]; then
    echo "  FAIL: $desc (second pattern '$second_pattern' not found in $file)"
    FAIL=$((FAIL + 1))
  elif [ "$first_line" -lt "$second_line" ]; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc ('$first_pattern' at line $first_line should be before '$second_pattern' at line $second_line)"
    FAIL=$((FAIL + 1))
  fi
}

# ============================================
# Helper: Extract Effective Intensity section
# Extracts text between "## Effective Intensity" and the next "## " heading.
# Normalizes trailing whitespace per line and trailing newlines.
# ============================================

extract_effective_intensity() {
  local file="$1"
  local in_section=0
  local result=""
  while IFS= read -r line; do
    if [ "$in_section" -eq 0 ]; then
      if [[ "$line" == "## Effective Intensity" ]]; then
        in_section=1
        result="${line}"
      fi
    else
      # Stop at the next level-2 heading (## but not ###)
      if [[ "$line" =~ ^##\  ]] && [[ ! "$line" =~ ^###\  ]]; then
        break
      fi
      result="${result}
${line}"
    fi
  done < "$file"
  # Normalize: strip trailing spaces per line, strip trailing newlines
  echo "$result" | sed 's/[[:space:]]*$//' | sed '/^$/{ :loop; N; /^\n*$/{ $d; b loop; }; }'
}

# ============================================
# R-001: /cspec table exists with correct columns, rows, values
# ============================================

test_r001_cspec_intensity_table() {
  echo ""
  echo "=== R-001: /cspec SKILL.md has Intensity Configuration table ==="

  local skill_file="$REPO_DIR/skills/cspec/SKILL.md"

  # R-001: section header exists
  file_contains "$skill_file" "## Intensity Configuration" \
    "R-001: cspec SKILL.md has '## Intensity Configuration' section"

  # R-001: table header row has Standard, High, Critical columns
  file_contains "$skill_file" "| Standard | High | Critical" \
    "R-001: table header has Standard, High, Critical columns"

  # R-001: Sections row
  file_contains_i "$skill_file" "| Sections" \
    "R-001: table has 'Sections' row"
  file_contains_i "$skill_file" "Sections.*5 + typed rules" \
    "R-001: Sections standard value '5 + typed rules'"
  file_contains_i "$skill_file" "Sections.*12 + invariants" \
    "R-001: Sections high value '12 + invariants'"
  file_contains_i "$skill_file" "Sections.*12 + all templates" \
    "R-001: Sections critical value '12 + all templates'"

  # R-001: Research agent row
  file_contains_i "$skill_file" "| Research agent" \
    "R-001: table has 'Research agent' row"
  file_contains_i "$skill_file" "Research agent.*If needed" \
    "R-001: Research agent standard value 'If needed'"
  file_contains_i "$skill_file" "Research agent.*Always (security)" \
    "R-001: Research agent high value 'Always (security)'"

  # R-001: STRIDE row
  file_contains_i "$skill_file" "| STRIDE" \
    "R-001: table has 'STRIDE' row"

  # R-001: Question depth row
  file_contains_i "$skill_file" "| Question depth" \
    "R-001: table has 'Question depth' row"
  file_contains_i "$skill_file" "Question depth.*Socratic" \
    "R-001: Question depth standard value 'Socratic'"
  file_contains_i "$skill_file" "Question depth.*Adversarial" \
    "R-001: Question depth high value 'Adversarial'"
  file_contains_i "$skill_file" "Question depth.*Exhaustive" \
    "R-001: Question depth critical value 'Exhaustive'"
}

# ============================================
# R-002: /cspec has verbatim Effective Intensity section
# ============================================

test_r002_cspec_effective_intensity() {
  echo ""
  echo "=== R-002: /cspec SKILL.md has verbatim Effective Intensity section ==="

  local skill_file="$REPO_DIR/skills/cspec/SKILL.md"

  # R-002: section header exists
  file_contains "$skill_file" "## Effective Intensity" \
    "R-002: cspec SKILL.md has '## Effective Intensity' section"

  # R-002: max computation
  file_contains "$skill_file" "max(project_intensity, feature_intensity)" \
    "R-002: documents max(project_intensity, feature_intensity)"

  # R-002: ordering
  file_contains "$skill_file" "standard < high < critical" \
    "R-002: documents ordering standard < high < critical"

  # R-002: 3-step process
  file_contains "$skill_file" "Read project intensity" \
    "R-002: step 1 — Read project intensity"
  file_contains "$skill_file" "Read feature intensity" \
    "R-002: step 2 — Read feature intensity"
  file_contains "$skill_file" "Compute effective intensity" \
    "R-002: step 3 — Compute effective intensity"

  # R-002: fallback chain
  file_contains "$skill_file" "feature_intensity -> workflow.intensity -> standard" \
    "R-002: fallback chain documented"

  # R-002: no-active-workflow handling
  file_contains_i "$skill_file" "no active workflow state\|no state file" \
    "R-002: handles no active workflow state"
}

# ============================================
# R-003: /cspec body references table values conditioned on intensity
# ============================================

test_r003_cspec_body_references() {
  echo ""
  echo "=== R-003: /cspec body references intensity-conditioned behavior ==="

  local skill_file="$REPO_DIR/skills/cspec/SKILL.md"

  # R-003: "spec-lite.md" for standard
  file_contains_i "$skill_file" "standard.*spec-lite" \
    "R-003: spec-lite.md conditioned on standard intensity"

  # R-003: "spec-full.md" for high+
  file_contains_i "$skill_file" "high.*spec-full\|spec-full.*high" \
    "R-003: spec-full.md conditioned on high+ intensity"

  # R-003: "STRIDE" for high+
  file_contains_i "$skill_file" "high.*STRIDE\|STRIDE.*high\|critical.*STRIDE" \
    "R-003: STRIDE conditioned on high+ intensity"

  # R-003: "research agent" conditioned on intensity
  file_contains_i "$skill_file" "research agent.*intensity\|intensity.*research agent\|research agent.*always\|always.*research agent" \
    "R-003: research agent conditioned on intensity"

  # R-003: "exhaustive" or "refuse vague" for critical
  file_contains_i "$skill_file" "critical.*exhaustive\|exhaustive.*critical\|critical.*refuse vague\|refuse vague.*critical" \
    "R-003: exhaustive/refuse vague conditioned on critical intensity"
}

# ============================================
# R-004: /cspec positioning — after title, before Progress Visibility;
#        "Detect Intensity" replaced, "Intensity Detection" unchanged
# ============================================

test_r004_cspec_positioning() {
  echo ""
  echo "=== R-004: /cspec positioning and Detect Intensity replaced ==="

  local skill_file="$REPO_DIR/skills/cspec/SKILL.md"

  # R-004: Intensity Configuration after title
  file_order "$skill_file" \
    "# /cspec" \
    "## Intensity Configuration" \
    "R-004: '## Intensity Configuration' appears after '# /cspec' title"

  # R-004: Effective Intensity before Progress Visibility
  file_order "$skill_file" \
    "## Effective Intensity" \
    "## Progress Visibility" \
    "R-004: '## Effective Intensity' appears before '## Progress Visibility'"

  # R-004: Intensity Configuration before Progress Visibility
  file_order "$skill_file" \
    "## Intensity Configuration" \
    "## Progress Visibility" \
    "R-004: '## Intensity Configuration' appears before '## Progress Visibility'"

  # R-004: "## Detect Intensity" must NOT exist (replaced by Effective Intensity)
  file_not_contains "$skill_file" "## Detect Intensity" \
    "R-004: '## Detect Intensity' section has been removed (replaced by Effective Intensity)"

  # R-004: old "configured intensity" template-selection logic is gone
  file_not_contains "$skill_file" "configured intensity" \
    "R-004: old 'configured intensity' template-selection text removed"

  # R-004: "## Intensity Detection" (Stage 2, line ~462) must STILL exist
  file_contains "$skill_file" "## Intensity Detection" \
    "R-004: '## Intensity Detection' section (Stage 2) is preserved"
}

# ============================================
# R-005: /ctdd table with correct rows and values
# ============================================

test_r005_ctdd_intensity_table() {
  echo ""
  echo "=== R-005: /ctdd SKILL.md has Intensity Configuration table ==="

  local skill_file="$REPO_DIR/skills/ctdd/SKILL.md"

  # R-005: section header exists
  file_contains "$skill_file" "## Intensity Configuration" \
    "R-005: ctdd SKILL.md has '## Intensity Configuration' section"

  # R-005: table header
  file_contains "$skill_file" "| Standard | High | Critical" \
    "R-005: table header has Standard, High, Critical columns"

  # R-005: Test audit row
  file_contains_i "$skill_file" "| Test audit" \
    "R-005: table has 'Test audit' row"
  file_contains_i "$skill_file" "Test audit.*Blocking" \
    "R-005: Test audit standard value 'Blocking'"
  file_contains_i "$skill_file" "Test audit.*Strict" \
    "R-005: Test audit high value contains 'Strict'"
  file_contains_i "$skill_file" "Test audit.*Strict + PBT" \
    "R-005: Test audit critical value 'Strict + PBT recommendations'"

  # R-005: QA rounds row
  file_contains_i "$skill_file" "| QA rounds" \
    "R-005: table has 'QA rounds' row"
  file_contains_i "$skill_file" "QA rounds.*2 max" \
    "R-005: QA rounds standard value '2 max'"
  file_contains_i "$skill_file" "QA rounds.*3 max" \
    "R-005: QA rounds high value '3 max'"
  file_contains_i "$skill_file" "QA rounds.*5 max" \
    "R-005: QA rounds critical value '5 max'"

  # R-005: Mutation testing row
  file_contains_i "$skill_file" "| Mutation testing" \
    "R-005: table has 'Mutation testing' row"

  # R-005: Calm resets row
  file_contains_i "$skill_file" "| Calm resets" \
    "R-005: table has 'Calm resets' row"
  file_contains_i "$skill_file" "Calm resets.*After 3 failures" \
    "R-005: Calm resets standard value 'After 3 failures'"
  file_contains_i "$skill_file" "Calm resets.*After 2 failures" \
    "R-005: Calm resets high value 'After 2 failures'"
  file_contains_i "$skill_file" "Calm resets.*supervisor notified" \
    "R-005: Calm resets critical value includes 'supervisor notified'"
}

# ============================================
# R-006: /ctdd has verbatim Effective Intensity section
# ============================================

test_r006_ctdd_effective_intensity() {
  echo ""
  echo "=== R-006: /ctdd SKILL.md has verbatim Effective Intensity section ==="

  local skill_file="$REPO_DIR/skills/ctdd/SKILL.md"

  # R-006: section header exists
  file_contains "$skill_file" "## Effective Intensity" \
    "R-006: ctdd SKILL.md has '## Effective Intensity' section"

  # R-006: max computation
  file_contains "$skill_file" "max(project_intensity, feature_intensity)" \
    "R-006: documents max(project_intensity, feature_intensity)"

  # R-006: ordering
  file_contains "$skill_file" "standard < high < critical" \
    "R-006: documents ordering standard < high < critical"

  # R-006: fallback chain
  file_contains "$skill_file" "feature_intensity -> workflow.intensity -> standard" \
    "R-006: fallback chain documented"

  # R-006: no-active-workflow handling
  file_contains_i "$skill_file" "no active workflow state\|no state file" \
    "R-006: handles no active workflow state"
}

# ============================================
# R-007: /ctdd body references intensity-conditioned behavior
# ============================================

test_r007_ctdd_body_references() {
  echo ""
  echo "=== R-007: /ctdd body references intensity-conditioned behavior ==="

  local skill_file="$REPO_DIR/skills/ctdd/SKILL.md"

  # R-007: "2 max" or "2 rounds" for standard QA
  file_contains_i "$skill_file" "standard.*2 max\|standard.*2 rounds\|2 max.*standard\|2 rounds.*standard" \
    "R-007: 2 max/2 rounds conditioned on standard"

  # R-007: "mutation testing" conditioned on high+
  file_contains_i "$skill_file" "high.*mutation testing\|mutation testing.*high\|critical.*mutation testing" \
    "R-007: mutation testing conditioned on high+"

  # R-007: "PBT" for critical
  file_contains_i "$skill_file" "critical.*PBT\|PBT.*critical" \
    "R-007: PBT conditioned on critical"
}

# ============================================
# R-008: /ctdd positioning — after title, before Philosophy or Progress Visibility
# ============================================

test_r008_ctdd_positioning() {
  echo ""
  echo "=== R-008: /ctdd positioning ==="

  local skill_file="$REPO_DIR/skills/ctdd/SKILL.md"

  # R-008: Intensity Configuration after title
  file_order "$skill_file" \
    "# /ctdd" \
    "## Intensity Configuration" \
    "R-008: '## Intensity Configuration' appears after '# /ctdd' title"

  # R-008: Effective Intensity after title
  file_order "$skill_file" \
    "# /ctdd" \
    "## Effective Intensity" \
    "R-008: '## Effective Intensity' appears after '# /ctdd' title"

  # R-008: Intensity Configuration before Philosophy (whichever first)
  file_order "$skill_file" \
    "## Intensity Configuration" \
    "## Philosophy" \
    "R-008: '## Intensity Configuration' appears before '## Philosophy'"

  # R-008: Effective Intensity before Philosophy
  file_order "$skill_file" \
    "## Effective Intensity" \
    "## Philosophy" \
    "R-008: '## Effective Intensity' appears before '## Philosophy'"
}

# ============================================
# R-009: /cverify table with correct rows and values
# ============================================

test_r009_cverify_intensity_table() {
  echo ""
  echo "=== R-009: /cverify SKILL.md has Intensity Configuration table ==="

  local skill_file="$REPO_DIR/skills/cverify/SKILL.md"

  # R-009: section header exists
  file_contains "$skill_file" "## Intensity Configuration" \
    "R-009: cverify SKILL.md has '## Intensity Configuration' section"

  # R-009: table header
  file_contains "$skill_file" "| Standard | High | Critical" \
    "R-009: table header has Standard, High, Critical columns"

  # R-009: Rule coverage row
  file_contains_i "$skill_file" "| Rule coverage" \
    "R-009: table has 'Rule coverage' row"
  file_contains_i "$skill_file" "Rule coverage.*Exists + weak detection" \
    "R-009: Rule coverage standard value 'Exists + weak detection'"
  file_contains_i "$skill_file" "Rule coverage.*Full matrix + Serena trace" \
    "R-009: Rule coverage high value 'Full matrix + Serena trace'"
  file_contains_i "$skill_file" "Rule coverage.*Full + mutation survivor" \
    "R-009: Rule coverage critical value contains 'Full + mutation survivor'"

  # R-009: Dependencies row
  file_contains_i "$skill_file" "| Dependencies" \
    "R-009: table has 'Dependencies' row"
  file_contains_i "$skill_file" "Dependencies.*List + license" \
    "R-009: Dependencies standard value 'List + license'"
  file_contains_i "$skill_file" "Dependencies.*List + CVE + maintenance" \
    "R-009: Dependencies high value 'List + CVE + maintenance'"
  file_contains_i "$skill_file" "Dependencies.*Full audit" \
    "R-009: Dependencies critical value 'Full audit'"

  # R-009: Architecture row
  file_contains_i "$skill_file" "| Architecture" \
    "R-009: table has 'Architecture' row"
  file_contains_i "$skill_file" "Architecture.*Basic compliance" \
    "R-009: Architecture standard value 'Basic compliance'"
  file_contains_i "$skill_file" "Architecture.*Full + drift detection" \
    "R-009: Architecture high value 'Full + drift detection'"
  file_contains_i "$skill_file" "Architecture.*Full + cross-spec + prohibitions" \
    "R-009: Architecture critical value 'Full + cross-spec + prohibitions'"
}

# ============================================
# R-010: /cverify has verbatim Effective Intensity section
# ============================================

test_r010_cverify_effective_intensity() {
  echo ""
  echo "=== R-010: /cverify SKILL.md has verbatim Effective Intensity section ==="

  local skill_file="$REPO_DIR/skills/cverify/SKILL.md"

  # R-010: section header exists
  file_contains "$skill_file" "## Effective Intensity" \
    "R-010: cverify SKILL.md has '## Effective Intensity' section"

  # R-010: max computation
  file_contains "$skill_file" "max(project_intensity, feature_intensity)" \
    "R-010: documents max(project_intensity, feature_intensity)"

  # R-010: ordering
  file_contains "$skill_file" "standard < high < critical" \
    "R-010: documents ordering standard < high < critical"

  # R-010: fallback chain
  file_contains "$skill_file" "feature_intensity -> workflow.intensity -> standard" \
    "R-010: fallback chain documented"

  # R-010: no-active-workflow handling
  file_contains_i "$skill_file" "no active workflow state\|no state file" \
    "R-010: handles no active workflow state"
}

# ============================================
# R-011: /cverify body references intensity-conditioned behavior
# ============================================

test_r011_cverify_body_references() {
  echo ""
  echo "=== R-011: /cverify body references intensity-conditioned behavior ==="

  local skill_file="$REPO_DIR/skills/cverify/SKILL.md"

  # R-011: "Serena trace" for high+
  file_contains_i "$skill_file" "high.*Serena trace\|Serena trace.*high\|critical.*Serena trace" \
    "R-011: Serena trace conditioned on high+"

  # R-011: "CVE" for high+
  file_contains_i "$skill_file" "high.*CVE\|CVE.*high\|critical.*CVE" \
    "R-011: CVE conditioned on high+"

  # R-011: "mutation survivor" for critical
  file_contains_i "$skill_file" "critical.*mutation survivor\|mutation survivor.*critical" \
    "R-011: mutation survivor conditioned on critical"

  # R-011: "cross-spec" for critical
  file_contains_i "$skill_file" "critical.*cross-spec\|cross-spec.*critical" \
    "R-011: cross-spec conditioned on critical"
}

# ============================================
# R-012: /cverify positioning — after title, before Progress Visibility
# ============================================

test_r012_cverify_positioning() {
  echo ""
  echo "=== R-012: /cverify positioning ==="

  local skill_file="$REPO_DIR/skills/cverify/SKILL.md"

  # R-012: Intensity Configuration after title
  file_order "$skill_file" \
    "# /cverify" \
    "## Intensity Configuration" \
    "R-012: '## Intensity Configuration' appears after '# /cverify' title"

  # R-012: Effective Intensity before Progress Visibility
  file_order "$skill_file" \
    "## Effective Intensity" \
    "## Progress Visibility" \
    "R-012: '## Effective Intensity' appears before '## Progress Visibility'"

  # R-012: Intensity Configuration before Progress Visibility
  file_order "$skill_file" \
    "## Intensity Configuration" \
    "## Progress Visibility" \
    "R-012: '## Intensity Configuration' appears before '## Progress Visibility'"
}

# ============================================
# R-013: /cdocs table with correct rows and values
# ============================================

test_r013_cdocs_intensity_table() {
  echo ""
  echo "=== R-013: /cdocs SKILL.md has Intensity Configuration table ==="

  local skill_file="$REPO_DIR/skills/cdocs/SKILL.md"

  # R-013: section header exists
  file_contains "$skill_file" "## Intensity Configuration" \
    "R-013: cdocs SKILL.md has '## Intensity Configuration' section"

  # R-013: table header
  file_contains "$skill_file" "| Standard | High | Critical" \
    "R-013: table header has Standard, High, Critical columns"

  # R-013: Scope row
  file_contains_i "$skill_file" "| Scope" \
    "R-013: table has 'Scope' row"
  file_contains_i "$skill_file" "Scope.*AGENT_CONTEXT + feature docs" \
    "R-013: Scope standard value 'AGENT_CONTEXT + feature docs'"
  file_contains_i "$skill_file" "Scope.*add Mermaid diagrams" \
    "R-013: Scope high value 'add Mermaid diagrams'"
  file_contains_i "$skill_file" "Scope.*add fact-checking subagent" \
    "R-013: Scope critical value 'add fact-checking subagent'"

  # R-013: Post-merge row
  file_contains_i "$skill_file" "| Post-merge" \
    "R-013: table has 'Post-merge' row"
  file_contains_i "$skill_file" "Post-merge.*Suggest /cmetrics" \
    "R-013: Post-merge standard value 'Suggest /cmetrics'"
  file_contains_i "$skill_file" "Post-merge.*Suggest /caudit" \
    "R-013: Post-merge high value 'Suggest /caudit'"
  file_contains_i "$skill_file" "Post-merge.*Require /caudit" \
    "R-013: Post-merge critical value 'Require /caudit'"
}

# ============================================
# R-014: /cdocs has verbatim Effective Intensity section
# ============================================

test_r014_cdocs_effective_intensity() {
  echo ""
  echo "=== R-014: /cdocs SKILL.md has verbatim Effective Intensity section ==="

  local skill_file="$REPO_DIR/skills/cdocs/SKILL.md"

  # R-014: section header exists
  file_contains "$skill_file" "## Effective Intensity" \
    "R-014: cdocs SKILL.md has '## Effective Intensity' section"

  # R-014: max computation
  file_contains "$skill_file" "max(project_intensity, feature_intensity)" \
    "R-014: documents max(project_intensity, feature_intensity)"

  # R-014: ordering
  file_contains "$skill_file" "standard < high < critical" \
    "R-014: documents ordering standard < high < critical"

  # R-014: fallback chain
  file_contains "$skill_file" "feature_intensity -> workflow.intensity -> standard" \
    "R-014: fallback chain documented"

  # R-014: no-active-workflow handling
  file_contains_i "$skill_file" "no active workflow state\|no state file" \
    "R-014: handles no active workflow state"
}

# ============================================
# R-015: /cdocs body references intensity-conditioned behavior
# ============================================

test_r015_cdocs_body_references() {
  echo ""
  echo "=== R-015: /cdocs body references intensity-conditioned behavior ==="

  local skill_file="$REPO_DIR/skills/cdocs/SKILL.md"

  # R-015: "Mermaid" for high+
  file_contains_i "$skill_file" "high.*Mermaid\|Mermaid.*high\|critical.*Mermaid" \
    "R-015: Mermaid conditioned on high+"

  # R-015: "fact-checking subagent" for critical
  file_contains_i "$skill_file" "critical.*fact-checking subagent\|fact-checking subagent.*critical" \
    "R-015: fact-checking subagent conditioned on critical"

  # R-015: "/caudit" for high+
  file_contains_i "$skill_file" "high.*/caudit\|/caudit.*high\|critical.*/caudit" \
    "R-015: /caudit conditioned on high+"

  # R-015: "Require /caudit" for critical
  file_contains_i "$skill_file" "critical.*Require /caudit\|Require /caudit.*critical" \
    "R-015: Require /caudit conditioned on critical"
}

# ============================================
# R-016: /cdocs positioning — after title, before Progress Visibility
# ============================================

test_r016_cdocs_positioning() {
  echo ""
  echo "=== R-016: /cdocs positioning ==="

  local skill_file="$REPO_DIR/skills/cdocs/SKILL.md"

  # R-016: Intensity Configuration after title
  file_order "$skill_file" \
    "# /cdocs" \
    "## Intensity Configuration" \
    "R-016: '## Intensity Configuration' appears after '# /cdocs' title"

  # R-016: Effective Intensity before Progress Visibility
  file_order "$skill_file" \
    "## Effective Intensity" \
    "## Progress Visibility" \
    "R-016: '## Effective Intensity' appears before '## Progress Visibility'"

  # R-016: Intensity Configuration before Progress Visibility
  file_order "$skill_file" \
    "## Intensity Configuration" \
    "## Progress Visibility" \
    "R-016: '## Intensity Configuration' appears before '## Progress Visibility'"
}

# ============================================
# R-017: /cstatus table with correct rows and values
# ============================================

test_r017_cstatus_intensity_table() {
  echo ""
  echo "=== R-017: /cstatus SKILL.md has Intensity Configuration table ==="

  local skill_file="$REPO_DIR/skills/cstatus/SKILL.md"

  # R-017: section header exists
  file_contains "$skill_file" "## Intensity Configuration" \
    "R-017: cstatus SKILL.md has '## Intensity Configuration' section"

  # R-017: table header
  file_contains "$skill_file" "| Standard | High | Critical" \
    "R-017: table header has Standard, High, Critical columns"

  # R-017: Display row
  file_contains_i "$skill_file" "| Display" \
    "R-017: table has 'Display' row"
  file_contains_i "$skill_file" "Display.*Phase + next step + time in phase" \
    "R-017: Display standard value 'Phase + next step + time in phase'"
  file_contains_i "$skill_file" "Display.*stale workflow warning" \
    "R-017: Display high value includes 'stale workflow warning'"
  file_contains_i "$skill_file" "Display.*token budget warning" \
    "R-017: Display critical value includes 'token budget warning'"
}

# ============================================
# R-018: /cstatus has verbatim Effective Intensity section
# ============================================

test_r018_cstatus_effective_intensity() {
  echo ""
  echo "=== R-018: /cstatus SKILL.md has verbatim Effective Intensity section ==="

  local skill_file="$REPO_DIR/skills/cstatus/SKILL.md"

  # R-018: section header exists
  file_contains "$skill_file" "## Effective Intensity" \
    "R-018: cstatus SKILL.md has '## Effective Intensity' section"

  # R-018: max computation
  file_contains "$skill_file" "max(project_intensity, feature_intensity)" \
    "R-018: documents max(project_intensity, feature_intensity)"

  # R-018: ordering
  file_contains "$skill_file" "standard < high < critical" \
    "R-018: documents ordering standard < high < critical"

  # R-018: fallback chain
  file_contains "$skill_file" "feature_intensity -> workflow.intensity -> standard" \
    "R-018: fallback chain documented"

  # R-018: no-active-workflow handling
  file_contains_i "$skill_file" "no active workflow state\|no state file" \
    "R-018: handles no active workflow state"
}

# ============================================
# R-019: /cstatus body references intensity-conditioned behavior
# ============================================

test_r019_cstatus_body_references() {
  echo ""
  echo "=== R-019: /cstatus body references intensity-conditioned behavior ==="

  local skill_file="$REPO_DIR/skills/cstatus/SKILL.md"

  # R-019: "stale workflow" for high+
  file_contains_i "$skill_file" "high.*stale workflow\|stale workflow.*high\|critical.*stale workflow" \
    "R-019: stale workflow conditioned on high+"

  # R-019: "token budget" for critical
  file_contains_i "$skill_file" "critical.*token budget\|token budget.*critical" \
    "R-019: token budget conditioned on critical"
}

# ============================================
# R-020: /cstatus positioning — after title, before Behavior
# ============================================

test_r020_cstatus_positioning() {
  echo ""
  echo "=== R-020: /cstatus positioning ==="

  local skill_file="$REPO_DIR/skills/cstatus/SKILL.md"

  # R-020: Intensity Configuration after title
  file_order "$skill_file" \
    "# /cstatus" \
    "## Intensity Configuration" \
    "R-020: '## Intensity Configuration' appears after '# /cstatus' title"

  # R-020: Effective Intensity before Behavior
  file_order "$skill_file" \
    "## Effective Intensity" \
    "## Behavior" \
    "R-020: '## Effective Intensity' appears before '## Behavior'"

  # R-020: Intensity Configuration before Behavior
  file_order "$skill_file" \
    "## Intensity Configuration" \
    "## Behavior" \
    "R-020: '## Intensity Configuration' appears before '## Behavior'"
}

# ============================================
# R-021: All 6 pipeline skills contain max() and ordering
# ============================================

test_r021_cross_cutting_consistency() {
  echo ""
  echo "=== R-021: All 6 pipeline skills have max() and ordering ==="

  local pipeline_skills=(
    "$REPO_DIR/skills/cspec/SKILL.md"
    "$REPO_DIR/skills/ctdd/SKILL.md"
    "$REPO_DIR/skills/cverify/SKILL.md"
    "$REPO_DIR/skills/cdocs/SKILL.md"
    "$REPO_DIR/skills/cstatus/SKILL.md"
    "$REPO_DIR/skills/creview/SKILL.md"
  )

  for skill_file in "${pipeline_skills[@]}"; do
    local skill_name
    skill_name="$(basename "$(dirname "$skill_file")")"

    # R-021: each skill contains max(project_intensity, feature_intensity)
    file_contains "$skill_file" "max(project_intensity, feature_intensity)" \
      "R-021: $skill_name contains max(project_intensity, feature_intensity)"

    # R-021: each skill contains ordering standard < high < critical
    file_contains "$skill_file" "standard < high < critical" \
      "R-021: $skill_name contains ordering standard < high < critical"
  done
}

# ============================================
# R-022: Effective Intensity section identical across all 6 skills
# ============================================

test_r022_verbatim_effective_intensity() {
  echo ""
  echo "=== R-022: Effective Intensity section character-for-character identical ==="

  local canonical_file="$REPO_DIR/skills/creview/SKILL.md"
  local canonical_section
  canonical_section="$(extract_effective_intensity "$canonical_file")"

  if [ -z "$canonical_section" ]; then
    echo "  FAIL: R-022: Could not extract Effective Intensity section from /creview (canonical)"
    FAIL=$((FAIL + 1))
    return
  fi

  local target_skills=(
    "$REPO_DIR/skills/cspec/SKILL.md"
    "$REPO_DIR/skills/ctdd/SKILL.md"
    "$REPO_DIR/skills/cverify/SKILL.md"
    "$REPO_DIR/skills/cdocs/SKILL.md"
    "$REPO_DIR/skills/cstatus/SKILL.md"
  )

  for skill_file in "${target_skills[@]}"; do
    local skill_name
    skill_name="$(basename "$(dirname "$skill_file")")"

    local target_section
    target_section="$(extract_effective_intensity "$skill_file")"

    if [ -z "$target_section" ]; then
      echo "  FAIL: R-022: $skill_name has no Effective Intensity section to compare"
      FAIL=$((FAIL + 1))
      continue
    fi

    local diff_output
    diff_output="$(diff <(echo "$canonical_section") <(echo "$target_section") 2>&1)"

    if [ -z "$diff_output" ]; then
      echo "  PASS: R-022: $skill_name Effective Intensity section matches /creview canonical"
      PASS=$((PASS + 1))
    else
      echo "  FAIL: R-022: $skill_name Effective Intensity section differs from /creview canonical"
      echo "    First diff:"
      echo "$diff_output" | head -5 | sed 's/^/    /'
      FAIL=$((FAIL + 1))
    fi
  done
}

# ============================================
# Runner
# ============================================

echo "============================================="
echo "Wire Intensity into Pipeline Skills Test Suite"
echo "============================================="

# /cspec (R-001 through R-004)
test_r001_cspec_intensity_table
test_r002_cspec_effective_intensity
test_r003_cspec_body_references
test_r004_cspec_positioning

# /ctdd (R-005 through R-008)
test_r005_ctdd_intensity_table
test_r006_ctdd_effective_intensity
test_r007_ctdd_body_references
test_r008_ctdd_positioning

# /cverify (R-009 through R-012)
test_r009_cverify_intensity_table
test_r010_cverify_effective_intensity
test_r011_cverify_body_references
test_r012_cverify_positioning

# /cdocs (R-013 through R-016)
test_r013_cdocs_intensity_table
test_r014_cdocs_effective_intensity
test_r015_cdocs_body_references
test_r016_cdocs_positioning

# /cstatus (R-017 through R-020)
test_r017_cstatus_intensity_table
test_r018_cstatus_effective_intensity
test_r019_cstatus_body_references
test_r020_cstatus_positioning

# Cross-cutting (R-021 through R-022)
test_r021_cross_cutting_consistency
test_r022_verbatim_effective_intensity

echo ""
echo "============================================="
echo "Results: $PASS passed, $FAIL failed"
echo ""

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
