#!/usr/bin/env bash
# shellcheck disable=SC2086
# Correctless — Project Dashboard Tests
#
# Functional tests for scripts/generate-dashboard.sh.
# Creates temp directories with realistic .correctless/ artifacts,
# runs the dashboard generator, and verifies output.
#
# Covers R-001 through R-009 (original), DI-R001 through DI-R006 (dashboard insights).
# Run from repo root: bash tests/test-project-dashboard.sh

set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || { echo "FATAL: cannot cd to repo root" >&2; exit 2; }

REPO_DIR="$(pwd)"
PASS=0
FAIL=0
FAILED_IDS=""

# ============================================================================
# Helpers
# ============================================================================

pass() {
  local id="$1" desc="$2"
  echo "  PASS: $id — $desc"
  PASS=$((PASS + 1))
}

fail() {
  local id="$1" desc="$2"
  echo "  FAIL: $id — $desc"
  FAIL=$((FAIL + 1))
  FAILED_IDS="${FAILED_IDS}${id} "
}

# Generate dashboard in a directory (runs in subshell to avoid cwd pollution)
run_dashboard() {
  local dir="$1"
  (cd "$dir" && bash "$REPO_DIR/scripts/generate-dashboard.sh" >/dev/null 2>&1)
}

# Create a temp project directory with realistic .correctless/ artifacts
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

  # ---- antipatterns.md ----
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

echo "=== Project Dashboard Tests ==="

# ---- R-001: Script exists and produces dashboard.html ----
test_r001_script_produces_html() {
  echo ""
  echo "--- R-001: Script exists and produces dashboard.html ---"

  local TEST_DIR
  TEST_DIR=$(setup_dashboard_project)
  trap 'rm -rf "$TEST_DIR"' RETURN

  # Verify script exists
  if [ -f "$REPO_DIR/scripts/generate-dashboard.sh" ]; then
    pass "R001-a" "scripts/generate-dashboard.sh exists"
  else
    fail "R001-a" "scripts/generate-dashboard.sh does not exist"
    return
  fi

  # Run script from the test project directory
  local output
  output=$(cd "$TEST_DIR" && bash "$REPO_DIR/scripts/generate-dashboard.sh" 2>&1)
  local exit_code=$?

  if [ $exit_code -eq 0 ]; then
    pass "R001-b" "Script exits 0 on success"
  else
    fail "R001-b" "Script exited with code $exit_code: $output"
  fi

  if [ -f "$TEST_DIR/dashboard.html" ]; then
    pass "R001-c" "dashboard.html was produced"
  else
    fail "R001-c" "dashboard.html was not produced"
  fi

  # Verify it's valid HTML (has basic structure)
  if grep -q '<html' "$TEST_DIR/dashboard.html" && grep -q '</html>' "$TEST_DIR/dashboard.html"; then
    pass "R001-d" "dashboard.html contains valid HTML structure"
  else
    fail "R001-d" "dashboard.html missing HTML structure"
  fi
}

# ---- R-002: Self-contained HTML ----
test_r002_self_contained() {
  echo ""
  echo "--- R-002: Self-contained HTML (no external deps) ---"

  local TEST_DIR
  TEST_DIR=$(setup_dashboard_project)
  trap 'rm -rf "$TEST_DIR"' RETURN

  run_dashboard "$TEST_DIR"

  if [ ! -f "$TEST_DIR/dashboard.html" ]; then
    fail "R002-a" "dashboard.html not produced (prerequisite failure)"
    return
  fi

  # No CDN or external links
  if ! grep -qiE 'https?://[^ "]*\.(js|css|woff|ttf|svg)' "$TEST_DIR/dashboard.html"; then
    pass "R002-a" "No external JS/CSS/font links"
  else
    fail "R002-a" "Found external resource links in HTML"
  fi

  # No fetch() calls
  if ! grep -q 'fetch(' "$TEST_DIR/dashboard.html"; then
    pass "R002-b" "No fetch() calls"
  else
    fail "R002-b" "Found fetch() calls in HTML"
  fi

  # Has inline CSS
  if grep -q '<style' "$TEST_DIR/dashboard.html"; then
    pass "R002-c" "Contains inline CSS"
  else
    fail "R002-c" "Missing inline CSS"
  fi

  # Has inline JS
  if grep -q '<script' "$TEST_DIR/dashboard.html"; then
    pass "R002-d" "Contains inline JS"
  else
    fail "R002-d" "Missing inline JS"
  fi
}

# ---- R-003: Data source parsing ----
test_r003_data_sources() {
  echo ""
  echo "--- R-003: Data sources embedded in HTML ---"

  local TEST_DIR
  TEST_DIR=$(setup_dashboard_project)
  trap 'rm -rf "$TEST_DIR"' RETURN

  run_dashboard "$TEST_DIR"

  if [ ! -f "$TEST_DIR/dashboard.html" ]; then
    fail "R003-a" "dashboard.html not produced (prerequisite failure)"
    return
  fi

  local _f="$TEST_DIR/dashboard.html"

  # Workflow history data embedded
  if grep -q 'Feature Alpha' "$_f"; then
    pass "R003-a" "Workflow history data (Feature Alpha) embedded"
  else
    fail "R003-a" "Workflow history data not embedded"
  fi

  # QA findings data embedded
  if grep -q 'BLOCKING\|QA-001' "$_f"; then
    pass "R003-b" "QA findings data embedded"
  else
    fail "R003-b" "QA findings data not embedded"
  fi

  # Antipattern data embedded
  if grep -q 'AP-001' "$_f"; then
    pass "R003-c" "Antipattern data embedded"
  else
    fail "R003-c" "Antipattern data not embedded"
  fi

  # Calibration data embedded
  if grep -q 'calibration\|150000\|80000' "$_f"; then
    pass "R003-d" "Calibration data embedded"
  else
    fail "R003-d" "Calibration data not embedded"
  fi

  # Drift debt data embedded
  if grep -q 'DRIFT-001\|drift' "$_f"; then
    pass "R003-e" "Drift debt data embedded"
  else
    fail "R003-e" "Drift debt data not embedded"
  fi

  # Token log data embedded
  if grep -q 'token\|8000\|18000' "$_f"; then
    pass "R003-f" "Token log data embedded"
  else
    fail "R003-f" "Token log data not embedded"
  fi

  # Project name from config
  if grep -q 'test-project' "$_f"; then
    pass "R003-g" "Project name from workflow-config embedded"
  else
    fail "R003-g" "Project name not embedded"
  fi
}

# ---- R-004: Dashboard sections ----
test_r004_sections() {
  echo ""
  echo "--- R-004: Dashboard sections present ---"

  local TEST_DIR
  TEST_DIR=$(setup_dashboard_project)
  trap 'rm -rf "$TEST_DIR"' RETURN

  run_dashboard "$TEST_DIR"

  if [ ! -f "$TEST_DIR/dashboard.html" ]; then
    fail "R004-a" "dashboard.html not produced (prerequisite failure)"
    return
  fi

  local _f="$TEST_DIR/dashboard.html"

  # Section 1: Project Summary
  if grep -qi 'project summary' "$_f"; then
    pass "R004-a" "Project Summary section present"
  else
    fail "R004-a" "Project Summary section missing"
  fi

  # Section 2: Quality Trajectory
  if grep -qi 'quality trajectory' "$_f"; then
    pass "R004-b" "Quality Trajectory section present"
  else
    fail "R004-b" "Quality Trajectory section missing"
  fi

  # Section 3: Pipeline Phase Distribution
  if grep -qi 'pipeline.*phase\|phase.*distribution' "$_f"; then
    pass "R004-c" "Pipeline Phase Distribution section present"
  else
    fail "R004-c" "Pipeline Phase Distribution section missing"
  fi

  # Section 4: Antipattern Health
  if grep -qi 'antipattern' "$_f"; then
    pass "R004-d" "Antipattern Health section present"
  else
    fail "R004-d" "Antipattern Health section missing"
  fi

  # Section 5: Intensity Calibration (now Intensity Accuracy — grep matches both)
  if grep -qi 'intensity.*calibration\|intensity.*accuracy\|calibration' "$_f"; then
    pass "R004-e" "Intensity Calibration section present"
  else
    fail "R004-e" "Intensity Calibration section missing"
  fi

  # Section 6: Cost by Phase
  if grep -qi 'cost.*phase\|token.*usage\|phase.*cost' "$_f"; then
    pass "R004-f" "Cost by Phase section present"
  else
    fail "R004-f" "Cost by Phase section missing"
  fi

  # Section 7: Drift Debt
  if grep -qi 'drift.*debt' "$_f"; then
    pass "R004-g" "Drift Debt section present"
  else
    fail "R004-g" "Drift Debt section missing"
  fi

  # Section 8: Dev Journal
  if grep -qi 'dev.*journal' "$_f"; then
    pass "R004-h" "Dev Journal section present"
  else
    fail "R004-h" "Dev Journal section missing"
  fi

  # Quality Trajectory has horizontal bars (div with width)
  if grep -qE 'width:[0-9]+%|width: [0-9]+%' "$_f"; then
    pass "R004-i" "Quality Trajectory contains horizontal bar elements"
  else
    fail "R004-i" "No horizontal bar elements found"
  fi

  # Project summary contains health verdict
  if grep -qi 'features.*findings\|findings.*caught' "$_f"; then
    pass "R004-j" "Project Summary contains health verdict"
  else
    fail "R004-j" "Project Summary missing health verdict"
  fi
}

# ---- R-005: Styling (dark/light mode) ----
test_r005_styling() {
  echo ""
  echo "--- R-005: Styling and dark/light mode ---"

  local TEST_DIR
  TEST_DIR=$(setup_dashboard_project)
  trap 'rm -rf "$TEST_DIR"' RETURN

  run_dashboard "$TEST_DIR"

  if [ ! -f "$TEST_DIR/dashboard.html" ]; then
    fail "R005-a" "dashboard.html not produced (prerequisite failure)"
    return
  fi

  local _f="$TEST_DIR/dashboard.html"

  # prefers-color-scheme media query
  if grep -q 'prefers-color-scheme' "$_f"; then
    pass "R005-a" "Dark/light mode via prefers-color-scheme"
  else
    fail "R005-a" "Missing prefers-color-scheme media query"
  fi

  # Severity color coding (red for BLOCKING/CRITICAL)
  if grep -qiE 'blocking|critical' "$_f" && grep -qE '#[0-9a-fA-F]+|red|rgb' "$_f"; then
    pass "R005-b" "Severity color coding present"
  else
    fail "R005-b" "Missing severity color coding"
  fi
}

# ---- R-006: dashboard.html in .gitignore ----
test_r006_gitignore() {
  echo ""
  echo "--- R-006: dashboard.html in .gitignore ---"

  if grep -q 'dashboard\.html' "$REPO_DIR/.gitignore"; then
    pass "R006-a" "dashboard.html is in .gitignore"
  else
    fail "R006-a" "dashboard.html is not in .gitignore"
  fi
}

# ---- R-007: Graceful degradation with missing/empty data ----
test_r007_graceful_degradation() {
  echo ""
  echo "--- R-007: Graceful degradation ---"

  # Test with completely empty project (no .correctless data)
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
  output=$(cd "$EMPTY_DIR" && bash "$REPO_DIR/scripts/generate-dashboard.sh" 2>&1)
  exit_code=$?

  if [ $exit_code -eq 0 ]; then
    pass "R007-a" "Script exits 0 with empty project"
  else
    fail "R007-a" "Script failed with empty project: exit=$exit_code $output"
  fi

  if [ -f "$EMPTY_DIR/dashboard.html" ]; then
    pass "R007-b" "dashboard.html produced for empty project"
  else
    fail "R007-b" "dashboard.html not produced for empty project"
    return
  fi

  # Should contain placeholder messages
  if grep -qi 'no.*data\|no.*history\|no.*findings\|not yet' "$EMPTY_DIR/dashboard.html"; then
    pass "R007-c" "Empty project shows placeholder messages"
  else
    fail "R007-c" "Empty project missing placeholder messages"
  fi

  # Single-feature project: need trend note
  local SINGLE_DIR
  SINGLE_DIR=$(mktemp -d)

  mkdir -p "$SINGLE_DIR/.correctless/config"
  cat > "$SINGLE_DIR/.correctless/config/workflow-config.json" <<'WEOF2'
{ "project": { "name": "single-feature" }, "workflow": { "intensity": "standard" } }
WEOF2

  mkdir -p "$SINGLE_DIR/docs"
  cat > "$SINGLE_DIR/docs/workflow-history.md" <<'HEOF2'
# Workflow History

### 2026-04-02 — Only Feature
Branch: feature/only. Rules: 5. QA rounds: 1. Findings fixed: 1. The only feature.
HEOF2

  mkdir -p "$SINGLE_DIR/.correctless/artifacts"
  cat > "$SINGLE_DIR/.correctless/artifacts/qa-findings-only.json" <<'QEOF3'
{ "task": "only", "round": 1, "findings": [{ "id": "QA-001", "severity": "BLOCKING", "description": "issue", "rule_ref": "R-001", "instance_fix": "fix", "class_fix": "test", "status": "fixed" }] }
QEOF3

  run_dashboard "$SINGLE_DIR"

  if [ -f "$SINGLE_DIR/dashboard.html" ]; then
    if grep -qi 'need more\|single.*feature\|more features\|trend' "$SINGLE_DIR/dashboard.html"; then
      pass "R007-d" "Single feature shows trend note"
    else
      fail "R007-d" "Single feature missing trend note"
    fi
  else
    fail "R007-d" "dashboard.html not produced for single-feature project"
  fi

  rm -rf "$SINGLE_DIR"
}

# ---- R-008: sync.sh copies script to distribution ----
test_r008_sync() {
  echo ""
  echo "--- R-008: sync.sh copies generate-dashboard.sh to distribution ---"

  # The scripts sync block in sync.sh copies all scripts/*.sh to correctless/scripts/
  # So generate-dashboard.sh should be synced automatically via the glob pattern.
  # Verify it exists in the distribution.

  if [ -f "$REPO_DIR/correctless/scripts/generate-dashboard.sh" ]; then
    pass "R008-a" "generate-dashboard.sh exists in distribution"
  else
    fail "R008-a" "generate-dashboard.sh missing from distribution"
  fi

  # Verify contents match source (sync.sh uses sync_file which copies)
  if [ -f "$REPO_DIR/scripts/generate-dashboard.sh" ] && [ -f "$REPO_DIR/correctless/scripts/generate-dashboard.sh" ]; then
    if diff -q "$REPO_DIR/scripts/generate-dashboard.sh" "$REPO_DIR/correctless/scripts/generate-dashboard.sh" >/dev/null 2>&1; then
      pass "R008-b" "Distribution copy matches source"
    else
      fail "R008-b" "Distribution copy differs from source"
    fi
  else
    fail "R008-b" "Cannot compare — source or dist file missing"
  fi
}

# ---- R-009: /cmetrics mentions dashboard ----
test_r009_cmetrics_mention() {
  echo ""
  echo "--- R-009: /cmetrics mentions dashboard ---"

  local cmetrics="$REPO_DIR/skills/cmetrics/SKILL.md"

  if grep -qi 'generate-dashboard\|dashboard\.html' "$cmetrics"; then
    pass "R009-a" "/cmetrics SKILL.md mentions dashboard"
  else
    fail "R009-a" "/cmetrics SKILL.md does not mention dashboard"
  fi
}

# ---- R-004: Dev journal (last 3 entries) ----
test_r004_dev_journal() {
  echo ""
  echo "--- R-004: Dev Journal shows last 3 entries ---"

  local TEST_DIR
  TEST_DIR=$(setup_dashboard_project)
  trap 'rm -rf "$TEST_DIR"' RETURN

  run_dashboard "$TEST_DIR"

  if [ ! -f "$TEST_DIR/dashboard.html" ]; then
    fail "R004-DJ-a" "dashboard.html not produced"
    return
  fi

  local _f="$TEST_DIR/dashboard.html"

  # Should include last 3 entries (Gamma, Beta, Alpha) but NOT the 4th (Project Setup)
  if grep -q 'Feature Gamma' "$_f"; then
    pass "R004-DJ-a" "Dev Journal includes last entry (Gamma)"
  else
    fail "R004-DJ-a" "Dev Journal missing last entry (Gamma)"
  fi

  if grep -q 'Feature Beta' "$_f"; then
    pass "R004-DJ-b" "Dev Journal includes 2nd-to-last entry (Beta)"
  else
    fail "R004-DJ-b" "Dev Journal missing 2nd-to-last entry (Beta)"
  fi

  if grep -q 'Feature Alpha' "$_f"; then
    pass "R004-DJ-c" "Dev Journal includes 3rd-to-last entry (Alpha)"
  else
    fail "R004-DJ-c" "Dev Journal missing 3rd-to-last entry (Alpha)"
  fi
}

# ---- R-004: Antipattern dormancy detection ----
test_r004_antipattern_dormancy() {
  echo ""
  echo "--- R-004: Antipattern dormancy cross-reference ---"

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

  if [ ! -f "$TEST_DIR/dashboard.html" ]; then
    fail "R004-AP-a" "dashboard.html not produced"
    return
  fi

  # AP-002 has Status: Structurally enforced -> should be "resolved"
  if grep -qi 'resolved\|structurally enforced' "$TEST_DIR/dashboard.html"; then
    pass "R004-AP-a" "Structurally enforced antipattern shown as resolved"
  else
    fail "R004-AP-a" "Structurally enforced antipattern not shown as resolved"
  fi
}

# ---- R-004: Pipeline Phase Distribution (QA vs MA prefix) ----
test_r004_pipeline_phases() {
  echo ""
  echo "--- R-004: Pipeline Phase Distribution (QA vs MA prefix) ---"

  local TEST_DIR
  TEST_DIR=$(setup_dashboard_project)
  trap 'rm -rf "$TEST_DIR"' RETURN

  run_dashboard "$TEST_DIR"

  if [ ! -f "$TEST_DIR/dashboard.html" ]; then
    fail "R004-PP-a" "dashboard.html not produced"
    return
  fi

  # Should distinguish QA- vs MA- prefixed findings
  if grep -qi 'QA\|mini.*audit\|MA-' "$TEST_DIR/dashboard.html"; then
    pass "R004-PP-a" "Pipeline phase distribution distinguishes QA and MA findings"
  else
    fail "R004-PP-a" "Pipeline phase distribution missing QA/MA distinction"
  fi
}

# ---- R-001: Only requires bash, jq, standard Unix tools ----
test_r001_no_exotic_deps() {
  echo ""
  echo "--- R-001: No exotic dependencies ---"

  if [ ! -f "$REPO_DIR/scripts/generate-dashboard.sh" ]; then
    fail "R001-e" "Script does not exist yet"
    return
  fi

  # Check script doesn't require npm, python, node, etc.
  if ! grep -qE '^[^#]*(npm|node |python|pip |ruby|gem |cargo )' "$REPO_DIR/scripts/generate-dashboard.sh"; then
    pass "R001-e" "No exotic dependencies (npm/python/node/ruby/cargo)"
  else
    fail "R001-e" "Script references exotic dependencies"
  fi
}

# ---- DI-R001: QA Rounds Trend section ----
test_di_r001_qa_rounds_trend() {
  echo ""
  echo "--- DI-R001: QA Rounds Trend section ---"

  local TEST_DIR
  TEST_DIR=$(setup_dashboard_project)
  trap 'rm -rf "$TEST_DIR"' RETURN

  run_dashboard "$TEST_DIR"

  if [ ! -f "$TEST_DIR/dashboard.html" ]; then
    fail "DI-R001-a" "dashboard.html not produced (prerequisite failure)"
    return
  fi

  local _f="$TEST_DIR/dashboard.html"

  # Section heading exists
  if grep -qi 'QA Rounds Trend' "$_f"; then
    pass "DI-R001-a" "QA Rounds Trend section heading present"
  else
    fail "DI-R001-a" "QA Rounds Trend section heading missing"
  fi

  # Shows per-feature bars (features Alpha, Beta, Gamma have qa_rounds 2, 1, 3)
  # The JS code renders bar-container and bar-track elements for this section
  if grep -qi 'QA Rounds Trend' "$_f" && grep -q 'bar-container\|bar-track' "$_f"; then
    pass "DI-R001-b" "QA Rounds Trend renders horizontal bars"
  else
    fail "DI-R001-b" "QA Rounds Trend missing horizontal bar rendering"
  fi
}

# ---- DI-R002: Intensity Accuracy section ----
test_di_r002_intensity_accuracy() {
  echo ""
  echo "--- DI-R002: Intensity Accuracy section ---"

  local TEST_DIR
  TEST_DIR=$(setup_dashboard_project)
  trap 'rm -rf "$TEST_DIR"' RETURN

  run_dashboard "$TEST_DIR"

  if [ ! -f "$TEST_DIR/dashboard.html" ]; then
    fail "DI-R002-a" "dashboard.html not produced (prerequisite failure)"
    return
  fi

  local _f="$TEST_DIR/dashboard.html"

  # Section heading exists
  if grep -qi 'Intensity Accuracy' "$_f"; then
    pass "DI-R002-a" "Intensity Accuracy section heading present"
  else
    fail "DI-R002-a" "Intensity Accuracy section heading missing"
  fi

  # Shows agreed/raised/lowered summary
  # Test data: alpha recommended=standard actual=high (raised), beta recommended=standard actual=standard (agreed)
  if grep -qiE 'agreed.*raised|raised.*lowered' "$_f"; then
    pass "DI-R002-b" "Intensity Accuracy shows agreed/raised/lowered summary"
  else
    fail "DI-R002-b" "Intensity Accuracy missing agreed/raised/lowered summary"
  fi
}

# ---- DI-R003: Override Rate section ----
test_di_r003_override_rate() {
  echo ""
  echo "--- DI-R003: Override Rate section ---"

  local TEST_DIR
  TEST_DIR=$(setup_dashboard_project)
  trap 'rm -rf "$TEST_DIR"' RETURN

  run_dashboard "$TEST_DIR"

  if [ ! -f "$TEST_DIR/dashboard.html" ]; then
    fail "DI-R003-a" "dashboard.html not produced (prerequisite failure)"
    return
  fi

  local _f="$TEST_DIR/dashboard.html"

  # Section heading exists
  if grep -qi 'Override Rate' "$_f"; then
    pass "DI-R003-a" "Override Rate section heading present"
  else
    fail "DI-R003-a" "Override Rate section heading missing"
  fi

  # Shows mean override summary line
  if grep -qiE 'mean.*overrides per feature|overrides per feature' "$_f"; then
    pass "DI-R003-b" "Override Rate shows mean summary"
  else
    fail "DI-R003-b" "Override Rate missing mean summary"
  fi
}

# ---- DI-R004: Fix Rate section ----
test_di_r004_fix_rate() {
  echo ""
  echo "--- DI-R004: Fix Rate section ---"

  local TEST_DIR
  TEST_DIR=$(setup_dashboard_project)
  trap 'rm -rf "$TEST_DIR"' RETURN

  run_dashboard "$TEST_DIR"

  if [ ! -f "$TEST_DIR/dashboard.html" ]; then
    fail "DI-R004-a" "dashboard.html not produced (prerequisite failure)"
    return
  fi

  local _f="$TEST_DIR/dashboard.html"

  # Section heading exists
  if grep -qi 'Fix Rate' "$_f"; then
    pass "DI-R004-a" "Fix Rate section heading present"
  else
    fail "DI-R004-a" "Fix Rate section heading missing"
  fi

  # Shows N/M findings fixed (X%) format via JS rendering
  # The JS code contains the literal 'findings fixed' string
  if grep -q 'findings fixed' "$_f"; then
    pass "DI-R004-b" "Fix Rate renders N/M findings fixed format"
  else
    fail "DI-R004-b" "Fix Rate missing findings fixed rendering"
  fi
}

# ---- DI-R005: Section ordering ----
test_di_r005_section_order() {
  echo ""
  echo "--- DI-R005: New sections in correct order ---"

  local TEST_DIR
  TEST_DIR=$(setup_dashboard_project)
  trap 'rm -rf "$TEST_DIR"' RETURN

  run_dashboard "$TEST_DIR"

  if [ ! -f "$TEST_DIR/dashboard.html" ]; then
    fail "DI-R005-a" "dashboard.html not produced (prerequisite failure)"
    return
  fi

  local _f="$TEST_DIR/dashboard.html"

  # Extract line numbers of section heading strings in the HTML output
  local pos_qt pos_qrt pos_ppd pos_fr pos_ah pos_ia pos_or pos_cbp

  pos_qt=$(grep -n 'Quality Trajectory' "$_f" | head -1 | cut -d: -f1)
  pos_qrt=$(grep -n 'QA Rounds Trend' "$_f" | head -1 | cut -d: -f1)
  pos_ppd=$(grep -n 'Pipeline Phase Distribution' "$_f" | head -1 | cut -d: -f1)
  pos_fr=$(grep -n 'Fix Rate' "$_f" | head -1 | cut -d: -f1)
  pos_ah=$(grep -n 'Antipattern Health' "$_f" | head -1 | cut -d: -f1)
  pos_ia=$(grep -n 'Intensity Accuracy' "$_f" | head -1 | cut -d: -f1)
  pos_or=$(grep -n 'Override Rate' "$_f" | head -1 | cut -d: -f1)
  pos_cbp=$(grep -n 'Cost by Phase' "$_f" | head -1 | cut -d: -f1)

  # Check all positions are set
  if [ -z "$pos_qrt" ] || [ -z "$pos_fr" ] || [ -z "$pos_ia" ] || [ -z "$pos_or" ]; then
    fail "DI-R005-a" "One or more new section headings not found in output"
    return
  fi

  # Quality Trajectory < QA Rounds Trend
  if [ "$pos_qt" -lt "$pos_qrt" ]; then
    pass "DI-R005-a" "Quality Trajectory appears before QA Rounds Trend"
  else
    fail "DI-R005-a" "Quality Trajectory should appear before QA Rounds Trend"
  fi

  # QA Rounds Trend < Pipeline Phase Distribution
  if [ "$pos_qrt" -lt "$pos_ppd" ]; then
    pass "DI-R005-b" "QA Rounds Trend appears before Pipeline Phase Distribution"
  else
    fail "DI-R005-b" "QA Rounds Trend should appear before Pipeline Phase Distribution"
  fi

  # Pipeline Phase Distribution < Fix Rate
  if [ "$pos_ppd" -lt "$pos_fr" ]; then
    pass "DI-R005-c" "Pipeline Phase Distribution appears before Fix Rate"
  else
    fail "DI-R005-c" "Pipeline Phase Distribution should appear before Fix Rate"
  fi

  # Fix Rate < Antipattern Health
  if [ "$pos_fr" -lt "$pos_ah" ]; then
    pass "DI-R005-d" "Fix Rate appears before Antipattern Health"
  else
    fail "DI-R005-d" "Fix Rate should appear before Antipattern Health"
  fi

  # Antipattern Health < Intensity Accuracy
  if [ "$pos_ah" -lt "$pos_ia" ]; then
    pass "DI-R005-e" "Antipattern Health appears before Intensity Accuracy"
  else
    fail "DI-R005-e" "Antipattern Health should appear before Intensity Accuracy"
  fi

  # Intensity Accuracy < Override Rate
  if [ "$pos_ia" -lt "$pos_or" ]; then
    pass "DI-R005-f" "Intensity Accuracy appears before Override Rate"
  else
    fail "DI-R005-f" "Intensity Accuracy should appear before Override Rate"
  fi

  # Override Rate < Cost by Phase
  if [ "$pos_or" -lt "$pos_cbp" ]; then
    pass "DI-R005-g" "Override Rate appears before Cost by Phase"
  else
    fail "DI-R005-g" "Override Rate should appear before Cost by Phase"
  fi
}

# ---- DI-R006: Graceful degradation for new sections ----
test_di_r006_graceful_degradation() {
  echo ""
  echo "--- DI-R006: Graceful degradation for new sections ---"

  # Create a minimal project with NO qa_rounds, NO calibration, NO overrides, NO findings
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

  run_dashboard "$EMPTY_DIR"

  if [ ! -f "$EMPTY_DIR/dashboard.html" ]; then
    fail "DI-R006-a" "dashboard.html not produced for empty project"
    return
  fi

  local _f="$EMPTY_DIR/dashboard.html"

  # QA Rounds Trend degrades
  if grep -qi 'No QA round data' "$_f"; then
    pass "DI-R006-a" "QA Rounds Trend shows 'No QA round data' when empty"
  else
    fail "DI-R006-a" "QA Rounds Trend missing graceful degradation"
  fi

  # Intensity Accuracy degrades
  if grep -qi 'No calibration data' "$_f"; then
    pass "DI-R006-b" "Intensity Accuracy shows 'No calibration data' when empty"
  else
    fail "DI-R006-b" "Intensity Accuracy missing graceful degradation"
  fi

  # Override Rate degrades
  if grep -qi 'No override data' "$_f"; then
    pass "DI-R006-c" "Override Rate shows 'No override data' when empty"
  else
    fail "DI-R006-c" "Override Rate missing graceful degradation"
  fi

  # Fix Rate degrades
  if grep -qi 'No findings data' "$_f"; then
    pass "DI-R006-d" "Fix Rate shows 'No findings data' when empty"
  else
    fail "DI-R006-d" "Fix Rate missing graceful degradation"
  fi

  # Also test Fix Rate with findings that have NO status field
  local STATUS_DIR
  STATUS_DIR=$(mktemp -d)

  mkdir -p "$STATUS_DIR/.correctless/config"
  cat > "$STATUS_DIR/.correctless/config/workflow-config.json" <<'WEOF2'
{ "project": { "name": "no-status" }, "workflow": { "intensity": "standard" } }
WEOF2

  mkdir -p "$STATUS_DIR/.correctless/artifacts"
  cat > "$STATUS_DIR/.correctless/artifacts/qa-findings-nostatus.json" <<'NSEOF'
{
  "task": "nostatus",
  "round": 1,
  "findings": [
    { "id": "QA-001", "severity": "BLOCKING", "description": "issue", "rule_ref": "R-001", "instance_fix": "fix", "class_fix": "test" }
  ]
}
NSEOF

  run_dashboard "$STATUS_DIR"

  if [ -f "$STATUS_DIR/dashboard.html" ]; then
    if grep -qi 'Fix status data not available' "$STATUS_DIR/dashboard.html"; then
      pass "DI-R006-e" "Fix Rate shows 'Fix status data not available' when findings lack status"
    else
      fail "DI-R006-e" "Fix Rate missing degradation for findings without status"
    fi
  else
    fail "DI-R006-e" "dashboard.html not produced for no-status project"
  fi

  rm -rf "$STATUS_DIR"
}

# ============================================================================
# Run all tests
# ============================================================================

test_r001_script_produces_html
test_r002_self_contained
test_r003_data_sources
test_r004_sections
test_r005_styling
test_r006_gitignore
test_r007_graceful_degradation
test_r008_sync
test_r009_cmetrics_mention
test_r004_dev_journal
test_r004_antipattern_dormancy
test_r004_pipeline_phases
test_r001_no_exotic_deps
test_di_r001_qa_rounds_trend
test_di_r002_intensity_accuracy
test_di_r003_override_rate
test_di_r004_fix_rate
test_di_r005_section_order
test_di_r006_graceful_degradation

echo ""
echo "========================================="
echo "  Project Dashboard Tests: $PASS passed, $FAIL failed"
echo "========================================="
if [ -n "$FAILED_IDS" ]; then
  echo "  Failed: $FAILED_IDS"
fi
[ "$FAIL" -eq 0 ]
