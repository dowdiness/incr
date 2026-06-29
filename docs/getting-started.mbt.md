# Getting Started

This guide walks you through using `incr` from your first computation to advanced patterns.

The core target-API examples in this guide are mirrored by checked literate
tests in [`target_api_examples.mbt.md`](target_api_examples.mbt.md), so changes
to constructor, read, committed-change callback, or batch rollback semantics are
caught by `moon check`.

## Installation

Add `incr` to your `moon.pkg`:

```moonbit nocheck
import {
  "dowdiness/incr",
}
```

## Your First Incremental Computation

### Step 1: Create a Runtime

Start with a `Runtime`. It owns the dependency graph, revision counter, and
garbage-collection roots.

```mbt nocheck
///|
let rt = @incr.Runtime()
```

For long-lived subsystems, create cells through a `Scope` so disposal is one
operation:

```mbt nocheck
///|
let rt = @incr.Runtime()

///|
let scope = @incr.Scope::new(rt)
```

`RuntimeContext` remains available for app structs that want to hide the
runtime, but the primary target API uses direct constructors (`Input(rt, ...)`,
`Derived(rt, ...)`) and scope helpers (`scope.input(...)`,
`scope.derived(...)`).

### Step 2: Create Inputs

Inputs are your settable values — the leaves of the dependency graph.

```mbt nocheck
///|
let rt = @incr.Runtime()

///|
let price = @incr.Input(rt, 100, label="price")

///|
let quantity = @incr.Input(rt, 5, label="quantity")
```

If these inputs should be disposed with a scope:

```mbt nocheck
///|
let rt = @incr.Runtime()

///|
let scope = @incr.Scope::new(rt)

///|
let scoped_price = scope.input(100, label="price")

///|
let scoped_quantity = scope.input(5, label="quantity")
```

> **Tip:** Always set a `label`. It has no runtime cost and makes cycle error messages and debug output much easier to read. For example, instead of `"Runtime 0 / Cell 2 → Cell 0 → …"` you'll see `"price → total → …"`.

### Step 3: Create Derived Computations

Derived values compute lazily and automatically track their dependencies.

```mbt nocheck
///|
let rt = @incr.Runtime()

///|
let price = @incr.Input(rt, 100, label="price")

///|
let quantity = @incr.Input(rt, 5, label="quantity")

///|
let total = @incr.Derived(rt, () => price.get() * quantity.get(), label="total")
```

Or scope-owned:

```mbt nocheck
///|
let rt = @incr.Runtime()

///|
let scope = @incr.Scope::new(rt)

///|
let scoped_price = scope.input(100, label="price")

///|
let scoped_quantity = scope.input(5, label="quantity")

///|
let scoped_total = scope.derived(
  () => scoped_price.get() * scoped_quantity.get(),
  label="total",
)
```

### Step 4: Read and Update

`Derived::get()` is only valid inside another derived compute function. From
outside the graph — top-level code, tests, event handlers — read with `read()`
or `read_or_abort()`. Both forms recompute lazily.

```mbt check
///|
test "getting started: read and update" {
  let rt = @incr.Runtime()
  let price = @incr.Input(rt, 100, label="price")
  let quantity = @incr.Input(rt, 5, label="quantity")
  let total = @incr.Derived(
    rt,
    () => price.get() * quantity.get(),
    label="total",
  )

  inspect(total.read_or_abort(), content="500")

  quantity.set(10)
  inspect(total.read_or_abort(), content="1000")
}
```

### Step 4.5: Prefer Graceful Reads

`read_or_abort()` is convenient but aborts on cycle errors. For resilient applications, use `read()`:

```mbt check
///|
test "getting started: graceful read" {
  let rt = @incr.Runtime()
  let price = @incr.Input(rt, 100, label="price")
  let quantity = @incr.Input(rt, 5, label="quantity")
  let total = @incr.Derived(
    rt,
    () => price.get() * quantity.get(),
    label="total",
  )

  match total.read() {
    Ok(value) => inspect(value, content="500")
    Err(err) => abort(err.format_path())
  }
}
```

`CycleError::format_path` takes no runtime — labels are captured at
detection time, so errors render the same regardless of where and when you
format them.

Inside another derived computation, use `get()` when you want to handle cycles
as values and `get_or_abort()` when an aborting strict read is acceptable.

### Step 5: Observe Committed Changes

Use `Runtime::set_on_change` to run a callback whenever the runtime commits a change.

```mbt check
///|
test "getting started: committed change callback" {
  let rt = @incr.Runtime()
  let quantity = @incr.Input(rt, 10, label="quantity")
  let changes : Ref[Int] = { val: 0 }

  rt.set_on_change(() => changes.val = changes.val + 1)

  quantity.set(12)
  inspect(changes.val, content="1")

  // Same-value set is a no-op, callback does not fire.
  quantity.set(12)
  inspect(changes.val, content="1")
}
```

### Step 5.5: Batch Rollback on Raised Errors

Batch writes are transactional for raised errors:

```mbt check
///|
suberror GettingStartedBatchStop {
  GettingStartedStop
}

///|
test "getting started: batch_result rollback" {
  let rt = @incr.Runtime()
  let amount = @incr.Input(rt, 100)
  let result = rt.batch_result(fn() raise {
    amount.set(999)
    raise GettingStartedStop
  })

  inspect(result is Err(_), content="true")
  inspect(amount.get(), content="100")
}
```

Note: `abort()` is not catchable in MoonBit. Rollback applies to raised errors only.

## Complete Example

```mbt check
///|
test "getting started: complete example" {
  let rt = @incr.Runtime()

  let base_price = @incr.Input(rt, 100, label="base_price")
  let tax_rate = @incr.Input(rt, 0.1, label="tax_rate")
  let quantity = @incr.Input(rt, 2, label="quantity")

  let subtotal = @incr.Derived(
    rt,
    () => base_price.get() * quantity.get(),
    label="subtotal",
  )
  let tax = @incr.Derived(
    rt,
    () => subtotal.get_or_abort().to_double() * tax_rate.get(),
    label="tax",
  )
  let total = subtotal.map2(tax, (s, t) => s.to_double() + t, label="total")

  inspect(subtotal.read_or_abort(), content="200")
  inspect(tax.read_or_abort(), content="20")
  inspect(total.read_or_abort(), content="220")

  quantity.set(3)
  inspect(total.read_or_abort(), content="330")
}
```

## What Makes It Incremental?

When you call `quantity.set(3)`, `incr` doesn't immediately recompute everything. Instead:

1. It notes that `quantity` changed at a new revision
2. When you read `total.read_or_abort()`, it checks if `total`'s dependencies changed
3. It walks the dependency chain: `total` → `subtotal` → `quantity` (changed!)
4. Only the affected derived values (`subtotal`, `tax`, `total`) recompute

If you had 100 other derived values that don't depend on `quantity`, they wouldn't even be checked.

## Next Steps

- [Core Concepts](./concepts.mbt.md) — Understand Inputs, Derived values, Revisions, and Durability
- [API Reference](./api-reference.mbt.md) — Complete reference for all public types and methods
- [Cookbook](./cookbook.mbt.md) — Common patterns and recipes
