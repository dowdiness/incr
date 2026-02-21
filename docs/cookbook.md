# Cookbook

Common patterns and recipes for using `incr` effectively.

## Pattern: Diamond Dependencies

Handle computations where multiple paths converge:

```
    [A]
   /   \
  [B]   [C]
   \   /
    [D]
```

```moonbit
let rt = Runtime::new()

let a = Signal::new(rt, 10)
let b = Memo::new(rt, fn() { a.get() * 2 })
let c = Memo::new(rt, fn() { a.get() + 5 })
let d = Memo::new(rt, fn() { b.get() + c.get() })

inspect(d.get(), content="35")  // (10*2) + (10+5)

a.set(20)
inspect(d.get(), content="65")  // (20*2) + (20+5)
```

`incr` handles diamonds correctly — `a` is only read once per computation of each memo.

---

## Pattern: Conditional Dependencies

Dependencies can vary based on runtime conditions:

```moonbit
let rt = Runtime::new()

let use_cache = Signal::new(rt, true)
let cache = Signal::new(rt, "cached_value")
let expensive_source = Signal::new(rt, "computed_value")

let result = Memo::new(rt, fn() {
  if use_cache.get() {
    cache.get()
  } else {
    expensive_source.get()
  }
})

// With caching enabled
inspect(result.get(), content="cached_value")

// Changes to expensive_source don't trigger recomputation
expensive_source.set("new_computed")
inspect(result.get(), content="cached_value")  // Still cached

// Switch to computed mode
use_cache.set(false)
inspect(result.get(), content="new_computed")
```

---

## Pattern: Configuration + Data Separation

Use durability to optimize stable configuration:

```moonbit
let rt = Runtime::new()

// Configuration changes rarely
let multiplier = Signal::new(rt, 1.5, durability=High)
let precision = Signal::new(rt, 2, durability=High)

// Data changes frequently
let measurements : Array[Signal[Double]] = []
for i = 0; i < 1000; i = i + 1 {
  measurements.push(Signal::new(rt, 0.0))
}

// Config-only computation
let config_factor = Memo::new(rt, fn() {
  multiplier.get() * 10.0.pow(precision.get().to_double())
})

// Mixed computation
let process = fn(i: Int) {
  Memo::new(rt, fn() { measurements[i].get() * config_factor.get() })
}
```

When measurements change:
- `config_factor` skips verification entirely (durability shortcut)
- Only affected `process` memos recompute

---

## Pattern: Atomic Multi-Update

Update related signals together:

```moonbit
let rt = Runtime::new()

let x = Signal::new(rt, 0)
let y = Signal::new(rt, 0)
let position = Memo::new(rt, fn() { (x.get(), y.get()) })

// Without batch: two revision bumps, position could see inconsistent state
// With batch: single revision bump, atomic update
rt.batch(fn() {
  x.set(100)
  y.set(200)
})

inspect(position.get(), content="(100, 200)")
```

---

## Pattern: Tentative Updates with Rollback

Use batch semantics for speculative changes:

```moonbit
let rt = Runtime::new()

let value = Signal::new(rt, 10)
let derived = Memo::new(rt, fn() { value.get() * 2 })

// Get initial state
let initial = value.get()

rt.batch(fn() {
  // Try a change
  value.set(99)

  // Decide to rollback
  value.set(initial)
})

// No revision bump occurred — revert detection
// derived is not marked stale
```

---

## Pattern: Computed Defaults

Derive default values from other signals:

```moonbit
let rt = Runtime::new()

let user_override : Signal[Int?] = Signal::new(rt, None)
let computed_default = Signal::new(rt, 100)

let effective_value = Memo::new(rt, fn() {
  match user_override.get() {
    Some(v) => v
    None => computed_default.get()
  }
})

inspect(effective_value.get(), content="100")  // Uses default

user_override.set(Some(42))
inspect(effective_value.get(), content="42")   // Uses override
```

---

## Pattern: Layered Caching

Build computation layers with natural caching:

```moonbit
let rt = Runtime::new()

// Raw input
let raw_data = Signal::new(rt, "  Hello World  ")

// Layer 1: Normalize
let normalized = Memo::new(rt, fn() {
  raw_data.get().trim()
})

// Layer 2: Transform
let transformed = Memo::new(rt, fn() {
  normalized.get().to_lower()
})

// Layer 3: Format
let formatted = Memo::new(rt, fn() {
  "[" + transformed.get() + "]"
})

inspect(formatted.get(), content="[hello world]")

// Change input
raw_data.set("  Hello World  ")  // Same after trim — no-op!
// Nothing recomputes due to same-value optimization
```

---

## Pattern: Aggregate Computation

Efficiently aggregate over multiple inputs:

```moonbit
let rt = Runtime::new()

let items : Array[Signal[Int]] = [
  Signal::new(rt, 10),
  Signal::new(rt, 20),
  Signal::new(rt, 30),
]

let sum = Memo::new(rt, fn() {
  let mut total = 0
  for item in items {
    total = total + item.get()
  }
  total
})

let count = items.length()
let average = Memo::new(rt, fn() { sum.get() / count })

inspect(sum.get(), content="60")
inspect(average.get(), content="20")

items[1].set(50)  // Change one item
inspect(sum.get(), content="90")
inspect(average.get(), content="30")
```

---

## Pattern: Change Notifications

Observe committed updates with `Runtime::set_on_change`:

```moonbit
let rt = Runtime::new()
let a = Signal::new(rt, 0)
let b = Signal::new(rt, 0)
let mut notifications = 0

rt.set_on_change(fn() { notifications = notifications + 1 })

// Outside batch: one callback per committed change
a.set(1)
b.set(2)
inspect(notifications, content="2")

// Inside batch: at most one callback at batch end
rt.batch(fn() {
  a.set(3)
  b.set(4)
})
inspect(notifications, content="3")
```

Useful for:
- Triggering UI refreshes
- Scheduling downstream side effects
- Collecting change metrics

---

## Anti-Pattern: Reading During Batch

Avoid reading memos inside a batch — they see pre-batch values:

```moonbit
let rt = Runtime::new()

let x = Signal::new(rt, 10)
let doubled = Memo::new(rt, fn() { x.get() * 2 })

rt.batch(fn() {
  x.set(20)
  // doubled.get() still returns 20, not 40!
  // Batch provides transactional isolation
})

// After batch, doubled.get() returns 40
```

---

## Anti-Pattern: Large Compute Functions

Keep compute functions focused:

```moonbit
// Bad: Monolithic computation
let result = Memo::new(rt, fn() {
  let a = step1(input.get())
  let b = step2(a)
  let c = step3(b)
  step4(c)
})

// Better: Composable memos
let step1_result = Memo::new(rt, fn() { step1(input.get()) })
let step2_result = Memo::new(rt, fn() { step2(step1_result.get()) })
let step3_result = Memo::new(rt, fn() { step3(step2_result.get()) })
let final_result = Memo::new(rt, fn() { step4(step3_result.get()) })
```

Benefits:
- Each step can backdate independently
- Intermediate results are cached
- Easier to debug and test

---

## Pattern: Graceful Cycle Handling

Handle potential cycles with fallback values instead of aborting:

```moonbit
let rt = Runtime::new()

// Self-referential memo that handles cycles gracefully
let memo_ref : Ref[Memo[Int]?] = { val: None }
let memo = Memo::new(rt, fn() {
  match memo_ref.val {
    Some(m) =>
      match m.get_result() {
        Ok(v) => v + 1
        Err(CycleDetected(_, _)) => 0  // Base case on cycle
      }
    None => 0
  }
})
memo_ref.val = Some(memo)

inspect(memo.get(), content="0")  // Returns fallback, doesn't abort
```

### Use Cases

- **Recursive data structures**: Tree traversal that might have back-edges
- **Plugin systems**: User-provided compute functions that might create cycles
- **Debugging**: Graceful degradation while investigating dependency issues

### Important Notes

1. **Handle errors inside compute**: If the `Err` propagates out of the compute function, the outer `get()` will still abort
2. **No spurious dependencies**: Failed `get_result()` calls don't record dependencies, so subsequent accesses work correctly
3. **State consistency**: The runtime remains usable after cycle errors

---

## Debugging

### Why Did This Memo Recompute?

Use introspection to identify which dependency triggered recomputation:

```moonbit
let rt = Runtime::new()
let x = Signal::new(rt, 10)
let y = Signal::new(rt, 20)
let sum = Memo::new(rt, fn() { x.get() + y.get() })

sum.get() |> ignore
let baseline = sum.verified_at()

// Make some changes
x.set(15)
sum.get() |> ignore

// Find the culprit
for dep_id in sum.dependencies() {
  match rt.cell_info(dep_id) {
    Some(info) => {
      if info.changed_at.value > baseline.value {
        println("Dependency " + dep_id.id.to_string() + " changed")
      }
    }
    None => ()
  }
}
```

### Analyzing Dependency Chains

Trace the full dependency path:

```moonbit
fn print_dependencies(rt : Runtime, memo : Memo[Int], depth : Int) -> Unit {
  let indent = "  ".repeat(depth)
  println(indent + "Memo " + memo.id().id.to_string())

  for dep_id in memo.dependencies() {
    match rt.cell_info(dep_id) {
      Some(info) => {
        println(indent + "  -> Cell " + dep_id.id.to_string() +
                " (changed_at=" + info.changed_at.value.to_string() + ")")
      }
      None => ()
    }
  }
}
```

### Testing Dependency Tracking

Verify that memos only depend on what they actually read:

```moonbit
test "memo only depends on x, not y" {
  let rt = Runtime::new()
  let x = Signal::new(rt, 1)
  let y = Signal::new(rt, 2)
  let uses_x_only = Memo::new(rt, fn() { x.get() * 2 })

  uses_x_only.get() |> ignore

  let deps = uses_x_only.dependencies()
  inspect(deps.contains(x.id()), content="true")
  inspect(deps.contains(y.id()), content="false")
}
```

### Understanding Backdating

Check if a memo's value actually changed:

```moonbit
let memo = Memo::new(rt, fn() { config.get().length() })
memo.get() |> ignore
let old_changed = memo.changed_at()

config.set("same_length")  // Different string, same length
memo.get() |> ignore

// Backdating: value didn't change, so changed_at is preserved
inspect(memo.changed_at() == old_changed, content="true")
```

### Debugging Cycles

When you encounter a cycle error, use the path information to understand the dependency chain:

```moonbit
match computation.get_result() {
  Err(err) => {
    let path = err.path()
    let formatted = err.format_path(rt)

    println("Cycle detected!")
    println(formatted)

    // Analyze the cycle
    println("\nDetailed path:")
    for i = 0; i < path.length(); i = i + 1 {
      match rt.cell_info(path[i]) {
        Some(info) => {
          println("  Step " + i.to_string() + ": Cell " + path[i].to_string())
          println("    Changed at: " + info.changed_at.value.to_string())
          println("    Dependencies: " + info.dependencies.length().to_string())
        }
        None => println("  Step " + i.to_string() + ": Unknown cell")
      }
    }
  }
  Ok(result) => use_result(result)
}
```

This helps identify:
- Which cells form the cycle
- The order of dependencies that created the loop
- Metadata about each cell in the cycle path

---

## Debugging Tips

### Check if a Memo Recomputed

Add logging inside compute functions during development:

```moonbit
let expensive = Memo::new(rt, fn() {
  println("Computing expensive...")
  heavy_computation(input.get())
})
```

### Verify Durability Shortcuts

High-durability memos should not log when only low-durability inputs change:

```moonbit
let config = Signal::new(rt, 100, durability=High)
let data = Signal::new(rt, 1)

let config_derived = Memo::new(rt, fn() {
  println("Config derived computing...")  // Should not print when data changes
  config.get() * 2
})

let data_derived = Memo::new(rt, fn() {
  println("Data derived computing...")
  data.get() * 2
})

config_derived.get()
data_derived.get()

data.set(2)  // Only data_derived should recompute
data_derived.get()
config_derived.get()
```
