# Property-Based Testing: TypeScript (fast-check)

## Quick Reference

### Import

Install the library:

```bash
npm install --save-dev fast-check
```

Import in test files:

```typescript
import fc from "fast-check";
```

### Basic Property Test

A fast-check property test uses `fc.assert` with `fc.property`. Wrap it in a test runner block (`test`, `it`, or `describe`) as usual.

```typescript
import fc from "fast-check";

test("reverse is an involution", () => {
  fc.assert(
    fc.property(fc.array(fc.integer()), (xs) => {
      const reversed = [...xs].reverse().reverse();
      expect(reversed).toEqual(xs);
    })
  );
});
```

`fc.assert` generates 100 random inputs by default, shrinks on failure, and throws an error with the minimal counterexample.

### Generators

fast-check calls generators "arbitraries." They are factory functions on the `fc` namespace.

**Primitive types:**

```typescript
fc.integer()                            // arbitrary integer (safe range)
fc.integer({ min: 0, max: 100 })        // integer in [0, 100]
fc.nat()                                // non-negative integer
fc.float()                              // 32-bit float
fc.double()                             // 64-bit double
fc.boolean()                            // true or false
fc.constant("fixed")                    // always "fixed"
```

**Strings and bytes:**

```typescript
fc.string()                             // arbitrary unicode string
fc.string({ minLength: 1, maxLength: 50 }) // bounded length
fc.stringOf(fc.char())                  // string of specific char arb
fc.hexaString()                         // hex characters only
fc.asciiString()                        // ASCII only
fc.stringMatching(/[a-z]{1,10}/)        // regex-constrained
fc.uint8Array()                         // Uint8Array (arbitrary bytes)
```

**Collections:**

```typescript
fc.array(fc.integer())                                  // number[]
fc.array(fc.integer(), { minLength: 1, maxLength: 50 }) // bounded, non-empty
fc.uniqueArray(fc.integer())                            // no duplicates
fc.set(fc.string())                                     // Set (via uniqueArray + map)
```

**Objects and records — `fc.record`:**

Use `fc.record` to generate objects matching a known shape.

```typescript
interface Interval {
  lo: number;
  hi: number;
}

const genInterval: fc.Arbitrary<Interval> = fc
  .record({
    lo: fc.integer({ min: -1000, max: 1000 }),
    hi: fc.integer({ min: -1000, max: 2000 }),
  })
  .filter((iv) => iv.lo <= iv.hi);
```

**Custom arbitraries — `fc.chain` (dependent generation):**

When one value depends on another, use `.chain`.

```typescript
const genInterval: fc.Arbitrary<Interval> = fc
  .integer({ min: -1000, max: 1000 })
  .chain((lo) =>
    fc.integer({ min: lo, max: lo + 1000 }).map((hi) => ({ lo, hi }))
  );
```

**Choosing from a fixed set:**

```typescript
fc.constantFrom("add", "remove", "update")
```

**Filtering (use sparingly — too many rejections slow the test):**

```typescript
fc.integer().filter((n) => n !== 0)
```

**Mapping (transform output):**

```typescript
fc.integer({ min: 1, max: 100 }).map((n) => n * 2) // even numbers
```

**Composing with `fc.tuple`:**

```typescript
fc.tuple(fc.string(), fc.integer())  // [string, number]
```

### Expressing Invariants as Properties

Map each spec rule to one or more properties. Common patterns:

**Roundtrip / inverse:** If `f` and `g` are inverses, then `g(f(x)) === x` for all valid `x`.

```typescript
fc.assert(
  fc.property(genMyType(), (original) => {
    const encoded = encode(original);
    const decoded = decode(encoded);
    expect(decoded).toEqual(original);
  })
);
```

**Idempotence:** Applying `f` twice yields the same result as applying it once.

```typescript
fc.assert(
  fc.property(fc.string(), (input) => {
    const once = normalize(input);
    const twice = normalize(once);
    expect(twice).toEqual(once);
  })
);
```

**Invariant preservation:** After any operation, a structural invariant still holds.

```typescript
fc.assert(
  fc.property(fc.array(fc.integer(), { maxLength: 100 }), (items) => {
    const heap = new MinHeap(items);
    expect(heap.isValid()).toBe(true);
  })
);
```

**Oracle / model comparison:** Compare the system under test against a simpler, known-correct model.

```typescript
fc.assert(
  fc.property(
    fc.array(fc.tuple(fc.string(), fc.integer()), { minLength: 1 }),
    (entries) => {
      const cache = new MyCache();
      const model = new Map<string, number>();
      for (const [key, value] of entries) {
        cache.set(key, value);
        model.set(key, value);
      }
      for (const [key, expected] of model) {
        expect(cache.get(key)).toBe(expected);
      }
    }
  )
);
```

**Return-based assertions (alternative to expect):**

fast-check also accepts boolean-returning properties. Return `false` to signal failure.

```typescript
fc.assert(
  fc.property(fc.integer(), fc.integer(), (a, b) => {
    return myAdd(a, b) === myAdd(b, a); // commutativity
  })
);
```

### Integration

fast-check works with any test runner. The two most common setups:

**Jest:**

```typescript
// jest.config.ts — no special config needed
// Just import fc and use fc.assert inside test() blocks.
test("my property", () => {
  fc.assert(fc.property(fc.integer(), (n) => { ... }));
});
```

**Vitest:**

```typescript
// vitest.config.ts — no special config needed
import { test, expect } from "vitest";
import fc from "fast-check";

test("my property", () => {
  fc.assert(fc.property(fc.integer(), (n) => { ... }));
});
```

**Running tests:**

```bash
npx jest                                # Jest
npx vitest                              # Vitest
npx vitest run                          # Vitest single run (CI)
npx jest --testPathPattern=props        # run only property test files
```

**Controlling example count:**

```typescript
fc.assert(
  fc.property(fc.integer(), (n) => { ... }),
  { numRuns: 500 }
);
```

**Seed reproduction:** When a property fails, fast-check prints a seed and path. Reproduce it:

```typescript
fc.assert(
  fc.property(fc.integer(), (n) => { ... }),
  { seed: 12345, path: "0:1:2" }
);
```

**Verbose output on failure:**

```typescript
fc.assert(
  fc.property(fc.integer(), (n) => { ... }),
  { verbose: fc.VerbosityLevel.VeryVerbose }
);
```

## Example: Roundtrip Property

A complete, copy-pasteable example testing JSON serialization roundtrip for a domain type.

```typescript
import fc from "fast-check";

interface User {
  name: string;
  age: number;
  email: string;
}

const genUser: fc.Arbitrary<User> = fc.record({
  name: fc.stringOf(fc.char(), { minLength: 1, maxLength: 50 }),
  age: fc.integer({ min: 0, max: 150 }),
  email: fc.stringMatching(/[a-z]{3,10}@[a-z]{3,8}\.(com|org|net)/),
});

function serialize(user: User): string {
  return JSON.stringify(user);
}

function deserialize(json: string): User {
  return JSON.parse(json) as User;
}

// Tests R-xxx: User JSON serialization is lossless.
test("User JSON roundtrip", () => {
  fc.assert(
    fc.property(genUser, (original) => {
      const json = serialize(original);
      const decoded = deserialize(json);
      expect(decoded).toEqual(original);
    }),
    { numRuns: 200 }
  );
});
```
