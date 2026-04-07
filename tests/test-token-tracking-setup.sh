#!/usr/bin/env bash
# Correctless — Token Tracking Setup Integration Tests
# Tests R-008 and R-012 from the token-tracking spec.
# Verifies setup script wiring and idempotency for the PostToolUse hook.
# Run from repo root: bash tests/test-token-tracking-setup.sh

set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SETUP_SCRIPT="$REPO_DIR/setup"
LIB_SH="$REPO_DIR/scripts/lib.sh"
PASS=0
FAIL=0

# ============================================================================
# Helpers
# ============================================================================

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

# ============================================================================
# Test environment
# ============================================================================

TEST_DIR="/tmp/correctless-test-token-setup-$$"

setup_test_env() {
  rm -rf "$TEST_DIR"
  mkdir -p "$TEST_DIR"
  cd "$TEST_DIR" || exit 1

  # Initialize a git repo
  git init -q
  git branch -M main
  echo "init" > README.md
  git add -A && git commit -q -m "init"
  git checkout -q -b feature/test-token-setup

  # Copy lib.sh
  mkdir -p scripts
  cp "$LIB_SH" scripts/lib.sh

  # Create .claude directory with settings.json
  mkdir -p .claude
}

cleanup() {
  rm -rf "$TEST_DIR"
}
trap cleanup EXIT

echo "Correctless Token Tracking Setup Tests"
echo "======================================="

# ============================================================================
# R-008 [integration]: hook is wired by setup script into .claude/settings.json
# ============================================================================

test_r008_setup_wiring() {
  echo ""
  echo "=== R-008: setup script wires PostToolUse hook with matcher Agent ==="

  setup_test_env

  # Create an existing settings.json with PreToolUse hooks (simulating
  # a project that already has Correctless installed but no token tracking)
  cat > "$TEST_DIR/.claude/settings.json" <<'EOF'
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Edit|Write|MultiEdit|NotebookEdit|CreateFile|Bash",
        "hooks": [
          {
            "type": "command",
            "command": ".correctless/hooks/workflow-gate.sh",
            "timeout_ms": 5000
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Edit|Write|MultiEdit|CreateFile|Bash",
        "hooks": [
          {
            "type": "command",
            "command": ".correctless/hooks/audit-trail.sh",
            "timeout_ms": 1000
          }
        ]
      }
    ]
  },
  "permissions": {
    "allow": [
      "Bash(.correctless/hooks/workflow-advance.sh *)"
    ]
  }
}
EOF

  # After running setup, token-tracking PostToolUse entry should be present.
  # The setup script needs to add a PostToolUse entry with:
  #   matcher: "Agent"
  #   command: path to token-tracking.sh
  #
  # We test by checking the settings.json for the expected entry.
  # Since the setup script may not yet have token-tracking support (STUB:TDD),
  # we test what the result SHOULD look like.

  # Run setup if it supports token-tracking wiring (may fail on stub)
  bash "$SETUP_SCRIPT" 2>/dev/null || true

  local settings
  settings="$(cat "$TEST_DIR/.claude/settings.json")"

  # Check PostToolUse array contains a token-tracking entry
  local has_token_tracking="no"
  if echo "$settings" | jq -e '.hooks.PostToolUse[] | select(.hooks[]?.command | test("token-tracking"))' >/dev/null 2>&1; then
    has_token_tracking="yes"
  fi
  assert_eq "R-008a: PostToolUse has token-tracking hook entry" "yes" "$has_token_tracking"

  # Check the matcher is "Agent" (not the write-tool matcher used by audit-trail)
  local token_matcher
  token_matcher="$(echo "$settings" | jq -r '.hooks.PostToolUse[] | select(.hooks[]?.command | test("token-tracking")) | .matcher' 2>/dev/null || echo "")"
  assert_eq "R-008b: token-tracking matcher is Agent" "Agent" "$token_matcher"

  # Check the command path points to the correct hook
  local token_cmd
  token_cmd="$(echo "$settings" | jq -r '.hooks.PostToolUse[] | select(.hooks[]?.command | test("token-tracking")) | .hooks[0].command' 2>/dev/null || echo "")"
  assert_contains "R-008c: token-tracking command path contains token-tracking.sh" "token-tracking.sh" "$token_cmd"

  # Existing audit-trail PostToolUse entry should still be present
  local has_audit="no"
  if echo "$settings" | jq -e '.hooks.PostToolUse[] | select(.hooks[]?.command | test("audit-trail"))' >/dev/null 2>&1; then
    has_audit="yes"
  fi
  assert_eq "R-008d: existing audit-trail entry preserved" "yes" "$has_audit"

  # Existing PreToolUse entries should be untouched
  local has_gate="no"
  if echo "$settings" | jq -e '.hooks.PreToolUse[] | select(.hooks[]?.command | test("workflow-gate"))' >/dev/null 2>&1; then
    has_gate="yes"
  fi
  assert_eq "R-008e: existing PreToolUse gate entry preserved" "yes" "$has_gate"
}

# ============================================================================
# R-008 [integration]: setup wires hook when settings.json doesn't exist
# ============================================================================

test_r008_fresh_install() {
  echo ""
  echo "=== R-008: setup wires hook in fresh settings.json ==="

  setup_test_env

  # Remove settings.json to test fresh install
  rm -f "$TEST_DIR/.claude/settings.json"

  # Run setup
  bash "$SETUP_SCRIPT" 2>/dev/null || true

  # settings.json should exist
  assert_file_exists "R-008f: settings.json created" "$TEST_DIR/.claude/settings.json"

  # Check for token-tracking PostToolUse entry
  local settings
  settings="$(cat "$TEST_DIR/.claude/settings.json" 2>/dev/null || echo "{}")"

  local has_token_tracking="no"
  if echo "$settings" | jq -e '.hooks.PostToolUse[] | select(.hooks[]?.command | test("token-tracking"))' >/dev/null 2>&1; then
    has_token_tracking="yes"
  fi
  assert_eq "R-008g: fresh install includes token-tracking hook" "yes" "$has_token_tracking"

  # Matcher should be "Agent"
  local token_matcher
  token_matcher="$(echo "$settings" | jq -r '.hooks.PostToolUse[] | select(.hooks[]?.command | test("token-tracking")) | .matcher' 2>/dev/null || echo "")"
  assert_eq "R-008h: fresh install token-tracking matcher is Agent" "Agent" "$token_matcher"
}

# ============================================================================
# R-012 [integration]: setup script is idempotent for PostToolUse hooks
# ============================================================================

test_r012_idempotent() {
  echo ""
  echo "=== R-012: setup is idempotent — no duplicate PostToolUse entries ==="

  setup_test_env

  # Start with settings.json that does NOT have a token-tracking entry
  # Setup must CREATE it on first run, then NOT duplicate it on second run
  cat > "$TEST_DIR/.claude/settings.json" <<'EOF'
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Edit|Write|MultiEdit|NotebookEdit|CreateFile|Bash",
        "hooks": [
          {
            "type": "command",
            "command": ".correctless/hooks/workflow-gate.sh",
            "timeout_ms": 5000
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Edit|Write|MultiEdit|CreateFile|Bash",
        "hooks": [
          {
            "type": "command",
            "command": ".correctless/hooks/audit-trail.sh",
            "timeout_ms": 1000
          }
        ]
      }
    ]
  },
  "permissions": {
    "allow": [
      "Bash(.correctless/hooks/workflow-advance.sh *)"
    ]
  }
}
EOF

  # Run setup ONCE — should add the token-tracking entry
  bash "$SETUP_SCRIPT" 2>/dev/null || true

  local settings
  settings="$(cat "$TEST_DIR/.claude/settings.json" 2>/dev/null || echo "{}")"

  # Verify token-tracking was created by the first run
  local token_count_after_first
  token_count_after_first="$(echo "$settings" | jq '[.hooks.PostToolUse[] | select(.hooks[]?.command | test("token-tracking"))] | length' 2>/dev/null || echo "0")"
  assert_eq "R-012a: 1 token-tracking entry after first setup run" "1" "$token_count_after_first"

  # Run setup AGAIN — should NOT duplicate
  bash "$SETUP_SCRIPT" 2>/dev/null || true

  settings="$(cat "$TEST_DIR/.claude/settings.json" 2>/dev/null || echo "{}")"

  local token_count_after_second
  token_count_after_second="$(echo "$settings" | jq '[.hooks.PostToolUse[] | select(.hooks[]?.command | test("token-tracking"))] | length' 2>/dev/null || echo "0")"
  assert_eq "R-012b: still exactly 1 token-tracking entry after second setup run" "1" "$token_count_after_second"

  # Count audit-trail entries — should also remain exactly 1
  local audit_count
  audit_count="$(echo "$settings" | jq '[.hooks.PostToolUse[] | select(.hooks[]?.command | test("audit-trail"))] | length' 2>/dev/null || echo "0")"
  assert_eq "R-012c: exactly 1 audit-trail entry (not duplicated)" "1" "$audit_count"

  # Total PostToolUse entries should be exactly 2 (audit-trail + token-tracking)
  local total_post
  total_post="$(echo "$settings" | jq '.hooks.PostToolUse | length' 2>/dev/null || echo "0")"
  assert_eq "R-012d: total PostToolUse entries is 2" "2" "$total_post"
}

# ============================================================================
# R-012 [integration]: setup adds token-tracking alongside existing audit-trail
# ============================================================================

test_r012_no_clobber_existing() {
  echo ""
  echo "=== R-012: setup adds token-tracking without clobbering audit-trail ==="

  setup_test_env

  # Settings with only audit-trail PostToolUse (no token-tracking yet)
  # Setup must create the token-tracking entry AND preserve audit-trail
  cat > "$TEST_DIR/.claude/settings.json" <<'EOF'
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Edit|Write|MultiEdit|NotebookEdit|CreateFile|Bash",
        "hooks": [
          {
            "type": "command",
            "command": ".correctless/hooks/workflow-gate.sh",
            "timeout_ms": 5000
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Edit|Write|MultiEdit|CreateFile|Bash",
        "hooks": [
          {
            "type": "command",
            "command": ".correctless/hooks/audit-trail.sh",
            "timeout_ms": 1000
          }
        ]
      }
    ]
  },
  "permissions": {
    "allow": [
      "Bash(.correctless/hooks/workflow-advance.sh *)"
    ]
  }
}
EOF

  # Run setup — should add token-tracking without removing audit-trail
  bash "$SETUP_SCRIPT" 2>/dev/null || true

  local settings
  settings="$(cat "$TEST_DIR/.claude/settings.json" 2>/dev/null || echo "{}")"

  # audit-trail should still be present
  local has_audit="no"
  if echo "$settings" | jq -e '.hooks.PostToolUse[] | select(.hooks[]?.command | test("audit-trail"))' >/dev/null 2>&1; then
    has_audit="yes"
  fi
  assert_eq "R-012e: audit-trail preserved after adding token-tracking" "yes" "$has_audit"

  # token-tracking should now also be present
  local has_token="no"
  if echo "$settings" | jq -e '.hooks.PostToolUse[] | select(.hooks[]?.command | test("token-tracking"))' >/dev/null 2>&1; then
    has_token="yes"
  fi
  assert_eq "R-012f: token-tracking added alongside audit-trail" "yes" "$has_token"

  # The two entries should have DIFFERENT matchers
  local audit_matcher token_matcher
  audit_matcher="$(echo "$settings" | jq -r '.hooks.PostToolUse[] | select(.hooks[]?.command | test("audit-trail")) | .matcher' 2>/dev/null || echo "")"
  token_matcher="$(echo "$settings" | jq -r '.hooks.PostToolUse[] | select(.hooks[]?.command | test("token-tracking")) | .matcher' 2>/dev/null || echo "")"

  if [ "$audit_matcher" != "$token_matcher" ]; then
    echo "  PASS: R-012g: audit-trail and token-tracking have different matchers ($audit_matcher vs $token_matcher)"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: R-012g: audit-trail and token-tracking should have different matchers (both are '$audit_matcher')"
    FAIL=$((FAIL + 1))
  fi

  # Run setup again — verify no duplication AND coexistence preserved
  bash "$SETUP_SCRIPT" 2>/dev/null || true
  settings="$(cat "$TEST_DIR/.claude/settings.json" 2>/dev/null || echo "{}")"

  local token_count audit_count
  token_count="$(echo "$settings" | jq '[.hooks.PostToolUse[] | select(.hooks[]?.command | test("token-tracking"))] | length' 2>/dev/null || echo "0")"
  audit_count="$(echo "$settings" | jq '[.hooks.PostToolUse[] | select(.hooks[]?.command | test("audit-trail"))] | length' 2>/dev/null || echo "0")"
  assert_eq "R-012h: still 1 token-tracking entry after second run" "1" "$token_count"
  assert_eq "R-012i: still 1 audit-trail entry after second run" "1" "$audit_count"
}

# ============================================================================
# Run all tests
# ============================================================================

test_r008_setup_wiring
test_r008_fresh_install
test_r012_idempotent
test_r012_no_clobber_existing

# ============================================================================
# Summary
# ============================================================================

echo ""
echo "=============================="
echo "  PASS: $PASS"
echo "  FAIL: $FAIL"
echo "=============================="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
