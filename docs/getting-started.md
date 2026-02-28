# Getting Started

This guide walks you through using `incr` from your first computation to advanced patterns.

## Installation

Add `incr` to your `moon.pkg`:

```
import {
  "dowdiness/incr",
}
```

## Your First Incremental Computation

### Recommended Approach: Database Pattern

The recommended way to use `incr` is to encapsulate the `Runtime` in your own database type. This keeps the runtime as an implementation detail and makes your API cleaner.

```moonbit
struct MyApp {
  rt : Runtime

  fn new() -> MyApp
}

impl Database for MyApp with runtime(self) { self.rt }

fn MyApp::new() -> MyApp {
  { rt: Runtime() }
}
```

Now you can use the database-centric API throughout your code without passing `Runtime` around explicitly.

### Alternative: Direct Runtime

For simple scripts or when learning, you can use the `Runtime` directly:

```moonbit
let rt = Runtime()
```

The rest of this guide will show **both patterns** — use whichever fits your needs.

### Step 2: Create Input Signals

Signals are your input values — the leaves of the dependency graph.

**Database pattern:**
```moonbit
let app = MyApp()
let price = create_signal(app, 100, label="price")
let quantity = create_signal(app, 5, label="quantity")
```

**Direct Runtime:**
```moonbit
let rt = Runtime()
let price = Signal(rt, 100, label="price")
let quantity = Signal(rt, 5, label="quantity")
```

> **Tip:** Always set a `label`. It has no runtime cost and makes cycle error messages and debug output much easier to read. For example, instead of `"Runtime 0 / Cell 2 → Cell 0 → …"` you'll see `"price → total → …"`.

### Step 3: Create Derived Computations (Memos)

Memos are computed values that automatically track their dependencies.

**Database pattern:**
```moonbit
let total = create_memo(app, () => price.get() * quantity.get(), label="total")
```

**Direct Runtime:**
```moonbit
let total = Memo(rt, () => price.get() * quantity.get(), label="total")
```

### Step 4: Read and Update

```moonbit
// First read — computes the value
inspect(total.get(), content="500")

// Change an input
quantity.set(10)

// Next read — recomputes because quantity changed
inspect(total.get(), content="1000")
```

### Step 4.5: Prefer Graceful Reads

`Memo::get()` is convenient but aborts on cycle errors. For resilient applications, use `get_result()`:

**Database pattern:**
```moonbit
match total.get_result() {
  Ok(value) => println("Total: \{value}")
  Err(err) => println(err.format_path(app.runtime()))
}
```

**Direct Runtime:**
```moonbit
match total.get_result() {
  Ok(value) => println("Total: \{value}")
  Err(err) => println(err.format_path(rt))
}
```

`Signal::get_result()` is always `Ok`, but useful for API symmetry in generic code.

### Step 5: Observe Committed Changes

Use `Runtime::set_on_change` to run a callback whenever the runtime commits a change.

**Database pattern:**
```moonbit
let mut changes = 0
app.runtime().set_on_change(() => { changes = changes + 1 })

quantity.set(12)
inspect(changes, content="1")

// Same-value set is a no-op, callback does not fire
quantity.set(12)
inspect(changes, content="1")
```

### Step 5.5: Batch Rollback on Raised Errors

Batch writes are transactional for raised errors:

**Shared setup:**
```moonbit
suberror BatchStop {
  Stop
}
```

**Database pattern:**
```moonbit
let amount = @incr.create_signal(app, 100)
let res = @incr.batch_result(app, fn() raise {
  amount.set(999)
  raise Stop
})

inspect(res is Err(_), content="true")
inspect(amount.get(), content="100") // rolled back
```

**Direct Runtime:**
```moonbit
let amount = Signal(rt, 100)
let res : Result[Unit, Error] = try? rt.batch(fn() raise {
  amount.set(999)
  raise Stop
})

inspect(res is Err(_), content="true")
inspect(amount.get(), content="100") // rolled back
```

Note: `abort()` is not catchable in MoonBit. Rollback applies to raised errors only.

## Complete Example

```moonbit
fn main {
  let rt = Runtime()

  // Inputs
  let base_price = Signal(rt, 100, label="base_price")
  let tax_rate = Signal(rt, 0.1, label="tax_rate")
  let quantity = Signal(rt, 2, label="quantity")

  // Derived values
  let subtotal = Memo(rt, () => base_price.get() * quantity.get(), label="subtotal")
  let tax = Memo(rt, () => subtotal.get().to_double() * tax_rate.get(), label="tax")
  let total = Memo(rt, () => subtotal.get().to_double() + tax.get(), label="total")

  println("Subtotal: \{subtotal.get()}")  // 200
  println("Tax: \{tax.get()}")            // 20.0
  println("Total: \{total.get()}")        // 220.0

  // Change quantity — only affected memos recompute
  quantity.set(3)
  println("New total: \{total.get()}")    // 330.0
}
```

## What Makes It Incremental?

When you call `quantity.set(3)`, `incr` doesn't immediately recompute everything. Instead:

1. It notes that `quantity` changed at a new revision
2. When you read `total.get()`, it checks if `total`'s dependencies changed
3. It walks the dependency chain: `total` → `subtotal` → `quantity` (changed!)
4. Only the affected memos (`subtotal`, `tax`, `total`) recompute

If you had 100 other memos that don't depend on `quantity`, they wouldn't even be checked.

## Next Steps

- [Core Concepts](./concepts.md) — Understand Signals, Memos, Revisions, and Durability
- [API Reference](./api-reference.md) — Complete reference for all public types and methods
- [Cookbook](./cookbook.md) — Common patterns and recipes
