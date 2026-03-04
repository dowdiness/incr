# Design: Dependency Diff in `force_recompute`

**Date:** 2026-02-22
**Status:** Approved

## Context

`Memo::force_recompute` currently replaces the dependency list wholesale and always rescans deps to recompute durability, even when the dep list is identical to the previous one. The todo item asks for a diff instead.

## Goals

- **Performance**: skip `compute_durability` when deps are stable (common case)
- **Subscriber prep**: structure the code so Phase 4 reverse links can be added surgically

## Approach

Reuse the `HashSet[CellId]` already built by `ActiveQuery` during tracking. `pop_tracking` is extended to return both the dependency array and the seen set, giving O(n) stability detection with zero extra allocation.

## Changes

### `runtime.mbt` — `pop_tracking`

Change return type from `Array[CellId]` to `(Array[CellId], @hashset.HashSet[CellId])`:

```moonbit
fn Runtime::pop_tracking(self : Runtime) -> (Array[CellId], @hashset.HashSet[CellId]) {
  match self.tracking_stack.pop() {
    Some(query) => (query.dependencies, query.seen)
    None => abort("Tracking stack underflow")
  }
}
```

`pop_tracking` is `fn` (private), so no public API change.

### `memo.mbt` — `force_recompute`

Capture `old_deps` before computation, unpack `(new_deps, new_seen)` from `pop_tracking`, compute stability, conditionally skip `compute_durability`:

```moonbit
let old_deps = cell.dependencies
self.rt.push_tracking(self.cell_id)
let new_value = (self.compute)()
let (new_deps, new_seen) = self.rt.pop_tracking()

// Diff: detect stable deps to skip durability rescan
let mut deps_changed = new_deps.length() != old_deps.length()
for dep in old_deps {
  if not(new_seen.contains(dep)) {
    deps_changed = true
  }
}
// Phase 4: removed = old_deps.filter(d => not(new_seen.contains(d)))
// Phase 4: unsubscribe self.cell_id from each removed dep

cell.dependencies = new_deps
if deps_changed {
  cell.durability = compute_durability(self.rt, new_deps)
}
```

### Tests (whitebox)

Two new tests — likely in `verify_wbtest.mbt` or a new `dep_diff_wbtest.mbt`:

1. **Stable deps**: signal changes but dep list stays the same — verify correct value, deps unchanged
2. **Dynamic deps**: conditional memo switches which signal it reads — verify new dep is tracked, old dep is not

## Non-Goals

- No public API changes
- No actual subscriber (reverse) link implementation (Phase 4)
- No `added` list computation (not needed until Phase 4)
