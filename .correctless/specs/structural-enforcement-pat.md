# Spec: Structural Enforcement PAT

## Metadata
- **Task**: structural-enforcement-pat
- **Recommended-intensity**: standard
- **Intensity**: high
- **Intensity reason**: project floor (workflow.intensity = high); no feature-level signals triggered
- **Intensity-note**: feature-level detection produced standard; project floor raised to high
- **Override**: none

## What

Promote "structural enforcement over prompt-level instruction" from an informal design principle to a formal PAT-018 entry in `.correctless/ARCHITECTURE.md`, add an `Enforcement:` field to the INV-xxx template in `/cspec` at high+ intensity, and add a mechanical check in `/creview-spec`'s Design Contract Checker that flags invariants missing a stated enforcement mechanism. This codifies a pattern that caught 8 of 20 review findings in the auto-mode-phase-2 spec — invariants that claimed a property but had only prompt-level enforcement.

## Rules

- **R-001** [unit]: `.correctless/ARCHITECTURE.md` contains a PAT-018 entry titled "Structural enforcement over prompt-level instruction" with Rule, Violated-when, Guards-against, and Test fields
- **R-002** [unit]: PAT-018's Rule field lists the acceptable enforcement mechanisms: allowed-tools restrictions, file permissions (sensitive-file-guard), phase-transition gate preconditions, cryptographic verification (hashes), static test assertions in CI, tool-pinning in plugin agent frontmatter
- **R-003** [unit]: PAT-018's Guards-against field references the class of review findings where an invariant states a property but enforcement is prompt-level only
- **R-004** [unit]: The INV-xxx template in `skills/cspec/SKILL.md` (high+ intensity format) includes an `Enforcement:` field between `Violated when` and `Guards against`
- **R-005** [unit]: The `Enforcement:` field has guidance text listing the acceptable mechanism categories from PAT-018 (allowed-tools, sensitive-file-guard, gate precondition, hash verification, CI test assertion, agent tool-pinning) and "prompt-level" as the fallback when no structural mechanism applies
- **R-006** [unit]: `/creview-spec`'s Design Contract Checker prompt includes an instruction to flag invariants where the `Enforcement:` field is "prompt-level" or absent, and to suggest a structural mechanism from PAT-018
- **R-007** [unit]: The spec template at `templates/spec-full.md` includes the `Enforcement:` field in the INV-xxx block, matching the cspec SKILL.md template
- **R-008** [unit]: `sync.sh` propagates the modified skill files to the distribution (existing infrastructure — satisfied by running sync)

## Won't Do

- Retroactively adding `Enforcement:` fields to existing specs — they're frozen post-merge
- Adding enforcement to standard-intensity specs — standard uses R-xxx rules, not INV-xxx invariants
- Automated enforcement-mechanism suggestion (the Design Contract Checker flags; the human decides)
- Modifying `/creview`'s single-agent review — only `/creview-spec`'s multi-agent review gets the check

## Risks

- **Review noise**: Design Contract Checker may flag invariants where prompt-level is genuinely the only option (e.g., "the agent must present findings before advancing"). Accepted — the flag is advisory and the "prompt-level" fallback makes the choice conscious. The noise is the value: forcing the spec author to explicitly choose "prompt-level" instead of unconsciously defaulting to it. Functional invariants are where structural enforcement is most often available but overlooked (phase-transition gates, allowed-tools restrictions, CI assertions). Thresholding to only security/data-integrity categories would lose the forcing function on exactly the invariants that benefit most.

## Open Questions

- None
