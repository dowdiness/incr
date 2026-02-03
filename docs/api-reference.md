# API Reference

Complete reference for all public types and methods in `incr`.

## Runtime

The central coordinator for incremental computation.

### `Runtime::new() -> Runtime`

Creates a new runtime with an empty dependency graph.

```moonbit
let rt = Runtime::new()
```

### `Runtime::batch(self, f: () -> Unit) -> Unit`

Executes a function with batched signal updates. All `Signal::set()` calls within the batch share a single revision bump.

```moonbit
rt.batch(fn() {
  x.set(1)
  y.set(2)
})
```

**Features:**
- Nested batches are supported (only outermost commits)
- Revert detection: setting a signal back to its original value results in no change
- Reads during batch see pre-batch values (transactional semantics)

### `Runtime::revision(self) -> Revision`

Returns the current global revision number.

```moonbit
let rev = rt.revision()
```

---

## Signal[T]

Input cells with externally-set values. `T` must implement `Eq`.

### `Signal::new[T : Eq](rt: Runtime, initial: T) -> Signal[T]`

Creates a signal with the given initial value and `Low` durability.

```moonbit
let count = Signal::new(rt, 0)
```

### `Signal::new_with_durability[T : Eq](rt: Runtime, initial: T, durability: Durability) -> Signal[T]`

Creates a signal with explicit durability level.

```moonbit
let config = Signal::new_with_durability(rt, "production", High)
```

### `Signal::get(self) -> T`

Returns the current value. If called inside a memo computation, records a dependency.

```moonbit
let value = count.get()
```

### `Signal::set(self, value: T) -> Unit`

Sets a new value. If the value equals the current value (via `Eq`), this is a no-op.

```moonbit
count.set(5)
```

### `Signal::set_unconditional(self, value: T) -> Unit`

Sets a new value and always bumps the revision, even if the value is unchanged.

```moonbit
count.set_unconditional(5)  // Forces downstream reverification
```

### `Signal::get_result(self) -> Result[T, CycleError]`

Returns the current value wrapped in `Ok`. This method exists for API consistency with `Memo::get_result()`. Since signals cannot have cycles (they are input cells with no dependencies), this method always succeeds.

```moonbit
match count.get_result() {
  Ok(value) => println(value.to_string())
  Err(_) => ()  // Never happens for signals
}
```

### `Signal::id(self) -> CellId`

Returns the cell's unique identifier.

```moonbit
let id = count.id()
```

---

## Memo[T]

Derived computations with automatic dependency tracking. `T` must implement `Eq`.

### `Memo::new[T : Eq](rt: Runtime, compute: () -> T) -> Memo[T]`

Creates a memo with the given compute function. The function is not called until the first `get()`.

```moonbit
let doubled = Memo::new(rt, fn() { count.get() * 2 })
```

**Dependency tracking:** Every `Signal::get()` or `Memo::get()` call inside `compute` is recorded as a dependency.

### `Memo::get(self) -> T`

Returns the cached value, recomputing if stale. Aborts if a cycle is detected.

```moonbit
let value = doubled.get()
```

**Verification flow:**
1. If already verified this revision → return cached value
2. Check durability shortcut → skip if no relevant inputs changed
3. Walk dependencies → recompute only if a dependency changed
4. Backdate if new value equals old value

**Panics:** Aborts if a cycle is detected. Use `get_result()` for graceful cycle handling.

### `Memo::get_result(self) -> Result[T, CycleError]`

Returns the cached value as a `Result`, recomputing if stale. Returns `Err(CycleError)` if a cycle is detected instead of aborting.

```moonbit
match doubled.get_result() {
  Ok(value) => println(value.to_string())
  Err(CycleDetected(cell_id)) => println("Cycle at cell " + cell_id.to_string())
}
```

**Use case:** Graceful cycle handling in compute functions:

```moonbit
let memo = Memo::new(rt, fn() {
  match other_memo.get_result() {
    Ok(v) => v + 1
    Err(_) => -1  // Fallback value on cycle
  }
})
```

**Note:** Dependencies are only recorded on successful reads. Failed `get_result()` calls do not create dependency edges, preventing spurious cycles on future accesses.

### `Memo::id(self) -> CellId`

Returns the cell's unique identifier.

```moonbit
let id = doubled.id()
```

---

## Durability

Classification of change frequency for optimization.

### Variants

```moonbit
enum Durability {
  Low     // Frequently changing (default)
  Medium  // Moderately stable
  High    // Rarely changing
}
```

### Ordering

`Low` < `Medium` < `High`

Memos inherit the **minimum** durability of their dependencies.

### Usage

```moonbit
// Frequently changing user input
let input = Signal::new(rt, "")

// Stable configuration
let config = Signal::new_with_durability(rt, Settings::default(), High)
```

---

## Revision

A monotonically increasing counter representing the global logical clock.

### `Revision::initial() -> Revision`

Returns the initial revision (revision 1).

```moonbit
let r = Revision::initial()
```

### Comparison

Revisions support standard comparison operators: `<`, `<=`, `==`, `!=`, `>`, `>=`.

---

## CellId

Unique identifier for a cell (signal or memo).

### `CellId::id(self) -> Int`

Returns the underlying integer ID.

```moonbit
let id_num = cell_id.id()
```

---

## CycleError

Error type for cycle detection during memo computation.

### Definition

```moonbit
pub suberror CycleError {
  CycleDetected(Int)  // The cell ID that caused the cycle
}
```

### `CycleError::cell_id(self) -> Int`

Returns the cell ID that caused the cycle.

```moonbit
match memo.get_result() {
  Ok(value) => println(value.to_string())
  Err(err) => println("Cycle at cell " + err.cell_id().to_string())
}
```

---

## Error Handling

The library provides two approaches for cycle detection:

### Aborting (default)

`Memo::get()` aborts the program if a cycle is detected:

```moonbit
let _ = cyclic_memo.get()  // Aborts: "Cycle detected: cell 0 is already being computed"
```

### Graceful handling

`Memo::get_result()` returns a `Result` that can be matched:

```moonbit
match cyclic_memo.get_result() {
  Ok(value) => use(value)
  Err(CycleDetected(id)) => handle_cycle(id)
}
```

**Important:** When using `get_result()` inside a compute function to handle cycles gracefully, the error must be handled (not re-thrown). If the error propagates up, the outer `get()` or `get_result()` will see it.

---

## Type Constraints

Both `Signal[T]` and `Memo[T]` require `T : Eq` because:

- **Signal**: Same-value optimization compares new value to current value
- **Memo**: Backdating compares new result to cached result

If your type doesn't implement `Eq`, wrap it or provide a custom implementation.

---

## Thread Safety

`incr` is currently single-threaded. Using a `Runtime` from multiple threads is undefined behavior.

---

## Memory Management

Cells are stored in the runtime and live until the runtime is dropped. There is currently no garbage collection of unused memos. Hold onto `Signal` and `Memo` references as long as you need them; the runtime maintains the underlying metadata.
