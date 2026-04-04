# Resource Lifecycle Invariant Template

When a feature allocates resources such as connections, file handles, goroutines, or map entries, the /cspec skill should ensure the spec addresses each of the following concerns.

## Checklist

For each applicable item, draft a starter invariant. Skip items that don't apply — but note why.

### 1. Every allocation has a corresponding release

- **Check**: Each resource allocation (open, dial, spawn, insert) has a matching release (close, cancel, remove) that executes on every code path — success, error, and panic.
- **Violated when**: A connection is opened but only closed on the success path, or a goroutine is spawned without a tracked cancellation handle, causing resource leaks under error conditions.
- **Starter invariant**: "INV-RESC-001: Every resource allocated by this feature must have a documented release point that executes on all exit paths, including error and panic."
- **Test approach**: Write tests that trigger each error path and assert resource counts return to baseline. Use leak detectors (goroutine counters, connection pool stats) in integration tests.

### 2. Defer cleanup ordered correctly (LIFO)

- **Check**: When multiple resources are acquired sequentially, their deferred cleanup runs in correct LIFO order so that dependencies are respected (e.g., a transaction is rolled back before the connection is returned to the pool).
- **Violated when**: Defers are ordered such that a dependent resource is released before the resource it depends on, causing use-after-close errors or failed rollbacks.
- **Starter invariant**: "INV-RESC-002: Deferred cleanup in this feature must follow LIFO order — resources acquired later must be released before resources they depend on."
- **Test approach**: Code review defer ordering against the dependency chain. Write a test that acquires multiple resources, triggers an error, and asserts cleanup ran in the expected order (via logging or mock instrumentation).

### 3. Error paths release resources

- **Check**: When an operation fails partway through resource acquisition (e.g., opened a file but failed to acquire a lock), all previously acquired resources are released before the error is returned.
- **Violated when**: A function returns an error after acquiring some but not all resources, and the partial acquisitions are not cleaned up — leaking file descriptors, connections, or goroutines on every failed call.
- **Starter invariant**: "INV-RESC-003: If this feature's initialization fails at step N, all resources acquired in steps 1 through N-1 must be released before returning the error."
- **Test approach**: Inject failures at each acquisition step (via mocks or fault injection) and assert that no resources are leaked. Measure file descriptors, goroutine count, or pool size before and after.

### 4. Crash paths have failsafe cleanup

- **Check**: Resources are recoverable or cleaned up even if the process crashes or restarts unexpectedly (e.g., temp files are cleaned on startup, stale lock files are detected).
- **Violated when**: A crash leaves orphaned temp files, stale PID locks, or half-written state that prevents the next startup from succeeding or silently corrupts data.
- **Starter invariant**: "INV-RESC-004: This feature must include a startup reconciliation step that detects and cleans up resources orphaned by a previous crash."
- **Test approach**: Simulate a crash (kill -9 or skip cleanup) and restart the feature. Assert it starts cleanly, detects orphaned resources, cleans them up, and logs the recovery action.

### 5. Long-lived entries have eviction or cleanup

- **Check**: Any map, cache, registry, or collection that grows over time has a bounded size, TTL-based eviction, or periodic cleanup sweep.
- **Violated when**: A map accumulates entries over the lifetime of the process without eviction, causing unbounded memory growth proportional to total events rather than active state.
- **Starter invariant**: "INV-RESC-005: Every long-lived collection in this feature must have a documented maximum size or TTL, with an eviction mechanism that prevents unbounded growth."
- **Test approach**: Run the feature for an extended simulated duration, inserting entries at a steady rate, and assert that the collection size plateaus at the configured bound rather than growing linearly.
