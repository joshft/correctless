#!/usr/bin/env bash
# Correctless — Sanctioned meta-writer tests (scripts/meta-record.sh)
# Spec: .correctless/specs/calibration-writer.md
#   INV-001..010, PRH-001..006, BND-001, exit-code semantics table.
# Run from repo root: bash tests/test-meta-record.sh
#
# RED PHASE: scripts/meta-record.sh is a STUB:TDD stub (exits non-zero, no
# output). Every behavioral test below asserts the SPEC'd behavior and MUST
# fail now for the right reason (missing writer/logic), not error spuriously.

source "$(dirname "${BASH_SOURCE[0]}")/test-helpers.sh"

WRITER="$REPO_DIR/scripts/meta-record.sh"
REGISTRY="$REPO_DIR/scripts/sanctioned-meta-writers.tsv"
GUARD="$REPO_DIR/hooks/sensitive-file-guard.sh"

CAL_REL=".correctless/meta/intensity-calibration.json"
PAT_REL=".correctless/meta/pat001-measurement-due.json"
BASE_REL=".correctless/meta/model-baselines.json"

# ---------------------------------------------------------------------------
# Harness helpers
# ---------------------------------------------------------------------------

# new_project — a throwaway project dir with .correctless/meta/ ready.
new_project() {
  local d
  d="$(mktemp -d "${TMPDIR:-/tmp}/mr-proj-XXXXXX")"
  mkdir -p "$d/.correctless/meta"
  printf '%s' "$d"
}

# write_tmp <content> -> path (byte-preserving via printf %s)
write_tmp() {
  local f
  f="$(mktemp "${TMPDIR:-/tmp}/mr-in-XXXXXX")"
  printf '%s' "$1" > "$f"
  printf '%s' "$f"
}

# run_writer <projdir> <stdin_file|-> op [args...]
# Populates globals RW_EXIT, RW_STDOUT, RW_STDERR. cd is scoped to a subshell
# so the writer resolves its .correctless/meta/ destinations relative to the
# throwaway project, while still sourcing the real lib.sh from its own dir.
run_writer() {
  local proj="$1" sfile="$2"; shift 2
  local errf; errf="$(mktemp)"
  if [ "$sfile" = "-" ]; then
    RW_STDOUT="$(cd "$proj" && bash "$WRITER" "$@" </dev/null 2>"$errf")"; RW_EXIT=$?
  else
    RW_STDOUT="$(cd "$proj" && bash "$WRITER" "$@" <"$sfile" 2>"$errf")"; RW_EXIT=$?
  fi
  RW_STDERR="$(cat "$errf" 2>/dev/null)"; rm -f "$errf"
}

hash_file() { sha256sum "$1" 2>/dev/null | cut -d' ' -f1; }
jq_valid()  { jq -e . "$1" >/dev/null 2>&1; }

# A real-shaped typed calibration entry (integers/enum strings), matching the
# skills/cverify/SKILL.md "Write Calibration Entry" producer schema (INV-008).
# NOT the placeholder-string template (whose numeric fields are documented as
# strings) — a typed fixture per the spec's AP-031 dormant-case directive.
typed_entry() {
  cat <<'JSON'
{"feature_slug":"calibration-writer","recommended_intensity":"high","actual_intensity":"high","actual_qa_rounds":2,"actual_findings_count":3,"actual_spec_updates":1,"actual_tokens":123456,"file_paths_touched":["scripts/meta-record.sh","tests/test-meta-record.sh"],"timestamp":"2026-07-04T12:00:00Z"}
JSON
}

# A real multi-entry calibration fixture (two prior entries), typed. Used to
# assert deep-equal preservation of the prior slice on append (INV-001/PRH-001).
seed_multi_calibration() {
  local dest="$1"
  cat > "$dest" <<'JSON'
{"calibration_entries":[
  {"feature_slug":"semi-auto-mode","recommended_intensity":"high","actual_intensity":"high","actual_qa_rounds":2,"actual_findings_count":3,"actual_spec_updates":0,"actual_tokens":0,"file_paths_touched":["skills/cauto/SKILL.md","sync.sh"],"timestamp":"2026-04-09T23:45:00Z"},
  {"feature_slug":"harness-fingerprint","recommended_intensity":"critical","actual_intensity":"critical","actual_qa_rounds":3,"actual_findings_count":22,"actual_spec_updates":2,"actual_tokens":999,"file_paths_touched":["scripts/harness-fingerprint.sh"],"timestamp":"2026-04-22T10:00:00Z"}
]}
JSON
}

# ===========================================================================
# INV-001 / PRH-001 — sole append-only writer, deep-equal prior slice + order
# ===========================================================================
section "INV-001 / PRH-001: append preserves prior entries deep-equal + in order"

test_inv001_deep_equal_append() {
  # Tests INV-001 [unit]: append one entry; every pre-existing entry unchanged
  # as a JSON value (deep-equal, NOT byte-identity — jq reformats) and prior
  # relative order preserved.
  local proj; proj="$(new_project)"
  seed_multi_calibration "$proj/$CAL_REL"
  local before_slice; before_slice="$(jq -S '.calibration_entries' "$proj/$CAL_REL")"

  local in; in="$(write_tmp "$(typed_entry)")"
  run_writer "$proj" "$in" calibration-append
  rm -f "$in"

  if [ "$RW_EXIT" -eq 0 ]; then
    pass "INV-001a" "calibration-append exits 0 on a valid entry"
  else
    fail "INV-001a" "calibration-append should exit 0 on a valid entry (got $RW_EXIT)"
  fi

  # length grew by exactly one
  local n; n="$(jq '.calibration_entries|length' "$proj/$CAL_REL" 2>/dev/null || echo -1)"
  if [ "$n" = "3" ]; then
    pass "INV-001b" "append grows calibration_entries from 2 -> 3"
  else
    fail "INV-001b" "expected 3 entries after append, got $n"
  fi

  # PRH-001: the prior [:-1] slice deep-equals the original entries, in order.
  local after_slice; after_slice="$(jq -S '.calibration_entries[:-1]' "$proj/$CAL_REL" 2>/dev/null)"
  if [ "$after_slice" = "$before_slice" ]; then
    pass "PRH-001a" "prior entries preserved deep-equal + in order (jq --sort-keys on [:-1] slice)"
  else
    fail "PRH-001a" "append mutated/reordered a prior calibration entry"
  fi

  # the new entry is the LAST one (append, not prepend)
  local last_slug; last_slug="$(jq -r '.calibration_entries[-1].feature_slug' "$proj/$CAL_REL" 2>/dev/null)"
  if [ "$last_slug" = "calibration-writer" ]; then
    pass "INV-001c" "new entry appended at the tail (order-preserving)"
  else
    fail "INV-001c" "new entry not appended at tail (last slug=$last_slug)"
  fi
  rm -rf "$proj"
}
test_inv001_deep_equal_append

test_inv001_duplicate_feature_slug_allowed() {
  # Tests INV-001 [unit] / DD-004: pure append — a duplicate feature_slug is
  # permitted (no dedup).
  local proj; proj="$(new_project)"
  seed_multi_calibration "$proj/$CAL_REL"
  # entry reusing an existing slug
  local dup; dup='{"feature_slug":"semi-auto-mode","recommended_intensity":"standard","actual_intensity":"standard","actual_qa_rounds":1,"actual_findings_count":0,"actual_spec_updates":0,"actual_tokens":10,"file_paths_touched":["x"],"timestamp":"2026-07-04T00:00:00Z"}'
  local in; in="$(write_tmp "$dup")"
  run_writer "$proj" "$in" calibration-append
  rm -f "$in"
  local dup_count; dup_count="$(jq '[.calibration_entries[]|select(.feature_slug=="semi-auto-mode")]|length' "$proj/$CAL_REL" 2>/dev/null || echo 0)"
  if [ "$RW_EXIT" -eq 0 ] && [ "$dup_count" = "2" ]; then
    pass "INV-001d" "duplicate feature_slug permitted (pure append, DD-004)"
  else
    fail "INV-001d" "duplicate feature_slug should append (exit=$RW_EXIT dup_count=$dup_count)"
  fi
  rm -rf "$proj"
}
test_inv001_duplicate_feature_slug_allowed

# ===========================================================================
# INV-002 — schema validation under lock, PERMISSIVE unknown fields, fail-closed
# ===========================================================================
section "INV-002: schema validation, permissive unknown fields, fail-closed"

test_inv002_unknown_field_accepted() {
  # Tests INV-002 [unit]: an entry with an UNKNOWN extra field is ACCEPTED and
  # PRESERVED (forward-compat) — never a rejection reason.
  local proj; proj="$(new_project)"
  printf '%s' '{"calibration_entries":[]}' > "$proj/$CAL_REL"
  local entry; entry="$(typed_entry | jq -c '. + {"future_field_v2":"keepme","nested_new":{"k":1}}')"
  local in; in="$(write_tmp "$entry")"
  run_writer "$proj" "$in" calibration-append
  rm -f "$in"
  local kept; kept="$(jq -r '.calibration_entries[-1].future_field_v2 // "MISSING"' "$proj/$CAL_REL" 2>/dev/null)"
  if [ "$RW_EXIT" -eq 0 ] && [ "$kept" = "keepme" ]; then
    pass "INV-002-unknown" "unknown extra field accepted AND preserved (permissive policy)"
  else
    fail "INV-002-unknown" "unknown field must be accepted+preserved (exit=$RW_EXIT kept=$kept)"
  fi
  rm -rf "$proj"
}
test_inv002_unknown_field_accepted

test_inv002_malformed_rejected_file_unchanged() {
  # Tests INV-002 [unit]: each malformed shape rejected with non-zero exit +
  # FAILED token AND the file is left byte-for-byte unchanged.
  local proj before_hash
  # payload label | payload
  local cases=(
    "missing-required::$(typed_entry | jq -c 'del(.feature_slug)')"
    "wrong-type-int::$(typed_entry | jq -c '.actual_qa_rounds="two"')"
    "wrong-type-array::$(typed_entry | jq -c '.file_paths_touched="notarray"')"
    "bad-enum::$(typed_entry | jq -c '.recommended_intensity="bogus"')"
    "negative-int::$(typed_entry | jq -c '.actual_findings_count=-1')"
    "not-json::this is not json {"
    "wrong-root::[1,2,3]"
  )
  local c label payload
  for c in "${cases[@]}"; do
    label="${c%%::*}"; payload="${c#*::}"
    proj="$(new_project)"
    printf '%s' '{"calibration_entries":[]}' > "$proj/$CAL_REL"
    before_hash="$(hash_file "$proj/$CAL_REL")"
    local in; in="$(write_tmp "$payload")"
    run_writer "$proj" "$in" calibration-append
    rm -f "$in"
    local after_hash; after_hash="$(hash_file "$proj/$CAL_REL")"
    if [ "$RW_EXIT" -ne 0 ] && [ "$before_hash" = "$after_hash" ]; then
      pass "INV-002-$label" "malformed ($label) rejected non-zero, file unchanged"
    else
      fail "INV-002-$label" "malformed ($label) must reject + leave file unchanged (exit=$RW_EXIT changed=$([ "$before_hash" != "$after_hash" ] && echo yes || echo no))"
    fi
    # FAILED token on stdout
    if echo "$RW_STDOUT" | grep -qF "meta-record: FAILED $CAL_REL:"; then
      pass "INV-002-$label-token" "rejected ($label) prints mechanical FAILED token"
    else
      fail "INV-002-$label-token" "rejected ($label) must print 'meta-record: FAILED $CAL_REL: <reason>'"
    fi
    rm -rf "$proj"
  done
}
test_inv002_malformed_rejected_file_unchanged

test_inv002_optional_field_wrong_type_rejected() {
  # Tests INV-002 [unit] / A3: optional fields are validated FOR TYPE when
  # present (accepted when absent). A wrong-typed optional field is rejected +
  # FAILED token + file unchanged.
  local proj before
  local cases=(
    "cost-not-number::$(typed_entry | jq -c '.actual_cost_usd="free"')"
    "harness-not-int::$(typed_entry | jq -c '.harness_version="v5"')"
    "harness-float::$(typed_entry | jq -c '.harness_version=5.5')"
    "fixrounds-not-int::$(typed_entry | jq -c '.fix_rounds_triggered="two"')"
  )
  local c label payload
  for c in "${cases[@]}"; do
    label="${c%%::*}"; payload="${c#*::}"
    proj="$(new_project)"
    printf '%s' '{"calibration_entries":[]}' > "$proj/$CAL_REL"
    before="$(hash_file "$proj/$CAL_REL")"
    local in; in="$(write_tmp "$payload")"
    run_writer "$proj" "$in" calibration-append
    rm -f "$in"
    if [ "$RW_EXIT" -ne 0 ] && [ "$before" = "$(hash_file "$proj/$CAL_REL")" ] \
       && echo "$RW_STDOUT" | grep -qF "meta-record: FAILED $CAL_REL:"; then
      pass "INV-002-opt-$label" "wrong-typed optional field ($label) rejected, file unchanged"
    else
      fail "INV-002-opt-$label" "wrong-typed optional ($label) must reject + FAILED token (exit=$RW_EXIT)"
    fi
    rm -rf "$proj"
  done

  # And the SAME optional fields, correctly typed OR absent, are ACCEPTED.
  proj="$(new_project)"
  printf '%s' '{"calibration_entries":[]}' > "$proj/$CAL_REL"
  local good; good="$(typed_entry | jq -c '.actual_cost_usd=1.23 | .harness_version=5 | .fix_rounds_triggered=1')"
  local gin; gin="$(write_tmp "$good")"
  run_writer "$proj" "$gin" calibration-append
  rm -f "$gin"
  if [ "$RW_EXIT" -eq 0 ]; then
    pass "INV-002-opt-typed-ok" "correctly-typed optional fields accepted"
  else
    fail "INV-002-opt-typed-ok" "correctly-typed optional fields must be accepted (exit=$RW_EXIT)"
  fi
  rm -rf "$proj"
}
test_inv002_optional_field_wrong_type_rejected

test_inv002_validation_under_lock_source() {
  # Tests INV-002 [unit] / A3: source-level — the jq required-field/type
  # validation must sit BETWEEN _acquire_state_lock and _release_state_lock (no
  # TOCTOU window; decision-read + validate + write all inside one critical
  # section). Assert acquire < validate < release by line number.
  local acq rel val
  acq="$(grep -nE '_acquire_state_lock' "$WRITER" | head -1 | cut -d: -f1)"
  rel="$(grep -nE '_release_state_lock' "$WRITER" | tail -1 | cut -d: -f1)"
  # A validation marker: a jq -e required-field/type check.
  val="$(grep -nE 'jq[[:space:]]+-e|jq[[:space:]].*-e[[:space:]]' "$WRITER" | head -1 | cut -d: -f1)"
  if [ -n "$acq" ] && [ -n "$rel" ] && [ -n "$val" ] && [ "$acq" -lt "$val" ] && [ "$val" -lt "$rel" ]; then
    pass "INV-002-under-lock" "jq validation sits between _acquire_state_lock and _release_state_lock (no TOCTOU)"
  else
    fail "INV-002-under-lock" "validation must be under the lock (acq=$acq val=$val rel=$rel)"
  fi
}
test_inv002_validation_under_lock_source

# ===========================================================================
# BND-001 — calibration target initialization (absent / zero-byte / bad-root)
# ===========================================================================
section "BND-001: calibration target initialization"

test_bnd001_calibration_absent_creates_and_appends() {
  # Tests BND-001 [unit] / RS-010: absent file -> create {"calibration_entries":[]}
  # then append (exit 0, entry present). The create happens AFTER the INV-010
  # parent-symlink check (EXT-005) — here the parent is a real dir.
  local proj; proj="$(new_project)"
  rm -f "$proj/$CAL_REL"
  local in; in="$(write_tmp "$(typed_entry)")"
  run_writer "$proj" "$in" calibration-append
  rm -f "$in"
  local n; n="$(jq '.calibration_entries|length' "$proj/$CAL_REL" 2>/dev/null || echo -1)"
  if [ "$RW_EXIT" -eq 0 ] && [ "$n" = "1" ]; then
    pass "BND-001-absent" "absent calibration file created + entry appended"
  else
    fail "BND-001-absent" "absent file must be created+appended (exit=$RW_EXIT n=$n)"
  fi
  rm -rf "$proj"
}
test_bnd001_calibration_absent_creates_and_appends

test_bnd001_calibration_zero_byte_creates() {
  # Tests BND-001 [unit] / RS-010: a zero-byte file ([ ! -s ]) takes the same
  # create-then-append path as an absent file.
  local proj; proj="$(new_project)"
  : > "$proj/$CAL_REL"   # zero bytes
  local in; in="$(write_tmp "$(typed_entry)")"
  run_writer "$proj" "$in" calibration-append
  rm -f "$in"
  local n; n="$(jq '.calibration_entries|length' "$proj/$CAL_REL" 2>/dev/null || echo -1)"
  if [ "$RW_EXIT" -eq 0 ] && [ "$n" = "1" ]; then
    pass "BND-001-zerobyte" "zero-byte calibration file re-seeded + entry appended (RS-010)"
  else
    fail "BND-001-zerobyte" "zero-byte file must take the create path (exit=$RW_EXIT n=$n)"
  fi
  rm -rf "$proj"
}
test_bnd001_calibration_zero_byte_creates

test_bnd001_calibration_bad_root_fails() {
  # Tests BND-001 [unit]: existing file parses but calibration_entries is NOT an
  # array (or root not an object) -> fail-loud + FAILED token, no write.
  local proj before
  local cases=(
    'entries-not-array::{"calibration_entries":"x"}'
    'root-not-object::[1,2,3]'
    'missing-key::{"other":1}'
  )
  local c label payload
  for c in "${cases[@]}"; do
    label="${c%%::*}"; payload="${c#*::}"
    proj="$(new_project)"
    printf '%s' "$payload" > "$proj/$CAL_REL"
    before="$(hash_file "$proj/$CAL_REL")"
    local in; in="$(write_tmp "$(typed_entry)")"
    run_writer "$proj" "$in" calibration-append
    rm -f "$in"
    if [ "$RW_EXIT" -ne 0 ] && [ "$before" = "$(hash_file "$proj/$CAL_REL")" ] \
       && echo "$RW_STDOUT" | grep -qF "meta-record: FAILED $CAL_REL:"; then
      pass "BND-001-badroot-$label" "bad-root calibration ($label) fails loud, unchanged"
    else
      fail "BND-001-badroot-$label" "bad-root ($label) must fail-loud (exit=$RW_EXIT)"
    fi
    rm -rf "$proj"
  done
}
test_bnd001_calibration_bad_root_fails

# ===========================================================================
# INV-003 / PRH-004 — fail-loud mechanical token; three-state exit table
# ===========================================================================
section "INV-003 / PRH-004: three-state exit table (write / intended-no-op / rejected)"

test_inv003_state_write_applied() {
  # Tests INV-003 [unit]: exit 0 + success line + mutation landed.
  local proj; proj="$(new_project)"
  printf '%s' '{"calibration_entries":[]}' > "$proj/$CAL_REL"
  local in; in="$(write_tmp "$(typed_entry)")"
  run_writer "$proj" "$in" calibration-append
  rm -f "$in"
  local n; n="$(jq '.calibration_entries|length' "$proj/$CAL_REL" 2>/dev/null || echo -1)"
  if [ "$RW_EXIT" -eq 0 ] && [ "$n" = "1" ] && ! echo "$RW_STDOUT" | grep -qF "FAILED"; then
    pass "INV-003-write" "write-applied state: exit 0, entry landed, no FAILED token"
  else
    fail "INV-003-write" "write-applied must be exit0+landed (exit=$RW_EXIT n=$n)"
  fi
  rm -rf "$proj"
}
test_inv003_state_write_applied

test_inv003_state_intended_noop_no_rewrite() {
  # Tests INV-003 [unit] / EXT-001: intended no-op = exit 0 + 'no change:' AND
  # NO file bytes rewritten (inode + content unchanged). Uses pat001 present-
  # non-null (a guarded INV-009 no-op).
  local proj; proj="$(new_project)"
  cat > "$proj/$PAT_REL" <<'JSON'
{"feature":"demo","due_at_pr_count":3,"created_at_commit":"206d68c05772bfca30d3a0f1dcf8ee063c3f3820"}
JSON
  local before_hash before_inode
  before_hash="$(hash_file "$proj/$PAT_REL")"
  before_inode="$(stat -c '%i' "$proj/$PAT_REL" 2>/dev/null || stat -f '%i' "$proj/$PAT_REL" 2>/dev/null)"
  run_writer "$proj" "-" pat001-set-created-at 0000000000000000000000000000000000000000
  local after_hash after_inode
  after_hash="$(hash_file "$proj/$PAT_REL")"
  after_inode="$(stat -c '%i' "$proj/$PAT_REL" 2>/dev/null || stat -f '%i' "$proj/$PAT_REL" 2>/dev/null)"

  if [ "$RW_EXIT" -eq 0 ] && echo "$RW_STDOUT" | grep -qF "no change:"; then
    pass "INV-003-noop-signal" "intended no-op: exit 0 + 'no change:' line"
  else
    fail "INV-003-noop-signal" "intended no-op must be exit0 + 'no change:' (exit=$RW_EXIT out=$RW_STDOUT)"
  fi
  if [ "$before_hash" = "$after_hash" ] && [ "$before_inode" = "$after_inode" ]; then
    pass "INV-003-noop-norewrite" "intended no-op rewrites NO bytes (inode+content unchanged, EXT-001)"
  else
    fail "INV-003-noop-norewrite" "intended no-op must NOT rewrite the file"
  fi
  rm -rf "$proj"
}
test_inv003_state_intended_noop_no_rewrite

test_inv003_state_rejected_failinjection() {
  # Tests INV-003 [unit] / PRH-004: an ATTEMPTED write that cannot complete
  # (unparsable existing file) exits non-zero + FAILED stdout token + stderr
  # diagnostic naming the file. NEVER exit 0 after an attempted-but-unlanded
  # write.
  local proj; proj="$(new_project)"
  printf '%s' '{ this is corrupt json' > "$proj/$CAL_REL"
  local in; in="$(write_tmp "$(typed_entry)")"
  run_writer "$proj" "$in" calibration-append
  rm -f "$in"
  if [ "$RW_EXIT" -ne 0 ]; then
    pass "INV-003-rej-exit" "attempted write on corrupt file exits non-zero (never silent success)"
  else
    fail "INV-003-rej-exit" "corrupt-target append must exit non-zero (got 0 — PRH-004 violation)"
  fi
  if echo "$RW_STDOUT" | grep -qE "^meta-record: FAILED $CAL_REL: .+"; then
    pass "INV-003-rej-token" "exact mechanical stdout token 'meta-record: FAILED <file>: <reason>'"
  else
    fail "INV-003-rej-token" "must print exact FAILED token to stdout"
  fi
  if echo "$RW_STDERR" | grep -qF "$CAL_REL"; then
    pass "INV-003-rej-stderr" "stderr diagnostic names the destination file"
  else
    fail "INV-003-rej-stderr" "stderr diagnostic must name the destination file"
  fi
  rm -rf "$proj"
}
test_inv003_state_rejected_failinjection

# ===========================================================================
# INV-006 — class closure: every SFG-DEFAULTS meta json maps to a registry row
# ===========================================================================
section "INV-006: class closure — DEFAULTS meta set maps to registered writers"

# AP-031 real fixture — verbatim excerpt of the SFG DEFAULTS meta lines.
# Source: hooks/sensitive-file-guard.sh  (DEFAULTS heredoc, STEP 6)
SFG_DEFAULTS_META_FIXTURE='.correctless/meta/harness-fingerprint.json
.correctless/meta/model-baselines.json
.correctless/meta/prune-pattern-baseline.json
.correctless/meta/intensity-calibration.json
.correctless/meta/pat001-measurement-due.json'

test_inv006_anchored_regex_rejects_siblings() {
  # Tests INV-006 [integration] / AP-032: the DEFAULTS-meta extraction regex is
  # ANCHORED (^\.correctless/meta/[^/]+\.json$) and REJECTS adversarial siblings
  # (bare credentials.json / a nested path / a non-meta json). A bare `.json`
  # substring match would over-match — this asserts it does not.
  local re='^\.correctless/meta/[^/]+\.json$'
  local reject
  for reject in 'credentials.json' 'service-account-x.json' '.correctless/meta/sub/dir.json' '.correctless/metaX/foo.json' '.correctless/meta/foo.json.bak'; do
    if printf '%s\n' "$reject" | grep -qE "$re"; then
      fail "INV-006-reject" "anchored regex must REJECT adversarial sibling '$reject'"
    else
      pass "INV-006-reject-$(printf '%s' "$reject" | tr -c 'a-zA-Z0-9' '_')" "anchored regex rejects '$reject'"
    fi
  done
  # positive: each of the five real meta files matches the anchor
  local f
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    if printf '%s\n' "$f" | grep -qE "$re"; then
      pass "INV-006-match-$(basename "$f")" "anchored regex matches real meta file '$f'"
    else
      fail "INV-006-match-$(basename "$f")" "anchored regex should match '$f'"
    fi
  done <<< "$SFG_DEFAULTS_META_FIXTURE"
}
test_inv006_anchored_regex_rejects_siblings

test_inv006_verbatim_fixture_matches_live_defaults() {
  # Tests INV-006 [integration] / AP-031: the pinned verbatim fixture is a real
  # subset of the LIVE SFG DEFAULTS heredoc — guards fixture drift from the
  # producer (hooks/sensitive-file-guard.sh).
  local re='^\.correctless/meta/[^/]+\.json$'
  # Extract the live DEFAULTS meta set (anchored) from the real hook.
  local live; live="$(grep -oE "$re" "$GUARD" 2>/dev/null | sort -u)"
  local fixture; fixture="$(printf '%s\n' "$SFG_DEFAULTS_META_FIXTURE" | sort -u)"
  local missing=0 f
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    echo "$live" | grep -qxF "$f" || { missing=1; echo "    (fixture line not in live DEFAULTS: $f)"; }
  done <<< "$fixture"
  if [ "$missing" -eq 0 ]; then
    pass "INV-006-fixture" "verbatim SFG fixture lines all present in live DEFAULTS (AP-031)"
  else
    fail "INV-006-fixture" "verbatim SFG fixture drifted from live hooks/sensitive-file-guard.sh"
  fi
}
test_inv006_verbatim_fixture_matches_live_defaults

test_inv006_every_defaults_meta_has_registry_row() {
  # Tests INV-006 [integration]: over-enumerate the live DEFAULTS meta set and
  # require EACH to match a row in the writer registry (never a hardcoded
  # pass-list). Registry columns: <meta-path>\t<writer-script>\t<operation>.
  # RED: the registry file does not exist yet -> every mapping fails.
  local re='^\.correctless/meta/[^/]+\.json$'
  local live; live="$(grep -oE "$re" "$GUARD" 2>/dev/null | sort -u)"
  if [ ! -f "$REGISTRY" ]; then
    # Absence is the RED signal — assert per-file so the failing count is clear.
    local f
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      fail "INV-006-reg-$(basename "$f")" "registry $REGISTRY missing — no mapping for '$f'"
    done <<< "$live"
    return
  fi
  local f
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    # Column 1 exact match; must name a writer script + operation.
    if awk -F'\t' -v p="$f" '$1==p && $2!="" && $3!="" {found=1} END{exit(found?0:1)}' "$REGISTRY"; then
      pass "INV-006-reg-$(basename "$f")" "'$f' maps to a registered (writer, operation)"
    else
      fail "INV-006-reg-$(basename "$f")" "'$f' has no complete registry row"
    fi
  done <<< "$live"

  # And the five known files resolve to the expected writers (closure = zero
  # exemptions, all script-writers).
  local expect=(
    ".correctless/meta/intensity-calibration.json	meta-record.sh"
    ".correctless/meta/pat001-measurement-due.json	meta-record.sh"
    ".correctless/meta/model-baselines.json	meta-record.sh"
    ".correctless/meta/harness-fingerprint.json	harness-fingerprint.sh"
    ".correctless/meta/prune-pattern-baseline.json	prune-scan.sh"
  )
  local e path writer
  for e in "${expect[@]}"; do
    path="${e%%$'\t'*}"; writer="${e#*$'\t'}"
    if awk -F'\t' -v p="$path" -v w="$writer" '$1==p && $2 ~ w {found=1} END{exit(found?0:1)}' "$REGISTRY" 2>/dev/null; then
      pass "INV-006-expect-$(basename "$path")" "'$path' registered to $writer"
    else
      fail "INV-006-expect-$(basename "$path")" "'$path' should map to $writer in registry"
    fi
  done
}
test_inv006_every_defaults_meta_has_registry_row

# ===========================================================================
# INV-007 — concurrent-safe atomic write via REUSED lock helpers (no lost update)
# ===========================================================================
section "INV-007: concurrent appends — no lost update, fail-loud on contention"

test_inv007_concurrent_no_lost_update() {
  # Tests INV-007 [integration] / AP-020: fire N concurrent calibration-appends
  # with a HIGH lock timeout; assert (a) valid JSON throughout, (b) entries
  # added == exit-0 successes, (c) each success added exactly one entry,
  # (d) any non-zero printed the FAILED token. Do NOT assert a fixed N — a
  # legitimately-contended fail-loud is allowed (would contradict INV-003 if
  # counted as success).
  local proj; proj="$(new_project)"
  printf '%s' '{"calibration_entries":[]}' > "$proj/$CAL_REL"
  local N=8
  local rc_dir; rc_dir="$(mktemp -d)"
  local i
  for i in $(seq 1 "$N"); do
    (
      cd "$proj" || exit 99
      entry="$(typed_entry | jq -c --arg s "concurrent-$i" '.feature_slug=$s')"
      out="$(printf '%s' "$entry" | CORRECTLESS_LOCK_TIMEOUT=60 bash "$WRITER" calibration-append 2>/dev/null)"
      rc=$?
      printf '%s' "$rc" > "$rc_dir/rc.$i"
      printf '%s' "$out" > "$rc_dir/out.$i"
    ) &
  done
  wait

  # (a) valid JSON throughout (final state parses)
  if jq_valid "$proj/$CAL_REL"; then
    pass "INV-007-valid" "calibration file is valid JSON after N concurrent appends"
  else
    fail "INV-007-valid" "concurrent appends left the file invalid (lost-update/partial write)"
  fi

  # count successes (rc 0) and failures
  local successes=0 failures=0 token_ok=1
  for i in $(seq 1 "$N"); do
    local rc; rc="$(cat "$rc_dir/rc.$i" 2>/dev/null)"
    if [ "$rc" = "0" ]; then
      successes=$((successes + 1))
    else
      failures=$((failures + 1))
      grep -qF "meta-record: FAILED" "$rc_dir/out.$i" 2>/dev/null || token_ok=0
    fi
  done
  local entries; entries="$(jq '.calibration_entries|length' "$proj/$CAL_REL" 2>/dev/null || echo -1)"

  # (b) + (c): entries added == exit-0 successes (started from empty)
  if [ "$entries" = "$successes" ]; then
    pass "INV-007-count" "entries added ($entries) == exit-0 successes ($successes); each success added exactly one"
  else
    fail "INV-007-count" "no-lost-update violated: entries=$entries successes=$successes failures=$failures"
  fi

  # (d) any non-zero must have printed the FAILED token
  if [ "$token_ok" -eq 1 ]; then
    pass "INV-007-failtoken" "every non-zero concurrent invocation printed the FAILED token"
  else
    fail "INV-007-failtoken" "a contended failure did not print the FAILED token (INV-003)"
  fi
  rm -rf "$proj" "$rc_dir"
}
test_inv007_concurrent_no_lost_update

# ===========================================================================
# INV-008 — calibration schema pinned to the /cverify producer shape (PAT-015)
# ===========================================================================
section "INV-008: calibration schema pinned to /cverify producer (drift test)"

test_inv008_fields_pinned_to_producer() {
  # Tests INV-008 [unit] / PAT-015: each required field name in the writer's
  # accepted schema is cross-referenced line-by-line to the "Write Calibration
  # Entry" block of skills/cverify/SKILL.md. Guards schema<->producer drift.
  local cverify="$REPO_DIR/skills/cverify/SKILL.md"
  # Extract just the "Write Calibration Entry" section for the pairing.
  local block; block="$(awk '/^### Write Calibration Entry/{f=1} f{print} /^#### Token Summation/{if(f)exit}' "$cverify")"
  local required=(feature_slug recommended_intensity actual_intensity actual_qa_rounds actual_findings_count actual_tokens actual_spec_updates file_paths_touched timestamp)
  local fld
  for fld in "${required[@]}"; do
    if printf '%s' "$block" | grep -qF "$fld"; then
      pass "INV-008-$fld" "required field '$fld' present in /cverify producer block"
    else
      fail "INV-008-$fld" "required field '$fld' missing from /cverify 'Write Calibration Entry' block (drift)"
    fi
  done
}
test_inv008_fields_pinned_to_producer

test_inv008_typed_fixture_accepted() {
  # Tests INV-008 [unit]: the TYPED fixture (integers/enums, not placeholder
  # strings) is accepted by the writer — the fixture shape is the contract.
  local proj; proj="$(new_project)"
  printf '%s' '{"calibration_entries":[]}' > "$proj/$CAL_REL"
  # sanity: fixture numeric fields are actually numbers, not strings
  local qa_type; qa_type="$(typed_entry | jq -r '.actual_qa_rounds|type')"
  if [ "$qa_type" = "number" ]; then
    pass "INV-008-typed" "fixture uses typed integer fields (not placeholder strings)"
  else
    fail "INV-008-typed" "fixture actual_qa_rounds must be a number (got $qa_type)"
  fi
  local in; in="$(write_tmp "$(typed_entry)")"
  run_writer "$proj" "$in" calibration-append
  rm -f "$in"
  if [ "$RW_EXIT" -eq 0 ]; then
    pass "INV-008-accept" "typed producer-shaped entry accepted by writer"
  else
    fail "INV-008-accept" "typed producer-shaped entry must be accepted (exit=$RW_EXIT)"
  fi
  rm -rf "$proj"
}
test_inv008_typed_fixture_accepted

# ===========================================================================
# INV-009 — pat001 present-null-only + single-file; baselines key-merge
# ===========================================================================
section "INV-009: pat001 present-null-only / single-file; baselines key-merge"

seed_pat001() { printf '%s' "$2" > "$1/$PAT_REL"; }

test_inv009_pat001_present_null_sets() {
  # Tests INV-009 [unit]: present-null created_at_commit -> SET (exit0+success).
  local proj; proj="$(new_project)"
  seed_pat001 "$proj" '{"feature":"demo","due_at_pr_count":3,"created_at_commit":null}'
  local sha=1234567890abcdef1234567890abcdef12345678   # 40-hex
  run_writer "$proj" "-" pat001-set-created-at "$sha"
  local got; got="$(jq -r '.created_at_commit' "$proj/$PAT_REL" 2>/dev/null)"
  if [ "$RW_EXIT" -eq 0 ] && [ "$got" = "$sha" ]; then
    pass "INV-009-null-set" "present-null created_at_commit is set (exit0), value == sha"
  else
    fail "INV-009-null-set" "present-null must be set (exit=$RW_EXIT got=$got)"
  fi
  rm -rf "$proj"
}
test_inv009_pat001_present_null_sets

test_inv009_pat001_absent_field_noop() {
  # Tests INV-009 [unit] / #192: field ABSENT -> intended no-op (exit0 + 'no
  # change:'), never adds the field.
  local proj; proj="$(new_project)"
  seed_pat001 "$proj" '{"feature":"demo","due_at_pr_count":3}'
  local before; before="$(hash_file "$proj/$PAT_REL")"
  run_writer "$proj" "-" pat001-set-created-at 1234567890abcdef1234567890abcdef12345678
  local after; after="$(hash_file "$proj/$PAT_REL")"
  local has; has="$(jq 'has("created_at_commit")' "$proj/$PAT_REL" 2>/dev/null)"
  if [ "$RW_EXIT" -eq 0 ] && echo "$RW_STDOUT" | grep -qF "no change:" && [ "$before" = "$after" ] && [ "$has" = "false" ]; then
    pass "INV-009-absent-noop" "absent field -> no-op, field NOT added, no rewrite (#192)"
  else
    fail "INV-009-absent-noop" "absent field must be a no-op (exit=$RW_EXIT has=$has changed=$([ "$before" != "$after" ] && echo yes||echo no))"
  fi
  rm -rf "$proj"
}
test_inv009_pat001_absent_field_noop

test_inv009_pat001_present_nonnull_noop() {
  # Tests INV-009 [unit]: present-non-null -> intended no-op (never overwrite).
  local proj; proj="$(new_project)"
  seed_pat001 "$proj" '{"feature":"demo","created_at_commit":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}'
  local before; before="$(hash_file "$proj/$PAT_REL")"
  run_writer "$proj" "-" pat001-set-created-at 1234567890abcdef1234567890abcdef12345678
  local after got
  after="$(hash_file "$proj/$PAT_REL")"
  got="$(jq -r '.created_at_commit' "$proj/$PAT_REL" 2>/dev/null)"
  if [ "$RW_EXIT" -eq 0 ] && echo "$RW_STDOUT" | grep -qF "no change:" && [ "$before" = "$after" ] && [ "$got" = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" ]; then
    pass "INV-009-nonnull-noop" "present-non-null -> no-op, value untouched"
  else
    fail "INV-009-nonnull-noop" "present-non-null must be a no-op (exit=$RW_EXIT got=$got)"
  fi
  rm -rf "$proj"
}
test_inv009_pat001_present_nonnull_noop

test_inv009_pat001_corrupt_fails() {
  # Tests INV-009 [unit]: corrupt/non-object target -> fail-loud (never spurious
  # write). Covers unparsable and wrong-root-type.
  local payloads=('{ corrupt' '[1,2,3]' '"a string"')
  local p proj
  for p in "${payloads[@]}"; do
    proj="$(new_project)"
    seed_pat001 "$proj" "$p"
    local before; before="$(hash_file "$proj/$PAT_REL")"
    run_writer "$proj" "-" pat001-set-created-at 1234567890abcdef1234567890abcdef12345678
    local after; after="$(hash_file "$proj/$PAT_REL")"
    if [ "$RW_EXIT" -ne 0 ] && echo "$RW_STDOUT" | grep -qF "meta-record: FAILED $PAT_REL:" && [ "$before" = "$after" ]; then
      pass "INV-009-corrupt-$(printf '%s' "$p" | tr -c 'a-z0-9' '_' | cut -c1-8)" "corrupt pat001 target fails loud, unchanged"
    else
      fail "INV-009-corrupt-$(printf '%s' "$p" | tr -c 'a-z0-9' '_' | cut -c1-8)" "corrupt pat001 must fail-loud (exit=$RW_EXIT)"
    fi
    rm -rf "$proj"
  done
}
test_inv009_pat001_corrupt_fails

test_inv009_pat001_missing_file_fails() {
  # Tests INV-009 [unit] / BND-001: invoked on a MISSING target -> fail-loud
  # (the writer never creates pat001; /cdocs only invokes when it exists).
  local proj; proj="$(new_project)"
  rm -f "$proj/$PAT_REL"
  run_writer "$proj" "-" pat001-set-created-at 1234567890abcdef1234567890abcdef12345678
  if [ "$RW_EXIT" -ne 0 ] && [ ! -f "$proj/$PAT_REL" ]; then
    pass "INV-009-missing" "missing pat001 target fails loud; writer never creates it"
  else
    fail "INV-009-missing" "missing pat001 must fail-loud + not create file (exit=$RW_EXIT exists=$([ -f "$proj/$PAT_REL" ] && echo yes||echo no))"
  fi
  rm -rf "$proj"
}
test_inv009_pat001_missing_file_fails

test_inv009_pat001_no_other_meta_touched() {
  # Tests INV-009 [integration] / #226: a pat001 write touches NO other meta
  # file (the blanket-scan cross-feature-pollution guard). Sibling meta files'
  # mtime + content stay unchanged.
  local proj; proj="$(new_project)"
  seed_pat001 "$proj" '{"feature":"A","created_at_commit":null}'
  printf '%s' '{"calibration_entries":[{"feature_slug":"x"}]}' > "$proj/$CAL_REL"
  printf '%s' '{"schema_version":1,"baselines":{"m|1":{"k":1}}}' > "$proj/$BASE_REL"
  local cal_h base_h; cal_h="$(hash_file "$proj/$CAL_REL")"; base_h="$(hash_file "$proj/$BASE_REL")"
  run_writer "$proj" "-" pat001-set-created-at 1234567890abcdef1234567890abcdef12345678
  local cal_h2 base_h2; cal_h2="$(hash_file "$proj/$CAL_REL")"; base_h2="$(hash_file "$proj/$BASE_REL")"
  if [ "$cal_h" = "$cal_h2" ] && [ "$base_h" = "$base_h2" ]; then
    pass "INV-009-single-file" "pat001 op touches no other meta file (#226 guard)"
  else
    fail "INV-009-single-file" "pat001 op corrupted a sibling meta file (#226 regression)"
  fi
  rm -rf "$proj"
}
test_inv009_pat001_no_other_meta_touched

test_inv009_pat001_sha_accepts_40_and_64() {
  # Tests INV-009 [unit] / RS-012: SHA argv accepts 40- OR 64-hex.
  local sha p proj
  for sha in 1234567890abcdef1234567890abcdef12345678 \
             1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef; do
    proj="$(new_project)"
    seed_pat001 "$proj" '{"feature":"demo","created_at_commit":null}'
    run_writer "$proj" "-" pat001-set-created-at "$sha"
    local got; got="$(jq -r '.created_at_commit' "$proj/$PAT_REL" 2>/dev/null)"
    if [ "$RW_EXIT" -eq 0 ] && [ "$got" = "$sha" ]; then
      pass "INV-009-sha-${#sha}" "${#sha}-hex SHA accepted"
    else
      fail "INV-009-sha-${#sha}" "${#sha}-hex SHA should be accepted (exit=$RW_EXIT)"
    fi
    rm -rf "$proj"
  done
  # a NON-hex / wrong-length sha is rejected
  proj="$(new_project)"
  seed_pat001 "$proj" '{"feature":"demo","created_at_commit":null}'
  run_writer "$proj" "-" pat001-set-created-at "not-a-sha; rm -rf /"
  if [ "$RW_EXIT" -ne 0 ]; then
    pass "INV-009-sha-bad" "malformed/hostile SHA argv rejected (fail-loud)"
  else
    fail "INV-009-sha-bad" "malformed SHA must be rejected"
  fi
  rm -rf "$proj"
}
test_inv009_pat001_sha_accepts_40_and_64

# A1 (auditor): the baselines-write envelope is DOCUMENTED by /cmodelupgrade and
# asserted end-to-end in the B1 integration test (test_b1_skill_writer_e2e). The
# spec pins the OUTCOME — exactly one `baselines["<model>|<version>"]` set, all
# siblings + top-level schema_version preserved (INV-009/EXT-002) — but does NOT
# pin whether the arg form is `baselines-write "<model>|<version>"` or
# `baselines-write <model> <version>`. To avoid failing an equally-spec-compliant
# GREEN for surface arg-splitting, the writer-side OUTCOME tests assert the
# key-merge RESULT and route the invocation through THIS single wrapper. GREEN
# reconciles the arg form here, in ONE place, if it differs — no outcome test is
# rewritten. The writer's own schema_version constant is 1; an existing file whose
# schema_version != 1 is a mismatch -> fail-loud (INV-009/EXT-002/BND-001).
run_baselines_write() {
  # run_baselines_write <proj> <value_stdin_file|-> <model> <version>
  local proj="$1" sfile="$2" model="$3" version="$4"
  run_writer "$proj" "$sfile" baselines-write "${model}|${version}"
}

test_inv009_baselines_new_key_added() {
  # Tests INV-009 [unit] / EXT-002: baselines-write adds a new key, preserving
  # siblings + schema_version.
  local proj; proj="$(new_project)"
  printf '%s' '{"schema_version":1,"baselines":{"opus-4.7|4":{"escape":0.4}}}' > "$proj/$BASE_REL"
  local in; in="$(write_tmp '{"escape":0.2,"qa_rounds":1}')"
  run_baselines_write "$proj" "$in" "opus-4.8" "5"
  rm -f "$in"
  local has_new has_old sv
  has_new="$(jq -r '.baselines["opus-4.8|5"].escape // "MISSING"' "$proj/$BASE_REL" 2>/dev/null)"
  has_old="$(jq -r '.baselines["opus-4.7|4"].escape // "MISSING"' "$proj/$BASE_REL" 2>/dev/null)"
  sv="$(jq -r '.schema_version' "$proj/$BASE_REL" 2>/dev/null)"
  if [ "$RW_EXIT" -eq 0 ] && [ "$has_new" = "0.2" ] && [ "$has_old" = "0.4" ] && [ "$sv" = "1" ]; then
    pass "INV-009-base-add" "baselines-write adds new key; sibling + schema_version preserved"
  else
    fail "INV-009-base-add" "baselines new-key add must preserve siblings (exit=$RW_EXIT new=$has_new old=$has_old sv=$sv)"
  fi
  rm -rf "$proj"
}
test_inv009_baselines_new_key_added

test_inv009_baselines_existing_key_replaced() {
  # Tests INV-009 [unit] / PRH-001: replacing an existing key preserves ALL
  # other keys and schema_version; only the targeted key changes.
  local proj; proj="$(new_project)"
  printf '%s' '{"schema_version":1,"baselines":{"a|1":{"x":1},"opus-4.8|5":{"old":true}}}' > "$proj/$BASE_REL"
  local sibling_before; sibling_before="$(jq -S '.baselines["a|1"]' "$proj/$BASE_REL")"
  local in; in="$(write_tmp '{"new":true,"escape":0.1}')"
  run_baselines_write "$proj" "$in" "opus-4.8" "5"
  rm -f "$in"
  local sibling_after target sv
  sibling_after="$(jq -S '.baselines["a|1"]' "$proj/$BASE_REL" 2>/dev/null)"
  target="$(jq -r '.baselines["opus-4.8|5"].new // "MISSING"' "$proj/$BASE_REL" 2>/dev/null)"
  sv="$(jq -r '.schema_version' "$proj/$BASE_REL" 2>/dev/null)"
  if [ "$RW_EXIT" -eq 0 ] && [ "$sibling_before" = "$sibling_after" ] && [ "$target" = "true" ] && [ "$sv" = "1" ]; then
    pass "INV-009-base-replace" "existing key replaced; all siblings + schema_version preserved"
  else
    fail "INV-009-base-replace" "key replace must preserve siblings+schema_version (exit=$RW_EXIT target=$target sv=$sv)"
  fi
  rm -rf "$proj"
}
test_inv009_baselines_existing_key_replaced

test_inv009_baselines_schema_mismatch_fails() {
  # Tests INV-009 [unit] / EXT-002: schema_version mismatch -> fail-loud, real
  # data preserved (never clobbered).
  local proj; proj="$(new_project)"
  printf '%s' '{"schema_version":2,"baselines":{"a|1":{"x":1}}}' > "$proj/$BASE_REL"
  local before; before="$(hash_file "$proj/$BASE_REL")"
  local in; in="$(write_tmp '{"escape":0.2}')"
  run_baselines_write "$proj" "$in" "opus-4.8" "5"
  rm -f "$in"
  local after; after="$(hash_file "$proj/$BASE_REL")"
  if [ "$RW_EXIT" -ne 0 ] && echo "$RW_STDOUT" | grep -qF "meta-record: FAILED $BASE_REL:" && [ "$before" = "$after" ]; then
    pass "INV-009-base-mismatch" "schema_version mismatch fails loud; data preserved"
  else
    fail "INV-009-base-mismatch" "schema mismatch must fail-loud + preserve data (exit=$RW_EXIT)"
  fi
  rm -rf "$proj"
}
test_inv009_baselines_schema_mismatch_fails

test_inv009_baselines_absent_creates() {
  # Tests INV-009 [unit] / BND-001: absent baselines file -> create
  # {"schema_version":1,"baselines":{}} then key-merge.
  local proj; proj="$(new_project)"
  rm -f "$proj/$BASE_REL"
  local in; in="$(write_tmp '{"escape":0.3}')"
  run_baselines_write "$proj" "$in" "opus-4.8" "5"
  rm -f "$in"
  local sv val
  sv="$(jq -r '.schema_version' "$proj/$BASE_REL" 2>/dev/null)"
  val="$(jq -r '.baselines["opus-4.8|5"].escape // "MISSING"' "$proj/$BASE_REL" 2>/dev/null)"
  if [ "$RW_EXIT" -eq 0 ] && [ "$sv" = "1" ] && [ "$val" = "0.3" ]; then
    pass "INV-009-base-create" "absent baselines file created with schema_version 1 + first key"
  else
    fail "INV-009-base-create" "absent baselines should be created+merged (exit=$RW_EXIT sv=$sv val=$val)"
  fi
  rm -rf "$proj"
}
test_inv009_baselines_absent_creates

# ===========================================================================
# INV-010 — bounded input, symlink-refusing destination, fail-closed realpath
# ===========================================================================
section "INV-010: bounded input + symlink refusal + fail-closed realpath"

test_inv010_oversize_stdin_rejected() {
  # Tests INV-010 [unit]: stdin above the 64 KB ceiling is rejected BEFORE
  # parsing (byte-counted with wc -c, not ${#var}).
  local proj; proj="$(new_project)"
  printf '%s' '{"calibration_entries":[]}' > "$proj/$CAL_REL"
  local before; before="$(hash_file "$proj/$CAL_REL")"
  # Build a >64KB but otherwise valid-looking entry (huge file_paths_touched).
  local big; big="$(mktemp)"
  {
    printf '{"feature_slug":"big","recommended_intensity":"high","actual_intensity":"high","actual_qa_rounds":1,"actual_findings_count":0,"actual_spec_updates":0,"actual_tokens":0,"timestamp":"2026-07-04T00:00:00Z","file_paths_touched":["'
    head -c 70000 /dev/zero | tr '\0' 'a'
    printf '"]}'
  } > "$big"
  run_writer "$proj" "$big" calibration-append
  rm -f "$big"
  local after; after="$(hash_file "$proj/$CAL_REL")"
  if [ "$RW_EXIT" -ne 0 ] && [ "$before" = "$after" ]; then
    pass "INV-010-oversize" "stdin > 64KB rejected, file unchanged"
  else
    fail "INV-010-oversize" "oversize stdin must be rejected before parse (exit=$RW_EXIT)"
  fi
  rm -rf "$proj"
}
test_inv010_oversize_stdin_rejected

test_inv010_payload_not_on_argv_source() {
  # Tests INV-010 [unit] / AP-039: the stdin payload must NOT transit argv.
  # Source-level guard: the writer must not pass a captured file/stdin var to
  # jq via --arg/--argjson, and must not use $(cat ...) capture (NUL-trunc).
  if grep -nE -- '--argjson[[:space:]]+[a-zA-Z_][a-zA-Z0-9_]*[[:space:]]+"\$' "$WRITER" >/dev/null 2>&1 \
     || grep -nE -- '--arg[[:space:]]+[a-zA-Z_][a-zA-Z0-9_]*[[:space:]]+"\$\(cat' "$WRITER" >/dev/null 2>&1; then
    fail "INV-010-argv" "writer passes stdin payload on argv via jq --arg/--argjson (ARG_MAX/AP-039)"
  else
    pass "INV-010-argv" "writer does not route the payload through argv (jq --arg/--argjson)"
  fi
  if grep -nE -- '\$\(cat[[:space:]]' "$WRITER" >/dev/null 2>&1; then
    fail "INV-010-catcapture" "writer uses \$(cat ...) capture (NUL-truncation risk) — use a temp file/stdin"
  else
    pass "INV-010-catcapture" "writer avoids \$(cat) capture of the payload"
  fi
}
test_inv010_payload_not_on_argv_source

test_inv010_nul_byte_no_silent_truncation() {
  # Tests INV-010 [unit]: a NUL byte mid-stdin must NOT be silently truncated
  # into a "valid" prefix and reported as success.
  local proj; proj="$(new_project)"
  printf '%s' '{"calibration_entries":[]}' > "$proj/$CAL_REL"
  local before; before="$(hash_file "$proj/$CAL_REL")"
  local nul; nul="$(mktemp)"
  # valid JSON object bytes, then a NUL, then trailing garbage.
  printf '{"feature_slug":"x"' > "$nul"
  printf '\000' >> "$nul"
  printf ',"garbage":true}' >> "$nul"
  run_writer "$proj" "$nul" calibration-append
  rm -f "$nul"
  local after; after="$(hash_file "$proj/$CAL_REL")"
  # Must NOT be a silent success that wrote a truncated entry.
  if [ "$RW_EXIT" -ne 0 ] && [ "$before" = "$after" ]; then
    pass "INV-010-nul" "NUL-byte stdin not silently truncated into a success"
  else
    fail "INV-010-nul" "NUL-byte stdin must fail-loud, not truncate (exit=$RW_EXIT)"
  fi
  rm -rf "$proj"
}
test_inv010_nul_byte_no_silent_truncation

test_inv010_symlinked_destination_refused() {
  # Tests INV-010 [unit]: a symlinked destination file (pointing outside
  # .correctless/meta/) is refused; the outside target is not written.
  local proj; proj="$(new_project)"
  local outside; outside="$(mktemp)"
  printf '%s' 'ORIGINAL' > "$outside"
  ln -s "$outside" "$proj/$CAL_REL"
  local in; in="$(write_tmp "$(typed_entry)")"
  run_writer "$proj" "$in" calibration-append
  rm -f "$in"
  local outside_content; outside_content="$(cat "$outside")"
  if [ "$RW_EXIT" -ne 0 ] && [ "$outside_content" = "ORIGINAL" ]; then
    pass "INV-010-symlink-dest" "symlinked destination refused; outside target untouched"
  else
    fail "INV-010-symlink-dest" "symlinked dest must be refused (exit=$RW_EXIT outside=$outside_content)"
  fi
  rm -f "$outside"; rm -rf "$proj"
}
test_inv010_symlinked_destination_refused

test_inv010_symlinked_parent_refused() {
  # Tests INV-010 [unit] / EXT-005: a symlinked PARENT dir (.correctless/meta ->
  # elsewhere) is refused BEFORE any mkdir/temp creation.
  local proj; proj="$(mktemp -d "${TMPDIR:-/tmp}/mr-proj-XXXXXX")"
  mkdir -p "$proj/.correctless"
  local outside_dir; outside_dir="$(mktemp -d)"
  ln -s "$outside_dir" "$proj/.correctless/meta"
  printf '%s' '{"calibration_entries":[]}' > "$outside_dir/intensity-calibration.json"
  local before; before="$(hash_file "$outside_dir/intensity-calibration.json")"
  local in; in="$(write_tmp "$(typed_entry)")"
  run_writer "$proj" "$in" calibration-append
  rm -f "$in"
  local after; after="$(hash_file "$outside_dir/intensity-calibration.json")"
  if [ "$RW_EXIT" -ne 0 ] && [ "$before" = "$after" ]; then
    pass "INV-010-symlink-parent" "symlinked parent dir refused; nothing written through it"
  else
    fail "INV-010-symlink-parent" "symlinked parent must be refused (exit=$RW_EXIT)"
  fi
  rm -rf "$outside_dir" "$proj"
}
test_inv010_symlinked_parent_refused

test_inv010_realpath_tool_absent_fails_loud() {
  # Tests INV-010 [unit] / EA-004: with neither realpath nor readlink -f
  # available, the writer fails loud (never a lexical canonicalize_path fallback
  # for the symlink verdict).
  #
  # A4 (auditor): build the shim by symlinking EVERY executable on the current
  # PATH EXCEPT realpath/readlink — so every other coreutil (mktemp, date, cmp,
  # ...) is present and the ONLY missing capability is realpath/readlink. Then
  # assert not merely a generic FAILED token but that the FAILED <reason> NAMES
  # realpath|readlink — proving the failure is the tool-absent branch and not a
  # collateral missing binary.
  local shim; shim="$(mktemp -d)"
  local d exe name
  local -a dirs
  IFS=: read -ra dirs <<< "$PATH"
  for d in "${dirs[@]}"; do
    [ -d "$d" ] || continue
    for exe in "$d"/*; do
      [ -e "$exe" ] || continue
      name="$(basename "$exe")"
      case "$name" in realpath|readlink) continue ;; esac
      [ -e "$shim/$name" ] || ln -s "$exe" "$shim/$name" 2>/dev/null || true
    done
  done
  # sanity: realpath/readlink genuinely absent from the shim, jq present
  if [ -e "$shim/realpath" ] || [ -e "$shim/readlink" ] || [ ! -e "$shim/jq" ]; then
    fail "INV-010-realpath-absent" "shim setup invalid (realpath/readlink leaked or jq missing)"
    rm -rf "$shim"; return
  fi

  local proj; proj="$(new_project)"
  printf '%s' '{"calibration_entries":[]}' > "$proj/$CAL_REL"
  local in; in="$(write_tmp "$(typed_entry)")"
  local errf; errf="$(mktemp)"
  # Combined output (stdout+stderr) so the reason is visible regardless of stream.
  local out; out="$(cd "$proj" && PATH="$shim" bash "$WRITER" calibration-append <"$in" 2>"$errf"; )"
  local rc=$?
  out="$out"$'\n'"$(cat "$errf" 2>/dev/null)"
  rm -f "$in" "$errf"
  if [ "$rc" -ne 0 ] \
     && echo "$out" | grep -qF "meta-record: FAILED" \
     && echo "$out" | grep -qiE 'realpath|readlink'; then
    pass "INV-010-realpath-absent" "realpath+readlink absent -> fail-loud; reason names realpath/readlink (A4)"
  else
    fail "INV-010-realpath-absent" "missing realpath/readlink must fail-loud with a reason naming the tool (rc=$rc)"
  fi
  rm -rf "$shim" "$proj"
}
test_inv010_realpath_tool_absent_fails_loud

# ===========================================================================
# PRH-005 — destination never derived from input; unknown op fails loud
# ===========================================================================
section "PRH-005: hardcoded destinations; unknown op fails loud"

test_prh005_unknown_op_fails_loud() {
  # Tests PRH-005 [unit] / DD-005: an unknown operation fails loud with NO
  # default write path.
  local proj; proj="$(new_project)"
  local in; in="$(write_tmp '{"anything":1}')"
  run_writer "$proj" "$in" totally-bogus-op
  rm -f "$in"
  # no meta file should have been created
  local created=0
  [ -e "$proj/$CAL_REL" ] && created=1
  [ -e "$proj/$PAT_REL" ] && created=1
  [ -e "$proj/$BASE_REL" ] && created=1
  if [ "$RW_EXIT" -ne 0 ] && [ "$created" -eq 0 ]; then
    pass "PRH-005-unknown-op" "unknown op fails loud, writes nothing"
  else
    fail "PRH-005-unknown-op" "unknown op must fail-loud with no default write (exit=$RW_EXIT created=$created)"
  fi
  rm -rf "$proj"
}
test_prh005_unknown_op_fails_loud

test_prh005_destination_not_from_input_source() {
  # Tests PRH-005 [unit]: source review — the per-op destination is a hardcoded
  # constant, never taken from stdin/argv. Assert each hardcoded meta path
  # literal is present in the writer, and no destination var is assigned from a
  # positional/stdin variable.
  local ok=1
  grep -qF 'intensity-calibration.json' "$WRITER" || ok=0
  grep -qF 'pat001-measurement-due.json' "$WRITER" || ok=0
  grep -qF 'model-baselines.json' "$WRITER" || ok=0
  if [ "$ok" -eq 1 ]; then
    pass "PRH-005-hardcoded" "writer hardcodes all three per-op destination literals"
  else
    fail "PRH-005-hardcoded" "writer must hardcode the three per-op destinations"
  fi
  # dest must not be assigned directly from $1/$2/stdin
  if grep -nE '(dest|DEST|target|TARGET)=("?\$[0-9]|"?\$\{?[0-9])' "$WRITER" >/dev/null 2>&1; then
    fail "PRH-005-noinput" "destination appears assigned from a positional argument"
  else
    pass "PRH-005-noinput" "destination not assigned from a positional/stdin variable"
  fi
}
test_prh005_destination_not_from_input_source

# ===========================================================================
# PRH-006 — reuse ABS-003 lock helpers; no bespoke locking; no locked_update_file
# ===========================================================================
section "PRH-006: reuse lock helpers; no bespoke lock; no locked_update_file"

test_prh006_reuses_lock_helpers() {
  # Tests PRH-006 [unit] / EXT-001: writer sources lib.sh and references
  # _acquire_state_lock; it must NOT invent a bespoke .lock, rm -rf a lock dir,
  # or call locked_update_file (deadlock).
  if grep -qF 'lib.sh' "$WRITER"; then
    pass "PRH-006-source" "writer sources lib.sh"
  else
    fail "PRH-006-source" "writer must source lib.sh (canonical lock helpers, PAT-006)"
  fi
  if grep -qF '_acquire_state_lock' "$WRITER"; then
    pass "PRH-006-acquire" "writer references _acquire_state_lock (reuses ABS-003 helper)"
  else
    fail "PRH-006-acquire" "writer must call _acquire_state_lock"
  fi
  if grep -qE '\.lock' "$WRITER"; then
    fail "PRH-006-nolock" "writer references a bespoke .lock path (helpers own the lock dir)"
  else
    pass "PRH-006-nolock" "writer does not hand-roll a .lock path"
  fi
  if grep -qE 'rm[[:space:]]+-rf' "$WRITER"; then
    fail "PRH-006-normrf" "writer uses rm -rf (never delete a lock dir directly)"
  else
    pass "PRH-006-normrf" "writer does not rm -rf a lock dir"
  fi
  if grep -qF 'locked_update_file' "$WRITER"; then
    fail "PRH-006-nowrap" "writer calls locked_update_file (two-state, cannot express tri-state; deadlock risk)"
  else
    pass "PRH-006-nowrap" "writer does not wrap locked_update_file (hand-rolls tri-state, EXT-001)"
  fi
}
test_prh006_reuses_lock_helpers

# ===========================================================================
# INV-004 / PRH-002 — skills rewired onto the Bash writer path (RED: not yet)
# ===========================================================================
section "INV-004 / PRH-002: skills invoke the Bash writer, echo FAILED token"

CVERIFY_SKILL="$REPO_DIR/skills/cverify/SKILL.md"
CDOCS_SKILL="$REPO_DIR/skills/cdocs/SKILL.md"
CMODELUPGRADE_SKILL="$REPO_DIR/skills/cmodelupgrade/SKILL.md"

check_skill_rewire() {
  # $1=id-prefix $2=skill-file $3=operation-token $4=removed-write-path
  local id="$1" file="$2" op="$3" removed="$4"
  local body; body="$(skill_body "$file")"
  local allowed; allowed="$(grep -m1 '^allowed-tools:' "$file" 2>/dev/null)"

  # invokes bash .correctless/scripts/meta-record.sh <op>
  if echo "$body" | grep -qE "bash[[:space:]]+\.correctless/scripts/meta-record\.sh[[:space:]]+$op"; then
    pass "$id-invoke" "invokes 'bash .correctless/scripts/meta-record.sh $op'"
  else
    fail "$id-invoke" "must invoke 'bash .correctless/scripts/meta-record.sh $op' (Bash path)"
  fi

  # NEVER interpolate input into bash -c
  if echo "$body" | grep -qE "bash[[:space:]]+-c[^\\n]*meta-record"; then
    fail "$id-nobashc" "must NOT wrap meta-record in 'bash -c' (TB-001 interpolation)"
  else
    pass "$id-nobashc" "does not interpolate input into 'bash -c'"
  fi

  # echoes the FAILED token verbatim (RS-005 — proves fail-loud is surfaced)
  if echo "$body" | grep -qF 'meta-record: FAILED'; then
    pass "$id-token" "echoes 'meta-record: FAILED' token on writer failure"
  else
    fail "$id-token" "must echo the 'meta-record: FAILED' token (RS-005)"
  fi

  # allowed-tools: has Bash(*meta-record.sh*), dropped the direct Write grant
  if echo "$allowed" | grep -qF 'meta-record.sh'; then
    pass "$id-grant-add" "allowed-tools grants Bash(*meta-record.sh*)"
  else
    fail "$id-grant-add" "allowed-tools must grant Bash(*meta-record.sh*)"
  fi
  if echo "$allowed" | grep -qF "Write($removed"; then
    fail "$id-grant-drop" "allowed-tools must DROP Write($removed...) (PRH-002)"
  else
    pass "$id-grant-drop" "allowed-tools no longer grants Write($removed...)"
  fi

  # PRH-002: no Write(/Edit fallback targeting the meta file in the body
  if echo "$body" | grep -qE "(Write|Edit)\([^)]*$(basename "$removed")"; then
    fail "$id-nofallback" "body still references Write/Edit on $(basename "$removed") (PRH-002)"
  else
    pass "$id-nofallback" "no Write/Edit fallback on the protected meta file"
  fi
}

check_skill_rewire "INV-004-cverify" "$CVERIFY_SKILL" "calibration-append" ".correctless/meta/intensity-calibration.json"
check_skill_rewire "INV-004-cdocs"   "$CDOCS_SKILL"   "pat001-set-created-at" ".correctless/meta/pat001-measurement-due.json"
check_skill_rewire "INV-004-cmu"     "$CMODELUPGRADE_SKILL" "baselines-write" ".correctless/meta/model-baselines.json"

test_inv004_cdocs_no_blanket_scan() {
  # Tests INV-004 [integration] / EXT-004: /cdocs no longer blanket-scans all
  # .correctless/meta/*.json; it invokes pat001 only for the present-null field.
  local body; body="$(skill_body "$CDOCS_SKILL")"
  if echo "$body" | grep -qE 'meta/\*\.json|for .* in .*meta.*json|blanket'; then
    fail "INV-004-cdocs-blanket" "/cdocs still blanket-scans .correctless/meta/*.json (EXT-004/#226)"
  else
    pass "INV-004-cdocs-blanket" "/cdocs no longer blanket-scans meta json files"
  fi
  # references present-null / has(...)==null guard intent
  if echo "$body" | grep -qiE 'present.*null|== *null|has\("created_at_commit"\)'; then
    pass "INV-004-cdocs-guard" "/cdocs documents the present-null-only invocation guard"
  else
    fail "INV-004-cdocs-guard" "/cdocs must document present-null-only invocation (EXT-004)"
  fi
}
test_inv004_cdocs_no_blanket_scan

test_inv004_script_absent_127_remediation() {
  # Tests INV-004 [integration] / RS-014: skills surface a script-absent (127)
  # remediation ("run /csetup to install meta-record.sh") rather than silently
  # discarding a non-zero writer exit.
  local sk id
  for sk in "$CVERIFY_SKILL:INV-004-cverify" "$CDOCS_SKILL:INV-004-cdocs" "$CMODELUPGRADE_SKILL:INV-004-cmu"; do
    id="${sk#*:}"
    local body; body="$(skill_body "${sk%%:*}")"
    if echo "$body" | grep -qiE '127|csetup.*meta-record|install.*meta-record'; then
      pass "$id-127" "surfaces script-absent (127) remediation (run /csetup)"
    else
      fail "$id-127" "must surface script-absent (127) remediation (RS-014)"
    fi
  done
}
test_inv004_script_absent_127_remediation

# ===========================================================================
# B1 (auditor, BLOCKING) — cross-executed skill→writer integration.
#   The check_skill_rewire greps above are prose-only: a skill documenting a
#   MISMATCHED envelope (entry as argv when the writer reads stdin, baselines
#   key/value swapped) would pass every literal grep while the production path
#   is dead. This test, for each op:
#     (1) reconstructs the CANONICAL documented envelope per the spec AND greps
#         the SKILL.md to confirm it documents that SAME channel (stdin vs argv),
#     (2) runs that exact invocation against the REAL meta-record.sh with a
#         failure injected, and asserts the writer's ACTUAL `meta-record: FAILED
#         <file>: <reason>` token appears in the CAPTURED COMBINED output — end
#         to end, not two independent literal greps (INV-003 / RS-005).
#   In RED this MUST fail (stub writer emits nothing; skills not yet rewired).
# ===========================================================================
section "B1: cross-executed skill->writer integration (documented envelope + real token)"

# Run the REAL writer via a specific channel, returning combined stdout+stderr
# in RUN_OUT and exit in RUN_RC. channel = "stdin" | "argv".
run_writer_combined() {
  local proj="$1" channel="$2" stdin_file="$3"; shift 3
  local errf; errf="$(mktemp)"
  if [ "$channel" = "stdin" ]; then
    RUN_OUT="$(cd "$proj" && bash "$WRITER" "$@" <"$stdin_file" 2>"$errf")"; RUN_RC=$?
  else
    RUN_OUT="$(cd "$proj" && bash "$WRITER" "$@" </dev/null 2>"$errf")"; RUN_RC=$?
  fi
  RUN_OUT="$RUN_OUT"$'\n'"$(cat "$errf" 2>/dev/null)"
  rm -f "$errf"
}

test_b1_calibration_e2e() {
  # calibration: entry JSON on STDIN. Confirm /cverify documents a stdin channel
  # (piped into meta-record.sh calibration-append), then execute against the
  # real writer with a corrupt target (failure injection) and assert the token.
  local body; body="$(skill_body "$CVERIFY_SKILL")"
  # documented-channel grep: a pipe feeds calibration-append (stdin), and the
  # entry is NOT passed as a positional JSON/quoted argv token.
  if echo "$body" | grep -qE '\|[^|]*meta-record\.sh calibration-append' \
     && ! echo "$body" | grep -qE "meta-record\.sh calibration-append[[:space:]]+['\"\$]?\{"; then
    pass "B1-cverify-channel" "/cverify documents entry on STDIN (piped) to calibration-append"
  else
    fail "B1-cverify-channel" "/cverify must feed the entry via STDIN (pipe), not argv"
  fi
  # execute canonical envelope against real writer, failure injected (corrupt file)
  local proj; proj="$(new_project)"
  printf '%s' '{ corrupt json' > "$proj/$CAL_REL"
  local in; in="$(write_tmp "$(typed_entry)")"
  run_writer_combined "$proj" "stdin" "$in" calibration-append
  rm -f "$in"
  if [ "$RUN_RC" -ne 0 ] && echo "$RUN_OUT" | grep -qE "meta-record: FAILED $CAL_REL: .+"; then
    pass "B1-cverify-token" "real writer emits FAILED token through the documented stdin channel"
  else
    fail "B1-cverify-token" "cross-executed calibration path must emit the FAILED token (rc=$RUN_RC)"
  fi
  rm -rf "$proj"
}
test_b1_calibration_e2e

test_b1_pat001_e2e() {
  # pat001: <sha> as DISCRETE ARGV. Confirm /cdocs documents the sha as an argv
  # token (not stdin), then execute against a corrupt target and assert the token.
  local body; body="$(skill_body "$CDOCS_SKILL")"
  if echo "$body" | grep -qE 'meta-record\.sh pat001-set-created-at[[:space:]]+["'"'"'\$a-f0-9]'; then
    pass "B1-cdocs-channel" "/cdocs documents <sha> as a discrete argv token to pat001-set-created-at"
  else
    fail "B1-cdocs-channel" "/cdocs must pass <sha> as discrete argv to pat001-set-created-at"
  fi
  local proj; proj="$(new_project)"
  printf '%s' '{ corrupt json' > "$proj/$PAT_REL"
  run_writer_combined "$proj" "argv" "-" pat001-set-created-at 1234567890abcdef1234567890abcdef12345678
  if [ "$RUN_RC" -ne 0 ] && echo "$RUN_OUT" | grep -qE "meta-record: FAILED $PAT_REL: .+"; then
    pass "B1-cdocs-token" "real writer emits FAILED token through the documented argv channel"
  else
    fail "B1-cdocs-token" "cross-executed pat001 path must emit the FAILED token (rc=$RUN_RC)"
  fi
  rm -rf "$proj"
}
test_b1_pat001_e2e

test_b1_baselines_e2e() {
  # baselines: key `<model>|<version>` as argv + value object on STDIN. Confirm
  # /cmodelupgrade documents a stdin channel for the value, then execute against
  # a schema_version-mismatch target (failure injection) and assert the token.
  # (A1: the exact arg form is centralized in run_baselines_write; here we assert
  # the documented channel + the real token, not a surface arg count.)
  local body; body="$(skill_body "$CMODELUPGRADE_SKILL")"
  if echo "$body" | grep -qE '\|[^|]*meta-record\.sh baselines-write'; then
    pass "B1-cmu-channel" "/cmodelupgrade documents the baseline value on STDIN (piped) to baselines-write"
  else
    fail "B1-cmu-channel" "/cmodelupgrade must feed the baseline value via STDIN (pipe) to baselines-write"
  fi
  local proj; proj="$(new_project)"
  printf '%s' '{"schema_version":2,"baselines":{"a|1":{"x":1}}}' > "$proj/$BASE_REL"
  local in; in="$(write_tmp '{"escape":0.2}')"
  # route via the same centralized wrapper the outcome tests use, but capture
  # combined output through run_writer_combined by expanding the envelope here.
  run_writer_combined "$proj" "stdin" "$in" baselines-write "opus-4.8|5"
  rm -f "$in"
  if [ "$RUN_RC" -ne 0 ] && echo "$RUN_OUT" | grep -qE "meta-record: FAILED $BASE_REL: .+"; then
    pass "B1-cmu-token" "real writer emits FAILED token through the documented baselines channel"
  else
    fail "B1-cmu-token" "cross-executed baselines path must emit the FAILED token (rc=$RUN_RC)"
  fi
  rm -rf "$proj"
}
test_b1_baselines_e2e

# ===========================================================================
# QA-003 — calibration-append pins to EXACTLY ONE JSON document (multi-doc reject)
# ===========================================================================
section "QA-003: calibration-append rejects multi-document stdin (exactly-one-doc)"

test_qa003_multidoc_stdin_rejected() {
  # Two concatenated JSON objects on stdin. With the pre-fix per-value `jq -e`
  # validation + `--slurpfile` append, BOTH objects would validate and BOTH would
  # be appended (a silent multi-append). The writer must require EXACTLY ONE
  # document: reject with non-zero + the mechanical FAILED token and add ZERO
  # entries (file byte-unchanged).
  local proj; proj="$(new_project)"
  printf '%s' '{"calibration_entries":[]}' > "$proj/$CAL_REL"
  local before; before="$(hash_file "$proj/$CAL_REL")"
  # Two individually schema-conformant entries concatenated. jq treats
  # whitespace-separated top-level values as a stream (no separator needed).
  local e1 e2 two
  e1="$(typed_entry | jq -c --arg s "doc-one" '.feature_slug=$s')"
  e2="$(typed_entry | jq -c --arg s "doc-two" '.feature_slug=$s')"
  two="$(printf '%s\n%s\n' "$e1" "$e2")"
  local in; in="$(write_tmp "$two")"
  run_writer "$proj" "$in" calibration-append
  rm -f "$in"
  local after; after="$(hash_file "$proj/$CAL_REL")"
  local n; n="$(jq '.calibration_entries|length' "$proj/$CAL_REL" 2>/dev/null || echo -1)"

  if [ "$RW_EXIT" -ne 0 ]; then
    pass "QA-003-exit" "multi-document stdin rejected (non-zero exit)"
  else
    fail "QA-003-exit" "two concatenated objects must be rejected (got exit 0 — both would append)"
  fi
  if echo "$RW_STDOUT" | grep -qE "^meta-record: FAILED $CAL_REL: .+"; then
    pass "QA-003-token" "multi-doc rejection prints the mechanical FAILED token"
  else
    fail "QA-003-token" "multi-doc rejection must print 'meta-record: FAILED $CAL_REL: <reason>'"
  fi
  if [ "$before" = "$after" ] && [ "$n" = "0" ]; then
    pass "QA-003-unchanged" "multi-doc stdin adds ZERO entries; file byte-unchanged"
  else
    fail "QA-003-unchanged" "multi-doc stdin must leave the file unchanged (n=$n changed=$([ "$before" != "$after" ] && echo yes || echo no))"
  fi
  rm -rf "$proj"
}
test_qa003_multidoc_stdin_rejected

# ===========================================================================
# Summary
# ===========================================================================
summary "test-meta-record.sh"
