# Incr API, DX, and Retention Architecture Redesign Proposal

**Date:** 2026-08-05

**Reader:** Maintainers evaluating a future getter/setter-based public API and
retention architecture for `incr`; reviewers of the companion first-principles
decision record.

**Decision:** Preserve as a directional design proposal. Interface exploration
only; not an accepted architecture, not an implementation authorization. The
retention kernel described here is not implementation-ready.

**Keep until:** The evidence gates in the companion decision record (parity
oracle, release benchmarks) commission or reject this direction; then distill
the durable decisions into an ADR and retire this note.

**Disposition:** Gated directional research in the same lineage as
[Bonsai-informed core direction](2026-07-14-bonsai-informed-incr-core-direction.md)
(cross-engine lifecycle hypothesis) and the retention evidence
([2026-07-14 baseline](../performance/2026-07-14-retention-baseline.md),
[2026-07-15 cost attribution](../performance/2026-07-15-retention-cost-attribution.md)).
If commissioned, proceed only through the phase plan after the parity oracle;
if rejected, record the rejection rationale in an ADR and delete this note.

**Provenance:** English translation (2026-08-05) of
`/tmp/incr-retention-api-design.md` (original SHA-256:
`6bdc66acb0ff98dc6f1f04535b732295ffb83cb44b956bb13691f2b0a750e609`). The
translation is faithful to the original, including its known errata;
corrections and follow-up decisions live in the first-principles decision
record.

**Related documents:**
[first-principles decision record](2026-08-05-retention-redesign-first-principles-decisions.md),
[session handoff](2026-08-05-retention-redesign-session-handoff.md)

---

## Conclusion

Incr's public API should not expose the machinery of the reactive graph to
callers.

The central principles are as follows.

1. Separate the read capability from the write capability.
2. Express the read capability as an ordinary getter function `() -> T`.
3. Express the write capability as an ordinary setter function `(T) -> Unit`.
4. Expose derived values as getter functions too.
5. Do not require `read()`, `expose()`, or `dispose()` on passive values.
6. Keep `Graph`, `Node`, roots, Watch, and Scope as internal implementation
   names.
7. Require explicit stopping only for resources that keep running externally,
   such as subscriptions, Effects, and I/O.
8. Change the retention architecture so that as long as a getter function is
   retained, its value is always readable.

The target API looks like this.

```moonbit
let store = Store()

let (source, set_source) = store.input("")

let document = store.view(() => {
  parse_markdown(source())
})

let title = store.view(() => {
  extract_title(document())
})

inspect(title())

set_source("# Hello")

inspect(title())
```

---

## 1. Separating the read and write capabilities

```moonbit
let (source, set_source) = store.input("")
```

The conceptual types are as follows.

```moonbit
type View[T] = () -> T raise ReadError
type Set[T] = (T) -> Unit
```

`source` permits reading only.

```moonbit
fn render(source : () -> String) {
  println(source())
  // it has no write capability
}
```

`set_source` permits writing only.

```moonbit
fn receive_remote_update(set_source : (String) -> Unit) {
  set_source("# Remote")
  // it has no capability to read the current value
}
```

Instead of adding opaque types such as `Readable[T]` and `Writable[T]`,
MoonBit's function types themselves can serve as capabilities.

### Why `read()` becomes unnecessary

If the read side is an opaque struct, extracting the value requires `read()`
or `get()`.

```moonbit
let value = document.read()
```

But if the read capability itself is expressed as a function, the function
call becomes the materialization boundary.

```moonbit
let value = document()
```

This is not special reactive syntax; it is an ordinary MoonBit function call.

---

## 2. Why `Graph` and `Node` are not exposed

`Graph` and `Node` are correct names for describing the implementation, but
they do not express what callers want to accomplish.

What callers want to do:

- Define inputs.
- Separate the read capability from the write capability.
- Create derived views.
- Use the current values.
- Connect UI or external Effects.

Callers do not want to manipulate graph vertices or edges.

In Canopy, the word `Node` is already overloaded:

- syntax node
- projection node
- MarkdownIR node
- DOM node
- CRDT node
- reactive graph node

Adding `Node[T]` to the public API would force readers to decide which Node
is meant every time they read the code.

Therefore the public vocabulary can be limited to roughly:

- `Store`: an independent state-and-computation context
- `input`: produce a read capability and a write capability
- `view`: produce a derived getter
- `effect`: register an external side effect that uses getters
- `batch`: treat multiple updates as one revision

Internally, the implementation may use names such as:

- `GraphCore`
- `NodeState`
- `MountRecord`
- `DependencyEdge`

There is no need to expose these to ordinary callers.

---

## 3. How to handle Store

`Store` does not represent the graph structure; it represents an independent
evaluation space.

```moonbit
let store = Store()
```

Store's responsibilities are limited to:

- revision
- batch state
- scheduler
- the current dependency-tracking context
- the active subscription table
- diagnostics

Store does not own passive derived values by strong reference.

```text
getter closure ──strong──> NodeState
NodeState      ──strong──> StoreCore
StoreCore      ──X───────> passive NodeState
```

Usually `Store` hides inside the constructor of a `MarkdownEditor` or an
application.

```moonbit
pub fn MarkdownEditor::new(...) -> MarkdownEditor {
  let store = Store()
  let (source, set_source) = store.input("")
  ...
}
```

Application callers should deal with Store directly only for low-level
purposes equivalent to Jotai's vanilla store.

---

## 4. Derived views

Derived views are also exposed as getter functions.

```moonbit
let document = store.view(() => {
  parse_markdown(source())
})
```

They can be derived further.

```moonbit
let title = store.view(() => {
  extract_title(document())
})
```

When a getter is called during evaluation, that call is recorded as a
dependency.

Conceptually the behavior is as follows.

```moonbit
fn source() -> String {
  if current_evaluation is Some(parent) {
    parent.record_dependency(source_state)
  }
  source_state.materialize()
}
```

Callers do not need to receive a dedicated function such as `get(source)`.

### Dynamic dependencies

Through ordinary control flow, only getters that were actually called become
dependencies.

```moonbit
let active_document = store.view(() => {
  match mode() {
    Raw => raw_document()
    Preview => markdown_document()
  }
})
```

While in `Raw`, `markdown_document` is not included among the dependencies.

When the branch changes, the dependency set is swapped at the next
evaluation.

---

## 5. Operator overloading

The operators MoonBit currently allows overloading are:

- `+`, `-`, `*`, `/`, `%`
- `==`
- `<<`, `>>`
- unary `-`
- `_[_]`
- `_[_]=_`
- `_[_:_]`
- `&`, `|`, `^`

Official reference:

https://docs.moonbitlang.com/en/latest/language/methods.html#operator-overloading

A call operator for invoking an opaque custom type like a function is not on
the currently supported list.

Therefore the following syntax cannot be implemented with an operator
overload on an opaque `View[T]`.

```moonbit
let source : View[String] = ...
source()
```

To realize `source()`, it is natural for `source` itself to be a real
function `() -> String`.

### Do not repurpose `_[_]` as a getter

The following API could technically be built.

```moonbit
source[()]
source[()] = "# Hello"
```

However, `_[_]` and `_[_]=_` mean element access and element update by
index.

Using them for materializing a reactive value makes the meaning of the syntax
disagree with the meaning of the API.

Also, `source[()] = value` merges the read and write capabilities back into a
single type.

Rejected.

### Do not repurpose `_[_:_]` as a reactive view

```moonbit
document[:]
```

MoonBit recognizes this as the slice/view operator. Since it does not look
like getting the current value, it is rejected.

### Using ordinary operators inside getters

Because getters return ordinary values, there is no need to implement
operators on reactive wrappers.

```moonbit
let (price, set_price) = store.input(100)
let (quantity, set_quantity) = store.input(2)

let total = store.view(() => {
  price() * quantity()
})
```

`price()` and `quantity()` are ordinary `Int`s, so the standard `*` works as
is.

Arrays and Maps are the same.

```moonbit
let selected = store.view(() => {
  items()[selected_index()]
})

let visible = store.view(() => {
  items()[start():end()]
})
```

Here `_[_]` and `_[_:_]` are used with their native meanings.

With this approach, each reactive wrapper does not need to implement:

- `Add`
- `Sub`
- `Mul`
- index operators
- slice operators
- `map2` through `map12`
- operator forwarding per underlying type

---

## 6. What to learn from Jotai

A key characteristic of Jotai is that callers are normally unaware of:

- Runtime
- roots
- GC
- mount
- dispose
- dependency edge registration

An atom is not the state value itself; it is a stable definition/identifier.
Values and dependencies are held in the store.

In React, `useAtomValue` ties subscription mount/unmount to the component
lifetime.

Unsubscribe appears only when subscribing actively outside React.

```typescript
const unsubscribe = store.sub(atom, callback)
unsubscribe()
```

The principles adopted from Jotai are:

1. Reading passive values alone requires no dispose.
2. Unsubscribe is needed only when an external callback keeps running.
3. The UI adapter owns unsubscription automatically.
4. Mount on the first subscription.
5. Unmount on the last unsubscribe.
6. Dependencies are tracked automatically from getter calls made during
   evaluation.

However, Jotai's retention based on WeakMap and the JavaScript GC is not
adopted as-is for MoonBit's shared JS/native/Wasm foundation.

---

## 7. What to learn from Duplix

Duplix's public API is very small.

```moonbit
let (source, set_source) = input("")
let length = source.map(text => text.length())

length.read()
set_source("hello")
length.read()
```

Duplix has the design goal that manual dispose is not required in ordinary
use even under an RC runtime.

It separates value dependencies and dirty propagation into different strands.

```text
value dependencies:
parent Node ──> child Node

dirty propagation:
child DirtyFlag ──> parent DirtyFlag
```

By cutting the reverse edges after dirty propagation, it avoids creating
reference cycles in the value graph.

The principles adopted from Duplix are:

1. Make retaining a read value equivalent to that value being alive.
2. Do not create cycles in the value graph.
3. Manage cleanup of dynamic branches inside `bind`, `switch`, and `assoc`.
4. Do not pass Scope to callers.

However, Duplix's global clock and global current scope are unsuitable for
multiple editors, test isolation, and concurrent execution, so they are not
adopted.

Also, reverse DirtyFlags can keep the small state of discarded parents alive
until the Input is updated.

In Incr, it is better not to create reverse dirty edges for passive values,
and to build reverse edges only while subscribed.

---

## 8. First principles of the retention architecture

Under an RC environment, the following three are hard to satisfy
simultaneously.

1. Permanent push invalidation from child to parent
2. Automatic release just by dropping the getter
3. Not using weak references, finalizers, or explicit dispose

If parents strongly reference children and children strongly reference
parents, a cycle is created.

Therefore the passive graph and the active graph are separated.

---

## 9. The passive graph is pull-only

Unsubscribed getters get no reverse edges.

```text
document getter ──strong──> source state
title getter    ──strong──> document state

source state   ──X──> document state
document state ──X──> title state
```

Derived state conceptually holds:

```moonbit
struct DerivedState[T] {
  store : StoreCore
  compute : () -> T raise ReadError
  dependencies : Array[ErasedState]
  value : T?
  changed_at : Revision
  verified_at : Revision
  computed_at : Revision
}
```

The getter closure strongly references `DerivedState`.

```text
document getter ──strong──> DerivedState[MarkdownIR]
```

Dropping the getter makes the DerivedState releasable.

Because DerivedState strongly references its current dependencies, the
necessary dependencies stay alive as long as the getter is alive.

### The pull verification algorithm

```text
materialize(state)
  ├─ verified_at == store.revision
  │    └─ return the cached value
  │
  ├─ verify dependencies recursively
  │
  ├─ dependency.changed_at unchanged
  │    ├─ do not recompute
  │    ├─ update verified_at
  │    └─ return the cached value
  │
  └─ a dependency changed
       ├─ run compute
       ├─ record the new dependency set
       ├─ compare values
       │    ├─ equal: keep changed_at
       │    └─ changed: update changed_at
       └─ return the new value
```

This achieves:

- lazy evaluation
- equality cutoff
- at most one recomputation per revision
- dynamic dependency tracking
- automatic release of passive getters
- no runtime-wide GC

The price: after an unrelated Input in the Store has been updated, the first
materialization must verify the dependency closure.

As an initial design this is an acceptable tradeoff that prioritizes safety
and retention. A change journal or revision summary can be added after
measurement.

---

## 10. Push invalidation only while subscribed

Reverse edges are built only for views subscribed to by UI or external
Effects.

```moonbit
let stop = store.effect(() => {
  render(document())
})

stop()
```

The passive value graph stays unidirectional.

```text
passive value graph:

document ───────────────> source
```

Reverse edges are registered in the Store's mount table only while
subscribed.

```text
mounted graph:

source ──edge id──> Store mount table ──> document subscriber
```

The important point is that no reverse strong reference is placed between
ordinary states.

### Mount lifecycle

1. On Effect registration, run once and record the getters used.
2. Record getters called during evaluation as dependencies.
3. Register reverse edges in the mount table.
4. On Input updates, dirty-propagate along mounted edges only.
5. Swap edges when dynamic dependencies change.
6. On Effect stop, remove the edges owned by that Effect.

Effect is an active resource, so requiring a stop capability is acceptable.

```moonbit
type Stop = () -> Unit
```

The UI adapter ties Stop to the component lifetime.

```moonbit
@rabbita.bind(document, doc => render(doc))
```

In that case, no `stop()` appears in app code.

---

## 11. Dynamic branches and keyed caches

The lifetime of a dynamic branch is owned by the combinator or the
evaluation engine.

```moonbit
let preview = store.view(() => {
  match mode() {
    Raw => raw_preview()
    Block => block_preview()
    Preview => markdown_preview()
  }
})
```

After evaluation, only the dependencies of the current branch are retained.

- On a branch change, cut the old dependencies.
- If mounted, swap the reverse edges too.
- The old branch is released by ordinary RC.

Keyed-collection caches are explicitly bounded.

- Retain only the current key set.
- Or have an explicit LRU cap.
- Or retain only while mounted.

Do not use runtime-wide GC as a substitute for keyed-cache management.

---

## 12. Do not mix reads with maintenance

Avoid getters like:

```moonbit
attachment.document() // runs Runtime::gc() internally
```

A getter should only return a value.

```moonbit
let document = attachment.document()
```

It must not run callbacks, I/O, runtime-wide GC, or external cleanup.

If maintenance is needed, do it at Store batch end or at scheduler idle
points.

The new retention architecture makes mark-and-sweep for ordinary correctness
itself unnecessary.

---

## 13. Why the current Incr API is hard to use

The current `Derived` facade can be held as a struct field in MoonBit.

```moonbit
struct Editor {
  projection : Derived[Projection]
}
```

However, holding a `Derived` does not make it a root of the Incr GC.

```moonbit
editor.projection.read_or_abort() // succeeds
other_scope.collect()             // GCs the whole runtime
editor.projection.read_or_abort() // Disposed
```

Even though the type and the ownership relationship have not changed, an
operation in another component makes the value unreadable.

To use it safely, callers must understand:

- the difference between `Derived` and `Watch`
- Incr's GC roots
- when to create a Watch
- which Scope to register it in
- who disposes it
- that `ignore(derived.watch())` becomes a leak
- that `Scope::collect()` acts on the whole runtime

This leaks the retention implementation to application callers.

In the new design, retaining the getter closure is equivalent to the internal
state being alive.

---

## 14. Distinguishing passive values from active resources

| Public concept | Role | Explicit stop/dispose |
|---|---|---:|
| getter `() -> T` | passive current value | not needed |
| setter `(T) -> Unit` | Input update capability | not needed |
| derived getter | lazily cached derived value | not needed |
| Effect | continued execution of an external side effect | needed |
| Effect | continued execution of an external side effect | needed |
| I/O adapter | listener, socket, DOM connection | needed |

The principle is:

> Do not demand cleanup for values that do nothing. Demand cleanup only for
> things that keep running externally.

---

## 15. Error handling

If a getter can fail, express it honestly in the type.

```moonbit
type View[T] = () -> T raise ReadError
```

Or convert to `Result` in a product-level API.

```moonbit
let document : () -> Result[MarkdownIR, ParseError] = ...
```

Ordinary passive getters must never become `Disposed` because of a missing GC
root.

`Closed` and `Disposed` are limited to genuinely active resources:

- an explicitly stopped Effect
- a closed socket
- an unmounted DOM adapter
- a disposed external session

---

## 16. Proposed public API

```moonbit
pub struct Store

pub type View[T] = () -> T raise ReadError

pub type Set[T] = (T) -> Unit

pub type Stop = () -> Unit

pub fn Store::Store() -> Store

pub fn[T : Eq] Store::input(
  Self,
  initial : T,
) -> (View[T], Set[T])

pub fn[T : Eq] Store::view(
  Self,
  compute : () -> T raise ReadError,
) -> View[T]

pub fn Store::effect(
  Self,
  run : () -> Unit raise ReadError,
) -> Stop

pub fn Store::batch(
  Self,
  action : () -> Unit,
) -> Unit
```

Details are adjusted to MoonBit's actual type aliases, raise effects, and
generic constraints.

### Usage example

```moonbit
let store = Store()

let (source, set_source) = store.input("")
let (mode, set_mode) = store.input(Preview)

let document = store.view(() => {
  parse_markdown(source())
})

let preview = store.view(() => {
  match mode() {
    Raw => render_raw(source())
    Preview => render_markdown(document())
  }
})

let stop = store.effect(() => {
  patch_dom(preview())
})

store.batch(() => {
  set_source("# Hello")
  set_mode(Preview)
})

stop()
```

Inside the Rabbita adapter, `effect` and `stop` can be hidden and exposed
as a UI-specific `bind`.

---

## 17. Retention invariants

The following are pinned in the implementation and tests.

1. A live getter does not become Disposed through an operation of another
   component.
2. Passive getters need no root, Watch, Scope, or dispose.
3. Store does not strongly reference passive derived state.
4. The passive graph has no reverse edges.
5. A getter closure strongly references its corresponding state.
6. Derived state strongly references only its current dependencies.
7. Reverse edges live only while their Effect exists.
8. After an Effect is stopped, the mount record count returns to its previous
   value.
9. After a dynamic branch switch, the old branch is not retained.
10. Getters do not run GC, callbacks, or I/O.
11. Code without a setter cannot change an Input.
12. Runtime-wide collection is not a precondition of correctness.
13. The same derived state is not recomputed more than once in one revision.
14. If the value is equal, `changed_at` is not updated and downstream is cut
    off.
15. Cross-store dependencies produce a clear error at construction or first
    evaluation.

---

## 18. Phased migration plan

### Phase 1: Experiment with the new getter/setter facade

- Build a prototype of `Store::input` and `Store::view` on top of existing
  Incr.
- A stopgap implementation where getter closures own internal Watches is
  acceptable.
- Validate the feel of the API and dependency tracking.
- Do not treat the retention architecture as complete at this stage.

### Phase 2: Pull-only passive core

- Move NodeState from the Runtime arena's CellId facade to state owned
  directly by getters.
- Abolish reverse subscriber edges on passive Nodes.
- Implement revision-based pull verification.
- Pin equality cutoff and at-most-once recomputation.

### Phase 3: Mounted subscription layer

- Build reverse edges only for getters used during an `effect` run.
- Implement the mount table and dynamic dependency swapping.
- The UI adapter owns the Effect's Stop.
- Confirm in create/destroy stress tests that mount records return.

### Phase 4: Dynamic collections

- Implement branch retention for switch/bind.
- Introduce explicit caps for keyed caches.
- Abolish cache cleanup that depends on runtime-wide GC.

### Phase 5: Shrink the old API

- Discourage direct use of `Derived::read*`.
- Move `Watch`, Scope, CellId, and Runtime GC to advanced/internal APIs.
- Remove `Scope::collect()` from ordinary product code.
- Migrate existing editors to the getter/setter API incrementally.

---

## Final direction

`Lifetime::expose()` can serve as a migration vehicle that safely wraps
existing Incr, but it is not the final DX.

The final goal is:

```moonbit
let (source, set_source) = store.input("")
let document = store.view(() => parse_markdown(source()))

let current = document()
set_source("# Hello")
```

With this API, callers are unaware of the graph, Node, roots, Watch, Scope,
and GC.

Internally the architecture becomes two layers:

1. **Passive layer:** pull-only, RC-safe, no reverse edges, no dispose.
2. **Active layer:** mounted reverse edges only while an Effect exists,
   released reliably on stop.

It integrates Jotai's mount/unmount DX with Duplix's bounded-retention and
acyclic design, adapted to MoonBit's multiple targets and RC constraints.
