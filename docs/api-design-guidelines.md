# API Design Guidelines

This document explains the design philosophy behind `incr`'s API and planned improvements.

## Design Principles

### 1. Progressive Disclosure

**Simple things simple, complex things possible:**

```moonbit
// Beginner: Just works
let count = Signal::new(rt, 0)

// Intermediate: Optimization
let config = Signal::new_with_durability(rt, 100, High)

// Advanced: Full control
let memo = Memo::new(rt, fn() {
  match other_memo.get_result() {
    Ok(v) => v + 1
    Err(CycleDetected(_, _)) => 0
  }
})
```

### 2. Type-Driven Constraints

**Constraints only where needed:**

```moonbit
Signal::new[T](rt, value)              // No Eq needed
Signal::set[T : Eq](value)             // Eq enables same-value optimization
Signal::set_unconditional[T](value)    // No Eq, always bumps revision
```

Why: Maximum flexibility. Types without `Eq` can still be used (just skip optimization).

### 3. Explicit Over Implicit

**No global state, no hidden dependencies:**

```moonbit
// ❌ Bad (implicit global runtime)
let sig = Signal::new(10)

// ✓ Good (explicit runtime)
let rt = Runtime::new()
let sig = Signal::new(rt, 10)

// ✓ Better (database pattern)
struct MyDb { rt : Runtime }
impl IncrDb for MyDb with runtime(self) { self.rt }
let sig = create_signal(db, 10)
```

### 4. Trait Composition

**Mix and match capabilities:**

```moonbit
// Minimal: just incremental computation
impl IncrDb for MyDb { ... }

// Add pipeline stages as needed
impl IncrDb + Sourceable for MyCompiler { ... }
impl IncrDb + Sourceable + Parseable for MyFullCompiler { ... }
```

Users implement only what they need. No forced inheritance hierarchy.

## Current API Strengths

### Clear Type Roles

| Type | Role | Mutability |
|------|------|------------|
| `Signal[T]` | Input cell | User sets via `set()` |
| `Memo[T]` | Derived cell | Framework computes via closure |
| `Runtime` | Coordinator | Manages global state |

No confusion about what each type does.

### Dual APIs for Error Handling

```moonbit
// Prototyping: fail fast
let value = memo.get()  // Aborts on cycle

// Production: graceful handling
match memo.get_result() {
  Ok(v) => use(v)
  Err(CycleDetected(cell, path)) => fallback()
}
```

Smooth onboarding path: start simple, add robustness later.

### Smart Method Naming

| Method | When to Use |
|--------|-------------|
| `set(value)` | Default (with same-value optimization) |
| `set_unconditional(value)` | Force recomputation even if unchanged |
| `get()` | Default (abort on error) |
| `get_result()` | When error handling needed |

Naming makes behavior obvious without reading docs.

## Planned Improvements

### Phase 2A: Introspection API (High Priority)

**Goal:** Debug and understand dependency graphs.

```moonbit
// Per-cell introspection
pub fn[T] Signal::id(self) -> CellId
pub fn[T] Signal::durability(self) -> Durability
pub fn[T] Memo::dependencies(self) -> Array[CellId]
pub fn[T] Memo::changed_at(self) -> Revision
pub fn[T] Memo::verified_at(self) -> Revision

// Runtime introspection
pub fn Runtime::cell_info(self, id : CellId) -> CellInfo

pub struct CellInfo {
  id : CellId
  kind : CellKind
  changed_at : Revision
  verified_at : Revision
  durability : Durability
  dependencies : Array[CellId]
}
```

**Use case:**

```moonbit
// Debug: why did this memo recompute?
if !expensive.is_up_to_date() {
  for dep in expensive.dependencies() {
    let info = rt.cell_info(dep)
    if info.changed_at > expensive.verified_at() {
      println("Recomputed due to: " + dep.to_string())
    }
  }
}
```

### Phase 2B: Per-Cell Change Callbacks (High Priority)

**Goal:** Fine-grained observability without coupling to Runtime.

```moonbit
pub fn[T] Signal::on_change(self, f : (T) -> Unit) -> Unit
pub fn[T] Memo::on_change(self, f : (T) -> Unit) -> Unit
```

**Use case:**

```moonbit
let count = Signal::new(rt, 0)
count.on_change(fn(new_val) {
  println("Count: " + new_val.to_string())
})

let doubled = Memo::new(rt, fn() { count.get() * 2 })
doubled.on_change(fn(new_val) {
  update_ui(new_val)
})
```

**Implementation notes:**

- Callbacks stored on `CellMeta` as `on_change : ((T) -> Unit)?`
- Requires type erasure (similar to `recompute_and_check`)
- Fire after revision bump, before `Runtime::fire_on_change`

### Phase 2C: Builder Pattern (Medium Priority)

**Goal:** Future-proof for additional options.

```moonbit
pub struct SignalBuilder[T] {
  rt : Runtime
  value : T
  durability : Durability
  label : String?  // For debugging/introspection
}

pub fn[T] Signal::builder(rt : Runtime) -> SignalBuilder[T]

impl[T] SignalBuilder[T] {
  pub fn with_value(self, value : T) -> Self
  pub fn with_durability(self, dur : Durability) -> Self
  pub fn with_label(self, label : String) -> Self
  pub fn build(self) -> Signal[T]
}
```

**Use case:**

```moonbit
let config = Signal::builder(rt)
  .with_value(100)
  .with_durability(High)
  .with_label("app_config")
  .build()
```

**Migration:** Keep existing `new()` and `new_with_durability()` — builder is additive.

### Phase 2A: Enhanced Error Diagnostics (High Priority) — Implemented

**Goal:** Better debugging for cycle errors.

```moonbit
pub suberror CycleError {
  CycleDetected(CellId, Array[CellId])  // (culprit, cycle_path)
}

pub fn CycleError::path(self) -> Array[CellId]
pub fn CycleError::format_path(self, rt : Runtime) -> String
```

**Use case:**

```moonbit
match memo.get_result() {
  Err(err) => {
    println(err.format_path(rt))
    // "Cycle detected: Cell[0] → Cell[1] → Cell[2] → Cell[0]"
  }
  Ok(v) => v
}
```

### Phase 3: Method Chaining (Low Priority)

**Goal:** Fluent configuration.

```moonbit
pub fn Runtime::with_on_change(self, f : () -> Unit) -> Runtime {
  self.set_on_change(f)
  self
}

// Usage
let rt = Runtime::new()
  .with_on_change(fn() { println("Changed!") })
```

**Trade-off:** Requires mutable self, which conflicts with MoonBit's borrowing if runtime is already borrowed by signals. **Deferred** until usage patterns clarify this.

## API Style Comparison

| Framework | Style | Pros | Cons |
|-----------|-------|------|------|
| **Salsa (Rust)** | Proc macros (`#[salsa::tracked]`) | Zero boilerplate | Magic, hard to debug, compile-time overhead |
| **alien-signals (JS)** | Direct functions (`signal(0)`) | Minimal, JS-idiomatic | No type safety, no compile-time checks |
| **SolidJS** | JSX integrated (`createSignal()`) | Natural for UI | Tightly coupled to UI framework |
| **incr (MoonBit)** | Explicit constructors + traits | Clear, inspectable, no magic | Slightly verbose |

**Position:** Explicitness over magic. This is correct for a foundational library.

## Recommended Usage Patterns

### Pattern 1: Database-Centric API (Recommended)

**Instead of passing `Runtime` everywhere, encapsulate it:**

```moonbit
struct MyApp {
  rt : Runtime
  // Domain state
  config : Signal[String]
  input : Signal[String]
}

impl IncrDb for MyApp with runtime(self) { self.rt }

fn MyApp::new() -> MyApp {
  let rt = Runtime::new()
  let app = {
    rt,
    config: Signal::new(rt, "prod"),
    input: Signal::new(rt, "")
  }
  app
}

// Users never see Runtime
fn process(app : MyApp) -> Memo[String] {
  create_memo(app, fn() {
    app.input.get().to_upper() + " [" + app.config.get() + "]"
  })
}
```

**Why:** Domain-driven design. `Runtime` is an implementation detail.

### Pattern 2: Trait Composition for Pipelines

**Build up capabilities incrementally:**

```moonbit
// Stage 1: Just incremental
trait MyDb : IncrDb { ... }

// Stage 2: Add source handling
trait MyCompiler : IncrDb + Sourceable { ... }

// Stage 3: Full pipeline
trait MyFullCompiler : IncrDb + Sourceable + Parseable + Checkable { ... }
```

**Why:** Pay only for what you use. No forced methods.

### Pattern 3: Graceful Cycle Handling

**Use `get_result()` for self-referential or plugin systems:**

```moonbit
let memo = Memo::new(rt, fn() {
  match potentially_cyclic.get_result() {
    Ok(v) => v + 1
    Err(CycleDetected(_, _)) => 0  // Base case
  }
})
```

**Why:** Production systems shouldn't panic. Handle errors where they occur.

## Anti-Patterns

### ❌ Anti-Pattern 1: Monolithic Compute Functions

```moonbit
// Bad: Large computation
let result = Memo::new(rt, fn() {
  let a = step1(input.get())
  let b = step2(a)
  let c = step3(b)
  step4(c)
})
```

**Problem:** No intermediate caching, no granular backdating.

**Solution:** Break into composable memos:

```moonbit
// Good: Composable pipeline
let step1_out = Memo::new(rt, fn() { step1(input.get()) })
let step2_out = Memo::new(rt, fn() { step2(step1_out.get()) })
let step3_out = Memo::new(rt, fn() { step3(step2_out.get()) })
let result = Memo::new(rt, fn() { step4(step3_out.get()) })
```

### ❌ Anti-Pattern 2: Reading Memos During Batch

```moonbit
// Bad: Unexpected behavior
rt.batch(fn() {
  x.set(20)
  println(doubled.get())  // Still returns old value!
})
```

**Problem:** Batches provide transactional isolation — reads see pre-batch values.

**Solution:** Read after batch:

```moonbit
// Good: Read after commit
rt.batch(fn() {
  x.set(20)
})
println(doubled.get())  // Now sees new value
```

### ❌ Anti-Pattern 3: Ignoring Same-Value Optimization

```moonbit
// Wasteful: Always use set_unconditional
sig.set_unconditional(value)
```

**Problem:** Forces downstream recomputation even when value unchanged.

**Solution:** Use `set()` by default:

```moonbit
// Good: Automatic optimization
sig.set(value)  // No-op if value unchanged
```

Only use `set_unconditional()` when you genuinely need to force update (e.g., types without `Eq`, or external side effects tied to writes).

## Future Considerations

### Deferred: RAII Batch Guards

**If MoonBit adds destructors:**

```moonbit
pub struct BatchGuard {
  rt : Runtime
}

impl Drop for BatchGuard {
  drop(self) {
    // Auto-commit on scope exit
    if self.rt.batch_depth == 1 {
      self.rt.commit_batch()
    }
    self.rt.batch_depth -= 1
  }
}

// Usage
{
  let _guard = BatchGuard::new(rt)
  x.set(1)
  y.set(2)
  // Auto-commits when guard drops
}
```

**Why deferred:** MoonBit doesn't have RAII/destructors yet. Revisit when language supports it.

### Deferred: Subscriber Links API

**If Phase 4 adds reverse edges:**

```moonbit
pub fn Runtime::dependents(self, id : CellId) -> Array[CellId]
pub fn[T] Memo::dependents(self) -> Array[CellId]
```

**Why deferred:** Requires architectural change (bidirectional edges). See ROADMAP Phase 4.

## Documentation Strategy

### For New Users

**Show in this order:**

1. **Database pattern** (hide Runtime details)
2. **Basic signals and memos** (simple API)
3. **Error handling** (`get()` → `get_result()`)
4. **Optimization** (durability, batching)
5. **Advanced** (introspection, custom traits)

### For Library Authors

**Emphasize:**

1. **Trait design** (`IncrDb`, `Readable`, pipeline traits)
2. **Type constraints** (when to require `Eq`)
3. **Performance** (backdating, durability shortcuts)
4. **Correctness** (cycle detection, batch semantics)

## API Stability Guarantees

### Stable (Won't Break)

- Core types: `Signal[T]`, `Memo[T]`, `Runtime`
- Core methods: `new`, `get`, `set`, `batch`
- Core traits: `IncrDb`, `Readable`
- Error types: `CycleError`

### Additive (Safe to Add)

- New methods on existing types (e.g., `on_change`)
- New traits (e.g., introspection)
- New optional parameters via builder pattern

### Experimental (May Change)

- Pipeline traits (`Sourceable`, `Parseable`, etc.) — API shape still evolving
- Internal details (`CellMeta`, `ActiveQuery`) — not public API

## Conclusion

`incr`'s API prioritizes **clarity, type safety, and explicitness** over brevity. This is the right trade-off for a foundational library:

- **Clarity:** No magic, easy to debug
- **Type safety:** Compiler catches mistakes
- **Explicitness:** No hidden global state

Future improvements will maintain these principles while adding:

- **Discoverability:** Better ergonomics for common cases
- **Observability:** Introspection and debugging tools
- **Composability:** Trait-based extension points

The goal: A library that's easy to start with, powerful to scale with, and pleasant to maintain.
