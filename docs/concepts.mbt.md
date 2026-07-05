# Core Concepts

This document explains the key concepts behind `incr` without diving into implementation details. For the technical deep-dive, see [design/internals.md](design/internals.md).

High-value behavior examples from this guide are mirrored by checked literate
tests in [`concepts_examples.mbt.md`](concepts_examples.mbt.md), so constructor,
read, backdating, batching, field-level input, accumulator, and reachable-derived
semantics are caught by `moon check`.

## The Dependency Graph

`incr` models your computations as a directed graph:

```
[Input: price] ──┐
                 ├──► [Derived: subtotal] ──► [Derived: total]
[Input: qty]   ──┘                                  ▲
                                                     │
[Input: tax_rate] ──► [Derived: tax] ───────────────┘
```

- **Inputs** are the leaves (values you control)
- **Derived values** are the interior nodes (cached computations)
- **Arrows** represent dependencies (automatically tracked)

Naming note: as of v0.13.0 the compatibility names `Reactive`, `TrackedCell`,
`FunctionalRelation`, and the `Database` trait have been removed; use
`EagerDerived`, `InputField`, `MapRelation`, and `RuntimeContext` instead.
Migrating older code? See the [CHANGELOG](../CHANGELOG.md).

## Inputs

Inputs hold values that you set directly:

```mbt check
///|
test "concepts: input read and update" {
  let rt = @incr.Runtime()
  let count = @incr.Input(rt, 0)

  inspect(count.get(), content="0")

  count.set(5)
  inspect(count.get(), content="5")
}
```

### Same-Value Optimization

Setting an input to its current value is a no-op — no revision bump, no recomputation. Use `force_set` to bump the revision even when the value is equal. The checked companion pins both behaviors in [`concepts_examples.mbt.md`](concepts_examples.mbt.md#inputs-labels-and-read-vocabulary).

## Labels

Every `Input`, `Derived`, and `InputField` accepts an optional `label` parameter. Labels have **no runtime cost** — they are stored as `String?` on the cell metadata and never read during normal computation. The checked companion verifies label introspection in [`concepts_examples.mbt.md`](concepts_examples.mbt.md#inputs-labels-and-read-vocabulary). They only appear in:

- **Cycle error messages**: `"price → subtotal → total → price"` instead of `"Cell 2 → Cell 5 → Cell 8 → Cell 2"`
- **Introspection output**: `Runtime::cell_info` exposes the label when set

**Best practice: always set a label.** Debugging a cycle or reading `format_path` output is significantly easier with names attached.

## Derived Values

Derived values compute from inputs or other derived values and cache the result:

```mbt check
///|
test "concepts: derived values read inputs" {
  let rt = @incr.Runtime()
  let count = @incr.Input(rt, 21)
  let doubled = @incr.Derived(rt, () => count.get() * 2)

  inspect(doubled.read_or_abort(), content="42")
}
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
`DerivedMap` reads. The checked companion pins the inside-vs-outside shape in
[`concepts_examples.mbt.md`](concepts_examples.mbt.md#inputs-labels-and-read-vocabulary).

### Dependency Tracking

You don't declare dependencies. `incr` discovers them from reads during the compute function. Dependencies can change between recomputations: if `mode = "add"`, a result may depend on `mode`, `x`, and `y`; if you change `mode` to `"multiply"`, the dependency set may differ on the next computation. The checked companion pins this dynamic-dependency behavior in [`concepts_examples.mbt.md`](concepts_examples.mbt.md#backdating-batching-and-dynamic-dependencies).

## How `incr` Decides What to Recompute

A useful mental model is:

> `incr` stores the dependency trace from the last successful run, then verifies that trace lazily on the next read.

When you call `input.set(...)`, `incr` does **not** eagerly recompute every downstream `Derived`. It records that an input changed. Later, when some derived value is read, `incr` walks backward through the dependency graph and asks one question at each derived node:

> Can the cached value be proven still valid?

There are three common outcomes:

1. **Already verified** — the derived value was already checked at the current revision, so its cached value is returned immediately.
2. **Green path** — its recorded dependencies are checked and none of them changed, so the compute function does not run.
3. **Red path** — some recorded dependency changed, so the compute function runs again and records a fresh dependency trace.

Backdating is the final cutoff: if the red path computes the same value as before, downstream derived values still see "unchanged" and can take their own green path.

This is why `incr` works well with dynamic dependencies. The trace is not a static declaration; it is the set of cells actually read during the last successful compute. If a later compute takes a different branch, the trace is replaced with the new branch's dependencies.

## Choosing a Computation Mode

Most programs should start with pull mode and add push mode only at UI or side-effect boundaries.

| Mode | Public types | Update behavior | Best fit | Avoid when |
|---|---|---|---|---|
| Pull | `Input`, `Derived`, `DerivedMap`, `InputField` | Inputs bump revisions; derived values verify and recompute lazily when read | Semantic queries, parser/typechecker projections, expensive work, values that may not be observed after every edit | You need a sink to update immediately after every input write |
| Push | `EagerDerived`, `Effect` | Upstream changes eagerly propagate in topological-level order; reads return already-maintained cached values | UI-facing state, subscriptions, side effects, low-cost derived values that should stay current | Computation is expensive and often unobserved |
| Reachable lazy | `ReachableDerived` | Same lazy revision verification as `Derived`; additionally participates in push reachability and `Watch`/GC lifetimes | Bridges from pull-derived values into push subscribers; long-lived watched lazy values | You expect eager recomputation — use `EagerDerived` instead |
| Datalog | `Relation`, `MapRelation`, `Rule` | `fixpoint()` derives facts until no new facts appear | Relational closure, graph reachability, rule systems | Ordinary one-value derived computations |

Guidelines:

- Choose `Derived` for ordinary derived state. It has the strongest default cost model because unused values do no work.
- Choose `DerivedMap` when the natural computation is a keyed query, such as `type_of(function_id)`.
- Choose `EagerDerived` when the value is part of a push-maintained UI graph and should already be current by the time it is read.
- Choose `Effect` for eager side effects; do not smuggle side effects through a `Derived` return value.
- Choose `ReachableDerived` when you need lazy pull semantics but the value must stay reachable through downstream `EagerDerived`/`Effect` subscribers or long-lived `Watch` roots.

## Revisions

A **Revision** is a global counter that increments when any input changes:

| Event | Global Revision |
|-------|-----------------|
| Initial state | R0 |
| `price.set(200)` | R1 |
| `qty.set(3)` | R2 |
| `qty.set(3)` (same value) | R2 (unchanged) |

Every cell tracks two timestamps:

- **`changed_at`** — When the cell's value last actually changed
- **`verified_at`** — When the cell was last confirmed up-to-date

A derived value is stale when `verified_at < current_revision`.

## Backdating

**Backdating** is the key optimization. When a derived value recomputes to the **same value** as before, its `changed_at` stays at the old revision. This prevents unnecessary cascading through the graph. The checked companion demonstrates the classic `4 → 6` evenness case in [`concepts_examples.mbt.md`](concepts_examples.mbt.md#backdating-batching-and-dynamic-dependencies).

### Backdating strategies
Three public `Derived` constructors offer different backdate strategies:

- **`Derived::Derived[T : Eq]`** — uses `a == b`. Standard choice for most types.
- **`Derived::with_backdate[T : BackdateEq]`** — uses `a.backdate_equal(b)`. Use for custom backdate logic, e.g. comparing embedded `changed_at` revisions instead of full values.
- **`Derived::derived_no_backdate[T]`** — never backdates. Use when downstream consumers always need to rerun, or when `T` has no suitable equality.

See the [API reference](api-reference.mbt.md) for details.

## Durability

**Durability** classifies inputs by change frequency:

| Level | Use Case |
|-------|----------|
| `Low` | Frequently changing (user input, source text) |
| `Medium` | Moderately stable |
| `High` | Rarely changing (configuration, schemas) |

```mbt nocheck
///|
let rt = @incr.Runtime()

///|
let config = @incr.Input(rt, 100, durability=High)

///|
let input = @incr.Input(rt, 1)
```

### Durability Shortcut

When only low-durability inputs change, derived values that depend solely on high-durability inputs skip verification entirely. The checked companion verifies that a high-durability-only derived value stays cached when an unrelated low-durability input changes in [`concepts_examples.mbt.md`](concepts_examples.mbt.md#backdating-batching-and-dynamic-dependencies).

### Inherited Durability

Derived values inherit the **minimum** durability of their dependencies:

```mbt nocheck
///|
let rt = @incr.Runtime()

///|
let high = @incr.Input(rt, 1, durability=High)

///|
let low = @incr.Input(rt, 2)

///|
let mixed = @incr.Derived(rt, () => high.get() + low.get())
```

## Batch Updates

Update multiple inputs atomically:

```mbt check
///|
test "concepts: batch updates" {
  let rt = @incr.Runtime()
  let x = @incr.Input(rt, 0)
  let y = @incr.Input(rt, 0)
  let z = @incr.Input(rt, 0)

  rt.batch(() => {
    x.set(10)
    y.set(20)
    z.set(30)
  })

  inspect(x.get() + y.get() + z.get(), content="60")
}
```

Benefits:
- Avoids intermediate recomputations
- Enables **revert detection**: if you set and then reset a value within a batch, no change is recorded. The checked companion pins this net-zero behavior in [`concepts_examples.mbt.md`](concepts_examples.mbt.md#backdating-batching-and-dynamic-dependencies).

## Cycle Detection

Cyclic dependencies are detected at runtime:

```mbt check
///|
test "concepts: cycles surface through Result reads" {
  let rt = @incr.Runtime()
  let a_ref : Ref[@incr.Derived[Int]?] = { val: None }
  let b_ref : Ref[@incr.Derived[Int]?] = { val: None }
  let saw_cycle : Ref[Bool] = { val: false }
  let a = @incr.Derived(rt, () => {
    match b_ref.val.unwrap().get() {
      Ok(v) => v + 1
      Err(_err) => {
        saw_cycle.val = true
        0
      }
    }
  })
  let b = @incr.Derived(rt, () => {
    match a_ref.val.unwrap().get() {
      Ok(v) => v + 1
      Err(_err) => {
        saw_cycle.val = true
        0
      }
    }
  })
  a_ref.val = Some(a)
  b_ref.val = Some(b)

  inspect(a.read_or_abort(), content="1")
  inspect(saw_cycle.val, content="true")
}
```

### Graceful Cycle Handling

Use `get()` inside a tracked compute or `read()` outside the graph to handle cycles without aborting. The checked cookbook companion shows a self-referential derived value recovering inside its compute function in [`cookbook_examples.mbt.md`](cookbook_examples.mbt.md#graceful-cycle-handling).

When a cycle is detected via a `Result` read:
- The error can be caught and handled in the compute function
- No dependency is recorded for failed reads (prevents spurious future cycles)
- The runtime remains in a consistent state for subsequent operations

## Field-Level Tracking

When a struct has several logically related fields, you often want derived values that depend on only one field to skip recomputation when a different field changes. `Input[MyStruct]` cannot do this — updating any field forces every downstream derived value to reverify.

**`InputField[T]`** solves this by giving each field its own independent input cell. Each `InputField` has the same core input behavior as `Input[T]` — same-value optimization, durability levels, change hooks — but it belongs to a named field. The checked companion defines a field-owner struct in [`concepts_examples.mbt.md`](concepts_examples.mbt.md#field-level-inputs-and-keyed-derived-values).

### InputFieldOwner Trait

Implement the `InputFieldOwner` trait to declare which fields a struct owns. This enables bulk lifecycle operations with `add_input_fields(scope, owner)`; the checked companion exercises this lifecycle wiring in [`concepts_examples.mbt.md`](concepts_examples.mbt.md#field-level-inputs-and-keyed-derived-values).

### Field-Level Dependency Isolation

Derived values that read individual `InputField` fields only depend on those fields, not on the whole struct. The checked companion verifies that changing `version` leaves `content` and `path` consumers untouched in [`concepts_examples.mbt.md`](concepts_examples.mbt.md#field-level-inputs-and-keyed-derived-values).

### When to Use InputField vs Input

| Situation | Recommendation |
|-----------|----------------|
| Single scalar value | `Input[T]` |
| Multiple related fields with independent consumers | `InputField[T]` in a field-owner struct |
| Monolithic struct updated atomically | `Input[MyStruct]` with batch |

## Keyed Queries with DerivedMap

Sometimes the same logical query is asked for many keys (e.g. file ID, symbol ID, route ID). `DerivedMap[K, V]` provides one memoized derived computation per key. The checked companion pins per-key cache creation and lazy recomputation in [`concepts_examples.mbt.md`](concepts_examples.mbt.md#field-level-inputs-and-keyed-derived-values).

Key behavior:

- The first read creates that key's derived value and computes it.
- Subsequent reads reuse the same key-local cache.
- Different keys are isolated from each other (independent derived instances).
- When dependencies change, each key recomputes lazily on its next read.

Read modes:

- `read(key)` is permissive: it works at top level and also records the per-key dependency when called inside a tracked compute.
- `read_or_abort(key)` is the aborting convenience for permissive reads.
- `get(key)` is strict: it records the same per-key dependency and returns read errors as `Result`, but aborts outside a tracked compute. Use it when top-level use would indicate a bug.
- `get_or_abort(key)` is the aborting convenience for strict reads.
This is a lightweight parameterized-query pattern built on top of `DerivedMap`; it does not change runtime verification internals.

Cache helpers use target names: `has_cached(key)`, `cache_len()`,
`sweep_cache()`, and `clear_cache()`.

## Side-Channel Data with Accumulators

Sometimes a derived value needs to report extra information — diagnostics, trace events, logs — that is semantically separate from its return value. Threading this data through return types forces allocations at every level of the graph and makes merging fragile. `Accumulator[T]` is the side channel; the checked companion shows derived-local diagnostic collection in [`concepts_examples.mbt.md`](concepts_examples.mbt.md#accumulators-and-reachable-derived-values).
Producers call `acc.push(v)` inside a `Derived` compute. Consumers read back via target methods:

| Method | Records dep? | On disposal/cycle |
|--------|--------------|-------------------|
| `derived.accumulated(acc)` | Yes (inside tracked context) | `Err(ReadError)` for target cycle/disposal; raises `Failure` for disposed accumulator |
| `derived.accumulated_or_abort(acc)` | Yes (inside tracked context) | aborts |
| `derived.accumulated_peek(acc)` | No | returns `[]` on disposed |
| `derived.accumulated_result(acc)` | Yes (inside tracked context) | `Err(ReadError)` (alias) |

### Push-Set Invalidation

The key property: when a producer recomputes and its push set differs from the previous run, downstream consumers reading via `accumulated` (or the strict `accumulated_or_abort`) invalidate — **even when the producer's return value is structurally equal and would otherwise be backdated**. A `push_revised_at` counter tracks push-set revisions independently of value equality.


This is why an accumulator is not "just an `Array` you return": a plain return would either lose the change (backdated) or force every level to allocate fresh arrays that merge upward.

### Local-Only Scope

`derived.accumulated(acc)` returns only the values that producer pushed — **not** values pushed by its dependencies. Transitive aggregation across a subgraph (e.g. collecting diagnostics from every def in a module) is the driver's job: read each producer's `accumulated` at the boundary and union the successful results.

### Scope-Owned Lifecycle

Prefer `Scope::accumulator` over `Accumulator(rt, ...)` when the accumulator's lifetime matches a larger unit of work (a chain rebuild, a compilation pass). Runtime-owned accumulators live until explicitly disposed, so drivers that rebuild on structural change accumulate stale per-cell buffers. Scope ownership ties cleanup to the chain that produced the data. The API-reference companion checks scope-owned accumulator disposal in [`api_reference_examples.mbt.md`](api_reference_examples.mbt.md#accumulator--compatibility-push-side-channel).

The same lifecycle pattern applies to long-lived target readers: use
`scope.add_watch(derived.watch())` when a `Watch` should be disposed with the
scope that owns the surrounding graph.

### When to Use

| Situation | Recommendation |
|-----------|----------------|
| Data is the derived cell's result | return it normally |
| Data is log-like and orthogonal to the value (diagnostics, traces, warnings) | `Accumulator[T]` |
| Data flows to a single consumer already in the graph | return it — accumulator is overkill |
| Data aggregates across many producers into one consumer | `Accumulator[T]` |

See the [Cookbook](./cookbook.mbt.md#pattern-side-channel-diagnostics-with-accumulator) for complete worked examples, and the [ADR](./decisions/2026-04-20-accumulator-api.md) for the design rationale.

## Reachable Derived Values

`ReachableDerived[T]` lives on the boundary between the push-driven and pull-driven engines. The checked companion verifies lazy reads and updates in [`concepts_examples.mbt.md`](concepts_examples.mbt.md#accumulators-and-reachable-derived-values).

### How It Works

`ReachableDerived` uses the same lazy revision-based verification as `Derived` — there
is **no separate dirty flag**. What makes it "reachable" is *reachability*, not
invalidation: it participates in `push_reachable_count` so that a live
`EagerDerived`/`Effect` observer downstream keeps the derived value and its upstream cells
alive across `Runtime::gc()` sweeps. When `get()` is called:

- **Fast path**: If `verified_at >= current_revision` → return cached value immediately, no dependency walk needed
- **Slow path**: Walk dependencies, recompute if needed
`ReachableDerived[T]` is the target facade. It is still lazy and does not eagerly recompute itself.

### ReachableDerived vs Derived

| Property | Derived | ReachableDerived |
|----------|------|------------|
| Invalidation | Lazy revision check on read | Lazy revision check on read (same) |
| Reachable via push BFS | No | Yes — retained as reachable through eager/rooted dependents |
| Use case | General derived values | Bridge between push and pull graphs that must survive GC while observed |

Both support backdating — if a `ReachableDerived` recomputes to the same value, downstream cells skip recomputation.

## Runtime Isolation

Each `Runtime` is a completely isolated universe. Inputs and derived values belong to exactly one Runtime, and cross-runtime reads are a hard error:

```mbt nocheck
///|
let rt_a = @incr.Runtime()

///|
let rt_b = @incr.Runtime()

///|
let input_b = @incr.Input(rt_b, 42)

///|
let bad = @incr.Derived(rt_a, () => input_b.get())
```

The design is intentional:
- **No accidental stale data**: a silent cross-runtime read would return a value that never invalidates when the foreign input changes
- **Consistent with fail-fast philosophy**: reading a cell through the wrong runtime aborts immediately instead of returning silently stale data

If you need to share data between two independent computation graphs, use a plain variable or a shared `Input` on a common Runtime.

## Summary

| Concept | Purpose |
|---------|---------|
| Input | Input values you control |
| Derived | Derived values with automatic caching |
| ReachableDerived | Pull derived value that stays reachable through eager/rooted dependents |
| DerivedMap | Per-key memoized derived values |
| Accumulator | Side-channel collector with push-set invalidation (diagnostics, logs) |
| Revision | Global clock for tracking changes |
| Backdating | Skip downstream work when values don't actually change |
| Durability | Skip verification for stable subgraphs |
| Batch | Atomic multi-input updates |
| InputField | Field-level input cells for fine-grained dependency isolation |
| EagerDerived | Push-reactive derived value |
| MapRelation | Functional Datalog relation keyed by map keys |
| Labels | Zero-cost names for readable error messages and debug output |
| Runtime Isolation | Each Runtime is independent; cross-runtime reads abort |

## Further Reading

- [API Reference](./api-reference.mbt.md) — Complete method reference
- [Cookbook](./cookbook.mbt.md) — Common patterns (including the field-level input recipe)
- [design/internals.md](design/internals.md) — Implementation details
