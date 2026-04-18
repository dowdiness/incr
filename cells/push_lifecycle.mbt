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
///
/// Note: `self.sources` is NOT cleared here — it stays populated so that
/// subscriber links can be reinstated on `on_observe`. This makes
/// `gc_role = Interior`'s `gc_dependencies(self) -> self.sources` a
/// temporarily stale list while suspended. That is safe because a
/// suspended reactive with no observers is itself GC-eligible (Interior),
/// and when the sweep collects it `clear_slot` empties `sources` before
/// the slot is reused. In the observer.dispose() → on_unobserve (suspend)
/// → rt.gc() integration flow, upstream cells must not be considered
/// preserved by this stale list. Do not refactor away the "suspend
/// without clearing sources" invariant — `on_observe` depends on it.
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
