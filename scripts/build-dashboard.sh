#!/usr/bin/env bash
# Correctless — Project Dashboard UI Builder
#
# Reads .correctless/ artifacts and generates a self-contained HTML dashboard
# at .correctless/dashboard/index.html. Two views: Metrics + Artifact Browser.
# Uses marked.js (CDN, SRI-pinned) + DOMPurify for safe markdown rendering.
#
# Usage: bash scripts/build-dashboard.sh [project-root]
#   project-root defaults to cwd if not provided.
#
# Requires: bash 4+, jq 1.7+, standard POSIX tools (sed, awk, grep, find).
# Exit 0 on success, 1 on failure (with passthrough fallback listing artifacts).

set -euo pipefail

# ============================================================================
# STEP 0: Resolve project root
# ============================================================================

PROJECT_ROOT="${1:-.}"
PROJECT_ROOT=$(cd "$PROJECT_ROOT" 2>/dev/null && pwd) || {
  echo "Error: cannot resolve project root: ${1:-.}" >&2
  exit 1
}
cd "$PROJECT_ROOT"

CONFIG_FILE=".correctless/config/workflow-config.json"
if [ ! -f "$CONFIG_FILE" ]; then
  echo "Error: $CONFIG_FILE not found. Run from a project root with Correctless installed." >&2
  # Passthrough fallback: list available artifacts
  echo "" >&2
  echo "Available artifacts in $PROJECT_ROOT:" >&2
  find "$PROJECT_ROOT/.correctless" -name '*.md' -o -name '*.json' 2>/dev/null | head -20 >&2 || true
  exit 1
fi

# ============================================================================
# STEP 1: Read project config
# ============================================================================

PROJECT_NAME=$(jq -r '.project.name // "Unknown Project"' "$CONFIG_FILE")
INTENSITY_FLOOR=$(jq -r '.workflow.intensity // "standard"' "$CONFIG_FILE")

# ============================================================================
# STEP 2: Parse workflow history
# ============================================================================

HISTORY_FILE="docs/workflow-history.md"
HISTORY_JSON="[]"
if [ -f "$HISTORY_FILE" ]; then
  _date="" _feature="" _body=""
  while IFS= read -r line || [ -n "$line" ]; do
    if [[ "$line" =~ ^###\ ([0-9]{4}-[0-9]{2}-[0-9]{2})\ —\ (.*) ]]; then
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
  if [ -n "$_date" ]; then
    HISTORY_JSON=$(echo "$HISTORY_JSON" | jq --arg d "$_date" --arg f "$_feature" --arg b "$_body" \
      '. + [{"date": $d, "feature": $f, "body": $b}]')
  fi
fi

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
# STEP 3: Parse QA findings
# ============================================================================

QA_FINDINGS_JSON="[]"
if compgen -G ".correctless/artifacts/qa-findings-*.json" >/dev/null 2>&1; then
  QA_FINDINGS_JSON=$(jq -n '[inputs | .findings[]? | {
    id: .id,
    severity: .severity,
    description: .description,
    rule_ref: .rule_ref,
    status: .status,
    lens: (.lens // null),
    task: (input_filename | ltrimstr(".correctless/artifacts/qa-findings-") | rtrimstr(".json"))
  }]' .correctless/artifacts/qa-findings-*.json 2>/dev/null || echo "[]")
fi

eval "$(echo "$QA_FINDINGS_JSON" | jq -r '
  "TOTAL_FINDINGS=\(length)",
  "QA_COUNT=\([.[] | select(.id | startswith("QA-"))] | length)",
  "MA_COUNT=\([.[] | select(.id | startswith("MA-"))] | length)",
  "BLOCKING_COUNT=\([.[] | select(.severity == "BLOCKING")] | length)",
  "NONBLOCKING_COUNT=\([.[] | select(.severity != "BLOCKING")] | length)"
')"

# ============================================================================
# STEP 4: Parse review decisions
# ============================================================================

REVIEW_COUNT=0
if compgen -G ".correctless/artifacts/review-decisions-*.json" >/dev/null 2>&1; then
  REVIEW_COUNT=$(jq -s '[.[] | .decisions[]?] | length' .correctless/artifacts/review-decisions-*.json 2>/dev/null || echo "0")
fi

# ============================================================================
# STEP 5: Parse antipatterns
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

DORMANCY_JSON="{}"
if [ "$ANTIPATTERNS_JSON" != "[]" ] && compgen -G ".correctless/artifacts/qa-findings-*.json" >/dev/null 2>&1; then
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
# STEP 6: Parse intensity calibration
# ============================================================================

CALIBRATION_JSON="[]"
if [ -f ".correctless/meta/intensity-calibration.json" ]; then
  CALIBRATION_JSON=$(jq '.calibration_entries // []' ".correctless/meta/intensity-calibration.json" 2>/dev/null || echo "[]")
fi

# ============================================================================
# STEP 7: Parse drift debt
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
# STEP 8: Parse token logs
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
# STEP 8b: Parse cost artifacts
# ============================================================================

COST_JSON="[]"
HAS_COST_ARTIFACTS=false
COST_UNKNOWN_MODELS=false
COST_WARNINGS="[]"
if compgen -G ".correctless/artifacts/cost-*.json" >/dev/null 2>&1; then
  HAS_COST_ARTIFACTS=true
  COST_JSON=$(jq -n '[inputs]' .correctless/artifacts/cost-*.json 2>/dev/null || echo "[]")
  eval "$(echo "$COST_JSON" | jq -r '
    "COST_UNKNOWN_MODELS=\([.[] | (.unknown_models // []) | length] | add // 0 | . > 0)",
    "COST_WARNINGS=\([.[] | (.warnings // [])[]] | unique | @json)"
  ' 2>/dev/null || echo 'COST_UNKNOWN_MODELS=false; COST_WARNINGS="[]"')"
fi

# ============================================================================
# STEP 8c: Parse escape metrics
# ============================================================================

ESCAPE_METRICS_JSON='{"dormant":true}'
HAS_ESCAPE_DATA=false
if compgen -G ".correctless/artifacts/findings/audit-*-round-*.json" >/dev/null 2>&1; then
  HAS_ESCAPE_DATA=true
  ESCAPE_METRICS_JSON=$(jq -n '[inputs]' .correctless/artifacts/findings/audit-*-round-*.json 2>/dev/null | jq '
    [.[] | (.findings // [])[] | select(.severity != null)] as $all_findings |
    [$all_findings[] | select((.severity | ascii_downcase) != "info")] as $escapes |
    {
      dormant: false,
      total_findings: ($all_findings | length),
      escape_count: ($escapes | length),
      weighted_score: ([$escapes[] |
        ((.severity | ascii_downcase) as $s |
          if $s == "critical" then 5
          elif $s == "high" then 3
          elif $s == "medium" then 2
          elif $s == "low" then 1
          else 0 end)
      ] | add // 0),
      severity_distribution: {
        critical: [$all_findings[] | select((.severity | ascii_downcase) == "critical")] | length,
        high: [$all_findings[] | select((.severity | ascii_downcase) == "high")] | length,
        medium: [$all_findings[] | select((.severity | ascii_downcase) == "medium")] | length,
        low: [$all_findings[] | select((.severity | ascii_downcase) == "low")] | length
      }
    }
  ' 2>/dev/null || echo '{"dormant":true}')
fi

# ============================================================================
# STEP 9: Parse overrides
# ============================================================================

OVERRIDE_COUNT=0
if compgen -G ".correctless/meta/overrides/*.json" >/dev/null 2>&1; then
  OVERRIDE_COUNT=$(jq -s '[.[] | (.overrides // []) | length] | add // 0' .correctless/meta/overrides/*.json 2>/dev/null || echo "0")
fi

# ============================================================================
# STEP 10: Parse dev journal (last 3 entries)
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
  JOURNAL_JSON=$(echo "$JOURNAL_JSON" | jq '.[0:3]')
fi

# ============================================================================
# STEP 11: Read test count from CONTRIBUTING.md
# ============================================================================

TEST_COUNT="N/A"
if [ -f "CONTRIBUTING.md" ]; then
  TEST_COUNT=$(grep -oE '[0-9]+ test files' CONTRIBUTING.md 2>/dev/null | grep -oE '[0-9]+' | head -1 || echo "N/A")
  [ -z "$TEST_COUNT" ] && TEST_COUNT="N/A"
fi

# ============================================================================
# STEP 12: Collect Artifact Browser data
# ============================================================================

# Helper: read a file and return JSON-safe content via jq --arg
read_file_json() {
  local filepath="$1"
  local name
  name=$(basename "$filepath")
  local content
  content=$(cat "$filepath" 2>/dev/null || echo "")
  jq -n --arg name "$name" --arg path "$filepath" --arg content "$content" \
    '{"name": $name, "path": $path, "content": $content}'
}

# Collect artifacts by category
BROWSER_SPECS="[]"
if compgen -G ".correctless/specs/*.md" >/dev/null 2>&1; then
  BROWSER_SPECS="[]"
  for f in .correctless/specs/*.md; do
    [ -f "$f" ] || continue
    entry=$(read_file_json "$f")
    BROWSER_SPECS=$(echo "$BROWSER_SPECS" | jq --argjson e "$entry" '. + [$e]')
  done
fi

BROWSER_VERIFICATIONS="[]"
if compgen -G ".correctless/verification/*.md" >/dev/null 2>&1; then
  BROWSER_VERIFICATIONS="[]"
  for f in .correctless/verification/*.md; do
    [ -f "$f" ] || continue
    entry=$(read_file_json "$f")
    BROWSER_VERIFICATIONS=$(echo "$BROWSER_VERIFICATIONS" | jq --argjson e "$entry" '. + [$e]')
  done
fi

BROWSER_REVIEW_FINDINGS="[]"
for pattern in ".correctless/artifacts/review-spec-findings-*.md" ".correctless/artifacts/review-findings-*.md"; do
  if compgen -G "$pattern" >/dev/null 2>&1; then
    # shellcheck disable=SC2086
    for f in $pattern; do
      [ -f "$f" ] || continue
      entry=$(read_file_json "$f")
      BROWSER_REVIEW_FINDINGS=$(echo "$BROWSER_REVIEW_FINDINGS" | jq --argjson e "$entry" '. + [$e]')
    done
  fi
done

BROWSER_RESEARCH="[]"
if compgen -G ".correctless/artifacts/research/*.md" >/dev/null 2>&1; then
  for f in .correctless/artifacts/research/*.md; do
    [ -f "$f" ] || continue
    entry=$(read_file_json "$f")
    BROWSER_RESEARCH=$(echo "$BROWSER_RESEARCH" | jq --argjson e "$entry" '. + [$e]')
  done
fi

BROWSER_ARCHITECTURE="[]"
for arch_file in ".correctless/ARCHITECTURE.md" ".correctless/AGENT_CONTEXT.md" ".correctless/antipatterns.md"; do
  if [ -f "$arch_file" ]; then
    entry=$(read_file_json "$arch_file")
    BROWSER_ARCHITECTURE=$(echo "$BROWSER_ARCHITECTURE" | jq --argjson e "$entry" '. + [$e]')
  fi
done

BROWSER_QA_FINDINGS="[]"
if compgen -G ".correctless/artifacts/qa-findings-*.json" >/dev/null 2>&1; then
  for f in .correctless/artifacts/qa-findings-*.json; do
    [ -f "$f" ] || continue
    entry=$(read_file_json "$f")
    BROWSER_QA_FINDINGS=$(echo "$BROWSER_QA_FINDINGS" | jq --argjson e "$entry" '. + [$e]')
  done
fi

BROWSER_AUDIT_HISTORY="[]"
if compgen -G ".correctless/artifacts/findings/audit-*-history.md" >/dev/null 2>&1; then
  for f in .correctless/artifacts/findings/audit-*-history.md; do
    [ -f "$f" ] || continue
    entry=$(read_file_json "$f")
    BROWSER_AUDIT_HISTORY=$(echo "$BROWSER_AUDIT_HISTORY" | jq --argjson e "$entry" '. + [$e]')
  done
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
  --argjson escape_metrics "$ESCAPE_METRICS_JSON" \
  --argjson has_escape_data "$HAS_ESCAPE_DATA" \
  --argjson browser_specs "$BROWSER_SPECS" \
  --argjson browser_verifications "$BROWSER_VERIFICATIONS" \
  --argjson browser_review_findings "$BROWSER_REVIEW_FINDINGS" \
  --argjson browser_research "$BROWSER_RESEARCH" \
  --argjson browser_architecture "$BROWSER_ARCHITECTURE" \
  --argjson browser_qa_findings "$BROWSER_QA_FINDINGS" \
  --argjson browser_audit_history "$BROWSER_AUDIT_HISTORY" \
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
    cost_warnings: $cost_warnings,
    escape_metrics: $escape_metrics,
    has_escape_data: $has_escape_data,
    browser: {
      specs: $browser_specs,
      verifications: $browser_verifications,
      review_findings: $browser_review_findings,
      research: $browser_research,
      architecture: $browser_architecture,
      qa_findings: $browser_qa_findings,
      audit_history: $browser_audit_history
    }
  }')

# ============================================================================
# STEP 14: Escape </script> sequences in JSON data for safe HTML embedding
# ============================================================================

# Replace </ with <\/ in the JSON to prevent </script> injection
# This is critical: the HTML parser terminates the script block at the first
# </script> regardless of JSON string boundaries (TB-003 mitigation)
DASHBOARD_DATA_ESCAPED=$(echo "$DASHBOARD_DATA" | sed 's/<\//<\\\//g')

# ============================================================================
# STEP 15: Generate HTML
# ============================================================================

OUTPUT_DIR=".correctless/dashboard"
OUTPUT_FILE="$OUTPUT_DIR/index.html"
mkdir -p "$OUTPUT_DIR"

cat > "$OUTPUT_FILE" <<'HTMLEOF'
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
    --sidebar-bg: #f4f5f7;
    --nav-bg: #edf0f3;
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
      --sidebar-bg: #161b22;
      --nav-bg: #21262d;
    }
  }
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body {
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
    background: var(--bg);
    color: var(--fg);
    line-height: 1.6;
  }
  .top-nav {
    display: flex;
    gap: 0;
    background: var(--nav-bg);
    border-bottom: 2px solid var(--border);
    padding: 0 1.5rem;
  }
  .nav-tab {
    padding: 0.75rem 1.5rem;
    cursor: pointer;
    font-weight: 600;
    font-size: 0.95rem;
    border-bottom: 3px solid transparent;
    color: var(--muted);
    background: none;
    border-top: none;
    border-left: none;
    border-right: none;
    font-family: inherit;
  }
  .nav-tab:hover { color: var(--fg); }
  .nav-tab.active { color: var(--accent); border-bottom-color: var(--accent); }
  .view { display: none; }
  .view.active { display: block; }
  .metrics-view {
    max-width: 900px;
    margin: 0 auto;
    padding: 2rem 1.5rem;
  }
  .browser-view {
    display: none;
    height: calc(100vh - 52px);
  }
  .browser-view.active {
    display: flex;
  }
  .sidebar {
    width: 260px;
    min-width: 260px;
    background: var(--sidebar-bg);
    border-right: 1px solid var(--border);
    overflow-y: auto;
    padding: 1rem 0;
  }
  .sidebar-category {
    padding: 0.4rem 1rem;
    font-weight: 700;
    font-size: 0.8rem;
    text-transform: uppercase;
    color: var(--muted);
    letter-spacing: 0.05em;
    cursor: pointer;
    user-select: none;
  }
  .sidebar-category:hover { color: var(--fg); }
  .sidebar-files {
    display: none;
    padding-left: 1rem;
  }
  .sidebar-files.expanded { display: block; }
  .sidebar-file {
    padding: 0.3rem 1rem;
    font-size: 0.85rem;
    cursor: pointer;
    color: var(--fg);
    border-radius: 3px;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .sidebar-file:hover { background: var(--card-bg); }
  .sidebar-file.active { background: var(--accent); color: #fff; }
  .content-area {
    flex: 1;
    overflow-y: auto;
    padding: 2rem;
  }
  .content-area .rendered-content {
    max-width: 800px;
    line-height: 1.7;
  }
  .content-area .rendered-content h1 { font-size: 1.6rem; margin: 1.5rem 0 0.75rem; }
  .content-area .rendered-content h2 { font-size: 1.3rem; margin: 1.25rem 0 0.5rem; border-bottom: 1px solid var(--border); padding-bottom: 0.25rem; }
  .content-area .rendered-content h3 { font-size: 1.1rem; margin: 1rem 0 0.5rem; }
  .content-area .rendered-content p { margin: 0.5rem 0; }
  .content-area .rendered-content code { background: var(--card-bg); padding: 0.15rem 0.4rem; border-radius: 3px; font-size: 0.9em; }
  .content-area .rendered-content pre { background: var(--card-bg); padding: 1rem; border-radius: 6px; overflow-x: auto; margin: 0.75rem 0; }
  .content-area .rendered-content ul, .content-area .rendered-content ol { padding-left: 1.5rem; margin: 0.5rem 0; }
  .content-area .rendered-content table { width: 100%; border-collapse: collapse; margin: 0.75rem 0; font-size: 0.85rem; }
  .content-area .rendered-content th, .content-area .rendered-content td { padding: 0.5rem 0.75rem; text-align: left; border-bottom: 1px solid var(--border); }
  .content-area .rendered-content th { font-weight: 600; color: var(--muted); text-transform: uppercase; font-size: 0.75rem; }
  .qa-findings-table { width: 100%; border-collapse: collapse; font-size: 0.85rem; margin: 1rem 0; }
  .qa-findings-table th, .qa-findings-table td { padding: 0.5rem 0.75rem; text-align: left; border-bottom: 1px solid var(--border); }
  .qa-findings-table th { font-weight: 600; color: var(--muted); text-transform: uppercase; font-size: 0.75rem; }
  .no-artifacts { color: var(--muted); font-style: italic; padding: 2rem; text-align: center; }
  .cdn-notice { background: var(--yellow); color: #000; padding: 0.5rem 1rem; border-radius: 4px; margin-bottom: 1rem; font-size: 0.85rem; display: none; }
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
  footer { margin-top: 3rem; text-align: center; color: var(--muted); font-size: 0.75rem; padding: 1rem; }
</style>
</head>
<body>

<div class="top-nav">
  <button class="nav-tab active" data-view="metrics" onclick="switchView('metrics')">Metrics</button>
  <button class="nav-tab" data-view="artifacts" onclick="switchView('artifacts')">Artifact Browser</button>
</div>

<script type="application/json" id="dashboard-data">
HTMLEOF

# Inject the escaped data JSON
echo "$DASHBOARD_DATA_ESCAPED" >> "$OUTPUT_FILE"

cat >> "$OUTPUT_FILE" <<'HTMLEOF2'
</script>

<!-- marked.js from CDN with SRI hash -->
<script src="https://cdn.jsdelivr.net/npm/marked@14.0.0/marked.min.js"
        integrity="sha384-2FNgXmGeBkCMenDlP/0UI83boC4mInc7i2xHB2K4+NFBJ0kMEPNhPkvMOFqUMEa"
        crossorigin="anonymous"
        onerror="window.__markedFailed=true;document.getElementById('cdn-notice').style.display='block'"></script>
<!-- DOMPurify from CDN with SRI hash -->
<script src="https://cdn.jsdelivr.net/npm/dompurify@3.2.4/dist/purify.min.js"
        integrity="sha384-bKFqMYICShXOF/ViPvz56WgL7GM4Zzx+ABXkEF1oA8hRJ2KVxLK94ZfVN2qHR7B"
        crossorigin="anonymous"
        onerror="window.__purifyFailed=true;document.getElementById('cdn-notice').style.display='block'"></script>

<div id="cdn-notice" class="cdn-notice">Markdown rendering unavailable — viewing raw text. CDN libraries failed to load.</div>

<div id="metrics-view" class="metrics-view view active"></div>

<div id="browser-view" class="browser-view view">
  <div class="sidebar" id="sidebar"></div>
  <div class="content-area" id="content-area">
    <div class="no-artifacts" id="browser-placeholder">Select a file from the sidebar to view its contents.</div>
  </div>
</div>

<script>
(function() {
  var data = JSON.parse(document.getElementById('dashboard-data').textContent);
  var metricsEl = document.getElementById('metrics-view');
  var sidebarEl = document.getElementById('sidebar');
  var contentEl = document.getElementById('content-area');

  // ---- View switching ----
  window.switchView = function(view) {
    document.querySelectorAll('.nav-tab').forEach(function(t) { t.classList.remove('active'); });
    document.querySelector('[data-view="' + view + '"]').classList.add('active');
    document.querySelectorAll('.view').forEach(function(v) { v.classList.remove('active'); });
    document.getElementById(view === 'metrics' ? 'metrics-view' : 'browser-view').classList.add('active');
  };

  // ---- DOM helper ----
  function h(tag, attrs) {
    var children = Array.prototype.slice.call(arguments, 2);
    var el = document.createElement(tag);
    if (attrs) {
      Object.keys(attrs).forEach(function(k) {
        var v = attrs[k];
        if (k === 'style' && typeof v === 'object') { Object.keys(v).forEach(function(sk) { el.style[sk] = v[sk]; }); }
        else if (k === 'className') el.className = v;
        else if (k === 'innerHTML') el.innerHTML = v;
        else if (k === 'onclick') el.onclick = v;
        else el.setAttribute(k, v);
      });
    }
    children.flat().forEach(function(c) {
      if (typeof c === 'string') el.appendChild(document.createTextNode(c));
      else if (c) el.appendChild(c);
    });
    return el;
  }

  // ---- Safe markdown rendering ----
  function renderMarkdown(text) {
    if (window.marked && window.DOMPurify && !window.__markedFailed && !window.__purifyFailed) {
      return DOMPurify.sanitize(marked.parse(text));
    }
    // Fallback: show raw text
    return '<pre>' + text.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;') + '</pre>';
  }

  // ========================================================================
  // METRICS VIEW
  // ========================================================================

  // ---- Project Summary ----
  metricsEl.appendChild(h('h1', null, data.project_name + ' Dashboard'));
  metricsEl.appendChild(h('div', { className: 'subtitle' }, 'Generated ' + new Date().toISOString().slice(0, 10)));

  var verdict = data.total_features + ' features, ' +
    data.total_findings + ' findings caught pre-merge, ' +
    data.antipatterns.length + ' antipatterns catalogued.';
  metricsEl.appendChild(h('div', { className: 'health-verdict' }, verdict));

  var stats = h('div', { className: 'stat-row' });
  [{l:'Features Shipped', v:data.total_features},
   {l:'Findings Caught', v:data.total_findings},
   {l:'Test Count', v:data.test_count},
   {l:'Intensity Floor', v:data.intensity_floor}
  ].forEach(function(s) {
    var st = h('div', { className: 'stat' });
    st.appendChild(h('div', { className: 'stat-label' }, s.l));
    st.appendChild(h('div', { className: 'stat-value' }, String(s.v)));
    stats.appendChild(st);
  });
  metricsEl.appendChild(stats);

  // ---- Quality Trajectory ----
  metricsEl.appendChild(h('h2', null, 'Quality Trajectory'));

  if (data.features.length === 0) {
    metricsEl.appendChild(h('div', { className: 'empty-msg' }, 'No workflow history yet. No data yet.'));
  } else {
    var featureSeverity = {};
    (data.findings || []).forEach(function(f) {
      if (!f.task) return;
      if (!featureSeverity[f.task]) featureSeverity[f.task] = { blocking: 0, nonblocking: 0 };
      if (f.severity === 'BLOCKING') featureSeverity[f.task].blocking++;
      else featureSeverity[f.task].nonblocking++;
    });
    var maxFindings = Math.max.apply(null, data.features.map(function(f) { return f.findings_fixed; }).concat([1]));
    data.features.forEach(function(f) {
      var slug = f.feature.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');
      var sev = featureSeverity[slug] || null;
      var pctBlocking, pctNonblocking;
      if (sev) {
        var total = sev.blocking + sev.nonblocking;
        pctBlocking = total > 0 ? Math.round((sev.blocking / maxFindings) * 100) : 0;
        pctNonblocking = total > 0 ? Math.round((sev.nonblocking / maxFindings) * 100) : 0;
      } else {
        pctBlocking = 0;
        pctNonblocking = f.findings_fixed > 0 ? Math.round((f.findings_fixed / maxFindings) * 100) : 0;
      }
      var container = h('div', { className: 'bar-container' });
      var label = h('div', { className: 'bar-label' });
      label.appendChild(h('span', null, f.feature));
      label.appendChild(h('span', null, f.findings_fixed + ' findings'));
      container.appendChild(label);
      var track = h('div', { className: 'bar-track' });
      if (pctBlocking > 0) track.appendChild(h('div', { className: 'bar-fill bar-blocking', style: { width: pctBlocking + '%' } }));
      if (pctNonblocking > 0) track.appendChild(h('div', { className: 'bar-fill bar-nonblocking', style: { width: pctNonblocking + '%' } }));
      container.appendChild(track);
      metricsEl.appendChild(container);
    });
    if (data.features.length === 1) {
      metricsEl.appendChild(h('div', { className: 'trend-note' }, 'Need more features to show a trend.'));
    }
  }

  // ---- QA Rounds Trend ----
  metricsEl.appendChild(h('h2', null, 'QA Rounds Trend'));
  var featuresWithRounds = data.features.filter(function(f) { return f.qa_rounds > 0; });
  if (featuresWithRounds.length === 0) {
    metricsEl.appendChild(h('div', { className: 'empty-msg' }, 'No QA round data.'));
  } else {
    var maxRounds = Math.max.apply(null, data.features.map(function(f) { return f.qa_rounds; }).concat([1]));
    data.features.forEach(function(f) {
      var container = h('div', { className: 'bar-container' });
      var label = h('div', { className: 'bar-label' });
      label.appendChild(h('span', null, f.feature));
      label.appendChild(h('span', null, f.qa_rounds + ' rounds'));
      container.appendChild(label);
      var track = h('div', { className: 'bar-track' });
      var pct = f.qa_rounds > 0 ? Math.round((f.qa_rounds / maxRounds) * 100) : 0;
      if (pct > 0) track.appendChild(h('div', { className: 'bar-fill bar-qa', style: { width: pct + '%' } }));
      container.appendChild(track);
      metricsEl.appendChild(container);
    });
  }

  // ---- Pipeline Phase Distribution ----
  metricsEl.appendChild(h('h2', null, 'Pipeline Phase Distribution'));
  var phaseTotal = data.qa_count + data.ma_count + data.review_count;
  if (phaseTotal === 0) {
    metricsEl.appendChild(h('div', { className: 'empty-msg' }, 'No findings data yet.'));
  } else {
    var bar = h('div', { className: 'stacked-bar' });
    if (data.qa_count > 0) bar.appendChild(h('div', { className: 'stacked-segment bar-qa', style: { width: Math.round((data.qa_count / phaseTotal) * 100) + '%' } }, 'QA ' + data.qa_count));
    if (data.ma_count > 0) bar.appendChild(h('div', { className: 'stacked-segment bar-ma', style: { width: Math.round((data.ma_count / phaseTotal) * 100) + '%' } }, 'Mini-audit ' + data.ma_count));
    if (data.review_count > 0) bar.appendChild(h('div', { className: 'stacked-segment bar-review', style: { width: Math.round((data.review_count / phaseTotal) * 100) + '%' } }, 'Review ' + data.review_count));
    metricsEl.appendChild(bar);
  }

  // ---- Fix Rate ----
  metricsEl.appendChild(h('h2', null, 'Fix Rate'));
  if (data.findings.length === 0) {
    metricsEl.appendChild(h('div', { className: 'empty-msg' }, 'No findings data.'));
  } else {
    var withStatus = data.findings.filter(function(f) { return f.status; });
    if (withStatus.length === 0) {
      metricsEl.appendChild(h('div', { className: 'empty-msg' }, 'Fix status data not available.'));
    } else {
      var fixedCount = withStatus.filter(function(f) { return f.status === 'fixed'; }).length;
      var totalWithStatus = withStatus.length;
      var fixPct = totalWithStatus > 0 ? Math.round((fixedCount / totalWithStatus) * 100) : 0;
      metricsEl.appendChild(h('div', { className: 'health-verdict' }, fixedCount + '/' + totalWithStatus + ' findings fixed (' + fixPct + '%)'));
      var fixTrack = h('div', { className: 'bar-track' });
      if (fixPct > 0) fixTrack.appendChild(h('div', { className: 'bar-fill bar-qa', style: { width: fixPct + '%' } }));
      metricsEl.appendChild(fixTrack);
    }
  }

  // ---- Antipattern Health ----
  metricsEl.appendChild(h('h2', null, 'Antipattern Health'));
  if (data.antipatterns.length === 0) {
    metricsEl.appendChild(h('div', { className: 'empty-msg' }, 'No antipatterns catalogued yet.'));
  } else {
    data.antipatterns.forEach(function(ap) {
      var item = h('div', { className: 'ap-item' });
      var header = h('div', { className: 'ap-header' });
      header.appendChild(h('span', { className: 'ap-title' }, ap.id + ': ' + ap.title));
      var badgeClass = ap.status === 'resolved' ? 'badge-resolved' : ap.status === 'dormant' ? 'badge-dormant' : 'badge-active';
      header.appendChild(h('span', { className: 'badge ' + badgeClass }, ap.status));
      item.appendChild(header);
      if (ap.frequency) item.appendChild(h('div', { className: 'ap-freq' }, ap.frequency));
      metricsEl.appendChild(item);
    });
  }

  // ---- Intensity Accuracy ----
  metricsEl.appendChild(h('h2', null, 'Intensity Accuracy'));
  if (data.calibration.length === 0) {
    metricsEl.appendChild(h('div', { className: 'empty-msg' }, 'No calibration data.'));
  } else {
    var iOrder = { lite: 0, standard: 1, high: 2, critical: 3 };
    var agreed = 0, raised = 0, lowered = 0;
    data.calibration.forEach(function(c) {
      var rec = iOrder[c.recommended_intensity] !== undefined ? iOrder[c.recommended_intensity] : -1;
      var act = iOrder[c.actual_intensity] !== undefined ? iOrder[c.actual_intensity] : -1;
      if (rec === act) agreed++;
      else if (act > rec) raised++;
      else lowered++;
    });
    metricsEl.appendChild(h('div', { className: 'health-verdict' }, 'Agreed: ' + agreed + ', Raised: ' + raised + ', Lowered: ' + lowered));
  }

  // ---- Override Rate ----
  metricsEl.appendChild(h('h2', null, 'Override Rate'));
  var featuresWithOverrides = data.features.filter(function(f) { return f.overrides > 0; });
  if (data.features.length === 0 || (featuresWithOverrides.length === 0 && data.override_count === 0)) {
    metricsEl.appendChild(h('div', { className: 'empty-msg' }, 'No override data.'));
  } else {
    var totalOverrides = data.features.reduce(function(sum, f) { return sum + f.overrides; }, 0);
    var meanOverrides = data.features.length > 0 ? (totalOverrides / data.features.length).toFixed(1) : '0.0';
    metricsEl.appendChild(h('div', { className: 'trend-note' }, 'Mean: ' + meanOverrides + ' overrides per feature.'));
  }

  // ---- Cost by Phase ----
  metricsEl.appendChild(h('h2', null, 'Cost by Phase'));
  if (data.token_by_skill.length === 0 && !data.has_cost_artifacts) {
    metricsEl.appendChild(h('div', { className: 'empty-msg' }, 'No token data yet.'));
  } else {
    var tokenTable = h('table');
    var tthead = h('thead');
    var the = h('tr');
    ['Skill', 'Total Tokens', 'Calls'].forEach(function(col) { the.appendChild(h('th', null, col)); });
    tthead.appendChild(the);
    tokenTable.appendChild(tthead);
    var ttbody = h('tbody');
    data.token_by_skill.forEach(function(t) {
      var row = h('tr');
      row.appendChild(h('td', null, t.skill));
      row.appendChild(h('td', null, String(t.total_tokens)));
      row.appendChild(h('td', null, String(t.count)));
      ttbody.appendChild(row);
    });
    tokenTable.appendChild(ttbody);
    metricsEl.appendChild(tokenTable);
  }

  // ---- Drift Debt ----
  metricsEl.appendChild(h('h2', null, 'Drift Debt'));
  if (data.drift.items.length === 0) {
    metricsEl.appendChild(h('div', { className: 'empty-msg' }, 'No drift debt items.'));
  } else {
    var driftStats = h('div', { className: 'stat-row' });
    [{l:'Open', v:data.drift.open}, {l:'Resolved', v:data.drift.resolved}].forEach(function(s) {
      var st = h('div', { className: 'stat' });
      st.appendChild(h('div', { className: 'stat-label' }, s.l));
      st.appendChild(h('div', { className: 'stat-value' }, String(s.v)));
      driftStats.appendChild(st);
    });
    metricsEl.appendChild(driftStats);
  }

  // ---- Dev Journal ----
  metricsEl.appendChild(h('h2', null, 'Dev Journal'));
  if (data.journal.length === 0) {
    metricsEl.appendChild(h('div', { className: 'empty-msg' }, 'No dev journal entries yet.'));
  } else {
    var section = h('div', { className: 'journal-section' });
    data.journal.forEach(function(j) {
      var entry = h('div', { className: 'journal-entry' });
      entry.appendChild(h('div', { className: 'journal-date' }, j.date));
      entry.appendChild(h('div', { className: 'journal-title' }, j.title));
      if (j.body) entry.appendChild(h('div', { className: 'journal-body' }, j.body));
      section.appendChild(entry);
    });
    metricsEl.appendChild(section);
  }

  metricsEl.appendChild(h('footer', null, 'Generated by Correctless'));

  // ========================================================================
  // ARTIFACT BROWSER
  // ========================================================================

  var categories = [
    { key: 'specs', label: 'Specs', items: data.browser.specs, type: 'md' },
    { key: 'verifications', label: 'Verifications', items: data.browser.verifications, type: 'md' },
    { key: 'review_findings', label: 'Review Findings', items: data.browser.review_findings, type: 'md' },
    { key: 'research', label: 'Research Briefs', items: data.browser.research, type: 'md' },
    { key: 'architecture', label: 'Architecture', items: data.browser.architecture, type: 'md' },
    { key: 'qa_findings', label: 'QA Findings', items: data.browser.qa_findings, type: 'json' },
    { key: 'audit_history', label: 'Audit History', items: data.browser.audit_history, type: 'md' }
  ];

  var hasAnyArtifacts = false;

  categories.forEach(function(cat) {
    if (!cat.items || cat.items.length === 0) return;
    hasAnyArtifacts = true;

    var catEl = document.createElement('div');
    catEl.className = 'sidebar-category';
    catEl.textContent = cat.label + ' (' + cat.items.length + ')';

    var filesEl = document.createElement('div');
    filesEl.className = 'sidebar-files';

    catEl.onclick = function() {
      filesEl.classList.toggle('expanded');
    };

    cat.items.forEach(function(item) {
      var fileEl = document.createElement('div');
      fileEl.className = 'sidebar-file';
      fileEl.textContent = item.name;
      fileEl.onclick = function(e) {
        e.stopPropagation();
        document.querySelectorAll('.sidebar-file').forEach(function(f) { f.classList.remove('active'); });
        fileEl.classList.add('active');
        showContent(item, cat.type);
      };
      filesEl.appendChild(fileEl);
    });

    sidebarEl.appendChild(catEl);
    sidebarEl.appendChild(filesEl);
  });

  if (!hasAnyArtifacts) {
    sidebarEl.appendChild(h('div', { className: 'no-artifacts' }, 'No artifacts found.'));
    contentEl.innerHTML = '<div class="no-artifacts">No artifacts found in this project.</div>';
  }

  function showContent(item, type) {
    contentEl.innerHTML = '';
    if (type === 'json') {
      // Parse and render as table
      try {
        var jsonData = JSON.parse(item.content);
        var wrapper = h('div', { className: 'rendered-content' });
        wrapper.appendChild(h('h2', null, item.name));
        if (jsonData.findings && Array.isArray(jsonData.findings)) {
          var table = document.createElement('table');
          table.className = 'qa-findings-table';
          var thead = h('thead');
          var hr = h('tr');
          ['ID', 'Severity', 'Description', 'Rule', 'Status'].forEach(function(col) { hr.appendChild(h('th', null, col)); });
          thead.appendChild(hr);
          table.appendChild(thead);
          var tbody = h('tbody');
          jsonData.findings.forEach(function(f) {
            var row = h('tr');
            row.appendChild(h('td', null, f.id || ''));
            var sevTd = h('td');
            var sevClass = (f.severity === 'BLOCKING' || f.severity === 'CRITICAL') ? 'badge-blocking' : 'badge-nonblocking';
            sevTd.appendChild(h('span', { className: 'badge ' + sevClass }, f.severity || ''));
            row.appendChild(sevTd);
            row.appendChild(h('td', null, f.description || ''));
            row.appendChild(h('td', null, f.rule_ref || ''));
            row.appendChild(h('td', null, f.status || ''));
            tbody.appendChild(row);
          });
          table.appendChild(tbody);
          wrapper.appendChild(table);
        } else {
          wrapper.appendChild(h('pre', null, JSON.stringify(jsonData, null, 2)));
        }
        contentEl.appendChild(wrapper);
      } catch (e) {
        contentEl.innerHTML = '<pre>' + item.content.replace(/&/g,'&amp;').replace(/</g,'&lt;') + '</pre>';
      }
    } else {
      // Render markdown
      var wrapper = h('div', { className: 'rendered-content' });
      wrapper.innerHTML = renderMarkdown(item.content);
      contentEl.appendChild(wrapper);
    }
  }

})();
</script>
</body>
</html>
HTMLEOF2

echo "Dashboard generated: .correctless/dashboard/index.html — open in a browser to view"
