///|
/// Type-erased metadata for a Pull Memo cell in the SoA layout.
///
/// The actual typed value lives in the `Memo[T]` handle held by user code.
/// `compute` is a closure captured at construction time that recomputes
/// the memo and returns whether the value changed.
priv struct MemoData {
  meta : CellMeta
  compute : () -> Result[Bool, CycleError]
  mut verified_at : Revision
  mut dependencies : Array[CellId]
  mut in_progress : Bool
  mut on_change : (() -> Unit)?
  is_hybrid : Bool
}

///|
impl HasCellMeta for MemoData with meta(self) {
  self.meta
}

///|
/// CellOps dispatch for pull-memo cells — defaults via HasCellMeta,
/// with deep-verification override.
impl CellOps for MemoData

///|
impl CellOps for MemoData with dep_changed_since(_self, _verified_at) -> Bool? {
  None
}

///|
impl CellOps for MemoData with gc_role(_self) -> GcRole {
  Interior
}

///|
impl CellOps for MemoData with gc_dependencies(self) -> Array[CellId] {
  self.dependencies
}

///|
impl CellLifecycle for MemoData with dispose_cell(
  self,
  rt,
  cell_id,
) -> Unit {
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
