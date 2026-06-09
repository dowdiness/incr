# Design: Composable Runtime Hooks (issue #210)

**Status:** Proposed (design / WHAT only — implementation HOW is a separate doc)
**Date:** 2026-06-09
**Issue:** [#210](https://github.com/dowdiness/incr/issues/210)
**Reopens:** the "Single listener, not multi-listener" trade-off deferred by
[2026-05-17-memo-event-observation.md](../decisions/2026-05-17-memo-event-observation.md)
("Reopen if a real two-consumer case arrives"). The Incremental TEA renderer
(PR #208) installing a runtime hook on top of an existing observer *is* that
two-consumer case.

## Problem

Two runtime-global hooks are singleton-style — a second registration silently
clobbers the first:

1. **on-change** — `Runtime::set_on_change` writes `RuntimeCore.on_change :
   (() -> Unit)?`; fired once per revision bump by `@kernel.fire_on_change`.
2. **derived-event** — `Runtime::on_derived_event` writes
   `EventBroadcastPhaseHook.listener : ((DerivedEvent) -> Unit)?`; buffered in
   `pending` and drained at safe points.

A browser/UI integration that installs the TEA renderer cannot coexist with any
other observer on the same `Runtime`.

## Goal

Make both hooks composable (N listeners coexist), with idempotent + phase-safe
removal, documented ordering and mutation-during-callback semantics, while
keeping the singleton APIs source-compatible.

## Design

### Shared mechanism: `ListenerRegistry[F]`

A single generic ordered registry, defined `pub(all)` in
`incr/cells/internal/kernel/` so both the on-change side (kernel-resident
`fire_on_change`) and the derived-event side (cells-resident hook) reuse one
implementation. It is **not** part of the public API — `kernel` is an `internal/`
package external consumers cannot import.

```
priv struct ListenerEntry[F] { id : ListenerId; mut callback : F }

pub(all) struct ListenerRegistry[F] {
  entries : Array[ListenerEntry[F]]   // registration order preserved
  mut singleton : ListenerId?         // the slot owned by the singleton API
}
```

Operations (all O(n) on a tiny n; listener counts are small):

- `add(id, f)` — append a new entry; used by the additive API.
- `remove(id) -> Bool` — delete the entry with `id` (and clear `singleton` if it
  matches). Returns whether anything was removed. **Idempotent**: removing an
  absent id is a no-op.
- `set_singleton(alloc_id, f)` — if `singleton` names a live entry, replace its
  `callback` **in place** (position preserved); else allocate via `alloc_id()`,
  append, and record it as `singleton`. The `alloc_id` thunk is only invoked
  when a new entry is created, so repeated `set_*` calls do not burn ids.
- `clear_singleton()` — remove the singleton entry if present; idempotent.
- `is_empty() -> Bool`
- `snapshot() -> Array[F]` — a fresh array of the callbacks, safe to iterate
  while `entries` is mutated.

**Invariant:** `singleton` is `Some(id)` iff an entry with that id exists *and*
was created via `set_singleton`. `remove` of that id (or `clear_singleton`)
restores it to `None`.

### Listener identity: `ListenerId`

A new public opaque handle in `incr/types/` (`@incr_types`), re-exported through
the facade, modeled on `RuntimeId`:

```
pub(all) struct ListenerId { runtime_id : RuntimeId; id : Int } derive(Eq, Hash, Debug)
```

An id pairs the originating `RuntimeId` with an allocation number drawn from a
single per-runtime monotonic counter (`RuntimeCore.next_listener_id`, via
`@kernel.alloc_listener_id`) **shared across both registries**. The two parts
guard two different mismatches: the shared counter makes ids unique across the
two registries *within* one runtime, and the `RuntimeId` makes them unique
*across* runtimes (the bare counter alone would collide — the first listener of
two runtimes would both be number 0, so an id from `rt1` would wrongly match and
detach `rt2`'s first listener). Together, passing an id to the wrong registry or
the wrong runtime is a no-op. Ids are introspection/debug identities (like
`RuntimeId`), not stable cross-run keys.

### On-change registry (unguarded)

`RuntimeCore.on_change : (() -> Unit)?` → `on_change_listeners :
ListenerRegistry[() -> Unit]`.

`fire_on_change(core)` snapshots and fires all listeners under a single
`run_callback` (callback-depth raise), preserving the existing depth-guard
behavior:

```
if core.on_change_listeners.is_empty() { return }
let snapshot = core.on_change_listeners.snapshot()
run_callback(core, () => { for f in snapshot { f() } })
```

**No phase guard** on on-change registration/removal — preserving the existing
`set_on_change` behavior, which is *principled*: the on-change hook has no
buffer/drain state. It is read as a snapshot at exactly one well-defined point
(post-propagation), so mutating the list at any time is safe (the change simply
takes effect on the next fire). This is the snapshot-before-fire invariant
already documented in `commit_batch` (kernel/batch.mbt §1, I4) extended from one
handler to N.

### Derived-event registry (idle-guarded)

`EventBroadcastPhaseHook.listener : ((DerivedEvent) -> Unit)?` → `listeners :
ListenerRegistry[(DerivedEvent) -> Unit]`.

- `before_recompute` / `after_success` / `after_abort` short-circuit on
  `self.listeners.is_empty()` (was `listener is None`); `event_broadcast_enabled`
  likewise.
- `drain` snapshots listeners once, then delivers **event-major**: for each
  buffered event (in pull-traversal order), every listener fires in registration
  order before the next event:

```
self.draining = true
let listeners = self.listeners.snapshot()   // mutation forbidden while draining
while !self.pending.is_empty() {
  let events = self.pending; self.pending = []
  for evt in events { for f in listeners { f(evt) } }
}
self.draining = false
```

**Phase guard retained** on all derived-event registration/removal
(`add`/`remove`/singleton) via the existing `is_listener_mutation_safe()`
composite predicate (phase Idle ∧ callback_depth 0 ∧ tracking stack empty ∧
batch depth 0 ∧ static_recompute_depth 0 ∧ no pending events ∧ not draining).
This is *principled and asymmetric* vs on-change: the derived-event hook **does**
have buffer/drain state. Registering a listener while events are buffered raises
the "does the new listener replay buffered events?" ambiguity; mutating during
drain is the concurrent-modification hazard. The guard forbids both. Removal is
still idempotent *within* the safe window (absent id → no-op success); mid-flight
removal raises `Failure`.

### Public API

Singleton APIs unchanged in signature and semantics (source-compatible), now
backed by the registry's reserved singleton slot:

| API | Guard | Maps to |
|-----|-------|---------|
| `set_on_change(f)` | none | `on_change_listeners.set_singleton` |
| `clear_on_change()` | none | `on_change_listeners.clear_singleton` |
| `on_derived_event(f) raise Failure` | idle | `listeners.set_singleton` |
| `clear_derived_event_listener() raise Failure` | idle | `listeners.clear_singleton` |
| `on_memo_event` / `clear_memo_event_listener` (deprecated) | idle | as today |

New additive APIs:

| API | Guard | Returns |
|-----|-------|---------|
| `add_on_change_listener(f) -> ListenerId` | none | id |
| `remove_on_change_listener(id)` | none | Unit (idempotent) |
| `add_derived_event_listener(f) -> ListenerId raise Failure` | idle | id |
| `remove_derived_event_listener(id) raise Failure` | idle | Unit (idempotent) |

### Documented contract

- **Ordering (on-change):** listeners fire in registration order. The
  `set_on_change` singleton fires at the position where its slot is *currently*
  registered: re-calling `set_on_change` while a singleton is live replaces the
  callback in place (position preserved); calling `clear_on_change` then
  `set_on_change` re-appends at the current end (new position). `remove_*` of the
  singleton's id clears the singleton marker too, so a later `set_on_change`
  re-appends.
- **Ordering (derived-event):** event-major — for each event (pull-traversal
  order), all listeners fire in registration order before the next event.
- **Mutation during callback (on-change):** allowed; takes effect on the *next*
  fire (current fire iterates a snapshot).
- **Mutation during callback (derived-event):** forbidden — the `draining`
  conjunct of `is_listener_mutation_safe()` makes any add/remove/singleton call
  from inside a listener raise `Failure`. Mutate between operations.
- **Idempotent removal:** removing an unknown/already-removed id is a no-op.
- **Singleton vs additive:** use `set_on_change`/`on_derived_event` for a single
  owner-controlled hook that should *replace* on re-registration (back-compat,
  app-level "the" callback); use `add_*_listener` for composable observers that
  must coexist and are individually removable by id (UI integrations, profilers,
  test taps).

### Consumer update (acceptance criterion)

The TEA browser renderer (`examples/incr_tea/renderer_js.mbt`) switches from the
singleton APIs to the additive ones so mounting no longer clobbers a pre-existing
hook, and stores the returned `ListenerId`s for a future unmount (#209):

- `runtime.set_on_change(...)` → `runtime.add_on_change_listener(...)`
- `try! runtime.on_derived_event(...)` → `runtime.add_derived_event_listener(...)`

## Invariants preserved

- **I4 / callback-snapshot-before-push:** the per-cell on_change snapshot in
  `commit_batch` is untouched; the *global* on_change now also iterates a
  snapshot, so push propagation triggered inside a listener cannot change which
  global handlers fire in the current wave.
- **Engine isolation:** `ListenerRegistry` lives in `kernel` (pub(all),
  internal); `cells/*.mbt` may import kernel (one-way rule); kernel never imports
  cells. `ListenerId` lives in the zero-dependency `types` package.
- **Lifecycle bracketing / drain protocol:** unchanged — only the listener
  *fan-out* changes (1 → N), buffering and drain sites are identical.

## Non-goals

- Push-reactive / effect / fixpoint / batch-boundary event surfaces (still
  driver-gated per the Memo Event Observation ADR).
- Per-listener ordering control or priorities (registration order only).
- The `RuntimeEvaluationEventHook` (internal trace/strategy hook) — not a
  user-facing API; out of scope.
