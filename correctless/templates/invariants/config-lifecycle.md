# Config Lifecycle Invariant Template

When a feature adds or modifies configuration fields, the /cspec skill should ensure the spec addresses each of the following concerns.

## Checklist

For each applicable item, draft a starter invariant. Skip items that don't apply — but note why.

### 1. Field appears in all config touchpoints

- **Check**: Every new config field is represented in the raw struct definition, the parse/unmarshal logic, the save/marshal logic, the defaults initialization, the validation function, and any reload handler.
- **Violated when**: A field is added to the struct but omitted from the defaults function (causing zero-value surprises), or present in parse but missing from save (causing config loss on round-trip), or absent from the reload handler (causing stale values after hot reload).
- **Starter invariant**: "INV-CONF-001: Every config field in this feature must appear in all six touchpoints — struct, parse, save, defaults, validation, and reload — verified by a test that round-trips a config through all paths."
- **Test approach**: Write a round-trip test: set every field to a non-default value, save, reload, and assert all values survive. Separately, load a config with all fields omitted and assert defaults are applied. Use reflection or code generation to detect struct fields missing from any touchpoint.

### 2. Validated at parse time

- **Check**: Each config field is validated when the config is first parsed, before any component uses it, with clear error messages that name the field and the constraint.
- **Violated when**: An invalid config value (e.g., negative timeout, empty required string, port out of range) passes parsing silently and causes a confusing runtime failure minutes or hours later.
- **Starter invariant**: "INV-CONF-002: Invalid values for this feature's config fields must be rejected at parse time with an error message that names the field, the invalid value, and the constraint."
- **Test approach**: For each field, supply values at and beyond boundary conditions (zero, negative, empty, max+1, wrong type) and assert that parse returns a descriptive error. Assert that no component starts when validation fails.

### 3. Documented safe default

- **Check**: Every config field has a default value that is safe, functional, and documented — a user who accepts all defaults gets a working, secure system.
- **Violated when**: A field defaults to zero/empty/nil and the feature silently degrades or becomes insecure (e.g., timeout defaults to 0 meaning no timeout, TLS defaults to disabled).
- **Starter invariant**: "INV-CONF-003: Every config field in this feature must have a default value that produces correct, secure behavior without requiring user intervention, documented with a rationale comment."
- **Test approach**: Start the feature with a completely empty config (all defaults) and assert it operates correctly. Review each default value against security and correctness criteria.

### 4. Interdependent fields validated together

- **Check**: Config fields that have logical relationships (e.g., min < max, retry count requires retry interval, TLS cert requires TLS key) are validated as a group, not individually.
- **Violated when**: Each field passes individual validation, but the combination is invalid — for example, max-connections is set to 5 but connection-pool-size is set to 10, or a retry interval is specified without enabling retries.
- **Starter invariant**: "INV-CONF-004: Interdependent config fields in this feature must be validated together, and the error message must name all fields involved in the constraint."
- **Test approach**: Supply config combinations where individual fields are valid but the combination is not. Assert that cross-field validation catches these and produces an error naming all involved fields.

### 5. Config wiring reaches runtime components

- **Check**: Parsed config values are actually delivered to the runtime component that uses them. A `Set*Config` method (or equivalent provisioning call) exists, is called during initialization, and the component's runtime state reflects the parsed values.
- **Violated when**: Config is parsed correctly and tests pass by constructing the component with hand-set values, but in production the component never receives the config because the wiring call is missing. The feature is dead code despite all tests passing.
- **Starter invariant**: "INV-CONF-006: An integration test verifies the config round-trip from file to runtime: construct a config with non-default values, run the real initialization path (module provisioning, dependency injection, etc.), then assert the runtime component's config snapshot contains the expected values. This test must fail if any wiring call is missing."
- **Test approach**: **This MUST be an integration test, not a unit test.** Do NOT hand-construct the component with config values — that bypasses the wiring path and defeats the purpose. Instead: load config from a test fixture, run the real initialization/provisioning path, then read the component's live config and assert field values match. If using an atomic config snapshot pattern, read the snapshot and verify. Run this test as part of the standard test suite so it executes on every change.

### 6. Reload does not race with in-flight requests

- **Check**: Config reload applies atomically from the perspective of any in-flight request — a request sees either the old config or the new config, never a mix of both.
- **Violated when**: A hot reload updates config fields one at a time while requests are in flight, causing a request to read the new timeout but the old retry count, or the new TLS cert but the old TLS key.
- **Starter invariant**: "INV-CONF-005: Config reload in this feature must swap the entire config atomically (e.g., pointer swap with atomic.Value) so that no in-flight request observes a partial update."
- **Test approach**: Start a sustained load of requests, trigger a config reload that changes multiple interdependent fields, and assert that every request's observed config is internally consistent (all old or all new, never mixed). Run with `-race`.
