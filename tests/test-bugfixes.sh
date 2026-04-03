#!/usr/bin/env bash
# Correctless — workflow bug fix tests
# Tests spec rules R-001 through R-011 from .correctless/specs/workflow-bug-fixes.md
# Run from repo root: bash test-bugfixes.sh

set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="/tmp/correctless-bugfix-test-$$"
PASS=0
FAIL=0

# ---------------------------------------------------------------------------
# Helpers (same as test.sh)
# ---------------------------------------------------------------------------

setup_test_project() {
  rm -rf "$TEST_DIR"
  mkdir -p "$TEST_DIR"
  cd "$TEST_DIR" || exit
  git init -q
  git branch -M main
  echo '{"name": "test-app", "scripts": {"test": "echo FAIL && exit 1", "lint": "echo ok", "build": "echo ok"}}' > package.json
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

assert_exit() {
  local desc="$1" expected_exit="$2"
  shift 2
  local actual_exit
  "$@" >/dev/null 2>&1 && actual_exit=0 || actual_exit=$?
  assert_eq "$desc" "$expected_exit" "$actual_exit"
}

file_contains() { grep -q "$2" "$1" 2>/dev/null; }

ADV() { cd "$TEST_DIR" && .correctless/hooks/workflow-advance.sh "$@"; }

# ---------------------------------------------------------------------------
# Bug 1: Slug Truncation — R-001, R-002, R-011
# ---------------------------------------------------------------------------

test_slug_truncation() {
  echo ""
  echo "=== Bug 1: Slug Truncation (R-001, R-002, R-011) ==="

  # --- R-001 [unit]: slug truncated to first 4 tokens, max 50 chars ---

  setup_test_project
  .claude/skills/workflow/setup >/dev/null 2>&1
  git checkout -q -b feature/slug-trunc

  ADV init "MCP integration Serena Context7 for symbol level code analysis" >/dev/null 2>&1

  # Read the spec_file from state
  local state_file spec_file slug token_count slug_len
  state_file="$(ls .correctless/artifacts/workflow-state-feature-slug-trunc-*.json 2>/dev/null | head -1)"
  spec_file="$(jq -r '.spec_file' "$state_file")"

  # Extract the slug portion: strip ".correctless/specs/" prefix and ".md" suffix
  slug="$(echo "$spec_file" | sed 's|^.correctless/specs/||' | sed 's|\.md$||')"

  # Count hyphen-separated tokens
  token_count="$(echo "$slug" | tr '-' '\n' | wc -l | tr -d ' ')"
  slug_len="${#slug}"

  # R-001: at most 4 tokens
  local four_or_fewer
  if [ "$token_count" -le 4 ]; then
    four_or_fewer="true"
  else
    four_or_fewer="false"
  fi
  assert_eq "R-001: slug has at most 4 hyphen-separated tokens (got $token_count: '$slug')" "true" "$four_or_fewer"

  # R-001: max 50 chars
  local within_limit
  if [ "$slug_len" -le 50 ]; then
    within_limit="true"
  else
    within_limit="false"
  fi
  assert_eq "R-001: slug is max 50 characters (got $slug_len)" "true" "$within_limit"

  # --- R-002 [unit]: /cspec SKILL.md asks for a short feature name ---

  local skill_file="$REPO_DIR/skills/cspec/SKILL.md"
  local has_short_name="false"
  if grep -qi "short.*name" "$skill_file" && grep -qi "used in filenames" "$skill_file"; then
    has_short_name="true"
  fi
  assert_eq "R-002: /cspec SKILL.md asks for short name used in filenames" "true" "$has_short_name"

  # --- R-011 [integration]: collision appends -2 ---

  # Reset: clean project
  setup_test_project
  .claude/skills/workflow/setup >/dev/null 2>&1
  git checkout -q -b feature/slug-collision

  # Pre-create a spec file that would collide
  mkdir -p .correctless/specs
  echo "# Existing spec" > .correctless/specs/workflow-bug.md

  ADV init "workflow bug" >/dev/null 2>&1

  state_file="$(ls .correctless/artifacts/workflow-state-feature-slug-collision-*.json 2>/dev/null | head -1)"
  spec_file="$(jq -r '.spec_file' "$state_file")"

  assert_eq "R-011: collision appends -2 to spec_file" ".correctless/specs/workflow-bug-2.md" "$spec_file"
}

# ---------------------------------------------------------------------------
# Bug 2: RED Gate with test_new — R-003, R-004, R-005
# ---------------------------------------------------------------------------

test_red_gate_test_new() {
  echo ""
  echo "=== Bug 2: RED Gate with test_new (R-003, R-004, R-005) ==="

  # --- R-003 [integration]: tests_fail_not_build_error uses commands.test_new ---

  setup_test_project
  .claude/skills/workflow/setup >/dev/null 2>&1
  git checkout -q -b feature/test-new-red

  # Configure: test (main suite) passes, test_new (new tests) fails
  # This mimics having existing passing tests + new failing tests
  cat > .correctless/config/workflow-config.json <<'WCONF'
{
  "project": { "name": "test-app", "language": "typescript", "description": "" },
  "commands": {
    "test": "echo ALL_PASS && exit 0",
    "test_new": "echo NEW_FAIL && exit 1",
    "lint": "echo ok",
    "build": "echo ok"
  },
  "patterns": {
    "test_file": "*.test.ts",
    "source_file": "*.ts",
    "test_fail_pattern": "FAIL",
    "build_error_pattern": "SyntaxError|Cannot find module"
  },
  "is_monorepo": false,
  "packages": {},
  "workflow": { "min_qa_rounds": 1, "require_review": true, "auto_update_antipatterns": true }
}
WCONF

  ADV init "test new red gate" >/dev/null 2>&1
  mkdir -p .correctless/specs
  echo "# Spec" > .correctless/specs/test-new-red-gate.md
  ADV review >/dev/null 2>&1
  ADV tests >/dev/null 2>&1

  # Create a test file so test_files_exist passes
  echo '// test' > foo.test.ts
  git add foo.test.ts

  # Advancing to impl should succeed: test_new fails (RED gate satisfied)
  local _impl_out impl_exit
  _impl_out="$(ADV impl 2>&1)" && impl_exit=0 || impl_exit=$?
  assert_eq "R-003: impl succeeds when test_new fails (RED gate)" "0" "$impl_exit"

  # --- R-004 [integration]: tests_pass (GREEN gate) uses commands.test ---

  # Now in tdd-impl phase. Configure test to fail (all tests including new must pass)
  cat > .correctless/config/workflow-config.json <<'WCONF'
{
  "project": { "name": "test-app", "language": "typescript", "description": "" },
  "commands": {
    "test": "echo SOME_FAIL && exit 1",
    "test_new": "echo NEW_PASS && exit 0",
    "lint": "echo ok",
    "build": "echo ok"
  },
  "patterns": {
    "test_file": "*.test.ts",
    "source_file": "*.ts",
    "test_fail_pattern": "FAIL",
    "build_error_pattern": "SyntaxError|Cannot find module"
  },
  "is_monorepo": false,
  "packages": {},
  "workflow": { "min_qa_rounds": 1, "require_review": true, "auto_update_antipatterns": true }
}
WCONF

  local _qa_out qa_exit
  _qa_out="$(ADV qa 2>&1)" && qa_exit=0 || qa_exit=$?
  assert_eq "R-004: qa blocked when commands.test fails (GREEN gate uses test, not test_new)" "1" "$qa_exit"

  # --- R-005 [integration]: without test_new, falls back to commands.test ---

  setup_test_project
  .claude/skills/workflow/setup >/dev/null 2>&1
  git checkout -q -b feature/test-no-new

  # Config has NO test_new field
  cat > .correctless/config/workflow-config.json <<'WCONF'
{
  "project": { "name": "test-app", "language": "typescript", "description": "" },
  "commands": {
    "test": "echo FAIL && exit 1",
    "lint": "echo ok",
    "build": "echo ok"
  },
  "patterns": {
    "test_file": "*.test.ts",
    "source_file": "*.ts",
    "test_fail_pattern": "FAIL",
    "build_error_pattern": "SyntaxError|Cannot find module"
  },
  "is_monorepo": false,
  "packages": {},
  "workflow": { "min_qa_rounds": 1, "require_review": true, "auto_update_antipatterns": true }
}
WCONF

  ADV init "test fallback" >/dev/null 2>&1
  mkdir -p .correctless/specs
  echo "# Spec" > .correctless/specs/test-fallback.md
  ADV review >/dev/null 2>&1
  ADV tests >/dev/null 2>&1

  echo '// test' > bar.test.ts
  git add bar.test.ts

  # Should succeed: test command fails (RED gate), no test_new => fallback to test
  local _fb_out fb_exit
  _fb_out="$(ADV impl 2>&1)" && fb_exit=0 || fb_exit=$?
  assert_eq "R-005: impl succeeds when no test_new and commands.test fails (fallback)" "0" "$fb_exit"
}

# ---------------------------------------------------------------------------
# Bug 3: QA Findings Status — R-006, R-007
# ---------------------------------------------------------------------------

test_qa_findings_status() {
  echo ""
  echo "=== Bug 3: QA Findings Status (R-006, R-007) ==="

  local ctdd_skill="$REPO_DIR/skills/ctdd/SKILL.md"

  # --- R-006 [unit]: /ctdd instructs fix agent to update findings status ---
  # The spec says: "instruction for the fix agent to update qa-findings-{task-slug}.json
  # after each fix: set status to fixed on findings it addressed."
  # This must be in the fix agent's instructions (the spawn prompt for GREEN fix rounds),
  # not just the orchestrator's findings persistence section.

  local has_fix_agent_instruction="false"
  # Look for fix-agent-specific instruction about updating findings status.
  # The existing "Update the findings artifact with status: fixed" is about the orchestrator's
  # general flow, not a specific instruction TO the fix agent. The spec (R-006) requires:
  # "instruction for the fix agent to update qa-findings-{task-slug}.json after each fix:
  #  set status to fixed on findings it addressed."
  # This must appear as a spawned agent instruction (in a blockquote or dedicated section),
  # not just the orchestrator's own procedure notes.
  # We look for "fix agent" near "qa-findings" and "status" in a targeted way.
  if grep -qiP 'fix\s+agent.*qa-findings.*status.*fixed' "$ctdd_skill" || \
     grep -qiP '> .*update.*qa-findings.*status.*fixed' "$ctdd_skill"; then
    has_fix_agent_instruction="true"
  fi
  assert_eq "R-006: /ctdd SKILL.md instructs fix agent to update findings status to fixed" "true" "$has_fix_agent_instruction"

  # --- R-007 [unit]: /ctdd instructs orchestrator to verify findings statuses ---
  # The spec says: "instruction for the orchestrator to verify findings statuses after
  # each fix round and update any finding that was fixed but still shows status: open"

  local has_verify_instruction="false"
  if grep -qiP 'orchestrator.*verify.*findings.*status' "$ctdd_skill" || \
     grep -qiP 'verify.*finding.*status.*(open|fixed)' "$ctdd_skill" || \
     grep -qiP 'after.*fix.*round.*verif' "$ctdd_skill"; then
    has_verify_instruction="true"
  fi
  assert_eq "R-007: /ctdd SKILL.md instructs orchestrator to verify findings statuses" "true" "$has_verify_instruction"
}

# ---------------------------------------------------------------------------
# Bug 4: Local Sync Check — R-008, R-009, R-010
# ---------------------------------------------------------------------------

test_sync_check() {
  echo ""
  echo "=== Bug 4: Local Sync Check (R-008, R-009, R-010) ==="

  # --- R-008 [integration]: sync.sh --check exits 0 when clean, 1 when dirty ---
  # The --check flag must be a recognized dry-run mode: compare source files against
  # distribution copies and exit 1 if any differ, exit 0 if clean. No files modified.

  # First, run sync.sh to ensure everything is in sync
  local _sync_out
  _sync_out="$(cd "$REPO_DIR" && bash sync.sh 2>&1)" || true

  # Verify --check is actually recognized (not silently ignored).
  # If --check is implemented, it should NOT produce the "Syncing source" banner
  # (that would mean it's doing a real sync, not a dry-run check).
  local check_output check_clean_exit
  check_output="$(cd "$REPO_DIR" && bash sync.sh --check 2>&1)" && check_clean_exit=0 || check_clean_exit=$?

  # The --check flag must NOT produce the sync banner (it's dry-run, not a real sync)
  local is_dryrun="true"
  if echo "$check_output" | grep -q "Syncing source"; then
    is_dryrun="false"
  fi
  assert_eq "R-008: sync.sh --check is dry-run (no sync banner)" "true" "$is_dryrun"

  # Only meaningful if --check is actually a dry-run (not just the normal sync exiting 0)
  if [ "$is_dryrun" = "true" ]; then
    assert_eq "R-008: sync.sh --check exits 0 when clean" "0" "$check_clean_exit"
  else
    # --check flag not implemented; report as fail
    assert_eq "R-008: sync.sh --check exits 0 when clean (requires --check to be implemented)" "true" "false"
  fi

  # Modify a source skill file to make it out of sync
  cp "$REPO_DIR/skills/cspec/SKILL.md" "/tmp/cspec-skill-backup-$$"
  echo "# DIRTY MODIFICATION FOR TEST" >> "$REPO_DIR/skills/cspec/SKILL.md"

  local check_dirty_exit
  (cd "$REPO_DIR" && bash sync.sh --check >/dev/null 2>&1) && check_dirty_exit=0 || check_dirty_exit=$?
  assert_eq "R-008: sync.sh --check exits 1 when out of sync" "1" "$check_dirty_exit"

  # Restore the file exactly and re-sync in case --check wasn't dry-run
  cp "/tmp/cspec-skill-backup-$$" "$REPO_DIR/skills/cspec/SKILL.md"
  rm -f "/tmp/cspec-skill-backup-$$"
  (cd "$REPO_DIR" && bash sync.sh >/dev/null 2>&1) || true

  # --- R-009 [integration]: .pre-commit-config.yaml has sync check hook ---

  local precommit="$REPO_DIR/.pre-commit-config.yaml"
  local has_sync_hook="false"
  if grep -q "sync.sh --check" "$precommit" 2>/dev/null; then
    has_sync_hook="true"
  fi
  assert_eq "R-009: .pre-commit-config.yaml contains sync.sh --check hook" "true" "$has_sync_hook"

  # --- R-010 [unit]: templates include commands.test_new field ---

  local lite_tmpl="$REPO_DIR/templates/workflow-config.json"
  local full_tmpl="$REPO_DIR/templates/workflow-config-full.json"

  local lite_has_test_new="false"
  if grep -q "test_new" "$lite_tmpl" 2>/dev/null; then
    lite_has_test_new="true"
  fi
  assert_eq "R-010: workflow-config.json template has test_new field" "true" "$lite_has_test_new"

  local full_has_test_new="false"
  if grep -q "test_new" "$full_tmpl" 2>/dev/null; then
    full_has_test_new="true"
  fi
  assert_eq "R-010: workflow-config-full.json template has test_new field" "true" "$full_has_test_new"
}

# ---------------------------------------------------------------------------
# Run all tests
# ---------------------------------------------------------------------------

trap cleanup EXIT

echo "Correctless — Workflow Bug Fix Tests"
echo "====================================="

test_slug_truncation
test_red_gate_test_new
test_qa_findings_status
test_sync_check

echo ""
echo "====================================="
echo "Results: $PASS passed, $FAIL failed"
echo "====================================="

[ "$FAIL" -eq 0 ] && exit 0 || exit 1
