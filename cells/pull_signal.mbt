///|
/// Type-erased metadata for a Pull Signal cell in the SoA layout.
///
/// The actual typed value lives in the `Signal[T]` handle held by user code.
/// The Runtime stores only the metadata needed for verification and callbacks.
priv struct PullSignalData {
  meta : CellMeta
  mut on_change : (() -> Unit)?
  mut commit_pending : (() -> Bool)?
  // rollback_pending removed — it was set but never invoked; actual rollback
  // is handled by the BatchUndo closure registered via record_batch_rollback.
}

///|
impl HasCellMeta for PullSignalData with meta(self) {
  self.meta
}

///|
/// CellOps dispatch for pull-signal cells — all defaults via HasCellMeta.
impl CellOps for PullSignalData

///|
/// Committable dispatch for pull-signal cells.
impl Committable for PullSignalData with do_commit(self) -> Bool {
  match self.commit_pending {
    Some(f) => {
      let changed = f()
      self.commit_pending = None
      changed
    }
    None =>
      abort(
        "invariant violation: batch_pending contained signal without commit_pending",
      )
  }
}

///|
impl Committable for PullSignalData with cell_id(self) -> CellId {
  self.meta.cell_id
}

///|
impl Committable for PullSignalData with durability(self) -> Durability {
  self.meta.durability
}

///|
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
