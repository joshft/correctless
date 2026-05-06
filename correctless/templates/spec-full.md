# Spec: {TITLE}

## Metadata
- **Created**: {ISO timestamp}
- **Status**: draft
- **Impacts**: {other spec slugs}
- **Branch**: {branch name}
- **Research**: {path or null}
- **Recommended-intensity**: {standard|high|critical}
- **Intensity**: {standard|high|critical}
- **Intensity reason**: {triggering signals or "user override"}
- **Override**: {none|raised|lowered}

## Context

{What this feature does and why. One paragraph.}

## Scope

{What this covers and what it does NOT.}

## Invariants

### INV-001: {short name}
- **Type**: must
- **Category**: functional
- **Statement**: {testable statement}
- **Violated when**: {condition}
- **Enforcement**: {structural mechanism from PAT-018: allowed-tools | sensitive-file-guard | gate precondition | hash verification | CI test assertion | agent tool-pinning | prompt-level}
- **Test approach**: unit

### INV-002: {short name} [integration]
- **Type**: must
- **Category**: functional
- **Statement**: {testable statement}
- **Violated when**: {condition}
- **Test approach**: integration
- **Integration contract**:
  Entry: {entrypoint from test_via — e.g., httptest.NewServer(handler)}
  Through: {components that must be exercised and must NOT be mocked}
  Exit: {observable behavior — e.g., response body contains X; no mock of Y}

## Prohibitions

### PRH-001: {short name}
- **Statement**: {what must never happen}
- **Detection**: {method}
- **Consequence**: {impact}

## Decision Points

When presenting choices to the user:

1. Present numbered options with the recommended option first
2. Mark the recommended option with "(recommended)"
3. Include 2-4 options maximum
4. Always end with: "Or type your own: ___"
5. Accept the number, the option name, or a typed response

## Open Questions

- **OQ-001**: {question} — {why it matters}
