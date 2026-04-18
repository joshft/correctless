# Spec: {TITLE}

## Metadata
- **Task**: {feature name}
- **Recommended-intensity**: {standard|high|critical}
- **Intensity**: {standard|high|critical}
- **Intensity reason**: {triggering signals or "user override"}
- **Override**: {none|raised|lowered}

## What

{One paragraph describing what this feature does, who it's for, and why it matters.}

## Rules

- **R-001** [{test_level}]: {testable statement}

For `[integration]` rules with Entry/Through/Exit contracts (derived from ARCHITECTURE.md entrypoints):

- **R-002** [integration]: {testable statement}
  Entry: {entrypoint from test_via — e.g., httptest.NewServer(handler)}
  Through: {components that must be exercised and must NOT be mocked}
  Exit: {observable behavior — e.g., response body contains X; no mock of Y}

## Won't Do

- {out of scope item}

## Risks

- {risk} — {mitigation or "accepted"}

## Decision Points

When presenting choices to the user:

1. Present numbered options with the recommended option first
2. Mark the recommended option with "(recommended)"
3. Include 2-4 options maximum
4. Always end with: "Or type your own: ___"
5. Accept the number, the option name, or a typed response

## Open Questions

- {question}
