#!/usr/bin/env bash
# Correctless — Auto Mode Phase 3: Override Cross-Check test suite
# Track 4: Tests INV-040, INV-041, INV-042, BND-007
# RED phase: these tests MUST FAIL — implementation does not exist yet.
# Run from repo root: bash tests/test-auto-crosscheck.sh

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
  if echo "$actual" | grep -qF "$expected"; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (expected output to contain '$expected')"
    FAIL=$((FAIL + 1))
  fi
}

assert_not_contains() {
  local desc="$1" unexpected="$2" actual="$3"
  if ! echo "$actual" | grep -qF "$unexpected"; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (expected output NOT to contain '$unexpected')"
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

assert_file_exists() {
  local desc="$1" path="$2"
  if [ -f "$path" ]; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (file '$path' does not exist)"
    FAIL=$((FAIL + 1))
  fi
}

# ============================================
# Source scripts at top level to avoid RETURN trap + source interaction
source "$REPO_DIR/scripts/override-crosscheck.sh"

# ============================================
# INV-040 [integration]: Base-commit cross-check
# ============================================

test_inv040_detect_pre_existing_claim() {
  echo ""
  echo "=== INV-040: Detect 'pre-existing' claims in override reason ==="

  # Controlled vocabulary: "pre-existing", "not caused by", "already present",
  # "existed before", "upstream issue"

  local result rc

  result="$(detect_pre_existing_claim "This error is pre-existing and not from this cycle" 2>/dev/null)"
  rc=$?
  assert_eq "INV-040: 'pre-existing' detected (rc=0)" "0" "$rc"
  assert_contains "INV-040: matched keyword includes 'pre-existing'" "pre-existing" "$result"

  result="$(detect_pre_existing_claim "This failure was not caused by our changes" 2>/dev/null)"
  rc=$?
  assert_eq "INV-040: 'not caused by' detected (rc=0)" "0" "$rc"

  result="$(detect_pre_existing_claim "The bug already present in upstream" 2>/dev/null)"
  rc=$?
  assert_eq "INV-040: 'already present' detected (rc=0)" "0" "$rc"

  result="$(detect_pre_existing_claim "This issue existed before we started" 2>/dev/null)"
  rc=$?
  assert_eq "INV-040: 'existed before' detected (rc=0)" "0" "$rc"

  result="$(detect_pre_existing_claim "This is an upstream issue in the dependency" 2>/dev/null)"
  rc=$?
  assert_eq "INV-040: 'upstream issue' detected (rc=0)" "0" "$rc"
}

test_inv040_no_pre_existing_claim() {
  echo ""
  echo "=== INV-040: No pre-existing claim detected ==="

  local result rc

  result="$(detect_pre_existing_claim "Build fails because our stub is incomplete" 2>/dev/null)"
  rc=$?
  assert_eq "INV-040: no pre-existing claim (rc=1)" "1" "$rc"
}

test_inv040_crosscheck_evidence_schema() {
  echo ""
  echo "=== INV-040: Cross-check evidence has required schema ==="

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN

  # Create a minimal config fixture
  cat > "$TEST_DIR/workflow-config.json" << 'CONFIG_EOF'
{
  "commands": {
    "test": "bash tests/run-all.sh",
    "test_timeout": 120
  }
}
CONFIG_EOF

  local result
  result="$(base_commit_crosscheck "$TEST_DIR/workflow-config.json" 2>/dev/null)"
  local rc=$?

  # Even if the cross-check can't run (not in a git context with proper base),
  # it should return valid JSON with the required fields
  local is_json="no"
  echo "$result" | jq '.' >/dev/null 2>&1 && is_json="yes"
  assert_eq "INV-040: cross-check evidence is valid JSON" "yes" "$is_json"

  # Check required fields exist (even if null/false)
  local has_claimed="no"
  echo "$result" | jq -e 'has("pre_existing_claimed")' >/dev/null 2>&1 && has_claimed="yes"
  assert_eq "INV-040: evidence has pre_existing_claimed field" "yes" "$has_claimed"

  local has_base="no"
  echo "$result" | jq -e 'has("base_commit")' >/dev/null 2>&1 && has_base="yes"
  assert_eq "INV-040: evidence has base_commit field" "yes" "$has_base"

  local has_success="no"
  echo "$result" | jq -e 'has("base_build_success")' >/dev/null 2>&1 && has_success="yes"
  assert_eq "INV-040: evidence has base_build_success field" "yes" "$has_success"

  local has_failure_mode="no"
  echo "$result" | jq -e 'has("failure_mode")' >/dev/null 2>&1 && has_failure_mode="yes"
  assert_eq "INV-040: evidence has failure_mode field" "yes" "$has_failure_mode"

  # Fields consumed by Track 3 (INV-035 override issuance review)
  local has_exit_code="no"
  echo "$result" | jq -e 'has("base_build_exit_code")' >/dev/null 2>&1 && has_exit_code="yes"
  assert_eq "INV-040: evidence has base_build_exit_code" "yes" "$has_exit_code"

  local has_stderr="no"
  echo "$result" | jq -e 'has("base_build_stderr")' >/dev/null 2>&1 && has_stderr="yes"
  assert_eq "INV-040: evidence has base_build_stderr" "yes" "$has_stderr"

  local has_verified="no"
  echo "$result" | jq -e 'has("claim_verified")' >/dev/null 2>&1 && has_verified="yes"
  assert_eq "INV-040: evidence has claim_verified" "yes" "$has_verified"
}

# ============================================
# INV-041 [integration]: File-touch scope drift
# ============================================

test_inv041_no_drift() {
  echo ""
  echo "=== INV-041: Files in scope — no drift detected ==="

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN

  cat > "$TEST_DIR/spec.md" << 'SPEC_EOF'
# Spec

## Scope
In scope: scripts/review-triage.sh, scripts/override-scrutiny.sh

## Files touched
- scripts/review-triage.sh
- scripts/override-scrutiny.sh
SPEC_EOF

  local touched_files='["scripts/review-triage.sh"]'
  local override_reason="Fix review-triage.sh stub function"
  local intent_summary="Build review triage system"

  local result
  result="$(detect_file_touch_drift "$touched_files" "$override_reason" "$TEST_DIR/spec.md" "$intent_summary" 2>/dev/null)"
  local rc=$?

  assert_eq "INV-041: detect_file_touch_drift exits 0" "0" "$rc"

  # Should indicate no drift
  local drift_detected="yes"
  echo "$result" | jq -e '.scope_drift_detected == false' >/dev/null 2>&1 && drift_detected="no"
  assert_eq "INV-041: no scope drift for in-scope file" "no" "$drift_detected"
}

test_inv041_drift_detected() {
  echo ""
  echo "=== INV-041: Out-of-scope file touched — drift detected ==="

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN

  cat > "$TEST_DIR/spec.md" << 'SPEC_EOF'
# Spec

## Scope
In scope: scripts/review-triage.sh

## Files touched
- scripts/review-triage.sh
SPEC_EOF

  # Touching a file NOT in spec, override reason, or intent
  local touched_files='["scripts/review-triage.sh","scripts/unrelated-module.sh"]'
  local override_reason="Fix review-triage.sh stub function"
  local intent_summary="Build review triage system"

  local result
  result="$(detect_file_touch_drift "$touched_files" "$override_reason" "$TEST_DIR/spec.md" "$intent_summary" 2>/dev/null)"
  local rc=$?

  assert_eq "INV-041: detect_file_touch_drift exits 0 with drift" "0" "$rc"

  # Should detect drift
  local drift_detected="no"
  echo "$result" | jq -e '.scope_drift_detected == true' >/dev/null 2>&1 && drift_detected="yes"
  assert_eq "INV-041: scope drift detected for out-of-scope file" "yes" "$drift_detected"

  # out_of_scope_files should list the drifted file
  local has_oos="no"
  echo "$result" | jq -e '.out_of_scope_files | index("scripts/unrelated-module.sh")' >/dev/null 2>&1 && has_oos="yes"
  assert_eq "INV-041: out_of_scope_files lists drifted file" "yes" "$has_oos"
}

test_inv041_transient_files_excluded() {
  echo ""
  echo "=== INV-041: Transient files excluded from drift check ==="

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN

  echo '## Scope' > "$TEST_DIR/spec.md"

  # /tmp files and *.tmp should not trigger drift
  local touched_files='["/tmp/build-output.log","scripts/review-triage.sh.tmp"]'
  local override_reason="Fix build issue"
  local intent_summary="Build system"

  local result
  result="$(detect_file_touch_drift "$touched_files" "$override_reason" "$TEST_DIR/spec.md" "$intent_summary" 2>/dev/null)"
  local rc=$?

  assert_eq "INV-041: detect_file_touch_drift exits 0" "0" "$rc"

  # Transient files should not appear in out_of_scope
  local oos_count
  oos_count="$(echo "$result" | jq '.out_of_scope_files | length' 2>/dev/null)" || oos_count="-1"
  assert_eq "INV-041: transient files not in out_of_scope" "0" "$oos_count"
}

# ============================================
# INV-042 [integration]: Spec completeness parsing
# ============================================

test_inv042_parse_deliverables_what_lands() {
  echo ""
  echo "=== INV-042: Parse deliverables from 'What lands' section ==="

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN

  cat > "$TEST_DIR/spec.md" << 'SPEC_EOF'
# Spec: Feature X

## What lands

- scripts/review-triage.sh
- scripts/override-scrutiny.sh
- tests/test-auto-review-triage.sh

## Invariants

### INV-021: Review triage
SPEC_EOF

  local result
  result="$(parse_spec_deliverables "$TEST_DIR/spec.md" 2>/dev/null)"
  local rc=$?

  assert_eq "INV-042: parse_spec_deliverables exits 0" "0" "$rc"

  # Should extract the file paths
  local count
  count="$(echo "$result" | jq 'length' 2>/dev/null)" || count="0"
  assert_eq "INV-042: extracted 3 deliverables from 'What lands'" "3" "$count"

  assert_contains "INV-042: extracted scripts/review-triage.sh" "scripts/review-triage.sh" "$result"
  assert_contains "INV-042: extracted scripts/override-scrutiny.sh" "scripts/override-scrutiny.sh" "$result"
}

test_inv042_parse_deliverables_in_scope() {
  echo ""
  echo "=== INV-042: Parse deliverables from 'In scope' section ==="

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN

  cat > "$TEST_DIR/spec.md" << 'SPEC_EOF'
# Spec

## In scope

- agents/supervisor.md
- scripts/lib.sh
SPEC_EOF

  local result
  result="$(parse_spec_deliverables "$TEST_DIR/spec.md" 2>/dev/null)"
  local rc=$?

  assert_eq "INV-042: parse from 'In scope' exits 0" "0" "$rc"

  local count
  count="$(echo "$result" | jq 'length' 2>/dev/null)" || count="0"
  assert_eq "INV-042: extracted 2 deliverables from 'In scope'" "2" "$count"
}

test_inv042_parse_deliverables_code_block_excluded() {
  echo ""
  echo "=== INV-042: Code block content excluded from deliverable parsing ==="

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN

  cat > "$TEST_DIR/spec.md" << 'SPEC_EOF'
# Spec

## What lands

- scripts/real-deliverable.sh

```json
{
  "example": "scripts/not-a-deliverable.sh"
}
```

## Invariants
SPEC_EOF

  local result
  result="$(parse_spec_deliverables "$TEST_DIR/spec.md" 2>/dev/null)"

  # Should only extract the real deliverable, not the one in the code block
  local count
  count="$(echo "$result" | jq 'length' 2>/dev/null)" || count="0"
  assert_eq "INV-042: only 1 deliverable (code block excluded)" "1" "$count"
  assert_contains "INV-042: extracted real deliverable" "scripts/real-deliverable.sh" "$result"
  assert_not_contains "INV-042: code block path excluded" "scripts/not-a-deliverable.sh" "$result"
}

test_inv042_parse_markdown_links() {
  echo ""
  echo "=== INV-042: Markdown links — extract link text, not URL ==="

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN

  cat > "$TEST_DIR/spec.md" << 'SPEC_EOF'
# Spec

## Deliverables

- [scripts/review-triage.sh](https://github.com/example/blob/main/scripts/review-triage.sh)
- [agents/supervisor.md](./agents/supervisor.md)
SPEC_EOF

  local result
  result="$(parse_spec_deliverables "$TEST_DIR/spec.md" 2>/dev/null)"
  local rc=$?

  assert_eq "INV-042: parse markdown links exits 0" "0" "$rc"
  assert_contains "INV-042: extracted link text scripts/review-triage.sh" "scripts/review-triage.sh" "$result"
  assert_contains "INV-042: extracted link text agents/supervisor.md" "agents/supervisor.md" "$result"
}

test_inv042_parse_deliverables_dockerfile() {
  echo ""
  echo "=== INV-042: Parse 'Dockerfile' as deliverable (literal, no extension) ==="

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN

  cat > "$TEST_DIR/spec.md" << 'SPEC_EOF'
# Spec

## What lands

- scripts/build.sh
- Dockerfile
SPEC_EOF

  local result
  result="$(parse_spec_deliverables "$TEST_DIR/spec.md" 2>/dev/null)"
  local rc=$?

  assert_eq "INV-042: parse Dockerfile exits 0" "0" "$rc"

  local count
  count="$(echo "$result" | jq 'length' 2>/dev/null)" || count="0"
  assert_eq "INV-042: extracted 2 deliverables (including Dockerfile)" "2" "$count"

  assert_contains "INV-042: extracted Dockerfile" "Dockerfile" "$result"
  assert_contains "INV-042: extracted scripts/build.sh" "scripts/build.sh" "$result"
}

test_inv042_completeness_all_delivered() {
  echo ""
  echo "=== INV-042: Spec completeness — all deliverables present ==="

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN

  cat > "$TEST_DIR/spec.md" << 'SPEC_EOF'
# Spec

## What lands

- scripts/review-triage.sh
- scripts/override-scrutiny.sh
SPEC_EOF

  local completed='["scripts/review-triage.sh","scripts/override-scrutiny.sh"]'

  local result
  result="$(check_spec_completeness "$TEST_DIR/spec.md" "$completed" 2>/dev/null)"
  local rc=$?

  assert_eq "INV-042: check_spec_completeness exits 0" "0" "$rc"

  local is_complete="no"
  echo "$result" | jq -e '.complete == true' >/dev/null 2>&1 && is_complete="yes"
  assert_eq "INV-042: all deliverables present → complete" "yes" "$is_complete"

  local missing_count
  missing_count="$(echo "$result" | jq '.missing_deliverables | length' 2>/dev/null)" || missing_count="-1"
  assert_eq "INV-042: no missing deliverables" "0" "$missing_count"
}

test_inv042_completeness_missing() {
  echo ""
  echo "=== INV-042: Spec completeness — deliverables missing ==="

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN

  cat > "$TEST_DIR/spec.md" << 'SPEC_EOF'
# Spec

## What lands

- scripts/review-triage.sh
- scripts/override-scrutiny.sh
- scripts/override-crosscheck.sh
SPEC_EOF

  # Only one of three delivered
  local completed='["scripts/review-triage.sh"]'

  local result
  result="$(check_spec_completeness "$TEST_DIR/spec.md" "$completed" 2>/dev/null)"
  local rc=$?

  assert_eq "INV-042: check_spec_completeness exits 0" "0" "$rc"

  local is_complete="no"
  echo "$result" | jq -e '.complete == false' >/dev/null 2>&1 && is_complete="yes"
  assert_eq "INV-042: missing deliverables → not complete" "yes" "$is_complete"

  local missing_count
  missing_count="$(echo "$result" | jq '.missing_deliverables | length' 2>/dev/null)" || missing_count="-1"
  assert_eq "INV-042: 2 missing deliverables" "2" "$missing_count"
}

test_inv042_no_deliverable_section_skipped() {
  echo ""
  echo "=== INV-042: No deliverable section — check skipped ==="

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN

  cat > "$TEST_DIR/spec.md" << 'SPEC_EOF'
# Spec

## Context

This spec has no deliverable section.

## Invariants

### INV-001: Something
SPEC_EOF

  local completed='["scripts/something.sh"]'

  local result
  result="$(check_spec_completeness "$TEST_DIR/spec.md" "$completed" 2>/dev/null)"
  local rc=$?

  assert_eq "INV-042: check_spec_completeness with no section exits 0" "0" "$rc"

  local check_applicable="yes"
  echo "$result" | jq -e '.check_applicable == false' >/dev/null 2>&1 && check_applicable="no"
  assert_eq "INV-042: no deliverable section → check not applicable" "no" "$check_applicable"
}

# ============================================
# BND-007 [unit]: Cross-check failure modes
# ============================================

test_bnd007_merge_base_fails() {
  echo ""
  echo "=== BND-007: merge-base failure → fail-closed evidence ==="

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN

  # Config with test command but we're in a temp dir without git
  cat > "$TEST_DIR/workflow-config.json" << 'EOF'
{"commands":{"test":"echo test","test_timeout":120}}
EOF

  local result
  result="$(base_commit_crosscheck "$TEST_DIR/workflow-config.json" 2>/dev/null)"

  # Must still return valid JSON with failure_mode set
  local is_json="no"
  echo "$result" | jq '.' >/dev/null 2>&1 && is_json="yes"
  assert_eq "BND-007: merge-base failure returns valid JSON" "yes" "$is_json"

  # failure_mode should not be null
  local has_failure="no"
  echo "$result" | jq -e '.failure_mode != null' >/dev/null 2>&1 && has_failure="yes"
  assert_eq "BND-007: merge-base failure sets failure_mode" "yes" "$has_failure"

  # R2-F3: infrastructure failures return null (inconclusive), not false (disconfirmed)
  local verified
  verified="$(echo "$result" | jq -r 'if .claim_verified == null then "null" elif .claim_verified == true then "true" else "false" end' 2>/dev/null)"
  assert_eq "BND-007: merge-base failure → claim inconclusive (null)" "null" "$verified"
}

test_bnd007_no_test_command() {
  echo ""
  echo "=== BND-007: No test command in config → fail-closed ==="

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN

  # Config with null test command
  cat > "$TEST_DIR/workflow-config.json" << 'EOF'
{"commands":{"test":null}}
EOF

  local result
  result="$(base_commit_crosscheck "$TEST_DIR/workflow-config.json" 2>/dev/null)"

  local is_json="no"
  echo "$result" | jq '.' >/dev/null 2>&1 && is_json="yes"
  assert_eq "BND-007: no test command returns valid JSON" "yes" "$is_json"

  local has_failure="no"
  echo "$result" | jq -e '.failure_mode != null' >/dev/null 2>&1 && has_failure="yes"
  assert_eq "BND-007: no test command sets failure_mode" "yes" "$has_failure"
}

test_bnd007_empty_test_command() {
  echo ""
  echo "=== BND-007: Empty test command → fail-closed ==="

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN

  cat > "$TEST_DIR/workflow-config.json" << 'EOF'
{"commands":{"test":""}}
EOF

  local result
  result="$(base_commit_crosscheck "$TEST_DIR/workflow-config.json" 2>/dev/null)"

  local is_json="no"
  echo "$result" | jq '.' >/dev/null 2>&1 && is_json="yes"
  assert_eq "BND-007: empty test command returns valid JSON" "yes" "$is_json"

  local has_failure="no"
  echo "$result" | jq -e '.failure_mode != null' >/dev/null 2>&1 && has_failure="yes"
  assert_eq "BND-007: empty test command sets failure_mode" "yes" "$has_failure"
}

# ============================================
# INV-040 [integration]: Success path with real git
# ============================================

test_inv040_success_path_real_git() {
  echo ""
  echo "=== INV-040: Success path — base commit build passes ==="

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN

  # Set up a real git repo
  (
    cd "$TEST_DIR" || exit
    git init -q
    git config user.email "test@test.com"
    git config user.name "Test"

    # Create a test script that passes
    echo '#!/bin/bash' > test.sh
    echo 'exit 0' >> test.sh
    chmod +x test.sh

    git add test.sh
    git commit -q -m "base commit"

    # Create a branch with a change
    git checkout -q -b feature-branch
    echo '# change' >> test.sh
    git add test.sh
    git commit -q -m "feature change"
  )

  # Create a workflow config pointing to the test command
  cat > "$TEST_DIR/workflow-config.json" << 'CONFIG_EOF'
{
  "commands": {
    "test": "bash test.sh",
    "test_timeout": 30
  }
}
CONFIG_EOF

  # Run cross-check from the feature branch context
  local result
  result="$(cd "$TEST_DIR" && base_commit_crosscheck "$TEST_DIR/workflow-config.json" 2>/dev/null)"
  local rc=$?

  # Must return valid JSON
  local is_json="no"
  echo "$result" | jq '.' >/dev/null 2>&1 && is_json="yes"
  assert_eq "INV-040: success path returns valid JSON" "yes" "$is_json"

  # Base build should succeed
  local build_success="no"
  echo "$result" | jq -e '.base_build_success == true' >/dev/null 2>&1 && build_success="yes"
  assert_eq "INV-040: base_build_success is true" "yes" "$build_success"

  # failure_mode should be null
  local failure_null="no"
  echo "$result" | jq -e '.failure_mode == null' >/dev/null 2>&1 && failure_null="yes"
  assert_eq "INV-040: failure_mode is null" "yes" "$failure_null"

  # base_commit should be non-empty
  local base_commit
  base_commit="$(echo "$result" | jq -r '.base_commit // ""' 2>/dev/null)" || base_commit=""
  local has_base="no"
  [ -n "$base_commit" ] && [ "$base_commit" != "null" ] && has_base="yes"
  assert_eq "INV-040: base_commit is non-empty" "yes" "$has_base"
}

test_inv040_success_path_build_fails() {
  echo ""
  echo "=== INV-040: Success path — base commit build fails ==="

  local TEST_DIR
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' RETURN

  # Set up a real git repo with a failing test on the base commit
  (
    cd "$TEST_DIR" || exit
    git init -q
    git config user.email "test@test.com"
    git config user.name "Test"

    # Create a test script that FAILS
    echo '#!/bin/bash' > test.sh
    echo 'exit 1' >> test.sh
    chmod +x test.sh

    git add test.sh
    git commit -q -m "base commit with failing test"

    # Create a branch with a change
    git checkout -q -b feature-branch
    echo '# change' >> test.sh
    git add test.sh
    git commit -q -m "feature change"
  )

  cat > "$TEST_DIR/workflow-config.json" << 'CONFIG_EOF'
{
  "commands": {
    "test": "bash test.sh",
    "test_timeout": 30
  }
}
CONFIG_EOF

  local result
  result="$(cd "$TEST_DIR" && base_commit_crosscheck "$TEST_DIR/workflow-config.json" 2>/dev/null)"

  # Must return valid JSON
  local is_json="no"
  echo "$result" | jq '.' >/dev/null 2>&1 && is_json="yes"
  assert_eq "INV-040: build-fails path returns valid JSON" "yes" "$is_json"

  # Base build should fail
  local build_fails="no"
  echo "$result" | jq -e '.base_build_success == false' >/dev/null 2>&1 && build_fails="yes"
  assert_eq "INV-040: base_build_success is false" "yes" "$build_fails"

  # Exit code should be 1
  local exit_code
  exit_code="$(echo "$result" | jq -r '.base_build_exit_code // ""' 2>/dev/null)" || exit_code=""
  assert_eq "INV-040: base_build_exit_code is 1" "1" "$exit_code"
}

# ============================================
# Runner
# ============================================

echo "============================================="
echo "Auto Mode Phase 3 — Override Cross-Checks"
echo "============================================="

# INV-040: Pre-existing claim detection
test_inv040_detect_pre_existing_claim
test_inv040_no_pre_existing_claim
test_inv040_crosscheck_evidence_schema
test_inv040_success_path_real_git
test_inv040_success_path_build_fails

# INV-041: File-touch scope drift
test_inv041_no_drift
test_inv041_drift_detected
test_inv041_transient_files_excluded

# INV-042: Spec completeness
test_inv042_parse_deliverables_what_lands
test_inv042_parse_deliverables_in_scope
test_inv042_parse_deliverables_code_block_excluded
test_inv042_parse_markdown_links
test_inv042_parse_deliverables_dockerfile
test_inv042_completeness_all_delivered
test_inv042_completeness_missing
test_inv042_no_deliverable_section_skipped

# BND-007: Cross-check failure modes
test_bnd007_merge_base_fails
test_bnd007_no_test_command
test_bnd007_empty_test_command

echo ""
echo "============================================="
echo "Results: $PASS passed, $FAIL failed"
echo ""

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
