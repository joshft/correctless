#!/usr/bin/env bash
# shellcheck disable=SC1090,SC1091,SC2086,SC2016,SC2034
# Correctless — /cdebug Autonomous Contract test suite
# Tests INV-006 (a)-(f) and INV-009 (the /cdebug-hop portion) from
# .correctless/specs/cchores.md
#
# RED phase: these tests MUST FAIL — the /cdebug autonomous rewrite and
# agents/cdebug-fix.md do not exist yet.
# Run from repo root: bash tests/test-cdebug-autonomous.sh
#
# STUB:TDD — GREEN delivers: skills/cdebug/SKILL.md rewrite (autonomous mode +
# Task in allowed-tools + frontmatter), agents/cdebug-fix.md (NEW), plus their
# correctless/ mirrors. Until then every assertion below fails or skips-as-fail.
#
# Case → INV-006 sub-part mapping is documented in the section headers and in
# the final summary block returned to the orchestrator.

source "$(dirname "${BASH_SOURCE[0]}")/test-helpers.sh"

# ============================================================================
# Constants — deliverables under test (absent/unmodified now)
# ============================================================================

CDEBUG_SKILL="$REPO_DIR/skills/cdebug/SKILL.md"
CDEBUG_SKILL_MIRROR="$REPO_DIR/correctless/skills/cdebug/SKILL.md"
FIX_AGENT="$REPO_DIR/agents/cdebug-fix.md"
FIX_AGENT_MIRROR="$REPO_DIR/correctless/agents/cdebug-fix.md"

# Body of the cdebug skill with frontmatter stripped — used for guard-proximity
# checks so a guard in frontmatter cannot be mistaken for a step-block guard.
if [ -f "$CDEBUG_SKILL" ]; then
  CDEBUG_BODY="$(skill_body "$CDEBUG_SKILL")"
else
  CDEBUG_BODY=""
fi

# ============================================================================
# Helpers
# ============================================================================

# Print the line numbers (in the skill body) of lines matching a fixed phrase.
# Used to locate human-interaction phrases and assert a mode guard lives in the
# SAME step block (within a bounded window), not merely appended elsewhere.
body_line_numbers() {
  local phrase="$1"
  printf '%s\n' "$CDEBUG_BODY" | grep -niF "$phrase" | cut -d: -f1
}

# Returns 0 if a "mode guard" phrase appears within +/- WINDOW lines of ANY
# line matching the human-interaction phrase. A mode guard is any of the
# canonical autonomous-gating phrasings the spec allows ("if mode != autonomous"
# or equivalent). This is the structural co-occurrence test for INV-006(a)/(e).
GUARD_WINDOW=18
guard_near_phrase() {
  local phrase="$1"
  local total guard_lines ln g
  [ -n "$CDEBUG_BODY" ] || return 1
  total="$(printf '%s\n' "$CDEBUG_BODY" | wc -l)"

  # Line numbers where a mode-guard token appears.
  # Accept several equivalent phrasings so GREEN isn't forced into one wording.
  guard_lines="$(printf '%s\n' "$CDEBUG_BODY" | grep -niE \
    'mode[[:space:]]*(!=|≠|is not|isn'\''t|not)[[:space:]]*autonomous|not[[:space:]]+(in[[:space:]]+)?autonomous|unless[[:space:]]+autonomous|interactive[[:space:]]+(or[[:space:]]+hybrid|/[[:space:]]*hybrid|and[[:space:]]+hybrid)[[:space:]]+mode|when[[:space:]]+mode[[:space:]]+is[[:space:]]+(interactive|hybrid|absent)|skip[[:space:]]+(this[[:space:]]+)?(step[[:space:]]+)?(in|under|when)[[:space:]]+autonomous|if[[:space:]]+mode[[:space:]]*==[[:space:]]*autonomous' \
    | cut -d: -f1)"
  [ -n "$guard_lines" ] || return 1

  for ln in $(body_line_numbers "$phrase"); do
    for g in $guard_lines; do
      local lo=$(( ln - GUARD_WINDOW ))
      local hi=$(( ln + GUARD_WINDOW ))
      if [ "$g" -ge "$lo" ] && [ "$g" -le "$hi" ]; then
        return 0
      fi
    done
  done
  return 1
}

# ============================================================================
# Precondition: deliverables must eventually exist. In RED they do not.
# ============================================================================

section "Precondition: deliverables exist (RED: expected to FAIL)"

if [ -f "$CDEBUG_SKILL" ]; then
  pass "PRE-skill" "skills/cdebug/SKILL.md exists"
else
  fail "PRE-skill" "skills/cdebug/SKILL.md not found"
fi

if [ -f "$FIX_AGENT" ]; then
  pass "PRE-fixagent" "agents/cdebug-fix.md exists"
else
  fail "PRE-fixagent" "agents/cdebug-fix.md not found (NEW — GREEN must create)"
fi

# ============================================================================
# INV-006(a): Human-path gating — every human-interaction step is guarded by
# an explicit mode conditional IN ITS OWN step block, not merely shadowed by a
# new appended autonomous section.
# Human-interaction phrases to gate (from current cdebug SKILL.md):
#   - Phase 1 "Ask the human"
#   - Phase 3.5 "present to the human" (Fix Design)
#   - the bisect offer ("Want me to?")
#   - Phase 6 escalation-present ("Present the escalation analysis to the human")
# ============================================================================

section "INV-006(a): each human-interaction step has an in-block mode guard"

# (a1) Phase 1 — "Ask the human"
if [ -n "$CDEBUG_BODY" ] && grep -q . <<<"$(body_line_numbers "Ask the human")"; then
  if guard_near_phrase "Ask the human"; then
    pass "INV-006a-1" "Phase 1 'Ask the human' co-occurs with a mode guard in its block"
  else
    fail "INV-006a-1" "Phase 1 'Ask the human' present but NO mode guard within +/-${GUARD_WINDOW} lines (shadow-only is a violation)"
  fi
else
  fail "INV-006a-1" "Phase 1 'Ask the human' phrase not found in cdebug body (deliverable absent or text changed)"
fi

# (a2) Phase 3.5 — present the fix design to the human
if [ -n "$CDEBUG_BODY" ] && grep -q . <<<"$(body_line_numbers "present to the human")"; then
  if guard_near_phrase "present to the human"; then
    pass "INV-006a-2" "Phase 3.5 'present to the human' co-occurs with a mode guard in its block"
  else
    fail "INV-006a-2" "Phase 3.5 'present to the human' present but NO in-block mode guard"
  fi
else
  fail "INV-006a-2" "Phase 3.5 'present to the human' phrase not found (deliverable absent or text changed)"
fi

# (a3) Bisect offer — "Want me to?" (the interactive offer prompt)
if [ -n "$CDEBUG_BODY" ] && grep -q . <<<"$(body_line_numbers "Want me to?")"; then
  if guard_near_phrase "Want me to?"; then
    pass "INV-006a-3" "Bisect offer 'Want me to?' co-occurs with a mode guard in its block"
  else
    fail "INV-006a-3" "Bisect offer present but NO in-block mode guard (autonomous mode must not offer bisect)"
  fi
else
  fail "INV-006a-3" "Bisect offer 'Want me to?' phrase not found (deliverable absent or text changed)"
fi

# (a4) Phase 6 escalation present — "Present the escalation analysis to the human"
if [ -n "$CDEBUG_BODY" ] && grep -q . <<<"$(body_line_numbers "Present the escalation analysis to the human")"; then
  if guard_near_phrase "Present the escalation analysis to the human"; then
    pass "INV-006a-4" "Phase 6 escalation-present co-occurs with a mode guard in its block"
  else
    fail "INV-006a-4" "Phase 6 escalation-present present but NO in-block mode guard"
  fi
else
  fail "INV-006a-4" "Phase 6 escalation-present phrase not found (deliverable absent or text changed)"
fi

# (a5) Anti-shadow structural assertion: a single appended ## Autonomous Mode
# section that merely overrides everything is NOT sufficient. There must be at
# least as many in-block mode guards as there are human-interaction phrases.
# This catches the RS-002/codex "shadowed by a new appended section" failure.
if [ -n "$CDEBUG_BODY" ]; then
  guard_total="$(printf '%s\n' "$CDEBUG_BODY" | grep -ciE \
    'mode[[:space:]]*(!=|≠|is not|isn'\''t|not)[[:space:]]*autonomous|not[[:space:]]+(in[[:space:]]+)?autonomous|unless[[:space:]]+autonomous|skip[[:space:]]+(this[[:space:]]+)?(step[[:space:]]+)?(in|under|when)[[:space:]]+autonomous|when[[:space:]]+mode[[:space:]]+is[[:space:]]+(interactive|hybrid|absent)' || true)"
  if [ "${guard_total:-0}" -ge 4 ]; then
    pass "INV-006a-5" "At least 4 in-block mode guards present (one per human-interaction step, not a single shadow section)"
  else
    fail "INV-006a-5" "Only ${guard_total:-0} mode guards found; expected >=4 (one per gated human-interaction step). A single appended override section is a violation."
  fi
else
  fail "INV-006a-5" "cdebug body empty — cannot count in-block mode guards"
fi

# ============================================================================
# INV-006(b): Agent separation wired — the fix agent is a REAL
# agents/cdebug-fix.md (read+write+bash pinned/closed), Task is in /cdebug's
# allowed-tools, and the test-writer and fix-writer are two DISTINCT
# Task(subagent_type=...) invocations.
# ============================================================================

section "INV-006(b): agent separation wired (real agent + Task + two distinct subagents)"

# (b1) agents/cdebug-fix.md exists with closed tools allowlist incl read+write+bash
if [ -f "$FIX_AGENT" ]; then
  tools_line="$(get_frontmatter_field "$FIX_AGENT" "tools")"
  has_read=$(grep -qiw 'Read' <<<"$tools_line" && echo 1 || echo 0)
  has_write=$(grep -qiw 'Write' <<<"$tools_line" && echo 1 || echo 0)
  has_bash=$(grep -qiw 'Bash' <<<"$tools_line" && echo 1 || echo 0)
  if [ "$has_read" = 1 ] && [ "$has_write" = 1 ] && [ "$has_bash" = 1 ]; then
    pass "INV-006b-1" "agents/cdebug-fix.md frontmatter tools include Read + Write + Bash (pinned): $tools_line"
  else
    fail "INV-006b-1" "agents/cdebug-fix.md tools missing one of Read/Write/Bash (got: '$tools_line')"
  fi
else
  fail "INV-006b-1" "agents/cdebug-fix.md not found — fix agent must be a real agent file (AP-013, not inline prose)"
fi

# (b2) the fix agent allowlist is CLOSED — uses tools: alone, no disallowed-tools
# (agents use the closed tools: allowlist convention, R4-4 — disallowed-tools is
# a skill-frontmatter convention).
if [ -f "$FIX_AGENT" ]; then
  if get_frontmatter_field "$FIX_AGENT" "tools" >/dev/null 2>&1; then
    if grep -qi 'disallowed-tools' <<<"$(extract_frontmatter "$FIX_AGENT")"; then
      fail "INV-006b-2" "agents/cdebug-fix.md uses disallowed-tools (agents must use a closed tools: allowlist alone — R4-4)"
    else
      pass "INV-006b-2" "agents/cdebug-fix.md uses a closed tools: allowlist (no disallowed-tools)"
    fi
  else
    fail "INV-006b-2" "agents/cdebug-fix.md has no tools: allowlist (must be pinned/closed)"
  fi
else
  fail "INV-006b-2" "agents/cdebug-fix.md not found (cannot check closed allowlist)"
fi

# (b3) the fix agent must NOT carry Task (no sub-agent spawning from the leaf fix agent)
if [ -f "$FIX_AGENT" ]; then
  tools_line="$(get_frontmatter_field "$FIX_AGENT" "tools")"
  if grep -qiw 'Task' <<<"$tools_line"; then
    fail "INV-006b-3" "agents/cdebug-fix.md tools include Task — leaf fix agent must not spawn sub-agents"
  else
    pass "INV-006b-3" "agents/cdebug-fix.md does not carry Task (leaf agent)"
  fi
else
  fail "INV-006b-3" "agents/cdebug-fix.md not found (cannot check Task absence)"
fi

# (b4) Task is present in /cdebug's allowed-tools frontmatter
if [ -f "$CDEBUG_SKILL" ]; then
  allowed="$(get_frontmatter_field "$CDEBUG_SKILL" "allowed-tools")"
  if grep -qw 'Task' <<<"$allowed"; then
    pass "INV-006b-4" "/cdebug allowed-tools includes Task"
  else
    fail "INV-006b-4" "/cdebug allowed-tools does NOT include Task (got: '$allowed')"
  fi
else
  fail "INV-006b-4" "skills/cdebug/SKILL.md not found (cannot check allowed-tools)"
fi

# (b5) test-writer and fix-writer are two DISTINCT Task(subagent_type=...) invocations.
# Assert both invocations exist and reference different subagents. The fix agent
# must be referenced by its real name (cdebug-fix); the test-writer references a
# different subagent_type. We assert >=2 distinct subagent_type values in the body.
if [ -n "$CDEBUG_BODY" ]; then
  # Collect distinct subagent_type identifiers referenced in Task invocations.
  subagents="$(printf '%s\n' "$CDEBUG_BODY" \
    | grep -oE 'subagent_type[[:space:]]*[:=][[:space:]]*["'\'']?[A-Za-z0-9:_-]+' \
    | sed -E 's/.*[:=][[:space:]]*["'\'']?//' | sort -u)"
  distinct_count="$(printf '%s\n' "$subagents" | grep -c . || true)"

  refs_fix_agent=$(grep -qiE 'subagent_type[^A-Za-z0-9]+[^"'\'' ]*cdebug-fix' <<<"$CDEBUG_BODY" && echo 1 || echo 0)

  if [ "${distinct_count:-0}" -ge 2 ]; then
    pass "INV-006b-5" "Two+ distinct Task(subagent_type=...) invocations found: $(printf '%s ' $subagents)"
  else
    fail "INV-006b-5" "Expected >=2 distinct Task(subagent_type=...) invocations (test-writer + fix-writer); found ${distinct_count:-0}: $(printf '%s ' $subagents)"
  fi

  if [ "$refs_fix_agent" = 1 ]; then
    pass "INV-006b-6" "/cdebug Task-invokes the cdebug-fix agent by subagent_type"
  else
    fail "INV-006b-6" "/cdebug does not Task-invoke cdebug-fix by subagent_type (fix-writer must be the real agent)"
  fi
else
  fail "INV-006b-5" "cdebug body empty — cannot count Task invocations"
  fail "INV-006b-6" "cdebug body empty — cannot check cdebug-fix invocation"
fi

# ============================================================================
# INV-006(c): Structured outcome — /cdebug emits a terminal block
# {outcome: fixed|escalated|unfixable, repro_test_path, files_changed[], summary}
# as its LAST block; schema pinned. Assert the SKILL documents this exact schema.
# ============================================================================

section "INV-006(c): structured terminal outcome block schema is documented"

if [ -n "$CDEBUG_BODY" ]; then
  c_fields=0
  for field in "outcome" "repro_test_path" "files_changed" "summary"; do
    if grep -q "$field" <<<"$CDEBUG_BODY"; then
      c_fields=$((c_fields + 1))
    fi
  done
  if [ "$c_fields" -eq 4 ]; then
    pass "INV-006c-1" "Terminal outcome schema documents all 4 fields (outcome, repro_test_path, files_changed, summary)"
  else
    fail "INV-006c-1" "Terminal outcome schema missing fields ($c_fields/4 of outcome/repro_test_path/files_changed/summary)"
  fi

  # The three outcome values must be enumerated together (the pinned enum).
  if grep -qE 'fixed[^A-Za-z]+escalated[^A-Za-z]+unfixable|outcome:[[:space:]]*fixed\|escalated\|unfixable' <<<"$CDEBUG_BODY"; then
    pass "INV-006c-2" "outcome enum 'fixed|escalated|unfixable' is pinned in the schema"
  else
    fail "INV-006c-2" "outcome enum 'fixed|escalated|unfixable' not pinned together in the schema"
  fi

  # The schema must be documented as the LAST / terminal block.
  if grep -qiE 'last block|terminal block|final block|final output|as its last|emit.*last' <<<"$CDEBUG_BODY"; then
    pass "INV-006c-3" "schema is documented as the LAST/terminal block"
  else
    fail "INV-006c-3" "schema not documented as the terminal/last block (consumer relies on terminal placement)"
  fi
else
  fail "INV-006c-1" "cdebug body empty — cannot check outcome schema"
  fail "INV-006c-2" "cdebug body empty — cannot check outcome enum"
  fail "INV-006c-3" "cdebug body empty — cannot check terminal placement"
fi

# ============================================================================
# INV-006(d): Fail-closed parse-gate contract is documented in cdebug, and the
# schema supports it: absent/malformed/partial/non-terminal/schema-invalid
# output → treated as `escalated`. The PMB-009 truncation case (successful
# return with no/partial outcome block = abort/escalate) must be documented.
# ============================================================================

section "INV-006(d): fail-closed parse-gate contract + PMB-009 truncation documented"

if [ -n "$CDEBUG_BODY" ]; then
  # Exactly the three outcome values — no fourth value introduced.
  enum_tokens="$(printf '%s\n' "$CDEBUG_BODY" \
    | grep -oE 'outcome:[[:space:]]*[a-z|]+' | head -1)"
  # Independent check: the body must NOT enumerate a fourth canonical outcome value.
  if grep -qE '\b(partial|truncated|completed|success|unknown)\b[^A-Za-z]*(is|maps|treated)[^A-Za-z]*escalat' <<<"$CDEBUG_BODY"; then
    pass "INV-006d-1" "non-terminal/partial/truncated outcome is documented as mapping to escalated"
  else
    fail "INV-006d-1" "no documented mapping of partial/truncated/non-terminal output -> escalated"
  fi

  # Fail-closed wording: absent/malformed/partial -> escalated/abort
  if grep -qiE 'fail.?closed|absent.*escalat|malformed.*escalat|partial.*escalat|cannot be parsed.*escalat|treated as escalat' <<<"$CDEBUG_BODY"; then
    pass "INV-006d-2" "fail-closed parse-gate (absent/malformed -> escalated) is documented"
  else
    fail "INV-006d-2" "fail-closed parse-gate behavior not documented (absent/malformed must -> escalated)"
  fi

  # PMB-009: successful Task return with no/partial outcome block is an abort trigger.
  if grep -qiE 'PMB-009|truncat.*(return|fork|complete)|successful return.*(no|partial|missing).*outcome|completed.*but.*(no|missing|partial).*outcome' <<<"$CDEBUG_BODY"; then
    pass "INV-006d-3" "PMB-009 truncation case (successful return with no/partial outcome -> escalate) is documented"
  else
    fail "INV-006d-3" "PMB-009 truncation case not documented (successful-return-but-no-outcome must escalate, not pass)"
  fi
else
  fail "INV-006d-1" "cdebug body empty — cannot check escalate mapping"
  fail "INV-006d-2" "cdebug body empty — cannot check fail-closed wording"
  fail "INV-006d-3" "cdebug body empty — cannot check PMB-009 truncation"
fi

# ============================================================================
# INV-006(e): No outward interaction under autonomous mode — every
# present/offer/escalate-to-human phrase is mode-guarded; failure paths map to
# structured `escalated`.
# ============================================================================

section "INV-006(e): no present/offer/escalate-to-human under autonomous mode"

# (e1)-(e3): each outward-interaction verb phrase must be near a mode guard.
e_phrases=("present to the human" "Present the escalation analysis to the human" "Want me to?")
e_idx=0
for ph in "${e_phrases[@]}"; do
  e_idx=$((e_idx + 1))
  if [ -n "$CDEBUG_BODY" ] && grep -q . <<<"$(body_line_numbers "$ph")"; then
    if guard_near_phrase "$ph"; then
      pass "INV-006e-$e_idx" "outward-interaction phrase '$ph' is mode-guarded"
    else
      fail "INV-006e-$e_idx" "outward-interaction phrase '$ph' is NOT mode-guarded (would interact with human under autonomous mode)"
    fi
  else
    fail "INV-006e-$e_idx" "outward-interaction phrase '$ph' not found (deliverable absent or text changed)"
  fi
done

# (e4): autonomous failure paths explicitly map to the structured escalated outcome
if [ -n "$CDEBUG_BODY" ]; then
  if grep -qiE 'autonomous.*(escalat|map.*escalated)|failure path.*escalat|under autonomous.*outcome.*escalated|emit.*escalated.*(instead|rather than).*present' <<<"$CDEBUG_BODY"; then
    pass "INV-006e-4" "autonomous failure paths documented to map to the structured 'escalated' outcome"
  else
    fail "INV-006e-4" "autonomous failure paths not documented to map to 'escalated' (must not present/offer to human)"
  fi
else
  fail "INV-006e-4" "cdebug body empty — cannot check autonomous failure mapping"
fi

# ============================================================================
# INV-006(f): Non-regression of interactive cdebug — with NO mode (or hybrid),
# the human-prompt paths STILL execute. Assert the human-interaction text
# remains present AND reachable (i.e., the guards are conditional, not deletions).
# ============================================================================

section "INV-006(f): interactive cdebug non-regression (human paths still present + reachable)"

# (f1) All four human-interaction phrases must STILL be present in the body —
# the autonomous rewrite must not DELETE interactive behavior.
f_phrases=("Ask the human" "present to the human" "Want me to?" "Present the escalation analysis to the human")
f_missing=""
for ph in "${f_phrases[@]}"; do
  if [ -n "$CDEBUG_BODY" ] && grep -q . <<<"$(body_line_numbers "$ph")"; then
    :
  else
    f_missing="${f_missing}[$ph] "
  fi
done
if [ -z "$f_missing" ] && [ -n "$CDEBUG_BODY" ]; then
  pass "INV-006f-1" "All four human-interaction phrases remain present (interactive behavior not deleted)"
else
  fail "INV-006f-1" "Human-interaction phrase(s) deleted by the autonomous rewrite: ${f_missing:-<body absent>}"
fi

# (f2) The frontmatter interaction_mode must NOT be hard-set to autonomous —
# interactive/hybrid behavior must remain the default when no mode is supplied.
if [ -f "$CDEBUG_SKILL" ]; then
  fm_mode="$(get_frontmatter_field "$CDEBUG_SKILL" "interaction_mode")"
  if [ "$fm_mode" = "autonomous" ]; then
    fail "INV-006f-2" "/cdebug frontmatter interaction_mode is hard-set to 'autonomous' — interactive non-regression broken (must be hybrid/interactive default)"
  elif [ -n "$fm_mode" ]; then
    pass "INV-006f-2" "/cdebug default interaction_mode is '$fm_mode' (not hard-autonomous; interactive path reachable)"
  else
    fail "INV-006f-2" "/cdebug has no interaction_mode frontmatter field (R-001 of autonomous-skill-contract)"
  fi
else
  fail "INV-006f-2" "skills/cdebug/SKILL.md not found (cannot check default mode)"
fi

# (f3) The guards must be CONDITIONAL ("if mode != autonomous") — not an
# unconditional removal. Behavioral proxy: every gated human phrase has a guard
# whose condition references autonomous (already asserted in (a)); here we assert
# the guard phrasing is conditional ("if"/"when"/"unless"), not an absolute "never".
if [ -n "$CDEBUG_BODY" ]; then
  if grep -qiE '(if|when|unless)[^.]*(mode|autonomous)' <<<"$CDEBUG_BODY"; then
    pass "INV-006f-3" "human-path guards are conditional (if/when/unless mode ...), preserving interactive reachability"
  else
    fail "INV-006f-3" "no conditional (if/when/unless) mode guard found — guards must be conditional, not unconditional removals"
  fi
else
  fail "INV-006f-3" "cdebug body empty — cannot check conditional guard phrasing"
fi

# ============================================================================
# INV-009 (the /cdebug-hop portion): the nonce-fence data-not-instructions
# directive is RE-ASSERTED inside /cdebug's autonomous-contract section (the
# fence lives in the caller's prompt; the directive must survive the Task hop),
# AND agents/cdebug-fix.md carries the prompt-level data-not-instructions
# directive.
# ============================================================================

section "INV-009: data-not-instructions directive survives the Task hop"

# (009-1) /cdebug autonomous-contract section re-asserts the directive.
if [ -n "$CDEBUG_BODY" ]; then
  if grep -qiE 'data,? not instructions|treat.*(issue|untrusted).*(content|body|text).*as data|never (execute|act on|obey).*(imperatives|instructions).*(in|within|from).*(issue|content)|nonce.?fence|do not follow instructions (in|within|from)' <<<"$CDEBUG_BODY"; then
    pass "INV-009-1" "/cdebug re-asserts the data-not-instructions directive (survives the Task hop)"
  else
    fail "INV-009-1" "/cdebug autonomous-contract section does NOT re-assert the nonce-fence/data-not-instructions directive"
  fi
else
  fail "INV-009-1" "cdebug body empty — cannot check directive re-assertion"
fi

# (009-2) The directive must specifically be tied to the untrusted issue content
# arriving via the autonomous-mode input (not a generic security boilerplate line).
if [ -n "$CDEBUG_BODY" ]; then
  if grep -qiE 'autonomous.*(nonce|fence|data,? not instructions|untrusted (issue|content))|(nonce|fence|untrusted (issue|content)).*autonomous' <<<"$CDEBUG_BODY"; then
    pass "INV-009-2" "directive is tied to the autonomous-mode untrusted-issue input"
  else
    fail "INV-009-2" "directive not tied to autonomous-mode untrusted-issue input (may be generic boilerplate, not hop-surviving)"
  fi
else
  fail "INV-009-2" "cdebug body empty — cannot check directive scoping"
fi

# (009-3) agents/cdebug-fix.md carries the prompt-level data-not-instructions directive.
if [ -f "$FIX_AGENT" ]; then
  if grep -qiE 'data,? not instructions|treat.*(issue|untrusted|input).*(content|body|text).*as data|never (execute|act on|obey|follow).*(imperatives|instructions)|do not follow instructions (in|within|from)|nonce.?fence' "$FIX_AGENT"; then
    pass "INV-009-3" "agents/cdebug-fix.md carries the prompt-level data-not-instructions directive"
  else
    fail "INV-009-3" "agents/cdebug-fix.md does NOT carry the data-not-instructions directive (fix agent receives untrusted content)"
  fi
else
  fail "INV-009-3" "agents/cdebug-fix.md not found (cannot check prompt-level directive)"
fi

# ============================================================================
# INV-006(g): Write-path gating — generalizes INV-006(a) beyond human-prompt
# phrases to ANY /cdebug phase that performs a non-artifact file write to a
# tracked project doc (e.g. the Phase 5 class-fix write to
# `.correctless/antipatterns.md`, which is NOT under `.correctless/artifacts/`
# or `.correctless/meta/`). An unguarded autonomous write to antipatterns.md
# leaks into the chore PR diff (INV-010 scope violation) and is an autonomous
# write to a shared doc driven by untrusted-issue input. Every write-bearing
# phase MUST co-occur with a `mode != autonomous` / `if mode` guard within its
# own step block. This assertion FAILS if Phase 5's guard is removed.
# ============================================================================

section "INV-006(g): write-bearing phases (antipatterns.md write) are mode-guarded"

# A "write-bearing" antipatterns.md line is one that instructs WRITING/EDITING
# the file (write verb adjacent to the path) — distinct from the read/check
# lines in Phase 2 ("Check antipatterns") and "Before You Start" (which are
# reads and must NOT be guarded). We isolate the write site by its write verb.
# Phrase pinned to the Phase 5 write instruction.
WRITE_PHRASE_5="add an antipattern entry to"

# Canonical autonomous-mode guard regex (shared by g1/g2). Matches the spec's
# allowed gating phrasings — same family as guard_near_phrase.
GUARD_REGEX='mode[[:space:]]*(!=|≠|is not|isn'\''t|not)[[:space:]]*autonomous|not[[:space:]]+(in[[:space:]]+)?autonomous|unless[[:space:]]+autonomous|skip[[:space:]]+(this[[:space:]]+)?(step[[:space:]]+)?(in|under|when)[[:space:]]+autonomous|when[[:space:]]+mode[[:space:]]+is[[:space:]]+autonomous|if[[:space:]]+mode[[:space:]]*==[[:space:]]*autonomous'

# Extract the body of a single ## section by its heading prefix, bounded by the
# next ## heading. Used to confine the guard search to the OWNING step block, so
# an ADJACENT phase's guard (e.g. Phase 6's "if mode != autonomous") cannot
# spuriously satisfy a Phase 5 write check via a wide proximity window
# (GUARD_WINDOW=18 is wider than the Phase-5→Phase-6 gap).
section_block() {
  local heading_prefix="$1"
  printf '%s\n' "$CDEBUG_BODY" | awk -v h="$heading_prefix" '
    index($0, "## " h) == 1 { inblk = 1; print; next }
    inblk && /^## / { inblk = 0 }
    inblk { print }
  '
}

PHASE5_BLOCK="$(section_block "Phase 5")"

# (g1) The Phase 5 write instruction exists AND a mode guard lives INSIDE the
# Phase 5 step block (header-bounded, not proximity-windowed). Removing the
# Phase 5 guard makes this FAIL even though Phase 6's guard is nearby.
if [ -n "$PHASE5_BLOCK" ] && grep -qiF "$WRITE_PHRASE_5" <<<"$PHASE5_BLOCK"; then
  if grep -qiE "$GUARD_REGEX" <<<"$PHASE5_BLOCK"; then
    pass "INV-006g-1" "Phase 5 block contains the antipatterns.md write AND an in-block autonomous-mode guard"
  else
    fail "INV-006g-1" "Phase 5 block has the antipatterns.md write but NO autonomous-mode guard INSIDE the block (autonomous run would write antipatterns.md -> INV-010 leak)"
  fi
else
  fail "INV-006g-1" "Phase 5 block or its antipatterns.md write phrase ('$WRITE_PHRASE_5') not found (deliverable absent or text changed)"
fi

# (g2) Generalized class assertion: for EVERY ## section block that contains a
# write-bearing antipatterns.md line (a write verb — add/write/append/edit/
# suppress — on the same line as the path), that SAME block must contain an
# autonomous-mode guard. Read/check-only blocks (Phase 2 "Check antipatterns",
# "Before You Start") have no write verb and are excluded. Confining the guard
# to the owning block (not a proximity window) means a future write-bearing
# phase without its own guard trips this — the class this finding generalizes.
if [ -n "$CDEBUG_BODY" ]; then
  # Heading names of all ## sections, in body order.
  mapfile -t g2_headings < <(grep -E '^## ' <<<"$CDEBUG_BODY" | sed -E 's/^## //')
  g2_write_blocks=0
  g2_unguarded=""
  for hd in "${g2_headings[@]}"; do
    blk="$(section_block "$hd")"
    # Is there a write-bearing antipatterns.md line in this block?
    if grep -iE 'antipatterns\.md' <<<"$blk" | grep -qiE '\b(add|write|append|edit|suppress|writing)\b'; then
      g2_write_blocks=$((g2_write_blocks + 1))
      if ! grep -qiE "$GUARD_REGEX" <<<"$blk"; then
        g2_unguarded="${g2_unguarded}[${hd}] "
      fi
    fi
  done
  if [ "$g2_write_blocks" -eq 0 ]; then
    fail "INV-006g-2" "no ## block with a write-bearing antipatterns.md line found (expected at least Phase 5)"
  elif [ -z "$g2_unguarded" ]; then
    pass "INV-006g-2" "all ${g2_write_blocks} write-bearing antipatterns.md block(s) contain an in-block autonomous-mode guard (write-path gating generalized from INV-006a)"
  else
    fail "INV-006g-2" "write-bearing antipatterns.md block(s) with NO in-block autonomous-mode guard: ${g2_unguarded}(unguarded autonomous write -> INV-010 PR leak)"
  fi
else
  fail "INV-006g-2" "cdebug body empty — cannot check write-path gating"
fi

# (g3) Non-regression: the suppression must be CONDITIONAL on autonomous mode,
# and the write instruction must STILL be present (interactive/hybrid still
# writes antipatterns.md). This mirrors INV-006(f) for the write path: the guard
# is a conditional gate, not a deletion of Phase 5.
if [ -n "$CDEBUG_BODY" ]; then
  if grep -q . <<<"$(body_line_numbers "$WRITE_PHRASE_5")" \
     && grep -qiE '(interactive|hybrid)[^.]*(still|perform|writ)|still[^.]*(perform|writ)[^.]*antipattern' <<<"$CDEBUG_BODY"; then
    pass "INV-006g-3" "antipatterns.md write retained for interactive/hybrid (suppression is a conditional guard, not a Phase 5 deletion)"
  else
    fail "INV-006g-3" "Phase 5 write deleted or interactive non-regression not stated (suppression must be conditional on autonomous mode only)"
  fi
else
  fail "INV-006g-3" "cdebug body empty — cannot check write-path non-regression"
fi

# ============================================================================
# Distribution parity: correctless/ mirrors must match (sync.sh propagation).
# In RED both source and mirror are absent → these fail.
# ============================================================================

section "Distribution parity: correctless/ mirrors of new deliverables"

# (mirror-1) cdebug skill mirror byte-equal to source
if [ -f "$CDEBUG_SKILL" ] && [ -f "$CDEBUG_SKILL_MIRROR" ]; then
  if diff -q "$CDEBUG_SKILL" "$CDEBUG_SKILL_MIRROR" >/dev/null 2>&1; then
    pass "MIRROR-1" "skills/cdebug/SKILL.md == correctless/ mirror (byte-equal)"
  else
    fail "MIRROR-1" "skills/cdebug/SKILL.md diverges from correctless/ mirror (run sync.sh)"
  fi
else
  fail "MIRROR-1" "cdebug SKILL.md source and/or mirror missing (sync parity unmet)"
fi

# (mirror-2) cdebug-fix agent mirror exists and byte-equal
if [ -f "$FIX_AGENT" ] && [ -f "$FIX_AGENT_MIRROR" ]; then
  if diff -q "$FIX_AGENT" "$FIX_AGENT_MIRROR" >/dev/null 2>&1; then
    pass "MIRROR-2" "agents/cdebug-fix.md == correctless/ mirror (byte-equal)"
  else
    fail "MIRROR-2" "agents/cdebug-fix.md diverges from correctless/ mirror (run sync.sh)"
  fi
else
  fail "MIRROR-2" "agents/cdebug-fix.md source and/or mirror missing (sync parity unmet)"
fi

# ============================================================================
# Summary
# ============================================================================

summary "/cdebug Autonomous Contract (INV-006 a-f, INV-009 hop)"
