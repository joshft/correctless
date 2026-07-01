#!/usr/bin/env bash
# Correctless — /cwtf rule-load presentation tests
# Spec: .correctless/specs/instructionsloaded-hook.md
# Covers: INV-008, INV-009, INV-016, PRH-005 (the /cwtf presentation section).
#
# /cwtf is a prose SKILL.md. The PRIMARY INV-008 check (B1) is an EXECUTABLE
# CONTRACT: the test extracts a runnable rule-load presentation block from
# skills/cwtf/SKILL.md (delimited by the cwtf:rule-load-extract markers) and runs
# it over real fixtures, asserting on OUTPUT behavior (RS-027 edit-session
# grouping, RS-030 .ts // .timestamp, PRH-005 no verdict) — NOT on prose. The
# contract greps over SKILL.md remain as a cheap secondary tripwire only. Both
# MUST FAIL now because the presentation section does not exist yet.
#
# The fixture-integrity + safe-parse demonstrations exercise the exact jq
# pipelines the section will run over real fixtures (AP-031) — these validate
# fixture realness and the consumer contract; they may pass now.
#
# Run from repo root: bash tests/test-instructions-loaded-cwtf.sh

# shellcheck disable=SC1090,SC1091,SC2016
source "$(dirname "${BASH_SOURCE[0]}")/test-helpers.sh"

echo "/cwtf Rule-Load Presentation Tests"
echo "=================================="

CWTF="$REPO_DIR/skills/cwtf/SKILL.md"
FIXTURES="$REPO_DIR/tests/fixtures"
# Source: verbatim repo copies (AP-031) —
#   audit-trail-real.jsonl   <- .correctless/artifacts/audit-trail-*.jsonl
#   log/sessioned fixtures    <- derived-from-real post-feature shapes (session_id added)
LOG_SAMPLE="$FIXTURES/instructions-loaded-log-sample.jsonl"
LOG_ALLNULL="$FIXTURES/instructions-loaded-log-allnull.jsonl"
AUDIT_REAL="$FIXTURES/audit-trail-real.jsonl"
AUDIT_SESS="$FIXTURES/audit-trail-sessioned.jsonl"

CWTF_BODY=""
[ -f "$CWTF" ] && CWTF_BODY="$(cat "$CWTF")"

has() { grep -qiE -- "$1" <<< "$CWTF_BODY"; }

# ----------------------------------------------------------------------------
# GREEN CONTRACT for the INV-008 executable block (DD-008: no new helper script,
# so the runnable pipeline lives IN skills/cwtf/SKILL.md and this test extracts
# and runs it). GREEN MUST add a fenced code block to skills/cwtf/SKILL.md,
# delimited EXACTLY by these HTML-comment markers:
#
#     <!-- cwtf:rule-load-extract:start -->
#     ```bash
#     ...runnable pipeline...
#     ```
#     <!-- cwtf:rule-load-extract:end -->
#
# Contract the block must satisfy:
#   * Inputs: env vars IL_LOG (path to instructions-loaded.jsonl) and
#     AUDIT_TRAIL (path to the TARGET branch's audit-trail-*.jsonl).
#   * Output: prints the grouped rule-load presentation data to stdout.
#   * Tools ONLY: jq / grep / find / bash — no new helper script, no new Bash
#     grant (DD-008).
#   * JSONL consumer contract: jq -R 'try(fromjson) catch empty' / fromjson?;
#     NEVER jq -s; NEVER slurp the whole file into a variable/argv.
#   * Grouping (RS-027): rule-loads are grouped by the TARGET workflow's
#     hook-edit session_ids (derived from audit-trail hook-edit entries), NOT by
#     the invoking session and NOT by every session present in IL_LOG.
#   * Timestamp normalization (RS-030): hook-edit times read as .ts // .timestamp.
#   * No automated verdict (PRH-005): no MG-001/MG-002 token in the output.
EXTRACT_START='<!-- cwtf:rule-load-extract:start -->'
EXTRACT_END='<!-- cwtf:rule-load-extract:end -->'

# Print the fenced code between the markers, with the ``` fence lines stripped.
# During RED the markers do not exist -> prints nothing.
extract_cwtf_block() {
  [ -f "$CWTF" ] || return 0
  awk -v s="$EXTRACT_START" -v e="$EXTRACT_END" '
    index($0, s) { inblk = 1; next }
    index($0, e) { inblk = 0; next }
    inblk && $0 !~ /^```/ { print }
  ' "$CWTF"
}

# ============================================================================
# INV-008 [integration]: presents rule-load + hook-edit evidence, read-only,
# JSONL-safe, session-grouped, no verdict.
# ============================================================================
section "INV-008: /cwtf presentation contract (skills/cwtf/SKILL.md)"

if [ ! -f "$CWTF" ]; then
  fail "INV-008" "skills/cwtf/SKILL.md not found"
else
  if has 'instructions-loaded\.jsonl'; then pass "INV-008a" "reads instructions-loaded.jsonl"; else fail "INV-008a" "no reference to .correctless/meta/instructions-loaded.jsonl"; fi
  # A1: tolerate optional spaces around // (`.ts // .timestamp`, `.ts//.timestamp`, ...)
  if has '\.ts *// *\.timestamp'; then pass "INV-008b" "reads time as .ts // .timestamp (RS-030 mixed shapes)"; else fail "INV-008b" "no '.ts // .timestamp' — mixed audit-trail shapes not handled (RS-030)"; fi
  if has 'fromjson'; then pass "INV-008c" "uses try/catch fromjson consumer contract"; else fail "INV-008c" "no fromjson skip-malformed parse (ABS-006/AP-014)"; fi
  if grep -qE 'jq -s' <<< "$CWTF_BODY"; then fail "INV-008d" "uses 'jq -s' slurp (forbidden AP-014)"; else pass "INV-008d" "no 'jq -s' slurp"; fi
  # RS-027 (secondary tripwire only — the executable contract below is the real
  # check). A1: dropped the loose bare-`session_id` alternative; require
  # edit-session grouping language specifically.
  if has 'edit.session' && has 'group|per session|per-session|grouped'; then
    pass "INV-008e" "groups rule-loads by edit-session (RS-027)"
  else
    fail "INV-008e" "no per-edit-session grouping language (RS-027)"
  fi
  if has 'unattributed'; then pass "INV-008f" "handles edits without session_id (unattributed group)"; else fail "INV-008f" "no 'unattributed' group for pre-instrumentation edits"; fi
  if has 'trigger_file_path'; then pass "INV-008g" "presents trigger_file_path with rule-loads"; else fail "INV-008g" "no trigger_file_path in presentation"; fi
  if grep -qE 'correlate' <<< "$CWTF_BODY"; then fail "INV-008h" "references a correlate helper script (DD-008 forbids new helper)"; else pass "INV-008h" "no correlate helper script (DD-008)"; fi
fi

# ============================================================================
# INV-008 [integration] EXECUTABLE CONTRACT (B1) — the primary INV-008 check.
# Extract the runnable rule-load presentation block from skills/cwtf/SKILL.md
# and run it over the real fixtures, asserting on OUTPUT (behavior), not prose.
# The prose greps above are now only a cheap secondary tripwire — they cannot
# catch a GREEN that groups by the invoking session, or reads .ts-only, because
# the keywords would still be present. This block can.
#
# Fixtures (Source: AP-031 verbatim/derived repo copies):
#   IL_LOG=instructions-loaded-log-sample.jsonl
#     sess 111 -> hooks-pretooluse.md ; sess 222 -> canonicalize-path.md ;
#     malformed line ; sess 999 (NON-edit) -> sfg-deliverable.md
#   AUDIT_TRAIL=audit-trail-sessioned.jsonl
#     edit sess 111 (ts, hooks/sensitive-file-guard.sh) ; edit sess 222 (ts,
#     hooks/workflow-gate.sh) ; session-less hooks/ edit (unattributed) ;
#     timestamp-shaped skill_completed sess 111 (hooks/audit-trail.sh @21:19:20) ;
#     malformed line.
# ============================================================================
section "INV-008 executable contract: extracted block groups rule-loads by edit-session (RS-027)"

blk="$(extract_cwtf_block)"
if [ -z "${blk//[[:space:]]/}" ]; then
  # RED: markers/block absent -> extraction empty -> feature unimplemented.
  fail "INV-008-exec" "cwtf rule-load-extract block absent — INV-008 unimplemented (RED)"
else
  tmp_blk="$(mktemp)"
  printf '%s\n' "$blk" > "$tmp_blk"
  out="$(IL_LOG="$LOG_SAMPLE" AUDIT_TRAIL="$AUDIT_SESS" bash "$tmp_blk" 2>/dev/null || true)"
  rm -f "$tmp_blk"

  # malformed lines in BOTH sources must not be fatal — output still produced.
  if [ -n "${out//[[:space:]]/}" ]; then
    pass "INV-008-exec-out" "extracted block produced output over the fixtures (malformed lines non-fatal)"
  else
    fail "INV-008-exec-out" "extracted block produced NO output (malformed line fatal, or wrong contract)"
  fi

  # RS-027: rule-loads grouped by TARGET edit sessions -> non-edit session 999
  # (present in IL_LOG but never an edit session) MUST be absent.
  if grep -q '99999999-9999-9999-9999-999999999999' <<< "$out"; then
    fail "INV-008-exec-nonedit" "non-edit session 9999... present — grouped by every log session, not edit-sessions (RS-027)"
  else
    pass "INV-008-exec-nonedit" "non-edit session 9999... absent from output (RS-027)"
  fi

  # Both edit sessions appear as distinct groups.
  if grep -q '11111111-1111-1111-1111-111111111111' <<< "$out"; then pass "INV-008-exec-sess1" "edit session 1111... present as a group"; else fail "INV-008-exec-sess1" "edit session 1111... missing from output"; fi
  if grep -q '22222222-2222-2222-2222-222222222222' <<< "$out"; then pass "INV-008-exec-sess2" "edit session 2222... present as a group"; else fail "INV-008-exec-sess2" "edit session 2222... missing from output"; fi

  # Pre-instrumentation edit (no session_id) -> "unattributed" group.
  if grep -qi 'unattributed' <<< "$out"; then pass "INV-008-exec-unattr" "session-less hook-edit shown in unattributed group"; else fail "INV-008-exec-unattr" "no unattributed group for the pre-instrumentation hook-edit"; fi

  # RS-030: the timestamp-shaped hook-edit (line 4) must be INCLUDED — proving
  # `.ts // .timestamp` selection, not `.ts`-only (which would drop its time).
  if grep -q 'hooks/audit-trail.sh' <<< "$out" && grep -q '21:19:20' <<< "$out"; then
    pass "INV-008-exec-tsalt" "timestamp-shaped hook-edit included (.ts // .timestamp, not .ts-only) (RS-030)"
  else
    fail "INV-008-exec-tsalt" "timestamp-shaped hook-edit (hooks/audit-trail.sh @21:19:20) missing — .ts-only drops it (RS-030)"
  fi

  # PRH-005: raw evidence only — no automated MG-001/MG-002 verdict in output.
  if grep -qE 'MG-001|MG-002' <<< "$out"; then
    fail "INV-008-exec-noverdict" "MG-001/MG-002 token in output (PRH-005 violated)"
  else
    pass "INV-008-exec-noverdict" "no MG-001/MG-002 token in output (PRH-005)"
  fi
fi

# ============================================================================
# PRH-005 [unit]: no automated MG-001/MG-002 verdict, no ts<=edit.ts join
# ============================================================================
section "PRH-005: no automated classification"

if grep -qE 'MG-001|MG-002' <<< "$CWTF_BODY"; then
  fail "PRH-005a" "SKILL.md emits an MG-001/MG-002 verdict (DD-007 scope-down violated)"
else
  pass "PRH-005a" "no MG-001/MG-002 token in /cwtf"
fi
if grep -qE 'ts *<=? *(edit|\.edit)' <<< "$CWTF_BODY"; then
  fail "PRH-005b" "SKILL.md contains a ts<=edit.ts correlation join (forbidden)"
else
  pass "PRH-005b" "no ts<=edit.ts correlation join"
fi

# ============================================================================
# INV-009 [unit]: dormant when log absent/empty; distinguishes empty vs all-null
# ============================================================================
section "INV-009: dormant / all-null distinction"

if [ -f "$CWTF" ]; then
  if has '2\.1\.69'; then pass "INV-009a" "dormant advisory names harness >=2.1.69 requirement"; else fail "INV-009a" "no dormant advisory referencing harness 2.1.69"; fi
  if has 'null rule_file|field drift|field-drift'; then pass "INV-009b" "surfaces all-null field-drift note (RS-008/UX-001)"; else fail "INV-009b" "no all-null field-drift note"; fi
else
  fail "INV-009a" "SKILL.md absent"
  fail "INV-009b" "SKILL.md absent"
fi

# ============================================================================
# INV-016 [unit]: liveness / self-diagnostic denominators line
# ============================================================================
section "INV-016: liveness / denominators line"

if [ -f "$CWTF" ]; then
  if has 'last written'; then pass "INV-016a" "liveness line shows log last-written ts"; else fail "INV-016a" "no 'last written' liveness marker"; fi
  if has 'rule-load event' && has 'hook-edit'; then pass "INV-016b" "denominators name rule-load + hook-edit counts"; else fail "INV-016b" "no rule-load/hook-edit denominators (DA-004 silent-telemetry guard)"; fi
else
  fail "INV-016a" "SKILL.md absent"
  fail "INV-016b" "SKILL.md absent"
fi

# ============================================================================
# Fixture integrity + safe-parse demonstration (AP-031) — validates that the
# fixtures satisfy the shapes the presentation must handle, and that the
# canonical try/catch consumer contract skips malformed lines. Supporting
# checks (may pass now); the RED signal is the SKILL.md contract above.
# ============================================================================
section "Fixture integrity + safe-parse (AP-031 real shapes)"

# audit-trail-real.jsonl carries BOTH a ts-shaped and a timestamp-shaped entry (RS-030)
if [ -f "$AUDIT_REAL" ]; then
  ts_shaped="$(grep -c '"ts"' "$AUDIT_REAL")"
  tsp_shaped="$(grep -c '"timestamp"' "$AUDIT_REAL")"
  if [ "$ts_shaped" -ge 1 ] && [ "$tsp_shaped" -ge 1 ]; then
    pass "FIX-real-shapes" "audit-trail-real.jsonl has both ts and timestamp shapes (RS-030)"
  else
    fail "FIX-real-shapes" "audit-trail-real.jsonl missing a ts or timestamp shape (ts=$ts_shaped timestamp=$tsp_shaped)"
  fi
  # safe-parse (never jq -s): .ts // .timestamp resolves on every well-formed line
  times="$(jq -R 'fromjson? | (.ts // .timestamp) // empty' "$AUDIT_REAL" 2>/dev/null | grep -c .)"
  if [ "$times" -ge 3 ]; then pass "FIX-real-time" ".ts // .timestamp resolves across real entries"; else fail "FIX-real-time" ".ts // .timestamp resolved on only $times entries"; fi
else
  fail "FIX-real-shapes" "audit-trail-real.jsonl fixture missing"
  fail "FIX-real-time" "audit-trail-real.jsonl fixture missing"
fi

# audit-trail-sessioned.jsonl: safe-parse SKIPS the malformed line; yields 2
# distinct edit session_ids (RS-027) plus an unattributed edit.
if [ -f "$AUDIT_SESS" ]; then
  raw_lines="$(wc -l < "$AUDIT_SESS" | tr -d ' ')"
  parsed="$(jq -R 'fromjson?' "$AUDIT_SESS" 2>/dev/null | jq -s 'length' 2>/dev/null || echo ERR)"
  # the malformed line must not abort parsing and must not be counted
  if [ "$parsed" -lt "$raw_lines" ] 2>/dev/null; then
    pass "FIX-sess-skip" "malformed audit line skipped (not fatal)"
  else
    fail "FIX-sess-skip" "malformed audit line not skipped (parsed=$parsed raw=$raw_lines)"
  fi
  sessions="$(jq -R 'fromjson? | select(.file != null and (.file|startswith("hooks/"))) | .session_id // empty' "$AUDIT_SESS" 2>/dev/null | grep -c .)"
  distinct="$(jq -R 'fromjson? | select(.file != null and (.file|startswith("hooks/"))) | .session_id // empty' "$AUDIT_SESS" 2>/dev/null | sort -u | grep -c .)"
  if [ "$distinct" = "2" ]; then pass "FIX-sess-distinct" "two distinct edit session_ids present (RS-027)"; else fail "FIX-sess-distinct" "expected 2 distinct edit sessions, got $distinct"; fi
  # RS-027: session grouping must collapse repeats. The fixture carries more
  # session-attributed hook-edit entries (session 111... on both the Edit line
  # and the skill_completed line) than distinct sessions, so a correct grouping
  # consumer yields fewer groups than rows — proving the grouping is non-trivial.
  if [ "$sessions" -gt "$distinct" ]; then pass "FIX-sess-grouping" "session-attributed edits ($sessions) exceed distinct sessions ($distinct) — grouping collapses repeats (RS-027)"; else fail "FIX-sess-grouping" "expected session-attributed edits > distinct sessions, got sessions=$sessions distinct=$distinct"; fi
else
  fail "FIX-sess-skip" "audit-trail-sessioned.jsonl fixture missing"
  fail "FIX-sess-distinct" "audit-trail-sessioned.jsonl fixture missing"
fi

# rule-load sample: malformed line skipped; loads for a non-edit session (9999)
# exist so a correct grouping excludes them.
if [ -f "$LOG_SAMPLE" ]; then
  good="$(jq -R 'fromjson?' "$LOG_SAMPLE" 2>/dev/null | jq -s 'length' 2>/dev/null || echo ERR)"
  if [ "$good" = "3" ]; then pass "FIX-log-skip" "3 well-formed rule-load events (1 malformed skipped)"; else fail "FIX-log-skip" "expected 3 parseable rule-loads, got $good"; fi
else
  fail "FIX-log-skip" "instructions-loaded-log-sample.jsonl fixture missing"
fi

# all-null fixture: every rule_file is null (INV-009 field-drift scenario)
if [ -f "$LOG_ALLNULL" ]; then
  nonnull="$(jq -R 'fromjson? | select(.rule_file != null)' "$LOG_ALLNULL" 2>/dev/null | grep -c .)"
  if [ "$nonnull" = "0" ]; then pass "FIX-allnull" "all-null fixture has zero non-null rule_file"; else fail "FIX-allnull" "all-null fixture has $nonnull non-null entries"; fi
else
  fail "FIX-allnull" "instructions-loaded-log-allnull.jsonl fixture missing"
fi

summary "test-instructions-loaded-cwtf"
