# API Reference

> **Checked companion:** [`api_reference_examples.mbt.md`](api_reference_examples.mbt.md)
> contains literate tests that pin the target facade snippets in this document
> (`Derived`, `DerivedMap`, `ReachableDerived`, `MapRelation`, `Scope` /
> `RuntimeContext` helpers, and `CycleError`) plus derived-event listener
> lifecycle, compatibility introspection/callbacks, and the compatibility-only
> accumulator push path. The README and getting-started target snippets are
> covered by [`target_api_examples.mbt.md`](target_api_examples.mbt.md).

Reference for the most commonly used public APIs in `incr`. This is not exhaustive — the authoritative surface is in `pkg.generated.mbti` and `cells/pkg.generated.mbti`. APIs surfaced here: `Runtime`, `Input`, `Derived`, `ReachableDerived`, `DerivedMap`, `InputField`, `Accumulator`, `DerivedEvent`, `CycleError`, the `RuntimeContext`/`Database`/`Freshness`/`Readable`/`InputFieldOwner`/`Trackable` traits, and the top-level helper functions. The legacy Memo-family types (`Memo`, `MemoMap`, `HybridMemo`) have been removed in v0.12.0 — use `Derived`, `DerivedMap`, and `ReachableDerived` respectively. Other legacy types (`Signal`, `TrackedCell`, `Reactive`, `FunctionalRelation`) remain re-exported from `@incr` for source compatibility.

> **Recommended Pattern:** Use the `RuntimeContext` trait to encapsulate your
> `Runtime` in an application context type. This makes your API cleaner and
> hides implementation details. Compatibility helpers still accept `Database`.
> See the [Helper Functions](#helper-functions) section and [API Design Guidelines](design/api-design-guidelines.md) for details.

> **Target-name migration:** Target facade types (`Derived`, `DerivedMap`, `ReachableDerived`) are the recommended names. The legacy Memo-family types (`Memo`, `MemoMap`, `HybridMemo`) have been removed in v0.12.0. Other legacy compatibility names (`TrackedCell`, `Reactive`, `Observer`, `FunctionalRelation`, `Readable`, `Trackable`, `Database`) remain re-exported from `@incr` for source compatibility. `Signal` was removed in v0.14.0 — use `Input`.

## Read Vocabulary Migration

Target reads use `read` for permissive outside-graph reads and `get` for strict
tracked-context reads. The target facades (`Derived`, `DerivedMap`, `ReachableDerived`) provide the full read vocabulary. The legacy `Memo`, `HybridMemo`, and `MemoMap` types have been removed in v0.12.0.

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

Call `Runtime()` for the default constructor, or `Runtime(on_change=...)` to
install the committed-change callback during construction.

### `Runtime::batch(self, f: () -> Unit raise?) -> Unit raise?`

Executes `f` with batched input updates.

Inside a batch, `Input::set()` and `Input::force_set()` writes are deferred and committed when the outermost batch exits.

The checked companion covers batched committed writes and rollback in
[`api_reference_examples.mbt.md`](api_reference_examples.mbt.md).

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

Dangerous pattern: calling an aborting read such as `read_or_abort()` inside a
batch can leave batch state corrupted if it hits a cycle. Safer pattern: call a
`Result`-returning read such as `read()`, then raise the returned error so the
batch rollback path can run.

### `Runtime::batch_result(self, f: () -> Unit raise) -> Result[Unit, Error]`

Executes a batch and returns raised errors as `Result` instead of re-raising.
Like `Runtime::batch`, this handles raised errors only; `abort()` still escapes, is not converted to `Err`, and leaves the runtime in the same inconsistent state described above.
The `f` parameter was tightened from `raise?` (error-polymorphic) to `raise`
(concrete `Error`) in PR #293 as part of the `try?` deprecation migration.
Non-raising callers continue to work (`noraise` ⊂ `raise Error`);
callers raising a custom error continue to work (any suberror lifts to `Error`).
Downstream wrappers accepting `f: () -> Unit raise?` that forward to
`batch_result` must change to `f: () -> Unit raise` (or `f: () -> Unit raise Error`).

The checked companion covers `batch_result` returning `Err` and rolling back
pending writes in [`api_reference_examples.mbt.md`](api_reference_examples.mbt.md).

### `Runtime::record_batch_rollback(self, cell_id: CellId, rollback: () -> Unit) -> Unit`

Registers an extension-owned rollback callback for the current batch frame. This
is for mutable side structures that are not themselves ordinary `Input` /
`InputField` cells: indexes, slot maps, metadata tables, or caches that must be
restored if `Runtime::batch` / `Runtime::batch_result` exits through a raised
error.

If no user batch frame is active, this is a no-op. If a batch frame is active,
only the first callback registered for a given `cell_id` in that frame is kept;
use a stable cell ID for the rollback unit and capture the pre-batch state on the
first mutation. That unit can be a whole external structure, an existing value
slot, or a per-entry token whose creation is not itself an untracked failed-batch
side effect. Rollback callbacks run in reverse registration order when a raised
error aborts the frame. An outermost successful batch discards the rollback log;
a successful nested batch merges its rollback entries into the parent frame so an
outer failure can still restore them.

Prefer modeling state as `Input` / `InputField` when possible. Those writes
already rollback through the normal batch machinery. `record_batch_rollback` is
not an undo/redo API and does not make `abort()` recoverable; it only composes
extension-owned side structures with raised-error batch rollback.

The cookbook companion includes a checked external-map insertion/replacement
example in
[`cookbook_examples.mbt.md`](cookbook_examples.mbt.md#batch-callbacks-read-isolation-and-extension-rollback).

### `Runtime::set_on_change(self, f: () -> Unit) -> Unit`

Registers the **singleton** on-change callback fired when the runtime records a
committed change. Re-registering replaces the previous singleton callback in
place (its registration position is preserved). It coexists with any additive
listeners added via `add_on_change_listener`.

The checked companion covers committed-change callbacks, batching, no-op sets,
and `clear_on_change` in
[`api_reference_examples.mbt.md`](api_reference_examples.mbt.md).

Behavior:
- Outside batch: fires immediately after each committed change
- Inside batch: fires once at batch end if at least one input actually changed
- No fire for no-op `Input::set()` (same value)

### `Runtime::clear_on_change(self) -> Unit`

Removes the singleton change callback. Idempotent; additive listeners are
unaffected.

See the checked callback examples in
[`api_reference_examples.mbt.md`](api_reference_examples.mbt.md).

### `Runtime::add_on_change_listener(self, f: () -> Unit) -> ListenerId`

Adds a **composable** on-change listener and returns a `ListenerId` for removal.
Multiple additive listeners (and the singleton) coexist on one runtime; use this
when several observers — a UI integration, a profiler, a test tap — must share a
runtime without clobbering each other.

- **Ordering:** listeners fire in registration order on every committed change.
  The `set_on_change` singleton fires at the position where its slot is currently
  registered.
- **Mutation during a callback:** allowed. Adding or removing listeners from
  inside an on-change callback takes effect on the *next* fire — the current fire
  iterates a snapshot. This is why on-change registration is **not** phase-guarded
  (unlike the derived-event hook, which buffers events).

### `Runtime::remove_on_change_listener(self, id: ListenerId) -> Unit`

Removes the additive on-change listener identified by `id`. Idempotent — an
unknown or already-removed id is a no-op.

### Singleton vs additive on-change

Use `set_on_change` for a single, owner-controlled callback that should *replace*
on re-registration (the back-compat "the" callback). Use `add_on_change_listener`
for composable observers that must coexist and are individually removable by id.


### `Runtime::on_derived_event(self, f: (DerivedEvent) -> Unit) -> Unit raise Failure`

> Renamed in 0.8.0 from `Runtime::on_memo_event`; older ADRs may use that name.

Registers the **singleton** derived-event listener: re-registering replaces the
previous singleton in place. It coexists with any additive listeners added via
`add_derived_event_listener`.

The checked companion covers listener registration and clearing in
[`api_reference_examples.mbt.md`](api_reference_examples.mbt.md); cookbook
examples show richer event logging patterns.

The listener is a synchronous, non-raising callback. If a driver needs async
logging, enqueue inside the callback and let another part of the driver drain
that queue.

Mutation guard:
- `on_derived_event` raises `Failure` while an operation is in flight
- Rejected windows include active recompute, open batch, non-idle propagation
  phase, buffered-but-undrained events, and listener drain reentry
- Register listeners between top-level operations, before starting the graph
  work you want to observe

### `Runtime::clear_derived_event_listener(self) -> Unit raise Failure`

> Renamed in 0.8.0 from `Runtime::clear_memo_event_listener`; older ADRs may use that name.

Removes the singleton derived-event listener. Idempotent; additive listeners are
unaffected. It has the same mutation guard as `on_derived_event`; clear it
between operations, not from inside compute, `on_change`, or a derived-event
listener.

The checked companion covers `clear_derived_event_listener` in
[`api_reference_examples.mbt.md`](api_reference_examples.mbt.md).

### `Runtime::add_derived_event_listener(self, f: (DerivedEvent) -> Unit) -> ListenerId raise Failure`

Adds a **composable** derived-event listener and returns a `ListenerId` for
removal. Multiple additive listeners (and the singleton) coexist on one runtime.

- **Ordering:** delivery is *event-major* — for each buffered event (in
  pull-verification traversal order), every listener fires in registration order
  before the next event.
- **Mutation guard:** carries the same idle guard as `on_derived_event` and
  raises `Failure` while an operation is in flight. The derived-event hook buffers
  events, so listener mutation (including from inside a listener — the drain
  reentry window) is rejected; register/remove between top-level operations.

### `Runtime::remove_derived_event_listener(self, id: ListenerId) -> Unit raise Failure`

Removes the additive derived-event listener identified by `id`. Idempotent within
the safe window — an unknown id is a no-op; carries the same idle guard, so a
mid-flight call raises `Failure`.

### `ListenerId`

Opaque handle returned by `add_on_change_listener` and
`add_derived_event_listener`, passed back to the matching `remove_*` method to
detach one listener. An id carries its originating `RuntimeId` alongside a
per-runtime counter shared across both hook surfaces, so a mismatched `remove`
(wrong registry *or* wrong runtime) is a harmless no-op rather than an accidental
detachment. Like `RuntimeId`, it is an introspection/debug identity, not a stable
application key.

### `DerivedEvent`

`DerivedEvent` is the public event payload delivered by
`Runtime::on_derived_event`.

> Renamed in 0.8.0 from `MemoEvent` with payloads `MemoEnteringEvent` /
> `MemoCompletedEvent` / `MemoAbortedEvent`; older ADRs may use those names.

```mbt nocheck
///|
pub(all) enum DerivedEvent {
  EnteringCompute(DerivedEnteringEvent)
  Completed(DerivedCompletedEvent)
  Aborted(DerivedAbortedEvent)
}
```

`DerivedEnteringEvent` fields:
- `cell_id`: derived cell entering recompute
- `started_revision`: runtime revision captured at recompute entry

`DerivedCompletedEvent` fields:
- `cell_id`: derived cell that completed
- `elapsed_ns`: best-effort elapsed duration for this recompute
- `started_revision`: same entry revision carried from `EnteringCompute`
- `verified_at`: verification revision after commit
- `changed_at`: change revision after backdating
- `backdated`: `true` when the recompute produced an equal value and preserved
  `changed_at`

`DerivedAbortedEvent` fields:
- `cell_id`: derived cell whose compute raised a catchable `Error`
- `elapsed_ns`: best-effort elapsed duration before the raise
- `started_revision`: same entry revision carried from `EnteringCompute`
- `error`: the captured `Error`; stringify in the driver if needed

Events are best-effort for catchable raises. A direct `abort()` inside a compute
closure is uncatchable and may leave an unmatched `EnteringCompute` event.

---

## Input[T]

`Input[T]` is the type for externally controlled values.

### `Input[T](rt: Runtime, initial: T, durability? : Durability, label? : String) -> Input[T]`

Creates an input. Both `durability` (default `Low`) and `label` are optional.

The `label` string is used in cycle error messages and `Runtime::cell_info` output. Without a label, cells appear as `Cell[42]` in diagnostics. **Prefer always setting a label** — it has no runtime cost and makes debugging significantly easier.

The checked companion covers direct `Input` construction, labels, durability,
and derived reads in [`api_reference_examples.mbt.md`](api_reference_examples.mbt.md).

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

### `Input::derived[T, U : Eq](self, f: (T) -> U, label?: String) -> Derived[U]`

Creates a new `Derived[U]` from this input by applying `f` to the current
value on each read. Provides pipeline-uniform `.derived(...)` access from an
input, replacing the `scope.derived(() => f(input.get()))` pattern with a
chained `input.derived(f).map(g)`.

Uses equality-based backdating: when recomputation produces a value equal to
the previous output, downstream dependents skip recomputation.

### `Input::derived_no_backdate[T, U](self, f: (T) -> U, label?: String) -> Derived[U]`

Creates a new `Derived[U]` from this input by applying `f` to the current
value on each read, without equality-based backdating. Each recomputation
advances the changed-at revision unconditionally, even when the output
equals the previous value. Accepts output types that do not implement `Eq`.



## InputField[T] / TrackedCell[T]

`InputField[T]` is the target-name field-level input facade. `TrackedCell[T]` remains available as the compatibility handle.

### `InputField[T](rt: Runtime, initial: T, durability?: Durability, label?: String) -> InputField[T]`

Creates a field-level input. Both `durability` (default `Low`) and `label` are optional. A label like `"SourceFile.path"` identifies which field of which struct caused a problem.

The checked companion covers labeled `InputField` construction, durability,
`cell_info`, and derived reads in
[`api_reference_examples.mbt.md`](api_reference_examples.mbt.md).

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
- `TrackedCell::get_result()` always returns `Ok(value)` and exists for legacy symmetry with `Memo::get_result()` (removed in v0.12.0).
- `TrackedCell::as_input()` returns the underlying `Input[T]`.

---

## Derived[T]

`Derived[T]` is the target-name lazy derived-value facade. The legacy `Memo[T]` type has been removed in v0.12.0.

### `Derived[T : Eq](rt: Runtime, compute: () -> T raise Failure, label? : String) -> Derived[T]`

Creates a lazily evaluated derived value using structural equality (`T : Eq`) for backdating. When a recomputation produces a value equal to the previous one, the derived value's `changed_at` timestamp is preserved rather than advanced, preventing unnecessary downstream invalidation.

The checked companion covers `Derived` construction, `map`, `map2`, `map3`,
`map_no_backdate`, labeled cells, inside-compute `get_or_abort`, and outside-graph
`read` / `read_or_abort` in
[`api_reference_examples.mbt.md`](api_reference_examples.mbt.md).

### `Derived::fallible[V : Eq, E : Eq](rt: Runtime, compute: () -> Result[V, E], label? : String) -> Derived[Result[V, E]]`

Creates a derived value whose `compute` is **noraise**: a recoverable, domain-specific failure is expressed in the value as `Result[V, E]`, never raised. The error then participates in caching and `Eq`-based backdating like any other value, and reads surface only graph failures (cycles/disposal), never an uncatchable abort. Prefer this over `Derived` when `Result` is the domain value shape. For custom enums or diagnostics payloads, use an ordinary `Derived[T]` and keep the recoverable failure in `T`; this is the same [domain errors as values](cookbook.mbt.md#pattern-domain-errors-as-values) pattern. A `raise Failure` from a plain `Derived` compute is a *defect*, not a domain-error channel — see [Honest Read-Error Ownership](design/specs/2026-05-28-honest-read-error-ownership.md).

### `Derived::derived_no_backdate[T](rt: Runtime, compute: () -> T raise Failure, label?: String) -> Derived[T]`

Creates a lazy derived value without equality-based backdating. Each
recomputation advances the changed-at revision unconditionally, even when the
output equals the previous value. Accepts output types that do not implement
`Eq`.

This is the target-facade constructor for the alternate backdating strategy.

### `Derived::map_no_backdate[U](self, f: (T) -> U, label? : String) -> Derived[U]`

Transforms this derived value into another derived value on the same `Runtime`.
The returned cell reads `self` with the strict tracked-context read, so it keeps
the normal dependency edge and updates when the source changes. The mapped value
does **not** backdate, so `U` does not need to implement `Eq`. The optional
`label` is attached to the returned cell for introspection.

### `Derived::map2_no_backdate[T2, U](self, other: Derived[T2], f: (T, T2) -> U, label? : String) -> Derived[U]`

Combines two derived values into another derived value on `self`'s `Runtime`.
The returned cell reads both inputs with strict tracked-context reads, so it
updates when either input changes. It aborts if `other` belongs to a different
`Runtime`. The mapped value does **not** backdate, so `U` does not need to
implement `Eq`. The optional `label` is attached to the returned cell for
introspection.

### `Derived::map3_no_backdate[T2, T3, U](self, second: Derived[T2], third: Derived[T3], f: (T, T2, T3) -> U, label? : String) -> Derived[U]`

Combines three derived values into another derived value on `self`'s `Runtime`.
It aborts if `second` or `third` belongs to a different `Runtime`. Like
`map_no_backdate` and `map2_no_backdate`, this uses no-backdate recomputation so
`U` does not need to implement `Eq`. The optional `label` is attached to the
returned cell for introspection.


### `Derived::map[U : Eq](self, f: (T) -> U, label? : String) -> Derived[U]`

Transforms this derived value into another derived value on the same `Runtime`
and keeps `Eq`-based backdating for the mapped output. Use this when the mapped
type implements `Eq` and downstream recomputation should be skipped when a
source change leaves the mapped value equal to its previous value. Use
`Derived::map_no_backdate` instead when `U` cannot implement `Eq`.

The optional `label` is attached to the returned cell for introspection.

### `Derived::map2[T2, U : Eq](self, other: Derived[T2], f: (T, T2) -> U, label? : String) -> Derived[U]`

Combines two derived values into another derived value on `self`'s `Runtime`
and keeps `Eq`-based backdating for the mapped output. It aborts if `other`
belongs to a different `Runtime`.

### `Derived::map3[T2, T3, U : Eq](self, second: Derived[T2], third: Derived[T3], f: (T, T2, T3) -> U, label? : String) -> Derived[U]`

Combines three derived values into another derived value on `self`'s `Runtime`
and keeps `Eq`-based backdating for the mapped output. It aborts if `second` or
`third` belongs to a different `Runtime`.



### `Derived::get(self) -> Result[T, ReadError]`

Strict graph read. It must be called inside another derived compute function, where it records a dependency. It aborts outside a tracked context and returns `Err(ReadError)` for mechanism failures — `Cycle` for cycles, `Disposed` for a read of this disposed cell.

### `Derived::get_or_abort(self) -> T`

Strict graph read that aborts on invalid context or any `ReadError`.

### `Derived::read(self) -> Result[T, ReadError]`

Permissive read. It works from top-level code, tests, event handlers, and callbacks, and it still records a dependency when called inside a tracked compute. The read channel carries only *mechanism* failures (`ReadError = Cycle | Disposed`); a domain failure lives in the value (`Derived::fallible` for `Result`, or a custom domain value). A read of a directly-disposed cell returns `Err(Disposed(_))` rather than aborting.

The checked companion covers `Derived::read()` returning `Result` and
cycle-safe handling in [`api_reference_examples.mbt.md`](api_reference_examples.mbt.md).

### `Derived::read_or_abort(self) -> T`

Permissive read that aborts on any `ReadError`.

### `Derived::watch(self) -> Watch[T]`

Creates a long-lived outside-graph reader. The `Watch` is a GC root until disposed, and `watch.read()` returns `Result[T, ReadError]`.

### `Derived::is_fresh(self) -> Bool`

Returns whether this derived value is verified at the current revision.


### `Derived::accumulated(self, acc: Accumulator[A]) -> Result[Array[A], ReadError] raise Failure`

Returns the values this derived cell pushed into `acc` during its most recent compute,
in push order. When called from a `Derived` or `ReachableDerived` compute frame and the
read succeeds, it records a synthetic dependency so that caller reinvalidates
when the push set changes — even when the derived cell's ordinary return value is
unchanged. Outside a derived-cell compute, it returns data without registering a
dependency. A failure in the underlying verify that was never caught as a cycle error is
never returned.

The read channel reports cycles as `Err(ReadError::Cycle(_))` and a directly
disposed target derived as `Err(ReadError::Disposed(_))`. Domain failures returned
as a value (for example `Derived[Result[V, E]]`) are successful computes; pushes
from that compute are committed and returned as `Ok(...)`. A target compute that
raises `Failure` is a defect and aborts. Disposed accumulators and
static-Derived recompute misuse raise `Failure`; cross-runtime reuse aborts.


## DerivedMap[K, V]

`DerivedMap[K, V]` is the target-name keyed derived facade. The legacy `MemoMap[K, V]` has been removed in v0.12.0.

### `DerivedMap[K : Hash + Eq, V](rt: Runtime, compute: (K) -> V raise Failure, label? : String) -> DerivedMap[K, V]`

Creates an empty derived map. No per-key derived value is allocated until first read of that key.

The checked companion covers `DerivedMap` construction, lazy keyed reads,
strict tracked reads, fallback reads, and cache maintenance in
[`api_reference_examples.mbt.md`](api_reference_examples.mbt.md).

### `DerivedMap::fallible[K : Hash + Eq, V, E](rt: Runtime, compute: (K) -> Result[V, E], label? : String) -> DerivedMap[K, Result[V, E]]`

Keyed counterpart to `Derived::fallible`: each key's recoverable domain failure is expressed in the value as `Result[V, E]` (the `compute` is **noraise**). For non-`Result` diagnostics, keep the custom domain status in the map value by the same [domain errors as values](cookbook.mbt.md#pattern-domain-errors-as-values) pattern. See [Honest Read-Error Ownership](design/specs/2026-05-28-honest-read-error-ownership.md).

### `DerivedMap::read[K : Hash + Eq, V : Eq](self, key: K) -> Result[V, ReadError]`

Permissive read for `key`. It works outside the graph and records a per-key dependency when called inside a tracked compute. Returns `Err(Disposed(_))` if the per-key memo was gc-disposed while the map still caches the entry, or if the owning scope disposed the map.

### `DerivedMap::read_or_abort[K : Hash + Eq, V : Eq](self, key: K) -> V`

Permissive read that aborts on any `ReadError`.

### `DerivedMap::get[K : Hash + Eq, V : Eq](self, key: K) -> Result[V, ReadError]`

Strict graph read for `key`. It records the per-key dependency inside a tracked compute, aborts outside a tracked context, and returns `Err(ReadError)` for mechanism failures (cycle / disposed per-key memo).

### `DerivedMap::get_or_abort[K : Hash + Eq, V : Eq](self, key: K) -> V`

Strict graph read that aborts on invalid context or any `ReadError`.

### `DerivedMap::read_or[K : Hash + Eq, V : Eq](self, key: K, fallback: V) -> V`

Returns the value for `key`, or `fallback` if a `ReadError` is detected.

### `DerivedMap::read_or_else[K : Hash + Eq, V : Eq](self, key: K, fallback: (ReadError) -> V) -> V`

Returns the value for `key`, or computes a fallback from the read error.

### `DerivedMap::has_cached[K : Hash + Eq, V](self, key: K) -> Bool`

Returns whether a cached entry exists for `key`.

### `DerivedMap::cache_len(self) -> Int`

Returns the number of cached entries.

### `DerivedMap::sweep_cache[K : Hash + Eq, V](self) -> Int`

Removes cached entries whose underlying cells have been disposed.

### `DerivedMap::clear_cache(self) -> Unit`

Clears all cached entries.

---

## ReachableDerived[T]

`ReachableDerived[T]` is a lazy derived value that participates in reachability propagation so eager/rooted downstream cells can keep its upstream graph reachable across `Runtime::gc()` sweeps. The legacy `HybridMemo[T]` type has been removed in v0.12.0.

### `ReachableDerived[T : Eq](rt: Runtime, compute: () -> T raise Failure, label? : String) -> ReachableDerived[T]`

Creates a reachable derived value. It does not make the value eager; recomputation still happens on read.

The checked companion covers `ReachableDerived` construction, reads, watches,
and GC reachability in [`api_reference_examples.mbt.md`](api_reference_examples.mbt.md).

### `ReachableDerived::get[T : Eq](self) -> Result[T, ReadError]`

Strict graph read. It must be called inside another derived compute function, aborts outside a tracked context, and returns `Err(ReadError)` for mechanism failures (cycle / disposed).

### `ReachableDerived::get_or_abort[T : Eq](self) -> T`

Strict graph read that aborts on invalid context or any `ReadError`.

### `ReachableDerived::read[T : Eq](self) -> Result[T, ReadError]`

Permissive read. It works outside the graph and records a dependency when called inside a tracked compute. A read of a directly-disposed cell returns `Err(Disposed(_))` rather than aborting.

### `ReachableDerived::read_or_abort[T : Eq](self) -> T`

Permissive read that aborts on any `ReadError`.

### `ReachableDerived::watch[T : Eq](self) -> Watch[T]`

Creates a long-lived outside-graph reader. The `Watch` is a GC root until disposed.

### `ReachableDerived::is_fresh(self) -> Bool`

Returns whether this reachable derived value is verified at the current revision.


## AcceptedDerived[V, E]

A success-gated derived authoring primitive. A fallible candidate `Result[V, E]` is computed from current inputs; only `Ok(v)` candidates that differ from the last accepted value advance the *accepted* state. On `Err(e)` the previous accepted value is **retained** while the *current* channel still reports the error — keeping diagnostics honest without destroying the last good value that downstream UI, preview, or indexing stages need. A graph `ReadError` (cycle/disposal) does not drive the state machine; it surfaces on the read channel and leaves the retained accepted value untouched. See [the design spec](design/specs/2026-06-05-committed-derived.md).

### `AcceptedDerived[V : Eq, E : Eq](rt: Runtime, compute: () -> Result[V, E], label? : String) -> AcceptedDerived[V, E]`

Builds an `AcceptedDerived` that owns its candidate compute. Like `Derived::fallible`, the compute is **noraise** — recoverable domain errors live in the `Result`, never raised.

### `AcceptedDerived::from_candidate[V : Eq, E](candidate: Derived[Result[V, E]], label? : String) -> AcceptedDerived[V, E]`

Wraps an existing candidate `Derived`. The candidate's lifecycle stays with the caller — `dispose()` does not dispose it.

### `Scope::accepted_derived[V : Eq, E : Eq](self, compute: () -> Result[V, E], label? : String) -> AcceptedDerived[V, E]`

Scope-owned convenience mirroring `Scope::derived`; the result lives in a child scope and is disposed with the parent.

#### `BackdateEq` tier — acceptance by revision identity

For candidate value types that are **not** `Eq` but carry a `Revision` (so they implement `BackdateEq`). Acceptance is gated by `BackdateEq::backdate_equal` (revision identity) instead of structural `Eq`, mirroring standard backdating vs `Derived::with_backdate`. Use this when the candidate holds closures or other non-`Eq` data — e.g. a projected document whose stable identity is a revision counter. `E : Eq` is retained, so the current channel still backdates on a repeated equal error.

### `AcceptedDerived::accepted_memo[V : BackdateEq, E : Eq](rt: Runtime, compute: () -> Result[V, E], label? : String) -> AcceptedDerived[V, E]`

`BackdateEq` companion of `AcceptedDerived(...)`: owns its candidate compute, accepts by revision identity.

### `Scope::accepted_memo[V : BackdateEq, E : Eq](self, compute: () -> Result[V, E], label? : String) -> AcceptedDerived[V, E]`

`BackdateEq` companion of `Scope::accepted_derived`: scope-owned, accepts by revision identity.

### `AcceptedDerived::current(self) -> Result[Result[V, E], ReadError]`

Outside-graph read of the current candidate result. The outer `Result` is the read channel (`Cycle`/`Disposed`); the inner `Result[V, E]` is the domain candidate.

### `AcceptedDerived::accepted(self) -> Result[V?, ReadError]`

Outside-graph read of the last accepted value. Records a dependency on the *current* candidate when called inside a tracked compute — in-graph consumers should use `accepted_get` / `accepted_get_or_abort` instead.

### `AcceptedDerived::snapshot(self) -> Result[AcceptedSnapshot[V, E], ReadError]`

Outside-graph read of a coherent `(current, accepted, status)` view.

### `AcceptedDerived::current_or_abort(self) -> Result[V, E]` / `accepted_or_abort(self) -> V?` / `snapshot_or_abort(self) -> AcceptedSnapshot[V, E]`

Strict companions to the reads above; abort on a `ReadError`.

### `AcceptedDerived::accepted_get(self) -> Result[V?, ReadError]`

Inside-graph read of the accepted value. Records a dependency on the *accepted projection*, which backdates on `V?`-equality, so an accepted-only consumer re-runs only when the accepted value actually changes — never on current-error churn.

### `AcceptedDerived::accepted_get_or_abort(self) -> V?`

Strict inside-graph companion to `accepted_get`; aborts on a `ReadError`.

### `AcceptedDerived::accepted_changed_at(self) -> Revision`

The revision at which the accepted value last actually changed. Gated by the constructor's acceptance predicate — `==` for the `Eq` tier, `BackdateEq::backdate_equal` (revision identity) for the `BackdateEq` tier — so current-result churn (changing diagnostics, repeated errors, accepted-equal recomputations) never advances it.

### `AcceptedDerived::watch_accepted(self) -> Watch[V?]`

A persistent outside-graph anchor on the accepted projection. It backdates with the accepted value, so it is woken only when the accepted value changes. The caller owns the returned `Watch` and must `dispose()` it.

### `AcceptedDerived::dispose(self) -> Unit` / `is_disposed(self) -> Bool`

Disposes the wrapper (idempotent); for `from_candidate`, the external candidate is spared. After disposal the read accessors surface `Disposed`.

### `AcceptedSnapshot[V, E]`

A coherent view of one committed revision, with fields `current : Result[V, E]`, `accepted : V?`, and `status : AcceptStatus`.

### `AcceptStatus`

The transition status of a committed revision: `NoAccept` (no prior value, candidate `Err`), `AcceptedChanged` (accepted value advanced), `AcceptedUnchanged` (equal success, no advance), `RetainedDueToError` (candidate `Err`, prior value retained).

---

## Accumulator[T]

Side-channel collector: derived cells push values during their compute, downstream readers pull them back with correct incremental invalidation. Use when a producer's ordinary return value (e.g. a `TypeResult`) is semantically distinct from log-like data it emits along the way (diagnostics, trace events, decorations).

Consumers that call `Derived::accumulated` from a `Derived` or `ReachableDerived` compute
are invalidated whenever a producing derived cell recomputes and its push
set differs from the previous run — even when the producer's return value is
structurally equal. Driver/debug reads outside a derived compute do not register

**Local-only semantics.** `derived.accumulated(acc)` returns only the values `derived` itself pushed — not its dependencies. Transitive aggregation is the driver's job (see the [Scope-owned accumulator](cookbook.mbt.md#pattern-scope-owned-accumulator-lifecycle) cookbook pattern). Use `accumulated_or_abort` for strict compute-closure reads.


Prefer `Scope::accumulator` when a scope is available — disposal is tied to the scope's lifecycle.

### `Scope::accumulator[T : Eq](self, label? : String) -> Accumulator[T]`

Creates an accumulator owned by a scope. When the scope is disposed, the accumulator is disposed automatically and cleared from the runtime.

The checked companion covers scope-owned accumulator disposal in
[`api_reference_examples.mbt.md`](api_reference_examples.mbt.md).

This is the preferred constructor for driver code where the accumulator's lifetime matches a larger unit of work (a chain rebuild, a compilation pass). See the [Scope-owned accumulator](cookbook.mbt.md#pattern-scope-owned-accumulator-lifecycle) cookbook pattern.

### `Accumulator::push[T](self, value: T) -> Unit raise Failure`

Appends `value` to the current compute's push buffer. Raises `Failure` if called:
- outside a tracked compute context
- from a non-`Derived` / non-`ReachableDerived` top frame
- on a disposed accumulator

Pushes within a single compute are ordered by call sequence;
`Derived::accumulated` returns them in that order inside `Ok(...)`. The checked
companion shows `push` inside a `Derived` compute in
[`api_reference_examples.mbt.md`](api_reference_examples.mbt.md).

### `Accumulator::dispose(self) -> Unit`

Disposes the accumulator. Subsequent `push`, `accumulated`, `accumulated_result`, and `accumulated_or_abort` calls raise `Failure`; subsequent `accumulated_peek` returns `[]`. Idempotent.

### `Accumulator::id(self) -> AccumulatorId`

Returns the unique runtime identifier for this accumulator. Stable across pushes and reads — useful for diagnostics and graph-shape probes.

### `Accumulator::label(self) -> String?`

Returns the optional label provided at construction.

### `Accumulator::is_disposed(self) -> Bool`

Returns `true` after `dispose` has been called.

### `Accumulator::debug(self) -> String`

Returns a human-readable summary (label, id, disposed state, per-memo push counts).

Read methods live on the `Derived` target facade: see `Derived::accumulated`, `Derived::accumulated_or_abort`, `Derived::accumulated_peek`, and `Derived::accumulated_result` in the Derived section above.

---

## Revision

Logical timestamp used by introspection APIs (`Derived::changed_at`, `Derived::verified_at`, and `CellInfo` fields).

`Revision` supports direct ordering comparisons (`<`, `<=`, `>`, `>=`), which is what verification uses internally.

The checked companion covers `changed_at`, `verified_at`, and direct revision
comparison in [`api_reference_examples.mbt.md`](api_reference_examples.mbt.md).

---

## Durability

Classification used for verification skipping:

```mbt nocheck
///|
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

```mbt nocheck
///|
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

The checked companion exercises labeled cycles and `CycleError` formatting in
[`api_reference_examples.mbt.md`](api_reference_examples.mbt.md).

### `CycleError::path(self) -> Array[CellId]`

Returns the full dependency path that forms the cycle.

The checked companion captures `err.path()` from inside a strict derived read in
[`api_reference_examples.mbt.md`](api_reference_examples.mbt.md).

### `CycleError::format_path(self) -> String`

Formats the cycle path as a human-readable string. Pure value — no runtime
handle required, because labels are captured at detection time.

The checked companion asserts that `format_path()` includes the expected cycle
labels in [`api_reference_examples.mbt.md`](api_reference_examples.mbt.md).

### Cycle Path Debugging

When a cycle is detected, `CycleError` now includes the full dependency path:

Use `err.cell()`, `err.path()`, and `err.format_path()` together when printing
cycle diagnostics. The checked companion exercises these accessors in
[`api_reference_examples.mbt.md`](api_reference_examples.mbt.md).

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
cell introspection is available on facade types such as `Derived`,
`ReachableDerived`, `Input`, and `InputField` (via `id()`)



## Per-Cell Callbacks

Target `InputField` exposes callbacks directly. For plain inputs and lazy
derived values, callbacks live on `Derived` and the `Input` handles.

### `Input::on_change(self, f : (T) -> Unit) -> Unit`

Registers a callback fired when this input's value changes. Replaces any previously registered callback.

The checked companion covers compatibility input callbacks in
[`api_reference_examples.mbt.md`](api_reference_examples.mbt.md).

### `Input::clear_on_change(self) -> Unit`

Removes the registered `on_change` callback for this input.

The checked companion covers `Input::clear_on_change` in
[`api_reference_examples.mbt.md`](api_reference_examples.mbt.md).

### `Derived::on_change(self, f : (T) -> Unit) -> Unit`

Registers a callback fired when this derived value's output changes.

The checked companion covers derived cell callbacks in
[`api_reference_examples.mbt.md`](api_reference_examples.mbt.md).

### `Derived::clear_on_change(self) -> Unit`

Removes the registered `on_change` callback for this derived value.

The checked companion covers `Derived::clear_on_change` in
[`api_reference_examples.mbt.md`](api_reference_examples.mbt.md).

**Behavior (on_change):**
- Fires after the cell's value changes
- Fires before `Runtime::on_change` callback
- During batch: fires at batch end for all changed cells

---

## Core Traits

### `RuntimeContext`

```mbt nocheck
///|
pub(open) trait RuntimeContext {
  fn runtime(Self) -> Runtime
}
```

Implemented by application context types that own an `incr` runtime. Target
constructor helpers such as `create_input` and `create_derived` use this trait.

### `Freshness`

```mbt nocheck
///|
pub(open) trait Freshness {
  fn is_fresh(Self) -> Bool
}
```

Implemented for `Input[T]`, `InputField[T]`, `Derived[T]`, and
`ReachableDerived[T]`.

### `InputFieldOwner`

```mbt nocheck
///|
pub(open) trait InputFieldOwner {
  fn cell_ids(Self) -> Array[CellId]
}
```

Implemented by structs that contain `InputField` fields. The returned `CellId`s
must be stable across calls and belong to the runtime of any scope they are
registered with.

The checked companion covers an `InputFieldOwner` implementation and
`add_input_fields` disposal in
[`api_reference_examples.mbt.md`](api_reference_examples.mbt.md).

Use `add_input_fields(scope, owner)` to register every field with a scope for
bulk disposal.

### Compatibility `Database`

```mbt nocheck
///|
pub(open) trait Database {
  fn runtime(Self) -> Runtime
}
```

Implemented for `Input[T]` and `TrackedCell[T]`.

### Compatibility `Trackable`

```mbt nocheck
///|
pub(open) trait Trackable {
  fn cell_ids(Self) -> Array[CellId]
}
```

Implemented by facade types (`Derived`, `Input`, `InputField`,
`ReachableDerived`, `EagerDerived`, `Effect`, `Reactive`) and compatibility
`TrackedCell` owners. The single method returns the `CellId` of every cell
owned by the value, in a stable order.

Use `scope.adopt(tracked)` to register a facade cell with a scope's lifecycle
(see [Scope section](#scope-target-constructors-and-watch-lifetimes)).
The checked companion covers a compatibility `Trackable` owner registered via
`add_tracked` in
[`api_reference_examples.mbt.md`](api_reference_examples.mbt.md).

The old standalone pipeline traits (`Sourceable`, `Parseable`, `Checkable`, `Executable`) were removed in the breaking cleanup. Define application-local build traits with concrete domain types instead.

---

## MapRelation[K, V]

`MapRelation[K, V]` is the target-name facade over `FunctionalRelation[K, V]`.
It keeps the same Datalog map behavior: `insert` stages key-value changes,
`get` and `iter` read the current materialized map, and `delta_iter` reads the
current frontier during fixpoint rules. The checked companion covers staged
inserts, delta reads, and materialized reads after `Runtime::fixpoint` in
[`api_reference_examples.mbt.md`](api_reference_examples.mbt.md).

---

## Helper Functions

Target helper functions take `Ctx : RuntimeContext` and construct target facade
handles from the context runtime. Compatibility helpers that take
`Db : Database` remain documented below.

### `create_input[Ctx : RuntimeContext, T](ctx: Ctx, value: T, durability?: Durability, label?: String) -> Input[T]`

Creates a target-name `Input` using the context runtime. The checked companion
covers construction, labels, and derived reads in
[`api_reference_examples.mbt.md`](api_reference_examples.mbt.md).

### `create_input_field[Ctx : RuntimeContext, T](ctx: Ctx, value: T, durability?: Durability, label?: String) -> InputField[T]`

Creates a target-name `InputField` using the context runtime. The checked
companion covers `create_input_field` with labeled fields in
[`api_reference_examples.mbt.md`](api_reference_examples.mbt.md).

### `create_derived[Ctx : RuntimeContext, T : Eq](ctx: Ctx, f: () -> T raise Failure, label?: String) -> Derived[T]`

Creates a target-name lazy `Derived` using the context runtime. The checked
companion covers `create_derived` together with context-created inputs in
[`api_reference_examples.mbt.md`](api_reference_examples.mbt.md).

### `create_reachable_derived[Ctx : RuntimeContext, T : Eq](ctx: Ctx, f: () -> T raise Failure, label?: String) -> ReachableDerived[T]`

Creates a target-name reachable lazy derived value using the context runtime.

### `create_eager_derived[Ctx : RuntimeContext, T : Eq](ctx: Ctx, compute: () -> T) -> EagerDerived[T]`

Creates a target-name eager derived value using the context runtime.

### `create_derived_map[Ctx : RuntimeContext, K : Hash + Eq, V](ctx: Ctx, f: (K) -> V raise Failure, label?: String) -> DerivedMap[K, V]`

Creates a target-name keyed derived map using the context runtime.

### `add_input_fields[T : InputFieldOwner](scope: Scope, owner: T) -> Unit`

Registers every cell in an `InputFieldOwner` struct with `scope`, so disposing
the scope disposes all of the struct's input fields in one call. The checked
companion covers struct-owned input fields and scope disposal in
[`api_reference_examples.mbt.md`](api_reference_examples.mbt.md).

### Scope Target Constructors and Watch Lifetimes

`Scope` also exposes target constructor methods that automatically register
owned cells for disposal:

- `scope.input(value, durability?, label?) -> Input[T]`
- `scope.input_field(value, durability?, label?) -> InputField[T]`
- `scope.derived(f, label?) -> Derived[T]`
- `scope.reachable_derived(f, label?) -> ReachableDerived[T]`
- `scope.eager_derived(compute) -> EagerDerived[T]`
- `scope.derived_map(f, label?) -> DerivedMap[K, V]`
- `scope.derived_no_backdate(f, label?) -> Derived[T]` — no `Eq` bound, no backdating
- `scope.accumulator(label?) -> Accumulator[T]`

Use `scope.adopt(tracked) -> T` to register a cell created outside the scope
(e.g. via `map` or raw constructors) with the scope's lifecycle. The cell
must implement `Trackable`. Returns the cell for convenient chaining.

Use `scope.add_watch(watch) -> Watch[T]` to tie a long-lived target `Watch` to
the same scope. Disposing the scope disposes the watch before owned cells are
disposed.

### Compatibility helpers

The helpers below take `Db : Database` and return compatibility handles.

### `create_input`

Creates a new `Input` using the context runtime.

The checked companion covers construction, durability, and label
introspection in
[`api_reference_examples.mbt.md`](api_reference_examples.mbt.md).


### `create_accumulator[Db : Database, T : Eq](db: Db, label? : String) -> Accumulator[T]`

Creates a runtime-owned accumulator using `db.runtime()`. Prefer `Scope::accumulator` for scope-bound lifetimes.

The checked companion covers accumulator construction and memo push retrieval
in [`api_reference_examples.mbt.md`](api_reference_examples.mbt.md).

### `create_tracked_cell`

Creates a new `TrackedCell` using the database's runtime.

The checked companion covers `create_tracked_cell`, durability, labels, and
scope disposal in
[`api_reference_examples.mbt.md`](api_reference_examples.mbt.md).

### `create_scope[Db : Database](db: Db) -> Scope`

Creates a root `Scope` using the database's runtime. Target-style code can also
construct a scope directly with `Scope::new(ctx.runtime())`.

### `add_tracked[T : Trackable](scope: Scope, tracked: T) -> Unit`

Compatibility helper for `TrackedCell` owners. Target-name code should use
`add_input_fields(scope, owner)`.

The checked companion covers `create_scope` and `add_tracked` disposal in
[`api_reference_examples.mbt.md`](api_reference_examples.mbt.md).


### `batch[Db : Database](db: Db, f: () -> Unit raise?) -> Unit raise?`

Runs a batch using `db.runtime()`, including rollback-on-raise semantics.
This is the Database helper form of `rt.batch(...)`.

The checked companion covers the Database helper form of `batch` in
[`api_reference_examples.mbt.md`](api_reference_examples.mbt.md).

### `batch_result[Db : Database](db: Db, f: () -> Unit raise) -> Result[Unit, Error]`

Runs a batch using `db.runtime()` and returns raised errors as `Result`.
This is the Database helper form of `rt.batch_result(...)`.
See `Runtime::batch_result` above for the `raise?` → `raise` migration note.

The checked companion covers the Database helper form of `batch_result`,
including rollback on `Err`, in
[`api_reference_examples.mbt.md`](api_reference_examples.mbt.md).

---

## Type Constraints

### Where `Eq` is used

`Eq` is used in two distinct optimizations:

**Same-value optimization (`Input::set`, `InputField::set`):** Before recording a change, the library compares the new value against the current one. If they are equal, the call is treated as a no-op: the global revision counter is not incremented and downstream derived values are not invalidated. This avoids spurious recomputation when an input is set to the value it already holds.

**Backdating (`Derived`, `ReachableDerived`):** After a derived value recomputes, the library compares the new result against the previous cached value. If they are equal, the underlying memo's `changed_at` timestamp is kept at its previous value rather than advanced to the current revision. Any cell that depends on this derived value therefore sees no change, and its own verification is skipped entirely.

**Custom `Eq` implementations:** If your type derives `Eq` with fields intentionally excluded — for example, a generation counter or metadata field that shouldn't influence downstream computation — backdating will treat updates to those fields as no-ops. This is correct and useful (the computation result hasn't changed semantically), but it must be intentional: if you rely on those excluded fields inside a derived compute function, you will get stale results. Only exclude fields from `Eq` that are never read by any derived value.

The checked cookbook companion covers custom equality and backdating in
[`cookbook_examples.mbt.md`](cookbook_examples.mbt.md). Treat any field omitted
from equality as forbidden input to downstream derived computations unless you
intentionally want those changes to be invisible.

### Backdating strategies

The backdate decision — whether a recomputed value counts as "changed" — is captured at construction, not at read time. Target `Derived` and `ReachableDerived` use structural `Eq`. For custom backdating strategies, see the `BackdateEq` trait and `Derived::with_backdate`.
### Constraint reference

| API | Constraint |
|---|---|
| `Input::set`, `InputField::set` | `T : Eq` |
| `Input::derived` | `U : Eq` (backdating) |
| `Input`, `Input::get`, `Input::peek`, `Input::force_set` | none |
| `Input::derived_no_backdate` | none |
| `Scope::derived_no_backdate` | none |
| `InputField`, `InputField::get`, `InputField::peek`, `InputField::force_set` | none |
| `Derived`, `ReachableDerived` | `T : Eq` |
| `Derived::with_backdate` | `T : BackdateEq` (supertrait: `HasChangedAt`) |
| `Derived::get`, `read`, `watch` | none |
| `ReachableDerived::get`, `read`, `watch` | `T : Eq` |
| `DerivedMap::get`, `read`, `read_or`, `read_or_else` | `K : Hash + Eq`, `V : Eq` |
| `DerivedMap::has_cached`, `sweep_cache` | `K : Hash + Eq` |
| `Input::set` | `T : Eq` |
| `Input::new`, `get`, `get_result`, `force_set` | none |
| `TrackedCell::set` | `T : Eq` |
| `TrackedCell::new`, `get`, `get_result`, `set_unconditional` | none |
