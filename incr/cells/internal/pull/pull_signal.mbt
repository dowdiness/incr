///|
/// Type-erased metadata for a Pull Signal cell in the SoA layout.
///
/// The actual typed value lives in the `Input[T]` handle held by user code.
/// The Runtime stores only the metadata needed for verification and callbacks.
pub(all) struct PullSignalData {
  meta : CellMeta
  mut on_change : (() -> Unit)?
  mut commit_pending : (() -> Bool)?
  // rollback_pending removed — it was set but never invoked; actual rollback
  // is handled by the BatchUndo closure registered via record_batch_rollback.
}

///|
pub impl HasCellMeta for PullSignalData with fn meta(self) {
  self.meta
}

///|
/// CellOps dispatch for pull-input cells — all defaults via HasCellMeta.
pub impl CellOps for PullSignalData

///|
/// Committable dispatch for pull-input cells.
pub impl Committable for PullSignalData with fn do_commit(self) -> Bool {
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
pub impl Committable for PullSignalData with fn cell_id(self) -> CellId {
  self.meta.cell_id
}

///|
pub impl Committable for PullSignalData with fn durability(self) -> Durability {
  self.meta.durability
}
