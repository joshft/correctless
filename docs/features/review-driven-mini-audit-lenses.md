# Review-Driven Mini-Audit Lenses

## What It Does

Bridges the gap between the review phase and the mini-audit phase. Review agents (`/creview-spec` at high+ intensity, `/creview` at standard intensity) analyze a feature's risk profile and recommend specific adversarial lenses for the mini-audit. The mini-audit then spawns custom agents for those recommended lenses alongside the 6 default lenses, using an UNTRUSTED_RECOMMENDATION fence to treat the review-generated guidance as directional rather than authoritative.

## How It Works

1. **Review writes recommendations**: After synthesizing findings, `/creview-spec` or `/creview` writes a `lens-recommendations-{branch_slug}.json` artifact containing structured lens recommendations (name, focus areas, severity guidance, source agent, linked finding).

2. **Mini-audit consumes recommendations**: Before spawning agents, `/ctdd`'s mini-audit reads the recommendation artifact. Up to 2 recommended lenses are selected per round (8-agent budget: 6 default + 2 recommended). Selection prioritizes lenses linked to CRITICAL/HIGH review findings, then source agent diversity.

3. **Custom lens agents**: Each recommended lens is instantiated via a custom lens template with `UNTRUSTED_RECOMMENDATION_START` / `UNTRUSTED_RECOMMENDATION_END` fence markers. The agent receives the focus areas and severity guidance as directional context, not instructions. Tool restrictions match the existing 6 default agents (read-only).

4. **Outcome recording**: After the mini-audit completes, the orchestrator updates the recommendation artifact with an `outcomes` object recording which lenses ran, finding counts by severity, and failure reasons for lenses that did not run. Best-effort, non-blocking.

5. **Auditability**: `/cmetrics` reports lens coverage (yield per lens, promotion candidates for lenses recommended 3+ times). `/cwtf` flags gaps where recommended lenses were not executed, especially those linked to CRITICAL findings.

## Key Design Decisions

- **Additive, not replacement**: Recommended lenses supplement the 6 default lenses. Core lenses (`hostile-input`, `cross-component`) can never be displaced (PRH-001).
- **Structured data, not prompts**: Review agents write structured recommendations (name, focus areas, severity guidance), not full agent system prompts. The mini-audit owns prompt construction (PRH-002).
- **Dormant degradation**: When no recommendation artifact exists (standard intensity, review not run, fresh session), the mini-audit runs the default 6 lenses with no change (PAT-019).
- **Non-gating**: The recommendation artifact never gates any pipeline phase transition (PRH-003). It is advisory data.

## Configuration

No new configuration options. The feature activates automatically when review skills run before `/ctdd`.

## Architecture

- **ABS-036**: Lens recommendation artifact contract. See `.correctless/ARCHITECTURE.md`.
- **Spec**: `.correctless/specs/review-driven-mini-audit-lenses.md` (13 INV, 3 PRH, 3 BND).
- **Tests**: `tests/test-review-driven-lenses.sh` (80 assertions).

## Known Limitations

- The 2-lens cap per round means features with many risk dimensions may not get full lens coverage. The priority heuristic selects the most important lenses, and unselected ones are logged for auditability.
- Lens outcome recording is best-effort. If the write fails, the warning is non-blocking and outcomes are lost for that feature.
- `/creview` recommendations at standard intensity tend to be fewer and broader than `/creview-spec`'s multi-agent analysis at high+ intensity.
