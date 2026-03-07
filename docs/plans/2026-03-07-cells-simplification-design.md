# Cells Simplification Design

**Status:** Design approved, implementation plan below

**Goal:** Reduce complexity in the `cells/` package by splitting `runtime.mbt`, deduplicating validation patterns, and extracting dispose cleanup methods.

**Prerequisite:** Runtime modularization (PR #19) — sub-structs, refunctionalized CellOps, capability traits are already in place.

---

## Changes

### 1. Split runtime.mbt (1,101 LOC) into 4 files

| New file | Content | ~LOC |
|----------|---------|------|
| `batch.mbt` | `BatchUndo`, `BatchFrame` structs + all batch methods (`batch`, `batch_result`, `commit_batch`, `rollback_current_batch_frame`, `complete_batch_frame_success`, `record_batch_signal`, `record_batch_rollback`, `remove_batch_signal`, `recompute_batch_max_durability`) | 250 |
| `tracking.mbt` (merge into existing 48 LOC) | `Tracker` impl (`record_dependency`, `push_tracking`, `pop_tracking`), `begin_tracking`, `end_tracking`, `finish_tracking`, `collect_tracking_path` | 170 |
| `introspection.mbt` | `CellInfo` struct, `cell_info`, `dependents`, `snapshot_subscribers`, `collect_in_progress_path` | 100 |
| `runtime.mbt` (remains) | Globals, sub-structs, `Runtime` struct, `new`, `alloc_next_id`, `alloc_cell_id`, `new_signal_id`, `validate_cell`, accessors (`get_changed_at`, `get_durability`, `get_pull_signal`, `get_pull_memo`, `get_hybrid_memo`, `get_subscribers`, `add_subscriber`, `remove_subscriber`, `cell_id_for`), `RevisionManager` impl, `on_change` methods, `dispose_reactive`, `dispose_effect` | 630 |

All methods stay on `Runtime`. This is a file-level split only — no package or visibility changes.

### 2. Extract validate_cell helper

The runtime_id + bounds check pattern appears 10 times in `runtime.mbt`:

- `get_changed_at`, `get_durability`, `get_subscribers`, `add_subscriber`, `remove_subscriber`
- `get_pull_signal`, `get_pull_memo`, `get_hybrid_memo`
- `cell_info`, `dependents`

Extract into:

```moonbit
fn Runtime::validate_cell(self : Runtime, id : CellId, caller : String) -> Unit {
  if id.runtime_id != self.core.runtime_id {
    abort("Cell belongs to a different Runtime")
  }
  if id.id < 0 || id.id >= self.core.cell_ops.length() {
    abort(caller + ": cell_id out of bounds: " + id.id.to_string())
  }
}
```

**Not refactored:** The 4 validation checks in `verify.mbt` stay inline — they're on the hot path and have different abort messages/semantics.

**Note:** `cell_info` and `dependents` currently return `None` / `[]` instead of aborting on invalid IDs. These will use a `validate_cell_soft` variant that returns `Bool` instead of aborting:

```moonbit
fn Runtime::validate_cell_soft(self : Runtime, id : CellId) -> Bool {
  id.runtime_id == self.core.runtime_id &&
  id.id >= 0 &&
  id.id < self.core.cell_ops.length()
}
```

### 3. Dispose cleanup methods

Add `clear_slot()` methods on push data structs to extract the field-clearing logic:

```moonbit
fn PushReactiveData::clear_slot(self : PushReactiveData) -> Unit {
  self.compute = () => false
  self.sources = []
  self.subscribers.clear()
  self.label = None
  self.dirty = false
}

fn PushEffectData::clear_slot(self : PushEffectData) -> Unit {
  self.execute = () => ()
  self.sources = []
  self.subscribers.clear()
  self.label = None
  self.dirty = false
}
```

No new traits. The CellRef match in `dispose_reactive` / `dispose_effect` stays — these are structural operations per the modularization design.

---

## What does NOT change

- **No behavioral changes.** All 194 tests pass unchanged.
- **No new traits.** Only 2 dispose call sites — trait overhead not justified.
- **No package split.** Everything stays in the `cells` package.
- **verify.mbt validation stays inline.** Hot path, different semantics.
- **CellRef matches in dispose stay.** Structural operations need concrete variant access.

---

## Migration Strategy

### Phase 1: Extract validate_cell helpers
Add `validate_cell` and `validate_cell_soft` to `runtime.mbt`. Replace 10 call sites. Run tests.

### Phase 2: Add clear_slot methods
Add `PushReactiveData::clear_slot` and `PushEffectData::clear_slot`. Update `dispose_reactive` and `dispose_effect` to call them. Run tests.

### Phase 3: Split runtime.mbt into files
Move code blocks to `batch.mbt`, merge into `tracking.mbt`, create `introspection.mbt`. Purely mechanical. Run tests.

Each phase is independently committable and testable.

---

## Risks

| Risk | Mitigation |
|------|-----------|
| File moves may break whitebox tests that reference runtime internals | All types/methods stay in `cells` package — same visibility |
| `validate_cell` string allocation on hot path | Only allocates on abort (error path). Normal path is two comparisons. |
| Merge into `tracking.mbt` changes existing file | `ActiveQuery` struct stays at top, new methods append below |
