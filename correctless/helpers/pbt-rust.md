# Property-Based Testing: Rust (proptest)

## Quick Reference

### Import

Add the dependency to `Cargo.toml`:

```toml
[dev-dependencies]
proptest = "1"
```

Import in test modules:

```rust
use proptest::prelude::*;
```

The prelude re-exports `proptest!`, `prop_assert!`, `prop_assert_eq!`, `any`, `Strategy`, and the common strategy combinators.

### Basic Property Test

The `proptest!` macro defines property tests inside a standard `#[cfg(test)]` module. Each test declares its generated inputs with `in` syntax.

```rust
use proptest::prelude::*;

proptest! {
    #[test]
    fn reverse_involution(xs in prop::collection::vec(any::<i32>(), 0..100)) {
        let mut reversed = xs.clone();
        reversed.reverse();
        reversed.reverse();
        prop_assert_eq!(xs, reversed);
    }
}
```

proptest generates 256 cases by default, shrinks on failure, and stores the minimal failing case in a `proptest-regressions/` file for replay.

### Generators

proptest calls generators "strategies." Strategies implement the `Strategy` trait and are composed with combinators.

**Primitive types — `any::<T>()`:**

```rust
any::<i32>()                            // arbitrary i32
any::<u64>()                            // arbitrary u64
any::<f64>()                            // arbitrary f64 (includes NaN, inf)
any::<bool>()                           // true or false
any::<char>()                           // arbitrary char
0..100i32                               // i32 in [0, 100) — ranges are strategies
-1000..=1000i64                         // i64 in [-1000, 1000] inclusive
```

**Strings:**

```rust
any::<String>()                                         // arbitrary String
"[a-z]{1,10}"                                           // regex-constrained (string literals are strategies)
prop::string::string_regex("[a-z]+@[a-z]+\\.com").unwrap()  // dynamic regex
```

**Collections:**

```rust
prop::collection::vec(any::<i32>(), 0..50)              // Vec<i32>, len in [0, 50)
prop::collection::vec(any::<i32>(), 1..=20)             // non-empty, len in [1, 20]
prop::collection::hash_set(any::<String>(), 0..10)      // HashSet<String>
prop::collection::hash_map(any::<String>(), any::<i32>(), 0..10)  // HashMap
prop::collection::btree_map(0..100i32, any::<String>(), 0..10)    // BTreeMap
```

**Options and results:**

```rust
prop::option::of(any::<i32>())                          // Option<i32>
prop::result::maybe_ok(any::<i32>(), any::<String>())   // Result<i32, String>
```

**Tuples (auto-derived for tuples up to 12 elements):**

```rust
(any::<i32>(), any::<String>())                         // (i32, String)
```

**Custom strategies — `prop_compose!`:**

Use `prop_compose!` to build strategies for domain types by composing simpler strategies.

```rust
#[derive(Debug, Clone, PartialEq)]
struct Interval {
    lo: i32,
    hi: i32,
}

prop_compose! {
    fn gen_interval()(lo in -1000..1000i32)(hi in lo..=(lo + 1000), lo in Just(lo)) -> Interval {
        Interval { lo, hi }
    }
}

// Usage inside proptest!:
proptest! {
    #[test]
    fn interval_is_valid(iv in gen_interval()) {
        prop_assert!(iv.lo <= iv.hi);
    }
}
```

Note the two-stage closure in `prop_compose!`: the first stage generates `lo`, the second stage uses `lo` to constrain `hi`. Use `Just(lo)` to carry `lo` into the second stage.

**Alternative: manual `Strategy` impl with `prop_flat_map`:**

```rust
fn gen_interval() -> impl Strategy<Value = Interval> {
    (-1000..1000i32).prop_flat_map(|lo| {
        (lo..=(lo + 1000)).prop_map(move |hi| Interval { lo, hi })
    })
}
```

**Choosing from a fixed set:**

```rust
prop_oneof![
    Just("add".to_string()),
    Just("remove".to_string()),
    Just("update".to_string()),
]
```

Or for simple enums:

```rust
prop::sample::select(vec!["add", "remove", "update"])
```

**Filtering (use sparingly — too many rejections cause proptest to give up):**

```rust
any::<i32>().prop_filter("non-zero", |n| *n != 0)
```

**Mapping:**

```rust
(1..100i32).prop_map(|n| n * 2)  // even numbers
```

### Expressing Invariants as Properties

Map each spec rule to one or more properties. Common patterns:

**Roundtrip / inverse:** If `f` and `g` are inverses, then `g(f(x)) == x` for all valid `x`.

```rust
proptest! {
    #[test]
    fn roundtrip(original in gen_my_type()) {
        let encoded = encode(&original);
        let decoded = decode(&encoded).unwrap();
        prop_assert_eq!(original, decoded);
    }
}
```

**Idempotence:** Applying `f` twice yields the same result as applying it once.

```rust
proptest! {
    #[test]
    fn normalize_idempotent(input in any::<String>()) {
        let once = normalize(&input);
        let twice = normalize(&once);
        prop_assert_eq!(once, twice);
    }
}
```

**Invariant preservation:** After any operation, a structural invariant still holds.

```rust
proptest! {
    #[test]
    fn heap_invariant(items in prop::collection::vec(any::<i32>(), 0..100)) {
        let heap = MinHeap::from(items);
        prop_assert!(heap.is_valid());
    }
}
```

**Oracle / model comparison:** Compare the system under test against a simpler, known-correct model.

```rust
use std::collections::HashMap;

proptest! {
    #[test]
    fn cache_matches_hashmap(
        entries in prop::collection::vec((any::<String>(), any::<i32>()), 1..20)
    ) {
        let mut cache = MyCache::new();
        let mut model = HashMap::new();
        for (key, value) in &entries {
            cache.set(key.clone(), *value);
            model.insert(key.clone(), *value);
        }
        for (key, expected) in &model {
            prop_assert_eq!(cache.get(key), Some(expected));
        }
    }
}
```

### Integration

proptest tests are standard Rust tests inside `#[cfg(test)]` modules. They run with `cargo test`.

```bash
cargo test                              # run all tests including proptest properties
cargo test reverse_involution           # run a specific property
cargo test -- --nocapture               # see stdout on failure
```

**Controlling example count with `ProptestConfig`:**

```rust
proptest! {
    #![proptest_config(ProptestConfig::with_cases(1000))]

    #[test]
    fn my_property(x in any::<i32>()) {
        // runs 1000 cases instead of the default 256
        prop_assert!(my_check(x));
    }
}
```

You can also set config per-test:

```rust
proptest! {
    #![proptest_config(ProptestConfig {
        cases: 500,
        max_shrink_iters: 10000,
        ..ProptestConfig::default()
    })]

    #[test]
    fn my_property(x in any::<i32>()) {
        prop_assert!(my_check(x));
    }
}
```

**Seed reproduction:** When a property fails, proptest writes the minimal failing case to a `proptest-regressions/<module>.txt` file. The next test run automatically replays it. Commit these files to your repository so CI catches regressions.

**Disabling persistence (e.g., in ephemeral CI):**

```rust
ProptestConfig {
    failure_persistence: None,
    ..ProptestConfig::default()
}
```

## Example: Roundtrip Property

A complete, copy-pasteable example testing JSON serialization roundtrip for a domain type.

```rust
#[cfg(test)]
mod tests {
    use proptest::prelude::*;
    use serde::{Deserialize, Serialize};

    #[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
    struct User {
        name: String,
        age: u32,
        email: String,
    }

    prop_compose! {
        fn gen_user()(
            name in "[A-Za-z]{1,50}",
            age in 0..=150u32,
            email in "[a-z]{3,10}@[a-z]{3,8}\\.(com|org|net)",
        ) -> User {
            User { name, age, email }
        }
    }

    proptest! {
        #![proptest_config(ProptestConfig::with_cases(200))]

        /// Tests R-xxx: User JSON serialization is lossless.
        #[test]
        fn user_json_roundtrip(original in gen_user()) {
            let json = serde_json::to_string(&original).unwrap();
            let decoded: User = serde_json::from_str(&json).unwrap();
            prop_assert_eq!(original, decoded);
        }
    }
}
```
