# Debug Trait Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Implement the `Debug` trait on `Signal[T]` and `Memo[T]` using `derive(Debug(ignore=[...]))`.

**Architecture:** Add `Debug` to `CellId`'s derive first (it is a field in both structs), then add `derive(Debug(ignore=[Runtime]))` to `Signal[T]` and `derive(Debug(ignore=[Runtime, Fn]))` to `Memo[T]`. Tests use `debug_inspect` with `#|` multiline string literals.

**Tech Stack:** MoonBit 0.8.0 — `derive(Debug(ignore=[...]))` syntax, `debug_inspect` test helper.

---

### Task 1: Write failing tests

**Files:**
- Create: `debug_test.mbt`

**Step 1: Create the test file**

```moonbit
///|
test "Signal derives Debug" {
  let rt = Runtime::new()
  let s = Signal::new(rt, 42)
  debug_inspect(
    s,
    content=(
      #|{
      #|  rt: ...,
      #|  cell_id: { runtime_id: 0, id: 0 },
      #|  value: 42,
      #|  pending_value: None,
      #|  durability: Low,
      #|}
    ),
  )
}

///|
test "Memo derives Debug before compute" {
  let rt = Runtime::new()
  let s = Signal::new(rt, 10)
  let m = Memo::new(rt, () => s.get() * 2)
  debug_inspect(
    m,
    content=(
      #|{
      #|  rt: ...,
      #|  cell_id: { runtime_id: 0, id: 1 },
      #|  compute: ...,
      #|  value: None,
      #|}
    ),
  )
}

///|
test "Memo derives Debug after compute" {
  let rt = Runtime::new()
  let s = Signal::new(rt, 10)
  let m = Memo::new(rt, () => s.get() * 2)
  let _ = m.get()
  debug_inspect(
    m,
    content=(
      #|{
      #|  rt: ...,
      #|  cell_id: { runtime_id: 0, id: 1 },
      #|  compute: ...,
      #|  value: Some(20),
      #|}
    ),
  )
}
```

**Step 2: Run to verify it fails**

```bash
moon test -p dowdiness/incr -f debug_test.mbt
```

Expected: compile error — `Signal[Int]` does not implement `Debug`.

Note: If the error message shows the actual debug output for any field, copy it into the `content=` strings above before continuing. The exact format of `{ runtime_id: 0, id: 0 }` for `CellId` should be confirmed from the error output.

---

### Task 2: Add Debug to CellId

**Files:**
- Modify: `cell.mbt:13`

**Step 1: Edit the derive on `CellId`**

Find:
```moonbit
} derive(Eq, Show)
```

Replace with:
```moonbit
} derive(Eq, Show, Debug)
```

**Step 2: Run tests — still expected to fail**

```bash
moon test -p dowdiness/incr -f debug_test.mbt
```

Expected: compile error — `Signal[Int]` still does not implement `Debug` (we haven't added it yet).

---

### Task 3: Add Debug to Signal

**Files:**
- Modify: `signal.mbt:22`

**Step 1: Edit the struct definition**

Find the closing brace of `Signal[T]` struct (line 22):
```moonbit
pub(all) struct Signal[T] {
  priv rt : Runtime
  priv cell_id : CellId
  priv mut value : T
  priv mut pending_value : T?
  priv durability : Durability
}
```

Add derive after the closing brace:
```moonbit
pub(all) struct Signal[T] {
  priv rt : Runtime
  priv cell_id : CellId
  priv mut value : T
  priv mut pending_value : T?
  priv durability : Durability
} derive(Debug(ignore=[Runtime]))
```

**Step 2: Run Signal test**

```bash
moon test -p dowdiness/incr -f debug_test.mbt -i 0
```

Expected: PASS for the Signal test, or FAIL with an actual output mismatch.

If it fails with a content mismatch, the error shows the actual output — update the `content=` string in Task 1 to match, then re-run.

---

### Task 4: Add Debug to Memo

**Files:**
- Modify: `memo.mbt:34`

**Step 1: Edit the struct definition**

Find the closing brace of `Memo[T]` struct (line 34):
```moonbit
pub(all) struct Memo[T] {
  priv rt : Runtime
  priv cell_id : CellId
  priv compute : () -> T
  priv mut value : T?
}
```

Add derive after the closing brace:
```moonbit
pub(all) struct Memo[T] {
  priv rt : Runtime
  priv cell_id : CellId
  priv compute : () -> T
  priv mut value : T?
} derive(Debug(ignore=[Runtime, Fn]))
```

**Step 2: Run all debug tests**

```bash
moon test -p dowdiness/incr -f debug_test.mbt
```

Expected: all 3 tests PASS. If any fail with content mismatches, update the expected strings to match actual output.

**Step 3: Run the full test suite**

```bash
moon test
```

Expected: all tests pass (currently 111). Zero regressions.

**Step 4: Commit**

```bash
git add cell.mbt signal.mbt memo.mbt debug_test.mbt
git commit -m "feat: implement Debug trait on Signal and Memo"
```

---

### Task 5: Update todo.md

**Files:**
- Modify: `docs/todo.md`

**Step 1: Mark the two items as done**

Find in the Introspection API section:
```markdown
- [ ] Add `Signal::debug(self) -> String` for formatted output
- [ ] Add `Memo::debug(self) -> String` for formatted output
```

Replace with:
```markdown
- [x] Add `Signal::debug(self) -> String` for formatted output
- [x] Add `Memo::debug(self) -> String` for formatted output
```

**Step 2: Commit**

```bash
git add docs/todo.md
git commit -m "docs: mark Signal and Memo Debug trait items as done"
```
