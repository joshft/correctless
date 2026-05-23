#!/usr/bin/env bash
# shellcheck disable=SC1090,SC1091,SC2016,SC2086
# Correctless — Review-Driven Mini-Audit Lenses Structural Tests
#
# Enforces the review-driven-mini-audit-lenses spec rules (INV-001..INV-013,
# PRH-001..PRH-003, BND-001..BND-003, ABS-036).
# Tests are structural — they verify file content in skill SKILL.md files,
# workflow-advance.sh modules, and sync.sh.
#
# Run from repo root: bash tests/test-review-driven-lenses.sh

source "$(dirname "${BASH_SOURCE[0]}")/test-helpers.sh"
set -f

# ============================================================================
# File paths
# ============================================================================

CREVIEW_SPEC_SKILL="skills/creview-spec/SKILL.md"
CREVIEW_SKILL="skills/creview/SKILL.md"
CTDD_SKILL="skills/ctdd/SKILL.md"
CMETRICS_SKILL="skills/cmetrics/SKILL.md"
CWTF_SKILL="skills/cwtf/SKILL.md"
# DA-002: workflow-advance.sh is decomposed into modules. Search all files.
WF_ALL_FILES="hooks/workflow-advance.sh scripts/wf/transitions.sh scripts/wf/utility.sh scripts/wf/metadata.sh"

# ============================================================================
# INV-001 [unit]: Review skills write lens recommendations to artifact
# ============================================================================

section "INV-001: Review skills write lens recommendations"

# INV-001a: /creview-spec mentions lens-recommendations artifact path
if grep -q 'lens-recommendations' "$CREVIEW_SPEC_SKILL"; then
  pass "INV-001a" "/creview-spec references lens-recommendations artifact"
else
  fail "INV-001a" "/creview-spec does not reference lens-recommendations artifact"
fi

# INV-001b: /creview-spec writes recommended_lenses array
if grep -q 'recommended_lenses' "$CREVIEW_SPEC_SKILL"; then
  pass "INV-001b" "/creview-spec references recommended_lenses"
else
  fail "INV-001b" "/creview-spec does not reference recommended_lenses"
fi

# INV-001c: /creview mentions lens-recommendations artifact path
if grep -q 'lens-recommendations' "$CREVIEW_SKILL"; then
  pass "INV-001c" "/creview references lens-recommendations artifact"
else
  fail "INV-001c" "/creview does not reference lens-recommendations artifact"
fi

# INV-001d: /creview writes recommended_lenses array
if grep -q 'recommended_lenses' "$CREVIEW_SKILL"; then
  pass "INV-001d" "/creview references recommended_lenses"
else
  fail "INV-001d" "/creview does not reference recommended_lenses"
fi

# INV-001e: /creview-spec derives branch_slug for lens artifact via workflow-advance.sh status or lib.sh
# Must reference branch_slug in the lens recommendation context, not just for spec path discovery
if grep -B 5 -A 5 'lens-recommendations' "$CREVIEW_SPEC_SKILL" | grep -qiE 'branch_slug|workflow-advance\.sh.*status|lib\.sh'; then
  pass "INV-001e" "/creview-spec uses canonical branch_slug derivation for lens artifact"
else
  fail "INV-001e" "/creview-spec does not use canonical branch_slug derivation for lens artifact"
fi

# INV-001f: /creview derives branch_slug for lens artifact via workflow-advance.sh status or lib.sh
if grep -B 5 -A 5 'lens-recommendations' "$CREVIEW_SKILL" | grep -qiE 'branch_slug|workflow-advance\.sh.*status|lib\.sh'; then
  pass "INV-001f" "/creview uses canonical branch_slug derivation for lens artifact"
else
  fail "INV-001f" "/creview does not use canonical branch_slug derivation for lens artifact"
fi

# INV-001g: /creview-spec writes artifact after synthesis (Step 2) and before presenting (Step 4)
# Check that lens recommendation writing is positioned between synthesis and presentation
if grep -n 'lens-recommendations' "$CREVIEW_SPEC_SKILL" > /dev/null 2>&1; then
  lens_line=$(grep -n 'lens-recommendations' "$CREVIEW_SPEC_SKILL" | head -1 | cut -d: -f1)
  synthesis_line=$(grep -n 'Step 2.*Synthesize\|Collect and Synthesize' "$CREVIEW_SPEC_SKILL" | head -1 | cut -d: -f1)
  present_line=$(grep -n 'Step 4.*Present\|Present to Human' "$CREVIEW_SPEC_SKILL" | head -1 | cut -d: -f1)
  if [ -n "$lens_line" ] && [ -n "$synthesis_line" ] && [ -n "$present_line" ]; then
    if [ "$synthesis_line" -lt "$lens_line" ] && [ "$lens_line" -lt "$present_line" ]; then
      pass "INV-001g" "Lens recommendation writing is between synthesis and presentation"
    else
      fail "INV-001g" "Lens recommendation writing not positioned correctly (synth=$synthesis_line, lens=$lens_line, present=$present_line)"
    fi
  else
    fail "INV-001g" "Could not find all section markers"
  fi
else
  fail "INV-001g" "No lens-recommendations reference found in /creview-spec"
fi

# ============================================================================
# INV-002 [unit]: Lens recommendation schema
# ============================================================================

section "INV-002: Lens recommendation schema"

# INV-002a: schema_version field documented in lens recommendation context
# Must be in lens-recommendation context, not the pre-existing deferred-findings schema_version
if grep -B 5 -A 5 'schema_version' "$CREVIEW_SPEC_SKILL" | grep -qi 'lens\|recommend'; then
  pass "INV-002a" "schema_version field referenced in lens recommendation context"
else
  fail "INV-002a" "schema_version field not referenced in lens recommendation context"
fi

# INV-002b: lens_name field in schema
if grep -q 'lens_name' "$CREVIEW_SPEC_SKILL" || grep -q 'lens_name' "$CREVIEW_SKILL"; then
  pass "INV-002b" "lens_name field referenced"
else
  fail "INV-002b" "lens_name field not referenced"
fi

# INV-002c: rationale field in schema
if grep -q 'rationale' "$CREVIEW_SPEC_SKILL" || grep -q 'rationale' "$CREVIEW_SKILL"; then
  pass "INV-002c" "rationale field referenced"
else
  fail "INV-002c" "rationale field not referenced"
fi

# INV-002d: focus_areas field in schema
if grep -q 'focus_areas' "$CREVIEW_SPEC_SKILL" || grep -q 'focus_areas' "$CREVIEW_SKILL"; then
  pass "INV-002d" "focus_areas field referenced"
else
  fail "INV-002d" "focus_areas field not referenced"
fi

# INV-002e: severity_guidance field in schema
if grep -q 'severity_guidance' "$CREVIEW_SPEC_SKILL" || grep -q 'severity_guidance' "$CREVIEW_SKILL"; then
  pass "INV-002e" "severity_guidance field referenced"
else
  fail "INV-002e" "severity_guidance field not referenced"
fi

# INV-002f: source_agent field in schema
if grep -q 'source_agent' "$CREVIEW_SPEC_SKILL" || grep -q 'source_agent' "$CREVIEW_SKILL"; then
  pass "INV-002f" "source_agent field referenced"
else
  fail "INV-002f" "source_agent field not referenced"
fi

# INV-002g: source_finding field in schema
if grep -q 'source_finding' "$CREVIEW_SPEC_SKILL" || grep -q 'source_finding' "$CREVIEW_SKILL"; then
  pass "INV-002g" "source_finding field referenced"
else
  fail "INV-002g" "source_finding field not referenced"
fi

# INV-002h: source_finding_summary field in schema
if grep -q 'source_finding_summary' "$CREVIEW_SPEC_SKILL" || grep -q 'source_finding_summary' "$CREVIEW_SKILL"; then
  pass "INV-002h" "source_finding_summary field referenced"
else
  fail "INV-002h" "source_finding_summary field not referenced"
fi

# INV-002i: kebab-case requirement for lens_name
if grep -qi 'kebab.case' "$CREVIEW_SPEC_SKILL" || grep -qi 'kebab.case' "$CREVIEW_SKILL" || \
   grep -qi 'kebab.case' "$CTDD_SKILL"; then
  pass "INV-002i" "kebab-case requirement for lens_name documented"
else
  fail "INV-002i" "kebab-case requirement for lens_name not documented"
fi

# INV-002j: /creview uses source_agent: "single-pass-review" as documented constant
if grep -q 'single-pass-review' "$CREVIEW_SKILL"; then
  pass "INV-002j" "/creview uses single-pass-review source_agent constant"
else
  fail "INV-002j" "/creview does not use single-pass-review source_agent constant"
fi

# ============================================================================
# INV-003 [unit]: Core lenses always run
# ============================================================================

section "INV-003: Core lenses always run"

# INV-003a: /ctdd documents hostile-input as core/always-run lens
if grep -qi 'hostile.input.*core\|core.*hostile.input\|always.*run.*hostile.input\|hostile.input.*always' "$CTDD_SKILL"; then
  pass "INV-003a" "hostile-input documented as core lens"
else
  fail "INV-003a" "hostile-input not documented as core/always-run lens"
fi

# INV-003b: /ctdd documents cross-component as core/always-run lens
if grep -qi 'cross.component.*core\|core.*cross.component\|always.*run.*cross.component\|cross.component.*always' "$CTDD_SKILL"; then
  pass "INV-003b" "cross-component documented as core lens"
else
  fail "INV-003b" "cross-component not documented as core/always-run lens"
fi

# INV-003c: Recommended lenses documented as additive (never displace)
# Must match in the context of recommended lenses, not the unrelated "additive" on status field line
if grep -qi 'recommend.*lens.*additive\|recommend.*supplement.*not.*replace\|recommend.*alongside\|recommend.*never.*displace' "$CTDD_SKILL"; then
  pass "INV-003c" "Recommended lenses documented as additive"
else
  fail "INV-003c" "Recommended lenses not documented as additive"
fi

# ============================================================================
# INV-004 [unit]: Custom lens agent template with UNTRUSTED_RECOMMENDATION fence
# ============================================================================

section "INV-004: Custom lens agent template with UNTRUSTED fence"

# INV-004a: UNTRUSTED_RECOMMENDATION fence markers present in /ctdd
if grep -q 'UNTRUSTED_RECOMMENDATION_START' "$CTDD_SKILL" && \
   grep -q 'UNTRUSTED_RECOMMENDATION_END' "$CTDD_SKILL"; then
  pass "INV-004a" "UNTRUSTED_RECOMMENDATION fence markers present in /ctdd"
else
  fail "INV-004a" "UNTRUSTED_RECOMMENDATION fence markers missing from /ctdd"
fi

# INV-004b: Custom lens agent template present in /ctdd
if grep -qi 'custom.*lens.*agent\|custom.*mini.audit.*lens' "$CTDD_SKILL"; then
  pass "INV-004b" "Custom lens agent template referenced in /ctdd"
else
  fail "INV-004b" "Custom lens agent template not referenced in /ctdd"
fi

# INV-004c: Template receives focus_areas from recommendation
if grep -q 'focus_areas' "$CTDD_SKILL"; then
  pass "INV-004c" "focus_areas referenced in /ctdd custom lens template"
else
  fail "INV-004c" "focus_areas not referenced in /ctdd custom lens template"
fi

# INV-004d: Template receives severity_guidance from recommendation
if grep -q 'severity_guidance' "$CTDD_SKILL"; then
  pass "INV-004d" "severity_guidance referenced in /ctdd custom lens template"
else
  fail "INV-004d" "severity_guidance not referenced in /ctdd custom lens template"
fi

# INV-004e: Custom lens template includes standard severity calibration reference
# Must be in custom lens template context, not the existing QA or mini-audit calibration
if grep -qi 'custom.*lens.*calibration\|Standard.*severity.*calibration.*example.*6.*fixed\|calibration.*example.*fixed.*lens' "$CTDD_SKILL"; then
  pass "INV-004e" "Severity calibration referenced in custom lens template"
else
  fail "INV-004e" "Severity calibration not referenced in custom lens template"
fi

# INV-004f: Custom lens template produces MA- prefix findings with LENS matching lens_name
# The template skeleton itself must reference MA- and LENS: {lens_name}
if grep -q 'LENS: {lens_name}' "$CTDD_SKILL"; then
  pass "INV-004f" "Custom lens template references LENS: {lens_name}"
else
  fail "INV-004f" "Custom lens template does not reference LENS: {lens_name}"
fi

# INV-004g: Template specifies LENS field matching lens_name
if grep -qi 'LENS.*lens_name\|lens_name.*LENS\|LENS.*field.*match' "$CTDD_SKILL"; then
  pass "INV-004g" "LENS field matching lens_name documented"
else
  fail "INV-004g" "LENS field matching lens_name not documented"
fi

# INV-004h: Custom lens agents are read-only forked subagents
# Must match in the custom/recommended lens context, not generic agent tool lists
if grep -qi 'custom.*lens.*read.only\|recommend.*lens.*read.only\|custom.*lens.*agent.*Read.*Grep\|custom.*agent.*tool.*restrict' "$CTDD_SKILL"; then
  pass "INV-004h" "Custom lens agents documented as read-only"
else
  fail "INV-004h" "Custom lens agents not documented as read-only"
fi

# INV-004i: Template mentions "directional guidance" or "verify claims"
if grep -qi 'directional.*guidance\|verify.*claims\|not.*instructions.*follow.*uncritically' "$CTDD_SKILL"; then
  pass "INV-004i" "UNTRUSTED fence guidance documented"
else
  fail "INV-004i" "UNTRUSTED fence guidance not documented"
fi

# ============================================================================
# INV-005 [unit]: LENS enum extension
# ============================================================================

section "INV-005: LENS enum extension"

# INV-005a: /ctdd documents LENS as open enum
if grep -qi 'open.*enum\|LENS.*open\|unknown.*LENS.*graceful\|handle.*unknown.*LENS' "$CTDD_SKILL"; then
  pass "INV-005a" "LENS field documented as open enum in /ctdd"
else
  fail "INV-005a" "LENS field not documented as open enum in /ctdd"
fi

# INV-005b: /cmetrics handles unknown LENS values gracefully
if grep -qi 'unknown.*LENS\|unknown.*lens.*graceful\|open.*enum' "$CMETRICS_SKILL"; then
  pass "INV-005b" "/cmetrics handles unknown LENS values"
else
  fail "INV-005b" "/cmetrics does not document handling unknown LENS values"
fi

# INV-005c: /cwtf handles unknown LENS values gracefully
if grep -qi 'unknown.*LENS\|unknown.*lens.*graceful\|open.*enum' "$CWTF_SKILL"; then
  pass "INV-005c" "/cwtf handles unknown LENS values"
else
  fail "INV-005c" "/cwtf does not document handling unknown LENS values"
fi

# ============================================================================
# INV-006 [unit]: Lens outcome recording (best-effort)
# ============================================================================

section "INV-006: Lens outcome recording"

# INV-006a: /ctdd documents outcome recording after mini-audit
if grep -qi 'outcome.*record\|record.*outcome\|outcomes.*object\|outcomes.*field' "$CTDD_SKILL"; then
  pass "INV-006a" "Outcome recording documented in /ctdd"
else
  fail "INV-006a" "Outcome recording not documented in /ctdd"
fi

# INV-006b: Outcome fields include ran, findings_count, findings_by_severity
if grep -q 'findings_count\|findings_by_severity' "$CTDD_SKILL"; then
  pass "INV-006b" "Outcome tracking fields documented"
else
  fail "INV-006b" "Outcome tracking fields not documented"
fi

# INV-006c: Non-blocking warning in cmd_done when outcomes missing
# DA-002: cmd_done may be in a module file
if cat $WF_ALL_FILES 2>/dev/null | grep -qi 'lens.*recommend.*warn\|warn.*lens.*outcome\|non.*block.*warn.*lens\|lens-recommendations'; then
  pass "INV-006c" "Non-blocking lens outcome warning in workflow-advance modules"
else
  fail "INV-006c" "No non-blocking lens outcome warning in workflow-advance modules"
fi

# INV-006d: Outcome recording does not block progression (PRH-003 alignment)
# Must match outcome-specific non-blocking language, not generic non-blocking references
if grep -qi 'outcome.*best.effort\|outcome.*does not block\|outcome.*non.blocking\|failure.*write.*outcome.*not.*block\|best.effort.*outcome' "$CTDD_SKILL"; then
  pass "INV-006d" "Outcome recording documented as non-blocking"
else
  fail "INV-006d" "Outcome recording not documented as non-blocking"
fi

# INV-006e: Skips outcome recording when recommendation artifact absent
if grep -qi 'skip.*outcome.*absent\|no.*artifact.*skip.*outcome\|recommendation.*not.*exist.*skip\|dormant.*outcome' "$CTDD_SKILL"; then
  pass "INV-006e" "Outcome skipping on absent artifact documented"
else
  fail "INV-006e" "Outcome skipping on absent artifact not documented"
fi

# ============================================================================
# INV-007 [unit]: Dormant degradation when no recommendations exist
# ============================================================================

section "INV-007: Dormant degradation"

# INV-007a: /ctdd documents dormant degradation when artifact absent
if grep -qi 'dormant.*degrad\|PAT-019\|dormant.*signal\|no.*recommendation.*existing.*6.*lens\|absent.*no.*error\|absent.*no.*warn' "$CTDD_SKILL"; then
  pass "INV-007a" "Dormant degradation documented in /ctdd"
else
  fail "INV-007a" "Dormant degradation not documented in /ctdd"
fi

# INV-007b: No error/warning when artifact absent
if grep -qi 'no.*error.*no.*warn.*absent\|absent.*no.*error\|not.*exist.*6.*fixed\|optional.*input\|recommendation.*artifact.*optional' "$CTDD_SKILL"; then
  pass "INV-007b" "No error/warning on absent artifact documented"
else
  fail "INV-007b" "No error/warning on absent artifact behavior not documented"
fi

# ============================================================================
# INV-008 [unit]: Lens budget per round
# ============================================================================

section "INV-008: Lens budget per round"

# INV-008a: Budget cap of 8 agents per round documented
if grep -q '8 agents\|8.*agent.*per.*round\|at most 8\|6.*core.*2.*recommend\|6.*default.*2.*recommend' "$CTDD_SKILL"; then
  pass "INV-008a" "8-agent budget cap documented"
else
  fail "INV-008a" "8-agent budget cap not documented"
fi

# INV-008b: Up to 2 recommended lenses documented
if grep -qE 'up to 2.*recommend|2 recommend|top 2|at most.*2.*recommend' "$CTDD_SKILL"; then
  pass "INV-008b" "2-recommended-lens limit documented"
else
  fail "INV-008b" "2-recommended-lens limit not documented"
fi

# INV-008c: Priority heuristic documented (CRITICAL/HIGH findings first)
if grep -qi 'CRITICAL.*HIGH.*first\|priority.*heuristic\|source.*finding.*severity\|linked.*CRITICAL.*HIGH' "$CTDD_SKILL"; then
  pass "INV-008c" "Priority heuristic documented"
else
  fail "INV-008c" "Priority heuristic not documented"
fi

# INV-008d: Source agent diversity in selection
if grep -qi 'source.*agent.*diversity\|diversity.*source.*agent\|different.*review.*agent\|prefer.*lens.*different.*agent' "$CTDD_SKILL"; then
  pass "INV-008d" "Source agent diversity in selection documented"
else
  fail "INV-008d" "Source agent diversity in selection not documented"
fi

# INV-008e: Unselected recommendations logged with ran: false
if grep -qi 'ran.*false.*budget\|budget.*exceeded.*ran.*false\|unselected.*ran.*false' "$CTDD_SKILL"; then
  pass "INV-008e" "Unselected recommendations logged with ran: false"
else
  fail "INV-008e" "Unselected recommendations logging not documented"
fi

# INV-008f: Same lenses run in every round (selection per-invocation, not per-round)
if grep -qi 'same.*lens.*every.*round\|selection.*per.invocation\|same.*2.*selected.*recommend.*lens.*run.*every\|not.*per.round' "$CTDD_SKILL"; then
  pass "INV-008f" "Same lenses across all rounds documented"
else
  fail "INV-008f" "Same lenses across all rounds not documented"
fi

# ============================================================================
# INV-009 [unit]: /cmetrics lens coverage reporting
# ============================================================================

section "INV-009: /cmetrics lens coverage reporting"

# INV-009a: /cmetrics has a lens coverage section
if grep -qi 'lens.*coverage\|Mini.Audit.*Lens.*Coverage' "$CMETRICS_SKILL"; then
  pass "INV-009a" "/cmetrics has lens coverage section"
else
  fail "INV-009a" "/cmetrics does not have lens coverage section"
fi

# INV-009b: Reports which lenses ran across features
if grep -qi 'which.*lens.*ran\|lens.*ran.*across.*feature\|qa-findings.*LENS' "$CMETRICS_SKILL"; then
  pass "INV-009b" "/cmetrics reports which lenses ran"
else
  fail "INV-009b" "/cmetrics does not report which lenses ran"
fi

# INV-009c: Reports recommended vs actually ran
if grep -qi 'recommend.*vs.*ran\|suggested.*vs.*ran\|recommend.*actually.*ran' "$CMETRICS_SKILL"; then
  pass "INV-009c" "/cmetrics reports recommended vs actually ran"
else
  fail "INV-009c" "/cmetrics does not report recommended vs actually ran"
fi

# INV-009d: Finding yield per lens
if grep -qi 'finding.*yield\|yield.*per.*lens\|findings.*count.*times.*lens.*ran' "$CMETRICS_SKILL"; then
  pass "INV-009d" "/cmetrics reports finding yield per lens"
else
  fail "INV-009d" "/cmetrics does not report finding yield per lens"
fi

# INV-009e: Flags lenses recommended 3+ times as promotion candidates
if grep -qi '3.*times\|recommended.*3\|promotion.*candidate\|candidate.*promotion\|PAT.*entry\|core.*lens.*set' "$CMETRICS_SKILL"; then
  pass "INV-009e" "/cmetrics flags 3+ recommendations as promotion candidates"
else
  fail "INV-009e" "/cmetrics does not flag 3+ recommendations"
fi

# INV-009f: Dormant when no lens recommendation artifacts exist (PAT-019)
if grep -qi 'dormant.*lens\|no.*lens.*recommend.*artifact.*omit\|PAT-019.*lens\|absent.*no.*error.*lens' "$CMETRICS_SKILL"; then
  pass "INV-009f" "/cmetrics lens coverage is dormant when no artifacts"
else
  fail "INV-009f" "/cmetrics lens coverage dormant behavior not documented"
fi

# ============================================================================
# INV-010 [unit]: /cwtf lens auditability
# ============================================================================

section "INV-010: /cwtf lens auditability"

# INV-010a: /cwtf checks if recommended lenses exist but none ran
if grep -qi 'recommend.*lens.*none.*ran\|lens.*recommend.*not.*ran\|recommendation.*ignored' "$CWTF_SKILL"; then
  pass "INV-010a" "/cwtf checks recommended-but-not-run gap"
else
  fail "INV-010a" "/cwtf does not check recommended-but-not-run gap"
fi

# INV-010b: /cwtf warns about CRITICAL finding linked lens not running
if grep -qi 'CRITICAL.*finding.*not.*executed\|CRITICAL.*lens.*not.*run\|CRITICAL.*review.*finding.*was.*not.*executed' "$CWTF_SKILL"; then
  pass "INV-010b" "/cwtf warns about CRITICAL finding lens not running"
else
  fail "INV-010b" "/cwtf does not warn about CRITICAL finding lens not running"
fi

# INV-010c: /cwtf uses source_finding_summary (no cross-artifact lookup)
if grep -q 'source_finding_summary' "$CWTF_SKILL"; then
  pass "INV-010c" "/cwtf uses source_finding_summary field"
else
  fail "INV-010c" "/cwtf does not use source_finding_summary field"
fi

# INV-010d: /cwtf reports full lens selection rationale
if grep -qi 'lens.*selection.*rationale\|selection.*rationale\|rationale.*from.*artifact' "$CWTF_SKILL"; then
  pass "INV-010d" "/cwtf reports lens selection rationale"
else
  fail "INV-010d" "/cwtf does not report lens selection rationale"
fi

# INV-010e: /cwtf dormant when recommendation artifact absent (PAT-019)
if grep -qi 'dormant.*lens\|absent.*skip.*lens\|no.*error.*no.*warn.*absent\|PAT-019' "$CWTF_SKILL"; then
  pass "INV-010e" "/cwtf lens checks dormant when artifact absent"
else
  fail "INV-010e" "/cwtf lens checks dormant behavior not documented"
fi

# ============================================================================
# INV-011 [unit]: /creview allowed-tools includes lens recommendation path
# ============================================================================

section "INV-011: /creview allowed-tools"

# INV-011a: /creview allowed-tools includes Write(.correctless/artifacts/lens-recommendations-*)
if grep -q 'Write(.correctless/artifacts/lens-recommendations-\*)' "$CREVIEW_SKILL"; then
  pass "INV-011a" "/creview allowed-tools includes lens-recommendations write path"
else
  fail "INV-011a" "/creview allowed-tools does not include lens-recommendations write path"
fi

# INV-011b: /creview-spec already has broader Write(.correctless/artifacts/*) — verify it covers lens-recommendations
if grep -q 'Write(.correctless/artifacts/\*)' "$CREVIEW_SPEC_SKILL"; then
  pass "INV-011b" "/creview-spec has broad artifact write permission covering lens-recommendations"
else
  fail "INV-011b" "/creview-spec does not have broad artifact write permission"
fi

# ============================================================================
# INV-012 [unit]: LENS field persisted in qa-findings JSON
# ============================================================================

section "INV-012: LENS field in qa-findings JSON"

# INV-012a: /ctdd documents LENS field in qa-findings JSON schema
# The finding persistence section should include LENS in the JSON structure
if grep -qi 'LENS.*field.*qa-findings\|LENS.*persist\|LENS.*json\|lens.*qa-findings' "$CTDD_SKILL"; then
  pass "INV-012a" "LENS field persistence in qa-findings documented"
else
  fail "INV-012a" "LENS field persistence in qa-findings not documented"
fi

# INV-012b: The JSON schema in SKILL.md includes a "lens" or "LENS" field
# Look for "lens" as a JSON key in the findings structure
if grep -qE '"lens"|"LENS"' "$CTDD_SKILL"; then
  pass "INV-012b" "LENS field present in qa-findings JSON schema"
else
  fail "INV-012b" "LENS field not present in qa-findings JSON schema"
fi

# ============================================================================
# INV-013 [unit]: Dynamic progress announcements
# ============================================================================

section "INV-013: Dynamic progress announcements"

# INV-013a: /ctdd documents dynamic agent count in progress announcement
if grep -qi 'spawning.*{count}.*specialist\|spawning.*specialist.*agent.*count\|{rec_count}.*recommend' "$CTDD_SKILL"; then
  pass "INV-013a" "Dynamic agent count in progress announcement documented"
else
  fail "INV-013a" "Dynamic agent count in progress announcement not documented"
fi

# INV-013b: Progress announcement distinguishes core from recommended
if grep -qi 'core.*recommend.*progress\|6.*core.*recommend\|core.*lens.*recommend.*lens' "$CTDD_SKILL"; then
  pass "INV-013b" "Core vs recommended distinction in progress announcement"
else
  fail "INV-013b" "Core vs recommended not distinguished in progress announcement"
fi

# INV-013c: Names of recommended lenses included in announcement
if grep -qi 'lens_name.*announce\|{lens_name\|recommend.*lens.*name' "$CTDD_SKILL"; then
  pass "INV-013c" "Recommended lens names in announcement"
else
  fail "INV-013c" "Recommended lens names not in announcement"
fi

# INV-013d: Falls back to existing "6 specialist agents" when no recommendations
if grep -qi 'no.*recommend.*6.*specialist\|unchanged.*6.*specialist\|existing.*6.*specialist.*announce\|without.*recommend.*use.*existing' "$CTDD_SKILL"; then
  pass "INV-013d" "Fallback to existing 6-agent announcement documented"
else
  fail "INV-013d" "Fallback to existing 6-agent announcement not documented"
fi

# ============================================================================
# PRH-001 [unit]: Recommended lenses must not displace core lenses
# ============================================================================

section "PRH-001: Core lenses never displaced"

# PRH-001a: /ctdd explicitly states core lenses cannot be displaced
if grep -qi 'never.*displace.*core\|core.*lens.*never.*displaced\|must not.*displace\|hostile.input.*cross.component.*must\|always.*run.*regardless' "$CTDD_SKILL"; then
  pass "PRH-001a" "Core lens displacement prohibition documented"
else
  fail "PRH-001a" "Core lens displacement prohibition not documented"
fi

# PRH-001b: Budget cap applies only to non-core slots
# Must match budget-cap in lens recommendation context, not PBT recommendations
if grep -qi 'budget.*non.core\|non.core.*slot\|budget.*cap.*applies.*only.*recommend.*lens\|6.*core.*default.*2.*recommend' "$CTDD_SKILL"; then
  pass "PRH-001b" "Budget cap scoped to non-core slots"
else
  fail "PRH-001b" "Budget cap not scoped to non-core slots"
fi

# ============================================================================
# PRH-002 [unit]: Review agents must not write mini-audit agent prompts
# ============================================================================

section "PRH-002: Review agents write data not prompts"

# PRH-002a: /creview-spec does not contain "system_prompt" or full prompt for mini-audit agents
if ! grep -qi 'system_prompt.*mini.audit\|write.*full.*prompt.*mini.audit' "$CREVIEW_SPEC_SKILL"; then
  pass "PRH-002a" "/creview-spec does not write mini-audit agent prompts"
else
  fail "PRH-002a" "/creview-spec appears to write mini-audit agent prompts"
fi

# PRH-002b: /creview does not contain "system_prompt" or full prompt for mini-audit agents
if ! grep -qi 'system_prompt.*mini.audit\|write.*full.*prompt.*mini.audit' "$CREVIEW_SKILL"; then
  pass "PRH-002b" "/creview does not write mini-audit agent prompts"
else
  fail "PRH-002b" "/creview appears to write mini-audit agent prompts"
fi

# PRH-002c: Recommendation schema contains no "prompt" or "system_prompt" field
# Check that the lens recommendation schema documented in review skills doesn't include prompt fields
if grep -A 30 'recommended_lenses' "$CREVIEW_SPEC_SKILL" | grep -qi '"prompt"\|"system_prompt"'; then
  fail "PRH-002c" "Recommendation schema contains prompt field"
else
  pass "PRH-002c" "Recommendation schema does not contain prompt field"
fi

# PRH-002d: /ctdd documents that mini-audit phase owns prompt construction
if grep -qi 'mini.audit.*owns.*prompt\|prompt.*construct.*mini.audit\|template.*embedded.*ctdd\|mini.audit.*phase.*owns' "$CTDD_SKILL"; then
  pass "PRH-002d" "Mini-audit prompt ownership documented"
else
  fail "PRH-002d" "Mini-audit prompt ownership not documented"
fi

# ============================================================================
# PRH-003 [unit]: No lens recommendation gating
# ============================================================================

section "PRH-003: No lens recommendation gating"

# PRH-003a: /ctdd does not gate on lens-recommendations artifact
# Check for actual gating patterns (require/must exist/die/exit) — not the phrase "never gates"
if grep -qi 'require.*lens.*recommend\|die.*lens.*recommend\|exit.*lens.*recommend\|must.*exist.*lens.*recommend' "$CTDD_SKILL"; then
  fail "PRH-003a" "/ctdd appears to gate on lens-recommendations"
else
  pass "PRH-003a" "/ctdd does not gate on lens-recommendations"
fi

# PRH-003b: workflow-advance.sh modules do not gate transitions on lens-recommendations
# (except the non-blocking warning in cmd_done per INV-006)
lens_gate_count=0
for f in $WF_ALL_FILES; do
  if [ -f "$f" ]; then
    # Count references to lens-recommendations that are gating (exit 1, exit 2, fail)
    gating=$(grep -c 'lens-recommendation.*exit [12]\|exit [12].*lens-recommendation' "$f" 2>/dev/null || true)
    lens_gate_count=$((lens_gate_count + gating))
  fi
done
if [ "$lens_gate_count" -eq 0 ]; then
  pass "PRH-003b" "No gating on lens-recommendations in workflow-advance modules"
else
  fail "PRH-003b" "Found $lens_gate_count gating references to lens-recommendations"
fi

# PRH-003c: INV-006 warning is explicitly non-blocking (warning, not gate)
# Must be in lens outcome context — not the generic non-blocking references
if grep -qi 'outcome.*warn.*not.*gate\|lens.*warn.*non.blocking\|outcome.*non.blocking.*warn\|warn.*lens.*outcome.*not.*block' "$CTDD_SKILL"; then
  pass "PRH-003c" "INV-006 warning is non-blocking"
else
  fail "PRH-003c" "INV-006 warning blocking status unclear"
fi

# ============================================================================
# BND-001 [unit]: Empty recommendations
# ============================================================================

section "BND-001: Empty recommendations"

# BND-001a: /ctdd handles empty recommended_lenses array
if grep -qi 'empty.*recommend\|recommended_lenses.*\[\]\|zero.*recommend\|no.*recommend.*6.*lens\|no.*feature.specific' "$CTDD_SKILL"; then
  pass "BND-001a" "Empty recommendations handling documented"
else
  fail "BND-001a" "Empty recommendations handling not documented"
fi

# ============================================================================
# BND-002 [unit]: Duplicate lens names across review agents
# ============================================================================

section "BND-002: Duplicate lens name deduplication"

# BND-002a: Deduplication by lens_name documented in review skills
if grep -qi 'dedup.*lens_name\|duplicate.*lens_name\|merge.*lens_name\|deduplicate.*lens_name' "$CREVIEW_SPEC_SKILL" || \
   grep -qi 'dedup.*lens_name\|duplicate.*lens_name\|merge.*lens_name\|deduplicate.*lens_name' "$CTDD_SKILL"; then
  pass "BND-002a" "Lens name deduplication documented"
else
  fail "BND-002a" "Lens name deduplication not documented"
fi

# BND-002b: Merge strategy documented (union focus_areas, higher severity_guidance)
if grep -qi 'union.*focus_areas\|merge.*focus_areas\|higher.*severity_guidance' "$CREVIEW_SPEC_SKILL" || \
   grep -qi 'union.*focus_areas\|merge.*focus_areas\|higher.*severity_guidance' "$CTDD_SKILL"; then
  pass "BND-002b" "Deduplication merge strategy documented"
else
  fail "BND-002b" "Deduplication merge strategy not documented"
fi

# ============================================================================
# BND-003 [unit]: Recommendation artifact from wrong branch
# ============================================================================

section "BND-003: Branch-scoped artifact matching"

# BND-003a: /ctdd reads lens-recommendations-{current_branch_slug}.json
if grep -q 'lens-recommendations-{' "$CTDD_SKILL" || \
   grep -q 'lens-recommendations.*branch_slug\|lens-recommendations.*{.*slug' "$CTDD_SKILL"; then
  pass "BND-003a" "Branch-scoped artifact reading documented"
else
  fail "BND-003a" "Branch-scoped artifact reading not documented"
fi

# BND-003b: File not found treated as absent (dormant degradation)
if grep -qi 'not.*found.*absent\|not.*found.*dormant\|mismatch.*absent\|file.*not.*found.*treat.*absent' "$CTDD_SKILL"; then
  pass "BND-003b" "File-not-found → dormant degradation documented"
else
  fail "BND-003b" "File-not-found → dormant degradation not documented"
fi

# ============================================================================
# ABS-036: Cross-file consistency checks
# ============================================================================

section "ABS-036: Cross-file consistency"

# ABS-036a: All 5 skill files reference lens-recommendations
creview_spec_has=$(grep -c 'lens-recommendations\|recommended_lenses' "$CREVIEW_SPEC_SKILL" 2>/dev/null || true)
creview_has=$(grep -c 'lens-recommendations\|recommended_lenses' "$CREVIEW_SKILL" 2>/dev/null || true)
ctdd_has=$(grep -c 'lens-recommendations\|recommended_lenses' "$CTDD_SKILL" 2>/dev/null || true)
cmetrics_has=$(grep -c 'lens-recommendations\|recommended_lenses' "$CMETRICS_SKILL" 2>/dev/null || true)
cwtf_has=$(grep -c 'lens-recommendations\|recommended_lenses' "$CWTF_SKILL" 2>/dev/null || true)

if [ "$creview_spec_has" -gt 0 ] && [ "$creview_has" -gt 0 ] && [ "$ctdd_has" -gt 0 ] && \
   [ "$cmetrics_has" -gt 0 ] && [ "$cwtf_has" -gt 0 ]; then
  pass "ABS-036a" "All 5 skill files reference lens-recommendations"
else
  fail "ABS-036a" "Not all 5 skill files reference lens-recommendations (creview-spec=$creview_spec_has, creview=$creview_has, ctdd=$ctdd_has, cmetrics=$cmetrics_has, cwtf=$cwtf_has)"
fi

# ABS-036b: /ctdd reads both recommended_lenses (consumer) and writes outcomes
if grep -q 'recommended_lenses' "$CTDD_SKILL" && grep -qi 'outcomes' "$CTDD_SKILL"; then
  pass "ABS-036b" "/ctdd reads recommended_lenses and writes outcomes"
else
  fail "ABS-036b" "/ctdd does not document both reading and writing roles"
fi

# ============================================================================
# Summary
# ============================================================================

echo ""
echo "========================================="
echo "  Review-Driven Lenses Tests: $PASS passed, $FAIL failed, $SKIPPED skipped"
echo "========================================="
if [ -n "$FAILED_IDS" ]; then
  echo "  Failed: $FAILED_IDS"
fi
echo ""

# Exit with failure if any tests failed
[ "$FAIL" -eq 0 ]
