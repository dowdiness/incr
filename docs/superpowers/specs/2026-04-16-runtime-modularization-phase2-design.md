# Runtime Modularization Phase 2: Coordinator Routing + Internal Package Split

**Status:** Approved design, pending implementation plan

**Prerequisite:** PR #35 (phase machine, state grouping, subscriber diff unification)

**Goal:** Complete the Runtime god-object decomposition by (1) routing all push propagation through a single coordinator method and (2) splitting engine-specific SoA types into `internal/` sub-packages with compile-time boundary enforcement.

---

## PR 1: Batch→Push Coordinator Routing

### New coordinator method

```moonbit
fn Runtime::propagate_changes(
  self : Runtime,
  changed_ids : Array[CellId],
  durability : Durability,
) -> Unit {
  self.advance_revision(durability)
  for id in changed_ids {
    self.core.cell_ops[id.id].set_changed_at(
      self.core.revision.current_revision,
    )
  }
  if self.push.node_count > 0 {
    self.push_propagate_from(changed_ids)
  }
}
```

After this method exists, `push_propagate_from` has exactly one caller: `propagate_changes`.

### Call site migrations

**`publish_cell_changes`** (runtime.mbt) — already the coordinator pattern for fixpoint:

```moonbit
fn Runtime::publish_cell_changes(self, changed_ids, durability) -> Unit {
  self.propagate_changes(changed_ids, durability)
  self.fire_on_change()
}
```

**`commit_batch`** (batch.mbt) — multi-wave loop with per-signal callbacks:

```moonbit
if changed.length() > 0 {
  any_changed = true
  // Snapshot callbacks BEFORE propagation — preserves invariant that
  // push propagation cannot affect which handlers fire in this wave.
  let callbacks : Array[() -> Unit] = []
  for c in changed {
    let sig = self.get_pull_signal(c.cell_id())
    match sig.on_change {
      Some(f) => callbacks.push(f)
      None => ()
    }
  }
  let changed_ids = changed.map(c => c.cell_id())
  self.propagate_changes(changed_ids, self.core.batch.max_durability)
  self.core.batch.max_durability = Low
  self.core.batch.depth = self.core.batch.depth + 1
  for cb in callbacks { cb() }
  self.core.batch.depth = self.core.batch.depth - 1
}
```

**Critical invariant:** Callbacks are snapshot before `propagate_changes` runs. The current code documents (batch.mbt:164-167) that handlers are captured before any callback executes so that `clear_on_change()` or `on_change()` calls during propagation don't affect which handlers fire. Snapshotting after propagation would be a behavioral regression — a PushReactive's compute closure could mutate `sig.on_change` during propagation.

**`signal.set_unconditional`** (signal.mbt) — non-batched single-signal path:

```moonbit
self.value = new_value
// Snapshot callback before propagation (same invariant as commit_batch)
let cb = self.rt.get_pull_signal(self.cell_id).on_change
self.rt.propagate_changes([self.cell_id], self.durability)
match cb { Some(f) => f(), None => () }
self.rt.fire_on_change()
```

Note: This path is only entered when `batch_depth == 0`. The current code calls `bump_revision` which, at `batch_depth == 0`, falls through to `advance_revision`. So `propagate_changes` calling `advance_revision` directly is semantically equivalent.

### Dead code removal and stale comments

- **`mark_input_changed`** (runtime.mbt:647) — both callers migrate away. Delete it.
- **Comment in `cell_ops.mbt:67`** — references `mark_input_changed`. Update to reference `propagate_changes`.
- **Doc comment on `publish_cell_changes`** (runtime.mbt:596-605) — states that `Signal::set_unconditional` and `commit_batch` "call the lower-level methods directly" and "cannot be expressed through this protocol without restructuring." After this PR, both callers use `propagate_changes`. Update the doc to reflect the new layering: `publish_cell_changes` = `propagate_changes` + `fire_on_change`, and callers that need custom callback sequencing use `propagate_changes` directly.
- **`bump_revision`** — still needed by batched signal paths (`set_batch`, `set_batch_unconditional`) which track `max_durability` during batch. Stays.

### Efficiency note

`commit_batch` gains a second iteration over changed signals (one for callback snapshot, one inside `propagate_changes` for stamping). Acceptable cost for clean coordinator separation.

---

## PR 2: Internal Package Split

### Problem: circular imports

Parent `cells/` and children `cells/internal/*/` cannot have circular imports. Engine packages need to implement traits defined in `cells/`, but `cells/` imports engine packages. Solution: shared trait package.

### Dependency graph

```
types/                          (pure values: CellId, Revision, Durability)
  ↑
cells/internal/shared/          (traits + CellMeta, pub(open) visibility)
  ↑           ↑           ↑
internal/pull/  internal/push/  internal/datalog/   (SoA types + trait impls)
  ↑           ↑           ↑
cells/                          (coordinator: Runtime, handles, algorithms, tests)
```

No cycles. Each engine imports only `types/` and `internal/shared/`. The coordinator imports all four internal packages.

### Verified MoonBit `internal` package behavior

Tested with moon 0.1.20260409:

- **Parent can import `internal/child`:** `cells/` importing `cells/internal/pull/` — compiles ✓
- **External packages blocked:** `other/` importing `cells/internal/pull/` — "Cannot import internal package... due to internal visibility rules" ✓
- **Internal siblings can import each other:** `cells/internal/push/` importing `cells/internal/pull/` — compiles ✓ (not blocked by `internal`)
- **Cross-package trait impl requires `pub(open)`:** `pub` trait from another package is "readonly". `pub(open)` trait allows cross-package `impl` ✓
- **Explicit `impl Trait for Type` required even with defaults:** MoonBit doesn't auto-derive trait conformance through supertrait impls ✓

### What moves where

| Destination | Types |
|-------------|-------|
| `internal/shared/` | `CellMeta`, `HasCellMeta`, `CellOps` (+ default impls), `CellLifecycle` (+ default impls), `Committable` |
| `internal/pull/` | `PullSignalData`, `MemoData`, `PullVerifyFrame` + their trait impls |
| `internal/push/` | `PushReactiveData`, `PushEffectData`, `PushEntry` (+ `Eq`/`Compare`) + trait impls |
| `internal/datalog/` | `RelationData`, `FunctionalRelationData`, `RuleData` + trait impls |
| Stays in `cells/` | `Runtime`, `RuntimeCore`, `PullState`, `PushState`, `DatalogState`, `CellRef`, `PropagationPhase`, `BatchState`, `RevisionState`, `TrackingState`, `ActiveQuery`, all handles (`Signal`, `Memo`, `HybridMemo`), all algorithms (`verify.mbt`, `push_propagate.mbt`, `batch.mbt`, `datalog_fixpoint.mbt`, etc.), all tests |

### Visibility changes

| Symbol | Current | New | Reason |
|--------|---------|-----|--------|
| `CellOps` | `priv` in `cells/` | `pub(open)` in `internal/shared/` | Engine packages must implement it |
| `HasCellMeta` | `priv` in `cells/` | `pub(open)` in `internal/shared/` | Same |
| `CellLifecycle` | `priv` in `cells/` | `pub(open)` in `internal/shared/` | Same |
| `Committable` | `priv` in `cells/` | `pub(open)` in `internal/shared/` | PullSignalData implements it |
| `CellMeta` | `priv` in `cells/` | `pub` in `internal/shared/` | All engines embed it |
| SoA data structs | `priv` in `cells/` | `pub` in `internal/*/` | Coordinator accesses fields |

All within `internal/` — nothing leaks to external consumers.

### Engine isolation enforcement

The `internal` feature blocks external access but does not block sibling imports. Engine isolation is enforced by `moon.pkg` contents — each engine's `moon.pkg` imports only `types/` and `internal/shared/`:

```
# cells/internal/pull/moon.pkg
import {
  "dowdiness/incr/types" @incr_types,
  "dowdiness/incr/cells/internal/shared" @shared,
}
```

CI verification script:

```bash
#!/bin/bash
# Verify no engine package imports another engine package.
# Only checks for cross-engine imports (pull↔push↔datalog).
# internal/shared is allowed — it's the trait package, not an engine.
engines="pull push datalog"
fail=0
for engine in $engines; do
  pkg="cells/internal/$engine/moon.pkg"
  [ -f "$pkg" ] || continue
  for other in $engines; do
    if [ "$engine" != "$other" ] && grep -q "internal/$other" "$pkg"; then
      echo "FAIL: $engine imports $other"
      fail=1
    fi
  done
done
exit $fail
```

### Whitebox tests

Stay in `cells/` — parent can access all `internal/` children. Tests that access SoA struct fields work because those fields are `pub` within the internal packages.

---

## Sequencing

**PR 1 first, PR 2 second.** PR 1 is independent and lower risk. PR 2 benefits from PR 1's clean coordinator boundaries (fewer files reference push internals directly).

## Non-goals

- No public API changes in either PR
- No algorithm changes (push propagation, pull verification, fixpoint stay in `cells/`)
- No handle changes (`Signal`, `Memo`, `HybridMemo` stay in `cells/`)
- No new features — pure structural refactoring

## Risk assessment

- **PR 1 (low):** 3 call sites, well-understood callback invariant, comprehensive test coverage (508+ tests)
- **PR 2 (medium):** Many file moves, visibility changes, import path updates. All mechanically verifiable by `moon check`. The `internal` package feature has been validated on the current moon version.
