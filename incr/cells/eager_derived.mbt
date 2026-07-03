///|
/// User-facing push-mode eager derived cell.
///
/// Recomputed eagerly when any upstream cell changes. Value is cached;
/// consecutive reads without upstream changes do not trigger recomputation.
pub(all) struct EagerDerived[T] {
  priv cell_id : @incr_types.ReactiveId[T]
  priv value : Ref[T?]
  priv rt : Runtime
}

///|
/// Creates an eager derived value.
///
/// `compute_fn` is invoked immediately to set the initial value and establish
/// dependencies. Whenever any dependency changes, the runtime calls
/// `compute_fn` again via push propagation (triggered by `Input::set` or
/// `Runtime::batch`).
///
/// # Type Erasure
///
/// `compute_fn` is captured in a `() -> Bool` closure stored on
/// `PushReactiveData`. The Bool indicates whether the value changed
/// (enabling early cutoff for downstream push cells).
pub fn[T : Eq] EagerDerived::EagerDerived(
  rt : Runtime,
  compute_fn : () -> T,
) -> EagerDerived[T] {
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
  let (cell_id, reactive_idx) = rt.install_cell(
    rt.push.free_reactives,
    rt.push.reactives,
    idx => PushReactive(idx),
    cell_id => {
      meta: {
        cell_id,
        label: None,
        changed_at: Revision::initial(),
        durability: Low,
        subscribers: @hashset.HashSet([]),
        push_reachable_count: 0,
      },
      compute,
      sources: [],
      level: 1,
      dirty: false,
    },
  )
  rt.push.node_count = rt.push.node_count + 1
  let derived : EagerDerived[T] = {
    cell_id: @incr_types.ReactiveId::{ id: cell_id },
    value,
    rt,
  }
  // Initial compute: establish dependencies and set initial value.
  rt.begin_tracking(cell_id)
  let _ = compute()
  let (new_sources, new_seen) = rt.end_tracking()
  rt.push.reactives[reactive_idx].sources = new_sources
  rt.push.reactives[reactive_idx].level = rt.recompute_level(
    cell_id, new_sources,
  )
  rt.finish_tracking(cell_id, [], new_sources, new_seen)
  if rt.has_pending_events() {
    rt.drain_pending_events_if_idle()
  }
  derived
}

///|
/// Returns the current cached value of the eager derived cell.
///
/// Must be called inside a tracked context (a memo or reactive compute function).
/// Outside a compute function, use `EagerDerived::read()` or
/// `EagerDerived::watch()`.
pub fn[T] EagerDerived::get(self : EagerDerived[T]) -> T {
  guard self.rt.core.tracking.stack.length() > 0 else {
    abort(
      "EagerDerived::get() called outside tracked context. Use EagerDerived::read() or EagerDerived::watch() to read from outside the graph.",
    )
  }
  self.read_permissive()
}

///|
fn[T] EagerDerived::read_permissive(self : EagerDerived[T]) -> T {
  self.rt.check_cross_runtime(self.rt.core.runtime_id, "EagerDerived")
  let cell_id = self.cell_id.id
  guard !self.rt.is_cell_disposed(cell_id) else {
    abort("EagerDerived::read called on a disposed eager derived cell")
  }
  self.rt.record_dependency(cell_id)
  self.value.val.unwrap()
}

///|
/// Permissive read. Works outside the graph and records a dependency if tracked.
pub fn[T] EagerDerived::read(self : EagerDerived[T]) -> T {
  self.read_permissive()
}

///|
/// Returns the unique cell identifier for this eager derived value. Stable
/// across reads — useful for graph-shape probes (gc anchoring, edge
/// inspection) where a cell needs an identity independent of its value.
pub fn[T] EagerDerived::id(self : EagerDerived[T]) -> CellId {
  self.cell_id.id
}

///|
/// Returns true if this eager derived cell has been disposed.
pub fn[T] EagerDerived::is_disposed(self : EagerDerived[T]) -> Bool {
  self.rt.is_cell_disposed(self.cell_id.id)
}

///|
/// Removes this eager derived cell from the dependency graph.
///
/// After disposal:
/// - The cell is removed from all source subscriber sets.
/// - `cell_index[id]` is set to `Disposed`.
/// - The SoA slot is added to `free_push_reactives` for future reuse.
pub fn[T] EagerDerived::dispose(self : EagerDerived[T]) -> Unit {
  self.rt.dispose_cell(self.cell_id.id)
}
