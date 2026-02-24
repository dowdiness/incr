# API Reference

Complete reference for the public API in `incr`.

> **Recommended Pattern:** Use the `IncrDb` trait to encapsulate your `Runtime` in a database type. This makes your API cleaner and hides implementation details. See the [Helper Functions](#helper-functions) section and [API Design Guidelines](api-design-guidelines.md) for details.

## Runtime

Central coordinator for dependency tracking, revisions, and batching.

### `Runtime::new(on_change? : () -> Unit) -> Runtime`

Creates a new runtime with an empty dependency graph. The optional `on_change` callback is equivalent to calling `Runtime::set_on_change` immediately after construction.

```moonbit
let rt = Runtime()
let rt = Runtime(on_change=() => rerender())
```

### `Runtime::batch(self, f: () -> Unit) -> Unit`

Executes `f` with batched signal updates.

Inside a batch, `Signal::set()` and `Signal::set_unconditional()` writes are deferred and committed when the outermost batch exits.

```moonbit
rt.batch(() => {
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
rt.set_on_change(() => { count = count + 1 })
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

### `Signal::new[T](rt: Runtime, initial: T, durability? : Durability, label? : String) -> Signal[T]`

Creates a signal. Both `durability` (default `Low`) and `label` are optional.

```moonbit
let count = Signal(rt, 0)                                    // defaults
let config = Signal(rt, "prod", durability=High, label="config")  // explicit
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

## TrackedCell[T]

A named, field-level input cell. `TrackedCell[T]` wraps a `Signal[T]` and provides an identical API; it is intended for use as a field in a tracked struct where you want each field to be tracked independently.

### `TrackedCell::new[T](rt: Runtime, initial: T, durability?: Durability, label?: String) -> TrackedCell[T]`

Creates a tracked cell. Both `durability` (default `Low`) and `label` are optional.

```moonbit
let path    = TrackedCell(rt, "/src/main.mbt", label="SourceFile.path")
let version = TrackedCell(rt, 0, durability=High, label="SourceFile.version")
```

### `TrackedCell::get(self) -> T`

Returns the current value and records a dependency when called inside a memo computation.

```moonbit
let value = path.get()
```

### `TrackedCell::get_result(self) -> Result[T, CycleError]`

Always returns `Ok(value)`. Present for API symmetry with `Memo::get_result()`.

### `TrackedCell::set[T : Eq](self, value: T) -> Unit`

Sets a new value with same-value optimization (no-op when value is unchanged).

```moonbit
path.set("/src/lib.mbt")
path.set("/src/lib.mbt") // No-op
```

### `TrackedCell::set_unconditional[T](self, value: T) -> Unit`

Sets a new value without equality checking; always treated as a change.

### `TrackedCell::id(self) -> CellId`

Returns the unique identifier for this cell. Use with `Runtime::cell_info()` or when implementing `Trackable`.

```moonbit
let id = path.id()
```

### `TrackedCell::durability(self) -> Durability`

Returns the durability level set at construction time.

### `TrackedCell::on_change(self, f: (T) -> Unit) -> Unit`

Registers a callback fired when this cell's value changes. Replaces any previously registered callback.

### `TrackedCell::clear_on_change(self) -> Unit`

Removes the registered `on_change` callback.

### `TrackedCell::is_up_to_date(self) -> Bool`

Always `true`. TrackedCells are input cells with directly-set values.

### `TrackedCell::as_signal(self) -> Signal[T]`

Returns the underlying `Signal[T]` for interop with APIs that expect a plain signal.

```moonbit
let sig = path.as_signal()
let memo = Memo(rt, () => sig.get().length())
```

---

## Memo[T]

Derived computations with dependency tracking and memoization.

### `Memo::new[T : Eq](rt: Runtime, compute: () -> T, label? : String) -> Memo[T]`

Creates a lazily evaluated memo. The optional `label` names the memo for debug output and cycle error messages.

```moonbit
let doubled = Memo(rt, () => count.get() * 2)
let tax = Memo(rt, () => price.get() * 0.1, label="tax")
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
  Err(CycleDetected(cell, path)) => println("Cycle: " + cell.to_string())
}
```

### `Memo::is_up_to_date(self) -> Bool`

Returns:
- `false` if the memo has never been computed
- `true` only when cached and verified at current revision

---

## MemoMap[K, V]

Keyed memoization map with one lazily-created `Memo[V]` per key.

### `MemoMap::new[K, V](rt: Runtime, compute: (K) -> V, label? : String) -> MemoMap[K, V]`

Creates an empty memo map. No per-key memo is allocated until first read of that key.

```moonbit
let by_id = MemoMap::new(rt, (id : Int) => id * 10)
let named = MemoMap::new(rt, (id : Int) => id * 10, label="by_id")
```

### `MemoMap::get[K : Hash + Eq, V : Eq](self, key: K) -> V`

Returns the value for `key`, creating and caching that key's memo on first access.

### `MemoMap::get_result[K : Hash + Eq, V : Eq](self, key: K) -> Result[V, CycleError]`

Result-returning variant of `get`, matching `Memo::get_result`.

### `MemoMap::contains[K : Hash + Eq, V](self, key: K) -> Bool`

Returns whether a memo entry for `key` has already been created.

### `MemoMap::length(self) -> Int`

Returns the number of memo entries created so far.

---

## Revision

Logical timestamp used by introspection APIs (`Memo::changed_at`, `Memo::verified_at`, and `CellInfo` fields).

`Revision` supports direct ordering comparisons (`<`, `<=`, `>`, `>=`), which is what verification uses internally.

```moonbit
let changed = memo.changed_at()
let verified = memo.verified_at()
let changed_since_verified = changed > verified
```

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
Direct comparisons (`<`, `<=`, `>`, `>=`) are supported.

Memos inherit the minimum durability of their dependencies.

---

## CycleError

Cycle detection error returned by `Memo::get_result()`.

```moonbit
pub suberror CycleError {
  CycleDetected(CellId, Array[CellId])
}
```

### `CycleError::cell(self) -> CellId`

Returns the cell that caused the cycle.

```moonbit
match memo.get_result() {
  Ok(v) => println(v.to_string())
  Err(err) => println(err.cell().to_string())
}
```

### `CycleError::path(self) -> Array[CellId]`

Returns the full dependency path that forms the cycle.

```moonbit
match memo.get_result() {
  Ok(v) => println(v.to_string())
  Err(err) => {
    let path = err.path()
    println("Cycle length: " + path.length().to_string())
  }
}
```

### `CycleError::format_path(self, rt: Runtime) -> String`

Formats the cycle path as a human-readable string.

```moonbit
match memo.get_result() {
  Ok(v) => println(v.to_string())
  Err(err) => println(err.format_path(rt))
}
```

### Cycle Path Debugging

When a cycle is detected, `CycleError` now includes the full dependency path:

```moonbit
match memo.get_result() {
  Err(err) => {
    println("Cycle detected at: " + err.cell().to_string())
    println("Dependency path:")
    let path = err.path()
    for i = 0; i < path.length(); i = i + 1 {
      println("  " + path[i].to_string())
    }

    // Or use the formatted version
    println(err.format_path(rt))
  }
  Ok(value) => use_value(value)
}
```

The `format_path()` method produces human-readable output:

```
Cycle detected: Cell[5] → Cell[7] → Cell[5]
```

For long cycles (>20 cells), the output is truncated:

```
Cycle detected: Cell[0] → Cell[1] → Cell[2] → ... → Cell[19] → ...
```

---

## Introspection and Debugging

### Signal Introspection

#### `Signal::id(self) -> CellId`

Returns the unique identifier for this signal.

**Example:**
```moonbit
let sig = Signal(rt, 42)
let id = sig.id()
```

#### `Signal::durability(self) -> Durability`

Returns the durability level of this signal (`Low`, `Medium`, or `High`).

**Example:**
```moonbit
let config = Signal(rt, "prod", durability=High)
inspect(config.durability(), content="High")
```

### Memo Introspection

#### `Memo::id(self) -> CellId`

Returns the unique identifier for this memo.

#### `Memo::dependencies(self) -> Array[CellId]`

Returns the list of cells this memo currently depends on. Empty if the memo has never been computed.

**Example:**
```moonbit
let x = Signal(rt, 1)
let doubled = Memo(rt, () => x.get() * 2)
doubled.get() |> ignore
inspect(doubled.dependencies().contains(x.id()), content="true")
```

#### `Memo::changed_at(self) -> Revision`

Returns when this memo's value last changed. Reflects backdating: if recomputation produces the same value, this timestamp is preserved.

#### `Memo::verified_at(self) -> Revision`

Returns when this memo was last verified up-to-date.

### Runtime Introspection

#### `Runtime::dependents(self, id : CellId) -> Array[CellId]`

Returns the cell IDs that depend on the given cell (reverse edges / subscriber links). The returned array is a snapshot; modifying it does not affect the runtime.

Returns an empty array if the cell ID is invalid, out of bounds, or belongs to a different runtime — matching `cell_info` semantics.

**Example:**
```moonbit
let rt = Runtime()
let x = Signal(rt, 10)
let doubled = Memo(rt, () => x.get() * 2)
doubled.get() |> ignore
let deps = rt.dependents(x.id())
inspect(deps.contains(doubled.id()), content="true")
```

#### `Runtime::cell_info(self, id : CellId) -> CellInfo?`

Retrieves structured metadata for any cell. Returns `None` if the CellId is invalid.

**Example:**
```moonbit
match rt.cell_info(memo.id()) {
  Some(info) => {
    println("Changed at: " + info.changed_at.value.to_string())
    println("Dependencies: " + info.dependencies.length().to_string())
  }
  None => println("Cell not found")
}
```

### CellInfo Structure

```moonbit
pub struct CellInfo {
  pub label : String?
  pub id : CellId
  pub changed_at : Revision
  pub verified_at : Revision
  pub durability : Durability
  pub dependencies : Array[CellId]
  pub subscribers : Array[CellId]
}
```

For signals, `dependencies` is empty. `subscribers` contains the cell IDs that depend on this cell (reverse edges).

---

## Per-Cell Callbacks

### `Signal::on_change(self, f : (T) -> Unit) -> Unit`

Registers a callback fired when this signal's value changes. Replaces any previously registered callback.

```moonbit
let count = Signal(rt, 0)
count.on_change(new_val => println("Count: " + new_val.to_string()))
```

### `Signal::clear_on_change(self) -> Unit`

Removes the registered `on_change` callback for this signal.

```moonbit
count.clear_on_change()
```

### `Memo::on_change(self, f : (T) -> Unit) -> Unit`

Registers a callback fired when this memo's value changes.

```moonbit
let doubled = Memo(rt, () => count.get() * 2)
doubled.on_change(new_val => update_ui(new_val))
```

### `Memo::clear_on_change(self) -> Unit`

Removes the registered `on_change` callback for this memo.

```moonbit
doubled.clear_on_change()
```

**Behavior (on_change):**
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

Implemented for `Signal[T]`, `Memo[T]`, and `TrackedCell[T]`.

### `Trackable`

```moonbit
pub(open) trait Trackable {
  cell_ids(Self) -> Array[CellId]
}
```

Implemented by structs that contain `TrackedCell` fields. The single method returns the `CellId` of every cell owned by the struct, in a stable order.

```moonbit
struct SourceFile {
  path    : TrackedCell[String]
  content : TrackedCell[String]
  version : TrackedCell[Int]
}

impl Trackable for SourceFile with cell_ids(self) {
  [self.path.id(), self.content.id(), self.version.id()]
}
```

`Trackable` is required by `gc_tracked`. The ordering of IDs must be deterministic across calls.

### Pipeline Traits (Experimental)

> **Experimental.** These traits may change or be removed in future versions.
> Defined in `pipeline/pipeline_traits.mbt` (`dowdiness/incr/pipeline` package).

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

### `create_signal`

Creates a new signal using the database's runtime.

```moonbit nocheck
create_signal(db, value)                               // Low durability, no label
create_signal(db, value, durability=High)              // explicit durability
create_signal(db, value, label="config")               // with debug label
create_signal(db, value, durability=High, label="cfg") // both
```

**Parameters:** `db: Db` (IncrDb), `value: T`, `durability?: Durability = Low`, `label?: String`

**Returns:** `Signal[T]`

### `create_memo[Db : IncrDb, T : Eq](db: Db, f: () -> T) -> Memo[T]`

Creates a memo using `db.runtime()`.

### `create_memo_map[Db : IncrDb, K, V](db: Db, f: (K) -> V, label? : String) -> MemoMap[K, V]`

Creates a memo map using `db.runtime()`. Each key is memoized independently.

### `create_tracked_cell`

Creates a new `TrackedCell` using the database's runtime. Follows the same pattern as `create_signal`.

```moonbit nocheck
create_tracked_cell(db, value)                               // Low durability, no label
create_tracked_cell(db, value, durability=High)              // explicit durability
create_tracked_cell(db, value, label="SourceFile.path")      // with debug label
create_tracked_cell(db, value, durability=High, label="cfg") // both
```

**Parameters:** `db: Db` (IncrDb), `value: T`, `durability?: Durability = Low`, `label?: String`

**Returns:** `TrackedCell[T]`

### `gc_tracked[T : Trackable](rt: Runtime, tracked: T) -> Unit`

Marks all cells of a `Trackable` struct as GC roots.

> **Note:** This is a no-op stub until Phase 4 adds GC infrastructure to the runtime. Include the call in your code now so that upgrading later requires no changes.

```moonbit
gc_tracked(rt, my_tracked_struct)
```

### `batch[Db : IncrDb](db: Db, f: () -> Unit) -> Unit`

Runs a batch using `db.runtime()`.

---

## Type Constraints

`Eq` is required only where value comparison is needed:

- `Memo::new`, `Memo::get`, `Memo::get_result` require `T : Eq`
- `MemoMap::get`, `MemoMap::get_result` require `K : Hash + Eq` and `V : Eq`
- `MemoMap::contains` requires `K : Hash + Eq`
- `Signal::set` requires `T : Eq`
- `TrackedCell::set` requires `T : Eq`
- `Signal::new`, `Signal::get`, `Signal::get_result`, `Signal::set_unconditional` do not require `Eq`
- `TrackedCell::new`, `TrackedCell::get`, `TrackedCell::get_result`, `TrackedCell::set_unconditional` do not require `Eq`
