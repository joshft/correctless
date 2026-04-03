# Property-Based Testing: Python (hypothesis)

## Quick Reference

### Import

Install the library:

```bash
pip install hypothesis
```

Import in test files:

```python
from hypothesis import given, settings, assume, example
from hypothesis import strategies as st
```

### Basic Property Test

A hypothesis property test is a regular function decorated with `@given`. Hypothesis generates random inputs, calls the function many times, and shrinks on failure.

```python
from hypothesis import given
from hypothesis import strategies as st


@given(xs=st.lists(st.integers()))
def test_reverse_involution(xs):
    assert list(reversed(list(reversed(xs)))) == xs
```

The test runs with `pytest` like any other test. Hypothesis produces 100 examples by default.

### Generators

Hypothesis calls generators "strategies." They live in the `hypothesis.strategies` module (conventionally imported as `st`).

**Primitive types:**

```python
st.integers()                          # arbitrary int (unbounded)
st.integers(min_value=0, max_value=100) # int in [0, 100]
st.floats()                            # float (includes NaN, inf by default)
st.floats(allow_nan=False, allow_infinity=False)  # finite floats only
st.booleans()                          # True or False
st.none()                              # always None
```

**Strings and bytes:**

```python
st.text()                              # arbitrary unicode text
st.text(min_size=1, max_size=50)       # bounded length
st.text(alphabet=st.characters(whitelist_categories=("L",)))  # letters only
st.from_regex(r"[a-z]{1,10}", fullmatch=True)  # regex-constrained
st.binary()                            # arbitrary bytes
st.binary(min_size=1, max_size=256)    # bounded bytes
```

**Collections:**

```python
st.lists(st.integers())                            # list[int]
st.lists(st.integers(), min_size=1, max_size=50)   # bounded length, non-empty
st.sets(st.text())                                  # set[str]
st.dictionaries(st.text(), st.integers())           # dict[str, int]
st.tuples(st.integers(), st.text())                 # tuple[int, str]
st.frozensets(st.integers())                        # frozenset[int]
```

**Custom types — `st.builds`:**

Use `st.builds` to construct instances of your own classes from strategies.

```python
from dataclasses import dataclass

@dataclass
class Interval:
    lo: int
    hi: int

def gen_interval():
    return st.builds(
        Interval,
        lo=st.integers(min_value=-1000, max_value=1000),
        hi=st.integers(min_value=-1000, max_value=2000),
    ).filter(lambda iv: iv.lo <= iv.hi)
```

**Alternative: `@st.composite` for complex generators:**

When the generator needs sequential draws (one value depends on a prior draw), use `@st.composite`.

```python
@st.composite
def gen_interval(draw):
    lo = draw(st.integers(min_value=-1000, max_value=1000))
    hi = draw(st.integers(min_value=lo, max_value=lo + 1000))
    return Interval(lo=lo, hi=hi)

# Usage:
@given(iv=gen_interval())
def test_interval_valid(iv):
    assert iv.lo <= iv.hi
```

**Choosing from a fixed set:**

```python
st.sampled_from(["add", "remove", "update"])
```

**Filtering (use sparingly — too many rejections cause HealthCheck failures):**

```python
st.integers().filter(lambda n: n != 0)
# Or inside the test:
assume(n != 0)
```

**Mapping (transform a strategy's output):**

```python
st.integers(min_value=1, max_value=100).map(lambda n: n * 2)  # even numbers
```

### Expressing Invariants as Properties

Map each spec rule to one or more properties. Common patterns:

**Roundtrip / inverse:** If `f` and `g` are inverses, then `g(f(x)) == x` for all valid `x`.

```python
@given(original=gen_my_type())
def test_roundtrip(original):
    encoded = encode(original)
    decoded = decode(encoded)
    assert decoded == original
```

**Idempotence:** Applying `f` twice yields the same result as applying it once.

```python
@given(text=st.text())
def test_normalize_idempotent(text):
    once = normalize(text)
    twice = normalize(once)
    assert once == twice
```

**Invariant preservation:** After any operation, a structural invariant still holds.

```python
@given(items=st.lists(st.integers(), max_size=100))
def test_heap_invariant(items):
    h = MinHeap(items)
    assert h.is_valid()
```

**Oracle / model comparison:** Compare the system under test against a simpler, known-correct model.

```python
@given(data=st.data())
def test_cache_matches_dict(data):
    cache = MyCache()
    model = {}
    for _ in range(data.draw(st.integers(min_value=1, max_value=20))):
        key = data.draw(st.text(min_size=1, max_size=10))
        value = data.draw(st.integers())
        cache.set(key, value)
        model[key] = value
    for key in model:
        assert cache.get(key) == model[key]
```

**Commutative / associative / algebraic laws:**

```python
@given(a=st.integers(), b=st.integers())
def test_addition_commutative(a, b):
    assert my_add(a, b) == my_add(b, a)
```

### Integration

Hypothesis tests are standard pytest tests. No special runner or plugin is required.

```bash
pytest                                     # run all tests including hypothesis properties
pytest tests/test_props.py                 # run a specific file
pytest -k test_roundtrip                   # run a specific property
pytest -v                                  # verbose output
```

**Controlling example count with `@settings`:**

```python
from hypothesis import settings

@settings(max_examples=500)
@given(xs=st.lists(st.integers()))
def test_with_more_examples(xs):
    assert sorted(sorted(xs)) == sorted(xs)
```

**Deadline control (disable for slow system-under-test):**

```python
@settings(deadline=None)
@given(data=gen_my_type())
def test_slow_property(data):
    ...
```

**Seed reproduction:** When a property fails, hypothesis saves the failing example in a database (`.hypothesis/` directory). Re-running the test replays it automatically. You can also pin examples:

```python
@example(xs=[3, 1, 2])  # always tested, in addition to random examples
@given(xs=st.lists(st.integers()))
def test_sort_stability(xs):
    ...
```

**Profiles for CI vs local:**

```python
# conftest.py
from hypothesis import settings, Phase

settings.register_profile("ci", max_examples=1000)
settings.register_profile("dev", max_examples=50)
settings.load_profile(os.getenv("HYPOTHESIS_PROFILE", "dev"))
```

```bash
HYPOTHESIS_PROFILE=ci pytest
```

## Example: Roundtrip Property

A complete, copy-pasteable example testing JSON serialization roundtrip for a domain type.

```python
import json
from dataclasses import dataclass, asdict

from hypothesis import given, settings
from hypothesis import strategies as st


@dataclass
class User:
    name: str
    age: int
    email: str


def gen_user():
    return st.builds(
        User,
        name=st.text(
            alphabet=st.characters(whitelist_categories=("L",)),
            min_size=1,
            max_size=50,
        ),
        age=st.integers(min_value=0, max_value=150),
        email=st.from_regex(r"[a-z]{3,10}@[a-z]{3,8}\.(com|org|net)", fullmatch=True),
    )


# Tests R-xxx: User JSON serialization is lossless.
@settings(max_examples=200)
@given(original=gen_user())
def test_user_json_roundtrip(original):
    data = json.dumps(asdict(original))
    raw = json.loads(data)
    decoded = User(**raw)
    assert decoded == original
```
