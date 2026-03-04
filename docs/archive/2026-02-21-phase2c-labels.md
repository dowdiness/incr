# Phase 2C: Cell Labels via Optional Parameters — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add optional `label? : String` to `Signal::new` and `Memo::new`, unify `Signal::new_with_durability` into `Signal::new` via `~durability : Durability = Low`, propagate labels through `CellMeta`/`CellInfo`/`format_path`, and surface labels in `derive(Debug)` output.

**Architecture:** Labels stored in both the typed struct (`Signal[T]`/`Memo[T]`) so `derive(Debug)` picks them up automatically, and in `CellMeta` for use by `format_path` and `Runtime::cell_info()`. MoonBit's native optional parameter syntax (`label? : String`, `~durability : Durability = Low`) replaces the builder pattern entirely. `Signal::new_with_durability` and `create_signal_durable` are removed outright. No new types introduced.

**Tech Stack:** MoonBit, single package `dowdiness/incr`. Tests use `///|` prefix, `test "name" { ... }` blocks, `inspect(expr, content="expected")` and `debug_inspect(expr, content=...)` assertions. Commands: `moon check`, `moon test`, `moon test -p dowdiness/incr -f <file>`.

---

### Task 1: Add `label` to `CellMeta` — internal foundation

**Files:**
- Modify: `cell.mbt`
- Modify: `cell_wbtest.mbt`

**Step 1: Write the failing whitebox test**

Add to `cell_wbtest.mbt`:

```moonbit
///|
test "CellMeta new_input stores label" {
  let rt = Runtime::new()
  let id = rt.alloc_cell_id()
  let meta = CellMeta::new_input(id, Low, Some("my_signal"))
  inspect(meta.label, content="Some(\"my_signal\")")
}

///|
test "CellMeta new_input stores None label" {
  let rt = Runtime::new()
  let id = rt.alloc_cell_id()
  let meta = CellMeta::new_input(id, Low, None)
  inspect(meta.label, content="None")
}
```

**Step 2: Run test to verify it fails**

```bash
moon test -p dowdiness/incr -f cell_wbtest.mbt
```

Expected: compile error — `CellMeta::new_input` has no third parameter.

**Step 3: Add `label` field to `CellMeta` struct in `cell.mbt`**

In the `CellMeta` struct, add `mut label : String?` as the last field, before the closing brace. The struct becomes:

```moonbit
priv struct CellMeta {
  id : CellId
  kind : CellKind
  mut changed_at : Revision
  mut verified_at : Revision
  mut dependencies : Array[CellId]
  mut durability : Durability
  mut recompute_and_check : (() -> Result[Bool, CycleError])?
  mut commit_pending : (() -> Bool)?
  mut on_change : (() -> Unit)?
  mut in_progress : Bool
  mut label : String?
}
```

**Step 4: Update `CellMeta::new_input` to accept and store label**

```moonbit
fn CellMeta::new_input(id : CellId, durability : Durability, label : String?) -> CellMeta {
  {
    id,
    kind: Input,
    changed_at: Revision::initial(),
    verified_at: Revision::initial(),
    dependencies: [],
    durability,
    recompute_and_check: None,
    commit_pending: None,
    on_change: None,
    in_progress: false,
    label,
  }
}
```

**Step 5: Update `CellMeta::new_derived` to accept and store label**

```moonbit
fn CellMeta::new_derived(
  id : CellId,
  recompute_and_check : () -> Result[Bool, CycleError],
  label : String?,
) -> CellMeta {
  {
    id,
    kind: Derived,
    changed_at: Revision::initial(),
    verified_at: Revision::initial(),
    dependencies: [],
    durability: Low,
    recompute_and_check: Some(recompute_and_check),
    commit_pending: None,
    on_change: None,
    in_progress: false,
    label,
  }
}
```

**Step 6: Fix the two callers of the old signatures (temporary `None`)**

In `signal.mbt`, the call `CellMeta::new_input(cell_id, durability)` becomes:
```moonbit
let meta = CellMeta::new_input(cell_id, durability, None)
```

In `memo.mbt`, the call `CellMeta::new_derived(cell_id, recompute_and_check)` becomes:
```moonbit
let meta = CellMeta::new_derived(cell_id, recompute_and_check, None)
```

**Step 7: Run check**

```bash
moon check
```

Expected: no errors.

**Step 8: Run the new tests**

```bash
moon test -p dowdiness/incr -f cell_wbtest.mbt
```

Expected: PASS (3 tests including existing 2 hash tests).

**Step 9: Run full suite to confirm no regressions**

```bash
moon test
```

Expected: all tests pass.

**Step 10: Commit**

```bash
git add cell.mbt cell_wbtest.mbt signal.mbt memo.mbt
git commit -m "feat: add label field to CellMeta"
```

---

### Task 2: Expose `label` in `CellInfo`

**Files:**
- Modify: `runtime.mbt`

**Step 1: Add `label` field to `CellInfo` struct in `runtime.mbt`**

The `CellInfo` struct becomes:

```moonbit
pub(all) struct CellInfo {
  label : String?
  id : CellId
  changed_at : Revision
  verified_at : Revision
  durability : Durability
  dependencies : Array[CellId]
}
```

**Step 2: Update `Runtime::cell_info()` to populate `label`**

In the `Some(meta) =>` branch, update the `CellInfo` construction:

```moonbit
Some(meta) =>
  Some(CellInfo::{
    label: meta.label,
    id,
    changed_at: meta.changed_at,
    verified_at: meta.verified_at,
    durability: meta.durability,
    dependencies: meta.dependencies.copy(),
  })
```

**Step 3: Run check**

```bash
moon check
```

Expected: no errors.

**Step 4: Run full suite**

```bash
moon test
```

Expected: all tests pass. (Existing `runtime_introspection_test.mbt` tests don't assert on `label` yet — they still pass since they only check `id`, `durability`, `dependencies`.)

**Step 5: Commit**

```bash
git add runtime.mbt
git commit -m "feat: add label field to CellInfo"
```

---

### Task 3: Unify `Signal::new` — optional `durability` and `label`, update all callers

**Files:**
- Modify: `signal.mbt`
- Modify: `durability_wbtest.mbt`
- Modify: `signal_introspection_test.mbt`
- Modify: `runtime_introspection_test.mbt`
- Modify: `integration_test.mbt`
- Modify: `batch_wbtest.mbt`
- Modify: `debug_test.mbt`

**Step 1: Write the failing tests**

Add to `signal_introspection_test.mbt`:

```moonbit
///|
test "signal: label stored via optional param" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 42, label="answer")
  match rt.cell_info(sig.id()) {
    Some(info) => inspect(info.label, content="Some(\"answer\")")
    None => abort("expected cell info")
  }
}

///|
test "signal: durability optional param replaces new_with_durability" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 42, durability=High)
  inspect(sig.durability(), content="High")
}

///|
test "signal: no label gives None" {
  let rt = Runtime::new()
  let sig = Signal::new(rt, 0)
  match rt.cell_info(sig.id()) {
    Some(info) => inspect(info.label, content="None")
    None => abort("expected cell info")
  }
}
```

**Step 2: Run test to verify it fails**

```bash
moon test -p dowdiness/incr -f signal_introspection_test.mbt
```

Expected: compile error — `Signal::new` doesn't accept `label` or `durability` keyword args.

**Step 3: Update `Signal[T]` struct in `signal.mbt` — add `label` field**

Add `priv label : String?` as the first `priv` field so it appears first in Debug output:

```moonbit
pub(all) struct Signal[T] {
  priv label : String?
  priv rt : Runtime
  priv cell_id : CellId
  priv mut value : T
  priv mut pending_value : T?
  priv durability : Durability
} derive(Debug(ignore=[Runtime, CellId]))
```

**Step 4: Replace `Signal::new` and remove `Signal::new_with_durability` in `signal.mbt`**

Delete the current `Signal::new` (which delegates to `new_with_durability`) and the entire `Signal::new_with_durability` function. Replace both with the unified constructor:

```moonbit
///|
/// Creates a new signal with the given initial value.
///
/// # Parameters
///
/// - `rt`: The runtime that will manage this signal
/// - `initial`: The initial value of the signal
/// - `durability`: How often this signal is expected to change (default: `Low`)
/// - `label`: An optional human-readable name for debugging and cycle error output
///
/// # Returns
///
/// A new signal containing the initial value
///
/// # Example
///
/// ```moonbit nocheck
/// let count = Signal::new(rt, 0)
/// let config = Signal::new(rt, "prod", durability=High)
/// let named  = Signal::new(rt, 0, label="count")
/// ```
pub fn[T] Signal::new(
  rt : Runtime,
  initial : T,
  ~durability : Durability = Low,
  label? : String,
) -> Signal[T] {
  let cell_id = rt.alloc_cell_id()
  let meta = CellMeta::new_input(cell_id, durability, label)
  rt.register_cell(meta)
  { label, rt, cell_id, value: initial, pending_value: None, durability }
}
```

**Step 5: Update `debug_test.mbt` — add `label: None` to expected Signal Debug content**

The Signal debug test content must include the new `label` field. Update the test:

```moonbit
///|
test "Signal derives Debug" {
  let rt = Runtime::new()
  let s = Signal::new(rt, 42)
  debug_inspect(
    s,
    content=(
      #|{
      #|  label: None,
      #|  rt: ...,
      #|  cell_id: ...,
      #|  value: 42,
      #|  pending_value: None,
      #|  durability: Low,
      #|}
    ),
  )
}
```

**Step 6: Update all callers of `Signal::new_with_durability` in test files**

In `durability_wbtest.mbt`, replace every `Signal::new_with_durability(rt, v, Dur)` with `Signal::new(rt, v, durability=Dur)`:
- Line 4: `Signal::new_with_durability(rt, "debug", High)` → `Signal::new(rt, "debug", durability=High)`
- Line 35: `Signal::new_with_durability(rt, 1, High)` → `Signal::new(rt, 1, durability=High)`
- Line 47: `Signal::new_with_durability(rt, 10, High)` → `Signal::new(rt, 10, durability=High)`
- Line 48: `Signal::new_with_durability(rt, 20, High)` → `Signal::new(rt, 20, durability=High)`
- Line 58: `Signal::new_with_durability(rt, 5, Medium)` → `Signal::new(rt, 5, durability=Medium)`
- Line 70: `Signal::new_with_durability(rt, 100, High)` → `Signal::new(rt, 100, durability=High)`

In `signal_introspection_test.mbt` line 13:
- `Signal::new_with_durability(rt, 2, High)` → `Signal::new(rt, 2, durability=High)`

In `runtime_introspection_test.mbt` line 4:
- `Signal::new_with_durability(rt, 42, High)` → `Signal::new(rt, 42, durability=High)`

In `integration_test.mbt` line 149:
- `Signal::new_with_durability(rt, 10, High)` → `Signal::new(rt, 10, durability=High)`

In `batch_wbtest.mbt` line 52:
- `Signal::new_with_durability(rt, 100, High)` → `Signal::new(rt, 100, durability=High)`

**Step 7: Run check**

```bash
moon check
```

Expected: no errors.

**Step 8: Run the new tests**

```bash
moon test -p dowdiness/incr -f signal_introspection_test.mbt
```

Expected: PASS.

**Step 9: Run full suite**

```bash
moon test
```

Expected: all tests pass.

**Step 10: Commit**

```bash
git add signal.mbt durability_wbtest.mbt signal_introspection_test.mbt \
        runtime_introspection_test.mbt integration_test.mbt batch_wbtest.mbt \
        debug_test.mbt
git commit -m "feat: unify Signal::new with optional durability and label params"
```

---

### Task 4: Add `label` to `Memo::new`, update debug tests

**Files:**
- Modify: `memo.mbt`
- Modify: `memo_introspection_test.mbt`
- Modify: `debug_test.mbt`

**Step 1: Write failing tests**

Add to `memo_introspection_test.mbt`:

```moonbit
///|
test "memo: label stored via optional param" {
  let rt = Runtime::new()
  let x = Signal::new(rt, 1)
  let m = Memo::new(rt, () => x.get() * 2, label="doubled")
  let _ = m.get()
  match rt.cell_info(m.id()) {
    Some(info) => inspect(info.label, content="Some(\"doubled\")")
    None => abort("expected cell info")
  }
}

///|
test "memo: no label gives None" {
  let rt = Runtime::new()
  let x = Signal::new(rt, 1)
  let m = Memo::new(rt, () => x.get() * 2)
  let _ = m.get()
  match rt.cell_info(m.id()) {
    Some(info) => inspect(info.label, content="None")
    None => abort("expected cell info")
  }
}
```

**Step 2: Run test to verify it fails**

```bash
moon test -p dowdiness/incr -f memo_introspection_test.mbt
```

Expected: compile error — `Memo::new` doesn't accept `label`.

**Step 3: Update `Memo[T]` struct in `memo.mbt` — add `label` field**

Add `priv label : String?` as the first `priv` field:

```moonbit
pub(all) struct Memo[T] {
  priv label : String?
  priv rt : Runtime
  priv cell_id : CellId
  priv compute : () -> T
  priv mut value : T?
} derive(Debug(ignore=[Runtime, Fn, CellId]))
```

**Step 4: Update `Memo::new` in `memo.mbt`**

```moonbit
pub fn[T : Eq] Memo::new(rt : Runtime, compute : () -> T, label? : String) -> Memo[T] {
  let cell_id = rt.alloc_cell_id()
  let memo : Memo[T] = { label, rt, cell_id, compute, value: None }
  let recompute_and_check : () -> Result[Bool, CycleError] = () => memo.recompute_inner()
  let meta = CellMeta::new_derived(cell_id, recompute_and_check, label)
  rt.register_cell(meta)
  memo
}
```

**Step 5: Update `debug_test.mbt` — add `label: None` to Memo Debug content**

```moonbit
///|
test "Memo derives Debug before compute" {
  let rt = Runtime::new()
  let s = Signal::new(rt, 10)
  let m = Memo::new(rt, () => s.get() * 2)
  debug_inspect(
    m,
    content=(
      #|{ label: None, rt: ..., cell_id: ..., compute: <function: ...>, value: None }
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
      #|{ label: None, rt: ..., cell_id: ..., compute: <function: ...>, value: Some(20) }
    ),
  )
}
```

**Step 6: Run check**

```bash
moon check
```

Expected: no errors.

**Step 7: Run the new tests**

```bash
moon test -p dowdiness/incr -f memo_introspection_test.mbt
```

Expected: PASS.

**Step 8: Run full suite**

```bash
moon test
```

Expected: all tests pass.

**Step 9: Commit**

```bash
git add memo.mbt memo_introspection_test.mbt debug_test.mbt
git commit -m "feat: add optional label param to Memo::new"
```

---

### Task 5: Update `format_cell` to use labels in cycle error output

**Files:**
- Modify: `cycle.mbt`
- Modify: `cycle_path_test.mbt`

**Step 1: Write failing test**

Add to `cycle_path_test.mbt`:

```moonbit
///|
test "format_path uses label when available" {
  let rt = Runtime::new()
  let memo_ref : Ref[Memo[Int]?] = { val: None }
  let memo = Memo::new(rt, () => {
    match memo_ref.val {
      Some(m) => m.get_result().unwrap_or(0) + 1
      None => 0
    }
  }, label="self_ref")
  memo_ref.val = Some(memo)
  match memo.get_result() {
    Err(e) => {
      let msg = e.format_path(rt)
      inspect(msg.contains("self_ref"), content="true")
    }
    Ok(_) => abort("expected cycle")
  }
}
```

**Step 2: Run test to verify it fails**

```bash
moon test -p dowdiness/incr -f cycle_path_test.mbt
```

Expected: FAIL — the new test runs but `format_path` still returns `Cell[N]` not `self_ref`.

**Step 3: Update `format_cell` in `cycle.mbt`**

Replace the current `format_cell` function (remove the `_rt` prefix — the parameter is now used):

```moonbit
///|
/// Helper function to format a single cell ID.
///
/// Returns the cell's label if one was set, otherwise "Cell[N]" where N is
/// the cell's ID number.
fn format_cell(rt : Runtime, cell_id : CellId) -> String {
  match rt.cell_info(cell_id) {
    Some({ label: Some(l), .. }) => l
    _ => "Cell[" + cell_id.id.to_string() + "]"
  }
}
```

**Step 4: Run check**

```bash
moon check
```

Expected: no errors.

**Step 5: Run the new test**

```bash
moon test -p dowdiness/incr -f cycle_path_test.mbt
```

Expected: PASS.

**Step 6: Run full suite**

```bash
moon test
```

Expected: all tests pass.

**Step 7: Commit**

```bash
git add cycle.mbt cycle_path_test.mbt
git commit -m "feat: use cell labels in format_path cycle error output"
```

---

### Task 6: Unify `traits.mbt` helpers — add `label`, remove `create_signal_durable`

**Files:**
- Modify: `traits.mbt`
- Modify: `traits_test.mbt`

**Step 1: Write failing tests**

Add to `traits_test.mbt`:

```moonbit
///|
test "trait: create_signal with label" {
  let db = TestDb::new()
  let sig = create_signal(db, 42, label="count")
  match db.rt.cell_info(sig.id()) {
    Some(info) => inspect(info.label, content="Some(\"count\")")
    None => abort("expected cell info")
  }
}

///|
test "trait: create_signal with durability" {
  let db = TestDb::new()
  let sig = create_signal(db, 42, durability=High)
  inspect(sig.durability(), content="High")
}

///|
test "trait: create_memo with label" {
  let db = TestDb::new()
  let x = create_signal(db, 1)
  let m = create_memo(db, () => x.get() * 2, label="doubled")
  let _ = m.get()
  match db.rt.cell_info(m.id()) {
    Some(info) => inspect(info.label, content="Some(\"doubled\")")
    None => abort("expected cell info")
  }
}
```

**Step 2: Run test to verify it fails**

```bash
moon test -p dowdiness/incr -f traits_test.mbt
```

Expected: compile error — `create_signal` and `create_memo` don't accept `label` or `durability` keyword args.

**Step 3: Update `traits.mbt` — replace `create_signal` and remove `create_signal_durable`**

Replace the current `create_signal` and delete `create_signal_durable` entirely. The new unified version:

```moonbit
///|
/// Creates a new signal using the database's runtime.
///
/// # Parameters
///
/// - `db`: Any type implementing `Database`
/// - `value`: The initial value of the signal
/// - `durability`: How often this signal is expected to change (default: `Low`)
/// - `label`: An optional human-readable name for debugging
pub fn[Db : Database, T] create_signal(
  db : Db,
  value : T,
  ~durability : Durability = Low,
  label? : String,
) -> Signal[T] {
  Signal::new(db.runtime(), value, ~durability, label?)
}
```

**Step 4: Update `create_memo` in `traits.mbt`**

```moonbit
///|
/// Creates a new memo using the database's runtime.
///
/// # Parameters
///
/// - `db`: Any type implementing `Database`
/// - `f`: The compute function for the memo
/// - `label`: An optional human-readable name for debugging
pub fn[Db : Database, T : Eq] create_memo(
  db : Db,
  f : () -> T,
  label? : String,
) -> Memo[T] {
  Memo::new(db.runtime(), f, label?)
}
```

**Step 5: Update the existing `create_signal_durable` test in `traits_test.mbt`**

Replace the removed `create_signal_durable` test:

```moonbit
///|
test "trait: create_signal_durable via Database" {
  let db = TestDb::new()
  let sig = create_signal(db, "hello", durability=High)
  inspect(sig.get(), content="hello")
  inspect(sig.durability(), content="High")
}
```

**Step 6: Run check**

```bash
moon check
```

Expected: no errors.

**Step 7: Run the new tests**

```bash
moon test -p dowdiness/incr -f traits_test.mbt
```

Expected: PASS.

**Step 8: Run full suite**

```bash
moon test
```

Expected: all tests pass.

**Step 9: Commit**

```bash
git add traits.mbt traits_test.mbt
git commit -m "feat: unify create_signal/create_signal_durable, add label to create_memo"
```

---

### Task 7: Final verification and docs update

**Files:**
- Modify: `docs/todo.md`

**Step 1: Run full suite one final time**

```bash
moon test
```

Expected: all tests pass with no failures.

**Step 2: Verify no remaining references to removed APIs**

```bash
grep -rn "new_with_durability\|create_signal_durable" --include="*.mbt" .
```

Expected: no output. If any remain, fix them before continuing.

**Step 3: Update `docs/todo.md` — mark Phase 2C items**

Under `### Builder Pattern (Phase 2C - Medium Priority)`, replace the unchecked items with:

```markdown
- [x] Unified `Signal::new` with `~durability : Durability = Low` (replaces `Signal::new_with_durability`)
- [x] Added `label? : String` to `Signal::new` and `Memo::new`
- [x] Added `label? : String` to `create_signal` and `create_memo`
- [x] Labels propagate through `CellMeta`, `CellInfo`, `format_path`
- [x] Labels surface in `derive(Debug)` output for `Signal` and `Memo`
- [ ] `SignalBuilder[T]` — skipped: optional params are sufficient in MoonBit
- [ ] `MemoBuilder[T]` — skipped: optional params are sufficient in MoonBit
```

Under `### Ergonomics (Phase 2C - Medium Priority)`:

```markdown
- [ ] Add `Runtime::with_on_change(self, f) -> Runtime` for method chaining
- [x] `create_signal` now accepts `label?` and `~durability` (replaces `create_signal_durable`)
- [ ] Explore RAII `BatchGuard` if MoonBit adds destructors
```

**Step 4: Commit**

```bash
git add docs/todo.md
git commit -m "docs: mark Phase 2C label and optional-param items as done"
```
