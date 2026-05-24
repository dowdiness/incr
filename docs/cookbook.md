# Cookbook

Common patterns and recipes for using `incr` effectively. Checked variants of the highest-value target facade snippets live in [`cookbook_examples.mbt.md`](cookbook_examples.mbt.md).

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
let rt = Runtime()

let a = Input(rt, 10)
let b = Derived(rt, () => a.get() * 2)
let c = Derived(rt, () => a.get() + 5)
let d = Derived(rt, () => b.get_or_abort() + c.get_or_abort())

inspect(d.read_or_abort(), content="35")  // (10*2) + (10+5)

a.set(20)
inspect(d.read_or_abort(), content="65")  // (20*2) + (20+5)
```

`incr` handles diamonds correctly — `a` is only read once per computation of each derived value.

---

## Pattern: Conditional Dependencies

Dependencies can vary based on runtime conditions:

```moonbit
let rt = Runtime()

let use_cache = Input(rt, true)
let cache = Input(rt, "cached_value")
let expensive_source = Input(rt, "computed_value")

let result = Derived(rt, () => {
  if use_cache.get() {
    cache.get()
  } else {
    expensive_source.get()
  }
})

// With caching enabled
inspect(result.read_or_abort(), content="cached_value")

// Changes to expensive_source don't trigger recomputation
expensive_source.set("new_computed")
inspect(result.read_or_abort(), content="cached_value")  // Still cached

// Switch to computed mode
use_cache.set(false)
inspect(result.read_or_abort(), content="new_computed")
```

---

## Pattern: Configuration + Data Separation

Use durability to optimize stable configuration:

```moonbit
let rt = Runtime()

// Configuration changes rarely
let multiplier = Input(rt, 1.5, durability=High)
let precision = Input(rt, 2, durability=High)

// Data changes frequently
let measurements : Array[Input[Double]] = []
for i = 0; i < 1000; i = i + 1 {
  measurements.push(Input(rt, 0.0))
}

// Config-only computation
let config_factor = Derived(rt, () => multiplier.get() * 10.0.pow(precision.get().to_double()))

// Mixed computation
let process = (i : Int) => Derived(rt, () => {
  measurements[i].get() * config_factor.get_or_abort()
})
```

When measurements change:
- `config_factor` skips verification entirely when only lower-durability data changed
- Only affected `process` derived values recompute

---

## Pattern: Atomic Multi-Update

Update related inputs together:

```moonbit
let rt = Runtime()

let x = Input(rt, 0)
let y = Input(rt, 0)
let position = Derived(rt, () => (x.get(), y.get()))

// Without batch: two revision bumps, position could see inconsistent state
// With batch: single revision bump, atomic update
rt.batch(() => {
  x.set(100)
  y.set(200)
})

inspect(position.read_or_abort(), content="(100, 200)")
```

---

## Pattern: Tentative Updates with Rollback

Use batch semantics for speculative changes:

```moonbit
let rt = Runtime()

let value = Input(rt, 10)
let derived = Derived(rt, () => value.get() * 2)

// Get initial state
let initial = value.get()

rt.batch(() => {
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

Derive default values from other inputs:

```moonbit
let rt = Runtime()

let user_override : Input[Int?] = Input(rt, None)
let computed_default = Input(rt, 100)

let effective_value = Derived(rt, () => {
  match user_override.get() {
    Some(v) => v
    None => computed_default.get()
  }
})

inspect(effective_value.read_or_abort(), content="100")  // Uses default

user_override.set(Some(42))
inspect(effective_value.read_or_abort(), content="42")   // Uses override
```

---

## Pattern: Layered Caching

Build computation layers with natural caching:

```moonbit
let rt = Runtime()

// Raw input
let raw_data = Input(rt, "  Hello World  ")

// Layer 1: Normalize
let normalized = Derived(rt, () => raw_data.get().trim())

// Layer 2: Transform
let transformed = Derived(rt, () => normalized.get_or_abort().to_lower())

// Layer 3: Format
let formatted = Derived(rt, () => "[" + transformed.get_or_abort() + "]")

inspect(formatted.read_or_abort(), content="[hello world]")

// Change input
raw_data.set("  Hello World  ")  // Same after trim — no-op!
// Nothing recomputes due to same-value optimization
```

---

## Pattern: Backdating with Custom Equality

Backdating suppresses downstream recomputation when a derived value's output is equal to its previous value. The comparison uses the type's `Eq` implementation, so you control exactly what "equal" means. This is useful when your type carries metadata that downstream consumers don't care about.

### Ignoring a Generation Counter

A common case: a value has a `generation` or `version` field that increments on every write, but downstream derived values only care about the semantic content.

```moonbit
struct Versioned {
  value      : Int
  generation : Int // bumped on every recomputation — not semantically meaningful
}

impl Eq for Versioned with equal(self, other) -> Bool {
  self.value == other.value  // generation intentionally excluded
}
```

```moonbit
let rt = Runtime()
let input = Input(rt, 100, label="input")

let mut gen = 0
let versioned = Derived(rt, () => {
  gen = gen + 1
  Versioned(input.get() / 10, gen)  // value=10, generation always increments
}, label="versioned")

let handler = Derived(rt, () => {
  versioned.get_or_abort().value * 2  // only reads .value
}, label="handler")

inspect(handler.read_or_abort(), content="20")  // Computes: Versioned(10, gen=1) → 20

input.set(105)                           // value still 10 (105/10 = 10), gen=2
inspect(handler.read_or_abort(), content="20")  // handler does NOT recompute — backdated
inspect(gen, content="2")                // versioned recomputed, but Eq said same value
```

`versioned` recomputed because `input` changed, but `handler` was skipped: the new `Versioned(10, 2)` equals the old `Versioned(10, 1)` under the custom `Eq`, so downstream derived values did not see a change.

### Ignoring Unstable Fields in Enums

The same pattern applies to enum variants where some fields are stable (drive behavior) and others are incidental (logging, diagnostics):

```moonbit
enum Status {
  Loading(progress~ : Int)
  Ready(data~ : Int)
  Error(code~ : Int, message~ : String)
}

impl Eq for Status with equal(self, other) -> Bool {
  match (self, other) {
    (Loading(progress=p1),  Loading(progress=p2))  => p1 == p2
    (Ready(data=d1),        Ready(data=d2))         => d1 == d2
    (Error(code=c1, ..),    Error(code=c2, ..))     => c1 == c2  // message excluded
    _ => false
  }
}
```

```moonbit
let rt = Runtime()
let error_code = Input(rt, 404, label="error_code")
let error_msg  = Input(rt, "Not Found", label="error_msg")

let status = Derived(rt, () => Error(code=error_code.get(), message=error_msg.get()), label="status")
let handler = Derived(rt, () => match status.get_or_abort() {
  Error(code=c, ..) => "Error: " + c.to_string()
  Ready(data=d)     => "Data: " + d.to_string()
  Loading(progress=p) => "Loading: " + p.to_string() + "%"
}, label="handler")

inspect(handler.read_or_abort(), content="Error: 404")

error_msg.set("Page Not Found")      // Different message, same code
inspect(handler.read_or_abort(), content="Error: 404")  // handler does NOT recompute — backdated
```

`status` recomputed when the message changed, but `handler` was skipped because the new `Error(code=404, message="Page Not Found")` equals the old one under the custom `Eq`.

### The Footgun: Excluding Fields That Are Actually Read

**Backdating only holds when the excluded fields are never read by any downstream derived value.** If a derived value reads a field excluded from `Eq`, it will receive a stale value silently — no error, no warning.

```moonbit
// SAFE: handler only reads .value; .generation is never read downstream
let handler = Derived(rt, () => versioned.get_or_abort().value * 2)

// UNSAFE: handler reads .generation, but generation is excluded from Eq
//         When generation changes, handler will not recompute
let handler = Derived(rt, () => versioned.get_or_abort().generation)  // stale!
```

**Rule:** Only exclude a field from `Eq` if you are certain no derived value in the graph reads that field from this type's values. When in doubt, include the field in `Eq` and accept the recomputation cost.

---

## Pattern: Aggregate Computation

Efficiently aggregate over multiple inputs:

```moonbit
let rt = Runtime()

let items : Array[Input[Int]] = [
  Input(rt, 10),
  Input(rt, 20),
  Input(rt, 30),
]

let sum = Derived(rt, () => {
  let mut total = 0
  for item in items {
    total = total + item.get()
  }
  total
})

let count = items.length()
let average = Derived(rt, () => sum.get_or_abort() / count)

inspect(sum.read_or_abort(), content="60")
inspect(average.read_or_abort(), content="20")

items[1].set(50)  // Change one item
inspect(sum.read_or_abort(), content="90")
inspect(average.read_or_abort(), content="30")
```

---

## Pattern: Side-Channel Diagnostics with Accumulator

A memo's ordinary return value (a value, a type, a compiled artifact) is
often semantically distinct from log-like data it emits along the way
(diagnostics, trace events, stats). Thread return values through the memo
graph; thread the log-like data through an `Accumulator[T]`.

Producers `push` during compute. Consumers read back via
`Memo::accumulated_peek` (outside the graph) or `Memo::accumulated` (inside
another memo, with correct incremental invalidation). See the
[Accumulator API](api-reference.md#accumulatort) reference.

```moonbit nocheck
let rt = Runtime()
let width = Input(rt, -5)

let diags : Accumulator[String] = Accumulator::new(rt~, label="diags")

let checked = Memo(rt, fn() raise {
  let w = width.get()
  if w < 0 {
    diags.push("negative width: \{w}")
  }
  w.abs()
})

let checked_reader = checked.observe()
let _ = checked_reader.get()

// Outside any compute: read pushes permissively (empty if producer never ran).
debug_inspect(checked.accumulated_peek(diags), content="[\"negative width: -5\"]")

width.set(10)
let _ = checked_reader.get()
// Producer re-ran; push set is empty this time.
debug_inspect(checked.accumulated_peek(diags), content="[]")
checked_reader.dispose()
```

**Top-frame restriction.** `push` is only legal inside a `Memo` or
`HybridMemo` compute. Calling `diags.push(...)` from an `Input::set`,
`Effect`, or bare function call raises `Failure`.

---

## Pattern: Accumulator-Driven Incremental Invalidation

When a consumer memo reads pushes via `Memo::accumulated`, it records a
synthetic dependency on the producer's push set. The consumer reinvalidates
when the push set changes — **even when the producer's ordinary return
value is unchanged**. This is the primary reason to use an accumulator
rather than returning an `Array` from the producer.

```moonbit nocheck
let rt = Runtime()
let width = Input(rt, -5)

let diags : Accumulator[String] = Accumulator::new(rt~, label="diags")

// Producer returns only its size; diagnostics flow through the accumulator.
let checked = Memo(rt, fn() raise {
  let w = width.get()
  if w < 0 {
    diags.push("negative width: \{w}")
  }
  w.abs()
})

// Consumer's compute reads `accumulated`, so it tracks the push set.
let report = Memo(rt, fn() raise {
  let size = checked.get()
  let ds = checked.accumulated(diags)
  "size=\{size}, diags=\{ds.length()}"
})
let report_reader = report.observe()

inspect(report_reader.get(), content="size=5, diags=1")

// Flip sign — producer's return value stays 5 (abs is symmetric),
// but the push set flips from [one diag] to [].
width.set(5)
inspect(report_reader.get(), content="size=5, diags=0")
report_reader.dispose()
```

Without the accumulator, `report` would not invalidate: `checked.get()`
still returns `5` (structurally equal, so backdated), and a plain
`checked.diagnostics` field would require a fresh `Array` allocation on
every compute to carry the change through.

Use `accumulated_result` at the boundary when a cycle in the producer
should surface as `Err(CycleError)` rather than raising.

---

## Pattern: Scope-Owned Accumulator Lifecycle

A driver that rebuilds its memo chain on structural change (new def set,
new schema, new file list) needs a matching rebuild of the accumulator —
or stale per-memo push buffers leak from the old graph into the new one.

Tie the accumulator to a **child scope** that owns the whole chain.
Disposing the scope disposes the accumulator automatically; allocating a
fresh scope gives you a fresh accumulator with no manual bookkeeping.

Shape (adapted from the lambda type-checker driver — see
`loom/examples/lambda/src/typecheck/typecheck.mbt`):

```moonbit nocheck
priv struct PipelineState {
  mut chain_scope : Scope?
  mut type_memos  : Array[Memo[TypeResult]]
  mut diags       : Accumulator[TypeDiagnostic]?
  // ... other per-chain state
}

fn rebuild_chain(
  state        : PipelineState,
  parent_scope : Scope,
  module       : ResolvedModule,
) -> Unit {
  // Dispose the old chain. Disposing the scope disposes every cell
  // allocated through it — memos, input cells, effects, AND the accumulator.
  match state.chain_scope {
    Some(old) => old.dispose()
    None      => ()
  }

  // Fresh scope → fresh accumulator in one call.
  let chain_scope = parent_scope.child()
  state.chain_scope = Some(chain_scope)
  let diags = chain_scope.accumulator(label="typecheck_diags")
  state.diags = Some(diags)

  // Allocate per-def memos on the chain scope; each closes over `diags`
  // and pushes diagnostics into it during compute.
  let type_memos = []
  for def in module.defs {
    let m = chain_scope.memo(() => infer_def(def, diags), label=def.name)
    type_memos.push(m)
  }
  state.type_memos = type_memos
}
```

The outer pipeline memo consumes diagnostics via `type_memo.accumulated(diags)`, so the invalidation chain is: def source changes → per-def memo recomputes → push set for that memo changes → pipeline memo invalidates → driver collects updated diagnostics.

**Why child scope, not runtime-owned.** An `Accumulator::new(rt~, ...)`
lives until explicitly disposed. In a driver that rebuilds on every
structural change, forgetting to dispose leaks per-memo state for every
retired memo. `parent_scope.child()` couples the accumulator's lifetime to
the chain it belongs to, so lifecycle correctness is a consequence of the
scope hierarchy rather than a discipline the driver must maintain.

---

## Pattern: Change Notifications

Observe committed updates with `Runtime::set_on_change`:

```moonbit
let rt = Runtime()
let a = Input(rt, 0)
let b = Input(rt, 0)
let mut notifications = 0

rt.set_on_change(() => { notifications = notifications + 1 })

// Outside batch: one callback per committed change
a.set(1)
b.set(2)
inspect(notifications, content="2")

// Inside batch: at most one callback at batch end
rt.batch(() => {
  a.set(3)
  b.set(4)
})
inspect(notifications, content="3")
```

Useful for:
- Triggering UI refreshes
- Scheduling downstream side effects
- Collecting change metrics

## Pattern: Per-Cell Change Callbacks

For finer-grained observation of field-level inputs, `InputField` supports a single per-cell callback:

```moonbit
let rt = Runtime()
let price = InputField(rt, 100, label="price")

// Fires immediately after price changes, before the global on_change
price.on_change(new_price => println("price changed to: \{new_price}"))

price.set(200)
// Prints "price changed to: 200"
```

**Callback ordering:**
1. Per-cell callbacks fire in the order input fields changed
2. The global `Runtime::set_on_change` callback fires after all per-cell callbacks

**Inside a batch**, per-cell callbacks fire once per changed field at the end of the batch — not once per `set()` call:

```moonbit
rt.batch(() => {
  price.set(150)
  price.set(200)  // Only the final value (200) is committed
})
// price on_change fires once with value 200
```

To remove a callback:

```moonbit
price.clear_on_change()
```

Compatibility `Signal` and `Memo` handles also expose per-cell callbacks for
code that still needs their introspection surface.

---

## Pattern: Memo Event Stream for Visualization

Use `Runtime::on_memo_event` when a driver needs recompute lifecycle data
rather than only value-change notifications. The listener is runtime-wide and
observes pull `Memo` / `HybridMemo` recomputes, including target
`Derived` / `ReachableDerived` wrappers.

```moonbit nocheck
let rt = Runtime()
let price = Input(rt, 100, label="price")
let total = Derived(rt, () => price.get() * 2, label="total")

let frames : Array[String] = []

rt.on_memo_event(evt => {
  match evt {
    EnteringCompute(e) => {
      let label = match rt.cell_info(e.cell_id) {
        Some(info) =>
          match info.label {
            Some(s) => s
            None => e.cell_id.id.to_string()
          }
        None => e.cell_id.id.to_string()
      }
      frames.push("enter " + label)
    }
    Completed(e) => {
      frames.push(
        "complete " +
        e.cell_id.id.to_string() +
        " in " +
        e.elapsed_ns.to_string() +
        "ns",
      )
    }
    Aborted(e) => {
      frames.push("abort " + e.cell_id.id.to_string() + ": " + e.error.to_string())
    }
  }
})

inspect(total.read_or_abort(), content="200")
```

Keep the listener small. It runs synchronously during the drain step, after the
memo compute has left the tracking stack. If the visualizer needs to read
other cells, use target facade `read()` / `read_or_abort()` methods or a
watch; compatibility `Memo::get()` is for tracked compute closures and aborts
from top-level event handlers.

The event stream is not a transaction log. Batch boundaries, signal-change
events, push-reactive events, snapshot/replay, and driver-owned event graphs
are intentionally separate design surfaces.

---

## Pattern: Async Memo Event Logging

Memo-event listeners are non-raising synchronous callbacks. For async logging,
enqueue a compact record in the listener and flush it from the driver.

```moonbit nocheck
struct LogRow {
  phase : String
  cell : CellId
  elapsed_ns : Int64
}

let rows : Array[LogRow] = []

rt.on_memo_event(evt => {
  match evt {
    EnteringCompute(e) =>
      rows.push({ phase: "enter", cell: e.cell_id, elapsed_ns: 0L })
    Completed(e) =>
      rows.push({
        phase: if e.backdated { "backdated" } else { "completed" },
        cell: e.cell_id,
        elapsed_ns: e.elapsed_ns,
      })
    Aborted(e) =>
      rows.push({ phase: "aborted", cell: e.cell_id, elapsed_ns: e.elapsed_ns })
  }
})

fn flush_log_rows() -> Unit {
  for row in rows {
    write_log(row)
  }
  rows.clear()
}
```

Replace the `Array` with the driver runtime's nonblocking queue when logging
from an async application. Do not raise from the listener; catch or encode
logging failures in the driver-owned queue.

---

## Pattern: Field-Level Inputs

Use `InputField` fields to give each field of a struct its own dependency cell. Derived values that read only one field are unaffected when a different field changes.

### When to Use InputField vs Input

| Situation | Recommendation |
|-----------|----------------|
| Single scalar value | `Input[T]` |
| Multiple related fields with independent consumers | `InputField[T]` in an owner struct |
| Monolithic struct updated atomically | `Input[MyStruct]` with `batch` |

### Defining an InputField Owner

Declare the struct with `InputField` fields, implement the `InputFieldOwner` trait, and provide a constructor:

```moonbit
struct SourceFile {
  path    : @incr.InputField[String]
  content : @incr.InputField[String]
  version : @incr.InputField[Int]
}

impl @incr.InputFieldOwner for SourceFile with cell_ids(self) {
  [self.path.id(), self.content.id(), self.version.id()]
}

fn SourceFile::SourceFile(
  rt      : @incr.Runtime,
  path    : String,
  content : String,
  version~ : Int = 0,
) -> SourceFile {
  {
    path:    @incr.InputField(rt, path,    label="SourceFile.path"),
    content: @incr.InputField(rt, content, label="SourceFile.content"),
    version: @incr.InputField(rt, version, label="SourceFile.version"),
  }
}
```

### Composing with Derived Values

Each derived value declares dependency only on the fields it actually reads:

```moonbit
let rt   = @incr.Runtime()
let file = SourceFile(rt, "/src/main.mbt", "fn main { 42 }")

let word_count = @incr.Derived(rt, () => {
  file.content.get().split(" ").fold(init=0, (acc, _s) => acc + 1)
})

let is_test = @incr.Derived(rt, () => file.path.get().ends_with("_test.mbt"))

// Change version — neither derived value recomputes
file.version.set(1)

// Change content — only word_count recomputes; is_test is not touched
file.content.set("fn main { let x = 42\n  x }")
```

### Batch Updates Across Multiple Fields

Use `rt.batch` to update several fields atomically:

```moonbit
rt.batch(() => {
  file.path.set("/src/lib.mbt")
  file.content.set("pub fn greet() -> String { \"hello\" }")
  file.version.set(2)
})
// Single revision bump; downstream derived values reverify once
```

### Using RuntimeContext with InputField

When your runtime is wrapped in a context type, use `create_input_field` instead of calling `InputField(...)` directly:

```moonbit
struct MyDb {
  rt : @incr.Runtime
}

fn MyDb::MyDb() -> MyDb {
  { rt: @incr.Runtime() }
}

impl @incr.RuntimeContext for MyDb with runtime(self) { self.rt }

let db   = MyDb()
let path = @incr.create_input_field(db, "/src/main.mbt", label="path")
```

### Lifecycle: Register Field Owners with a Scope

Use `add_input_fields(scope, owner)` to register all of a struct's `InputField`
fields with a `Scope`; disposing the scope disposes the fields:

```moonbit nocheck
let scope = @incr.Scope::new(db.runtime())
let file = SourceFile(db.runtime(), "/src/main.mbt", "fn main { 42 }")
@incr.add_input_fields(scope, file)
// ... later ...
scope.dispose()  // disposes every InputField field of `file`
```

Compatibility `TrackedCell` structs use `Trackable` and `add_tracked(scope,
tracked)`. `gc_tracked` is deprecated and remains a no-op kept for source
compatibility.

### Lifecycle: Register Watches with a Scope

Use `scope.add_watch(derived.watch())` when an outside-graph reader should live
exactly as long as a `Scope`:

```moonbit nocheck
let scope = @incr.Scope::new(rt)
let watch = scope.add_watch(summary.watch())
inspect(watch.read_or_abort(), content="42")
scope.dispose()  // disposes the watch before scope-owned cells
```

### Migration: Input[MyStruct] → Field-Level Inputs

If you have an existing `Input[MyStruct]` and derived recomputation is too coarse, migrate field by field:

```moonbit
// Before
struct Doc { content : String; version : Int }
let doc = Input(rt, { content: "hello", version: 0 })
let length = Derived(rt, () => doc.get().content.length())
// Updating version also invalidates length — unnecessary work

// After
struct Doc {
  content : @incr.InputField[String]
  version : @incr.InputField[Int]
}
// Now version.set(...) does not touch length at all
```

---

## Pattern: Keyed Queries with DerivedMap

Use `DerivedMap[K, V]` when you want one lazy derived computation per key.

```moonbit
let rt = Runtime()
let base = Input(rt, 10)
let by_id = DerivedMap(rt, (id : Int) => base.get() + id)

inspect(by_id.read_or_abort(1), content="11")  // creates entry for key=1
inspect(by_id.read_or_abort(1), content="11")  // cache hit for key=1
inspect(by_id.read_or_abort(2), content="12")  // creates entry for key=2
inspect(by_id.cache_len(), content="2")

base.set(20)
inspect(by_id.read_or_abort(1), content="21")  // key=1 recomputes lazily
inspect(by_id.read_or_abort(2), content="22")  // key=2 recomputes when read
```

For `RuntimeContext`-style code, use `create_derived_map(ctx, f, label?)`.

---

## Anti-Pattern: Reading During Batch

Avoid reading derived values inside a batch — they see pre-batch values:

```moonbit
let rt = Runtime()

let x = Input(rt, 10)
let doubled = Derived(rt, () => x.get() * 2)

rt.batch(() => {
  x.set(20)
  // doubled.read_or_abort() still returns 20, not 40!
  // Batch provides transactional isolation
})

// After batch, doubled.read_or_abort() returns 40
```

---

## Anti-Pattern: Large Compute Functions

Keep compute functions focused:

```moonbit
// Bad: Monolithic computation
let result = Derived(rt, () => {
  let a = step1(input.get())
  let b = step2(a)
  let c = step3(b)
  step4(c)
})

// Better: Composable derived values
let step1_result = Derived(rt, () => step1(input.get()))
let step2_result = Derived(rt, () => step2(step1_result.get_or_abort()))
let step3_result = Derived(rt, () => step3(step2_result.get_or_abort()))
let final_result = Derived(rt, () => step4(step3_result.get_or_abort()))
```

Benefits:
- Each step can backdate independently
- Intermediate results are cached
- Easier to debug and test

---

## Pattern: Graceful Cycle Handling

Handle potential cycles with fallback values instead of aborting:

```moonbit
let rt = Runtime()

// Self-referential derived value that handles cycles gracefully
let derived_ref : Ref[Derived[Int]?] = { val: None }
let derived = Derived(rt, () => {
  match derived_ref.val {
    Some(d) =>
      match d.get() {
        Ok(v) => v + 1
        Err(CycleDetected(_, _, _)) => 0  // Base case on cycle
      }
    None => 0
  }
})
derived_ref.val = Some(derived)

inspect(derived.read_or_abort(), content="0")  // Returns fallback, doesn't abort
```

### Use Cases

- **Recursive data structures**: Tree traversal that might have back-edges
- **Plugin systems**: User-provided compute functions that might create cycles
- **Debugging**: Graceful degradation while investigating dependency issues

### Important Notes

1. **Handle errors inside compute**: If the `Err` propagates out of the compute function, the outer `read_or_abort()` will still abort
2. **No spurious dependencies**: Failed `get()` calls don't record dependencies, so subsequent accesses work correctly
3. **State consistency**: The runtime remains usable after cycle errors

---

## Debugging

Target facades are intentionally small. When you need low-level cell IDs,
dependency lists, revisions, or changed-at timestamps, use the compatibility
`Signal` / `Memo` handles shown in these introspection recipes.

### Why Did This Memo Recompute?

Use introspection to identify which dependency triggered recomputation:

```moonbit
let rt = Runtime()
let x = Signal(rt, 10)
let y = Signal(rt, 20)
let sum = Memo(rt, () => x.get() + y.get())
let sum_reader = sum.observe()

sum_reader.get() |> ignore
let baseline = sum.verified_at()

// Make some changes
x.set(15)
sum_reader.get() |> ignore

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
sum_reader.dispose()
```

### Analyzing Dependency Chains

Trace the full dependency path (forward edges — what does this memo depend on?):

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

### Inspecting Dependents (Reverse Edges)

Use `Runtime::dependents` or `Memo::dependents` to answer: "what will be invalidated if this cell changes?"

```moonbit
let rt = Runtime()
let source = Signal(rt, 1, label="source")
let doubled = Memo(rt, () => source.get() * 2, label="doubled")
let tripled = Memo(rt, () => source.get() * 3, label="tripled")
let doubled_reader = doubled.observe()
let tripled_reader = tripled.observe()

// Must read memos at least once to establish dependencies
doubled_reader.get() |> ignore
tripled_reader.get() |> ignore

// Inspect who depends on source
for dep_id in rt.dependents(source.id()) {
  match rt.cell_info(dep_id) {
    Some(info) => println("depends on source: " + info.label.or("(unlabeled)"))
    None => ()
  }
}
// Prints: "depends on source: doubled"
// Prints: "depends on source: tripled"
doubled_reader.dispose()
tripled_reader.dispose()
```

This is useful for impact analysis — understanding how wide the blast radius of a change will be before committing it.

### Testing Dependency Tracking

Verify that memos only depend on what they actually read:

```moonbit
test "memo only depends on x, not y" {
  let rt = Runtime()
  let x = Signal(rt, 1)
  let y = Signal(rt, 2)
  let uses_x_only = Memo(rt, () => x.get() * 2)
  let uses_x_only_reader = uses_x_only.observe()

  uses_x_only_reader.get() |> ignore

  let deps = uses_x_only.dependencies()
  inspect(deps.contains(x.id()), content="true")
  inspect(deps.contains(y.id()), content="false")
  uses_x_only_reader.dispose()
}
```

### Understanding Backdating

Check if a memo's value actually changed:

```moonbit
let memo = Memo(rt, () => config.get().length())
let memo_reader = memo.observe()
memo_reader.get() |> ignore
let old_changed = memo.changed_at()

config.set("same_length")  // Different string, same length
memo_reader.get() |> ignore

// Backdating: value didn't change, so changed_at is preserved
inspect(memo.changed_at() == old_changed, content="true")
memo_reader.dispose()
```

### Debugging Cycles

When you encounter a cycle error, use the path information to understand the dependency chain:

```moonbit
match computation.get_result() {
  Err(err) => {
    let path = err.path()
    let formatted = err.format_path()

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

### Check if a Derived Value Recomputed

Add logging inside compute functions during development:

```moonbit
let expensive = Derived(rt, () => {
  println("Computing expensive...")
  heavy_computation(input.get())
})
```

### Verify Durability Shortcuts

High-durability derived values should not log when only low-durability inputs change:

```moonbit
let config = Input(rt, 100, durability=High)
let data = Input(rt, 1)

let config_derived = Derived(rt, () => {
  println("Config derived computing...")  // Should not print when data changes
  config.get() * 2
})

let data_derived = Derived(rt, () => {
  println("Data derived computing...")
  data.get() * 2
})

config_derived.read_or_abort()
data_derived.read_or_abort()

data.set(2)  // Only data_derived should recompute
data_derived.read_or_abort()
config_derived.read_or_abort()
```
