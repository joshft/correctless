#!/usr/bin/env bash
# Correctless — Project Dashboard Generator
#
# Reads .correctless/ artifacts and generates a self-contained dashboard.html
# in the current directory. No external dependencies — just bash, jq, and
# standard Unix tools (sed, awk, grep, find, date).
#
# Usage: bash .correctless/scripts/generate-dashboard.sh
#   (or from the repo root: bash scripts/generate-dashboard.sh)
#
# The generated HTML is self-contained — all CSS, JS, and data inline.
# Opens correctly via file:// protocol.

set -euo pipefail

# ============================================================================
# STEP 1: Locate data sources
# ============================================================================

# Resolve paths — works from repo root or installed project
CONFIG_FILE=".correctless/config/workflow-config.json"
if [ ! -f "$CONFIG_FILE" ]; then
  echo "Error: $CONFIG_FILE not found. Run from a project root with Correctless installed." >&2
  exit 1
fi

# ============================================================================
# STEP 2: Read project config
# ============================================================================

PROJECT_NAME=$(jq -r '.project.name // "Unknown Project"' "$CONFIG_FILE")
INTENSITY_FLOOR=$(jq -r '.workflow.intensity // "standard"' "$CONFIG_FILE")

# ============================================================================
# STEP 3: Parse workflow history
# ============================================================================

HISTORY_FILE="docs/workflow-history.md"
HISTORY_JSON="[]"
if [ -f "$HISTORY_FILE" ]; then
  # Parse workflow history entries, using jq for safe JSON string escaping
  HISTORY_JSON="[]"
  _date="" _feature="" _body=""
  while IFS= read -r line || [ -n "$line" ]; do
    if [[ "$line" =~ ^###\ ([0-9]{4}-[0-9]{2}-[0-9]{2})\ —\ (.*) ]]; then
      # Emit previous entry if exists
      if [ -n "$_date" ]; then
        HISTORY_JSON=$(echo "$HISTORY_JSON" | jq --arg d "$_date" --arg f "$_feature" --arg b "$_body" \
          '. + [{"date": $d, "feature": $f, "body": $b}]')
      fi
      _date="${BASH_REMATCH[1]}"
      _feature="${BASH_REMATCH[2]}"
      _body=""
    elif [ -n "$_date" ] && [[ "$line" =~ ^[^#] ]] && [ -n "$line" ]; then
      [ -n "$_body" ] && _body="$_body "
      _body="$_body$line"
    fi
  done < "$HISTORY_FILE"
  # Emit last entry
  if [ -n "$_date" ]; then
    HISTORY_JSON=$(echo "$HISTORY_JSON" | jq --arg d "$_date" --arg f "$_feature" --arg b "$_body" \
      '. + [{"date": $d, "feature": $f, "body": $b}]')
  fi
fi

# Extract structured fields from history body text
FEATURES_JSON=$(echo "$HISTORY_JSON" | jq '
  [.[] | {
    date: .date,
    feature: .feature,
    rules: ((.body | capture("Rules: (?<n>[0-9]+)") | .n | tonumber) // 0),
    qa_rounds: ((.body | capture("QA rounds: (?<n>[0-9]+)") | .n | tonumber) // 0),
    findings_fixed: ((.body | capture("Findings fixed: (?<n>[0-9]+)") | .n | tonumber) // 0),
    overrides: ((.body | capture("Overrides: (?<n>[0-9]+)") | .n | tonumber) // 0),
    branch: ((.body | capture("Branch: (?<b>[^ .]+)") | .b) // "")
  }]
')

TOTAL_FEATURES=$(echo "$FEATURES_JSON" | jq 'length')

# ============================================================================
# STEP 4: Parse QA findings
# ============================================================================

QA_FINDINGS_JSON="[]"
if compgen -G ".correctless/artifacts/qa-findings-*.json" >/dev/null 2>&1; then
  # Extract findings with task slug from each file
  _findings_parts=""
  for _qf in .correctless/artifacts/qa-findings-*.json; do
    _task_slug=$(basename "$_qf" .json | sed 's/^qa-findings-//')
    _part=$(jq --arg task "$_task_slug" '
      [.findings[]? | {
        id: .id,
        severity: .severity,
        description: .description,
        rule_ref: .rule_ref,
        status: .status,
        lens: (.lens // null),
        task: $task
      }]
    ' "$_qf" 2>/dev/null || echo "[]")
    if [ -z "$_findings_parts" ]; then
      _findings_parts="$_part"
    else
      _findings_parts=$(echo "$_findings_parts" "$_part" | jq -s 'add')
    fi
  done
  QA_FINDINGS_JSON="${_findings_parts:-[]}"
fi

TOTAL_FINDINGS=$(echo "$QA_FINDINGS_JSON" | jq 'length')

# Count by phase prefix
QA_COUNT=$(echo "$QA_FINDINGS_JSON" | jq '[.[] | select(.id | startswith("QA-"))] | length')
MA_COUNT=$(echo "$QA_FINDINGS_JSON" | jq '[.[] | select(.id | startswith("MA-"))] | length')
BLOCKING_COUNT=$(echo "$QA_FINDINGS_JSON" | jq '[.[] | select(.severity == "BLOCKING")] | length')
NONBLOCKING_COUNT=$(echo "$QA_FINDINGS_JSON" | jq '[.[] | select(.severity != "BLOCKING")] | length')

# ============================================================================
# STEP 5: Parse review decisions (optional, Phase 3 only)
# ============================================================================

REVIEW_COUNT=0
if compgen -G ".correctless/artifacts/review-decisions-*.json" >/dev/null 2>&1; then
  REVIEW_COUNT=$(jq -s '[.[] | .decisions[]?] | length' .correctless/artifacts/review-decisions-*.json 2>/dev/null || echo "0")
fi

# ============================================================================
# STEP 6: Parse antipatterns
# ============================================================================

ANTIPATTERNS_JSON="[]"
if [ -f ".correctless/antipatterns.md" ]; then
  ANTIPATTERNS_JSON=$(awk '
    /^### AP-[0-9]+:/ {
      if (id != "") {
        gsub(/"/, "\\\"", title)
        gsub(/"/, "\\\"", freq)
        printf "%s{\"id\":\"%s\",\"title\":\"%s\",\"frequency\":\"%s\",\"resolved\":%s}", sep, id, title, freq, resolved
        sep=","
      }
      line = $0
      sub(/^### /, "", line)
      # Extract AP-xxx
      match(line, /AP-[0-9]+/)
      id = substr(line, RSTART, RLENGTH)
      sub(/AP-[0-9]+: */, "", line)
      title = line
      freq = ""
      resolved = "false"
      next
    }
    /\*\*Frequency\*\*/ {
      line = $0
      sub(/.*\*\*Frequency\*\*: */, "", line)
      freq = line
      gsub(/"/, "\\\"", freq)
    }
    /\*\*Status\*\*:.*[Ss]tructurally [Ee]nforced/ {
      resolved = "true"
    }
    END {
      if (id != "") {
        gsub(/"/, "\\\"", title)
        gsub(/"/, "\\\"", freq)
        printf "%s{\"id\":\"%s\",\"title\":\"%s\",\"frequency\":\"%s\",\"resolved\":%s}", sep, id, title, freq, resolved
      }
    }
    BEGIN { sep="" }
  ' ".correctless/antipatterns.md")
  ANTIPATTERNS_JSON="[$ANTIPATTERNS_JSON]"
fi

# Cross-reference dormancy: check last 5 qa-findings files for AP-xxx references
DORMANCY_JSON="{}"
if [ "$ANTIPATTERNS_JSON" != "[]" ] && compgen -G ".correctless/artifacts/qa-findings-*.json" >/dev/null 2>&1; then
  # Get the 5 most recent qa-findings files (by filename sort)
  RECENT_FILES=$(ls -1 .correctless/artifacts/qa-findings-*.json 2>/dev/null | sort | tail -5)
  if [ -n "$RECENT_FILES" ]; then
    # shellcheck disable=SC2086
    DORMANCY_JSON=$(jq -s '
      [.[] | .findings[]? | (.rule_ref // "", .description // "")] | join(" ")
    ' $RECENT_FILES 2>/dev/null | jq -R '
      split(" ") |
      reduce .[] as $word ({};
        if ($word | test("^AP-[0-9]+$")) then .[$word] = true else . end
      )
    ' 2>/dev/null || echo "{}")
  fi
fi

# Enrich antipatterns with dormancy status
ANTIPATTERNS_ENRICHED=$(jq -n \
  --argjson aps "$ANTIPATTERNS_JSON" \
  --argjson dorm "$DORMANCY_JSON" '
  [$aps[] | . + {
    status: (
      if .resolved then "resolved"
      elif ($dorm[.id] // false) then "active"
      else "dormant"
      end
    )
  }]
')

# ============================================================================
# STEP 7: Parse intensity calibration
# ============================================================================

CALIBRATION_JSON="[]"
if [ -f ".correctless/meta/intensity-calibration.json" ]; then
  CALIBRATION_JSON=$(jq '.calibration_entries // []' ".correctless/meta/intensity-calibration.json" 2>/dev/null || echo "[]")
fi

# ============================================================================
# STEP 8: Parse drift debt
# ============================================================================

DRIFT_JSON='{"open":0,"resolved":0,"wont_fix":0,"items":[]}'
if [ -f ".correctless/meta/drift-debt.json" ]; then
  DRIFT_JSON=$(jq '{
    open: [(.items // [])[] | select(.status == "open")] | length,
    resolved: [(.items // [])[] | select(.status == "resolved")] | length,
    wont_fix: [(.items // [])[] | select(.status == "wont-fix")] | length,
    items: (.items // [])
  }' ".correctless/meta/drift-debt.json" 2>/dev/null || echo '{"open":0,"resolved":0,"wont_fix":0,"items":[]}')
fi

# ============================================================================
# STEP 9: Parse token logs
# ============================================================================

TOKEN_JSON="[]"
if compgen -G ".correctless/artifacts/token-log-*.jsonl" >/dev/null 2>&1; then
  TOKEN_JSON=$(cat .correctless/artifacts/token-log-*.jsonl 2>/dev/null | jq -R '
    try (fromjson | {
      phase: (.phase // "unknown"),
      skill: (.skill // "unknown"),
      total_tokens: (.total_tokens // 0),
      input_tokens: (.input_tokens // 0),
      output_tokens: (.output_tokens // 0)
    }) catch empty
  ' | jq -s '.')
fi

# Aggregate tokens by skill
TOKEN_BY_SKILL=$(echo "$TOKEN_JSON" | jq '
  group_by(.skill) |
  [.[] | {
    skill: .[0].skill,
    total_tokens: (map(.total_tokens) | add),
    count: length
  }] | sort_by(-.total_tokens)
')

TOTAL_TOKENS=$(echo "$TOKEN_JSON" | jq '[.[] | .total_tokens] | add // 0')

# ============================================================================
# STEP 9b: Parse cost artifacts (R-007 session-cost-analysis)
# ============================================================================

COST_JSON="[]"
HAS_COST_ARTIFACTS=false
COST_UNKNOWN_MODELS=false
COST_WARNINGS="[]"
if compgen -G ".correctless/artifacts/cost-*.json" >/dev/null 2>&1; then
  HAS_COST_ARTIFACTS=true
  COST_JSON=$(jq -n '[inputs]' .correctless/artifacts/cost-*.json 2>/dev/null || echo "[]")
  # Check for unknown models across all cost artifacts
  COST_UNKNOWN_MODELS=$(echo "$COST_JSON" | jq '[.[] | (.unknown_models // []) | length] | add // 0 | . > 0' 2>/dev/null || echo "false")
  # Collect warnings
  COST_WARNINGS=$(echo "$COST_JSON" | jq '[.[] | (.warnings // [])[]] | unique' 2>/dev/null || echo "[]")
fi

# ============================================================================
# STEP 10: Parse overrides
# ============================================================================

OVERRIDE_COUNT=0
if compgen -G ".correctless/meta/overrides/*.json" >/dev/null 2>&1; then
  OVERRIDE_COUNT=$(jq -s '[.[] | (.overrides // []) | length] | add // 0' .correctless/meta/overrides/*.json 2>/dev/null || echo "0")
fi

# ============================================================================
# STEP 11: Parse dev journal (last 3 entries)
# ============================================================================

JOURNAL_JSON="[]"
if [ -f "docs/dev-journal.md" ]; then
  JOURNAL_JSON=$(awk '
    /^### [0-9]{4}-[0-9]{2}-[0-9]{2} — / {
      if (date != "") {
        gsub(/"/, "\\\"", body)
        printf "%s{\"date\":\"%s\",\"title\":\"%s\",\"body\":\"%s\"}", sep, date, title, body
        sep=","
      }
      line = $0
      sub(/^### /, "", line)
      date = substr(line, 1, 10)
      sub(/^[0-9-]+ — /, "", line)
      title = line
      gsub(/"/, "\\\"", title)
      body = ""
      next
    }
    date != "" && /^[^#]/ && !/^$/ {
      gsub(/"/, "\\\"", $0)
      if (body != "") body = body "\\n"
      body = body $0
    }
    END {
      if (date != "") {
        gsub(/"/, "\\\"", body)
        printf "%s{\"date\":\"%s\",\"title\":\"%s\",\"body\":\"%s\"}", sep, date, title, body
      }
    }
    BEGIN { sep="" }
  ' "docs/dev-journal.md")
  JOURNAL_JSON="[$JOURNAL_JSON]"
  # Take last 3 (they are in file order, most recent first)
  JOURNAL_JSON=$(echo "$JOURNAL_JSON" | jq '.[0:3]')
fi

# ============================================================================
# STEP 12: Read test count from CONTRIBUTING.md
# ============================================================================

TEST_COUNT="N/A"
if [ -f "CONTRIBUTING.md" ]; then
  TEST_COUNT=$(grep -oE '[0-9]+ test files' CONTRIBUTING.md 2>/dev/null | grep -oE '[0-9]+' | head -1 || echo "N/A")
  if [ -z "$TEST_COUNT" ]; then
    TEST_COUNT="N/A"
  fi
fi

# ============================================================================
# STEP 13: Build the unified data JSON
# ============================================================================

DASHBOARD_DATA=$(jq -n \
  --arg project_name "$PROJECT_NAME" \
  --arg intensity_floor "$INTENSITY_FLOOR" \
  --argjson total_features "$TOTAL_FEATURES" \
  --argjson total_findings "$TOTAL_FINDINGS" \
  --arg test_count "$TEST_COUNT" \
  --argjson features "$FEATURES_JSON" \
  --argjson findings "$QA_FINDINGS_JSON" \
  --argjson qa_count "$QA_COUNT" \
  --argjson ma_count "$MA_COUNT" \
  --argjson review_count "$REVIEW_COUNT" \
  --argjson blocking_count "$BLOCKING_COUNT" \
  --argjson nonblocking_count "$NONBLOCKING_COUNT" \
  --argjson antipatterns "$ANTIPATTERNS_ENRICHED" \
  --argjson calibration "$CALIBRATION_JSON" \
  --argjson drift "$DRIFT_JSON" \
  --argjson token_by_skill "$TOKEN_BY_SKILL" \
  --argjson total_tokens "$TOTAL_TOKENS" \
  --argjson override_count "$OVERRIDE_COUNT" \
  --argjson journal "$JOURNAL_JSON" \
  --argjson cost_artifacts "$COST_JSON" \
  --argjson has_cost_artifacts "$HAS_COST_ARTIFACTS" \
  --argjson cost_unknown_models "$COST_UNKNOWN_MODELS" \
  --argjson cost_warnings "$COST_WARNINGS" \
  '{
    project_name: $project_name,
    intensity_floor: $intensity_floor,
    total_features: $total_features,
    total_findings: $total_findings,
    test_count: $test_count,
    features: $features,
    findings: $findings,
    qa_count: $qa_count,
    ma_count: $ma_count,
    review_count: $review_count,
    blocking_count: $blocking_count,
    nonblocking_count: $nonblocking_count,
    antipatterns: $antipatterns,
    calibration: $calibration,
    drift: $drift,
    token_by_skill: $token_by_skill,
    total_tokens: $total_tokens,
    override_count: $override_count,
    journal: $journal,
    cost_artifacts: $cost_artifacts,
    has_cost_artifacts: $has_cost_artifacts,
    cost_unknown_models: $cost_unknown_models,
    cost_warnings: $cost_warnings
  }')

# ============================================================================
# STEP 14: Generate HTML
# ============================================================================

cat > dashboard.html <<'HTMLEOF'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Correctless Dashboard</title>
<style>
  :root {
    --bg: #ffffff;
    --fg: #1a1a2e;
    --card-bg: #f8f9fa;
    --border: #dee2e6;
    --accent: #4361ee;
    --red: #e63946;
    --yellow: #f4a261;
    --green: #2a9d8f;
    --muted: #6c757d;
    --journal-bg: #f0f0f0;
  }
  @media (prefers-color-scheme: dark) {
    :root {
      --bg: #0d1117;
      --fg: #c9d1d9;
      --card-bg: #161b22;
      --border: #30363d;
      --accent: #58a6ff;
      --red: #f85149;
      --yellow: #d29922;
      --green: #3fb950;
      --muted: #8b949e;
      --journal-bg: #1c2128;
    }
  }
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body {
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
    background: var(--bg);
    color: var(--fg);
    line-height: 1.6;
    max-width: 900px;
    margin: 0 auto;
    padding: 2rem 1.5rem;
  }
  h1 { font-size: 1.8rem; margin-bottom: 0.25rem; }
  h2 { font-size: 1.3rem; margin-top: 2.5rem; margin-bottom: 1rem; border-bottom: 2px solid var(--accent); padding-bottom: 0.3rem; }
  .subtitle { color: var(--muted); font-size: 0.9rem; margin-bottom: 2rem; }
  .health-verdict { background: var(--card-bg); padding: 1rem; border-radius: 6px; border-left: 4px solid var(--accent); margin-bottom: 1rem; font-size: 0.95rem; }
  .stat-row { display: flex; gap: 1rem; flex-wrap: wrap; margin-bottom: 1rem; }
  .stat { background: var(--card-bg); padding: 0.75rem 1rem; border-radius: 6px; flex: 1; min-width: 120px; }
  .stat-label { font-size: 0.75rem; color: var(--muted); text-transform: uppercase; letter-spacing: 0.05em; }
  .stat-value { font-size: 1.4rem; font-weight: 700; }
  .bar-container { margin-bottom: 0.75rem; }
  .bar-label { font-size: 0.85rem; margin-bottom: 0.25rem; display: flex; justify-content: space-between; }
  .bar-track { background: var(--card-bg); border-radius: 4px; height: 24px; overflow: hidden; display: flex; }
  .bar-fill { height: 100%; display: flex; align-items: center; justify-content: center; font-size: 0.7rem; color: #fff; min-width: 2px; transition: width 0.3s; }
  .bar-blocking { background: var(--red); }
  .bar-nonblocking { background: var(--yellow); }
  .bar-qa { background: var(--accent); }
  .bar-ma { background: var(--green); }
  .bar-review { background: var(--yellow); }
  .badge { display: inline-block; padding: 0.15rem 0.5rem; border-radius: 3px; font-size: 0.75rem; font-weight: 600; }
  .badge-blocking, .badge-critical { background: var(--red); color: #fff; }
  .badge-nonblocking, .badge-medium { background: var(--yellow); color: #000; }
  .badge-resolved, .badge-clean { background: var(--green); color: #fff; }
  .badge-dormant { background: var(--muted); color: #fff; }
  .badge-active { background: var(--red); color: #fff; }
  table { width: 100%; border-collapse: collapse; margin-bottom: 1rem; font-size: 0.85rem; }
  th, td { padding: 0.5rem 0.75rem; text-align: left; border-bottom: 1px solid var(--border); }
  th { font-weight: 600; color: var(--muted); font-size: 0.75rem; text-transform: uppercase; }
  .ap-item { margin-bottom: 0.75rem; padding: 0.5rem 0.75rem; background: var(--card-bg); border-radius: 4px; }
  .ap-header { display: flex; justify-content: space-between; align-items: center; }
  .ap-title { font-weight: 600; font-size: 0.9rem; }
  .ap-freq { font-size: 0.8rem; color: var(--muted); }
  .journal-section { background: var(--journal-bg); padding: 1.5rem; border-radius: 6px; margin-top: 0.5rem; }
  .journal-entry { margin-bottom: 1.25rem; padding-bottom: 1rem; border-bottom: 1px solid var(--border); }
  .journal-entry:last-child { border-bottom: none; margin-bottom: 0; padding-bottom: 0; }
  .journal-date { font-size: 0.8rem; color: var(--muted); }
  .journal-title { font-weight: 600; font-size: 0.95rem; }
  .journal-body { font-size: 0.85rem; color: var(--muted); margin-top: 0.25rem; white-space: pre-wrap; }
  .empty-msg { color: var(--muted); font-style: italic; padding: 1rem 0; }
  .trend-note { color: var(--muted); font-size: 0.85rem; font-style: italic; margin-top: 0.25rem; }
  .stacked-bar { display: flex; height: 32px; border-radius: 4px; overflow: hidden; margin-bottom: 0.5rem; }
  .stacked-segment { display: flex; align-items: center; justify-content: center; font-size: 0.7rem; color: #fff; }
  .legend { display: flex; gap: 1rem; flex-wrap: wrap; font-size: 0.8rem; margin-bottom: 1rem; }
  .legend-item { display: flex; align-items: center; gap: 0.3rem; }
  .legend-dot { width: 12px; height: 12px; border-radius: 2px; }
  footer { margin-top: 3rem; text-align: center; color: var(--muted); font-size: 0.75rem; }
</style>
</head>
<body>
<script id="dashboard-data" type="application/json">
HTMLEOF

# Inject the data JSON
echo "$DASHBOARD_DATA" >> dashboard.html

cat >> dashboard.html <<'HTMLEOF2'
</script>

<div id="app"></div>

<script>
(function() {
  const data = JSON.parse(document.getElementById('dashboard-data').textContent);
  const app = document.getElementById('app');

  function h(tag, attrs, ...children) {
    const el = document.createElement(tag);
    if (attrs) Object.entries(attrs).forEach(([k, v]) => {
      if (k === 'style' && typeof v === 'object') Object.assign(el.style, v);
      else if (k === 'className') el.className = v;
      else if (k === 'innerHTML') el.innerHTML = v;
      else el.setAttribute(k, v);
    });
    children.flat().forEach(c => {
      if (typeof c === 'string') el.appendChild(document.createTextNode(c));
      else if (c) el.appendChild(c);
    });
    return el;
  }

  // ---- Section 1: Project Summary ----
  app.appendChild(h('h1', null, data.project_name + ' Dashboard'));
  app.appendChild(h('div', { className: 'subtitle' }, 'Generated ' + new Date().toISOString().slice(0, 10)));

  const verdict = data.total_features + ' features, ' +
    data.total_findings + ' findings caught pre-merge, ' +
    data.antipatterns.length + ' antipatterns catalogued.';
  app.appendChild(h('div', { className: 'health-verdict' }, verdict));

  const stats = h('div', { className: 'stat-row' });
  [{l:'Features Shipped', v:data.total_features},
   {l:'Findings Caught', v:data.total_findings},
   {l:'Test Count', v:data.test_count},
   {l:'Intensity Floor', v:data.intensity_floor}
  ].forEach(s => {
    const st = h('div', { className: 'stat' });
    st.appendChild(h('div', { className: 'stat-label' }, s.l));
    st.appendChild(h('div', { className: 'stat-value' }, String(s.v)));
    stats.appendChild(st);
  });
  app.appendChild(stats);

  // ---- Section 2: Quality Trajectory ----
  app.appendChild(h('h2', null, 'Quality Trajectory'));

  if (data.features.length === 0) {
    app.appendChild(h('div', { className: 'empty-msg' }, 'No workflow history yet.'));
  } else {
    // Build per-feature severity counts from real findings data
    const featureSeverity = {};
    (data.findings || []).forEach(f => {
      if (!f.task) return;
      if (!featureSeverity[f.task]) featureSeverity[f.task] = { blocking: 0, nonblocking: 0 };
      if (f.severity === 'BLOCKING') featureSeverity[f.task].blocking++;
      else featureSeverity[f.task].nonblocking++;
    });
    const maxFindings = Math.max(...data.features.map(f => f.findings_fixed), 1);
    data.features.forEach(f => {
      // Match feature to findings by normalized slug comparison
      const slug = f.feature.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');
      const sev = featureSeverity[slug] || null;
      let pctBlocking, pctNonblocking;
      if (sev) {
        const total = sev.blocking + sev.nonblocking;
        pctBlocking = total > 0 ? Math.round((sev.blocking / maxFindings) * 100) : 0;
        pctNonblocking = total > 0 ? Math.round((sev.nonblocking / maxFindings) * 100) : 0;
      } else {
        // No per-severity data available — show single-color bar with total
        pctBlocking = 0;
        pctNonblocking = f.findings_fixed > 0 ? Math.round((f.findings_fixed / maxFindings) * 100) : 0;
      }
      const container = h('div', { className: 'bar-container' });
      const label = h('div', { className: 'bar-label' });
      label.appendChild(h('span', null, f.feature));
      label.appendChild(h('span', null, f.findings_fixed + ' findings'));
      container.appendChild(label);
      const track = h('div', { className: 'bar-track' });
      if (pctBlocking > 0) {
        track.appendChild(h('div', { className: 'bar-fill bar-blocking', style: { width: pctBlocking + '%' } }));
      }
      if (pctNonblocking > 0) {
        track.appendChild(h('div', { className: 'bar-fill bar-nonblocking', style: { width: pctNonblocking + '%' } }));
      }
      container.appendChild(track);
      app.appendChild(container);
    });

    if (data.features.length === 1) {
      app.appendChild(h('div', { className: 'trend-note' }, 'Need more features to show a trend.'));
    }

    const legend = h('div', { className: 'legend' });
    [{c:'bar-blocking', l:'BLOCKING'}, {c:'bar-nonblocking', l:'NON-BLOCKING'}].forEach(item => {
      const li = h('div', { className: 'legend-item' });
      li.appendChild(h('div', { className: 'legend-dot ' + item.c }));
      li.appendChild(h('span', null, item.l));
      legend.appendChild(li);
    });
    app.appendChild(legend);
  }

  // ---- Section 2b: QA Rounds Trend ----
  app.appendChild(h('h2', null, 'QA Rounds Trend'));

  const featuresWithRounds = data.features.filter(f => f.qa_rounds > 0);
  if (featuresWithRounds.length === 0) {
    app.appendChild(h('div', { className: 'empty-msg' }, 'No QA round data.'));
  } else {
    const maxRounds = Math.max(...data.features.map(f => f.qa_rounds), 1);
    data.features.forEach(f => {
      const container = h('div', { className: 'bar-container' });
      const label = h('div', { className: 'bar-label' });
      label.appendChild(h('span', null, f.feature));
      label.appendChild(h('span', null, f.qa_rounds + ' rounds'));
      container.appendChild(label);
      const track = h('div', { className: 'bar-track' });
      const pct = f.qa_rounds > 0 ? Math.round((f.qa_rounds / maxRounds) * 100) : 0;
      if (pct > 0) {
        track.appendChild(h('div', { className: 'bar-fill bar-qa', style: { width: pct + '%' } }));
      }
      container.appendChild(track);
      app.appendChild(container);
    });
  }

  // ---- Section 3: Pipeline Phase Distribution ----
  app.appendChild(h('h2', null, 'Pipeline Phase Distribution'));

  const phaseTotal = data.qa_count + data.ma_count + data.review_count;
  if (phaseTotal === 0) {
    app.appendChild(h('div', { className: 'empty-msg' }, 'No findings data yet.'));
  } else {
    const bar = h('div', { className: 'stacked-bar' });
    if (data.qa_count > 0) {
      const pct = Math.round((data.qa_count / phaseTotal) * 100);
      bar.appendChild(h('div', { className: 'stacked-segment bar-qa', style: { width: pct + '%' } }, 'QA ' + data.qa_count));
    }
    if (data.ma_count > 0) {
      const pct = Math.round((data.ma_count / phaseTotal) * 100);
      bar.appendChild(h('div', { className: 'stacked-segment bar-ma', style: { width: pct + '%' } }, 'Mini-audit ' + data.ma_count));
    }
    if (data.review_count > 0) {
      const pct = Math.round((data.review_count / phaseTotal) * 100);
      bar.appendChild(h('div', { className: 'stacked-segment bar-review', style: { width: pct + '%' } }, 'Review ' + data.review_count));
    }
    app.appendChild(bar);

    const phaseLegend = h('div', { className: 'legend' });
    [{c:'bar-qa', l:'QA (QA- prefix)'}, {c:'bar-ma', l:'Mini-audit (MA- prefix)'}, {c:'bar-review', l:'Review'}].forEach(item => {
      const li = h('div', { className: 'legend-item' });
      li.appendChild(h('div', { className: 'legend-dot ' + item.c }));
      li.appendChild(h('span', null, item.l));
      phaseLegend.appendChild(li);
    });
    app.appendChild(phaseLegend);
  }

  // ---- Section 3b: Fix Rate ----
  app.appendChild(h('h2', null, 'Fix Rate'));

  if (data.findings.length === 0) {
    app.appendChild(h('div', { className: 'empty-msg' }, 'No findings data.'));
  } else {
    const withStatus = data.findings.filter(f => f.status);
    if (withStatus.length === 0) {
      app.appendChild(h('div', { className: 'empty-msg' }, 'Fix status data not available.'));
    } else {
      const fixedCount = withStatus.filter(f => f.status === 'fixed').length;
      const totalWithStatus = withStatus.length;
      const fixPct = totalWithStatus > 0 ? Math.round((fixedCount / totalWithStatus) * 100) : 0;
      app.appendChild(h('div', { className: 'health-verdict' },
        fixedCount + '/' + totalWithStatus + ' findings fixed (' + fixPct + '%)'));
      const fixTrack = h('div', { className: 'bar-track' });
      if (fixPct > 0) {
        fixTrack.appendChild(h('div', { className: 'bar-fill bar-qa', style: { width: fixPct + '%' } }));
      }
      app.appendChild(fixTrack);
    }
  }

  // ---- Section 4: Antipattern Health ----
  app.appendChild(h('h2', null, 'Antipattern Health'));

  if (data.antipatterns.length === 0) {
    app.appendChild(h('div', { className: 'empty-msg' }, 'No antipatterns catalogued yet.'));
  } else {
    data.antipatterns.forEach(ap => {
      const item = h('div', { className: 'ap-item' });
      const header = h('div', { className: 'ap-header' });
      header.appendChild(h('span', { className: 'ap-title' }, ap.id + ': ' + ap.title));
      const badgeClass = ap.status === 'resolved' ? 'badge-resolved' :
                         ap.status === 'dormant' ? 'badge-dormant' : 'badge-active';
      header.appendChild(h('span', { className: 'badge ' + badgeClass }, ap.status));
      item.appendChild(header);
      if (ap.frequency) {
        item.appendChild(h('div', { className: 'ap-freq' }, ap.frequency));
      }
      app.appendChild(item);
    });
  }

  // ---- Section 5: Intensity Accuracy ----
  app.appendChild(h('h2', null, 'Intensity Accuracy'));

  if (data.calibration.length === 0) {
    app.appendChild(h('div', { className: 'empty-msg' }, 'No calibration data.'));
  } else {
    // Compute agreed/raised/lowered summary
    const intensityOrder = { lite: 0, standard: 1, high: 2, critical: 3 };
    let agreed = 0, raised = 0, lowered = 0;
    data.calibration.forEach(c => {
      const rec = intensityOrder[c.recommended_intensity] !== undefined ? intensityOrder[c.recommended_intensity] : -1;
      const act = intensityOrder[c.actual_intensity] !== undefined ? intensityOrder[c.actual_intensity] : -1;
      if (rec === act) agreed++;
      else if (act > rec) raised++;
      else lowered++;
    });
    const totalCal = agreed + raised + lowered;
    const agreedPct = totalCal > 0 ? Math.round((agreed / totalCal) * 100) : 0;
    app.appendChild(h('div', { className: 'health-verdict' },
      'Agreed: ' + agreed + ', Raised: ' + raised + ', Lowered: ' + lowered + ' (' + agreedPct + '% agreed)'));

    // Detailed calibration table
    const table = h('table');
    const thead = h('thead');
    const hrow = h('tr');
    ['Feature', 'Recommended', 'Actual', 'QA Rounds', 'Tokens'].forEach(col => {
      hrow.appendChild(h('th', null, col));
    });
    thead.appendChild(hrow);
    table.appendChild(thead);
    const tbody = h('tbody');
    data.calibration.forEach(c => {
      const row = h('tr');
      row.appendChild(h('td', null, c.feature_slug));
      row.appendChild(h('td', null, c.recommended_intensity));
      const actualTd = h('td', null, c.actual_intensity);
      if (c.recommended_intensity !== c.actual_intensity) {
        actualTd.style.fontWeight = '700';
        actualTd.style.color = 'var(--yellow)';
      }
      row.appendChild(actualTd);
      row.appendChild(h('td', null, String(c.actual_qa_rounds)));
      row.appendChild(h('td', null, c.actual_tokens ? c.actual_tokens.toLocaleString() : '-'));
      tbody.appendChild(row);
    });
    table.appendChild(tbody);
    app.appendChild(table);
  }

  // ---- Section 5b: Override Rate ----
  app.appendChild(h('h2', null, 'Override Rate'));

  const featuresWithOverrides = data.features.filter(f => f.overrides > 0);
  if (data.features.length === 0 || (featuresWithOverrides.length === 0 && data.override_count === 0)) {
    app.appendChild(h('div', { className: 'empty-msg' }, 'No override data.'));
  } else {
    const maxOverrides = Math.max(...data.features.map(f => f.overrides), 1);
    data.features.forEach(f => {
      const container = h('div', { className: 'bar-container' });
      const label = h('div', { className: 'bar-label' });
      label.appendChild(h('span', null, f.feature));
      label.appendChild(h('span', null, f.overrides + ' overrides'));
      container.appendChild(label);
      const track = h('div', { className: 'bar-track' });
      const pct = f.overrides > 0 ? Math.round((f.overrides / maxOverrides) * 100) : 0;
      if (pct > 0) {
        track.appendChild(h('div', { className: 'bar-fill bar-yellow', style: { width: pct + '%', background: 'var(--yellow)' } }));
      }
      container.appendChild(track);
      app.appendChild(container);
    });
    const totalOverrides = data.features.reduce((sum, f) => sum + f.overrides, 0);
    const meanOverrides = data.features.length > 0 ? (totalOverrides / data.features.length).toFixed(1) : '0.0';
    app.appendChild(h('div', { className: 'trend-note' }, 'Mean: ' + meanOverrides + ' overrides per feature.'));
  }

  // ---- Section 6: Cost by Phase ----
  app.appendChild(h('h2', null, 'Cost by Phase'));

  if (data.has_cost_artifacts && data.cost_artifacts.length > 0) {
    // Render USD cost from cost artifacts (R-007)
    const allPhases = data.cost_artifacts.flatMap(a => a.by_phase || []);
    const totalCost = data.cost_artifacts.reduce((s, a) => s + (a.total_cost_usd || 0), 0);
    // Merge phases across artifacts
    const phaseMap = {};
    allPhases.forEach(p => {
      if (!phaseMap[p.phase]) phaseMap[p.phase] = { phase: p.phase, cost_usd: 0, turns: 0 };
      phaseMap[p.phase].cost_usd += p.cost_usd || 0;
      phaseMap[p.phase].turns += p.turns || 0;
    });
    const phases = Object.values(phaseMap).sort((a, b) => b.cost_usd - a.cost_usd);

    const costTable = h('table');
    const cthead = h('thead');
    const chr = h('tr');
    ['Phase', 'Cost (USD)', '% of Total', 'Turns'].forEach(col => {
      chr.appendChild(h('th', null, col));
    });
    cthead.appendChild(chr);
    costTable.appendChild(cthead);
    const ctbody = h('tbody');
    phases.forEach(p => {
      const row = h('tr');
      row.appendChild(h('td', null, p.phase));
      row.appendChild(h('td', null, '$' + p.cost_usd.toFixed(2)));
      const pct = totalCost > 0 ? Math.round((p.cost_usd / totalCost) * 100) : 0;
      row.appendChild(h('td', null, pct + '%'));
      row.appendChild(h('td', null, String(p.turns)));
      ctbody.appendChild(row);
    });
    costTable.appendChild(ctbody);
    app.appendChild(costTable);
    app.appendChild(h('div', { className: 'trend-note' }, 'Total: $' + totalCost.toFixed(2)));
    if (data.cost_unknown_models) {
      app.appendChild(h('div', { className: 'trend-note' }, '* includes estimated pricing for unrecognized models.'));
    }
    if (data.cost_warnings.length > 0) {
      data.cost_warnings.forEach(w => {
        app.appendChild(h('div', { className: 'trend-note' }, 'Warning: ' + w));
      });
    }
  } else if (data.token_by_skill.length === 0) {
    app.appendChild(h('div', { className: 'empty-msg' }, 'No token data yet.'));
  } else {
    // Fallback: token-log data only (no cost artifacts)
    app.appendChild(h('div', { className: 'trend-note' }, '(token count only — run /cdocs to compute USD cost)'));
    const tokenTable = h('table');
    const tthead = h('thead');
    const the = h('tr');
    ['Skill', 'Total Tokens', '% of Total', 'Calls'].forEach(col => {
      the.appendChild(h('th', null, col));
    });
    tthead.appendChild(the);
    tokenTable.appendChild(tthead);
    const ttbody = h('tbody');
    data.token_by_skill.forEach(t => {
      const row = h('tr');
      row.appendChild(h('td', null, t.skill));
      row.appendChild(h('td', null, t.total_tokens.toLocaleString()));
      const pct = data.total_tokens > 0 ? Math.round((t.total_tokens / data.total_tokens) * 100) : 0;
      row.appendChild(h('td', null, pct + '%'));
      row.appendChild(h('td', null, String(t.count)));
      ttbody.appendChild(row);
    });
    tokenTable.appendChild(ttbody);
    app.appendChild(tokenTable);
  }

  // ---- Section 7: Drift Debt ----
  app.appendChild(h('h2', null, 'Drift Debt'));

  if (data.drift.items.length === 0) {
    app.appendChild(h('div', { className: 'empty-msg' }, 'No drift debt items.'));
  } else {
    const driftStats = h('div', { className: 'stat-row' });
    [{l:'Open', v:data.drift.open}, {l:'Resolved', v:data.drift.resolved}, {l:'Won\'t Fix', v:data.drift.wont_fix}].forEach(s => {
      const st = h('div', { className: 'stat' });
      st.appendChild(h('div', { className: 'stat-label' }, s.l));
      st.appendChild(h('div', { className: 'stat-value' }, String(s.v)));
      driftStats.appendChild(st);
    });
    app.appendChild(driftStats);

    const driftTable = h('table');
    const dthead = h('thead');
    const dhrow = h('tr');
    ['ID', 'Description', 'Status'].forEach(col => {
      dhrow.appendChild(h('th', null, col));
    });
    dthead.appendChild(dhrow);
    driftTable.appendChild(dthead);
    const dtbody = h('tbody');
    data.drift.items.forEach(d => {
      const row = h('tr');
      row.appendChild(h('td', null, d.id));
      row.appendChild(h('td', null, d.description));
      const badgeClass = d.status === 'resolved' ? 'badge-resolved' :
                         d.status === 'open' ? 'badge-active' : 'badge-dormant';
      const statusTd = h('td');
      statusTd.appendChild(h('span', { className: 'badge ' + badgeClass }, d.status));
      row.appendChild(statusTd);
      dtbody.appendChild(row);
    });
    driftTable.appendChild(dtbody);
    app.appendChild(driftTable);
  }

  // ---- Section 8: Dev Journal ----
  app.appendChild(h('h2', null, 'Dev Journal'));

  if (data.journal.length === 0) {
    app.appendChild(h('div', { className: 'empty-msg' }, 'No dev journal entries yet.'));
  } else {
    const section = h('div', { className: 'journal-section' });
    data.journal.forEach(j => {
      const entry = h('div', { className: 'journal-entry' });
      entry.appendChild(h('div', { className: 'journal-date' }, j.date));
      entry.appendChild(h('div', { className: 'journal-title' }, j.title));
      if (j.body) {
        entry.appendChild(h('div', { className: 'journal-body' }, j.body));
      }
      section.appendChild(entry);
    });
    app.appendChild(section);
  }

  // ---- Footer ----
  app.appendChild(h('footer', null, 'Generated by Correctless — correctless.dev'));

})();
</script>
</body>
</html>
HTMLEOF2

echo "Dashboard generated: dashboard.html"
