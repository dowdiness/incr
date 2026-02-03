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
/// ```moonbit
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
pub struct Memo[T] {
  rt : Runtime
  cell_id : CellId
  compute : () -> T
  mut value : T?
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
  let recompute_and_check : () -> Bool = fn() { memo.recompute_inner() }
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
pub fn[T : Eq] Memo::get(self : Memo[T]) -> T {
  // Record dependency from current tracking context
  self.rt.record_dependency(self.cell_id)
  let cell = self.rt.get_cell(self.cell_id)
  // First computation: no cached value yet
  match self.value {
    None => {
      self.force_recompute()
      self.value.unwrap()
    }
    Some(_) => {
      // Fast path: already verified this revision
      if cell.verified_at == self.rt.current_revision {
        return self.value.unwrap()
      }
      // Check if any dependency changed since last verification.
      // Note: maybe_changed_after may recompute this cell internally
      // (via recompute_and_check) to determine if value actually changed.
      if not(maybe_changed_after(self.rt, self.cell_id, cell.verified_at)) {
        // Green path: nothing changed, verified_at already set by maybe_changed_after
        return self.value.unwrap()
      }
      // maybe_changed_after returned true AND already recomputed this cell.
      // The value is now up-to-date in self.value.
      self.value.unwrap()
    }
  }
}

///|
/// Force recomputation: push tracking frame, execute compute, pop frame,
/// update dependencies and value.
fn[T : Eq] Memo::force_recompute(self : Memo[T]) -> Unit {
  let cell = self.rt.get_cell(self.cell_id)
  if cell.in_progress {
    abort("Cycle detected: cell " + cell.id.to_string() + " is already being recomputed")
  }
  cell.in_progress = true
  // Push tracking frame to record dependencies
  self.rt.push_tracking(self.cell_id)
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
}

///|
/// Internal: recompute and return whether the value changed.
/// This is the closure stored in CellMeta for type-erased recomputation.
fn[T : Eq] Memo::recompute_inner(self : Memo[T]) -> Bool {
  let cell = self.rt.get_cell(self.cell_id)
  let old_changed_at = cell.changed_at
  self.force_recompute()
  cell.changed_at != old_changed_at
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
