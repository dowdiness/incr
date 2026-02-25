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
/// let rt = Runtime()
/// let a = Signal(rt, 10)
/// let b = Signal(rt, 20)
/// let sum = Memo(rt, () => a.get() + b.get())
///
/// inspect(sum.get(), content="30")  // Computes and caches
/// inspect(sum.get(), content="30")  // Returns cached value
///
/// a.set(15)
/// inspect(sum.get(), content="35")  // Recomputes because `a` changed
/// ```
pub(all) struct Memo[T] {
  priv label : String?
  priv rt : Runtime
  priv cell_id : CellId
  priv compute : () -> T
  priv mut value : T?

  fn[T : Eq] new(rt : Runtime, compute : () -> T, label? : String) -> Memo[T]
} derive(Debug(ignore=[Runtime, Fn, CellId]))

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
pub fn[T : Eq] Memo::new(
  rt : Runtime,
  compute : () -> T,
  label? : String,
) -> Memo[T] {
  let cell_id = rt.alloc_cell_id()
  let memo : Memo[T] = { label, rt, cell_id, compute, value: None }
  let recompute_and_check : () -> Result[Bool, CycleError] = () => {
    memo.recompute_inner()
  }
  let meta = CellMeta::new_derived(cell_id, recompute_and_check, label)
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
///
/// The panic tests in `cycle_test.mbt` call `get()` directly and exercise this abort path.
pub fn[T : Eq] Memo::get(self : Memo[T]) -> T {
  match self.get_result() {
    Ok(value) => value
    Err(e) => abort(e.format_path(self.rt))
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
///   Err(err) => {
///     println("Cycle at " + err.cell().to_string())
///     println("Path: " + err.format_path(rt))
///   }
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
        Ok(_) => {
          self.rt.record_dependency(self.cell_id)
          Ok(self.value.unwrap())
        }
        Err(e) => Err(e)
      }
    }
  }
}

///|
/// Returns the memoized value, or `fallback` if a cycle is detected.
///
/// This is a convenience wrapper around `get_result()` for call sites that
/// prefer a non-panicking, non-Result API.
pub fn[T : Eq] Memo::get_or(self : Memo[T], fallback : T) -> T {
  match self.get_result() {
    Ok(value) => value
    Err(_) => fallback
  }
}

///|
/// Returns the memoized value, or computes a fallback value from the cycle error.
///
/// This is a convenience wrapper around `get_result()` for graceful recovery.
pub fn[T : Eq] Memo::get_or_else(
  self : Memo[T],
  fallback : (CycleError) -> T,
) -> T {
  match self.get_result() {
    Ok(value) => value
    Err(e) => fallback(e)
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
    return Err(CycleError::from_path(self.rt.collect_tracking_path(), cell.id))
  }
  cell.in_progress = true
  let old_deps = cell.dependencies
  // Push tracking frame to record dependencies
  self.rt.push_tracking(self.cell_id)
  let new_value = (self.compute)()
  let (new_deps, new_seen) = self.rt.pop_tracking()
  // Diff: check whether the dep set changed.
  // new_seen is the HashSet already built by ActiveQuery — no extra allocation.
  // We walk old_deps and check membership in new_seen; a length mismatch is a
  // fast-path indicator of change (avoids the loop when counts differ).
  let mut deps_changed = new_deps.length() != old_deps.length()
  // Single pass over old_deps: detect changes, unsubscribe dropped deps,
  // and build old_seen for the symmetric diff that follows.
  let old_seen : @hashset.HashSet[CellId] = @hashset.new()
  for dep in old_deps {
    old_seen.add(dep)
    if not(new_seen.contains(dep)) {
      deps_changed = true
    }
  }
  // Maintain subscriber links (reverse edges)
  if deps_changed {
    // Remove self from subscribers of deps that were dropped
    for dep in old_deps {
      if not(new_seen.contains(dep)) {
        let dep_meta = self.rt.get_cell(dep)
        dep_meta.subscribers.remove(self.cell_id)
      }
    }
    // Add self to subscribers of newly added deps
    for dep in new_deps {
      if not(old_seen.contains(dep)) {
        let dep_meta = self.rt.get_cell(dep)
        dep_meta.subscribers.add(self.cell_id)
      }
    }
  }
  cell.dependencies = new_deps
  // Update durability only when the dep set changed (skip rescan on stable path)
  if deps_changed {
    cell.durability = compute_durability(self.rt, new_deps)
  }
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
    Ok(_) => {
      let changed = cell.changed_at != old_changed_at
      if changed {
        match cell.on_change {
          Some(f) => f()
          None => ()
        }
      }
      Ok(changed)
    }
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
  let mut min_dur = Durability::High
  for dep_id in deps {
    let dep_cell = rt.get_cell(dep_id)
    if dep_cell.durability < min_dur {
      min_dur = dep_cell.durability
    }
  }
  min_dur
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
/// let x = Signal(rt, 1)
/// let m = Memo(rt, () => x.get() * 2)
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

///|
/// Registers a callback that fires whenever this memo's value changes.
///
/// The callback fires lazily — only during `get()` when recomputation
/// produces a new value that differs from the previous value. It does not
/// fire on the first computation (which establishes the initial value),
/// and does not fire if the memo backdates (recomputes to the same value).
/// Only one callback can be registered at a time; calling this again
/// replaces the previous callback.
///
/// # Parameters
///
/// - `f`: Called with the new value whenever this memo's value changes
pub fn[T] Memo::on_change(self : Memo[T], f : (T) -> Unit) -> Unit {
  let cell = self.rt.get_cell(self.cell_id)
  cell.on_change = Some(() => {
    match self.value {
      Some(v) => f(v)
      None => ()
    }
  })
}

///|
/// Removes the `on_change` callback for this memo.
pub fn[T] Memo::clear_on_change(self : Memo[T]) -> Unit {
  let cell = self.rt.get_cell(self.cell_id)
  cell.on_change = None
}

///|
/// Returns true if the memo has a cached value and its verified_at matches
/// the runtime's current revision. Returns false if the memo has never been
/// computed (value is None), even at the initial revision.
pub fn[T] Memo::is_up_to_date(self : Memo[T]) -> Bool {
  match self.value {
    None => false
    Some(_) => {
      let cell = self.rt.get_cell(self.cell_id)
      cell.verified_at == self.rt.current_revision
    }
  }
}
