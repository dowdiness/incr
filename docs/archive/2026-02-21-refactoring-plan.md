# Refactoring Plan

> **Status: ✅ Complete.** All 8 items implemented as of 2026-02-23. 162 tests passing.

Internal quality improvements for existing code. No new features — all items tighten invariants, reduce duplication, or improve consistency. All tests pass at time of writing; run `moon test` after every change.

## 1. Consolidate duplicated revision-bump logic

**Risk:** Medium · **Effort:** ~1h

The "advance revision + update `durability_last_changed`" pattern is duplicated:

- `Runtime::bump_revision` (`runtime.mbt` L269–274)
- `Runtime::commit_batch` phase 2 (`runtime.mbt` L351–355)

Similarly, "mark input changed" (`meta.changed_at = rev; meta.verified_at = rev`) is duplicated between `Signal::set_unconditional` and `commit_batch`'s sweep loop.

### Action

1. Extract `fn Runtime::advance_revision(self, durability : Durability)` that increments `current_revision` and updates `durability_last_changed[0..=dur_idx]`.
2. Extract `fn Runtime::mark_input_changed(self, id : CellId)` that sets both `changed_at` and `verified_at` to `current_revision`.
3. Call these from `bump_revision` (non-batch path), `commit_batch`, and `set_unconditional`.

### Notes

- `advance_revision` must update `durability_last_changed[0..=dur_idx]` exactly as both callers currently do — verify the slice range matches. A focused test on durability shortcut behavior after the refactor is recommended.

### Verification

- `moon test` — all tests pass
- Pay special attention to batch revert detection, callback ordering, and durability shortcut tests

## 2. Replace silent fallbacks with assertions

**Risk:** Low · **Effort:** ~30min

Internal invariants are silently swallowed instead of failing loudly:

- `finish_frame_changed` (`verify.mbt`): `recompute_and_check` being `None` for a `Derived` cell returns `Ok(true)` — should be impossible
- `commit_batch` (`runtime.mbt`): `commit_pending` being `None` for a cell in `batch_pending_signals` is silently ignored

### Action

1. In `finish_frame_changed`, replace `None => Ok(true)` with `None => abort("Derived cell missing recompute_and_check")`. Note: `CellMeta::new_derived` already enforces `recompute_and_check = Some(...)` at construction, so this abort is defense-in-depth against internal corruption, not a reachable error path.
2. In `commit_batch`, add an assertion or abort when `commit_pending` is `None` for a batched signal.

### Verification

- `moon test` — no existing test should hit these paths (they are invariant violations)
- Add targeted `*_wbtest.mbt` panic tests (name prefix `test "panic ..."`) that intentionally corrupt internal state via white-box access, then assert aborts:
  - For `finish_frame_changed`: create a memo, fetch its `CellMeta` via `rt.get_cell(memo.id())`, set `recompute_and_check = None`, then trigger verification.
  - For `commit_batch`: manually enqueue a signal `CellId` into `batch_pending_signals` with `commit_pending = None`, then call `commit_batch()`.

## 3. Add runtime ownership check in `get_cell`

**Risk:** Low · **Effort:** ~15min

`Runtime::cell_info` validates `id.runtime_id != self.runtime_id` but the internal `Runtime::get_cell` does not. A cross-runtime bug would produce a confusing "Cell not found" abort instead of a clear message.

### Action

Add both guards at the top of `Runtime::get_cell`:

1. `if id.runtime_id != self.runtime_id { abort("Cell belongs to a different Runtime") }` — runtime ownership
2. `if id.id < 0 { abort("Invalid cell id: " + id.id.to_string()) }` — negative index guard (matches the check already in `cell_info`)

### Verification

- `moon test` — all tests pass (no cross-runtime or negative-id usage exists)

## 4. Simplify `Signal::get` / `get_result` relationship

**Risk:** Low · **Effort:** ~30min

Both `Signal::get` and `Signal::get_result` independently call `record_dependency`. Since `Signal::get()` has no error path, `get_result` can safely delegate to `get` without semantic change:

### Action

Replace `Signal::get_result` body with:

```moonbit
pub fn[T] Signal::get_result(self : Signal[T]) -> Result[T, CycleError] {
  Ok(self.get())
}
```

### Verification

- `moon test` — all tests pass

## 5. Improve `Memo::get` abort message

**Risk:** Low · **Effort:** ~10min

`Memo::get` manually builds an abort string. The existing `CycleError::format_path` produces better output.

### Action

Replace the `Err` branch in `Memo::get`:

```moonbit
Err(e) => abort(e.format_path(self.rt))
```

### Notes

- Cycle tests use `get_result`, not `get`, so they won't exercise this abort path directly. Consider adding a comment in code noting this gap.

### Verification

- `moon test` — cycle tests still pass (they use `get_result`, not `get`)

## 6. Centralize cycle-path construction

**Risk:** Medium · **Effort:** ~1h

Cycle paths are built in two places with similar but not identical logic:

- `Memo::force_recompute` (`memo.mbt`): collects from `tracking_stack`
- `try_start_verify` (`verify.mbt`): collects from the verification `path` array

### Action

Centralize path building with a decoupled API:

1. Add `fn CycleError::from_path(path : Array[CellId], closing_id : CellId) -> CycleError` in `cycle.mbt` (copies `path`, appends `closing_id`).
2. Add a small runtime-side collector helper (e.g., `Runtime::collect_tracking_path() -> Array[CellId]`) that extracts cell IDs from `tracking_stack`.

Update `Memo::force_recompute` and `try_start_verify` to call `CycleError::from_path(...)` using their respective path sources.

### Notes

- `CycleError::from_path` should be path-source agnostic; keep runtime internals (`tracking_stack`) out of `cycle.mbt` to avoid unnecessary coupling.
- Verify the path-closing logic is identical to both callers' current behavior — it's easy to introduce an off-by-one difference in the cycle boundary.

### Verification

- `moon test` — especially `cycle_test.mbt`, `cycle_path_test.mbt`, `verify_path_test.mbt`

## 7. Demote unused pipeline traits

**Risk:** Low (API breaking) · **Effort:** ~30min

`Sourceable`, `Parseable`, `Checkable`, `Executable` in `traits.mbt` have:

- No production usage — implementations exist only in `traits_test.mbt` as demo/test fixtures (`CalcPipeline`)
- No internal usage by the library itself

They are premature public API surface area that is only exercised by test code.

### Action

1. Move them to a separate `pipeline_traits.mbt` file.
2. Add doc comments marking them as experimental/unstable.
3. Optionally reduce visibility if comfortable with the breaking change at this stage.

### Notes

- Moving traits to a different file should not affect MoonBit's module identity (all `.mbt` files in the root belong to the same package), but reducing visibility (`pub(open)` → non-public) **is** a breaking change for any downstream user importing these traits. Since there are no known consumers and the library is pre-1.0, this is the cheapest time to do it.
- If visibility is reduced, record it as an intentional API break in release notes/changelog and align versioning policy for the release.

### Verification

- `moon check` — compiles cleanly
- `moon info` — regenerate `pkg.generated.mbti` and confirm the delta is intentional

## 8. Use idiomatic loop patterns

**Risk:** Low · **Effort:** ~30min

Several loops use C-style indexing where MoonBit supports more idiomatic forms:

```moonbit
// Before
for i = 0; i < deps.length(); i = i + 1 {
  let dep_cell = rt.get_cell(deps[i])
  ...
}

// After (if MoonBit version supports it)
for dep_id in deps {
  let dep_cell = rt.get_cell(dep_id)
  ...
}
```

### Action

1. Check which loop sites can use `for .. in` without changing semantics (some loops in `verify.mbt` mutate the index or access `stack[top]` by position — those must stay C-style).
2. Convert safe sites in `memo.mbt` (`compute_durability`), `runtime.mbt` (`commit_batch` callback collection), and `cycle.mbt` (`format_path`).

### Verification

- `moon test` — all tests pass

## Execution order

All items are independent (no cross-dependencies). Recommended sequence goes from highest impact to lowest, saving the riskiest correctness-sensitive change for last:

| Order | Item | Task |
|-------|------|------|
| 1st | 1 | Consolidate revision-bump logic |
| 2nd | 2 | Replace silent fallbacks with assertions |
| 3rd | 4 | Simplify `Signal::get_result` |
| 4th | 5 | Improve `Memo::get` abort message |
| 5th | 3 | Add runtime ownership check in `get_cell` |
| 6th | 8 | Idiomatic loops |
| 7th | 7 | Demote pipeline traits |
| 8th | 6 | Centralize cycle-path construction |

## Out of scope

These are tracked elsewhere and are **not** part of this refactoring:

- Builder pattern (roadmap Phase 2C)
- Subscriber/reverse links (roadmap Phase 4)
- Push-pull hybrid invalidation (roadmap Phase 4)
- Incremental dependency diffing (todo.md)
- `CellMeta` enum redesign (`Input | Derived` variants) — higher payoff when multiple derived node types exist; note that Items 2 and 3 (assertions) become partially redundant once `CellMeta` is split into `Input | Derived` variants, since the type system would enforce those invariants directly
