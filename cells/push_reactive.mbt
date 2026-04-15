///|
/// Internal SoA entry for a push-mode reactive cell.
///
/// Recomputed eagerly when upstream cells change via push propagation.
/// Uses the same type-erased `compute : () -> Bool` pattern as `MemoData`.
priv struct PushReactiveData {
  meta : CellMeta
  /// Type-erased compute closure. Returns true if the value changed (for backdating).
  mut compute : () -> Bool
  /// Cells this reactive reads (updated on recompute via begin/end_tracking).
  mut sources : Array[CellId]
  /// Topological depth (max source level + 1). Recalculated when sources change.
  mut level : Int
  /// Set true by push propagation when an upstream cell changes.
  mut dirty : Bool
}

///|
impl HasCellMeta for PushReactiveData with meta(self) {
  self.meta
}

///|
/// CellOps dispatch for push-reactive cells — defaults via HasCellMeta,
/// with sentinel durability and stored level overrides.
impl CellOps for PushReactiveData

///|
/// Push cells have no Durability (they always propagate immediately).
/// Returns `Low` as a sentinel value.
impl CellOps for PushReactiveData with durability(self) -> Durability {
  ignore(self)
  Low
}

///|
impl CellOps for PushReactiveData with level(self) -> Int {
  self.level
}

///|
impl CellOps for PushReactiveData with gc_role(_self) -> GcRole {
  Interior
}

///|
impl CellOps for PushReactiveData with gc_dependencies(self) -> Array[CellId] {
  self.sources
}

///|
impl CellLifecycle for PushReactiveData with dispose_cell(self, rt, cell_id) -> Unit {
  match rt.core.cell_index[cell_id.id] {
    PushReactive(idx) => {
      for dep in self.sources {
        rt.remove_subscriber(dep, cell_id)
      }
      rt.core.cell_index[cell_id.id] = Disposed
      self.clear_slot()
      rt.push.free_reactives.push(idx)
      rt.push.node_count = rt.push.node_count - 1
    }
    _ => ()
  }
}

///|
/// Suspends the push path when the last observer is removed.
///
/// Only suspends if no other cell reads this reactive (subscribers empty).
/// A Memo or another Reactive in the subscriber set means this cell's
/// changed_at must keep advancing — suspension would cause stale reads.
impl CellLifecycle for PushReactiveData with on_unobserve(self, rt, cell_id) {
  guard self.meta.subscribers.is_empty() else { return }
  for source in self.sources {
    rt.remove_subscriber(source, cell_id)
  }
}

///|
/// Activates the push path when the first observer is added.
///
/// Recomputes with fresh tracking to establish current sources and
/// a correct cached value. Passes [] as old_sources because subscriber
/// links were removed during suspension. For fresh cells (never
/// suspended), add_subscriber is idempotent.
impl CellLifecycle for PushReactiveData with on_observe(self, rt, cell_id) {
  guard !(rt.core.phase is PushPropagating) else {
    abort("on_observe: cannot activate during push propagation")
  }
  guard !(rt.core.phase is InFixpoint) else {
    abort("on_observe: cannot activate during fixpoint evaluation")
  }
  rt.begin_tracking(cell_id)
  let _ = (self.compute)()
  let new_sources = rt.end_tracking()
  rt.finish_tracking(cell_id, [], new_sources)
  self.sources = new_sources
  self.level = rt.recompute_level(cell_id, new_sources)
  self.dirty = false
}

///|
/// Clears all mutable fields to release captured closures and graph edges.
/// Called by the CellLifecycle dispose impl after removing subscriber links.
fn PushReactiveData::clear_slot(self : PushReactiveData) -> Unit {
  self.compute = () => false
  self.sources.clear()
  self.meta.subscribers.clear()
  self.meta.label = None
  self.meta.changed_at = Revision::initial()
  self.level = 0
  self.dirty = false
}

///|
/// User-facing push-mode reactive cell.
///
/// Recomputed eagerly when any upstream cell changes. Value is cached;
/// consecutive reads without upstream changes do not trigger recomputation.
pub struct Reactive[T] {
  priv cell_id : @incr_types.ReactiveId[T]
  priv value : Ref[T?]
  priv rt : Runtime
}

///|
/// Creates a new push-mode reactive cell.
///
/// `compute_fn` is invoked immediately to set the initial value and establish
/// dependencies. Whenever any dependency changes, the runtime calls
/// `compute_fn` again via push propagation (triggered by `Signal::set` or
/// `Runtime::batch`).
///
/// # Type Erasure
///
/// `compute_fn` is captured in a `() -> Bool` closure stored on
/// `PushReactiveData`. The Bool indicates whether the value changed
/// (enabling early cutoff for downstream push cells).
pub fn[T : Eq] Reactive::new(rt : Runtime, compute_fn : () -> T) -> Reactive[T] {
  let value : Ref[T?] = { val: None }
  // Type-erased compute: invoked by push_propagate_from after begin_tracking.
  let compute : () -> Bool = () => {
    let new_val = compute_fn()
    let changed = match value.val {
      None => true
      Some(v) => v != new_val
    }
    value.val = Some(new_val)
    changed
  }
  // Reuse a freed slot if available, otherwise append a new one.
  let reactive_idx = match rt.push.free_reactives.pop() {
    Some(idx) => idx
    None => rt.push.reactives.length()
  }
  let cell_id = rt.alloc_cell_id(PushReactive(reactive_idx))
  rt.push.node_count = rt.push.node_count + 1
  let new_data : PushReactiveData = {
    meta: {
      cell_id,
      label: None,
      changed_at: Revision::initial(),
      durability: Low,
      subscribers: @hashset.new(),
      push_reachable_count: 0,
    },
    compute,
    sources: [],
    level: 1,
    dirty: false,
  }
  if reactive_idx < rt.push.reactives.length() {
    rt.push.reactives[reactive_idx] = new_data
  } else {
    rt.push.reactives.push(new_data)
  }
  let ops : &CellOps = rt.push.reactives[reactive_idx]
  rt.core.cell_ops.push(ops)
  let lifecycle : &CellLifecycle = rt.push.reactives[reactive_idx]
  rt.core.cell_lifecycle.push(lifecycle)
  let reactive : Reactive[T] = {
    cell_id: @incr_types.ReactiveId::{ id: cell_id },
    value,
    rt,
  }
  // Initial compute: establish dependencies and set initial value.
  rt.begin_tracking(cell_id)
  let _ = compute()
  let new_sources = rt.end_tracking()
  rt.push.reactives[reactive_idx].sources = new_sources
  rt.push.reactives[reactive_idx].level = rt.recompute_level(
    cell_id, new_sources,
  )
  rt.finish_tracking(cell_id, [], new_sources)
  reactive
}

///|
/// Returns the current cached value of the reactive cell.
///
/// Must be called inside a tracked context (a memo or reactive compute function).
/// Outside a compute function, use `rt.read_reactive(reactive)` or
/// `reactive.observe()`.
pub fn[T] Reactive::get(self : Reactive[T]) -> T {
  guard self.rt.core.tracking_stack.length() > 0 else {
    abort(
      "Reactive::get() called outside tracked context. Use rt.read_reactive(reactive) or reactive.observe() to read from outside the graph.",
    )
  }
  self.get_untracked()
}

///|
/// Package-private untracked read. Bypasses the tracked-context guard.
/// Used by Observer to read from outside the dependency graph.
fn[T] Reactive::get_untracked(self : Reactive[T]) -> T {
  let active_rt = current_computing_runtime_id.val
  if active_rt >= 0 && active_rt != self.rt.core.runtime_id {
    current_computing_runtime_id.val = -1
    abort(
      "Cross-runtime dependency: Reactive belongs to Runtime " +
      self.rt.core.runtime_id.to_string() +
      " but is read inside a computation on Runtime " +
      active_rt.to_string(),
    )
  }
  let cell_id = self.cell_id.id
  guard !self.rt.is_cell_disposed(cell_id) else {
    abort("Reactive::get called on a disposed reactive")
  }
  self.rt.record_dependency(cell_id)
  self.value.val.unwrap()
}

///|
/// Returns the unique cell identifier for this reactive.
pub fn[T] Reactive::id(self : Reactive[T]) -> CellId {
  self.cell_id.id
}

///|
/// Returns true if this reactive has been disposed.
pub fn[T] Reactive::is_disposed(self : Reactive[T]) -> Bool {
  self.rt.is_cell_disposed(self.cell_id.id)
}

///|
/// Removes this reactive from the dependency graph.
///
/// After disposal:
/// - The reactive is removed from all source subscriber sets.
/// - `cell_index[id]` is set to `Disposed`.
/// - The SoA slot is added to `free_push_reactives` for future reuse.
pub fn[T] Reactive::dispose(self : Reactive[T]) -> Unit {
  self.rt.dispose_cell(self.cell_id.id)
}
