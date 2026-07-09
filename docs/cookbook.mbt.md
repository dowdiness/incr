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

## Pattern: Batch Rollback for Extension-Owned State

Prefer ordinary `Input` / `InputField` mutation for state that can be modeled as
cells; those writes already participate in `Runtime::batch` rollback. Use
`Runtime::record_batch_rollback` only for app-owned mutable structures that sit
beside the graph, such as indexes, slot maps, worksheet metadata, or caches that
must stay transactional with a batch.

Register the rollback immediately after mutating the external structure, and make
the callback narrow and deterministic: restore a small map snapshot, restore one
entry, remove one inserted slot, or reinstall one prior pointer.
`record_batch_rollback` stores only the first rollback callback for a given
`CellId` in each batch frame, so capture the pre-batch state on the first
mutation of that rollback unit. Pick a stable cell ID that identifies the
external state unit: an existing value-slot/input ID, a whole-structure rollback
token, or a per-entry token whose own creation is not an untracked side effect in
a failed batch.

When `Runtime::batch_result` returns `Err(_)`, the current batch frame has already
replayed these callbacks in reverse order. An outermost successful batch discards
the rollback log; a successful nested batch merges its rollback entries into the
parent frame so an outer failure can still restore them. This is not a general
undo/redo API and not a replacement for modeling state as cells; it only keeps
extension-owned side structures consistent with raised-error batch rollback.

The checked companion demonstrates both insertion and replacement rollback for
an external `Map` in
[`cookbook_examples.mbt.md`](cookbook_examples.mbt.md#batch-callbacks-read-isolation-and-extension-rollback).
The typed spreadsheet example uses the same pattern for worksheet-owned cell slot
maps while ordinary value/presence cells remain `InputField` / `Derived` graph
state.

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

A derived cell's ordinary return value (a value, a type, a compiled artifact)
is often semantically distinct from log-like data it emits along the way
(diagnostics, trace events, stats). Thread return values through the derived
graph; thread the log-like data through an `Accumulator[T]`.

Producers `push` during compute. Consumers read back via
`Derived::accumulated_peek` (outside the graph), `Derived::accumulated`
(Result-style read), or `Derived::accumulated_or_abort` (strict
compute-closure convenience), with correct incremental invalidation. See the
[Accumulator API](api-reference.mbt.md#accumulatort) reference.

The checked companion demonstrates this pattern in
[`cookbook_examples.mbt.md`](cookbook_examples.mbt.md#accumulator-diagnostics-and-synthetic-invalidation).

**Top-frame restriction.** `push` is only legal inside a `Derived` or
`ReachableDerived` compute. Calling `diags.push(...)` from an `Input::set`,
`Effect`, or bare function call raises `Failure`.

---

## Pattern: Accumulator-Driven Incremental Invalidation

When a consumer derived cell successfully reads pushes via
`Derived::accumulated` (or the strict `Derived::accumulated_or_abort`), it
records a synthetic dependency on the
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

A driver that rebuilds its derived chain on structural change (new def set,
new schema, new file list) needs a matching rebuild of the accumulator —
or stale per-cell push buffers leak from the old graph into the new one.

Tie the accumulator to a **child scope** that owns the whole chain.
Disposing the scope disposes the accumulator automatically; allocating a
fresh scope gives you a fresh accumulator with no manual bookkeeping.

The operational shape is: store the current child `Scope` in the driver state,
dispose it before rebuilding the chain, allocate a fresh `parent_scope.child()`,
then allocate the accumulator and per-definition derived cells through that child scope.
The checked API-reference companion covers the scope-owned disposal guarantee in
[`api_reference_examples.mbt.md`](api_reference_examples.mbt.md#accumulator--compatibility-push-side-channel).

The outer pipeline cell consumes diagnostics via `type_derived.accumulated_or_abort(diags)`, so the invalidation chain is: def source changes → per-def derived cell recomputes → push set for that cell changes → pipeline cell invalidates → driver collects updated diagnostics.

**Why child scope, not runtime-owned.** An `Accumulator(rt, ...)` lives until explicitly disposed. In a driver that rebuilds on every structural change, forgetting to dispose leaks per-cell state for every retired derived cell. `parent_scope.child()` couples the accumulator's lifetime to the chain it belongs to, so lifecycle correctness is a consequence of the scope hierarchy rather than a discipline the driver must maintain.

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

`Input::on_change` and `Derived::on_change` provide the same single per-cell
callback on non-field cells; `clear_on_change()` removes it.

---

## Pattern: Derived Event Stream for Visualization

Use `Runtime::on_derived_event` when a driver needs recompute lifecycle data
rather than only value-change notifications. The listener is runtime-wide and
observes every pull-mode recompute (`Derived` and `ReachableDerived`).

The checked companion records the same event phases in
[`cookbook_examples.mbt.md`](cookbook_examples.mbt.md#derived-event-logging).

Keep the listener small. It runs synchronously during the drain step, after
the derived compute has left the tracking stack. If the visualizer needs to
read other cells, use the outside-graph reads `read()` / `read_or_abort()` or
a watch; `get()` is the in-graph read for tracked compute closures, not for
event handlers.

The event stream is not a transaction log. Batch boundaries, input-change
events, push-reactive events, snapshot/replay, and driver-owned event graphs
are intentionally separate design surfaces.

---

## Pattern: Async Derived Event Logging

Derived-event listeners are non-raising synchronous callbacks. For async logging,
enqueue a compact record in the listener and flush it from the driver.

The checked companion shows the listener enqueuing compact log rows in
[`cookbook_examples.mbt.md`](cookbook_examples.mbt.md#derived-event-logging).

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

## Pattern: Sparse Address Maps with Presence Anchors

Sparse application maps often need a derived value to depend on an address that
is currently missing. A plain map miss records no dependency, so later creation
of that key will not invalidate the derived value. Keep a lightweight
per-address presence anchor, usually `InputField[Bool]`, and make missing reads
consult that anchor before returning a domain error.

Use this shape:

- `Map[Key, InputField[Bool]]` for stable presence anchors
- `Map[Key, ValueSlot]` for heavier value, formula, parser, or cache slots
- read: call `presence.get()` first; if false, return `Err(...)` or a domain
  `RefError` value
- create/recreate: install or update the value slot, then set presence `true`
- delete: set presence `false`; decide separately whether to retain or compact
  the heavyweight slot

**Compaction warning:** if the heavyweight slot is itself an incremental cell and
a dependent last read it while the key was present, that dependent's dependency
list can still point at the heavyweight value slot. Disposing or removing the
slot immediately after setting presence `false` can make the next pull
verification fail on a disposed dependency before the dependent compute runs and
re-anchors on presence. A compactor must either retain the slot, or force
affected dependents to reread the missing state before disposing/removing the
heavyweight cell. The typed spreadsheet compactor does this by refreshing
present formulas before pruning deleted slots.

Allocate the presence anchor when installing the query/formula, or lazily on
first read if the driver can safely allocate a lightweight cell there. The
important invariant is that every future read for the same logical key reuses the
same anchor. The checked companion shows a missing read returning a domain error,
then resolving after creation, failing again after deletion, and resolving again
after recreation in
[`cookbook_examples.mbt.md`](cookbook_examples.mbt.md#sparse-address-maps-with-presence-anchors).

This is an invalidation-identity pattern, not a core collection API. Deleted-slot
lifecycle is application policy: the typed spreadsheet example keeps lightweight
presence anchors and exposes example-local compaction for heavyweight tombstones.
See the lifecycle ADR for [GitHub issue #130](decisions/2026-06-02-typed-spreadsheet-tombstone-lifecycle.md).

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

Keep recoverable parse, projection, and semantic failures in the cached value,
following the same ownership split as
[domain errors as values](#pattern-domain-errors-as-values). For the last-good
result pattern, store the last successful semantic/lowered value at the facade
boundary. On a successful terminal read, update `last_good`; on an invalid
current input, publish diagnostics while returning the previous `last_good`
value. Do not mutate that state from inside a `Derived` closure — recomputation
order should not become domain state.

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

## Pattern: Domain Errors as Values

When a compute can fail in a way the caller should *recover from* — parse
errors, type errors, reference errors, validation failures, diagnostics — make
that failure part of the computed **value**, not a raised exception and not the
read channel. The value can be `Result[V, E]`, a custom enum, or a diagnostics
payload inside the `T` of `Derived[T]`.

This keeps the ownership split honest:

- graph/runtime failures live in reads: `Err(ReadError)` for cycles, disposal,
  and other mechanism failures;
- domain/application failures live in values: `Ok(Diagnostics(...))`,
  `Ok(Err(parse_error))`, `Ok(TypeError(...))`, etc.;
- defects still abort or fail.

Because the domain failure is a value, it is cached, shared, replayed, compared
with `Eq`, and backdated like any other derived state. The typed spreadsheet
example is the motivating boundary: formula evaluation returns `CellResult`
variants for type/reference/parse outcomes instead of raising, while the
spreadsheet API itself stays example-local.

The checked companion includes both a custom diagnostics enum and the
`Result`-shaped specialization in
[`cookbook_examples.mbt.md`](cookbook_examples.mbt.md#domain-errors-as-values).

### `Result` Specialization: `Derived::fallible`

Use `Derived::fallible` when the domain shape is exactly `Result[V, E]`. It takes
a `noraise` compute (`() -> Result[V, E]`) and produces a
`Derived[Result[V, E]]`, forcing recoverable failures into the cached value at
the type level.

A read of `Derived[Result[V, E]]` has **three** distinct outcomes, each owned by
a different layer:

| Read result | Meaning | What to do |
|-------------|---------|------------|
| `Err(_)` | graph-read failure (cycle, disposal) | report graph health |
| `Ok(Err(e))` | domain failure, reified as a cached value | surface the diagnostic |
| `Ok(Ok(v))` | the value | use it |

For a custom enum or diagnostics payload, replace the inner `Result` with your
application's value shape; the outer `Ok(...)` still means the graph read
succeeded.

### Important Notes

1. **`raise Failure` from a plain `Derived` compute is a defect, not a domain
   channel.** It is caught at the read boundary and converted to an uncatchable
   abort. Return a domain value, or use `Derived::fallible` when `Result` is the
   right shape.
2. **`Eq` quality matters.** Reified domain failures participate in invalidation
   like values: an error-to-success transition correctly invalidates downstream,
   and two equal diagnostic payloads can backdate and avoid noisy recomputation.
   A poor `Eq` causes stale reads or unnecessary work.
3. **Per-key analog:** `DerivedMap::fallible` produces a
   `DerivedMap[K, Result[V, E]]` with the same value-as-`Result` contract for
   keyed queries. A custom enum payload works with ordinary `DerivedMap` values
   by the same rule.

See the [honest read-error ownership spec](design/specs/2026-05-28-honest-read-error-ownership.md)
for the full rationale and the [`Derived::fallible` API reference](api-reference.mbt.md#derivedt)
for the constructor contract.

---

## Pattern: History-Dependent State with `mut` Capture

Compute closures must be pure functions of their tracked reads (see the
[composition contract ADR](decisions/2026-07-08-evaluation-strategy-composition-contract.md#1-cell-taxonomy-the-purity-axis)).
When you genuinely need state that survives across recomputes — a counter, a
running total, a previous value for comparison — the sanctioned approach is
`mut` capture: a `Ref[T]` in the closure environment that the compute mutates.

**Why not `Input::force_set`?** The runtime guard aborts any `Input::force_set`
call from inside a compute context. This is by design: `force_set` triggers
reentrant propagation, and even without subscribers the result depends on
how many times the compute ran, which under lazy pull + verification skipping
+ backdating is a caching/demand decision, not semantics. The same caveat
applies to `mut` capture — the `mut` also depends on compute frequency —
but `mut` is a local side effect that cannot corrupt the graph, so it is safe.

The performance profile also differs: `mut` avoids the allocation, revision
bump, and propagation machinery that `Input::force_set` would trigger even
in a subscriber-free counter. There is no cell overhead.

The checked companion pins the full semantics — including the critical
difference between skipped recomputes (compute did not run at all) and
backdating (compute ran, but the output was equal to the previous value) —
in [`cookbook_examples.mbt.md`](cookbook_examples.mbt.md#history-dependent-state-with-mut-capture).

**Key caveat:** The `mut` advances on every compute, not on every *visible*
change. Backdating still advances the `mut`. Only a fully skipped
recompute — no invalidated dependencies — leaves the `mut` unchanged.
This means the `mut` reflects compute frequency, not semantic output
changes. Keep this in mind when designing stateful derived values.

**When `mut` is insufficient.** The ADR reserves a first-class `fold`
primitive for cases where exactly one step per committed change is required
([ADR §5](decisions/2026-07-08-evaluation-strategy-composition-contract.md#5-reserved-fold--pairwise-delivery-contract)).
`mut` capture is the sanctioned approach today; `fold` is the eventual
answer if a second concrete consumer need materializes.
---

## Debugging

For low-level introspection, `Derived` exposes `id()`, `dependencies()`,
`changed_at()`, and `verified_at()`; `Runtime` exposes `cell_info` and
`dependents`. These are the tools the recipes below build on.

### Why Did This Derived Value Recompute?

Use introspection to identify which dependency triggered recomputation:

The checked companion captures a `verified_at` baseline, changes one input,
walks `sum.dependencies()`, and uses `Runtime::cell_info` to identify the changed
dependency.

### Analyzing Dependency Chains

Trace the full dependency path (forward edges — what does this derived value depend on?):

Walk `derived.dependencies()` for forward edges and call `Runtime::cell_info` for
labels, durability, revisions, dependencies, and subscribers. The checked
companion pins this introspection surface.

### Inspecting Dependents (Reverse Edges)

Use `Runtime::dependents` to answer: "what will be invalidated if this cell changes?"

Read the dependent derived cells at least once to establish edges, then call
`rt.dependents(source.id())` and inspect each returned cell with
`Runtime::cell_info`. The checked companion verifies this reverse-edge query.

This is useful for impact analysis — understanding how wide the blast radius of a change will be before committing it.

### Testing Dependency Tracking

Verify that derived cells only depend on what they actually read:

In tests, read the derived cell once, inspect `derived.dependencies()`, and assert that the
active input IDs are present while inactive IDs are absent. The checked
companion demonstrates the same dependency snapshot mechanics.

### Understanding Backdating

Check if a derived value actually changed:

The checked companion reads a derived cell, stores `changed_at`, changes an input to a
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
