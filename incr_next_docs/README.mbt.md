# Incr Next executable guide

**Reader:** MoonBit consumers evaluating the unpublished `dowdiness/incr_next`
public interface.

**Decision:** Teach the smallest correct public model with checked literate
examples, while keeping caller-contract violations in a separate package.

**Keep until:** Superseded by accepted Incr Next product documentation.

**Disposition:** Retained at K2 closure as executable product documentation.

**Status:** K2 is complete and the exact MoonBit 0.10.9 packager prerequisite is
satisfied. Incr Next remains unpublished until a separate commission explicitly
authorizes publication. This guide uses the post-K2 typed-raise interface.

Every `mbt check` block is compiled and tested on default, native, JavaScript,
and wasm-gc. The separate
[`expected_divergence`](expected_divergence/README.mbt.md) package demonstrates
caller-contract violations rather than kernel promises.

## Dependency

Incr Next is not published. K2.3 proved consumption of an unpacked candidate
artifact outside the source tree; this guide does not imply registry
availability.

```moonbit nocheck
///|
// moon.mod
import {
  "dowdiness/incr_next@0.1.0-alpha.1",
}
```

```moonbit nocheck
///|
// moon.pkg
import {
  "dowdiness/incr_next",
}
```

## Quickstart

A Store owns committed state. A Region owns Sources, Derived Values, Queries,
memos, and their lifetime. `Store::get` reads one View; every write occurs in a
Transaction.

```mbt check
///|
test "incr next docs: quickstart" {
  let store = @incr_next.Store::Store()
  let region = store.region()
  let quantity = region.source(2)
  let doubled = region.derived(ctx => ctx.get(quantity.view()) * 2)

  assert_eq(store.get(doubled), 4)
  let committed : Result[Unit, Unit] = store.transaction(tx => {
    tx.set(quantity, 5)
    Ok(())
  })
  assert_eq(committed, Ok(()))
  assert_eq(store.get(doubled), 10)

  region.close()
  let after_close : Result[Int, @incr_next.ReadError] = Ok(store.get(doubled)) catch {
    error => Err(error)
  }
  assert_true(after_close is Err(@incr_next.ReadError::ClosedRegion(_)))
}
```

## Mental model

| Handle | Responsibility |
|---|---|
| `Store` | Owns committed state, root gets, and Transactions |
| `Region` | Owns Source payloads, definitions, memos, and their lifetime |
| `Source[T]` | Names committed input state and attenuates to a View |
| Derived Value | One keyless tracked value, represented directly by `View[V]` |
| `Query[K, V]` | A key-indexed family; `view(key)` selects one member |
| `View[V]` | A read capability that does not keep its Region open |
| `QueryContext` | A callback-scoped capability for tracked gets |
| `Transaction` | A callback-scoped capability for staging Source writes |

## Transactions

`Ok(value)` commits all final staged writes and returns the caller-owned success
value. `Err(error)` is an expected Domain Outcome: it rolls back and returns the
same value. A structural Transaction failure rolls back and raises
`TransactionError`.

```mbt check
///|
test "incr next docs: transaction returns domain data" {
  let store = @incr_next.Store::Store()
  let region = store.region()
  let left = region.source(2)
  let right = region.source(5)
  let total = region.derived(ctx => ctx.get(left.view()) + ctx.get(right.view()))

  let committed : Result[String, String] = store.transaction(tx => {
    tx.set(left, 20)
    tx.set(right, 50)
    Ok("invoice-7")
  })
  assert_eq(committed, Ok("invoice-7"))
  assert_eq(store.get(total), 70)

  let rejected : Result[Unit, String] = store.transaction(tx => {
    tx.set(left, 99)
    Err("limit exceeded")
  })
  assert_eq(rejected, Err("limit exceeded"))
  assert_eq(store.get(total), 70)
  region.close()
}
```

## Tracked gets and dynamic dependencies

A Query is for caller-keyed families. `QueryContext::get` records only the Views
used by the successful invocation, so changing a branch replaces its old trace.

```mbt check
///|
test "incr next docs: tracked gets follow the selected branch" {
  let store = @incr_next.Store::Store()
  let region = store.region()
  let left = region.source(2)
  let right = region.source(11)
  let select_right = region.source(false)
  let selected = region.query((ctx, key : Bool) => {
    if key || ctx.get(select_right.view()) {
      ctx.get(right.view())
    } else {
      ctx.get(left.view())
    }
  })

  assert_eq(store.get(selected.view(false)), 2)
  ignore(
    (
      store.transaction(tx => {
        tx.set(right, 13)
        tx.set(select_right, true)
        Ok(())
      }) : Result[Unit, Unit]),
  )
  assert_eq(store.get(selected.view(false)), 13)
  region.close()
}
```

A QueryContext expires when its callback returns. Capturing it does not extend
its authority.

```mbt check
///|
test "incr next docs: QueryContext expires after its callback" {
  let store = @incr_next.Store::Store()
  let region = store.region()
  let source = region.source(7)
  let captured = Ref(None)
  let value = region.derived(ctx => {
    captured.val = Some(ctx)
    ctx.get(source.view())
  })

  assert_eq(store.get(value), 7)
  let expired : Result[Int, @incr_next.ReadError] = Ok(
    captured.val.unwrap().get(source.view()),
  ) catch {
    error => Err(error)
  }
  assert_true(expired is Err(@incr_next.ReadError::ExpiredQueryContext(_)))
  region.close()
}
```

## Structural failures and Domain Outcomes

Structural Failures use concrete typed `raise`. Expected domain alternatives
remain values and may therefore be memoized, compared, displayed, and handled
normally.

```mbt check
///|
test "incr next docs: structural failure and Domain Outcome stay separate" {
  let store = @incr_next.Store::Store()
  let region = store.region()
  let domain_value = region.derived(_ctx => {
    let value : Result[Int, String] = Err("missing invoice")
    value
  })
  assert_eq(store.get(domain_value), Err("missing invoice"))

  let foreign = @incr_next.Store::Store().region().source(9)
  let invalid = region.derived(ctx => ctx.get(foreign.view()))
  let failure : Result[Int, @incr_next.ReadError] = Ok(store.get(invalid)) catch {
    error => Err(error)
  }
  assert_true(failure is Err(@incr_next.ReadError::CrossStore(_)))
  region.close()
}
```

A Query invocation remembers the first Structural Failure observed through its
`QueryContext`. Catching that error inside the callback cannot convert it into
a successful memo.

```mbt check
///|
test "incr next docs: caught structural failure still fails closed" {
  let store = @incr_next.Store::Store()
  let region = store.region()
  let foreign = @incr_next.Store::Store().region().source(9)
  let cannot_hide = region.derived(ctx => {
    ctx.get(foreign.view()) catch {
      _error => 77
    }
  })
  let failure : Result[Int, @incr_next.ReadError] = Ok(store.get(cannot_hide)) catch {
    error => Err(error)
  }
  assert_true(failure is Err(@incr_next.ReadError::CrossStore(_)))
  region.close()
}
```

Application quarantine seams may display the opaque Diagnostic without parsing
internal IDs or graph paths.

```mbt check
///|
test "incr next docs: diagnostics are actionable" {
  let store = @incr_next.Store::Store()
  let region = store.region()
  let foreign = @incr_next.Store::Store().region().source(1)
  let invalid = region.derived(ctx => ctx.get(foreign.view()))
  let failure : Result[Int, @incr_next.ReadError] = Ok(store.get(invalid)) catch {
    error => Err(error)
  }
  match failure {
    Err(@incr_next.ReadError::CrossStore(diagnostic)) => {
      assert_true(diagnostic.message().length() > 0)
      assert_true(diagnostic.help() is Some(_))
    }
    _ => abort("expected CrossStore")
  }
}
```

## Choosing cutoff

Cutoff is optional. Omission conservatively propagates every successful
recomputation. `Cutoff::equal()` requires `V : Eq`; no arbitrary or type-owned
predicate is public. A manual `Eq` implementation used for cutoff must make
equality strong enough that every downstream observer can safely reuse its
prior observation. Ignoring an observable field can produce a stale result.

```mbt check
///|
test "incr next docs: optional Eq cutoff suppresses downstream work" {
  let store = @incr_next.Store::Store()
  let region = store.region()
  let input = region.source(1)
  let parity = region.derived(
    ctx => ctx.get(input.view()) % 2,
    cutoff=@incr_next.Cutoff::equal(),
  )
  let downstream_runs = Ref(0)
  let downstream = region.derived(ctx => {
    downstream_runs.val = downstream_runs.val + 1
    ctx.get(parity)
  })

  assert_eq(store.get(downstream), 1)
  ignore(
    (
      store.transaction(tx => {
        tx.set(input, 3)
        Ok(())
      }) : Result[Unit, Unit]),
  )
  assert_eq(store.get(downstream), 1)
  assert_eq(downstream_runs.val, 1)
  region.close()
}
```

## Caller snapshot obligations

Incr Next does not make generic defensive copies. Keep values reachable from a
key, Source payload, or cached result observationally immutable, or copy at the
ownership boundary.

```mbt check
///|
test "incr next docs: explicit copies protect mutable Array boundaries" {
  let store = @incr_next.Store::Store()
  let region = store.region()
  let caller_payload = [1]
  let source = region.source(caller_payload.copy())
  caller_payload[0] = 8
  assert_eq(store.get(source.view())[0], 1)

  let result = region.derived(_ctx => [4])
  let detached = store.get(result).copy()
  detached[0] = 9
  assert_eq(store.get(result)[0], 4)
  region.close()
}
```

## Common mistakes

| Mistake | Consequence | Correct boundary |
|---|---|---|
| Capturing and later using QueryContext or Transaction | Expired capability failure | Use capabilities synchronously inside callbacks |
| Returning Structural Failure as domain data | Kernel validity is confused with expected outcomes | Let typed structural failure propagate; keep domain alternatives in `V` |
| Mutating captured keys or committed values in place | Cached snapshots may appear stale | Use immutable snapshots, copies, or tracked semantic versions |
| Using partial or observer-dependent equality for cutoff | Propagation may return a stale normal value | Use omission or an `Eq` relation that preserves every downstream observation |
| Treating a retained View as lifetime ownership | Gets fail after Region close | Keep the owning Region alive for the required lifetime |
