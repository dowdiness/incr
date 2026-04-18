# `Relation::subscribe_delta` — Design Sketch

Opt-in delta observation on Datalog relations. Extends Family A from
[reactive-collections.md](reactive-collections.md), scoped to the
existing Datalog engine so the pull-based backdating model is
undisturbed.

**Status:** Exploratory. Revised 2026-04-19 after code verification.
The v1 draft claimed "this matches existing semi-naive promotion
semantics" for fixpoint coalescing — that was wrong. Net-delta
computation requires new snapshot-and-diff machinery at fixpoint
exit. Scope revised accordingly.
**Driver:** Existing `Relation[T]` consumers see only whole-relation
snapshots; they cannot efficiently forward "these rows were added,
those were removed" to external sinks (UI updates, logging,
IPC to a parent process). The Datalog engine already maintains
per-iteration deltas internally; this surface exposes a net-delta
view at commit boundary.

## What the engine actually does today

Verified in `cells/datalog_fixpoint.mbt:32-88` and
`cells/datalog_relation.mbt`:

- `Relation[T]` is **insert-only within a revision.** There is no
  `Relation::remove(row)` API. Rows disappear across revisions only
  when a rule that derived them no longer fires on recomputation.
- Each fixpoint iteration drains the frontier delta into `current`
  and promotes staged deltas to become the next frontier.
- At fixpoint exit, `delta.val` holds only the **final iteration's**
  new facts; facts from earlier iterations are already merged into
  `current` and are indistinguishable.
- `publish_cell_changes(changed_ids, Low)` bumps the revision for
  changed relations. The runtime knows *which relations* changed; it
  does not retain *which rows* changed.

Consequence: exposing a net delta per commit requires **snapshotting
`current` before fixpoint and diffing after.** This is NEW machinery
— not "already free."

## Non-goals

- **Not a pull-side surface.** Pull memos continue to see whole-value
  relation snapshots. Mixing deltas into pull memos would break
  backdating unless the engine retains per-revision history
  (Differential Dataflow's "arrangements"). That is a much bigger
  commitment; we do not take it on here.
- **Not a replacement for `Relation::snapshot` / `iter`.** Snapshots
  remain the canonical read API for pull consumers.
- **Not delta-to-delta composition.** `filter`, `map`, `join` across
  delta streams are Family A proper. Observers just receive deltas.
- **Not cross-relation happens-before ordering.** Observers on two
  different relations in the same commit see their own deltas in
  relation-creation order, but cannot correlate specific rows across
  relations.

## API sketch

```moonbit
// Observer callback. Invoked at commit boundary with the net delta
// since the last invocation (or since subscription, for the first
// call if replay is enabled).
pub trait DeltaObserver[T] {
  on_delta(
    self : Self,
    added : Array[T],
    removed : Array[T],
    rev : Revision,
  ) -> Unit
}

// Opaque subscription handle. Held by the caller; dropped via
// unsubscribe or scope dispose.
pub struct DeltaSubscription {
  priv id : Int
  priv relation_id : CellId
}

// `replay~ = true` (default): first callback delivers all current
// rows in `added`, empty `removed`. `replay~ = false`: observer sees
// only changes that occur after subscription.
pub fn[T] Relation::subscribe_delta(
  self : Relation[T],
  observer : &DeltaObserver[T],
  replay~ : Bool = true,
) -> DeltaSubscription

pub fn Relation::unsubscribe_delta(
  self : Relation[T],
  sub : DeltaSubscription,
) -> Unit
```

## Key design decisions

### Bulk delivery, not per-row

`on_delta` receives `(added, removed, rev)` once per commit. Per-row
delivery rejected: forces the engine to iterate changes on behalf of
every observer, and most observers batch anyway. Matches DDlog's
`dump_changes` shape.

### Net delta via pre-snapshot + post-diff

At the start of any commit that may touch a relation with observers,
snapshot `current` into a per-relation shadow. At commit boundary,
diff shadow against new `current`: `added = new \ shadow`,
`removed = shadow \ new`. Emit if non-empty; clear shadow.

This is O(|relation|) per commit for observed relations only.
Relations without observers pay nothing — no shadow allocated, no
diff computed. Observers that don't care about removals can ignore
the `removed` array; relations that never see removals (most Datalog
inputs) will always deliver empty `removed`.

The shadow-and-diff approach is simple, correct, and engine-local.
Retaining per-iteration deltas would be Differential Dataflow's
arrangement-and-trace — vastly more complex and unnecessary for the
target use cases.

### Replay on subscribe (opt-in, default true)

A new subscriber with `replay~ = true` gets one initial callback with
all current rows in `added`, empty `removed`, `rev` = current
revision. With `replay~ = false`, the subscriber's first callback
fires only on the next real delta.

Replay matters for consumers that need a consistent local view
(UI widgets, logs). Opt-out matters for consumers that only care
about future changes (rule activation traces, debug logging).

Design tradeoff: replay of a million-row relation allocates a
million-item `added`. Acceptable for target use cases (relations
are small). Consumers who subscribe to huge relations with
`replay~ = true` pay the O(n) allocation once at subscribe time.

### Commit-boundary firing

Observers fire at the same point as `Runtime::fire_on_change()`:
after all fixpoint iterations complete, after all batched commits
flush, before `Runtime::batch` returns control to the caller.

Within a single commit, observers on relation R1 fire before
observers on R2 iff R1 was created before R2 (by `cell_ops` index
order). Within a single relation, observer-registration order.

### Re-entry: abort

An observer's callback that calls `insert` on the observed relation
triggers `abort("DeltaObserver re-entry on subscribed relation")`.
MoonBit is single-threaded; deadlock is impossible, so abort is
strictly better than any deferred-fire or queue mechanism. Calls to
*other* relations from within a callback are allowed but their
changes land in the next commit, not this one.

### Subscription lifetime

`DeltaSubscription` is a value-typed handle. Drop it via
`unsubscribe_delta`. When created inside a `Scope`, the subscription
registers on the scope's `dispose_hooks` — scope dispose
auto-unsubscribes.

### Trait placement: new `DeltaDispatch` trait, not CellOps

The runtime's `cell_ops` is the "what every cell supports" trait;
polluting it with a `fire_deltas()` method that most cells no-op
would be wrong. Instead, add a parallel trait:

```moonbit
pub trait DeltaDispatch {
  snapshot_for_observers(self) -> Unit   // before commit
  fire_deltas(self, rev : Revision) -> Unit  // after commit
  has_observers(self) -> Bool            // for fast skip
}
```

Implemented only by `RelationData` and `FunctionalRelationData`.
Registered in a parallel array `rt.core.delta_dispatch :
Array[&DeltaDispatch]`. The runtime's commit-boundary code calls
`fire_deltas` on each entry with observers.

## Semantics / invariants

1. **First-delivery replay (opt-in default).** First `on_delta`
   after subscribe with `replay~ = true` delivers all current rows
   in `added`, empty in `removed`.
2. **Net delta.** Subsequent deliveries carry
   `added = new_current \ pre_commit_current`,
   `removed = pre_commit_current \ new_current`.
3. **No empty deliveries.** If both `added` and `removed` are empty,
   the callback is not invoked.
4. **Fixpoint invisibility.** Deltas from intermediate fixpoint
   iterations are invisible. Only the net result of fixpoint is
   observable, because the shadow is taken before fixpoint and
   the diff after.
5. **Insert-only within revision.** Relations do not support
   row removal. In practice: `removed` is always empty on commits
   whose only mutation was direct `Relation::insert` calls.
   `removed` is non-empty only on cross-revision fixpoint
   recomputations where a previously derived row no longer derives.
6. **Ordering.** Within one commit, observers on relation R1 fire
   before observers on R2 iff R1 was created first. Within one
   relation, observer-registration order.
7. **No re-entry.** Callbacks that insert into the observed relation
   trigger `abort`.
8. **No push-during-pull.** Observer callbacks are invoked outside
   any tracking context; they cannot record dependencies.
9. **Batch rollback invisibility.** `Runtime::batch` rolls back
   pending writes on raise. Observers fire after batch exit, so
   rolled-back inserts never reach observers. Never-fired commits
   do not count toward "last delivery revision."

## Open questions

- **Shadow allocation strategy.** Allocate the shadow lazily when a
  relation first gets an observer, or eagerly on every commit
  regardless? Proposal: lazy — only relations with at least one
  observer allocate.
- **Observer dispatch under `gc()`.** If `gc()` disposes a relation
  that has observers, do observers get a final `removed`-everything
  callback, or just silently disconnect? Proposal: silent
  disconnect matches existing dispose semantics; add a `disposed`
  notification to the trait if a use case materializes.
- **Ordering across multiple observers on the same relation.**
  Observers fire in registration order. Does an observer that
  mutates *another* relation during its callback see that
  relation's in-flight pre-snapshot? Proposal: no — inter-relation
  mutations during delta dispatch land in the next commit, not this
  one.

## Test checklist

- Subscribe to empty relation; insert row; observer sees row in
  `added`, empty in `removed`.
- Subscribe to populated relation with `replay~ = true`; first
  callback has all current rows in `added`.
- Subscribe with `replay~ = false`; first callback fires only after
  a subsequent mutation.
- Insert row, then fixpoint where rule retracts via
  non-rederivation: observer sees net-zero if the row was never
  stable.
- Fixpoint with rule that re-derives an existing row: observer
  does not see the row as `added` again (already in pre-snapshot).
- Fixpoint where a previously-derived row no longer derives: observer
  sees the row in `removed` at commit boundary.
- Multiple observers on one relation: each sees the same delta
  sequence; unsubscribing one doesn't affect others.
- Unsubscribe: no further deliveries after unsubscribe.
- Scope dispose: subscription auto-cancelled; observer never hears
  from disposed relation.
- Pull-side consumer (`Relation::iter` / `Relation::contains`) of
  the same relation continues to see whole-value snapshots
  unaffected by delta subscription.
- Re-entry: observer callback that inserts into the observed
  relation triggers `abort`.
- **Batch rollback:** a batch that inserts rows then raises — observer
  sees no delta from the rolled-back batch.
- **No-observer path is zero-cost:** relations without observers
  do not allocate shadow, do not run diff.

## Integration with existing engine

Requires changes in:

1. **`cells/datalog_relation.mbt`** — add per-relation
   `observers : Array[(Int, &DeltaObserver[T])]`, `shadow :
   Ref[@hashset.HashSet[T]?]`. Add `subscribe_delta`,
   `unsubscribe_delta`. Implement `DeltaDispatch`.
2. **`cells/datalog_functional_relation.mbt`** — same, for
   `FunctionalRelationData`.
3. **`cells/runtime.mbt`** — add `delta_dispatch :
   Array[&DeltaDispatch]`. Call `snapshot_for_observers` before
   commit phases that may touch relations (fixpoint, direct
   inserts). Call `fire_deltas` after `fire_on_change`. Lazy-skip
   if `has_observers` is false.
4. **`cells/datalog_lifecycle.mbt`** — dispose path clears
   observers and shadow.
5. **`cells/scope.mbt`** — register subscription for auto-dispose
   via `dispose_hooks`.

Non-changes: pull verification (`pull_verify`) untouched. `MemoMap`,
`TrackedCell`, `HybridMemo` untouched. Batch / revision / durability
unchanged. `Relation::insert`, `Relation::iter`, `Relation::contains`
unchanged.

## Scope estimate

- Source: ~250 lines across 5 files. The snapshot-and-diff logic is
  the new machinery; the trait dispatch is straightforward.
- Tests: ~400 lines. Fixpoint scenarios and rollback semantics are
  the correctness-heavy parts — budget more testing than source.
- Docs: cookbook entry, Datalog concepts update, a note in
  `reactive-collections.md` that Family A is now partially live.
- **Total: 3–5 days** of focused work. The hard part is fixpoint-
  exit semantics correctness — not the line count. Land as one PR
  with the full observer machinery; splitting earlier invites
  partial states.

## What this does not solve

- **Delta-to-delta composition.** See non-goals.
- **Cross-relation ordering.** See non-goals.
- **Pull-side delta consumption.** Pull memos see snapshots; the
  two channels are parallel, not layered.
- **Retraction as a primitive.** Relations remain insert-only
  within a revision. Adding `Relation::remove` is a separate
  discussion.
