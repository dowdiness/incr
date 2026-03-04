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
  mut rollback_pending : (() -> Unit)?
}
