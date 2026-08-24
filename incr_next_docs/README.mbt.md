# Incr Next executable guide

**Reader:** MoonBit consumers evaluating the unpublished `dowdiness/incr_next`
public interface.

**Decision:** Teach the smallest correct public model with checked literate
examples, while keeping caller-contract violations in a separate package.

**Keep until:** Superseded by accepted Incr Next product documentation.

**Disposition:** Retained at K2 closure as executable product documentation.

**Status:** K2.2 accepted and squash-merged as `9360816f`; K2.3 distribution
evidence accepted and squash-merged as `3007f5ff`; K2 is complete. A separate
alpha publication commission is recommended after packager standardization.
Incr Next remains unpublished until that later commission explicitly authorizes
it.

Every `mbt check` block in this guide is compiled and tested on default,
native, JavaScript, and wasm-gc. CI discovers all `.mbt.md` files in this module, so the
text and executable examples have one source. The separate
[`expected_divergence`](expected_divergence/README.mbt.md) package demonstrates
caller-contract violations; those results are not kernel promises or Fresh
conformance evidence. The public-only boundary rejects `.mbt.md` front matter,
so file-local `moonbit.import` or `moonbit.deps` cannot bypass the canonical
module and package manifests.

## Dependency

Incr Next is not published. K2.3 separately proved consumption of an unpacked
candidate artifact outside the source tree; this workspace guide still does not
imply registry availability.

```moonbit nocheck
// moon.mod
import {
  "dowdiness/incr_next@0.1.0-alpha.1",
}
```

```moonbit nocheck
// moon.pkg
import {
  "dowdiness/incr_next",
}
```

## Quickstart

An Incr Next application owns a `Store`, opens a `Region`, defines Sources and
Queries, retains Views, and performs every write through a Transaction. A root
`Store::read` evaluates one committed snapshot.

```mbt check
///|
test "incr next docs: quickstart" {
  let store = @incr_next.Store::Store()
  let region = store.region().unwrap()
  let quantity = region.source(2).unwrap()
  let doubled = region
    .query((ctx, _unit : Unit) => {
      ctx.read(quantity.view()).map(value => value * 2)
    })
    .unwrap()
  let doubled_view = doubled.at(())

  assert_eq(store.read(doubled_view), Ok(4))
  ignore(store.transaction(tx => tx.set(quantity, 5)).unwrap())
  assert_eq(store.read(doubled_view), Ok(10))

  region.close().unwrap()
  assert_true(
    store.read(doubled_view) is Err(@incr_next.ReadError::ClosedRegion(..)),
  )
}
```

## Mental model

The handles have distinct authority:

| Handle | Responsibility |
|---|---|
| `Store` | Owns committed state, clocks, root reads, and Transactions |
| `Region` | Owns Source payloads, Query definitions, memos, and their lifetime |
| `Source[T]` | Names committed input state; exposes a read-only View |
| `Query[K, V]` | Defines a keyed tracked computation; `at(key)` creates a View |
| `View[V]` | A lightweight read recipe; it does not keep a Region open |
| `QueryContext` | A callback-scoped capability for tracked reads and Revision access |
| `Transaction` | A callback-scoped capability for staging Source writes |

## Transactions and snapshots

A successful nonempty Transaction publishes all final staged values atomically
and advances the Store Revision exactly once. Do not call `Store::read` inside
the callback; read only after `transaction` returns.

```mbt check
///|
test "incr next docs: one transaction publishes one snapshot" {
  let store = @incr_next.Store::Store()
  let region = store.region().unwrap()
  let left = region.source(2).unwrap()
  let right = region.source(5).unwrap()
  let snapshot = region
    .query((ctx, _unit : Unit) => {
      match ctx.revision() {
        Err(error) => Err(error)
        Ok(revision) =>
          match ctx.read(left.view()) {
            Err(error) => Err(error)
            Ok(left_value) =>
              ctx
              .read(right.view())
              .map(right_value => (revision.value(), left_value, right_value))
          }
      }
    })
    .unwrap()
  let snapshot_view = snapshot.at(())

  assert_eq(store.read(snapshot_view), Ok((0, 2, 5)))
  let committed = store
    .transaction(tx => {
      match tx.set(left, 20) {
        Err(error) => Err(error)
        Ok(_) => tx.set(right, 50)
      }
    })
    .unwrap()
  assert_eq(committed.value(), 1)
  assert_eq(store.read(snapshot_view), Ok((1, 20, 50)))
  region.close().unwrap()
}
```

A failed, empty, poisoned, or rejected Transaction publishes no partial state.
Every `tx.set` result must be propagated; ignoring a failed write does not make
the transaction admissible.

## Tracked reads and dynamic dependencies

`QueryContext::read` records View dependencies, while
`QueryContext::revision` records a dependency on the Store Revision clock. The
successful View trace contains the Views actually read by that invocation, so
changing a branch replaces the old trace.

```mbt check
///|
test "incr next docs: tracked reads follow the selected branch" {
  let store = @incr_next.Store::Store()
  let region = store.region().unwrap()
  let left = region.source(2).unwrap()
  let right = region.source(11).unwrap()
  let select_right = region.source(false).unwrap()
  let selected = region
    .query((ctx, _unit : Unit) => {
      match ctx.read(select_right.view()) {
        Err(error) => Err(error)
        Ok(false) => ctx.read(left.view())
        Ok(true) => ctx.read(right.view())
      }
    })
    .unwrap()
  let selected_view = selected.at(())

  assert_eq(store.read(selected_view), Ok(2))
  ignore(store.transaction(tx => tx.set(right, 13)).unwrap())
  assert_eq(store.read(selected_view), Ok(2))
  ignore(store.transaction(tx => tx.set(select_right, true)).unwrap())
  assert_eq(store.read(selected_view), Ok(13))
  region.close().unwrap()
}
```

A `QueryContext` is valid only while its callback is running. Capturing it does
not extend its authority.

```mbt check
///|
test "incr next docs: QueryContext expires after its callback" {
  let store = @incr_next.Store::Store()
  let region = store.region().unwrap()
  let captured = Ref(None)
  let query = region
    .query((ctx, _unit : Unit) => {
      captured.val = Some(ctx)
      ctx.revision().map(_ => 7)
    })
    .unwrap()

  assert_eq(store.read(query.at(())), Ok(7))
  assert_true(
    captured.val.unwrap().revision()
    is Err(@incr_next.ReadError::ExpiredQueryContext),
  )
  region.close().unwrap()
}
```

## Region lifetime

A Region owns the heavy Source payloads, Query callbacks, memo values, and
traces created through it. `Region::close` releases that state. A retained View
is only a lightweight recipe: it does not keep the Region open, and a later
root or tracked read returns `ReadError::ClosedRegion`. The Quickstart pins this
surviving-View behavior executablely.

## Structural and domain errors

The outer `Result[V, ReadError]` is owned by the kernel. Domain failure belongs
inside `V`, commonly as `V = Result[Value, DomainError]`. A Query callback must
return a failed tracked read unchanged rather than turn it into an apparently
successful value.

```mbt check
///|
test "incr next docs: structural and domain errors stay separate" {
  let store = @incr_next.Store::Store()
  let region = store.region().unwrap()
  let domain_query = region
    .query((_ctx, _unit : Unit) => {
      let domain_value : Result[Int, String] = Err("missing invoice")
      Ok(domain_value)
    })
    .unwrap()
  assert_eq(store.read(domain_query.at(())), Ok(Err("missing invoice")))

  let foreign_store = @incr_next.Store::Store()
  let foreign_region = foreign_store.region().unwrap()
  let foreign_source = foreign_region.source(9).unwrap()
  let structural_query = region
    .query((ctx, _unit : Unit) => ctx.read(foreign_source.view()))
    .unwrap()
  assert_true(
    store.read(structural_query.at(()))
    is Err(@incr_next.ReadError::CrossStore(..)),
  )
  foreign_region.close().unwrap()
  region.close().unwrap()
}
```

## Choosing cutoff

Cutoff controls downstream propagation. Every successful recompute retains the
newest value and trace.

- `Region::query` is the concise baseline used by the Quickstart.
- `Region::query_always_changed` makes the always-changed policy explicit.
- `Region::query_eq` uses `V`'s `Eq` implementation and requires `V : Eq`.
  That implementation is caller-owned and must be sound as a propagation
  equivalence for every downstream observer.
- `Region::query_type_owned` uses `V : CutoffEq`; the value type owns a sound
  propagation-equivalence relation.

Use `query_eq` only when equality means every downstream observer may reuse its
prior observation. The `Ref` counters below are test-only observation hooks;
they do not contribute to either Query value. Application Query callbacks must
remain snapshot-determined. Callback invocation counts and side effects are not
public API behavior.

```mbt check
///|
test "incr next docs: Eq cutoff backdates an equal result" {
  let store = @incr_next.Store::Store()
  let region = store.region().unwrap()
  let input = region.source(1).unwrap()
  let target_runs = Ref(0)
  let downstream_runs = Ref(0)
  let parity = region
    .query_eq((ctx, _unit : Unit) => {
      target_runs.val = target_runs.val + 1
      ctx.read(input.view()).map(value => value % 2)
    })
    .unwrap()
  let downstream = region
    .query((ctx, _unit : Unit) => {
      downstream_runs.val = downstream_runs.val + 1
      ctx.read(parity.at(()))
    })
    .unwrap()

  assert_eq(store.read(downstream.at(())), Ok(1))
  ignore(store.transaction(tx => tx.set(input, 3)).unwrap())
  assert_eq(store.read(downstream.at(())), Ok(1))
  assert_eq(target_runs.val, 2)
  assert_eq(downstream_runs.val, 1)
  region.close().unwrap()
}
```

The expected-divergence package shows why a non-equivalence such as local
nearness is unsound for `CutoffEq`.

## Caller snapshot obligations

Incr Next never mutates committed payloads or memo results, but it does not make
generic defensive copies. Keep everything reachable from a captured key,
committed Source value, or cached Query result observationally immutable. Use
immutable values, persistent collections, read-only facades, explicit copies,
or a tracked `(reference, semantic_version)` pair. The shallow copy below is
sufficient for `Array[Int]`; nested references require an ownership-appropriate
snapshot.

```mbt check
///|
test "incr next docs: explicit copies protect mutable Array boundaries" {
  let store = @incr_next.Store::Store()
  let region = store.region().unwrap()
  let caller_payload = [1]
  let source = region.source(caller_payload.copy()).unwrap()
  caller_payload[0] = 8
  assert_eq(store.read(source.view()).unwrap()[0], 1)

  let query = region.query((_ctx, _unit : Unit) => Ok([4])).unwrap()
  let detached = store.read(query.at(())).unwrap().copy()
  detached[0] = 9
  assert_eq(store.read(query.at(())).unwrap()[0], 4)
  region.close().unwrap()
}
```

## Common mistakes

| Mistake | Consequence | Correct boundary |
|---|---|---|
| Root read inside a Transaction | `ReadDuringTransaction`; no intermediate snapshot is public | Stage writes, return, then root-read |
| Reading a dependency without `QueryContext::read` | No trace records the state | Put semantic state in a Source/View and tracked-read it |
| Converting `ReadError` to `Ok` | Structural failure looks like valid domain data | Return the same `Err(error)` |
| Mutable key, payload, or memo aliases | Cached/committed observations can change outside publication | Use immutable values or explicit copies/versioning |
| Unsound `Eq` or `CutoffEq` | Downstream reuse can preserve a stale observation | Use always-changed or a true propagation equivalence |
| Keeping a View after Region close | The View survives but reads `ClosedRegion` | Close only after all owned computations are finished |
| Treating setup `unwrap` as recovery | Example-only assumptions abort on rejected setup | Handle `RegionError`/`TransactionError` at application boundaries |
