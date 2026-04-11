#!/usr/bin/env bash
# shellcheck disable=SC1090,SC1091,SC2016,SC2086
# Correctless — Fix-Diff Reviewer Plugin Agent Migration Tests
#
# Enforces the fix-diff-reviewer-migration spec's invariants, prohibitions,
# and boundary conditions (INV-001..INV-019, PRH-001..PRH-005, BND-001..BND-006).
#
# Run from repo root: bash tests/test-fix-diff-reviewer-agent.sh
#
# This is the RED-phase structural test. It asserts:
#   - agents/fix-diff-reviewer.md exists with correct frontmatter
#   - correctless/agents/fix-diff-reviewer.md is in sync and also locked down
#   - skills/caudit/SKILL.md step 6a wires the Task invocation, deletes the
#     inline prompt, contains the canonical fail-closed marker exactly once,
#     DD-008 rule-scan instructions, UNTRUSTED fences, 100KB cap, jq -e parse,
#     and the configurable zero-findings threshold key.
#   - sync.sh propagates agents/ to correctless/agents/ and catches stale files.
#   - .correctless/ARCHITECTURE.md has ABS-010 and ENV-007 headings.
#   - The new test is wired into tests/test.sh without exit-code swallowing
#     and into .correctless/config/workflow-config.json commands.test.
#   - Fixture .diff files exist with pinned SHA-256 hashes.
#   - The /cverify-produced verification replay report satisfies VP-001/VP-002
#     (SKIPPED when the report is absent — GREEN should leave those as SKIP).
#
# POSIX-portable externals only: grep, sed, awk, sha256sum, find. Bash 4+
# constructs are permitted.

set -uo pipefail
set -f

cd "$(dirname "${BASH_SOURCE[0]}")/.." || { echo "FATAL: cannot cd to repo root" >&2; exit 2; }

# ============================================================================
# Colors (only if stdout is a terminal)
# ============================================================================

if [ -t 1 ]; then
  GREEN=$'\033[0;32m'
  RED=$'\033[0;31m'
  YELLOW=$'\033[0;33m'
  RESET=$'\033[0m'
else
  GREEN=""
  RED=""
  YELLOW=""
  RESET=""
fi

PASS=0
FAIL=0
SKIPPED=0
FAILED_IDS=""

# ============================================================================
# Result helpers
# ============================================================================

pass() {
  local id="$1" desc="$2"
  echo "  ${GREEN}PASS${RESET}: $id: $desc"
  PASS=$((PASS + 1))
}

fail() {
  local id="$1" desc="$2"
  echo "  ${RED}FAIL${RESET}: $id: $desc"
  FAIL=$((FAIL + 1))
  FAILED_IDS="${FAILED_IDS}${id} "
}

skip() {
  local id="$1" desc="$2"
  echo "  ${YELLOW}SKIP${RESET}: $id: $desc"
  SKIPPED=$((SKIPPED + 1))
}

section() {
  echo ""
  echo "--- Testing: $1 ---"
}

# ============================================================================
# File paths
# ============================================================================

AGENT_SRC="agents/fix-diff-reviewer.md"
AGENT_DIST="correctless/agents/fix-diff-reviewer.md"
CAUDIT_SKILL="skills/caudit/SKILL.md"
SYNC_SH="sync.sh"
ARCH_FILE=".correctless/ARCHITECTURE.md"
TEST_RUNNER="tests/test.sh"
WORKFLOW_CONFIG=".correctless/config/workflow-config.json"
FIXTURE_R1="tests/fixtures/fix-diff-reviewer-historical-r1.diff"
FIXTURE_R2="tests/fixtures/fix-diff-reviewer-historical-r2.diff"
FIXTURE_R3="tests/fixtures/fix-diff-reviewer-historical-r3.diff"
FIXTURE_META="tests/fixtures/fix-diff-reviewer-historical-commits.md"
VERIFY_REPORT=".correctless/verification/fix-diff-reviewer-migration-replay.md"

EXPECTED_NAMESPACED_TASK='subagent_type="correctless:fix-diff-reviewer"'
EXPECTED_BARE_TASK='subagent_type="fix-diff-reviewer"'
EXPECTED_DOGFOOD_MARKER='<!-- Dogfood prototype (2026-04-10): fix-diff-reviewer-migration — Phase 2a of custom sub-agents. See .correctless/specs/fix-diff-reviewer-migration.md -->'
EXPECTED_CANONICAL_MARKER='FAIL-CLOSED: Task failure aborts the current round'

# ============================================================================
# Helpers
# ============================================================================

# Extract frontmatter block (between leading --- lines) from a markdown file.
# Emits nothing and returns non-zero if frontmatter is absent or malformed.
#
# Result is memoized per-file — multiple check functions read the same
# agent/skill frontmatter, and extraction + field-lookup were previously
# forking awk ~13 times for the same content.
extract_frontmatter() {
  local file="$1"
  [ -f "$file" ] || return 1
  local cache_var
  cache_var="_FM_CACHE_$(printf '%s' "$file" | tr -c 'a-zA-Z0-9' '_')"
  # Indirect variable expansion is bash-specific but this test file is bash-only.
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
      # Match "key: value" (allow leading whitespace).
      if (match($0, "^[[:space:]]*" k ":[[:space:]]*")) {
        val = substr($0, RSTART + RLENGTH)
        # Strip trailing whitespace.
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
# Normalizes whitespace and strips empties. Returns non-zero if field missing.
parse_tools_list() {
  local file="$1"
  local raw
  raw="$(get_frontmatter_field "$file" "tools")" || return 1
  [ -n "$raw" ] || return 1
  # Split on comma, trim whitespace, print one per line.
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

# Extract the step 6a block from caudit SKILL.md, delimited by the HTML
# sentinel comments `<!-- STEP 6A BEGIN -->` and `<!-- STEP 6A END -->`
# (required by INV-020). The sentinel lines themselves are NOT included
# in the output. Returns empty if either sentinel is missing (RED state).
#
# Result is memoized per-file — caudit SKILL.md is immutable during a
# test run, and ~10 check functions invoke this helper. Without caching
# each invocation forks awk and re-parses the file.
extract_step_6a_block() {
  local file="$1"
  [ -f "$file" ] || return 1
  if [ -n "${_STEP_6A_CACHE_FILE:-}" ] && [ "$_STEP_6A_CACHE_FILE" = "$file" ]; then
    printf '%s' "$_STEP_6A_CACHE"
    [ -n "$_STEP_6A_CACHE" ] && return 0 || return 1
  fi
  _STEP_6A_CACHE_FILE="$file"
  _STEP_6A_CACHE="$(awk '
    BEGIN { in_block = 0; found = 0 }
    /<!-- STEP 6A BEGIN -->/ { in_block = 1; found = 1; next }
    /<!-- STEP 6A END -->/ { in_block = 0; next }
    in_block { print }
    END { exit (found ? 0 : 1) }
  ' "$file" 2>/dev/null || true)"
  printf '%s' "$_STEP_6A_CACHE"
  [ -n "$_STEP_6A_CACHE" ] && return 0 || return 1
}

# Extract the entire caudit SKILL.md with the narrative
# `### Why fix verification is mandatory` section removed. Used by B02
# (belt-and-suspenders whole-file denylist checks). Memoized like
# extract_step_6a_block — 3 call sites, same file, same result.
extract_caudit_minus_narrative() {
  local file="$1"
  [ -f "$file" ] || return 1
  if [ -n "${_CAUDIT_MINUS_CACHE_FILE:-}" ] && [ "$_CAUDIT_MINUS_CACHE_FILE" = "$file" ]; then
    printf '%s' "$_CAUDIT_MINUS_CACHE"
    return 0
  fi
  _CAUDIT_MINUS_CACHE_FILE="$file"
  _CAUDIT_MINUS_CACHE="$(awk '
    BEGIN { skip = 0 }
    /^### Why fix verification is mandatory/ { skip = 1; next }
    skip && (/^### / || /^## /) { skip = 0 }
    !skip { print }
  ' "$file" 2>/dev/null || true)"
  printf '%s' "$_CAUDIT_MINUS_CACHE"
}

# Emit a warning (advisory) if the extracted 6a block is shorter than N lines.
# Does not fail — downstream 6a checks still run and will fail naturally if
# the block is empty. This is a signal that assertions may be vacuous.
warn_if_stub_block() {
  local block="$1" min="${2:-30}"
  local lc
  lc="$(printf '%s\n' "$block" | grep -c '' 2>/dev/null || echo 0)"
  if [ -z "$block" ]; then
    echo "  ${YELLOW}NOTE${RESET}: step 6a block is EMPTY (sentinels <!-- STEP 6A BEGIN/END --> missing — GREEN hasn't run yet)" >&2
  elif [ "$lc" -lt "$min" ]; then
    echo "  ${YELLOW}NOTE${RESET}: step 6a block has $lc lines (<$min) — assertions may be operating on a stub" >&2
  fi
}

# Parse the skill frontmatter `allowed-tools:` field (comma-flow form) and
# emit one tool (or tool sub-pattern) per line.
parse_allowed_tools() {
  local file="$1"
  local raw
  raw="$(get_frontmatter_field "$file" "allowed-tools")" || return 1
  [ -n "$raw" ] || return 1
  # Split on commas that are NOT inside parentheses (to preserve Bash(git*)).
  printf '%s\n' "$raw" | awk '
    {
      s = $0
      depth = 0
      start = 1
      for (i = 1; i <= length(s); i++) {
        c = substr(s, i, 1)
        if (c == "(") depth++
        else if (c == ")") depth--
        else if (c == "," && depth == 0) {
          tok = substr(s, start, i - start)
          gsub(/^[[:space:]]+|[[:space:]]+$/, "", tok)
          if (tok != "") print tok
          start = i + 1
        }
      }
      tok = substr(s, start)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", tok)
      if (tok != "") print tok
    }
  '
}

# ============================================================================
# INV-001: agents/fix-diff-reviewer.md exists and has valid frontmatter
# ============================================================================

check_inv001() {
  section "INV-001: Agent file exists with valid frontmatter"

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

  local name
  name="$(get_frontmatter_field "$AGENT_SRC" "name" 2>/dev/null)" || name=""
  if [ -n "$name" ]; then
    pass "INV-001(c)" "frontmatter has non-empty name: field"
  else
    fail "INV-001(c)" "frontmatter missing or empty name: field"
  fi

  local desc
  desc="$(get_frontmatter_field "$AGENT_SRC" "description" 2>/dev/null)" || desc=""
  if [ -z "$desc" ]; then
    fail "INV-001(d)" "frontmatter missing or empty description: field"
  elif [ "${#desc}" -lt 20 ]; then
    fail "INV-001(d)" "description: field is ${#desc} characters, required >=20"
  else
    pass "INV-001(d)" "description: field present and >=20 characters"
  fi

  local tools_raw
  tools_raw="$(get_frontmatter_field "$AGENT_SRC" "tools" 2>/dev/null)" || tools_raw=""
  if [ -z "$tools_raw" ]; then
    fail "INV-001(e)" "frontmatter missing or empty tools: field"
  elif ! printf '%s' "$tools_raw" | grep -q ","; then
    # Comma-flow form: at least two commas expected for Read, Grep, Glob.
    # But a minimum of one comma proves it's not a YAML list (- foo).
    # If the tools field starts with a dash, it's block-style and violates EA-006.
    if printf '%s' "$tools_raw" | grep -qE '^\[|^-'; then
      fail "INV-001(e)" "tools: field is not comma-flow form (got: $tools_raw)"
    else
      # A01: <2 entries is a soft-warning advisory — INV-003 enforces the
      # exact 3-tool set, but flag the ambiguity clearly here.
      echo "  ${YELLOW}NOTE${RESET}: INV-001(e): tools: has <2 comma-separated entries (got: '$tools_raw') — see INV-003 for final set-equality enforcement" >&2
      pass "INV-001(e)" "tools: field present (value: $tools_raw) — advisory: <2 entries"
    fi
  else
    pass "INV-001(e)" "tools: field present in comma-flow form"
  fi

  # Optional model: field — if present, must be in allowlist.
  local model
  model="$(get_frontmatter_field "$AGENT_SRC" "model" 2>/dev/null)" || model=""
  if [ -n "$model" ]; then
    case "$model" in
      sonnet|opus|haiku|inherit)
        pass "INV-001(f)" "optional model: field has allowed value ($model)"
        ;;
      *)
        fail "INV-001(f)" "optional model: field has disallowed value ($model); must be sonnet|opus|haiku|inherit"
        ;;
    esac
  else
    pass "INV-001(f)" "optional model: field absent (allowed)"
  fi
}

# ============================================================================
# INV-002: frontmatter name matches filename basename
# ============================================================================

check_inv002() {
  section "INV-002: Agent name matches file path"

  if [ ! -f "$AGENT_SRC" ]; then
    fail "INV-002" "$AGENT_SRC does not exist (cannot check name/basename)"
    return
  fi
  local name basename_minus_ext
  name="$(get_frontmatter_field "$AGENT_SRC" "name" 2>/dev/null)" || name=""
  basename_minus_ext="$(basename "$AGENT_SRC" .md)"
  if [ "$name" = "fix-diff-reviewer" ] && [ "$name" = "$basename_minus_ext" ]; then
    pass "INV-002" "frontmatter name ('$name') == basename ('$basename_minus_ext') == 'fix-diff-reviewer'"
  else
    fail "INV-002" "name='$name' basename='$basename_minus_ext' (both must equal 'fix-diff-reviewer')"
  fi
}

# ============================================================================
# INV-003: tools set-equal to {Read, Grep, Glob} (source AND distribution)
# ============================================================================

check_tools_set_equality() {
  local file="$1" label="$2"
  if [ ! -f "$file" ]; then
    fail "INV-003($label)" "$file does not exist"
    return
  fi
  local tools
  tools="$(parse_tools_list "$file" 2>/dev/null)" || {
    fail "INV-003($label)" "$file has no parseable tools: field"
    return
  }
  # Sort and dedupe the actual tools list.
  local actual_sorted expected_sorted
  actual_sorted="$(printf '%s\n' "$tools" | sort -u)"
  expected_sorted="$(printf 'Glob\nGrep\nRead\n')"
  if [ "$actual_sorted" = "$expected_sorted" ]; then
    pass "INV-003($label)" "tools set-equal to {Read, Grep, Glob}"
  else
    local actual_compact
    actual_compact="$(printf '%s' "$actual_sorted" | tr '\n' ',' | sed 's/,$//')"
    fail "INV-003($label)" "tools set is {$actual_compact}, expected exactly {Glob,Grep,Read}"
  fi
}

check_inv003() {
  section "INV-003: Agent tools == {Read, Grep, Glob} in source AND distribution"
  check_tools_set_equality "$AGENT_SRC" "source"
  check_tools_set_equality "$AGENT_DIST" "dist"

  # G03: byte-equality between source and dist (sync.sh invariant).
  if [ -f "$AGENT_SRC" ] && [ -f "$AGENT_DIST" ]; then
    if diff -q "$AGENT_SRC" "$AGENT_DIST" >/dev/null 2>&1; then
      pass "INV-003(byte-eq)" "source and dist agent files are byte-equal"
    else
      fail "INV-003(byte-eq)" "source and dist agent files differ (sync.sh must enforce byte equality)"
    fi
  else
    skip "INV-003(byte-eq)" "byte-equality skipped (one or both agent files absent)"
  fi
}

# ============================================================================
# INV-020: Step 6a delimited by HTML sentinel comments (cardinality=1 each,
# BEGIN before END).
# ============================================================================

check_inv020() {
  section "INV-020: Step 6a HTML sentinel comments (cardinality 1, BEGIN<END)"
  if [ ! -f "$CAUDIT_SKILL" ]; then
    fail "INV-020" "$CAUDIT_SKILL does not exist"
    return
  fi

  local begin_count end_count
  begin_count="$(grep -c '<!-- STEP 6A BEGIN -->' "$CAUDIT_SKILL" 2>/dev/null | head -n 1 | tr -d '[:space:]')"
  end_count="$(grep -c '<!-- STEP 6A END -->' "$CAUDIT_SKILL" 2>/dev/null | head -n 1 | tr -d '[:space:]')"
  begin_count="${begin_count:-0}"
  end_count="${end_count:-0}"

  if [ "$begin_count" -eq 1 ]; then
    pass "INV-020(a)" "'<!-- STEP 6A BEGIN -->' appears exactly once"
  else
    fail "INV-020(a)" "'<!-- STEP 6A BEGIN -->' appears $begin_count time(s) (expected exactly 1)"
  fi

  if [ "$end_count" -eq 1 ]; then
    pass "INV-020(b)" "'<!-- STEP 6A END -->' appears exactly once"
  else
    fail "INV-020(b)" "'<!-- STEP 6A END -->' appears $end_count time(s) (expected exactly 1)"
  fi

  if [ "$begin_count" -eq 1 ] && [ "$end_count" -eq 1 ]; then
    local begin_ln end_ln
    begin_ln="$(grep -n '<!-- STEP 6A BEGIN -->' "$CAUDIT_SKILL" | head -n 1 | cut -d: -f1)"
    end_ln="$(grep -n '<!-- STEP 6A END -->' "$CAUDIT_SKILL" | head -n 1 | cut -d: -f1)"
    if [ -n "$begin_ln" ] && [ -n "$end_ln" ] && [ "$begin_ln" -lt "$end_ln" ]; then
      pass "INV-020(c)" "BEGIN (line $begin_ln) < END (line $end_ln)"
    else
      fail "INV-020(c)" "BEGIN line ($begin_ln) must be < END line ($end_ln)"
    fi
  else
    skip "INV-020(c)" "cannot check BEGIN<END ordering (counts not both 1)"
  fi
}

# ============================================================================
# INV-004: Diff uses <round-start-sha>..HEAD, NOT HEAD~1..HEAD; UNTRUSTED_DIFF
# fences present in step 6a.
# ============================================================================

check_inv004() {
  section "INV-004: Orchestrator-computed diff with UNTRUSTED fences"
  if [ ! -f "$CAUDIT_SKILL" ]; then
    fail "INV-004" "$CAUDIT_SKILL does not exist"
    return
  fi
  local block
  block="$(extract_step_6a_block "$CAUDIT_SKILL" 2>/dev/null)" || block=""
  warn_if_stub_block "$block" 30
  if [ -z "$block" ]; then
    fail "INV-004" "step 6a block is empty — sentinels missing, GREEN hasn't run yet"
    return
  fi

  if printf '%s\n' "$block" | grep -qF '<round-start-sha>..HEAD'; then
    pass "INV-004(a)" "step 6a references <round-start-sha>..HEAD diff range"
  else
    fail "INV-004(a)" "step 6a missing literal '<round-start-sha>..HEAD' diff range"
  fi

  # A02: require <round-start-sha>..HEAD adjacent to a `git diff` command.
  if printf '%s\n' "$block" | grep -qE 'git[[:space:]]+diff[[:space:]].*<round-start-sha>\.\.HEAD|<round-start-sha>\.\.HEAD.*git[[:space:]]+diff'; then
    pass "INV-004(a2)" "step 6a '<round-start-sha>..HEAD' is adjacent to 'git diff' invocation"
  else
    fail "INV-004(a2)" "step 6a '<round-start-sha>..HEAD' not adjacent to 'git diff' command"
  fi

  # B02: belt-and-suspenders — the extracted block AND the whole-file-minus-
  # narrative must BOTH lack the prohibited HEAD~1..HEAD range.
  local block_hit=0 file_hit=0
  if printf '%s\n' "$block" | grep -qF 'HEAD~1..HEAD'; then block_hit=1; fi
  local file_minus
  file_minus="$(extract_caudit_minus_narrative "$CAUDIT_SKILL" 2>/dev/null || true)"
  if printf '%s\n' "$file_minus" | grep -qF 'HEAD~1..HEAD'; then file_hit=1; fi
  if [ "$block_hit" -eq 0 ] && [ "$file_hit" -eq 0 ]; then
    pass "INV-004(b)" "neither the 6a block nor the whole-file-minus-narrative contains 'HEAD~1..HEAD'"
  else
    fail "INV-004(b)" "forbidden 'HEAD~1..HEAD' present (block=$block_hit, file-minus-narrative=$file_hit)"
  fi

  if printf '%s\n' "$block" | grep -qF '<UNTRUSTED_DIFF>'; then
    pass "INV-004(c)" "step 6a contains <UNTRUSTED_DIFF> opening fence"
  else
    fail "INV-004(c)" "step 6a missing <UNTRUSTED_DIFF> opening fence"
  fi

  if printf '%s\n' "$block" | grep -qF '</UNTRUSTED_DIFF>'; then
    pass "INV-004(d)" "step 6a contains </UNTRUSTED_DIFF> closing fence"
  else
    fail "INV-004(d)" "step 6a missing </UNTRUSTED_DIFF> closing fence"
  fi
}

# ============================================================================
# INV-005: caudit uses namespaced subagent_type; bare form absent.
# ============================================================================

check_inv005() {
  section "INV-005: caudit invokes via namespaced subagent_type"
  if [ ! -f "$CAUDIT_SKILL" ]; then
    fail "INV-005" "$CAUDIT_SKILL does not exist"
    return
  fi

  if grep -qF "$EXPECTED_NAMESPACED_TASK" "$CAUDIT_SKILL"; then
    pass "INV-005(a)" "caudit contains namespaced subagent_type=\"correctless:fix-diff-reviewer\""
  else
    fail "INV-005(a)" "caudit missing namespaced subagent_type=\"correctless:fix-diff-reviewer\""
  fi

  # Bare form must NOT appear. A03: exclude backtick code spans and blockquote
  # lines (^> ). Strip them before counting. The bare form is a substring of
  # the namespaced form, so subtract namespaced occurrences from bare count.
  local filtered
  filtered="$(awk '
    /^>[[:space:]]/ { next }
    {
      s = $0
      out = ""
      in_span = 0
      for (i = 1; i <= length(s); i++) {
        c = substr(s, i, 1)
        if (c == "`") { in_span = 1 - in_span; continue }
        if (!in_span) out = out c
      }
      print out
    }
  ' "$CAUDIT_SKILL")"
  local bare_hits ns_hits
  bare_hits="$(printf '%s\n' "$filtered" | grep -cF "$EXPECTED_BARE_TASK" 2>/dev/null)" || bare_hits=0
  ns_hits="$(printf '%s\n' "$filtered" | grep -cF "$EXPECTED_NAMESPACED_TASK" 2>/dev/null)" || ns_hits=0
  bare_hits="${bare_hits:-0}"
  ns_hits="${ns_hits:-0}"
  # Every namespaced match also matches the bare substring, so a "clean" state
  # is bare_hits == ns_hits.
  if [ "$bare_hits" -le "$ns_hits" ]; then
    pass "INV-005(b)" "no unnamespaced subagent_type=\"fix-diff-reviewer\" occurrences (excluding code spans/blockquotes)"
  else
    fail "INV-005(b)" "found $((bare_hits - ns_hits)) unnamespaced subagent_type=\"fix-diff-reviewer\" occurrence(s)"
  fi
}

# ============================================================================
# INV-006 (+ PRH-001): no inline fix-diff-reviewer prompt in any skill.
# ============================================================================

check_inv006() {
  section "INV-006 / PRH-001: Inline fix-diff-reviewer prompt removed from all skills"

  # Enumerate all skill files via find (glob expansion is disabled under set -f).
  local skill_files
  skill_files="$(find skills -type f -name 'SKILL.md' 2>/dev/null)"

  # (a) No "### Fix-Diff Review Agent" heading in any skill (case-sensitive).
  local heading_hits=""
  if [ -n "$skill_files" ]; then
    local sf
    for sf in $skill_files; do
      if grep -q '^### Fix-Diff Review Agent' "$sf" 2>/dev/null; then
        heading_hits="${heading_hits}${sf} "
      fi
    done
  fi
  if [ -z "$heading_hits" ]; then
    pass "INV-006(a)" "no '### Fix-Diff Review Agent' heading in any skills/*/SKILL.md"
  else
    fail "INV-006(a)" "'### Fix-Diff Review Agent' heading found in: $heading_hits"
  fi

  # (a2) Case-insensitive/variant heading: "### fix-diff review", "### Fix/Diff Review", etc.
  local vhits=""
  if [ -n "$skill_files" ]; then
    local sf
    for sf in $skill_files; do
      if grep -qE '^### *[Ff]ix.?[Dd]iff +[Rr]eview' "$sf" 2>/dev/null; then
        vhits="${vhits}${sf} "
      fi
    done
  fi
  if [ -z "$vhits" ]; then
    pass "INV-006(a2)" "no case-variant '### fix.?diff review' heading in any skills/*/SKILL.md"
  else
    fail "INV-006(a2)" "case-variant fix-diff review heading found in: $vhits"
  fi

  # (a3) Consecutive blockquote-run detection in caudit's Loop section. The
  # current inline prompt is a 22-line blockquote between "## The Loop" and
  # "## Convergence". Any run of >=4 consecutive "^> " lines fails.
  if [ -f "$CAUDIT_SKILL" ]; then
    local max_run
    max_run="$(awk '
      BEGIN { in_scope = 0; run = 0; max = 0 }
      /^## The Loop/ { in_scope = 1; next }
      in_scope && /^## Convergence/ { exit }
      in_scope {
        if ($0 ~ /^> /) {
          run++
          if (run > max) max = run
        } else {
          run = 0
        }
      }
      END { print max + 0 }
    ' "$CAUDIT_SKILL")"
    if [ "${max_run:-0}" -lt 4 ]; then
      pass "INV-006(a3)" "no blockquote-run >=4 lines between '## The Loop' and '## Convergence' (max run: $max_run)"
    else
      fail "INV-006(a3)" "blockquote-run of $max_run consecutive '^> ' lines detected in the Loop section (inline prompt likely surviving)"
    fi
  else
    fail "INV-006(a3)" "$CAUDIT_SKILL does not exist"
  fi

  # (b) Denylist of 8 inline-prompt phrases (aggregated across all skill files).
  # Using grep -F (fixed string) to avoid regex surprises.
  local phrases=(
    "You are the fix-diff reviewer"
    "Your sole job is to find new bugs introduced by the fix commits"
    "git diff HEAD~1..HEAD"
    "Does the change actually address"
    ".correctless/antipatterns.md. Especially AP-011"
    "spawn a single subagent with this framing"
    "scope is the diff of the fix commit"
    "out of scope — this agent catches bugs"
  )
  local total_hits=0
  local phrase sf
  for phrase in "${phrases[@]}"; do
    if [ -n "$skill_files" ]; then
      for sf in $skill_files; do
        local cnt
        cnt="$(grep -cF "$phrase" "$sf" 2>/dev/null)" || cnt=0
        cnt="${cnt:-0}"
        total_hits=$((total_hits + cnt))
      done
    fi
  done
  if [ "$total_hits" -eq 0 ]; then
    pass "INV-006(b)" "none of the 8 inline-prompt denylist phrases appear in any skills/*/SKILL.md"
  else
    fail "INV-006(b)" "$total_hits inline-prompt denylist phrase hit(s) across skills/*/SKILL.md"
  fi
}

# ============================================================================
# INV-007: VP-002 functional-equivalence replay section in verification report.
# Wrapped in SKIP when report is absent (created during /cverify, not /ctdd).
# ============================================================================

check_inv007() {
  section "INV-007: VP-002 functional-equivalence replay (wrapped in SKIP)"

  if [ ! -f "$VERIFY_REPORT" ]; then
    skip "INV-007" "verification report assertions (run /cverify first): $VERIFY_REPORT"
    return
  fi

  # (a) Has the VP-002 heading.
  if grep -qF '## VP-002: Functional Equivalence Replay' "$VERIFY_REPORT"; then
    pass "INV-007(a)" "VP-002 heading present"
  else
    fail "INV-007(a)" "VP-002 heading missing"
  fi

  # B12(1): Extract the body of the VP-002 section and search within it only.
  local vp002_body
  vp002_body="$(awk '
    /^## VP-002: Functional Equivalence Replay/ { in_section = 1; next }
    in_section && /^## / { exit }
    in_section { print }
  ' "$VERIFY_REPORT")"

  # (b) "Result: PASS" anchored within VP-002 section.
  if printf '%s\n' "$vp002_body" | grep -qE '^Result:[[:space:]]*PASS[[:space:]]*$'; then
    pass "INV-007(b)" "VP-002 section contains anchored '^Result: PASS$'"
  else
    fail "INV-007(b)" "VP-002 section missing anchored '^Result: PASS$' line"
  fi

  # B12(2): Mapping table row count, scoped to the actual table inside VP-002.
  # Find table header row matching "| ... Regression ... layer ..." and count
  # data rows (skip the header row itself and the --- separator row).
  local data_rows
  data_rows="$(printf '%s\n' "$vp002_body" | awk '
    BEGIN { in_table = 0; rows = 0 }
    /^\|[[:space:]]*Regression[[:space:]]*layer/ { in_table = 1; next }
    in_table {
      if ($0 !~ /^\|/) { in_table = 0; next }
      if ($0 ~ /^\|[[:space:]]*-+/) next
      rows++
    }
    END { print rows + 0 }
  ')"
  if [ "${data_rows:-0}" -ge 3 ]; then
    pass "INV-007(c)" "VP-002 mapping table has $data_rows data rows (>=3)"
  else
    fail "INV-007(c)" "VP-002 mapping table has $data_rows data rows (<3)"
  fi

  # B12(3): Expanded placeholder regex.
  if printf '%s\n' "$vp002_body" | grep -qE 'FD-xxx|FD-yyy|FD-zzz|FD-\?\?\??|\bTODO\b|\bN/A\b|\bFIXME\b|\bXXX\b|\btbd\b|\bTBD\b|<fill|<placeholder|placeholder'; then
    fail "INV-007(d)" "placeholder/TODO markers detected in VP-002 section"
  else
    pass "INV-007(d)" "no placeholder/TODO markers in VP-002 section"
  fi

  # (e) Each Response r{1,2,3} block is >=50 non-whitespace characters AND
  # B12(4): contains at least one plausibility marker ({, [, "id", Task(,
  # severity, subagent_type).
  local r
  for r in r1 r2 r3; do
    local body
    body="$(awk -v want="### Response $r" '
      $0 == want { in_block = 1; next }
      in_block && /^### / { exit }
      in_block && /^## / { exit }
      in_block { print }
    ' "$VERIFY_REPORT")"
    local nonws
    nonws="$(printf '%s' "$body" | tr -d '[:space:]' | wc -c)"
    if [ "$nonws" -ge 50 ]; then
      pass "INV-007(e:$r)" "### Response $r block has $nonws non-ws chars (>=50)"
    else
      fail "INV-007(e:$r)" "### Response $r block has $nonws non-ws chars (<50)"
    fi
    if printf '%s\n' "$body" | grep -qE '\{|\[|"id"|Task\(|severity|subagent_type'; then
      pass "INV-007(e2:$r)" "### Response $r contains at least one plausibility marker"
    else
      fail "INV-007(e2:$r)" "### Response $r lacks any plausibility marker ({, [, \"id\", Task(, severity, subagent_type)"
    fi
  done

  # (f) findings_returned_per_replay field present and not [0, 0, 0].
  # B12(5): normalize whitespace before matching.
  if grep -qE 'findings_returned_per_replay' "$VERIFY_REPORT"; then
    local normalized
    normalized="$(tr -d ' \t' < "$VERIFY_REPORT")"
    if printf '%s' "$normalized" | grep -qE 'findings_returned_per_replay.*\[0,0,0\]'; then
      fail "INV-007(f)" "findings_returned_per_replay is [0, 0, 0] (auto-fail)"
    else
      pass "INV-007(f)" "findings_returned_per_replay present and non-trivial"
    fi
  else
    fail "INV-007(f)" "findings_returned_per_replay field missing"
  fi
}

# ============================================================================
# INV-008: sync.sh edits + stale-file detection contract.
# ============================================================================

check_inv008() {
  section "INV-008: sync.sh propagates agents/ with stale-file detection"

  if [ ! -f "$SYNC_SH" ]; then
    fail "INV-008" "$SYNC_SH not found"
    return
  fi

  # (a) Top-level directory allowlist case statement includes `agents`.
  # Check within a narrow window around line 146: look at the stale-top-level-items
  # case statement body (5 lines after "# Expected top-level dirs").
  # NOTE: uses index() rather than `\<agents\>` because mawk (Ubuntu default)
  # parses \<...\> as literal `<agents>` rather than word boundaries.
  if awk '
    /Expected top-level dirs:/ { scan = 5; next }
    scan > 0 {
      if (index($0, "|agents)") > 0) { found = 1; exit }
      scan--
    }
    END { exit (found ? 0 : 1) }
  ' "$SYNC_SH"; then
    pass "INV-008(a)" "top-level dir allowlist case statement includes 'agents'"
  else
    fail "INV-008(a)" "top-level dir allowlist case statement missing 'agents'"
  fi

  # (b) Stale-file detection loop covers `agents`.
  # Look for "for dir in ... agents" pattern in the stale-file loop area.
  # Same mawk-portability note as (a): use index() not \<agents\>.
  #
  # QA-004 class fix: primary-window miss emits a visible WARN to stderr
  # before falling through to the looser whole-file fallback. Silent
  # fall-through hides drift between test intent and effect.
  if awk '
    /Hooks and scripts: check for stale/ { scan = 3; next }
    scan > 0 {
      if ($0 ~ /for[[:space:]]+dir[[:space:]]+in[[:space:]]/ && index($0, "agents") > 0) { found = 1; exit }
      scan--
    }
    END { exit (found ? 0 : 1) }
  ' "$SYNC_SH"; then
    pass "INV-008(b)" "stale-file detection loop covers 'agents'"
  else
    # Primary window missed — emit a WARN so the drift is visible.
    echo "  ${YELLOW}NOTE${RESET}: INV-008(b): primary window check (3 lines after 'Hooks and scripts: check for stale') missed — falling back to file-wide scan" >&2
    # Fallback: search for any loop that pairs 'agents' with a .md glob.
    if grep -E "for[[:space:]]+(dir|f)[[:space:]]+in[[:space:]]+.*agents" "$SYNC_SH" >/dev/null 2>&1 \
       && grep -F '*.md' "$SYNC_SH" >/dev/null 2>&1; then
      pass "INV-008(b)" "sync.sh has an agents loop and .md file glob (fallback matched)"
    else
      fail "INV-008(b)" "stale-file detection loop does not cover 'agents' with .md glob"
    fi
  fi

  # (c)/(d)/(e) Use PID-scoped sentinel names to avoid collisions; run
  # idempotent cleanup first; perform a sanity precheck that sync.sh --check
  # succeeds in the current state (skip if dirty); then test a stale dist file
  # and a stale source file (reverse direction).
  local sentinel_dist="correctless/agents/stale-test-sentinel-$$.md"
  local sentinel_src="agents/temp-sync-test-$$.md"

  # Idempotent cleanup of lingering sentinels from prior runs.
  rm -f correctless/agents/stale-test-sentinel-*.md 2>/dev/null || true
  rm -f agents/temp-sync-test-*.md 2>/dev/null || true

  cleanup_sync_sentinels() {
    rm -f "$sentinel_dist" 2>/dev/null || true
    rm -f "$sentinel_src" 2>/dev/null || true
  }
  trap cleanup_sync_sentinels EXIT

  # Sanity precheck: sync.sh --check should succeed right now. If it fails, the
  # test environment is already dirty — report that and skip the sentinel tests.
  if bash "$SYNC_SH" --check >/dev/null 2>&1; then
    pass "INV-008(c)" "bash sync.sh --check passes (sanity precheck — clean state)"
    local precheck_clean=1
  else
    fail "INV-008(c)" "bash sync.sh --check FAILS before any sentinel — environment already dirty"
    local precheck_clean=0
  fi

  if [ "$precheck_clean" = 1 ]; then
    # (d) Dist-side stale: write a sentinel under correctless/agents/ with no
    # matching source file. sync.sh --check should fail.
    mkdir -p correctless/agents 2>/dev/null || true
    if printf '# stale dist sentinel %s\n' "$$" > "$sentinel_dist" 2>/dev/null; then
      if bash "$SYNC_SH" --check >/dev/null 2>&1; then
        fail "INV-008(d)" "sync.sh --check PASSED with stale dist sentinel (should fail)"
      else
        pass "INV-008(d)" "sync.sh --check fails with stale dist sentinel (as expected)"
      fi
      rm -f "$sentinel_dist" 2>/dev/null || true
    else
      fail "INV-008(d)" "cannot create dist sentinel at $sentinel_dist"
    fi

    # (e) Reverse direction: source file with no matching dist. sync.sh --check
    # should fail (source → dist propagation gap).
    mkdir -p agents 2>/dev/null || true
    if printf '# temp source sentinel %s\n' "$$" > "$sentinel_src" 2>/dev/null; then
      if bash "$SYNC_SH" --check >/dev/null 2>&1; then
        fail "INV-008(e)" "sync.sh --check PASSED with source-only sentinel (should fail)"
      else
        pass "INV-008(e)" "sync.sh --check fails with source-only sentinel (as expected)"
      fi
      rm -f "$sentinel_src" 2>/dev/null || true
    else
      fail "INV-008(e)" "cannot create source sentinel at $sentinel_src"
    fi
  else
    skip "INV-008(d)" "stale dist sentinel test (precheck failed)"
    skip "INV-008(e)" "reverse-direction source sentinel test (precheck failed)"
  fi

  cleanup_sync_sentinels
  trap - EXIT
}

# ============================================================================
# INV-009: delegates to PRH-003 — no independent assertion. Comment only.
# ============================================================================

check_inv009() {
  section "INV-009: Fail-closed enforcement (delegates to PRH-003)"
  # No independent assertion: INV-009's enforcement is entirely PRH-003's
  # canonical marker + denylist. If PRH-003 passes, INV-009 passes.
  pass "INV-009" "delegates to PRH-003 (no independent check)"
}

# ============================================================================
# INV-010: Agent file carries dogfood marker; marker's spec path resolves.
# ============================================================================

check_inv010() {
  section "INV-010: Dogfood marker with resolvable spec reference"
  if [ ! -f "$AGENT_SRC" ]; then
    fail "INV-010" "$AGENT_SRC does not exist"
    return
  fi
  if grep -qF "$EXPECTED_DOGFOOD_MARKER" "$AGENT_SRC"; then
    pass "INV-010(a)" "dogfood marker literal present"
  else
    fail "INV-010(a)" "dogfood marker literal missing"
    return
  fi
  # A04: Extract spec path from the actual marker text via sed instead of
  # hardcoding. Grabs `See <path>` component up to ` -->` or end of line.
  local marker_line extracted_path
  marker_line="$(grep -F "Dogfood prototype" "$AGENT_SRC" | head -n 1)"
  extracted_path="$(printf '%s' "$marker_line" | sed -n 's/.*See[[:space:]]\+\([^ ]\+\.md\).*/\1/p' | head -n 1)"
  if [ -z "$extracted_path" ]; then
    fail "INV-010(b)" "cannot extract spec path from dogfood marker line"
  elif [ -f "$extracted_path" ]; then
    pass "INV-010(b)" "dogfood marker spec reference resolves ($extracted_path)"
  else
    fail "INV-010(b)" "dogfood marker spec reference does not resolve ($extracted_path)"
  fi
}

# ============================================================================
# INV-011: ABS-010 and ENV-007 in ARCHITECTURE.md.
# ============================================================================

check_inv011() {
  section "INV-011: ABS-010 and ENV-007 in ARCHITECTURE.md"
  if [ ! -f "$ARCH_FILE" ]; then
    fail "INV-011" "$ARCH_FILE not found"
    return
  fi
  if grep -qE '^### ABS-010:' "$ARCH_FILE"; then
    pass "INV-011(a)" "ARCHITECTURE.md has ### ABS-010: heading"
  else
    fail "INV-011(a)" "ARCHITECTURE.md missing ### ABS-010: heading"
  fi
  if grep -qE '^### ENV-007:' "$ARCH_FILE"; then
    pass "INV-011(b)" "ARCHITECTURE.md has ### ENV-007: heading"
  else
    fail "INV-011(b)" "ARCHITECTURE.md missing ### ENV-007: heading"
  fi

  # A05: Required sub-fields within 40 lines after each heading.
  local abs_body env_body
  abs_body="$(awk '
    /^### ABS-010:/ { in_block = 1; n = 0; next }
    in_block {
      n++
      if (n > 40) exit
      if (/^### / || /^## /) exit
      print
    }
  ' "$ARCH_FILE")"
  local sub missing_abs=""
  for sub in "Invariant" "Enforced at" "Violated when" "Test"; do
    if ! printf '%s\n' "$abs_body" | grep -qF "$sub"; then
      missing_abs="${missing_abs}${sub}, "
    fi
  done
  if [ -z "$missing_abs" ]; then
    pass "INV-011(a-subfields)" "ABS-010 section contains Invariant, Enforced at, Violated when, Test"
  else
    fail "INV-011(a-subfields)" "ABS-010 section missing sub-field(s): ${missing_abs%, }"
  fi

  env_body="$(awk '
    /^### ENV-007:/ { in_block = 1; n = 0; next }
    in_block {
      n++
      if (n > 40) exit
      if (/^### / || /^## /) exit
      print
    }
  ' "$ARCH_FILE")"
  local missing_env=""
  for sub in "Assumption" "Consequence if wrong" "Test"; do
    if ! printf '%s\n' "$env_body" | grep -qF "$sub"; then
      missing_env="${missing_env}${sub}, "
    fi
  done
  if [ -z "$missing_env" ]; then
    pass "INV-011(b-subfields)" "ENV-007 section contains Assumption, Consequence if wrong, Test"
  else
    fail "INV-011(b-subfields)" "ENV-007 section missing sub-field(s): ${missing_env%, }"
  fi
}

# ============================================================================
# INV-012: Test wired into tests/test.sh without exit-code swallowing + into
# workflow-config.json commands.test chain.
# ============================================================================

check_inv012() {
  section "INV-012: Test wired into runner without exit-code swallowing"

  if [ ! -f "$TEST_RUNNER" ]; then
    fail "INV-012" "$TEST_RUNNER not found"
    return
  fi

  # (a) The test filename is mentioned in tests/test.sh.
  local wired_ok=0
  if grep -nF 'test-fix-diff-reviewer-agent.sh' "$TEST_RUNNER" >/dev/null 2>&1; then
    pass "INV-012(a)" "test file wired into $TEST_RUNNER"
    wired_ok=1
  else
    fail "INV-012(a)" "test file NOT wired into $TEST_RUNNER"
  fi

  # B08: (b) only runs when (a) passed. Otherwise emit SKIP, never a false PASS.
  if [ "$wired_ok" -eq 1 ]; then
    local bad_line
    bad_line="$(grep -nF 'test-fix-diff-reviewer-agent.sh' "$TEST_RUNNER" 2>/dev/null | grep -E '\|\|[[:space:]]*(true|:)' || true)"
    if [ -z "$bad_line" ]; then
      pass "INV-012(b)" "no '|| true' or '|| :' on the test invocation line"
    else
      fail "INV-012(b)" "exit-code swallowing detected: $bad_line"
    fi
  else
    skip "INV-012(b)" "exit-code-swallowing check skipped (INV-012(a) failed — no invocation line to inspect)"
  fi

  # (c) Counter-increment idiom: near the invocation line, PASS=$((PASS+1))
  # and FAIL=$((FAIL+1)) should both appear within a small window.
  if awk '
    /test-fix-diff-reviewer-agent\.sh/ {
      seen = NR
    }
    seen && NR >= seen && NR <= seen + 8 {
      if ($0 ~ /PASS=\$\(\(PASS[[:space:]]*\+[[:space:]]*1\)\)/) have_pass = 1
      if ($0 ~ /FAIL=\$\(\(FAIL[[:space:]]*\+[[:space:]]*1\)\)/) have_fail = 1
    }
    END { exit ((have_pass && have_fail) ? 0 : 1) }
  ' "$TEST_RUNNER"; then
    pass "INV-012(c)" "counter-increment idiom (PASS and FAIL) present near invocation"
  else
    fail "INV-012(c)" "counter-increment idiom (PASS and FAIL) NOT present near invocation"
  fi

  # (d) workflow-config.json commands.test chain mentions the new test.
  if [ -f "$WORKFLOW_CONFIG" ]; then
    if grep -F 'test-fix-diff-reviewer-agent.sh' "$WORKFLOW_CONFIG" >/dev/null 2>&1; then
      pass "INV-012(d)" "$WORKFLOW_CONFIG commands.test chain includes the new test"
    else
      fail "INV-012(d)" "$WORKFLOW_CONFIG does not reference the new test"
    fi
  else
    fail "INV-012(d)" "$WORKFLOW_CONFIG not found"
  fi
}

# ============================================================================
# INV-013: VP-001 smoke test section (wrapped in SKIP when report absent).
# ============================================================================

check_inv013() {
  section "INV-013: VP-001 smoke-test section (wrapped in SKIP)"

  if [ ! -f "$VERIFY_REPORT" ]; then
    skip "INV-013" "VP-001 assertions (run /cverify first): $VERIFY_REPORT"
    return
  fi

  # (a) ## VP-001: Smoke Test heading + Result: PASS within 20 lines.
  if awk '
    /^## VP-001: Smoke Test/ { in_section = 1; count = 0; next }
    in_section {
      count++
      if (count > 20) exit 1
      if ($0 ~ /Result:[[:space:]]*PASS/) { found = 1; exit 0 }
    }
    END { exit (found ? 0 : 1) }
  ' "$VERIFY_REPORT"; then
    pass "INV-013(a)" "VP-001 'Result: PASS' within 20 lines of heading"
  else
    fail "INV-013(a)" "VP-001 heading or 'Result: PASS' within 20 lines missing"
  fi

  # (b) ### Response block contains the dogfood fingerprint substring.
  if awk '
    /^## VP-001:/ { in_section = 1; next }
    in_section && /^## / { exit }
    in_section && /^### Response/ { in_resp = 1; next }
    in_section && in_resp && /^### / { in_resp = 0 }
    in_section && in_resp {
      if (index($0, "Dogfood prototype (2026-04-10): fix-diff-reviewer-migration") > 0) {
        found = 1
        exit 0
      }
    }
    END { exit (found ? 0 : 1) }
  ' "$VERIFY_REPORT"; then
    pass "INV-013(b)" "VP-001 Response contains dogfood fingerprint substring"
  else
    fail "INV-013(b)" "VP-001 Response missing dogfood fingerprint substring"
  fi

  # (c) ### Tool Enumeration contains Read, Grep, Glob and no forbidden tools.
  local tool_block
  tool_block="$(awk '
    /^## VP-001:/ { in_section = 1; next }
    in_section && /^## / { exit }
    in_section && /^### Tool Enumeration/ { in_tools = 1; next }
    in_section && in_tools && /^### / { exit }
    in_section && in_tools { print }
  ' "$VERIFY_REPORT")"
  if [ -n "$tool_block" ]; then
    # A06: extract every capitalised token that looks like a tool name, sort
    # unique, require exact set-equality with {Glob, Grep, Read}.
    local enumerated expected
    enumerated="$(printf '%s\n' "$tool_block" | grep -oE '\b(Read|Grep|Glob|Write|Edit|MultiEdit|NotebookEdit|Task|Bash|WebFetch|WebSearch)\b' | sort -u)"
    expected="$(printf 'Glob\nGrep\nRead\n')"
    if [ "$enumerated" = "$expected" ]; then
      pass "INV-013(c)" "VP-001 tool enumeration set-equal to {Read, Grep, Glob}"
    else
      local actual_compact
      actual_compact="$(printf '%s' "$enumerated" | tr '\n' ',' | sed 's/,$//')"
      fail "INV-013(c)" "VP-001 tool enumeration is {$actual_compact}, expected exactly {Glob,Grep,Read}"
    fi
  else
    fail "INV-013(c)" "VP-001 '### Tool Enumeration' subsection missing"
  fi
}

# ============================================================================
# INV-014: caudit's allowed-tools frontmatter includes Task.
# ============================================================================

check_inv014() {
  section "INV-014: caudit allowed-tools includes Task (AP-008 cross-check)"
  if [ ! -f "$CAUDIT_SKILL" ]; then
    fail "INV-014" "$CAUDIT_SKILL does not exist"
    return
  fi
  local tools
  tools="$(parse_allowed_tools "$CAUDIT_SKILL" 2>/dev/null)" || {
    fail "INV-014" "cannot parse allowed-tools from caudit frontmatter"
    return
  }
  if [ -z "$tools" ]; then
    fail "INV-014" "caudit allowed-tools must use comma-flow form per EA-006 (parse returned empty — block-style detected)"
    return
  fi
  # B10: explicit allowlist. Accept exactly one of:
  #   - Task
  #   - Task(*)
  #   - Task(correctless:fix-diff-reviewer)
  local found_ok=0
  local bad_form=""
  while IFS= read -r t; do
    [ -z "$t" ] && continue
    case "$t" in
      Task|'Task(*)'|'Task(correctless:fix-diff-reviewer)')
        found_ok=1
        ;;
      Task\(*)
        bad_form="${bad_form}${t}, "
        ;;
    esac
  done <<< "$tools"
  if [ "$found_ok" -eq 1 ] && [ -z "$bad_form" ]; then
    pass "INV-014" "caudit allowed-tools contains an allowed Task form (bare, wildcard, or namespaced fix-diff-reviewer)"
  elif [ "$found_ok" -eq 1 ]; then
    fail "INV-014" "caudit allowed-tools contains an allowed Task form, but ALSO disallowed sub-pattern(s): ${bad_form%, }"
  elif [ -n "$bad_form" ]; then
    fail "INV-014" "caudit allowed-tools contains disallowed Task sub-pattern(s): ${bad_form%, } (allowed: Task, Task(*), Task(correctless:fix-diff-reviewer))"
  else
    fail "INV-014" "caudit allowed-tools does NOT contain any Task form"
  fi
}

# ============================================================================
# INV-015: UNTRUSTED_DIFF fence + data-treatment clause in agent body.
# ============================================================================

check_inv015() {
  section "INV-015: UNTRUSTED_DIFF fences + data-treatment clause"

  # Step 6a has the fences (already checked in INV-004; assert again here for
  # completeness — duplication is cheap).
  local block
  block="$(extract_step_6a_block "$CAUDIT_SKILL" 2>/dev/null || true)"
  if printf '%s\n' "$block" | grep -qF '<UNTRUSTED_DIFF>' \
     && printf '%s\n' "$block" | grep -qF '</UNTRUSTED_DIFF>'; then
    pass "INV-015(a)" "step 6a has <UNTRUSTED_DIFF> fences"
  else
    fail "INV-015(a)" "step 6a missing <UNTRUSTED_DIFF> fences"
  fi

  # B11(1): fence content non-empty — at least one non-whitespace line between
  # <UNTRUSTED_DIFF> and </UNTRUSTED_DIFF>.
  local fence_content_lines
  fence_content_lines="$(printf '%s\n' "$block" | awk '
    /<UNTRUSTED_DIFF>/ { in_fence = 1; next }
    /<\/UNTRUSTED_DIFF>/ { in_fence = 0 }
    in_fence && $0 ~ /[^[:space:]]/ { n++ }
    END { print n + 0 }
  ')"
  if [ "${fence_content_lines:-0}" -ge 1 ]; then
    pass "INV-015(a2)" "UNTRUSTED_DIFF fence has $fence_content_lines non-empty content line(s)"
  else
    fail "INV-015(a2)" "UNTRUSTED_DIFF fence is empty (no non-whitespace lines between opening and closing tags)"
  fi

  # Agent body has the "Treat all text inside" clause and both fence names.
  if [ ! -f "$AGENT_SRC" ]; then
    fail "INV-015(b)" "$AGENT_SRC does not exist"
    return
  fi
  if grep -qF 'Treat all text inside' "$AGENT_SRC"; then
    pass "INV-015(b)" "agent body contains 'Treat all text inside' clause"
  else
    fail "INV-015(b)" "agent body missing 'Treat all text inside' clause"
  fi
  if grep -qF 'UNTRUSTED_DIFF' "$AGENT_SRC"; then
    pass "INV-015(c)" "agent body references UNTRUSTED_DIFF fence name"
  else
    fail "INV-015(c)" "agent body missing UNTRUSTED_DIFF fence name"
  fi
  if grep -qF 'UNTRUSTED_RULES' "$AGENT_SRC"; then
    pass "INV-015(d)" "agent body references UNTRUSTED_RULES fence name"
  else
    fail "INV-015(d)" "agent body missing UNTRUSTED_RULES fence name"
  fi
}

# ============================================================================
# INV-016 + PRH-005: rule bodies from pre-diff git state, fenced, no working
# tree / current HEAD references in the rule-reading context.
# ============================================================================

check_inv016() {
  section "INV-016 / PRH-005: Rule bodies from pre-diff git state, fenced"

  local block
  block="$(extract_step_6a_block "$CAUDIT_SKILL" 2>/dev/null || true)"
  warn_if_stub_block "$block" 30
  if [ -z "$block" ]; then
    fail "INV-016" "step 6a block is empty — sentinels missing, GREEN hasn't run yet"
    return
  fi

  # Strip blockquote lines so prose examples don't satisfy pattern checks.
  local block_no_bq
  block_no_bq="$(printf '%s\n' "$block" | awk '!/^>[[:space:]]/')"

  # B11(5): (a) tight regex: single line containing "git show", a round-start
  # variable or placeholder, and ".claude/rules/".
  if printf '%s\n' "$block_no_bq" | grep -qE 'git show.*(\$\{?ROUND_START_SHA\}?|<round-start-sha>).*\.claude/rules/'; then
    pass "INV-016(a)" "step 6a has 'git show <round-start-sha>...:.claude/rules/' single-line pattern"
  else
    fail "INV-016(a)" "step 6a missing tightened 'git show <round-start-sha>:.claude/rules/' single-line pattern"
  fi

  # G04: ROUND_START_SHA= variable assignment must appear BEFORE the first
  # `git show ... .claude/rules/` line.
  local ordering_ok
  ordering_ok="$(printf '%s\n' "$block_no_bq" | awk '
    BEGIN { assign_ln = 0; show_ln = 0 }
    /^[[:space:]]*(ROUND_START_SHA|round_start_sha)[[:space:]]*=/ {
      if (assign_ln == 0) assign_ln = NR
    }
    /git show/ && /\.claude\/rules\// {
      if (show_ln == 0) show_ln = NR
    }
    END {
      if (assign_ln > 0 && show_ln > 0 && assign_ln < show_ln) print "ok"
      else if (assign_ln == 0) print "no_assign"
      else if (show_ln == 0) print "no_show"
      else print "wrong_order"
    }
  ')"
  case "$ordering_ok" in
    ok)
      pass "INV-016(a-order)" "ROUND_START_SHA= assignment precedes first 'git show .claude/rules/' line"
      ;;
    no_assign)
      fail "INV-016(a-order)" "step 6a missing a ROUND_START_SHA= variable assignment"
      ;;
    no_show)
      fail "INV-016(a-order)" "step 6a has no 'git show .claude/rules/' line"
      ;;
    wrong_order|*)
      fail "INV-016(a-order)" "ROUND_START_SHA= assignment does not precede first 'git show .claude/rules/' line ($ordering_ok)"
      ;;
  esac

  # (b) <UNTRUSTED_RULES> fences present.
  if printf '%s\n' "$block" | grep -qF '<UNTRUSTED_RULES>' \
     && printf '%s\n' "$block" | grep -qF '</UNTRUSTED_RULES>'; then
    pass "INV-016(b)" "step 6a has <UNTRUSTED_RULES> fences"
  else
    fail "INV-016(b)" "step 6a missing <UNTRUSTED_RULES> fences"
  fi

  # (c1/c2) B02: belt-and-suspenders — neither the extracted block NOR the
  # whole caudit file (minus the 'Why fix verification is mandatory' narrative
  # section) may contain 'working tree' or 'current HEAD'.
  local file_minus
  file_minus="$(extract_caudit_minus_narrative "$CAUDIT_SKILL" 2>/dev/null || true)"

  local wt_block=0 wt_file=0
  if printf '%s\n' "$block" | grep -qiF 'working tree'; then wt_block=1; fi
  if printf '%s\n' "$file_minus" | grep -qiF 'working tree'; then wt_file=1; fi
  if [ "$wt_block" -eq 0 ] && [ "$wt_file" -eq 0 ]; then
    pass "INV-016(c1)" "neither block nor whole-file-minus-narrative contains 'working tree'"
  else
    fail "INV-016(c1)" "'working tree' present (block=$wt_block, file-minus-narrative=$wt_file)"
  fi

  local ch_block=0 ch_file=0
  if printf '%s\n' "$block" | grep -qiF 'current HEAD'; then ch_block=1; fi
  if printf '%s\n' "$file_minus" | grep -qiF 'current HEAD'; then ch_file=1; fi
  if [ "$ch_block" -eq 0 ] && [ "$ch_file" -eq 0 ]; then
    pass "INV-016(c2)" "neither block nor whole-file-minus-narrative contains 'current HEAD'"
  else
    fail "INV-016(c2)" "'current HEAD' present (block=$ch_block, file-minus-narrative=$ch_file)"
  fi
}

# ============================================================================
# INV-017: agent body says "Return ONLY the JSON array"; caudit uses `jq -e .`.
# ============================================================================

check_inv017() {
  section "INV-017: JSON envelope contract + jq -e . parsing"

  if [ ! -f "$AGENT_SRC" ]; then
    fail "INV-017(a)" "$AGENT_SRC does not exist"
    fail "INV-017(schema)" "$AGENT_SRC does not exist — cannot check DD-009 schema fields"
  else
    if grep -qF 'Return ONLY the JSON array' "$AGENT_SRC"; then
      pass "INV-017(a)" "agent body contains 'Return ONLY the JSON array' clause"
    else
      fail "INV-017(a)" "agent body missing 'Return ONLY the JSON array' clause"
    fi

    # B04 / G01: all 9 DD-009 schema field names must appear in the agent body.
    local field missing_fields=""
    for field in id severity title description evidence impact location instance_fix class_fix; do
      if ! grep -qF "$field" "$AGENT_SRC"; then
        missing_fields="${missing_fields}${field}, "
      fi
    done
    if [ -z "$missing_fields" ]; then
      pass "INV-017(schema-fields)" "agent body contains all 9 DD-009 schema field names"
    else
      fail "INV-017(schema-fields)" "agent body missing DD-009 schema field(s): ${missing_fields%, }"
    fi

    # All 4 severity enum values.
    local sev missing_sev=""
    for sev in critical high medium low; do
      if ! grep -qF "$sev" "$AGENT_SRC"; then
        missing_sev="${missing_sev}${sev}, "
      fi
    done
    if [ -z "$missing_sev" ]; then
      pass "INV-017(schema-severity)" "agent body contains all 4 severity enum values"
    else
      fail "INV-017(schema-severity)" "agent body missing severity enum(s): ${missing_sev%, }"
    fi

    # FD- id prefix convention.
    if grep -qE 'FD-[0-9]+|FD-NNN' "$AGENT_SRC"; then
      pass "INV-017(schema-idprefix)" "agent body documents the FD-<number> id prefix convention"
    else
      fail "INV-017(schema-idprefix)" "agent body missing FD-<number> id prefix convention"
    fi

    # location: {file, lines} proximity check — all three tokens within 200
    # characters on a single-line-squashed view.
    local squashed
    squashed="$(tr '\n' ' ' < "$AGENT_SRC")"
    if printf '%s' "$squashed" | grep -qE 'location[^a-zA-Z0-9]{1,200}file[^a-zA-Z0-9]{1,200}lines|location[^a-zA-Z0-9]{1,200}lines[^a-zA-Z0-9]{1,200}file'; then
      pass "INV-017(schema-location)" "agent body describes location: {file, lines} shape within 200 chars"
    else
      fail "INV-017(schema-location)" "agent body missing location/file/lines proximity description"
    fi
  fi

  local block
  block="$(extract_step_6a_block "$CAUDIT_SKILL" 2>/dev/null || true)"
  # B05 / G05: anchored identity-parse regex. `jq -e .` must be followed by a
  # whitespace, EOL, quote, or '$' — not by a filter like `.findings` or `.[0]`.
  if printf '%s\n' "$block" | grep -qE '(^|[^[:alnum:]._-])jq -e \.([[:space:]"'"'"'$]|$)'; then
    pass "INV-017(b)" "step 6a has anchored 'jq -e .' identity-parse invocation"
    # Additionally require the matching line contains a $, <<<, or | (so the
    # identity parse is consuming actual input, not just a comment).
    if printf '%s\n' "$block" | grep -E '(^|[^[:alnum:]._-])jq -e \.([[:space:]"'"'"'$]|$)' | grep -qE '\$|<<<|\|'; then
      pass "INV-017(b2)" "'jq -e .' line references input via \$var / <<< / pipe"
    else
      fail "INV-017(b2)" "'jq -e .' line has no input adjacency (\$var, <<<, or pipe) — likely a comment"
    fi
  else
    fail "INV-017(b)" "step 6a missing anchored 'jq -e .' identity parse"
  fi
  # Negative: `jq -e .findings`, `jq -e .[0]` etc. are filters, not identity.
  if printf '%s\n' "$block" | grep -qE 'jq -e \.[a-zA-Z\[]'; then
    fail "INV-017(b3)" "step 6a contains filter-form 'jq -e .<name>' or 'jq -e .[...]' (identity parse required)"
  else
    pass "INV-017(b3)" "no filter-form 'jq -e .<name>' / 'jq -e .[...]' in step 6a"
  fi
}

# ============================================================================
# INV-018: DD-008 rule-scan instructions in step 6a.
# ============================================================================

check_producer_consumer_closure() {
  section "Producer-consumer closure: ROUND_START_SHA has an assignment before its read"

  # QA-002 class fix: any variable consumed inside step 6a (ROUND_START_SHA,
  # etc.) must be PRODUCED (assigned or git-ref'd into existence) somewhere
  # earlier in caudit SKILL.md. Searches the whole file — the producer may
  # live outside the step 6a sentinel block (e.g., at the top of The Loop).
  # The test is: find at least one producer for `refs/audit-round-${ROUND_N}-start`
  # (the ref the consumer reads via git rev-parse) OR a direct assignment
  # of ROUND_START_SHA from a non-rev-parse source, AND that producer's line
  # number must precede the consumer's line number.
  if [ ! -f "$CAUDIT_SKILL" ]; then
    fail "PRODUCER-CONSUMER" "$CAUDIT_SKILL does not exist"
    return
  fi

  local producer_ln consumer_ln
  # Producer forms (any of):
  #   git update-ref "refs/audit-round-${ROUND_N}-start" HEAD
  #   git update-ref refs/audit-round-${ROUND_N}-start HEAD
  #   ROUND_START_SHA=$(...)  — non rev-parse assignment of the var
  producer_ln="$(grep -nE 'git[[:space:]]+update-ref.*refs/audit-round-\$\{?ROUND_N\}?-start' "$CAUDIT_SKILL" | head -n 1 | cut -d: -f1)"
  consumer_ln="$(grep -nE 'ROUND_START_SHA=.*git[[:space:]]+rev-parse.*refs/audit-round' "$CAUDIT_SKILL" | head -n 1 | cut -d: -f1)"

  if [ -z "$producer_ln" ]; then
    fail "PRODUCER-CONSUMER(a)" "no producer for 'refs/audit-round-\${ROUND_N}-start' found in $CAUDIT_SKILL (expected 'git update-ref refs/audit-round-\${ROUND_N}-start HEAD')"
    return
  fi
  pass "PRODUCER-CONSUMER(a)" "producer 'git update-ref refs/audit-round-\${ROUND_N}-start' present at line $producer_ln"

  if [ -z "$consumer_ln" ]; then
    fail "PRODUCER-CONSUMER(b)" "no consumer 'ROUND_START_SHA=\$(git rev-parse refs/audit-round-...)' found"
    return
  fi
  pass "PRODUCER-CONSUMER(b)" "consumer ROUND_START_SHA rev-parse present at line $consumer_ln"

  if [ "$producer_ln" -lt "$consumer_ln" ]; then
    pass "PRODUCER-CONSUMER(c)" "producer (line $producer_ln) precedes consumer (line $consumer_ln)"
  else
    fail "PRODUCER-CONSUMER(c)" "producer (line $producer_ln) does NOT precede consumer (line $consumer_ln)"
  fi
}

check_inv018() {
  section "INV-018: DD-008 rule-scan instructions in step 6a"

  local block
  block="$(extract_step_6a_block "$CAUDIT_SKILL" 2>/dev/null || true)"
  warn_if_stub_block "$block" 30
  if [ -z "$block" ]; then
    fail "INV-018" "step 6a block is empty — sentinels missing, GREEN hasn't run yet"
    return
  fi

  # Strip blockquote lines so prose examples can't satisfy checks.
  local block_no_bq
  block_no_bq="$(printf '%s\n' "$block" | awk '!/^>[[:space:]]/')"

  # NOTE (QA-003 class fix): order-matters assertions use strict state
  # machines (`idx == N-1`) not monotonic-advance (`idx < N`) to prevent
  # pattern-4 being skipped when pattern-5 lines match first. With the
  # weak `idx < N` form, a later pattern's line can advance the index
  # past earlier patterns, falsely passing the ordering check even though
  # earlier patterns never matched in-order.
  #
  # Canonical order for step 6a (mirrors the actual SKILL.md layout):
  #   1. .claude/rules/      (rule enumeration directive)
  #   2. paths:               (frontmatter field being parsed)
  #   3. git show             (pre-diff state read)
  #   4. Path-scoped rules applying to this diff  (fence section heading)
  #   5. <UNTRUSTED_RULES>    (the fence itself)
  local patterns=(
    '.claude/rules/'
    'paths:'
    'git show'
    'Path-scoped rules applying to this diff'
    '<UNTRUSTED_RULES>'
  )
  local p
  for p in "${patterns[@]}"; do
    if printf '%s\n' "$block_no_bq" | grep -qF "$p"; then
      pass "INV-018:$p" "step 6a contains '$p'"
    else
      fail "INV-018:$p" "step 6a missing '$p'"
    fi
  done

  # B11(2): pattern ordering — the 5 patterns must appear in sequence in the
  # order listed. Strict-next-step state machine: each pattern N can only
  # advance idx when idx is exactly N-1 (not "below N"). This prevents a
  # later-listed pattern from skipping earlier ones.
  local ordering_ok
  ordering_ok="$(printf '%s\n' "$block_no_bq" | awk '
    BEGIN { idx = 0 }
    {
      # Strict next-step: each pattern only fires when idx == its position - 1.
      if (idx == 0 && index($0, ".claude/rules/") > 0) { idx = 1; next }
      if (idx == 1 && index($0, "paths:") > 0) { idx = 2; next }
      if (idx == 2 && index($0, "git show") > 0) { idx = 3; next }
      if (idx == 3 && index($0, "Path-scoped rules applying to this diff") > 0) { idx = 4; next }
      if (idx == 4 && index($0, "<UNTRUSTED_RULES>") > 0) { idx = 5; next }
    }
    END { print idx }
  ')"
  if [ "${ordering_ok:-0}" -ge 5 ]; then
    pass "INV-018(order)" "all 5 patterns appear in the required order (strict state machine)"
  else
    fail "INV-018(order)" "only $ordering_ok of 5 patterns matched in strict order (pattern sequence broken)"
  fi

  # G07: a parser reference for the `paths:` frontmatter must appear.
  # Accept yq, awk-with-paths, or grep-with-paths.
  if printf '%s\n' "$block_no_bq" | grep -qE 'yq|awk[[:space:]].*paths|grep[[:space:]].*paths:'; then
    pass "INV-018(parser)" "step 6a references a paths: frontmatter parser (yq / awk / grep)"
  else
    fail "INV-018(parser)" "step 6a missing a paths: frontmatter parser reference"
  fi
}

# ============================================================================
# INV-019: Reviewer system prompt forbids verbatim file content.
# ============================================================================

check_inv019() {
  section "INV-019: No verbatim file content in finding prose"

  if [ ! -f "$AGENT_SRC" ]; then
    fail "INV-019" "$AGENT_SRC does not exist"
    return
  fi
  if grep -qF 'Do not include file contents verbatim' "$AGENT_SRC"; then
    pass "INV-019" "agent body contains 'Do not include file contents verbatim' clause"
  else
    fail "INV-019" "agent body missing 'Do not include file contents verbatim' clause"
  fi
}

# ============================================================================
# PRH-001: covered by INV-006. Cross-reference comment only.
# ============================================================================

check_prh001() {
  section "PRH-001: No inline fix-diff-reviewer prompt (see INV-006)"
  # PRH-001's denylist is identical to INV-006(b). No independent assertion.
  pass "PRH-001" "covered by INV-006(a)+(b)"
}

# ============================================================================
# PRH-002: No write tools in agent frontmatter (source AND distribution).
# ============================================================================

check_prh002_for() {
  local file="$1" label="$2"
  if [ ! -f "$file" ]; then
    fail "PRH-002($label)" "$file does not exist"
    return
  fi
  local tools
  tools="$(parse_tools_list "$file" 2>/dev/null)" || {
    fail "PRH-002($label)" "$file has no parseable tools list"
    return
  }
  local forbidden hits
  forbidden="Write Edit MultiEdit NotebookEdit Task"
  hits=""
  for f in $forbidden; do
    if printf '%s\n' "$tools" | grep -qw "$f"; then
      hits="$hits $f"
    fi
  done
  if [ -z "$hits" ]; then
    pass "PRH-002($label)" "no forbidden tools ({Write,Edit,MultiEdit,NotebookEdit,Task}) in tools list"
  else
    fail "PRH-002($label)" "forbidden tools present:$hits"
  fi
}

check_prh002() {
  section "PRH-002: No write/escalation tools in agent frontmatter"
  check_prh002_for "$AGENT_SRC" "source"
  check_prh002_for "$AGENT_DIST" "dist"
}

# ============================================================================
# PRH-003: Fail-closed canonical marker — cardinality, invocation, proximity,
# denylist.
# ============================================================================

check_prh003() {
  section "PRH-003: Fail-closed canonical marker (cardinality=1, proximity, denylist)"

  if [ ! -f "$CAUDIT_SKILL" ]; then
    fail "PRH-003" "$CAUDIT_SKILL does not exist"
    return
  fi

  # (a) Cardinality: exact one occurrence in the whole file.
  local marker_count
  marker_count="$(grep -cF "$EXPECTED_CANONICAL_MARKER" "$CAUDIT_SKILL" 2>/dev/null)" || marker_count=0
  marker_count="${marker_count:-0}"
  if [ "$marker_count" -eq 1 ]; then
    pass "PRH-003(a)" "canonical marker appears exactly once in $CAUDIT_SKILL"
  else
    fail "PRH-003(a)" "canonical marker appears $marker_count time(s) in $CAUDIT_SKILL (expected exactly 1)"
  fi

  # (b) Invocation presence: exactly one namespaced Task invocation inside
  # the step 6a block.
  local block
  block="$(extract_step_6a_block "$CAUDIT_SKILL" 2>/dev/null || true)"
  local inv_count
  inv_count="$(printf '%s\n' "$block" | grep -cF "$EXPECTED_NAMESPACED_TASK" 2>/dev/null)" || inv_count=0
  inv_count="${inv_count:-0}"
  if [ "$inv_count" -eq 1 ]; then
    pass "PRH-003(b)" "exactly one namespaced Task invocation in step 6a block"
  else
    fail "PRH-003(b)" "$inv_count namespaced Task invocations in step 6a block (expected exactly 1)"
  fi

  # (c) Proximity: canonical marker and namespaced Task invocation both within
  # step 6a block AND within 50 lines of each other.
  if [ -n "$block" ]; then
    if printf '%s\n' "$block" | grep -qF "$EXPECTED_CANONICAL_MARKER"; then
      # Compute line numbers within block.
      local marker_ln inv_ln
      marker_ln="$(printf '%s\n' "$block" | grep -nF "$EXPECTED_CANONICAL_MARKER" | head -n 1 | cut -d: -f1)"
      inv_ln="$(printf '%s\n' "$block" | grep -nF "$EXPECTED_NAMESPACED_TASK" | head -n 1 | cut -d: -f1)"
      if [ -n "$marker_ln" ] && [ -n "$inv_ln" ]; then
        local delta
        if [ "$marker_ln" -gt "$inv_ln" ]; then
          delta=$((marker_ln - inv_ln))
        else
          delta=$((inv_ln - marker_ln))
        fi
        if [ "$delta" -le 50 ]; then
          pass "PRH-003(c)" "marker and invocation both in step 6a, $delta lines apart (<=50)"
        else
          fail "PRH-003(c)" "marker and invocation $delta lines apart (>50)"
        fi
      else
        fail "PRH-003(c)" "cannot locate marker/invocation line numbers in step 6a block"
      fi
    else
      fail "PRH-003(c)" "canonical marker not found within step 6a block"
    fi
  else
    fail "PRH-003(c)" "step 6a block empty or unavailable"
  fi

  # (d) Denylist: step 6a AND whole-file-minus-narrative must NOT contain any
  # paraphrase phrase (B02 belt-and-suspenders).
  local denylist=(
    "skip the round"
    "continue anyway"
    "fallback to inline"
    "warn and proceed"
    "silently ignore"
    "best effort"
    "if unavailable continue"
    "logs a warning and continues"
    "records telemetry and proceeds"
  )
  local block_hits=0 file_hits=0
  local file_minus
  file_minus="$(extract_caudit_minus_narrative "$CAUDIT_SKILL" 2>/dev/null || true)"
  for phrase in "${denylist[@]}"; do
    if [ -n "$block" ] && printf '%s\n' "$block" | grep -qiF "$phrase"; then
      block_hits=$((block_hits + 1))
    fi
    if printf '%s\n' "$file_minus" | grep -qiF "$phrase"; then
      file_hits=$((file_hits + 1))
    fi
  done
  if [ "$block_hits" -eq 0 ] && [ "$file_hits" -eq 0 ]; then
    pass "PRH-003(d)" "no denylist paraphrase phrases in step 6a or whole-file-minus-narrative"
  else
    fail "PRH-003(d)" "denylist hits — block=$block_hits, file-minus-narrative=$file_hits"
  fi
}

# ============================================================================
# PRH-004: Phase 2b scope not included. Advisory — enforced via PR review,
# not structural check. Comment only, no failing assertion.
# ============================================================================

check_prh004() {
  section "PRH-004: Phase 2b scope exclusion (advisory, enforced via PR review)"
  pass "PRH-004" "advisory — enforced via PR diff review, not structural check"
}

# ============================================================================
# PRH-005: covered by INV-016. Comment only.
# ============================================================================

check_prh005() {
  section "PRH-005: Rule bodies fenced + pre-diff state (see INV-016)"
  pass "PRH-005" "covered by INV-016(a)(b)(c1)(c2)"
}

# ============================================================================
# BND-001: delegates to PRH-003. Comment only.
# ============================================================================

check_bnd001() {
  section "BND-001: Subagent unavailability (delegates to PRH-003)"
  pass "BND-001" "delegates to PRH-003 canonical marker + denylist"
}

# ============================================================================
# BND-002: configurable zero-findings threshold documented in step 6a.
# ============================================================================

check_bnd002() {
  section "BND-002: Configurable audit.zero_findings_threshold key"
  local block
  block="$(extract_step_6a_block "$CAUDIT_SKILL" 2>/dev/null || true)"
  if printf '%s\n' "$block" | grep -qF 'audit.zero_findings_threshold'; then
    pass "BND-002(a)" "step 6a documents 'audit.zero_findings_threshold' config key"
  else
    fail "BND-002(a)" "step 6a missing 'audit.zero_findings_threshold' config key reference"
  fi
  # A07: the key must be used in a jq/json/config-read context, not a bare
  # comment. Find the line(s) referencing the key and require adjacency to
  # jq, json, or a config-path reference.
  local used_line
  used_line="$(printf '%s\n' "$block" | grep -F 'audit.zero_findings_threshold' | grep -E 'jq|json|config|\.correctless/config|workflow-config' | head -n 1 || true)"
  if [ -n "$used_line" ]; then
    pass "BND-002(b)" "'audit.zero_findings_threshold' is used adjacent to jq/json/config context"
  else
    fail "BND-002(b)" "'audit.zero_findings_threshold' only appears as bare mention (no jq/json/config adjacency)"
  fi

  # QA-001 class fix: BND-002 is a LINES-CHANGED threshold with default 50,
  # not a findings-count threshold. Assert three things structurally:
  #   (c) numeric `50` (or literal `// 50` jq default) within ~20 chars of
  #       `audit.zero_findings_threshold`
  #   (d) the word `lines` within 40 chars of the key (semantic binding —
  #       rejects findings-count paraphrases)
  #   (e) an artifact-write instruction referencing `audit-trail` and
  #       `zero_findings_on_nontrivial_diff`

  # (c) default value 50 within 20 chars of the key. Accept `// 50`,
  # `default 50`, `50 lines`, etc.
  if printf '%s\n' "$block" | grep -qE 'audit\.zero_findings_threshold.{0,20}(//[[:space:]]*)?50|50.{0,20}audit\.zero_findings_threshold'; then
    pass "BND-002(c)" "default value '50' is within 20 chars of 'audit.zero_findings_threshold'"
  else
    fail "BND-002(c)" "default value '50' not adjacent (<=20 chars) to 'audit.zero_findings_threshold'"
  fi

  # (d) semantic binding to `lines` within 40 chars of the key. Rejects
  # findings-count paraphrases like "how many new fix-diff findings".
  if printf '%s\n' "$block" | grep -qE 'audit\.zero_findings_threshold.{0,40}lines|lines.{0,40}audit\.zero_findings_threshold'; then
    pass "BND-002(d)" "'lines' appears within 40 chars of 'audit.zero_findings_threshold' (semantic binding)"
  else
    fail "BND-002(d)" "'lines' not adjacent (<=40 chars) to 'audit.zero_findings_threshold' — rejects findings-count paraphrases"
  fi

  # (e) forensic-logging block must reference audit-trail artifact AND the
  # zero_findings_on_nontrivial_diff flag somewhere in step 6a.
  if printf '%s\n' "$block" | grep -qF 'audit-trail' && \
     printf '%s\n' "$block" | grep -qF 'zero_findings_on_nontrivial_diff'; then
    pass "BND-002(e)" "forensic-logging block references 'audit-trail' and 'zero_findings_on_nontrivial_diff'"
  else
    fail "BND-002(e)" "step 6a missing audit-trail artifact write or 'zero_findings_on_nontrivial_diff' flag (forensic logging)"
  fi
}

# ============================================================================
# BND-003: fixture .diff files exist, non-empty, match pinned SHA-256 hashes.
# ============================================================================

check_bnd003() {
  section "BND-003: Historical replay fixtures exist with pinned SHA-256"

  local all_present=1
  local f
  for f in "$FIXTURE_R1" "$FIXTURE_R2" "$FIXTURE_R3"; do
    if [ ! -f "$f" ]; then
      fail "BND-003(exists:$f)" "$f does not exist"
      all_present=0
    elif [ ! -s "$f" ]; then
      fail "BND-003(nonempty:$f)" "$f is empty"
      all_present=0
    else
      pass "BND-003(exists:$f)" "$f exists and is non-empty"
      # B07(2): each .diff >= 500 bytes.
      local sz
      sz="$(wc -c < "$f" 2>/dev/null || echo 0)"
      if [ "${sz:-0}" -ge 500 ]; then
        pass "BND-003(size:$f)" "$f is $sz bytes (>=500)"
      else
        fail "BND-003(size:$f)" "$f is $sz bytes (<500)"
      fi
      # B07(3): first line matches `^diff --git `.
      if head -n 1 "$f" 2>/dev/null | grep -qE '^diff --git '; then
        pass "BND-003(git:$f)" "$f starts with 'diff --git '"
      else
        fail "BND-003(git:$f)" "$f does not start with 'diff --git '"
      fi
    fi
  done

  if [ ! -f "$FIXTURE_META" ]; then
    fail "BND-003(meta)" "$FIXTURE_META does not exist"
    return
  fi
  pass "BND-003(meta)" "$FIXTURE_META exists"

  # B07(4): metadata file must reference all three spec SHAs.
  local spec_sha missing_spec=""
  for spec_sha in 9d61920 2824387 6c0d919; do
    if ! grep -qF "$spec_sha" "$FIXTURE_META"; then
      missing_spec="${missing_spec}${spec_sha}, "
    fi
  done
  if [ -z "$missing_spec" ]; then
    pass "BND-003(spec-shas)" "metadata file references all three spec commit SHAs (9d61920, 2824387, 6c0d919)"
  else
    fail "BND-003(spec-shas)" "metadata file missing spec SHA(s): ${missing_spec%, }"
  fi

  if [ "$all_present" -eq 0 ]; then
    skip "BND-003(sha)" "SHA-256 pin verification (fixtures not yet created)"
    return
  fi

  # Extract pinned hashes from metadata .md file. Expect lines of the form:
  #   r1: sha256=<64-hex>
  # B07(5): require that each matching line contains exactly ONE 64-hex token
  # (rules out ambiguous lines with multiple hashes).
  local r pinned_list=""
  for r in 1 2 3; do
    local pinned actual
    local match_line
    match_line="$(grep -E "r${r}[^0-9a-f]*sha256[^0-9a-f]*[0-9a-f]{64}" "$FIXTURE_META" 2>/dev/null | head -n 1)"
    if [ -z "$match_line" ]; then
      fail "BND-003(sha:r$r)" "no pinned sha256 hash for r$r in $FIXTURE_META"
      continue
    fi
    local hex_count
    hex_count="$(printf '%s' "$match_line" | grep -oE '[0-9a-f]{64}' | wc -l | tr -d ' ')"
    if [ "${hex_count:-0}" -ne 1 ]; then
      fail "BND-003(sha:r$r)" "line for r$r has $hex_count 64-hex tokens (expected exactly 1): $match_line"
      continue
    fi
    pinned="$(printf '%s' "$match_line" | grep -oE '[0-9a-f]{64}' | head -n 1)"
    pinned_list="${pinned_list}${pinned}
"
    actual="$(sha256sum "tests/fixtures/fix-diff-reviewer-historical-r${r}.diff" 2>/dev/null | awk '{print $1}')"
    if [ -z "$actual" ]; then
      fail "BND-003(sha:r$r)" "cannot compute sha256 of tests/fixtures/fix-diff-reviewer-historical-r${r}.diff"
    elif [ "$pinned" = "$actual" ]; then
      pass "BND-003(sha:r$r)" "pinned sha256 matches actual (${pinned:0:12}...)"
    else
      fail "BND-003(sha:r$r)" "pinned sha256 ($pinned) != actual ($actual)"
    fi
  done

  # B07(1): three pinned hashes must be distinct.
  if [ -n "$pinned_list" ]; then
    local distinct_count total_count
    distinct_count="$(printf '%s' "$pinned_list" | grep -c '.' | tr -d ' ')"
    total_count="$distinct_count"
    distinct_count="$(printf '%s' "$pinned_list" | grep -v '^$' | sort -u | wc -l | tr -d ' ')"
    if [ "${distinct_count:-0}" -eq 3 ] && [ "${total_count:-0}" -eq 3 ]; then
      pass "BND-003(distinct)" "all 3 pinned sha256 hashes are distinct"
    else
      fail "BND-003(distinct)" "pinned hashes not all distinct ($distinct_count unique of $total_count)"
    fi
  else
    fail "BND-003(distinct)" "no pinned hashes extracted — cannot check distinctness"
  fi
}

# ============================================================================
# BND-004: Task prompt 100 KB budget documented in step 6a with fail-closed.
# ============================================================================

check_bnd004() {
  section "BND-004: Task prompt 100 KB size budget + fail-closed overflow"
  local block
  block="$(extract_step_6a_block "$CAUDIT_SKILL" 2>/dev/null || true)"

  # B06(1): 100 KB must be adjacent to a budget/overflow/abort keyword within
  # 40 chars on the same line. Accept either direction.
  if printf '%s\n' "$block" | grep -qE '(exceeds|cap|limit|budget|ceiling|abort|fail).{0,40}100[[:space:]]*KB|100[[:space:]]*KB.{0,40}(exceeds|abort|fail|cap|limit|ceiling|budget)'; then
    pass "BND-004(a)" "step 6a mentions 100 KB adjacent to a budget/overflow/abort keyword"
  else
    fail "BND-004(a)" "step 6a missing '100 KB' with a budget/abort keyword within 40 chars"
  fi

  # B06(2): NO other size values (e.g. 50 KB, 200 KB) in the block. Every
  # `<n> KB` token must be `100 KB`.
  local bad_sizes
  bad_sizes="$(printf '%s\n' "$block" | grep -oE '[0-9]+[[:space:]]*KB' | grep -vE '^100[[:space:]]*KB$' || true)"
  if [ -z "$bad_sizes" ]; then
    pass "BND-004(a2)" "no non-100 KB size tokens in step 6a"
  else
    fail "BND-004(a2)" "non-100 KB size token(s) in step 6a: $(printf '%s' "$bad_sizes" | tr '\n' ' ')"
  fi

  # B06(3): the canonical marker appears within 10 lines of the 100 KB mention.
  local kb_ln marker_ln delta
  kb_ln="$(printf '%s\n' "$block" | grep -nE '100[[:space:]]*KB' | head -n 1 | cut -d: -f1)"
  marker_ln="$(printf '%s\n' "$block" | grep -nF "$EXPECTED_CANONICAL_MARKER" | head -n 1 | cut -d: -f1)"
  if [ -n "$kb_ln" ] && [ -n "$marker_ln" ]; then
    if [ "$marker_ln" -gt "$kb_ln" ]; then
      delta=$((marker_ln - kb_ln))
    else
      delta=$((kb_ln - marker_ln))
    fi
    if [ "$delta" -le 10 ]; then
      pass "BND-004(b)" "canonical marker is $delta lines from '100 KB' mention (<=10)"
    else
      fail "BND-004(b)" "canonical marker is $delta lines from '100 KB' mention (>10)"
    fi
  else
    fail "BND-004(b)" "cannot locate both '100 KB' and canonical marker lines (kb=$kb_ln marker=$marker_ln)"
  fi

  # QA-006 class fix: a byte-counting operation (`wc -c`, `${#VAR}`,
  # `wc --bytes`) MUST appear within 5 lines of the 100 KB mention. A
  # budget with no concrete measurement is unenforceable — a sloppy
  # orchestrator could skip the check entirely.
  local measure_ln mdelta
  measure_ln="$(printf '%s\n' "$block" | grep -nE 'wc[[:space:]]+-c|wc[[:space:]]+--bytes|\$\{#[A-Za-z_]' | head -n 1 | cut -d: -f1)"
  if [ -n "$kb_ln" ] && [ -n "$measure_ln" ]; then
    if [ "$measure_ln" -gt "$kb_ln" ]; then
      mdelta=$((measure_ln - kb_ln))
    else
      mdelta=$((kb_ln - measure_ln))
    fi
    if [ "$mdelta" -le 5 ]; then
      pass "BND-004(c)" "byte-counting operation is $mdelta lines from '100 KB' mention (<=5)"
    else
      fail "BND-004(c)" "byte-counting operation is $mdelta lines from '100 KB' mention (>5) — budget lacks concrete measurement"
    fi
  else
    fail "BND-004(c)" "no byte-counting operation (wc -c, wc --bytes, \${#VAR}) found near '100 KB' mention"
  fi
}

# ============================================================================
# BND-005: graceful degradation when .claude/rules/ is empty or absent.
# ============================================================================

check_bnd005() {
  section "BND-005: Graceful degradation on empty .claude/rules/"
  local block
  block="$(extract_step_6a_block "$CAUDIT_SKILL" 2>/dev/null || true)"
  # B11(4): require one of several structurally specific forms:
  #   (a) `.claude/rules/` adjacent to empty|absent|missing|zero within 40 chars
  #   (b) literal phrase `no matching rule`
  #   (c) literal phrase `zero rule bodies`
  #   (d) literal `BND-005` reference
  if printf '%s\n' "$block" | grep -qE '\.claude/rules/.{0,40}(empty|absent|missing|zero)|(empty|absent|missing|zero).{0,40}\.claude/rules/|no matching rule|zero rule bodies|BND-005'; then
    pass "BND-005" "step 6a documents graceful degradation for empty .claude/rules/ (structural form)"
  else
    fail "BND-005" "step 6a missing graceful-degradation reference for empty .claude/rules/"
  fi
}

# ============================================================================
# BND-006: atomic GREEN commit discipline — not structurally testable here.
# INV-006's denylist is the structural enforcement on intermediate states.
# Comment only, no assertion.
# ============================================================================

check_bnd006() {
  section "BND-006: Atomic commit discipline (enforced via INV-006 denylist)"
  pass "BND-006" "not directly testable — INV-006 blocks intermediate dual-source states"
}

# ============================================================================
# GAP-002: DD-009 orchestrator-promotion metadata keys in step 6a.
# ============================================================================

check_gap002_dd009_metadata() {
  section "GAP-002: DD-009 orchestrator-promotion metadata keys in step 6a"
  local block
  block="$(extract_step_6a_block "$CAUDIT_SKILL" 2>/dev/null || true)"
  if [ -z "$block" ]; then
    fail "GAP-002" "step 6a block is empty — cannot check DD-009 promotion metadata"
    return
  fi
  local literals=(
    'source: "fix-diff-reviewer"'
    'agent: "fix-diff-reviewer"'
    'tier: "confirmed"'
    'status: "open"'
    'bounty: 0'
    'invariant_ref: null'
  )
  local lit missing=""
  for lit in "${literals[@]}"; do
    if ! printf '%s\n' "$block" | grep -qF "$lit"; then
      missing="${missing}${lit}; "
    fi
  done
  if [ -z "$missing" ]; then
    pass "GAP-002(literals)" "all 6 orchestrator-promotion literal keys present"
  else
    fail "GAP-002(literals)" "missing orchestrator-promotion literal(s): ${missing%; }"
  fi
  if printf '%s\n' "$block" | grep -qw 'round'; then
    pass "GAP-002(round)" "step 6a mentions 'round'"
  else
    fail "GAP-002(round)" "step 6a missing 'round' reference"
  fi
  if printf '%s\n' "$block" | grep -qw 'timestamp'; then
    pass "GAP-002(timestamp)" "step 6a mentions 'timestamp'"
  else
    fail "GAP-002(timestamp)" "step 6a missing 'timestamp' reference"
  fi
}

# ============================================================================
# GAP-008: ABS-010 section body narrow scope (no cross-references to
# TB-005, ABS-011, or PAT-011).
# ============================================================================

check_gap008_abs010_narrow_scope() {
  section "GAP-008: ABS-010 body narrow scope (no TB-005/ABS-011/PAT-011)"
  if [ ! -f "$ARCH_FILE" ]; then
    fail "GAP-008" "$ARCH_FILE not found — cannot check ABS-010 body"
    return
  fi
  if ! grep -qE '^### ABS-010:' "$ARCH_FILE"; then
    fail "GAP-008" "$ARCH_FILE missing ### ABS-010: heading — cannot extract body"
    return
  fi
  local abs_body
  abs_body="$(awk '
    /^### ABS-010:/ { in_block = 1; next }
    in_block && /^### / { exit }
    in_block { print }
  ' "$ARCH_FILE")"
  local token bad=""
  for token in TB-005 ABS-011 PAT-011; do
    if printf '%s\n' "$abs_body" | grep -qF "$token"; then
      bad="${bad}${token}, "
    fi
  done
  if [ -z "$bad" ]; then
    pass "GAP-008" "ABS-010 body does not reference TB-005, ABS-011, or PAT-011"
  else
    fail "GAP-008" "ABS-010 body contains out-of-scope cross-reference(s): ${bad%, }"
  fi
}

# ============================================================================
# Run all checks
# ============================================================================

echo "Correctless Fix-Diff Reviewer Agent Tests"
echo "=========================================="

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
check_inv013
check_inv014
check_inv015
check_inv016
check_inv017
check_inv018
check_inv019
check_inv020
check_prh001
check_prh002
check_prh003
check_prh004
check_prh005
check_bnd001
check_bnd002
check_bnd003
check_bnd004
check_bnd005
check_bnd006
check_producer_consumer_closure
check_gap002_dd009_metadata
check_gap008_abs010_narrow_scope

# ============================================================================
# Summary
# ============================================================================

echo ""
echo "=========================================="
echo "  ${GREEN}PASS${RESET}: $PASS"
echo "  ${RED}FAIL${RESET}: $FAIL"
echo "  ${YELLOW}SKIP${RESET}: $SKIPPED"
if [ -n "$FAILED_IDS" ]; then
  echo "  Failed IDs: $FAILED_IDS"
fi
echo "=========================================="
echo "$PASS tests passed, $FAIL tests failed, $SKIPPED tests skipped"

exit $((FAIL > 0))
