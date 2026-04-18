# Datalog Dispose Factoring — Design Note

**Date:** 2026-04-18
**Scope:** `cells/datalog_lifecycle.mbt`
**Status:** Decision recorded; helper-function refactor applied.

## Context

Three `CellLifecycle::dispose_cell` impls for `RelationData`, `FunctionalRelationData`, and `RuleData` had identical three-line bodies:

```moonbit
self.meta.subscribers.clear()
self.meta.label = None
rt.core.cell_index[cell_id.id] = Disposed
```

The question: factor via a private helper function, or hoist to a trait-level default impl on `CellLifecycle`?

## Options Considered

### A. Private helper function (chosen)

```moonbit
fn dispose_datalog_cell(meta : CellMeta, rt : Runtime, cell_id : CellId) -> Unit {
  meta.subscribers.clear()
  meta.label = None
  rt.core.cell_index[cell_id.id] = Disposed
}

impl CellLifecycle for RelationData with dispose_cell(self, rt, cell_id) -> Unit {
  dispose_datalog_cell(self.meta, rt, cell_id)
}
// ... and for FunctionalRelationData, RuleData
```

### B. Trait-level default impl with `HasCellMeta` supertrait

```moonbit
priv trait CellLifecycle : HasCellMeta {
  dispose_cell(Self, Runtime, CellId) -> Unit = _
  on_observe(Self, Runtime, CellId) -> Unit = _
  on_unobserve(Self, Runtime, CellId) -> Unit = _
}

impl CellLifecycle with dispose_cell(self, rt, cell_id) -> Unit {
  let meta = HasCellMeta::meta(self)
  meta.subscribers.clear()
  meta.label = None
  rt.core.cell_index[cell_id.id] = Disposed
}
```

The three datalog impls disappear entirely; pull/push/memo continue to override.

## First-Principle Analysis

**Is the three-line body universally correct?** Checked against every existing `CellLifecycle` impl:

| Impl                | Clears `meta.subscribers` | Sets `meta.label = None` | Sets `cell_index = Disposed` |
|---------------------|---------------------------|--------------------------|------------------------------|
| `PullSignalData`    | ✓                         | ✓                        | ✓                            |
| `MemoData`          | ✓                         | ✓                        | ✓                            |
| `PushReactiveData`  | ✓ (via `clear_slot`)      | ✓ (via `clear_slot`)     | ✓                            |
| `PushEffectData`    | ✓ (via `clear_slot`)      | ✓ (via `clear_slot`)     | ✓                            |
| `RelationData`      | ✓                         | ✓                        | ✓                            |
| `FunctionalRelationData` | ✓                    | ✓                        | ✓                            |
| `RuleData`          | ✓                         | ✓                        | ✓                            |

The three-line body is a genuine subset of every correct dispose today — Option B is semantically viable.

### Arguments for Option A (helper)

1. **Silent-wrong-default risk.** A new cell kind inheriting the default could leak if it also needs upstream-link cleanup (`rt.remove_subscriber`) or free-list bookkeeping. With the helper, the compiler forces an explicit `dispose_cell` impl; the author sees pull/push as examples and chooses deliberately. Disposal is correctness-critical; defaults that are "subset of correct" are footguns.
2. **Discoverability.** Reading `datalog_lifecycle.mbt` to answer "what happens when a `Rule` is disposed?" yields the three impls plus a docstring explicitly contrasting datalog ("no upstream subscriber links, no free-list slots") with pull/push. The default-impl version cannot host that contrast naturally — a trait default reads as universal, obscuring why pull/push override.
3. **Asymmetry with existing defaults.** `on_observe` / `on_unobserve` defaults are `()` — genuinely no-ops. A default that *does work* is categorically different; it elevates a kind-specific minimum into a universal contract.

### Arguments for Option B (default impl)

1. Eliminates three one-liner impls (~5 lines saved).
2. Encodes the shared invariant at the trait level.
3. `HasCellMeta` supertrait is already satisfied by every impl via `CellOps` — the bound change is honest, not constraining.

## Decision

**Option A.** The line savings is marginal. The correctness-critical nature of disposal tips the balance toward forcing explicit thought at each implementor. The helper's docstring scopes the shared logic precisely to where it's actually shared (datalog kinds), leaving the trait honest about having no universal disposal.

## Revisit Criteria

Reconsider Option B if:

- A fourth or fifth datalog-shaped cell kind appears with the same minimal disposal.
- Adding cell kinds becomes frequent enough that the boilerplate cost exceeds the explicit-dispatch benefit.
- The invariant "every cell's minimum disposal is clear-meta + mark-disposed" needs enforcement at the type level (e.g., a refactor introduces a new kind that incorrectly omits `cell_index = Disposed`).
