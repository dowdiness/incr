# API Reference

Reference for the most commonly used public APIs in `incr`. This is not exhaustive — the authoritative surface is in `pkg.generated.mbti` and `cells/pkg.generated.mbti`. APIs surfaced here: `Runtime`, `Input`, `Derived`, `ReachableDerived`, `DerivedMap`, `InputField`, legacy compatibility handles (`Signal`, `Memo`, `HybridMemo`, `MemoMap`, `TrackedCell`), `Accumulator`, `MemoEvent`, `CycleError`, the `RuntimeContext`/`Database`/`Freshness`/`Readable`/`InputFieldOwner`/`Trackable` traits, and the top-level helper functions. Specialised APIs (`EagerDerived` / `Reactive`, `Effect`, `Relation`, `MapRelation` / `FunctionalRelation`, `Scope`, `Watch` / `Observer`) are documented next to their constructors in `cells/`.

> **Recommended Pattern:** Use the `RuntimeContext` trait to encapsulate your
> `Runtime` in an application context type. This makes your API cleaner and
> hides implementation details. Compatibility helpers still accept `Database`.
> See the [Helper Functions](#helper-functions) section and [API Design Guidelines](design/api-design-guidelines.md) for details.

> **Naming direction:** Target facade names are recommended for new code.
> Legacy compatibility names remain available while migration continues:
> `Signal`, `Memo`, `HybridMemo`, `Reactive`, `MemoMap`, `TrackedCell`,
> `Observer`, `FunctionalRelation`, `Readable`, `Trackable`, and `Database`.
> The mapping is recorded in [2026-05-21-public-api-ideal-naming](decisions/2026-05-21-public-api-ideal-naming.md).

## Read Vocabulary Migration

Target reads use `read` for permissive outside-graph reads and `get` for strict
tracked-context reads:

| Legacy compatibility | Target facade |
|---|---|
| `rt.read(memo)` | `derived.read_or_abort()` or `derived.read()` |
| `memo.observe().get()` | `derived.watch().read_or_abort()` or `derived.watch().read()` |
| `Memo::get()` inside a compute | `Derived::get_or_abort()` |
| `Memo::get_result()` outside the graph | `Derived::read()` |
| `Memo::get_result()` inside a compute | `Derived::get()` |
| `MemoMap::get(key)` | `DerivedMap::read_or_abort(key)` |
| `MemoMap::get_tracked(key)` | `DerivedMap::get_or_abort(key)` |
| `MemoMap::contains(key)` / `length()` | `DerivedMap::has_cached(key)` / `cache_len()` |
| `rt.read_hybrid(hybrid)` | `reachable.read_or_abort()` or `reachable.read()` |
| `hybrid.observe().get()` | `reachable.watch().read_or_abort()` or `reachable.watch().read()` |

## Runtime

Central coordinator for dependency tracking, revisions, and batching.

### `Runtime::new(on_change? : () -> Unit) -> Runtime`

Creates a new runtime with an empty dependency graph. The optional `on_change` callback is equivalent to calling `Runtime::set_on_change` immediately after construction.

```moonbit
let rt = Runtime()
let rt = Runtime(on_change=() => rerender())
```

### `Runtime::batch(self, f: () -> Unit raise?) -> Unit raise?`

Executes `f` with batched input updates.

Inside a batch, `Input::set()` and `Input::force_set()` writes are deferred and committed when the outermost batch exits. Compatibility `Signal::set()` and `Signal::set_unconditional()` have the same batching behavior.

```moonbit
rt.batch(() => {
  x.set(1)
  y.set(2)
})
```

Behavior:
- Nested batches are supported (only the outermost batch commits)
- If an inner batch raises, its writes are rolled back before the error is re-raised
- All committed changes share one revision bump
- Revert detection applies to `Input::set()` writes (`5 -> 0 -> 5` can result in no net change)
- Reads during a batch observe pre-batch values
- If `f` raises, pending writes are rolled back and the error is re-raised

Limit — abort safety:
- `abort()` is not catchable in MoonBit. If `f` calls `abort()` (directly or indirectly), the catch block inside `batch()` never runs. The runtime is left in inconsistent state: `batch_depth` is not decremented, the batch frame stack is not popped, and pending inputs retain dangling `commit_pending`/`rollback_pending` closures. The runtime should be considered unusable after an abort.
- The most common indirect source of `abort()` inside a batch is using an aborting read on a derived value involved in a dependency cycle. Use `Derived::read()` inside batch functions to handle cycles gracefully instead of aborting.

```moonbit
// Dangerous: cycle causes abort(), leaving batch state corrupted
rt.batch(() => {
  x.set(1)
  let _ = cyclic_derived.read_or_abort()  // aborts if cycle exists
})

// Safe: cycle is returned as Err, batch rolls back cleanly on raise
rt.batch(fn() raise {
  x.set(1)
  match cyclic_derived.read() {
    Ok(v) => use_value(v)
    Err(e) => raise e  // triggers rollback
  }
})
```

### `Runtime::batch_result(self, f: () -> Unit raise?) -> Result[Unit, Error]`

Executes a batch and returns raised errors as `Result` instead of re-raising.
Like `Runtime::batch`, this handles raised errors only; `abort()` still escapes, is not converted to `Err`, and leaves the runtime in the same inconsistent state described above.

```moonbit
suberror BatchStop {
  Stop
}

let res = rt.batch_result(fn() raise {
  x.set(1)
  raise Stop
})
inspect(res is Err(_), content="true")
```

### `Runtime::set_on_change(self, f: () -> Unit) -> Unit`

Registers a callback fired when the runtime records a committed change.

```moonbit
let mut count = 0
rt.set_on_change(() => { count = count + 1 })
```

Behavior:
- Outside batch: fires immediately after each committed change
- Inside batch: fires once at batch end if at least one input actually changed
- No fire for no-op `Input::set()` (same value)

### `Runtime::clear_on_change(self) -> Unit`

Removes the registered change callback.

```moonbit
rt.clear_on_change()
```

### `Runtime::read[T](self, memo: Memo[T]) -> T`

Deprecated legacy compatibility helper for reading a memo from **outside** a tracked
compute. It observes once, reads the value, and disposes the observer in one
call. New target-facade code should prefer `Derived::read()`,
`Derived::read_or_abort()`, or `Derived::watch()`. Aborts if the memo has been
disposed.

```moonbit
let value = rt.read(my_memo)
```

### `Runtime::read_hybrid[T : Eq](self, memo: HybridMemo[T]) -> T`

Deprecated legacy one-shot observe for `HybridMemo[T]`. New target-facade code should
prefer `ReachableDerived::read()`, `ReachableDerived::read_or_abort()`, or
`ReachableDerived::watch()`.

### `Runtime::read_reactive[T](self, reactive: Reactive[T]) -> T`

Deprecated legacy one-shot observe for `Reactive[T]`. New target-facade code
should prefer `EagerDerived::read()` or `EagerDerived::watch()`.

### `Runtime::on_memo_event(self, f: (MemoEvent) -> Unit) -> Unit raise Failure`

Registers the runtime's memo recompute listener. The listener receives pull
`Memo` and `HybridMemo` lifecycle events after the recompute path reaches a
safe drain point; it is not called inline from the memo compute closure.

Only one listener is stored. Calling `on_memo_event` replaces the previous
listener.

```moonbit
let events : Array[MemoEvent] = []
rt.on_memo_event(evt => events.push(evt))
```

The listener is a synchronous, non-raising callback. If a driver needs async
logging, enqueue inside the callback and let another part of the driver drain
that queue.

Mutation guard:
- `on_memo_event` raises `Failure` while an operation is in flight
- Rejected windows include active recompute, open batch, non-idle propagation
  phase, buffered-but-undrained events, and listener drain reentry
- Register listeners between top-level operations, before starting the graph
  work you want to observe

### `Runtime::clear_memo_event_listener(self) -> Unit raise Failure`

Removes the memo event listener. It has the same mutation guard as
`on_memo_event`; clear it between operations, not from inside compute,
`on_change`, or a memo-event listener.

```moonbit
rt.clear_memo_event_listener()
```

### `MemoEvent`

`MemoEvent` is the public event payload delivered by
`Runtime::on_memo_event`.

```moonbit
pub(all) enum MemoEvent {
  EnteringCompute(MemoEnteringEvent)
  Completed(MemoCompletedEvent)
  Aborted(MemoAbortedEvent)
}
```

`MemoEnteringEvent` fields:
- `cell_id`: memo cell entering recompute
- `started_revision`: runtime revision captured at recompute entry

`MemoCompletedEvent` fields:
- `cell_id`: memo cell that completed
- `elapsed_ns`: best-effort elapsed duration for this recompute
- `started_revision`: same entry revision carried from `EnteringCompute`
- `verified_at`: memo verification revision after commit
- `changed_at`: memo change revision after backdating
- `backdated`: `true` when the recompute produced an equal value and preserved
  `changed_at`

`MemoAbortedEvent` fields:
- `cell_id`: memo cell whose compute raised a catchable `Error`
- `elapsed_ns`: best-effort elapsed duration before the raise
- `started_revision`: same entry revision carried from `EnteringCompute`
- `error`: the captured `Error`; stringify in the driver if needed

Events are best-effort for catchable raises. A direct `abort()` inside a compute
closure is uncatchable and may leave an unmatched `EnteringCompute` event.

---

## Input[T] / Signal[T]

`Input[T]` is the target-name facade for externally controlled values. `Signal[T]` remains available as the compatibility handle.

### `Input[T](rt: Runtime, initial: T, durability? : Durability, label? : String) -> Input[T]`

Creates an input. Both `durability` (default `Low`) and `label` are optional.

The `label` string is used in cycle error messages and `Runtime::cell_info` output. Without a label, cells appear as `Cell[42]` in diagnostics. **Prefer always setting a label** — it has no runtime cost and makes debugging significantly easier.

```moonbit
let count = Input(rt, 0)
let config = Input(rt, "prod", durability=High, label="config")
```

### `Input::get(self) -> T`

Returns the current input value and records a dependency when called inside a derived computation. Aborts on cross-runtime reads.

### `Input::peek(self) -> T`

Returns the current value **without** recording a dependency, even when called inside a derived computation. Use for telemetry, logging, or any read that should not invalidate the caller when the input changes.

### `Input::set[T : Eq](self, value: T) -> Unit`

Sets a new value. If the new value equals the current value (`old == new`), the call is a no-op: no revision is bumped and downstream derived values are not invalidated. Requires `T : Eq`. See [Type Constraints](#type-constraints) for why.

### `Input::force_set[T](self, value: T) -> Unit`

Sets a new value without equality checking; always treated as a change when committed.

### `Input::is_fresh(self) -> Bool`

Always returns `true`. Inputs are directly-set cells.

### Compatibility `Signal[T]`

`Signal[T]` exposes the same underlying input cell with legacy names:

- `Signal(rt, value, durability?, label?)` constructs a compatibility input handle.
- `Signal::set_unconditional(value)` is `Input::force_set(value)`.
- `Signal::is_up_to_date()` is `Input::is_fresh()`.
- `Signal::get_result()` always returns `Ok(value)` and exists for legacy symmetry with `Memo::get_result()`.
- `Signal::id()`, `Signal::durability()`, `Signal::on_change()`, and `Signal::clear_on_change()` remain available on the compatibility handle for introspection and callbacks.

---

## InputField[T] / TrackedCell[T]

`InputField[T]` is the target-name field-level input facade. `TrackedCell[T]` remains available as the compatibility handle.

### `InputField[T](rt: Runtime, initial: T, durability?: Durability, label?: String) -> InputField[T]`

Creates a field-level input. Both `durability` (default `Low`) and `label` are optional. A label like `"SourceFile.path"` identifies which field of which struct caused a problem.

```moonbit
let path = InputField(rt, "/src/main.mbt", label="SourceFile.path")
let version = InputField(rt, 0, durability=High, label="SourceFile.version")
```

### `InputField::get(self) -> T`

Returns the current field value and records a dependency when called inside a derived computation.

### `InputField::peek(self) -> T`

Returns the current field value without recording a dependency.

### `InputField::set[T : Eq](self, value: T) -> Unit`

Sets a new value with same-value optimization.

### `InputField::force_set[T](self, value: T) -> Unit`

Sets a new value without equality checking; always treated as a change.

### `InputField::id(self) -> CellId`

Returns the unique identifier for this field. Use with `Runtime::cell_info()` or when implementing `InputFieldOwner`.

### `InputField::durability(self) -> Durability`

Returns the durability level set at construction time.

### `InputField::on_change(self, f: (T) -> Unit) -> Unit`

Registers a callback fired when this field's value changes. Replaces any previously registered callback.

### `InputField::clear_on_change(self) -> Unit`

Removes the registered `on_change` callback.

### `InputField::is_fresh(self) -> Bool`

Always returns `true`. Input fields are directly-set cells.

### `InputField::dispose(self) -> Unit`

Disposes the underlying tracked cell. Reads or writes after disposal abort.

### `InputField::is_disposed(self) -> Bool`

Returns whether the field has been disposed.

### `InputField::as_tracked_cell(self) -> TrackedCell[T]`

Returns the compatibility `TrackedCell[T]` handle for interop.

### Compatibility `TrackedCell[T]`

`TrackedCell[T]` exposes the same underlying field cell with legacy names:

- `TrackedCell(rt, value, durability?, label?)` constructs a compatibility field handle.
- `TrackedCell::set_unconditional(value)` is `InputField::force_set(value)`.
- `TrackedCell::is_up_to_date()` is `InputField::is_fresh()`.
- `TrackedCell::get_result()` always returns `Ok(value)` and exists for legacy symmetry with `Memo::get_result()`.
- `TrackedCell::as_signal()` returns the underlying compatibility `Signal[T]`.

---

## Derived[T] / Memo[T]

`Derived[T]` is the target-name lazy derived-value facade. `Memo[T]` remains available as the compatibility handle.

### `Derived[T : Eq](rt: Runtime, compute: () -> T raise Failure, label? : String) -> Derived[T]`

Creates a lazily evaluated derived value using structural equality (`T : Eq`) for backdating. When a recomputation produces a value equal to the previous one, the derived value's `changed_at` timestamp is preserved rather than advanced, preventing unnecessary downstream invalidation.

```moonbit
let doubled = Derived(rt, () => count.get() * 2)
let tax = Derived(rt, () => price.get() * 0.1, label="tax")
```

### `Derived::get(self) -> Result[T, CycleError]`

Strict graph read. It must be called inside another derived compute function, where it records a dependency. It aborts outside a tracked context and returns `Err(CycleError)` for cycles.

### `Derived::get_or_abort(self) -> T`

Strict graph read that aborts on invalid context or cycle.

### `Derived::read(self) -> Result[T, CycleError]`

Permissive read. It works from top-level code, tests, event handlers, and callbacks, and it still records a dependency when called inside a tracked compute.

```moonbit
match doubled.read() {
  Ok(v) => println(v.to_string())
  Err(cycle) => println(cycle.format_path())
}
```

### `Derived::read_or_abort(self) -> T`

Permissive read that aborts on cycle.

### `Derived::watch(self) -> Watch[T]`

Creates a long-lived outside-graph reader. The `Watch` is a GC root until disposed, and `watch.read()` returns `Result[T, CycleError]`.

### `Derived::is_fresh(self) -> Bool`

Returns whether this derived value is verified at the current revision.

### Compatibility `Memo[T]`

`Memo[T]` exposes the underlying lazy cell with legacy names and additional compatibility-only APIs:

- `Memo(rt, f, label?)` constructs a compatibility memo using `T : Eq` backdating.
- `Memo::new_memo[T : BackdateEq]` and `Memo::new_no_backdate[T]` expose alternate backdating strategies.
- `Memo::get()` is the legacy strict aborting graph read.
- `Memo::get_result()`, `get_or()`, and `get_or_else()` are legacy permissive cycle-safe reads.
- `Memo::is_up_to_date()` is `Derived::is_fresh()`.
- `Memo::observe()` creates a legacy `Observer[T]`.
- `Memo::id()`, `dependencies()`, `changed_at()`, `verified_at()`, `on_change()`, and `clear_on_change()` remain available on the compatibility handle.

### `Memo::accumulated[T, A](self, acc: Accumulator[A]) -> Array[A] raise Failure`

Returns the values this memo pushed into `acc` during its most recent compute,
in push order. When called from a `Memo` or `HybridMemo` compute frame, it
records a synthetic dependency so that caller reinvalidates when the push set
changes — even when the memo's ordinary return value is unchanged. Outside a
memo compute, it returns data without registering a dependency. Forces
verification of the target memo first, so stale results are never returned.

Raises `Failure` on: disposed accumulator, cross-runtime accumulator, disposed target memo, a cycle involving the target, or a `Failure` raised inside the target's compute.

### `Memo::accumulated_peek[T, A](self, acc: Accumulator[A]) -> Array[A]`

Untracked read of the values the memo pushed into `acc` during its most recent compute. Does **not** record a dependency, does **not** force verification, and is **permissive on disposal** — returns `[]` when the accumulator or target is disposed, or when the target has never been computed.

### `Memo::accumulated_result[T, A](self, acc: Accumulator[A]) -> Result[Array[A], CycleError] raise Failure`

Tracked, verifying read that surfaces a cycle in the target as `Err(CycleError)` rather than raising. Other defect classes (disposed handles, cross-runtime reuse) still raise `Failure`.

---

## DerivedMap[K, V] / MemoMap[K, V]

`DerivedMap[K, V]` is the target-name keyed derived facade. `MemoMap[K, V]` remains available as the compatibility handle.

### `DerivedMap[K : Hash + Eq, V](rt: Runtime, compute: (K) -> V raise Failure, label? : String) -> DerivedMap[K, V]`

Creates an empty derived map. No per-key derived value is allocated until first read of that key.

```moonbit
let by_id = DerivedMap(rt, (id : Int) => id * 10)
let named = DerivedMap(rt, (id : Int) => id * 10, label="by_id")
```

### `DerivedMap::read[K : Hash + Eq, V : Eq](self, key: K) -> Result[V, CycleError]`

Permissive read for `key`. It works outside the graph and records a per-key dependency when called inside a tracked compute.

### `DerivedMap::read_or_abort[K : Hash + Eq, V : Eq](self, key: K) -> V`

Permissive read that aborts on cycle.

### `DerivedMap::get[K : Hash + Eq, V : Eq](self, key: K) -> Result[V, CycleError]`

Strict graph read for `key`. It records the per-key dependency inside a tracked compute, aborts outside a tracked context, and returns `Err(CycleError)` for cycles.

### `DerivedMap::get_or_abort[K : Hash + Eq, V : Eq](self, key: K) -> V`

Strict graph read that aborts on invalid context or cycle.

### `DerivedMap::read_or[K : Hash + Eq, V : Eq](self, key: K, fallback: V) -> V`

Returns the value for `key`, or `fallback` if a cycle is detected.

### `DerivedMap::read_or_else[K : Hash + Eq, V : Eq](self, key: K, fallback: (CycleError) -> V) -> V`

Returns the value for `key`, or computes a fallback from the cycle error.

### `DerivedMap::has_cached[K : Hash + Eq, V](self, key: K) -> Bool`

Returns whether a cached entry exists for `key`.

### `DerivedMap::cache_len(self) -> Int`

Returns the number of cached entries.

### `DerivedMap::sweep_cache[K : Hash + Eq, V](self) -> Int`

Removes cached entries whose underlying cells have been disposed.

### `DerivedMap::clear_cache(self) -> Unit`

Clears all cached entries.

### Compatibility `MemoMap[K, V]`

`MemoMap[K, V]` exposes the underlying keyed memo cache with legacy names:

- `MemoMap(rt, f, label?)` constructs a compatibility keyed memo map.
- `MemoMap::get(key)` is the legacy permissive aborting read.
- `MemoMap::get_tracked(key)` is the legacy strict aborting read.
- `MemoMap::get_result(key)`, `get_or(key, fallback)`, and `get_or_else(key, fallback)` are legacy permissive cycle-safe reads.
- `MemoMap::contains(key)` is `DerivedMap::has_cached(key)`.
- `MemoMap::length()` is `DerivedMap::cache_len()`.

---

## ReachableDerived[T] / HybridMemo[T]

`ReachableDerived[T]` is a lazy derived value that participates in reachability propagation so eager/rooted downstream cells can keep its upstream graph reachable across `Runtime::gc()` sweeps. `HybridMemo[T]` remains available as the compatibility handle.

### `ReachableDerived[T : Eq](rt: Runtime, compute: () -> T raise Failure, label? : String) -> ReachableDerived[T]`

Creates a reachable derived value. It does not make the value eager; recomputation still happens on read.

```moonbit
let reachable = ReachableDerived(rt, () => input.get() * 2, label="doubled")
```

### `ReachableDerived::get[T : Eq](self) -> Result[T, CycleError]`

Strict graph read. It must be called inside another derived compute function, aborts outside a tracked context, and returns `Err(CycleError)` for cycles.

### `ReachableDerived::get_or_abort[T : Eq](self) -> T`

Strict graph read that aborts on invalid context or cycle.

### `ReachableDerived::read[T : Eq](self) -> Result[T, CycleError]`

Permissive read. It works outside the graph and records a dependency when called inside a tracked compute.

### `ReachableDerived::read_or_abort[T : Eq](self) -> T`

Permissive read that aborts on cycle.

### `ReachableDerived::watch[T : Eq](self) -> Watch[T]`

Creates a long-lived outside-graph reader. The `Watch` is a GC root until disposed.

### `ReachableDerived::is_fresh(self) -> Bool`

Returns whether this reachable derived value is verified at the current revision.

### Compatibility `HybridMemo[T]`

`HybridMemo[T]` exposes the same lazy reachable cell with legacy names:

- `HybridMemo(rt, f, label?)` constructs a compatibility reachable memo.
- `HybridMemo::get()` is the legacy strict aborting graph read.
- `HybridMemo::is_up_to_date()` is `ReachableDerived::is_fresh()`.
- `HybridMemo::observe()` creates a legacy `Observer[T]`.
- `HybridMemo::id()`, `dispose()`, and `is_disposed()` remain available on the compatibility handle.

---

## Accumulator[T]

Side-channel collector: compatibility memos push values during their compute, downstream readers pull them back with correct incremental invalidation. Use when a producer's ordinary return value (e.g. a `TypeResult`) is semantically distinct from log-like data it emits along the way (diagnostics, trace events, decorations).

Consumers that call `Memo::accumulated` from a `Memo` or `HybridMemo` compute
are invalidated whenever a producing compatibility memo recomputes and its push
set differs from the previous run — even when the producer's return value is
structurally equal. Driver/debug reads outside a memo compute do not register
that synthetic dependency. See the ADR: [Accumulator API](decisions/2026-04-20-accumulator-api.md).

**Local-only semantics.** `memo.accumulated(acc)` returns only the values `memo` itself pushed — not its dependencies. Transitive aggregation is the driver's job (see the [Scope-owned accumulator](cookbook.md#pattern-scope-owned-accumulator-lifecycle) cookbook pattern).

**Top-frame restriction.** `push` is only legal inside a compatibility `Memo` or `HybridMemo` compute. Pushing from an input, `Effect`, `EagerDerived` / `Reactive`, or outside any compute raises `Failure`.

### `Accumulator::new[T : Eq](rt~: Runtime, label? : String) -> Accumulator[T]`

Creates a runtime-owned accumulator. Lives until explicitly disposed (or until the runtime is dropped).

```moonbit nocheck
let diags : Accumulator[TypeDiagnostic] = Accumulator::new(rt~, label="diags")
```

Prefer `Scope::accumulator` when a scope is available — disposal is tied to the scope's lifecycle.

### `Scope::accumulator[T : Eq](self, label? : String) -> Accumulator[T]`

Creates an accumulator owned by a scope. When the scope is disposed, the accumulator is disposed automatically and cleared from the runtime.

```moonbit nocheck
let diags = scope.accumulator(label="typecheck_diags")
```

This is the preferred constructor for driver code where the accumulator's lifetime matches a larger unit of work (a chain rebuild, a compilation pass). See the [Scope-owned accumulator](cookbook.md#pattern-scope-owned-accumulator-lifecycle) cookbook pattern.

### `Accumulator::push[T](self, value: T) -> Unit raise Failure`

Appends `value` to the current compute's push buffer. Raises `Failure` if called:
- outside a tracked compute context
- from a non-`Memo` / non-`HybridMemo` top frame
- on a disposed accumulator

Pushes within a single compute are ordered by call sequence; `Memo::accumulated` returns them in that order.

```moonbit nocheck
if width < 0 {
  diags.push(TypeDiagnostic("negative width", span))
}
```

### `Accumulator::dispose(self) -> Unit`

Disposes the accumulator. Subsequent `push` calls raise `Failure`; subsequent `accumulated_peek` returns `[]`; subsequent `accumulated` / `accumulated_result` raise `Failure`. Idempotent.

### `Accumulator::id(self) -> AccumulatorId`

Returns the accumulator's unique identifier (for debug/introspection).

### `Accumulator::label(self) -> String?`

Returns the optional label provided at construction.

### `Accumulator::is_disposed(self) -> Bool`

Returns `true` after `dispose` has been called.

### `Accumulator::debug(self) -> String`

Returns a human-readable summary (label, id, disposed state, per-memo push counts).

Read methods live on the compatibility `Memo[T]` handle: see `Memo::accumulated`, `Memo::accumulated_peek`, and `Memo::accumulated_result` in the Derived / Memo section above.

---

## Revision

Logical timestamp used by introspection APIs (`Memo::changed_at`, `Memo::verified_at`, and `CellInfo` fields).

`Revision` supports direct ordering comparisons (`<`, `<=`, `>`, `>=`), which is what verification uses internally.

```moonbit
let changed = memo.changed_at()
let verified = memo.verified_at()
let changed_since_verified = changed > verified
```

---

## Durability

Classification used for verification skipping:

```moonbit
enum Durability {
  Low
  Medium
  High
}
```

Ordering: `Low < Medium < High`.
Direct comparisons (`<`, `<=`, `>`, `>=`) are supported.

Derived values inherit the minimum durability of their dependencies.

---

## CycleError

Cycle detection error returned by target `Result` reads such as `Derived::read()`, `Derived::get()`, `DerivedMap::read(key)`, and `ReachableDerived::read()`.

```moonbit
pub(all) suberror CycleError {
  CycleDetected(CellId, Array[CellId], Array[String?])
}
```

The variant carries: the cell that closes the cycle, the full untruncated
dependency path, and a parallel snapshot of labels captured at detection
time. Label snapshot length is capped at `MAX_CYCLE_DISPLAY_STEPS` (20) to
bound memory even for pathological long cycles; `path()` is always full.

### `CycleError::cell(self) -> CellId`

Returns the cell that caused the cycle.

```moonbit
match derived.read() {
  Ok(v) => println(v.to_string())
  Err(err) => println(err.cell().to_string())
}
```

### `CycleError::path(self) -> Array[CellId]`

Returns the full dependency path that forms the cycle.

```moonbit
match derived.read() {
  Ok(v) => println(v.to_string())
  Err(err) => {
    let path = err.path()
    println("Cycle length: " + path.length().to_string())
  }
}
```

### `CycleError::format_path(self) -> String`

Formats the cycle path as a human-readable string. Pure value — no runtime
handle required, because labels are captured at detection time.

```moonbit
match derived.read() {
  Ok(v) => println(v.to_string())
  Err(err) => println(err.format_path())
}
```

### Cycle Path Debugging

When a cycle is detected, `CycleError` now includes the full dependency path:

```moonbit
match derived.read() {
  Err(err) => {
    println("Cycle detected at: " + err.cell().to_string())
    println("Dependency path:")
    let path = err.path()
    for i = 0; i < path.length(); i = i + 1 {
      println("  " + path[i].to_string())
    }

    // Or use the formatted version
    println(err.format_path())
  }
  Ok(value) => use_value(value)
}
```

The `format_path()` method produces human-readable output. The quality of the output depends on whether labels were set at construction time:

Without labels:
```
Cycle detected: Cell[5] → Cell[7] → Cell[5]
```

With labels:
```
Cycle detected: price → tax → price
```

Labels are set via the `label` parameter on `Input`, `Derived`, `ReachableDerived`, `DerivedMap`, and `InputField` constructors. They have no runtime cost. **Always set labels on inputs and derived values** — unlabeled output is difficult to map back to specific cells in a large graph.

For long cycles (>20 cells), the output is truncated regardless of labels:

```
Cycle detected: Cell[0] → Cell[1] → Cell[2] → ... → Cell[19] → ...
```

---

## Introspection and Debugging

The target facades keep their surface focused on read/write semantics. Deeper
cell introspection currently lives on compatibility handles such as `Signal`
and `Memo`, or on `InputField` where field ownership requires `CellId`s.

### Compatibility Input Introspection

#### `Signal::id(self) -> CellId`

Returns the unique identifier for a compatibility input handle.

**Example:**
```moonbit
let sig = Signal(rt, 42)
let id = sig.id()
```

#### `Signal::durability(self) -> Durability`

Returns the durability level of this compatibility input handle (`Low`, `Medium`, or `High`).

**Example:**
```moonbit
let config = Signal(rt, "prod", durability=High)
inspect(config.durability(), content="High")
```

### Compatibility Derived Introspection

#### `Memo::id(self) -> CellId`

Returns the unique identifier for a compatibility derived handle.

#### `Memo::dependencies(self) -> Array[CellId]`

Returns the list of cells this compatibility derived handle currently depends on. Empty if it has never been computed.

**Example:**
```moonbit
let x = Signal(rt, 1)
let doubled = Memo(rt, () => x.get() * 2)
let observer = doubled.observe()
let _ = observer.get()
observer.dispose()
inspect(doubled.dependencies().contains(x.id()), content="true")
```

#### `Memo::changed_at(self) -> Revision`

Returns when this compatibility derived value last changed. Reflects backdating: if recomputation produces the same value, this timestamp is preserved.

#### `Memo::verified_at(self) -> Revision`

Returns when this compatibility derived value was last verified up-to-date.

### Runtime Introspection

#### `Runtime::dependents(self, id : CellId) -> Array[CellId]`

Returns the cell IDs that depend on the given cell (reverse edges / subscriber links). The returned array is a snapshot; modifying it does not affect the runtime.

Returns an empty array if the cell ID is invalid, out of bounds, or belongs to a different runtime — matching `cell_info` semantics.

**Example:**
```moonbit
let rt = Runtime()
let x = Signal(rt, 10)
let doubled = Memo(rt, () => x.get() * 2)
let observer = doubled.observe()
let _ = observer.get()
observer.dispose()
let deps = rt.dependents(x.id())
inspect(deps.contains(doubled.id()), content="true")
```

#### `Runtime::cell_info(self, id : CellId) -> CellInfo?`

Retrieves structured metadata for any cell. Returns `None` if the CellId is invalid.

**Example:**
```moonbit
match rt.cell_info(memo.id()) {
  Some(info) => {
    println("Changed at: " + info.changed_at.value.to_string())
    println("Dependencies: " + info.dependencies.length().to_string())
  }
  None => println("Cell not found")
}
```

### CellInfo Structure

```moonbit
pub struct CellInfo {
  pub label : String?
  pub id : CellId
  pub changed_at : Revision
  pub verified_at : Revision
  pub durability : Durability
  pub dependencies : Array[CellId]
  pub subscribers : Array[CellId]
}
```

For inputs, `dependencies` is empty. `subscribers` contains the cell IDs that depend on this cell (reverse edges).

---

## Per-Cell Callbacks

Target `InputField` exposes callbacks directly. For plain inputs and lazy
derived values, callbacks currently live on the compatibility `Signal` and
`Memo` handles.

### `Signal::on_change(self, f : (T) -> Unit) -> Unit`

Registers a callback fired when this compatibility input's value changes. Replaces any previously registered callback.

```moonbit
let count = Signal(rt, 0)
count.on_change(new_val => println("Count: " + new_val.to_string()))
```

### `Signal::clear_on_change(self) -> Unit`

Removes the registered `on_change` callback for this compatibility input.

```moonbit
count.clear_on_change()
```

### `Memo::on_change(self, f : (T) -> Unit) -> Unit`

Registers a callback fired when this compatibility derived value changes.

```moonbit
let doubled = Memo(rt, () => count.get() * 2)
doubled.on_change(new_val => update_ui(new_val))
```

### `Memo::clear_on_change(self) -> Unit`

Removes the registered `on_change` callback for this compatibility derived value.

```moonbit
doubled.clear_on_change()
```

**Behavior (on_change):**
- Fires after the cell's value changes
- Fires before `Runtime::on_change` callback
- During batch: fires at batch end for all changed cells

---

## Core Traits

### `RuntimeContext`

```moonbit
pub(open) trait RuntimeContext {
  runtime(Self) -> Runtime
}
```

Implemented by application context types that own an `incr` runtime. Target
constructor helpers such as `create_input` and `create_derived` use this trait.

### `Freshness`

```moonbit
pub(open) trait Freshness {
  is_fresh(Self) -> Bool
}
```

Implemented for `Input[T]`, `InputField[T]`, `Derived[T]`, and
`ReachableDerived[T]`.

### `InputFieldOwner`

```moonbit
pub(open) trait InputFieldOwner {
  cell_ids(Self) -> Array[CellId]
}
```

Implemented by structs that contain `InputField` fields. The returned `CellId`s
must be stable across calls and belong to the runtime of any scope they are
registered with.

```moonbit
struct SourceFile {
  path    : InputField[String]
  content : InputField[String]
  version : InputField[Int]
}

impl InputFieldOwner for SourceFile with cell_ids(self) {
  [self.path.id(), self.content.id(), self.version.id()]
}
```

Use `add_input_fields(scope, owner)` to register every field with a scope for
bulk disposal.

### Compatibility `Database`

```moonbit
pub(open) trait Database {
  runtime(Self) -> Runtime
}
```

Compatibility trait used by legacy helper functions such as `create_signal`,
`create_memo`, and `batch`.

### Compatibility `Readable`

```moonbit
pub(open) trait Readable {
  is_up_to_date(Self) -> Bool
}
```

Implemented for `Signal[T]`, `Memo[T]`, `HybridMemo[T]`, and `TrackedCell[T]`.

### Compatibility `Trackable`

```moonbit
pub(open) trait Trackable {
  cell_ids(Self) -> Array[CellId]
}
```

Implemented by structs that contain compatibility `TrackedCell` fields. The
single method returns the `CellId` of every cell owned by the struct, in a
stable order.

```moonbit
struct SourceFile {
  path    : TrackedCell[String]
  content : TrackedCell[String]
  version : TrackedCell[Int]
}

impl Trackable for SourceFile with cell_ids(self) {
  [self.path.id(), self.content.id(), self.version.id()]
}
```

`Trackable` is required by `gc_tracked`. The ordering of IDs must be deterministic across calls.

### Pipeline Traits (Experimental)

> **Experimental.** These traits may change or be removed in future versions.
> Defined in `pipeline/pipeline_traits.mbt` (`dowdiness/incr/pipeline` package).

```moonbit
pub(open) trait Sourceable {
  set_source_text(Self, String) -> Unit
  source_text(Self) -> String
}

pub(open) trait Parseable {
  parse_errors(Self) -> Array[String]
}

pub(open) trait Checkable {
  check_errors(Self) -> Array[String]
}

pub(open) trait Executable {
  run(Self) -> Array[String]
}
```

---

## MapRelation[K, V]

`MapRelation[K, V]` is the target-name facade over `FunctionalRelation[K, V]`.
It keeps the same Datalog map behavior: `insert` stages key-value changes,
`get` and `iter` read the current materialized map, and `delta_iter` reads the
current frontier during fixpoint rules.

```moonbit nocheck
let weights : MapRelation[(Int, Int), Int] = MapRelation(rt)
ignore(weights.insert((1, 2), 10))
rt.fixpoint()
```

---

## Helper Functions

Target helper functions take `Ctx : RuntimeContext` and construct target facade
handles from the context runtime. Compatibility helpers that take
`Db : Database` remain documented below.

### `create_input[Ctx : RuntimeContext, T](ctx: Ctx, value: T, durability?: Durability, label?: String) -> Input[T]`

Creates a target-name `Input` using the context runtime.

```moonbit nocheck
create_input(ctx, value)
create_input(ctx, value, durability=High, label="config")
```

### `create_input_field[Ctx : RuntimeContext, T](ctx: Ctx, value: T, durability?: Durability, label?: String) -> InputField[T]`

Creates a target-name `InputField` using the context runtime.

```moonbit nocheck
let path = create_input_field(ctx, "/src/main.mbt", label="SourceFile.path")
```

### `create_derived[Ctx : RuntimeContext, T : Eq](ctx: Ctx, f: () -> T raise Failure, label?: String) -> Derived[T]`

Creates a target-name lazy `Derived` using the context runtime.

```moonbit nocheck
let doubled = create_derived(ctx, () => input.get() * 2, label="doubled")
```

### `create_reachable_derived[Ctx : RuntimeContext, T : Eq](ctx: Ctx, f: () -> T raise Failure, label?: String) -> ReachableDerived[T]`

Creates a target-name reachable lazy derived value using the context runtime.

### `create_eager_derived[Ctx : RuntimeContext, T : Eq](ctx: Ctx, compute: () -> T) -> EagerDerived[T]`

Creates a target-name eager derived value using the context runtime.

### `create_derived_map[Ctx : RuntimeContext, K : Hash + Eq, V](ctx: Ctx, f: (K) -> V raise Failure, label?: String) -> DerivedMap[K, V]`

Creates a target-name keyed derived map using the context runtime.

### `add_input_fields[T : InputFieldOwner](scope: Scope, owner: T) -> Unit`

Registers every cell in an `InputFieldOwner` struct with `scope`, so disposing
the scope disposes all of the struct's input fields in one call.

```moonbit nocheck
let scope = Scope::new(rt)
let fields = MyInputFields(rt)
add_input_fields(scope, fields)
scope.dispose()
```

### Scope Target Constructors

`Scope` also exposes target constructor methods that automatically register
owned cells for disposal:

- `scope.input(value, durability?, label?) -> Input[T]`
- `scope.input_field(value, durability?, label?) -> InputField[T]`
- `scope.derived(f, label?) -> Derived[T]`
- `scope.reachable_derived(f, label?) -> ReachableDerived[T]`
- `scope.eager_derived(compute) -> EagerDerived[T]`
- `scope.derived_map(f, label?) -> DerivedMap[K, V]`
- `scope.accumulator(label?) -> Accumulator[T]`

### Compatibility helpers

The helpers below take `Db : Database` and return compatibility handles.

### `create_signal`

Creates a new `Signal` using the database's runtime.

```moonbit nocheck
create_signal(db, value)
create_signal(db, value, durability=High, label="config")
```

### `create_memo[Db : Database, T : Eq](db: Db, f: () -> T raise Failure, label? : String) -> Memo[T]`

Creates a memo using `db.runtime()`. Uses `Memo::new` internally — requires `T : Eq` for backdating via structural equality. For revision-based backdating use `Memo::new_memo` directly; for no backdating use `Memo::new_no_backdate` directly.

### `create_hybrid_memo[Db : Database, T : Eq](db: Db, f: () -> T raise Failure, label? : String) -> HybridMemo[T]`

Creates a hybrid memo using `db.runtime()`.

```moonbit nocheck
let h = create_hybrid_memo(app, () => signal.get() * 2, label="doubled")
```

### `create_memo_map[Db : Database, K : Hash + Eq, V](db: Db, f: (K) -> V raise Failure, label? : String) -> MemoMap[K, V]`

Creates a memo map using `db.runtime()`. Each key is memoized independently.

### `create_accumulator[Db : Database, T : Eq](db: Db, label? : String) -> Accumulator[T]`

Creates a runtime-owned accumulator using `db.runtime()`. Prefer `Scope::accumulator` for scope-bound lifetimes.

```moonbit nocheck
let diags = create_accumulator(app, label="diags")
```

### `create_tracked_cell`

Creates a new `TrackedCell` using the database's runtime.

```moonbit nocheck
create_tracked_cell(db, value)
create_tracked_cell(db, value, durability=High, label="SourceFile.path")
```

### `create_scope[Db : Database](db: Db) -> Scope`

Creates a root `Scope` using the database's runtime. Target-style code can also
construct a scope directly with `Scope::new(ctx.runtime())`.

### `add_tracked[T : Trackable](scope: Scope, tracked: T) -> Unit`

Compatibility helper for `TrackedCell` owners. Target-name code should use
`add_input_fields(scope, owner)`.

```moonbit nocheck
let scope = create_scope(app)
let tracked = MyTracked(app)
add_tracked(scope, tracked)
scope.dispose()
```

### `gc_tracked[T : Trackable](rt: Runtime, tracked: T) -> Unit`

Deprecated no-op kept for source compatibility; use `add_tracked(scope,
tracked)` instead for lifecycle management. `TrackedCell` fields are leaves of
the dependency graph, so marking them as GC roots keeps nothing alive. The
target names for new code are `InputField`, `InputFieldOwner`, and
`add_input_fields`.

```moonbit
add_tracked(scope, my_tracked_struct)
```

```moonbit
gc_tracked(rt, my_tracked_struct)
```

### `batch[Db : Database](db: Db, f: () -> Unit raise?) -> Unit raise?`

Runs a batch using `db.runtime()`, including rollback-on-raise semantics.
This is the Database helper form of `rt.batch(...)`.

```moonbit
fn update_cart[Db : Database](
  app : Db,
  price : Input[Int],
  quantity : Input[Int],
) -> Unit raise? {
  @incr.batch(app, fn() raise {
    price.set(100)
    quantity.set(3)
  })
}
```

### `batch_result[Db : Database](db: Db, f: () -> Unit raise?) -> Result[Unit, Error]`

Runs a batch using `db.runtime()` and returns raised errors as `Result`.
This is the Database helper form of `rt.batch_result(...)`.

```moonbit
suberror BatchStop {
  Stop
}

fn update_cart_result[Db : Database](
  app : Db,
  price : Input[Int],
  quantity : Input[Int],
) -> Result[Unit, Error] {
  let res = @incr.batch_result(app, fn() raise {
    price.set(100)
    quantity.set(3)
    raise Stop
  })
  inspect(res is Err(_), content="true")
  res
}
```

---

## Type Constraints

### Where `Eq` is used

`Eq` is used in two distinct optimizations:

**Same-value optimization (`Input::set`, `InputField::set`):** Before recording a change, the library compares the new value against the current one. If they are equal, the call is treated as a no-op: the global revision counter is not incremented and downstream derived values are not invalidated. This avoids spurious recomputation when an input is set to the value it already holds. Compatibility `Signal::set` and `TrackedCell::set` use the same rule.

**Backdating (`Derived`, `ReachableDerived`, `Memo::new`):** After a derived value recomputes, the library compares the new result against the previous cached value. If they are equal, the underlying memo's `changed_at` timestamp is kept at its previous value rather than advanced to the current revision. Any cell that depends on this derived value therefore sees no change, and its own verification is skipped entirely.

**Custom `Eq` implementations:** If your type derives `Eq` with fields intentionally excluded — for example, a generation counter or metadata field that shouldn't influence downstream computation — backdating will treat updates to those fields as no-ops. This is correct and useful (the computation result hasn't changed semantically), but it must be intentional: if you rely on those excluded fields inside a derived compute function, you will get stale results. Only exclude fields from `Eq` that are never read by any derived value.

```moonbit
// Safe: gen is never read by any derived value
struct Versioned {
  value : Int
  gen   : Int  // excluded from Eq by custom impl
}

// Dangerous: gen IS read by the derived value, but excluded from Eq causes stale cache
let m = Derived(rt, () => src.get().gen)  // will not recompute when gen changes
```

### Backdating strategies

The backdate decision — whether a recomputed value counts as "changed" — is captured at construction, not at read time. Target `Derived` and `ReachableDerived` use structural `Eq`. Compatibility `Memo` exposes three constructors for different strategies:

| Constructor | Constraint | Backdate logic |
|---|---|---|
| `Memo::new` | `T : Eq` | `a == b` (structural equality) |
| `Memo::new_memo` | `T : BackdateEq` | `a.backdate_equal(b)` (revision comparison by default; override for custom logic) |
| `Memo::new_no_backdate` | none | always `false` — never backdates |

Compatibility `Memo` read methods have **no additional** trait constraint; the equality decision is baked into the closure at construction. Target facade read constraints are listed below.

Use `BackdateEq` through the compatibility `Memo::new_memo` constructor when structural `Eq` is too expensive (e.g. comparing large collections) and you can instead embed a `Revision` in the value that tracks when its content last changed. Use `Memo::new_no_backdate` when downstream derived values always need to recompute, or when `T` has no `Eq` instance.

### Constraint reference

| API | Constraint |
|---|---|
| `Input::set`, `InputField::set` | `T : Eq` |
| `Input`, `Input::get`, `Input::peek`, `Input::force_set` | none |
| `InputField`, `InputField::get`, `InputField::peek`, `InputField::force_set` | none |
| `Derived`, `ReachableDerived` | `T : Eq` |
| `Derived::get`, `read`, `watch` | none |
| `ReachableDerived::get`, `read`, `watch` | `T : Eq` |
| `DerivedMap::get`, `read`, `read_or`, `read_or_else` | `K : Hash + Eq`, `V : Eq` |
| `DerivedMap::has_cached`, `sweep_cache` | `K : Hash + Eq` |
| `Memo::new` | `T : Eq` |
| `Memo::new_memo` | `T : BackdateEq` (supertrait: `HasChangedAt`) |
| `Memo::new_no_backdate` | none |
| `Memo::get`, `get_result`, `get_or`, `get_or_else` | none |
| `MemoMap::get`, `get_result`, `get_or`, `get_or_else` | `K : Hash + Eq`, `V : Eq` |
| `MemoMap::contains` | `K : Hash + Eq` |
| `Signal::set` | `T : Eq` |
| `Signal::new`, `get`, `get_result`, `set_unconditional` | none |
| `TrackedCell::set` | `T : Eq` |
| `TrackedCell::new`, `get`, `get_result`, `set_unconditional` | none |
