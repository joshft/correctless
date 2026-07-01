#!/usr/bin/env bash
# Correctless — audit-trail.sh session-identity field tests
# Spec: .correctless/specs/instructionsloaded-hook.md — INV-015
#
# INV-015: hooks/audit-trail.sh extracts the harness stdin `session_id` (the
# SAME documented field the InstructionsLoaded hook reads — NOT lib.sh's
# PID-based get_current_session_id) and includes it in every entry alongside
# the existing ts, phase, tool, file, branch fields. Additive + backward-compatible.
#
# RED phase: audit-trail.sh does not yet extract session_id, so the entry it
# emits will lack the field and INV-015a/b MUST FAIL.
#
# Run from repo root: bash tests/test-audit-trail.sh

# shellcheck disable=SC1090,SC1091,SC2016
source "$(dirname "${BASH_SOURCE[0]}")/test-helpers.sh"

echo "audit-trail.sh Session-Field Tests (INV-015)"
echo "============================================"

AUDIT_HOOK="$REPO_DIR/hooks/audit-trail.sh"
LIB_SH="$REPO_DIR/scripts/lib.sh"
FIXTURES="$REPO_DIR/tests/fixtures"

ENV_DIRS=()
cleanup_envs() { local d; for d in "${ENV_DIRS[@]:-}"; do [ -n "$d" ] && rm -rf "$d"; done; }
trap cleanup_envs EXIT

# Build a temp git project with the audit-trail runtime layout, run the hook
# once with a payload carrying session_id, and return the produced entry.
run_audit_with_session() {  # $1 = session_id value ; prints last audit-trail line
  local sid="$1"
  local d; d="$(mktemp -d "/tmp/correctless-audit-XXXXXX")"
  ENV_DIRS+=("$d")
  mkdir -p "$d/hooks" "$d/scripts" "$d/.correctless/artifacts" "$d/.correctless/config"
  cp "$AUDIT_HOOK" "$d/hooks/audit-trail.sh" 2>/dev/null || return 1
  cp "$LIB_SH" "$d/scripts/lib.sh" 2>/dev/null || return 1
  (
    cd "$d" || exit 1
    git init -q 2>/dev/null
    git checkout -b feature/il-audit-test -q 2>/dev/null || git branch -M feature/il-audit-test 2>/dev/null
    # Compute the branch slug the hook will use, then seed a matching state file.
    # shellcheck disable=SC1091
    slug="$(source scripts/lib.sh 2>/dev/null; branch_slug 2>/dev/null)"
    [ -n "$slug" ] || slug="unknown"
    printf '{"phase":"tdd-impl","task":"il-audit"}\n' > ".correctless/artifacts/workflow-state-${slug}.json"
    printf '{"patterns":{"test_file":"tests/test-*.sh","source_file":"hooks/*.sh"},"workflow":{"intensity":"low"}}\n' > ".correctless/config/workflow-config.json"
    payload="$(jq -nc --arg s "$sid" '{tool_name:"Edit", tool_input:{file_path:"hooks/foo.sh"}, session_id:$s}')"
    printf '%s' "$payload" | bash hooks/audit-trail.sh >/dev/null 2>&1 || true
  )
  local trail
  trail="$(ls "$d"/.correctless/artifacts/audit-trail-*.jsonl 2>/dev/null | head -1)"
  [ -n "$trail" ] && tail -1 "$trail" || printf ''
}

# ============================================================================
# INV-015a: entry includes session_id sourced from the harness stdin field
# ============================================================================
section "INV-015a: audit entry carries harness session_id"

if [ ! -f "$AUDIT_HOOK" ]; then
  fail "INV-015a" "hooks/audit-trail.sh not found"
else
  line="$(run_audit_with_session "sess-abc-123")"
  if [ -n "$line" ] && printf '%s' "$line" | jq -e . >/dev/null 2>&1; then
    got="$(printf '%s' "$line" | jq -r '.session_id // "<<absent>>"' 2>/dev/null)"
    if [ "$got" = "sess-abc-123" ]; then
      pass "INV-015a" "audit entry session_id == harness stdin session_id"
    else
      fail "INV-015a" "audit entry session_id is '$got' (want 'sess-abc-123' from stdin)"
    fi
    # existing fields retained (backward-compatible additive change)
    keep_ok=true
    for f in ts phase tool file branch; do
      printf '%s' "$line" | jq -e "has(\"$f\")" >/dev/null 2>&1 || keep_ok=false
    done
    if [ "$keep_ok" = true ]; then pass "INV-015b" "existing fields ts/phase/tool/file/branch retained"; else fail "INV-015b" "an existing audit field was dropped"; fi
  else
    fail "INV-015a" "no valid audit entry produced (RED: session field / run absent)"
    fail "INV-015b" "no audit entry to inspect for retained fields"
  fi
fi

# ============================================================================
# INV-015c: empty/null session_id is shown as such (never treated as a match)
# ============================================================================
section "INV-015c: empty session_id shown as-is"

if [ -f "$AUDIT_HOOK" ]; then
  line="$(run_audit_with_session "")"
  if [ -n "$line" ] && printf '%s' "$line" | jq -e 'has("session_id")' >/dev/null 2>&1; then
    val="$(printf '%s' "$line" | jq -r '.session_id' 2>/dev/null)"
    if [ "$val" = "" ] || [ "$val" = "null" ]; then
      pass "INV-015c" "empty stdin session_id surfaced as empty/null"
    else
      fail "INV-015c" "empty session_id was rewritten to '$val'"
    fi
    # QA-001 / INV-015: canonical-empty->null. An empty stdin session_id MUST be
    # emitted as JSON null (not ""), matching hooks/instructions-loaded.sh. This
    # is the producer half of the guarantee that a "" session can never form its
    # own /cwtf group or match a real session — it collapses to the same shape as
    # a genuinely absent session.
    if printf '%s' "$line" | jq -e '.session_id == null' >/dev/null 2>&1; then
      pass "INV-015c-null" "empty stdin session_id normalized to JSON null (not empty string)"
    else
      _stype="$(printf '%s' "$line" | jq -r '.session_id | type' 2>/dev/null)"
      fail "INV-015c-null" "empty session_id emitted as JSON $_stype, want null (canonical-empty->null)"
    fi
  else
    fail "INV-015c" "entry lacks session_id field for empty-session case (RED)"
    fail "INV-015c-null" "no audit entry to inspect for canonical-empty->null"
  fi
else
  fail "INV-015c" "hooks/audit-trail.sh not found"
  fail "INV-015c-null" "hooks/audit-trail.sh not found"
fi

# ============================================================================
# INV-015d: session_id sourced from stdin, NOT lib.sh get_current_session_id
# (grep guard — the field must be extracted alongside the other stdin fields)
# ============================================================================
section "INV-015d: session_id source is stdin, not PID-based"

if [ -f "$AUDIT_HOOK" ]; then
  if grep -qE 'session_id.*\\\(\.session_id|\.session_id' "$AUDIT_HOOK"; then
    pass "INV-015d-src" "audit-trail extracts .session_id from stdin"
  else
    fail "INV-015d-src" "audit-trail does not extract stdin .session_id (INV-015)"
  fi
  if grep -q 'get_current_session_id' "$AUDIT_HOOK"; then
    fail "INV-015d-nopid" "audit-trail uses lib.sh get_current_session_id (PID-based — forbidden source)"
  else
    pass "INV-015d-nopid" "audit-trail does not use PID-based get_current_session_id"
  fi
else
  fail "INV-015d-src" "hooks/audit-trail.sh not found"
  fail "INV-015d-nopid" "hooks/audit-trail.sh not found"
fi

# ============================================================================
# INV-015 (AP-031): presentation parsing tested against a REAL audit-trail
# entry (verbatim repo copy), not a hand-authored fixture.
# Source: .correctless/artifacts/audit-trail-*.jsonl (verbatim lines)
# ============================================================================
section "INV-015 AP-031: parse real audit-trail fixture"

AUDIT_REAL="$FIXTURES/audit-trail-real.jsonl"
if [ -f "$AUDIT_REAL" ]; then
  bad="$(jq -Rc 'fromjson? // empty' "$AUDIT_REAL" 2>/dev/null | grep -c . )"
  total="$(grep -c . "$AUDIT_REAL")"
  if [ "$bad" = "$total" ] && [ "$total" -ge 3 ]; then
    pass "INV-015-real" "real audit-trail fixture parses via try/catch consumer contract"
  else
    fail "INV-015-real" "real audit-trail fixture did not fully parse ($bad/$total)"
  fi
  # .ts // .timestamp resolves on the real mixed-shape lines
  resolved="$(jq -R 'fromjson? | (.ts // .timestamp) // empty' "$AUDIT_REAL" 2>/dev/null | grep -c .)"
  if [ "$resolved" -ge 3 ]; then pass "INV-015-real-time" ".ts // .timestamp resolves on real entries"; else fail "INV-015-real-time" ".ts // .timestamp resolved on $resolved real entries"; fi
else
  fail "INV-015-real" "audit-trail-real.jsonl fixture missing"
  fail "INV-015-real-time" "audit-trail-real.jsonl fixture missing"
fi

summary "test-audit-trail"
