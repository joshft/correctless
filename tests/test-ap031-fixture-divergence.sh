#!/usr/bin/env bash
# shellcheck disable=SC1090,SC1091,SC2086,SC2016
# Correctless — AP-031 Fixture Divergence Prevention Tests
# Enforces the ap031-fixture-divergence-prevention spec rules R-001..R-006.
#
# ALL block-scoped assertions (R-001/R-002/R-003/R-006) extract the relevant
# heading-delimited section FIRST, then grep within that block. File-wide grep
# is NOT used for any R-004 keyword assertion — this directly mitigates AP-003
# (keyword-presence tests that pass when keywords appear in unrelated sections).
#
# Run from repo root: bash tests/test-ap031-fixture-divergence.sh

source "$(dirname "${BASH_SOURCE[0]}")/test-helpers.sh"

echo "AP-031 Fixture Divergence Prevention Tests"
echo "==========================================="

CSPEC_SKILL="$REPO_DIR/skills/cspec/SKILL.md"
CTDD_RED_AGENT="$REPO_DIR/agents/ctdd-red.md"
CTDD_SKILL="$REPO_DIR/skills/ctdd/SKILL.md"
AGENT_CONTEXT="$REPO_DIR/.correctless/AGENT_CONTEXT.md"
DIST_CSPEC="$REPO_DIR/correctless/skills/cspec/SKILL.md"
DIST_CTDD="$REPO_DIR/correctless/skills/ctdd/SKILL.md"
DIST_CTDD_RED="$REPO_DIR/correctless/agents/ctdd-red.md"

# ============================================================================
# R-001 [unit]: skills/cspec/SKILL.md Step 3 block contains format-pinning
# directive with AP-031 reference, format/producer keywords, detection
# heuristics, and a concrete example.
# BLOCK-SCOPED: extracts Step 3 section only (R-004 mitigates AP-003)
# ============================================================================

section "R-001: cspec Step 3 format-pinning directive (block-scoped)"

if [ ! -f "$CSPEC_SKILL" ]; then
  fail "R-001(a)" "skills/cspec/SKILL.md not found"
  fail "R-001(b)" "skills/cspec/SKILL.md not found"
  fail "R-001(c)" "skills/cspec/SKILL.md not found"
  fail "R-001(d)" "skills/cspec/SKILL.md not found"
  fail "R-001(e)" "skills/cspec/SKILL.md not found"
  fail "R-001(f)" "skills/cspec/SKILL.md not found"
else
  # BLOCK-SCOPED (R-004): extract from "### Step 3:" to the next "### Step N"
  # heading (where N begins with a digit or letter), which is "### Step 3a:".
  # Stops before Step 3a so only the core Step 3 body is checked.
  step3_block="$(awk '
    /^### Step 3:/{found=1}
    found && /^### Step [0-9a-zA-Z]/ && !/^### Step 3:/{exit}
    found{print}
  ' "$CSPEC_SKILL")"

  # Tests R-001 [unit]: Step 3 block references AP-031
  if grep -qF "AP-031" <<< "$step3_block"; then
    pass "R-001(a)" "cspec Step 3 block references AP-031"
  else
    fail "R-001(a)" "cspec Step 3 block missing AP-031 reference"
  fi

  # Tests R-001 [unit]: Step 3 block contains format-pinning language (exact/pin/parsed/heading regex)
  if grep -qiE "(pin.*format|format.*pin|exact format|format.*(being )?parsed|heading regex|JSON schema)" <<< "$step3_block"; then
    pass "R-001(b)" "cspec Step 3 block contains format-pinning language"
  else
    fail "R-001(b)" "cspec Step 3 block missing format-pinning language (pin.*format/exact format/heading regex/JSON schema)"
  fi

  # Tests R-001 [unit]: Step 3 block contains "producer" (cite producer file path)
  if grep -qi "producer" <<< "$step3_block"; then
    pass "R-001(c)" "cspec Step 3 block contains 'producer'"
  else
    fail "R-001(c)" "cspec Step 3 block missing 'producer'"
  fi

  # Tests R-001 [unit]: Step 3 block contains detection heuristic keywords.
  # Spec requires trigger conditions: reads/extracts/pattern-matches against
  # files produced by another skill/script, including jq field access.
  # Bare 'reads' and 'extracts' are excluded — require specific anchors to
  # avoid false positives from unrelated prose.
  if grep -qiE "(heading (regex|format)|pattern.match|jq|regex.*against|artifact.*content|reads.*artifact|extracts.*from)" <<< "$step3_block"; then
    pass "R-001(d)" "cspec Step 3 block contains detection heuristic keywords"
  else
    fail "R-001(d)" "cspec Step 3 block missing detection heuristics (heading regex/pattern-match/jq/reads.*artifact/extracts.*from)"
  fi

  # Tests R-001 [unit]: Step 3 block contains concrete example.
  # Spec: "must include a concrete example: 'Heading format: ## Finding RS-{NNN}:
  # {title} per skills/creview-spec/SKILL.md Step 3.5 template.'"
  if grep -qiE "(Example:|e\.g\.,|e\.g\.:)" <<< "$step3_block"; then
    pass "R-001(e)" "cspec Step 3 block contains concrete example marker (Example: / e.g.)"
  else
    fail "R-001(e)" "cspec Step 3 block missing concrete example (no 'Example:' or 'e.g.')"
  fi

  # Tests R-001 [unit]: Step 3 block references a SKILL.md template path in the example.
  # The concrete example must cross-reference the producer's SKILL.md as the authoritative
  # format source (not just "the script reads review findings").
  if grep -qi "SKILL\.md" <<< "$step3_block"; then
    pass "R-001(f)" "cspec Step 3 block cross-references a SKILL.md template path"
  else
    fail "R-001(f)" "cspec Step 3 block missing SKILL.md cross-reference in example"
  fi

  # Tests R-001 [unit]: Step 3 block contains the negative-trigger exclusion clause.
  # Spec: "does NOT trigger for file existence checks or path-only operations"
  if grep -qiE "(does not trigger|does NOT trigger|file.exist|path.only)" <<< "$step3_block"; then
    pass "R-001(g)" "cspec Step 3 block contains negative-trigger exclusion clause"
  else
    fail "R-001(g)" "cspec Step 3 block missing negative-trigger exclusion clause (does not trigger/file exist/path-only)"
  fi

  # Tests R-001 [unit]: Step 3 block includes the "Not:" contrast in the concrete example.
  # Spec: "Not: 'The script reads review findings.'"
  if grep -qE "Not:" <<< "$step3_block"; then
    pass "R-001(h)" "cspec Step 3 block contains 'Not:' contrast in concrete example"
  else
    fail "R-001(h)" "cspec Step 3 block missing 'Not:' contrast in concrete example"
  fi
fi

# ============================================================================
# R-002 [unit]: agents/ctdd-red.md contains a real-fixture directive.
# BLOCK-SCOPED: extracts ## Process section (the natural home for process
# directives). Falls back to file body if no specific "real-fixture" heading
# exists, but the ## Process scope is the primary enforced scope.
# ============================================================================

section "R-002: ctdd-red.md real-fixture directive (block-scoped)"

if [ ! -f "$CTDD_RED_AGENT" ]; then
  fail "R-002(a)" "agents/ctdd-red.md not found"
  fail "R-002(b)" "agents/ctdd-red.md not found"
  fail "R-002(c)" "agents/ctdd-red.md not found"
  fail "R-002(d)" "agents/ctdd-red.md not found"
  fail "R-002(e)" "agents/ctdd-red.md not found"
  fail "R-002(f)" "agents/ctdd-red.md not found"
  fail "R-002(h)" "agents/ctdd-red.md not found"
  fail "R-002(i)" "agents/ctdd-red.md not found"
  fail "R-002(j)" "agents/ctdd-red.md not found"
else
  # BLOCK-SCOPED (R-004): first try to extract a dedicated "real-fixture" or
  # "real artifact" heading section (preferred — most specific scope).
  # Falls back to the ## Process section if no such heading exists yet.
  # In RED phase: no "real fixture" heading exists; falls back to ## Process,
  # which also lacks the keywords → all checks fail (expected RED state).
  real_fixture_block="$(awk '
    tolower($0) ~ /^### .*(real.fixture|real.artifact|fixture.requirement)/{found=1}
    found && tolower($0) !~ /^### .*(real.fixture|real.artifact|fixture.requirement)/ && /^##/{exit}
    found{print}
  ' "$CTDD_RED_AGENT")"

  _in_fallback=0
  if [ -z "$real_fixture_block" ]; then
    _in_fallback=1
    # No dedicated heading found — fall back to ## Process section.
    real_fixture_block="$(awk '
      /^## Process/{found=1}
      found && !/^## Process/ && /^## /{exit}
      found{print}
    ' "$CTDD_RED_AGENT")"
  fi

  # TA-007: Fallback scope is wide; require anchor keywords to co-locate within
  # a 25-line window to prevent scattered keyword matches passing vacuously.
  # Only applies when using the ## Process fallback (not dedicated heading scope).
  if [ "$_in_fallback" -eq 1 ] && [ -n "$real_fixture_block" ]; then
    _line_real="$(grep -ni "real artifact" <<< "$real_fixture_block" | head -1 | cut -d: -f1)"
    _line_source="$(grep -nF "# Source:" <<< "$real_fixture_block" | head -1 | cut -d: -f1)"
    _line_dormant="$(grep -ni "dormant" <<< "$real_fixture_block" | head -1 | cut -d: -f1)"
    if [ -n "$_line_real" ] && [ -n "$_line_source" ] && [ -n "$_line_dormant" ]; then
      _max=$(( _line_real > _line_source ? _line_real : _line_source ))
      _max=$(( _max > _line_dormant ? _max : _line_dormant ))
      _min=$(( _line_real < _line_source ? _line_real : _line_source ))
      _min=$(( _min < _line_dormant ? _min : _line_dormant ))
      _window=$(( _max - _min ))
      if [ "$_window" -le 25 ]; then
        pass "R-002(g)" "fallback scope: anchor keywords co-locate within 25-line window ($_window lines)"
      else
        fail "R-002(g)" "fallback scope: anchor keywords span $_window lines (>25); directive may be scattered"
      fi
    fi
  fi

  # Tests R-002 [unit]: "real artifact" — core phrase specifying fixture source
  if grep -qi "real artifact" <<< "$real_fixture_block"; then
    pass "R-002(a)" "ctdd-red directive block contains 'real artifact'"
  else
    fail "R-002(a)" "ctdd-red directive block missing 'real artifact'"
  fi

  # Tests R-002 [unit]: "# Source:" — mandatory citation prefix format.
  # Spec: "Citation MUST use the prefix # Source: followed by the artifact path"
  if grep -qF "# Source:" <<< "$real_fixture_block"; then
    pass "R-002(b)" "ctdd-red directive block contains '# Source:' citation prefix"
  else
    fail "R-002(b)" "ctdd-red directive block missing '# Source:' citation prefix"
  fi

  # Tests R-002 [unit]: "dormant" — dormant behavior when no real artifact exists
  # (new producer + consumer in same PR with no prior artifact).
  if grep -qi "dormant" <<< "$real_fixture_block"; then
    pass "R-002(c)" "ctdd-red directive block contains 'dormant' behavior description"
  else
    fail "R-002(c)" "ctdd-red directive block missing 'dormant' behavior (bootstrap case)"
  fi

  # Tests R-002 [unit]: "verbatim" — preferred form: verbatim excerpt included in test
  # with # Source: citation. Spec: "The preferred form is a verbatim excerpt included
  # in the test file... with a comment citing the source path"
  if grep -qi "verbatim" <<< "$real_fixture_block"; then
    pass "R-002(d)" "ctdd-red directive block contains 'verbatim' (preferred excerpt form)"
  else
    fail "R-002(d)" "ctdd-red directive block missing 'verbatim' (preferred form not documented)"
  fi

  # Tests R-002 [unit]: hermetic / CI / fresh clone concern documented.
  # Spec: "this form is hermetic and works in CI and fresh clones"
  if grep -qiE "(hermetic|CI.*clone|clone.*CI|fresh.*clone|gitignored)" <<< "$real_fixture_block"; then
    pass "R-002(e)" "ctdd-red directive block documents hermetic/CI/fresh-clone form"
  else
    fail "R-002(e)" "ctdd-red directive block missing hermetic/CI concern documentation"
  fi

  # Tests R-002 [unit]: alternative live-file form documented and its limitation noted.
  # Spec: "alternative form — reading the real artifact from its file path at test time —
  # must not be the sole form, since .correctless/artifacts/ is gitignored and absent in CI"
  if grep -qiE "(alternative|gitignore|absent.*CI|CI.*absent|live.*file|file.*path.*test)" <<< "$real_fixture_block"; then
    pass "R-002(f)" "ctdd-red directive block documents alternative live-file form and limitation"
  else
    fail "R-002(f)" "ctdd-red directive block missing alternative form / gitignored limitation"
  fi

  # Tests R-002 [unit]: post-review amended clauses pin (sprint/r004-amended-clause-pins).
  # The MA-117 trigger-detection block and MA-211 language-aware citation forms were
  # added to agents/ctdd-red.md after the original R-002 keyword contract was set, so
  # R-004's keyword set didn't pin them. Without these checks, an edit to ctdd-red.md
  # could silently remove the clauses and the test would still pass.

  # R-002(h): MA-117 trigger-detection block — both halves must be present (the
  # positive directive AND the negative-trigger exclusion). Mirrors R-001's
  # detection-heuristics structure in skills/cspec/SKILL.md Step 3.
  if grep -qF "Trigger detection" <<< "$real_fixture_block" && \
     grep -qF "does NOT trigger" <<< "$real_fixture_block"; then
    pass "R-002(h)" "ctdd-red directive block contains MA-117 trigger-detection (positive + negative)"
  else
    fail "R-002(h)" "ctdd-red directive block missing MA-117 trigger-detection block (need 'Trigger detection' AND 'does NOT trigger')"
  fi

  # R-002(i): producer-to-artifact reference table mirrors check 11's table.
  # Requires both table headers AND at least one concrete producer mapping —
  # headers alone could be a placeholder, but a real mapping anchors the contract.
  if grep -qF "Producer" <<< "$real_fixture_block" && \
     grep -qF "Artifact pattern" <<< "$real_fixture_block" && \
     grep -qF "review-spec-findings-" <<< "$real_fixture_block"; then
    pass "R-002(i)" "ctdd-red directive block contains producer-to-artifact table with concrete mapping"
  else
    fail "R-002(i)" "ctdd-red directive block missing producer table headers or concrete producer mapping"
  fi

  # R-002(j): MA-211 language-aware Source: citation forms. The original R-002(b)
  # only pins '# Source:' (shell/Python). Non-shell projects need '// Source:'
  # (Go/TS/Java) and '-- Source:' (SQL). All three must be present so a writer
  # using any of these languages has a documented citation form.
  # Note: '--' separator is required before '-- Source:' because grep parses
  # a literal starting with '-' as an option flag otherwise.
  if grep -qF -- "// Source:" <<< "$real_fixture_block" && \
     grep -qF -- "-- Source:" <<< "$real_fixture_block"; then
    pass "R-002(j)" "ctdd-red directive block contains MA-211 language-aware citation forms (// Source:, -- Source:)"
  else
    fail "R-002(j)" "ctdd-red directive block missing language-aware citation forms (need '// Source:' AND '-- Source:')"
  fi
fi

# ============================================================================
# R-003 [unit]: skills/ctdd/SKILL.md test audit section contains check 11
# (fixture provenance check) and orchestrator computes modified-test-file list.
#
# TWO block-scoped checks:
#   (a-e) The check 11 block within the > blockquote (the agent's check list)
#   (f-g) The ## Between RED and GREEN orchestrator section (git commands)
# ============================================================================

section "R-003: ctdd check 11 fixture provenance (block-scoped)"

if [ ! -f "$CTDD_SKILL" ]; then
  fail "R-003(a)" "skills/ctdd/SKILL.md not found"
  fail "R-003(b)" "skills/ctdd/SKILL.md not found"
  fail "R-003(c)" "skills/ctdd/SKILL.md not found"
  fail "R-003(d)" "skills/ctdd/SKILL.md not found"
  fail "R-003(e)" "skills/ctdd/SKILL.md not found"
  fail "R-003(f)" "skills/ctdd/SKILL.md not found"
  fail "R-003(g)" "skills/ctdd/SKILL.md not found"
else
  # BLOCK-SCOPED (R-004): extract check 11 block from the test auditor blockquote.
  # Starts at "> 11." and ends before "> 12." OR at the first non-> line.
  # In RED phase: no "> 11." exists (currently checks 1-10 only) → empty block
  # → all keyword checks fail (expected RED state).
  check11_block="$(awk '
    /^>[[:space:]]*11\./{found=1}
    found && /^>[[:space:]]*12\./{exit}
    found && /^[[:space:]]*$/{next}
    found && !/^>/{exit}
    found{print}
  ' "$CTDD_SKILL")"

  # Tests R-003 [unit]: check 11 uses "fixture provenance" as the check name
  if grep -qi "fixture provenance" <<< "$check11_block"; then
    pass "R-003(a)" "ctdd check 11 block contains 'fixture provenance'"
  else
    fail "R-003(a)" "ctdd check 11 block missing 'fixture provenance'"
  fi

  # Tests R-003 [unit]: check 11 flags tests with only synthetic fixtures as BLOCKING
  if grep -qF "BLOCKING" <<< "$check11_block"; then
    pass "R-003(b)" "ctdd check 11 block flags as BLOCKING"
  else
    fail "R-003(b)" "ctdd check 11 block missing BLOCKING severity"
  fi

  # Tests R-003 [unit]: check 11 references "real artifact" (the required fixture form)
  if grep -qi "real artifact" <<< "$check11_block"; then
    pass "R-003(c)" "ctdd check 11 block contains 'real artifact'"
  else
    fail "R-003(c)" "ctdd check 11 block missing 'real artifact'"
  fi

  # Tests R-003 [unit]: check 11 distinguishes dormant (no real artifact exists)
  # from finding (real artifact exists but test doesn't use it).
  # Spec: "The check must distinguish between 'no real artifact exists' (dormant)
  # and 'real artifact exists but test doesn't use it' (finding)."
  if grep -qi "dormant" <<< "$check11_block"; then
    pass "R-003(d)" "ctdd check 11 block contains 'dormant' (dormant vs finding distinction)"
  else
    fail "R-003(d)" "ctdd check 11 block missing 'dormant' distinction"
  fi

  # Tests R-003 [unit]: check 11 includes a concrete producer-to-artifact mapping.
  # Spec example: "/creview-spec → .correctless/artifacts/review-spec-findings-*.md"
  if grep -qiE "(review-spec-findings|creview-spec.*artifacts|artifacts.*creview-spec)" <<< "$check11_block"; then
    pass "R-003(e)" "ctdd check 11 block contains producer-to-artifact mapping (review-spec-findings)"
  else
    fail "R-003(e)" "ctdd check 11 block missing producer-to-artifact mapping (e.g. review-spec-findings-)"
  fi

  # Tests R-003 [unit]: check 11 follows fixture file paths referenced by modified tests.
  # Spec: "The audit should also follow fixture file paths referenced by modified tests
  # (e.g., tests/fixtures/*.md), not just examine the test files themselves."
  if grep -qiE "(tests/fixtures|fixture file|follow.*fixture|referenced.*fixture)" <<< "$check11_block"; then
    pass "R-003(h)" "ctdd check 11 block references following fixture file paths (tests/fixtures)"
  else
    fail "R-003(h)" "ctdd check 11 block missing fixture file path following (tests/fixtures or fixture file)"
  fi

  # ---- Orchestrator section: git commands passed to test audit agent ----
  # BLOCK-SCOPED (R-004): extract ## Between RED and GREEN: Test Audit section
  # (from its heading to ## Phase: GREEN).
  # Spec: "The /ctdd orchestrator computes the modified-test-file list via
  # git diff ... AND git status --porcelain ... and passes both lists to the
  # test audit agent as input"
  test_audit_orch_block="$(awk '
    /^## Between RED and GREEN: Test Audit/{found=1}
    found && /^## Phase: GREEN/{exit}
    found{print}
  ' "$CTDD_SKILL")"

  # TA-003 fix: exclude "> " blockquote lines so audit-agent blockquote instructions
  # cannot satisfy the orchestrator's git-command contract. The audit agent is
  # read-only and must not run git; only orchestrator prose should contain these.
  non_blockquote="$(grep -v '^>' <<< "$test_audit_orch_block")"

  # Tests R-003 [unit]: orchestrator (non-blockquote) contains git diff for modified test files
  if grep -qE "git diff" <<< "$non_blockquote"; then
    pass "R-003(f)" "ctdd test audit orchestrator (non-blockquote) contains 'git diff'"
  else
    fail "R-003(f)" "ctdd test audit orchestrator (non-blockquote) missing 'git diff' (modified file list)"
  fi

  # Tests R-003 [unit]: orchestrator (non-blockquote) contains git status --porcelain for
  # untracked files (new RED-phase test files are untracked, not just modified).
  if grep -qE "git status.*--porcelain|--porcelain" <<< "$non_blockquote"; then
    pass "R-003(g)" "ctdd test audit orchestrator (non-blockquote) contains 'git status --porcelain'"
  else
    fail "R-003(g)" "ctdd test audit orchestrator (non-blockquote) missing 'git status --porcelain' (untracked file list)"
  fi

  # Tests R-003 [unit]: orchestrator prose documents passing both lists to the audit agent.
  # Spec: "passes both lists to the test audit agent as input — the audit agent itself
  # has read-only tools (Read, Grep, Glob) and cannot run git commands"
  if grep -qiE "(passes both lists|pass(es)?.*lists?.*(audit|agent)|both.*lists?.*(audit|agent))" <<< "$non_blockquote"; then
    pass "R-003(i)" "ctdd test audit orchestrator documents passing both lists to audit agent"
  else
    fail "R-003(i)" "ctdd test audit orchestrator missing 'passes both lists' or equivalent in non-blockquote prose"
  fi

  # Tests R-003 [unit]: class fix QA-004 — no trailing-slash bare-directory globs in producer table (does not detect wildcard-at-directory or prefix-collision patterns; see R-003(k))
  _bare_dir_found=0
  while IFS= read -r _row; do
    [ -z "$_row" ] && continue
    _artifact_cell="$(echo "$_row" | awk -F'|' '{print $3}')"
    _artifact_path="$(echo "$_artifact_cell" | grep -o '`[^`]*`' | tr -d '`' | head -1)"
    [ -z "$_artifact_path" ] && continue
    _final="${_artifact_path##*/}"
    if [ -z "$_final" ]; then
      _bare_dir_found=1
    fi
  done < <(grep '| `/' <<< "$check11_block" || true)
  if [ "$_bare_dir_found" -eq 0 ] && [ -n "$check11_block" ]; then
    pass "R-003(j)" "no trailing-slash bare-directory globs in producer-to-artifact table (QA-004 class fix)"
  elif [ -z "$check11_block" ]; then
    fail "R-003(j)" "check 11 block not found — cannot validate producer table"
  else
    fail "R-003(j)" "producer-to-artifact table contains a bare-directory glob (ends in '/' with no file component)"
  fi

  # Tests R-003 [unit]: class fix QA-006 — /cdocs row must carry the cost-cache exclusion
  _cdocs_row="$(grep '/cdocs' <<< "$check11_block" | head -1)"
  if grep -qF 'cost-*.json' <<< "$_cdocs_row" && grep -qF 'cost-cache-*' <<< "$_cdocs_row"; then
    pass "R-003(k)" "/cdocs producer row contains cost-*.json with cost-cache-* exclusion (QA-006 class fix)"
  else
    fail "R-003(k)" "/cdocs producer row missing cost-*.json and/or cost-cache-* exclusion (QA-006 class fix)"
  fi

  # Tests R-003 [unit]: class fix MA-104 — anti-anchoring language pinned
  if grep -qF "data to format-compare" <<< "$check11_block" && grep -qF "not as instructions" <<< "$check11_block"; then
    pass "R-003(l)" "ctdd check 11 block contains anti-anchoring language (MA-104)"
  else
    fail "R-003(l)" "ctdd check 11 block missing 'data to format-compare' and/or 'not as instructions' (MA-104)"
  fi

  # Tests R-003 [unit]: class fix MA-112 — absent-list sentinel pinned
  if grep -qF "Check 11 cannot run" <<< "$check11_block"; then
    pass "R-003(m)" "ctdd check 11 block contains absent-list sentinel (MA-112)"
  else
    fail "R-003(m)" "ctdd check 11 block missing 'Check 11 cannot run' sentinel (MA-112)"
  fi

  # Tests R-003 [unit]: class fix MA-209 — budget cap pinned
  if grep -qF "at most 10 fixture files" <<< "$check11_block"; then
    pass "R-003(n)" "ctdd check 11 block contains fixture budget cap (MA-209)"
  else
    fail "R-003(n)" "ctdd check 11 block missing 'at most 10 fixture files' (MA-209)"
  fi

  # Tests R-003 [unit]: class fix MA-216 — live-read exclusion pinned
  if grep -qF "live" <<< "$check11_block" && grep -qF "does NOT count" <<< "$check11_block"; then
    pass "R-003(o)" "ctdd check 11 block contains live-read exclusion (MA-216)"
  else
    fail "R-003(o)" "ctdd check 11 block missing 'live' and/or 'does NOT count' (MA-216)"
  fi

  # Tests R-003 [unit]: class fix MA-220 — scope clarification pinned
  if grep -qF "retroactive real-fixture retrofits" <<< "$check11_block"; then
    pass "R-003(p)" "ctdd check 11 block contains scope clarification (MA-220)"
  else
    fail "R-003(p)" "ctdd check 11 block missing 'retroactive real-fixture retrofits' (MA-220)"
  fi

  # Tests R-003 [unit]: class fix MA-211 — language-aware citation pinned
  if grep -qF "// Source:" <<< "$check11_block"; then
    pass "R-003(q)" "ctdd check 11 block contains language-aware citation syntax (MA-211)"
  else
    fail "R-003(q)" "ctdd check 11 block missing '// Source:' citation form (MA-211)"
  fi
fi

# ============================================================================
# R-004 [unit]: A structural test file exists under tests/ that verifies
# keywords appear within the correct section of each file (block-scoped,
# not file-wide — mitigates AP-003).
# This is a meta-test: the structural test IS this file. We assert it exists
# and uses awk-based section extraction rather than file-wide grep.
# ============================================================================

section "R-004: Structural test uses block-scoped extraction (meta)"

THIS_TEST="$REPO_DIR/tests/test-ap031-fixture-divergence.sh"

# Tests R-004 [unit]: structural test file exists
if [ -f "$THIS_TEST" ]; then
  pass "R-004(a)" "tests/test-ap031-fixture-divergence.sh exists"
else
  fail "R-004(a)" "tests/test-ap031-fixture-divergence.sh does not exist"
fi

# Tests R-004 [unit]: structural test uses awk-based block extraction, not file-wide grep.
# Verifies this test file itself implements the block-scoped checking it mandates.
if grep -qF "awk" "$THIS_TEST" && grep -qE "found=1" "$THIS_TEST"; then
  pass "R-004(b)" "test file uses awk state-machine for block-scoped section extraction"
else
  fail "R-004(b)" "test file missing awk-based section extraction (AP-003 mitigation not applied)"
fi

# ============================================================================
# R-005 [unit]: Distribution copies match source copies after sync.sh runs.
# GUARD TEST — expected to PASS in RED phase (both copies equally lack the
# new directives). Guards the GREEN phase sync step: after GREEN edits the
# source files, sync.sh must propagate so this test continues to pass.
# ============================================================================

section "R-005: Distribution parity guard (expected PASS in RED)"

# Tests R-005 [unit] (guard): skills/cspec/SKILL.md matches correctless/ copy
if [ ! -f "$DIST_CSPEC" ]; then
  fail "R-005(a)" "correctless/skills/cspec/SKILL.md not found (sync.sh not run?)"
elif diff -q "$CSPEC_SKILL" "$DIST_CSPEC" > /dev/null 2>&1; then
  pass "R-005(a)" "skills/cspec/SKILL.md matches correctless/skills/cspec/SKILL.md"
else
  fail "R-005(a)" "skills/cspec/SKILL.md diverges from correctless/skills/cspec/SKILL.md (run sync.sh)"
fi

# Tests R-005 [unit] (guard): skills/ctdd/SKILL.md matches correctless/ copy
if [ ! -f "$DIST_CTDD" ]; then
  fail "R-005(b)" "correctless/skills/ctdd/SKILL.md not found"
elif diff -q "$CTDD_SKILL" "$DIST_CTDD" > /dev/null 2>&1; then
  pass "R-005(b)" "skills/ctdd/SKILL.md matches correctless/skills/ctdd/SKILL.md"
else
  fail "R-005(b)" "skills/ctdd/SKILL.md diverges from correctless/skills/ctdd/SKILL.md (run sync.sh)"
fi

# Tests R-005 [unit] (guard): agents/ctdd-red.md matches correctless/ copy
if [ ! -f "$DIST_CTDD_RED" ]; then
  fail "R-005(c)" "correctless/agents/ctdd-red.md not found"
elif diff -q "$CTDD_RED_AGENT" "$DIST_CTDD_RED" > /dev/null 2>&1; then
  pass "R-005(c)" "agents/ctdd-red.md matches correctless/agents/ctdd-red.md"
else
  fail "R-005(c)" "agents/ctdd-red.md diverges from correctless/agents/ctdd-red.md (run sync.sh)"
fi

# ============================================================================
# R-006 [unit]: .correctless/AGENT_CONTEXT.md references the AP-031
# real-fixture requirement in the ctdd-red agent row (Key Components table)
# or the Design Patterns section.
# Also verifies test count reflects new test file.
# BLOCK-SCOPED: Agents table row and Design Patterns section (R-004).
# ============================================================================

section "R-006: AGENT_CONTEXT.md updated with AP-031 requirement (block-scoped)"

if [ ! -f "$AGENT_CONTEXT" ]; then
  fail "R-006(a)" ".correctless/AGENT_CONTEXT.md not found"
  fail "R-006(b)" ".correctless/AGENT_CONTEXT.md not found"
  fail "R-006(c)" ".correctless/AGENT_CONTEXT.md not found"
else
  # BLOCK-SCOPED (R-004): extract the Agents row from the Key Components table.
  # The table row starts with "| Agents |" and contains ctdd-red in the description.
  agents_row="$(grep -E "^\| Agents \|" "$AGENT_CONTEXT" || true)"

  # BLOCK-SCOPED (R-004): extract the Design Patterns section.
  design_patterns_block="$(awk '
    /^## Design Patterns/{found=1}
    found && /^## [A-Z]/ && !/^## Design Patterns/{exit}
    found{print}
  ' "$AGENT_CONTEXT")"

  # Tests R-006 [unit]: AP-031 referenced in agents row OR Design Patterns section.
  # Spec: "the ctdd-red agent row or Design Patterns section references the
  # AP-031 real-fixture requirement."
  if grep -qF "AP-031" <<< "$agents_row" || grep -qF "AP-031" <<< "$design_patterns_block"; then
    pass "R-006(a)" "AGENT_CONTEXT.md references AP-031 in agents row or Design Patterns section"
  else
    fail "R-006(a)" "AGENT_CONTEXT.md missing AP-031 reference in agents row or Design Patterns section"
  fi

  # Tests R-006 [unit]: "real-fixture" or "real artifact" referenced in scope.
  # The new requirement phrase should appear in the ctdd-red agent description or patterns section.
  if grep -qiE "real.artifact|real.fixture" <<< "$agents_row" || \
     grep -qiE "real.artifact|real.fixture" <<< "$design_patterns_block"; then
    pass "R-006(b)" "AGENT_CONTEXT.md contains real-fixture/real-artifact reference in relevant section"
  else
    fail "R-006(b)" "AGENT_CONTEXT.md missing real-fixture/real-artifact in agents row or Design Patterns"
  fi

  # --- R-006(c) BLOCK START (agent-context-count-sync #219 / INV-002/004, EXT-003) ---
  # Tests R-006(c) [integration]: test-count freshness is decoupled from the
  # INV-010-protected AGENT_CONTEXT.md onto the tracked, unprotected, generated
  # artifact tests/test-inventory.json ({schema_version,test_file_count}).
  #
  # R-006(c) reads `test_file_count` from tests/test-inventory.json and asserts it
  # EQUALS "actual", where "actual" is obtained ONLY from the SHARED count command
  # `bash scripts/gen-test-inventory.sh count` (INV-002 / PRH-003). This block MUST
  # NOT re-implement any counting primitive (find / wc -l / grep -c / ls-pipe /
  # ${#arr[@]}) to compute "actual" — that would let writer and consumer drift.
  # Exact `==`, NO band (EXT-003). Fail-closed with a copy-pasteable remediation
  # string containing exactly `bash scripts/gen-test-inventory.sh write` on: missing
  # artifact, malformed artifact (invalid JSON / missing test_file_count /
  # string-typed / fractional / schema_version absent or != 1), jq absent, or a
  # stale count mismatch. R-006(a)/(b) above (AP-031 checks) are UNCHANGED — R-006(c)
  # no longer reads any figure from AGENT_CONTEXT.md.
  INVENTORY_ARTIFACT="$REPO_DIR/tests/test-inventory.json"
  GEN_SCRIPT="$REPO_DIR/scripts/gen-test-inventory.sh"
  # Copy-pasteable remediation — MUST contain the exact source-repo command.
  REMEDIATION="regenerate the artifact: bash scripts/gen-test-inventory.sh write"

  if ! command -v jq >/dev/null 2>&1; then
    fail "R-006(c)" "jq not found — cannot validate tests/test-inventory.json fail-closed — $REMEDIATION"
  elif [ ! -f "$GEN_SCRIPT" ]; then
    fail "R-006(c)" "scripts/gen-test-inventory.sh missing — cannot compute actual via the shared count command — $REMEDIATION"
  elif [ ! -f "$INVENTORY_ARTIFACT" ]; then
    fail "R-006(c)" "tests/test-inventory.json missing — $REMEDIATION"
  elif ! jq -e '.schema_version == 1' "$INVENTORY_ARTIFACT" >/dev/null 2>&1; then
    fail "R-006(c)" "tests/test-inventory.json is malformed (invalid JSON or schema_version absent/!=1) — $REMEDIATION"
  elif ! jq -e '.test_file_count | (type=="number" and . >= 0 and floor == .)' "$INVENTORY_ARTIFACT" >/dev/null 2>&1; then
    fail "R-006(c)" "tests/test-inventory.json test_file_count is missing or non-integer (string/fractional) — $REMEDIATION"
  else
    inv_count="$(jq -r '.test_file_count' "$INVENTORY_ARTIFACT" 2>/dev/null || true)"
    # "actual" comes ONLY from the shared generator command (never a local find|wc).
    actual_count="$(bash "$GEN_SCRIPT" count 2>/dev/null || true)"
    if ! printf '%s' "$actual_count" | grep -qE '^[0-9]+$'; then
      fail "R-006(c)" "gen-test-inventory.sh count did not return an integer (got '$actual_count') — $REMEDIATION"
    elif [ "$inv_count" = "$actual_count" ]; then
      pass "R-006(c)" "tests/test-inventory.json count ($inv_count) == actual ($actual_count) via shared count command"
    else
      fail "R-006(c)" "tests/test-inventory.json count ($inv_count) != actual ($actual_count) — stale; $REMEDIATION"
    fi
  fi
  # --- R-006(c) BLOCK END ---
fi

# ============================================================================
# Summary
# ============================================================================

summary "AP-031 Fixture Divergence Prevention Tests"
