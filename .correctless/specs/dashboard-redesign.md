# Spec: Dashboard Visual Redesign

## Metadata
- **Task**: dashboard-redesign
- **Recommended-intensity**: standard
- **Intensity**: standard
- **Intensity reason**: no security paths, hooks, or trust boundaries beyond existing TB-003 (already mitigated by DOMPurify); pure CSS/HTML/JS frontend changes within a single script
- **Override**: lowered (project floor is high, user approved standard for visual-only scope)

## What

A complete visual and UX redesign of the Correctless project dashboard (`scripts/build-dashboard.sh`). The current dashboard is functional but uses generic system fonts, GitHub's blue accent color, flat layout with no visual hierarchy, and doesn't communicate the value of the Correctless methodology. The redesign makes the dashboard visually distinctive, polished, and user-friendly for external users — not just the tool's author. It restructures information presentation to tell a value narrative: what Correctless caught before it shipped, what would have escaped, and how quality trends over time. All surfaces are in scope: Metrics view, Artifact Browser, right panel, sidebar, and the top-level navigation. The data collection (bash Steps 0-13) is unchanged — only the HTML/CSS/JS output (Step 15) changes.

## Rules

- **R-001** [unit]: The dashboard uses a distinctive, non-generic visual identity. Custom fonts loaded from CDN (Google Fonts or equivalent) with SRI hashes and graceful degradation to system fonts if CDN is unreachable. The font stack must NOT be the default `-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto` system font cascade alone — at least one distinctive display or body font must be loaded. The color palette must NOT use `#58a6ff` (GitHub's blue) or `#4361ee` as the primary accent — the accent color must be visually distinct from GitHub/GitLab default palettes.

- **R-002** [unit]: The Metrics view has a "value narrative" section near the top (before or immediately after the project summary stats) that prominently communicates what Correctless caught. This section must include: (a) total findings caught pre-merge as a large, visually prominent number, (b) escape metrics if available (findings that audits caught post-implementation — data from `escape_metrics` in the dashboard JSON), (c) a visual breakdown of where findings were caught (QA vs mini-audit vs review — the pipeline phase distribution data). The goal is that a first-time viewer immediately understands "this tool caught N bugs before they shipped."

- **R-003** [unit]: The Metrics view uses card-based layout with visual hierarchy — stats, charts, and sections are grouped into visually distinct cards with backgrounds, borders, or shadows rather than flat inline elements separated only by `<h2>` tags. Section headers must be visually distinct from body content (size, weight, or color differentiation).

- **R-004** [unit]: The Artifact Browser sidebar shows spec items with status indicators (existing: status dots for complete/in-progress/none, dates, blocking badges). Specs are sorted by date (newest first). A search/filter input exists at the top of the sidebar. Clicking a spec shows its content in the main area with tabs (Spec, Review, Verification — in pipeline phase order). A right panel shows per-spec pipeline data when a spec is selected.

- **R-005** [unit]: The Artifact Browser content area renders markdown via marked.js + DOMPurify (existing requirement from project-dashboard-ui spec R-002 — security constraint, not visual). Typography for rendered markdown content (headings, paragraphs, code blocks, tables, lists) must be styled consistently with the dashboard's design system, not left as browser defaults.

- **R-006** [unit]: Dark mode and light mode are both supported. The dashboard respects `prefers-color-scheme: dark` media query. Both modes must be visually polished — light mode must NOT be an afterthought or a simple color inversion. CSS variables must be defined for both modes.

- **R-007** [unit]: The `file://` protocol output URL is printed by the script on success (e.g., `echo "Dashboard generated: file://${DASHBOARD_PATH}"`). The absolute path is computed from the resolved `$PROJECT_ROOT`.

- **R-008** [unit]: All existing structural test assertions in `tests/test-project-dashboard.sh` continue to pass after the redesign. This means: inline `<style>` present, inline `<script>` present, marked.js CDN with SRI, DOMPurify reference, `<script type="application/json">` data block, `</script>` injection escaping, no `fetch()` calls, `onerror` handler on CDN tags, graceful degradation notice text, two navigation views (Metrics + Artifact Browser), all artifact browser categories inlined in JSON, all metrics data sources parsed, output at `.correctless/dashboard/index.html`, `.correctless/dashboard/` in `.gitignore`, dark mode CSS media query, empty state handling. Tests that grep for specific CSS class names or HTML element patterns may need updating — the rule is that the test's INTENT (what it verifies) is preserved, not necessarily the exact grep pattern.

- **R-009** [unit]: Empty state handling — when `.correctless/` has no artifacts (fresh project), the dashboard renders with "No data yet" or equivalent placeholders in both Metrics and Browser views. The dashboard does not error or show a broken layout on empty projects.

- **R-010** [unit]: Any new CDN dependencies (fonts, icons, etc.) must follow the existing CDN pattern: pinned version, SRI hash, `onerror` fallback. If a font CDN fails to load, the dashboard falls back to system fonts and remains fully functional — no broken layout, no missing text. Font loading must not block initial page render (use `font-display: swap` or equivalent).

- **R-011** [unit]: The distribution copy at `correctless/scripts/build-dashboard.sh` is synced from `scripts/build-dashboard.sh` via the standard sync process.

## Won't Do

- **Interactive features** — no user input, annotation, commenting, or write-back to artifacts (same as v1).
- **Server-side rendering** — no local server, opens via `file://` protocol.
- **Custom charting library** — no Chart.js, D3, or similar. CSS-based visualizations only.
- **Live reload / file watching** — static snapshot generated on demand.
- **Data collection changes** — bash Steps 0-13 that parse workflow history, QA findings, antipatterns, calibration, drift debt, token logs, cost artifacts, escape metrics, overrides, dev journal, and browser artifacts are unchanged. The redesign only changes how the collected data is rendered in HTML/CSS/JS.
- **New data sources** — no new artifact types or parsing logic. Only the existing data fields in the dashboard JSON are used.

## Risks

- **Test breakage from CSS class/HTML structure changes** — the 89 existing tests grep for specific patterns. Mitigation: R-008 requires all test intents to pass; tests that grep for renamed classes are updated as part of this feature.
- **CDN font dependency** — adding Google Fonts adds a CDN dependency. Mitigation: R-010 requires SRI + graceful degradation; dashboard works without fonts.
- **Large CSS/JS rewrite in bash heredoc** — the entire HTML output is a bash heredoc, making large changes error-prone. Mitigation: build and view in browser after each major change; run test suite frequently.
- **Subjective design quality** — "polished" is subjective. Mitigation: iterative browser review with the user during implementation.

## Open Questions

- ~~**OQ-001**: Which specific font pairing?~~ **Resolved** — determined during implementation; any distinctive non-system font with CDN + SRI + fallback satisfies R-001.
- ~~**OQ-002**: Should the metrics view use a grid/multi-column layout instead of single column?~~ **Resolved** — implementation decides; R-003 requires card-based visual hierarchy, layout details are design decisions.
