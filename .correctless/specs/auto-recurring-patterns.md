# Spec: Auto-Promote Recurring Antipatterns to Architecture

## Metadata
- **Created**: 2026-04-08T23:30:00Z
- **Status**: approved
- **Impacts**: cspec, cpostmortem
- **Branch**: feature/auto-recurring-patterns
- **Research**: null
- **Recommended-intensity**: high
- **Intensity**: high
- **Intensity reason**: file path signal (skills/), impacts spec and postmortem workflow phases
- **Override**: none

## Context

The antipatterns file grows as QA catches bug classes, but nothing bridges the gap between "we've seen this bug across 4 features" and "this is a documented architectural constraint." The data exists — each AP-xxx entry has a Frequency field counting findings and features — but no skill reads it proactively. This feature adds auto-promotion: when an antipattern's feature count crosses 3+, /cspec and /cpostmortem suggest drafting a PAT-xxx or ABS-xxx entry in ARCHITECTURE.md. The human approves or skips. This closes the gap between observation (antipatterns.md) and codification (ARCHITECTURE.md).

## Scope

**Covers:**
- /cspec Step 5 (Check Antipatterns): after checking each AP-xxx for relevance, also check frequency and suggest promotion for entries at 3+ features (capped at 2 per invocation)
- /cpostmortem Step 3 (Determine Corrective Action): when creating or updating an AP-xxx entry, check if the new frequency crosses the 3-feature threshold and suggest promotion
- Add `Write(.correctless/ARCHITECTURE.md)` to cpostmortem's allowed-tools frontmatter
- Deduplication: skip promotion suggestion if the antipattern already has a corresponding ARCHITECTURE.md entry (detected via AP-xxx mention in ARCHITECTURE.md)
- Draft entry format: suggest a PAT-xxx or ABS-xxx entry skeleton with `Guards against: AP-xxx` field, invariant, violated-when, and test fields pre-populated from the antipattern's "How to catch it" section
- Structured decision: present the promotion suggestion with numbered options (add, skip, modify, defer)

**Does NOT cover:**
- Auto-writing ARCHITECTURE.md entries without human approval — always advisory
- Changing the antipattern format or schema — frequency field stays as-is
- Removing or archiving promoted antipatterns — they remain in antipatterns.md
- Threshold configuration — v1 hardcodes 3 features; configurable thresholds deferred

## Complexity Budget
- **Estimated LOC**: ~80 net change
- **Files touched**: ~4 (cspec SKILL.md, cpostmortem SKILL.md, cpostmortem frontmatter, test file)
- **New abstractions**: 0
- **Trust boundaries touched**: 0
- **Risk surface delta**: low (LLM skill instructions only, no hooks or scripts modified)

## Invariants

### INV-001: /cspec suggests promotion for high-frequency antipatterns (capped at 2)
- **Type**: must
- **Category**: functional
- **Statement**: During Step 5 (Check Antipatterns), after checking each AP-xxx entry for relevance to the current feature, /cspec also checks the Frequency field. If the frequency indicates 3 or more features (parsed from the "N findings across M features" text), and the antipattern has not already been promoted (INV-004), /cspec presents a promotion suggestion to the human with the structured decision format (INV-005). At most 2 promotion suggestions are presented per /cspec invocation — remaining qualifying entries are deferred to the next run. This prevents hijacking the spec workflow with a flood of architectural decisions.
- **Violated when**: /cspec's Step 5 does not check frequency, does not suggest promotion when the threshold is met, or presents more than 2 promotion suggestions per invocation
- **Test approach**: unit — grep cspec SKILL.md for frequency check, promotion suggestion, and the cap of 2 per invocation

### INV-002a: /cpostmortem checks frequency after antipattern creation/update
- **Type**: must
- **Category**: functional
- **Statement**: During Step 3 (Determine Corrective Action), after creating or updating an AP-xxx entry, /cpostmortem checks whether the antipattern's frequency now meets the 3-feature threshold. If it does and the antipattern has not already been promoted (INV-004), /cpostmortem presents a promotion suggestion with the structured decision format (INV-005).
- **Violated when**: /cpostmortem creates/updates an AP-xxx entry that meets the threshold without checking frequency or suggesting promotion
- **Test approach**: unit — grep cpostmortem SKILL.md for frequency check and promotion suggestion after antipattern creation/update

### INV-002b: Prefer threshold crossings over pre-existing entries (advisory)
- **Type**: must
- **Category**: functional
- **Statement**: /cpostmortem's promotion instructions prefer firing on threshold crossings (frequency just changed from below 3 to 3+) rather than on entries that already met the threshold before this postmortem. This is advisory LLM behavior — the instruction says to prefer crossings, but the deduplication check (INV-004) provides the safety net for repeated suggestions.
- **Violated when**: /cpostmortem SKILL.md does not contain language preferring threshold crossings
- **Test approach**: unit — grep cpostmortem SKILL.md for language about threshold crossing or "just crossed" or "newly meets"

### INV-003: Promotion drafts a PAT-xxx or ABS-xxx skeleton with Guards against field
- **Type**: must
- **Category**: functional
- **Statement**: When suggesting promotion, both /cspec and /cpostmortem draft a candidate ARCHITECTURE.md entry. The draft includes a `Guards against: AP-xxx` field that embeds the antipattern's ID — this is required for INV-004 deduplication to work. The draft uses the antipattern's "How to catch it" section to pre-populate the entry's Rule/Invariant field, and the "What went wrong" section to inform the Violated-when field. The draft format follows the existing PAT-xxx or ABS-xxx structure in ARCHITECTURE.md (Pattern, Rule, Violated when, Test, Guards against). The skill chooses PAT-xxx for process/convention patterns and ABS-xxx for code-level invariants — this classification is advisory and correctable via the "Modify" option in the structured decision.
- **Violated when**: A promotion suggestion is presented without a draft entry, the draft does not reference the antipattern's content, or the draft is missing the `Guards against: AP-xxx` field
- **Test approach**: unit — grep both skill files for draft entry generation referencing "How to catch it", "What went wrong", and "Guards against" with AP-xxx

### INV-004: Deduplication — skip already-promoted antipatterns
- **Type**: must
- **Category**: data-integrity
- **Statement**: Before suggesting promotion, both /cspec and /cpostmortem check whether ARCHITECTURE.md already references the AP-xxx identifier. The check searches for the literal string `AP-xxx` (e.g., `AP-002`) in ARCHITECTURE.md. If found, the antipattern is considered already promoted and no suggestion is made.
- **Violated when**: A promotion is suggested for an antipattern that is already referenced in ARCHITECTURE.md
- **Test approach**: unit — grep both skill files for deduplication check referencing ARCHITECTURE.md and AP-xxx

### INV-005: Structured decision format for promotion
- **Type**: must
- **Category**: functional
- **Statement**: Promotion suggestions are presented as structured decisions with numbered options: (1) Add (recommended) — add the drafted entry to ARCHITECTURE.md, (2) Skip — this antipattern doesn't warrant an architecture entry, (3) Modify — edit the draft before adding, (4) Defer — revisit in a future feature. Always ends with "Or type your own: ___". This matches the existing decision format used throughout Correctless skills.
- **Violated when**: A promotion suggestion uses a different decision format, or is missing the numbered options
- **Test approach**: unit — grep both skill files for the structured decision format with numbered promotion options

### INV-006: Threshold is 3 features
- **Type**: must
- **Category**: functional
- **Statement**: The promotion threshold is 3 or more features in the antipattern's Frequency field. The feature count is parsed from the standard format "N findings across M features" where M is the feature count. If the Frequency field is absent or unparsable, the antipattern is skipped (no promotion, no error).
- **Violated when**: The threshold is not 3 features, or an unparsable Frequency field causes an error
- **Test approach**: unit — grep both skill files for the threshold value of 3 features and graceful handling of missing/malformed frequency

### INV-007: /cspec promotion runs after relevance check
- **Type**: must
- **Category**: functional
- **Statement**: In /cspec Step 5, the promotion check runs after the existing antipattern relevance check ("does this feature risk repeating this bug class?"). The promotion check is a separate concern — it fires for any antipattern at the threshold regardless of whether it's relevant to the current feature. An antipattern that appeared in 5 features but isn't relevant to the current feature still gets a promotion suggestion.
- **Violated when**: /cspec only suggests promotion for antipatterns relevant to the current feature, or mixes the relevance check with the promotion check
- **Test approach**: unit — grep cspec SKILL.md for promotion check as separate from relevance check, firing regardless of relevance

### INV-008: /cpostmortem has write permission for ARCHITECTURE.md
- **Type**: must
- **Category**: functional
- **Statement**: /cpostmortem's `allowed-tools` frontmatter includes `Write(.correctless/ARCHITECTURE.md)` so that the "Add" option in the promotion decision can write the entry. Without this permission, promotion in /cpostmortem is dead on arrival.
- **Violated when**: /cpostmortem's allowed-tools does not include Write permission for ARCHITECTURE.md
- **Test approach**: unit — grep cpostmortem SKILL.md frontmatter for Write(.correctless/ARCHITECTURE.md)

## Risks

- **Frequency format drift**: The "N findings across M features" format is convention, not schema. A human writing "Found in 4 features" would be silently skipped by the promotion check forever. INV-006 handles this gracefully (skip, no error), but the risk is that legitimate high-frequency antipatterns become invisible to promotion. Accepted — fail-silent is the correct behavior, and standardizing the format is deferred.

## Prohibitions

### PRH-001: No auto-writing to ARCHITECTURE.md
- **Statement**: Neither /cspec nor /cpostmortem may write to ARCHITECTURE.md without human approval. The promotion suggestion is always presented as a structured decision. The human must explicitly choose "Add" before any write occurs.
- **Detection**: grep both skill files for write/edit instructions to ARCHITECTURE.md — must always be gated by human approval
- **Consequence**: Unwanted architecture entries pollute the documentation

### PRH-002: v1 threshold is a behavioral constant
- **Statement**: The 3-feature threshold is documented in skill files, not stored in workflow-config.json. Defer configurable thresholds until real demand exists.
- **Detection**: grep workflow-config.json templates for promotion_threshold or similar fields (must find none)
- **Consequence**: Premature config exposure creates values users don't understand

## Open Questions

None.

## Review Notes

- F1: Added INV-008 and Write permission to cpostmortem scope
- F2: Added cap of 2 promotions per /cspec invocation to INV-001
- F3: Added "Guards against: AP-xxx" requirement to INV-003 draft
- F4: Split INV-002 into INV-002a (testable) and INV-002b (advisory)
- F5: Added Risks section for frequency format drift
- F6: Accepted for v1 — cap from F2 limits nag frequency
- F7: Added "advisory and correctable" note to INV-003 classification
- F8: Adjusted LOC estimate to ~80
