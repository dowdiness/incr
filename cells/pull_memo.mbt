///|
/// Type-erased metadata for a Pull Memo cell in the SoA layout.
///
/// The actual typed value lives in the `Memo[T]` handle held by user code.
/// `compute` is a closure captured at construction time that recomputes
/// the memo and returns whether the value changed.
priv struct PullMemoData {
  cell_id : CellId
  label : String?
  compute : () -> Result[Bool, CycleError]
  mut changed_at : Revision
  mut verified_at : Revision
  mut durability : Durability
  mut dependencies : Array[CellId]
  subscribers : @hashset.HashSet[CellId]
  mut in_progress : Bool
  mut on_change : (() -> Unit)?
}

///|
/// CellOps dispatch for pull-memo cells.
impl CellOps for PullMemoData with cell_id(self) -> CellId {
  self.cell_id
}

///|
impl CellOps for PullMemoData with changed_at(self) -> Revision {
  self.changed_at
}

///|
impl CellOps for PullMemoData with set_changed_at(self, rev : Revision) -> Unit {
  self.changed_at = rev
}

///|
impl CellOps for PullMemoData with subscribers(self) -> @hashset.HashSet[CellId] {
  self.subscribers
}

///|
impl CellOps for PullMemoData with label(self) -> String? {
  self.label
}

///|
impl CellOps for PullMemoData with durability(self) -> Durability {
  self.durability
}
