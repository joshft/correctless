#!/usr/bin/env bash
# Correctless — InstructionsLoaded hook behavior tests
# Spec: .correctless/specs/instructionsloaded-hook.md
# Covers: INV-001, INV-002, INV-003, INV-004, INV-005, INV-010, INV-011,
#         INV-012a, INV-014, PRH-002, PRH-004.
#
# RED phase: hooks/instructions-loaded.sh does not exist yet, so the behavioral
# assertions below MUST FAIL (feature absent). The gitignore/prohibition guards
# (INV-010/PRH-002/PRH-004) assert the "bad thing" is absent and may pass now.
#
# Run from repo root: bash tests/test-instructions-loaded.sh

# shellcheck disable=SC1090,SC1091,SC2016
source "$(dirname "${BASH_SOURCE[0]}")/test-helpers.sh"

echo "InstructionsLoaded Hook Behavior Tests"
echo "======================================"

IL_HOOK="$REPO_DIR/hooks/instructions-loaded.sh"
LIB_SH="$REPO_DIR/scripts/lib.sh"
FIXTURES="$REPO_DIR/tests/fixtures"
LOG_REL=".correctless/meta/instructions-loaded.jsonl"

# ============================================================================
# Env helpers — build an isolated temp project mirroring the hook's runtime
# layout (hooks/ sibling to scripts/lib.sh; .correctless/meta/ writable).
# ============================================================================

ENV_DIRS=()
cleanup_envs() { local d; for d in "${ENV_DIRS[@]:-}"; do [ -n "$d" ] && rm -rf "$d"; done; }
trap cleanup_envs EXIT

# make_env [with_lib=yes|no] -> prints temp dir path
make_env() {
  local with_lib="${1:-yes}"
  local d; d="$(mktemp -d "/tmp/correctless-il-XXXXXX")"
  ENV_DIRS+=("$d")
  mkdir -p "$d/hooks" "$d/scripts" "$d/.correctless/meta"
  [ -f "$IL_HOOK" ] && cp "$IL_HOOK" "$d/hooks/instructions-loaded.sh" 2>/dev/null
  if [ "$with_lib" = "yes" ]; then
    cp "$LIB_SH" "$d/scripts/lib.sh" 2>/dev/null
  fi
  printf '%s' "$d"
}

# il_run <env_dir> <payload> -> prints hook exit code (127 if hook absent)
il_run() {
  local d="$1" payload="$2" rc=0
  printf '%s' "$payload" | ( cd "$d" && bash hooks/instructions-loaded.sh ) >/dev/null 2>&1 || rc=$?
  printf '%s' "$rc"
}

# il_run_nojq <env_dir> <payload> -> like il_run but with a restricted PATH that
# contains bash + coreutils but NOT jq, so `command -v jq` correctly returns false
# and the hook's real missing-jq -> exit 0 path is exercised.
#
# NOTE: PATH="/nonexistent" is WRONG here — the shell cannot resolve `bash` itself
# (rc 127 before the hook runs), so it would test the harness, not the hook. This
# uses the established symlink-farm pattern (see test-antipattern-scan.sh QA-007).
il_run_nojq() {
  local d="$1" payload="$2" rc=0
  local fake_bin; fake_bin="$(mktemp -d "/tmp/correctless-il-nojq-XXXXXX")"
  ENV_DIRS+=("$fake_bin")
  # Symlink the REAL commands the hook (and its sourced lib.sh) may invoke —
  # everything EXCEPT jq. `command -v`/`printf`/`cd`/`pwd` are bash builtins.
  local cmd cmd_path
  for cmd in bash cat date mkdir dirname basename rm mv sed grep awk cut tr head tail wc sort env ln readlink ps md5sum; do
    cmd_path="$(command -v "$cmd" 2>/dev/null || true)"
    [ -n "$cmd_path" ] && ln -sf "$cmd_path" "$fake_bin/$cmd"
  done
  printf '%s' "$payload" | ( cd "$d" && PATH="$fake_bin" bash hooks/instructions-loaded.sh ) >/dev/null 2>&1 || rc=$?
  printf '%s' "$rc"
}

log_lines() {
  local d="$1" f="$1/$LOG_REL"
  if [ -f "$f" ]; then wc -l < "$f" | tr -d ' '; else echo 0; fi
}
last_log_line() {
  local f="$1/$LOG_REL"
  [ -f "$f" ] && tail -1 "$f" || printf ''
}

# Reusable payloads (jq-built where embedded control chars are needed)
RULE_PAYLOAD='{"session_id":"s-1","file_path":".claude/rules/hooks-pretooluse.md","trigger_file_path":"hooks/workflow-gate.sh","load_reason":"path_glob_match","cwd":"/proj"}'
# A4: real harness payloads carry an ABSOLUTE file_path where `.claude/rules/` is
# a mid-path component — canonicalize_path + prefix-check must still match.
ABS_RULE_PAYLOAD='{"session_id":"s-1","file_path":"/home/user/project/.claude/rules/hooks-pretooluse.md","trigger_file_path":"hooks/workflow-gate.sh","load_reason":"path_glob_match","cwd":"/home/user/project"}'
CLAUDEMD_PAYLOAD='{"session_id":"s-1","file_path":"CLAUDE.md","load_reason":"path_glob_match","cwd":"/proj"}'
TRAVERSAL_PAYLOAD='{"session_id":"s-1","file_path":".claude/rules/../../etc/passwd","load_reason":"path_glob_match","cwd":"/proj"}'
NULLPATH_GLOB_PAYLOAD='{"session_id":"s-1","load_reason":"path_glob_match","cwd":"/proj"}'
NULLPATH_START_PAYLOAD='{"session_id":"s-1","load_reason":"session_start","cwd":"/proj"}'

# ============================================================================
# INV-001 [unit]: Hook is fail-open (exit 0 on every degenerate input)
# ============================================================================
section "INV-001: hook is fail-open"

if [ ! -f "$IL_HOOK" ]; then
  fail "INV-001" "hooks/instructions-loaded.sh does not exist (RED: feature absent)"
fi

# empty stdin -> exit 0, no log
d="$(make_env yes)"
rc="$(il_run "$d" "")"
if [ "$rc" = "0" ]; then pass "INV-001a" "empty stdin -> exit 0"; else fail "INV-001a" "empty stdin exit was '$rc' (want 0)"; fi
if [ "$(log_lines "$d")" = "0" ]; then pass "INV-001a-nolog" "empty stdin writes no log"; else fail "INV-001a-nolog" "empty stdin wrote a log line"; fi

# malformed JSON -> exit 0
d="$(make_env yes)"
rc="$(il_run "$d" '{not valid json')"
if [ "$rc" = "0" ]; then pass "INV-001b" "malformed JSON -> exit 0"; else fail "INV-001b" "malformed JSON exit was '$rc' (want 0)"; fi

# missing jq (PATH stripped) -> exit 0
d="$(make_env yes)"
rc="$(il_run_nojq "$d" "$RULE_PAYLOAD")"
if [ "$rc" = "0" ]; then pass "INV-001c" "missing jq -> exit 0"; else fail "INV-001c" "missing-jq exit was '$rc' (want 0)"; fi

# unwritable .correctless/meta -> exit 0 (skip when running as root, chmod is a no-op)
d="$(make_env yes)"
chmod 000 "$d/.correctless/meta" 2>/dev/null || true
if [ "$(id -u)" = "0" ]; then
  skip "INV-001d" "running as root — unwritable-dir perms not enforceable"
else
  rc="$(il_run "$d" "$RULE_PAYLOAD")"
  if [ "$rc" = "0" ]; then pass "INV-001d" "unwritable meta dir -> exit 0"; else fail "INV-001d" "unwritable-meta exit was '$rc' (want 0)"; fi
fi
chmod 755 "$d/.correctless/meta" 2>/dev/null || true

# RS-031: missing lib.sh / absent canonicalize_path -> exit 0 with NO log
d="$(make_env no)"   # no scripts/lib.sh copied
rc="$(il_run "$d" "$RULE_PAYLOAD")"
if [ "$rc" = "0" ]; then pass "INV-001e" "missing lib.sh -> exit 0 (RS-031)"; else fail "INV-001e" "missing-lib exit was '$rc' (want 0)"; fi
if [ "$(log_lines "$d")" = "0" ]; then pass "INV-001e-nolog" "missing lib.sh writes NO log (no un-canonicalized fallback)"; else fail "INV-001e-nolog" "missing lib.sh wrote a log line — un-canonicalized fallback is forbidden (RS-031)"; fi

# grep: set -f present, set -e / set -euo pipefail ABSENT
if [ -f "$IL_HOOK" ]; then
  if grep -qE '^[[:space:]]*set -f' "$IL_HOOK"; then pass "INV-001f" "hook sets 'set -f'"; else fail "INV-001f" "hook missing 'set -f'"; fi
  if grep -qE '^[[:space:]]*set -(e|euo)' "$IL_HOOK"; then fail "INV-001g" "hook uses strict mode (set -e/-euo) — forbidden fail-open violation"; else pass "INV-001g" "hook has no 'set -e'/'set -euo pipefail'"; fi
else
  fail "INV-001f" "hook absent — cannot verify 'set -f'"
  fail "INV-001g" "hook absent — cannot verify absence of strict mode"
fi

# ============================================================================
# INV-002 [unit]: Fast-path scope — rule-file loads only, canonicalize_path
# ============================================================================
section "INV-002: fast-path scope (rule-file loads only)"

# (a) rule-file load -> writes exactly one line
d="$(make_env yes)"
il_run "$d" "$RULE_PAYLOAD" >/dev/null
if [ "$(log_lines "$d")" = "1" ]; then pass "INV-002a" "rule-file load writes one entry"; else fail "INV-002a" "rule-file load wrote $(log_lines "$d") lines (want 1)"; fi

# (a2) A4: ABSOLUTE file_path under .claude/rules/ -> writes exactly one line.
# Asserts absolute-vs-relative prefix handling directly (canonicalize_path plus
# prefix-check must recognize `.claude/rules/` as a mid-path component), not only
# implicitly via the INV-012a round-trip.
d="$(make_env yes)"
il_run "$d" "$ABS_RULE_PAYLOAD" >/dev/null
if [ "$(log_lines "$d")" = "1" ]; then pass "INV-002a2" "absolute .claude/rules/ file_path writes one entry"; else fail "INV-002a2" "absolute .claude/rules/ file_path wrote $(log_lines "$d") lines (want 1) — absolute-path prefix handling missing"; fi

# (b) CLAUDE.md load -> no write
d="$(make_env yes)"
il_run "$d" "$CLAUDEMD_PAYLOAD" >/dev/null
if [ "$(log_lines "$d")" = "0" ]; then pass "INV-002b" "CLAUDE.md load writes no entry"; else fail "INV-002b" "CLAUDE.md load wrote a log line"; fi

# (c) traversal payload that canonicalizes OUTSIDE .claude/rules/ -> no write
d="$(make_env yes)"
il_run "$d" "$TRAVERSAL_PAYLOAD" >/dev/null
if [ "$(log_lines "$d")" = "0" ]; then pass "INV-002c" "traversal (.claude/rules/../../etc) writes no entry"; else fail "INV-002c" "traversal payload wrote a log line — canonicalize+prefix bypass (AP-032)"; fi

# (d) absent file_path + path_glob_match -> writes null rule_file
d="$(make_env yes)"
il_run "$d" "$NULLPATH_GLOB_PAYLOAD" >/dev/null
if [ "$(log_lines "$d")" = "1" ]; then
  pass "INV-002d" "absent file_path + path_glob_match writes one entry"
  rf="$(last_log_line "$d" | jq -r '.rule_file' 2>/dev/null || echo ERR)"
  if [ "$rf" = "null" ]; then pass "INV-002d-null" "null-path entry has rule_file:null"; else fail "INV-002d-null" "rule_file was '$rf' (want null)"; fi
else
  fail "INV-002d" "absent file_path + path_glob_match wrote $(log_lines "$d") lines (want 1)"
  fail "INV-002d-null" "no entry to inspect for rule_file:null"
fi

# (e) absent file_path + session_start -> no write
d="$(make_env yes)"
il_run "$d" "$NULLPATH_START_PAYLOAD" >/dev/null
if [ "$(log_lines "$d")" = "0" ]; then pass "INV-002e" "absent file_path + session_start writes no entry"; else fail "INV-002e" "absent-path non-glob reason wrote a log line"; fi

# grep: path decision uses canonicalize_path (PAT-017), not substring/suffix
if [ -f "$IL_HOOK" ]; then
  if grep -q 'canonicalize_path' "$IL_HOOK"; then pass "INV-002f" "hook uses canonicalize_path (PAT-017)"; else fail "INV-002f" "hook does not reference canonicalize_path — substring/suffix matching is prohibited (AP-032/RS-011)"; fi
else
  fail "INV-002f" "hook absent — cannot verify canonicalize_path usage"
fi

# ============================================================================
# INV-003 [unit]: JSONL entry schema
# ============================================================================
section "INV-003: JSONL entry schema"

d="$(make_env yes)"
il_run "$d" "$RULE_PAYLOAD" >/dev/null
line="$(last_log_line "$d")"
if [ -n "$line" ] && printf '%s' "$line" | jq -e . >/dev/null 2>&1; then
  pass "INV-003a" "appended line is valid JSON (jq -e .)"
  for field in ts session_id rule_file trigger_file_path load_reason cwd; do
    if printf '%s' "$line" | jq -e "has(\"$field\")" >/dev/null 2>&1; then
      pass "INV-003-$field" "entry has field '$field'"
    else
      fail "INV-003-$field" "entry missing required field '$field'"
    fi
  done
  ts="$(printf '%s' "$line" | jq -r '.ts' 2>/dev/null)"
  if printf '%s' "$ts" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$'; then
    pass "INV-003-ts" "ts matches audit-trail date -u +%FT%TZ format"
  else
    fail "INV-003-ts" "ts '$ts' does not match ^YYYY-MM-DDTHH:MM:SSZ\$"
  fi
  if printf '%s' "$line" | jq -e 'has("transcript_path")' >/dev/null 2>&1; then
    fail "INV-003-notp" "entry contains transcript_path (forbidden home-path disclosure — RS-024b)"
  else
    pass "INV-003-notp" "entry has no transcript_path field"
  fi
else
  fail "INV-003a" "no valid JSON line produced (RED: feature absent)"
  for field in ts session_id rule_file trigger_file_path load_reason cwd ts-fmt notp; do
    fail "INV-003-$field" "no entry to inspect"
  done
fi

# ============================================================================
# INV-004 [unit]: Safe extraction AND safe serialization
# ============================================================================
section "INV-004: safe extraction + jq -n serialization"

# (a) shell metacharacters in file_path -> logged literally, no command execution
d="$(make_env yes)"
META_PAYLOAD='{"session_id":"s","file_path":".claude/rules/$(touch PWNED).md","trigger_file_path":"x","load_reason":"path_glob_match","cwd":"/proj"}'
il_run "$d" "$META_PAYLOAD" >/dev/null
if [ ! -e "$d/PWNED" ]; then pass "INV-004a" "metacharacter file_path did not execute (no PWNED file)"; else fail "INV-004a" "command substitution in file_path executed — shell injection"; fi

# (b) embedded newline in a field -> exactly ONE jsonl line
d="$(make_env yes)"
NL_PAYLOAD="$(jq -nc '{session_id:"s", file_path:".claude/rules/a\nb.md", trigger_file_path:"x\ny", load_reason:"path_glob_match", cwd:"/proj"}')"
il_run "$d" "$NL_PAYLOAD" >/dev/null
nl_lines="$(log_lines "$d")"
if [ "$nl_lines" = "1" ]; then pass "INV-004b" "embedded newline yields exactly one JSONL line"; else fail "INV-004b" "embedded newline produced $nl_lines lines (want 1) — record-injection risk (RS-020)"; fi

# (c) grep: log line built via jq -n, not printf/echo interpolation
if [ -f "$IL_HOOK" ]; then
  if grep -qE 'jq -n' "$IL_HOOK"; then pass "INV-004c" "hook builds log line via jq -n"; else fail "INV-004c" "hook does not use 'jq -n' to serialize the log line (RS-020)"; fi
else
  fail "INV-004c" "hook absent — cannot verify jq -n serialization"
fi

# ============================================================================
# INV-005 [unit]: Absent/malformed loaded-path — null logging for observability
# (both null-path branches already exercised by INV-002d/002e; assert exit 0)
# ============================================================================
section "INV-005: null-path branches exit 0"

d="$(make_env yes)"
rc="$(il_run "$d" "$NULLPATH_GLOB_PAYLOAD")"
if [ "$rc" = "0" ]; then pass "INV-005a" "null-path path_glob_match branch exits 0"; else fail "INV-005a" "null-path glob branch exit '$rc' (want 0)"; fi
d="$(make_env yes)"
rc="$(il_run "$d" "$NULLPATH_START_PAYLOAD")"
if [ "$rc" = "0" ]; then pass "INV-005b" "null-path session_start branch exits 0"; else fail "INV-005b" "null-path non-glob branch exit '$rc' (want 0)"; fi

# ============================================================================
# INV-011 [unit]: Append-only, O(1) writes (behavioral, bounded medium)
# ============================================================================
section "INV-011: append-only behavioral"

d="$(make_env yes)"
# Pre-seed the log with N known lines
mkdir -p "$d/.correctless/meta"
{
  echo '{"seed":1}'
  echo '{"seed":2}'
  echo '{"seed":3}'
} > "$d/$LOG_REL"
before="$(log_lines "$d")"
before_hash="$(head -n "$before" "$d/$LOG_REL" | shasum 2>/dev/null | awk '{print $1}')"
il_run "$d" "$RULE_PAYLOAD" >/dev/null
after="$(log_lines "$d")"
grew=$((after - before))
if [ "$grew" = "1" ]; then pass "INV-011a" "log grew by exactly one line"; else fail "INV-011a" "log grew by $grew lines (want 1)"; fi
after_first_hash="$(head -n "$before" "$d/$LOG_REL" | shasum 2>/dev/null | awk '{print $1}')"
if [ "$before_hash" = "$after_first_hash" ]; then pass "INV-011b" "first N lines byte-identical after append"; else fail "INV-011b" "pre-existing lines were rewritten (not append-only)"; fi
appended="$(tail -1 "$d/$LOG_REL")"
if printf '%s' "$appended" | jq -e . >/dev/null 2>&1; then pass "INV-011c" "appended line is valid JSON"; else fail "INV-011c" "appended line is not valid JSON"; fi

# secondary tripwire: hook never reads the whole log file into a variable/argv
if [ -f "$IL_HOOK" ]; then
  if grep -qE '\$\(cat[^)]*instructions-loaded|<[[:space:]]*"?\$?\{?[A-Z_]*LOG' "$IL_HOOK"; then
    fail "INV-011d" "hook appears to read the whole log file (ARG_MAX exposure — AP-039)"
  else
    pass "INV-011d" "hook does not read the whole log file"
  fi
else
  fail "INV-011d" "hook absent — cannot verify O(1) append"
fi

# ============================================================================
# INV-012a [unit]: Real captured payload fixture (AP-031) — presence + round-trip
# Source: .correctless/artifacts/dd004-raw-capture.json (sanitized per DD-004
#         capture record; harness 2.1.185, load_reason=path_glob_match)
# ============================================================================
section "INV-012a: real captured payload fixture (AP-031)"

FIX="$FIXTURES/instructionsloaded-real-payload.json"
if [ -f "$FIX" ] && jq -e . "$FIX" >/dev/null 2>&1; then
  pass "INV-012a-valid" "fixture passes jq -e ."
  for k in file_path trigger_file_path load_reason session_id; do
    if jq -e "has(\"$k\")" "$FIX" >/dev/null 2>&1; then
      pass "INV-012a-key-$k" "fixture has required key '$k'"
    else
      fail "INV-012a-key-$k" "fixture missing required key '$k'"
    fi
  done
else
  fail "INV-012a-valid" "fixture missing or invalid JSON"
  for k in file_path trigger_file_path load_reason session_id; do fail "INV-012a-key-$k" "fixture absent"; done
fi

# ROUND-TRIP (the high-value AP-031 check): pipe fixture through the hook,
# expect exactly one line satisfying the full INV-003 schema.
d="$(make_env yes)"
if [ -f "$FIX" ]; then
  il_run "$d" "$(cat "$FIX")" >/dev/null
fi
rt_lines="$(log_lines "$d")"
if [ "$rt_lines" = "1" ]; then
  pass "INV-012a-rt" "real payload round-trips to exactly one entry"
  rtline="$(last_log_line "$d")"
  ok=true
  for field in ts session_id rule_file trigger_file_path load_reason cwd; do
    printf '%s' "$rtline" | jq -e "has(\"$field\")" >/dev/null 2>&1 || ok=false
  done
  printf '%s' "$rtline" | jq -r '.ts' 2>/dev/null | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$' || ok=false
  if [ "$ok" = true ]; then pass "INV-012a-rt-schema" "round-trip entry satisfies INV-003 schema"; else fail "INV-012a-rt-schema" "round-trip entry violates INV-003 schema"; fi
else
  fail "INV-012a-rt" "real payload did not round-trip (RED: feature absent) — got $rt_lines lines"
  fail "INV-012a-rt-schema" "no round-trip entry to inspect"
fi

# ============================================================================
# INV-010 [unit]: Log is gitignored runtime telemetry
# ============================================================================
section "INV-010: log is gitignored"

if git -C "$REPO_DIR" check-ignore -q ".correctless/meta/instructions-loaded.jsonl"; then
  pass "INV-010" ".correctless/meta/instructions-loaded.jsonl is gitignored"
else
  fail "INV-010" "instructions-loaded.jsonl is NOT matched by .gitignore"
fi

# ============================================================================
# INV-014 [unit]: Source <-> distribution mirror parity (RS-024c strip transform)
# ============================================================================
section "INV-014: mirror parity (sync.sh strip transform, never raw cmp)"

check_mirror() {
  local base="$1" src="$REPO_DIR/hooks/$1" dst="$REPO_DIR/correctless/hooks/$1"
  if [ ! -f "$src" ]; then fail "INV-014-$base-src" "source hooks/$base missing (RED)"; return; fi
  pass "INV-014-$base-src" "source hooks/$base exists"
  if [ ! -f "$dst" ]; then fail "INV-014-$base-mirror" "mirror correctless/hooks/$base missing (RED)"; return; fi
  # RS-024c: compare using the same `# Rule: `-line strip transform sync.sh uses
  if diff -q <(sed '/^# Rule: /d' "$src") "$dst" >/dev/null 2>&1; then
    pass "INV-014-$base-parity" "hooks/$base mirror has no strip-transform drift"
  else
    fail "INV-014-$base-parity" "hooks/$base drifts from its mirror"
  fi
}
check_mirror "instructions-loaded.sh"
check_mirror "audit-trail.sh"

# ============================================================================
# PRH-002 [unit]: Log path must NOT be in sensitive-file-guard DEFAULTS
# ============================================================================
section "PRH-002: log not in sensitive-file-guard DEFAULTS"

SFG="$REPO_DIR/hooks/sensitive-file-guard.sh"
if grep -q 'instructions-loaded.jsonl' "$SFG" 2>/dev/null; then
  fail "PRH-002" "instructions-loaded.jsonl present in SFG (AP-037 friction on AP-040 non-threat)"
else
  pass "PRH-002" "instructions-loaded.jsonl absent from sensitive-file-guard.sh"
fi

# ============================================================================
# PRH-004 [unit]: No gate/phase-transition may depend on the log
# ============================================================================
section "PRH-004: no gate depends on the log path"

prh004_fail=false
for f in "$REPO_DIR/hooks/workflow-advance.sh" "$REPO_DIR"/hooks/*.sh "$REPO_DIR"/scripts/wf/*.sh; do
  [ -f "$f" ] || continue
  if grep -q 'instructions-loaded.jsonl' "$f" 2>/dev/null; then
    echo "    log path referenced in: ${f#"$REPO_DIR"/}"
    prh004_fail=true
  fi
done
if [ "$prh004_fail" = true ]; then
  fail "PRH-004" "log path referenced in a gate/phase-transition script (must be absent)"
else
  pass "PRH-004" "log path absent from workflow-advance.sh / hooks/*.sh / scripts/wf/*.sh"
fi

summary "test-instructions-loaded"
