#!/usr/bin/env bash
# Correctless — coded outbound secret redactor (INV-013 / OQ-007).
#
# The SOLE redaction entrypoint for /cchores. Reads text on STDIN, writes the
# redacted text on STDOUT, replacing every match of every configured pattern
# with the literal <REDACTED>. Exit 0 on success.
#
# FAIL-CLOSED (INV-013): if NO pattern source can be found/read, the script
# exits NON-ZERO and emits EMPTY stdout — it never passes the input through
# unredacted (a fail-OPEN redactor would leak secrets to a public surface).
#
# Pattern-source precedence (pinned, ordered):
#   1. $REDACT_PATTERN_SOURCE env override, if set (used by tests + advanced cfg)
#   2. .correctless/config/gitleaks.toml      (regex patterns extracted from TOML)
#   3. .correctless/config/secret-patterns.txt (installed POSIX-ERE, one/line)
#   4. templates/secret-patterns.txt           (bundled fallback)
#
# Patterns are POSIX-ERE, one per line; '#' comments and blank lines ignored.
# Patterns are applied case-insensitively via `sed -E` with the GNU `I` flag.
#
# Shell discipline: fail-closed semantics, so `set -euo pipefail`. Uses only
# portable POSIX tools (grep -E / sed -E). No bashisms beyond arrays, which the
# project's bash shell provides.

set -euo pipefail

# ============================================
# STEP 1: Resolve the script's own location so the bundled fallback can be found
#         regardless of the caller's cwd.
# ============================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Repo/install root is the parent of scripts/.
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

GITLEAKS_TOML="$ROOT_DIR/.correctless/config/gitleaks.toml"
INSTALLED_PATTERNS="$ROOT_DIR/.correctless/config/secret-patterns.txt"
FALLBACK_PATTERNS="$ROOT_DIR/templates/secret-patterns.txt"

# When invoked from an installed project the layout differs: the script lives at
# .correctless/scripts/redact-secrets.sh, so ROOT_DIR == .correctless and the
# config files sit beside it. Probe both layouts.
INSTALLED_PATTERNS_ALT="$ROOT_DIR/config/secret-patterns.txt"
GITLEAKS_TOML_ALT="$ROOT_DIR/config/gitleaks.toml"
FALLBACK_PATTERNS_ALT="$ROOT_DIR/templates/secret-patterns.txt"

# ============================================
# STEP 2: Select the pattern source per the pinned precedence.
# ============================================
PATTERN_SOURCE=""
SOURCE_KIND=""   # "toml" or "lines"

if [ -n "${REDACT_PATTERN_SOURCE:-}" ]; then
  # Explicit override always wins. It MUST exist and be readable, else fail
  # closed — an override pointing at a missing file is a misconfiguration, not a
  # reason to silently fall back (the caller asked for THAT source).
  if [ -f "$REDACT_PATTERN_SOURCE" ] && [ -r "$REDACT_PATTERN_SOURCE" ]; then
    PATTERN_SOURCE="$REDACT_PATTERN_SOURCE"
    case "$PATTERN_SOURCE" in
      *.toml) SOURCE_KIND="toml" ;;
      *)      SOURCE_KIND="lines" ;;
    esac
  else
    echo "redact-secrets: REDACT_PATTERN_SOURCE='$REDACT_PATTERN_SOURCE' not found or unreadable — failing closed" >&2
    exit 3
  fi
elif [ -f "$GITLEAKS_TOML" ] && [ -r "$GITLEAKS_TOML" ]; then
  PATTERN_SOURCE="$GITLEAKS_TOML"; SOURCE_KIND="toml"
elif [ -f "$GITLEAKS_TOML_ALT" ] && [ -r "$GITLEAKS_TOML_ALT" ]; then
  PATTERN_SOURCE="$GITLEAKS_TOML_ALT"; SOURCE_KIND="toml"
elif [ -f "$INSTALLED_PATTERNS" ] && [ -r "$INSTALLED_PATTERNS" ]; then
  PATTERN_SOURCE="$INSTALLED_PATTERNS"; SOURCE_KIND="lines"
elif [ -f "$INSTALLED_PATTERNS_ALT" ] && [ -r "$INSTALLED_PATTERNS_ALT" ]; then
  PATTERN_SOURCE="$INSTALLED_PATTERNS_ALT"; SOURCE_KIND="lines"
elif [ -f "$FALLBACK_PATTERNS" ] && [ -r "$FALLBACK_PATTERNS" ]; then
  PATTERN_SOURCE="$FALLBACK_PATTERNS"; SOURCE_KIND="lines"
elif [ -f "$FALLBACK_PATTERNS_ALT" ] && [ -r "$FALLBACK_PATTERNS_ALT" ]; then
  PATTERN_SOURCE="$FALLBACK_PATTERNS_ALT"; SOURCE_KIND="lines"
fi

# FAIL-CLOSED: no resolvable source -> non-zero exit, empty stdout.
if [ -z "$PATTERN_SOURCE" ]; then
  echo "redact-secrets: no pattern source found (checked \$REDACT_PATTERN_SOURCE, .correctless/config/gitleaks.toml, .correctless/config/secret-patterns.txt, templates/secret-patterns.txt) — failing closed" >&2
  exit 2
fi

# ============================================
# STEP 3: Load patterns into an array.
#   - "lines": POSIX-ERE, one per line, strip '#' comments + blank/whitespace.
#   - "toml":  extract the RHS of `regex = '...'` / `regex = "..."` (single- or
#              triple-quoted) gitleaks rule entries.
# ============================================
PATTERNS=()

if [ "$SOURCE_KIND" = "lines" ]; then
  while IFS= read -r raw || [ -n "$raw" ]; do
    # Strip leading/trailing whitespace.
    line="$(printf '%s' "$raw" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
    # Skip blank lines and full-line comments.
    case "$line" in
      ''|\#*) continue ;;
    esac
    PATTERNS+=("$line")
  done < "$PATTERN_SOURCE"
else
  # gitleaks TOML: pull regex = '''...''' | "..." | '...'. Triple-quoted first.
  while IFS= read -r rx || [ -n "$rx" ]; do
    [ -z "$rx" ] && continue
    PATTERNS+=("$rx")
  done < <(
    sed -nE "s/^[[:space:]]*regex[[:space:]]*=[[:space:]]*'''(.*)'''[[:space:]]*$/\1/p; \
             s/^[[:space:]]*regex[[:space:]]*=[[:space:]]*\"(.*)\"[[:space:]]*$/\1/p;   \
             s/^[[:space:]]*regex[[:space:]]*=[[:space:]]*'([^']*)'[[:space:]]*$/\1/p"   \
      "$PATTERN_SOURCE"
  )
fi

# A source that resolved but yielded zero usable patterns is also fail-closed:
# redacting against an empty pattern set would silently pass everything through.
if [ "${#PATTERNS[@]}" -eq 0 ]; then
  echo "redact-secrets: pattern source '$PATTERN_SOURCE' contained zero usable patterns — failing closed" >&2
  exit 4
fi

# ============================================
# STEP 3b: Validate every pattern is genuinely POSIX-ERE (MA-S7).
#   gitleaks.toml is an advertised pattern source, but its patterns are written
#   in the PCRE dialect (`\d`, `\w`, `\s`, `(?i)`/`(?s)` inline flags,
#   `(?=...)`/`(?!...)` lookarounds, non-greedy `*?`/`+?`). These are NOT POSIX
#   ERE. Two failure modes must both be caught:
#     1. HARD compile error — `sed -E`/`grep -E` rejects the pattern.
#     2. SILENT misapplication — GNU grep/sed leniently ACCEPT `\d`/`(?i)` but
#        interpret them as literals (`\d` => literal 'd'), so the pattern
#        UNDER-redacts. A pure "does it compile?" check misses this class.
#   To keep "advertised gitleaks.toml support" HONEST we fail closed on BOTH:
#   any PCRE-only construct OR any pattern that does not compile as ERE.
# ============================================
# PCRE-only construct probe. ERE has no inline-flag/lookaround `(?...)` groups,
# no `\d`/`\w`/`\s`/`\D`/`\W`/`\S` shorthands, and no lazy `*?`/`+?`/`??`/`{m,n}?`
# quantifiers. Any of these means the pattern was authored for PCRE, not ERE.
pcre_only_construct() {
  local p="$1"
  case "$p" in
    *'(?'*) return 0 ;;            # inline flags / lookarounds / named groups
    *'\d'*|*'\D'*) return 0 ;;
    *'\w'*|*'\W'*) return 0 ;;
    *'\s'*|*'\S'*) return 0 ;;
  esac
  # Lazy quantifiers: a quantifier immediately followed by '?'.
  if printf '%s' "$p" | grep -Eq -e '[*+?}]\?'; then
    return 0
  fi
  return 1
}

for pat in "${PATTERNS[@]}"; do
  if pcre_only_construct "$pat"; then
    echo "redact-secrets: pattern uses PCRE-only constructs unsupported by POSIX-ERE (\\d / \\w / \\s / (?...) / lazy quantifier): '$pat' — failing closed" >&2
    exit 5
  fi
  # `printf '' | grep -E "$pat"` compiles the regex without needing a match.
  # grep exits 1 (no match) on a valid pattern against empty input, and 2 on a
  # regex COMPILE error. We only treat exit >=2 as a compile failure. The
  # `|| grep_status=$?` form keeps `set -e` from aborting on the benign exit 1.
  # `-e "$pat"` so a pattern beginning with `-` (e.g. the PEM header) is not
  # mistaken for a grep option.
  grep_status=0
  printf '' | grep -E -e "$pat" >/dev/null 2>&1 || grep_status=$?
  if [ "$grep_status" -ge 2 ]; then
    echo "redact-secrets: pattern does not compile as POSIX-ERE: '$pat' — failing closed" >&2
    exit 5
  fi
done

# ============================================
# STEP 4: Read all of stdin, then apply each pattern's substitution over the
#   WHOLE buffer (MA-S2). A line-oriented engine (`sed` without -z) matches per
#   line, so a secret split across a newline — and ANY inherently multi-line
#   secret such as a PEM private key block — would pass through unredacted to a
#   public sink. We process the entire buffer as a single string so the dotall /
#   cross-newline match works.
#
#   Substitution delimiter: SOH (0x01) control byte — cannot appear in the
#   patterns (POSIX-ERE source text) nor in realistic egress prose, so it never
#   collides with the '/', '+', '=' characters present in the patterns.
#
#   Multiline mechanism precedence:
#     1. perl -0777  — slurp whole input; `(?i)`+`(?s)` make `.` cross newlines.
#                      Translate ERE patterns directly (perl regex is a PCRE
#                      superset of ERE for the constructs we accept). Preferred.
#     2. GNU sed -z  — null-separated => the whole buffer is one "line", so the
#                      `I` (case-insensitive) flag plus a newline-aware pattern
#                      span the buffer. Used when perl is unavailable.
#     3. portable awk fallback — read the whole record (RS set to a byte that
#                      cannot appear in text) and shell out per pattern is not
#                      portable; instead the final fallback applies sed -E per
#                      pattern over the buffer with explicit newline handling.
# ============================================

# Slurp stdin verbatim into a temp file (preserve embedded newlines exactly;
# command-substitution would strip trailing newlines and cannot hold NULs).
INPUT_FILE="$(mktemp)"
trap 'rm -f "$INPUT_FILE"' EXIT
cat > "$INPUT_FILE"

# Build the PEM-block span pattern. A PEM private key is ALWAYS multi-line; we
# redact the ENTIRE span from the BEGIN header through the END footer, not just
# the header line (MA-S2). This augments (does not replace) any line-oriented
# PEM-header pattern already present in the source.
PEM_BEGIN='-----BEGIN [A-Z ]*PRIVATE KEY-----'
PEM_END='-----END [A-Z ]*PRIVATE KEY-----'

redact_with_perl() {
  # Pass patterns as @ARGV after a sentinel; read text from the temp file via
  # -0777 slurp. (?is) => case-insensitive + dotall so `.` crosses newlines.
  perl -0777 -e '
    my $marker = "<REDACTED>";
    my $pem_begin = shift @ARGV;
    my $pem_end   = shift @ARGV;
    my $file      = shift @ARGV;
    my @pats      = @ARGV;
    local $/; open(my $fh, "<", $file) or exit 7;
    my $text = <$fh>; close($fh);
    # PEM multi-line span first: BEGIN ... END, non-greedy, dotall + case-insens.
    # $pem_begin/$pem_end are themselves ERE; embed them as regex, not literal.
    my $span = "(?is)$pem_begin.*?$pem_end";
    $text =~ s/$span/$marker/g;
    for my $p (@pats) {
      $text =~ s/(?i)$p/$marker/g;
    }
    print $text;
  ' -- "$PEM_BEGIN" "$PEM_END" "$INPUT_FILE" "${PATTERNS[@]}"
}

redact_with_sed_z() {
  # GNU sed -z: the whole buffer is one NUL-terminated record, so a pattern can
  # span newlines and the `I` flag applies case-insensitively across it.
  local out
  out="$(cat "$INPUT_FILE")"
  # PEM span first. With -z the buffer is one record but `.` still does not match
  # a newline, so we span with `(.|\n)*` to cross the multi-line key body. The
  # match is greedy; in practice one PEM block per body, so greedy is fine.
  out="$(printf '%s' "$out" \
    | sed -zE "s${DELIM}${PEM_BEGIN}(.|\n)*${PEM_END}${DELIM}<REDACTED>${DELIM}gI" 2>/dev/null || printf '%s' "$out")"
  for pat in "${PATTERNS[@]}"; do
    out="$(printf '%s' "$out" \
      | sed -zE "s${DELIM}${pat}${DELIM}<REDACTED>${DELIM}gI")"
  done
  printf '%s' "$out"
}

DELIM="$(printf '\001')"

if command -v perl >/dev/null 2>&1; then
  OUTPUT="$(redact_with_perl)"
elif printf '' | sed -zE 's/x/y/' >/dev/null 2>&1; then
  # GNU sed with -z support.
  OUTPUT="$(redact_with_sed_z)"
else
  # Portable last-resort fallback: per-pattern sed over the buffer. This is
  # line-oriented for single-line patterns; the PEM span is handled by a tr-join
  # trick (collapse newlines to a sentinel, redact the span, restore). It is
  # strictly a degraded path for environments lacking both perl and GNU sed -z.
  OUTPUT="$(cat "$INPUT_FILE")"
  # Join lines on a SUB (0x1a) sentinel so the PEM span pattern can match across
  # original newlines, then restore the surviving newlines.
  SENT="$(printf '\032')"
  joined="$(printf '%s' "$OUTPUT" | tr '\n' "$SENT")"
  joined="$(printf '%s' "$joined" \
    | sed -E "s${DELIM}${PEM_BEGIN}[^${DELIM}]*${PEM_END}${DELIM}<REDACTED>${DELIM}gI" 2>/dev/null || printf '%s' "$joined")"
  OUTPUT="$(printf '%s' "$joined" | tr "$SENT" '\n')"
  for pat in "${PATTERNS[@]}"; do
    OUTPUT="$(printf '%s' "$OUTPUT" \
      | sed -E "s${DELIM}${pat}${DELIM}<REDACTED>${DELIM}gI")"
  done
fi

printf '%s' "$OUTPUT"
exit 0
