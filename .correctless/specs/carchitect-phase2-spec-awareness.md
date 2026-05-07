# Spec: carchitect Phase 2 — Architecture-Aware Spec Writing

## Metadata
- **Created**: 2026-05-06T14:30:00Z
- **Status**: draft
- **Impacts**: none (additive to /cspec)
- **Branch**: feature/carchitect-phase2-spec-awareness
- **Research**: null
- **Recommended-intensity**: high
- **Intensity**: high
- **Intensity reason**: project floor (workflow.intensity = high); file path signal (skills/cspec/SKILL.md in skills/)
- **Intensity-note**: feature-level detection produced high (skills/ path pattern); project floor matches
- **Override**: none

## Context

When `/cspec` writes a spec, it reads `.correctless/ARCHITECTURE.md` for general context but does not mechanically identify which trust boundaries, patterns, or abstractions the feature's file scope overlaps with. The spec author must already know which TB-xxx entries are relevant — if they don't, security considerations are inferred rather than grounded. This caused the highest-frequency gap in carchitect Phase 2 validation: specs miss security considerations that are already documented in ARCHITECTURE.md but aren't surfaced to the agent. Additionally, specs sometimes introduce patterns that duplicate or conflict with existing PAT-xxx conventions, which only surfaces during review — wasting a review round on something `/cspec` could have caught mechanically.

This feature adds three capabilities to `/cspec`: (1) mechanical TB-xxx matching from the feature's file scope, with per-TB security questions and STRIDE grounding, (2) detection of new patterns not yet in PAT-xxx during spec writing, and (3) composition checking that verifies new rules don't conflict with existing PAT-xxx entries.

**Key design choice: file-scope overlap, not keyword matching.** TB-xxx matching works by comparing the feature's affected file paths against the domain each TB-xxx entry documents — not by scanning for security keywords. Keyword matching would produce noise: a feature mentioning "token" matches TB-001 because "token" is a security keyword, even if the feature is about token tracking (a metrics concern, not a trust boundary). File-scope overlap produces signal: a feature touching `hooks/workflow-gate.sh` matches TB-001 because TB-001 documents config-sourced shell execution in hooks — the hook's actual domain. This grounding is what makes the TB matching useful rather than a restatement of the existing keyword-based intensity detection.

## Scope

**Covers:**
- `/cspec` Step 1 enhancement: mechanical TB-xxx identification from feature file scope
- `/cspec` Step 3 enhancement: per-TB security questions derived from documented invariants
- `/cspec` STRIDE grounding: STRIDE analysis runs per matched TB-xxx, not per inferred boundary
- `/cspec` new pattern detection: flag when a feature introduces a convention not in PAT-xxx
- `/cspec` pattern composition check: verify new rules compose with existing PAT-xxx, don't conflict
- `/creview-spec` Design Contract Checker: cross-reference TB-xxx coverage in the spec

**Does NOT cover:**
- Retroactive TB-xxx matching on existing specs (frozen post-merge)
- Modifying ARCHITECTURE.md (that's `/cupdate-arch`'s job)
- Adding new TB-xxx entries during spec writing (the spec flags gaps; the human decides)
- Changing `/creview-spec`'s Red Team agent (it already reads ARCHITECTURE.md generically)
- Standard-intensity specs for TB matching and STRIDE (TB matching and STRIDE are high+ only; pattern detection applies at all intensities)

## Rules

- **R-001** [unit]: `/cspec` Step 1 (at high+ intensity) includes a "TB-xxx scope matching" substep — after gathering the feature's file scope from Step 0 brainstorm and Step 1 questions — that extracts all TB-xxx entries from `.correctless/ARCHITECTURE.md` by scanning for `### TB-\d{3}:` heading patterns and matches them against the feature's described file scope. Enforcement: prompt-level (skill prompt instructions; no structural mechanism available for LLM-judgment-based matching)
- **R-002** [unit]: The TB-xxx matching step produces a list of "relevant TBs" presented to the spec author with each TB's name, boundary description, and invariant — the spec author confirms or corrects the list before STRIDE analysis. Enforcement: prompt-level
- **R-003** [unit]: For each confirmed relevant TB-xxx, `/cspec` generates a targeted security question derived from that TB's documented invariant and "violated when" field, not from generic security keywords. Enforcement: prompt-level
- **R-004** [unit]: STRIDE analysis (at high+ intensity with `require_stride`) runs per confirmed relevant TB-xxx entry, not per inferred boundary — each STRIDE section header references the specific TB-xxx ID. Enforcement: prompt-level
- **R-005** [unit]: If the feature's file scope overlaps with a TB-xxx entry but the spec contains no invariant referencing that TB-xxx, `/cspec` warns: "TB-xxx ({name}) overlaps with this feature's scope but no invariant references it — is this intentional?" Enforcement: prompt-level
- **R-006** [unit]: `/cspec` Step 3 (at all intensities) includes a "pattern detection" substep that extracts all PAT-xxx entries from `.correctless/ARCHITECTURE.md` by scanning for `### PAT-\d{3}:` heading patterns and checks whether any spec rule introduces a convention not covered by an existing PAT-xxx. Enforcement: prompt-level
- **R-007** [unit]: When pattern detection identifies a potential new pattern, `/cspec` presents it to the spec author: "This rule introduces a convention ({description}). No existing PAT-xxx covers this. Flag for `/cupdate-arch` after implementation?" Enforcement: prompt-level
- **R-008** [unit]: `/cspec` Step 3 (at high+ intensity) includes a "pattern composition check" that operates on the patterns flagged by R-006 in the same Step 3 execution — for each potential new pattern identified by R-006, R-008 checks it against existing PAT-xxx entries and warns if it contradicts or duplicates an existing pattern, citing the specific PAT-xxx ID and the conflict. If R-006 finds no new patterns, R-008 has nothing to check. Enforcement: prompt-level
- **R-009** [unit]: `/creview-spec`'s Design Contract Checker prompt includes an instruction to cross-reference the spec's invariant `Boundary:` fields against the TB-xxx entries in ARCHITECTURE.md and flag any relevant TB-xxx that the spec does not reference. Enforcement: CI test assertion (structural test verifying prompt text contains TB-xxx cross-reference instruction)
- **R-010** [unit]: The TB-xxx matching uses file-scope overlap as the primary matching strategy — a feature touching `hooks/workflow-gate.sh` matches TB-001 because TB-001's invariant references config-sourced shell execution (the hook's domain), not because the word "security" appears. When a TB-xxx entry does not contain file path references in its Invariant, Enforced-at, or Test fields, matching falls back to keyword matching against the TB's description and "Crosses" field — less precise than file-scope overlap but better than dormant. The confirmation step (R-002) filters false positives from both matching strategies. Enforcement: prompt-level
- **R-011** [unit]: When no TB-xxx entries exist in ARCHITECTURE.md (no headings matching `### TB-\d{3}:`), the TB matching step is dormant — no error, no warning, `/cspec` proceeds without TB-grounded questions (same dormant-signal pattern as intensity detection). Missing section headers are treated identically to empty sections — both produce dormant behavior. Enforcement: prompt-level (dormant path)
- **R-012** [unit]: When no PAT-xxx entries exist in ARCHITECTURE.md (no headings matching `### PAT-\d{3}:`), pattern detection and composition checking are dormant — no error, no warning. Missing section headers are treated identically to empty sections — both produce dormant behavior. Enforcement: prompt-level (dormant path)

## Won't Do

- Automated TB-xxx entry creation (the spec flags gaps; `/cupdate-arch` handles additions)
- Modifying the Red Team agent in `/creview-spec` (it already reads ARCHITECTURE.md generically)
- Pattern detection at high+ intensity only (pattern detection is useful at all intensities — a standard-intensity feature can still introduce an undocumented convention)
- Blocking spec advancement when a TB-xxx gap is found (advisory, not gating)

## Risks

- **False positive TB matches**: File scope overlap is fuzzy — a feature touching `hooks/` matches TB-001 but may not actually involve config-sourced execution. Accepted — the spec author confirms the list (R-002), so false positives are filtered interactively. The alternative (keyword matching) has worse false negatives.
- **Pattern detection noise**: Many rules introduce conventions that don't warrant a PAT-xxx entry. Accepted — the detection is advisory (R-007) and the human decides. The cost of a false positive (one extra question) is far lower than the cost of a false negative (undocumented pattern that drifts).
- **ARCHITECTURE.md parsing fragility**: TB-xxx and PAT-xxx entries are Markdown with no formal schema. Accepted — the entries follow a consistent `### TB-xxx:` / `### PAT-xxx:` heading format that's grepable (regex: `### (TB|PAT)-\d{3}:`). If the format drifts, the matching degrades to the current behavior (generic reading without mechanical matching), not to failure.
- **Keyword-presence testing limitation (AP-003 class)**: All rules are prompt-level instructions in SKILL.md files. Tests verify the instruction text is present; they cannot verify the LLM follows the instructions at runtime. This is the standard testing limitation for LLM skill modifications — behavioral verification is inherently prompt-level. The same limitation applies to every other skill prompt rule in Correctless (R-006 in structural-enforcement-pat, the entire /creview-spec agent prompt suite, etc.).

## Open Questions

- None
