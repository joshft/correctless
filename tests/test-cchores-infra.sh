#!/usr/bin/env bash
# shellcheck disable=SC1090,SC1091,SC2086,SC2016,SC2154
# Correctless — /cchores infrastructure-delta test suite
#
# Spec: .correctless/specs/cchores.md
#
# Scope of THIS suite (RED phase — the deltas under test do NOT exist yet, so
# every assertion below FAILs until /cchores ships):
#   - INV-015  shared global working-tree lock (.correctless/artifacts/worktree.lock)
#              acquired by BOTH /cchores and /cauto via scripts/cauto-lock.sh
#   - DD-007   config migration: patterns.test_file_marker (default "") in BOTH
#              templates + additive setup migration (never overwrites a set value),
#              schema_version NOT bumped
#   - INV-012  ABS-030 sole-writer revision naming /cchores as an authorized
#              invoker + tests/test-autonomous-skill-contract.sh R-006d allowlist
#              adds `cchores`
#   - OQ-005   prune-scan.sh recognizes the three gitignored chore artifacts
#              (chore-run-*.json / chore-abort-*.md / chore-report-*.md) as
#              slug_type `branch-slug`; the .correctless/meta/ cross-run store
#              cchores-attempted.json is NOT a prune-deletion candidate
#
# This file writes tests ONLY. No source edits. Stub markers below use STUB:TDD.
#
# Run from repo root: bash tests/test-cchores-infra.sh

source "$(dirname "${BASH_SOURCE[0]}")/test-helpers.sh"

# ============================================================================
# Path constants
#
# NOTE: path tokens are referenced via variables (not editing these files).
# The prune-scan / lib / SKILL paths are SFG-protected; this suite only READS
# and EXECUTES them (which the guard permits inside an already-running test
# process), it never Edits/Writes them.
# ============================================================================

SKILLS_DIR="$REPO_DIR/skills"
SCRIPTS_DIR="$REPO_DIR/scripts"
TEMPLATES_DIR="$REPO_DIR/templates"

CCHORES_SKILL="$SKILLS_DIR/cchores/SKILL.md"
CAUTO_SKILL="$SKILLS_DIR/cauto/SKILL.md"
CAUTO_LOCK="$SCRIPTS_DIR/cauto-lock.sh"
PRUNE_SCAN="$SCRIPTS_DIR/prune-scan.sh"
LIB_SH="$SCRIPTS_DIR/lib.sh"
SETUP_SCRIPT="$REPO_DIR/setup"
ARCH_FILE="$REPO_DIR/.correctless/ARCHITECTURE.md"
AUTON_CONTRACT_TEST="$REPO_DIR/tests/test-autonomous-skill-contract.sh"
TPL_LITE="$TEMPLATES_DIR/workflow-config.json"
TPL_FULL="$TEMPLATES_DIR/workflow-config-full.json"

# Shared global lock path (fixed, non-branch-scoped) per INV-015.
WORKTREE_LOCK_PATH=".correctless/artifacts/worktree.lock"

cleanup_dirs=()
register_cleanup() { cleanup_dirs+=("$1"); }
trap 'for d in "${cleanup_dirs[@]:-}"; do [ -n "$d" ] && rm -rf "$d"; done' EXIT

# ============================================================================
# Helper: stage a runnable copy of prune-scan.sh + lib.sh into an arbitrary
# directory (so we can drive a fixture base without invoking the protected
# in-tree script path from argv). Returns the path to the runnable scanner.
# ============================================================================
stage_scanner() {
  # STUB:TDD — this is a test helper, not source under test. Returns 0/scanner path.
  local stage_dir="$1"
  mkdir -p "$stage_dir/bin"
  cat "$PRUNE_SCAN" > "$stage_dir/bin/prune-scan.sh" 2>/dev/null || return 1
  # lib.sh must sit beside the script (prune-scan sources $SCRIPT_DIR/lib.sh first)
  cat "$LIB_SH" > "$stage_dir/bin/lib.sh" 2>/dev/null || return 1
  echo "$stage_dir/bin/prune-scan.sh"
}

# Extract + eval ONLY the _classify_artifact_pattern function, then classify a
# pattern. Mirrors the technique used by tests/test-prune-scan-slug-aware.sh so
# we do not trigger the bottom-of-file category dispatch.
classify_pattern() {
  local pattern="$1"
  bash -c "
    eval \"\$(sed -n '/^_classify_artifact_pattern()/,/^}/p' '$PRUNE_SCAN')\" 2>/dev/null
    _classify_artifact_pattern '$pattern' 2>/dev/null
  " 2>/dev/null || true
}

# ============================================================================
# INV-015 — Shared global working-tree lock (cchores ⇄ cauto)
# ============================================================================

section "INV-015: shared global working-tree lock"

# --- INV-015-a [unit]: cauto-lock.sh supports acquiring an arbitrary/global
# lock path AND its error messaging names the HOLDING orchestrator (generalized
# from the cauto-only "Another /cauto run is active" wording). ---
#
# Today cauto-lock.sh hardcodes "/cauto run is active on this branch" — it does
# not name the holder generically. The generalization is the delta.
if [ -f "$CAUTO_LOCK" ]; then
  # Drive a real lock collision against a global (non-branch-scoped) path and
  # assert the second acquire fails AND the message names the holder generically
  # (not hardcoded to "/cauto ... on this branch").
  lock_tmp="$(mktemp -d)"; register_cleanup "$lock_tmp"
  # shellcheck disable=SC1090
  source "$CAUTO_LOCK"
  GLOBAL_LOCK="$lock_tmp/worktree.lock"

  if lock_acquire "$GLOBAL_LOCK" >/dev/null 2>&1; then
    second_msg="$(lock_acquire "$GLOBAL_LOCK" 2>&1 1>/dev/null || true)"
    lock_release "$GLOBAL_LOCK" >/dev/null 2>&1 || true

    # Generic holder-naming requirement (R3-4): the message must NOT be the
    # cauto-only "active on this branch" phrasing; it must name the holder
    # ("locked by", "held by", "holder", or an orchestrator placeholder).
    if echo "$second_msg" | grep -qiE 'locked by|held by|holder|holding'; then
      pass "INV-015-a" "cauto-lock.sh global-lock collision message names the holding orchestrator"
    else
      fail "INV-015-a" "cauto-lock.sh collision message does not name the holder generically (got: '$second_msg')"
    fi
  else
    fail "INV-015-a" "cauto-lock.sh lock_acquire failed for an arbitrary/global lock path"
  fi
else
  fail "INV-015-a" "scripts/cauto-lock.sh not found"
fi

# --- INV-015-b [integration]: cross-skill mutual exclusion — BOTH /cchores
# AND /cauto SKILL.md reference acquiring the SHARED global worktree.lock via
# cauto-lock.sh lock_acquire. ---
#
# cchores SKILL is absent today (FAIL). cauto SKILL does not yet acquire the
# shared worktree.lock today (FAIL).
if [ -f "$CCHORES_SKILL" ] && grep -q "$WORKTREE_LOCK_PATH" "$CCHORES_SKILL" 2>/dev/null; then
  pass "INV-015-b1" "cchores SKILL references acquiring $WORKTREE_LOCK_PATH"
else
  fail "INV-015-b1" "cchores SKILL.md missing or does not reference the shared $WORKTREE_LOCK_PATH"
fi

if [ -f "$CAUTO_SKILL" ] && grep -q "$WORKTREE_LOCK_PATH" "$CAUTO_SKILL" 2>/dev/null; then
  pass "INV-015-b2" "cauto SKILL references acquiring the shared $WORKTREE_LOCK_PATH"
else
  fail "INV-015-b2" "cauto SKILL.md does not reference acquiring the shared $WORKTREE_LOCK_PATH (retrofit missing)"
fi

# Both skills must route the acquire through cauto-lock.sh lock_acquire (the
# shared mutual-exclusion primitive), not a bespoke per-skill mechanism.
for _sk_pair in "cchores:$CCHORES_SKILL" "cauto:$CAUTO_SKILL"; do
  _sk_name="${_sk_pair%%:*}"; _sk_file="${_sk_pair#*:}"
  if [ -f "$_sk_file" ] && grep -qE 'cauto-lock\.sh|lock_acquire' "$_sk_file" 2>/dev/null; then
    pass "INV-015-b3-$_sk_name" "$_sk_name SKILL routes lock acquisition through cauto-lock.sh lock_acquire"
  else
    fail "INV-015-b3-$_sk_name" "$_sk_name SKILL does not route acquisition through cauto-lock.sh lock_acquire"
  fi
done

# --- INV-015-c [integration]: cross-skill mutual exclusion is REAL — a second
# acquire on the same fixed global path while held returns non-zero. This is the
# "cchores cannot acquire while cauto holds the global lock, and vice-versa"
# behavioral assertion (substrate is cauto-lock.sh, which both skills share). ---
if [ -f "$CAUTO_LOCK" ]; then
  mx_tmp="$(mktemp -d)"; register_cleanup "$mx_tmp"
  # shellcheck disable=SC1090
  source "$CAUTO_LOCK"
  MX_LOCK="$mx_tmp/worktree.lock"
  rc_first=1; rc_second=0
  lock_acquire "$MX_LOCK" >/dev/null 2>&1 && rc_first=0
  if lock_acquire "$MX_LOCK" >/dev/null 2>&1; then rc_second=0; else rc_second=1; fi
  lock_release "$MX_LOCK" >/dev/null 2>&1 || true
  if [ "$rc_first" -eq 0 ] && [ "$rc_second" -ne 0 ]; then
    pass "INV-015-c" "Second acquire on a held shared global lock is refused (mutual exclusion holds)"
  else
    fail "INV-015-c" "Mutual exclusion broken: first rc=$rc_first second rc=$rc_second (expected 0 then non-zero)"
  fi
else
  fail "INV-015-c" "scripts/cauto-lock.sh not found"
fi

# --- INV-015-d [integration]: stale-lock recovery behavior exists — a lock
# whose recorded PID is dead is auto-cleaned, allowing re-acquire. ---
if [ -f "$CAUTO_LOCK" ]; then
  stale_tmp="$(mktemp -d)"; register_cleanup "$stale_tmp"
  # shellcheck disable=SC1090
  source "$CAUTO_LOCK"
  STALE_LOCK="$stale_tmp/worktree.lock"
  # Simulate a held lock from a long-dead PID (atomic mkdir lock dir + pid file).
  mkdir -p "${STALE_LOCK}.d"
  echo "999999" > "${STALE_LOCK}.d/pid" 2>/dev/null || true
  echo "999999" > "$STALE_LOCK" 2>/dev/null || true
  if lock_acquire "$STALE_LOCK" >/dev/null 2>&1; then
    lock_release "$STALE_LOCK" >/dev/null 2>&1 || true
    pass "INV-015-d" "Stale lock (dead PID) is recovered and re-acquired"
  else
    fail "INV-015-d" "Stale-lock recovery failed: could not re-acquire a lock held by a dead PID"
  fi
  # Also assert the documented stale-recovery hook is wired in BOTH skills (so a
  # crashed orchestrator does not permanently wedge the global lock).
  recov_ok=true
  for _sk_file in "$CCHORES_SKILL" "$CAUTO_SKILL"; do
    [ -f "$_sk_file" ] || { recov_ok=false; continue; }
    grep -qiE 'stale|check_stale|lock_check_stale|dead PID|recover' "$_sk_file" 2>/dev/null || recov_ok=false
  done
  if $recov_ok; then
    pass "INV-015-d2" "Both cchores and cauto SKILLs document stale-lock recovery for the shared lock"
  else
    fail "INV-015-d2" "Stale-lock recovery not documented in both cchores and cauto SKILLs"
  fi
else
  fail "INV-015-d" "scripts/cauto-lock.sh not found"
fi

# ============================================================================
# DD-007 — Config migration: patterns.test_file_marker
# ============================================================================

section "DD-007: patterns.test_file_marker config migration"

# --- DD-007-a [unit]: the key is present (default empty string "") under
# `patterns` in BOTH templates. ---
for _pair in "lite:$TPL_LITE" "full:$TPL_FULL"; do
  _tpl_name="${_pair%%:*}"; _tpl_file="${_pair#*:}"
  if [ -f "$_tpl_file" ]; then
    # Must EXIST under .patterns (has() distinguishes "present but empty" from absent)
    if jq -e '.patterns | has("test_file_marker")' "$_tpl_file" >/dev/null 2>&1; then
      _val="$(jq -r '.patterns.test_file_marker' "$_tpl_file" 2>/dev/null)"
      if [ "$_val" = "" ]; then
        pass "DD-007-a-$_tpl_name" "$_tpl_name template has patterns.test_file_marker defaulting to empty string"
      else
        fail "DD-007-a-$_tpl_name" "$_tpl_name template patterns.test_file_marker is '$_val' (expected empty string default)"
      fi
    else
      fail "DD-007-a-$_tpl_name" "$_tpl_name template missing patterns.test_file_marker key"
    fi
  else
    fail "DD-007-a-$_tpl_name" "$_tpl_file not found"
  fi
done

# --- DD-007-b [unit]: schema_version is NOT bumped (additive change). Both
# templates must remain schema_version 1. ---
for _pair in "lite:$TPL_LITE" "full:$TPL_FULL"; do
  _tpl_name="${_pair%%:*}"; _tpl_file="${_pair#*:}"
  if [ -f "$_tpl_file" ]; then
    _sv="$(jq -r '.schema_version' "$_tpl_file" 2>/dev/null)"
    if [ "$_sv" = "1" ]; then
      pass "DD-007-b-$_tpl_name" "$_tpl_name template schema_version remains 1 (additive change, not bumped)"
    else
      fail "DD-007-b-$_tpl_name" "$_tpl_name template schema_version is '$_sv' (expected 1 — additive change must not bump)"
    fi
  else
    fail "DD-007-b-$_tpl_name" "$_tpl_file not found"
  fi
done

# --- DD-007-c [integration]: setup migrates an EXISTING installed config
# additively — adds patterns.test_file_marker with "" when absent. This drives
# the real setup migration path against a fixture config that predates the key. ---
#
# Today setup `skip`s an existing config entirely (no additive key migration),
# so the key stays absent → FAIL.
mig_tmp="$(mktemp -d)"; register_cleanup "$mig_tmp"
mkdir -p "$mig_tmp/.correctless/config"
OLD_CFG="$mig_tmp/.correctless/config/workflow-config.json"
# Pre-existing config WITHOUT test_file_marker (simulates an upgrade).
cat > "$OLD_CFG" <<'OLDCFG'
{
  "schema_version": 1,
  "project": { "name": "demo", "language": "go", "description": "" },
  "commands": { "test": "go test ./...", "test_new": "", "test_verbose": "", "coverage": "", "lint": "", "build": "" },
  "patterns": { "test_file": "*_test.go", "source_file": "", "test_fail_pattern": "FAIL", "build_error_pattern": "" },
  "is_monorepo": false,
  "packages": {},
  "workflow": { "min_qa_rounds": 1 },
  "mcp": { "serena": false, "context7": false }
}
OLDCFG

# The setup script must expose a migration that, given an existing config,
# ADDS patterns.test_file_marker="" when absent. We assert two complementary
# things so the test fails loudly today and passes only on a correct fix:
#
#  (1) setup's SOURCE references an additive migration of patterns.test_file_marker
#      that uses an "add-if-absent" idiom (`has(...)` / `// ""`), NOT an
#      unconditional overwrite.
if [ -f "$SETUP_SCRIPT" ]; then
  if grep -q 'test_file_marker' "$SETUP_SCRIPT" 2>/dev/null; then
    pass "DD-007-c1" "setup references patterns.test_file_marker migration"
  else
    fail "DD-007-c1" "setup does not reference patterns.test_file_marker migration"
  fi

  # The migration must be additive: it must guard with has()/if-absent or `// \"\"`
  # so a set value is never overwritten (AP-004 idempotency).
  if grep -E 'test_file_marker' "$SETUP_SCRIPT" 2>/dev/null \
       | grep -qE 'has\("?test_file_marker"?\)|test_file_marker // ""|test_file_marker.*//.*""|if .*test_file_marker'; then
    pass "DD-007-c2" "setup migration is additive (add-if-absent idiom, never overwrites a set value)"
  else
    fail "DD-007-c2" "setup migration for test_file_marker is not visibly additive (no has()/// guard)"
  fi
else
  fail "DD-007-c1" "setup script not found"
  fail "DD-007-c2" "setup script not found"
fi

#  (2) Behavioral: applying the additive migration idiom that setup MUST use
#      adds the key with "" when absent and preserves a pre-set value. We model
#      the contract the implementation must satisfy by running the canonical
#      additive jq on the fixture and asserting the result; the corresponding
#      assertion against the ACTUAL setup-invoked migration fails until setup
#      ships a function we can call. We assert the contract shape here so the
#      GREEN implementation has a pinned target.
#
# Pre-set-value preservation fixture:
PRESET_CFG="$mig_tmp/.correctless/config/workflow-config-preset.json"
cat > "$PRESET_CFG" <<'PRESETCFG'
{
  "schema_version": 1,
  "patterns": { "test_file": "*_test.go", "test_file_marker": ">>> {file}", "test_fail_pattern": "FAIL" }
}
PRESETCFG

# The contract: additive add-if-absent. We assert there is a setup function or
# inline block named for config migration that we can drive. The presence check
# is the gate; the value assertions pin the expected behavior.
if [ -f "$SETUP_SCRIPT" ] && grep -qE 'migrate.*config|config.*migrat|test_file_marker' "$SETUP_SCRIPT" 2>/dev/null; then
  # Drive setup's migration helper if it is independently sourceable. We look
  # for a function whose name contains "config" and "migrat"; if found, source
  # the script in a guarded subshell and call it. If no such callable exists,
  # this fails (the migration must be testable, not buried inline-only).
  mig_fn="$(grep -oE '^[a-zA-Z0-9_]*(migrate[a-zA-Z0-9_]*config|config[a-zA-Z0-9_]*migrat[a-zA-Z0-9_]*)[a-zA-Z0-9_]*\(\)' "$SETUP_SCRIPT" 2>/dev/null | head -1 | sed 's/().*//')"
  if [ -n "$mig_fn" ]; then
    # Add-if-absent: key gets "" on the old config.
    out_absent="$(bash -c "
      eval \"\$(sed -n '/^${mig_fn}()/,/^}/p' '$SETUP_SCRIPT')\" 2>/dev/null
      ${mig_fn} '$OLD_CFG' 2>/dev/null
      jq -r '.patterns.test_file_marker // \"__ABSENT__\"' '$OLD_CFG' 2>/dev/null
    " 2>/dev/null || true)"
    if [ "$out_absent" = "" ]; then
      pass "DD-007-c3" "setup migration adds patterns.test_file_marker=\"\" to a config that lacked it"
    else
      fail "DD-007-c3" "setup migration did not add empty test_file_marker (got: '$out_absent')"
    fi

    # Never-overwrite: a pre-set value survives migration.
    out_preset="$(bash -c "
      eval \"\$(sed -n '/^${mig_fn}()/,/^}/p' '$SETUP_SCRIPT')\" 2>/dev/null
      ${mig_fn} '$PRESET_CFG' 2>/dev/null
      jq -r '.patterns.test_file_marker' '$PRESET_CFG' 2>/dev/null
    " 2>/dev/null || true)"
    if [ "$out_preset" = ">>> {file}" ]; then
      pass "DD-007-c4" "setup migration preserves a pre-set patterns.test_file_marker value (idempotent, AP-004)"
    else
      fail "DD-007-c4" "setup migration overwrote a pre-set test_file_marker (got: '$out_preset', expected '>>> {file}')"
    fi
  else
    fail "DD-007-c3" "setup has no independently-callable config-migration function for test_file_marker"
    fail "DD-007-c4" "setup has no independently-callable config-migration function for test_file_marker"
  fi
else
  fail "DD-007-c3" "setup does not reference a config migration for test_file_marker"
  fail "DD-007-c4" "setup does not reference a config migration for test_file_marker"
fi

# ============================================================================
# INV-012 — ABS-030 sole-writer revision + R-006d allowlist adds cchores
# ============================================================================

section "INV-012: ABS-030 revision names cchores as authorized invoker"

# --- INV-012-a [unit]: ABS-030 sole-writer wording is REVISED to name the
# autonomous-decision-writer.sh script invoked by /cauto OR /cchores (not
# "/cauto orchestrator" alone). ---
if [ -f "$ARCH_FILE" ]; then
  # Pull the ABS-030 entry block (from its heading to the next ### heading).
  abs030_block="$(awk '/^### ABS-030/{f=1} f{print} /^### ABS-03[1-9]/{if(f && !/^### ABS-030/)exit}' "$ARCH_FILE" 2>/dev/null)"

  # The sole-writer line must name cchores as an authorized invoker.
  if echo "$abs030_block" | grep -qi 'cchores' ; then
    pass "INV-012-a1" "ABS-030 entry names /cchores as an authorized invoker"
  else
    fail "INV-012-a1" "ABS-030 entry does not name /cchores (sole-writer wording not revised)"
  fi

  # The sole-writer must be the SCRIPT (autonomous-decision-writer.sh invoked by
  # cauto OR cchores), not "/cauto orchestrator" as the sole writer.
  if echo "$abs030_block" | grep -qiE 'autonomous-decision-writer\.sh.*(cauto|cchores)|invoked by .*(cauto|cchores)' \
     && echo "$abs030_block" | grep -qi 'cchores'; then
    pass "INV-012-a2" "ABS-030 sole-writer is the writer script invoked by /cauto OR /cchores"
  else
    fail "INV-012-a2" "ABS-030 sole-writer wording still scoped to /cauto only (script-level OR-invoker revision missing)"
  fi
else
  fail "INV-012-a1" "ARCHITECTURE.md not found"
  fail "INV-012-a2" "ARCHITECTURE.md not found"
fi

# --- INV-012-b [unit]: tests/test-autonomous-skill-contract.sh R-006d allowlist
# ADDS `cchores` — i.e. /cchores is exempted (like /cauto) from the
# "no non-cauto skill writes autonomous-decisions" denylist. ---
#
# Today R-006d skips only `cauto`. The delta adds a `cchores` skip/allow.
if [ -f "$AUTON_CONTRACT_TEST" ]; then
  # Locate the R-006d block and assert it allowlists cchores alongside cauto.
  r006d_block="$(awk '/R-006d/{f=1} f{print} /^# ===/{if(f)c++; if(c>1)exit}' "$AUTON_CONTRACT_TEST" 2>/dev/null)"
  if echo "$r006d_block" | grep -qE '\[ "\$skill_name" = "cchores" \]|skill_name.*=.*cchores|"cchores"'; then
    pass "INV-012-b" "R-006d allowlist in test-autonomous-skill-contract.sh includes cchores"
  else
    # Fall back to a whole-file scan for a cchores allowlist entry near R-006d.
    if grep -qE 'skill_name.*=.*"cchores"|= "cchores"' "$AUTON_CONTRACT_TEST" 2>/dev/null; then
      pass "INV-012-b" "R-006d allowlist in test-autonomous-skill-contract.sh includes cchores"
    else
      fail "INV-012-b" "R-006d allowlist does not include cchores (only cauto is exempted today)"
    fi
  fi
else
  fail "INV-012-b" "tests/test-autonomous-skill-contract.sh not found"
fi

# ============================================================================
# OQ-005 — prune-scan.sh recognizes the three chore artifact patterns +
# cchores-attempted.json is durable (never a prune-deletion candidate)
#
# AP-031 real-fixture citation:
#   The wrapped-object output shape asserted below
#   ({candidates, skipped_unclassified, protection_set, protection_status})
#   is verbatim the structure emitted by scripts/prune-scan.sh --category
#   artifacts against this repo's live .correctless/artifacts/ on 2026-06-17.
#   Verified keys: ["candidates","protection_set","protection_status",
#   "skipped_unclassified"]; protection_set keys: ["live_branch_slugs",
#   "live_branches","live_session_ids","live_task_slugs",
#   "source_workflow_state_files"]; candidate slug_type observed: "branch-slug".
#   # Source: scripts/prune-scan.sh --category artifacts --base <repo> (live run)
# ============================================================================

section "OQ-005: prune-scan chore artifact patterns + meta-store durability"

# --- OQ-005-a [unit]: _classify_artifact_pattern classifies the three chore
# artifacts as `branch-slug`. ---
for _cp in "chore-run-*.json" "chore-abort-*.md" "chore-report-*.md"; do
  _got="$(classify_pattern "$_cp")"
  if [ "$_got" = "branch-slug" ]; then
    pass "OQ-005-a:$_cp" "_classify_artifact_pattern classifies '$_cp' as branch-slug"
  else
    fail "OQ-005-a:$_cp" "_classify_artifact_pattern returned '$_got' for '$_cp' (expected branch-slug)"
  fi
done

# Build a fixture base mirroring a REAL prune-scan invocation. We control the
# live branch set via --branches-file so the chore slug is deterministically
# STALE (live branch = main; chore slug = chore-issue-42-...). Once the patterns
# are recognized as branch-slug, the stale chore artifacts must surface as
# candidates. Today they are unrecognized → zero chore candidates → RED.
oq_tmp="$(mktemp -d)"; register_cleanup "$oq_tmp"
SCANNER_BIN="$(stage_scanner "$oq_tmp" || true)"
FIX_BASE="$oq_tmp/repo"
mkdir -p "$FIX_BASE/.correctless/artifacts" "$FIX_BASE/.correctless/meta"
(
  cd "$FIX_BASE" \
    && git init -q \
    && git config user.email t@example.com \
    && git config user.name tester \
    && git commit -q --allow-empty -m init \
    && git branch -m main
) >/dev/null 2>&1 || true

# Live branches: only `main` (chore branch is gone/merged → its artifacts stale).
printf 'main\n' > "$oq_tmp/branches.txt"

# The three gitignored chore artifacts for a NON-live (stale) branch slug.
CHORE_STEM="chore-issue-42-fix-thing-abc123"
printf '%s' '{"selected_issue":42,"status":"aborted"}' > "$FIX_BASE/.correctless/artifacts/chore-run-${CHORE_STEM}.json"
printf '%s' '# abort'  > "$FIX_BASE/.correctless/artifacts/chore-abort-${CHORE_STEM}.md"
printf '%s' '# report' > "$FIX_BASE/.correctless/artifacts/chore-report-${CHORE_STEM}.md"

# The durable cross-run store lives under .correctless/meta/ (NOT artifacts/).
# Place it where it belongs; it must never become a deletion candidate.
printf '%s' '{"schema_version":1,"attempts":[{"issue":42,"branch_slug":"'"$CHORE_STEM"'","outcome":"aborted"}]}' \
  > "$FIX_BASE/.correctless/meta/cchores-attempted.json"

run_artifacts_scan() {
  if [ -n "$SCANNER_BIN" ] && [ -f "$SCANNER_BIN" ]; then
    bash "$SCANNER_BIN" --category artifacts --base "$FIX_BASE" --branches-file "$oq_tmp/branches.txt" 2>/dev/null
  else
    bash "$PRUNE_SCAN" --category artifacts --base "$FIX_BASE" --branches-file "$oq_tmp/branches.txt" 2>/dev/null
  fi
}

scan_out="$(run_artifacts_scan)"

# --- OQ-005-b [integration]: scan output is the wrapped object (AP-031 shape). ---
if echo "$scan_out" | jq -e 'has("candidates") and has("skipped_unclassified") and has("protection_set") and has("protection_status")' >/dev/null 2>&1; then
  pass "OQ-005-b" "artifacts scan emits the wrapped object (candidates/skipped/protection_set/protection_status)"
else
  fail "OQ-005-b" "artifacts scan did not emit the expected wrapped-object shape"
fi

# --- OQ-005-c [integration]: each stale chore artifact is recognized as a
# branch-slug candidate (NOT silently skipped/unclassified). ---
for _stem_pair in "chore-run-${CHORE_STEM}.json" "chore-abort-${CHORE_STEM}.md" "chore-report-${CHORE_STEM}.md"; do
  _slug_type="$(echo "$scan_out" | jq -r --arg id "$_stem_pair" '.candidates[] | select(.id == $id) | .slug_type' 2>/dev/null | head -1)"
  if [ "$_slug_type" = "branch-slug" ]; then
    pass "OQ-005-c:$_stem_pair" "stale chore artifact '$_stem_pair' surfaces as a branch-slug candidate"
  else
    fail "OQ-005-c:$_stem_pair" "chore artifact '$_stem_pair' not recognized as branch-slug candidate (got slug_type='$_slug_type')"
  fi
done

# --- OQ-005-d [integration]: chore patterns are NOT routed into the
# skipped_unclassified bucket (which is where an unrecognized pattern lands). ---
chore_skipped="$(echo "$scan_out" | jq -r '[.skipped_unclassified[] | select(.pattern | test("^chore-"))] | length' 2>/dev/null || echo "?")"
if [ "$chore_skipped" = "0" ]; then
  pass "OQ-005-d" "no chore-* pattern is recorded as skipped_unclassified (patterns are classified)"
else
  fail "OQ-005-d" "chore-* patterns landed in skipped_unclassified ($chore_skipped entries) — classification rows missing"
fi

# --- OQ-005-e [integration]: the durable .correctless/meta/ store
# cchores-attempted.json is NEVER a prune-deletion candidate. The artifacts
# scanner only scans .correctless/artifacts/, so a correctly-placed meta file is
# structurally excluded — assert no candidate references it under ANY category. ---
attempted_as_candidate="$(echo "$scan_out" | jq -r '[.candidates[] | select((.id // "") | test("cchores-attempted")) ] | length' 2>/dev/null || echo "?")"
if [ "$attempted_as_candidate" = "0" ]; then
  pass "OQ-005-e1" "cchores-attempted.json is not an artifacts deletion candidate"
else
  fail "OQ-005-e1" "cchores-attempted.json appeared as a deletion candidate ($attempted_as_candidate) — meta store must be excluded"
fi

# Defensive: even if a cchores-attempted.json is mistakenly dropped into the
# artifacts dir, it must NOT classify as a prunable slug type (its pattern is
# not a branch/task/session slug artifact). A robust classifier returns
# 'unclassified' for it (→ skipped, never deleted).
attempted_classification="$(classify_pattern "cchores-attempted.json")"
if [ "$attempted_classification" = "unclassified" ] || [ -z "$attempted_classification" ]; then
  pass "OQ-005-e2" "cchores-attempted.json pattern is unclassified (never auto-pruned)"
else
  fail "OQ-005-e2" "cchores-attempted.json classified as '$attempted_classification' (must be unclassified/durable)"
fi

# --- OQ-005-f [unit]: the chore patterns are added to the prune baseline via
# --update-baseline (so they are not flagged forever as "newly added"). The
# baseline manifest must list all three chore patterns after an update. ---
bl_tmp="$(mktemp -d)"; register_cleanup "$bl_tmp"
BL_BASE="$bl_tmp/repo"
mkdir -p "$BL_BASE/.correctless/artifacts" "$BL_BASE/.correctless/meta"
(
  cd "$BL_BASE" && git init -q \
    && git config user.email t@example.com && git config user.name tester \
    && git commit -q --allow-empty -m init && git branch -m main
) >/dev/null 2>&1 || true
printf 'main\n' > "$bl_tmp/branches.txt"
BL_SCANNER="$(stage_scanner "$bl_tmp" || true)"
if [ -n "$BL_SCANNER" ] && [ -f "$BL_SCANNER" ]; then
  bash "$BL_SCANNER" --category artifacts --base "$BL_BASE" --branches-file "$bl_tmp/branches.txt" --update-baseline >/dev/null 2>&1 || true
else
  bash "$PRUNE_SCAN" --category artifacts --base "$BL_BASE" --branches-file "$bl_tmp/branches.txt" --update-baseline >/dev/null 2>&1 || true
fi
BL_FILE="$BL_BASE/.correctless/meta/prune-pattern-baseline.json"
if [ -f "$BL_FILE" ]; then
  bl_missing=""
  for _bp in "chore-run-*.json" "chore-abort-*.md" "chore-report-*.md"; do
    if ! jq -e --arg p "$_bp" '.patterns | index($p) != null' "$BL_FILE" >/dev/null 2>&1; then
      bl_missing="${bl_missing}${_bp} "
    fi
  done
  if [ -z "$bl_missing" ]; then
    pass "OQ-005-f" "--update-baseline records all three chore patterns in prune-pattern-baseline.json"
  else
    fail "OQ-005-f" "baseline missing chore patterns after --update-baseline: $bl_missing"
  fi
else
  fail "OQ-005-f" "--update-baseline did not produce prune-pattern-baseline.json"
fi

# ============================================================================
# Summary
# ============================================================================

summary "cchores infrastructure delta"
