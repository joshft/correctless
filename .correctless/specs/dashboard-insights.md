# Spec: Dashboard Trend Insights

## Metadata
- **Task**: dashboard-insights
- **Recommended-intensity**: standard
- **Intensity**: standard
- **Intensity reason**: no signals triggered; user explicitly requested standard
- **Override**: lowered

## What

Add trend analysis sections to the project dashboard that answer "is Correctless working?" — QA rounds per feature over time, override rate trend, intensity accuracy summary, and fix rate. These transform the dashboard from a data dump into a trajectory view.

## Rules

- **R-001** [unit]: A new "QA Rounds Trend" section is added to the dashboard after the Quality Trajectory section. For each feature (chronologically from workflow-history.md), display the QA round count as a horizontal bar, same visual format as Quality Trajectory. The data is already parsed from workflow-history.md (the `QA rounds: N` field in each entry body). A declining bar length across features is a healthy trend.

- **R-002** [unit]: A new "Intensity Accuracy" section is added to the dashboard. It reads the intensity calibration data (already parsed) and computes: how many features the user agreed with the recommendation vs raised vs lowered. Displays as a simple summary: "Agreed: N, Raised: N, Lowered: N" with the percentage agreed. This uses the `recommended_intensity` and `actual_intensity` fields from calibration entries.

- **R-003** [unit]: A new "Override Rate" section is added to the dashboard after Intensity Accuracy. For each feature that has override data (from `.correctless/meta/overrides/` files, already parsed), show the override count. A simple horizontal bar per feature, same format as QA Rounds Trend. Features with 0 overrides are shown with an empty bar. The section includes a one-line summary: "Mean: N.N overrides per feature."

- **R-004** [unit]: A new "Fix Rate" section is added to the dashboard. It reads the findings data (already parsed with task and status fields) and computes: total findings, count with status "fixed", count with status "open" or other. Displays as a single summary line: "N/M findings fixed (X%)" with a simple bar showing the ratio. If no findings have status fields, the section shows "Fix status data not available."

- **R-005** [unit]: The new sections are inserted into the dashboard's vertical narrative between the existing sections. Order: Project Summary → Quality Trajectory → QA Rounds Trend → Pipeline Phase Distribution → Fix Rate → Antipattern Health → Intensity Accuracy → Override Rate → Cost by Phase → Drift Debt → Dev Journal.

- **R-006** [unit]: All new sections degrade gracefully when data is missing. QA Rounds Trend shows "No QA round data" if no features have round counts. Intensity Accuracy shows "No calibration data" if no calibration entries exist. Override Rate shows "No override data" if no override files exist. Fix Rate shows "No findings data" if no findings exist.

## Won't Do

- **Round distribution within QA** — the `round` field in qa-findings JSON is file-level (last round that ran), not per-finding. Can't determine which round caught which finding without per-finding round data. Deferred until the data model supports it.
- **Feature velocity** — confounded by schedule, feature size, other projects. Not meaningful for solo developers.
- **Rules per feature** — measures spec complexity, not project health.
- **Word frequency across findings** — antipatterns already do this better manually.

## Risks

- **Small data produces noisy trends**: With 6 overrides across 37 features, the override rate trend is essentially flat with occasional spikes. The visualization is correct but may not show a meaningful trend until 50+ features.
  1. Accept — the data is still useful as a record. The trend becomes meaningful as the project matures.

## Open Questions

- **OQ-001**: Should the QA Rounds Trend also show a rolling average line (e.g., 5-feature window) to smooth noise? **Tentative answer**: no, keep it simple. The bars themselves show the trend visually. A rolling average adds JS complexity for marginal value at 37 features. Revisit at 100+ features.
