#!/usr/bin/env bash
# shellcheck disable=SC1090,SC1091,SC2016,SC2086
# Correctless — Architecture Drift Tests
# Enforces the path-scoped-rules-pat001 spec invariants:
#   INV-001..011, INV-016..027 (INV-012/013/014 reclassified to MG-001..003;
#   INV-015 is a manual canary procedure, NOT merge-time testable; INV-022
#   idempotency is a GREEN-phase shell fixture, deferred — see comment below.)
#
# Run from repo root: bash tests/test-architecture-drift.sh
#
# This is the dogfood test for Feature A of the rules-canonical /
# ARCHITECTURE.md index pattern. The test must use only POSIX-portable
# external tools (grep/sed/awk) — no GNU extensions. Bash 4+ constructs
# are permitted (EA-001).
#
# INV-015 NOTE: The canary verification of Claude Code's .claude/rules/
# loading mechanism is a manual procedure executed by the operator and
# recorded in .correctless/verification/path-scoped-rules-pat001-canary.md.
# It is NOT enforceable at merge time and is intentionally not checked here.
# See spec INV-015 for the procedure.
#
# INV-022 NOTE: Migration idempotency is a GREEN-phase shell fixture
# (see DD/PRH discussion in spec). It diffs the result of running the
# migration twice — that is the GREEN agent's job, not a merge-time
# drift check. This file does not enforce INV-022 directly.

source "$(dirname "${BASH_SOURCE[0]}")/test-helpers.sh"

# ============================================================================
# Bootstrap — source scripts/lib.sh for repo_root (INV-020 / ABS-001)
# Do NOT locally re-implement repo_root, branch_slug, classify_file, etc.
# ============================================================================

LIB_SH="$REPO_DIR/scripts/lib.sh"

if [ ! -f "$LIB_SH" ]; then
  echo "FATAL: scripts/lib.sh not found at $LIB_SH" >&2
  exit 2
fi

# shellcheck source=../scripts/lib.sh
. "$LIB_SH"

REPO_ROOT="$(repo_root)"

# ============================================================================
# Constants — file paths
# ============================================================================

ARCH_FILE=".correctless/ARCHITECTURE.md"
RULE_FILE=".claude/rules/hooks-pretooluse.md"
CLAUDE_MD="CLAUDE.md"
README_MD="README.md"
SYNC_SH="sync.sh"
CI_YAML=".github/workflows/ci.yml"
LOCAL_RUNNER="tests/test.sh"
CSTATUS_SKILL="skills/cstatus/SKILL.md"
MEASUREMENT_META=".correctless/meta/pat001-measurement-due.json"

EXPECTED_RULE_COMMENT="# Rule: .claude/rules/hooks-pretooluse.md (PAT-001 — fail-closed posture)"
EXPECTED_DOGFOOD_MARKER="DOGFOOD: Correctless-internal rule. Do not copy as a user-project template"

# ============================================================================
# Drift-detection functions — take a file path argument so they can be
# invoked against synthetic fixtures from the negative-case harness.
# ============================================================================

# ----------------------------------------------------------------------------
# check_architecture_shape ARCH_FILE
# ----------------------------------------------------------------------------
# Awk state-machine parser. For each `### PAT-NNN:` section in ARCH_FILE:
#   - Skip fenced code blocks (``` lines toggle state).
#   - End the section at the next `### ` or `## ` heading or EOF.
#   - Do NOT end the section at `#### ` (sub-headings).
#   - A section is "migrated" iff its body contains a real (non-fenced)
#     See-link line of the form: See `.claude/rules/<file>.md`.
#   - For migrated sections: assert there are exactly two non-blank,
#     non-comment lines — the heading and the See-link line. Anything
#     else (bullets, paragraphs, code blocks, sub-headings) is a violation.
#   - Emit "migrated sections checked: N" on stderr (positive-case anchor).
#   - On unclassifiable input, fail-closed (BND-001).
#
# Exit 0 if all migrated sections pass; non-zero otherwise.
# Diagnostics on stderr.
check_architecture_shape() {
  local file="$1"
  if [ ! -f "$file" ]; then
    echo "check_architecture_shape: ERROR: file not found: $file" >&2
    return 1
  fi

  awk '
    BEGIN {
      in_fence = 0
      in_section = 0
      migrated_count = 0
      violations = 0
      cur_pat = ""
      cur_nonblank = 0
      cur_has_see = 0
    }

    # Toggle fenced code block state on lines that start with ```.
    /^```/ {
      in_fence = 1 - in_fence
      if (in_section) {
        # Code block lines inside a section count as content for the
        # shape check (a migrated section may not contain code blocks).
        cur_nonblank++
        cur_lines[cur_nonblank] = $0
      }
      next
    }

    # Section terminator: ### PAT- or ## (level-2) or any other ### heading.
    # Specifically NOT terminated by #### (sub-headings).
    {
      # Detect a section boundary BEFORE processing the line.
      is_pat_heading = 0
      is_terminator = 0
      if (!in_fence) {
        if ($0 ~ /^### PAT-[0-9][0-9]*:/) {
          is_pat_heading = 1
          is_terminator = 1
        } else if ($0 ~ /^### [^#]/) {
          is_terminator = 1
        } else if ($0 ~ /^## [^#]/) {
          is_terminator = 1
        }
      }

      if (is_terminator && in_section) {
        # Close out the current section.
        finalize_section()
        in_section = 0
      }

      if (is_pat_heading) {
        # Open a new PAT section.
        in_section = 1
        cur_pat = $0
        cur_nonblank = 1
        delete cur_lines
        cur_lines[1] = $0
        cur_has_see = 0
        next
      }

      if (in_section) {
        # Skip blank lines.
        if ($0 ~ /^[[:space:]]*$/) {
          next
        }
        cur_nonblank++
        cur_lines[cur_nonblank] = $0
        # Detect a real See-link line (only outside fenced code blocks).
        # Pattern: starts with optional whitespace, then "See `.claude/rules/...md`."
        # We require backticks AND the trailing period to match the spec
        # exactly. Inside a fenced block, in_fence is 1 so we skip.
        if (in_fence == 0 && $0 ~ /^[[:space:]]*See `\.claude\/rules\/[^`]+\.md`\./) {
          cur_has_see = 1
        }
      }
    }

    END {
      if (in_section) finalize_section()
      # Emit positive-case anchor on stderr.
      printf("migrated sections checked: %d\n", migrated_count) | "cat 1>&2"
      close("cat 1>&2")
      if (violations > 0) exit 1
      exit 0
    }

    function finalize_section(   i, body_lines) {
      if (cur_has_see != 1) {
        # Non-migrated section — shape check does not apply.
        return
      }
      migrated_count++
      # cur_nonblank includes the heading line as line 1.
      # Migrated sections must have exactly 2 non-blank lines: heading + See-link.
      if (cur_nonblank != 2) {
        printf("INV-003 SHAPE VIOLATION: %s has %d non-blank lines, expected exactly 2 (heading + See-link)\n", cur_pat, cur_nonblank) | "cat 1>&2"
        for (i = 1; i <= cur_nonblank; i++) {
          printf("    line %d: %s\n", i, cur_lines[i]) | "cat 1>&2"
        }
        close("cat 1>&2")
        violations++
        return
      }
      # Verify line 2 is the See-link itself (not some other line).
      if (cur_lines[2] !~ /^[[:space:]]*See `\.claude\/rules\/[^`]+\.md`\.[[:space:]]*$/) {
        printf("INV-003 MALFORMED See-link in %s: %s\n", cur_pat, cur_lines[2]) | "cat 1>&2"
        close("cat 1>&2")
        violations++
      }
    }
  ' "$file"
}

# ----------------------------------------------------------------------------
# strip_shell_comments [FILE]
# ----------------------------------------------------------------------------
# Emit every line from FILE (or stdin if no arg) except lines whose first
# non-whitespace character is `#`. Used by INV-007 (tests/test.sh + ci.yml
# run-block comment stripping) and INV-024 (sync.sh comment stripping) so
# the "strip comment-only lines" idiom lives in exactly one place. The
# self-scan at INV-010 uses a more elaborate heredoc-aware parser and does
# not share this helper.
strip_shell_comments() {
  awk '
    {
      tmp = $0
      sub(/^[[:space:]]+/, "", tmp)
      if (substr(tmp, 1, 1) == "#") next
      print
    }
  ' "$@"
}

# ----------------------------------------------------------------------------
# extract_see_link_paths FILE
# ----------------------------------------------------------------------------
# Emit one path per line for every `See `.claude/rules/{file}.md`.` occurrence
# in FILE, skipping fenced code blocks. Used by check_see_link_targets (for
# target-existence checks) and check_inv005 (for frontmatter checks) so both
# callers share the same parser — any change to the See-link grammar lives
# in exactly one place.
extract_see_link_paths() {
  awk '
    BEGIN { in_fence = 0 }
    /^```/ { in_fence = 1 - in_fence; next }
    {
      if (in_fence) next
      if (match($0, /See `\.claude\/rules\/[^`]+\.md`\./)) {
        line = substr($0, RSTART, RLENGTH)
        sub(/^See `/, "", line)
        sub(/`\.$/, "", line)
        print line
      }
    }
  ' "$1"
}

# ----------------------------------------------------------------------------
# check_see_link_targets ARCH_FILE
# ----------------------------------------------------------------------------
# For every See-link line outside fenced code blocks, verify the target
# file exists at the path relative to repo root via [ -f ]. [ -f ] follows
# symlinks; broken symlinks fail.
check_see_link_targets() {
  local file="$1"
  if [ ! -f "$file" ]; then
    echo "check_see_link_targets: ERROR: file not found: $file" >&2
    return 1
  fi
  local missing=0
  local paths
  paths="$(extract_see_link_paths "$file")"
  if [ -z "$paths" ]; then
    return 0
  fi
  while IFS= read -r p; do
    [ -z "$p" ] && continue
    if [ ! -f "$p" ]; then
      if [ -L "$p" ]; then
        echo "INV-004 BROKEN SYMLINK: See-link target is a broken symlink: $p" >&2
      else
        echo "INV-004 MISSING TARGET: See-link target does not exist: $p" >&2
      fi
      missing=$((missing + 1))
    fi
  done <<EOF_PATHS
$paths
EOF_PATHS
  [ "$missing" -eq 0 ]
}

# ----------------------------------------------------------------------------
# check_rule_frontmatter RULE_FILE
# ----------------------------------------------------------------------------
# Per BND-003: line 1 must be exactly "---" (LF only, no \r).
# Closing "---" must appear within the first 20 lines.
# A `paths:` key must appear inside the frontmatter block.
check_rule_frontmatter() {
  local file="$1"
  if [ ! -f "$file" ]; then
    echo "INV-005 MISSING RULE FILE: $file" >&2
    return 1
  fi
  # Read first line in a portable way and detect CRLF.
  local first_line
  first_line="$(sed -n '1p' "$file")"
  case "$first_line" in
    "---") : ;;
    *)
      echo "INV-005 BAD FRONTMATTER START: line 1 of $file is not '---' (got: '$first_line')" >&2
      return 1
      ;;
  esac
  # Check for CRLF in the first line by inspecting the raw byte length.
  # If the displayed line is "---" but the raw line includes \r, the awk
  # length check below will reveal it.
  local raw_len
  raw_len="$(awk 'NR==1 {print length($0); exit}' "$file")"
  if [ "$raw_len" != "3" ]; then
    echo "INV-005 BAD FRONTMATTER START: line 1 of $file has unexpected length $raw_len (CRLF?)" >&2
    return 1
  fi
  # Find closing --- within first 20 lines.
  local close_line
  close_line="$(awk 'NR>=2 && NR<=20 && /^---[[:space:]]*$/ {print NR; exit}' "$file")"
  if [ -z "$close_line" ]; then
    echo "INV-005 NO FRONTMATTER CLOSE: $file has no closing '---' within first 20 lines" >&2
    return 1
  fi
  # Look for ^paths: between line 2 and the closing line.
  local has_paths
  has_paths="$(awk -v end="$close_line" 'NR>=2 && NR<end && /^paths:/ {print "yes"; exit}' "$file")"
  if [ "$has_paths" != "yes" ]; then
    echo "INV-005 NO PATHS KEY: $file frontmatter has no 'paths:' key" >&2
    return 1
  fi
  return 0
}

# ----------------------------------------------------------------------------
# parse_paths_list RULE_FILE
# ----------------------------------------------------------------------------
# Parse the YAML `paths:` list from a rule file's frontmatter and emit
# one path per line. Supports both flow form `paths: [a, b]` and block
# form with `- entry` lines. Strips quotes.
parse_paths_list() {
  local file="$1"
  [ -f "$file" ] || return 1
  awk '
    BEGIN { state = 0; close_line = 0 }
    NR == 1 && /^---/ { state = 1; next }
    state == 1 && /^---/ { exit }
    state == 1 && /^paths:[[:space:]]*\[/ {
      # Flow form: paths: [a, b, c]
      line = $0
      sub(/^paths:[[:space:]]*\[/, "", line)
      sub(/\].*$/, "", line)
      n = split(line, parts, ",")
      for (i = 1; i <= n; i++) {
        s = parts[i]
        gsub(/^[[:space:]"\x27]+|[[:space:]"\x27]+$/, "", s)
        if (s != "") print s
      }
      next
    }
    state == 1 && /^paths:[[:space:]]*$/ {
      state = 2
      next
    }
    state == 2 && /^[[:space:]]+-[[:space:]]+/ {
      s = $0
      sub(/^[[:space:]]+-[[:space:]]+/, "", s)
      gsub(/^[[:space:]"\x27]+|[[:space:]"\x27]+$/, "", s)
      if (s != "") print s
      next
    }
    state == 2 && /^[^[:space:]]/ {
      state = 1
    }
  ' "$file"
}

# ----------------------------------------------------------------------------
# enumerate_pretooluse_hooks
# ----------------------------------------------------------------------------
# Emit one path per line for every hook in hooks/*.sh whose first 10 lines
# contain `# HOOK_TYPE: PreToolUse`. Paths are repo-root-relative.
enumerate_pretooluse_hooks() {
  local f
  for f in hooks/*.sh; do
    [ -f "$f" ] || continue
    if head -10 "$f" 2>/dev/null | grep -q '^# HOOK_TYPE: PreToolUse'; then
      echo "$f"
    fi
  done
}

# ============================================================================
# INV-001: Rule file exists with path-scoped frontmatter (set of two)
# ============================================================================

check_inv001() {
  if [ ! -f "$RULE_FILE" ]; then
    fail "INV-001" "rule file $RULE_FILE does not exist"
    return
  fi
  pass "INV-001(a)" "rule file exists"
  if ! check_rule_frontmatter "$RULE_FILE" 2>/dev/null; then
    fail "INV-001(b)" "rule file lacks valid YAML frontmatter with paths: key"
    return
  fi
  pass "INV-001(b)" "rule file has YAML frontmatter with paths: key"
  # Set equality: exactly the two expected paths.
  local got expected_a expected_b have_a have_b extra
  expected_a="hooks/workflow-gate.sh"
  expected_b="hooks/sensitive-file-guard.sh"
  got="$(parse_paths_list "$RULE_FILE" | sort -u)"
  have_a="$(echo "$got" | grep -cFx "$expected_a" || true)"
  have_b="$(echo "$got" | grep -cFx "$expected_b" || true)"
  extra="$(echo "$got" | grep -cvFx -e "$expected_a" -e "$expected_b" || true)"
  if [ "$have_a" = "1" ] && [ "$have_b" = "1" ] && [ "$extra" = "0" ]; then
    pass "INV-001(c)" "paths list contains exactly the two expected entries"
  else
    fail "INV-001(c)" "paths list mismatch (have_a=$have_a have_b=$have_b extra=$extra) — got: $got"
  fi
}

# ============================================================================
# INV-002: Rule file content sections present
# ============================================================================

check_inv002() {
  if [ ! -f "$RULE_FILE" ]; then
    fail "INV-002" "rule file missing — cannot check sections"
    return
  fi
  local body
  body="$(cat "$RULE_FILE")"

  # (a) full PAT-001 rule text — five clauses. A-004 fix: anchor every clause.
  # Substrings drawn verbatim from the current ARCHITECTURE.md PAT-001 body:
  #   Clause 1: "set -euo pipefail" + "set -f"
  #   Clause 2: "command -v jq" + "fail-closed exit 2"
  #   Clause 3: "bulk-parse stdin" + "jq -r @sh"
  #   Clause 4: "fast-path" + "BEFORE loading config"
  #   Clause 5: "exit 0 to allow" + "exit 2 to block"
  local c1_ok c2_ok c3_ok c4_ok c5_ok
  c1_ok=0; c2_ok=0; c3_ok=0; c4_ok=0; c5_ok=0
  # Clause 1
  if echo "$body" | grep -qF "set -euo pipefail" && echo "$body" | grep -qF "set -f"; then
    c1_ok=1
  fi
  # Clause 2
  if echo "$body" | grep -qF "command -v jq" && echo "$body" | grep -qF "fail-closed exit 2"; then
    c2_ok=1
  fi
  # Clause 3 — two non-adjacent substrings from verbatim text.
  if echo "$body" | grep -qF "bulk-parse stdin" && echo "$body" | grep -qF "jq -r @sh"; then
    c3_ok=1
  fi
  # Clause 4 — two substrings from verbatim text.
  if echo "$body" | grep -qF "fast-path" && echo "$body" | grep -qF "BEFORE loading config"; then
    c4_ok=1
  fi
  # Clause 5
  if echo "$body" | grep -qF "exit 0 to allow" && echo "$body" | grep -qF "exit 2 to block"; then
    c5_ok=1
  fi
  if [ "$c1_ok" = "1" ] && [ "$c2_ok" = "1" ] && [ "$c3_ok" = "1" ] \
     && [ "$c4_ok" = "1" ] && [ "$c5_ok" = "1" ]; then
    pass "INV-002(a)" "rule body contains all five clause anchors (1-5)"
  else
    fail "INV-002(a)" "rule body missing clause anchors (c1=$c1_ok c2=$c2_ok c3=$c3_ok c4=$c4_ok c5=$c5_ok)"
  fi

  # (b) "Violated when" list naming clause-5 fail-open
  if echo "$body" | grep -qi "Violated when" \
     && echo "$body" | grep -qi "fail-open"; then
    pass "INV-002(b)" "rule body has 'Violated when' list naming fail-open"
  else
    fail "INV-002(b)" "rule body missing 'Violated when' list or fail-open mention"
  fi

  # (c) rationale section citing QA-R1-004 and QA-R1-005
  if echo "$body" | grep -qF "QA-R1-004" \
     && echo "$body" | grep -qF "QA-R1-005"; then
    pass "INV-002(c)" "rule body cites QA-R1-004 and QA-R1-005"
  else
    fail "INV-002(c)" "rule body missing QA-R1-004 / QA-R1-005 citations"
  fi

  # (d) Tests section referencing the three test files
  if echo "$body" | grep -qF "tests/test-sensitive-file-guard.sh" \
     && echo "$body" | grep -qF "tests/test-workflow-gate.sh" \
     && echo "$body" | grep -qF "tests/test-dynamic-rigor.sh"; then
    pass "INV-002(d)" "rule body references all three test files"
  else
    fail "INV-002(d)" "rule body missing one or more test file references"
  fi

  # (e) Related cross-references PAT-005 and PAT-006; NOT PAT-002 / TB-001a
  if echo "$body" | grep -qF "PAT-005" \
     && echo "$body" | grep -qF "PAT-006"; then
    if echo "$body" | grep -qF "PAT-002"; then
      fail "INV-002(e)" "rule body should NOT cross-reference PAT-002"
    elif echo "$body" | grep -qF "TB-001a"; then
      fail "INV-002(e)" "rule body should NOT cross-reference TB-001a"
    else
      pass "INV-002(e)" "rule body cross-references PAT-005 and PAT-006 only"
    fi
  else
    fail "INV-002(e)" "rule body missing PAT-005 / PAT-006 cross-references"
  fi
}

# ============================================================================
# INV-003: ARCHITECTURE.md PAT-001 entry matches index-line shape
# (Run the parser against the real ARCHITECTURE.md and assert success.)
# ============================================================================

check_inv003() {
  if [ ! -f "$ARCH_FILE" ]; then
    fail "INV-003" "$ARCH_FILE not found"
    return
  fi
  local out rc
  # Capture stderr: the parser emits "migrated sections checked: N" to stderr.
  out="$(check_architecture_shape "$ARCH_FILE" 2>&1)"
  rc=$?
  if [ "$rc" -ne 0 ]; then
    fail "INV-003" "shape check failed for $ARCH_FILE: $out"
    return
  fi
  # A-001 fix: require at least one migrated section, not zero (vacuous pass).
  if echo "$out" | grep -qE "migrated sections checked: [1-9][0-9]*"; then
    pass "INV-003" "ARCHITECTURE.md migrated PAT sections match index-line shape (>=1 checked)"
  else
    fail "INV-003" "ARCHITECTURE.md has zero migrated PAT sections (vacuous pass blocked): $out"
  fi

  # INV-003-real: awk-parse the real PAT-001 block out of ARCHITECTURE.md
  # and assert the body contains exactly ONE non-blank non-heading line
  # matching the exact See-link shape.
  local pat001_body see_count body_nonblank
  pat001_body="$(awk '
    BEGIN { in_fence = 0; in_sec = 0 }
    /^```/ { in_fence = 1 - in_fence; if (in_sec) print; next }
    {
      if (!in_fence) {
        if ($0 ~ /^### PAT-001:/) { in_sec = 1; next }
        if (in_sec && ($0 ~ /^### / || $0 ~ /^## /)) { exit }
      }
      if (in_sec) print
    }
  ' "$ARCH_FILE")"
  if [ -z "$pat001_body" ]; then
    fail "INV-003-real" "could not extract PAT-001 section body from $ARCH_FILE"
    return
  fi
  # Count non-blank non-heading lines, and count lines matching the exact See-link shape.
  body_nonblank="$(printf '%s\n' "$pat001_body" | awk '
    /^[[:space:]]*$/ { next }
    /^#/ { next }
    { print }
  ')"
  see_count="$(printf '%s\n' "$body_nonblank" | grep -cFx 'See `.claude/rules/hooks-pretooluse.md`.' || true)"
  local total_nonblank
  total_nonblank="$(printf '%s\n' "$body_nonblank" | grep -cv '^$' || true)"
  if [ "${see_count:-0}" -eq 1 ] && [ "${total_nonblank:-0}" -eq 1 ]; then
    pass "INV-003-real" "PAT-001 body is exactly one See-link line in canonical shape"
  else
    fail "INV-003-real" "PAT-001 body is not exactly one See-link line (see_count=$see_count, total_nonblank=$total_nonblank)"
  fi
}

# ============================================================================
# INV-004: All See-link targets exist
# ============================================================================

check_inv004() {
  if [ ! -f "$ARCH_FILE" ]; then
    fail "INV-004" "$ARCH_FILE not found"
    return
  fi
  local out rc
  out="$(check_see_link_targets "$ARCH_FILE" 2>&1)"
  rc=$?
  if [ "$rc" -eq 0 ]; then
    pass "INV-004" "all See-link targets exist"
  else
    fail "INV-004" "$out"
  fi
}

# ============================================================================
# INV-005: Referenced rule files have YAML frontmatter with paths: key
# ============================================================================

check_inv005() {
  if [ ! -f "$ARCH_FILE" ]; then
    fail "INV-005" "$ARCH_FILE not found"
    return
  fi
  local paths
  paths="$(extract_see_link_paths "$ARCH_FILE")"
  if [ -z "$paths" ]; then
    # Vacuously true: no See-links means no referenced rule files to check.
    # INV-001/003 will catch the absence of the migration itself.
    pass "INV-005" "no See-links in ARCHITECTURE.md (vacuous)"
    return
  fi
  local bad=0
  while IFS= read -r p; do
    [ -z "$p" ] && continue
    if ! check_rule_frontmatter "$p" 2>/dev/null; then
      bad=$((bad + 1))
    fi
  done <<EOF_P
$paths
EOF_P
  if [ "$bad" -eq 0 ]; then
    pass "INV-005" "all referenced rule files have valid frontmatter"
  else
    fail "INV-005" "$bad referenced rule file(s) lack valid frontmatter with paths: key"
  fi
}

# ============================================================================
# INV-006: Drift test fails closed on drift
# Verified indirectly via INV-011's negative-case harness.
# Here we just emit a marker.
# ============================================================================

check_inv006() {
  pass "INV-006" "fail-closed posture verified by INV-011 negative cases below"
}

# ============================================================================
# INV-007: Drift test wired into CI and local test runner
# ============================================================================

check_inv007() {
  local in_ci=0 in_local=0

  # A-003 fix: check tests/test.sh for an actual invocation (not a comment).
  if [ -f "$LOCAL_RUNNER" ]; then
    if strip_shell_comments "$LOCAL_RUNNER" | grep -qE '(bash|sh)[[:space:]]+tests/test-architecture-drift\.sh|\./tests/test-architecture-drift\.sh'; then
      in_local=1
    fi
  fi

  # A-003 fix: awk state machine to extract YAML "run:" block bodies, then
  # scan inside those blocks for a real invocation. Track the indent of the
  # run: line; anything at the same or lower indent that starts a new YAML
  # key closes the block.
  if [ -f "$CI_YAML" ]; then
    local ci_run_bodies
    ci_run_bodies="$(awk '
      function indent_of(line,   i, c) {
        for (i = 1; i <= length(line); i++) {
          c = substr(line, i, 1)
          if (c != " " && c != "\t") return i - 1
        }
        return length(line)
      }
      BEGIN { in_run = 0; run_indent = -1 }
      {
        if (in_run == 0) {
          # Look for a `run:` key with optional `|`.
          if ($0 ~ /^[[:space:]]*run:[[:space:]]*\|?[[:space:]]*$/) {
            in_run = 1
            run_indent = indent_of($0)
            next
          }
        } else {
          # Check if this line closes the run block.
          # A line closes the block if:
          #   - it is non-blank
          #   - its indent is <= run_indent
          #   - it begins a new YAML key (matches ^[space]*KEY:)
          if ($0 ~ /^[[:space:]]*$/) { print; next }
          cur_indent = indent_of($0)
          if (cur_indent <= run_indent && $0 ~ /^[[:space:]]*[a-zA-Z_-]+:/) {
            in_run = 0
            run_indent = -1
            next
          }
          # Otherwise we are still inside the run block body.
          print
        }
      }
    ' "$CI_YAML")"

    # Strip YAML comments from the extracted run-block bodies and grep for the invocation.
    if printf '%s\n' "$ci_run_bodies" | strip_shell_comments | grep -qF 'bash tests/test-architecture-drift.sh'; then
      in_ci=1
    fi
  fi

  if [ "$in_ci" = "1" ] && [ "$in_local" = "1" ]; then
    pass "INV-007" "drift test wired into both CI and local runner"
  else
    fail "INV-007" "drift test wiring missing (ci.yml=$in_ci, local=$in_local)"
  fi
}

# ============================================================================
# INV-008: CLAUDE.md PAT-001 references are accurate post-migration
# ============================================================================

# ----------------------------------------------------------------------------
# get_learning_entry_section HEADER_REGEX FILE
# ----------------------------------------------------------------------------
# Extract a CLAUDE.md Correctless Learnings entry as a multi-line block,
# delimited from HEADER_REGEX through the next `### ` / `## ` heading or EOF.
# Used by check_inv008 to scope citation checks to specific learning entries.
# The header regex must be an awk ERE (passed via -v).
get_learning_entry_section() {
  local header_regex="$1" file="$2"
  awk -v re="$header_regex" '
    BEGIN { in_sec = 0 }
    $0 ~ re { in_sec = 1; next }
    in_sec && /^### / { exit }
    in_sec && /^## / { exit }
    in_sec { print }
  ' "$file"
}

check_inv008() {
  if [ ! -f "$CLAUDE_MD" ]; then
    fail "INV-008" "$CLAUDE_MD not found"
    return
  fi

  # Note: the broader "PAT-001 + ARCHITECTURE.md on same line" scan in INV-018
  # already covers the old exact-phrase "See PAT-001 in `.correctless/ARCHITECTURE.md`"
  # for CLAUDE.md, so no dedicated sub-check for that phrase is needed here.

  # (b) 2026-04-07 PostToolUse learning preserves "Contrast with PAT-001" AND
  # cites the rule file in its parenthetical.
  local posttool_section
  posttool_section="$(get_learning_entry_section \
    '^### 2026-04-07 — Convention confirmed: PostToolUse hook structure' \
    "$CLAUDE_MD")"
  if printf '%s\n' "$posttool_section" | grep -qF "Contrast with PAT-001" \
     && printf '%s\n' "$posttool_section" | grep -qF ".claude/rules/hooks-pretooluse.md"; then
    pass "INV-008(b)" "2026-04-07 PostToolUse learning preserves 'Contrast with PAT-001' and cites rule file"
  else
    fail "INV-008(b)" "2026-04-07 PostToolUse learning entry malformed (contrast intact? rule cite?)"
  fi

  # (c) A-006 fix: both the 2026-04-05 PreToolUse and 2026-04-07 PostToolUse
  # learning entries must each cite the rule file. Scoped to the specific
  # learning-entry section (not anywhere in CLAUDE.md).
  local pretool_section
  pretool_section="$(get_learning_entry_section \
    '^### 2026-04-05 — Convention confirmed: PreToolUse hook structure' \
    "$CLAUDE_MD")"
  local pretool_cites posttool_cites
  pretool_cites="$(printf '%s\n' "$pretool_section" | grep -cF "See \`.claude/rules/hooks-pretooluse.md\`" || true)"
  posttool_cites="$(printf '%s\n' "$posttool_section" | grep -cF "See \`.claude/rules/hooks-pretooluse.md\`" || true)"
  if [ "${pretool_cites:-0}" -ge 1 ] && [ "${posttool_cites:-0}" -ge 1 ]; then
    pass "INV-008(c)" "2026-04-05 and 2026-04-07 learning entries each cite the rule file"
  else
    fail "INV-008(c)" "learning-entry citations missing (pretool=$pretool_cites posttool=$posttool_cites)"
  fi
}

# ============================================================================
# INV-009: README Defense in Depth has exactly 4 tiers (no L5)
# ============================================================================

check_inv009() {
  if [ ! -f "$README_MD" ]; then
    fail "INV-009" "$README_MD not found"
    return
  fi
  # A-002 fix: extract the Defense-in-Depth mermaid block using an awk state
  # machine — strictly between ```mermaid and the next ``` — then scan only
  # within that block. Solid-vs-dashed visual distinction is verified by
  # humans, not by this test.
  local mermaid_blocks
  mermaid_blocks="$(awk '
    BEGIN { in_block = 0; block_count = 0 }
    /^```mermaid[[:space:]]*$/ {
      in_block = 1
      block_count++
      printf("\n===BLOCK-%d===\n", block_count)
      next
    }
    in_block && /^```[[:space:]]*$/ { in_block = 0; next }
    in_block { print }
  ' "$README_MD")"

  if [ -z "$mermaid_blocks" ]; then
    fail "INV-009(a)" 'README has no mermaid code blocks — cannot validate Defense in Depth'
    check_inv009_prose
    return
  fi

  # Find the Defense-in-Depth block — the one containing all four tier labels.
  local did_block
  did_block="$(printf '%s\n' "$mermaid_blocks" | awk '
    BEGIN { cur = ""; buf = "" }
    /^===BLOCK-/ {
      if (cur != "" && buf ~ /Gate/ && buf ~ /Audit/ && buf ~ /[Pp]ath-scoped/ && buf ~ /[Ss]kill/) {
        print buf
        exit
      }
      cur = $0
      buf = ""
      next
    }
    { buf = buf $0 "\n" }
    END {
      if (buf ~ /Gate/ && buf ~ /Audit/ && buf ~ /[Pp]ath-scoped/ && buf ~ /[Ss]kill/) {
        print buf
      }
    }
  ')"

  if [ -z "$did_block" ]; then
    fail "INV-009(a)" "Defense-in-Depth mermaid block not found (missing one of: Gate, Audit, Path-scoped, Skill)"
    check_inv009_prose
    return
  fi

  # Within the identified block, require each label to appear inside a
  # Mermaid node declaration (brackets of form [...], (...), or ((...))).
  local gate_ok audit_ok path_ok skill_ok
  gate_ok="$(printf '%s' "$did_block" | grep -cE '[\[(][^])]*Gate[^])]*[])]' || true)"
  audit_ok="$(printf '%s' "$did_block" | grep -cE '[\[(][^])]*Audit([[:space:]]+Trail)?[^])]*[])]' || true)"
  path_ok="$(printf '%s' "$did_block" | grep -cE '[\[(][^])]*[Pp]ath-scoped([[:space:]]+rules)?[^])]*[])]' || true)"
  skill_ok="$(printf '%s' "$did_block" | grep -cE '[\[(][^])]*[Ss]kill([[:space:]]+[Ii]nstructions)?[^])]*[])]' || true)"

  # No L5 node and no CLAUDE.md node inside the block.
  local no_l5=1 no_claudemd=1
  if printf '%s' "$did_block" | grep -qE '[\[(][^])]*Layer[[:space:]]*5[^])]*[])]|[\[(][^])]*L5[^])]*[])]'; then
    no_l5=0
  fi
  if printf '%s' "$did_block" | grep -qE '[\[(][^])]*CLAUDE\.md[^])]*[])]'; then
    no_claudemd=0
  fi

  # At least one arrow in the block.
  local has_arrow=0
  if printf '%s' "$did_block" | grep -qE -- '-->|-\.->'; then
    has_arrow=1
  fi

  if [ "${gate_ok:-0}" -ge 1 ] && [ "${audit_ok:-0}" -ge 1 ] \
     && [ "${path_ok:-0}" -ge 1 ] && [ "${skill_ok:-0}" -ge 1 ] \
     && [ "$no_l5" -eq 1 ] && [ "$no_claudemd" -eq 1 ] \
     && [ "$has_arrow" -eq 1 ]; then
    pass "INV-009(a)" "README mermaid has 4 tier node labels (Gate, Audit, Path-scoped, Skill), no L5, no CLAUDE.md, has arrows"
  else
    fail "INV-009(a)" "README mermaid block labels: Gate=$gate_ok Audit=$audit_ok Path=$path_ok Skill=$skill_ok no_l5=$no_l5 no_claudemd=$no_claudemd arrow=$has_arrow"
  fi

  check_inv009_prose
}

# ----------------------------------------------------------------------------
# check_inv009_prose
# ----------------------------------------------------------------------------
# INV-009(b): README prose outside mermaid blocks must say "four independent
# layers" and must not say "three independent layers". Extracted from
# check_inv009 so the parent function can use early-return guards for the
# mermaid-block checks without duplicating the prose assertion at each exit
# path.
check_inv009_prose() {
  # Prose check — scoped to README body OUTSIDE the mermaid blocks.
  local readme_prose
  readme_prose="$(awk '
    BEGIN { in_block = 0 }
    /^```mermaid[[:space:]]*$/ { in_block = 1; next }
    in_block && /^```[[:space:]]*$/ { in_block = 0; next }
    !in_block { print }
  ' "$README_MD")"
  if printf '%s' "$readme_prose" | grep -qF "four independent layers" \
     && ! printf '%s' "$readme_prose" | grep -qF "three independent layers"; then
    pass "INV-009(b)" "README prose says 'four independent layers' (not 'three')"
  else
    fail "INV-009(b)" "README prose has wrong layer count (expected 'four', not 'three')"
  fi
}

# ============================================================================
# INV-010 / INV-020: Self-check — POSIX portability + lib.sh sourcing
# ============================================================================

check_inv010_self_scan() {
  local self="${BASH_SOURCE[0]}"
  # Strip comment-only lines and heredoc bodies; then scan for forbidden patterns.
  # Forbidden patterns (literal substrings or simple regexes):
  #   grep -P
  #   sed -i '' (BSD style without backup arg) — distinct from sed -i which can be portable with arg
  #   gensub(
  #   PROCINFO
  # And forbidden lib.sh local re-definitions:
  #   repo_root() {  branch_slug() {  classify_file() {  config_file() {
  #   artifacts_dir() {  read_patterns() {  read_intensity() {
  #   _has_write_pattern() {  get_target_file() {  locked_update_state() {

  local stripped
  stripped="$(awk '
    BEGIN { in_heredoc = 0; heredoc_tag = "" }
    {
      # Detect heredoc start: <<EOF or <<-EOF or <<"EOF" etc.
      if (in_heredoc == 0 && match($0, /<<-?[[:space:]]*[A-Za-z_][A-Za-z0-9_]*/)) {
        tag = substr($0, RSTART, RLENGTH)
        sub(/^<<-?[[:space:]]*/, "", tag)
        heredoc_tag = tag
        in_heredoc = 1
        # Print the line itself (the marker) to keep line counts; the body is suppressed
        print
        next
      }
      if (in_heredoc == 1) {
        # Check for end-of-heredoc
        line = $0
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
        if (line == heredoc_tag) {
          in_heredoc = 0
          heredoc_tag = ""
        }
        next
      }
      # Strip pure comment lines (lines whose first non-whitespace is #)
      tmp = $0
      sub(/^[[:space:]]+/, "", tmp)
      if (substr(tmp, 1, 1) == "#") next
      print
    }
  ' "$self")"

  local bad=0
  if echo "$stripped" | grep -qF 'grep -P'; then
    fail "INV-010" "self-scan: forbidden 'grep -P' usage"
    bad=1
  fi
  # GNU awk extensions
  if echo "$stripped" | grep -qF 'gensub('; then
    fail "INV-010" "self-scan: forbidden 'gensub(' (GNU awk extension)"
    bad=1
  fi
  if echo "$stripped" | grep -qF 'PROCINFO'; then
    fail "INV-010" "self-scan: forbidden 'PROCINFO' (GNU awk extension)"
    bad=1
  fi
  # sed -i without backup arg is BSD-incompatible. We tolerate sed -i.bak / sed -i ''.
  # We DON'T tolerate naked `sed -i ` followed by an expression.
  if echo "$stripped" | grep -qE "sed[[:space:]]+-i[[:space:]]+['\"]?[a-zA-Z]"; then
    fail "INV-010" "self-scan: forbidden 'sed -i' without backup arg (non-portable)"
    bad=1
  fi

  # Lib.sh function re-definitions
  local lib_funcs
  lib_funcs="repo_root branch_slug classify_file config_file artifacts_dir read_patterns read_intensity _has_write_pattern get_target_file locked_update_state _acquire_state_lock _release_state_lock"
  for fn in $lib_funcs; do
    # L5 fix: match both POSIX-style `funcname() {` / `funcname () {` AND
    # the bash-keyword form `function funcname {` / `function funcname() {`
    # at start of line. Project convention uses the POSIX form exclusively
    # but the check should not miss a future deviation.
    if echo "$stripped" | grep -qE "^${fn}[[:space:]]*\\(\\)[[:space:]]*\\{" \
       || echo "$stripped" | grep -qE "^function[[:space:]]+${fn}([[:space:]]*\\(\\))?[[:space:]]*\\{"; then
      fail "INV-020" "self-scan: forbidden local re-definition of lib.sh function: $fn"
      bad=1
    fi
  done

  # Verify the file actually sources lib.sh
  if grep -qE '^[[:space:]]*\.[[:space:]]+"\$\{?LIB_SH' "$self" \
     || grep -qE '^[[:space:]]*source[[:space:]]+"\$\{?LIB_SH' "$self"; then
    pass "INV-020" "test file sources scripts/lib.sh"
  else
    fail "INV-020" "test file does NOT source scripts/lib.sh"
    bad=1
  fi

  if [ "$bad" -eq 0 ]; then
    pass "INV-010" "self-scan: no GNU-only extensions found"
  fi
}

# ============================================================================
# INV-011: Negative-case harness (8 cases) + positive-case anchor
# ============================================================================

FIXTURE_DIR="$REPO_ROOT/.correctless/artifacts/drift-test-fixtures"

cleanup_fixtures() {
  if [ -n "${FIXTURE_DIR:-}" ] && [ -d "$FIXTURE_DIR" ]; then
    rm -rf "$FIXTURE_DIR"
  fi
}
trap cleanup_fixtures EXIT INT TERM

run_negative_cases() {
  echo ""
  echo "=== INV-011: Negative-case verification ==="
  mkdir -p "$FIXTURE_DIR" || {
    fail "INV-011" "cannot create fixture dir $FIXTURE_DIR"
    return
  }

  local case_file out rc

  # ----------------------------------------------------------------
  # Case 1: Migrated section with extra body content (shape violation)
  # ----------------------------------------------------------------
  case_file="$FIXTURE_DIR/case1-shape.md"
  cat > "$case_file" <<'EOF_C1'
## Patterns

### PAT-001: PreToolUse hook conventions
See `.claude/rules/hooks-pretooluse.md`.
- extra bullet that should not be here
- another bullet

### PAT-002: Some other pattern
- this is fine because it is not migrated
EOF_C1
  out="$(check_architecture_shape "$case_file" 2>&1)"
  rc=$?
  if [ "$rc" -ne 0 ] && echo "$out" | grep -qF "INV-003 SHAPE VIOLATION"; then
    pass "INV-011-case1" "shape violation detected (extra body content)"
  else
    fail "INV-011-case1" "shape violation not detected (rc=$rc, out=$out)"
  fi

  # ----------------------------------------------------------------
  # Case 2: See-link points at a nonexistent file
  # ----------------------------------------------------------------
  case_file="$FIXTURE_DIR/case2-broken.md"
  cat > "$case_file" <<'EOF_C2'
### PAT-001: PreToolUse hook conventions
See `.claude/rules/this-file-does-not-exist-xyz.md`.
EOF_C2
  out="$(check_see_link_targets "$case_file" 2>&1)"
  rc=$?
  if [ "$rc" -ne 0 ] && echo "$out" | grep -qF "INV-004"; then
    pass "INV-011-case2" "broken target detected"
  else
    fail "INV-011-case2" "broken target not detected (rc=$rc, out=$out)"
  fi

  # ----------------------------------------------------------------
  # Case 3: Rule file missing the `paths:` frontmatter
  # ----------------------------------------------------------------
  case_file="$FIXTURE_DIR/case3-no-frontmatter.md"
  cat > "$case_file" <<'EOF_C3'
# Some rule file
This file has no YAML frontmatter at all.
EOF_C3
  out="$(check_rule_frontmatter "$case_file" 2>&1)"
  rc=$?
  if [ "$rc" -ne 0 ] && echo "$out" | grep -qF "INV-005"; then
    pass "INV-011-case3a" "missing frontmatter detected"
  else
    fail "INV-011-case3a" "missing frontmatter not detected (rc=$rc, out=$out)"
  fi

  # Variant: has frontmatter but no paths: key
  case_file="$FIXTURE_DIR/case3-no-paths-key.md"
  cat > "$case_file" <<'EOF_C3B'
---
title: foo
description: bar
---
# body
EOF_C3B
  out="$(check_rule_frontmatter "$case_file" 2>&1)"
  rc=$?
  if [ "$rc" -ne 0 ] && echo "$out" | grep -qF "INV-005"; then
    pass "INV-011-case3b" "missing paths: key detected"
  else
    fail "INV-011-case3b" "missing paths: key not detected (rc=$rc, out=$out)"
  fi

  # ----------------------------------------------------------------
  # Case 4: Malformed See-link (no backticks)
  # ----------------------------------------------------------------
  # A-010: A malformed See-link is INTENTIONALLY classified as non-migrated
  # by the strict parser. This is the correct behavior: the parser only
  # recognizes the canonical "See `.claude/rules/...md`." form. Anything
  # else is treated as regular body content in a non-migrated section,
  # which means the shape check is not enforced for that section.
  # Case 5 (below) is the complementary false-positive guard: prose that
  # happens to contain the word "See" must not be treated as a See-link.
  # Together, these two cases bracket the strict-format behavior of the
  # parser from both directions.
  # The malformed See-link should NOT be classified as a migrated section,
  # so the section should be treated as non-migrated. But because the
  # heading is a PAT heading and there is body content, the parser should
  # NOT crash on it. We assert: shape parser passes (it does not see this
  # as migrated), AND that the See-link target check correctly does NOT
  # match the malformed line. The "drift" the spec describes is that the
  # malformed line escapes detection — so we test the parser is strict
  # about the format and does NOT treat this as a See-link.
  case_file="$FIXTURE_DIR/case4-malformed-see.md"
  cat > "$case_file" <<'EOF_C4'
### PAT-001: foo
See .claude/rules/foo.md without backticks
- some content
EOF_C4
  # The strict parser should NOT classify this as migrated, so the shape
  # check passes (no migrated sections to check). We invert: assert the
  # See-link target check finds zero links AND the section is not flagged
  # as migrated (zero migrated sections counted).
  out="$(check_architecture_shape "$case_file" 2>&1)"
  rc=$?
  if [ "$rc" -eq 0 ] && echo "$out" | grep -qF "migrated sections checked: 0"; then
    pass "INV-011-case4" "malformed See-link not classified as migrated (strict format)"
  else
    fail "INV-011-case4" "malformed See-link handling wrong (rc=$rc, out=$out)"
  fi

  # ----------------------------------------------------------------
  # Case 5: False-positive guard — non-migrated PAT with "See" prose
  # ----------------------------------------------------------------
  case_file="$FIXTURE_DIR/case5-prose-see.md"
  cat > "$case_file" <<'EOF_C5'
### PAT-002: Some pattern
- **Pattern**: Some words
- **Rule**: Do the thing. See the related table below.
- **Test**: foo
EOF_C5
  out="$(check_architecture_shape "$case_file" 2>&1)"
  rc=$?
  # Parser must NOT trigger on "See ..." prose. The non-migrated section
  # has body content but no real See-link, so it should pass.
  if [ "$rc" -eq 0 ] && echo "$out" | grep -qF "migrated sections checked: 0"; then
    pass "INV-011-case5" "false-positive 'See' prose not flagged"
  else
    fail "INV-011-case5" "false-positive 'See' prose triggered parser (rc=$rc, out=$out)"
  fi

  # ----------------------------------------------------------------
  # Case 6: Multi-migration fixture — first clean, second drifted
  # Parser must catch the second without short-circuiting on the first.
  # ----------------------------------------------------------------
  case_file="$FIXTURE_DIR/case6-multi.md"
  cat > "$case_file" <<'EOF_C6'
## Patterns

### PAT-001: First migration (clean)
See `.claude/rules/foo.md`.

### PAT-002: Second migration (drifted)
See `.claude/rules/bar.md`.
- this extra content makes the second migrated section invalid

### PAT-003: Third (unrelated)
- normal content
EOF_C6
  out="$(check_architecture_shape "$case_file" 2>&1)"
  rc=$?
  if [ "$rc" -ne 0 ] \
     && echo "$out" | grep -qF "INV-003 SHAPE VIOLATION" \
     && echo "$out" | grep -qF "PAT-002"; then
    pass "INV-011-case6" "multi-migration: second drifted section caught"
  else
    fail "INV-011-case6" "multi-migration drift not caught correctly (rc=$rc, out=$out)"
  fi

  # ----------------------------------------------------------------
  # Case 7 (F19): PAT section containing a #### sub-heading
  # Parser must NOT treat #### as a section boundary.
  # ----------------------------------------------------------------
  case_file="$FIXTURE_DIR/case7-subheading.md"
  cat > "$case_file" <<'EOF_C7'
### PAT-001: With sub-heading
See `.claude/rules/foo.md`.

#### Sub-heading inside the section
- this content belongs to PAT-001 and should make the shape check fail

### PAT-002: Next pattern
- normal
EOF_C7
  out="$(check_architecture_shape "$case_file" 2>&1)"
  rc=$?
  if [ "$rc" -ne 0 ] \
     && echo "$out" | grep -qF "INV-003 SHAPE VIOLATION" \
     && echo "$out" | grep -qF "PAT-001"; then
    pass "INV-011-case7" "F19 sub-heading: #### not treated as section boundary"
  else
    fail "INV-011-case7" "F19 sub-heading handling wrong (rc=$rc, out=$out)"
  fi

  # ----------------------------------------------------------------
  # Case 8 (F19): See-link example inside a fenced code block
  # Parser must skip fenced blocks.
  # ----------------------------------------------------------------
  case_file="$FIXTURE_DIR/case8-fenced.md"
  cat > "$case_file" <<'EOF_C8'
### PAT-001: Some pattern
- **Pattern**: foo
- **Rule**: bar
- **Example**: like this:
```
See `.claude/rules/example.md`.
```
- **Test**: baz
EOF_C8
  # The fenced See-link is NOT a real link. The section is not migrated.
  # Shape check should pass (zero migrated sections), AND the See-link
  # target check should find zero links.
  out="$(check_architecture_shape "$case_file" 2>&1)"
  rc=$?
  if [ "$rc" -eq 0 ] && echo "$out" | grep -qF "migrated sections checked: 0"; then
    pass "INV-011-case8a" "F19 fenced code block: See-link example not classified as migrated"
  else
    fail "INV-011-case8a" "F19 fenced handling wrong in shape check (rc=$rc, out=$out)"
  fi
  out="$(check_see_link_targets "$case_file" 2>&1)"
  rc=$?
  if [ "$rc" -eq 0 ]; then
    pass "INV-011-case8b" "F19 fenced code block: See-link target check skips fenced"
  else
    fail "INV-011-case8b" "F19 fenced target check wrong (rc=$rc, out=$out)"
  fi

  # ----------------------------------------------------------------
  # Positive case: clean fixture must emit "migrated sections checked: N>=1"
  # ----------------------------------------------------------------
  case_file="$FIXTURE_DIR/positive-clean.md"
  # Need a real target file for the See-link to point at.
  mkdir -p "$FIXTURE_DIR/.claude/rules"
  cat > "$FIXTURE_DIR/.claude/rules/positive.md" <<'EOF_RULE'
---
paths:
  - hooks/workflow-gate.sh
---
# Positive fixture rule file
EOF_RULE
  cat > "$case_file" <<'EOF_POS'
## Patterns

### PAT-001: Clean migrated entry
See `.claude/rules/positive.md`.

### PAT-002: Non-migrated
- normal content
EOF_POS
  out="$(check_architecture_shape "$case_file" 2>&1)"
  rc=$?
  if [ "$rc" -eq 0 ] && echo "$out" | grep -qE "migrated sections checked: [1-9][0-9]*"; then
    pass "INV-011-positive" "clean fixture emits 'migrated sections checked: N >= 1'"
  else
    fail "INV-011-positive" "positive-case anchor missing (rc=$rc, out=$out)"
  fi
}

# ============================================================================
# INV-016: Dormant /cstatus measurement-overdue check
# ============================================================================

check_inv016() {
  if [ ! -f "$CSTATUS_SKILL" ]; then
    fail "INV-016(a)" "$CSTATUS_SKILL not found"
  else
    if grep -qF "pat001-measurement-due.json" "$CSTATUS_SKILL" \
       && grep -qF "Measurement overdue" "$CSTATUS_SKILL"; then
      pass "INV-016(a)" "/cstatus has measurement-overdue check instructions"
    else
      fail "INV-016(a)" "/cstatus SKILL.md missing measurement-overdue check block"
    fi
  fi

  if [ -f "$MEASUREMENT_META" ]; then
    # A-012 fix: enforce exact numeric match for 3 (not 30/300) with a
    # trailing comma or closing brace.
    if grep -qE '"due_at_pr_count"[[:space:]]*:[[:space:]]*3[[:space:]]*[,}]' "$MEASUREMENT_META"; then
      pass "INV-016(b)" "$MEASUREMENT_META exists with due_at_pr_count: 3 (exact numeric)"
    else
      fail "INV-016(b)" "$MEASUREMENT_META exists but does not have exact due_at_pr_count: 3"
    fi
  else
    fail "INV-016(b)" "$MEASUREMENT_META does not exist"
  fi
}

# ============================================================================
# INV-017: Paths list set-equal to PreToolUse hook discovery
# ============================================================================

check_inv017() {
  if [ ! -f "$RULE_FILE" ]; then
    fail "INV-017" "rule file missing — cannot check set equality"
    return
  fi
  # A-011 fix: normalize both sides by stripping empty lines, then sort -u.
  # Compare with diff so trailing-newline / blank-line differences don't
  # produce a false positive.
  local hooks_set rule_set
  hooks_set="$(enumerate_pretooluse_hooks | grep -v '^$' | sort -u)"
  rule_set="$(parse_paths_list "$RULE_FILE" | grep -v '^$' | sort -u)"
  if diff <(printf '%s\n' "$hooks_set") <(printf '%s\n' "$rule_set") >/dev/null 2>&1; then
    pass "INV-017" "paths list set-equal to PreToolUse hook discovery"
  else
    fail "INV-017" "set inequality. hooks={$(printf '%s' "$hooks_set" | tr '\n' ',')} rule={$(printf '%s' "$rule_set" | tr '\n' ',')}"
  fi
}

# ============================================================================
# INV-018: Zero stale "PAT-001 in .correctless/ARCHITECTURE.md" refs
# across hooks/*.sh, tests/*.sh, and CLAUDE.md
# ============================================================================

check_inv018() {
  local hits=0 file self
  # Exclude this test file itself — it is the enforcer, not a consumer.
  # Its diagnostic messages and comment headers intentionally contain the
  # grep target substring.
  # L6 fix: derive self-path dynamically from BASH_SOURCE relative to the
  # repo root. Do not hardcode `tests/` — if the drift test is ever moved
  # (e.g., to tests/drift/), the self-exclusion would break silently and
  # the test file's own diagnostic strings would match as stale refs.
  local self_abs
  self_abs="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
  self="${self_abs#"$REPO_ROOT"/}"
  # A-005 fix: a broader pattern catches any line that co-mentions PAT-001
  # AND .correctless/ARCHITECTURE.md together (any phrasing), not just the
  # narrow "PAT-001 in ..." form.
  scan_file_for_stale() {
    local f="$1"
    if grep -qi 'pat-001 in \.correctless/architecture\.md' "$f"; then
      return 0
    fi
    if awk '/PAT-001/ && /\.correctless\/ARCHITECTURE\.md/' "$f" | grep -q .; then
      return 0
    fi
    return 1
  }
  for file in hooks/*.sh tests/*.sh; do
    [ -f "$file" ] || continue
    [ "$file" = "$self" ] && continue
    if scan_file_for_stale "$file"; then
      hits=$((hits + 1))
      echo "    INV-018 hit: $file" >&2
    fi
  done
  if [ -f "$CLAUDE_MD" ] && scan_file_for_stale "$CLAUDE_MD"; then
    hits=$((hits + 1))
    echo "    INV-018 hit: $CLAUDE_MD" >&2
  fi
  if [ "$hits" -eq 0 ]; then
    pass "INV-018" "no stale PAT-001 ARCHITECTURE.md references in hooks/tests/CLAUDE.md"
  else
    fail "INV-018" "$hits file(s) contain stale 'PAT-001 + ARCHITECTURE.md' references"
  fi
}

# ============================================================================
# INV-019: Rule file semantic integrity anchors
# ============================================================================

check_inv019() {
  if [ ! -f "$RULE_FILE" ]; then
    fail "INV-019" "rule file missing — cannot check semantic anchors"
    return
  fi
  local body
  body="$(cat "$RULE_FILE")"

  # (a) literal "exit 2 on unexpected input"
  if echo "$body" | grep -qF "exit 2 on unexpected input"; then
    pass "INV-019(a)" "rule body contains 'exit 2 on unexpected input' anchor"
  else
    fail "INV-019(a)" "rule body missing 'exit 2 on unexpected input' anchor"
  fi

  # Note: the QA-R1-004 / QA-R1-005 presence check lives in INV-002(c) —
  # no sub-check needed here to avoid duplication.

  # (c) A-007 fix: single-line co-occurrence of (persisted|persistence|persisting)
  # AND a 2024-2027 year AND (PR|PRs|pull request). Intent: pin the rule file
  # to the concrete baseline failure story, not just any prose mentioning
  # "persisted" near any random 4-digit number. Note: sub-letter (b) was
  # removed — the QA-R1 ID check lives in INV-002(c).
  local persist_year_ok
  persist_year_ok="$(awk '
    /[Pp]ersist(ed|ence|ing)/ && /20(24|25|26|27)/ && (/PR/ || /pull request/) { print "yes"; exit }
  ' "$RULE_FILE")"
  if [ "$persist_year_ok" = "yes" ]; then
    pass "INV-019(c)" "rule body has persistence+year+PR baseline-failure anchor on a single line"
  else
    fail "INV-019(c)" "rule body missing persistence+year(2024-2027)+PR anchor"
  fi

  # Prohibited substrings
  local prohibited=(
    "except in development"
    "unless \$"
    "can exit 0"
    "may exit 0"
    "weakened for debuggability"
  )
  local bad=0 p
  for p in "${prohibited[@]}"; do
    if echo "$body" | grep -qF "$p"; then
      fail "INV-019(d)" "rule body contains prohibited substring: '$p'"
      bad=1
    fi
  done
  if [ "$bad" -eq 0 ]; then
    pass "INV-019(d)" "rule body has no prohibited weakening substrings"
  fi
}

# ============================================================================
# INV-021: In-file rule pointer comments in scoped hook files
# ============================================================================

check_inv021() {
  if [ ! -f "$RULE_FILE" ]; then
    fail "INV-021" "rule file missing — cannot enumerate scoped files"
    return
  fi
  local paths bad=0
  paths="$(parse_paths_list "$RULE_FILE")"
  if [ -z "$paths" ]; then
    fail "INV-021" "rule file has empty paths list"
    return
  fi
  while IFS= read -r p; do
    [ -z "$p" ] && continue
    if [ ! -f "$p" ]; then
      fail "INV-021" "scoped file does not exist: $p"
      bad=1
      continue
    fi
    if head -20 "$p" 2>/dev/null | grep -qF "$EXPECTED_RULE_COMMENT"; then
      pass "INV-021" "$p has rule pointer comment"
    else
      fail "INV-021" "$p missing rule pointer comment '$EXPECTED_RULE_COMMENT' in first 20 lines"
      bad=1
    fi
  done <<EOF_PP
$paths
EOF_PP
}

# ============================================================================
# INV-023: Allowed-tools allowlist for Write(.claude/rules/...)
# Exactly cspec, cdocs, cupdate-arch.
# ============================================================================

check_inv023() {
  local sk hits found_set expected_set
  expected_set="skills/cdocs/SKILL.md skills/cspec/SKILL.md skills/cupdate-arch/SKILL.md"
  found_set=""
  for sk in skills/*/SKILL.md; do
    [ -f "$sk" ] || continue
    # A-008 fix: extract the YAML frontmatter block (first ^---$ to next ^---$)
    # and within it find the allowed-tools line or array. Grep the frontmatter
    # for Write(.claude/rules/ . If no frontmatter or no allowed-tools key,
    # treat as "no permission" (skip).
    local fm
    fm="$(awk '
      BEGIN { state = 0 }
      state == 0 && /^---[[:space:]]*$/ { state = 1; next }
      state == 1 && /^---[[:space:]]*$/ { exit }
      state == 1 { print }
    ' "$sk")"
    [ -z "$fm" ] && continue
    # Check only lines within the allowed-tools YAML value (the allowed-tools:
    # key line plus any continuation lines until the next top-level key).
    local at_block
    at_block="$(printf '%s\n' "$fm" | awk '
      BEGIN { in_at = 0 }
      /^allowed-tools:/ { in_at = 1; print; next }
      in_at && /^[[:space:]]/ { print; next }
      in_at && /^[^[:space:]]/ { exit }
    ')"
    [ -z "$at_block" ] && continue
    if printf '%s\n' "$at_block" | grep -qF "Write(.claude/rules/"; then
      found_set="$found_set $sk"
    fi
  done
  # Normalize: trim and sort.
  local found_sorted expected_sorted
  found_sorted="$(echo "$found_set" | tr ' ' '\n' | sed '/^$/d' | sort -u | tr '\n' ' ')"
  expected_sorted="$(echo "$expected_set" | tr ' ' '\n' | sed '/^$/d' | sort -u | tr '\n' ' ')"
  if [ "$found_sorted" = "$expected_sorted" ]; then
    pass "INV-023" "Write(.claude/rules/...) allowlist is exactly {cspec, cdocs, cupdate-arch}"
  else
    fail "INV-023" "Write(.claude/rules/...) allowlist mismatch. found='$found_sorted' expected='$expected_sorted'"
  fi
}

# ============================================================================
# INV-024: sync.sh does not reference .claude/rules/
# ============================================================================

check_inv024() {
  if [ ! -f "$SYNC_SH" ]; then
    fail "INV-024" "$SYNC_SH not found"
    return
  fi
  if grep -qF ".claude/rules" "$SYNC_SH"; then
    fail "INV-024(a)" "sync.sh contains '.claude/rules' reference"
  else
    pass "INV-024(a)" "sync.sh does not reference .claude/rules"
  fi
  # Any non-comment .claude/ reference is a violation.
  # A-013 caveat: this awk filter strips lines whose first non-whitespace
  # char is `#`, so it will miss `.claude/` references embedded inside
  # heredoc bodies (sync.sh occasionally emits shell snippets via heredocs,
  # and those bodies pass through unfiltered). A future refinement could
  # use a heredoc state machine like check_inv010_self_scan. Today's test
  # accepts this false-negative risk; the coarse grep above (INV-024(a))
  # would still catch a literal '.claude/rules' inside a heredoc body.
  local non_comment_hits
  non_comment_hits="$(strip_shell_comments "$SYNC_SH" | awk '/\.claude\//')"
  if [ -z "$non_comment_hits" ]; then
    pass "INV-024(b)" "sync.sh has no non-comment .claude/ references"
  else
    fail "INV-024(b)" "sync.sh has non-comment .claude/ references: $non_comment_hits"
  fi
}

# ============================================================================
# INV-025: New CLAUDE.md learning entry for migration convention
# ============================================================================

check_inv025() {
  if [ ! -f "$CLAUDE_MD" ]; then
    fail "INV-025" "$CLAUDE_MD not found"
    return
  fi
  # (a) header line — exact text including em-dash U+2014.
  local header="### 2026-04-10 — Convention introduced: rules-canonical / ARCHITECTURE.md index"
  if grep -qF "$header" "$CLAUDE_MD"; then
    pass "INV-025(a)" "CLAUDE.md has exact 2026-04-10 convention header"
  else
    fail "INV-025(a)" "CLAUDE.md missing exact header: '$header'"
  fi
  # Find the entry block to check b/c/d/e.
  local block
  block="$(awk -v h="$header" '
    index($0, h) > 0 { in_block = 1 }
    in_block { print }
    in_block && /^Source:/ { exit }
  ' "$CLAUDE_MD")"
  # (b) PAT-001 migrated to .claude/rules/hooks-pretooluse.md
  if echo "$block" | grep -qF "PAT-001" \
     && echo "$block" | grep -qF ".claude/rules/hooks-pretooluse.md"; then
    pass "INV-025(b)" "entry references PAT-001 -> rule file"
  else
    fail "INV-025(b)" "entry missing PAT-001 / rule file reference"
  fi
  # (c) MG-001 or MG-002
  if echo "$block" | grep -qE "MG-00[12]"; then
    pass "INV-025(c)" "entry references MG-001 or MG-002"
  else
    fail "INV-025(c)" "entry missing MG-001/MG-002 reference"
  fi
  # (d) PRH-002
  if echo "$block" | grep -qF "PRH-002"; then
    pass "INV-025(d)" "entry references PRH-002"
  else
    fail "INV-025(d)" "entry missing PRH-002 reference"
  fi
  # (e) Source: /cspec after path-scoped-rules-pat001
  if echo "$block" | grep -qF "Source: /cspec after path-scoped-rules-pat001"; then
    pass "INV-025(e)" "entry has correct Source attribution"
  else
    fail "INV-025(e)" "entry missing correct Source: /cspec attribution"
  fi
}

# ============================================================================
# INV-026: Dogfood marker in rule file
# ============================================================================

check_inv026() {
  if [ ! -f "$RULE_FILE" ]; then
    fail "INV-026" "rule file missing — cannot check dogfood marker"
    return
  fi
  if grep -qF "$EXPECTED_DOGFOOD_MARKER" "$RULE_FILE"; then
    pass "INV-026" "rule file contains dogfood marker"
  else
    fail "INV-026" "rule file missing dogfood marker substring: '$EXPECTED_DOGFOOD_MARKER'"
  fi
}

# ============================================================================
# INV-027: ARCHITECTURE.md contains ABS-009, ENV-005, ENV-006, Patterns reader note
# ============================================================================

check_inv027() {
  if [ ! -f "$ARCH_FILE" ]; then
    fail "INV-027" "$ARCH_FILE not found"
    return
  fi
  if grep -qE '^### ABS-009:' "$ARCH_FILE"; then
    pass "INV-027(a)" "ARCHITECTURE.md has ### ABS-009: heading"
  else
    fail "INV-027(a)" "ARCHITECTURE.md missing ### ABS-009: heading"
  fi
  if grep -qE '^### ENV-005:' "$ARCH_FILE"; then
    pass "INV-027(b)" "ARCHITECTURE.md has ### ENV-005: heading"
  else
    fail "INV-027(b)" "ARCHITECTURE.md missing ### ENV-005: heading"
  fi
  if grep -qE '^### ENV-006:' "$ARCH_FILE"; then
    pass "INV-027(c)" "ARCHITECTURE.md has ### ENV-006: heading"
  else
    fail "INV-027(c)" "ARCHITECTURE.md missing ### ENV-006: heading"
  fi
  # A-009 fix: blockquote containing ABS-009 must appear strictly between
  # `## Patterns` and `### PAT-001:` — not anywhere in the file.
  if awk '
    /^## Patterns/ { in_section = 1; next }
    in_section && /^### PAT-001:/ { exit }
    in_section && /^>.*ABS-009/ { found = 1 }
    END { exit found ? 0 : 1 }
  ' "$ARCH_FILE"; then
    pass "INV-027(d)" "ARCHITECTURE.md has blockquote reader note (referencing ABS-009) between ## Patterns and ### PAT-001:"
  else
    fail "INV-027(d)" "ARCHITECTURE.md missing blockquote reader note (referencing ABS-009) between ## Patterns and ### PAT-001:"
  fi
}

# ============================================================================
# QA-001 CLASS FIX: No circular "See PAT-NNN" self-references in CLAUDE.md
# learning entries.
#
# Source: QA-001 from the tdd-qa phase of path-scoped-rules-pat001-migration.
# The PAT-005 learning entry ended with "See PAT-005 for the PostToolUse
# counterpart" — pointing at itself. The rewrite was forced by an INV-018
# fix that dropped the original `.correctless/ARCHITECTURE.md` reference
# and introduced a circular placeholder. Catches this class structurally:
# for every `### YYYY-MM-DD — ... (PAT-NNN)` header, the entry body must
# NOT contain the literal substring `See PAT-NNN` for the matching NNN.
# ============================================================================

check_qa_001_class() {
  if [ ! -f "$CLAUDE_MD" ]; then
    fail "QA-001-CLASS" "$CLAUDE_MD not found"
    return
  fi
  local violations
  violations="$(awk '
    # Match dated learning entry header with a PAT ID in parens.
    /^### 20[0-9][0-9]-[0-9][0-9]-[0-9][0-9] .*\(PAT-[0-9]+\)/ {
      if (cur_pat != "" && has_self_ref) {
        print cur_header
      }
      cur_header = $0
      has_self_ref = 0
      match($0, /PAT-[0-9]+/)
      cur_pat = substr($0, RSTART, RLENGTH)
      next
    }
    # End of entry at next level-3 or level-2 header (exact hash count).
    /^### [^#]/ || /^## [^#]/ {
      if (cur_pat != "" && has_self_ref) {
        print cur_header
      }
      cur_pat = ""
      cur_header = ""
      has_self_ref = 0
      next
    }
    # Inside an entry: check each body line for `See PAT-NNN` where NNN
    # matches the entry header'\''s own PAT ID.
    cur_pat != "" {
      target = "See " cur_pat
      if (index($0, target) > 0) {
        has_self_ref = 1
      }
    }
    END {
      if (cur_pat != "" && has_self_ref) {
        print cur_header
      }
    }
  ' "$CLAUDE_MD")"
  if [ -z "$violations" ]; then
    pass "QA-001-CLASS" "no circular 'See PAT-NNN' self-references in CLAUDE.md learning entries"
  else
    local count
    count="$(printf '%s\n' "$violations" | wc -l | tr -d ' ')"
    fail "QA-001-CLASS" "$count circular 'See PAT-NNN' self-reference(s) in CLAUDE.md learning entries"
  fi
}

# ============================================================================
# QA-002 CLASS FIX: /cdocs must have a back-fill instruction for deferred
# `created_at_commit` fields in `.correctless/meta/*.json` files.
#
# Source: QA-002 from the tdd-qa phase of path-scoped-rules-pat001-migration.
# The pat001-measurement-due.json file was created with
# `created_at_commit: null` as a deferred-until-merge marker, but no skill
# actually back-filled the field. Without this instruction in /cdocs, the
# MG-003 measurement gate stalls forever (bug-by-forgetting). Catches this
# class structurally: the /cdocs SKILL.md must contain an instruction that
# references `.correctless/meta/`, `created_at_commit`, and the phrase
# `back-fill`. If the instruction is removed or the anchors drift, the test
# fails.
# ============================================================================

check_qa_002_class() {
  local cdocs_skill="$REPO_ROOT/skills/cdocs/SKILL.md"
  if [ ! -f "$cdocs_skill" ]; then
    fail "QA-002-CLASS" "skills/cdocs/SKILL.md not found"
    return
  fi
  # L4 fix: extract the "Back-fill Deferred Meta Fields" section body
  # (from its `### ` heading to the next `### `/`## `/EOF), then require
  # all three anchors to appear inside that specific section. Prevents a
  # stray comment elsewhere in SKILL.md from making the check pass by
  # coincidence.
  local section
  section="$(awk '
    /^### Back-fill Deferred Meta Fields[[:space:]]*$/ { in_sec = 1; next }
    in_sec && /^### [^#]/ { exit }
    in_sec && /^## [^#]/ { exit }
    in_sec { print }
  ' "$cdocs_skill")"
  if [ -z "$section" ]; then
    fail "QA-002-CLASS" "skills/cdocs/SKILL.md missing '### Back-fill Deferred Meta Fields' section"
    return
  fi
  local have_meta_path=0 have_field=0 have_backfill=0
  printf '%s\n' "$section" | grep -qF ".correctless/meta/" && have_meta_path=1
  printf '%s\n' "$section" | grep -qF "created_at_commit" && have_field=1
  printf '%s\n' "$section" | grep -qiF "back-fill" && have_backfill=1
  if [ $have_meta_path -eq 1 ] && [ $have_field -eq 1 ] && [ $have_backfill -eq 1 ]; then
    pass "QA-002-CLASS" "skills/cdocs/SKILL.md 'Back-fill Deferred Meta Fields' section contains all required anchors"
  else
    fail "QA-002-CLASS" "'Back-fill Deferred Meta Fields' section missing anchors (meta_path=$have_meta_path created_at_commit=$have_field back-fill=$have_backfill)"
  fi
}

# ============================================================================
# QA-011 CLASS FIX: inline branch-slug drift (AP-005 / ABS-001 regression).
#
# Source: QA-011 from round 2 of fix-diff-reviewer-migration. A fix round
# hand-rolled `git rev-parse --abbrev-ref HEAD | tr '/' '-'` inside caudit
# SKILL.md, diverging from the canonical `branch_slug()` helper in
# scripts/lib.sh that was extracted specifically to eliminate this drift
# class (2026-04-05 ABS-001 learning). This check greps for the inline
# pattern across all skills/, hooks/, and scripts/ and fails if any match
# is found outside scripts/lib.sh itself.
#
# Enforced pattern: `git rev-parse --abbrev-ref ... tr` or
# `git branch --show-current ... tr` on the same line.
# ============================================================================

check_no_inline_branch_slug() {
  local violations
  # rg-style grep with line-content output, then filter out scripts/lib.sh
  # (the canonical site) and any commented-out lines starting with #.
  violations="$(grep -rnE 'git[[:space:]]+(rev-parse[[:space:]]+--abbrev-ref|branch[[:space:]]+--show-current)[^\n]*\|[[:space:]]*tr[[:space:]]' \
    skills/ hooks/ scripts/ 2>/dev/null \
    | grep -vE '^scripts/lib\.sh:' \
    | grep -vE ':[[:space:]]*#' \
    || true)"
  if [ -z "$violations" ]; then
    pass "QA-011-CLASS" "no inline branch-slug drift (git rev-parse|tr or git branch --show-current|tr) outside scripts/lib.sh"
  else
    local count
    count="$(printf '%s\n' "$violations" | wc -l | tr -d ' ')"
    fail "QA-011-CLASS" "$count inline branch-slug site(s) found outside scripts/lib.sh — drift of ABS-001 canonical helper:"
    printf '%s\n' "$violations" | sed 's/^/    /' >&2
  fi
}

# ============================================================================
# QA-013 CLASS FIX: /tmp/ path usage in skill code fences.
#
# Source: QA-013 from round 2 of fix-diff-reviewer-migration. caudit's own
# "All files inside the project directory. Never /tmp." constraint was
# violated by two /tmp/fd-findings-*.json sites inside the skill's own step
# 6a code fences. This check greps for `/tmp/` across all skills/*/SKILL.md,
# excluding the prose constraint line itself (which documents the rule).
# Any remaining match is a violation.
# ============================================================================

check_no_tmp_paths_in_skills() {
  local violations
  # Exclude the documentary constraint line which legitimately contains
  # "Never /tmp" or "inside the project directory" prose. Any other /tmp/
  # reference is a violation.
  violations="$(grep -rnE '/tmp/' skills/ 2>/dev/null \
    | grep -vE 'Never[[:space:]]*/tmp|inside the project directory' \
    || true)"
  if [ -z "$violations" ]; then
    pass "QA-013-CLASS" "no /tmp/ paths in skill files (excluding documentary constraint lines)"
  else
    local count
    count="$(printf '%s\n' "$violations" | wc -l | tr -d ' ')"
    fail "QA-013-CLASS" "$count /tmp/ usage(s) found in skill files — violates caudit's 'Never /tmp' constraint:"
    printf '%s\n' "$violations" | sed 's/^/    /' >&2
  fi
}

# ============================================================================
# Path Discovery Guard (R-005 from skill-path-discovery spec)
#
# Skills that reference "Read the spec artifact" must include explicit path
# discovery instructions. PMB-004 proved agents hallucinate wrong paths without
# them. This guard maintains two lists:
#   MUST_HAVE_DISCOVERY — skills that need at least one discovery token
#   EXCLUDED_FROM_DISCOVERY — skills that don't need single-spec discovery
# Any skill directory not in either list causes the test to fail, forcing
# the author to classify every new skill.
# ============================================================================

check_path_discovery_guard() {
  # Skills that MUST have at least one path discovery token in their body
  MUST_HAVE_DISCOVERY="creview-spec creview ctdd cverify cpostmortem csummary cdocs cmodel"

  # Skills excluded from the path discovery requirement — they don't reference
  # a single spec artifact or use directory-scan patterns instead
  EXCLUDED_FROM_DISCOVERY="crelease cupdate-arch carchitect csetup chelp cstatus cquick cexplain cdebug crefactor ccontribute cmaintain cpr-review credteam caudit cdevadv cauto cwtf cmetrics cspec"

  # Valid discovery tokens (checked as extended regex against the skill body)
  local discovery_pattern="workflow-advance\.sh status|spec_file|path from workflow|\.correctless/specs/"

  # Helper: extract everything after YAML frontmatter
  local_skill_body() {
    awk '
      BEGIN { state = 0 }
      NR == 1 && /^---/ { state = 1; next }
      state == 1 && /^---/ { state = 0; next }
      state == 0 { print }
    ' "$1"
  }

  # Part 1: verify every MUST_HAVE skill contains at least one discovery token
  local skill skill_file body
  for skill in $MUST_HAVE_DISCOVERY; do
    skill_file="skills/$skill/SKILL.md"
    if [ ! -f "$skill_file" ]; then
      fail "DISC-001-$skill" "MUST_HAVE_DISCOVERY skill file not found: $skill_file"
      continue
    fi
    body="$(local_skill_body "$skill_file")"
    if grep -qE "$discovery_pattern" <<< "$body"; then
      pass "DISC-001-$skill" "$skill has path discovery token"
    else
      fail "DISC-001-$skill" "Skill $skill in MUST_HAVE_DISCOVERY but has no path discovery token"
    fi
  done

  # Part 2: verify every skill directory is classified in one of the two lists
  local skill_dir skill_name in_must in_excluded m e
  for skill_dir in skills/*/; do
    [ -d "$skill_dir" ] || continue
    skill_name="$(basename "$skill_dir")"
    # Skip _shared — it's not a skill
    [ "$skill_name" = "_shared" ] && continue

    in_must=0
    in_excluded=0
    for m in $MUST_HAVE_DISCOVERY; do
      [ "$skill_name" = "$m" ] && in_must=1 && break
    done
    for e in $EXCLUDED_FROM_DISCOVERY; do
      [ "$skill_name" = "$e" ] && in_excluded=1 && break
    done

    if [ "$in_must" = "0" ] && [ "$in_excluded" = "0" ]; then
      fail "DISC-002-$skill_name" "Skill $skill_name not classified in path-discovery guard — add to MUST_HAVE_DISCOVERY or EXCLUDED_FROM_DISCOVERY list"
    else
      pass "DISC-002-$skill_name" "Skill $skill_name classified in path-discovery guard"
    fi
  done
}

# ============================================================================
# Run all checks
# ============================================================================

echo "Correctless Architecture Drift Tests"
echo "===================================="

check_inv010_self_scan   # Also checks INV-020
check_inv001
check_inv002
check_inv003
check_inv004
check_inv005
check_inv006
check_inv007
check_inv008
check_inv009
check_inv016
check_inv017
check_inv018
check_inv019
check_inv021
check_inv023
check_inv024
check_inv025
check_inv026
check_inv027
check_qa_001_class
check_qa_002_class
check_no_inline_branch_slug
check_no_tmp_paths_in_skills
check_path_discovery_guard

run_negative_cases

# ============================================================================
# AP-005: Mechanical enforcement of documented counts
# Prevents stale count claims in README.md and CONTRIBUTING.md.
# ============================================================================

check_ap005_stale_counts() {
  local root
  root="$(repo_root)"

  # Test file count in CONTRIBUTING.md
  local claimed_tests actual_tests
  claimed_tests="$(grep -oP '\d+(?= test files)' "$root/CONTRIBUTING.md" 2>/dev/null | head -1)" || claimed_tests=""
  actual_tests="$(find "$root/tests" -maxdepth 1 -name 'test-*.sh' -type f | wc -l | tr -d ' ')"
  if [ -n "$claimed_tests" ] && [ "$claimed_tests" -eq "$actual_tests" ]; then
    pass "AP-005(tests)" "CONTRIBUTING.md claims $claimed_tests test files, actual is $actual_tests"
  elif [ -n "$claimed_tests" ]; then
    fail "AP-005(tests)" "CONTRIBUTING.md claims $claimed_tests test files, actual is $actual_tests"
  else
    pass "AP-005(tests)" "no test count claim found in CONTRIBUTING.md (nothing to drift)"
  fi

  # Skill count in CONTRIBUTING.md
  local claimed_skills actual_skills
  claimed_skills="$(grep -oP '\d+(?= SKILL\.md files)' "$root/CONTRIBUTING.md" 2>/dev/null | head -1)" || claimed_skills=""
  actual_skills="$(find "$root/skills" -name 'SKILL.md' -type f | wc -l | tr -d ' ')"
  if [ -n "$claimed_skills" ] && [ "$claimed_skills" -eq "$actual_skills" ]; then
    pass "AP-005(skills)" "CONTRIBUTING.md claims $claimed_skills skills, actual is $actual_skills"
  elif [ -n "$claimed_skills" ]; then
    fail "AP-005(skills)" "CONTRIBUTING.md claims $claimed_skills skills, actual is $actual_skills"
  else
    pass "AP-005(skills)" "no skill count claim found in CONTRIBUTING.md (nothing to drift)"
  fi

  # Skill count in README.md badge
  local readme_skills
  readme_skills="$(grep -oP '(?<=skills-)\d+' "$root/README.md" 2>/dev/null | head -1)" || readme_skills=""
  if [ -n "$readme_skills" ] && [ "$readme_skills" -eq "$actual_skills" ]; then
    pass "AP-005(readme-badge)" "README badge claims $readme_skills skills, actual is $actual_skills"
  elif [ -n "$readme_skills" ]; then
    fail "AP-005(readme-badge)" "README badge claims $readme_skills skills, actual is $actual_skills"
  else
    pass "AP-005(readme-badge)" "no skill badge found in README.md (nothing to drift)"
  fi
}

check_ap005_stale_counts

# ============================================================================
# Test registration guard: every test-*.sh must be in all three registries
# Catches the recurring gap where new test files are created but not registered
# in workflow-config.json, ci.yml, and/or tests/test.sh.
# ============================================================================

check_test_registration() {
  local root
  root="$(git rev-parse --show-toplevel)"
  local config="$root/.correctless/config/workflow-config.json"
  local ci_yml="$root/.github/workflows/ci.yml"
  local missing_config="" missing_ci=""

  while IFS= read -r test_file; do
    local basename
    basename="$(basename "$test_file")"

    # Skip test-helpers.sh — it is a shared harness sourced by other tests,
    # not a standalone test file. It should NOT be registered in CI or config.
    [ "$basename" = "test-helpers.sh" ] && continue

    if [ -f "$config" ] && ! grep -q "$basename" "$config" 2>/dev/null; then
      missing_config="$missing_config $basename"
    fi
    if [ -f "$ci_yml" ] && ! grep -q "$basename" "$ci_yml" 2>/dev/null; then
      missing_ci="$missing_ci $basename"
    fi
  done < <(find "$root/tests" -maxdepth 1 -name 'test-*.sh' -type f | sort)

  if [ -z "$missing_config" ]; then
    pass "REG-001(config)" "all test files registered in workflow-config.json"
  else
    fail "REG-001(config)" "missing from workflow-config.json:$missing_config"
  fi

  if [ -z "$missing_ci" ]; then
    pass "REG-001(ci)" "all test files registered in ci.yml"
  else
    fail "REG-001(ci)" "missing from ci.yml:$missing_ci"
  fi
}

check_test_registration

# ============================================================================
# Summary
# ============================================================================

echo ""
echo "===================================="
echo "  PASS: $PASS"
echo "  FAIL: $FAIL"
if [ -n "$FAILED_IDS" ]; then
  echo "  Failed invariants: $FAILED_IDS"
fi
echo "===================================="

[ "$FAIL" -eq 0 ] && exit 0 || exit 1
