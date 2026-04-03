# Data Integrity Invariant Template

When a feature involves data transformation, storage, or transmission, the /cspec skill should ensure the spec addresses each of the following concerns.

## Checklist

For each applicable item, draft a starter invariant. Skip items that don't apply — but note why.

### 1. Byte length vs character count explicit for Unicode

- **Check**: Every operation that measures, truncates, or allocates based on string size explicitly states whether it uses byte length or character (rune) count, and the choice is correct for the context (byte length for I/O buffers, character count for user-visible limits).
- **Violated when**: A truncation uses byte length on a UTF-8 string and cuts a multi-byte character in half, producing invalid UTF-8. Or a character-count limit is used for a network buffer, allowing oversized payloads from multi-byte content. Or `len()` is used in Go assuming character count when it returns byte length.
- **Starter invariant**: "INV-DATA-001: Every string length operation in this feature must document whether it measures bytes or characters. Truncation must never produce invalid UTF-8."
- **Test approach**: Supply strings containing multi-byte characters (emoji, CJK, combining characters) at exactly the truncation boundary. Assert truncated output is valid UTF-8. Assert buffer allocations based on byte length are not exceeded by multi-byte content.

### 2. Serialization roundtrips preserve data

- **Check**: Data serialized (to JSON, protobuf, database, wire format) and deserialized back produces a value equal to the original, with no silent field loss, type coercion, or precision degradation.
- **Violated when**: A float64 is serialized to JSON and loses precision beyond 15 significant digits, or a protobuf field is added but the deserializer uses an older schema that silently drops it, or a database column truncates a string without error.
- **Starter invariant**: "INV-DATA-002: Serialization roundtrip (encode then decode) for this feature must produce output equal to the input. Any lossy transformation must be documented and tested."
- **Test approach**: Generate test values at precision boundaries (max int64 as JSON number, strings at column length limits, timestamps at timezone boundaries). Roundtrip through each serialization path and assert equality. Use property-based testing to exercise edge cases.

### 3. Partial writes are atomic or recoverable

- **Check**: Write operations that can fail midway (file writes, multi-row database inserts, multi-field updates) are either atomic (write-to-temp-then-rename, transaction) or recoverable (idempotent retry, WAL).
- **Violated when**: A crash during a file write leaves a half-written config that the next startup cannot parse. Or a database insert of 100 rows fails at row 50 without a transaction, leaving the system in an inconsistent state that is not automatically detected or repaired.
- **Starter invariant**: "INV-DATA-003: Every write operation in this feature must be atomic (all-or-nothing) or recoverable (safe to retry). Partial writes must never leave the system in an undetected inconsistent state."
- **Test approach**: Inject failures at each possible interruption point (after flush but before rename, after row 50 of 100). Assert the system either rolled back completely or can recover to a consistent state on retry. Verify startup detects and handles partial writes.

### 4. Validation at ingress, not at use-site

- **Check**: Data from external sources (user input, API responses, file contents, environment variables) is validated once at the ingress boundary and represented as a validated type internally, rather than re-checked at every use-site.
- **Violated when**: Raw strings are passed deep into the codebase and validated ad hoc at each use-site, leading to inconsistent validation (one path checks for empty, another does not) and defense-in-depth gaps where a new use-site forgets to validate entirely.
- **Starter invariant**: "INV-DATA-004: External data entering this feature must be validated and converted to a domain type at the ingress boundary. Internal code must accept the domain type, not raw input."
- **Test approach**: Attempt to construct the domain type with invalid input and assert it fails at the ingress boundary. Verify that internal functions accept only the domain type (not raw strings/bytes). Grep for raw input types used past the ingress layer.

### 5. Error messages do not leak sensitive data

- **Check**: Error messages, log entries, and API responses produced by this feature do not include sensitive data (credentials, tokens, PII, internal paths, raw query parameters containing secrets).
- **Violated when**: A connection error logs the full DSN including the database password. Or a validation error returns the raw input value which contains a user's API key. Or a stack trace in a production response reveals internal file paths and dependency versions.
- **Starter invariant**: "INV-DATA-005: Error messages and log entries in this feature must not contain credentials, tokens, PII, or internal system paths. Sensitive values must be redacted or replaced with references."
- **Test approach**: Trigger every error path with input containing marked sensitive values (e.g., a known token string). Capture all log output and API responses. Assert the sensitive marker does not appear in any output. Review error format strings for %v/%+v on types that may contain secrets.
