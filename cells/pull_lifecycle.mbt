///|
using @pull {type PullSignalData}

///|
/// CellLifecycle impl for PullSignalData (signals).
/// Lives here rather than in internal/pull/ because it references
/// Runtime-only helpers that cannot leak into an internal package.
impl CellLifecycle for PullSignalData with dispose_cell(self, rt, cell_id) -> Unit {
  match rt.core.cell_index[cell_id.id] {
    PullSignal(idx) => {
      if rt.core.batch.depth > 0 {
        rt.remove_batch_signal(cell_id)
      }
      self.meta.subscribers.clear()
      self.meta.label = None
      self.on_change = None
      self.commit_pending = None
      rt.core.cell_index[cell_id.id] = Disposed
      rt.pull.free_signals.push(idx)
    }
    _ => ()
  }
}
