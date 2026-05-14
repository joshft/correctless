# Spec: Project Dashboard UI

## Metadata
- **Task**: project-dashboard-ui
- **Recommended-intensity**: standard
- **Intensity**: standard
- **Intensity reason**: standard for feature scope (read-only HTML generation, no hooks); review identified TB-003 trust boundary (LLM content → browser rendering) addressed by R-002 sanitization requirements
- **Override**: lowered (project floor is high, user requested standard)

## What

A `/cdashboard` skill that replaces the former dashboard script with a unified artifact browser + metrics dashboard (`scripts/build-dashboard.sh`). The skill reads `.correctless/` artifacts and generates a self-contained HTML file at `.correctless/dashboard/index.html` (gitignored). The dashboard has two views: a **Metrics** view preserving all existing dashboard sections (quality trajectory, antipattern health, intensity calibration, cost by phase, drift debt, dev journal, etc.), and an **Artifact Browser** view with sidebar navigation for browsing specs, verifications, review findings, architecture docs, and antipatterns as rendered markdown. Uses marked.js from CDN for markdown rendering. Read-only v1 — no user input, no annotation, no write-back to artifacts.

## Rules

- **R-001** [unit]: A skill file exists at `skills/cdashboard/SKILL.md`. The skill invokes `scripts/build-dashboard.sh` — a bash script requiring only bash 4+, jq 1.7+, and POSIX tools. It accepts one optional argument (project root, defaults to cwd). Exits 0 on success, 1 on failure. The script reads `.correctless/` artifacts and generates a single self-contained HTML file at `.correctless/dashboard/index.html`. Failure mode: passthrough — if artifact reading fails, the skill falls back to terminal output listing available artifacts with paths, with the failure reason included. `scripts/build-dashboard.sh` must have an ABS-xxx entry documenting its sole-writer contract for the output file.

- **R-002** [unit]: The generated HTML is a single file with all CSS and JS inline. The only external dependency is `marked.js` loaded from CDN with a pinned version and SRI hash (e.g., `https://cdn.jsdelivr.net/npm/marked@14.0.0/marked.min.js` with `integrity="sha384-..."`). The specific version and hash are determined at implementation time; the requirement is that both are present. All artifact data is inlined as JSON inside a `<script type="application/json">` block; the literal sequence `</` in all JSON string values must be escaped as `<\/` before embedding in HTML (prevents `</script>` injection — the HTML parser terminates the script block at the first `</script>` regardless of JSON string boundaries). Markdown is rendered via marked.js configured with DOMPurify for sanitization — raw HTML passthrough is prohibited because artifact markdown files contain LLM-generated prose that could include `<script>` tags or event handlers (crosses TB-003: LLM-generated content → browser HTML rendering). The file opens correctly in a browser via `file://` protocol. If the CDN is unreachable, markdown content displays as raw text with an in-HTML notice ("Markdown rendering unavailable — viewing raw text") (graceful degradation).

- **R-003** [unit]: The dashboard has two top-level navigation views accessible via tabs or a nav bar:
  1. **Metrics** — all existing metrics sections from the former dashboard script (project summary, quality trajectory, QA rounds, pipeline phase distribution, fix rate, escape metrics, antipattern health, intensity calibration, override rate, cost by phase, drift debt, dev journal). The metrics view is the default landing page.
  2. **Artifact Browser** — sidebar navigation listing artifact categories (specs, verifications, review findings, research briefs, architecture, antipatterns, QA findings). Clicking a category expands to show individual files. Clicking a file renders its markdown content in the main content area via marked.js.

- **R-004** [unit]: The Artifact Browser reads these directories and files, organized by category:
  - **Specs**: `.correctless/specs/*.md`
  - **Verifications**: `.correctless/verification/*.md`
  - **Review Findings**: `.correctless/artifacts/review-spec-findings-*.md`, `.correctless/artifacts/review-findings-*.md`
  - **Research Briefs**: `.correctless/artifacts/research/*.md`
  - **Architecture**: `.correctless/ARCHITECTURE.md`, `.correctless/AGENT_CONTEXT.md`, `.correctless/antipatterns.md`
  - **QA Findings**: `.correctless/artifacts/qa-findings-*.json` (rendered as formatted tables, not raw JSON)
  - **Audit History**: `.correctless/artifacts/findings/audit-*-history.md`
  Missing categories are omitted from the sidebar (no empty sections). Missing individual files are skipped.

- **R-005** [unit]: The Metrics view reads the same data sources as the former dashboard script (R-003 of the original `project-dashboard` spec): workflow history, QA findings, review decisions, antipatterns, intensity calibration, drift debt, token logs, cost artifacts, override counts, dev journal, contributing stats, and workflow config. All existing metric sections are preserved — no data loss from the migration.

- **R-006** [unit]: The skill writes the output to `.correctless/dashboard/index.html`. The `.correctless/dashboard/` directory is created if it doesn't exist. The path `.correctless/dashboard/` must be added to `.gitignore` if not already present.

- **R-007** [unit]: The skill replaces the former dashboard script. After this feature ships: (a) the old script is deleted from source AND the stale installed copy is removed (setup's glob only installs, never cleans up deleted sources), (b) the old output in the project root is removed if present, (c) all references are updated — verified by grep returning zero matches after migration. Known affected files include: `ARCHITECTURE.md` ABS-026 consumer list, `skills/cmetrics/SKILL.md`, `tests/test-session-cost.sh`, `sync.sh` (hardcoded skill list — add `cdashboard`, update count), `FEATURES.md`, `setup`, `CLAUDE.md` (Available commands), `AGENT_CONTEXT.md` (skill count), and test files with hardcoded count assertions (`test-dynamic-rigor.sh`, `test-mcp.sh`, `test-carchitect.sh`), (d) `tests/test-project-dashboard.sh` is updated to test the new output path and skill invocation.

- **R-008**: The HTML includes dark mode support (respects `prefers-color-scheme: dark` media query, matching the existing dashboard's dark mode). Typography and layout should be clean and readable — the dashboard is for humans scanning project health at a glance. **Testability split**: structural assertions (grep for CSS media query, script tags, data presence in HTML, `onerror` handler on CDN script tag) are tagged `[unit]` and tested in shell. Browser-dependent behavior (actual rendering, interaction, CDN fallback visual) is tagged `[manual]` and documented as manual verification items.

- **R-009** [unit]: Empty state handling — when `.correctless/` has no artifacts (fresh project), the dashboard renders with "No data yet" placeholders in the Metrics view and "No artifacts found" in the Browser view. The skill does not error on empty projects.

- **R-010** [unit]: The skill must be registered in `workflow-config.json` under `skills` if the project uses skill registration, and must be added to the `setup.sh` installation glob if skills are installed. The skill file must be propagated by `sync.sh` if the project uses sync-based distribution.

- **R-011** [unit]: The skill prints a success message with the output path after generating the dashboard (e.g., "Dashboard generated: .correctless/dashboard/index.html — open in a browser to view"). On passthrough fallback (R-001), the failure reason is included in the terminal output. When marked.js fails to load in the browser, the HTML displays a visible notice indicating markdown rendering is unavailable (see R-002 graceful degradation).

- **R-012**: The Artifact Browser sidebar navigation (R-003) and file selection rendering are browser-dependent behavior. Structural proxy tests (tagged `[unit]`) verify: (a) sidebar category headings are present in the HTML, (b) artifact data for each category is inlined in the JSON data block, (c) the marked.js script tag has an `onerror` fallback handler. Interactive behavior (clicking categories, file selection, markdown rendering) is tagged `[manual]`.

## Won't Do

- **Interactive review UI** — no user input, annotation, commenting, or write-back to artifacts. That's v2.
- **Live reload / file watching** — the dashboard is a static snapshot generated on demand. No WebSocket, no polling.
- **Server-side rendering** — no local server. The HTML opens via `file://` protocol.
- **Custom charting library** — metrics use inline CSS bars and tables (same approach as existing dashboard). No Chart.js, D3, or similar.
- **Diff views or version comparison** — no artifact versioning or history comparison within the browser.
- **Overcorrect/Factory artifacts** — `.factory/runs/` data (run summaries, metrics, cross-model comparisons) is a v2 addition to the Artifact Browser once Overcorrect ships.

## Risks

- **marked.js CDN dependency** — if jsdelivr goes down, markdown won't render. Mitigation: raw markdown text is still readable; CDN failures are rare and transient. R-002 requires graceful degradation with visible notice.
- **XSS via LLM-generated markdown** — artifact files contain LLM-generated prose rendered as HTML. Mitigation: R-002 requires DOMPurify sanitization; raw HTML passthrough prohibited.
- **CDN supply chain** — unpinned CDN URL risks silent version drift or compromise. Mitigation: R-002 requires pinned version with SRI hash.
- **Large artifact inlining** — projects with many specs/verifications could produce a large HTML file. Mitigation: acceptable for v1; lazy-load artifact content in v2 if needed.
- **Former dashboard script test coupling** — existing tests (1067 lines) tested the old bash script directly. Migration required significant test rewriting. Mitigation: R-007 scoped the test update.

## Open Questions

- ~~**OQ-001**~~: **Resolved** — direct port of existing metrics layout for v1. Iterate after shipping.
- ~~**OQ-002**~~: **Resolved** — helper script (`scripts/build-dashboard.sh`) invoked by the skill. A 1000+ line HTML generation script doesn't belong in a SKILL.md prompt.
