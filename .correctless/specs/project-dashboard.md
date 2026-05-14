# Spec: Project Dashboard

## Metadata
- **Task**: project-dashboard
- **Recommended-intensity**: standard
- **Intensity**: standard
- **Intensity reason**: no signals triggered; user explicitly requested standard
- **Override**: lowered (project floor is high, user requested standard)

## What

A bash script (`scripts/build-dashboard.sh`) that reads `.correctless/` artifacts and generates a self-contained `.correctless/dashboard/index.html` in the project root. The dashboard tells the longitudinal story of the project's quality posture — are features getting cleaner over time, where in the pipeline are findings caught, is the antipattern loop compounding. No server, no build step, no external dependencies — just `open .correctless/dashboard/index.html` in a browser. Gitignored.

## Rules

- **R-001** [unit]: `scripts/build-dashboard.sh` exists and produces a `.correctless/dashboard/index.html` file in the project root when run from the repo root. Exit code 0 on success. The script requires only `bash`, `jq`, and standard Unix tools (sed, awk, grep, find, date). No npm, no python, no external chart libraries fetched at runtime.

- **R-002** [unit]: The generated HTML is self-contained — all CSS, JS, and data are inline. No external CDN links, no fetch calls, no network dependencies. The file opens correctly in a browser via `file://` protocol.

- **R-003** [unit]: The script reads these data sources and embeds them as a JSON object in the HTML:
  - `docs/workflow-history.md` — parsed into structured entries (date, feature name, branch, rules, QA rounds, findings fixed, overrides)
  - `.correctless/artifacts/qa-findings-*.json` — findings by severity and by source (QA-prefix = QA phase, MA-prefix = mini-audit phase) across features
  - `.correctless/artifacts/review-decisions-*.json` — review triage decisions (Phase 3 `/cauto` only; may not exist for interactive-mode features)
  - `.correctless/meta/intensity-calibration.json` — recommended vs actual intensity, QA rounds, token counts per feature
  - `.correctless/antipatterns.md` — parsed into entries with ID, frequency (N findings across M features), and feature names cited
  - `.correctless/meta/overrides/*.json` — override counts per feature
  - `.correctless/meta/drift-debt.json` — drift items with status (open/resolved/wont-fix)
  - `.correctless/artifacts/token-log-*.jsonl` — token usage per phase per feature (skill field for phase breakdown)
  - `CONTRIBUTING.md` — test file count and assertion count extracted
  - `.correctless/config/workflow-config.json` — project name, intensity floor
  Missing data sources are skipped gracefully — the dashboard renders with whatever data is available. An empty project (no workflow history) produces a dashboard with "No data yet" placeholders.

- **R-004** [unit]: The dashboard displays these sections in a single vertical narrative scroll — project summary at top, feature history in the middle, deep cuts at the bottom:

  1. **Project Summary** — project name, total features shipped, total QA findings caught, current test count, intensity floor. A one-line health verdict: "X features, Y findings caught pre-merge, Z antipatterns catalogued."

  2. **Quality Trajectory** — the core longitudinal view. For each feature (chronologically), show findings count as a horizontal bar. The bars visually answer "are features getting cleaner over time?" — a declining bar length across features is a healthy trend. Color-code bars by severity (red portion = BLOCKING, yellow = NON-BLOCKING). Implemented as inline `<div>` elements with percentage widths — no charting library needed.

  3. **Pipeline Phase Distribution** — where in the pipeline findings are caught. Aggregate across all features: how many findings came from QA (QA- prefix in qa-findings files), mini-audit (MA- prefix in qa-findings files), review (from review-decisions files, if they exist), and audit (from audit findings history, if it exists). Shows whether the workflow is shifting left. Single stacked horizontal bar. If only QA and mini-audit data exists (the common case for interactive-mode features), the bar shows those two phases — still useful for seeing the QA-to-mini-audit ratio.

  4. **Antipattern Health** — list of AP-xxx entries with visual status: active, dormant, or resolved. Dormancy is computed by cross-referencing the AP-xxx ID against the last N qa-findings files — if the antipattern's ID doesn't appear in any finding's `rule_ref` or description across the most recent 5 features, it's dormant. Antipatterns with a `Status: Structurally enforced` note are marked resolved. Shows the compounding loop — antipatterns added early that stopped firing are evidence the workflow is learning.

  5. **Intensity Calibration** — table of calibration entries showing recommended vs actual intensity, QA rounds, and token cost. Highlights overrides (where user changed the recommendation). Shows whether the intensity detection is calibrating well.

  6. **Cost by Phase** — token usage breakdown per phase (spec, review, tdd, verify, docs) aggregated from token log JSONL. Shows where time/cost goes. If TDD consistently costs 5x more than review, that's a data point about pipeline balance.

  7. **Drift Debt** — current open/resolved/wont-fix counts from drift-debt.json. Simple table showing trajectory.

  8. **Dev Journal** — last 3 entries from `docs/dev-journal.md`, rendered as collapsible prose sections at the bottom. Visually distinct from the structured data above — different background, smaller text, clearly labeled as context rather than metrics.

- **R-005** [unit]: The HTML uses simple, clean styling. Dark/light mode based on `prefers-color-scheme`. The page scrolls vertically as a single narrative — not a grid of cards. Color-coded severity badges (red for BLOCKING/CRITICAL, yellow for MEDIUM/NON-BLOCKING, green for clean/resolved). Horizontal bars for trends (inline `<div>` elements with percentage widths). Readable on a 13" laptop screen without horizontal scrolling.

- **R-006** [unit]: `.correctless/dashboard/index.html` is added to `.gitignore` (alongside ROADMAP.md in the existing "Implementation plans" section).

- **R-007** [unit]: The script handles minimal-data projects gracefully. Each section degrades independently: "No workflow history yet", "No QA findings", "No calibration data", etc. The Quality Trajectory section needs at least 2 features to show a trend — with 1 feature, it shows a single bar with a note "Need more features to show a trend." The dashboard is useful from the first feature.

- **R-008** [unit]: `sync.sh` copies `scripts/build-dashboard.sh` to the distribution at `correctless/scripts/build-dashboard.sh` so users get the script when they install the plugin.

- **R-009** [unit]: `/cmetrics` SKILL.md is updated with a one-line mention at the end of its output: "For a full project dashboard, run `bash .correctless/scripts/build-dashboard.sh` and open `.correctless/dashboard/index.html`." This makes the dashboard discoverable at the moment the user is thinking about project-level data.

## Won't Do

- **Live/interactive dashboard** — static snapshot, not a running server. Regenerate when you want fresh data.
- **Chart.js or external charting libraries** — self-contained with zero dependencies. Horizontal bars via `<div>` widths and inline SVG sparklines are sufficient. No CDN links.
- **Diff between snapshots** — each run produces a fresh dashboard. No history of dashboard states.
- **Integration into the pipeline** — not a skill, not part of `/cauto` or `/cdocs`. Standalone script run when the user wants a snapshot.
- **Workflow state file duration tracking** — would require parsing timestamps from workflow state files across branches. Deferred — the token log JSONL gives phase-level cost which is a reasonable proxy for duration.

## Risks

- **Markdown parsing in bash is fragile**: Parsing `workflow-history.md` and `antipatterns.md` with sed/awk/grep will break if the format changes.
  1. Accept — the formats are stable and documented. If they change, the parser breaks visibly (empty sections), not silently (wrong data).

- **Token log JSONL may not be reliably populated**: Token tracking had a silent failure (branch_slug bug, fixed in PR #66) and may still have gaps.
  1. Accept — the Cost by Phase section shows whatever data exists. Missing data shows as "No token data" per R-007. The dashboard doesn't claim completeness.

## Open Questions

- **OQ-001**: Should the script also read `docs/workflow-history.md` format strictly (the exact `### {date} — {feature}` pattern) or be lenient? **Tentative answer**: strict. The format is documented in `/cdocs` and hasn't changed. Strict parsing catches format drift early.
