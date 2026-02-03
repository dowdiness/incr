# Getting Started

This guide walks you through using `incr` from your first computation to advanced patterns.

## Installation

Add `incr` to your `moon.pkg.json`:

```json
{
  "import": [
    "dowdiness/incr"
  ]
}
```

## Your First Incremental Computation

### Step 1: Create a Runtime

Every `incr` program starts with a `Runtime`. It manages all the bookkeeping for dependency tracking and change detection.

```moonbit
let rt = Runtime::new()
```

### Step 2: Create Input Signals

Signals are your input values — the leaves of the dependency graph:

```moonbit
let price = Signal::new(rt, 100)
let quantity = Signal::new(rt, 5)
```

### Step 3: Create Derived Computations (Memos)

Memos are computed values that automatically track their dependencies:

```moonbit
let total = Memo::new(rt, fn() { price.get() * quantity.get() })
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

## Complete Example

```moonbit
fn main {
  let rt = Runtime::new()

  // Inputs
  let base_price = Signal::new(rt, 100)
  let tax_rate = Signal::new(rt, 0.1)
  let quantity = Signal::new(rt, 2)

  // Derived values
  let subtotal = Memo::new(rt, fn() { base_price.get() * quantity.get() })
  let tax = Memo::new(rt, fn() { subtotal.get().to_double() * tax_rate.get() })
  let total = Memo::new(rt, fn() { subtotal.get().to_double() + tax.get() })

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
