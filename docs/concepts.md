# Core Concepts

This document explains the key concepts behind `incr` without diving into implementation details. For the technical deep-dive, see [design/internals.md](design/internals.md).

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

Naming note: this document uses the current public names. The accepted ideal
API vocabulary is recorded in [ADR 2026-05-21](decisions/2026-05-21-public-api-ideal-naming.md):
`Signal -> Input`, `Memo -> Derived`, `HybridMemo -> ReachableDerived`,
`Reactive -> EagerDerived`, `MemoMap -> DerivedMap`, `TrackedCell ->
InputField`, and `Database -> RuntimeContext`.

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

## Labels

Every `Signal`, `Memo`, and `TrackedCell` accepts an optional `label` parameter:

```moonbit
let price = Signal(rt, 100, label="price")
let total = Memo(rt, () => price.get() * qty.get(), label="total")
```

Labels have **no runtime cost** — they are stored as `String?` on the cell metadata and never read during normal computation. They only appear in:

- **Cycle error messages**: `"price → subtotal → total → price"` instead of `"Cell 2 → Cell 5 → Cell 8 → Cell 2"`
- **Debug output**: `Signal::debug()` and `Memo::debug()` include the label when set

**Best practice: always set a label.** Debugging a cycle or reading `format_path` output is significantly easier with names attached.

## Memos

Memos compute derived values and cache the result:

```moonbit
let doubled = Memo(rt, () => count.get() * 2)
```

Key properties:

1. **Lazy** — Only computed when first read
2. **Cached** — Same value returned until dependencies change
3. **Auto-tracking** — Dependencies discovered by intercepting `get()` calls

### Reading from inside vs outside a derived value

Target facade reads separate strict graph reads from permissive outside reads:
`Derived::get()` is only legal **inside** another derived compute function,
where it records the dependency for auto-tracking. From outside the graph —
top-level code, tests, event handlers, callbacks — use `read()` or
`read_or_abort()`. The same shape applies for `ReachableDerived` and keyed
`DerivedMap` reads.

```moonbit
let doubled = Derived(rt, () => count.get() * 2)

// Inside another derived value: use get() / get_or_abort() to record the dependency.
let plus_one = Derived(rt, () => doubled.get_or_abort() + 1)

// Outside any derived value: use read() / read_or_abort().
let value = doubled.read_or_abort()
```

### Dependency Tracking

You don't declare dependencies. `incr` discovers them:

```moonbit
let mode = Signal(rt, "add")
let x = Signal(rt, 10)
let y = Signal(rt, 20)

let result = Memo(rt, () => {
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
let input = Input(rt, 4)
let is_even = Derived(rt, () => input.get() % 2 == 0)
let label = Derived(rt, () => if is_even.get_or_abort() { "even" } else { "odd" })

inspect(label.read_or_abort(), content="even")

// Change 4 → 6 (both even)
input.set(6)

// is_even recomputes: true → true (same!)
// Backdating: is_even.changed_at stays at R0
// label sees no change, skips recomputation
inspect(label.read_or_abort(), content="even")  // Did NOT recompute
```

This prevents unnecessary cascading through the graph.

### Backdating strategies

Three memo constructors offer different backdate strategies:

- **`Memo::new[T : Eq]`** — uses `a == b`. Standard choice for most types.
- **`Memo::new_memo[T : BackdateEq]`** — uses `a.backdate_equal(b)`. By default compares `changed_at` revisions (O(1)). Useful when structural equality is expensive and you can embed a revision in the value instead.
- **`Memo::new_no_backdate[T]`** — never backdates. Use when downstream consumers always need to rerun, or when `T` has no `Eq` instance.

The `create_memo` helper always uses `Memo::new`. For the other strategies, call the constructors directly.

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

let config_hash = Memo(rt, () => hash(config.get()))
let processed = Memo(rt, () => process(user_input.get()))

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

let mixed = Memo(rt, () => high.get() + low.get())
// mixed inherits Low durability (can't use the shortcut)
```

## Batch Updates

Update multiple signals atomically:

```moonbit
rt.batch(() => {
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
rt.batch(() => {
  counter.set(5)   // temporary
  counter.set(0)   // back to original
})
// No revision bump — net change is zero
```

## Cycle Detection

Cyclic dependencies are detected at runtime:

```moonbit
let a = Derived(rt, () => b.get_or_abort() + 1)
let b = Derived(rt, () => a.get_or_abort() + 1)

a.read_or_abort()  // Aborts: "Cycle detected"
```

### Graceful Cycle Handling

Use `get()` inside a tracked compute or `read()` outside the graph to handle cycles without aborting:

```moonbit
let memo = Derived(rt, () => {
  match self_ref.get() {
    Ok(v) => v + 1
    Err(CycleDetected(_, _, _)) => -1  // Fallback value
  }
})

match memo.read() {
  Ok(value) => println(value.to_string())  // Prints "-1"
  Err(_) => ()  // Only if error wasn't handled inside
}
```

When a cycle is detected via a `Result` read:
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
let word_count = Memo(rt, () => {
  file.content.get().split(" ").fold(init=0, (acc, _s) => acc + 1)
})

let is_test = Memo(rt, () => file.path.get().ends_with("_test.mbt"))

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

## Keyed Queries with MemoMap

Sometimes the same logical query is asked for many keys (e.g. file ID, symbol ID, route ID). `MemoMap[K, V]` provides one memoized computation per key:

```moonbit
let by_id = MemoMap::new(rt, (id : Int) => expensive_lookup(id))
```

Key behavior:

- The first `get(key)` creates that key's memo and computes it.
- Subsequent `get(key)` calls reuse the same key-local memo cache.
- Different keys are isolated from each other (independent memo instances).
- When dependencies change, each key recomputes lazily on its next read.

Read modes:

- `get(key)` is permissive: it works at top level and also records the per-key dependency when called inside a tracked compute.
- `get_tracked(key)` is strict: it records the same per-key dependency, but aborts outside a tracked compute. Use it when top-level use would indicate a bug.

This is a lightweight parameterized-query pattern built on top of `Memo`; it does not change runtime verification internals.

Future naming: the ideal API name is `DerivedMap[K, V]`. In that model,
fallible derived reads own the simple method names: `get(key)` is the strict
tracked-context `Result` read, `read(key)` is the permissive `Result` read, and
aborting conveniences use `_or_abort`.

## Side-Channel Data with Accumulators

Sometimes a memo needs to report extra information — diagnostics, trace events, logs — that is semantically separate from its return value. Threading this data through return types forces allocations at every level of the graph and makes merging fragile. `Accumulator[T]` is the side channel:

```moonbit
let rt = Runtime()
let width = Signal(rt, -5)
let diags : Accumulator[String] = Accumulator::new(rt~, label="diags")

let checked = Memo(rt, fn() raise {
  let w = width.get()
  if w < 0 { diags.push("negative width: \{w}") }
  w.abs()
})

let checked_observer = checked.observe()
let _ = checked_observer.get()
checked_observer.dispose()
// Outside any compute — untracked, permissive read:
debug_inspect(checked.accumulated_peek(diags), content="[\"negative width: -5\"]")
```

Producers call `acc.push(v)` inside a `Memo` or `HybridMemo` compute. Consumers have three read methods:

| Method | Records dep? | On disposal/cycle |
|--------|--------------|-------------------|
| `memo.accumulated(acc)` | yes — invalidates consumer when push set changes | raises `Failure` |
| `memo.accumulated_peek(acc)` | no — driver/debug use | returns `[]` |
| `memo.accumulated_result(acc)` | yes | `Result[_, CycleError]` |

### Push-Set Invalidation

The key property: when a producer memo recomputes and its push set differs from the previous run, downstream consumers reading via `accumulated` invalidate — **even when the producer's return value is structurally equal and would otherwise be backdated**. A per-memo `push_revised_at` counter tracks push-set revisions independently of value equality.

This is why an accumulator is not "just an `Array` you return": a plain return would either lose the change (backdated) or force every level to allocate fresh arrays that merge upward.

### Local-Only Scope

`memo.accumulated(acc)` returns only the values that memo's own compute pushed — **not** values pushed by its dependencies. Transitive aggregation across a subgraph (e.g. collecting diagnostics from every def in a module) is the driver's job: read each producer's `accumulated` at the boundary and union the results.

### Scope-Owned Lifecycle

Prefer `Scope::accumulator` over `Accumulator::new(rt~, ...)` when the accumulator's lifetime matches a larger unit of work (a chain rebuild, a compilation pass):

```moonbit
let chain_scope = parent_scope.child()
let diags = chain_scope.accumulator(label="typecheck_diags")
// Disposing chain_scope also disposes diags and clears its push buffers.
```

Runtime-owned accumulators live until explicitly disposed, so drivers that rebuild on structural change accumulate stale per-memo buffers. Scope ownership ties cleanup to the chain that produced the data.

### When to Use

| Situation | Recommendation |
|-----------|----------------|
| Data is the memo's value | return it normally |
| Data is log-like and orthogonal to the value (diagnostics, traces, warnings) | `Accumulator[T]` |
| Data flows to a single consumer already in the graph | return it — accumulator is overkill |
| Data aggregates across many producers into one consumer | `Accumulator[T]` |

See the [Cookbook](./cookbook.md#pattern-side-channel-diagnostics-with-accumulator) for complete worked examples, and the [ADR](./decisions/2026-04-20-accumulator-api.md) for the design rationale.

## Hybrid Push-Pull (HybridMemo)

`HybridMemo[T]` lives on the boundary between the push-driven and pull-driven engines:

```moonbit
let rt = Runtime()
let s = Input(rt, 1)
let h = ReachableDerived(rt, () => s.get() * 2)

inspect(h.read_or_abort(), content="2")
s.set(5)
inspect(h.read_or_abort(), content="10")
```

### How It Works

`HybridMemo` uses the same lazy revision-based verification as `Memo` — there
is **no separate dirty flag**. What makes it "hybrid" is *reachability*, not
invalidation: it participates in `push_reachable_count` so that a live
`Reactive`/`Effect` observer downstream keeps the memo and its upstream cells
alive across `Runtime::gc()` sweeps. When `get()` is called:

- **Fast path**: If `verified_at >= current_revision` → return cached value immediately, no dependency walk needed
- **Slow path**: Walk dependencies, recompute if needed

Future naming: the ideal API name is `ReachableDerived[T]`, because the
deterministic trait is reachability propagation. It is still lazy and does not
eagerly recompute itself.

### HybridMemo vs Memo

| Property | Memo | HybridMemo |
|----------|------|------------|
| Invalidation | Lazy revision check on read | Lazy revision check on read (same) |
| Reachable via push BFS | No | Yes — retained as reachable through eager/rooted dependents |
| Use case | General derived values | Bridge between push and pull graphs that must survive GC while observed |

Both support backdating — if a `HybridMemo` recomputes to the same value, downstream cells skip recomputation.

## Runtime Isolation

Each `Runtime` is a completely isolated universe. Signals and Memos belong to exactly one Runtime, and cross-runtime reads are a hard error:

```moonbit
let rt_a = Runtime()
let rt_b = Runtime()
let sig_b = Input(rt_b, 42)

// This aborts: sig_b belongs to rt_b, not rt_a
let bad = Derived(rt_a, () => sig_b.get())
bad.read_or_abort()  // abort: "Cross-runtime dependency"
```

The design is intentional:
- **No accidental stale data**: a silent cross-runtime read would return a value that never invalidates when the foreign signal changes
- **Consistent with fail-fast philosophy**: `Runtime::get_cell` aborts on wrong-runtime cell IDs; `Signal::get` and `Memo::get` follow the same rule

If you need to share data between two independent computation graphs, use a plain variable or a shared `Signal` on a common Runtime.

## Summary

| Concept | Purpose |
|---------|---------|
| Signal (`Input` target name) | Input values you control |
| Memo (`Derived` target name) | Derived values with automatic caching |
| HybridMemo (`ReachableDerived` target name) | Pull memo that participates in reachability propagation through eager/rooted dependents |
| MemoMap (`DerivedMap` target name) | Per-key memoized derived values |
| Accumulator | Side-channel collector with push-set invalidation (diagnostics, logs) |
| Revision | Global clock for tracking changes |
| Backdating | Skip downstream work when values don't actually change |
| Durability | Skip verification for stable subgraphs |
| Batch | Atomic multi-signal updates |
| TrackedCell (`InputField` target name) | Field-level input cells for fine-grained dependency isolation |
| Labels | Zero-cost names for readable error messages and debug output |
| Runtime Isolation | Each Runtime is independent; cross-runtime reads abort |

## Further Reading

- [API Reference](./api-reference.md) — Complete method reference
- [Cookbook](./cookbook.md) — Common patterns (including the Tracked Struct recipe)
- [design/internals.md](design/internals.md) — Implementation details
