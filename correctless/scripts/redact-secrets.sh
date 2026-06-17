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
# STEP 4: Read all of stdin, then apply each pattern's substitution in turn.
#   Substitution delimiter: SOH (0x01) control byte — cannot appear in the
#   patterns (POSIX-ERE source text) nor in realistic egress prose, so it never
#   collides with the '/', '+', '=' characters present in the patterns.
# ============================================
DELIM="$(printf '\001')"

# Slurp stdin verbatim (preserve embedded newlines; command-substitution strips
# only the trailing newline, which is acceptable for egress bodies).
INPUT="$(cat)"

OUTPUT="$INPUT"
for pat in "${PATTERNS[@]}"; do
  # `I` flag (GNU sed) makes the match case-insensitive so PASSWORD=, Token:,
  # etc. all redact. `g` replaces every occurrence on every line.
  OUTPUT="$(printf '%s' "$OUTPUT" \
    | sed -E "s${DELIM}${pat}${DELIM}<REDACTED>${DELIM}gI")"
done

printf '%s' "$OUTPUT"
exit 0
