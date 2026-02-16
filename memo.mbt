///|
/// A derived computation with automatic dependency tracking and memoization.
///
/// Memos are the interior nodes of the dependency graph. They compute a value
/// from other signals and memos, cache the result, and only recompute when
/// their dependencies actually change.
///
/// # Key Features
///
/// - **Lazy evaluation**: The compute function is not called until `get()`.
/// - **Automatic tracking**: Dependencies are discovered by intercepting `get()` calls.
/// - **Memoization**: Results are cached; repeated `get()` calls return the cached value.
/// - **Backdating**: If a recomputation produces the same value, downstream memos skip work.
///
/// # Example
///
/// ```moonbit nocheck
/// let rt = Runtime::new()
/// let a = Signal::new(rt, 10)
/// let b = Signal::new(rt, 20)
/// let sum = Memo::new(rt, fn() { a.get() + b.get() })
///
/// inspect(sum.get(), content="30")  // Computes and caches
/// inspect(sum.get(), content="30")  // Returns cached value
///
/// a.set(15)
/// inspect(sum.get(), content="35")  // Recomputes because `a` changed
/// ```
pub(all) struct Memo[T] {
  priv rt : Runtime
  priv cell_id : CellId
  priv compute : () -> T
  priv mut value : T?
}

///|
/// Creates a new memo with the given compute function.
///
/// The compute function is called lazily on the first `get()` call, not
/// at creation time. Every `Signal::get()` or `Memo::get()` call inside
/// the compute function is automatically recorded as a dependency.
///
/// # Parameters
///
/// - `rt`: The runtime that will manage this memo
/// - `compute`: A function that computes the derived value
///
/// # Returns
///
/// A new memo. The compute function has not yet been called.
///
/// # Type Constraints
///
/// `T` must implement `Eq` for backdating: when the compute function returns
/// the same value as before, the memo's `changed_at` timestamp is preserved,
/// preventing unnecessary downstream recomputation.
pub fn[T : Eq] Memo::new(rt : Runtime, compute : () -> T) -> Memo[T] {
  let cell_id = rt.alloc_cell_id()
  let memo : Memo[T] = { rt, cell_id, compute, value: None }
  // Create the type-erased recompute closure that bridges Memo[T] to CellMeta
  let recompute_and_check : () -> Result[Bool, CycleError] = fn() {
    memo.recompute_inner()
  }
  let meta = CellMeta::new_derived(cell_id, recompute_and_check)
  rt.register_cell(meta)
  memo
}

///|
/// Returns the memoized value, recomputing if necessary.
///
/// This method implements the core verification algorithm:
///
/// 1. If no cached value exists, compute and cache the value.
/// 2. If already verified this revision, return the cached value immediately.
/// 3. Otherwise, check if any dependency changed:
///    - If no dependency changed (green path), mark verified and return cached.
///    - If a dependency changed, recompute. Backdating applies if the new
///      value equals the old value.
///
/// If called inside another memo's compute function, this automatically
/// records a dependency.
///
/// # Returns
///
/// The current (possibly recomputed) value
///
/// # Panics
///
/// Aborts if a cycle is detected (this memo transitively depends on itself).
/// Use `get_result()` instead to handle cycles gracefully.
pub fn[T : Eq] Memo::get(self : Memo[T]) -> T {
  match self.get_result() {
    Ok(value) => value
    Err(CycleDetected(id)) =>
      abort(
        "Cycle detected: cell " + id.to_string() + " is already being computed",
      )
  }
}

///|
/// Returns the memoized value as a Result, recomputing if necessary.
///
/// This is the error-returning version of `get()`. Use this method when you
/// want to handle cycles gracefully instead of aborting.
///
/// # Returns
///
/// `Ok(value)` with the current (possibly recomputed) value, or
/// `Err(CycleError)` if a cycle is detected
///
/// # Example
///
/// ```moonbit nocheck
/// match memo.get_result() {
///   Ok(value) => println("Got: " + value.to_string())
///   Err(CycleDetected(id)) => println("Cycle at cell " + id.to_string())
/// }
/// ```
pub fn[T : Eq] Memo::get_result(self : Memo[T]) -> Result[T, CycleError] {
  let cell = self.rt.get_cell(self.cell_id)
  // First computation: no cached value yet
  match self.value {
    None =>
      match self.force_recompute() {
        Ok(_) => {
          // Only record dependency on successful read to avoid poisoning
          // the dependency graph with failed cyclic edges
          self.rt.record_dependency(self.cell_id)
          Ok(self.value.unwrap())
        }
        Err(e) => Err(e)
      }
    Some(_) => {
      // Fast path: already verified this revision
      if cell.verified_at == self.rt.current_revision {
        self.rt.record_dependency(self.cell_id)
        return Ok(self.value.unwrap())
      }
      // Check if any dependency changed since last verification.
      // Note: maybe_changed_after may recompute this cell internally
      // (via recompute_and_check) to determine if value actually changed.
      match maybe_changed_after(self.rt, self.cell_id, cell.verified_at) {
        Ok(false) => {
          // Green path: nothing changed, verified_at already set by maybe_changed_after
          self.rt.record_dependency(self.cell_id)
          Ok(self.value.unwrap())
        }
        Ok(true) => {
          // maybe_changed_after returned true AND already recomputed this cell.
          // The value is now up-to-date in self.value.
          self.rt.record_dependency(self.cell_id)
          Ok(self.value.unwrap())
        }
        Err(e) => Err(e)
      }
    }
  }
}

///|
/// Force recomputation: push tracking frame, execute compute, pop frame,
/// update dependencies and value.
///
/// Returns `Ok(())` on success, or `Err(CycleError)` if a cycle is detected.
fn[T : Eq] Memo::force_recompute(self : Memo[T]) -> Result[Unit, CycleError] {
  let cell = self.rt.get_cell(self.cell_id)
  if cell.in_progress {
    return Err(CycleDetected(cell.id.id))
  }
  cell.in_progress = true
  // Push tracking frame to record dependencies
  self.rt.push_tracking()
  let new_value = (self.compute)()
  let new_deps = self.rt.pop_tracking()
  cell.dependencies = new_deps
  // Update durability: max of all dependencies' durabilities
  cell.durability = compute_durability(self.rt, new_deps)
  // Backdating: if value unchanged, keep old changed_at
  let value_changed = match self.value {
    None => true
    Some(old) => old != new_value
  }
  self.value = Some(new_value)
  if value_changed {
    cell.changed_at = self.rt.current_revision
  }
  // else: backdate — keep old changed_at (key Salsa insight)
  cell.verified_at = self.rt.current_revision
  cell.in_progress = false
  Ok(())
}

///|
/// Internal: recompute and return whether the value changed.
/// This is the closure stored in CellMeta for type-erased recomputation.
///
/// Returns `Ok(true)` if the value changed, `Ok(false)` if unchanged (backdated),
/// or `Err(CycleError)` if a cycle is detected.
fn[T : Eq] Memo::recompute_inner(self : Memo[T]) -> Result[Bool, CycleError] {
  let cell = self.rt.get_cell(self.cell_id)
  let old_changed_at = cell.changed_at
  match self.force_recompute() {
    Ok(_) => Ok(cell.changed_at != old_changed_at)
    Err(e) => Err(e)
  }
}

///|
/// Compute the durability of a derived cell from its dependencies.
/// A derived cell's durability is the minimum of its dependencies' durabilities.
fn compute_durability(rt : Runtime, deps : Array[CellId]) -> Durability {
  if deps.length() == 0 {
    return Low
  }
  let mut min_dur = High
  for i = 0; i < deps.length(); i = i + 1 {
    let dep_cell = rt.get_cell(deps[i])
    let dep_dur = dep_cell.durability
    if dur_less_than(dep_dur, min_dur) {
      min_dur = dep_dur
    }
  }
  min_dur
}

///|
fn dur_less_than(a : Durability, b : Durability) -> Bool {
  a.index() < b.index()
}

///|
/// Returns the unique identifier for this memo.
///
/// The CellId can be used with `Runtime::cell_info()` to retrieve
/// metadata, or to compare cell identities.
///
/// # Returns
///
/// The cell identifier for this memo
pub fn[T] Memo::id(self : Memo[T]) -> CellId {
  self.cell_id
}

///|
/// Returns the list of cell IDs this memo currently depends on.
///
/// The dependency list is empty before the first computation and
/// updates each time the memo recomputes (for dynamic dependencies).
///
/// # Returns
///
/// A copy of the current dependency list. Returns empty array if
/// the memo has never been computed.
///
/// # Example
///
/// ```moonbit nocheck
/// let x = Signal::new(rt, 1)
/// let m = Memo::new(rt, fn() { x.get() * 2 })
/// m.get() |> ignore
/// inspect(m.dependencies().contains(x.id()), content="true")
/// ```
pub fn[T] Memo::dependencies(self : Memo[T]) -> Array[CellId] {
  let meta = self.rt.cells[self.cell_id.id]
  match meta {
    Some(m) => m.dependencies.copy()
    None => []
  }
}

///|
/// Returns the revision when this memo's value last changed.
///
/// This reflects backdating: if a recomputation produces the same
/// value, `changed_at` is preserved from the previous computation.
///
/// # Returns
///
/// The revision timestamp of the last actual value change
pub fn[T] Memo::changed_at(self : Memo[T]) -> Revision {
  let meta = self.rt.cells[self.cell_id.id]
  match meta {
    Some(m) => m.changed_at
    None => Revision::initial()
  }
}

///|
/// Returns the revision when this memo was last verified up-to-date.
///
/// A memo is stale when `verified_at < current_revision`. Use this
/// to understand when a memo was last checked.
///
/// # Returns
///
/// The revision timestamp of the last verification
pub fn[T] Memo::verified_at(self : Memo[T]) -> Revision {
  let meta = self.rt.cells[self.cell_id.id]
  match meta {
    Some(m) => m.verified_at
    None => Revision::initial()
  }
}
