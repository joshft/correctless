# Property-Based Testing: Go (pgregory.net/rapid)

## Quick Reference

### Import

Add the dependency:

```bash
go get pgregory.net/rapid
```

Import in test files:

```go
import (
    "testing"
    "pgregory.net/rapid"
)
```

### Basic Property Test

A rapid property test is a standard Go test that calls `rapid.Check` inside it. Each property receives a `*rapid.T` that serves as both a test handle and the source of generated values.

```go
func TestReverse_Involution(t *testing.T) {
    rapid.Check(t, func(t *rapid.T) {
        xs := rapid.SliceOf(rapid.Int()).Draw(t, "xs")
        reversed := reverse(reverse(xs))
        if !slices.Equal(xs, reversed) {
            t.Fatalf("double reverse changed the slice: got %v, want %v", reversed, xs)
        }
    })
}
```

`rapid.Check` generates many random inputs, shrinks on failure, and reports the minimal failing case through the standard `testing.T`.

### Generators

Generators are called "machines" in rapid. You draw values from them inside the property function.

**Primitive types:**

```go
n := rapid.Int().Draw(t, "n")                          // int
n := rapid.IntRange(0, 100).Draw(t, "n")               // int in [0, 100]
n := rapid.Int32().Draw(t, "n")                         // int32
f := rapid.Float64().Draw(t, "f")                       // float64
b := rapid.Bool().Draw(t, "b")                          // bool
```

**Strings and bytes:**

```go
s := rapid.String().Draw(t, "s")                        // arbitrary string
s := rapid.StringOf(rapid.RuneFrom(nil, unicode.Letter)).Draw(t, "s") // letters only
s := rapid.StringMatching(`[a-z]{1,10}`).Draw(t, "s")  // regex-constrained
bs := rapid.SliceOf(rapid.Byte()).Draw(t, "bs")         // []byte
```

**Collections:**

```go
xs := rapid.SliceOf(rapid.Int()).Draw(t, "xs")                      // []int
xs := rapid.SliceOfN(rapid.Int(), 1, 50).Draw(t, "xs")             // []int, len in [1, 50]
m := rapid.MapOf(rapid.String(), rapid.Int()).Draw(t, "m")          // map[string]int
```

**Custom generators — `rapid.Custom`:**

Use `rapid.Custom` to compose generators for domain types.

```go
type Interval struct {
    Lo, Hi int
}

func genInterval() *rapid.Generator[Interval] {
    return rapid.Custom(func(t *rapid.T) Interval {
        lo := rapid.IntRange(-1000, 1000).Draw(t, "lo")
        hi := rapid.IntRange(lo, lo+1000).Draw(t, "hi")
        return Interval{Lo: lo, Hi: hi}
    })
}

// Usage inside a property:
iv := genInterval().Draw(t, "interval")
```

**Choosing from a fixed set:**

```go
op := rapid.SampledFrom([]string{"add", "remove", "update"}).Draw(t, "op")
```

**Filtering (use sparingly — too many rejections slow the test):**

```go
nonZero := rapid.Int().Filter(func(n int) bool { return n != 0 })
n := nonZero.Draw(t, "n")
```

### Expressing Invariants as Properties

Map each spec rule to one or more properties. Common patterns:

**Roundtrip / inverse:** If `f` and `g` are inverses, then `g(f(x)) == x` for all valid `x`.

```go
rapid.Check(t, func(t *rapid.T) {
    original := genMyType().Draw(t, "original")
    encoded := encode(original)
    decoded, err := decode(encoded)
    if err != nil {
        t.Fatalf("decode failed: %v", err)
    }
    if !reflect.DeepEqual(original, decoded) {
        t.Fatalf("roundtrip failed: %v != %v", original, decoded)
    }
})
```

**Idempotence:** Applying `f` twice yields the same result as applying it once.

```go
rapid.Check(t, func(t *rapid.T) {
    input := rapid.String().Draw(t, "input")
    once := normalize(input)
    twice := normalize(once)
    if once != twice {
        t.Fatalf("normalize is not idempotent: %q -> %q -> %q", input, once, twice)
    }
})
```

**Invariant preservation:** After any operation, a structural invariant still holds.

```go
rapid.Check(t, func(t *rapid.T) {
    items := rapid.SliceOfN(rapid.Int(), 0, 100).Draw(t, "items")
    h := NewMinHeap(items)
    if !h.IsValid() {
        t.Fatalf("heap invariant violated after construction with %v", items)
    }
})
```

**Oracle / model comparison:** Compare the system under test against a simpler, known-correct model.

```go
rapid.Check(t, func(t *rapid.T) {
    key := rapid.String().Draw(t, "key")
    value := rapid.Int().Draw(t, "value")
    cache.Set(key, value)
    model[key] = value
    got, _ := cache.Get(key)
    if got != model[key] {
        t.Fatalf("cache disagrees with model for key %q: got %d, want %d", key, got, model[key])
    }
})
```

### Integration

rapid tests are standard Go tests. They run with `go test` and require no special flags.

```bash
go test ./...                        # run all tests including rapid properties
go test -run TestReverse_Involution  # run a specific property
go test -v ./...                     # verbose output shows drawn values on failure
```

**Seed reproduction:** When a property fails, rapid prints a seed. Reproduce it:

```bash
go test -run TestReverse_Involution -rapid.seed=<seed>
```

**Increasing iterations:** By default rapid runs 100 iterations. Override per-test:

```go
rapid.Check(t, func(t *rapid.T) {
    // property body
}, rapid.WithChecks(1000))
```

Or set globally via the `-rapid.checks` flag:

```bash
go test -rapid.checks=500 ./...
```

## Example: Roundtrip Property

A complete, copy-pasteable example testing JSON serialization roundtrip for a domain type.

```go
package user_test

import (
    "encoding/json"
    "reflect"
    "testing"
    "unicode"

    "pgregory.net/rapid"
)

type User struct {
    Name  string `json:"name"`
    Age   int    `json:"age"`
    Email string `json:"email"`
}

func genUser() *rapid.Generator[User] {
    return rapid.Custom(func(t *rapid.T) User {
        return User{
            Name:  rapid.StringOfN(rapid.RuneFrom(nil, unicode.Letter), 1, 50).Draw(t, "name"),
            Age:   rapid.IntRange(0, 150).Draw(t, "age"),
            Email: rapid.StringMatching(`[a-z]{3,10}@[a-z]{3,8}\.(com|org|net)`).Draw(t, "email"),
        }
    })
}

// Tests R-xxx: User JSON serialization is lossless.
func TestUser_JSON_Roundtrip(t *testing.T) {
    rapid.Check(t, func(t *rapid.T) {
        original := genUser().Draw(t, "user")

        data, err := json.Marshal(original)
        if err != nil {
            t.Fatalf("marshal failed: %v", err)
        }

        var decoded User
        if err := json.Unmarshal(data, &decoded); err != nil {
            t.Fatalf("unmarshal failed: %v", err)
        }

        if !reflect.DeepEqual(original, decoded) {
            t.Fatalf("roundtrip mismatch:\n  original: %+v\n  decoded:  %+v", original, decoded)
        }
    })
}
```
