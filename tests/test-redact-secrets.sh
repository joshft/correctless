#!/usr/bin/env bash
# Correctless — Outbound Secret Redactor Tests
# Tests spec rules from .correctless/specs/cchores.md
#   INV-013  (Outbound redaction, coded, fail-closed)
#   OQ-007   (pinned minimum pattern set + "test tracks the file" AP-031 guard)
#
# RED PHASE (TDD): the implementation `scripts/redact-secrets.sh` and the
# bundled fallback pattern set `templates/secret-patterns.txt` do NOT exist
# yet — every assertion below is expected to FAIL now. The STUB:TDD comments
# mark behavior that GREEN must satisfy.
#
# Run from repo root: bash tests/test-redact-secrets.sh

# shellcheck disable=SC1090,SC1091,SC2034

source "$(dirname "${BASH_SOURCE[0]}")/test-helpers.sh"

# ============================================
# SETUP: paths under test
# ============================================

# STUB:TDD — these paths are the INV-013 contract; GREEN creates them.
REDACTOR="$REPO_DIR/scripts/redact-secrets.sh"            # the coded redactor
FALLBACK_PATTERNS="$REPO_DIR/templates/secret-patterns.txt" # bundled fallback (POSIX-ERE, one per line)
# Installed location per INV-013 source precedence:
#   (1) .correctless/config/gitleaks.toml if present, ELSE
#   (2) templates/secret-patterns.txt installed to .correctless/config/secret-patterns.txt
INSTALLED_PATTERNS="$REPO_DIR/.correctless/config/secret-patterns.txt"
GITLEAKS_TOML="$REPO_DIR/.correctless/config/gitleaks.toml"

REDACTION_MARKER="<REDACTED>"

# Resolve the pattern source the redactor will actually consume, per the pinned
# precedence. Used only by the "enumerate every line" coverage guard.
resolve_pattern_source() {
  if [ -f "$GITLEAKS_TOML" ]; then
    echo "$GITLEAKS_TOML"
  elif [ -f "$INSTALLED_PATTERNS" ]; then
    echo "$INSTALLED_PATTERNS"
  elif [ -f "$FALLBACK_PATTERNS" ]; then
    echo "$FALLBACK_PATTERNS"
  else
    echo ""
  fi
}

# Run the redactor with the given stdin; capture stdout, stderr, exit code into
# globals R_OUT / R_ERR / R_CODE. Returns the exit code.
run_redactor() {
  local input="$1"
  local tmp_out tmp_err
  tmp_out="$(mktemp)"
  tmp_err="$(mktemp)"
  printf '%s' "$input" | bash "$REDACTOR" >"$tmp_out" 2>"$tmp_err"
  R_CODE=$?
  R_OUT="$(cat "$tmp_out")"
  R_ERR="$(cat "$tmp_err")"
  rm -f "$tmp_out" "$tmp_err"
  return $R_CODE
}

# Assert that a secret sample, when piped through the redactor, is replaced by
# <REDACTED> AND that no raw byte of the secret survives on stdout.
assert_redacts() {
  local id="$1" desc="$2" sample="$3"
  if [ ! -x "$REDACTOR" ]; then
    fail "$id" "$desc (scripts/redact-secrets.sh not found or not executable)"
    return
  fi
  run_redactor "$sample"
  if [ "$R_CODE" -ne 0 ]; then
    fail "$id" "$desc (redactor exited $R_CODE on a valid input)"
    return
  fi
  case "$R_OUT" in
    *"$sample"*)
      fail "$id" "$desc (raw secret survived on stdout: '$R_OUT')"
      return
      ;;
  esac
  case "$R_OUT" in
    *"$REDACTION_MARKER"*)
      pass "$id" "$desc"
      ;;
    *)
      fail "$id" "$desc (no $REDACTION_MARKER in output: '$R_OUT')"
      ;;
  esac
}

# ============================================
# INV-013 [unit]: script existence + executability + API contract
# ============================================

section "INV-013: redactor existence and executable bit"

# Tests INV-013 [unit]: scripts/redact-secrets.sh exists and is executable.
if [ -f "$REDACTOR" ]; then
  pass "INV013-EXISTS" "scripts/redact-secrets.sh exists"
else
  fail "INV013-EXISTS" "scripts/redact-secrets.sh not found"
fi

# Tests INV-013 [unit]: the redactor is executable.
if [ -x "$REDACTOR" ]; then
  pass "INV013-EXEC" "scripts/redact-secrets.sh is executable"
else
  fail "INV013-EXEC" "scripts/redact-secrets.sh is not executable (chmod +x)"
fi

section "INV-013: API contract — stdin in, redacted stdout out, exit 0"

# Tests INV-013 [unit]: clean (non-secret) text passes through unchanged, exit 0.
if [ -x "$REDACTOR" ]; then
  CLEAN_INPUT="This issue describes a null-pointer crash in parse() at line 42."
  run_redactor "$CLEAN_INPUT"
  if [ "$R_CODE" -eq 0 ] && [ "$R_OUT" = "$CLEAN_INPUT" ]; then
    pass "INV013-PASSTHROUGH" "clean text passes through unchanged, exit 0"
  else
    fail "INV013-PASSTHROUGH" "clean text not preserved (exit=$R_CODE, out='$R_OUT')"
  fi
else
  fail "INV013-PASSTHROUGH" "scripts/redact-secrets.sh not found — cannot exercise passthrough"
fi

# Tests INV-013 [unit]: redactor reads stdin (empty stdin → exit 0, empty out).
if [ -x "$REDACTOR" ]; then
  run_redactor ""
  if [ "$R_CODE" -eq 0 ]; then
    pass "INV013-STDIN-EMPTY" "empty stdin yields exit 0"
  else
    fail "INV013-STDIN-EMPTY" "empty stdin should exit 0 (got $R_CODE)"
  fi
else
  fail "INV013-STDIN-EMPTY" "scripts/redact-secrets.sh not found"
fi

# ============================================
# INV-013 [integration]: fail-closed when pattern source is missing
# ============================================

section "INV-013: fail-closed on missing/unreadable pattern source"

# Tests INV-013 [integration]: when the pattern source is MISSING/unreadable,
# the redactor exits NON-ZERO and emits EMPTY stdout — it must NOT pass text
# through unredacted (a fail-OPEN redactor would leak secrets to GitHub).
#
# We exercise this by invoking the redactor with the pattern source path forced
# to a non-existent file. The contract: the redactor honors an override of its
# source location (env var or arg) OR — at minimum — when no source exists at
# any of the pinned precedence paths it fails closed.
#
# STUB:TDD: GREEN must support pointing the redactor at an explicit pattern
# source so this isolation test does not depend on deleting the real installed
# file. Convention assumed: REDACT_PATTERN_SOURCE env var overrides precedence.
# DECISION: chose an env-var override (REDACT_PATTERN_SOURCE) over deleting the
# real config because tests must not mutate tracked repo files. If GREEN uses a
# different override mechanism, update this single block — the contract under
# test (non-zero exit + empty stdout on missing source) is unchanged.
if [ -x "$REDACTOR" ]; then
  MISSING_SRC="$(mktemp -u)/definitely-not-here.txt"
  tmp_out="$(mktemp)"; tmp_err="$(mktemp)"
  printf '%s' "secret token here: ghp_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" \
    | REDACT_PATTERN_SOURCE="$MISSING_SRC" bash "$REDACTOR" >"$tmp_out" 2>"$tmp_err"
  fc_code=$?
  fc_out="$(cat "$tmp_out")"
  rm -f "$tmp_out" "$tmp_err"
  if [ "$fc_code" -ne 0 ] && [ -z "$fc_out" ]; then
    pass "INV013-FAILCLOSED" "missing pattern source: non-zero exit AND empty stdout"
  elif [ "$fc_code" -eq 0 ]; then
    fail "INV013-FAILCLOSED" "FAILED OPEN: exited 0 with a missing pattern source"
  else
    fail "INV013-FAILCLOSED" "non-zero exit but stdout NOT empty: '$fc_out' (would leak text)"
  fi
else
  fail "INV013-FAILCLOSED" "scripts/redact-secrets.sh not found — cannot test fail-closed"
fi

# Tests INV-013 [integration]: a missing source must NEVER echo the input back.
# Explicit anti-passthrough assertion distinct from the empty-stdout check above,
# because a redactor could conceivably write a banner to stdout yet still leak.
if [ -x "$REDACTOR" ]; then
  MISSING_SRC2="$(mktemp -u)/nope.txt"
  SENTINEL="AKIAIOSFODNN7EXAMPLE"
  tmp_out="$(mktemp)"
  printf '%s' "$SENTINEL" \
    | REDACT_PATTERN_SOURCE="$MISSING_SRC2" bash "$REDACTOR" >"$tmp_out" 2>/dev/null
  fc2_out="$(cat "$tmp_out")"
  rm -f "$tmp_out"
  case "$fc2_out" in
    *"$SENTINEL"*)
      fail "INV013-FAILCLOSED-NOLEAK" "FAILED OPEN: raw secret reached stdout on missing source"
      ;;
    *)
      pass "INV013-FAILCLOSED-NOLEAK" "missing source never echoes the input secret"
      ;;
  esac
else
  fail "INV013-FAILCLOSED-NOLEAK" "scripts/redact-secrets.sh not found"
fi

# ============================================
# INV-013: pattern source precedence (pinned)
# ============================================

section "INV-013: pattern source precedence + bundled fallback presence"

# Tests INV-013 [unit]: a bundled fallback pattern set ships in templates/.
if [ -f "$FALLBACK_PATTERNS" ]; then
  pass "INV013-FALLBACK-SHIPS" "templates/secret-patterns.txt bundled fallback exists"
else
  fail "INV013-FALLBACK-SHIPS" "templates/secret-patterns.txt not found (bundled fallback missing)"
fi

# Tests INV-013 [unit]: fallback file is POSIX-ERE, one pattern per non-comment line.
# We assert it is non-empty after stripping comments/blank lines.
if [ -f "$FALLBACK_PATTERNS" ]; then
  pat_count="$(grep -cE '^[[:space:]]*[^#[:space:]]' "$FALLBACK_PATTERNS" 2>/dev/null || echo 0)"
  if [ "${pat_count:-0}" -ge 6 ]; then
    pass "INV013-FALLBACK-NONEMPTY" "fallback has >=6 active patterns ($pat_count)"
  else
    fail "INV013-FALLBACK-NONEMPTY" "fallback should carry the >=6 pinned patterns (found $pat_count)"
  fi
else
  fail "INV013-FALLBACK-NONEMPTY" "templates/secret-patterns.txt not found"
fi

# Tests OQ-007 [structural / QA-003 class guard]: the shipped JWT pattern must
# carry the spec-pinned per-segment floor {8,}, not a relaxed {7,} fitted to a
# test sample. This fails loudly if the floor ever drifts off the spec value,
# catching the "relax the pattern to satisfy the test" inversion (spec divergence).
if [ -f "$FALLBACK_PATTERNS" ]; then
  jwt_line="$(grep -E '^[[:space:]]*eyJ\[' "$FALLBACK_PATTERNS" 2>/dev/null || true)"
  if [ -z "$jwt_line" ]; then
    fail "INV013-JWT-FLOOR" "no JWT (eyJ...) pattern line found in templates/secret-patterns.txt"
  elif grep -qF '{8,}' <<<"$jwt_line" && ! grep -qE '\{[0-7],' <<<"$jwt_line"; then
    pass "INV013-JWT-FLOOR" "JWT pattern carries the spec-pinned {8,} per-segment floor (OQ-007)"
  else
    fail "INV013-JWT-FLOOR" "JWT pattern floor drifted off the spec-pinned {8,}: '$jwt_line'"
  fi
else
  fail "INV013-JWT-FLOOR" "templates/secret-patterns.txt not found — cannot verify JWT floor"
fi

# ============================================
# INV-013 / OQ-007 [integration]: canonical secret shapes are redacted
# Each pinned shape is driven through stdin; assert <REDACTED> replacement
# and that no raw secret bytes survive.
# ============================================

section "OQ-007: canonical secret shapes redact (pinned minimum set)"

# Tests OQ-007 [integration]: AWS access key id  AKIA[0-9A-Z]{16}
assert_redacts "OQ007-AWS" "AWS access key id is redacted" \
  "AWS key AKIAIOSFODNN7EXAMPLE leaked in the log"

# Tests OQ-007 [integration]: generic secret/token/password/api_key assignment >=16 chars
assert_redacts "OQ007-GENERIC-SECRET" "generic secret= assignment redacted" \
  "secret = 'abcdef0123456789ABCDEF'"  # gitleaks:allow (test fixture, fake secret)
assert_redacts "OQ007-GENERIC-TOKEN" "generic token: assignment redacted" \
  "token: aZ09aZ09aZ09aZ09aZ09"
assert_redacts "OQ007-GENERIC-PASSWORD" "generic password= assignment redacted" \
  "password=SuperSecretValue123456"
assert_redacts "OQ007-GENERIC-APIKEY" "generic api_key= assignment redacted" \
  "api_key = \"k3y_abcdefABCDEF0123456789\""

# Tests OQ-007 [integration]: private key PEM header  -----BEGIN ... PRIVATE KEY-----
assert_redacts "OQ007-PEM-RSA" "RSA private key PEM header redacted" \
  "-----BEGIN RSA PRIVATE KEY-----"  # gitleaks:allow
assert_redacts "OQ007-PEM-EC" "EC private key PEM header redacted" \
  "-----BEGIN EC PRIVATE KEY-----"
assert_redacts "OQ007-PEM-PLAIN" "generic private key PEM header redacted" \
  "-----BEGIN PRIVATE KEY-----"  # gitleaks:allow

# Tests OQ-007 [integration]: JWT  eyJ... three dot-delimited base64url segments
assert_redacts "OQ007-JWT" "JWT three-segment token redacted" \
  "auth: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dozjgNryP4J3jVmNHl0w5N_XgL0n3I9PlFUP0THsR8U"  # gitleaks:allow

# Tests OQ-007 [integration]: GitHub token  gh[pousr]_ + 36+ chars
assert_redacts "OQ007-GH-GHP" "GitHub ghp_ token redacted" \
  "GITHUB_TOKEN=ghp_0123456789abcdefABCDEF0123456789abcd"  # gitleaks:allow
assert_redacts "OQ007-GH-GHO" "GitHub gho_ token redacted" \
  "oauth gho_0123456789abcdefABCDEF0123456789abcd"  # gitleaks:allow

# Tests OQ-007 [integration]: Slack token  xox[baprs]-...
assert_redacts "OQ007-SLACK" "Slack xoxb- token redacted" \
  "slack=xoxb-1234567890-abcdefABCDEF"

# ============================================
# OQ-007 / AP-031: "test tracks the file" — enumerate EVERY pattern line in the
# installed source and assert a synthesized minimal match redacts.
# This is the guard that coverage never lags the shipped pattern set.
# ============================================

section "OQ-007 / AP-031: every pattern in the source has a redaction test"

# Synthesize a minimal matching sample for a given POSIX-ERE pattern line.
# Known pinned patterns get hand-built canonical samples (the regex itself is
# hard to invert generically); unknown/added patterns fall back to a heuristic
# that strips ERE metacharacters to produce a literal-ish probe. If GREEN adds
# a pattern this heuristic cannot satisfy, the test FAILS loudly — which is the
# intended AP-031 behavior (coverage must not silently lag).
synthesize_sample() {
  local pat="$1"
  case "$pat" in
    *AKIA*)                       echo "AKIAIOSFODNN7EXAMPLE" ;;
    *PRIVATE\ KEY*)                 echo "-----BEGIN RSA PRIVATE KEY-----" ;;
    # JWT: the spec-pinned floor (OQ-007) is {8,} base64url chars PER segment.
    # Synthesize a sample whose FIRST segment carries >=8 chars after the eyJ
    # prefix (eyJ + 8 = eyJhbGciOiJI) and whose 2nd/3rd segments are each >=8
    # chars, so the enumeration guard exercises the restored {8,} pattern.
    *eyJ*)                        echo "eyJhbGciOiJIUzI.eyJzdWIiOiIxMjM.dozjgNryP4J3jVm" ;;
    *gh*_*|*"gh[pousr]"*)         echo "ghp_0123456789abcdefABCDEF0123456789abcd" ;;  # gitleaks:allow
    *xox*)                        echo "xoxb-1234567890-abcdefABCDEF" ;;
    *secret*|*token*|*password*|*passwd*|*api*key*)
                                  echo "secret=abcdef0123456789ABCDEF" ;;  # gitleaks:allow
    *)
      # Heuristic: drop ERE metacharacters and quantifier braces; if a literal
      # core of >=4 chars remains, use it as the probe, else mark unsatisfiable.
      local core
      core="$(printf '%s' "$pat" \
        | sed -E 's/\([^)]*\)//g; s/\{[0-9,]*\}//g; s/\[[^]]*\]//g; s/[\\^$.*+?|]//g' \
        | tr -cd 'A-Za-z0-9_/+=-')"
      if [ "${#core}" -ge 4 ]; then
        echo "$core""abcdef0123456789ABCDEF"
      else
        echo "__UNSYNTHESIZABLE__"
      fi
      ;;
  esac
}

PAT_SRC="$(resolve_pattern_source)"
if [ -z "$PAT_SRC" ] || [ ! -f "$PAT_SRC" ]; then
  fail "OQ007-ENUM-SOURCE" "no installed/bundled pattern source resolvable (expected templates/secret-patterns.txt or .correctless/config/*)"
elif [ ! -x "$REDACTOR" ]; then
  fail "OQ007-ENUM-SOURCE" "scripts/redact-secrets.sh not found — cannot enumerate-and-drive patterns"
else
  pass "OQ007-ENUM-SOURCE" "resolved pattern source: ${PAT_SRC#"$REPO_DIR"/}"
  line_no=0
  # gitleaks.toml is TOML; the line-enumeration guard targets the POSIX-ERE
  # one-per-line fallback format. If the source is the TOML config, we still
  # require the fallback file to exist and enumerate THAT (the shipped contract).
  ENUM_FILE="$PAT_SRC"
  case "$PAT_SRC" in
    *.toml) ENUM_FILE="$FALLBACK_PATTERNS" ;;
  esac
  if [ ! -f "$ENUM_FILE" ]; then
    fail "OQ007-ENUM-FILE" "enumeration file $ENUM_FILE missing"
  else
    while IFS= read -r raw_line || [ -n "$raw_line" ]; do
      # Skip blank lines and comments.
      case "$raw_line" in
        ''|\#*|[[:space:]]*\#*) continue ;;
      esac
      # Trim leading/trailing whitespace.
      line="$(printf '%s' "$raw_line" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
      [ -z "$line" ] && continue
      line_no=$((line_no + 1))
      sample="$(synthesize_sample "$line")"
      if [ "$sample" = "__UNSYNTHESIZABLE__" ]; then
        fail "OQ007-ENUM-L${line_no}" "cannot synthesize a sample for pattern: $line (extend synthesize_sample)"
        continue
      fi
      assert_redacts "OQ007-ENUM-L${line_no}" "pattern line ${line_no} redacts a matching sample" "$sample"
    done < "$ENUM_FILE"

    if [ "$line_no" -eq 0 ]; then
      fail "OQ007-ENUM-COUNT" "pattern source contained zero active patterns to enumerate"
    else
      pass "OQ007-ENUM-COUNT" "enumerated $line_no active pattern line(s) from the source"
    fi
  fi
fi

# ============================================
# INV-013 [integration]: multi-secret + embedded-in-prose redaction
# (egress bodies carry secrets inside surrounding text)
# ============================================

section "INV-013: multiple secrets in one body all redact"

# Tests INV-013 [integration]: a body with several secret shapes redacts ALL of
# them and leaks none — mirrors a real PR/comment body passing through the sink.
if [ -x "$REDACTOR" ] && { [ -f "$INSTALLED_PATTERNS" ] || [ -f "$FALLBACK_PATTERNS" ] || [ -f "$GITLEAKS_TOML" ]; }; then
  MULTI="Stack trace mentions AKIAIOSFODNN7EXAMPLE and token=abcdef0123456789ABCDEF and ghp_0123456789abcdefABCDEF0123456789abcd"  # gitleaks:allow
  run_redactor "$MULTI"
  leaked=0
  for s in "AKIAIOSFODNN7EXAMPLE" "abcdef0123456789ABCDEF" "ghp_0123456789abcdefABCDEF0123456789abcd"; do  # gitleaks:allow
    case "$R_OUT" in *"$s"*) leaked=1 ;; esac
  done
  if [ "$R_CODE" -eq 0 ] && [ "$leaked" -eq 0 ]; then
    pass "INV013-MULTI" "all secrets in a mixed body redacted, none leaked"
  else
    fail "INV013-MULTI" "mixed body leaked a secret or non-zero exit (exit=$R_CODE, out='$R_OUT')"
  fi
else
  fail "INV013-MULTI" "redactor or pattern source absent — cannot test mixed body"
fi

# ============================================
summary "test-redact-secrets"
