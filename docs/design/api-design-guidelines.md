# API Design Guidelines

This document explains the design philosophy behind `incr`'s API and planned improvements.

## Design Principles

### 1. Progressive Disclosure

**Simple things simple, complex things possible:**

```moonbit
// Beginner: Just works
let count = Signal(rt, 0)

// Intermediate: Optimization
let config = Signal(rt, 100, durability=High)

// Advanced: Full control
let memo = Memo(rt, () => {
  match other_memo.get_result() {
    Ok(v) => v + 1
    Err(CycleDetected(_, _)) => 0
  }
})
```

### 2. Type-Driven Constraints

**Constraints only where needed:**

```moonbit
Signal(rt, value)          // Constructor: no Eq needed (accepts any T)
sig.set(value)             // set requires T : Eq — enables same-value optimization
sig.set_unconditional(v)   // No Eq required — always bumps revision
```

Why: Maximum flexibility. Types without `Eq` can still be used (just skip optimization).

### 3. Explicit Over Implicit

**No global state, no hidden dependencies:**

```moonbit
// ❌ Bad (implicit global runtime)
let sig = Signal(10)

// ✓ Good (explicit runtime)
let rt = Runtime()
let sig = Signal(rt, 10)

// ✓ Better in current API (database pattern)
struct MyDb { rt : Runtime }
impl Database for MyDb with runtime(self) { self.rt }
let sig = create_signal(db, 10)
```

Future naming: [ADR 2026-05-21](../decisions/2026-05-21-public-api-ideal-naming.md)
renames this capability to `RuntimeContext` and treats custom struct
constructors as the primary construction API. The current `Database` /
`create_*` shape remains documented here as current API, not as the ideal
final surface.

### 4. Trait Composition

**Mix and match capabilities:**

```moonbit
// Minimal: just incremental computation
impl Database for MyDb { ... }

// Add application-local pipeline capabilities as needed
impl Database + ProjectSource for MyCompiler { ... }
impl Database + ProjectSource + ProjectParser for MyFullCompiler { ... }
```

Users implement only what they need. No forced inheritance hierarchy. Keep
pipeline traits local until their concrete key, source, syntax, diagnostic, and
artifact types are stable across more than one consumer.

## Current API Strengths

### Clear Type Roles

| Type | Role | Mutability |
|------|------|------------|
| `Signal[T]` | Input cell | User sets via `set()` |
| `Memo[T]` | Derived cell | Framework computes via closure |
| `Runtime` | Coordinator | Manages global state |

No confusion about what each type does.

### Current Dual APIs for Error Handling

```moonbit
// Prototyping: fail fast
let value = memo.get()  // Aborts on cycle

// Production: graceful handling
match memo.get_result() {
  Ok(v) => use(v)
  Err(CycleDetected(cell, path)) => fallback()
}
```

Current releases support a smooth onboarding path: start simple, add
robustness later. The accepted ideal API flips the default for fallible derived
reads so recoverable `Result` reads use the shortest names and aborting
shortcuts carry `_or_abort`.

### Read Method Naming

Current API:

| Method | When to Use |
|--------|-------------|
| `set(value)` | Default input write with same-value optimization |
| `set_unconditional(value)` | Force recomputation even if unchanged |
| `get()` | Aborting derived read |
| `get_result()` | Recoverable derived read |

Ideal API from [ADR 2026-05-21](../decisions/2026-05-21-public-api-ideal-naming.md):

| Method | When to Use |
|--------|-------------|
| `get()` | Strict graph read returning `Result` |
| `get_or_abort()` | Strict graph read convenience that aborts |
| `read()` | Permissive read returning `Result` |
| `read_or_abort()` | Permissive read convenience that aborts |
| `force_set(value)` | Force an input write even if unchanged |

## Improvements

### Phase 2A: Introspection API ✓

**Goal:** Debug and understand dependency graphs.

```moonbit
// Per-cell introspection
pub fn[T] Signal::id(self) -> CellId
pub fn[T] Signal::durability(self) -> Durability
pub fn[T] Memo::dependencies(self) -> Array[CellId]
pub fn[T] Memo::changed_at(self) -> Revision
pub fn[T] Memo::verified_at(self) -> Revision

// Runtime introspection
pub fn Runtime::cell_info(self, id : CellId) -> CellInfo?

pub struct CellInfo {
  pub label : String?
  pub id : CellId
  pub changed_at : Revision
  pub verified_at : Revision
  pub durability : Durability
  pub dependencies : Array[CellId]
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

### Phase 2B: Per-Cell Change Callbacks ✓

**Goal:** Fine-grained observability without coupling to Runtime.

```moonbit
pub fn[T] Signal::on_change(self, f : (T) -> Unit) -> Unit
pub fn[T] Memo::on_change(self, f : (T) -> Unit) -> Unit
pub fn[T] Signal::clear_on_change(self) -> Unit
pub fn[T] Memo::clear_on_change(self) -> Unit
```

**Use case:**

```moonbit
let count = Signal(rt, 0)
count.on_change(new_val => println("Count: " + new_val.to_string()))

let doubled = Memo(rt, () => count.get() * 2)
doubled.on_change(new_val => update_ui(new_val))
```

**Behavior:**

- Callbacks stored on `CellMeta` via type-erased closures
- Fire after revision bump, before `Runtime::fire_on_change`
- During batch: fires at batch end for all changed cells

### Phase 2C: Unified Constructors with Optional Params ✓

**Goal:** Ergonomic API without builder boilerplate.

Instead of a builder pattern, MoonBit's optional parameters provide a cleaner solution:

```moonbit
// Signal: durability and label are optional
Signal(rt, 100)                                    // defaults
Signal(rt, 100, durability=High)                   // explicit durability
Signal(rt, 100, durability=High, label="config")   // both

// Memo: label is optional
Memo(rt, () => x.get() * 2)                    // default
Memo(rt, () => x.get() * 2, label="doubled")   // with label

// Helper functions follow the same pattern
create_signal(db, value, durability=High, label="cfg")
create_memo(db, () => { ... }, label="tax")
```

This replaced `Signal::new_with_durability` and `create_signal_durable` with unified constructors. Labels propagate through `CellMeta`, `CellInfo`, and `format_path` for debugging.

### Phase 2A: Enhanced Error Diagnostics (High Priority) — Implemented

**Goal:** Better debugging for cycle errors.

```moonbit
pub(all) suberror CycleError {
  CycleDetected(CellId, Array[CellId], Array[String?])  // (culprit, cycle_path, labels)
}

pub fn CycleError::path(self) -> Array[CellId]
pub fn CycleError::format_path(self) -> String
```

**Use case:**

```moonbit
match memo.get_result() {
  Err(err) => {
    println(err.format_path())
    // "Cycle detected: price → tax → price"
  }
  Ok(v) => v
}
```

`format_path` is pure-value: labels are snapshotted at detection time, so
rendering doesn't need a runtime handle and stays informative even if cells
are later renamed or disposed.

### Phase 3: Method Chaining (Low Priority)

**Goal:** Fluent configuration.

```moonbit
pub fn Runtime::with_on_change(self, f : () -> Unit) -> Runtime {
  self.set_on_change(f)
  self
}

// Usage
let rt = Runtime()
  .with_on_change(() => println("Changed!"))
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

  fn new() -> MyApp
}

impl Database for MyApp with runtime(self) { self.rt }

fn MyApp::new() -> MyApp {
  let rt = Runtime()
  let app = {
    rt,
    config: Signal(rt, "prod"),
    input: Signal(rt, "")
  }
  app
}

// Users never see Runtime
fn process(app : MyApp) -> Memo[String] {
  create_memo(app, () => app.input.get().to_upper() + " [" + app.config.get() + "]")
}
```

**Why:** Domain-driven design. `Runtime` is an implementation detail.

### Pattern 2: Trait Composition for Pipelines

**Build up application-local capabilities incrementally:**

```moonbit
// Stage 1: Just incremental
trait MyDb : Database { ... }

// Stage 2: Add source handling over this package's ModuleKey/SourceText types
trait MyCompiler : Database + ProjectSource { ... }

// Stage 3: Add parsing/checking over this package's concrete syntax and diagnostics
trait MyFullCompiler : Database + ProjectSource + ProjectParser + ProjectChecker { ... }
```

**Why:** Pay only for what you use. No forced methods, and no shared stringly-typed
pipeline abstraction before the domain types are real.

### Pattern 3: Graceful Cycle Handling

**Use `get_result()` for self-referential or plugin systems:**

```moonbit
let memo = Memo(rt, () => {
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
let result = Memo(rt, () => {
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
let step1_out = Memo(rt, () => step1(input.get()))
let step2_out = Memo(rt, () => step2(step1_out.get()))
let step3_out = Memo(rt, () => step3(step2_out.get()))
let result = Memo(rt, () => step4(step3_out.get()))
```

### ❌ Anti-Pattern 2: Reading Memos During Batch

```moonbit
// Bad: Unexpected behavior
rt.batch(() => {
  x.set(20)
  println(doubled.get())  // Still returns old value!
})
```

**Problem:** Batches provide transactional isolation — reads see pre-batch values.

**Solution:** Read after batch:

```moonbit
// Good: Read after commit
rt.batch(() => {
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

### Accepted: Ideal Public API Naming

| Current | Proposed | Rationale |
|---------|----------|-----------|
| `Signal` | `Input` | User-provided value that enters the graph. |
| `Memo` | `Derived` | Lazy value derived from graph dependencies. |
| `Reactive` | `EagerDerived` | Clearly "a Derived that recomputes eagerly." Current name sounds unrelated to `Memo` even though both are derived computations. |
| `HybridMemo` | `ReachableDerived` | Lazy derived value that participates in reachability propagation through eager/rooted dependents. |
| `MemoMap` | `DerivedMap` | Map-shaped derived computation; each key lazily owns one derived value. |
| `TrackedCell` | `InputField` | Input cell intended to live as a field of a larger tracked value. |
| `Observer` | `Watch` | Long-lived outside read handle that roots a derived value. |
| `FunctionalRelation` | `MapRelation` | Relation-shaped Datalog input keyed like a map. |
| `Readable` | `Freshness` | Capability for querying whether a node is fresh. |
| `Trackable` | `InputFieldOwner` | Structured value that owns input fields. |
| `Database` | `RuntimeContext` | User context that exposes an `incr` runtime. |
| `Effect` | `Effect` | No change — already clear. |
| `Relation` | `Relation` | No change. |
| `Rule` | `Rule` | No change. |

**Why `Input` / `Derived` over `Signal` / `Memo`:** These names describe graph
role rather than ecosystem vocabulary or implementation technique. Inputs are
set from outside the graph; derived values are computed from dependencies.

**Why `ReachableDerived`:** The current `HybridMemo` has no dirty ping. It is
lazy like `Memo`; its deterministic trait is that it participates in
reachability propagation through eager/rooted dependents.

**Read method convention:** Fallible derived reads should own the simple names:
`get` for strict graph reads and `read` for permissive reads. Aborting
conveniences should carry `_or_abort`. Input reads remain direct because cycles
are impossible.

**Construction convention:** Use custom struct constructors as the primary API.
The ideal final API does not rely on `create_*` free helpers.

See [ADR 2026-05-21](../decisions/2026-05-21-public-api-ideal-naming.md). The
ADR records a target design; migration staging belongs in a future plan.

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
  let _guard = BatchGuard(rt)
  x.set(1)
  y.set(2)
  // Auto-commits when guard drops
}
```

**Why deferred:** MoonBit doesn't have RAII/destructors yet. Revisit when language supports it.

### Subscriber Links API (Implemented)

Reverse-edge lookup is available via:

```moonbit
pub fn Runtime::dependents(self, id : CellId) -> Array[CellId]
pub fn[T] Memo::dependents(self) -> Array[CellId]
```

Subscriber links are maintained incrementally in `force_recompute`: added when a dependency is newly recorded, removed when a dependency is dropped (dynamic dep set). Useful for impact analysis and debugging.

## Documentation Strategy

### For New Users

**Show in this order:**

1. **Database pattern** (current API; target name `RuntimeContext`)
2. **Basic signals and memos** (simple API)
3. **Error handling** (current API: `get()` → `get_result()`; target API:
   fallible `get()` / `read()` with `_or_abort` conveniences)
4. **Optimization** (durability, batching)
5. **Advanced** (introspection, custom traits)

### For Library Authors

**Emphasize:**

1. **Trait design** (`Database` / target `RuntimeContext`, `Readable` /
   target `Freshness`; application pipeline traits should live in consumer packages)
2. **Type constraints** (when to require `Eq`)
3. **Performance** (backdating, durability shortcuts)
4. **Correctness** (cycle detection, batch semantics)

## API Stability

### Current Compatibility Surface

Until a migration plan lands, code should continue to treat the current names
as the source of truth:

- Core types: `Signal[T]`, `Memo[T]`, `MemoMap[K, V]`, `HybridMemo[T]`,
  `Reactive[T]`, `Effect`, `Relation[T]`, `FunctionalRelation[K, V]`,
  `Runtime`
- Core methods: constructors (`Signal(rt, ...)`, `Memo(rt, ...)`), `get`,
  `set`, `batch`
- Core traits: `Database`, `Readable`, `Trackable`
- Error types: `CycleError`

The accepted ideal naming ADR is explicitly a future target, not a statement
that these names have already changed.

### Additive (Safe to Add)

- New methods on existing types (e.g., `on_change`)
- New traits (e.g., introspection)
- New optional parameters via builder pattern

### Deprecated / Internal

- Pipeline traits (`Sourceable`, `Parseable`, etc.) — deprecated early sketch; define application-local build traits with concrete domain types instead
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
