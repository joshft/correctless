# AI Antipattern Checklist (Semantic)

These patterns are NOT detectable by grep/regex. They require human or LLM semantic review.
Referenced by `/ctdd` QA agent, `/creview`, and `/cverify` smell check.

## Patterns

1. **disconnected middleware** -- Middleware or hooks registered but never called in the actual request chain. The code exists but the wiring is missing, so the feature is dead code in production.

2. **scope creep** -- Implementation adds capabilities beyond what the spec describes. Extra endpoints, additional fields, bonus features that were never requested. Each addition is an untested surface area.

3. **over-abstraction** -- Unnecessary layers of indirection: base classes with a single subclass, factory functions that create one type, adapter patterns wrapping a single dependency. Adds complexity without flexibility.

4. **mock-testing-the-mock** -- Tests that construct their own inputs and verify their own outputs. The mock is so elaborate that the test passes regardless of whether the real system works. The test exercises the test setup, not the production code.

5. **happy-path-only testing** -- Tests only cover the success case. No error paths, no boundary conditions, no concurrent access, no malformed input. The implementation appears correct until it meets real-world data.

6. **silently removed safety guards** -- Existing validation, error handling, or security checks that were present before the feature and are now missing or weakened. Often happens during refactoring when the AI rebuilds a function from scratch instead of modifying it.
