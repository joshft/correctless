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
#   AUDIT_TRAIL=audit-trail-sessioned.jsonl (RECONCILED for FIX 6 write-tool gate)
#     Edit sess 111 (ts, hooks/sensitive-file-guard.sh) ; Edit sess 222 (ts,
#     hooks/workflow-gate.sh) ; ONE clean session-less EDIT (unattributed,
#     hooks/workflow-advance.sh) ; a timestamp-shaped Edit sess 111
#     (hooks/audit-trail.sh @21:19:20 — COUNTED now that it carries a write tool,
#     proving .ts // .timestamp on a counted edit) ; malformed line.
#     -> 4 counted hook-edits across 3 edit-sessions {111, 222, unattributed}.
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
# AP-014/AP-039 STRUCTURAL: the extracted cwtf:rule-load-extract block must read
# IL_LOG / AUDIT_TRAIL by LINE-STREAMING from the file path (jq -R / jq -Rr),
# NEVER by slurping the whole file into a shell variable or onto argv.
#
# The "data does not transit argv / no whole-file slurp" contract is only guarded
# above by the `jq -s` prose grep (INV-008d). A `content="$(cat "$IL_LOG")"` or
# `$(<"$AUDIT_TRAIL")` whole-file slurp into a variable bypasses that grep
# entirely and passes every other test. This block-scoped assertion (over the
# EXTRACTED block, not all of SKILL.md) kills that mutant: it rejects any
# $(cat ...IL_LOG/AUDIT_TRAIL...), any $(< ...IL_LOG/AUDIT_TRAIL...), and (belt)
# any `jq -s`. The current block reads both files line-by-line via jq -R/-Rr, so
# this PASSES on correct code.
# ============================================================================
section "AP-014/AP-039: extracted block line-streams IL_LOG/AUDIT_TRAIL (no whole-file slurp)"

blk_slurp="$(extract_cwtf_block)"
if [ -z "${blk_slurp//[[:space:]]/}" ]; then
  fail "INV-008-noslurp" "cwtf rule-load-extract block absent — cannot verify no-slurp contract"
else
  _slurp_hit=""
  for _pat in \
    '\$\(cat[^)]*IL_LOG' \
    '\$\(<[^)]*IL_LOG' \
    '\$\(cat[^)]*AUDIT_TRAIL' \
    '\$\(<[^)]*AUDIT_TRAIL' \
    'jq -s'; do
    if printf '%s\n' "$blk_slurp" | grep -qE -- "$_pat"; then
      _slurp_hit="$_slurp_hit [$_pat]"
    fi
  done
  if [ -z "$_slurp_hit" ]; then
    pass "INV-008-noslurp" "block reads IL_LOG/AUDIT_TRAIL via jq -R/-Rr from the path (no cat/\$(<)/jq -s slurp)"
  else
    fail "INV-008-noslurp" "block slurps a whole file into a variable/argv (AP-014/AP-039):$_slurp_hit"
  fi
fi

# ============================================================================
# QA-001 / INV-015 [integration] EXECUTABLE CONTRACT: an empty-string session
# folds into the "unattributed" group — it can never form its own (blank-named)
# group. Uses a SEPARATE fixture (audit-trail-emptysession.jsonl) so the
# FIX-sess-distinct / FIX-sess-grouping assertions on audit-trail-sessioned.jsonl
# (which expect exactly 2 distinct sessions) are not perturbed.
#
# Fixture: hooks/audit-trail.sh edit with session_id:"" (empty) + hooks/workflow-
# gate.sh edit with session 3333... . Correct grouping -> {unattributed, 3333...},
# never a group whose name is the empty string.
# ============================================================================
section "QA-001 executable contract: empty-string session folds into unattributed"

AUDIT_EMPTY="$FIXTURES/audit-trail-emptysession.jsonl"
blk_e="$(extract_cwtf_block)"
if [ -z "${blk_e//[[:space:]]/}" ]; then
  fail "QA-001-empty" "cwtf rule-load-extract block absent — cannot exercise grouping"
elif [ ! -f "$AUDIT_EMPTY" ]; then
  fail "QA-001-empty" "audit-trail-emptysession.jsonl fixture missing"
else
  tmp_e="$(mktemp)"
  printf '%s\n' "$blk_e" > "$tmp_e"
  # IL_LOG intentionally absent — this contract is purely about edit-session
  # grouping derived from AUDIT_TRAIL, independent of any rule-load evidence.
  out_e="$(IL_LOG="$FIXTURES/no-such-il-log-$$.jsonl" AUDIT_TRAIL="$AUDIT_EMPTY" bash "$tmp_e" 2>/dev/null || true)"
  rm -f "$tmp_e"

  # The empty-string session must surface under the unattributed group.
  if grep -qi 'unattributed' <<< "$out_e"; then
    pass "QA-001-empty-unattr" "empty-string session shown in the unattributed group"
  else
    fail "QA-001-empty-unattr" "no unattributed group for the empty-string session"
  fi
  # No blank-named edit-session group: the header is `=== edit-session: <name> ===`,
  # so an empty name would render as `edit-session:  ===` (whitespace then ===).
  # A real name (`unattributed`, a uuid) has non-space text before ` ===`.
  if grep -qE 'edit-session:[[:space:]]+===' <<< "$out_e"; then
    fail "QA-001-empty-noblank" "blank-named edit-session group present — empty session formed its own group"
  else
    pass "QA-001-empty-noblank" "no blank-named edit-session group (empty folded into unattributed)"
  fi
  # The genuine (non-empty) session still forms its own distinct group.
  if grep -q '33333333-3333-3333-3333-333333333333' <<< "$out_e"; then
    pass "QA-001-empty-real" "non-empty session 3333... still forms its own group"
  else
    fail "QA-001-empty-real" "non-empty session 3333... missing from output"
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
# INV-009 [integration] EXECUTABLE CONTRACT (primary) — mirror the B1 pattern:
# RUN the extracted block and assert on its OUTPUT across the empty/absent and
# all-null branches, not just SKILL.md prose. The spec Enforcement for INV-009 is
# a behavioral CI test (empty / all-null / populated).
#   (a) EMPTY/ABSENT IL_LOG -> non-alarming dormant advisory + clean exit 0.
#   (b) ALL-NULL log         -> field-drift note (unreliable, not healthy).
# The prose greps below are retained as a SECONDARY tripwire only.
# ============================================================================
section "INV-009 executable contract: dormant + all-null branches"

blk9="$(extract_cwtf_block)"
if [ -z "${blk9//[[:space:]]/}" ]; then
  fail "INV-009-exec" "cwtf rule-load-extract block absent — INV-009 unimplemented"
else
  tmp9="$(mktemp)"
  printf '%s\n' "$blk9" > "$tmp9"

  # (a) EMPTY/ABSENT IL_LOG: dormant advisory + exit 0. Point IL_LOG at a file
  # that does not exist ([ ! -s ] is true for both absent and empty).
  # RECONCILE (MA-004 self-glob): the block now falls back to
  # `find .correctless/artifacts -name 'audit-trail-*.jsonl'` when AUDIT_TRAIL is
  # empty/unresolved. Run from the repo root that would find the repo's real
  # audit-trails (36 hook-edits) and the benign dormant branch is replaced by the
  # dead-channel WARNING. To exercise the genuinely-fresh (dead-vs-fresh) branch,
  # run in an ISOLATED temp cwd whose .correctless/artifacts is empty, so the
  # self-glob finds nothing (audit_located=0 AND hook_edits=0). The dead-channel
  # and self-glob-hit branches are covered by MA-003 / MA-004 below.
  iso_dormant="$(mktemp -d)"
  mkdir -p "$iso_dormant/.correctless/artifacts"
  out_dormant="$( cd "$iso_dormant" && IL_LOG="$FIXTURES/no-such-il-log-$$.jsonl" AUDIT_TRAIL="" bash "$tmp9" 2>/dev/null )"
  rc_dormant=$?
  rm -rf "$iso_dormant"
  if [ "$rc_dormant" -eq 0 ]; then
    pass "INV-009-dormant-rc" "block exits 0 when IL_LOG is absent/empty"
  else
    fail "INV-009-dormant-rc" "block exited $rc_dormant on absent IL_LOG (want 0)"
  fi
  if grep -qi 'populates' <<< "$out_dormant" && grep -q '2\.1\.69' <<< "$out_dormant"; then
    pass "INV-009-dormant-msg" "absent-log output is the non-alarming dormant advisory (log populates on first rule open; harness >=2.1.69)"
  else
    fail "INV-009-dormant-msg" "absent-log output lacks the non-alarming dormant advisory"
  fi

  # (b) ALL-NULL log: field-drift note. Fixture has 2 rule-loads, both null.
  out_allnull="$(IL_LOG="$LOG_ALLNULL" AUDIT_TRAIL="" bash "$tmp9" 2>/dev/null || true)"
  if grep -q 'all with null rule_file' <<< "$out_allnull" && grep -qi 'field drift' <<< "$out_allnull"; then
    pass "INV-009-allnull-msg" "all-null log prints the field-drift note (rule-load evidence unreliable)"
  else
    fail "INV-009-allnull-msg" "all-null log did not surface the field-drift note"
  fi
  rm -f "$tmp9"
fi

# INV-009 SECONDARY tripwire (prose greps — cheap, but cannot catch a wrong
# dormant/all-null branch; the executable assertions above are primary).
if [ -f "$CWTF" ]; then
  if has '2\.1\.69'; then pass "INV-009a" "dormant advisory names harness >=2.1.69 requirement"; else fail "INV-009a" "no dormant advisory referencing harness 2.1.69"; fi
  if has 'null rule_file|field drift|field-drift'; then pass "INV-009b" "surfaces all-null field-drift note (RS-008/UX-001)"; else fail "INV-009b" "no all-null field-drift note"; fi
else
  fail "INV-009a" "SKILL.md absent"
  fail "INV-009b" "SKILL.md absent"
fi

# ============================================================================
# INV-016 [integration] EXECUTABLE CONTRACT (primary) — RUN the block over a
# POPULATED log and assert the liveness/denominators line reports counts that
# match the fixtures (DA-004 silent-telemetry guard: the denominators must be
# real, not zero/placeholder). Prose greps retained as SECONDARY tripwire.
#
# IL_LOG=instructions-loaded-log-sample.jsonl -> 3 parseable rule-loads,
#   last-written 2026-06-15T03:06:00Z.
# AUDIT_TRAIL=audit-trail-sessioned.jsonl -> 4 hook-edit entries across 3
#   edit-sessions (111, 222, unattributed).
# ============================================================================
section "INV-016 executable contract: liveness denominators over populated log"

blk16="$(extract_cwtf_block)"
if [ -z "${blk16//[[:space:]]/}" ]; then
  fail "INV-016-exec" "cwtf rule-load-extract block absent — INV-016 unimplemented"
else
  tmp16="$(mktemp)"
  printf '%s\n' "$blk16" > "$tmp16"
  out_live="$(IL_LOG="$LOG_SAMPLE" AUDIT_TRAIL="$AUDIT_SESS" bash "$tmp16" 2>/dev/null || true)"
  rm -f "$tmp16"

  # Rule-load denominator matches the fixture (3 parseable events).
  if grep -qE 'read 3 rule-load event\(s\)' <<< "$out_live"; then
    pass "INV-016-count" "liveness line reports the 3-event rule-load denominator"
  else
    fail "INV-016-count" "liveness line missing 'read 3 rule-load event(s)' denominator"
  fi
  # hook-edit + edit-session denominators match the fixture (4 edits, 3 sessions).
  if grep -qE '4 hook-edit entries' <<< "$out_live" && grep -qE 'across 3 edit-session\(s\)' <<< "$out_live"; then
    pass "INV-016-denoms" "hook-edit (4) + edit-session (3) denominators match fixture"
  else
    fail "INV-016-denoms" "hook-edit/edit-session denominators do not match fixture"
  fi
  # Liveness line carries the log's last-written ts (the block emits the raw jq
  # string, so the ts may be quoted — tolerate the surrounding quote).
  if grep -qE 'log last written "?2026-06-15T03:06:00Z"?' <<< "$out_live"; then
    pass "INV-016-lastwritten" "liveness line shows the log last-written ts from the fixture"
  else
    fail "INV-016-lastwritten" "liveness line missing 'log last written <ts>' marker"
  fi
fi

# INV-016 SECONDARY tripwire (prose greps).
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

# ============================================================================
# MINI-AUDIT FIX ROUND (MA-001..MA-008) — regression tests locking 8 fixes to
# the cwtf:rule-load-extract block. Each assertion runs the EXTRACTED block over
# a crafted fixture and asserts on the GREEN agent's reported verbatim output
# substrings. Fixtures added this round:
#   instructions-loaded-log-poison.jsonl   (MA-001: objects + interleaved scalars)
#   audit-trail-correctless-hooks.jsonl    (MA-002: installed-project hook paths)
#   instructions-loaded-log-unmatched.jsonl (MA-006: no session matches an edit)
#   instructions-loaded-log-corrupt.jsonl   (MA-008a: 0 parseable object lines)
#   instructions-loaded-log-partialnull.jsonl (MA-008b: >50% null rule_file)
#
# MA-001 is the jq-1.7-abort guard: on jq 1.7 (CI) a VALID-but-non-object or
# mistyped line raises a downstream `.field`/`test`/`startswith` runtime error
# that bare `fromjson?` does NOT catch, aborting the whole stream. `| objects`
# + `(.file // "") | tostring` skips those lines on 1.7 AND 1.8. We run on 1.8
# here (where even the old code survives) — the poison-line test documents the
# contract and catches a regression that reintroduces an un-guarded pipeline.
# ============================================================================

# One extraction shared by every MA assertion (absolute path — survives cwd cd).
MA_BLK="$(mktemp)"
extract_cwtf_block > "$MA_BLK"

# Run the block from an ISOLATED temp cwd whose .correctless/artifacts is empty,
# so the MA-004 self-glob (`find .correctless/artifacts -name audit-trail-*.jsonl`)
# finds nothing. Args: IL_LOG AUDIT_TRAIL. Echoes stdout; sets MA_RC to exit code.
MA_RC=0
run_block_iso() {
  local il="$1" at="$2" iso out
  iso="$(mktemp -d)"
  mkdir -p "$iso/.correctless/artifacts"
  out="$( cd "$iso" && IL_LOG="$il" AUDIT_TRAIL="$at" bash "$MA_BLK" 2>/dev/null )"
  MA_RC=$?
  rm -rf "$iso"
  printf '%s' "$out"
}

# Create an ISOLATED git repo on branch $1 (with one commit so
# `git rev-parse --abbrev-ref HEAD` resolves the branch name — it returns "HEAD"
# on an unborn branch), with an empty .correctless/artifacts/. Echoes the dir.
# The caller drops branch-named audit-trail-*.jsonl fixtures under
# .correctless/artifacts, runs the block with AUDIT_TRAIL="" to exercise the
# FIX-1 branch-scoped self-glob, then rm -rf's the dir.
make_git_iso() {
  local branch="$1" d
  d="$(mktemp -d)"
  (
    cd "$d" \
      && git init -q \
      && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m init \
      && git checkout -q -b "$branch"
  ) >/dev/null 2>&1
  mkdir -p "$d/.correctless/artifacts"
  printf '%s' "$d"
}

if [ ! -s "$MA_BLK" ]; then
  section "MA fix round: extracted block absent — MA-001..MA-008 cannot run"
  fail "MA-block" "cwtf rule-load-extract block absent — mini-audit fixes unverifiable"
else
  NOLOG="$FIXTURES/no-such-il-log-$$.jsonl"
  LOG_POISON="$FIXTURES/instructions-loaded-log-poison.jsonl"
  AUDIT_CH="$FIXTURES/audit-trail-correctless-hooks.jsonl"
  LOG_UNMATCHED="$FIXTURES/instructions-loaded-log-unmatched.jsonl"
  LOG_CORRUPT="$FIXTURES/instructions-loaded-log-corrupt.jsonl"
  LOG_PARTIALNULL="$FIXTURES/instructions-loaded-log-partialnull.jsonl"
  # Round-2 regression fixtures (TASK B):
  AUDIT_NONHOOK="$FIXTURES/audit-trail-nonhook-dirs.jsonl"      # MA-R2-srchooks
  AUDIT_TOOLGATE="$FIXTURES/audit-trail-toolgate.jsonl"         # MA-R2-toolgate
  AUDIT_ALLUNATTR="$FIXTURES/audit-trail-allunattr.jsonl"       # MA-R2-driftnote-suppressed
  LOG_HALFNULL="$FIXTURES/instructions-loaded-log-halfnull.jsonl" # MA-R2-nullratio-50

  # ------------------------------------------------------------------------
  # MA-001 [integration]: non-object / mistyped JSONL lines are never fatal.
  # ------------------------------------------------------------------------
  section "MA-001: poison lines (scalars + mistyped objects) do not abort the pipeline"

  out_ma1="$(IL_LOG="$LOG_POISON" AUDIT_TRAIL="$AUDIT_SESS" bash "$MA_BLK" 2>/dev/null)"
  rc_ma1=$?
  if [ "$rc_ma1" -eq 0 ]; then
    pass "MA-001-il-rc" "block exits 0 with scalar/mistyped lines interleaved in IL_LOG (jq-1.7-abort guard)"
  else
    fail "MA-001-il-rc" "block exited $rc_ma1 on poisoned IL_LOG (want 0 — pipeline aborted?)"
  fi
  if grep -q '.claude/rules/hooks-pretooluse.md' <<< "$out_ma1" \
     && grep -q '.claude/rules/canonicalize-path.md' <<< "$out_ma1"; then
    pass "MA-001-il-goodcount" "good rule-load events still rendered despite interleaved poison lines"
  else
    fail "MA-001-il-goodcount" "good rule-loads dropped — poison line truncated the stream"
  fi
  if grep -qE 'Liveness: read [0-9]+ rule-load event' <<< "$out_ma1"; then
    pass "MA-001-il-liveness" "normal liveness output still produced with poisoned IL_LOG"
  else
    fail "MA-001-il-liveness" "no liveness line — poisoned IL_LOG broke normal output"
  fi

  # Also poison AUDIT_TRAIL (temp copy of the sessioned fixture + scalar lines).
  ma1_audit="$(mktemp)"
  cat "$AUDIT_SESS" > "$ma1_audit"
  printf '5\n"x"\n[1,2,3]\n{"file":5,"session_id":7}\ntrue\n' >> "$ma1_audit"
  out_ma1b="$(IL_LOG="$LOG_POISON" AUDIT_TRAIL="$ma1_audit" bash "$MA_BLK" 2>/dev/null)"
  rc_ma1b=$?
  rm -f "$ma1_audit"
  if [ "$rc_ma1b" -eq 0 ] && grep -qE '4 hook-edit entries' <<< "$out_ma1b"; then
    pass "MA-001-audit-safe" "scalar/mistyped lines in AUDIT_TRAIL skipped; 4 real hook-edits still counted, exit 0"
  else
    fail "MA-001-audit-safe" "poisoned AUDIT_TRAIL aborted or miscounted (rc=$rc_ma1b)"
  fi

  # ------------------------------------------------------------------------
  # MA-002 [integration] (RECONCILED for FIX 2 — anchored hook-root filter):
  # the hook-edit filter now matches ONLY `^hooks/` (source tree) or
  # `(^|/)\.correctless/hooks/` (installed) PLUS a write-tool gate. So the
  # installed-project `.correctless/hooks/...` path counts, but an absolute
  # non-.correctless `/x/hooks/y.sh` is now INTENTIONALLY EXCLUDED, as are
  # scripts/foo.sh and webhooks/x.sh. Only 1 of the 4 fixture rows counts.
  # ------------------------------------------------------------------------
  section "MA-002: .correctless/hooks path counted; absolute/non-hook paths excluded (FIX 2)"

  out_ma2="$(IL_LOG="$NOLOG" AUDIT_TRAIL="$AUDIT_CH" bash "$MA_BLK" 2>/dev/null)"
  if grep -q '.correctless/hooks/workflow-advance.sh' <<< "$out_ma2"; then
    pass "MA-002-correctless-hook" "installed-project hook (.correctless/hooks/workflow-advance.sh) appears in output"
  else
    fail "MA-002-correctless-hook" ".correctless/hooks/... path silently excluded ((^|/)\\.correctless/hooks/ regression)"
  fi
  # INVERTED (FIX 2): absolute non-.correctless /x/hooks/y.sh must NOT be counted.
  if grep -q '/x/hooks/y.sh' <<< "$out_ma2"; then
    fail "MA-002-abs-hook" "absolute non-.correctless /x/hooks/y.sh counted — anchored hook-root filter regressed (FIX 2)"
  else
    pass "MA-002-abs-hook" "absolute non-.correctless /x/hooks/y.sh EXCLUDED (only ^hooks/ or .correctless/hooks/ match)"
  fi
  if grep -qE 'and 1 hook-edit entries across 1 edit-session' <<< "$out_ma2"; then
    pass "MA-002-count" "exactly 1 hook-edit counted (only .correctless/hooks/...); abs/scripts/webhooks excluded"
  else
    fail "MA-002-count" "hook-edit count wrong — expected 1 (.correctless/hooks/...) with abs/scripts/webhooks excluded"
  fi
  if grep -q 'scripts/foo.sh' <<< "$out_ma2"; then
    fail "MA-002-nonhook" "scripts/foo.sh counted as a hook-edit (over-match)"
  else
    pass "MA-002-nonhook" "scripts/foo.sh NOT counted as a hook-edit"
  fi
  if grep -q 'webhooks/x.sh' <<< "$out_ma2"; then
    fail "MA-002-webhooks" "webhooks/x.sh matched — '(^|/)hooks/' anchor missing (substring over-match)"
  else
    pass "MA-002-webhooks" "webhooks/x.sh NOT matched (anchor requires start-or-slash before hooks/)"
  fi

  # ------------------------------------------------------------------------
  # MA-003 [integration]: dormant (fresh) vs dead-channel branches.
  # ------------------------------------------------------------------------
  section "MA-003: dead-vs-fresh — benign advisory (fresh) vs dead-channel WARNING"

  out_ma3_fresh="$(run_block_iso "$NOLOG" "")"
  rc_ma3_fresh="$MA_RC"
  if grep -q 'requires harness >=2.1.69 AND that /csetup has registered' <<< "$out_ma3_fresh" \
     && [ "$rc_ma3_fresh" -eq 0 ]; then
    pass "MA-003-fresh" "empty log + 0 hook-edits emits the benign dormant advisory, exit 0"
  else
    fail "MA-003-fresh" "fresh branch missing dormant advisory or non-zero exit (rc=$rc_ma3_fresh)"
  fi

  out_ma3_dead="$(IL_LOG="$NOLOG" AUDIT_TRAIL="$AUDIT_CH" bash "$MA_BLK" 2>/dev/null)"
  # RECONCILED for FIX 3: the dead-channel cause list now names the benign
  # harness-too-old cause verbatim.
  if grep -q 'the channel may be dead (hook not registered, harness <2.1.69 which does not emit InstructionsLoaded, or not firing)' <<< "$out_ma3_dead"; then
    pass "MA-003-dead-msg" "empty log + hook-edits>0 emits the dead-channel note with the harness <2.1.69 benign cause (FIX 3)"
  else
    fail "MA-003-dead-msg" "dead-channel note absent or missing the 'harness <2.1.69 which does not emit InstructionsLoaded' cause (FIX 3)"
  fi
  if grep -q 'WARNING:' <<< "$out_ma3_dead" \
     && grep -q 'hook-edit(s) occurred but zero rule-load events' <<< "$out_ma3_dead"; then
    pass "MA-003-dead-warning" "dead-channel line is a WARNING naming hook-edits-with-zero-rule-loads"
  else
    fail "MA-003-dead-warning" "dead-channel WARNING substring missing"
  fi

  # ------------------------------------------------------------------------
  # MA-004 [integration]: unresolved AUDIT_TRAIL — do not report "0 hook-edits"
  # as if measured; contrast with a real audit-trail found by the self-glob.
  # ------------------------------------------------------------------------
  section "MA-004: unresolved hook-edit source vs self-glob hit"

  out_ma4="$(run_block_iso "$LOG_SAMPLE" "")"
  rc_ma4="$MA_RC"
  # -F (fixed-string): the literal substring carries a '*' and '.' that a basic regex would misread.
  if grep -qF 'hook-edit source not located (audit-trail-*.jsonl not found)' <<< "$out_ma4" \
     && grep -qF 'hook-edit attribution unavailable' <<< "$out_ma4" \
     && [ "$rc_ma4" -eq 0 ]; then
    pass "MA-004-unresolved" "empty AUDIT_TRAIL + no artifacts -> attribution-unavailable liveness, exit 0"
  else
    fail "MA-004-unresolved" "unresolved-source liveness wording missing or non-zero exit (rc=$rc_ma4)"
  fi
  if grep -q '0 hook-edit entries across' <<< "$out_ma4"; then
    fail "MA-004-not-measured" "reports '0 hook-edit entries' as if measured when source is unresolved"
  else
    pass "MA-004-not-measured" "does not fabricate a measured '0 hook-edit entries' denominator"
  fi

  # Contrast (RECONCILED for FIX 1 — branch-scoped self-glob): a real audit-trail
  # named for THIS branch's slug IS found. The self-glob now derives the current
  # branch slug via `git rev-parse --abbrev-ref HEAD | tr / -` and globs
  # `audit-trail-<slug>*.jsonl` ONLY, so the contrast case needs a real git repo
  # on a branch whose slug matches the fixture name (a bare mktemp -d has no repo,
  # so the slug is empty and the glob finds nothing).
  ma4_iso="$(make_git_iso feature/ma4demo)"
  cat "$AUDIT_SESS" > "$ma4_iso/.correctless/artifacts/audit-trail-feature-ma4demo.jsonl"
  out_ma4b="$( cd "$ma4_iso" && IL_LOG="$LOG_SAMPLE" AUDIT_TRAIL="" bash "$MA_BLK" 2>/dev/null )"
  rm -rf "$ma4_iso"
  if grep -qE '[0-9]+ hook-edit entries across' <<< "$out_ma4b" \
     && ! grep -q 'not located' <<< "$out_ma4b"; then
    pass "MA-004-glob-hit" "branch-scoped self-glob finds audit-trail-<slug>.jsonl and reports measured hook-edits"
  else
    fail "MA-004-glob-hit" "branch-scoped self-glob did not attribute hook-edits from this branch's audit-trail"
  fi
  # FIX 1 provenance: an auto-resolved source must be NAMED with the verify caveat.
  if grep -q 'hook-edit source auto-resolved to audit-trail-feature-ma4demo.jsonl' <<< "$out_ma4b" \
     && grep -q 'verify it matches the workflow you are auditing' <<< "$out_ma4b"; then
    pass "MA-004-glob-provenance" "auto-resolved liveness names the resolved basename + verify caveat (FIX 1)"
  else
    fail "MA-004-glob-provenance" "auto-resolved liveness missing 'auto-resolved to <basename>' + verify caveat (FIX 1)"
  fi

  # ------------------------------------------------------------------------
  # MA-005 [integration]: liveness last-written ts is UNQUOTED (-Rr, not -R).
  # Replaces the prior quote-tolerant last-written assertion.
  # ------------------------------------------------------------------------
  section "MA-005: liveness 'log last written' timestamp is unquoted"

  out_ma5="$(IL_LOG="$LOG_SAMPLE" AUDIT_TRAIL="$AUDIT_SESS" bash "$MA_BLK" 2>/dev/null)"
  if grep -qE 'log last written 2026-[0-9-]+T[0-9:]+Z' <<< "$out_ma5" \
     && ! grep -q 'log last written "' <<< "$out_ma5"; then
    pass "MA-005-unquoted-ts" "last-written ts rendered raw (log last written 2026-...Z, no surrounding quote)"
  else
    fail "MA-005-unquoted-ts" "last-written ts is quoted or malformed (want unquoted -Rr output)"
  fi

  # ------------------------------------------------------------------------
  # MA-006 [integration]: rule-loads exist but none match an edit-session id ->
  # surface the distinct rule-load session_ids (EA-005 format-drift hint).
  # ------------------------------------------------------------------------
  section "MA-006: unmatched rule-load sessions surface a format-drift note"

  out_ma6="$(IL_LOG="$LOG_UNMATCHED" AUDIT_TRAIL="$AUDIT_SESS" bash "$MA_BLK" 2>/dev/null)"
  if grep -q 'none matched an edit-session_id — possible session_id format drift' <<< "$out_ma6" \
     && grep -q 'rule-load session_ids seen:' <<< "$out_ma6"; then
    pass "MA-006-drift-note" "no-match case prints the EA-005 format-drift note with observed session_ids"
  else
    fail "MA-006-drift-note" "unmatched-session drift note missing"
  fi
  # Non-triggering: the sample+sessioned fixtures where 2 rule-loads DO attribute.
  out_ma6b="$(IL_LOG="$LOG_SAMPLE" AUDIT_TRAIL="$AUDIT_SESS" bash "$MA_BLK" 2>/dev/null)"
  if grep -q 'none matched an edit-session_id' <<< "$out_ma6b"; then
    fail "MA-006-no-false-note" "drift note printed even though 2 rule-loads attribute (false positive)"
  else
    pass "MA-006-no-false-note" "drift note absent when rule-loads attribute to edit-sessions"
  fi

  # ------------------------------------------------------------------------
  # MA-007 [integration]: the unattributed (pre-instrumentation) group carries
  # the "predates session_id instrumentation / not evidence unloaded" caveat.
  # ------------------------------------------------------------------------
  section "MA-007: unattributed group header explains pre-instrumentation edits"

  out_ma7="$(IL_LOG="$NOLOG" AUDIT_TRAIL="$AUDIT_SESS" bash "$MA_BLK" 2>/dev/null)"
  if grep -q 'these edits predate session_id instrumentation' <<< "$out_ma7" \
     && grep -q 'absence of rule-loads here is NOT evidence the rule was unloaded' <<< "$out_ma7"; then
    pass "MA-007-unattr-caveat" "session-less hook-edit renders the unattributed-group caveat"
  else
    fail "MA-007-unattr-caveat" "unattributed-group caveat wording missing"
  fi

  # ------------------------------------------------------------------------
  # MA-008 [integration]: corrupted log (0 parseable objects) + partial null.
  # ------------------------------------------------------------------------
  section "MA-008: corrupted-log note + partial null-ratio note"

  out_ma8a="$(run_block_iso "$LOG_CORRUPT" "")"
  if grep -q 'log present but 0 parseable JSONL lines — possible corruption or torn writes' <<< "$out_ma8a"; then
    pass "MA-008-corrupt" "non-empty log with 0 parseable objects emits the corruption/torn-writes note"
  else
    fail "MA-008-corrupt" "corruption note missing for a non-empty, unparsable log"
  fi

  out_ma8b="$(run_block_iso "$LOG_PARTIALNULL" "")"
  if grep -q 'high null-rule ratio (' <<< "$out_ma8b" \
     && grep -q 'possible harness field drift' <<< "$out_ma8b"; then
    pass "MA-008-partialnull" ">50% (not 100%) null rule_file emits the high-null-ratio field-drift note"
  else
    fail "MA-008-partialnull" "partial null-ratio note missing (want 'high null-rule ratio (' + field drift)"
  fi

  # 100%-null wording unchanged (co-checked with the existing INV-009-allnull-msg).
  out_ma8c="$(run_block_iso "$LOG_ALLNULL" "")"
  if grep -q 'all with null rule_file' <<< "$out_ma8c" \
     && grep -qi 'field drift' <<< "$out_ma8c"; then
    pass "MA-008-allnull-wording" "100%-null log still emits the 'all with null rule_file' field-drift note"
  else
    fail "MA-008-allnull-wording" "100%-null wording changed — 'all with null rule_file' + field drift expected"
  fi

  # ========================================================================
  # MINI-AUDIT ROUND-2 REGRESSION TESTS (MA-R2-*) — lock the 7 source fixes made
  # this round. Each would have caught a round-1 regression; each asserts on the
  # GREEN agent's reported verbatim output substrings.
  # ========================================================================

  # ------------------------------------------------------------------------
  # MA-R2-glob-scope [integration] (FIX 1 / MA-R2-001 core guard): the AUDIT_TRAIL
  # self-glob is scoped to THIS branch's slug — it must NOT pick another branch's
  # trail even when that trail sorts lexicographically LATER (which is exactly what
  # the round-1 unscoped `find audit-trail-*.jsonl | sort | tail -1` did).
  # ------------------------------------------------------------------------
  section "MA-R2-glob-scope: branch-scoped self-glob resolves THIS branch, ignores a later-sorting other-branch trail (MA-R2-001)"

  gs_iso="$(make_git_iso feature/alpha)"
  # THIS branch (slug feature-alpha): distinctive hook-edit.
  printf '%s\n' '{"ts":"2026-06-20T01:00:00Z","tool":"Edit","file":"hooks/x-branch-marker.sh","session_id":"11111111-1111-1111-1111-111111111111"}' \
    > "$gs_iso/.correctless/artifacts/audit-trail-feature-alpha.jsonl"
  # A DIFFERENT branch's trail that sorts LEXICOGRAPHICALLY LATER — an unscoped
  # global sort|tail (the round-1 bug) would wrongly pick THIS one.
  printf '%s\n' '{"ts":"2026-06-20T02:00:00Z","tool":"Edit","file":"hooks/other-branch-marker.sh","session_id":"22222222-2222-2222-2222-222222222222"}' \
    > "$gs_iso/.correctless/artifacts/audit-trail-zzzz-otherbranch.jsonl"
  out_gs="$( cd "$gs_iso" && IL_LOG="$NOLOG" AUDIT_TRAIL="" bash "$MA_BLK" 2>/dev/null )"
  rm -rf "$gs_iso"
  if grep -qF 'hooks/x-branch-marker.sh' <<< "$out_gs"; then
    pass "MA-R2-glob-scope-this" "self-glob resolved THIS branch's audit-trail (its hook-edit appears)"
  else
    fail "MA-R2-glob-scope-this" "THIS branch's audit-trail-feature-alpha.jsonl was not resolved"
  fi
  if grep -qF 'hooks/other-branch-marker.sh' <<< "$out_gs"; then
    fail "MA-R2-glob-scope-other" "later-sorting other-branch trail leaked in — self-glob not branch-scoped (MA-R2-001 regression)"
  else
    pass "MA-R2-glob-scope-other" "later-sorting other-branch trail NOT picked (branch-scoped glob, not global sort|tail)"
  fi

  # ------------------------------------------------------------------------
  # MA-R2-provenance [integration] (FIX 1): an auto-resolved source is NAMED with a
  # verify caveat and NOT claimed as "for the target workflow"; an explicitly-
  # supplied AUDIT_TRAIL keeps "for the target workflow" and omits the auto phrase.
  # ------------------------------------------------------------------------
  section "MA-R2-provenance: auto-resolved names the source + verify caveat; explicit says 'for the target workflow' (MA-R2-001)"

  pv_iso="$(make_git_iso feature/prov)"
  cat "$AUDIT_SESS" > "$pv_iso/.correctless/artifacts/audit-trail-feature-prov.jsonl"
  out_pv_auto="$( cd "$pv_iso" && IL_LOG="$LOG_SAMPLE" AUDIT_TRAIL="" bash "$MA_BLK" 2>/dev/null )"
  rm -rf "$pv_iso"
  if grep -qF 'hook-edit source auto-resolved to audit-trail-feature-prov.jsonl' <<< "$out_pv_auto" \
     && grep -qF 'verify it matches the workflow you are auditing' <<< "$out_pv_auto"; then
    pass "MA-R2-provenance-auto" "auto-resolved liveness names the basename + verify caveat"
  else
    fail "MA-R2-provenance-auto" "auto-resolved provenance line missing basename or verify caveat"
  fi
  if grep -qF 'for the target workflow' <<< "$out_pv_auto"; then
    fail "MA-R2-provenance-auto-notarget" "auto-resolved output wrongly claims 'for the target workflow'"
  else
    pass "MA-R2-provenance-auto-notarget" "auto-resolved output does NOT claim 'for the target workflow'"
  fi
  out_pv_explicit="$(IL_LOG="$LOG_SAMPLE" AUDIT_TRAIL="$AUDIT_SESS" bash "$MA_BLK" 2>/dev/null)"
  if grep -qF 'for the target workflow' <<< "$out_pv_explicit" \
     && ! grep -qF 'hook-edit source auto-resolved to' <<< "$out_pv_explicit"; then
    pass "MA-R2-provenance-explicit" "explicit AUDIT_TRAIL says 'for the target workflow' and omits the auto-resolved phrase"
  else
    fail "MA-R2-provenance-explicit" "explicit AUDIT_TRAIL wording wrong (want 'for the target workflow', no auto-resolved phrase)"
  fi

  # ------------------------------------------------------------------------
  # MA-R2-srchooks [integration] (FIX 2 / MA-R2-002 / MA-CC-01): src/hooks/,
  # .git/hooks/, node_modules/**/hooks/, app/hooks/ are all EXCLUDED by the
  # anchored hook-root filter; a sibling .correctless/hooks/ edit IS counted.
  # ------------------------------------------------------------------------
  section "MA-R2-srchooks: src/.git/node_modules/app hooks excluded; .correctless/hooks counted (MA-R2-002)"

  out_nh="$(IL_LOG="$NOLOG" AUDIT_TRAIL="$AUDIT_NONHOOK" bash "$MA_BLK" 2>/dev/null)"
  nh_leak=""
  for _p in 'src/hooks/useAuth.ts' '.git/hooks/pre-commit' 'node_modules/x/hooks/y.js' 'app/hooks/z.ts'; do
    grep -qF "$_p" <<< "$out_nh" && nh_leak="$nh_leak [$_p]"
  done
  if [ -z "$nh_leak" ]; then
    pass "MA-R2-srchooks-excluded" "no non-Correctless hooks dir counted (src/.git/node_modules/app hooks excluded)"
  else
    fail "MA-R2-srchooks-excluded" "non-hook path(s) leaked in as hook-edits:$nh_leak"
  fi
  if grep -qF '.correctless/hooks/foo.sh' <<< "$out_nh"; then
    pass "MA-R2-srchooks-included" ".correctless/hooks/foo.sh IS counted (real hook root, sibling to the excluded dirs)"
  else
    fail "MA-R2-srchooks-included" ".correctless/hooks/foo.sh not counted — real hook root dropped"
  fi
  if grep -qE 'and 1 hook-edit entries across 1 edit-session' <<< "$out_nh"; then
    pass "MA-R2-srchooks-count" "exactly 1 hook-edit counted (only the .correctless/hooks entry)"
  else
    fail "MA-R2-srchooks-count" "hook-edit count wrong — expected exactly 1 (.correctless/hooks/foo.sh)"
  fi

  # ------------------------------------------------------------------------
  # MA-R2-toolgate [integration] (FIX 6): Read/Grep entries on a hooks/ file are
  # NOT counted (write-tool gate); Edit AND Bash entries on a hooks/ file ARE.
  # ------------------------------------------------------------------------
  section "MA-R2-toolgate: Read/Grep on a hooks/ file excluded; Edit and Bash counted (FIX 6)"

  out_tg="$(IL_LOG="$NOLOG" AUDIT_TRAIL="$AUDIT_TOOLGATE" bash "$MA_BLK" 2>/dev/null)"
  tg_leak=""
  for _p in 'hooks/read-not-an-edit.sh' 'hooks/grep-not-an-edit.sh'; do
    grep -qF "$_p" <<< "$out_tg" && tg_leak="$tg_leak [$_p]"
  done
  if [ -z "$tg_leak" ]; then
    pass "MA-R2-toolgate-readgrep" "Read/Grep entries on a hooks/ file NOT counted (write-tool gate)"
  else
    fail "MA-R2-toolgate-readgrep" "Read/Grep hook access leaked in as hook-edits:$tg_leak"
  fi
  if grep -qF 'hooks/edited-via-edit.sh' <<< "$out_tg" \
     && grep -qF 'hooks/edited-via-bash.sh' <<< "$out_tg"; then
    pass "MA-R2-toolgate-editbash" "Edit and Bash entries on a hooks/ file ARE counted (Bash is a real write vector)"
  else
    fail "MA-R2-toolgate-editbash" "Edit and/or Bash hook edit dropped — write-tool gate over-restrictive"
  fi
  if grep -qE 'and 2 hook-edit entries across 2 edit-session' <<< "$out_tg"; then
    pass "MA-R2-toolgate-count" "exactly 2 hook-edits counted (Edit + Bash); Read/Grep excluded"
  else
    fail "MA-R2-toolgate-count" "hook-edit count wrong — expected 2 (Edit + Bash)"
  fi

  # ------------------------------------------------------------------------
  # MA-R2-deadchannel-harness [integration] (FIX 3): the dead-channel WARNING now
  # names the benign "harness <2.1.69 which does not emit InstructionsLoaded" cause.
  # ------------------------------------------------------------------------
  section "MA-R2-deadchannel-harness: dead-channel WARNING names the harness <2.1.69 benign cause (FIX 3)"

  out_dc="$(IL_LOG="$NOLOG" AUDIT_TRAIL="$AUDIT_SESS" bash "$MA_BLK" 2>/dev/null)"
  if grep -qF 'WARNING:' <<< "$out_dc" \
     && grep -qF 'harness <2.1.69 which does not emit InstructionsLoaded' <<< "$out_dc"; then
    pass "MA-R2-deadchannel-harness" "dead-channel WARNING includes the harness <2.1.69 benign cause"
  else
    fail "MA-R2-deadchannel-harness" "dead-channel WARNING missing the harness <2.1.69 benign cause (FIX 3)"
  fi

  # ------------------------------------------------------------------------
  # MA-R2-driftnote-suppressed [integration] (FIX 4): when EVERY hook-edit is
  # unattributed (pre-instrumentation), the MA-006 format-drift note is SUPPRESSED
  # (attributed==0 is benign, not drift) — but the unattributed-group caveat still
  # renders. rule-loads DO carry session_ids, which the round-1 code would have
  # misinterpreted as a format-drift signal.
  # ------------------------------------------------------------------------
  section "MA-R2-driftnote-suppressed: all-unattributed edits suppress the format-drift note; caveat still shown (FIX 4)"

  out_dn="$(IL_LOG="$LOG_SAMPLE" AUDIT_TRAIL="$AUDIT_ALLUNATTR" bash "$MA_BLK" 2>/dev/null)"
  if grep -qF 'session_id format drift' <<< "$out_dn" \
     || grep -qF 'none matched an edit-session_id' <<< "$out_dn"; then
    fail "MA-R2-driftnote-suppressed" "format-drift note fired though ALL edits are unattributed (FIX 4 regression)"
  else
    pass "MA-R2-driftnote-suppressed" "no session_id-format-drift note when every edit is unattributed (FIX 4)"
  fi
  if grep -qF 'these edits predate session_id instrumentation' <<< "$out_dn"; then
    pass "MA-R2-driftnote-caveat" "unattributed-group caveat still shown (suppression does not hide the caveat)"
  else
    fail "MA-R2-driftnote-caveat" "unattributed-group caveat missing"
  fi

  # ------------------------------------------------------------------------
  # MA-R2-liveness-reconcile [integration] (FIX 5): the liveness rule-load
  # denominator reconciles as read K = attributed + (K-attributed from other
  # sessions) + null. LOG_SAMPLE has 3 rule-loads (sess 111,222,999); AUDIT_SESS
  # real edit-sessions are 111,222 -> 2 attributed, 1 other, 0 null, 2+1+0=3.
  # ------------------------------------------------------------------------
  section "MA-R2-liveness-reconcile: read K = attributed + other-session + null (FIX 5)"

  out_lr="$(IL_LOG="$LOG_SAMPLE" AUDIT_TRAIL="$AUDIT_SESS" bash "$MA_BLK" 2>/dev/null)"
  if grep -qF "read 3 rule-load event(s) (2 attributed to this workflow's edit-sessions, 1 from other sessions, 0 with null rule_file)" <<< "$out_lr"; then
    pass "MA-R2-liveness-reconcile" "liveness reconciles read 3 = 2 attributed + 1 other + 0 null (A + (K-A) = K)"
  else
    fail "MA-R2-liveness-reconcile" "liveness reconciliation wrong (want '2 attributed ... 1 from other sessions, 0 with null rule_file')"
  fi

  # ------------------------------------------------------------------------
  # MA-R2-nullratio-50 [integration] (FIX 7 boundary): exactly 50% null rule_file
  # (2 of 4) fires the high-null-ratio note (null_rules*2 >= rule_loads), but NOT
  # the 100%-equality 'all with null rule_file' wording.
  # ------------------------------------------------------------------------
  section "MA-R2-nullratio-50: exactly 50% null fires the high-null-ratio note (FIX 7 boundary)"

  out_nr="$(run_block_iso "$LOG_HALFNULL" "")"
  if grep -q 'high null-rule ratio (2/4)' <<< "$out_nr" \
     && grep -q 'possible harness field drift' <<< "$out_nr"; then
    pass "MA-R2-nullratio-50" "2-of-4 null (50%) fires 'high null-rule ratio (2/4)' (null*2 >= rule_loads boundary)"
  else
    fail "MA-R2-nullratio-50" "50% null did not fire the high-null-ratio note (FIX 7 boundary null*2>=K)"
  fi
  if grep -q 'all with null rule_file' <<< "$out_nr"; then
    fail "MA-R2-nullratio-50-not100" "50%-null wrongly emitted the 100% 'all with null rule_file' wording"
  else
    pass "MA-R2-nullratio-50-not100" "50%-null does not emit the 100% 'all with null rule_file' wording"
  fi
fi

rm -f "$MA_BLK"

summary "test-instructions-loaded-cwtf"
