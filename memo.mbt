///|
/// A derived computation with automatic dependency tracking and memoization.
/// Recomputes only when its dependencies have actually changed.
pub struct Memo[T] {
  rt : Runtime
  cell_id : CellId
  compute : () -> T
  mut value : T?
}

///|
/// Create a new Memo. The compute function will be called lazily on first get().
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
/// Get the memoized value, recomputing if necessary.
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
