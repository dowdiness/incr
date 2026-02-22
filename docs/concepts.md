# Core Concepts

This document explains the key concepts behind `incr` without diving into implementation details. For the technical deep-dive, see [design.md](design.md).

## The Dependency Graph

`incr` models your computations as a directed graph:

```
[Signal: price] ──┐
                  ├──► [Memo: subtotal] ──► [Memo: total]
[Signal: qty]   ──┘                              ▲
                                                 │
[Signal: tax_rate] ──► [Memo: tax] ─────────────┘
```

- **Signals** are the leaves (inputs you control)
- **Memos** are the interior nodes (derived values)
- **Arrows** represent dependencies (automatically tracked)

## Signals

Signals hold input values that you set directly:

```moonbit
let count = Signal(rt, 0)

// Read the value
let current = count.get()  // 0

// Update the value
count.set(5)
```

### Same-Value Optimization

Setting a signal to its current value is a no-op — no revision bump, no recomputation:

```moonbit
count.set(5)  // Bumps revision
count.set(5)  // No-op, value unchanged
```

To force an update even with the same value:

```moonbit
count.set_unconditional(5)  // Always bumps revision
```

## Memos

Memos compute derived values and cache the result:

```moonbit
let doubled = Memo(rt, fn() { count.get() * 2 })
```

Key properties:

1. **Lazy** — Only computed when first read
2. **Cached** — Same value returned until dependencies change
3. **Auto-tracking** — Dependencies discovered by intercepting `get()` calls

### Dependency Tracking

You don't declare dependencies. `incr` discovers them:

```moonbit
let mode = Signal(rt, "add")
let x = Signal(rt, 10)
let y = Signal(rt, 20)

let result = Memo(rt, fn() {
  if mode.get() == "add" {
    x.get() + y.get()
  } else {
    x.get() * y.get()
  }
})
```

Dependencies can change between recomputations. If `mode = "add"`, `result` depends on `mode`, `x`, and `y`. If you change `mode` to `"multiply"`, the dependency set may differ on the next computation.

## Revisions

A **Revision** is a global counter that increments when any signal changes:

| Event | Global Revision |
|-------|-----------------|
| Initial state | R0 |
| `price.set(200)` | R1 |
| `qty.set(3)` | R2 |
| `qty.set(3)` (same value) | R2 (unchanged) |

Every cell tracks two timestamps:

- **`changed_at`** — When the cell's value last actually changed
- **`verified_at`** — When the cell was last confirmed up-to-date

A memo is stale when `verified_at < current_revision`.

## Backdating

**Backdating** is the key optimization. When a memo recomputes to the **same value** as before, its `changed_at` stays at the old revision:

```moonbit
let input = Signal(rt, 4)
let is_even = Memo(rt, fn() { input.get() % 2 == 0 })
let label = Memo(rt, fn() { if is_even.get() { "even" } else { "odd" } })

inspect(label.get(), content="even")

// Change 4 → 6 (both even)
input.set(6)

// is_even recomputes: true → true (same!)
// Backdating: is_even.changed_at stays at R0
// label sees no change, skips recomputation
inspect(label.get(), content="even")  // Did NOT recompute
```

This prevents unnecessary cascading through the graph.

## Durability

**Durability** classifies inputs by change frequency:

| Level | Use Case |
|-------|----------|
| `Low` | Frequently changing (user input, source text) |
| `Medium` | Moderately stable |
| `High` | Rarely changing (configuration, schemas) |

```moonbit
let config = Signal(rt, 100, durability=High)
let input = Signal(rt, 1)  // Default: Low
```

### Durability Shortcut

When only low-durability inputs change, memos that depend solely on high-durability inputs skip verification entirely:

```moonbit
let config = Signal(rt, "production", durability=High)
let user_input = Signal(rt, "hello")  // Low durability

let config_hash = Memo(rt, fn() { hash(config.get()) })
let processed = Memo(rt, fn() { process(user_input.get()) })

// Only user_input changed
user_input.set("world")

// config_hash.get() → skips verification (durability shortcut)
// processed.get() → verifies and recomputes
```

### Inherited Durability

Memos inherit the **minimum** durability of their dependencies:

```moonbit
let high = Signal(rt, 1, durability=High)
let low = Signal(rt, 2)  // Low durability

let mixed = Memo(rt, fn() { high.get() + low.get() })
// mixed inherits Low durability (can't use the shortcut)
```

## Batch Updates

Update multiple signals atomically:

```moonbit
rt.batch(fn() {
  x.set(10)
  y.set(20)
  z.set(30)
})
// Single revision bump for all three changes
```

Benefits:
- Avoids intermediate recomputations
- Enables **revert detection**: if you set and then reset a value within a batch, no change is recorded

```moonbit
rt.batch(fn() {
  counter.set(5)   // temporary
  counter.set(0)   // back to original
})
// No revision bump — net change is zero
```

## Cycle Detection

Cyclic dependencies are detected at runtime:

```moonbit
let a = Memo(rt, fn() { b.get() + 1 })
let b = Memo(rt, fn() { a.get() + 1 })

a.get()  // Aborts: "Cycle detected"
```

### Graceful Cycle Handling

Use `get_result()` to handle cycles without aborting:

```moonbit
let memo = Memo(rt, fn() {
  match self_ref.get_result() {
    Ok(v) => v + 1
    Err(CycleDetected(_, _)) => -1  // Fallback value
  }
})

match memo.get_result() {
  Ok(value) => println(value.to_string())  // Prints "-1"
  Err(_) => ()  // Only if error wasn't handled inside
}
```

When a cycle is detected via `get_result()`:
- The error can be caught and handled in the compute function
- No dependency is recorded for failed reads (prevents spurious future cycles)
- The runtime remains in a consistent state for subsequent operations

## Field-Level Tracking

When a struct has several logically related fields, you often want memos that depend on only one field to skip recomputation when a different field changes. `Signal[MyStruct]` cannot do this — updating any field forces every downstream memo to reverify.

**`TrackedCell[T]`** solves this by giving each field its own independent cell:

```moonbit
struct SourceFile {
  path    : TrackedCell[String]
  content : TrackedCell[String]
  version : TrackedCell[Int]
}
```

Each `TrackedCell` is an input cell identical to `Signal[T]` in every way — same-value optimization, durability levels, change hooks — but it belongs to a named field.

### Trackable Trait

Implement the `Trackable` trait to declare which cells a struct owns:

```moonbit
impl Trackable for SourceFile with cell_ids(self) {
  [self.path.id(), self.content.id(), self.version.id()]
}
```

This enables bulk operations on all cells in the struct (e.g., introspection, future GC).

### Field-Level Dependency Isolation

Memos that read individual `TrackedCell` fields only depend on those fields, not on the whole struct:

```moonbit
let word_count = Memo(rt, fn() {
  file.content.get().split(" ").fold(init=0, fn(acc, _s) { acc + 1 })
})

let is_test = Memo(rt, fn() {
  file.path.get().ends_with("_test.mbt")
})

// Change version — neither memo recomputes
file.version.set(1)

// Change content — only word_count recomputes; is_test is untouched
file.content.set("fn main { let x = 42 }")
```

### When to Use TrackedCell vs Signal

| Situation | Recommendation |
|-----------|----------------|
| Single scalar value | `Signal[T]` |
| Multiple related fields with independent consumers | `TrackedCell[T]` in a tracked struct |
| Monolithic struct updated atomically | `Signal[MyStruct]` with batch |

## Summary

| Concept | Purpose |
|---------|---------|
| Signal | Input values you control |
| Memo | Derived values with automatic caching |
| Revision | Global clock for tracking changes |
| Backdating | Skip downstream work when values don't actually change |
| Durability | Skip verification for stable subgraphs |
| Batch | Atomic multi-signal updates |
| TrackedCell | Field-level input cells for fine-grained dependency isolation |

## Further Reading

- [API Reference](./api-reference.md) — Complete method reference
- [Cookbook](./cookbook.md) — Common patterns (including the Tracked Struct recipe)
- [design.md](design.md) — Implementation details
