# API Reference

Complete reference for the public API in `incr`.

> **Recommended Pattern:** Use the `IncrDb` trait to encapsulate your `Runtime` in a database type. This makes your API cleaner and hides implementation details. See the [Helper Functions](#helper-functions) section and [API Design Guidelines](api-design-guidelines.md) for details.

## Runtime

Central coordinator for dependency tracking, revisions, and batching.

### `Runtime::new() -> Runtime`

Creates a new runtime with an empty dependency graph.

```moonbit
let rt = Runtime::new()
```

### `Runtime::batch(self, f: () -> Unit) -> Unit`

Executes `f` with batched signal updates.

Inside a batch, `Signal::set()` and `Signal::set_unconditional()` writes are deferred and committed when the outermost batch exits.

```moonbit
rt.batch(fn() {
  x.set(1)
  y.set(2)
})
```

Behavior:
- Nested batches are supported (only the outermost batch commits)
- All committed changes share one revision bump
- Revert detection applies to `Signal::set()` writes (`5 -> 0 -> 5` can result in no net change)
- Reads during a batch observe pre-batch values

### `Runtime::set_on_change(self, f: () -> Unit) -> Unit`

Registers a callback fired when the runtime records a committed change.

```moonbit
let mut count = 0
rt.set_on_change(fn() { count = count + 1 })
```

Behavior:
- Outside batch: fires immediately after each committed change
- Inside batch: fires once at batch end if at least one signal actually changed
- No fire for no-op `Signal::set()` (same value)

### `Runtime::clear_on_change(self) -> Unit`

Removes the registered change callback.

```moonbit
rt.clear_on_change()
```

---

## Signal[T]

Input cells with externally controlled values.

### `Signal::new[T](rt: Runtime, initial: T) -> Signal[T]`

Creates a signal with `Low` durability.

```moonbit
let count = Signal::new(rt, 0)
```

### `Signal::new_with_durability[T](rt: Runtime, initial: T, durability: Durability) -> Signal[T]`

Creates a signal with explicit durability.

```moonbit
let config = Signal::new_with_durability(rt, "prod", High)
```

### `Signal::get(self) -> T`

Returns the current signal value and records dependency when called inside a memo computation.

```moonbit
let value = count.get()
```

### `Signal::get_result(self) -> Result[T, CycleError]`

Always returns `Ok(value)`. Present for API symmetry with `Memo::get_result()`.

```moonbit
match count.get_result() {
  Ok(v) => println(v.to_string())
  Err(_) => () // Never happens for signals
}
```

### `Signal::set[T : Eq](self, value: T) -> Unit`

Sets a new value using equality-based no-op detection.

```moonbit
count.set(5)
count.set(5) // No-op when unchanged
```

### `Signal::set_unconditional[T](self, value: T) -> Unit`

Sets a new value without equality checking; always treated as a change when committed.

```moonbit
count.set_unconditional(5) // Forces downstream reverification
```

### `Signal::is_up_to_date(self) -> Bool`

Signals are always up-to-date (`true`).

---

## Memo[T]

Derived computations with dependency tracking and memoization.

### `Memo::new[T : Eq](rt: Runtime, compute: () -> T) -> Memo[T]`

Creates a lazily evaluated memo.

```moonbit
let doubled = Memo::new(rt, fn() { count.get() * 2 })
```

### `Memo::get[T : Eq](self) -> T`

Returns cached value, recomputing if stale. Aborts on cycle.

```moonbit
let value = doubled.get()
```

### `Memo::get_result[T : Eq](self) -> Result[T, CycleError]`

Returns cached value as `Result`, allowing graceful cycle handling.

```moonbit
match doubled.get_result() {
  Ok(v) => println(v.to_string())
  Err(CycleDetected(id)) => println("Cycle at cell " + id.to_string())
}
```

### `Memo::is_up_to_date(self) -> Bool`

Returns:
- `false` if the memo has never been computed
- `true` only when cached and verified at current revision

---

## Durability

Classification used for verification skipping:

```moonbit
enum Durability {
  Low
  Medium
  High
}
```

Ordering: `Low < Medium < High`.

Memos inherit the minimum durability of their dependencies.

---

## CycleError

Cycle detection error returned by `Memo::get_result()`.

```moonbit
pub suberror CycleError {
  CycleDetected(Int)
}
```

### `CycleError::cell_id(self) -> Int`

Returns the cell ID that triggered cycle detection.

```moonbit
match memo.get_result() {
  Ok(v) => println(v.to_string())
  Err(err) => println(err.cell_id().to_string())
}
```

---

## Introspection (Planned - Phase 2A)

> **Note:** These APIs are planned but not yet implemented. See [roadmap.md](roadmap.md) for details.

### Signal Introspection

```moonbit
pub fn[T] Signal::id(self) -> CellId
pub fn[T] Signal::durability(self) -> Durability
pub fn[T] Signal::debug(self) -> String
```

### Memo Introspection

```moonbit
pub fn[T] Memo::id(self) -> CellId
pub fn[T] Memo::dependencies(self) -> Array[CellId]
pub fn[T] Memo::changed_at(self) -> Revision
pub fn[T] Memo::verified_at(self) -> Revision
pub fn[T] Memo::debug(self) -> String
```

### Runtime Introspection

```moonbit
pub fn Runtime::cell_info(self, id : CellId) -> CellInfo

pub struct CellInfo {
  id : CellId
  kind : CellKind
  changed_at : Revision
  verified_at : Revision
  durability : Durability
  dependencies : Array[CellId]
}
```

**Use case:**

```moonbit
// Debug: why did this memo recompute?
if !expensive.is_up_to_date() {
  for dep in expensive.dependencies() {
    let info = rt.cell_info(dep)
    if info.changed_at > expensive.verified_at() {
      println("Recomputed due to cell " + dep.to_string())
    }
  }
}
```

---

## Per-Cell Callbacks (Planned - Phase 2B)

> **Note:** These APIs are planned but not yet implemented. See [roadmap.md](roadmap.md) for details.

### `Signal::on_change(self, f : (T) -> Unit) -> Unit`

Registers a callback fired when this signal's value changes.

```moonbit
let count = Signal::new(rt, 0)
count.on_change(fn(new_val) {
  println("Count: " + new_val.to_string())
})
```

### `Memo::on_change(self, f : (T) -> Unit) -> Unit`

Registers a callback fired when this memo's value changes.

```moonbit
let doubled = Memo::new(rt, fn() { count.get() * 2 })
doubled.on_change(fn(new_val) {
  update_ui(new_val)
})
```

**Behavior:**
- Fires after the cell's value changes
- Fires before `Runtime::on_change` callback
- During batch: fires at batch end for all changed cells

---

## Core Traits

### `IncrDb`

```moonbit
pub(open) trait IncrDb {
  runtime(Self) -> Runtime
}
```

### `Readable`

```moonbit
pub(open) trait Readable {
  is_up_to_date(Self) -> Bool
}
```

Implemented for both `Signal[T]` and `Memo[T]`.

### Pipeline Traits

```moonbit
pub(open) trait Sourceable {
  set_source_text(Self, String) -> Unit
  source_text(Self) -> String
}

pub(open) trait Parseable {
  parse_errors(Self) -> Array[String]
}

pub(open) trait Checkable {
  check_errors(Self) -> Array[String]
}

pub(open) trait Executable {
  run(Self) -> Array[String]
}
```

---

## Helper Functions

### `create_signal[Db : IncrDb, T](db: Db, value: T) -> Signal[T]`

Creates a low-durability signal using `db.runtime()`.

### `create_signal_durable[Db : IncrDb, T](db: Db, value: T, durability: Durability) -> Signal[T]`

Creates a signal with explicit durability using `db.runtime()`.

### `create_memo[Db : IncrDb, T : Eq](db: Db, f: () -> T) -> Memo[T]`

Creates a memo using `db.runtime()`.

### `batch[Db : IncrDb](db: Db, f: () -> Unit) -> Unit`

Runs a batch using `db.runtime()`.

---

## Type Constraints

`Eq` is required only where value comparison is needed:

- `Memo::new`, `Memo::get`, `Memo::get_result` require `T : Eq`
- `Signal::set` requires `T : Eq`
- `Signal::new`, `Signal::new_with_durability`, `Signal::get`, `Signal::get_result`, `Signal::set_unconditional` do not require `Eq`
