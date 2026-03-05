///|
/// Type-erased metadata for a HybridMemo cell in the SoA layout.
///
/// Like PullMemoData but adds a `dirty` flag set eagerly by push propagation.
/// On `get()`, the dirty flag allows skipping full dependency verification
/// when no upstream push cell has signaled a change.
priv struct HybridMemoData {
  cell_id : CellId
  label : String?
  compute : () -> Result[Bool, CycleError]
  mut changed_at : Revision
  mut verified_at : Revision
  mut durability : Durability
  mut dependencies : Array[CellId]
  subscribers : @hashset.HashSet[CellId]
  mut in_progress : Bool
  mut dirty : Bool
}

///|
/// CellOps dispatch for hybrid-memo cells.
impl CellOps for HybridMemoData with cell_id(self) -> CellId {
  self.cell_id
}

///|
impl CellOps for HybridMemoData with changed_at(self) -> Revision {
  self.changed_at
}

///|
impl CellOps for HybridMemoData with set_changed_at(self, rev : Revision) -> Unit {
  self.changed_at = rev
}

///|
impl CellOps for HybridMemoData with subscribers(
  self,
) -> @hashset.HashSet[CellId] {
  self.subscribers
}

///|
impl CellOps for HybridMemoData with label(self) -> String? {
  self.label
}

///|
impl CellOps for HybridMemoData with durability(self) -> Durability {
  self.durability
}
