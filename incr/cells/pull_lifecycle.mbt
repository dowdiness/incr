///|
using @pull {type PullInputData}

///|
/// CellLifecycle impl for PullInputData (inputs).
/// Lives here rather than in internal/pull/ because it references
/// Runtime-only helpers that cannot leak into an internal package.
impl CellLifecycle for PullInputData with fn dispose_cell(self, rt, cell_id) -> Unit {
  match rt.core.cell_index[cell_id.id] {
    PullInput(idx) => {
      if rt.core.batch.depth > 0 {
        rt.remove_batch_input(cell_id)
      }
      self.meta.subscribers.clear()
      self.meta.label = None
      self.on_change = None
      self.commit_pending = None
      rt.core.cell_index[cell_id.id] = Disposed
      rt.pull.free_inputs.push(idx)
    }
    _ => ()
  }
}
