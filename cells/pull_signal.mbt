///|
/// Type-erased metadata for a Pull Signal cell in the SoA layout.
///
/// The actual typed value lives in the `Signal[T]` handle held by user code.
/// The Runtime stores only the metadata needed for verification and callbacks.
priv struct PullSignalData {
  cell_id : CellId
  label : String?
  mut changed_at : Revision
  mut durability : Durability
  subscribers : @hashset.HashSet[CellId]
  mut on_change : (() -> Unit)?
  mut commit_pending : (() -> Bool)?
  // rollback_pending removed — it was set but never invoked; actual rollback
  // is handled by the BatchUndo closure registered via record_batch_rollback.
}

///|
/// CellOps dispatch for pull-signal cells.
impl CellOps for PullSignalData with cell_id(self) -> CellId {
  self.cell_id
}

///|
impl CellOps for PullSignalData with changed_at(self) -> Revision {
  self.changed_at
}

///|
impl CellOps for PullSignalData with set_changed_at(self, rev : Revision) -> Unit {
  self.changed_at = rev
}

///|
impl CellOps for PullSignalData with subscribers(
  self,
) -> @hashset.HashSet[CellId] {
  self.subscribers
}

///|
impl CellOps for PullSignalData with label(self) -> String? {
  self.label
}

///|
impl CellOps for PullSignalData with durability(self) -> Durability {
  self.durability
}

///|
/// Committable dispatch for pull-signal cells.
impl Committable for PullSignalData with do_commit(self) -> Bool {
  match self.commit_pending {
    Some(f) => {
      let changed = f()
      self.commit_pending = None
      changed
    }
    None => false
  }
}

///|
impl Committable for PullSignalData with cell_id(self) -> CellId {
  self.cell_id
}

///|
impl Committable for PullSignalData with durability(self) -> Durability {
  self.durability
}

///|
impl Committable for PullSignalData with fire_on_change_if_set(self) -> Unit {
  match self.on_change {
    Some(f) => f()
    None => ()
  }
}
