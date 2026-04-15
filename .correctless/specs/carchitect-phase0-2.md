# Spec: /carchitect Phase 0 — Architecture Definition Skill

## Metadata
- **Task**: carchitect-phase0
- **Recommended-intensity**: high
- **Intensity**: high
- **Intensity reason**: file path signal (skills/, hooks/); keyword signal (trust boundary in feature description); project floor is high
- **Override**: none
- **Review findings**: 10 findings, all accepted (see Review Findings Summary)

## What

A new skill (`/carchitect`) that produces a structured ARCHITECTURE.md for any project. Two modes: greenfield (directed discovery from scratch) and reverse-engineer (synthesize from existing code). Output includes machine-referenceable entrypoints and scope mappings in fenced YAML blocks, plus human-readable prose sections for patterns, layers, boundaries, and decisions. Phase 0 ships the skill standalone — no downstream skill changes.

## Rules

- **R-001** [unit]: The skill file `skills/carchitect/SKILL.md` exists with valid frontmatter (`name`, `description`, `allowed-tools`, `context: fork`). The `allowed-tools` list includes `Read`, `Grep`, `Glob`, `Bash(git*)`, `Write(.correctless/ARCHITECTURE.md)`, `Edit(.correctless/ARCHITECTURE.md)`, and appropriate MCP tools for Serena/Context7 fallback. The write target is `.correctless/ARCHITECTURE.md` (the Correctless-managed doc, consistent with `/cupdate-arch`'s write target). `Edit` is scoped to `.correctless/ARCHITECTURE.md` only — the skill does not need unscoped edit access. Prerequisite: add ABS-023 to ARCHITECTURE.md documenting the entrypoints YAML contract (sole writer: `/carchitect`, extraction: `scripts/extract-entrypoints.sh`, schema: R-004, evolution: additive fields only). Prerequisite: add ENV-008 to ARCHITECTURE.md documenting `python3` with PyYAML (or `yq`) as a dependency for entrypoints extraction, with the fallback chain `yq` → `python3 -c 'import yaml; ...'` → exit 1 with error message.

- **R-002** [integration]: When invoked on a project with existing source code and no ARCHITECTURE.md (or a stub with `{PLACEHOLDER}` markers), the skill enters reverse-engineer mode. It must: (a) scan the codebase for structural patterns, (b) report what it examined as a coverage report ("analyzed N of M files of type X"), (c) present inconsistencies as enumerated groups ("X handlers do A, Y handlers do B — which is canonical?") rather than silently picking the majority, and (d) require user confirmation before writing any pattern as canonical.

- **R-003** [integration]: When invoked on a project with little or no source code, the skill enters greenfield mode. It must: (a) ask concrete discovery questions (what does it do, who calls it, what does it call, deployment model, optimization priority, constraints), (b) present architectural decisions using the tiered format (Tier 1: full tradeoffs, Tier 2: brief tradeoffs + recommendation, Tier 3: recommendation only), and (c) not produce scaffolding or code — document only.

- **R-004** [unit]: The output ARCHITECTURE.md contains a `## Entrypoints` section with a fenced YAML block between `<!-- correctless:entrypoints:start -->` and `<!-- correctless:entrypoints:end -->` marker comments. The YAML schema is a list of objects, each with fields: `name` (string, required), `type` (enum: http, cli, grpc, queue, cron, library, websocket — required), `handler` (string: file path + symbol, required), `test_via` (non-empty string: how an integration test reaches this entrypoint — see OQ-004 for future schema tightening, required), `scope` (list of glob patterns: which source files this entrypoint governs, required). The skill validates all fields at write time before committing to disk, including enum membership for `type` and non-empty for `test_via`. Invalid entries are rejected with an error, not written. Prerequisite: add TB-005 to ARCHITECTURE.md documenting the intra-skill agent-to-agent handoff trust boundary — one agent's draft becomes input to another agent's adversarial review. Frame generally ("intra-skill agent-to-agent handoff where one agent's output feeds another agent's reasoning context") so other skills can cite it.

- **R-005** [unit]: A helper script at `scripts/extract-entrypoints.sh` extracts the entrypoints YAML from `.correctless/ARCHITECTURE.md` and outputs valid YAML to stdout. The script reads between the `correctless:entrypoints:start` and `correctless:entrypoints:end` marker comments, strips the code fence, and validates the result is parseable YAML via the fallback chain: `yq` → `python3 -c 'import yaml; yaml.safe_load(open("/dev/stdin").read())'` → exit 1 with message "Neither yq nor python3 with PyYAML available." Returns exit 0 on success with YAML on stdout, exit 1 if markers not found, YAML is invalid, or no parser available. The script does NOT validate enum membership or field semantics — that is the writer's responsibility (R-004). Extraction is dumb and fast; validation is at write time. Phase 1+ consumers call this script, not a raw pipeline. A test validates the script against a fixture.

- **R-006** [integration]: In reverse-engineer mode, the skill invokes the adversarial second-pass agent via `Task(subagent_type="correctless:architecture-reviewer")`. The agent is defined in `agents/architecture-reviewer.md` with tool allowlist `{Read, Grep, Glob}` (read-only — no Write, no Edit). It reads the draft ARCHITECTURE.md and the codebase with the prompt: "Find patterns this document claims exist but that the codebase violates. Find entrypoints the document misses." Findings are categorized as: (a) pattern claimed but violated, (b) entrypoint missing, (c) inconsistency the draft smoothed over. Findings are presented to the user sequentially, one at a time, consistent with the `/creview` presentation pattern. The user adjudicates each before seeing the next. The agent's scope is narrow: adversarial review of architecture drafts only. Do not expand it into general-purpose architecture analysis.

- **R-007** [unit]: The output ARCHITECTURE.md contains these sections in order: System Purpose and Boundaries, Entrypoints (with structured YAML), Key Patterns, Layer Conventions, Anti-Patterns, Decision Log, Known Limitations. Of these, only Entrypoints is mandatory and structured (R-004/R-005). The remaining sections are prose stubs that the user can fill in — the skill populates what it can from discovery/analysis but marks uncertain sections with `<!-- TODO: verify -->` rather than presenting guesses as facts.

- **R-008** [unit]: The decision format for greenfield Tier 1 decisions includes: numbered options (minimum 2), each with advantages and disadvantages, a "Best when" qualifier, a recommendation with rationale, and an "Or describe your own approach: ___" escape hatch. Tier 2 decisions have brief tradeoffs and recommendation. Tier 3 decisions have recommendation only with brief rationale.

- **R-009** [unit]: The skill asks the user which mode to use: "Does this project have meaningful existing code I should analyze, or are we designing from scratch?" Two options: (1) Reverse-engineer — analyze existing code, (2) Greenfield — design from scratch. If ARCHITECTURE.md exists with real content (no `{PLACEHOLDER}` markers and more than 20 lines of non-comment text), the skill offers a third option: see R-015. Non-comment lines are defined as lines not matching `^\s*$`, `^\s*<!--`, or `^\s*#`. The user can also specify mode via `--greenfield` or `--reverse-engineer` flags to skip the prompt.

- **R-010** [integration]: The skill's coverage report in reverse-engineer mode lists: (a) directories scanned with file counts, (b) files analyzed vs skipped (with skip reasons: too small, binary, generated, vendored/dependency), (c) patterns detected with file lists per pattern group. The coverage report respects `.gitignore` and excludes known vendor/dependency directories (`node_modules/`, `vendor/`, `.venv/`, `target/`, `build/`, `dist/`). This is output as a structured summary before the draft is presented — the user sees the sampling, not just the conclusions.

- **R-011** [unit]: The skill is registered in `sync.sh` for distribution propagation and has a corresponding entry in `docs/skills/carchitect.md`. The CONTRIBUTING.md and README.md skill counts are updated (or the AP-005 drift test will catch it).

- **R-012** [unit]: The skill does NOT modify any other skill's SKILL.md, frontmatter, or behavior. Phase 0 is standalone — downstream skill integrations are deferred to Phases 1-5 per the roadmap. The skill writes only to `.correctless/ARCHITECTURE.md`.

- **R-013** [integration]: In reverse-engineer mode, detected patterns are batched by confidence. High-confidence patterns (>= 75% of examined files of that type following the pattern, where "files of that type" means files matching the pattern the skill is attempting to document — e.g., for a "handler pattern," files in `pkg/handlers/**` or files matching a skill-determined glob) are presented as a group with a "confirm all or drill into any" prompt. Low-confidence patterns (< 75% of examined files following the pattern) are presented individually with 2-3 representative files and the question "Is this pattern intentional, or is this coincidence?" Patterns the user rejects are not documented. Patterns confirmed are documented with representative files as examples. Cap: at most 10 patterns presented per session. If more are detected, rank by coverage percentage and defer the rest with "N additional patterns detected — run `/carchitect --continue` to review the next batch." The `--continue` flag works within a session only — cross-session continuation is not supported (pattern state is ephemeral, not persisted to an artifact).

- **R-014** [unit]: The `## Entrypoints` section includes a `test_via` field per entrypoint that describes the canonical way to write an integration test against that entrypoint. For HTTP entrypoints, this is the test server construction. For CLI entrypoints, the exec invocation. For library entrypoints, the public API import. This field is what Phase 1's test audit will use to determine whether a test goes through the right path. The field must be a non-empty string (enforced at write time by R-004).

- **R-015** [unit]: If ARCHITECTURE.md exists with real content (no `{PLACEHOLDER}` markers and more than 20 lines of non-comment text per R-009's definition), the skill detects this and presents options: (1) "Delete the existing doc and start fresh with reverse-engineer mode" — destructive but clean, (2) "Keep the existing doc — use `/cupdate-arch` for feature-level updates instead" — redirects to the right tool, (3) "Exit — I'll handle this manually." The skill does NOT silently overwrite or merge with existing content. Refresh/regeneration mode is deferred to a future phase.

## Won't Do

- **Scaffolding or code generation** — the skill produces a document, not files.
- **Downstream skill integration** — no changes to `/cspec`, `/ctdd`, `/caudit`, `/creview`, or any other skill. Those are Phases 1-5.
- **Automated architecture enforcement** — the document is advisory in Phase 0.
- **Formal modeling** — `/cmodel` handles Alloy/TLA+.
- **Continuous maintenance** — `/cupdate-arch` handles feature-level deltas.
- **Refresh/regeneration of existing ARCHITECTURE.md** — Phase 0 handles creation only. Regeneration over an existing filled-in doc is a future phase (see R-015 for the detection and redirect).

## Risks

- **Reverse-engineer mode produces plausible but wrong architecture**: Agent reads 20 files, infers a pattern, misses the 5 places where the pattern is violated.
  1. Mitigate (recommended) — R-006 (adversarial second pass via read-only plugin agent), R-010 (coverage report), R-013 (user confirmation per pattern). Three independent mitigation layers.

- **Greenfield mode produces generic architecture**: Discovery questions are too generic, output looks like a template, user doesn't engage.
  1. Mitigate (recommended) — R-003 requires concrete questions tied to the user's answers, R-008 requires honest tradeoffs not boilerplate recommendations.

- **Entrypoints YAML schema becomes a maintenance burden**: Schema changes require updating the skill, tests, and all downstream consumers (Phases 1+).
  1. Accept — the schema is deliberately minimal (6 fields). Pin it now, evolve via additive fields only. The helper script (R-005) abstracts the extraction, so format changes touch one file.

- **User expects a complete architecture doc, gets mostly stubs**: Phase 0 only mandates entrypoints; other sections are prose stubs.
  1. Accept — stubs are clearly marked. Users who want more can fill them in or re-run with more context.

- **Overlap confusion with /csetup and /cupdate-arch**: Users don't know which skill to run.
  1. Mitigate (recommended) — R-012 keeps Phase 0 standalone. R-015 detects existing docs and redirects. The skill's help text explicitly states the boundary.

- **Decision fatigue in reverse-engineer mode**: 15-20 detected patterns each requiring confirmation overwhelms the user.
  1. Mitigate (recommended) — R-013 batches high-confidence patterns, presents low-confidence individually, caps at 10 per session.

## Open Questions

- **OQ-001**: Should reverse-engineer mode require an existing test suite? Patterns inferred from code without tests may be misleading. **Tentative answer**: no hard requirement, but the coverage report (R-010) should flag "no test files found — patterns inferred from implementation only, confidence is lower."

- **OQ-002**: Should the entrypoints YAML live in ARCHITECTURE.md (fenced block) or in a sibling file? Fenced-in-markdown is one file to review in PRs but ugly to edit. Sibling file is cleaner but creates a sync problem. **Tentative answer**: fenced YAML in ARCHITECTURE.md for now (R-004). The helper script (R-005) abstracts the extraction, making the decision reversible — swap the helper's backend to read a sibling file, no consumer changes.

- **OQ-003**: How does `/carchitect` interact with monorepos? **Tentative answer**: defer — Phase 0 targets single-project repos. The entrypoints YAML schema has no `package` or `module` field. Adding one later is a non-breaking additive change; the helper script (R-005) is the migration boundary.

- **OQ-004**: Should `test_via` be a freeform string or a structured object? Freeform strings ("use httptest", "httptest.NewServer(...)") produce inconsistent data. A structured schema (`{pattern: "httptest.NewServer", imports: ["net/http/httptest"]}`) is more machine-readable but heavier. **Tentative answer**: non-empty freeform string in Phase 0 (enforced at write time by R-004). If Phase 1's test audit discovers `test_via` is too loose for mechanical checking, tighten the schema then — the helper script (R-005) can migrate the format without consumers knowing.

## Review Findings Summary

10 findings from adversarial review (self-assessment + 4 agents), all accepted:

1. Added ABS-023 prerequisite for entrypoints YAML contract (R-001)
2. Added ENV-008 prerequisite for python3/yq dependency (R-001)
3. Created agents/architecture-reviewer.md with read-only tools {Read, Grep, Glob} (R-006)
4. Added TB-005 prerequisite for intra-skill agent-to-agent trust boundary, framed generally (R-004)
5. Added non-empty constraint on test_via (R-004, R-014)
6. Defined high-confidence as >= 75% with explicit denominator definition (R-013)
7. Subsumed by finding 3 — adversarial agent is now read-only
8. Modified: enum validation at write time in the skill (R-004), not in extraction script (R-005)
9. Documented --continue as session-scoped only (R-013)
10. Defined "non-comment text" as lines not matching `^\s*$`, `^\s*<!--`, or `^\s*#` (R-009)
