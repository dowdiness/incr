# API Design Guidelines

This document records the design philosophy behind `incr`'s public API, the
improvements already shipped under it, and the deferred ideas. Code snippets
are illustrative, not checked.

## Design Principles

### 1. Progressive Disclosure

**Simple things simple, complex things possible:**

```moonbit
// Beginner: Just works
let count = Input(rt, 0)

// Intermediate: Optimization
let config = Input(rt, 100, durability=High)

// Advanced: Full control
let derived = Derived(rt, () => {
  match other_derived.get() {
    Ok(v) => v + 1
    Err(_) => 0
  }
})
```

### 2. Type-Driven Constraints

**Constraints only where needed:**

```moonbit
Input(rt, value)      // Constructor: no Eq needed (accepts any T)
input.set(value)      // set requires T : Eq — enables same-value optimization
input.force_set(v)    // No Eq required — always bumps revision
```

Why: maximum flexibility. Types without `Eq` can still be used (just skip the
same-value optimization).

### 3. Explicit Over Implicit

**No global state, no hidden dependencies:**

```moonbit
// ❌ Bad (implicit global runtime)
let input = Input(10)

// ✓ Good (explicit runtime)
let rt = Runtime()
let input = Input(rt, 10)

// ✓ Also good: hide the runtime behind your own context type
struct MyDb { rt : Runtime }
impl RuntimeContext for MyDb with runtime(self) { self.rt }
let input = create_input(db, 10)
```

The naming and construction direction is recorded in
[ADR 2026-05-21](../decisions/2026-05-21-public-api-ideal-naming.md).

### 4. Trait Composition

**Mix and match capabilities:**

```moonbit
// Minimal: just incremental computation
impl RuntimeContext for MyDb { ... }

// Add application-local pipeline capabilities as needed
impl RuntimeContext + ProjectSource for MyCompiler { ... }
impl RuntimeContext + ProjectSource + ProjectParser for MyFullCompiler { ... }
```

Users implement only what they need. No forced inheritance hierarchy. Keep
pipeline traits local until their concrete key, source, syntax, diagnostic, and
artifact types are stable across more than one consumer.

## Current API Strengths

### Clear Type Roles

| Type | Role | Mutability |
|------|------|------------|
| `Input[T]` | Input cell | User sets via `set()` |
| `Derived[T]` | Derived cell | Framework computes via closure |
| `Runtime` | Coordinator | Manages global state |

No confusion about what each type does.

### Read and Write Naming

Fallible derived reads own the simple names; aborting conveniences carry
`_or_abort`. Input reads stay direct because cycles are impossible there.

| Method | When to Use |
|--------|-------------|
| `set(value)` | Default input write with same-value optimization |
| `force_set(value)` | Force an input write even if unchanged |
| `get()` | Strict tracked-context read returning `Result` |
| `get_or_abort()` | Strict read convenience that aborts |
| `read()` | Permissive outside-graph read returning `Result` |
| `read_or_abort()` | Permissive read convenience that aborts |

## Shipped Improvements

These phases are implemented; they are kept here as the record of what the
principles produced. Signatures below are illustrative — `pkg.generated.mbti`
is authoritative.

### Introspection API (Phase 2A) ✓

**Goal:** Debug and understand dependency graphs.

```moonbit
// Per-cell introspection
pub fn[T] Input::id(self) -> CellId
pub fn[T] Input::durability(self) -> Durability
pub fn[T] Derived::dependencies(self) -> Array[CellId]
pub fn[T] Derived::changed_at(self) -> Revision
pub fn[T] Derived::verified_at(self) -> Revision

// Runtime introspection
pub fn Runtime::cell_info(self, id : CellId) -> CellInfo?

pub struct CellInfo {
  label : String?
  id : CellId
  changed_at : Revision
  verified_at : Revision
  durability : Durability
  dependencies : Array[CellId]
  subscribers : Array[CellId]
}
```

**Use case:**

```moonbit
// Debug: why did this derived value recompute?
for dep in expensive.dependencies() {
  match rt.cell_info(dep) {
    Some(info) =>
      if info.changed_at > expensive.verified_at() {
        println("Recomputed due to: " + dep.to_string())
      }
    None => ()
  }
}
```

### Per-Cell Change Callbacks (Phase 2B) ✓

**Goal:** Fine-grained observability without coupling to Runtime.

```moonbit
pub fn[T] Input::on_change(self, f : (T) -> Unit) -> Unit
pub fn[T] Derived::on_change(self, f : (T) -> Unit) -> Unit
pub fn[T] Input::clear_on_change(self) -> Unit
pub fn[T] Derived::clear_on_change(self) -> Unit
```

**Behavior:**

- Callbacks stored on cell metadata via type-erased closures
- Fire after revision bump, before the global `Runtime` on-change callback
- During batch: fires at batch end for all changed cells

### Unified Constructors with Optional Params (Phase 2C) ✓

**Goal:** Ergonomic API without builder boilerplate. MoonBit's optional
parameters replace the builder pattern:

```moonbit
Input(rt, 100)                                    // defaults
Input(rt, 100, durability=High)                   // explicit durability
Input(rt, 100, durability=High, label="config")   // both

Derived(rt, () => x.get_or_abort() * 2, label="doubled")

// RuntimeContext helpers follow the same pattern
create_input(db, value, durability=High, label="cfg")
create_derived(db, () => { ... }, label="tax")
```

This replaced separate `*_with_durability` constructors. Labels propagate
through cell metadata, `CellInfo`, and `format_path` for debugging.

### Enhanced Error Diagnostics ✓

**Goal:** Better debugging for cycle errors.

```moonbit
pub suberror CycleError {
  CycleDetected(CellId, Array[CellId], Array[String?])  // (culprit, cycle_path, labels)
}

pub fn CycleError::path(self) -> Array[CellId]
pub fn CycleError::format_path(self) -> String
```

**Use case:**

```moonbit
match derived.read() {
  Err(Cycle(err)) => println(err.format_path())
  // "Cycle detected: price → tax → price"
  Err(Disposed(_)) => println("cell disposed")
  Ok(v) => use(v)
}
```

`format_path` is pure-value: labels are snapshotted at detection time, so
rendering doesn't need a runtime handle and stays informative even if cells
are later renamed or disposed.

### Subscriber Links ✓

Reverse-edge lookup is available via `Runtime::dependents(id) -> Array[CellId]`
(and per-cell `CellInfo::subscribers`). Subscriber links are maintained
incrementally during recompute: added when a dependency is newly recorded,
removed when a dependency is dropped (dynamic dep set). Useful for impact
analysis and debugging.

## Deferred Ideas

### Method Chaining (Low Priority)

```moonbit
let rt = Runtime()
  .with_on_change(() => println("Changed!"))
```

**Trade-off:** requires mutable self, which conflicts with MoonBit's borrowing
if the runtime is already borrowed by cells. **Deferred** until usage patterns
clarify this.

### RAII Batch Guards

If MoonBit adds destructors, a `BatchGuard` whose drop auto-commits the
outermost batch would remove the closure requirement from `batch`.
**Deferred:** MoonBit doesn't have RAII/destructors yet.

## API Style Comparison

| Framework | Style | Pros | Cons |
|-----------|-------|------|------|
| **Salsa (Rust)** | Proc macros (`#[salsa::tracked]`) | Zero boilerplate | Magic, hard to debug, compile-time overhead |
| **alien-signals (JS)** | Direct functions (`signal(0)`) | Minimal, JS-idiomatic | No type safety, no compile-time checks |
| **SolidJS** | JSX integrated (`createSignal()`) | Natural for UI | Tightly coupled to UI framework |
| **incr (MoonBit)** | Explicit constructors + traits | Clear, inspectable, no magic | Slightly verbose |

**Position:** explicitness over magic. This is correct for a foundational library.

## Recommended Usage Patterns

### Pattern 1: Context-Centric API (Recommended)

**Instead of passing `Runtime` everywhere, encapsulate it:**

```moonbit
struct MyApp {
  rt : Runtime
  // Domain state
  config : Input[String]
  input : Input[String]
}

impl RuntimeContext for MyApp with runtime(self) { self.rt }

fn MyApp::new() -> MyApp {
  let rt = Runtime()
  { rt, config: Input(rt, "prod"), input: Input(rt, "") }
}

// Users never see Runtime
fn process(app : MyApp) -> Derived[String] {
  create_derived(app, () => app.input.get() + " [" + app.config.get() + "]")
}
```

**Why:** domain-driven design. `Runtime` is an implementation detail.

### Pattern 2: Trait Composition for Pipelines

**Build up application-local capabilities incrementally:**

```moonbit
// Stage 1: Just incremental
trait MyDb : RuntimeContext { ... }

// Stage 2: Add source handling over this package's ModuleKey/SourceText types
trait MyCompiler : RuntimeContext + ProjectSource { ... }

// Stage 3: Add parsing/checking over this package's concrete syntax and diagnostics
trait MyFullCompiler : RuntimeContext + ProjectSource + ProjectParser + ProjectChecker { ... }
```

**Why:** pay only for what you use. No forced methods, and no shared
stringly-typed pipeline abstraction before the domain types are real.

### Pattern 3: Graceful Cycle Handling

**Use `get()`'s `Result` for self-referential or plugin systems:**

```moonbit
let derived = Derived(rt, () => {
  match potentially_cyclic.get() {
    Ok(v) => v + 1
    Err(_) => 0  // Base case
  }
})
```

**Why:** production systems shouldn't panic. Handle errors where they occur.

## Anti-Patterns

### ❌ Anti-Pattern 1: Monolithic Compute Functions

```moonbit
// Bad: one large computation — no intermediate caching, no granular backdating
let result = Derived(rt, () => step4(step3(step2(step1(input.get())))))

// Good: composable pipeline — each stage caches and backdates independently
let step1_out = Derived(rt, () => step1(input.get()))
let step2_out = Derived(rt, () => step2(step1_out.get_or_abort()))
let result = Derived(rt, () => step3(step2_out.get_or_abort()))
```

### ❌ Anti-Pattern 2: Reading Derived Values During Batch

```moonbit
// Bad: batches are transactionally isolated — reads see pre-batch values
rt.batch(() => {
  x.set(20)
  println(doubled.read_or_abort())  // Still returns the old value!
})

// Good: read after commit
rt.batch(() => x.set(20))
println(doubled.read_or_abort())  // Now sees the new value
```

### ❌ Anti-Pattern 3: Ignoring Same-Value Optimization

```moonbit
// Wasteful: forces downstream recomputation even when the value is unchanged
input.force_set(value)

// Good: no-op if the value is unchanged
input.set(value)
```

Only use `force_set()` when you genuinely need to force an update (e.g., types
without `Eq`, or external side effects tied to writes).

## Naming Rationale (Completed Rename)

The public API rename recorded in
[ADR 2026-05-21](../decisions/2026-05-21-public-api-ideal-naming.md) is
complete. The rationale is kept because it explains what the current names
mean:

| Former | Current | Rationale |
|--------|---------|-----------|
| `Signal` | `Input` | User-provided value that enters the graph. |
| `Memo` | `Derived` | Lazy value derived from graph dependencies. |
| `Reactive` | `EagerDerived` | Clearly "a Derived that recomputes eagerly." |
| `HybridMemo` | `ReachableDerived` | Lazy derived value that participates in reachability propagation through eager/rooted dependents — it has no dirty ping. |
| `MemoMap` | `DerivedMap` | Map-shaped derived computation; each key lazily owns one derived value. |
| `TrackedCell` | `InputField` | Input cell intended to live as a field of a larger tracked value. |
| `Observer` | `Watch` | Long-lived outside read handle that roots a derived value. |
| `FunctionalRelation` | `MapRelation` | Relation-shaped Datalog input keyed like a map. |
| `Readable` | `Freshness` | Capability for querying whether a node is fresh. |
| `Trackable` | `InputFieldOwner` | Structured value that owns input fields. |
| `Database` | `RuntimeContext` | User context that exposes an `incr` runtime. |
| `Effect`, `Relation`, `Rule` | (unchanged) | Already clear. |

The names describe graph role rather than ecosystem vocabulary or
implementation technique: inputs are set from outside the graph; derived
values are computed from dependencies. Custom struct constructors are the
primary construction API; `create_*` free helpers exist for `RuntimeContext`
consumers.

## Documentation Strategy

### For New Users

**Show in this order:**

1. **Direct constructors and `RuntimeContext`** (hide the runtime in app types)
2. **Basic inputs and derived values**
3. **Error handling** (`get()` / `read()` return `Result`; `_or_abort` conveniences)
4. **Optimization** (durability, batching)
5. **Advanced** (introspection, custom traits)

### For Library Authors

**Emphasize:**

1. **Trait design** (`RuntimeContext`, `Freshness`; application pipeline traits should live in consumer packages)
2. **Type constraints** (when to require `Eq`)
3. **Performance** (backdating, durability shortcuts)
4. **Correctness** (cycle detection, batch semantics)

## API Stability

### Naming Surface

Facade names are the API: `Input[T]`, `Derived[T]`, `DerivedMap[K, V]`,
`ReachableDerived[T]`, `EagerDerived[T]`, `InputField[T]`, `MapRelation[K, V]`,
`Effect`, `Relation[T]`, `Runtime`, `Observer`; traits `RuntimeContext` /
`Freshness` / `InputFieldOwner`. As of v0.13.0 the compatibility names
(`Reactive[T]`, `TrackedCell[T]`, `FunctionalRelation[K, V]`, and traits
`Database` / `Readable` / `Trackable`) have been removed as a direct breaking
cleanup (no deprecation stage). The full removal mapping, plus the removed
pre-v0.12.0 names, is in the [CHANGELOG](../../CHANGELOG.md).

### Additive (Safe to Add)

- New methods on existing types (e.g., `on_change`)
- New traits (e.g., introspection)
- New optional parameters on constructors

### Removed / Internal

- Pipeline traits (`Sourceable`, `Parseable`, etc.) were removed; define application-local build traits with concrete domain types instead
- Internal details (`CellMeta`, `ActiveQuery`) — not public API

## Conclusion

`incr`'s API prioritizes **clarity, type safety, and explicitness** over
brevity — no magic, compiler-checked mistakes, no hidden global state. That is
the right trade-off for a foundational library. Future work adds
discoverability, observability, and composability without giving those up.
