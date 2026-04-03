# Security Detection Invariant Template

When a feature involves detection rules, pattern matching, or security decisions, the /cspec skill should ensure the spec addresses each of the following concerns.

## Checklist

For each applicable item, draft a starter invariant. Skip items that don't apply — but note why.

### 1. Every rule has TP and FP test cases

- **Check**: Each detection rule ships with at least one true-positive (TP) test case that triggers the rule and at least one plausible false-positive (FP) test case that must not trigger it.
- **Violated when**: A rule is added with only positive matches, and in production it fires on benign traffic (e.g., a SQL injection rule that matches legitimate queries containing "OR"), causing alert fatigue or blocking legitimate users.
- **Starter invariant**: "INV-DET-001: Every detection rule in this feature must have at least one TP test case and at least one realistic FP test case. Rules without both must not be merged."
- **Test approach**: Maintain a test corpus per rule with labeled TP and FP samples. Run each rule against the corpus in CI. Any new rule PR must include additions to both the TP and FP sets. Track the FP/TP ratio over time.

### 2. Regex anchored appropriately

- **Check**: Regular expressions used in detection are anchored to prevent unintended partial matches. Start/end anchors (`^`, `$`), word boundaries (`\b`), or explicit delimiters are used where the pattern must match a complete token, not a substring.
- **Violated when**: An unanchored pattern like `admin` matches `sysadmin` or `administrator`, or a path pattern like `/api/secret` matches `/api/secret-public/docs`, causing false positives or security bypasses depending on match semantics.
- **Starter invariant**: "INV-DET-002: Every regex in this feature must document its anchoring strategy. Patterns intended to match whole tokens must use anchors or word boundaries; substring matching must be explicitly justified."
- **Test approach**: For each regex, include test cases with the target pattern embedded in a larger string (prefix, suffix, and infix). Assert anchored patterns reject these. Review unanchored patterns for documented justification.

### 3. Scan limits emit truncation events

- **Check**: When input exceeds scan limits (max body size, max header count, max regex backtracking steps), the scanner truncates gracefully and emits a structured event indicating what was truncated and how much was skipped.
- **Violated when**: Oversized input is silently truncated, and an attacker hides a payload after the scan limit boundary knowing the detector will never see it. Or the truncation is not logged, making it invisible to operators reviewing coverage gaps.
- **Starter invariant**: "INV-DET-003: When this feature truncates input due to scan limits, it must emit a structured truncation event containing the limit name, the actual size, and the configured maximum."
- **Test approach**: Submit input that exceeds each scan limit by a known amount. Assert the feature emits a truncation event with correct metadata. Assert that detection results for the truncated input are marked as partial, not clean.

### 4. Block actions document what they prevent and what they do not

- **Check**: Every blocking action (request rejection, connection drop, quarantine) has documentation stating what attack it mitigates, what it does not prevent (residual risk), and what user-visible impact it has.
- **Violated when**: A block rule is deployed with the assumption it fully mitigates an attack, but a variant bypasses it (e.g., blocking `<script>` but not `<img onerror=...>`), and the residual risk is never communicated to operators or security reviewers.
- **Starter invariant**: "INV-DET-004: Every block action in this feature must document: (a) the specific threat it mitigates, (b) known residual risks or bypass scenarios, (c) user-visible impact of the block."
- **Test approach**: Review block action documentation for completeness. For each documented residual risk, write a test case confirming the bypass exists (to prevent false confidence). Track bypass test cases alongside block rules.

### 5. Bypass vectors enumerated

- **Check**: Each detection rule or security decision documents known bypass techniques (encoding variations, protocol-level evasion, logic-layer circumvention) and states whether the rule is intended to catch them.
- **Violated when**: A rule detects `../` path traversal but not `..%2F` or `..%252F` (double encoding), or a header check is case-sensitive when the protocol is case-insensitive, and these gaps are never documented or tested.
- **Starter invariant**: "INV-DET-005: Every detection rule in this feature must enumerate known bypass vectors (encoding variants, case sensitivity, protocol-level evasion) and include test cases for each."
- **Test approach**: Maintain a bypass corpus per rule category (encoding, case, unicode normalization, protocol quirks). Run each rule against its bypass corpus. New rules must either pass the relevant bypass tests or document which bypasses are explicitly out of scope.
