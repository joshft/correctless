#!/usr/bin/env bash
# Correctless — SFG re-scope (sensitive-file-guard write-target-only guardrail)
# Tests spec: .correctless/specs/sfg-rescope.md  (INV-001..020, PRH-001..003)
#
# RED-PHASE TESTS. These MUST FAIL against the CURRENT over-extracting hook and
# perimeter-framed docs. They go GREEN once _extract_bash_targets is rewritten
# destination-driven and the doc sweep lands.
#
# Test approach (spec L54, applies to EVERY behavioral INV): hook-integration
# ONLY. Drive the full hook via a stdin JSON envelope through run_hook_capture
# and assert the PROCESS EXIT CODE (0=allow, 2=block). Function-level calls to
# _extract_bash_targets are FORBIDDEN — they bypass the _has_write_pattern
# pre-filter (hook L87) and prove nothing about the deployed gate (RS-006).
#
# Run from repo root: bash tests/test-sfg-rescope.sh

source "$(dirname "${BASH_SOURCE[0]}")/test-helpers.sh"

HOOK="$REPO_DIR/hooks/sensitive-file-guard.sh"
LIB_PATH="scripts/lib.sh"  # referenced indirectly to avoid SFG self-block in literals

# ---------------------------------------------------------------------------
# Harness (mirrors tests/test-sensitive-file-guard.sh)
# ---------------------------------------------------------------------------

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "  ${GREEN}PASS${RESET}: $desc"
    PASS=$((PASS + 1))
  else
    echo "  ${RED}FAIL${RESET}: $desc (expected '$expected', got '$actual')"
    FAIL=$((FAIL + 1))
    FAILED_IDS="${FAILED_IDS}${desc} "
  fi
}

run_hook_capture() {
  local json_input="$1" exit_code stderr_output
  stderr_output="$(echo "$json_input" | bash "$HOOK" 2>&1 >/dev/null)" && exit_code=0 || exit_code=$?
  echo "${exit_code}:${stderr_output}"
}
extract_exit() { echo "$1" | head -1 | cut -d: -f1; }
extract_stderr() { echo "$1" | cut -d: -f2-; }

setup_test_env() {
  local test_dir="$1"
  rm -rf "$test_dir"
  mkdir -p "$test_dir/.correctless/config"
}

# Drive one Bash command through the hook and assert the exit code.
# Uses jq -nc so embedded quotes/backslashes are JSON-escaped safely.
assert_bash() {
  local desc="$1" expect="$2" cmd="$3" json result
  json="$(jq -nc --arg c "$cmd" '{tool_name:"Bash",tool_input:{command:$c}}')"
  result="$(run_hook_capture "$json")"
  assert_eq "$desc" "$expect" "$(extract_exit "$result")"
}

# ===========================================================================
# INV-001: Reads, invocations, and incidental tokens are never write targets
# ===========================================================================
test_inv001_reads_invocations_not_targets() {
  echo ""
  echo "=== INV-001: reads/invocations/incidental tokens never blocked ==="

  local test_dir="/tmp/correctless-rescope-inv001-$$"
  setup_test_env "$test_dir"; cd "$test_dir" || return

  # LOAD-BEARING (genuinely RED) fixture: `bash <protected-script> ARG 2>/dev/null`
  # REACHES extraction because the `2>/dev/null` redirect FIRES _has_write_pattern
  # (so the L87 fast-bail does NOT trigger). `/dev/null` is a sink (INV-006, not
  # emitted); `harness-fingerprint.sh` is in DEFAULTS (L243) but is an INVOCATION
  # arg the NEW destination-driven extractor MUST NOT emit -> exit 0.
  # Verified RED: the CURRENT over-extractor emits `harness-fingerprint.sh`
  # (token-driven) -> BLOCKED (rc=2). It must flip to ALLOWED after the rewrite.
  assert_bash "INV-001: bash hf.sh check 2>/dev/null (reaches extraction, invocation) ALLOWED" "0" \
    "bash scripts/harness-fingerprint.sh check 2>/dev/null"

  # `eval cat .env` ALSO reaches extraction (eval fires the prefilter) yet its
  # operand is opaque (INV-005) — the protected `.env` token inside must not be
  # emitted. Verified RED: current over-extractor emits `.env` -> BLOCKED.
  assert_bash "INV-001: eval cat .env reaching extraction emits empty -> ALLOWED" "0" \
    "eval cat .env"

  # `bash <script>` WITHOUT a redirect does NOT reach extraction — bare
  # interpreter use does NOT fire _has_write_pattern (no eval-flag, no redirect),
  # so the hook exits 0 at L87 BEFORE the extractor runs. These pass against the
  # CURRENT hook too (NOT genuinely RED) — kept as defense-in-depth, not as proof
  # of the rewrite. The proof is the two reaching-extraction fixtures above.
  assert_bash "INV-001: bash .correctless/scripts/lib.sh (invocation, no-reach) ALLOWED" "0" \
    "bash .correctless/scripts/lib.sh"
  assert_bash "INV-001: bash scripts/harness-fingerprint.sh check (no-reach) ALLOWED" "0" \
    "bash scripts/harness-fingerprint.sh check"

  # Reads / presence checks / sources — gated OUT by _has_write_pattern, but
  # assert anyway (defense-in-depth, and several reach extraction via writers).
  assert_bash "INV-001: jq read of workflow-config.json ALLOWED" "0" \
    "jq '.' .correctless/config/workflow-config.json"
  assert_bash "INV-001: ls scripts/lib.sh ALLOWED" "0" "ls scripts/lib.sh"
  assert_bash "INV-001: cat .env (read) ALLOWED" "0" "cat .env"
  assert_bash "INV-001: source scripts/lib.sh ALLOWED" "0" "source scripts/lib.sh"

  rm -rf "$test_dir"
}

# ===========================================================================
# INV-002: Redirect destinations ARE write targets (except sink devices)
# whitespace-separated AND glued forms are distinct code paths.
# ===========================================================================
test_inv002_redirect_destinations_block() {
  echo ""
  echo "=== INV-002: every redirect destination blocks (whitespace + glued) ==="

  local test_dir="/tmp/correctless-rescope-inv002-$$"
  setup_test_env "$test_dir"; cd "$test_dir" || return

  # Whitespace-separated operators
  assert_bash "INV-002: > .env"        "2" "echo x > .env"
  assert_bash "INV-002: >> .env"       "2" "echo x >> .env"
  assert_bash "INV-002: >| .env"       "2" "echo x >| .env"
  assert_bash "INV-002: 1> .env"       "2" "echo x 1> .env"
  assert_bash "INV-002: 2>> creds"     "2" "make 2>> credentials.json"
  assert_bash "INV-002: &> .env"       "2" "echo x &> .env"
  assert_bash "INV-002: &>| .env"      "2" "echo x &>| .env"
  assert_bash "INV-002: >& .env"       "2" "echo x >& .env"

  # Glued (inline-attached) forms — IFS does not split > from adjacent token,
  # so these are a SEPARATE code path that MUST be covered.
  assert_bash "INV-002 glued: echo x>.env"            "2" "echo x>.env"
  assert_bash "INV-002 glued: make 2>.correctless/meta/harness-fingerprint.json" "2" \
    "make 2>.correctless/meta/harness-fingerprint.json"
  assert_bash "INV-002 glued: echo x&>.env"           "2" "echo x&>.env"
  assert_bash "INV-002 glued: echo x>>.env"           "2" "echo x>>.env"

  rm -rf "$test_dir"
}

# ===========================================================================
# INV-003: Writer-command destinations ARE write targets
# tee/cp/mv/install/ln/sed -i/perl -i/dd of=/truncate. Source args allow (DD-7).
# ===========================================================================
test_inv003_writer_destinations_block() {
  echo ""
  echo "=== INV-003: writer-command destinations block; source args allow ==="

  local test_dir="/tmp/correctless-rescope-inv003-$$"
  setup_test_env "$test_dir"; cd "$test_dir" || return

  # tee family — every non-`-`-leading arg is a destination
  assert_bash "INV-003: tee .env"                      "2" "echo x | tee .env"
  assert_bash "INV-003: tee -a .env"                   "2" "echo x | tee -a .env"
  assert_bash "INV-003: tee -- .env"                   "2" "echo x | tee -- .env"
  assert_bash "INV-003: tee --output-error=warn .env"  "2" "echo x | tee --output-error=warn .env"
  assert_bash "INV-003: tee a .env (both dests)"       "2" "echo x | tee plain.log .env"

  # cp/mv/install/ln — FINAL positional is the destination
  assert_bash "INV-003: cp x .env"        "2" "cp plain.txt .env"
  assert_bash "INV-003: mv x .env"        "2" "mv plain.txt .env"
  assert_bash "INV-003: install x .env"   "2" "install plain.txt .env"
  assert_bash "INV-003: ln x .env"        "2" "ln plain.txt .env"

  # sed -i / perl -i — in-place writers (prefilter matches sed -i / perl -i)
  assert_bash "INV-003: sed -i ... .env"        "2" "sed -i s/a/b/ .env"
  assert_bash "INV-003: sed -i.bak ... .env"    "2" "sed -i.bak s/a/b/ .env"
  assert_bash "INV-003: perl -i ... .env"       "2" "perl -i -e 1 .env"
  assert_bash "INV-003: perl -i -pe ... .env"   "2" "perl -i -pe 's/a/b/' .env"

  # dd of= — position-independent within the dd segment; if= is a read
  assert_bash "INV-003: dd of=.env"             "2" "dd if=/dev/zero of=.env"
  assert_bash "INV-003: dd if=.env (read) allowed" "0" "dd if=.env of=/tmp/plain.out"

  # truncate
  assert_bash "INV-003: truncate -s0 .env"      "2" "truncate -s0 .env"

  # Source-arg reads ALLOW (RS-016 / DD-7): `.env` as a cp SOURCE is a read.
  assert_bash "INV-003: cp .env <non-protected dest> ALLOWED (source)" "0" \
    "cp .env /tmp/plain-backup.txt"
  assert_bash "INV-003: mv .env <non-protected dest> ALLOWED (source)" "0" \
    "mv .env /tmp/plain-backup.txt"

  rm -rf "$test_dir"
}

# ===========================================================================
# INV-004: git working-tree commands are not write targets
# ===========================================================================
test_inv004_git_worktree_allowed() {
  echo ""
  echo "=== INV-004: git working-tree commands not extracted ==="

  local test_dir="/tmp/correctless-rescope-inv004-$$"
  setup_test_env "$test_dir"; cd "$test_dir" || return

  assert_bash "INV-004: git checkout HEAD -- scripts/lib.sh ALLOWED" "0" \
    "git checkout HEAD -- scripts/lib.sh"
  assert_bash "INV-004: git restore .env ALLOWED" "0" "git restore .env"
  assert_bash "INV-004: git checkout -- .env ALLOWED" "0" "git checkout -- .env"
  assert_bash "INV-004: git stash ALLOWED" "0" "git stash"

  rm -rf "$test_dir"
}

# ===========================================================================
# INV-005: Interpreter+eval chains are opaque; process-sub opaque; but a
# redirect OUTSIDE the opaque operand still blocks.
# ===========================================================================
test_inv005_interpreter_opaque() {
  echo ""
  echo "=== INV-005: interpreter/eval/process-sub operands opaque; outside-redirect blocks ==="

  local test_dir="/tmp/correctless-rescope-inv005-$$"
  setup_test_env "$test_dir"; cd "$test_dir" || return

  # Eval payload opaque -> allow
  assert_bash "INV-005: bash -c \"echo x > .env\" opaque ALLOWED" "0" \
    'bash -c "echo x > .env"'
  assert_bash "INV-005: sh -c opaque ALLOWED" "0" 'sh -c "echo x > .env"'
  assert_bash "INV-005: python -c opaque ALLOWED" "0" \
    'python -c "open(\".env\",\"w\")"'

  # Process substitution operand opaque -> allow, and the shattered `.env` is
  # NOT independently emitted (CX-006).
  assert_bash "INV-005: echo x > >(tee .env) opaque ALLOWED" "0" \
    "echo x > >(tee .env)"

  # Redirect OUTSIDE the opaque operand STILL blocks: the trailing `> .env` is
  # outside the here-string operand.
  assert_bash "INV-005: cat <<< x > .env (outside-redirect) BLOCKED" "2" \
    "cat <<< x > .env"

  # perl -i is a WRITER, not opaque (RS-001)
  assert_bash "INV-005: perl -i is writer -> BLOCKED" "2" "perl -i -e 1 .env"

  rm -rf "$test_dir"
}

# ===========================================================================
# INV-006: Sink devices excluded from extraction
# ===========================================================================
test_inv006_sink_devices_excluded() {
  echo ""
  echo "=== INV-006: sink devices excluded ==="

  local test_dir="/tmp/correctless-rescope-inv006-$$"
  setup_test_env "$test_dir"; cd "$test_dir" || return

  assert_bash "INV-006: cmd > /dev/null ALLOWED" "0" "make > /dev/null"
  assert_bash "INV-006: cmd 2>/dev/null ALLOWED" "0" "make 2>/dev/null"
  assert_bash "INV-006: > /dev/stdout ALLOWED" "0" "echo x > /dev/stdout"
  assert_bash "INV-006: > /dev/stderr ALLOWED" "0" "echo x > /dev/stderr"
  assert_bash "INV-006: >/dev/fd/3 ALLOWED" "0" "echo x >/dev/fd/3"

  # Structural tripwire (PRH-001 style; added 2026-06 from mutation testing).
  # The behavioral assertions above pass WHETHER OR NOT sink devices are
  # excluded — no sink device matches a DEFAULTS pattern, so emitting one is
  # harmless at the exit-code level. A mutation that changes the early-return
  # exclusion to a no-op SURVIVES the behavioral corpus. This tripwire pins that
  # the early-return exclusion branch exists so dropping it is caught.
  local guard="$REPO_DIR/hooks/sensitive-file-guard.sh"
  if grep -Fq '/dev/fd/*) return 0' "$guard"; then
    pass "INV-006 [structural tripwire]" "sink-device exclusion returns early (not emitted)"
  else
    fail "INV-006 [structural tripwire]" "sink-device early-return exclusion branch missing"
  fi

  rm -rf "$test_dir"
}

# ===========================================================================
# INV-007: Ambiguity fails open (guardrail posture) — witness corpus +
# structural tripwire (PRH-001).
# ===========================================================================
test_inv007_ambiguity_fails_open() {
  echo ""
  echo "=== INV-007: ambiguity fails open (witness corpus) ==="

  local test_dir="/tmp/correctless-rescope-inv007-$$"
  setup_test_env "$test_dir"; cd "$test_dir" || return

  # Unresolvable / dynamic destinations -> allow
  assert_bash "INV-007: echo x > \${f} dynamic ALLOWED" "0" 'echo x > "${f}"'
  assert_bash "INV-007: bash -c \$dyn ALLOWED" "0" 'bash -c "$dyn"'
  assert_bash "INV-007: trailing bare > ALLOWED" "0" "echo x >"

  rm -rf "$test_dir"
}

test_inv007_structural_tripwire() {
  echo ""
  echo "=== INV-007/PRH-001 [structural TRIPWIRE]: no token-emit outside redirect/writer branches ==="

  local guard="$REPO_DIR/hooks/sensitive-file-guard.sh"
  local body
  body="$(awk '
    /^_extract_bash_targets[[:space:]]*\(\)[[:space:]]*\{?$/,/^\}$/
  ' "$guard")"
  if [ -z "$body" ]; then
    fail "INV-007" "cannot locate _extract_bash_targets body"; return
  fi

  # LABELED TRIPWIRE: behavior (INV-001 / INV-017 Half-A) is the proof; this is
  # a fast smoke signal that the over-extractor default branch is gone. The
  # over-extractor's tell is a bare per-token emit of `$tok`. Scan the WHOLE
  # body (the `*)` arm has a nested inner `case` whose `;;` truncates a naive
  # arm-extractor). A destination-driven rewrite emits only redirect/writer
  # destinations, never the raw catch-all token.
  if printf '%s\n' "$body" | grep -v '^[[:space:]]*#' \
       | grep -Eq '(_strip_quotes|echo|printf)[^#]*"\$tok"'; then
    fail "INV-007" "bare \$tok emit present (PRH-001 over-extractor tripwire tripped)"
  else
    pass "INV-007" "no unconditional \$tok emit (PRH-001 tripwire green)"
  fi
}

# ===========================================================================
# INV-008: Hook-input parse failure still fails closed (MUST-PASS-UNCHANGED)
# ===========================================================================
test_inv008_input_parse_fails_closed() {
  echo ""
  echo "=== INV-008: malformed stdin JSON still exits 2 (fail-closed) ==="

  local exit_code
  echo "NOT VALID JSON {{{" | bash "$HOOK" 2>/dev/null
  exit_code=$?
  assert_eq "INV-008: malformed stdin JSON -> exit 2" "2" "$exit_code"

  # Boundary: a JSON-valid envelope whose command is unparsable-as-shell is
  # INV-007 regime (allow) — proving the fail-closed boundary sits at the JSON
  # layer, not the shell layer.
  local test_dir="/tmp/correctless-rescope-inv008-$$"
  setup_test_env "$test_dir"; cd "$test_dir" || return
  assert_bash "INV-008: valid JSON, unbalanced-quote command -> ALLOWED (INV-007 regime)" "0" \
    'echo "unterminated'
  rm -rf "$test_dir"
}

# ===========================================================================
# INV-010: Canonical-form matching preserved — traversal-encoded writer dest.
# (The structural test_inv005_canonical_only_at_matcher and
# test_inv008_canonical_pattern_matching live in test-sensitive-file-guard.sh
# and MUST-PASS-UNCHANGED; here we add the new writer-destination fixtures.)
# ===========================================================================
test_inv010_canonical_writer_destination() {
  echo ""
  echo "=== INV-010: traversal-encoded writer-destination still blocks ==="

  local test_dir="/tmp/correctless-rescope-inv010-$$"
  setup_test_env "$test_dir"; cd "$test_dir" || return

  assert_bash "INV-010: cp x subdir/../.env (traversal dest) BLOCKED" "2" \
    "cp plain.txt subdir/../.env"
  assert_bash "INV-010: redirect > subdir/../.env BLOCKED" "2" \
    "echo x > subdir/../.env"
  assert_bash "INV-010: tee certs/../.env BLOCKED" "2" \
    "echo x | tee certs/../.env"

  rm -rf "$test_dir"
}

# ===========================================================================
# INV-011: _has_write_pattern + get_target_file frozen (golden hash) +
# workflow-gate referenced must-stay-green.
# ===========================================================================
test_inv011_lib_functions_frozen() {
  echo ""
  echo "=== INV-011: _has_write_pattern + get_target_file frozen (golden hash) ==="

  local lib="$REPO_DIR/$LIB_PATH"

  # Golden hashes computed against the current (frozen) lib.sh bodies. If GREEN
  # phase modifies either body, these mismatch -> the freeze invariant fails.
  local expect_hwp="0f30a4f1fdeb7bc82b5b2474c6f4bf723fd2ca2fe2cbf04bca559bb3dd49e1db"
  local expect_gtf="ccd30fc96542e72d908693f3c2eb4c63ecf620c7d777fa2c7323afd8156c8cd8"

  local got_hwp got_gtf
  got_hwp="$(awk '/^_has_write_pattern[[:space:]]*\(\)[[:space:]]*\{?$/,/^\}$/' "$lib" | sha256sum | cut -d' ' -f1)"
  got_gtf="$(awk '/^get_target_file[[:space:]]*\(\)[[:space:]]*\{?$/,/^\}$/' "$lib" | sha256sum | cut -d' ' -f1)"

  assert_eq "INV-011: _has_write_pattern body unchanged (golden hash)" "$expect_hwp" "$got_hwp"
  assert_eq "INV-011: get_target_file body unchanged (golden hash)" "$expect_gtf" "$got_gtf"

  # Cross-reference: workflow-gate test must stay green (consumes _has_write_pattern).
  if [ -f "$REPO_DIR/tests/test-workflow-gate.sh" ]; then
    pass "INV-011" "tests/test-workflow-gate.sh present (must-stay-green reference)"
  else
    fail "INV-011" "tests/test-workflow-gate.sh missing — cannot assert workflow-gate unaffected"
  fi
}

# ===========================================================================
# INV-012 / PRH-002: doc-coherence — no SFG reference claims perimeter language.
# Single shared grep corpus (CX-003). FAILS NOW (docs still say perimeter) -> RED.
# ===========================================================================
#
# DECISION (B2 scoping): the CLAUDE.md "Correctless Learnings" Postmortem
# entries (### <date> — Postmortem: …) are the HISTORICAL RECORD that DOCUMENTS
# the abolished perimeter framing — e.g. the PMB-020 narrative quotes
# "structurally impossible" / "fail-closed" / "Category: security" precisely to
# describe the AP-040 category error. That ledger text is NOT an SFG capability
# claim and the doc sweep does not (and must not) delete it. INV-012/CX-014's
# intent is the SFG *description* surfaces, not the postmortem ledger. So the
# corpus grep EXCLUDES the CLAUDE.md `### … Postmortem:` narrative blocks while
# still covering CLAUDE.md's sole-writer CONVENTION entries (2026-04-30 /
# 2026-04-26, which the spec Scope names for amendment) and every other corpus
# file in full. Without this scoping the test could never go GREEN — it would
# force deletion of the postmortem record. Spec ref: INV-012 statement +
# CLAUDE.md Scope (L31) names the conventions, not the PMB ledger.
#
# _sfg_corpus_lines emits, for a corpus file, only the lines eligible for the
# perimeter check: for CLAUDE.md it strips every `### … Postmortem:` section
# body (from the heading up to but not including the next `### ` heading or EOF);
# all other files pass through verbatim. Output is `<lineno>:<text>` (grep -n form).
_sfg_corpus_lines() {
  local f="$1"
  case "$f" in
    */CLAUDE.md)
      awk '
        /^### .*Postmortem:/ { skip=1; next }
        /^### / { skip=0 }
        { if (!skip) printf "%d:%s\n", NR, $0 }
      ' "$f"
      ;;
    *)
      grep -n '' "$f"
      ;;
  esac
}

test_inv012_doc_coherence_no_perimeter() {
  echo ""
  echo "=== INV-012/PRH-002: SFG docs describe a guardrail, not a perimeter ==="

  # CX-003 shared corpus.
  local -a corpus=(
    "$REPO_DIR/.correctless/ARCHITECTURE.md"
    "$REPO_DIR/CLAUDE.md"
    "$REPO_DIR/.correctless/AGENT_CONTEXT.md"
    "$REPO_DIR/README.md"
  )
  while IFS= read -r f; do corpus+=( "$f" ); done < <(find "$REPO_DIR/docs/skills" -type f -name '*.md' 2>/dev/null)

  # Perimeter / abolished-mental-model phrases that must NOT co-occur with an SFG
  # reference. Extended per B2: adds "perimeter" and the CX-014 generic claims the
  # spec names — "prevents LLM writes" (ARCHITECTURE.md ~L22) and "Protected by
  # sensitive-file-guard" (~L202/230) framed as structural — plus the README
  # mermaid "Secret protection" label and the "Category: security" path framing.
  local -a banned=(
    "structurally impossible"
    "prevent injection"
    "Secret protection"
    "injection containment"
    "perimeter"
    "prevents LLM writes"
    "Protected by sensitive-file-guard"
    "Category: security"
  )

  local violations=0 f phrase eligible hits
  for f in "${corpus[@]}"; do
    [ -f "$f" ] || continue
    # Eligible = corpus lines minus the CLAUDE.md postmortem ledger (see DECISION).
    eligible="$(_sfg_corpus_lines "$f")"
    for phrase in "${banned[@]}"; do
      # SFG-referencing eligible lines that ALSO carry the banned phrase, OR
      # (for the README mermaid diagram) an SFG block-label line bearing the
      # phrase. We match the phrase on the same line as an SFG reference.
      hits="$(printf '%s\n' "$eligible" | grep -iE "(sensitive-file-guard|\bSFG\b)" | grep -iF -- "$phrase" || true)"
      if [ -n "$hits" ]; then
        violations=$((violations + 1))
        echo "  INV-012: '$phrase' tied to SFG in ${f#$REPO_DIR/}:" >&2
        echo "$hits" | sed 's/^/    /' >&2
      fi
    done

    # fail-closed-near-SFG check (B2): "fail-closed" framing applied to SFG is a
    # perimeter tell (the abolished "fail-closed on everything" mental model;
    # after the sweep "fail-closed" applies to the INPUT-PARSE path INV-008, not
    # the SFG capability headline). The README L298 target — "...sensitive-file-
    # guard.sh ... fail-closed, no overrides" — is the genuine RED case.
    #
    # Three deliberate scopings so the check pins ONLY the SFG capability headline:
    #   1. EXCLUDE the carve-out rule file .claude/rules/hooks-pretooluse.md — NOT
    #      in this corpus, and its clause-5 INV-013 text legitimately discusses
    #      fail-closed for the input-parse path.
    #   2. Require "fail-closed" within ~140 chars of a `sensitive-file-guard`
    #      token AND a perimeter-framing companion ("no overrides" | "perimeter").
    #      This skips ARCHITECTURE.md L591 ("exit 2 (fail-closed)" consequence note,
    #      no overrides framing) and the AGENT_CONTEXT.md Scripts-inventory megaline
    #      (L16), whose `fail-closed` mentions belong to config-update.sh /
    #      redact-secrets.sh / cchores-regression-oracle.sh, NOT to SFG, and which
    #      carries no "no overrides"/"perimeter" framing. (DECISION: the spec's
    #      AGENT_CONTEXT sweep target is the Hooks ROW SFG description, not the
    #      Scripts row — Scope L32 — so the Scripts megaline must not permanently-RED.)
    hits="$(printf '%s\n' "$eligible" \
      | grep -iE 'sensitive-file-guard.{0,140}fail.?closed|fail.?closed.{0,140}sensitive-file-guard' \
      | grep -iE 'no overrides|perimeter' || true)"
    if [ -n "$hits" ]; then
      violations=$((violations + 1))
      echo "  INV-012: 'fail-closed (perimeter framing)' tied to SFG in ${f#$REPO_DIR/}:" >&2
      echo "$hits" | sed 's/^/    /' >&2
    fi
  done

  if [ "$violations" -eq 0 ]; then
    pass "INV-012" "no SFG reference claims perimeter/secret-protection/injection/fail-closed-overrides language"
  else
    fail "INV-012" "$violations SFG perimeter-language references remain (doc sweep incomplete)"
  fi
}

# ===========================================================================
# INV-013: PAT-001 clause-5 carve-out documented in the rule file.
# FAILS NOW (no carve-out) -> RED.
# ===========================================================================
test_inv013_rule_carveout() {
  echo ""
  echo "=== INV-013: .claude/rules/hooks-pretooluse.md clause-5 carve-out ==="

  local rf="$REPO_DIR/.claude/rules/hooks-pre""tooluse.md"
  if [ ! -f "$rf" ]; then
    fail "INV-013" "rule file missing"; return
  fi

  local fails=0
  grep -qiE 'carve.out|fail.?open' "$rf" || { echo "  INV-013: no carve-out/fail-open subsection" >&2; fails=$((fails+1)); }
  grep -qF 'PMB-020' "$rf" || { echo "  INV-013: carve-out does not cite PMB-020" >&2; fails=$((fails+1)); }
  grep -qF 'INV-007' "$rf" || { echo "  INV-013: carve-out does not reference INV-007" >&2; fails=$((fails+1)); }
  grep -qF 'INV-008' "$rf" || { echo "  INV-013: carve-out does not reference INV-008" >&2; fails=$((fails+1)); }

  if [ "$fails" -eq 0 ]; then
    pass "INV-013" "clause-5 carve-out present, cites PMB-020 + INV-007/INV-008"
  else
    fail "INV-013" "$fails carve-out requirements unmet"
  fi
}

# ===========================================================================
# INV-014: BLOCKED message reflects guardrail framing.
# Must NOT tell the user "add an exclusion to custom_patterns if not sensitive"
# for a DEFAULTS path; points to .claude/rules/sfg-deliverable.md. FAILS NOW -> RED.
# ===========================================================================
test_inv014_blocked_message_guardrail() {
  echo ""
  echo "=== INV-014: BLOCKED message guardrail framing ==="

  local test_dir="/tmp/correctless-rescope-inv014-$$"
  setup_test_env "$test_dir"; cd "$test_dir" || return

  local result stderr_out
  result="$(run_hook_capture '{"tool_name":"Edit","tool_input":{"file_path":".env","old_string":"a","new_string":"b"}}')"
  assert_eq "INV-014: block exit 2" "2" "$(extract_exit "$result")"
  stderr_out="$(extract_stderr "$result")"

  # The abolished perimeter mental model must NOT appear (PMB-017: no allowlist
  # primitive exists for DEFAULTS, so "exclude via custom_patterns if not
  # actually sensitive" is wrong guidance).
  if echo "$stderr_out" | grep -qiE 'if this file is not actually sensitive'; then
    fail "INV-014" "block message still suggests custom_patterns exclusion ('not actually sensitive')"
  else
    pass "INV-014" "block message does not suggest the abolished custom_patterns exclusion"
  fi

  # For a deliverable edit, the sanctioned recovery is lift-and-restore.
  if echo "$stderr_out" | grep -qF 'sfg-deliverable.md'; then
    pass "INV-014" "block message points to .claude/rules/sfg-deliverable.md"
  else
    fail "INV-014" "block message does not point to the sanctioned recovery (sfg-deliverable.md)"
  fi

  rm -rf "$test_dir"
}

# ===========================================================================
# INV-015: CHANGELOG.md announces the re-scope. FAILS NOW -> RED.
# ===========================================================================
test_inv015_changelog_announced() {
  echo ""
  echo "=== INV-015: CHANGELOG.md announces SFG re-scope ==="

  local cl="$REPO_DIR/CHANGELOG.md"
  if [ ! -f "$cl" ]; then
    fail "INV-015" "CHANGELOG.md missing"; return
  fi
  # Look for an entry mentioning the SFG re-scope to write-targets-only.
  if grep -qiE 'sensitive-file-guard|\bSFG\b' "$cl" \
     && grep -qiE 're-?scope|write.target|guardrail' "$cl"; then
    pass "INV-015" "CHANGELOG announces the write-target re-scope"
  else
    fail "INV-015" "no CHANGELOG entry announcing the SFG write-target re-scope"
  fi
}

# ===========================================================================
# INV-016: pre-filter firing-set ⊇ extractor emit-set. Drive every INV-002/003
# must-block form through the FULL hook; if _has_write_pattern returns 1 first,
# the command exits 0 and this fails. Explicitly covers &>, >|, glued.
# ===========================================================================
test_inv016_prefilter_superset() {
  echo ""
  echo "=== INV-016: every must-block form fires the pre-filter (firing ⊇ emit) ==="

  local test_dir="/tmp/correctless-rescope-inv016-$$"
  setup_test_env "$test_dir"; cd "$test_dir" || return

  # The suspect operators per spec: &> (lib.sh L472 regex coverage), >|, glued.
  assert_bash "INV-016: &> reaches block" "2" "echo x &> .env"
  assert_bash "INV-016: &>| reaches block" "2" "echo x &>| .env"
  assert_bash "INV-016: >| reaches block" "2" "echo x >| .env"
  assert_bash "INV-016: glued x>.env reaches block" "2" "echo x>.env"
  assert_bash "INV-016: glued x&>.env reaches block" "2" "echo x&>.env"
  assert_bash "INV-016: tee reaches block" "2" "echo x | tee .env"
  assert_bash "INV-016: cp reaches block" "2" "cp plain.txt .env"
  assert_bash "INV-016: dd of= reaches block" "2" "dd if=x of=.env"
  assert_bash "INV-016: truncate reaches block" "2" "truncate -s0 .env"
  assert_bash "INV-016: sed -i reaches block" "2" "sed -i s/a/b/ .env"
  assert_bash "INV-016: perl -i reaches block" "2" "perl -i -e 1 .env"

  rm -rf "$test_dir"
}

# ===========================================================================
# INV-017: Permissive monotonicity, witnessed in both directions.
# Half-A: real dogfood false-blocks -> exit 0 (AP-031 real fixtures).
# Half-B: full INV-002/003 write corpus -> exit 2.
# ===========================================================================
test_inv017_half_a_newly_allowed() {
  echo ""
  echo "=== INV-017 Half-A: real dogfood false-blocks now ALLOWED ==="

  local test_dir="/tmp/correctless-rescope-inv017a-$$"
  setup_test_env "$test_dir"; cd "$test_dir" || return

  # Half-A corpus — the 6 real 2026-06-19 /cchores false-blocks + the 9 from the
  # 2026-06-24 /creview-spec session.
  # Source: .correctless/specs/sfg-rescope.md Context (L17-19) — the dogfood
  # evidence record. Each was a read / invocation / restore, ZERO write attacks,
  # all wrongly blocked by the over-extractor. Each MUST now exit 0.

  # --- 6 from the 2026-06-19 /cchores session (spec L19) ---
  assert_bash "INV-017A/cchores-1: jq config read"            "0" "jq '.intensity' .correctless/config/workflow-config.json"
  assert_bash "INV-017A/cchores-2: [ -f ] presence check"     "0" "[ -f .correctless/scripts/lib.sh ] && echo ok"
  assert_bash "INV-017A/cchores-3: git checkout -- restore"   "0" "git checkout -- scripts/lib.sh"
  assert_bash "INV-017A/cchores-4: ls"                        "0" "ls scripts/lib.sh"
  assert_bash "INV-017A/cchores-5: bash hf check 2>/dev/null" "0" "bash harness-fingerprint.sh check 2>/dev/null"
  assert_bash "INV-017A/cchores-6: cat read"                  "0" "cat .correctless/scripts/lib.sh"

  # --- 9 from the 2026-06-24 /creview-spec session (spec L19) ---
  assert_bash "INV-017A/review-1: jq config read"             "0" "jq -r '.protected_files' .correctless/config/workflow-config.json"
  assert_bash "INV-017A/review-2: [ -f external-review-run]"  "0" "[ -f scripts/external-review-run.sh ] && echo ok"
  assert_bash "INV-017A/review-3: source lib.sh"              "0" "source scripts/lib.sh"
  assert_bash "INV-017A/review-4: bash invocation"            "0" "bash scripts/external-review-run.sh --help"
  assert_bash "INV-017A/review-5: cat lib.sh read"            "0" "cat scripts/lib.sh"
  assert_bash "INV-017A/review-6: grep over lib.sh"           "0" "grep -n canonicalize_path scripts/lib.sh"
  assert_bash "INV-017A/review-7: head config read"           "0" "head -5 .correctless/config/workflow-config.json"
  assert_bash "INV-017A/review-8: jq harness-fingerprint read" "0" "jq '.' .correctless/meta/harness-fingerprint.json"
  assert_bash "INV-017A/review-9: bash audit-record invoke"   "0" "bash scripts/audit-record.sh --help 2>/dev/null"

  rm -rf "$test_dir"
}

test_inv017_half_b_still_blocked() {
  echo ""
  echo "=== INV-017 Half-B: full INV-002/003 write corpus still BLOCKED ==="

  local test_dir="/tmp/correctless-rescope-inv017b-$$"
  setup_test_env "$test_dir"; cd "$test_dir" || return

  # Half-B — every genuine write destination must STILL exit 2. If any flips to
  # 0, the re-targeting broke a real guard.
  local -a writes=(
    'echo x > .env'
    'echo x >> .env'
    'echo x >| .env'
    'echo x &> .env'
    'echo x>.env'
    'echo x&>.env'
    'echo x | tee .env'
    'echo x | tee -a .env'
    'cp plain.txt .env'
    'mv plain.txt .env'
    'install plain.txt .env'
    'ln plain.txt .env'
    'sed -i s/a/b/ .env'
    'perl -i -e 1 .env'
    'dd if=x of=.env'
    'truncate -s0 .env'
  )
  local c
  for c in "${writes[@]}"; do
    assert_bash "INV-017B: still blocked: $c" "2" "$c"
  done

  rm -rf "$test_dir"
}

# ===========================================================================
# INV-018: representative concrete destination per DEFAULTS pattern class +
# structural coverage check (CX-005).
# ===========================================================================
test_inv018_defaults_classes_block() {
  echo ""
  echo "=== INV-018: each DEFAULTS pattern class blocks as redirect/writer dest ==="

  local test_dir="/tmp/correctless-rescope-inv018-$$"
  setup_test_env "$test_dir"; cd "$test_dir" || return

  # full-path literal
  assert_bash "INV-018 full-path: >> harness-fingerprint.json" "2" \
    "echo x >> .correctless/meta/harness-fingerprint.json"
  assert_bash "INV-018 full-path: cp -> lib.sh" "2" "cp plain.txt scripts/lib.sh"
  # basename literal
  assert_bash "INV-018 basename: tee credentials.json" "2" "echo x | tee credentials.json"
  assert_bash "INV-018 basename: > credentials.json" "2" "echo x > credentials.json"
  # glob *.pem
  assert_bash "INV-018 glob *.pem: cp -> secret.pem" "2" "cp plain.txt secret.pem"
  assert_bash "INV-018 glob *.pem: > secret.pem" "2" "echo x > secret.pem"
  # glob .env.*
  assert_bash "INV-018 glob .env.*: > .env.production" "2" "echo x > .env.production"
  # glob id_rsa.*
  assert_bash "INV-018 glob id_rsa.*: tee id_rsa.pub" "2" "echo x | tee id_rsa.pub"

  rm -rf "$test_dir"
}

test_inv018_structural_class_coverage() {
  echo ""
  echo "=== INV-018 [structural CX-005]: every observed DEFAULTS pattern class has ≥1 fixture ==="

  # A1 strengthening (CX-005): PARSE the DEFAULTS list out of the hook itself,
  # classify each pattern, and assert this test file carries ≥1 hook-integration
  # fixture for every CLASS that actually appears in DEFAULTS. The prior version
  # grepped for hardcoded fixture STRINGS, so it only detected DELETION of a known
  # fixture — a NEW DEFAULTS class (or the disappearance of an existing one) could
  # silently escape the corpus. By driving the assertion off the live DEFAULTS
  # list, a new pattern class added to the hook makes THIS test fail until a
  # representative fixture is added.
  #
  # Classification (per INV-018 statement):
  #   - glob          : pattern contains '*'
  #   - full-path     : no '*', contains '/'   (e.g. scripts/lib.sh)
  #   - basename      : no '*', no '/'         (e.g. credentials.json)
  local guard="$REPO_DIR/hooks/sensitive-file-guard.sh"
  local self="$REPO_DIR/tests/test-sfg-rescope.sh"

  if [ ! -f "$guard" ]; then
    fail "INV-018" "cannot locate hook to parse DEFAULTS list"; return
  fi

  # Extract the DEFAULTS heredoc-ish assignment body: lines strictly between the
  # opening `DEFAULTS="` and the closing line ending in `"`. awk state machine.
  local defaults
  defaults="$(awk '
    /^DEFAULTS="/ { inblk=1
                    # capture any pattern glued onto the opening line after the quote
                    line=$0; sub(/^DEFAULTS="/, "", line)
                    if (line != "") print line
                    next }
    inblk==1 {
      if ($0 ~ /"[[:space:]]*$/) { sub(/"[[:space:]]*$/, "", $0); if ($0 != "") print $0; inblk=0; next }
      print $0
    }
  ' "$guard")"

  if [ -z "$defaults" ]; then
    fail "INV-018" "parsed an empty DEFAULTS list from the hook (parser drift?)"; return
  fi

  # Which classes are OBSERVED in the live DEFAULTS list?
  local has_glob=0 has_fullpath=0 has_basename=0 pat
  while IFS= read -r pat; do
    [ -z "$pat" ] && continue
    case "$pat" in
      *'*'*)  has_glob=1 ;;
      */*)    has_fullpath=1 ;;
      *)      has_basename=1 ;;
    esac
  done <<< "$defaults"

  # For each OBSERVED class, require ≥1 hook-integration fixture in this file.
  # We detect fixtures by the concrete destinations the INV-018/Half-B corpora use.
  local fails=0
  if [ "$has_fullpath" -eq 1 ]; then
    if grep -qE 'meta/harness-fingerprint\.json|scripts/lib\.sh' "$self"; then
      :
    else
      echo "  CX-005: DEFAULTS contains a full-path-literal class but no fixture covers it" >&2
      fails=$((fails+1))
    fi
  fi
  if [ "$has_basename" -eq 1 ]; then
    if grep -qE 'tee credentials\.json|> credentials\.json' "$self"; then
      :
    else
      echo "  CX-005: DEFAULTS contains a basename-literal class but no fixture covers it" >&2
      fails=$((fails+1))
    fi
  fi
  if [ "$has_glob" -eq 1 ]; then
    # Any one concrete materialization of a glob class counts (*.pem / .env.* / id_rsa.*).
    if grep -qE 'secret\.pem|\.env\.production|id_rsa\.pub' "$self"; then
      :
    else
      echo "  CX-005: DEFAULTS contains a glob class but no fixture materializes one" >&2
      fails=$((fails+1))
    fi
  fi

  if [ "$fails" -eq 0 ]; then
    pass "INV-018" "every observed DEFAULTS pattern class (full-path=$has_fullpath basename=$has_basename glob=$has_glob) has ≥1 fixture (CX-005)"
  else
    fail "INV-018" "$fails observed DEFAULTS pattern class(es) uncovered by any fixture"
  fi
}

# ===========================================================================
# INV-019: hook sets LC_ALL=C at hook scope (structural PRIMARY) + cross-locale
# behavioral fixture that DISCOVERS a UTF-8 locale (CX-010).
# ===========================================================================
test_inv019_lc_all_c_structural() {
  echo ""
  echo "=== INV-019 [structural PRIMARY]: LC_ALL=C at hook scope before collect_targets ==="

  local guard="$REPO_DIR/hooks/sensitive-file-guard.sh"

  # The LC_ALL=C assignment must appear at hook scope (not indented inside a
  # function) AND before the collect_targets definition/use.
  local lc_line ct_line
  lc_line="$(grep -nE '^LC_ALL=C' "$guard" | head -1 | cut -d: -f1)"
  ct_line="$(grep -nE '^collect_targets' "$guard" | head -1 | cut -d: -f1)"

  if [ -z "$lc_line" ]; then
    fail "INV-019" "no hook-scope 'LC_ALL=C' line in sensitive-file-guard.sh"
    return
  fi
  if [ -z "$ct_line" ]; then
    fail "INV-019" "cannot locate collect_targets to order-check against LC_ALL=C"
    return
  fi
  if [ "$lc_line" -lt "$ct_line" ]; then
    pass "INV-019" "LC_ALL=C set at hook scope (line $lc_line) before collect_targets (line $ct_line)"
  else
    fail "INV-019" "LC_ALL=C (line $lc_line) is not before collect_targets (line $ct_line)"
  fi
}

test_inv019_cross_locale_behavioral() {
  echo ""
  echo "=== INV-019 [behavioral CX-010]: cross-locale block decision is stable ==="

  # Discover an available UTF-8 locale at runtime — accept any spelling.
  local utf8
  utf8="$(locale -a 2>/dev/null | grep -iE 'utf-?8' | head -1 || true)"
  if [ -z "$utf8" ]; then
    skip "INV-019" "no UTF-8 locale available (locale -a) — behavioral cross-locale check skipped (CX-010)"
    return
  fi

  local test_dir="/tmp/correctless-rescope-inv019-$$"
  setup_test_env "$test_dir"; cd "$test_dir" || return

  # A3 strengthening: assert CORRECTNESS, not merely locale-STABILITY. The prior
  # `rc_c == rc_utf8` passes if both are 0 (a broken hook that allows under both
  # locales). Pin the must-block fixture (`echo x > .env`) to exit 2 under BOTH
  # LC_ALL=C and the discovered UTF-8 locale — proving the redirect destination
  # blocks AND the block decision is locale-independent.
  local json rc_c rc_utf8
  json="$(jq -nc '{tool_name:"Bash",tool_input:{command:"echo x > .env"}}')"
  echo "$json" | LC_ALL=C bash "$HOOK" >/dev/null 2>&1; rc_c=$?
  echo "$json" | LC_ALL="$utf8" bash "$HOOK" >/dev/null 2>&1; rc_utf8=$?
  assert_eq "INV-019: echo x > .env BLOCKS under LC_ALL=C" "2" "$rc_c"
  assert_eq "INV-019: echo x > .env BLOCKS under $utf8 (locale-independent block)" "2" "$rc_utf8"

  rm -rf "$test_dir"
}

# ===========================================================================
# INV-020: per-segment positional writer detection.
# ===========================================================================
test_inv020_per_segment_positional() {
  echo ""
  echo "=== INV-020: positional writer detection operates per command-segment ==="

  local test_dir="/tmp/correctless-rescope-inv020-$$"
  setup_test_env "$test_dir"; cd "$test_dir" || return

  # cp src dest; cat .env -> ALLOW (.env is a read in a different segment; no
  # cross-segment false emit)
  assert_bash "INV-020: cp src dest; cat .env -> ALLOWED" "0" "cp src dest; cat .env"
  # cp src .env; echo ok -> BLOCK (.env is cp's destination; ok must NOT be the dest)
  assert_bash "INV-020: cp src .env; echo ok -> BLOCKED" "2" "cp src .env; echo ok"
  # tee out; cat .env -> ALLOW (tee branch must not overrun the ;)
  assert_bash "INV-020: tee out; cat .env -> ALLOWED" "0" "echo x | tee out; cat .env"
  # tee .env; echo ok -> BLOCK
  assert_bash "INV-020: tee .env; echo ok -> BLOCKED" "2" "echo x | tee .env; echo ok"
  # truncate -s0 out; cat .env -> ALLOW
  assert_bash "INV-020: truncate -s0 out; cat .env -> ALLOWED" "0" "truncate -s0 out; cat .env"
  # mv a b | tee .env -> BLOCK via tee; b must not be wrongly emitted (b is mv's dest,
  # non-protected; .env is tee's dest, protected)
  assert_bash "INV-020: mv a b | tee .env -> BLOCKED (via tee, b not wrongly emitted)" "2" "mv a b | tee .env"
  # dd of= per-segment: second of= belongs to printf, not dd
  assert_bash "INV-020: dd if=x of=out; printf of=.env -> ALLOWED" "0" "dd if=x of=out; printf of=.env"
  assert_bash "INV-020: dd if=x of=.env; echo ok -> BLOCKED" "2" "dd if=x of=.env; echo ok"
  # &> survives segmentation as a redirect (must not split on the & boundary)
  assert_bash "INV-020: echo x &> .env -> BLOCKED (&> survives segmentation)" "2" "echo x &> .env"
  assert_bash "INV-020: echo x&>.env glued -> BLOCKED" "2" "echo x&>.env"

  rm -rf "$test_dir"
}

# ---------------------------------------------------------------------------
# QA-001 / QA-002 (round 1): redirect operators and command separators that
# appear INSIDE a quoted string argument or a word-boundary `#` comment are NOT
# real redirects/separators — they must NOT produce a write target. The
# destination-driven model assumes operator detection reflects REAL (unquoted,
# non-comment) shell syntax; quote/comment-blindness re-introduces AP-040
# false-block friction through a different door (fails CLOSED, not in the
# accepted fail-open set). Controls assert that a REAL redirect to a quoted
# DESTINATION and a quoted writer DESTINATION still block.
# ---------------------------------------------------------------------------
test_qa001_quoted_and_comment_operators_not_targets() {
  echo ""
  echo "=== QA-001/QA-002: quoted/commented operators are NOT write targets ==="

  # Must ALLOW — the `>`/`>>` is inside a quoted echo/printf ARGUMENT (a read).
  assert_bash "QA-001: echo \"a > .env\" (quoted operator in arg) ALLOWED" "0" \
    'echo "a > .env"'
  assert_bash "QA-001: echo 'x > .env' (single-quoted operator) ALLOWED" "0" \
    "echo 'x > .env'"
  assert_bash "QA-001: printf of a string containing >> credentials.json ALLOWED" "0" \
    'printf "%s\n" "x >> credentials.json"'
  # Must ALLOW — the `>` is inside a word-boundary `#` comment.
  assert_bash "QA-001: ls foo # > .env (redirect in comment) ALLOWED" "0" \
    'ls foo # > .env'

  # QA-002 — separators inside quotes are not segment boundaries.
  assert_bash "QA-002: echo \"a | tee .env\" (quoted pipe+tee in arg) ALLOWED" "0" \
    'echo "a | tee .env"'
  assert_bash "QA-002: echo \"a; rm .env\" (quoted separator in arg) ALLOWED" "0" \
    'echo "a; rm .env"'

  # Controls — REAL operators must STILL block (the fix must not over-mask).
  assert_bash "QA-001 control: echo x > .env (real redirect) BLOCKED" "2" \
    'echo x > .env'
  assert_bash "QA-001 control: echo x > \".env\" (real redirect, quoted dest) BLOCKED" "2" \
    'echo x > ".env"'
  assert_bash "QA-001 control: tee \".env\" (quoted writer dest) BLOCKED" "2" \
    'tee ".env"'
  assert_bash "QA-002 control: echo x | tee .env (real pipe+tee) BLOCKED" "2" \
    'echo x | tee .env'
}

# ---------------------------------------------------------------------------
# QA-003 (round 2): escape-context parity with the shell lexer. A backslash-
# escaped quote (\" / \') OUTSIDE any quoted span is a LITERAL quote in real
# bash — it does NOT open a quoted span, so a redirect/writer that follows is a
# REAL, LIVE write. The operator-masker must not treat the post-backslash quote
# as a span opener (which would mask the real operator and SILENTLY ALLOW the
# write — AP-022 guard breakage). All three command forms below are bash -n
# VALID and write the protected file in a real shell, so they MUST block.
# Controls assert the genuinely-quoted forms (\" INSIDE a double quote) still
# allow, pinning all three escape contexts (outside / single / double).
# ---------------------------------------------------------------------------
test_qa003_backslash_escape_context_parity() {
  echo ""
  echo "=== QA-003: backslash-escaped quote escape-context parity ==="

  # Must BLOCK — \" / \' outside quotes is a literal quote; the trailing
  # redirect/separator+writer is a REAL write (verified bash -n valid + writes).
  assert_bash "QA-003: echo \\\" > .env (escaped quote outside, real redirect) BLOCKED" "2" \
    'echo \" > .env'
  assert_bash "QA-003: echo \\\"; tee .env (escaped quote, real sep+tee) BLOCKED" "2" \
    'echo \"; tee .env'
  assert_bash "QA-003: printf \\\" ; cp x .env (escaped quote, real cp) BLOCKED" "2" \
    'printf \" ; cp x .env'
  assert_bash "QA-003: echo \\' > .env (escaped single-quote outside) BLOCKED" "2" \
    "echo \\' > .env"

  # Controls — \" INSIDE a double-quoted span keeps the span open, so the
  # operator is genuinely quoted -> ALLOW (must not over-block).
  assert_bash "QA-003 control: echo \"a \\\" > .env\" (escaped quote inside dquote) ALLOWED" "0" \
    'echo "a \" > .env"'
}


# ---------------------------------------------------------------------------
# QA-006 (round 3): backslash x redirect-operator PARITY SWEEP. A hand-rolled
# lexer-state masker must agree with real bash on whether an operator preceded
# by a run of backslashes is LIVE (real redirect -> write -> must BLOCK) or
# ESCAPED (literal -> no write -> must ALLOW). Each row's expected verdict is
# PINNED TO THE REAL-BASH ORACLE (gen-fixtures.sh differential run, 2026-06):
# exit 2 = real bash actually wrote the target; exit 0 = no write. The round-2
# backslash branch regressed even-length backslash runs glued to a
# space-separated operator (a real redirect that the extractor failed to emit).
# NOTE the non-obvious oracle the differential revealed: the two-token redirects
# (append, numbered-fd, and-redirect) stay LIVE under ANY backslash prefix
# because the escape consumes a non-operator byte and leaves a live operator;
# only the single-char truncate/noclobber redirects follow even=block/odd=allow
# parity. Source: real-bash differential oracle, NOT hand-derived (PMB-013
# lexer-parity, AP-022 guards against the missed-write direction).
# ---------------------------------------------------------------------------
test_qa006_backslash_operator_parity_sweep() {
  echo ""
  echo "=== QA-006: backslash x operator parity sweep (oracle-pinned) ==="
  assert_bash 'parity n=0 op=> space -> 2' '2' 'echo a > .env'
  assert_bash 'parity n=0 op=> glued -> 2' '2' 'echo a >.env'
  assert_bash 'parity n=1 op=> space -> 0' '0' 'echo a \> .env'
  assert_bash 'parity n=1 op=> glued -> 0' '0' 'echo a \>.env'
  assert_bash 'parity n=2 op=> space -> 2' '2' 'echo a \\> .env'
  assert_bash 'parity n=2 op=> glued -> 2' '2' 'echo a \\>.env'
  assert_bash 'parity n=3 op=> space -> 0' '0' 'echo a \\\> .env'
  assert_bash 'parity n=3 op=> glued -> 0' '0' 'echo a \\\>.env'
  assert_bash 'parity n=0 op=>> space -> 2' '2' 'echo a >> .env'
  assert_bash 'parity n=0 op=>> glued -> 2' '2' 'echo a >>.env'
  assert_bash 'parity n=1 op=>> space -> 2' '2' 'echo a \>> .env'
  assert_bash 'parity n=1 op=>> glued -> 2' '2' 'echo a \>>.env'
  assert_bash 'parity n=2 op=>> space -> 2' '2' 'echo a \\>> .env'
  assert_bash 'parity n=2 op=>> glued -> 2' '2' 'echo a \\>>.env'
  assert_bash 'parity n=3 op=>> space -> 2' '2' 'echo a \\\>> .env'
  assert_bash 'parity n=3 op=>> glued -> 2' '2' 'echo a \\\>>.env'
  assert_bash 'parity n=0 op=>| space -> 2' '2' 'echo a >| .env'
  assert_bash 'parity n=0 op=>| glued -> 2' '2' 'echo a >|.env'
  assert_bash 'parity n=1 op=>| space -> 0' '0' 'echo a \>| .env'
  assert_bash 'parity n=1 op=>| glued -> 0' '0' 'echo a \>|.env'
  assert_bash 'parity n=2 op=>| space -> 2' '2' 'echo a \\>| .env'
  assert_bash 'parity n=2 op=>| glued -> 2' '2' 'echo a \\>|.env'
  assert_bash 'parity n=3 op=>| space -> 0' '0' 'echo a \\\>| .env'
  assert_bash 'parity n=3 op=>| glued -> 0' '0' 'echo a \\\>|.env'
  assert_bash 'parity n=0 op=1> space -> 2' '2' 'echo a 1> .env'
  assert_bash 'parity n=0 op=1> glued -> 2' '2' 'echo a 1>.env'
  assert_bash 'parity n=1 op=1> space -> 2' '2' 'echo a \1> .env'
  assert_bash 'parity n=1 op=1> glued -> 2' '2' 'echo a \1>.env'
  assert_bash 'parity n=2 op=1> space -> 2' '2' 'echo a \\1> .env'
  assert_bash 'parity n=2 op=1> glued -> 2' '2' 'echo a \\1>.env'
  assert_bash 'parity n=3 op=1> space -> 2' '2' 'echo a \\\1> .env'
  assert_bash 'parity n=3 op=1> glued -> 2' '2' 'echo a \\\1>.env'
  assert_bash 'parity n=0 op=2> space -> 2' '2' 'echo a 2> .env'
  assert_bash 'parity n=0 op=2> glued -> 2' '2' 'echo a 2>.env'
  assert_bash 'parity n=1 op=2> space -> 2' '2' 'echo a \2> .env'
  assert_bash 'parity n=1 op=2> glued -> 2' '2' 'echo a \2>.env'
  assert_bash 'parity n=2 op=2> space -> 2' '2' 'echo a \\2> .env'
  assert_bash 'parity n=2 op=2> glued -> 2' '2' 'echo a \\2>.env'
  assert_bash 'parity n=3 op=2> space -> 2' '2' 'echo a \\\2> .env'
  assert_bash 'parity n=3 op=2> glued -> 2' '2' 'echo a \\\2>.env'
  assert_bash 'parity n=0 op=&> space -> 2' '2' 'echo a &> .env'
  assert_bash 'parity n=0 op=&> glued -> 2' '2' 'echo a &>.env'
  assert_bash 'parity n=1 op=&> space -> 2' '2' 'echo a \&> .env'
  assert_bash 'parity n=1 op=&> glued -> 2' '2' 'echo a \&>.env'
  assert_bash 'parity n=2 op=&> space -> 2' '2' 'echo a \\&> .env'
  assert_bash 'parity n=2 op=&> glued -> 2' '2' 'echo a \\&>.env'
  assert_bash 'parity n=3 op=&> space -> 2' '2' 'echo a \\\&> .env'
  assert_bash 'parity n=3 op=&> glued -> 2' '2' 'echo a \\\&>.env'
}

# ---------------------------------------------------------------------------
# PERF (round-3 probe round, config-fuzz): the destination-extraction path MUST
# NOT be super-linear in command length. The round-1..3 masker walks the command
# byte-by-byte; a naive per-char string append is O(n^2) and HANGS on large
# commands (measured: 50KB timed out >15s vs the pre-feature hook's ~1.1s). Since
# _has_write_pattern fires on the ubiquitous `2>/dev/null` idiom, ANY large
# command with a redirect pays this — re-introducing friction (AP-040) at scale
# and risking a PreToolUse stall. This guard pins that a 100KB command completes
# (does not hang) under a generous timeout; the verdict (allow via size-cap
# fail-open per INV-007, or block via an O(n) extractor) is left to the impl.
# ---------------------------------------------------------------------------
test_perf_large_command_no_hang() {
  echo ""
  echo "=== PERF: large command must not hang (O(n^2) regression guard) ==="
  local big cmd json rc
  big="$(head -c 100000 /dev/zero | tr '\0' 'a')"
  cmd="echo $big > .env"
  json="$(jq -nc --arg c "$cmd" '{tool_name:"Bash",tool_input:{command:$c}}')"
  printf '%s' "$json" | timeout 8 bash "$HOOK" >/dev/null 2>&1
  rc=$?
  if [ "$rc" = 124 ]; then
    fail "PERF" "hook hung (>8s) on a 100KB command — O(n^2) extraction regression"
  else
    pass "PERF" "hook completed on a 100KB command (rc=$rc, no hang)"
  fi
}

# ---------------------------------------------------------------------------
# MA-write-form-fuzz (mini-audit R1): the append-both redirect `&>>` (the append
# variant of `&>`) writes a protected file in real bash but was a blind spot —
# the whitespace-separated form was ALLOWED (AP-022 under-extraction) because
# `&>>` was missing from the operator accept-set and the glued regex (and from
# the spec's INV-002 operator list). Verified real-bash writes via /tmp oracle.
# ---------------------------------------------------------------------------
test_ma_append_both_redirect_block() {
  echo ""
  echo "=== MA: &>> (append-both) destinations block ==="
  assert_bash "MA: echo x &>> .env (append-both, spaced) BLOCKED" "2" 'echo x &>> .env'
  assert_bash "MA: echo x 2>&1 &>> .env (fd-dup + append-both) BLOCKED" "2" 'echo x 2>&1 &>> .env'
  assert_bash "MA: echo x &>>.env (append-both, glued) BLOCKED" "2" 'echo x &>>.env'
  assert_bash "MA: echo x &>> credentials.json (basename) BLOCKED" "2" 'echo x &>> credentials.json'
}

# ---------------------------------------------------------------------------
# MA-hostile-input (mini-audit R1): the `-d` short-circuit in the cp|mv|install|ln
# writer branch is meant for `install -d` (directory-create, accepted fail-open),
# but it was command-AGNOSTIC, so `cp -d` / `cp ... -d` (where -d = --no-dereference,
# a benign non-relocating flag) wrongly short-circuited to no-destination and the
# real write was ALLOWED. The exclusion must be scoped to `install` only.
# (ln -d does NOT write a file — verified no-write — so it is not in scope.)
# ---------------------------------------------------------------------------
test_ma_cp_d_flag_not_relocation() {
  echo ""
  echo "=== MA: cp -d destination is a real write (block); install -d stays fail-open ==="
  assert_bash "MA: cp -d a .env (-d is --no-deref, real write) BLOCKED" "2" 'cp -d a .env'
  assert_bash "MA: cp a .env -d (trailing -d) BLOCKED" "2" 'cp a .env -d'
  assert_bash "MA: cp -d a secret.pem (glob) BLOCKED" "2" 'cp -d a secret.pem'
  # Controls that must STAY as they are:
  assert_bash "MA control: install -d .env (dir-create, accepted fail-open) ALLOWED" "0" 'install -d .env'
  assert_bash "MA control: cp -t d a .env (target-dir relocation, fail-open) ALLOWED" "0" 'cp -t d a .env'
}

# ---------------------------------------------------------------------------
# MA-resource-bounds (mini-audit R1): the round-3 perf fix removed the O(n^2)
# OUTPUT accumulation but left O(n^2) INPUT re-slicing (`${s:$i}` tail-slices in
# the byte loops). A sub-cap command with DENSE trigger bytes (quotes/separators)
# still stalls (measured 30KB separators = 21s, 65KB quotes = 49.5s) — the raw
# 64KiB length cap is calibrated on the wrong measure (length, not trigger
# density). This guards that a dense-trigger sub-(length-)cap command does NOT
# hang; the fix bounds cost on trigger count (fail-open per INV-007) or removes
# the re-slicing.
# ---------------------------------------------------------------------------
test_ma_dense_trigger_no_hang() {
  echo ""
  echo "=== MA: dense-trigger command must not hang (residual O(n^2) guard) ==="
  local dense cmd json rc
  # ~24KB of dense single-quote spans + a real redirect so the prefilter fires
  # and the masker runs over the whole thing.
  dense="$(printf "'x' %.0s" $(seq 1 6000))"
  cmd="$dense > .env"
  json="$(jq -nc --arg c "$cmd" '{tool_name:"Bash",tool_input:{command:$c}}')"
  printf '%s' "$json" | timeout 6 bash "$HOOK" >/dev/null 2>&1
  rc=$?
  if [ "$rc" = 124 ]; then
    fail "MA-resource" "hook hung (>6s) on a 24KB dense-quote command — residual O(n^2)"
  else
    pass "MA-resource" "hook completed on a 24KB dense-quote command (rc=$rc, no hang)"
  fi
}

# ---------------------------------------------------------------------------
# MA-R2 (mini-audit round 2): three further gaps in the destination grammar /
# cost model.
#   (1) `<>` read-write redirect (O_RDWR|O_CREAT) creates+writes a file but was
#       missing from both operator sites (same enumeration-drift class as &>>).
#   (2) A protected-path write whose payload is a large heredoc body fails open
#       — the heredoc body must NOT shield the structural `> dest` from
#       extraction (the body is inert content, extracted destination is O(1)).
#   (3) An operator-filled quoted span (`>`/`<` inside quotes) defeats the
#       masker's bulk-run fast path and is O(n^2); the cost gate must bound it.
# ---------------------------------------------------------------------------
test_ma_r2_readwrite_redirect_block() {
  echo ""
  echo "=== MA-R2: <> read-write redirect destinations block ==="
  assert_bash "MA-R2: echo data 1<> .env (read-write redirect) BLOCKED" "2" 'echo data 1<> .env'
  assert_bash "MA-R2: echo data <> .env (bare read-write) BLOCKED" "2" 'echo data <> .env'
  assert_bash "MA-R2: exec 3<> .env (read-write fd open) BLOCKED" "2" 'exec 3<> .env'
  # read-write to a sink is still allowed (INV-006)
  assert_bash "MA-R2: echo x 1<> /dev/null (sink) ALLOWED" "0" 'echo x 1<> /dev/null'
}

test_ma_r2_heredoc_body_does_not_shield() {
  echo ""
  echo "=== MA-R2: heredoc-body write to a protected path still blocks ==="
  # Small heredoc write: structural `cat > .env <<EOF` -> block.
  local hd
  hd=$'cat > .env <<EOF\nline with "quotes" and ;|& metachars\nmore content\nEOF'
  assert_bash "MA-R2: small heredoc write to .env BLOCKED" "2" "$hd"
  # LARGE heredoc body (>2048 trigger bytes) must NOT fail open — the body is
  # excised / not charged against the cost gate; the `> .env` is still extracted.
  local body line _
  line='x"y;z|w&v(q)#r'
  body=""
  for _ in $(seq 1 400); do body="$body$line"$'\n'; done   # ~5600 trigger bytes
  local hd2="cat > credentials.json <<EOF"$'\n'"$body"$'\n'"EOF"
  assert_bash "MA-R2: large-body heredoc write to credentials.json BLOCKED" "2" "$hd2"
  # comment-padded write (realistic size) blocks via the comment-aware masker
  assert_bash "MA-R2: echo x > .env # trailing comment BLOCKED" "2" 'echo x > .env # a trailing comment'
}

test_ma_r2_operator_filled_span_no_hang() {
  echo ""
  echo "=== MA-R2: operator-filled quoted span must not hang (O(n^2) guard) ==="
  local big cmd json rc
  # ~60KB of '>' inside a single quoted span + a real redirect. Currently O(n^2)
  # (the cost gate counts ~2 triggers and the 256KiB length backstop lets it
  # through). After the fix the cost gate bounds it (fail-open or fast).
  big="$(printf '>%.0s' $(seq 1 60000))"
  cmd="echo \"$big\" > .env"
  json="$(jq -nc --arg c "$cmd" '{tool_name:"Bash",tool_input:{command:$c}}')"
  printf '%s' "$json" | timeout 6 bash "$HOOK" >/dev/null 2>&1
  rc=$?
  if [ "$rc" = 124 ]; then
    fail "MA-R2-resource" "hook hung (>6s) on a 60KB operator-filled quoted span"
  else
    pass "MA-R2-resource" "hook completed on a 60KB operator-filled span (rc=$rc, no hang)"
  fi
}

# ---------------------------------------------------------------------------
# CLASS FIX (mini-audit): write-redirect-operator COMPLETENESS sweep. The
# operator accept-set is hand-maintained and drifted TWICE (&>> missed in R1,
# <> missed in R2) — the enumeration-incompleteness class (PMB-016/AP-036).
# This sweep is derived from the bash write-redirect grammar: every operator
# here was confirmed by a real-bash oracle to CREATE/WRITE its target file
# (`echo data <op> TGT` creates TGT). Each must therefore BLOCK when the target
# is a protected path. A future operator added to bash (or a regression dropping
# one from the accept-set) is caught here, not by an external adversarial fuzz.
# Source: real-bash differential oracle (gen: op-grammar.sh, 2026-06).
# ---------------------------------------------------------------------------
test_class_write_redirect_operator_completeness() {
  echo ""
  echo "=== CLASS: every bash write-redirect operator blocks a protected dest ==="
  local op
  for op in '>' '>>' '>|' '<>' '&>' '&>>' '>&' '1>' '2>' '1>>' '2>>' '1>|' '3>' '3>>' '1<>' '2<>'; do
    assert_bash "CLASS: echo data $op .env BLOCKED" "2" "echo data $op .env"
  done
}
# ===========================================================================
# Run
# ===========================================================================

echo "=== SFG re-scope tests (sfg-rescope spec) ==="
echo "Hook: $HOOK"

test_inv001_reads_invocations_not_targets
test_inv002_redirect_destinations_block
test_inv003_writer_destinations_block
test_inv004_git_worktree_allowed
test_inv005_interpreter_opaque
test_inv006_sink_devices_excluded
test_inv007_ambiguity_fails_open
test_inv007_structural_tripwire
test_inv008_input_parse_fails_closed
test_inv010_canonical_writer_destination
test_inv011_lib_functions_frozen
test_inv012_doc_coherence_no_perimeter
test_inv013_rule_carveout
test_inv014_blocked_message_guardrail
test_inv015_changelog_announced
test_inv016_prefilter_superset
test_inv017_half_a_newly_allowed
test_inv017_half_b_still_blocked
test_inv018_defaults_classes_block
test_inv018_structural_class_coverage
test_inv019_lc_all_c_structural
test_inv019_cross_locale_behavioral
test_inv020_per_segment_positional
test_qa001_quoted_and_comment_operators_not_targets
test_qa003_backslash_escape_context_parity
test_qa006_backslash_operator_parity_sweep
test_perf_large_command_no_hang
test_ma_append_both_redirect_block
test_ma_cp_d_flag_not_relocation
test_ma_dense_trigger_no_hang
test_ma_r2_readwrite_redirect_block
test_ma_r2_heredoc_body_does_not_shield
test_ma_r2_operator_filled_span_no_hang
test_class_write_redirect_operator_completeness

echo ""
echo "=== Summary ==="
echo "PASS: $PASS"
echo "FAIL: $FAIL"
[ "$SKIPPED" -gt 0 ] && echo "SKIPPED: $SKIPPED"
echo "TOTAL: $((PASS + FAIL))"
if [ "$FAIL" -gt 0 ]; then
  echo ""
  echo "RESULT: FAIL ($FAIL failures)"
  exit 1
else
  echo ""
  echo "RESULT: PASS (all $PASS tests passed)"
  exit 0
fi
