# Architecture

## Trust Boundaries

### TB-001: Config-sourced commands and patterns
See [docs/architecture/trust-boundaries.md](docs/architecture/trust-boundaries.md).

### TB-002: Script-generated JSON → LLM agent context
See [docs/architecture/trust-boundaries.md](docs/architecture/trust-boundaries.md).

### TB-003: LLM-generated historical findings → review agent context
See [docs/architecture/trust-boundaries.md](docs/architecture/trust-boundaries.md).

### TB-004: LLM orchestrator autonomy boundary
See [docs/architecture/trust-boundaries.md](docs/architecture/trust-boundaries.md).

### TB-005: Intra-skill agent-to-agent handoff
See [docs/architecture/trust-boundaries.md](docs/architecture/trust-boundaries.md).

### TB-006: Session transcript filesystem reads (~/.claude/projects/)
See [docs/architecture/trust-boundaries.md](docs/architecture/trust-boundaries.md).

### TB-007: External web content ingestion via research agent
See [docs/architecture/trust-boundaries.md](docs/architecture/trust-boundaries.md).

### TB-008: External model output → Claude review synthesis → spec
See [docs/architecture/trust-boundaries.md](docs/architecture/trust-boundaries.md).

### TB-001c: Structured external-tool config → argv (no eval)
See [docs/architecture/trust-boundaries.md](docs/architecture/trust-boundaries.md).

### TB-009: Untrusted GitHub issue content → autonomous orchestrator
See [docs/architecture/trust-boundaries.md](docs/architecture/trust-boundaries.md).

### TB-004d: Autonomous issue-selection authority
See [docs/architecture/trust-boundaries.md](docs/architecture/trust-boundaries.md).

### TB-010: Claude Code harness → hook stdin JSON
See [docs/architecture/trust-boundaries.md](docs/architecture/trust-boundaries.md).

## Abstractions

### ABS-001: Shared script library (scripts/lib.sh)
See [docs/architecture/abstractions.md](docs/architecture/abstractions.md).

### ABS-002: Ephemeral in-context classification (shift-left review)
See [docs/architecture/abstractions.md](docs/architecture/abstractions.md).

### ABS-003: State file locking (scripts/lib.sh)
See [docs/architecture/abstractions.md](docs/architecture/abstractions.md).

### ABS-004: Hook metadata headers for auto-registration
See [docs/architecture/abstractions.md](docs/architecture/abstractions.md).

### ABS-005: Cross-skill calibration data (.correctless/meta/)
See [docs/architecture/abstractions.md](docs/architecture/abstractions.md).

### ABS-006: Token-log JSONL contract (.correctless/artifacts/)
See [docs/architecture/abstractions.md](docs/architecture/abstractions.md).

### ABS-007: Escalation file contract (.correctless/artifacts/)
See [docs/architecture/abstractions.md](docs/architecture/abstractions.md).

### ABS-008: preferences.md contract (.correctless/)
See [docs/architecture/abstractions.md](docs/architecture/abstractions.md).

### ABS-009: Path-scoped rule files (.claude/rules/)
See [docs/architecture/abstractions.md](docs/architecture/abstractions.md).

### ABS-010: Plugin-agent file contract (narrow)
See [docs/architecture/abstractions.md](docs/architecture/abstractions.md).

### ABS-011: Decision record (.correctless/artifacts/)
See [docs/architecture/abstractions.md](docs/architecture/abstractions.md).

### ABS-012: Intent summary (.correctless/artifacts/)
See [docs/architecture/abstractions.md](docs/architecture/abstractions.md).

### ABS-013: Auto Run Report (.correctless/artifacts/)
See [docs/architecture/abstractions.md](docs/architecture/abstractions.md).

### ABS-014: Pending-decision checkpoint (.correctless/artifacts/)
See [docs/architecture/abstractions.md](docs/architecture/abstractions.md).

### ABS-015: Pipeline lockfile (.correctless/artifacts/)
See [docs/architecture/abstractions.md](docs/architecture/abstractions.md).

### ABS-016: Auto-policy config (.correctless/config/)
See [docs/architecture/abstractions.md](docs/architecture/abstractions.md).

### ABS-017: Structured decision request (DR-xxx)
See [docs/architecture/abstractions.md](docs/architecture/abstractions.md).

### ABS-018: Review-triage artifact (.correctless/artifacts/)
See [docs/architecture/abstractions.md](docs/architecture/abstractions.md).

### ABS-019: Supervisor mandate contract (agents/supervisor.md)
See [docs/architecture/abstractions.md](docs/architecture/abstractions.md).

### ABS-020: Override scrutiny lifecycle (scripts/override-scrutiny.sh)
See [docs/architecture/abstractions.md](docs/architecture/abstractions.md).

### ABS-021: Override history directory (.correctless/meta/overrides/)
See [docs/architecture/abstractions.md](docs/architecture/abstractions.md).

### ABS-022: Install manifest (.correctless/.install-manifest.json)
See [docs/architecture/abstractions.md](docs/architecture/abstractions.md).

### ABS-023: Entrypoints YAML contract (.correctless/ARCHITECTURE.md)
See [docs/architecture/abstractions.md](docs/architecture/abstractions.md).

### ABS-024: Entry/Through/Exit integration test contract format
See [docs/architecture/abstractions.md](docs/architecture/abstractions.md).

### ABS-025: Agent hook JSON contract (hooks/*.json)
See [docs/architecture/abstractions.md](docs/architecture/abstractions.md).

### ABS-026: Cost artifact contract (.correctless/artifacts/)
See [docs/architecture/abstractions.md](docs/architecture/abstractions.md).

### ABS-027: Harness fingerprint store contract (.correctless/meta/)
See [docs/architecture/abstractions.md](docs/architecture/abstractions.md).

### ABS-028: Test-features baseline contract (.correctless/test-features/)
See [docs/architecture/abstractions.md](docs/architecture/abstractions.md).

### ABS-029: Audit findings persistence contract (.correctless/artifacts/findings/)
See [docs/architecture/abstractions.md](docs/architecture/abstractions.md).

### ABS-030: Autonomous decisions JSONL contract
See [docs/architecture/abstractions.md](docs/architecture/abstractions.md).

### ABS-031: Pipeline manifest artifact contract
See [docs/architecture/abstractions.md](docs/architecture/abstractions.md).

### ABS-032: Dashboard UI output contract (.correctless/dashboard/)
See [docs/architecture/abstractions.md](docs/architecture/abstractions.md).

### ABS-033: Deferred findings backlog contract (.correctless/meta/)
See [docs/architecture/abstractions.md](docs/architecture/abstractions.md).

### ABS-034: Probe results artifact contract (.correctless/artifacts/)
See [docs/architecture/abstractions.md](docs/architecture/abstractions.md).

### ABS-035: Workflow-advance module contract (scripts/wf/)
See [docs/architecture/abstractions.md](docs/architecture/abstractions.md).

### ABS-036: Lens recommendation artifact (.correctless/artifacts/)
See [docs/architecture/abstractions.md](docs/architecture/abstractions.md).

### ABS-037: Cross-feature intelligence brief (.correctless/meta/)
See [docs/architecture/abstractions.md](docs/architecture/abstractions.md).

### ABS-038: Archive file contract (.correctless/)
See [docs/architecture/abstractions.md](docs/architecture/abstractions.md).

### ABS-039: Slug-type classification mapping (scripts/prune-scan.sh)
See [docs/architecture/abstractions.md](docs/architecture/abstractions.md).

### ABS-040: Prune-pattern baseline manifest (.correctless/meta/)
See [docs/architecture/abstractions.md](docs/architecture/abstractions.md).

### ABS-041: SFG lift-and-restore sentinel + final-state backstop
See [docs/architecture/abstractions.md](docs/architecture/abstractions.md).

### ABS-042: Sole-writer external-review producer (scripts/external-review-run.sh)
See [docs/architecture/abstractions.md](docs/architecture/abstractions.md).

### ABS-043: Chore-run manifest contract (.correctless/artifacts/)
See [docs/architecture/abstractions.md](docs/architecture/abstractions.md).

### ABS-044: Cross-run re-selection store (.correctless/meta/)
See [docs/architecture/abstractions.md](docs/architecture/abstractions.md).

### ABS-045: sensitive-file-guard capability boundary (write-target guardrail)
See [docs/architecture/abstractions.md](docs/architecture/abstractions.md).

### ABS-046: Audit-trail JSONL producer/consumer contract (.correctless/artifacts/)
See [docs/architecture/abstractions.md](docs/architecture/abstractions.md).

## Patterns

> **Reader note**: Some PAT entries below are migrated index lines — the heading is followed by a single See-link pointing to a canonical rule file under `.claude/rules/`. Full rule bodies live in the rule file; this document retains the stable ID and title. See **ABS-009** for the governing contract and the measurement gate that decides whether this pattern becomes the default. New PAT entries default to full-body form in this file until the rules-canonical experiment (PAT-001 migration, 2026-04-10) proves out its measurement gate.

### PAT-001: PreToolUse hook conventions
See `.claude/rules/hooks-pretooluse.md`.

### PAT-002: Separate concerns in hooks
See [docs/architecture/patterns.md](docs/architecture/patterns.md).

### PAT-003: Phase-transition scripts
See [docs/architecture/patterns.md](docs/architecture/patterns.md).

### PAT-004: Data budget for historical context
See [docs/architecture/patterns.md](docs/architecture/patterns.md).

### PAT-005: PostToolUse hook conventions
See [docs/architecture/patterns.md](docs/architecture/patterns.md).

### PAT-007: Conditional update path testing (guards AP-002)
See [docs/architecture/patterns.md](docs/architecture/patterns.md).

### PAT-008: Idempotent migration testing (guards AP-004)
See [docs/architecture/patterns.md](docs/architecture/patterns.md).

### PAT-006: Hook self-description via metadata headers
See [docs/architecture/patterns.md](docs/architecture/patterns.md).

### PAT-009: Orchestrator skill conventions
See [docs/architecture/patterns.md](docs/architecture/patterns.md).

### PAT-010: jq `as $var` bindings must be explicitly parenthesized
See [docs/architecture/patterns.md](docs/architecture/patterns.md).

### PAT-011: SHA-256 hash verification chain
See [docs/architecture/patterns.md](docs/architecture/patterns.md).

### PAT-012: Wiring tests over keyword tests (guards AP-003)
See [docs/architecture/patterns.md](docs/architecture/patterns.md).

### PAT-013: Doc-update invariant on refactoring (guards AP-005)
See [docs/architecture/patterns.md](docs/architecture/patterns.md).

### PAT-014: Scanner tag conventions (`# scanner: security`, `# scanner: library`)
See [docs/architecture/patterns.md](docs/architecture/patterns.md).

### PAT-015: Content-pairing drift tests (guards AP-005 dual-source drift)
See [docs/architecture/patterns.md](docs/architecture/patterns.md).

### PAT-016: Glob over directory contents — never enumerate (guards AP-024)
See [docs/architecture/patterns.md](docs/architecture/patterns.md).

### PAT-017: canonicalize_path security invariants
See `.claude/rules/canonicalize-path.md`.

### PAT-018: Structural enforcement over prompt-level instruction
See [docs/architecture/patterns.md](docs/architecture/patterns.md).

### PAT-019: Dormant-signal graceful degradation
See [docs/architecture/patterns.md](docs/architecture/patterns.md).

### PAT-020: Fail-closed realpath probe before canonicalization-dependent security checks
See [docs/architecture/patterns.md](docs/architecture/patterns.md).

## Environment Assumptions

### ENV-001: Bash 4+ required
See [docs/architecture/environment.md](docs/architecture/environment.md).

### ENV-002: jq 1.7+ required
See [docs/architecture/environment.md](docs/architecture/environment.md).

### ENV-003: Filesystem modification timestamps unreliable for recency
See [docs/architecture/environment.md](docs/architecture/environment.md).

### ENV-004: gh CLI as optional dependency
See [docs/architecture/environment.md](docs/architecture/environment.md).

### ENV-005: Claude Code path-scoped rule loading
See [docs/architecture/environment.md](docs/architecture/environment.md).

### ENV-006: POSIX-portable external tools (grep, sed, awk)
See [docs/architecture/environment.md](docs/architecture/environment.md).

### ENV-008: python3 with PyYAML (or yq) for entrypoints extraction
See [docs/architecture/environment.md](docs/architecture/environment.md).

### ENV-007: Plugin-agent loader contract
See [docs/architecture/environment.md](docs/architecture/environment.md).

### ENV-009: Claude Code session transcript storage format
See [docs/architecture/environment.md](docs/architecture/environment.md).

### ENV-010: Agent tool worktree isolation contract
See [docs/architecture/environment.md](docs/architecture/environment.md).

### ENV-011: Claude Code v2.1.150+ for `disallowed-tools` skill frontmatter
See [docs/architecture/environment.md](docs/architecture/environment.md).

### ENV-012: Claude Code InstructionsLoaded hook event
See [docs/architecture/environment.md](docs/architecture/environment.md).
