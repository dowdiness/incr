# Refactoring Expansion Design

**Date:** 2026-02-21
**Scope:** Four new items extending `refactoring-plan.md`. Same category as existing items — duplication removal, invariant hardening, correctness fixes. No new features.

---

## Item 9 — Merge identical arms in `Memo::get_result`

**Risk:** Low · **Effort:** ~10min · **File:** `memo.mbt`

### Problem

`maybe_changed_after` returns `Ok(false)` (green path) or `Ok(true)` (recomputed). Both arms in `Memo::get_result` execute identical code:

```moonbit
Ok(false) => {
  self.rt.record_dependency(self.cell_id)
  Ok(self.value.unwrap())
}
Ok(true) => {
  self.rt.record_dependency(self.cell_id)
  Ok(self.value.unwrap())
}
```

The distinction is internal to the verification algorithm. The caller only needs the value.

### Action

Replace both arms with a single wildcard arm:

```moonbit
Ok(_) => {
  self.rt.record_dependency(self.cell_id)
  Ok(self.value.unwrap())
}
```

### Verification

- `moon test` — all memo, backdating, and durability tests pass.

---

## Item 10 — Extract frame pop+propagate helper in `verify.mbt`

**Risk:** Medium · **Effort:** ~30min · **File:** `verify.mbt`

### Problem

After both `finish_frame_changed` and `finish_frame_unchanged` return a `Bool` result, the same block runs in `maybe_changed_after_derived`:

```moonbit
let _ = stack.pop()
let _ = path.pop()
if stack.length() > 0 {
  if result { stack[stack.length() - 1].any_dep_changed = true }
} else {
  final_result = result
}
```

This is duplicated verbatim in both the `any_dep_changed` branch and the "all deps checked" branch.

### Action

Extract a private helper. `final_result` must be wrapped in `Ref[Bool]` since MoonBit captures by reference:

```moonbit
fn pop_frame(
  stack : Array[VerifyFrame],
  path : Array[CellId],
  result : Bool,
  final_result : Ref[Bool],
) -> Unit {
  let _ = stack.pop()
  let _ = path.pop()
  if stack.length() > 0 {
    if result {
      stack[stack.length() - 1].any_dep_changed = true
    }
  } else {
    final_result.val = result
  }
}
```

Call from both branches in `maybe_changed_after_derived`, replacing the duplicated blocks.

### Notes

- Pop order (`stack` before updating parent) must be preserved exactly.
- The verification loop is correctness-critical — review the call sites carefully after the change.
- `Ref[Bool]` is the only structural change to `maybe_changed_after_derived`.

### Verification

- `moon test` — especially `backdating_test.mbt`, `durability_wbtest.mbt`, `cycle_test.mbt`, `verify_path_test.mbt`.

---

## Item 11 — Guard `batch_depth` underflow

**Risk:** Low · **Effort:** ~10min · **File:** `runtime.mbt`

### Problem

`Runtime::batch` decrements `batch_depth` with no lower-bound check:

```moonbit
self.batch_depth = self.batch_depth - 1
if self.batch_depth == 0 {
  self.commit_batch()
}
```

A latent imbalance bug (e.g., mismatched nesting) would silently produce negative depth, making `== 0` never fire and deferring commits indefinitely.

### Action

Add an underflow guard immediately after the decrement:

```moonbit
self.batch_depth = self.batch_depth - 1
if self.batch_depth < 0 {
  abort("batch_depth underflow: batch() nesting is unbalanced")
}
if self.batch_depth == 0 {
  self.commit_batch()
}
```

### Verification

- `moon test` — all batch tests pass. No existing test hits this path.

---

## Item 12 — Fix `CellId::hash` additive combination

**Risk:** Low · **Effort:** ~10min · **File:** `cell.mbt`

### Problem

The `Hash` impl uses addition:

```moonbit
impl Hash for CellId with hash(self) {
  self.runtime_id.hash() + self.id.hash()
}
```

Addition is commutative — `CellId{runtime_id: 1, id: 2}` produces the same hash as `CellId{runtime_id: 2, id: 1}`. This degrades HashSet performance when multiple runtimes are used concurrently.

The `hash_combine` impl (L21–24) is already correct and uses MoonBit's hasher machinery.

### Action

Rewrite `hash` to delegate to `hash_combine`:

```moonbit
impl Hash for CellId with hash(self) {
  let h = Hasher::new()
  self.hash_combine(h)
  h.finalize()
}
```

**Note:** Verify the exact `Hasher` API against `moonbitlang/core` before committing — the method names (`Hasher::new`, `h.finalize`) must match what the stdlib exposes.

### Verification

- `moon test` — HashSet-based deduplication in `ActiveQuery` still works correctly.
- `moon check` — no type errors.

---

## Execution order

Append to the existing plan's execution table. All four items are independent of each other and of the original eight.

| Order | Item | Task |
|-------|------|------|
| After original item 5 | 9 | Merge `Ok(_)` arms in `Memo::get_result` |
| After original item 3 | 11 | `batch_depth` underflow guard |
| After original item 8 | 12 | Fix `CellId::hash` |
| Last (after original item 6) | 10 | Frame pop+propagate helper in `verify.mbt` |

Item 10 goes last for the same reason item 6 does — both touch correctness-critical code paths and benefit from the full test suite being green first.
