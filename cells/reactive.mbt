///|
/// Internal SoA entry for a push-mode reactive cell.
///
/// Recomputed eagerly when upstream cells change via push propagation.
/// Uses the same type-erased `compute : () -> Bool` pattern as `PullMemoData`.
priv struct PushReactiveData {
  cell_id : CellId
  label : String?
  /// Type-erased compute closure. Returns true if the value changed (for backdating).
  compute : () -> Bool
  /// Cells this reactive reads (updated on recompute via begin/end_tracking).
  mut sources : Array[CellId]
  /// Cells that depend on this reactive (reverse edges for push propagation).
  subscribers : @hashset.HashSet[CellId]
  /// Last revision where value actually changed (for pull→push boundary).
  mut changed_at : Revision
  /// Topological depth (max source level + 1). Recalculated when sources change.
  mut level : Int
  /// Set true by push propagation when an upstream cell changes.
  mut dirty : Bool
}

///|
impl CellOps for PushReactiveData with cell_id(self) -> CellId {
  self.cell_id
}

///|
impl CellOps for PushReactiveData with changed_at(self) -> Revision {
  self.changed_at
}

///|
impl CellOps for PushReactiveData with set_changed_at(
  self,
  rev : Revision,
) -> Unit {
  self.changed_at = rev
}

///|
impl CellOps for PushReactiveData with subscribers(
  self,
) -> @hashset.HashSet[CellId] {
  self.subscribers
}

///|
impl CellOps for PushReactiveData with label(self) -> String? {
  self.label
}

///|
/// Push cells have no Durability (they always propagate immediately).
/// Returns `Low` as a sentinel value.
impl CellOps for PushReactiveData with durability(self) -> Durability {
  ignore(self)
  Low
}

///|
/// Typed handle for a push-mode reactive cell.
pub struct ReactiveId[T] {
  id : CellId
}

///|
/// User-facing push-mode reactive cell.
///
/// Recomputed eagerly when any upstream cell changes. Value is cached;
/// consecutive reads without upstream changes do not trigger recomputation.
pub struct Reactive[T] {
  priv cell_id : ReactiveId[T]
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
  let reactive_idx = rt.push_reactives.length()
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
  let cell_id = rt.alloc_cell_id(PushReactive(reactive_idx))
  rt.push_node_count = rt.push_node_count + 1
  rt.push_reactives.push({
    cell_id,
    label: None,
    compute,
    sources: [],
    subscribers: @hashset.new(),
    changed_at: Revision::initial(),
    level: 1,
    dirty: false,
  })
  let ops : &CellOps = rt.push_reactives[reactive_idx]
  rt.cell_ops.push(ops)
  let reactive : Reactive[T] = { cell_id: { id: cell_id }, value, rt }
  // Initial compute: establish dependencies and set initial value.
  rt.begin_tracking(cell_id)
  let _ = compute()
  let new_sources = rt.end_tracking()
  rt.push_reactives[reactive_idx].sources = new_sources
  rt.push_reactives[reactive_idx].level = rt.recompute_level(cell_id, new_sources)
  rt.finish_tracking(cell_id, [], new_sources)
  reactive
}

///|
/// Returns the current cached value of the reactive cell.
///
/// Push propagation ensures the value is already up-to-date by the time
/// `get()` is called outside a reactive computation. No verification walk
/// is needed.
pub fn[T] Reactive::get(self : Reactive[T]) -> T {
  // Cross-runtime check (mirrors Signal::get): abort rather than silently
  // recording a dependency from the wrong runtime's tracking stack.
  let active_rt = current_computing_runtime_id.val
  if active_rt >= 0 && active_rt != self.rt.runtime_id {
    current_computing_runtime_id.val = -1
    abort(
      "Cross-runtime dependency: Reactive belongs to Runtime " +
      self.rt.runtime_id.to_string() +
      " but is read inside a computation on Runtime " +
      active_rt.to_string(),
    )
  }
  // Disposal check: reading after dispose() returns stale data and records
  // an invalid dependency; abort instead.
  let cell_id = self.cell_id.id
  match self.rt.cell_index[cell_id.id] {
    Disposed => abort("Reactive::get called on a disposed reactive")
    _ => ()
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
/// Removes this reactive from the dependency graph.
///
/// After disposal:
/// - The reactive is removed from all source subscriber sets.
/// - `cell_index[id]` is set to `Disposed`.
/// - The SoA slot is added to `free_push_reactives` for future reuse.
pub fn[T] Reactive::dispose(self : Reactive[T]) -> Unit {
  self.rt.dispose_reactive(self.cell_id.id)
}
