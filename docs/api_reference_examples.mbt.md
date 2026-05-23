# Checked API Reference Examples

Literate tests that mirror the executable snippets in [`api-reference.md`](api-reference.md).
They exist to catch docs/API drift on the target facade surfaces — `Derived`,
`DerivedMap`, `ReachableDerived`, and the `RuntimeContext` / `Scope` helper
families — beyond the README and getting-started examples already covered by
[`target_api_examples.mbt.md`](target_api_examples.mbt.md).

Snippets that legitimately require compatibility names (`Accumulator` push,
`Memo::observe`, introspection-only handles) are not duplicated here; their
prose examples remain in `api-reference.md`.

## `Derived` — strict get, permissive read, watch

```mbt check
///|
test "docs api-ref: derived get inside compute, read outside" {
  let rt = @incr.Runtime()
  let price = @incr.Input(rt, 100, label="price")
  let tax_rate = @incr.Input(rt, 0.1, label="tax_rate")
  let tax = @incr.Derived(
    rt,
    () => price.get().to_double() * tax_rate.get(),
    label="tax",
  )
  let total = @incr.Derived(
    rt,
    // `get_or_abort` is the strict tracked-context read.
    () => price.get().to_double() + tax.get_or_abort(),
    label="total",
  )

  // Outside the graph: `read()` returns Result so cycles surface as Err.
  match total.read() {
    Ok(value) => inspect(value, content="110")
    Err(err) => abort(err.format_path())
  }

  // `read_or_abort` is the convenient permissive read.
  price.set(200)
  inspect(total.read_or_abort(), content="220")
}

///|
test "docs api-ref: derived.watch survives gc and tracks updates" {
  let rt = @incr.Runtime()
  let input = @incr.Input(rt, 1, label="input")
  let watch = {
    let derived = @incr.Derived(rt, () => input.get() * 10, label="derived")
    derived.watch()
  }

  // Even though the local `derived` handle is out of scope, the Watch keeps it
  // alive across GC sweeps.
  rt.gc()
  inspect(watch.read_or_abort(), content="10")

  input.set(4)
  match watch.read() {
    Ok(v) => inspect(v, content="40")
    Err(err) => abort(err.format_path())
  }
  watch.dispose()
}
```

## `DerivedMap` — keyed derived values

```mbt check
///|
test "docs api-ref: derived_map permissive and strict reads" {
  let rt = @incr.Runtime()
  let multiplier = @incr.Input(rt, 10, label="multiplier")
  let by_id : @incr.DerivedMap[Int, Int] = @incr.DerivedMap(
    rt,
    (id : Int) => id * multiplier.get(),
    label="by_id",
  )

  // Outside the graph: `read_or_abort` lazily computes and caches the entry.
  inspect(by_id.read_or_abort(3), content="30")
  inspect(by_id.read_or_abort(4), content="40")
  inspect(by_id.has_cached(3), content="true")
  inspect(by_id.cache_len(), content="2")

  // Inside a tracked compute, `get_or_abort` records a per-key dependency.
  let sum_3_4 = @incr.Derived(
    rt,
    () => by_id.get_or_abort(3) + by_id.get_or_abort(4),
    label="sum_3_4",
  )
  inspect(sum_3_4.read_or_abort(), content="70")

  // Bumping the multiplier invalidates only the keys read by `sum_3_4`.
  multiplier.set(5)
  inspect(sum_3_4.read_or_abort(), content="35")
}

///|
test "docs api-ref: derived_map clear_cache drops cached entries" {
  let rt = @incr.Runtime()
  let by_key : @incr.DerivedMap[Int, Int] = @incr.DerivedMap(rt, (key : Int) => {
    key + 1
  })

  inspect(by_key.read_or_abort(1), content="2")
  inspect(by_key.read_or_abort(2), content="3")
  inspect(by_key.cache_len(), content="2")

  by_key.clear_cache()
  inspect(by_key.cache_len(), content="0")
  inspect(by_key.has_cached(1), content="false")
}

///|
test "docs api-ref: derived_map read_or / read_or_else return the value on the happy path" {
  let rt = @incr.Runtime()
  let by_key : @incr.DerivedMap[Int, Int] = @incr.DerivedMap(rt, (key : Int) => {
    key * 100
  })

  // No cycle — both fallback forms see Ok(value) and pass through.
  inspect(by_key.read_or(3, 999), content="300")
  inspect(by_key.read_or_else(4, _err => -1), content="400")
}

///|
test "docs api-ref: derived_map sweep_cache prunes gc-disposed entries" {
  let rt = @incr.Runtime()
  let source = @incr.Input(rt, 10, label="source")
  let by_key : @incr.DerivedMap[Int, Int] = @incr.DerivedMap(
    rt,
    (key : Int) => source.get() + key,
    label="by_key",
  )

  // Populate three entries with no persistent observer.
  inspect(by_key.read_or_abort(1), content="11")
  inspect(by_key.read_or_abort(2), content="12")
  inspect(by_key.read_or_abort(3), content="13")
  inspect(by_key.cache_len(), content="3")

  // `rt.gc()` disposes the unobserved interior memos; `sweep_cache` then
  // drops the now-stale entries from the cache.
  rt.gc()
  inspect(by_key.sweep_cache(), content="3")
  inspect(by_key.cache_len(), content="0")
}
```

## `ReachableDerived` — lazy reads that participate in reachability

```mbt check
///|
test "docs api-ref: reachable_derived chained with watch survives gc" {
  let rt = @incr.Runtime()
  let input = @incr.Input(rt, 1, label="input")
  let reachable = @incr.ReachableDerived(
    rt,
    () => input.get() * 2,
    label="doubled",
  )
  let downstream = @incr.Derived(
    rt,
    () => reachable.get_or_abort() + 100,
    label="downstream",
  )
  let watch = downstream.watch()

  inspect(watch.read_or_abort(), content="102")
  rt.gc()
  input.set(5)
  inspect(watch.read_or_abort(), content="110")
  inspect(reachable.is_fresh(), content="true")
  watch.dispose()
}

///|
test "docs api-ref: reachable_derived.watch is a GC root for the reachable cell itself" {
  let rt = @incr.Runtime()
  let input = @incr.Input(rt, 2, label="input")
  let watch = {
    let reachable = @incr.ReachableDerived(
      rt,
      () => input.get() * 3,
      label="reachable_watched",
    )
    reachable.watch()
  }

  // The local `reachable` handle is gone, but `watch` keeps the cell alive
  // across gc — the next read still reflects updated input.
  inspect(watch.read_or_abort(), content="6")
  rt.gc()
  input.set(4)
  inspect(watch.read_or_abort(), content="12")
  watch.dispose()
}
```

## `RuntimeContext` and the `create_*` helpers

```mbt check
///|
struct AppCtx {
  rt : @incr.Runtime
}

///|
impl @incr.RuntimeContext for AppCtx with runtime(self) {
  self.rt
}

///|
test "docs api-ref: create_input / create_derived / create_derived_map via context" {
  let ctx : AppCtx = { rt: @incr.Runtime() }
  let price = @incr.create_input(ctx, 100, label="price")
  let quantity = @incr.create_input(ctx, 2, label="quantity")
  let total = @incr.create_derived(
    ctx,
    () => price.get() * quantity.get(),
    label="total",
  )
  let by_id = @incr.create_derived_map(
    ctx,
    (id : Int) => id * price.get(),
    label="by_id",
  )

  inspect(total.read_or_abort(), content="200")
  inspect(by_id.read_or_abort(3), content="300")

  quantity.set(5)
  inspect(total.read_or_abort(), content="500")
}

///|
test "docs api-ref: create_input_field / create_reachable_derived / create_eager_derived" {
  let ctx : AppCtx = { rt: @incr.Runtime() }
  let count = @incr.create_input(ctx, 1, label="count")
  let path_field = @incr.create_input_field(
    ctx,
    "src/main.mbt",
    label="SourceFile.path",
  )
  let reachable = @incr.create_reachable_derived(
    ctx,
    () => count.get() * 10,
    label="reachable_doubled",
  )
  let eager = @incr.create_eager_derived(ctx, () => count.get() + 100)

  inspect(path_field.get(), content="src/main.mbt")
  inspect(reachable.read_or_abort(), content="10")
  inspect(eager.read(), content="101")

  count.set(3)
  inspect(reachable.read_or_abort(), content="30")
  inspect(eager.read(), content="103")
}
```

## `Scope` constructors and `InputFieldOwner`

```mbt check
///|
struct SourceFile {
  path : @incr.InputField[String]
  version : @incr.InputField[Int]
}

///|
impl @incr.InputFieldOwner for SourceFile with cell_ids(self) {
  [self.path.id(), self.version.id()]
}

///|
test "docs api-ref: scope-owned target handles dispose together" {
  let rt = @incr.Runtime()
  let scope = @incr.Scope::new(rt)
  let count = scope.input(0, label="count")
  let path_field = scope.input_field("src/main.mbt", label="path")
  let doubled = scope.derived(() => count.get() * 2, label="doubled")
  let reachable = scope.reachable_derived(
    () => count.get() + 100,
    label="reachable",
  )
  let eager = scope.eager_derived(() => count.get() * 10)
  let by_id = scope.derived_map((id : Int) => count.get() + id)

  count.set(7)
  inspect(path_field.get(), content="src/main.mbt")
  inspect(doubled.read_or_abort(), content="14")
  inspect(reachable.read_or_abort(), content="107")
  inspect(eager.read(), content="70")
  inspect(by_id.read_or_abort(3), content="10")

  scope.dispose()
  inspect(scope.is_disposed(), content="true")
  inspect(path_field.is_disposed(), content="true")
}

///|
test "docs api-ref: add_input_fields wires struct-owned input fields to a scope" {
  let rt = @incr.Runtime()
  let scope = @incr.Scope::new(rt)
  let file : SourceFile = {
    path: @incr.InputField(rt, "src/main.mbt", label="SourceFile.path"),
    version: @incr.InputField(rt, 1, label="SourceFile.version"),
  }
  @incr.add_input_fields(scope, file)

  inspect(file.path.get(), content="src/main.mbt")
  inspect(file.version.get(), content="1")

  scope.dispose()
  inspect(file.path.is_disposed(), content="true")
  inspect(file.version.is_disposed(), content="true")
}
```

## `CycleError` captured via strict `Derived::get` inside a compute

When a compute reads a derived value that is part of a cycle, `Derived::get`
returns `Err(CycleError)` to the *inner* call site. The compute closure is
expected to react to that (by returning a sentinel, raising `Failure`, or
otherwise handling it) — outer `read()` / `read_or_abort()` do not catch the
cycle after the closure has produced a value. See
[`cells/cycle_path_test.mbt`](../cells/cycle_path_test.mbt) for the full set of
cycle shapes.

```mbt check
///|
test "docs api-ref: derived.get surfaces Err(CycleError) inside compute" {
  let rt = @incr.Runtime()
  let self_ref : Ref[@incr.Derived[Int]?] = { val: None }
  let captured_formatted : Ref[String] = { val: "" }
  let captured_len : Ref[Int] = { val: 0 }

  let m = @incr.Derived(
    rt,
    () => {
      match self_ref.val {
        Some(d) =>
          match d.get() {
            Ok(v) => v + 1
            Err(err) => {
              captured_formatted.val = err.format_path()
              captured_len.val = err.path().length()
              -1
            }
          }
        None => 0
      }
    },
    label="self_cycle",
  )
  self_ref.val = Some(m)

  // Trigger the cycle and observe the captured error from inside the compute.
  let _ = m.read_or_abort()
  inspect(captured_len.val >= 1, content="true")
  inspect(captured_formatted.val.contains("Cycle"), content="true")
}
```
