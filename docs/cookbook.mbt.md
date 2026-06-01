# Cookbook

Common patterns and recipes for using `incr` effectively. Checked variants of the highest-value snippets live in [`cookbook_examples.mbt.md`](cookbook_examples.mbt.md).

## Pattern: Diamond Dependencies

Handle computations where multiple paths converge:

```text
    [A]
   /   \
  [B]   [C]
   \   /
    [D]
```

The checked companion pins the diamond shape and verifies each branch recomputes once in [`cookbook_examples.mbt.md`](cookbook_examples.mbt.md#diamond-dependencies-and-layered-derived-values).

`incr` handles diamonds correctly — `a` is only read once per computation of each derived value.

---

## Pattern: Conditional Dependencies

Dependencies can vary based on runtime conditions:

The checked companion verifies that dependency tracking follows the active branch and ignores inactive inputs in [`cookbook_examples.mbt.md`](cookbook_examples.mbt.md#conditional-dependencies).

---

## Pattern: Configuration + Data Separation

Use durability to optimize stable configuration. Mark rarely changing inputs as `High`; derived values that depend only on high-durability inputs can skip verification when only lower-durability data changed. The checked concepts companion pins the durability shortcut in [`concepts_examples.mbt.md`](concepts_examples.mbt.md#backdating-batching-and-dynamic-dependencies).

When measurements change:
- `config_factor` skips verification entirely when only lower-durability data changed
- Only affected `process` derived values recompute

---

## Pattern: Atomic Multi-Update

Update related inputs together:

The checked companion verifies that batched related inputs commit atomically in [`cookbook_examples.mbt.md`](cookbook_examples.mbt.md#batch-callbacks-and-read-isolation).

---

## Pattern: Tentative Updates with Rollback

Use batch semantics for speculative changes:

The concepts companion pins this net-zero revert behavior in [`concepts_examples.mbt.md`](concepts_examples.mbt.md#backdating-batching-and-dynamic-dependencies).

---

## Pattern: Computed Defaults

Derive default values from other inputs:

The checked companion verifies that computed defaults yield to explicit overrides and resume when the override is removed in [`cookbook_examples.mbt.md`](cookbook_examples.mbt.md#computed-defaults).

---

## Pattern: Layered Caching

Build computation layers with natural caching:

The checked companion verifies that layered derived values cache intermediate results and skip downstream recomputation after backdating in [`cookbook_examples.mbt.md`](cookbook_examples.mbt.md#diamond-dependencies-and-layered-derived-values).

---

## Pattern: Backdating with Custom Equality

Backdating suppresses downstream recomputation when a derived value's output is equal to its previous value. The comparison uses the type's `Eq` implementation, so you control exactly what "equal" means. This is useful when your type carries metadata that downstream consumers don't care about.

### Ignoring a Generation Counter

A common case: a value has a `generation` or `version` field that increments on every write, but downstream derived values only care about the semantic content.

The checked companion defines the `Versioned` type and verifies that the downstream handler does not recompute when only the ignored generation changes in [`cookbook_examples.mbt.md`](cookbook_examples.mbt.md#backdating-with-custom-equality).

`versioned` recomputed because `input` changed, but `handler` was skipped: the new `Versioned(10, 2)` equals the old `Versioned(10, 1)` under the custom `Eq`, so downstream derived values did not see a change.

### Ignoring Unstable Fields in Enums

The same pattern applies to enum variants where some fields are stable (drive behavior) and others are incidental (logging, diagnostics):

```mbt nocheck
///|
enum Status {
  Loading(progress~ : Int)
  Ready(data~ : Int)
  Error(code~ : Int, message~ : String)
}

///|
impl Eq for Status with fn equal(self, other) -> Bool {
  match (self, other) {
    (Loading(progress=p1), Loading(progress=p2)) => p1 == p2
    (Ready(data=d1), Ready(data=d2)) => d1 == d2
    (Error(code=c1, ..), Error(code=c2, ..)) => c1 == c2
    _ => false
  }
}
```

The checked companion verifies the runtime behavior: changing only the excluded
message field recomputes `status` but backdates it, so the downstream `handler`
does not recompute. Changing the stable code field invalidates `handler`:

```mbt nocheck
let rt = @incr.Runtime()
let error_code = @incr.Input(rt, 404, label="error_code")
let error_msg = @incr.Input(rt, "Not Found", label="error_msg")

let status = @incr.Derived(
  rt,
  () => Error(code=error_code.get(), message=error_msg.get()),
  label="status",
)
let handler = @incr.Derived(
  rt,
  () =>
    match status.get_or_abort() {
      Error(code=c, ..) => "Error: " + c.to_string()
      Ready(data=d) => "Data: " + d.to_string()
      Loading(progress=p) => "Loading: " + p.to_string() + "%"
    },
  label="handler",
)

inspect(handler.read_or_abort(), content="Error: 404")
error_msg.set("Page Not Found")
inspect(handler.read_or_abort(), content="Error: 404")
```

`status` recomputed when the message changed, but `handler` was skipped because the new `Error(code=404, message="Page Not Found")` equals the old one under the custom `Eq`.

### The Footgun: Excluding Fields That Are Actually Read

**Backdating only holds when the excluded fields are never read by any downstream derived value.** If a derived value reads a field excluded from `Eq`, it will receive a stale value silently — no error, no warning.

```mbt nocheck
///|
struct Versioned {
  value : Int
  generation : Int
}

///|
impl Eq for Versioned with fn equal(self, other) -> Bool {
  self.value == other.value
}

///|
let rt = @incr.Runtime()

///|
let input = @incr.Input(rt, 100)

///|
let generation : Ref[Int] = { val: 0 }

///|
let versioned = @incr.Derived(rt, () => {
  generation.val = generation.val + 1
  { value: input.get() / 10, generation: generation.val }
})

///|
let safe_handler = @incr.Derived(rt, () => versioned.get_or_abort().value * 2)

///|
let unsafe_handler = @incr.Derived(rt, () => versioned.get_or_abort().generation)
```

The first derived value is safe because it only reads fields that participate in
`Eq`. The second is unsafe: `generation` is excluded from `Eq`, so backdating can
preserve the upstream timestamp and leave the downstream cached value stale.

**Rule:** Only exclude a field from `Eq` if you are certain no derived value in the graph reads that field from this type's values. When in doubt, include the field in `Eq` and accept the recomputation cost.

---

## Pattern: Aggregate Computation

Efficiently aggregate over multiple inputs:

The checked companion verifies that an aggregate derived value and its dependent average update when one input changes in [`cookbook_examples.mbt.md`](cookbook_examples.mbt.md#aggregate-computation).

---

## Pattern: Side-Channel Diagnostics with Accumulator

A memo's ordinary return value (a value, a type, a compiled artifact) is
often semantically distinct from log-like data it emits along the way
(diagnostics, trace events, stats). Thread return values through the memo
graph; thread the log-like data through an `Accumulator[T]`.

Producers `push` during compute. Consumers read back via
`Memo::accumulated_peek` (outside the graph), `Memo::accumulated` (Result-style
read), or `Memo::accumulated_or_abort` (strict compute-closure convenience),
with correct incremental invalidation. See the
[Accumulator API](api-reference.mbt.md#accumulatort) reference.

The checked companion demonstrates this pattern in
[`cookbook_examples.mbt.md`](cookbook_examples.mbt.md#accumulator-diagnostics-and-synthetic-invalidation).

**Top-frame restriction.** `push` is only legal inside a `Memo` or
`HybridMemo` compute. Calling `diags.push(...)` from an `Input::set`,
`Effect`, or bare function call raises `Failure`.

---

## Pattern: Accumulator-Driven Incremental Invalidation

When a consumer memo successfully reads pushes via `Memo::accumulated` (or the
strict `Memo::accumulated_or_abort`), it records a synthetic dependency on the
producer's push set. The consumer reinvalidates when the push set changes —
**even when the producer's ordinary return value is unchanged**. This is the
primary reason to use an accumulator rather than returning an `Array` from the
producer.

The checked companion pins this backdating-sensitive invalidation behavior in
[`cookbook_examples.mbt.md`](cookbook_examples.mbt.md#accumulator-diagnostics-and-synthetic-invalidation).

Without the accumulator, `report` would not invalidate: `checked.get()`
still returns `5` (structurally equal, so backdated), and a plain
`checked.diagnostics` field would require a fresh `Array` allocation on
every compute to carry the change through.

Use `accumulated` at the boundary when a cycle in the producer should surface
as `Err(ReadError::Cycle(_))`; use `accumulated_or_abort` inside strict compute
closures.

---

## Pattern: Scope-Owned Accumulator Lifecycle

A driver that rebuilds its memo chain on structural change (new def set,
new schema, new file list) needs a matching rebuild of the accumulator —
or stale per-memo push buffers leak from the old graph into the new one.

Tie the accumulator to a **child scope** that owns the whole chain.
Disposing the scope disposes the accumulator automatically; allocating a
fresh scope gives you a fresh accumulator with no manual bookkeeping.

The operational shape is: store the current child `Scope` in the driver state,
dispose it before rebuilding the chain, allocate a fresh `parent_scope.child()`,
then allocate the accumulator and per-definition memos through that child scope.
The checked API-reference companion covers the scope-owned disposal guarantee in
[`api_reference_examples.mbt.md`](api_reference_examples.mbt.md#accumulator--compatibility-push-side-channel).

The outer pipeline memo consumes diagnostics via `type_memo.accumulated_or_abort(diags)`, so the invalidation chain is: def source changes → per-def memo recomputes → push set for that memo changes → pipeline memo invalidates → driver collects updated diagnostics.

**Why child scope, not runtime-owned.** An `Accumulator::new(rt~, ...)`
lives until explicitly disposed. In a driver that rebuilds on every
structural change, forgetting to dispose leaks per-memo state for every
retired memo. `parent_scope.child()` couples the accumulator's lifetime to
the chain it belongs to, so lifecycle correctness is a consequence of the
scope hierarchy rather than a discipline the driver must maintain.

---

## Pattern: Change Notifications

Observe committed updates with `Runtime::set_on_change`:

```mbt check
///|
test "cookbook: change notifications" {
  let rt = @incr.Runtime()
  let a = @incr.Input(rt, 0)
  let b = @incr.Input(rt, 0)
  let notifications : Ref[Int] = { val: 0 }

  rt.set_on_change(() => notifications.val = notifications.val + 1)

  a.set(1)
  b.set(2)
  inspect(notifications.val, content="2")

  rt.batch(() => {
    a.set(3)
    b.set(4)
  })
  inspect(notifications.val, content="3")
}
```

Useful for:
- Triggering UI refreshes
- Scheduling downstream side effects
- Collecting change metrics

## Pattern: Per-Cell Change Callbacks

For finer-grained observation of field-level inputs, `InputField` supports a single per-cell callback. The API-reference companion checks that field callbacks fire before the global runtime callback in [`api_reference_examples.mbt.md`](api_reference_examples.mbt.md#runtime-batching-and-change-callbacks).

**Callback ordering:**
1. Per-cell callbacks fire in the order input fields changed
2. The global `Runtime::set_on_change` callback fires after all per-cell callbacks

**Inside a batch**, per-cell callbacks fire once per changed field at the end of the batch — not once per `set()` call. Use `clear_on_change()` to remove the field callback.

Compatibility `Signal` and `Memo` handles also expose per-cell callbacks for
code that still needs their introspection surface.

---

## Pattern: Memo Event Stream for Visualization

Use `Runtime::on_memo_event` when a driver needs recompute lifecycle data
rather than only value-change notifications. The listener is runtime-wide and
observes pull `Memo` / `HybridMemo` recomputes, including target
`Derived` / `ReachableDerived` wrappers.

The checked companion records the same event phases in
[`cookbook_examples.mbt.md`](cookbook_examples.mbt.md#memo-event-logging).

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

The checked companion shows the listener enqueuing compact log rows in
[`cookbook_examples.mbt.md`](cookbook_examples.mbt.md#memo-event-logging).

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

Declare the struct with `InputField` fields, implement the `InputFieldOwner` trait, and provide a constructor. The checked companion includes the full owner struct and constructor shape in [`cookbook_examples.mbt.md`](cookbook_examples.mbt.md#field-level-inputs-and-scoped-watches).

### Composing with Derived Values

Each derived value declares dependency only on the fields it actually reads. The checked companion verifies that changing `version` does not recompute consumers of `path` or `content` in [`cookbook_examples.mbt.md`](cookbook_examples.mbt.md#field-level-inputs-and-scoped-watches).

### Batch Updates Across Multiple Fields

Use `rt.batch` to update several fields atomically. The batch examples above cover the same single-commit behavior for related inputs.

### Using RuntimeContext with InputField

When your runtime is wrapped in a context type, use `create_input_field` instead of calling `InputField(...)` directly:

```mbt nocheck
///|
struct MyDb {
  rt : @incr.Runtime
}

///|
fn MyDb::MyDb() -> MyDb {
  { rt: @incr.Runtime() }
}

///|
impl @incr.RuntimeContext for MyDb with fn runtime(self) {
  self.rt
}

///|
let db = MyDb()

///|
let path = @incr.create_input_field(db, "/src/main.mbt", label="path")
```

### Lifecycle: Register Field Owners with a Scope

Use `add_input_fields(scope, owner)` to register all of a struct's `InputField`
fields with a `Scope`; disposing the scope disposes the fields:

The checked companion verifies that `add_input_fields` wires all fields to the
scope lifecycle in
[`cookbook_examples.mbt.md`](cookbook_examples.mbt.md#field-level-inputs-and-scoped-watches).

Compatibility `TrackedCell` structs use `Trackable` and `add_tracked(scope,
tracked)`. `gc_tracked` is deprecated and remains a no-op kept for source
compatibility.

### Lifecycle: Register Watches with a Scope

Use `scope.add_watch(derived.watch())` when an outside-graph reader should live
exactly as long as a `Scope`:

The checked companion verifies that `scope.add_watch` keeps the watch live
across `gc()` and disposes it with the scope in
[`cookbook_examples.mbt.md`](cookbook_examples.mbt.md#field-level-inputs-and-scoped-watches).

### Migration: Input[MyStruct] → Field-Level Inputs

If you have an existing `Input[MyStruct]` and derived recomputation is too coarse, migrate field by field:

Before, any update to the `Doc` struct invalidates consumers of the whole input:

```mbt nocheck
///|
struct Doc {
  content : String
  version : Int
}

///|
let rt = @incr.Runtime()

///|
let doc = @incr.Input(rt, { content: "hello", version: 0 })

///|
let length = @incr.Derived(rt, () => doc.get().content.length())
```

After, consumers of `content` depend only on the `content` field, so
`version.set(...)` does not touch them:

```mbt nocheck
///|
struct FieldDoc {
  content : @incr.InputField[String]
  version : @incr.InputField[Int]
}

///|
let rt = @incr.Runtime()

///|
let doc : FieldDoc = {
  content: @incr.InputField(rt, "hello", label="Doc.content"),
  version: @incr.InputField(rt, 0, label="Doc.version"),
}

///|
let length = @incr.Derived(rt, () => doc.content.get().length())
```

---

## Pattern: Long-Lived Authoring Pipeline

Use this shape for editors, DSL workbenches, and other authoring surfaces that
live longer than a single read. The facade owns `Scope` / `Watch` lifetime, the
graph owns deterministic cached stages, and boundary code owns side effects.

```text
Input[String] or Input[Patch]
  -> Derived[ParseResult]
  -> Derived[Projection]
  -> Derived[SemanticGraph]
  -> Derived[LoweredGraph]
  -> Derived[TerminalState]
  -> Watch[TerminalState]
```

Create parsers and heavyweight engines before installing cells, then capture
those handles as collaborators. A `Derived` closure may read upstream cells and
run deterministic stage work over the current value; it should not construct a
parser, start a worker, perform IO, or publish render/audio side effects.

Use one `Derived` per stage rather than one monolithic `Derived`. Inside stage
closures, read `Input` with `.get()`, upstream `Derived` / `ReachableDerived`
values with `.get_or_abort()` (or `.get()` when graph read errors are explicit
data), and upstream `EagerDerived` values with `.get()`. Outside the graph —
event handlers, facade methods, tests, and drivers — use outside-read methods
(`Derived` / `ReachableDerived`: `.read()` / `.read_or_abort()`;
`EagerDerived`: `.read()`) or read through a persistent `Watch`. A public
`snapshot()` method should read a terminal `Watch`, not call `.get_or_abort()`.
Prime each terminal `Watch` once before exposing the facade if `Runtime::gc()`
can run before the first consumer read: a watch roots its terminal cell
immediately, but upstream dependencies are recorded only after the terminal
computes. If the facade stores last-good state, seed it from that priming read.

Keep recoverable parse, projection, and semantic failures in the cached value
(`Result`), following the same ownership split as
[`Derived::fallible`](#pattern-recoverable-domain-failures-with-derivedfallible).
For the last-good result pattern, store the last successful semantic/lowered
value at the facade boundary. On a successful terminal read, update `last_good`;
on an invalid current input, publish diagnostics while returning the previous
`last_good` value. Do not mutate that state from inside a `Derived` closure —
recomputation order should not become domain state.

Use `ReachableDerived` for sparse panels by mounting the panel in a child scope
only while it is visible, then storing and priming a `Watch` for that panel's
terminal read. Do not keep an un-watched or unprimed `ReachableDerived` as a
public read surface across `Runtime::gc()`. Introduce `DerivedMap` only after a
measurement shows that per-key caching is worth the extra shape; otherwise, a
linear chain of named `Derived` stages is easier to inspect and dispose.

Reserve `EagerDerived` / `Effect` for control-side reactions to prepared
terminal state: enqueue UI invalidation, mirror diagnostics to the host, or hand
off immutable snapshots to another subsystem. Parser construction, parser
mutation, audio callbacks, and other heavy or realtime work should stay outside
those closures.

The checked companion demonstrates this target-facade recipe, including a
primed terminal `Watch`, a primed child-scope `ReachableDerived` panel, explicit
disposal, and last-good diagnostics in
[`cookbook_examples.mbt.md`](cookbook_examples.mbt.md#long-lived-authoring-pipelines).

---

## Pattern: Keyed Queries with DerivedMap

Use `DerivedMap[K, V]` when you want one lazy derived computation per key. The concepts companion pins per-key cache creation and lazy recomputation in [`concepts_examples.mbt.md`](concepts_examples.mbt.md#field-level-inputs-and-keyed-derived-values).

For `RuntimeContext`-style code, use `create_derived_map(ctx, f, label?)`.

---

## Anti-Pattern: Reading During Batch

Avoid reading derived values inside a batch — they see pre-batch values. The checked companion demonstrates this read isolation in [`cookbook_examples.mbt.md`](cookbook_examples.mbt.md#batch-callbacks-and-read-isolation).

---

## Anti-Pattern: Large Compute Functions

Keep compute functions focused:

Bad pattern: one monolithic `Derived` performs every step. Better pattern:
compose one `Derived` per step, using `get_or_abort()` inside downstream compute
functions. This lets each step cache and backdate independently.

Benefits:
- Each step can backdate independently
- Intermediate results are cached
- Easier to debug and test

---

## Pattern: Graceful Cycle Handling

Handle potential cycles with fallback values instead of aborting. The checked companion verifies a self-referential derived value recovering inside its compute function in [`cookbook_examples.mbt.md`](cookbook_examples.mbt.md#graceful-cycle-handling).

### Use Cases

- **Recursive data structures**: Tree traversal that might have back-edges
- **Plugin systems**: User-provided compute functions that might create cycles
- **Debugging**: Graceful degradation while investigating dependency issues

### Important Notes

1. **Handle errors inside compute**: If the `Err` propagates out of the compute function, the outer `read_or_abort()` will still abort
2. **No spurious dependencies**: Failed `get()` calls don't record dependencies, so subsequent accesses work correctly
3. **State consistency**: The runtime remains usable after cycle errors

---

## Pattern: Recoverable Domain Failures with `Derived::fallible`

When a compute can fail in a way the caller should *recover from* — a parse
error, a validation failure — express that failure as a **value**, not as a
raised exception. `Derived::fallible` takes a `noraise` compute
(`() -> Result[V, E]`) and produces a `Derived[Result[V, E]]`. The domain error
is forced into the cached value, where it is change-detected (`Eq`), shared, and
replayed like any other value. The checked companion verifies a fallible derived
recovering across input changes in [`cookbook_examples.mbt.md`](cookbook_examples.mbt.md#recoverable-domain-failures-with-derivedfallible).

A read then has **three** distinct outcomes, each owned by a different layer:

| Read result | Meaning | What to do |
|-------------|---------|------------|
| `Err(_)` | graph-read failure (cycle, disposal) | report graph health |
| `Ok(Err(e))` | domain failure, reified as a cached value | surface the diagnostic |
| `Ok(Ok(v))` | the value | use it |

### Important Notes

1. **`raise Failure` from a plain `Derived` compute is a defect, not a domain
   channel.** It is caught at the read boundary and converted to an uncatchable
   abort. Use `Derived::fallible` for any failure a caller is meant to handle.
2. **`E : Eq` matters.** The reified error participates in invalidation like a
   value: an `Err → Ok` transition correctly invalidates downstream. A poor `Eq`
   on the domain error causes stale reads or noisy recomputation.
3. **Per-key analog:** `DerivedMap::fallible` produces a
   `DerivedMap[K, Result[V, E]]` with the same value-as-`Result` contract for
   keyed queries.

See [the honest read-error ownership spec](design/specs/2026-05-28-honest-read-error-ownership.md)
for the full rationale (why value-as-`Result` is the ideal, not a workaround).

---

## Debugging

Target facades are intentionally small. When you need low-level cell IDs,
dependency lists, revisions, or changed-at timestamps, use the compatibility
`Signal` / `Memo` handles shown in these introspection recipes.

### Why Did This Memo Recompute?

Use introspection to identify which dependency triggered recomputation:

The checked companion captures a `verified_at` baseline, changes one input,
walks `sum.dependencies()`, and uses `Runtime::cell_info` to identify the changed
dependency.

### Analyzing Dependency Chains

Trace the full dependency path (forward edges — what does this memo depend on?):

Walk `memo.dependencies()` for forward edges and call `Runtime::cell_info` for
labels, durability, revisions, dependencies, and subscribers. The checked
companion pins this introspection surface.

### Inspecting Dependents (Reverse Edges)

Use `Runtime::dependents` or `Memo::dependents` to answer: "what will be invalidated if this cell changes?"

Read the dependent memos at least once to establish edges, then call
`rt.dependents(source.id())` and inspect each returned cell with
`Runtime::cell_info`. The checked companion verifies this reverse-edge query.

This is useful for impact analysis — understanding how wide the blast radius of a change will be before committing it.

### Testing Dependency Tracking

Verify that memos only depend on what they actually read:

In tests, read the memo once, inspect `memo.dependencies()`, and assert that the
active input IDs are present while inactive IDs are absent. The checked
companion demonstrates the same dependency snapshot mechanics.

### Understanding Backdating

Check if a memo's value actually changed:

The checked companion reads a memo, stores `changed_at`, changes an input to a
different value with the same computed length, and verifies that backdating
preserves `changed_at`.

### Debugging Cycles

When you encounter a cycle error, use the path information to understand the dependency chain:

On `Err(err)`, call `err.path()` for the full cell path and
`err.format_path()` for display. Combine path entries with `Runtime::cell_info`
when you need per-cell metadata. The API-reference checked companion exercises
these `CycleError` accessors.

This helps identify:
- Which cells form the cycle
- The order of dependencies that created the loop
- Metadata about each cell in the cycle path

---

## Debugging Tips

### Check if a Derived Value Recomputed

Add logging inside compute functions during development:

Add a temporary log line inside the `Derived` compute closure while developing,
or better, count recomputes in a test as the checked companion examples do.

### Verify Durability Shortcuts

High-durability derived values should not log when only low-durability inputs change:

The concepts checked companion verifies the durability shortcut: when only a
low-durability input changes, derived values that depend only on high-durability
inputs can skip verification.
