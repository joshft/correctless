# Concurrency Invariant Template

When a feature involves goroutines, channels, mutexes, or shared state, the /cspec skill should ensure the spec addresses each of the following concerns.

## Checklist

For each applicable item, draft a starter invariant. Skip items that don't apply — but note why.

### 1. Explicit shutdown paths

- **Check**: Every goroutine monitors `ctx.Done()` or an equivalent cancellation signal and exits promptly when it fires.
- **Violated when**: A goroutine blocks indefinitely on a channel send/receive or loop iteration without selecting on a context cancellation path, causing goroutine leaks on shutdown.
- **Starter invariant**: "INV-CONC-001: Every goroutine spawned by this feature must select on ctx.Done() and terminate within [bounded duration] of context cancellation."
- **Test approach**: Cancel the parent context under load and assert (via runtime.NumGoroutine or leak detector) that all feature goroutines exit within the bounded duration.

### 2. Bounded mutex hold time

- **Check**: No mutex is held across I/O operations (network calls, disk reads, channel sends to unbuffered/full channels).
- **Violated when**: A lock is acquired, then the code performs a blocking I/O operation before releasing it, causing lock contention that scales with I/O latency rather than computation time.
- **Starter invariant**: "INV-CONC-002: No mutex in this feature may be held across any I/O operation; critical sections must contain only in-memory computation."
- **Test approach**: Code review for lock scope. Instrument mutex hold durations in benchmarks and assert they remain below a fixed threshold (e.g., 1ms p99) under concurrent load.

### 3. Documented channel producer/consumer/backpressure

- **Check**: Every channel has a documented producer, consumer, capacity rationale, and backpressure strategy (block, drop, or error).
- **Violated when**: A channel is created without clear ownership, leading to sends that block indefinitely because the consumer exited, or unbounded buffering that exhausts memory.
- **Starter invariant**: "INV-CONC-003: Each channel in this feature must document its producer, consumer, buffer capacity rationale, and behavior when the consumer falls behind."
- **Test approach**: Stall or slow the consumer and verify the producer either blocks within acceptable bounds, drops messages with a logged event, or returns an error — never panics or leaks memory.

### 4. Documented synchronization strategy for shared data

- **Check**: Every piece of shared mutable state has an explicit synchronization strategy (mutex, atomic, channel ownership, copy-on-read) documented where the state is declared.
- **Violated when**: A struct field or package-level variable is accessed from multiple goroutines without synchronization, or the synchronization approach is inconsistent (sometimes mutex, sometimes atomic) for the same data.
- **Starter invariant**: "INV-CONC-004: Every shared mutable field in this feature must have a comment naming its synchronization mechanism, and all accesses must use that mechanism exclusively."
- **Test approach**: Run the full test suite with `-race` enabled. Additionally, review that each shared field's doc comment names exactly one synchronization strategy and grep for accesses that bypass it.

### 5. Race detector passes under load

- **Check**: The feature's tests pass with Go's race detector enabled (`-race`) under concurrent load, not just sequential execution.
- **Violated when**: Tests pass without `-race` but data races surface when multiple goroutines exercise the feature simultaneously, indicating unsynchronized shared state that is invisible under low concurrency.
- **Starter invariant**: "INV-CONC-005: All tests for this feature must pass with -race enabled while exercising at least [N] concurrent callers for [duration]."
- **Test approach**: Run `go test -race -count=5` with test cases that spawn multiple goroutines hitting the feature concurrently. Integrate race detection into CI as a blocking check.
