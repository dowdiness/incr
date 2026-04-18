///|
using @pull {type MemoData}

///|
/// CellLifecycle impl for MemoData (pull memos and hybrid memos).
/// Lives here rather than in internal/pull/ because it references Runtime,
/// which cannot leak into an internal package.
impl CellLifecycle for MemoData with dispose_cell(self, rt, cell_id) -> Unit {
  match rt.core.cell_index[cell_id.id] {
    PullMemo(idx) | HybridMemo(idx) => {
      for dep in self.dependencies {
        rt.remove_subscriber(dep, cell_id)
      }
      self.dependencies = []
      self.meta.subscribers.clear()
      self.meta.label = None
      self.on_change = None
      self.verified_at = Revision::initial()
      self.in_progress = false
      rt.core.cell_index[cell_id.id] = Disposed
      rt.pull.free_memos.push(idx)
    }
    _ => ()
  }
}
