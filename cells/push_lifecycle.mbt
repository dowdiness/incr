///|
using @push {type PushReactiveData, type PushEffectData}

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
  let (new_sources, new_seen) = rt.end_tracking()
  rt.finish_tracking(cell_id, [], new_sources, new_seen)
  self.sources = new_sources
  self.level = rt.recompute_level(cell_id, new_sources)
  self.dirty = false
}

///|
impl CellLifecycle for PushEffectData with dispose_cell(self, rt, cell_id) -> Unit {
  match rt.core.cell_index[cell_id.id] {
    PushEffect(idx) => {
      for dep in self.sources {
        rt.remove_subscriber(dep, cell_id)
      }
      rt.core.cell_index[cell_id.id] = Disposed
      self.clear_slot()
      rt.push.free_effects.push(idx)
      rt.push.node_count = rt.push.node_count - 1
    }
    _ => ()
  }
}
