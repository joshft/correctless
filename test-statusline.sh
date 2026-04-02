#!/usr/bin/env bash
# Correctless — statusline redesign tests
# Tests R-001 through R-018 from:
#   docs/specs/redesign-statusline-with-grouped-sections-token-counts-dirty-file-count-session-duration-and-richer-workflow-status.md
# Run from repo root: bash test-statusline.sh

set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATUSLINE="$REPO_DIR/hooks/statusline.sh"
TEST_DIR="/tmp/correctless-statusline-test-$$"
PASS=0
FAIL=0

# ---------------------------------------------------------------------------
# Helpers
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

# Regex match (grep -q)
assert_contains() {
  local desc="$1" pattern="$2" actual="$3"
  if printf '%s' "$actual" | grep -q "$pattern"; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (expected output to match /$pattern/, got: $actual)"
    FAIL=$((FAIL + 1))
  fi
}

# Fixed-string match (grep -qF)
assert_contains_str() {
  local desc="$1" needle="$2" actual="$3"
  if printf '%s' "$actual" | grep -qF "$needle"; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (expected output to contain '$needle', got: $actual)"
    FAIL=$((FAIL + 1))
  fi
}

# Absence: fixed-string must NOT appear
assert_not_contains_str() {
  local desc="$1" needle="$2" actual="$3"
  if printf '%s' "$actual" | grep -qF "$needle"; then
    echo "  FAIL: $desc (expected output NOT to contain '$needle', got: $actual)"
    FAIL=$((FAIL + 1))
  else
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  fi
}

# Absence: regex must NOT match
assert_not_contains() {
  local desc="$1" pattern="$2" actual="$3"
  if printf '%s' "$actual" | grep -q "$pattern"; then
    echo "  FAIL: $desc (expected output NOT to match /$pattern/, got: $actual)"
    FAIL=$((FAIL + 1))
  else
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  fi
}

# Strip ANSI color codes
strip_colors() {
  sed 's/\x1b\[[0-9;]*m//g; s/\\x1b\[[0-9;]*m//g'
}

# Run the statusline script with JSON input; returns plain text (colors stripped)
run_sl() {
  local json="$1"
  printf '%s' "$json" | bash "$STATUSLINE" 2>/dev/null | strip_colors
}

# Run the statusline script with JSON input; returns raw output with color codes intact
run_sl_raw() {
  local json="$1"
  printf '%s' "$json" | bash "$STATUSLINE" 2>/dev/null
}

# Build JSON for unit tests pointing at a non-git dir (no workflow state)
# Override individual fields by passing jq filters
unit_json() {
  cat <<'JSON'
{
  "workspace":       {"current_dir": "/tmp"},
  "model":           {"display_name": "Claude 3.5"},
  "output_style":    {"name": "default"},
  "context_window":  {
    "current_usage": {"input_tokens": 10000, "cache_creation_input_tokens": 0, "cache_read_input_tokens": 0},
    "context_window_size": 100000,
    "total_input_tokens":  19700,
    "total_output_tokens": 2100
  },
  "cost": {
    "total_cost_usd":      0.5133767499999999,
    "total_lines_added":   4,
    "total_lines_removed": 0
  },
  "total_duration_ms": 1380000
}
JSON
}

# Modify the unit JSON: set a jq path to a value
# Usage: patch_json '{"x":1}' '.cost.total_cost_usd' 'null'
patch_json() {
  local json="$1" path="$2" value="$3"
  printf '%s' "$json" | jq "$path = $value"
}

# Set up a temp git repo for integration tests.
# Exports TEST_REPO pointing at the temp dir.
setup_test_repo() {
  rm -rf "$TEST_DIR"
  mkdir -p "$TEST_DIR/.claude/artifacts"
  cd "$TEST_DIR" || exit 1
  git init -q
  git -c user.email="t@t.com" -c user.name="T" commit -q --allow-empty -m "init"
  git checkout -q -b main 2>/dev/null || true
}

cleanup() {
  rm -rf "$TEST_DIR"
}

# Compute the workflow state filename for a given branch (matches statusline algorithm)
state_filename() {
  local branch="$1"
  local slug hash
  slug="$(printf '%s' "$branch" | sed 's/[^a-zA-Z0-9]/-/g' | cut -c1-80)"
  hash="$(printf '%s' "$branch" | md5sum | cut -c1-6)"
  echo ".claude/artifacts/workflow-state-${slug}-${hash}.json"
}

# JSON for integration tests pointing at TEST_DIR
integration_json() {
  jq -n --arg dir "$TEST_DIR" '{
    workspace: {current_dir: $dir},
    model: {display_name: "Opus 4.6"},
    output_style: {name: "default"},
    context_window: {
      current_usage: {input_tokens: 10000, cache_creation_input_tokens: 0, cache_read_input_tokens: 0},
      context_window_size: 200000,
      total_input_tokens: 19700,
      total_output_tokens: 2100
    },
    cost: {total_cost_usd: 0.51, total_lines_added: 4, total_lines_removed: 0},
    total_duration_ms: 1380000
  }'
}

trap cleanup EXIT

# ===========================================================================
echo "=== R-001: Cost formatting ==="
# ===========================================================================

# Tests R-001 [unit]: Cost formatted to 2 decimal places; null/0 omitted

echo "--- R-001a: cost=0.5133... formatted to \$0.51 ---"
json_r001=$(unit_json)
out=$(run_sl "$json_r001")
assert_contains_str "R-001a: output contains \$0.51" '$0.51' "$out"
assert_not_contains_str "R-001a: output does NOT contain long decimal" '0.5133' "$out"

echo "--- R-001b: cost=null → cost element omitted ---"
json_r001b=$(patch_json "$(unit_json)" '.cost.total_cost_usd' 'null')
out=$(run_sl "$json_r001b")
assert_not_contains "R-001b: output does NOT contain dollar sign for null cost" '\$' "$out"

echo "--- R-001c: cost=0 → cost element omitted ---"
json_r001c=$(patch_json "$(unit_json)" '.cost.total_cost_usd' '0')
out=$(run_sl "$json_r001c")
assert_not_contains "R-001c: output does NOT contain dollar sign for zero cost" '\$' "$out"

echo "--- R-001d (QA-002): cost=0.0 → cost element omitted ---"
json_r001d=$(patch_json "$(unit_json)" '.cost.total_cost_usd' '0.0')
out=$(run_sl "$json_r001d")
assert_not_contains "R-001d: output does NOT contain dollar sign for 0.0 cost" '\$' "$out"

# ===========================================================================
echo ""
echo "=== R-002: Token count formatting ==="
# ===========================================================================

# Tests R-002 [unit]: integer <1000, Nk for 1000-999999, NM for 1000000+

echo "--- R-002a: input tokens < 1000 shown as integer ---"
json_r002a=$(unit_json | jq '.context_window.total_input_tokens = 847 | .context_window.total_output_tokens = 312')
out=$(run_sl "$json_r002a")
assert_contains_str "R-002a: 847 input shown as integer" '847' "$out"

echo "--- R-002b: input tokens 19700 shown as 19.7k ---"
json_r002b=$(unit_json)
out=$(run_sl "$json_r002b")
assert_contains_str "R-002b: 19700 input shown as 19.7k" '19.7k' "$out"

echo "--- R-002c: output tokens 2100 shown as 2.1k ---"
out=$(run_sl "$(unit_json)")
assert_contains_str "R-002c: 2100 output shown as 2.1k" '2.1k' "$out"

echo "--- R-002d: input tokens 1200000 shown as 1.2M ---"
json_r002d=$(patch_json "$(unit_json)" '.context_window.total_input_tokens' '1200000')
out=$(run_sl "$json_r002d")
assert_contains_str "R-002d: 1200000 shown as 1.2M" '1.2M' "$out"

echo "--- R-002e: token format includes (in:out) label ---"
out=$(run_sl "$(unit_json)")
assert_contains_str "R-002e: output contains (in:out)" '(in:out)' "$out"

echo "--- R-002h: boundary: 999 tokens shown as integer 999 (not 1.0k) ---"
json_r002h=$(unit_json | jq '.context_window.total_input_tokens = 999 | .context_window.total_output_tokens = 100')
out=$(run_sl "$json_r002h")
assert_contains_str "R-002h: 999 → integer 999" '999' "$out"
assert_not_contains_str "R-002h: 999 → not shown as k" '1.0k' "$out"

echo "--- R-002i: boundary: 1000 tokens shown as 1.0k ---"
json_r002i=$(unit_json | jq '.context_window.total_input_tokens = 1000 | .context_window.total_output_tokens = 100')
out=$(run_sl "$json_r002i")
assert_contains_str "R-002i: 1000 → 1.0k" '1.0k' "$out"

echo "--- R-002j: boundary: 999999 tokens shown as 999.9k (not 1.0M) ---"
json_r002j=$(unit_json | jq '.context_window.total_input_tokens = 999999 | .context_window.total_output_tokens = 100')
out=$(run_sl "$json_r002j")
assert_contains_str "R-002j: 999999 → 999.9k" '999.9k' "$out"
assert_not_contains_str "R-002j: 999999 → not shown as M" '1.0M' "$out"

echo "--- R-002k: boundary: 1000000 tokens shown as 1.0M ---"
json_r002k=$(unit_json | jq '.context_window.total_input_tokens = 1000000 | .context_window.total_output_tokens = 100')
out=$(run_sl "$json_r002k")
assert_contains_str "R-002k: 1000000 → 1.0M" '1.0M' "$out"

echo "--- R-002l: full token format: in : out (in:out) in correct order ---"
out=$(run_sl "$(unit_json)")
assert_contains_str "R-002l: full token format 19.7k : 2.1k (in:out)" '19.7k : 2.1k (in:out)' "$out"

echo "--- R-002f: null input tokens → token element omitted ---"
json_r002f=$(patch_json "$(unit_json)" '.context_window.total_input_tokens' 'null')
out=$(run_sl "$json_r002f")
assert_not_contains_str "R-002f: null tokens → no (in:out)" '(in:out)' "$out"

echo "--- R-002g: null output tokens → token element omitted ---"
json_r002g=$(patch_json "$(unit_json)" '.context_window.total_output_tokens' 'null')
out=$(run_sl "$json_r002g")
assert_not_contains_str "R-002g: null output tokens → no (in:out)" '(in:out)' "$out"

# ===========================================================================
echo ""
echo "=== R-003: Context window percentage color coding ==="
# ===========================================================================

# Tests R-003 [unit]: green <40%, yellow 40-69%, red 70%+

echo "--- R-003a: 10% context usage → green color code ---"
# 10000/100000 = 10%
json_r003a=$(printf '%s' "$(unit_json)" | jq '
  .context_window.current_usage = {input_tokens: 10000, cache_creation_input_tokens: 0, cache_read_input_tokens: 0}
  | .context_window.context_window_size = 100000
')
raw=$(run_sl_raw "$json_r003a")
# Green: \x1b[38;5;42m or \033[38;5;42m or similar
# We test that output contains a percentage AND a green-variant escape code
stripped=$(printf '%s' "$raw" | strip_colors)
assert_contains "R-003a: 10% context → percentage shown" '[0-9]*%' "$stripped"
# Raw output must contain the green ANSI escape code specifically
assert_contains "R-003a: 10% context → green ANSI code" $'\x1b\[38;5;42m' "$raw"

echo "--- R-003b: 50% context usage → yellow color code ---"
json_r003b=$(printf '%s' "$(unit_json)" | jq '
  .context_window.current_usage = {input_tokens: 50000, cache_creation_input_tokens: 0, cache_read_input_tokens: 0}
  | .context_window.context_window_size = 100000
')
raw=$(run_sl_raw "$json_r003b")
stripped=$(printf '%s' "$raw" | strip_colors)
assert_contains "R-003b: 50% context → percentage shown" '50%' "$stripped"
# Yellow escape code: \x1b[38;5;226m
assert_contains "R-003b: 50% context → yellow ANSI code" $'\x1b\[38;5;226m' "$raw"

echo "--- R-003c: 80% context usage → red color code ---"
json_r003c=$(printf '%s' "$(unit_json)" | jq '
  .context_window.current_usage = {input_tokens: 80000, cache_creation_input_tokens: 0, cache_read_input_tokens: 0}
  | .context_window.context_window_size = 100000
')
raw=$(run_sl_raw "$json_r003c")
stripped=$(printf '%s' "$raw" | strip_colors)
assert_contains "R-003c: 80% context → percentage shown" '80%' "$stripped"
# Red escape code: \033[31m = \x1b[31m
assert_contains "R-003c: 80% context → red ANSI code" $'\x1b\[31m' "$raw"

echo "--- R-003e: boundary 39% → green (last green value) ---"
json_r003e=$(printf '%s' "$(unit_json)" | jq '
  .context_window.current_usage = {input_tokens: 39000, cache_creation_input_tokens: 0, cache_read_input_tokens: 0}
  | .context_window.context_window_size = 100000
')
raw=$(run_sl_raw "$json_r003e")
assert_contains "R-003e: 39% context → green ANSI code" $'\x1b\[38;5;42m' "$raw"

echo "--- R-003f: boundary 40% → yellow (first yellow value) ---"
json_r003f=$(printf '%s' "$(unit_json)" | jq '
  .context_window.current_usage = {input_tokens: 40000, cache_creation_input_tokens: 0, cache_read_input_tokens: 0}
  | .context_window.context_window_size = 100000
')
raw=$(run_sl_raw "$json_r003f")
assert_contains "R-003f: 40% context → yellow ANSI code" $'\x1b\[38;5;226m' "$raw"

echo "--- R-003g: boundary 69% → yellow (last yellow value) ---"
json_r003g=$(printf '%s' "$(unit_json)" | jq '
  .context_window.current_usage = {input_tokens: 69000, cache_creation_input_tokens: 0, cache_read_input_tokens: 0}
  | .context_window.context_window_size = 100000
')
raw=$(run_sl_raw "$json_r003g")
assert_contains "R-003g: 69% context → yellow ANSI code" $'\x1b\[38;5;226m' "$raw"

echo "--- R-003h: boundary 70% → red (first red value) ---"
json_r003h=$(printf '%s' "$(unit_json)" | jq '
  .context_window.current_usage = {input_tokens: 70000, cache_creation_input_tokens: 0, cache_read_input_tokens: 0}
  | .context_window.context_window_size = 100000
')
raw=$(run_sl_raw "$json_r003h")
assert_contains "R-003h: 70% context → red ANSI code" $'\x1b\[31m' "$raw"

echo "--- R-003d: null usage → no context percentage shown ---"
json_r003d=$(patch_json "$(unit_json)" '.context_window.current_usage' 'null')
out=$(run_sl "$json_r003d")
assert_not_contains "R-003d: null usage → no % in output" '%' "$out"

# ===========================================================================
echo ""
echo "=== R-004: Dirty file count ==="
# ===========================================================================

# Tests R-004 [integration]: N dirty after branch; 0 or unavailable → omit

echo "--- R-004a: uncommitted file → N dirty shown ---"
setup_test_repo
echo "untracked" > "$TEST_DIR/dirty.txt"
out=$(run_sl "$(integration_json)")
assert_contains "R-004a: dirty file count shown" '[0-9][0-9]* dirty' "$out"

echo "--- R-004b: clean repo → no dirty element ---"
setup_test_repo
out=$(run_sl "$(integration_json)")
assert_not_contains "R-004b: clean repo → no 'dirty'" 'dirty' "$out"

echo "--- R-004c: non-git directory → no dirty element ---"
SAVED_TEST_DIR="$TEST_DIR"
TEST_DIR="/tmp/no-git-$$"
mkdir -p "$TEST_DIR"
out=$(run_sl "$(integration_json)")
assert_not_contains "R-004c: non-git dir → no 'dirty'" 'dirty' "$out"
rm -rf "$TEST_DIR"
TEST_DIR="$SAVED_TEST_DIR"

# ===========================================================================
echo ""
echo "=== R-005: Session duration formatting ==="
# ===========================================================================

# Tests R-005 [unit]: Nm under 60min, Nh Nm 60min+; null/0 omitted

echo "--- R-005a: 1380000ms = 23min → shows 23m ---"
out=$(run_sl "$(unit_json)")
assert_contains_str "R-005a: 1380000ms shown as 23m" '23m' "$out"

echo "--- R-005b: 3720000ms = 62min → shows 1h 2m ---"
json_r005b=$(patch_json "$(unit_json)" '.total_duration_ms' '3720000')
out=$(run_sl "$json_r005b")
assert_contains_str "R-005b: 3720000ms shown as 1h 2m" '1h 2m' "$out"

echo "--- R-005c: null duration → no duration element ---"
json_r005c=$(patch_json "$(unit_json)" '.total_duration_ms' 'null')
out=$(run_sl "$json_r005c")
# Duration format is Nm or Nh Nm; check no standalone minutes pattern near session stats
assert_not_contains "R-005c: null duration → no Nm duration element" '[0-9][0-9]*m ' "$out"

echo "--- R-005d: zero duration → no duration element ---"
json_r005d=$(patch_json "$(unit_json)" '.total_duration_ms' '0')
out=$(run_sl "$json_r005d")
assert_not_contains "R-005d: zero duration → no Nm duration element" '[0-9][0-9]*m' "$out"
assert_not_contains_str "R-005d: zero duration → no 0m literal" '0m' "$out"

# ===========================================================================
echo ""
echo "=== R-006: Workflow section format ==="
# ===========================================================================

# Tests R-006 [integration]: ⚙ {task} · {PHASE} R{n} · {time}

echo "--- R-006a: active workflow with QA rounds → full format ---"
setup_test_repo
state_file="$(state_filename "main")"
cat > "$TEST_DIR/$state_file" <<SFJSON
{
  "phase": "tdd-qa",
  "task": "add-auth",
  "qa_rounds": 2,
  "phase_entered_at": "$(date -u -d '5 minutes ago' '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date -u -v-5M '+%Y-%m-%dT%H:%M:%SZ')"
}
SFJSON
out=$(run_sl "$(integration_json)")
assert_contains_str "R-006a: workflow icon ⚙ present" '⚙' "$out"
assert_contains_str "R-006a: task name present" 'add-auth' "$out"
assert_contains "R-006a: QA rounds shown as R2" 'R2' "$out"
assert_contains_str "R-006a (QA-006): middot separator present" '· ' "$out"

echo "--- R-006b: QA rounds = 0 → no Rn in output ---"
setup_test_repo
state_file="$(state_filename "main")"
cat > "$TEST_DIR/$state_file" <<SFJSON
{
  "phase": "tdd-impl",
  "task": "add-auth",
  "qa_rounds": 0,
  "phase_entered_at": "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
}
SFJSON
out=$(run_sl "$(integration_json)")
assert_contains_str "R-006b: workflow section present" '⚙' "$out"
assert_not_contains "R-006b: qa_rounds=0 → no R0 in output" 'R0' "$out"

echo "--- R-006c: no workflow state → no ⚙ in output ---"
setup_test_repo
out=$(run_sl "$(integration_json)")
assert_not_contains_str "R-006c: no workflow → no ⚙" '⚙' "$out"

# ===========================================================================
echo ""
echo "=== R-007: Workflow phase color coding ==="
# ===========================================================================

# Tests R-007 [unit]: cyan=spec/review/model, red=tdd-tests, green=tdd-impl,
#                     yellow=tdd-qa/verify, gray=done/verified/documented, orange=audit

echo "--- R-007a: spec phase → cyan color ---"
setup_test_repo
state_file="$(state_filename "main")"
cat > "$TEST_DIR/$state_file" <<SFJSON
{"phase": "spec", "task": "my-task", "qa_rounds": 0}
SFJSON
raw=$(run_sl_raw "$(integration_json)")
# Cyan: \x1b[38;5;81m
assert_contains "R-007a: spec phase → cyan ANSI code" $'\x1b\[38;5;81m' "$raw"

echo "--- R-007b: tdd-tests phase → red color ---"
setup_test_repo
cat > "$TEST_DIR/$state_file" <<SFJSON
{"phase": "tdd-tests", "task": "my-task", "qa_rounds": 0}
SFJSON
raw=$(run_sl_raw "$(integration_json)")
assert_contains "R-007b: tdd-tests → red ANSI code" $'\x1b\[31m' "$raw"

echo "--- R-007c: tdd-impl phase → green color ---"
setup_test_repo
cat > "$TEST_DIR/$state_file" <<SFJSON
{"phase": "tdd-impl", "task": "my-task", "qa_rounds": 0}
SFJSON
raw=$(run_sl_raw "$(integration_json)")
# Green: \x1b[38;5;42m
assert_contains "R-007c: tdd-impl → green ANSI code" $'\x1b\[38;5;42m' "$raw"

echo "--- R-007d: tdd-qa phase → yellow color ---"
setup_test_repo
cat > "$TEST_DIR/$state_file" <<SFJSON
{"phase": "tdd-qa", "task": "my-task", "qa_rounds": 1}
SFJSON
raw=$(run_sl_raw "$(integration_json)")
# Yellow: \x1b[38;5;226m
assert_contains "R-007d: tdd-qa → yellow ANSI code" $'\x1b\[38;5;226m' "$raw"

echo "--- R-007e: done phase → gray color ---"
setup_test_repo
cat > "$TEST_DIR/$state_file" <<SFJSON
{"phase": "done", "task": "my-task", "qa_rounds": 0}
SFJSON
raw=$(run_sl_raw "$(integration_json)")
# Gray: \033[2m = \x1b[2m
assert_contains "R-007e: done → gray ANSI code" $'\x1b\[2m' "$raw"

echo "--- R-007f: audit phase → orange color ---"
setup_test_repo
cat > "$TEST_DIR/$state_file" <<SFJSON
{"phase": "audit", "task": "my-task", "qa_rounds": 0}
SFJSON
raw=$(run_sl_raw "$(integration_json)")
# Orange: \033[38;5;214m = \x1b[38;5;214m
assert_contains "R-007f: audit → orange ANSI code" $'\x1b\[38;5;214m' "$raw"

echo "--- R-007g (QA-005): review phase → cyan color ---"
setup_test_repo
cat > "$TEST_DIR/$state_file" <<SFJSON
{"phase": "review", "task": "my-task", "qa_rounds": 0}
SFJSON
raw=$(run_sl_raw "$(integration_json)")
assert_contains "R-007g: review → cyan ANSI code" $'\x1b\[38;5;81m' "$raw"

echo "--- R-007h (QA-005): review-spec phase → cyan color ---"
setup_test_repo
cat > "$TEST_DIR/$state_file" <<SFJSON
{"phase": "review-spec", "task": "my-task", "qa_rounds": 0}
SFJSON
raw=$(run_sl_raw "$(integration_json)")
assert_contains "R-007h: review-spec → cyan ANSI code" $'\x1b\[38;5;81m' "$raw"

echo "--- R-007i (QA-005): model phase → cyan color ---"
setup_test_repo
cat > "$TEST_DIR/$state_file" <<SFJSON
{"phase": "model", "task": "my-task", "qa_rounds": 0}
SFJSON
raw=$(run_sl_raw "$(integration_json)")
assert_contains "R-007i: model → cyan ANSI code" $'\x1b\[38;5;81m' "$raw"

echo "--- R-007j (QA-005): tdd-verify phase → yellow color ---"
setup_test_repo
cat > "$TEST_DIR/$state_file" <<SFJSON
{"phase": "tdd-verify", "task": "my-task", "qa_rounds": 0}
SFJSON
raw=$(run_sl_raw "$(integration_json)")
assert_contains "R-007j: tdd-verify → yellow ANSI code" $'\x1b\[38;5;226m' "$raw"

echo "--- R-007k (QA-005): verified phase → gray color ---"
setup_test_repo
cat > "$TEST_DIR/$state_file" <<SFJSON
{"phase": "verified", "task": "my-task", "qa_rounds": 0}
SFJSON
raw=$(run_sl_raw "$(integration_json)")
assert_contains "R-007k: verified → gray ANSI code" $'\x1b\[2m' "$raw"

echo "--- R-007l (QA-005): documented phase → gray color ---"
setup_test_repo
cat > "$TEST_DIR/$state_file" <<SFJSON
{"phase": "documented", "task": "my-task", "qa_rounds": 0}
SFJSON
raw=$(run_sl_raw "$(integration_json)")
assert_contains "R-007l: documented → gray ANSI code" $'\x1b\[2m' "$raw"

# ===========================================================================
echo ""
echo "=== R-008: Workflow time-in-phase ==="
# ===========================================================================

# Tests R-008 [integration]: time shown from phase_entered_at; missing → omit

echo "--- R-008a: phase_entered_at set → time shown in workflow section ---"
setup_test_repo
state_file="$(state_filename "main")"
# Set phase_entered_at to 7 minutes ago
entered_at="$(date -u -d '7 minutes ago' '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date -u -v-7M '+%Y-%m-%dT%H:%M:%SZ')"
cat > "$TEST_DIR/$state_file" <<SFJSON
{"phase": "tdd-impl", "task": "my-task", "qa_rounds": 0, "phase_entered_at": "$entered_at"}
SFJSON
out=$(run_sl "$(integration_json)")
# Workflow section should have time like "7m" or close
assert_contains "R-008a: phase_entered_at → Nm time in workflow" '⚙.*[0-9][0-9]*m' "$out"

echo "--- R-008d (QA-003): phase_entered_at 30 seconds ago → no time element (sub-minute) ---"
setup_test_repo
state_file="$(state_filename "main")"
entered_at="$(date -u -d '30 seconds ago' '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date -u -v-30S '+%Y-%m-%dT%H:%M:%SZ')"
cat > "$TEST_DIR/$state_file" <<SFJSON
{"phase": "tdd-impl", "task": "my-task", "qa_rounds": 0, "phase_entered_at": "$entered_at"}
SFJSON
out=$(run_sl "$(integration_json)")
assert_contains_str "R-008d: workflow present with sub-minute phase" '⚙' "$out"
assert_not_contains "R-008d: no time element for sub-minute phase" '· [0-9][0-9]*[mh]' "$out"

echo "--- R-008b: phase_entered_at missing → no time element in workflow ---"
setup_test_repo
cat > "$TEST_DIR/$state_file" <<SFJSON
{"phase": "tdd-impl", "task": "my-task", "qa_rounds": 0}
SFJSON
out=$(run_sl "$(integration_json)")
# Workflow should still be present (⚙) but time element after the last · should be absent
assert_contains_str "R-008b: workflow present without time" '⚙' "$out"
# The format without time is "⚙ task · PHASE" with no trailing "· Nm"
# Check there's no "· [0-9]m" or "· [0-9]h" pattern
assert_not_contains "R-008b: no time element without phase_entered_at" '· [0-9][0-9]*[mh]' "$out"

echo "--- R-008c: phase_entered_at invalid/garbage → no crash, no time element ---"
setup_test_repo
cat > "$TEST_DIR/$state_file" <<SFJSON
{"phase": "tdd-impl", "task": "my-task", "qa_rounds": 0, "phase_entered_at": "INVALID-NOT-A-DATE"}
SFJSON
r008c_exit=0
r008c_out=$(printf '%s' "$(integration_json)" | bash "$STATUSLINE" 2>/dev/null) || r008c_exit=$?
assert_eq "R-008c: script exits 0 with invalid phase_entered_at" "0" "$r008c_exit"
out=$(printf '%s' "$r008c_out" | strip_colors)
assert_not_contains "R-008c: no time element for invalid timestamp" '· [0-9][0-9]*[mh]' "$out"

# ===========================================================================
echo ""
echo "=== R-009: Task name truncation ==="
# ===========================================================================

# Tests R-009 [unit]: task name truncated to 20 chars; longer → append …

echo "--- R-009a: task name > 20 chars → truncated with … ---"
setup_test_repo
state_file="$(state_filename "main")"
cat > "$TEST_DIR/$state_file" <<SFJSON
{"phase": "tdd-impl", "task": "implement-oauth2-with-pkce-extension", "qa_rounds": 0}
SFJSON
out=$(run_sl "$(integration_json)")
# "implement-oauth2-with-pkce-extension" is 36 chars; truncated to 20 = "implement-oauth2-wit" + "…"
assert_contains_str "R-009a: long task name ends with ellipsis" '…' "$out"
# Should NOT contain the full name
assert_not_contains_str "R-009a: full name not in output" 'implement-oauth2-with-pkce-extension' "$out"

echo "--- R-009c (QA-008): task name with CJK characters → truncation works correctly ---"
setup_test_repo
state_file="$(state_filename "main")"
cat > "$TEST_DIR/$state_file" <<SFJSON
{"phase": "tdd-impl", "task": "implement-日本語-feature-with-extra", "qa_rounds": 0}
SFJSON
out=$(run_sl "$(integration_json)")
assert_contains_str "R-009c: CJK task ends with ellipsis" '…' "$out"
assert_not_contains_str "R-009c: full CJK name not in output" 'implement-日本語-feature-with-extra' "$out"

echo "--- R-009b: task name <= 20 chars → no truncation ---"
setup_test_repo
cat > "$TEST_DIR/$state_file" <<SFJSON
{"phase": "tdd-impl", "task": "add-auth", "qa_rounds": 0}
SFJSON
out=$(run_sl "$(integration_json)")
assert_contains_str "R-009b: short task name shown in full" 'add-auth' "$out"
assert_not_contains_str "R-009b: no ellipsis for short task" '…' "$out"

# ===========================================================================
echo ""
echo "=== R-010: Section separators │ ==="
# ===========================================================================

# Tests R-010 [integration]: sections separated by ' │ '; empty section omitted with its separator

echo "--- R-010a: multiple sections present → output contains ' │ ' separator ---"
setup_test_repo
state_file="$(state_filename "main")"
cat > "$TEST_DIR/$state_file" <<SFJSON
{"phase": "tdd-impl", "task": "add-auth", "qa_rounds": 0}
SFJSON
out=$(run_sl "$(integration_json)")
assert_contains_str "R-010a: sections separated by ' │ '" ' │ ' "$out"

echo "--- R-010b: session stats all empty → no double separator in output ---"
setup_test_repo
# No workflow state, no cost, no lines, no duration
json_r010b=$(jq -n --arg dir "$TEST_DIR" '{
  workspace: {current_dir: $dir},
  model: {display_name: "Claude 3.5"},
  output_style: {name: "default"},
  context_window: {
    current_usage: null,
    context_window_size: null,
    total_input_tokens: null,
    total_output_tokens: null
  },
  cost: {total_cost_usd: null, total_lines_added: null, total_lines_removed: null},
  total_duration_ms: null
}')
out=$(run_sl "$json_r010b")
# Adjacent separators would indicate an empty section left in
assert_not_contains_str "R-010b: no double separator for empty section" ' │  │ ' "$out"

# ===========================================================================
echo ""
echo "=== R-011: Override warning ==="
# ===========================================================================

# Tests R-011 [integration]: ⚠override({N}) when override active

echo "--- R-011a: override_remaining > 0 → ⚠override(N) in workflow section ---"
setup_test_repo
state_file="$(state_filename "main")"
cat > "$TEST_DIR/$state_file" <<SFJSON
{"phase": "tdd-impl", "task": "add-auth", "qa_rounds": 0, "override_remaining": 3}
SFJSON
out=$(run_sl "$(integration_json)")
assert_contains_str "R-011a: override warning shown" '⚠override(3)' "$out"

echo "--- R-011b: no override_remaining → no ⚠override ---"
setup_test_repo
cat > "$TEST_DIR/$state_file" <<SFJSON
{"phase": "tdd-impl", "task": "add-auth", "qa_rounds": 0}
SFJSON
out=$(run_sl "$(integration_json)")
assert_not_contains_str "R-011b: no override → no ⚠override" '⚠override' "$out"

# ===========================================================================
echo ""
echo "=== R-012: Spec-update warning ==="
# ===========================================================================

# Tests R-012 [integration]: ⚠spec×{N} when spec_updates >= 2

echo "--- R-012a: spec_updates=3 → ⚠spec×3 in workflow section ---"
setup_test_repo
state_file="$(state_filename "main")"
cat > "$TEST_DIR/$state_file" <<SFJSON
{"phase": "tdd-impl", "task": "add-auth", "qa_rounds": 0, "spec_updates": 3}
SFJSON
out=$(run_sl "$(integration_json)")
assert_contains_str "R-012a: spec updates >= 2 → ⚠spec×3" '⚠spec×3' "$out"

echo "--- R-012b: spec_updates=1 → no ⚠spec× ---"
setup_test_repo
cat > "$TEST_DIR/$state_file" <<SFJSON
{"phase": "tdd-impl", "task": "add-auth", "qa_rounds": 0, "spec_updates": 1}
SFJSON
out=$(run_sl "$(integration_json)")
assert_not_contains_str "R-012b: spec_updates=1 → no ⚠spec×" '⚠spec×' "$out"

echo "--- R-012c: spec_updates=2 → ⚠spec×2 shown (boundary case) ---"
setup_test_repo
cat > "$TEST_DIR/$state_file" <<SFJSON
{"phase": "tdd-impl", "task": "add-auth", "qa_rounds": 0, "spec_updates": 2}
SFJSON
out=$(run_sl "$(integration_json)")
assert_contains_str "R-012c: spec_updates=2 (boundary) → ⚠spec×2" '⚠spec×2' "$out"

# ===========================================================================
echo ""
echo "=== R-013: Sync to distributions ==="
# ===========================================================================

# Tests R-013 [integration]: hooks/statusline.sh is identical in both distributions

echo "--- R-013a: hooks/statusline.sh matches correctless-lite/hooks/statusline.sh ---"
if diff -q "$REPO_DIR/hooks/statusline.sh" "$REPO_DIR/correctless-lite/hooks/statusline.sh" >/dev/null 2>&1; then
  assert_eq "R-013a: source matches correctless-lite distribution" "match" "match"
else
  assert_eq "R-013a: source matches correctless-lite distribution" "match" "diff"
fi

echo "--- R-013b: hooks/statusline.sh matches correctless-full/hooks/statusline.sh ---"
if diff -q "$REPO_DIR/hooks/statusline.sh" "$REPO_DIR/correctless-full/hooks/statusline.sh" >/dev/null 2>&1; then
  assert_eq "R-013b: source matches correctless-full distribution" "match" "match"
else
  assert_eq "R-013b: source matches correctless-full distribution" "match" "diff"
fi

# ===========================================================================
echo ""
echo "=== R-014: Lines delta formatting ==="
# ===========================================================================

# Tests R-014 [unit]: +N/-N shown; both 0 or null → omit

echo "--- R-014a: lines added=4, removed=0 → +4/-0 shown ---"
out=$(run_sl "$(unit_json)")
assert_contains_str "R-014a: lines delta +4/-0 shown" '+4/-0' "$out"

echo "--- R-014b: lines added=3, removed=5 → +3/-5 shown ---"
json_r014b=$(printf '%s' "$(unit_json)" | jq '.cost.total_lines_added = 3 | .cost.total_lines_removed = 5')
out=$(run_sl "$json_r014b")
assert_contains_str "R-014b: lines delta +3/-5 shown" '+3/-5' "$out"

echo "--- R-014c: lines added=0, removed=0 → no delta element ---"
json_r014c=$(printf '%s' "$(unit_json)" | jq '.cost.total_lines_added = 0 | .cost.total_lines_removed = 0')
out=$(run_sl "$json_r014c")
assert_not_contains "R-014c: both zero → no +N/-N" '+[0-9]' "$out"

echo "--- R-014d: null lines → no delta element ---"
json_r014d=$(printf '%s' "$(unit_json)" | jq '.cost.total_lines_added = null | .cost.total_lines_removed = null')
out=$(run_sl "$json_r014d")
assert_not_contains "R-014d: null lines → no +N/-N" '+[0-9]' "$out"

# ===========================================================================
echo ""
echo "=== R-015: Setup registers statusLine in settings.json ==="
# ===========================================================================

# Tests R-015 [integration]: statusLine.command registered in .claude/settings.json

SETUP_TEST_DIR="/tmp/correctless-setup-test-$$"

setup_install_project() {
  rm -rf "$SETUP_TEST_DIR"
  mkdir -p "$SETUP_TEST_DIR"
  cd "$SETUP_TEST_DIR" || exit 1
  git init -q
  git -c user.email="t@t.com" -c user.name="T" commit -q --allow-empty -m "init"
  git checkout -q -b main 2>/dev/null || true
  mkdir -p .claude/skills/workflow
  rsync -a --exclude='.git' "$REPO_DIR/" .claude/skills/workflow/
}

cleanup_setup() {
  rm -rf "$SETUP_TEST_DIR"
}

echo "--- R-015a: no settings.json → fresh template includes statusLine ---"
setup_install_project
.claude/skills/workflow/setup >/dev/null 2>&1 || true
settings_content="$(cat "$SETUP_TEST_DIR/.claude/settings.json" 2>/dev/null || echo '{}')"
assert_contains_str "R-015a: fresh settings.json has statusLine key" 'statusLine' "$settings_content"
assert_contains_str "R-015a: statusLine.command points to .claude/hooks/statusline.sh" '.claude/hooks/statusline.sh' "$settings_content"
cleanup_setup

echo "--- R-015b: settings.json exists without statusLine → jq merge adds it ---"
setup_install_project
mkdir -p .claude
cat > .claude/settings.json <<'EXISTING'
{
  "hooks": {
    "PreToolUse": [{"matcher": "Edit", "hooks": [{"type": "command", "command": ".claude/hooks/workflow-gate.sh"}]}]
  }
}
EXISTING
.claude/skills/workflow/setup >/dev/null 2>&1 || true
settings_file="$SETUP_TEST_DIR/.claude/settings.json"
settings_content="$(cat "$settings_file" 2>/dev/null || echo '{}')"
assert_contains_str "R-015b: statusLine added to existing settings" 'statusLine' "$settings_content"
assert_contains_str "R-015b: existing hook preserved" 'workflow-gate' "$settings_content"
# QA-004: Verify no duplicate hook entries after merge
gate_count=$(grep -c 'workflow-gate' "$settings_file")
assert_eq "R-015b (QA-004): exactly 1 workflow-gate entry" "1" "$gate_count"
cleanup_setup

echo "--- R-015c: settings.json exists with different statusLine → overwritten ---"
setup_install_project
mkdir -p .claude
cat > .claude/settings.json <<'EXISTING'
{
  "hooks": {
    "PreToolUse": [{"matcher": "Edit", "hooks": [{"type": "command", "command": ".claude/hooks/workflow-gate.sh"}]}]
  },
  "statusLine": {
    "command": "/usr/local/bin/some-other-statusline"
  }
}
EXISTING
.claude/skills/workflow/setup >/dev/null 2>&1 || true
settings_file="$SETUP_TEST_DIR/.claude/settings.json"
settings_content="$(cat "$settings_file" 2>/dev/null || echo '{}')"
assert_contains_str "R-015c: statusLine command is now Correctless statusline" '.claude/hooks/statusline.sh' "$settings_content"
assert_not_contains_str "R-015c: old statusLine command gone" '/usr/local/bin/some-other-statusline' "$settings_content"
# QA-004: Verify no duplicate hook entries after overwrite
gate_count=$(grep -c 'workflow-gate' "$settings_file")
assert_eq "R-015c (QA-004): exactly 1 workflow-gate entry" "1" "$gate_count"
cleanup_setup

echo "--- R-015d (QA-001): running setup twice does not duplicate hook entries ---"
setup_install_project
.claude/skills/workflow/setup >/dev/null 2>&1 || true
.claude/skills/workflow/setup >/dev/null 2>&1 || true
settings_file="$SETUP_TEST_DIR/.claude/settings.json"
gate_count=$(grep -c 'workflow-gate' "$settings_file")
audit_count=$(grep -c 'audit-trail' "$settings_file")
advance_count=$(grep -c 'workflow-advance' "$settings_file")
assert_eq "R-015d (QA-001): exactly 1 workflow-gate after double setup" "1" "$gate_count"
assert_eq "R-015d (QA-001): exactly 1 audit-trail after double setup" "1" "$audit_count"
assert_eq "R-015d (QA-001): exactly 1 workflow-advance after double setup" "1" "$advance_count"
cleanup_setup

echo "--- R-015e (QA-001): setup on partial config does not duplicate existing entries ---"
setup_install_project
mkdir -p .claude
cat > .claude/settings.json <<'PARTIAL'
{
  "hooks": {
    "PreToolUse": [{"matcher": "Edit|Write|MultiEdit|NotebookEdit|CreateFile|Bash", "hooks": [{"type": "command", "command": ".claude/hooks/workflow-gate.sh", "timeout_ms": 5000}]}]
  }
}
PARTIAL
.claude/skills/workflow/setup >/dev/null 2>&1 || true
settings_file="$SETUP_TEST_DIR/.claude/settings.json"
gate_count=$(grep -c 'workflow-gate' "$settings_file")
assert_eq "R-015e (QA-001): exactly 1 workflow-gate after partial merge" "1" "$gate_count"
cleanup_setup

cd "$REPO_DIR" || exit 1

# ===========================================================================
echo ""
echo "=== QA-009: Null workspace.current_dir ==="
# ===========================================================================

echo "--- QA-009: null workspace.current_dir → no crash, no git info ---"
json_qa009=$(unit_json | jq '.workspace.current_dir = null')
qa009_exit=0
qa009_out=$(printf '%s' "$json_qa009" | bash "$STATUSLINE" 2>/dev/null) || qa009_exit=$?
assert_eq "QA-009: script exits 0 with null current_dir" "0" "$qa009_exit"
out=$(printf '%s' "$qa009_out" | strip_colors)
assert_not_contains "QA-009: no branch info with null dir" 'main' "$out"
assert_not_contains "QA-009: no dirty info with null dir" 'dirty' "$out"

# ===========================================================================
echo ""
echo "=== QA-011: Null model display_name ==="
# ===========================================================================

echo "--- QA-011: null model.display_name → 'null' literal does not appear ---"
json_qa011=$(unit_json | jq '.model.display_name = null')
out=$(run_sl "$json_qa011")
assert_not_contains_str "QA-011: null model → no literal 'null' in output" 'null' "$out"

# ===========================================================================
echo ""
echo "=== R-016: git status uses --no-optional-locks ==="
# ===========================================================================

# Tests R-016 [integration]: git status call in script uses --no-optional-locks

echo "--- R-016: hooks/statusline.sh uses --no-optional-locks with git status ---"
# Verify the script source contains the --no-optional-locks flag on a git status call
if grep -q 'git.*--no-optional-locks.*status\|git status.*--no-optional-locks' "$STATUSLINE"; then
  assert_eq "R-016: git status uses --no-optional-locks" "yes" "yes"
else
  assert_eq "R-016: git status uses --no-optional-locks" "yes" "no"
fi

# ===========================================================================
echo ""
echo "=== R-017: context_window_size null/0/missing guard ==="
# ===========================================================================

# Tests R-017 [unit]: null, 0, or missing context_window_size → context % omitted

echo "--- R-017a: context_window_size=null → no % in output ---"
json_r017a=$(printf '%s' "$(unit_json)" | jq '
  .context_window.current_usage = {input_tokens: 10000, cache_creation_input_tokens: 0, cache_read_input_tokens: 0}
  | .context_window.context_window_size = null
')
out=$(run_sl "$json_r017a")
assert_not_contains "R-017a: null context_window_size → no %" '%' "$out"

echo "--- R-017b: context_window_size=0 → no % in output (avoids division by zero) ---"
json_r017b=$(printf '%s' "$(unit_json)" | jq '
  .context_window.current_usage = {input_tokens: 10000, cache_creation_input_tokens: 0, cache_read_input_tokens: 0}
  | .context_window.context_window_size = 0
')
# Script must exit cleanly (no crash from division by zero) AND produce some output
r017b_exit=0
r017b_out=$(printf '%s' "$json_r017b" | bash "$STATUSLINE" 2>/dev/null) || r017b_exit=$?
assert_eq "R-017b: script exits 0 with context_window_size=0 (no crash)" "0" "$r017b_exit"
out=$(printf '%s' "$r017b_out" | strip_colors)
assert_not_contains "R-017b: zero context_window_size → no %" '%' "$out"
# The script source must contain an explicit guard for zero/null context_window_size
if grep -q 'context_window_size.*0\|CONTEXT_SIZE.*0\|-eq 0\|-le 0\|context_window_size.*null' "$STATUSLINE"; then
  assert_eq "R-017b: source has explicit zero-size guard" "yes" "yes"
else
  assert_eq "R-017b: source has explicit zero-size guard" "yes" "no"
fi

echo "--- R-017c: context_window_size missing → no % in output ---"
json_r017c=$(printf '%s' "$(unit_json)" | jq '
  .context_window.current_usage = {input_tokens: 10000, cache_creation_input_tokens: 0, cache_read_input_tokens: 0}
  | del(.context_window.context_window_size)
')
out=$(run_sl "$json_r017c")
assert_not_contains "R-017c: missing context_window_size → no %" '%' "$out"

# ===========================================================================
echo ""
echo "=== R-018: Both token counts zero → element omitted ==="
# ===========================================================================

# Tests R-018 [unit]: both total_input_tokens=0 and total_output_tokens=0 → no token element

echo "--- R-018: both tokens=0 → (in:out) element omitted ---"
json_r018=$(printf '%s' "$(unit_json)" | jq '.context_window.total_input_tokens = 0 | .context_window.total_output_tokens = 0')
out=$(run_sl "$json_r018")
assert_not_contains_str "R-018: both zero tokens → no (in:out)" '(in:out)' "$out"

# ===========================================================================
echo ""
echo "==========================================="
echo "  Results: $PASS passed, $FAIL failed"
echo "==========================================="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
