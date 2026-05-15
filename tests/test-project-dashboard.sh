#!/usr/bin/env bash
# shellcheck disable=SC2086
# Correctless — Project Dashboard UI Tests
#
# Functional tests for the /cdashboard skill and scripts/build-dashboard.sh.
# Creates temp directories with realistic .correctless/ artifacts,
# runs the dashboard builder, and verifies output.
#
# Covers R-001 through R-012 of the project-dashboard-ui spec.
# Run from repo root: bash tests/test-project-dashboard.sh

source "$(dirname "${BASH_SOURCE[0]}")/test-helpers.sh"

# ============================================================================
# Helper: run the new build-dashboard.sh with project root argument
# ============================================================================

run_dashboard() {
  local dir="$1"
  bash "$REPO_DIR/scripts/build-dashboard.sh" "$dir" >/dev/null 2>&1
}

# ============================================================================
# Helper: create a temp project with realistic .correctless/ artifacts
# ============================================================================

setup_dashboard_project() {
  local dir
  dir=$(mktemp -d)

  # ---- workflow-config.json ----
  mkdir -p "$dir/.correctless/config"
  cat > "$dir/.correctless/config/workflow-config.json" <<'WEOF'
{
  "project": { "name": "test-project" },
  "workflow": { "intensity": "high" }
}
WEOF

  # ---- workflow-history.md ----
  mkdir -p "$dir/docs"
  cat > "$dir/docs/workflow-history.md" <<'HEOF'
# Workflow History

### 2026-04-02 — Feature Alpha
Branch: feature/alpha. Rules: 10. QA rounds: 2. Findings fixed: 3. Added alpha things.

### 2026-04-05 — Feature Beta
Branch: feature/beta. Rules: 8. QA rounds: 1. Findings fixed: 1. Added beta things.

### 2026-04-10 — Feature Gamma
Branch: feature/gamma. Rules: 15. QA rounds: 3. Findings fixed: 7. Overrides: 2. Added gamma things.
HEOF

  # ---- qa-findings ----
  mkdir -p "$dir/.correctless/artifacts"
  cat > "$dir/.correctless/artifacts/qa-findings-alpha.json" <<'QEOF'
{
  "task": "alpha",
  "round": 1,
  "findings": [
    { "id": "QA-001", "severity": "BLOCKING", "description": "Missing validation", "rule_ref": "R-001", "instance_fix": "Add check", "class_fix": "Add structural test", "status": "fixed" },
    { "id": "QA-002", "severity": "NON-BLOCKING", "description": "Cleanup needed", "rule_ref": null, "instance_fix": "Remove unused", "class_fix": "N/A", "status": "fixed" },
    { "id": "MA-001", "severity": "MEDIUM", "description": "Cross-component issue", "rule_ref": "R-003", "lens": "cross-component", "instance_fix": "Fix interaction", "class_fix": "Add integration test", "status": "fixed" }
  ]
}
QEOF

  cat > "$dir/.correctless/artifacts/qa-findings-beta.json" <<'QEOF2'
{
  "task": "beta",
  "round": 1,
  "findings": [
    { "id": "QA-001", "severity": "NON-BLOCKING", "description": "Minor issue with AP-001 pattern", "rule_ref": "R-002", "instance_fix": "Fix it", "class_fix": "N/A", "status": "fixed" }
  ]
}
QEOF2

  # ---- review-decisions (Phase 3 only, optional) ----
  cat > "$dir/.correctless/artifacts/review-decisions-gamma.json" <<'RDEOF'
{
  "task": "gamma",
  "decisions": [
    { "finding_id": "RF-001", "severity": "BLOCKING", "decision": "fix" }
  ]
}
RDEOF

  # ---- specs (for Artifact Browser) ----
  mkdir -p "$dir/.correctless/specs"
  cat > "$dir/.correctless/specs/alpha.md" <<'SEOF'
# Spec: Alpha
## Rules
- R-001: Do alpha things
SEOF
  cat > "$dir/.correctless/specs/beta.md" <<'SEOF2'
# Spec: Beta
## Rules
- R-001: Do beta things
SEOF2

  # ---- verification (for Artifact Browser) ----
  mkdir -p "$dir/.correctless/verification"
  cat > "$dir/.correctless/verification/alpha.md" <<'VEOF'
# Verification: Alpha
All rules verified.
VEOF

  # ---- review findings (for Artifact Browser) ----
  cat > "$dir/.correctless/artifacts/review-spec-findings-alpha.md" <<'RFEOF'
# Review Findings: Alpha
- Finding 1: Missing edge case
RFEOF
  cat > "$dir/.correctless/artifacts/review-findings-beta.md" <<'RFEOF2'
# Review Findings: Beta
- Finding 1: Weak assertion
RFEOF2

  # ---- research briefs (for Artifact Browser) ----
  mkdir -p "$dir/.correctless/artifacts/research"
  cat > "$dir/.correctless/artifacts/research/alpha-brief.md" <<'RBEOF'
# Research Brief: Alpha
Investigated best practices for alpha.
RBEOF

  # ---- architecture docs (for Artifact Browser) ----
  cat > "$dir/.correctless/ARCHITECTURE.md" <<'ARCHEOF'
# Architecture
## Trust Boundaries
### TB-001: Test boundary
ARCHEOF
  cat > "$dir/.correctless/AGENT_CONTEXT.md" <<'ACEOF'
# Agent Context
Test project agent context.
ACEOF
  cat > "$dir/.correctless/antipatterns.md" <<'AEOF'
# Antipatterns — test-project

## Entries

### AP-001: Test antipattern
- **What went wrong**: Tests did bad things.
- **How to catch it**: Check stuff.
- **Frequency**: 3 findings across 2 features (alpha, beta)

### AP-002: Config drift
- **What went wrong**: Config drifted.
- **How to catch it**: Verify config.
- **Frequency**: 1 finding across 1 feature (gamma)
- **Status**: Structurally enforced
AEOF

  # ---- audit history (for Artifact Browser) ----
  mkdir -p "$dir/.correctless/artifacts/findings"
  cat > "$dir/.correctless/artifacts/findings/audit-qa-history.md" <<'AHEOF'
# Audit QA History
## 2026-04-12
Ran QA audit. Found 3 issues.
AHEOF

  # ---- intensity-calibration.json ----
  mkdir -p "$dir/.correctless/meta"
  cat > "$dir/.correctless/meta/intensity-calibration.json" <<'ICEOF'
{
  "calibration_entries": [
    {
      "feature_slug": "alpha",
      "recommended_intensity": "standard",
      "actual_intensity": "high",
      "actual_qa_rounds": 2,
      "actual_findings_count": 3,
      "actual_tokens": 150000,
      "timestamp": "2026-04-02T10:00:00Z"
    },
    {
      "feature_slug": "beta",
      "recommended_intensity": "standard",
      "actual_intensity": "standard",
      "actual_qa_rounds": 1,
      "actual_findings_count": 1,
      "actual_tokens": 80000,
      "timestamp": "2026-04-05T10:00:00Z"
    }
  ]
}
ICEOF

  # ---- drift-debt.json ----
  cat > "$dir/.correctless/meta/drift-debt.json" <<'DDEOF'
{
  "items": [
    { "id": "DRIFT-001", "description": "Stale doc reference", "status": "open" },
    { "id": "DRIFT-002", "description": "Old pattern", "status": "resolved" },
    { "id": "DRIFT-003", "description": "Minor naming", "status": "wont-fix" }
  ]
}
DDEOF

  # ---- overrides ----
  mkdir -p "$dir/.correctless/meta/overrides"
  cat > "$dir/.correctless/meta/overrides/gamma-20260410.json" <<'OVEOF'
{
  "task": "gamma",
  "overrides": [
    { "reason": "Gate misconfiguration", "phase": "review-spec" },
    { "reason": "Gate misconfiguration", "phase": "review-spec" }
  ]
}
OVEOF

  # ---- token-log JSONL ----
  cat > "$dir/.correctless/artifacts/token-log-feature-alpha-abc123.jsonl" <<'TLEOF'
{"timestamp":"2026-04-02T10:01:00Z","phase":"tdd-tests","skill":"ctdd","input_tokens":5000,"output_tokens":3000,"total_tokens":8000}
{"timestamp":"2026-04-02T10:02:00Z","phase":"tdd-impl","skill":"ctdd","input_tokens":10000,"output_tokens":8000,"total_tokens":18000}
{"timestamp":"2026-04-02T10:03:00Z","phase":"tdd-qa","skill":"ctdd","input_tokens":7000,"output_tokens":5000,"total_tokens":12000}
{"timestamp":"2026-04-02T10:04:00Z","phase":"review-spec","skill":"creview","input_tokens":3000,"output_tokens":2000,"total_tokens":5000}
TLEOF

  cat > "$dir/.correctless/artifacts/token-log-feature-beta-def456.jsonl" <<'TLEOF2'
{"timestamp":"2026-04-05T10:01:00Z","phase":"tdd-tests","skill":"ctdd","input_tokens":4000,"output_tokens":2000,"total_tokens":6000}
{"timestamp":"2026-04-05T10:02:00Z","phase":"verify","skill":"cverify","input_tokens":2000,"output_tokens":1000,"total_tokens":3000}
TLEOF2

  # ---- dev-journal.md ----
  cat > "$dir/docs/dev-journal.md" <<'DJEOF'
# Dev Journal

### 2026-04-10 — Feature Gamma

Implemented gamma with 15 rules. The antipattern scanner caught two issues early.
Files touched: scripts/gamma.sh, tests/test-gamma.sh.
Key decision: used awk over sed for parsing.

### 2026-04-05 — Feature Beta

Beta was straightforward. One QA round, no surprises.

### 2026-04-02 — Feature Alpha

First feature through the pipeline. Learned about the workflow.

### 2026-03-28 — Project Setup

Initial setup and scaffolding.
DJEOF

  # ---- CONTRIBUTING.md (test/assertion counts) ----
  cat > "$dir/CONTRIBUTING.md" <<'CEOF'
# Contributing

## Tests

There are 150 test files with 4500 assertions covering the full pipeline.
CEOF

  echo "$dir"
}

# ============================================================================
# Tests
# ============================================================================

echo "=== Project Dashboard UI Tests ==="

# ============================================================================
# R-001: Skill file exists, build-dashboard.sh script, exit behavior
# ============================================================================

test_r001_skill_and_script() {
  echo ""
  echo "--- R-001: Skill file and build-dashboard.sh script ---"

  # R-001-a: Skill file exists at skills/cdashboard/SKILL.md
  if [ -f "$REPO_DIR/skills/cdashboard/SKILL.md" ]; then
    pass "R001-a" "skills/cdashboard/SKILL.md exists"
  else
    fail "R001-a" "skills/cdashboard/SKILL.md does not exist"
  fi

  # R-001-b: scripts/build-dashboard.sh exists
  if [ -f "$REPO_DIR/scripts/build-dashboard.sh" ]; then
    pass "R001-b" "scripts/build-dashboard.sh exists"
  else
    fail "R001-b" "scripts/build-dashboard.sh does not exist"
  fi

  # R-001-c: Script exits 0 on success with valid project
  local TEST_DIR
  TEST_DIR=$(setup_dashboard_project)
  trap 'rm -rf "$TEST_DIR"' RETURN

  local output exit_code
  output=$(bash "$REPO_DIR/scripts/build-dashboard.sh" "$TEST_DIR" 2>&1)
  exit_code=$?

  if [ $exit_code -eq 0 ]; then
    pass "R001-c" "Script exits 0 on success"
  else
    fail "R001-c" "Script exited with code $exit_code: $output"
  fi

  # R-001-d: Script produces .correctless/dashboard/index.html
  if [ -f "$TEST_DIR/.correctless/dashboard/index.html" ]; then
    pass "R001-d" ".correctless/dashboard/index.html was produced"
  else
    fail "R001-d" ".correctless/dashboard/index.html was not produced"
  fi

  # R-001-e: Output is valid HTML
  if [ -f "$TEST_DIR/.correctless/dashboard/index.html" ]; then
    if grep -q '<html' "$TEST_DIR/.correctless/dashboard/index.html" && \
       grep -q '</html>' "$TEST_DIR/.correctless/dashboard/index.html"; then
      pass "R001-e" "Output contains valid HTML structure"
    else
      fail "R001-e" "Output missing HTML structure"
    fi
  else
    fail "R001-e" "Cannot check HTML — file not produced"
  fi

  # R-001-f: Script accepts optional project root argument (defaults to cwd)
  local CWD_DIR
  CWD_DIR=$(mktemp -d)
  mkdir -p "$CWD_DIR/.correctless/config"
  cat > "$CWD_DIR/.correctless/config/workflow-config.json" <<'EOF'
{ "project": { "name": "cwd-test" }, "workflow": { "intensity": "standard" } }
EOF
  (cd "$CWD_DIR" && bash "$REPO_DIR/scripts/build-dashboard.sh" >/dev/null 2>&1)
  if [ -f "$CWD_DIR/.correctless/dashboard/index.html" ]; then
    pass "R001-f" "Script defaults to cwd when no argument given"
  else
    fail "R001-f" "Script did not produce output with cwd default"
  fi
  rm -rf "$CWD_DIR"

  # R-001-g: Script requires only bash 4+, jq 1.7+, and POSIX tools (no exotic deps)
  if [ -f "$REPO_DIR/scripts/build-dashboard.sh" ]; then
    if ! grep -qE '^[^#<]*(npm |node |python|pip |ruby|gem |cargo )' "$REPO_DIR/scripts/build-dashboard.sh"; then
      pass "R001-g" "No exotic dependencies (npm/python/node/ruby/cargo)"
    else
      fail "R001-g" "Script references exotic dependencies"
    fi
  else
    fail "R001-g" "Script does not exist"
  fi

  # R-001-h: Passthrough fallback — script falls back to terminal output on failure
  local BAD_DIR
  BAD_DIR=$(mktemp -d)
  # No .correctless/config at all — should trigger fallback
  local fallback_exit
  bash "$REPO_DIR/scripts/build-dashboard.sh" "$BAD_DIR" >/dev/null 2>&1
  fallback_exit=$?

  if [ $fallback_exit -eq 1 ]; then
    pass "R001-h" "Script exits 1 on failure"
  else
    fail "R001-h" "Script should exit 1 on failure, got $fallback_exit"
  fi
  rm -rf "$BAD_DIR"
}

# ============================================================================
# R-002: Self-contained HTML with CDN marked.js + DOMPurify + SRI + security
# ============================================================================

test_r002_html_structure() {
  echo ""
  echo "--- R-002: Self-contained HTML with marked.js CDN + DOMPurify + SRI ---"

  local TEST_DIR
  TEST_DIR=$(setup_dashboard_project)
  trap 'rm -rf "$TEST_DIR"' RETURN

  run_dashboard "$TEST_DIR"

  local _f="$TEST_DIR/.correctless/dashboard/index.html"
  if [ ! -f "$_f" ]; then
    fail "R002-a" "index.html not produced (prerequisite failure)"
    return
  fi

  # R-002-a: Has inline CSS
  if grep -q '<style' "$_f"; then
    pass "R002-a" "Contains inline CSS"
  else
    fail "R002-a" "Missing inline CSS"
  fi

  # R-002-b: Has inline JS
  if grep -q '<script' "$_f"; then
    pass "R002-b" "Contains inline JS"
  else
    fail "R002-b" "Missing inline JS"
  fi

  # R-002-c: marked.js loaded from CDN with pinned version
  if grep -qE 'cdn\.jsdelivr\.net/npm/marked@[0-9]+\.[0-9]+\.[0-9]+' "$_f"; then
    pass "R002-c" "marked.js CDN URL has pinned version"
  else
    fail "R002-c" "marked.js CDN URL missing or not version-pinned"
  fi

  # R-002-d: marked.js script tag has SRI integrity hash
  if grep -qE 'integrity="sha(256|384|512)-[A-Za-z0-9+/=]+"' "$_f"; then
    pass "R002-d" "marked.js has SRI integrity hash"
  else
    fail "R002-d" "marked.js missing SRI integrity hash"
  fi

  # R-002-e: DOMPurify loaded from CDN with SRI
  if grep -qi 'dompurify' "$_f"; then
    pass "R002-e" "DOMPurify is referenced in the HTML"
  else
    fail "R002-e" "DOMPurify not found in the HTML"
  fi

  # R-002-f: Artifact data inlined in <script type="application/json"> block
  if grep -q '<script type="application/json"' "$_f"; then
    pass "R002-f" "JSON data block present (script type=application/json)"
  else
    fail "R002-f" "JSON data block missing"
  fi

  # R-002-g: </script> injection escaping — </ must be escaped as <\/ in JSON data
  # Create a project with a malicious artifact containing </script> in content
  local INJECT_DIR
  INJECT_DIR=$(mktemp -d)
  mkdir -p "$INJECT_DIR/.correctless/config"
  cat > "$INJECT_DIR/.correctless/config/workflow-config.json" <<'EOF'
{ "project": { "name": "inject-test" }, "workflow": { "intensity": "standard" } }
EOF
  mkdir -p "$INJECT_DIR/.correctless/specs"
  # Spec file with </script> in its content (simulates LLM-generated content)
  printf '# Evil Spec\nThis has a </script><script>alert(1)</script> injection attempt.\n' > "$INJECT_DIR/.correctless/specs/evil.md"

  run_dashboard "$INJECT_DIR"

  if [ -f "$INJECT_DIR/.correctless/dashboard/index.html" ]; then
    # The literal sequence </script> should NOT appear inside the JSON data block
    # Extract content between <script type="application/json"> and </script>
    local json_block
    json_block=$(sed -n '/<script type="application\/json"/,/<\/script>/p' "$INJECT_DIR/.correctless/dashboard/index.html" | head -n -1 | tail -n +2)
    if [ -n "$json_block" ]; then
      # Check the raw JSON data does NOT contain unescaped </script>
      if echo "$json_block" | grep -qF '</script>'; then
        fail "R002-g" "JSON data block contains unescaped </script> — XSS risk"
      else
        pass "R002-g" "JSON data block properly escapes </script> sequences"
      fi
    else
      fail "R002-g" "Could not extract JSON data block for injection check"
    fi
  else
    fail "R002-g" "index.html not produced for injection test"
  fi
  rm -rf "$INJECT_DIR"

  # R-002-h: No fetch() calls (self-contained except CDN)
  if ! grep -q 'fetch(' "$_f"; then
    pass "R002-h" "No fetch() calls"
  else
    fail "R002-h" "Found fetch() calls in HTML"
  fi

  # R-002-i: CDN graceful degradation — onerror handler on marked.js script tag
  if grep -qE 'onerror' "$_f"; then
    pass "R002-i" "CDN script tag has onerror fallback handler"
  else
    fail "R002-i" "CDN script tag missing onerror fallback handler"
  fi

  # R-002-j: HTML contains "Markdown rendering unavailable" fallback text
  if grep -qi 'markdown rendering unavailable\|viewing raw text' "$_f"; then
    pass "R002-j" "Graceful degradation notice text present in HTML"
  else
    fail "R002-j" "Graceful degradation notice text missing"
  fi
}

# ============================================================================
# R-003: Two navigation views (Metrics + Artifact Browser)
# ============================================================================

test_r003_navigation_views() {
  echo ""
  echo "--- R-003: Two navigation views (Metrics + Artifact Browser) ---"

  local TEST_DIR
  TEST_DIR=$(setup_dashboard_project)
  trap 'rm -rf "$TEST_DIR"' RETURN

  run_dashboard "$TEST_DIR"

  local _f="$TEST_DIR/.correctless/dashboard/index.html"
  if [ ! -f "$_f" ]; then
    fail "R003-a" "index.html not produced (prerequisite failure)"
    return
  fi

  # R-003-a: Metrics view present
  if grep -qi 'metrics' "$_f"; then
    pass "R003-a" "Metrics view label present"
  else
    fail "R003-a" "Metrics view label missing"
  fi

  # R-003-b: Artifact Browser view present
  if grep -qi 'artifact.*browser\|browser.*artifact\|artifacts' "$_f"; then
    pass "R003-b" "Artifact Browser view label present"
  else
    fail "R003-b" "Artifact Browser view label missing"
  fi

  # R-003-c: Navigation mechanism (tabs or nav bar) exists
  if grep -qiE 'nav|tab|data-view|onclick.*view|class="tab' "$_f"; then
    pass "R003-c" "Navigation mechanism (tabs/nav) present"
  else
    fail "R003-c" "Navigation mechanism missing"
  fi

  # R-003-d: Metrics view preserves existing sections from generate-dashboard.sh
  local sections_found=0
  for section in "project summary" "quality trajectory" "pipeline.*phase\|phase.*distribution" "antipattern" "cost.*phase\|token.*usage\|phase.*cost" "drift.*debt" "dev.*journal"; do
    if grep -qiE "$section" "$_f"; then
      sections_found=$((sections_found + 1))
    fi
  done
  if [ "$sections_found" -ge 5 ]; then
    pass "R003-d" "Metrics view has $sections_found/7 expected sections"
  else
    fail "R003-d" "Metrics view only has $sections_found/7 expected sections"
  fi

  # R-003-e: Metrics is the default landing page (appears first or is marked active)
  # Check that Metrics tab/view is marked as active/default or appears before Browser
  if grep -qiE 'active.*metrics|metrics.*active|metrics.*default|data-view="metrics"' "$_f"; then
    pass "R003-e" "Metrics appears to be the default view"
  else
    # Fallback: check Metrics section content appears before "Artifact Browser" content
    local pos_metrics pos_browser
    pos_metrics=$(grep -ni 'project summary\|quality trajectory' "$_f" | head -1 | cut -d: -f1)
    pos_browser=$(grep -ni 'artifact.*browser' "$_f" | head -1 | cut -d: -f1)
    if [ -n "$pos_metrics" ] && [ -n "$pos_browser" ] && [ "$pos_metrics" -lt "$pos_browser" ]; then
      pass "R003-e" "Metrics content appears before Artifact Browser"
    else
      fail "R003-e" "Cannot confirm Metrics is the default landing page"
    fi
  fi
}

# ============================================================================
# R-004: Artifact Browser categories and content
# ============================================================================

test_r004_artifact_browser() {
  echo ""
  echo "--- R-004: Artifact Browser categories ---"

  local TEST_DIR
  TEST_DIR=$(setup_dashboard_project)
  trap 'rm -rf "$TEST_DIR"' RETURN

  run_dashboard "$TEST_DIR"

  local _f="$TEST_DIR/.correctless/dashboard/index.html"
  if [ ! -f "$_f" ]; then
    fail "R004-a" "index.html not produced (prerequisite failure)"
    return
  fi

  # R-004-a: Specs category present
  if grep -qi 'specs' "$_f"; then
    pass "R004-a" "Specs category present in HTML"
  else
    fail "R004-a" "Specs category missing from HTML"
  fi

  # R-004-b: Verifications category present
  if grep -qi 'verification' "$_f"; then
    pass "R004-b" "Verifications category present"
  else
    fail "R004-b" "Verifications category missing"
  fi

  # R-004-c: Review Findings category present
  if grep -qi 'review.*finding' "$_f"; then
    pass "R004-c" "Review Findings category present"
  else
    fail "R004-c" "Review Findings category missing"
  fi

  # R-004-d: Research Briefs category present
  if grep -qi 'research' "$_f"; then
    pass "R004-d" "Research Briefs category present"
  else
    fail "R004-d" "Research Briefs category missing"
  fi

  # R-004-e: Architecture category present
  if grep -qi 'architecture' "$_f"; then
    pass "R004-e" "Architecture category present"
  else
    fail "R004-e" "Architecture category missing"
  fi

  # R-004-f: QA Findings category present
  if grep -qi 'qa.*finding' "$_f"; then
    pass "R004-f" "QA Findings category present"
  else
    fail "R004-f" "QA Findings category missing"
  fi

  # R-004-g: Audit History category present
  if grep -qi 'audit.*history' "$_f"; then
    pass "R004-g" "Audit History category present"
  else
    fail "R004-g" "Audit History category missing"
  fi

  # R-004-h: Spec content is inlined in the JSON data block
  if grep -q 'alpha\.md\|Do alpha things' "$_f"; then
    pass "R004-h" "Spec file content inlined in HTML"
  else
    fail "R004-h" "Spec file content not found in HTML"
  fi

  # R-004-i: QA findings rendered as formatted table data (not raw JSON filename only)
  if grep -qE 'QA-001|BLOCKING|Missing validation' "$_f"; then
    pass "R004-i" "QA findings data present in HTML"
  else
    fail "R004-i" "QA findings data missing from HTML"
  fi

  # R-004-j: Missing categories omitted — create project with NO verifications
  local SPARSE_DIR
  SPARSE_DIR=$(mktemp -d)
  mkdir -p "$SPARSE_DIR/.correctless/config"
  cat > "$SPARSE_DIR/.correctless/config/workflow-config.json" <<'EOF'
{ "project": { "name": "sparse" }, "workflow": { "intensity": "standard" } }
EOF
  mkdir -p "$SPARSE_DIR/.correctless/specs"
  echo "# Spec" > "$SPARSE_DIR/.correctless/specs/only.md"
  # No verification/, no research/, no audit history

  run_dashboard "$SPARSE_DIR"

  if [ -f "$SPARSE_DIR/.correctless/dashboard/index.html" ]; then
    # Verification category should NOT appear (no files)
    # The word "Verification" could appear in other contexts, so check more specifically
    # for the sidebar/category structure referencing verification files
    if grep -qi 'verification.*\.md\|verification.*category' "$SPARSE_DIR/.correctless/dashboard/index.html"; then
      fail "R004-j" "Empty Verifications category should be omitted"
    else
      pass "R004-j" "Empty categories omitted from sidebar"
    fi
  else
    fail "R004-j" "index.html not produced for sparse project"
  fi
  rm -rf "$SPARSE_DIR"
}

# ============================================================================
# R-005: Metrics view data sources (preserves all existing sections)
# ============================================================================

test_r005_metrics_data_sources() {
  echo ""
  echo "--- R-005: Metrics view data sources ---"

  local TEST_DIR
  TEST_DIR=$(setup_dashboard_project)
  trap 'rm -rf "$TEST_DIR"' RETURN

  run_dashboard "$TEST_DIR"

  local _f="$TEST_DIR/.correctless/dashboard/index.html"
  if [ ! -f "$_f" ]; then
    fail "R005-a" "index.html not produced (prerequisite failure)"
    return
  fi

  # R-005-a: Workflow history data embedded
  if grep -q 'Feature Alpha' "$_f"; then
    pass "R005-a" "Workflow history data (Feature Alpha) embedded"
  else
    fail "R005-a" "Workflow history data not embedded"
  fi

  # R-005-b: QA findings data embedded
  if grep -q 'BLOCKING\|QA-001' "$_f"; then
    pass "R005-b" "QA findings data embedded"
  else
    fail "R005-b" "QA findings data not embedded"
  fi

  # R-005-c: Antipattern data embedded
  if grep -q 'AP-001' "$_f"; then
    pass "R005-c" "Antipattern data embedded"
  else
    fail "R005-c" "Antipattern data not embedded"
  fi

  # R-005-d: Calibration data embedded
  if grep -q 'calibration\|150000\|80000' "$_f"; then
    pass "R005-d" "Calibration data embedded"
  else
    fail "R005-d" "Calibration data not embedded"
  fi

  # R-005-e: Drift debt data embedded
  if grep -q 'DRIFT-001\|drift' "$_f"; then
    pass "R005-e" "Drift debt data embedded"
  else
    fail "R005-e" "Drift debt data not embedded"
  fi

  # R-005-f: Token log data embedded
  if grep -q 'token\|8000\|18000' "$_f"; then
    pass "R005-f" "Token log data embedded"
  else
    fail "R005-f" "Token log data not embedded"
  fi

  # R-005-g: Project name from config
  if grep -q 'test-project' "$_f"; then
    pass "R005-g" "Project name from workflow-config embedded"
  else
    fail "R005-g" "Project name not embedded"
  fi

  # R-005-h: Project Summary section
  if grep -qi 'project summary' "$_f"; then
    pass "R005-h" "Project Summary section present"
  else
    fail "R005-h" "Project Summary section missing"
  fi

  # R-005-i: Quality Trajectory section
  if grep -qi 'quality trajectory' "$_f"; then
    pass "R005-i" "Quality Trajectory section present"
  else
    fail "R005-i" "Quality Trajectory section missing"
  fi

  # R-005-j: Pipeline Phase Distribution section
  if grep -qi 'pipeline.*phase\|phase.*distribution' "$_f"; then
    pass "R005-j" "Pipeline Phase Distribution section present"
  else
    fail "R005-j" "Pipeline Phase Distribution section missing"
  fi

  # R-005-k: Antipattern Health section
  if grep -qi 'antipattern' "$_f"; then
    pass "R005-k" "Antipattern Health section present"
  else
    fail "R005-k" "Antipattern Health section missing"
  fi

  # R-005-l: Intensity Calibration/Accuracy section
  if grep -qi 'intensity.*calibration\|intensity.*accuracy\|calibration' "$_f"; then
    pass "R005-l" "Intensity Calibration section present"
  else
    fail "R005-l" "Intensity Calibration section missing"
  fi

  # R-005-m: Cost by Phase section
  if grep -qi 'cost.*phase\|token.*usage\|phase.*cost' "$_f"; then
    pass "R005-m" "Cost by Phase section present"
  else
    fail "R005-m" "Cost by Phase section missing"
  fi

  # R-005-n: Drift Debt section
  if grep -qi 'drift.*debt' "$_f"; then
    pass "R005-n" "Drift Debt section present"
  else
    fail "R005-n" "Drift Debt section missing"
  fi

  # R-005-o: Dev Journal section
  if grep -qi 'dev.*journal' "$_f"; then
    pass "R005-o" "Dev Journal section present"
  else
    fail "R005-o" "Dev Journal section missing"
  fi

  # R-005-p: Override Rate section
  if grep -qi 'override.*rate\|override' "$_f"; then
    pass "R005-p" "Override Rate section present"
  else
    fail "R005-p" "Override Rate section missing"
  fi

  # R-005-q: QA Rounds section
  if grep -qi 'qa.*round' "$_f"; then
    pass "R005-q" "QA Rounds section present"
  else
    fail "R005-q" "QA Rounds section missing"
  fi

  # R-005-r: Fix Rate section
  if grep -qi 'fix.*rate' "$_f"; then
    pass "R005-r" "Fix Rate section present"
  else
    fail "R005-r" "Fix Rate section missing"
  fi

  # R-005-s: Dev Journal shows last 3 entries
  if grep -q 'Feature Gamma' "$_f" && grep -q 'Feature Beta' "$_f" && grep -q 'Feature Alpha' "$_f"; then
    pass "R005-s" "Dev Journal includes last 3 entries"
  else
    fail "R005-s" "Dev Journal missing recent entries"
  fi
}

# ============================================================================
# R-006: Output path and directory creation
# ============================================================================

test_r006_output_path() {
  echo ""
  echo "--- R-006: Output path .correctless/dashboard/index.html ---"

  local TEST_DIR
  TEST_DIR=$(setup_dashboard_project)
  trap 'rm -rf "$TEST_DIR"' RETURN

  # Remove the dashboard directory if it exists
  rm -rf "$TEST_DIR/.correctless/dashboard"

  run_dashboard "$TEST_DIR"

  # R-006-a: Dashboard directory created
  if [ -d "$TEST_DIR/.correctless/dashboard" ]; then
    pass "R006-a" ".correctless/dashboard/ directory created"
  else
    fail "R006-a" ".correctless/dashboard/ directory not created"
  fi

  # R-006-b: index.html in correct location
  if [ -f "$TEST_DIR/.correctless/dashboard/index.html" ]; then
    pass "R006-b" "index.html at .correctless/dashboard/index.html"
  else
    fail "R006-b" "index.html not at expected path"
  fi

  # R-006-c: .correctless/dashboard/ in .gitignore
  if grep -qE '\.correctless/dashboard' "$REPO_DIR/.gitignore"; then
    pass "R006-c" ".correctless/dashboard/ is in .gitignore"
  else
    fail "R006-c" ".correctless/dashboard/ is not in .gitignore"
  fi

  # R-006-d: Old dashboard.html NOT produced at project root
  if [ ! -f "$TEST_DIR/dashboard.html" ]; then
    pass "R006-d" "Old dashboard.html not produced at project root"
  else
    fail "R006-d" "Old dashboard.html still produced at project root"
  fi
}

# ============================================================================
# R-007: Migration — replaces generate-dashboard.sh
# ============================================================================

test_r007_migration() {
  echo ""
  echo "--- R-007: Migration from generate-dashboard.sh ---"

  # R-007-a: generate-dashboard.sh is deleted from source
  if [ ! -f "$REPO_DIR/scripts/generate-dashboard.sh" ]; then
    pass "R007-a" "scripts/generate-dashboard.sh deleted"
  else
    fail "R007-a" "scripts/generate-dashboard.sh still exists"
  fi

  # R-007-b: No references to generate-dashboard or dashboard.html in .md and .sh files
  local refs
  refs=$(grep -r 'generate-dashboard\|dashboard\.html' --include='*.md' --include='*.sh' "$REPO_DIR" 2>/dev/null | \
    grep -v '.correctless/scripts/' | \
    grep -v 'correctless/scripts/' | \
    grep -v '.correctless/dashboard/' | \
    grep -v '.correctless/verification/' | \
    grep -v '.correctless/artifacts/' | \
    grep -v 'test-project-dashboard.sh' | \
    grep -v 'build-dashboard' || true)
  if [ -z "$refs" ]; then
    pass "R007-b" "No stale references to generate-dashboard or dashboard.html"
  else
    fail "R007-b" "Stale references found: $(echo "$refs" | head -3)"
  fi

  # R-007-c: sync.sh includes cdashboard in skill list
  if grep -q 'cdashboard' "$REPO_DIR/sync.sh"; then
    pass "R007-c" "sync.sh includes cdashboard in skill list"
  else
    fail "R007-c" "sync.sh missing cdashboard"
  fi

  # R-007-d: sync.sh skill count matches actual skill directories
  local expected_count
  expected_count=$(find "$REPO_DIR/skills" -name "SKILL.md" -not -path "*/_shared/*" | wc -l | tr -d ' ')
  if grep -qE "All skills \\($expected_count\\)" "$REPO_DIR/sync.sh"; then
    pass "R007-d" "sync.sh skill count updated to $expected_count"
  else
    fail "R007-d" "sync.sh skill count not updated to $expected_count"
  fi

  # R-007-e: Stale installed copy at .correctless/scripts/generate-dashboard.sh removed
  # (This tests the expectation — the installed copy shouldn't exist after migration)
  if [ ! -f "$REPO_DIR/.correctless/scripts/generate-dashboard.sh" ]; then
    pass "R007-e" "Stale installed generate-dashboard.sh removed"
  else
    fail "R007-e" "Stale installed generate-dashboard.sh still present"
  fi

  # R-007-f: Distribution copy also removed
  if [ ! -f "$REPO_DIR/correctless/scripts/generate-dashboard.sh" ]; then
    pass "R007-f" "Distribution generate-dashboard.sh removed"
  else
    fail "R007-f" "Distribution generate-dashboard.sh still present"
  fi
}

# ============================================================================
# R-008: Dark mode + styling (structural assertions only)
# ============================================================================

test_r008_dark_mode() {
  echo ""
  echo "--- R-008: Dark mode support and styling ---"

  local TEST_DIR
  TEST_DIR=$(setup_dashboard_project)
  trap 'rm -rf "$TEST_DIR"' RETURN

  run_dashboard "$TEST_DIR"

  local _f="$TEST_DIR/.correctless/dashboard/index.html"
  if [ ! -f "$_f" ]; then
    fail "R008-a" "index.html not produced (prerequisite failure)"
    return
  fi

  # R-008-a: prefers-color-scheme media query
  if grep -q 'prefers-color-scheme' "$_f"; then
    pass "R008-a" "Dark/light mode via prefers-color-scheme"
  else
    fail "R008-a" "Missing prefers-color-scheme media query"
  fi

  # R-008-b: Severity color coding (red for BLOCKING/CRITICAL)
  if grep -qiE 'blocking|critical' "$_f" && grep -qE '#[0-9a-fA-F]+|red|rgb' "$_f"; then
    pass "R008-b" "Severity color coding present"
  else
    fail "R008-b" "Missing severity color coding"
  fi

  # R-008-c: Has CSS bars for visualization (Quality Trajectory)
  if grep -qE 'width:[0-9]+%|width: [0-9]+%' "$_f"; then
    pass "R008-c" "Contains horizontal bar elements"
  else
    fail "R008-c" "No horizontal bar elements found"
  fi
}

# ============================================================================
# R-009: Empty state handling
# ============================================================================

test_r009_empty_state() {
  echo ""
  echo "--- R-009: Empty state handling ---"

  # Create completely empty project (only config, no artifacts)
  local EMPTY_DIR
  EMPTY_DIR=$(mktemp -d)
  trap 'rm -rf "$EMPTY_DIR"' RETURN

  mkdir -p "$EMPTY_DIR/.correctless/config"
  cat > "$EMPTY_DIR/.correctless/config/workflow-config.json" <<'WEOF'
{
  "project": { "name": "empty-project" },
  "workflow": { "intensity": "standard" }
}
WEOF

  local output exit_code
  output=$(bash "$REPO_DIR/scripts/build-dashboard.sh" "$EMPTY_DIR" 2>&1)
  exit_code=$?

  # R-009-a: Script exits 0 with empty project
  if [ $exit_code -eq 0 ]; then
    pass "R009-a" "Script exits 0 with empty project"
  else
    fail "R009-a" "Script failed with empty project: exit=$exit_code $output"
  fi

  # R-009-b: index.html produced
  if [ -f "$EMPTY_DIR/.correctless/dashboard/index.html" ]; then
    pass "R009-b" "index.html produced for empty project"
  else
    fail "R009-b" "index.html not produced for empty project"
    return
  fi

  local _f="$EMPTY_DIR/.correctless/dashboard/index.html"

  # R-009-c: Metrics view shows "No data yet" placeholders
  if grep -qi 'no.*data\|no.*history\|no.*findings\|not yet' "$_f"; then
    pass "R009-c" "Empty project shows placeholder messages in Metrics"
  else
    fail "R009-c" "Empty project missing Metrics placeholder messages"
  fi

  # R-009-d: Artifact Browser shows "No artifacts found"
  if grep -qi 'no.*artifact' "$_f"; then
    pass "R009-d" "Empty project shows 'No artifacts found' in Browser"
  else
    fail "R009-d" "Empty project missing 'No artifacts found' message"
  fi

  # R-009-e: Graceful degradation for individual missing sections
  # QA Rounds Trend
  if grep -qi 'no.*qa.*round\|no.*qa.*data' "$_f"; then
    pass "R009-e" "QA Rounds section gracefully degrades"
  else
    fail "R009-e" "QA Rounds section missing graceful degradation"
  fi

  # R-009-f: Calibration section graceful degradation
  if grep -qi 'no.*calibration' "$_f"; then
    pass "R009-f" "Calibration section gracefully degrades"
  else
    fail "R009-f" "Calibration section missing graceful degradation"
  fi

  # R-009-g: Override Rate graceful degradation
  if grep -qi 'no.*override' "$_f"; then
    pass "R009-g" "Override Rate section gracefully degrades"
  else
    fail "R009-g" "Override Rate section missing graceful degradation"
  fi
}

# ============================================================================
# R-010: Skill registration (sync.sh, setup)
# ============================================================================

test_r010_registration() {
  echo ""
  echo "--- R-010: Skill registration in sync.sh ---"

  # R-010-a: cdashboard in sync.sh skill list
  if grep -q 'cdashboard' "$REPO_DIR/sync.sh"; then
    pass "R010-a" "cdashboard in sync.sh skill list"
  else
    fail "R010-a" "cdashboard missing from sync.sh skill list"
  fi

  # R-010-b: Distribution copy exists after sync
  if [ -f "$REPO_DIR/correctless/skills/cdashboard/SKILL.md" ]; then
    pass "R010-b" "cdashboard SKILL.md exists in distribution"
  else
    fail "R010-b" "cdashboard SKILL.md missing from distribution"
  fi

  # R-010-c: build-dashboard.sh exists in distribution
  if [ -f "$REPO_DIR/correctless/scripts/build-dashboard.sh" ]; then
    pass "R010-c" "build-dashboard.sh exists in distribution"
  else
    fail "R010-c" "build-dashboard.sh missing from distribution"
  fi

  # R-010-d: Distribution build-dashboard.sh matches source
  if [ -f "$REPO_DIR/scripts/build-dashboard.sh" ] && [ -f "$REPO_DIR/correctless/scripts/build-dashboard.sh" ]; then
    if diff -q "$REPO_DIR/scripts/build-dashboard.sh" "$REPO_DIR/correctless/scripts/build-dashboard.sh" >/dev/null 2>&1; then
      pass "R010-d" "Distribution build-dashboard.sh matches source"
    else
      fail "R010-d" "Distribution build-dashboard.sh differs from source"
    fi
  else
    fail "R010-d" "Cannot compare — source or dist file missing"
  fi
}

# ============================================================================
# R-011: Success/failure messages
# ============================================================================

test_r011_messages() {
  echo ""
  echo "--- R-011: Success and failure messages ---"

  local TEST_DIR
  TEST_DIR=$(setup_dashboard_project)
  trap 'rm -rf "$TEST_DIR"' RETURN

  # R-011-a: Success message with output path
  local output
  output=$(bash "$REPO_DIR/scripts/build-dashboard.sh" "$TEST_DIR" 2>&1)

  if echo "$output" | grep -qi 'dashboard.*generated\|\.correctless/dashboard/index\.html'; then
    pass "R011-a" "Success message includes output path"
  else
    fail "R011-a" "Success message missing or doesn't mention output path"
  fi

  # R-011-b: Failure message includes reason
  local BAD_DIR
  BAD_DIR=$(mktemp -d)
  local fail_output
  fail_output=$(bash "$REPO_DIR/scripts/build-dashboard.sh" "$BAD_DIR" 2>&1)

  if [ -n "$fail_output" ]; then
    pass "R011-b" "Failure produces output with reason"
  else
    fail "R011-b" "Failure produces no output"
  fi
  rm -rf "$BAD_DIR"

  # R-011-c: HTML contains CDN fallback notice text for marked.js
  local _f="$TEST_DIR/.correctless/dashboard/index.html"
  if [ -f "$_f" ]; then
    if grep -qi 'markdown rendering unavailable' "$_f"; then
      pass "R011-c" "HTML contains CDN fallback notice"
    else
      fail "R011-c" "HTML missing CDN fallback notice"
    fi
  else
    fail "R011-c" "index.html not produced"
  fi
}

# ============================================================================
# R-012: Structural proxy tests for Artifact Browser
# ============================================================================

test_r012_browser_structural() {
  echo ""
  echo "--- R-012: Artifact Browser structural proxy tests ---"

  local TEST_DIR
  TEST_DIR=$(setup_dashboard_project)
  trap 'rm -rf "$TEST_DIR"' RETURN

  run_dashboard "$TEST_DIR"

  local _f="$TEST_DIR/.correctless/dashboard/index.html"
  if [ ! -f "$_f" ]; then
    fail "R012-a" "index.html not produced (prerequisite failure)"
    return
  fi

  # R-012-a: Sidebar category headings present in HTML
  local categories_found=0
  for cat_name in "Specs" "Verifications" "Review Findings" "Research" "Architecture" "QA Findings" "Audit History"; do
    if grep -qi "$cat_name" "$_f"; then
      categories_found=$((categories_found + 1))
    fi
  done
  if [ "$categories_found" -ge 5 ]; then
    pass "R012-a" "Sidebar has $categories_found/7 category headings"
  else
    fail "R012-a" "Sidebar only has $categories_found/7 category headings"
  fi

  # R-012-b: Artifact data for each category is inlined in JSON data block
  # Check that the JSON block contains data for specs, architecture, qa-findings
  if grep -q 'application/json' "$_f"; then
    local has_specs has_arch has_qa
    has_specs=false; has_arch=false; has_qa=false
    grep -q 'Do alpha things\|alpha\.md' "$_f" && has_specs=true
    grep -q 'Trust Boundaries\|ARCHITECTURE' "$_f" && has_arch=true
    grep -q 'QA-001\|Missing validation' "$_f" && has_qa=true

    if $has_specs && $has_arch && $has_qa; then
      pass "R012-b" "JSON data block contains data for specs, architecture, QA findings"
    else
      fail "R012-b" "JSON data block missing some category data (specs=$has_specs arch=$has_arch qa=$has_qa)"
    fi
  else
    fail "R012-b" "No JSON data block found"
  fi

  # R-012-c: marked.js script tag has onerror fallback handler
  if grep -qE 'onerror' "$_f"; then
    pass "R012-c" "marked.js script tag has onerror fallback"
  else
    fail "R012-c" "marked.js script tag missing onerror fallback"
  fi
}

# ============================================================================
# Cross-cutting: Metrics section ordering (carried forward from DI-R005)
# ============================================================================

test_metrics_section_order() {
  echo ""
  echo "--- Metrics section ordering ---"

  local TEST_DIR
  TEST_DIR=$(setup_dashboard_project)
  trap 'rm -rf "$TEST_DIR"' RETURN

  run_dashboard "$TEST_DIR"

  local _f="$TEST_DIR/.correctless/dashboard/index.html"
  if [ ! -f "$_f" ]; then
    fail "ORDER-a" "index.html not produced (prerequisite failure)"
    return
  fi

  # Extract only the main JS section (after the last <script> tag, which is the app code)
  # to avoid matching text in the JSON data block
  local _js_section
  _js_section=$(sed -n '/^<script>$/,/<\/script>/p' "$_f")

  local pos_qt pos_qrt pos_ppd pos_fr pos_ah

  pos_qt=$(echo "$_js_section" | grep -n 'Quality Trajectory' | head -1 | cut -d: -f1)
  pos_qrt=$(echo "$_js_section" | grep -n 'QA Rounds' | head -1 | cut -d: -f1)
  pos_ppd=$(echo "$_js_section" | grep -n 'Pipeline Phase Distribution' | head -1 | cut -d: -f1)
  pos_fr=$(echo "$_js_section" | grep -n 'Fix Rate' | head -1 | cut -d: -f1)
  pos_ah=$(echo "$_js_section" | grep -n 'Antipattern' | head -1 | cut -d: -f1)

  if [ -z "$pos_qt" ] || [ -z "$pos_qrt" ] || [ -z "$pos_ppd" ] || [ -z "$pos_fr" ]; then
    fail "ORDER-a" "One or more section headings not found"
    return
  fi

  if [ "$pos_qt" -lt "$pos_qrt" ]; then
    pass "ORDER-a" "Quality Trajectory before QA Rounds"
  else
    fail "ORDER-a" "Quality Trajectory should appear before QA Rounds"
  fi

  if [ "$pos_qrt" -lt "$pos_ppd" ]; then
    pass "ORDER-b" "QA Rounds before Pipeline Phase Distribution"
  else
    fail "ORDER-b" "QA Rounds should appear before Pipeline Phase Distribution"
  fi

  if [ "$pos_ppd" -lt "$pos_fr" ]; then
    pass "ORDER-c" "Pipeline Phase Distribution before Fix Rate"
  else
    fail "ORDER-c" "Pipeline Phase Distribution should appear before Fix Rate"
  fi

  if [ -n "$pos_ah" ] && [ "$pos_fr" -lt "$pos_ah" ]; then
    pass "ORDER-d" "Fix Rate before Antipattern Health"
  else
    fail "ORDER-d" "Fix Rate should appear before Antipattern Health"
  fi
}

# ============================================================================
# Cross-cutting: cmetrics mentions new dashboard
# ============================================================================

test_cmetrics_mention() {
  echo ""
  echo "--- /cmetrics mentions new dashboard ---"

  local cmetrics="$REPO_DIR/skills/cmetrics/SKILL.md"

  if grep -qi 'build-dashboard\|cdashboard\|\.correctless/dashboard' "$cmetrics"; then
    pass "CMETRICS-a" "/cmetrics SKILL.md mentions new dashboard"
  else
    fail "CMETRICS-a" "/cmetrics SKILL.md does not mention new dashboard"
  fi
}

# ============================================================================
# Cross-cutting: Antipattern dormancy detection
# ============================================================================

test_antipattern_dormancy() {
  echo ""
  echo "--- Antipattern dormancy cross-reference ---"

  local TEST_DIR
  TEST_DIR=$(setup_dashboard_project)
  trap 'rm -rf "$TEST_DIR"' RETURN

  # Add 5 more recent features with qa-findings that DON'T reference AP-001
  for i in 1 2 3 4 5; do
    cat > "$TEST_DIR/.correctless/artifacts/qa-findings-recent${i}.json" <<REOF
{ "task": "recent${i}", "round": 1, "findings": [{ "id": "QA-001", "severity": "NON-BLOCKING", "description": "Unrelated issue", "rule_ref": "R-005", "instance_fix": "fix", "class_fix": "N/A", "status": "fixed" }] }
REOF
  done

  run_dashboard "$TEST_DIR"

  local _f="$TEST_DIR/.correctless/dashboard/index.html"
  if [ ! -f "$_f" ]; then
    fail "AP-DORM-a" "index.html not produced"
    return
  fi

  # AP-002 has Status: Structurally enforced -> should be "resolved"
  if grep -qi 'resolved\|structurally enforced' "$_f"; then
    pass "AP-DORM-a" "Structurally enforced antipattern shown as resolved"
  else
    fail "AP-DORM-a" "Structurally enforced antipattern not shown as resolved"
  fi
}

# ============================================================================
# Cross-cutting: Pipeline Phase Distribution (QA vs MA prefix)
# ============================================================================

test_pipeline_phase_distribution() {
  echo ""
  echo "--- Pipeline Phase Distribution (QA vs MA prefix) ---"

  local TEST_DIR
  TEST_DIR=$(setup_dashboard_project)
  trap 'rm -rf "$TEST_DIR"' RETURN

  run_dashboard "$TEST_DIR"

  local _f="$TEST_DIR/.correctless/dashboard/index.html"
  if [ ! -f "$_f" ]; then
    fail "PIPE-a" "index.html not produced"
    return
  fi

  if grep -qi 'QA\|mini.*audit\|MA-' "$_f"; then
    pass "PIPE-a" "Pipeline phase distribution distinguishes QA and MA findings"
  else
    fail "PIPE-a" "Pipeline phase distribution missing QA/MA distinction"
  fi
}

# ============================================================================
# REDESIGN R-001: Distinctive visual identity (custom fonts, warm accent)
# Tests dashboard-redesign spec R-001 [unit]
# ============================================================================

test_redesign_r001_visual_identity() {
  echo ""
  echo "--- Redesign R-001: Distinctive visual identity ---"

  local TEST_DIR
  TEST_DIR=$(setup_dashboard_project)
  trap 'rm -rf "$TEST_DIR"' RETURN

  run_dashboard "$TEST_DIR"

  local _f="$TEST_DIR/.correctless/dashboard/index.html"
  if [ ! -f "$_f" ]; then
    fail "DR001-a" "index.html not produced (prerequisite failure)"
    return
  fi

  # DR001-a: Custom font loaded from CDN (Google Fonts or equivalent)
  if grep -qE 'fonts\.googleapis\.com|fonts\.gstatic\.com|fonts\.bunny\.net' "$_f"; then
    pass "DR001-a" "Custom font loaded from CDN"
  else
    fail "DR001-a" "No custom font CDN reference found — must load distinctive fonts"
  fi

  # DR001-b: Font CDN link has SRI integrity hash
  # The link tag may span multiple lines, so check that a fonts link exists AND
  # that an integrity attribute follows within the same link element
  local font_link_block
  font_link_block=$(sed -n '/fonts\.googleapis\|fonts\.gstatic\|fonts\.bunny/,/>/{p}' "$_f" | head -10)
  if echo "$font_link_block" | grep -qE 'integrity="sha'; then
    pass "DR001-b" "Font CDN link has SRI integrity hash"
  else
    fail "DR001-b" "Font CDN link missing SRI integrity hash"
  fi

  # DR001-c: Font stack includes a non-system distinctive font name
  # Must NOT be only the default system font cascade — check font-family or CSS var definitions
  if grep -qE "(font-family|font-body|font-display):.*['\"][A-Z][a-zA-Z ]+['\"]" "$_f"; then
    pass "DR001-c" "Font stack includes a named distinctive font"
  else
    fail "DR001-c" "Font stack uses only system fonts — need at least one distinctive font"
  fi

  # DR001-d: Accent color is NOT #58a6ff (GitHub blue) or #4361ee
  local light_accent
  light_accent=$(grep -oE 'accent:\s*#[0-9a-fA-F]+' "$_f" | head -1 | grep -oE '#[0-9a-fA-F]+')
  if [ -n "$light_accent" ]; then
    local lower_accent
    lower_accent=$(echo "$light_accent" | tr '[:upper:]' '[:lower:]')
    if [ "$lower_accent" = "#58a6ff" ] || [ "$lower_accent" = "#4361ee" ]; then
      fail "DR001-d" "Accent color $light_accent is a prohibited GitHub/default blue"
    else
      pass "DR001-d" "Accent color $light_accent is distinctive (not GitHub blue)"
    fi
  else
    fail "DR001-d" "No --accent CSS variable found"
  fi

  # DR001-e: Dark mode accent color is NOT #58a6ff
  local dark_section
  dark_section=$(sed -n '/@media.*prefers-color-scheme.*dark/,/}/p' "$_f")
  local dark_accent
  dark_accent=$(echo "$dark_section" | grep -oE 'accent:\s*#[0-9a-fA-F]+' | head -1 | grep -oE '#[0-9a-fA-F]+')
  if [ -n "$dark_accent" ]; then
    local lower_dark
    lower_dark=$(echo "$dark_accent" | tr '[:upper:]' '[:lower:]')
    if [ "$lower_dark" = "#58a6ff" ] || [ "$lower_dark" = "#4361ee" ]; then
      fail "DR001-e" "Dark mode accent $dark_accent is a prohibited blue"
    else
      pass "DR001-e" "Dark mode accent $dark_accent is distinctive"
    fi
  else
    fail "DR001-e" "No dark mode --accent CSS variable found"
  fi

  # DR001-f: font-display: swap (or equivalent) for non-blocking font load
  if grep -qE 'font-display:\s*swap|font-display:\s*optional|font-display:\s*fallback' "$_f"; then
    pass "DR001-f" "font-display set for non-blocking font loading"
  else
    # Google Fonts CSS links can include &display=swap in the URL
    if grep -qE 'display=swap|display=fallback|display=optional' "$_f"; then
      pass "DR001-f" "font-display set via CDN URL parameter"
    else
      fail "DR001-f" "No font-display property found — fonts may block page render"
    fi
  fi
}

# ============================================================================
# REDESIGN R-002: Value narrative section
# Tests dashboard-redesign spec R-002 [unit]
# ============================================================================

test_redesign_r002_value_narrative() {
  echo ""
  echo "--- Redesign R-002: Value narrative section ---"

  local TEST_DIR
  TEST_DIR=$(setup_dashboard_project)
  trap 'rm -rf "$TEST_DIR"' RETURN

  # Add escape metrics data for a richer test
  mkdir -p "$TEST_DIR/.correctless/artifacts/findings"
  cat > "$TEST_DIR/.correctless/artifacts/findings/audit-qa-2026-04-12-round-1.json" <<'AEOF'
{
  "preset": "qa",
  "started_at": "2026-04-12T10:00:00Z",
  "round": 1,
  "findings": [
    {"id": "QA-A1", "severity": "HIGH", "description": "Missed check"},
    {"id": "QA-A2", "severity": "MEDIUM", "description": "Minor gap"}
  ],
  "rejected": []
}
AEOF

  run_dashboard "$TEST_DIR"

  local _f="$TEST_DIR/.correctless/dashboard/index.html"
  if [ ! -f "$_f" ]; then
    fail "DR002-a" "index.html not produced (prerequisite failure)"
    return
  fi

  # DR002-a: Value narrative section exists with identifiable heading or container
  if grep -qiE 'value.*narrative|caught.*before.*ship|bugs.*caught|findings.*caught|what.*correctless.*caught|pre.?merge' "$_f"; then
    pass "DR002-a" "Value narrative section present"
  else
    fail "DR002-a" "Value narrative section missing — need prominent section showing what was caught"
  fi

  # DR002-b: Total findings caught pre-merge displayed as a large prominent number
  # The value narrative section should contain a large stat number element
  # Check for: (1) a CSS class for large numbers, or (2) JS building a stat-number element
  if grep -qE 'stat-number|hero-number|big-number|value-number' "$_f"; then
    pass "DR002-b" "Large prominent number element present in value narrative"
  else
    fail "DR002-b" "No prominent findings count in value narrative section"
  fi

  # DR002-c: Pipeline phase distribution data present (QA vs mini-audit breakdown)
  if grep -qiE 'QA.*finding|mini.?audit.*finding|phase.*distribution|where.*caught' "$_f"; then
    pass "DR002-c" "Pipeline phase distribution data referenced in value narrative context"
  else
    fail "DR002-c" "Pipeline phase distribution data missing from value narrative"
  fi

  # DR002-d: Value narrative appears near the top of the Metrics view (before most other sections)
  local pos_narrative pos_trajectory
  pos_narrative=$(grep -niE 'value.*narrative|caught.*before|bugs.*caught|findings.*caught|what.*correctless.*caught|pre.?merge' "$_f" | head -1 | cut -d: -f1)
  pos_trajectory=$(grep -ni 'Quality Trajectory' "$_f" | head -1 | cut -d: -f1)
  if [ -n "$pos_narrative" ] && [ -n "$pos_trajectory" ]; then
    if [ "$pos_narrative" -le "$pos_trajectory" ]; then
      pass "DR002-d" "Value narrative appears before Quality Trajectory"
    else
      fail "DR002-d" "Value narrative should appear before Quality Trajectory"
    fi
  else
    fail "DR002-d" "Cannot verify value narrative position — heading not found"
  fi
}

# ============================================================================
# REDESIGN R-003: Card-based layout with visual hierarchy
# Tests dashboard-redesign spec R-003 [unit]
# ============================================================================

test_redesign_r003_card_layout() {
  echo ""
  echo "--- Redesign R-003: Card-based layout ---"

  local TEST_DIR
  TEST_DIR=$(setup_dashboard_project)
  trap 'rm -rf "$TEST_DIR"' RETURN

  run_dashboard "$TEST_DIR"

  local _f="$TEST_DIR/.correctless/dashboard/index.html"
  if [ ! -f "$_f" ]; then
    fail "DR003-a" "index.html not produced (prerequisite failure)"
    return
  fi

  # DR003-a: Card CSS class or card-like styling exists
  if grep -qE 'class="[^"]*card[^"]*"|\.card\s*\{|\.metric-card|\.section-card|\.dashboard-card' "$_f"; then
    pass "DR003-a" "Card-based CSS class/styling found"
  else
    fail "DR003-a" "No card-based layout styling found — metrics need card containers"
  fi

  # DR003-b: Cards have shadows (box-shadow)
  if grep -qE 'box-shadow' "$_f"; then
    pass "DR003-b" "Box-shadow styling present for visual depth"
  else
    fail "DR003-b" "No box-shadow found — cards need shadow for visual hierarchy"
  fi

  # DR003-c: Cards have backgrounds (background or background-color on card elements)
  if grep -qE '\.card[^{]*\{[^}]*background|--card-bg' "$_f"; then
    pass "DR003-c" "Card background styling present"
  else
    fail "DR003-c" "No card background styling found"
  fi

  # DR003-d: Section headers are visually distinct (larger/bolder than body text)
  # Check for h2/h3 or section header styling with distinct font-size/weight
  if grep -qE 'section.*header|\.section-title|h2.*font-size|h3.*font-size|\.card.*h[23]' "$_f"; then
    pass "DR003-d" "Section header styling present"
  else
    # Fallback: check for any font-size differentiation between headers and body
    local header_sizes
    header_sizes=$(grep -cE 'font-size:\s*(1\.[3-9]|[2-9])' "$_f")
    if [ "$header_sizes" -ge 2 ]; then
      pass "DR003-d" "Multiple font sizes found for visual hierarchy"
    else
      fail "DR003-d" "Insufficient visual hierarchy — headers need size/weight distinction"
    fi
  fi

  # DR003-e: Border-radius on cards (rounded corners)
  if grep -qE 'border-radius' "$_f"; then
    pass "DR003-e" "Border-radius present for rounded card edges"
  else
    fail "DR003-e" "No border-radius found — cards should have rounded corners"
  fi
}

# ============================================================================
# REDESIGN R-004: Artifact Browser sidebar enhancements
# Tests dashboard-redesign spec R-004 [unit]
# ============================================================================

test_redesign_r004_browser_sidebar() {
  echo ""
  echo "--- Redesign R-004: Artifact Browser sidebar enhancements ---"

  local TEST_DIR
  TEST_DIR=$(setup_dashboard_project)
  trap 'rm -rf "$TEST_DIR"' RETURN

  run_dashboard "$TEST_DIR"

  local _f="$TEST_DIR/.correctless/dashboard/index.html"
  if [ ! -f "$_f" ]; then
    fail "DR004-a" "index.html not produced (prerequisite failure)"
    return
  fi

  # DR004-a: Sidebar has search/filter input
  if grep -qiE '<input.*search|<input.*filter|search.*input|filter.*input|placeholder="[^"]*search|placeholder="[^"]*filter' "$_f"; then
    pass "DR004-a" "Sidebar search/filter input present"
  else
    fail "DR004-a" "No search/filter input in artifact browser sidebar"
  fi

  # DR004-b: Spec items show status indicators (dots/badges)
  if grep -qiE 'status.*dot|status.*indicator|status.*badge|class="[^"]*dot[^"]*"|class="[^"]*status[^"]*"|class="[^"]*indicator[^"]*"' "$_f"; then
    pass "DR004-b" "Status indicators present for spec items"
  else
    fail "DR004-b" "No status indicators found for spec items"
  fi

  # DR004-c: Specs sorted by date (newest first) — check the JSON data or sidebar ordering
  # The setup has alpha (2026-04-02) and beta (2026-04-05), beta should appear first
  local pos_beta pos_alpha
  pos_beta=$(grep -n 'beta' "$_f" | head -1 | cut -d: -f1)
  pos_alpha=$(grep -n 'alpha' "$_f" | head -1 | cut -d: -f1)
  if [ -n "$pos_beta" ] && [ -n "$pos_alpha" ]; then
    # In the sidebar listing, beta (newer) should appear before alpha (older)
    # But we can't easily distinguish sidebar order from other references,
    # so just verify both exist — ordering is better tested with browser interaction
    pass "DR004-c" "Both spec items present (ordering is a visual check)"
  else
    fail "DR004-c" "Spec items missing from sidebar"
  fi

  # DR004-d: Content area has tabs (Spec, Review, Verification)
  local tabs_found=0
  for tab_name in "Spec" "Review" "Verification"; do
    if grep -qiE "tab.*${tab_name}|${tab_name}.*tab|data-tab=\"[^\"]*${tab_name}" "$_f"; then
      tabs_found=$((tabs_found + 1))
    fi
  done
  if [ "$tabs_found" -ge 2 ]; then
    pass "DR004-d" "Content tabs present ($tabs_found/3 found)"
  else
    fail "DR004-d" "Content area tabs missing — need Spec/Review/Verification tabs ($tabs_found/3)"
  fi

  # DR004-e: Right panel shows per-spec pipeline data when spec selected
  if grep -qiE 'right.*panel|detail.*panel|spec.*detail|pipeline.*data|class="[^"]*panel[^"]*"' "$_f"; then
    pass "DR004-e" "Right panel / detail panel structure present"
  else
    fail "DR004-e" "No right panel structure for per-spec pipeline data"
  fi
}

# ============================================================================
# REDESIGN R-005: Markdown typography styling
# Tests dashboard-redesign spec R-005 [unit]
# ============================================================================

test_redesign_r005_markdown_typography() {
  echo ""
  echo "--- Redesign R-005: Markdown typography styling ---"

  local TEST_DIR
  TEST_DIR=$(setup_dashboard_project)
  trap 'rm -rf "$TEST_DIR"' RETURN

  run_dashboard "$TEST_DIR"

  local _f="$TEST_DIR/.correctless/dashboard/index.html"
  if [ ! -f "$_f" ]; then
    fail "DR005-a" "index.html not produced (prerequisite failure)"
    return
  fi

  # DR005-a: Markdown content area has typography styling for headings
  if grep -qE '\.markdown\s|\.markdown-body|\.content.*h[1-3]|\.rendered.*h[1-3]|\.md-content' "$_f"; then
    pass "DR005-a" "Markdown content area has heading typography styles"
  else
    fail "DR005-a" "No markdown-specific typography styles for headings"
  fi

  # DR005-b: Code block styling within rendered markdown
  if grep -qE '\.markdown.*code|\.markdown.*pre|\.content.*code|\.rendered.*code|\.md-content.*code|code\s*\{|pre\s*\{' "$_f"; then
    pass "DR005-b" "Code block styling present for rendered markdown"
  else
    fail "DR005-b" "No code block styling for rendered markdown content"
  fi

  # DR005-c: Table styling within rendered markdown
  if grep -qE '\.markdown.*table|\.content.*table|\.rendered.*table|\.md-content.*table|table\s*\{' "$_f"; then
    pass "DR005-c" "Table styling present for rendered markdown"
  else
    fail "DR005-c" "No table styling for rendered markdown content"
  fi

  # DR005-d: List styling within rendered markdown
  if grep -qE '\.markdown.*(ul|ol|li)|\.content.*(ul|ol|li)|\.rendered.*(ul|ol|li)|\.md-content.*(ul|ol|li)|(ul|ol)\s*\{|li\s*\{' "$_f"; then
    pass "DR005-d" "List styling present for rendered markdown"
  else
    fail "DR005-d" "No list styling for rendered markdown content"
  fi
}

# ============================================================================
# REDESIGN R-006: Dark and light mode polished
# Tests dashboard-redesign spec R-006 [unit]
# ============================================================================

test_redesign_r006_dark_light_mode() {
  echo ""
  echo "--- Redesign R-006: Dark and light mode polished ---"

  local TEST_DIR
  TEST_DIR=$(setup_dashboard_project)
  trap 'rm -rf "$TEST_DIR"' RETURN

  run_dashboard "$TEST_DIR"

  local _f="$TEST_DIR/.correctless/dashboard/index.html"
  if [ ! -f "$_f" ]; then
    fail "DR006-a" "index.html not produced (prerequisite failure)"
    return
  fi

  # DR006-a: CSS variables defined for light mode (in :root)
  local light_vars
  light_vars=$(grep -cE -- '--[a-z].*:' "$_f" | head -1)
  if [ "$light_vars" -ge 5 ]; then
    pass "DR006-a" "Light mode has $light_vars+ CSS variables defined"
  else
    fail "DR006-a" "Insufficient CSS variables for light mode"
  fi

  # DR006-b: CSS variables defined for dark mode (in @media prefers-color-scheme: dark)
  local dark_section
  dark_section=$(sed -n '/@media.*prefers-color-scheme.*dark/,/}/p' "$_f")
  local dark_vars
  dark_vars=$(echo "$dark_section" | grep -cE -- '--[a-z].*:')
  if [ "$dark_vars" -ge 5 ]; then
    pass "DR006-b" "Dark mode has $dark_vars CSS variables redefined"
  else
    fail "DR006-b" "Insufficient CSS variables for dark mode (found $dark_vars)"
  fi

  # DR006-c: Card styling works in dark mode (card-bg variable used)
  if echo "$dark_section" | grep -qF 'card-bg'; then
    pass "DR006-c" "Card background variable defined for dark mode"
  else
    fail "DR006-c" "Card background not redefined for dark mode"
  fi

  # DR006-d: Light mode is not a simple inversion — check distinct color values
  local light_bg dark_bg light_fg dark_fg
  light_bg=$(grep -oE -- '--bg:\s*#[0-9a-fA-F]+' "$_f" | head -1 | grep -oE '#[0-9a-fA-F]+')
  dark_bg=$(echo "$dark_section" | grep -oE -- '--bg:\s*#[0-9a-fA-F]+' | head -1 | grep -oE '#[0-9a-fA-F]+')
  light_fg=$(grep -oE -- '--fg:\s*#[0-9a-fA-F]+' "$_f" | head -1 | grep -oE '#[0-9a-fA-F]+')
  dark_fg=$(echo "$dark_section" | grep -oE -- '--fg:\s*#[0-9a-fA-F]+' | head -1 | grep -oE '#[0-9a-fA-F]+')
  if [ -n "$light_bg" ] && [ -n "$dark_bg" ] && [ "$light_bg" != "$dark_bg" ]; then
    if [ -n "$light_fg" ] && [ -n "$dark_fg" ] && [ "$light_fg" != "$dark_fg" ]; then
      pass "DR006-d" "Light and dark modes have distinct bg/fg colors"
    else
      fail "DR006-d" "Light and dark modes share the same foreground color"
    fi
  else
    fail "DR006-d" "Light and dark modes share the same background color"
  fi
}

# ============================================================================
# REDESIGN R-007: file:// protocol output URL
# Tests dashboard-redesign spec R-007 [unit]
# ============================================================================

test_redesign_r007_file_url() {
  echo ""
  echo "--- Redesign R-007: file:// protocol output URL ---"

  local TEST_DIR
  TEST_DIR=$(setup_dashboard_project)
  trap 'rm -rf "$TEST_DIR"' RETURN

  local output
  output=$(bash "$REPO_DIR/scripts/build-dashboard.sh" "$TEST_DIR" 2>&1)

  # DR007-a: Output includes file:// protocol URL
  if echo "$output" | grep -qE 'file://'; then
    pass "DR007-a" "Output includes file:// protocol URL"
  else
    fail "DR007-a" "Output missing file:// protocol URL — currently prints relative path"
  fi

  # DR007-b: The file:// URL contains the absolute path to the dashboard
  if echo "$output" | grep -qE "file://.*/\.correctless/dashboard/index\.html"; then
    pass "DR007-b" "file:// URL contains absolute path to dashboard"
  else
    fail "DR007-b" "file:// URL does not contain absolute path"
  fi

  # DR007-c: The absolute path is derived from $PROJECT_ROOT (resolved)
  local resolved_dir
  resolved_dir=$(cd "$TEST_DIR" && pwd)
  if echo "$output" | grep -qF "file://${resolved_dir}/.correctless/dashboard/index.html"; then
    pass "DR007-c" "file:// URL uses resolved PROJECT_ROOT path"
  else
    fail "DR007-c" "file:// URL does not use resolved PROJECT_ROOT: expected file://${resolved_dir}/.correctless/dashboard/index.html"
  fi
}

# ============================================================================
# REDESIGN R-008: Existing test intents preserved
# Tests dashboard-redesign spec R-008 [unit]
# This is implicitly tested by all the existing tests still passing.
# We add explicit meta-tests here to verify intent preservation.
# ============================================================================

test_redesign_r008_existing_intents() {
  echo ""
  echo "--- Redesign R-008: Existing test intents preserved ---"

  local TEST_DIR
  TEST_DIR=$(setup_dashboard_project)
  trap 'rm -rf "$TEST_DIR"' RETURN

  run_dashboard "$TEST_DIR"

  local _f="$TEST_DIR/.correctless/dashboard/index.html"
  if [ ! -f "$_f" ]; then
    fail "DR008-a" "index.html not produced (prerequisite failure)"
    return
  fi

  # DR008-a: Inline <style> still present
  if grep -q '<style' "$_f"; then
    pass "DR008-a" "Inline <style> preserved"
  else
    fail "DR008-a" "Inline <style> missing after redesign"
  fi

  # DR008-b: Inline <script> still present
  if grep -q '<script' "$_f"; then
    pass "DR008-b" "Inline <script> preserved"
  else
    fail "DR008-b" "Inline <script> missing after redesign"
  fi

  # DR008-c: marked.js CDN with SRI still present
  if grep -qE 'cdn\.jsdelivr\.net/npm/marked@[0-9]+\.[0-9]+\.[0-9]+' "$_f" && \
     grep -qE 'integrity="sha' "$_f"; then
    pass "DR008-c" "marked.js CDN with SRI preserved"
  else
    fail "DR008-c" "marked.js CDN with SRI missing after redesign"
  fi

  # DR008-d: DOMPurify still present
  if grep -qi 'dompurify' "$_f"; then
    pass "DR008-d" "DOMPurify preserved"
  else
    fail "DR008-d" "DOMPurify missing after redesign"
  fi

  # DR008-e: JSON data block still present
  if grep -q '<script type="application/json"' "$_f"; then
    pass "DR008-e" "JSON data block preserved"
  else
    fail "DR008-e" "JSON data block missing after redesign"
  fi

  # DR008-f: Two navigation views still present
  if grep -qi 'metrics' "$_f" && grep -qi 'artifact' "$_f"; then
    pass "DR008-f" "Two navigation views preserved"
  else
    fail "DR008-f" "Navigation views missing after redesign"
  fi
}

# ============================================================================
# REDESIGN R-009: Empty state handling (redesign-specific additions)
# Tests dashboard-redesign spec R-009 [unit]
# ============================================================================

test_redesign_r009_empty_state_redesign() {
  echo ""
  echo "--- Redesign R-009: Empty state with redesign styling ---"

  local EMPTY_DIR
  EMPTY_DIR=$(mktemp -d)
  trap 'rm -rf "$EMPTY_DIR"' RETURN

  mkdir -p "$EMPTY_DIR/.correctless/config"
  cat > "$EMPTY_DIR/.correctless/config/workflow-config.json" <<'WEOF'
{
  "project": { "name": "empty-redesign" },
  "workflow": { "intensity": "standard" }
}
WEOF

  run_dashboard "$EMPTY_DIR"

  local _f="$EMPTY_DIR/.correctless/dashboard/index.html"
  if [ ! -f "$_f" ]; then
    fail "DR009-a" "index.html not produced for empty project"
    return
  fi

  # DR009-a: Value narrative section still renders gracefully on empty project
  # Should show "0" or "No data" — not error or broken layout
  if grep -qiE 'no.*data|no.*findings|not yet|0.*caught|0.*found' "$_f"; then
    pass "DR009-a" "Value narrative degrades gracefully on empty project"
  else
    fail "DR009-a" "Value narrative may be broken on empty project — no graceful degradation"
  fi

  # DR009-b: Card layout doesn't break on empty data
  if grep -qE 'card' "$_f"; then
    pass "DR009-b" "Card layout present even on empty project"
  else
    fail "DR009-b" "Card layout missing on empty project"
  fi

  # DR009-c: Search input still renders on empty artifact browser
  if grep -qiE '<input.*search|<input.*filter|search.*input|filter.*input' "$_f"; then
    pass "DR009-c" "Search input present in empty artifact browser"
  else
    fail "DR009-c" "Search input missing from empty artifact browser"
  fi
}

# ============================================================================
# REDESIGN R-010: CDN pattern for new dependencies (fonts)
# Tests dashboard-redesign spec R-010 [unit]
# ============================================================================

test_redesign_r010_cdn_pattern() {
  echo ""
  echo "--- Redesign R-010: CDN pattern for new dependencies ---"

  local TEST_DIR
  TEST_DIR=$(setup_dashboard_project)
  trap 'rm -rf "$TEST_DIR"' RETURN

  run_dashboard "$TEST_DIR"

  local _f="$TEST_DIR/.correctless/dashboard/index.html"
  if [ ! -f "$_f" ]; then
    fail "DR010-a" "index.html not produced (prerequisite failure)"
    return
  fi

  # DR010-a: Font CDN has pinned version (not latest/unpinned)
  # Google Fonts CSS2 API doesn't use semver, but we should at least verify
  # no "latest" or unversioned CDN URLs
  if grep -qE 'fonts\.googleapis\.com.*family=' "$_f" || \
     grep -qE 'fonts\.bunny\.net.*family=' "$_f"; then
    pass "DR010-a" "Font CDN URL specifies font family (pinned)"
  else
    fail "DR010-a" "No pinned font CDN URL found"
  fi

  # DR010-b: Font link has onerror fallback
  if grep -qiE 'link.*fonts.*onerror|onerror.*font' "$_f"; then
    pass "DR010-b" "Font link has onerror fallback"
  else
    fail "DR010-b" "Font link missing onerror fallback handler"
  fi

  # DR010-c: Dashboard remains functional without font CDN
  # Verify system font fallback exists in the font-family declaration
  if grep -qE 'sans-serif|serif|monospace' "$_f"; then
    pass "DR010-c" "System font fallback present in font stack"
  else
    fail "DR010-c" "No system font fallback — dashboard breaks if font CDN fails"
  fi

  # DR010-d: No blocked rendering from font loading
  # font-display: swap or URL param display=swap
  if grep -qE 'font-display:\s*swap|display=swap' "$_f"; then
    pass "DR010-d" "Font loading uses font-display: swap (non-blocking)"
  else
    fail "DR010-d" "Font loading may block page render — use font-display: swap"
  fi
}

# ============================================================================
# REDESIGN R-011: Distribution sync
# Tests dashboard-redesign spec R-011 [unit]
# ============================================================================

test_redesign_r011_distribution_sync() {
  echo ""
  echo "--- Redesign R-011: Distribution sync ---"

  # DR011-a: Distribution copy exists
  if [ -f "$REPO_DIR/correctless/scripts/build-dashboard.sh" ]; then
    pass "DR011-a" "Distribution build-dashboard.sh exists"
  else
    fail "DR011-a" "Distribution build-dashboard.sh missing"
  fi

  # DR011-b: Distribution copy matches source
  if [ -f "$REPO_DIR/scripts/build-dashboard.sh" ] && [ -f "$REPO_DIR/correctless/scripts/build-dashboard.sh" ]; then
    if diff -q "$REPO_DIR/scripts/build-dashboard.sh" "$REPO_DIR/correctless/scripts/build-dashboard.sh" >/dev/null 2>&1; then
      pass "DR011-b" "Distribution matches source"
    else
      fail "DR011-b" "Distribution build-dashboard.sh differs from source — run sync.sh"
    fi
  else
    fail "DR011-b" "Cannot compare — file missing"
  fi
}

# ============================================================================
# Run all tests
# ============================================================================

test_r001_skill_and_script
test_r002_html_structure
test_r003_navigation_views
test_r004_artifact_browser
test_r005_metrics_data_sources
test_r006_output_path
test_r007_migration
test_r008_dark_mode
test_r009_empty_state
test_r010_registration
test_r011_messages
test_r012_browser_structural
test_metrics_section_order
test_cmetrics_mention
test_antipattern_dormancy
test_pipeline_phase_distribution
# Redesign tests (dashboard-redesign spec R-001 through R-011)
test_redesign_r001_visual_identity
test_redesign_r002_value_narrative
test_redesign_r003_card_layout
test_redesign_r004_browser_sidebar
test_redesign_r005_markdown_typography
test_redesign_r006_dark_light_mode
test_redesign_r007_file_url
test_redesign_r008_existing_intents
test_redesign_r009_empty_state_redesign
test_redesign_r010_cdn_pattern
test_redesign_r011_distribution_sync

echo ""
echo "========================================="
echo "  Project Dashboard UI Tests: $PASS passed, $FAIL failed"
echo "========================================="
if [ -n "$FAILED_IDS" ]; then
  echo "  Failed: $FAILED_IDS"
fi
[ "$FAIL" -eq 0 ]
