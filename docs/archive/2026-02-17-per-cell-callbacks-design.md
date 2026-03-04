# Per-Cell Callbacks Design

**Date:** 2026-02-17
**Status:** Approved

## Overview

Add per-cell `on_change` callbacks to `Signal[T]` and `Memo[T]`. Each cell can
register one typed callback `(T) -> Unit` that fires whenever that cell's value
actually changes. Per-cell callbacks fire before the global
`Runtime::fire_on_change()`.

`incr` remains a pull-based incremental computation library. Memo callbacks
fire lazily — only during `Memo::get()` when recomputation detects a value
change. There is no eager re-evaluation of memos. Reactive programming
patterns are out of scope and belong in a plugin or opt-in layer on top.

## Data Model

`CellMeta` (`cell.mbt`) gets one new field:

```moonbit
mut on_change : (() -> Unit)?
```

Initialized to `None` in both `CellMeta::new_input` and
`CellMeta::new_derived`. The callback is type-erased to `() -> Unit`
internally, consistent with the existing `recompute_and_check` and
`commit_pending` closure fields.

## API Surface

### Signal (`signal.mbt`)

```moonbit
pub fn[T] Signal::on_change(self : Signal[T], f : (T) -> Unit) -> Unit
pub fn[T] Signal::clear_on_change(self : Signal[T]) -> Unit
```

`on_change` type-erases the callback by capturing `self.value`:

```moonbit
pub fn[T] Signal::on_change(self : Signal[T], f : (T) -> Unit) -> Unit {
  let cell = self.rt.get_cell(self.cell_id)
  cell.on_change = Some(() => f(self.value))
}
```

`clear_on_change` sets the field to `None`:

```moonbit
pub fn[T] Signal::clear_on_change(self : Signal[T]) -> Unit {
  let cell = self.rt.get_cell(self.cell_id)
  cell.on_change = None
}
```

### Memo (`memo.mbt`)

```moonbit
pub fn[T] Memo::on_change(self : Memo[T], f : (T) -> Unit) -> Unit
pub fn[T] Memo::clear_on_change(self : Memo[T]) -> Unit
```

`on_change` captures `self.value` at call time and unwraps safely:

```moonbit
pub fn[T] Memo::on_change(self : Memo[T], f : (T) -> Unit) -> Unit {
  let cell = self.rt.get_cell(self.cell_id)
  cell.on_change = Some(() => {
    match self.value {
      Some(v) => f(v)
      None => ()
    }
  })
}
```

## Firing Logic

### Signal callbacks

**Outside batch** — in `Signal::set_unconditional`, after bumping the revision
and updating `changed_at`/`verified_at`, fire the per-cell callback then the
global callback:

```moonbit
match meta.on_change {
  Some(f) => f()
  None => ()
}
self.rt.fire_on_change()
```

**Inside batch** — in `Runtime::commit_batch`, after the revision sweep over
`changed_ids`, collect all `on_change` closures into a local array, raise
`batch_depth` as a re-entrancy guard, invoke them, then lower `batch_depth`,
commit any signals queued during callbacks, and finally call `fire_on_change()`
once:

```moonbit
let callbacks : Array[() -> Unit] = []
for i = 0; i < changed_ids.length(); i = i + 1 {
  let meta = self.get_cell(changed_ids[i])
  match meta.on_change {
    Some(f) => callbacks.push(f)
    None => ()
  }
}
self.batch_max_durability = Low
self.batch_depth = self.batch_depth + 1
for i = 0; i < callbacks.length(); i = i + 1 {
  callbacks[i]()
}
self.batch_depth = self.batch_depth - 1
if self.batch_pending_signals.length() > 0 {
  self.commit_batch()
}
self.fire_on_change()
```

### Memo callbacks

In `Memo::recompute_inner`, after `force_recompute` completes, if
`changed_at` advanced (value actually changed), fire the per-cell callback:

```moonbit
let changed = cell.changed_at != old_changed_at
if changed {
  match cell.on_change {
    Some(f) => f()
    None => ()
  }
}
Ok(changed)
```

### Firing order guarantee

Per-cell callback always fires **before** `Runtime::fire_on_change()`. For
batches with multiple changed signals, per-cell callbacks fire in the order
signals were registered in the batch (`batch_pending_signals` order).

## Tests (`callback_test.mbt`)

1. **Signal callback fires on value change** — set signal, verify callback called with new value
2. **Signal callback does not fire when value unchanged** — same-value set, verify callback not called
3. **Memo callback fires on `get()` when value changed** — change upstream signal, call `memo.get()`, verify callback fired
4. **Memo callback does not fire when value backdated** — signal changes but memo recomputes to same value, verify callback not called
5. **Per-cell callback fires before global `on_change`** — verify ordering with both registered
6. **`clear_on_change` removes Signal callback** — register, set signal, clear, set again, verify callback fired exactly once
7. **Batch: per-cell callbacks fire once per changed signal at batch end** — two signals with callbacks in batch, verify each fires exactly once
8. **`clear_on_change` removes Memo callback** — register Memo callback, call `get()` to prime, clear, mutate upstream signal, call `get()` again, verify callback not invoked after clear
9. **Batch re-entrancy: callback calling `set` is handled correctly** — s1's on_change calls `s2.set`; after batch on s1, verify both s1 and s2 callbacks fired exactly once

## Files Changed

| File | Change |
|------|--------|
| `cell.mbt` | Add `mut on_change : (() -> Unit)?` to `CellMeta`, initialize in `new_input` and `new_derived` |
| `signal.mbt` | Add `Signal::on_change` and `Signal::clear_on_change`; fire in `set_unconditional` |
| `memo.mbt` | Add `Memo::on_change` and `Memo::clear_on_change`; fire in `recompute_inner` |
| `runtime.mbt` | Fire per-cell callbacks in `commit_batch` before global `fire_on_change` |
| `callback_test.mbt` | New file with 9 tests |
| `docs/todo.md` | Mark Phase 2B items as done |
