# `ReactiveMap[K, V]` — Design Sketch

Per-key memoized map for fine-grained incremental computation over
collection-valued results. Extends Family B from
[reactive-collections.md](reactive-collections.md).

**Status:** Exploratory. Revised 2026-04-19 after code verification
exposed a critical flaw in the v1 draft. A second Codex review the same
day surfaced additional blockers in the v2 sketch — see §"Codex review
2026-04-19" below. Do not implement from this doc; the cross-key dispose
semantics need resolving and `MemoMap::remove_except` is not safe to land
alone.
**Driver:** Lambda name resolution currently returns
`Memo[ResolvedModule]`; any def change invalidates the whole module's
downstream consumers. A `ReactiveMap[DefName, ResolvedDef]` whose per-key
reads are *tracked* lets downstream memos that read one def ignore edits
to other defs.

## Why v1 was broken

The v1 draft built `ReactiveMap::get` directly on `MemoMap::get`. But
`MemoMap::get` is **untracked** (`memo_map.mbt:52-54` calls
`get_or_create_memo(key).get_untracked()`). Reading `map.get(k)` from
inside another `Memo` records no dependency on the per-key memo — so
the downstream consumer had no per-key isolation at all. The core
value proposition was impossible under the existing API.

This revision fixes that by (a) requiring a new tracked read on
`MemoMap`, and (b) restructuring the primitive so the key set is owned
upstream, not managed internally.

## Codex review 2026-04-19

A second validation pass against current HEAD surfaced blockers the
v1→v2 revision did not address. The central tracking claim is correct
(`MemoMap::get_or_create_memo(key).get()` records exactly the per-key
memo's `CellId` as a dependency, via `cells/memo.mbt:157-166` →
`cells/tracking.mbt:60-65`). The broken claims are about *disposal* and
*call context*.

### Blocker 1: Cross-key dispose aborts, doesn't recompute

§"Cross-key dep + key removal: cascade via dispose" (below) claims that
disposing k₂'s memo via `sweep()` invalidates subscribers and triggers
k₁'s recompute on next verify. **This is false at HEAD.** The pull-memo
dispose path (`cells/pull_memo_lifecycle.mbt:8-22`) removes the disposed
memo from its own upstream deps and clears its own subscriber set — but
does *not* notify existing subscribers. Any downstream memo that still
references the disposed dep hits the disposed-dep guard in
`cells/verify.mbt:123-131` and aborts. PR #32's push-suspension
machinery is orthogonal — it handles push subscribers, not pull-memo
disposal.

Two options to resolve:

- **Option A (scope-limited, ~no engine work):** forbid cross-key deps
  in v1. `compute(k)` may not read `rm.get(k')`. Document the
  restriction; block future lifting on engine work. The driver (name
  resolution: def A references def B) becomes unsupported in v1.
- **Option B (engine work):** change the pull-verify path to treat
  disposed deps as "invalidated, must recompute" rather than abort.
  Non-trivial — touches the dispose/GC layers from PRs #28–#33 and
  likely needs a new cell lifecycle state ("disposed-but-resurrectable").

### Blocker 2: `ReactiveMap::get` is tracked-only

`Memo::get` aborts at top level (`cells/memo.mbt:157-163`) — unlike
`Relation::iter` / `Relation::contains`, which are usable outside a
tracking context. The API sketch's `ReactiveMap::get` inherits this
restriction: top-level (non-memo) reads abort. The driver example in
§"Calling-site example" assumes `lookup_type(name)` can be called
freely; in fact it would only be callable from inside another memo.

Resolve: either (a) add `ReactiveMap::get_untracked(k) -> V` explicitly
and document which call contexts use which, or (b) document that
`ReactiveMap::get` is tracked-only and restructure the driver example.

### Blocker 3: `remove_except` is not isolated bookkeeping

§"Integration with existing engine" claims "Non-changes: pull
verification". This is wrong once Blocker 1 is considered:
`MemoMap::remove_except` triggers the same disposed-dep abort path as
`sweep()`. It is *safe to call only when no downstream memo references
the removed keys* — a contract the caller must enforce. Document this,
or block `remove_except` behind Blocker 1's engine work.

### Revised scope estimate

The 2–3 day / 2–3 PR estimate is credible for **"tracked per-key memo
lookup exists without cross-key deps"** (Blocker 2 resolution +
`MemoMap::get_tracked` alone). It is not credible for **"cross-key deps
plus key removal are safe"** (Blocker 1 Option B), which requires
engine work in `verify.mbt` and the dispose lifecycle and should be
scoped separately.

### Recommended next step

Land `MemoMap::get_tracked` alone as a standalone PR (3-line addition,
Codex-confirmed tracking path is correct). Do **not** land
`MemoMap::remove_except` or `ReactiveMap` itself until the cross-key
dispose semantics are resolved. Then pick Option A (ship v1 with
no-cross-key-deps restriction) or Option B (engine work, larger scope).

## Shape: derive-from-upstream

The revised design treats `ReactiveMap` as a *lens*, not an input
container:

- The **key set** is a `Memo[Set[K]]` or `Signal[Set[K]]` owned by the
  caller (typically derived from a parsed source).
- The **per-key compute** is a function fixed at construction.
- The primitive's job is to offer two read channels — coarse
  (over the key set) and fine (per-key, tracked) — plus a disposal
  helper when keys leave.

This matches the actual driver: the set of def names is not a direct
input but is derived from an upstream parse memo. Alternatives
considered in §Alternatives.

## API sketch

```moonbit
pub struct ReactiveMap[K, V] {
  priv rt : Runtime
  priv keys : Memo[@immut/hashset.T[K]]
  priv cells : MemoMap[K, V]
}

pub fn[K : Hash + Eq, V : Eq] ReactiveMap::new(
  rt : Runtime,
  keys : Memo[@immut/hashset.T[K]],
  compute : (K) -> V,
  label? : String,
) -> ReactiveMap[K, V]

// Fine-grained per-key read. Records a dependency on the per-key memo
// only — NOT on the upstream key set. Used inside compute closures
// that only care about one key's value.
//
// Requires MemoMap::get_tracked (new — see §Integration).
pub fn[K : Hash + Eq, V : Eq] ReactiveMap::get(
  self : ReactiveMap[K, V],
  key : K,
) -> V

// Coarse read of the current key set. Records a dependency on the
// upstream `keys` memo. Used when iterating all entries or reacting
// to key-set changes.
pub fn[K, V] ReactiveMap::keys(
  self : ReactiveMap[K, V],
) -> @immut/hashset.T[K]

// Iterate (k, v) pairs. Records dependencies on the key set AND every
// per-key memo touched during iteration. Use sparingly — this is the
// "read everything" channel.
pub fn[K : Hash + Eq, V : Eq] ReactiveMap::iter(
  self : ReactiveMap[K, V],
) -> Iter[(K, V)]

// Dispose per-key memos whose keys are no longer in the upstream key
// set. Idempotent. Call periodically (e.g. after each
// Runtime::fire_on_change cycle) to prevent unbounded memo growth.
//
// Requires MemoMap::remove_except (new — see §Integration).
pub fn[K : Hash + Eq, V] ReactiveMap::sweep(
  self : ReactiveMap[K, V],
) -> Int
```

No mutation API on `ReactiveMap`. The upstream `keys : Memo` changes
as its dependencies change; `ReactiveMap` reacts.

## Key design decisions

### Tracked per-key read requires a `MemoMap` addition

`MemoMap::get` is deliberately untracked (it's called from test and
lifecycle code). `ReactiveMap::get` needs a *tracked* read path. Add
to `MemoMap`:

```moonbit
pub fn[K : Hash + Eq, V : Eq] MemoMap::get_tracked(
  self : MemoMap[K, V],
  key : K,
) -> V {
  self.get_or_create_memo(key).get()  // .get() is tracked
}
```

This is a 3-line addition, but it's a real API-surface change; it
should land as a standalone PR before `ReactiveMap` builds on it.

### Absent-key semantics: auto-create, sweep explicitly

`get(k)` for a key not in the upstream set *still creates and computes
the per-key memo* — matching existing `MemoMap` behavior. The upstream
`keys` memo is advisory, not enforced. Consistency is maintained by
periodic `sweep()`, which disposes memos for keys that have left the
upstream set.

Alternatives considered:

- **Abort on absent key.** Rejected — forces every `get(k)` to also
  read the keys memo, creating a coarse-grained dep that defeats the
  per-key isolation the design exists to provide.
- **Return `Option[V]`.** Rejected — changes call-site ergonomics
  from `rm.get(k)` to `rm.get(k).unwrap()`, and doesn't meaningfully
  help: the consumer already has to handle "what if k isn't there" in
  upstream logic.

### Cross-key dependencies are allowed

`compute(k1)` may call `rm.get(k2)`. Creates a per-key dep edge in the
runtime's graph. Cycle detection via `get_result` works per-key.
Required for the driver (name resolution: def A references def B).

### Cross-key dep + key removal: cascade via dispose

If `compute(k1)` reads `rm.get(k2)` and `k2` is removed (disposed by
`sweep`), the existing dispose path in `incr` invalidates subscribers
of `k2`'s memo. On `k1`'s next verify, it sees a disposed dep and
recomputes. If the recomputation no longer reads `k2`, no dangling
reference; if it does, `MemoMap::get_or_create_memo` auto-creates a
fresh entry.

This works *if* subscribers are correctly notified on dispose — which
they are (PR #32's push-suspension machinery). Verify with a test.

### Scope integration is explicit, not ambient

There is no ambient scope in `incr`. To integrate `ReactiveMap` with
`Scope`-based lifecycle, add a `Scope::reactive_map(...)` constructor
that registers `sweep` + final disposal on the scope's
`dispose_hooks`. This is analogous to `Scope::signal` and
`Scope::memo`.

## Calling-site example

Before (lambda name resolution today):

```moonbit
// One coarse memo — any def change invalidates the whole thing.
let resolved : Memo[ResolvedModule] = Memo::new(rt, () =>
  resolve_all_defs(parse_memo.get())
)

// Downstream: every read of a single def's type re-runs on any edit.
fn lookup_type(name : DefName) -> Type {
  resolved.get().defs.get(name).map(|d| d.type).unwrap()
}
```

After:

```moonbit
// Upstream: key set is itself a memo over parsed defs.
let def_names : Memo[@immut/hashset.T[DefName]] = Memo::new(rt, () =>
  parse_memo.get().defs.keys().collect()
)

// Per-key resolution. compute reads only this def's body + its deps.
let resolved : ReactiveMap[DefName, ResolvedDef] =
  ReactiveMap::new(rt, def_names, (name) => resolve_def(parse_memo, name))

fn lookup_type(name : DefName) -> Type {
  resolved.get(name).type  // tracked per-key read
}
```

A downstream memo that only reads `lookup_type("foo")` is invalidated
only when `foo`'s def changes, not when `bar`'s def changes.

## Semantics / invariants

1. **Isolation.** A consumer of `rm.get(k1)` is not invalidated by
   changes to `rm.get(k2)`, assuming `compute(k1)` does not read
   `compute(k2)`.
2. **Key-set observability.** A consumer of `rm.keys()` sees inserts
   and removes (via the upstream memo changing) but not per-key value
   changes.
3. **Lazy instantiation.** `compute(k)` runs at most once per revision
   in which `get(k)` is called.
4. **Advisory key set.** `get(k)` works for any `k`, regardless of
   whether `k` is in the upstream set. Consistency is an explicit
   `sweep()` call, not an automatic check.
5. **Backdating.** Requires `V : Eq`; per-key memos use existing memo
   backdating. A `compute(k)` that returns a value equal to the
   cached one does not invalidate downstream.
6. **Cross-key deps work.** A memo for `k1` that reads `get(k2)`
   records `k2`'s memo as a dep; edits to `k2` invalidate `k1`.

## Open questions

- **HashSet `Eq`.** Does `@immut/hashset.T[K]` implement structural
  `Eq` so `Memo[Set[K]]` backdating works? Verify before committing
  to the type signature. (If not, the user can wrap in a newtype with
  a custom `Eq`.)
- **Sweep frequency.** Who calls `sweep()`? Options: (a) caller's
  responsibility, (b) wired to `Runtime::fire_on_change`, (c) tied
  to scope dispose only. Proposal: (a) for v1 — explicit is better
  than magic; revisit after a real consumer exists.
- **`iter()` semantics.** Does iteration record a dep on every
  per-key memo, or just on the key set? The API above says "every
  per-key memo," which makes `iter` effectively coarse. A variant
  `iter_lazy()` returning `Iter[(K, () -> V)]` would defer tracking
  until each value is read. Defer this decision to v2.

## Test checklist

- `get(k1)` not invalidated by upstream edits that change only `k2`'s
  value.
- `keys()` invalidated when upstream `keys` memo changes.
- Cross-key dep: `compute(k1)` reads `get(k2)`; edit to `k2`
  invalidates `k1`'s memo.
- Cycle across keys: `compute(k1)` reads `get(k2)` and vice versa;
  `get_result` returns `CycleError`.
- `sweep`: after upstream key set drops `k`, `sweep()` disposes
  `k`'s memo; subsequent `get(k)` auto-creates a fresh entry.
- Cross-key + sweep: if `compute(k1)` depends on `get(k2)` and `k2`
  is swept, `k1`'s next verify recomputes. No dangling reads.
- Backdating: upstream keys memo emits the same set on a
  non-structural edit; `keys()` consumers don't re-run.
- Scope: `Scope::reactive_map` constructor; scope dispose sweeps all
  and disposes the map.

## Integration with existing engine

Three additions required (in order):

1. **`MemoMap::get_tracked(k) -> V`** — thin tracked wrapper over the
   inner `Memo::get`. 3 lines. Ships as a standalone PR.
2. **`MemoMap::remove_except(keys : Set[K]) -> Int`** — bulk disposal
   of entries not in `keys`. Returns count disposed. ~15 lines. Ships
   with `ReactiveMap` since it's `ReactiveMap`'s driver.
3. **`Scope::reactive_map(...)` constructor** — analogous to
   `Scope::memo`. Optional for v1; can be added post-facto.

Non-changes: pull verification, subscription/dispose cascade, batch,
durability.

## Scope estimate

- `MemoMap::get_tracked` + `MemoMap::remove_except` + tests:
  ~0.5 day.
- `ReactiveMap` source + tests: ~1 day.
- `Scope::reactive_map` + test: ~0.5 day (can defer).
- Docs: cookbook entry, `reactive-collections.md` update, concepts
  note. ~0.5 day.
- **Total: 2–3 days** of focused work, landing as 2–3 PRs.

## Alternatives considered

**Self-contained with mutation API.** `insert_key(k)` / `remove_key(k)`
on `ReactiveMap`, owning an internal `Signal[Set[K]]`. Rejected: adds
mutation-state to the primitive and forces users to manually
synchronize with whatever upstream source actually drives the key set.
For the driver (name resolution) the keys come from parsing —
deriving from upstream is the natural shape.

**Expose inner `Memo[V]` instead of `V`.** `get_memo(k) -> Memo[V]`,
user calls `.get()`. Rejected: leaks internal cell identity, makes
disposal semantics confusing (user might hold a reference to a
disposed memo), and doesn't save any code over `get_tracked`.

## Non-goals

- **Dynamic key-set derivation from scratch.** Users wire the
  upstream `keys : Memo[Set[K]]` themselves. `ReactiveMap` does not
  infer keys from insertions.
- **Aggregations (sum, fold, join across keys).** These still re-run
  on any key change. Family A (delta streams) is the direction.
- **Automatic sweep.** Explicit call in v1; revisit once a consumer
  exists.
