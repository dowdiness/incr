# Runtime::new on_change Optional Parameter Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add `on_change?` as an optional parameter to `Runtime::new`, consistent with Phase 2C patterns used in `Signal::new` and `Memo::new`.

**Architecture:** Modify `Runtime::new` to accept an optional `(() -> Unit)` callback, assign it directly to the `on_change` field. No new types, no new methods. Mark the `with_on_change` todo item as skipped.

**Tech Stack:** MoonBit. Run tests with `moon test`. Type-check with `moon check`.

---

### Task 1: Write the failing test

**Files:**
- Modify: `on_change_test.mbt`

**Step 1: Add the test at the end of `on_change_test.mbt`**

Append this block (note the `///|` prefix — required for every MoonBit test):

```moonbit
///|
test "on_change optional param fires on signal set" {
  let mut count = 0
  let rt = Runtime::new(on_change=() => count = count + 1)
  let s = Signal::new(rt, 0)
  s.set(1)
  inspect(count, content="1")
}
```

**Step 2: Run the test to verify it fails**

```bash
moon test -p dowdiness/incr -f on_change_test.mbt
```

Expected: compile error — `Runtime::new` does not accept `on_change` argument.

---

### Task 2: Implement `on_change?` in `Runtime::new`

**Files:**
- Modify: `runtime.mbt`

**Step 1: Update the `Runtime::new` signature and body**

Current signature (line 48):
```moonbit
pub fn Runtime::new() -> Runtime {
```

New signature:
```moonbit
pub fn Runtime::new(on_change? : (() -> Unit)) -> Runtime {
```

Current body initialiser (line 64):
```moonbit
    on_change: None,
```

New body initialiser:
```moonbit
    on_change,
```

The full function after the change:

```moonbit
pub fn Runtime::new(on_change? : (() -> Unit)) -> Runtime {
  let id = next_runtime_id.val
  next_runtime_id.val = next_runtime_id.val + 1
  {
    runtime_id: id,
    current_revision: Revision::initial(),
    cells: [],
    next_cell_id: 0,
    tracking_stack: [],
    durability_last_changed: FixedArray::make(
      DURABILITY_COUNT,
      Revision::initial(),
    ),
    batch_depth: 0,
    batch_pending_signals: [],
    batch_max_durability: Low,
    on_change,
  }
}
```

**Step 2: Type-check**

```bash
moon check
```

Expected: no errors.

---

### Task 3: Update the doc comment

**Files:**
- Modify: `runtime.mbt` (the `Runtime::new` doc comment, lines 39–47)

Add the `on_change?` parameter to the Parameters section and extend the example. Replace the existing doc comment with:

```moonbit
///|
/// Creates a new runtime with an empty dependency graph.
///
/// This is the entry point for using the incremental computation framework.
/// Create one runtime, then create signals and memos associated with it.
///
/// # Parameters
///
/// - `on_change`: Optional callback invoked whenever any signal changes
///   (or at the end of a batch if values actually changed). Equivalent
///   to calling `Runtime::set_on_change` immediately after construction.
///
/// # Returns
///
/// A new runtime ready to manage signals and memos
///
/// # Example
///
/// ```moonbit nocheck
/// let rt = Runtime::new()
///
/// let rt = Runtime::new(on_change=() => rerender())
///
/// let x = Signal::new(rt, 10)
///
/// let doubled = Memo::new(rt, () => x.get() * 2)
/// ```
```

**Step 2: Type-check**

```bash
moon check
```

Expected: no errors.

---

### Task 4: Run all tests

```bash
moon test
```

Expected: all tests pass (128+ tests). The new test from Task 1 should now be included and passing.

---

### Task 5: Update `docs/todo.md`

**Files:**
- Modify: `docs/todo.md`

Find this line:
```markdown
- [ ] Add `Runtime::with_on_change(self, f) -> Runtime` for method chaining
```

Replace with:
```markdown
- ~~Add `Runtime::with_on_change(self, f) -> Runtime` for method chaining~~ — skipped (replaced by `on_change?` optional param in `Runtime::new`)
```

---

### Task 6: Commit

```bash
git add runtime.mbt on_change_test.mbt docs/todo.md
git commit -m "feat: add on_change optional param to Runtime::new"
```
